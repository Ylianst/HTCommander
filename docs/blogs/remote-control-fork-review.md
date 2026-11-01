# Two Roads to a Remote Radio: The Web Bridge vs. the HTCommander-Remote Fork

*HTCommander already lets you drive a radio from somewhere else: the desktop app
runs a small web server, serves the Flutter web build, and bridges a browser tab
to the radio it has connected. In late October 2026 a community fork,
[HTCommander-Remote](https://github.com/Xixixiao2007/HTCommander-Remote), took a
different road — it lets one native HTCommander attach to another over a
WebSocket, with authentication, a single-operator lock, two-way audio and an
audit trail. This post reviews what the fork changed, compares it point by point
with the existing web bridge, and lays out a starting plan for growing the web
server and adding first-class support for remote HTCommanders.*

---

## The fork at a glance

The fork branched from upstream at `7d8d318` (2026-10-26) and added 58 commits,
about 12,200 lines across 83 files — more than half of which are tests. Almost
all of it is one feature: **remote control**. The rest is supporting work.

| Area | Change |
| --- | --- |
| Remote control | New `/remote` WebSocket endpoint, host and client roles, two-way audio, remote PTT, operator lock, token auth, audit trail (~20 new files under `src/lib/services/remote/`) |
| Firebase | `firebase_core`, `firebase_messaging` and the Google Services Gradle plugin removed; `main.dart` always uses the APRS cloud stub, so cloud push is a no-op |
| Android identity | `applicationId` changed to `com.meshcentral.htcommander.remote` so the fork installs beside the official app (namespace unchanged) |
| Licensing & docs | `NOTICE` with an Apache-2.0 §4(b) statement of changes, rewritten README, Simplified Chinese README, `REMOTE-CONTROL.md`, an ADR on which radio a remote transmit targets |
| CI | GitHub Pages deploy reduced to manual dispatch |

Upstream files the fork touched are few and the changes are additive:

- `services/data_broker.dart` — remote peer and remote host transports
- `radio/pcm_player.dart` — the single `playbackTap` became a multicast tap
- `services/db/app_database_io.dart` — `remote_audit` DAO, schema 3 → 4
- `main.dart` — role-driven startup wiring
- `dialogs/settings_dialog.dart` — a **Remote Control** settings section
- `widgets/comms_tab.dart` — hosts the remote PTT panel

At the time of review the fork is 17 commits behind upstream and does not include
the XARA modem work, the Bluetooth audio fixes or the latest satellite changes.

Importantly, the fork **does not modify the existing web server**. Its server
explicitly leaves `/websocket.aspx` untouched, and `WebServerHandler` is still
registered on desktop exactly as before. A fork build runs both endpoints side by
side on separate ports.

---

## How the existing web bridge works

The details are in [The Same App, Two Homes](web-hosted-in-desktop.md); the short
version:

- **Server:** `services/web/web_server_io.dart` binds an `HttpServer` on
  `0.0.0.0` (default port 8080), serves the Flutter web build (built with
  `--dart-define=HTC_HOSTED=true`), and upgrades `/websocket.aspx` to a WebSocket.
  `handlers/web_server_handler.dart` orchestrates the bridge.
- **Client:** a browser running the hosted web build. `radio/websocket_transport.dart`
  implements `RadioTransport` over the socket, so the web app's `Radio` object
  talks to the real radio through the desktop.
- **Protocol:** two layers on one socket.
  - *Binary radio frames.* The browser sends raw command frames
    (`[group_hi, group_lo, cmd_hi, cmd_lo, payload…]`) which the host dispatches
    as `SendRawCommand`; radio responses are broadcast back.
  - *Text messages* for things the radio protocol cannot carry: `setsetting:`,
    `selectradio:`, `mailop:`, `winlinksync:`, `clear:`, `audioon`/`audiooff`
    from the browser; `settings:`, `setting:`, `history:`, `mail:`,
    `winlinkstate:`, `airplanes:`, `radiolist:` from the host.
  - *Audio frames* `[0xF1, channels, rateLo, rateHi] + int16 LE PCM`, fed from
    `PcmPlayer.playbackTap` to every browser that sent `audioon`.
- **Design rule:** the host does all autonomous work; the browser only syncs,
  displays and forwards the operator's own actions.

It is simple, needs nothing installed on the client, and has purpose-built support
for Winlink mail, history and Dump1090 aircraft. It was designed for a trusted LAN.

---

## How the fork's remote control works

One binary, a role setting: **Off** (default, behaves as upstream), **Host** or
**Client**. A role change requires a restart.

- **Host** keeps the radio on Bluetooth and serves `/remote`
  (`remote_broker_server.dart`).
- **Client** is a native HTCommander with no radio. It attaches to a host
  (`remote_broker_client.dart`) and mirrors its state.

### Protocol: mirror the DataBroker

Rather than tunnel raw radio frames, the fork carries the same message shape the
desktop already uses between its main window and detached windows:

| Client → host | Meaning |
| --- | --- |
| `{"m":"snapshot"}` | Request full broker state |
| `{"m":"dispatch","deviceId":N,"name":"X","payload":"…","store":bool}` | Write a value |
| `{"m":"detach"}` | Release everything this peer attached |
| `{"m":"operator-acquire"}` / `{"m":"operator-release"}` | Take / drop operator authority |

| Host → client | Meaning |
| --- | --- |
| `{"m":"snapshot","entries":[…]}` | Broker state |
| `{"m":"onData",…}` | A value changed |
| `{"m":"operator","holderId":…}` | Who holds authority |
| `{"m":"refused","name":"X","reason":"not-operator"}` | A write was refused |

Audio reuses the bridge's `0xF1` frame layout in both directions. A socket
carries one peer, so inbound binary is always uplink (microphone) and outbound is
always downlink.

### Audio

- **Downlink** (`remote_audio*.dart`): host playback goes out at a selectable
  32 / 16 / 8 kHz tier. Above the target rate it is low-pass filtered (4th-order
  cascaded biquad) before decimation, and the client plays it through a jitter
  buffer. Streaming can be switched off for a control-only session.
- **Uplink** (`remote_mic_*.dart`, `remote_uplink.dart`, `remote_tx_injector.dart`):
  the client microphone is captured only while PTT is held, converted to the
  radio rate, and injected into the selected radio's transmit path. The injector
  has a stall watchdog, so a dropped link cannot leave the transmitter keyed.

### Authority and security

- **Bearer tokens** (`remote_token_store.dart`): 32 random bytes, one per device,
  issued and revoked in Settings, shown once, kept in the platform secret store.
  Checked **before** the WebSocket upgrade; the rejection does not distinguish
  missing, wrong or revoked. Never placed in a query string.
- **Loopback by default:** the host binds `127.0.0.1` until *Accept connections
  from other devices* is ticked.
- **No TLS in-app:** a reverse proxy (Caddy, nginx, Cloudflare Tunnel) is expected
  for `wss://`.
- **Single-operator lock** (`remote_operator_lock.dart`, `remote_ptt_state.dart`):
  many watchers, one operator. Released explicitly, on disconnect, or after five
  minutes idle — speaking counts as activity. No local pre-emption.
- **Write gating** (`remote_privileged.dart`): transmit, any device-0 settings
  write, `WriteChannel`, `SetRegion`, `SetRegionName` require authority. Reading
  state, listening, history, VFO tuning and radio UI operation do not.
- **Audit trail** (`remote_audit.dart`, `remote_audit_dao.dart`): attach, rejected
  attach, detach, refused writes and each transmission (one entry per burst) with
  token name and client address. `X-Forwarded-For` is recorded only when
  explicitly trusted and never used for a security decision.
- **Remote PTT UI** (`remote_ptt_button.dart`, `remote_ptt_panel.dart`) in the
  Comms tab shows three states: *available*, *ready* (you hold it), *in use: id*.

### Status, by the fork's own account

Exercised with one phone against one PC. Not tested from the web build, through
the TLS proxy it relies on, across NATs, or for iOS audio.

---

## Side by side

| | Existing web bridge (`/websocket.aspx`) | Fork remote control (`/remote`) |
| --- | --- | --- |
| Client | Any browser running the hosted web build | Native HTCommander (Android, iOS, desktop) in Client role |
| Host platforms | Desktop only (Windows, Linux, macOS) | Any native build, including phones (gated only on `!kIsWeb`) |
| Control model | Raw radio command frames + bespoke text messages | DataBroker mirroring (`snapshot` / `dispatch` / `onData`) |
| RX audio | `0xF1` frames at the engine's native rate, broadcast to opted-in clients | Same framing; 32/16/8 kHz tiers, anti-alias filter, jitter buffer |
| TX audio | **None** — no uplink from the browser | Press-and-hold PTT, resampled mic uplink, stall watchdog |
| Authentication | **None** | Mandatory per-device bearer token, revocable, pre-upgrade |
| Bind address | All interfaces | Loopback by default; explicit LAN opt-in |
| TLS | None | None built-in; reverse proxy expected |
| Concurrency | Unlimited clients, all equal | Unlimited watchers, one operator at a time |
| Write restrictions | None — any client can change settings or key the radio via raw frames | Transmit, settings, channel and region writes require authority; refusals reported |
| Audit | None | Persisted `remote_audit` table |
| Feature-specific messages | Winlink mail ops & sync, history, Dump1090 aircraft, radio list, connect/disconnect | None; relies on whatever flows through the DataBroker. Whether mail ops, Winlink sync, aircraft and history clear work remotely is **unverified** |
| Zero-install | Yes | No — needs the app on the client |

### Where each one wins

- **The fork** closes every security gap in the bridge (no auth, open to the LAN,
  no write gating, raw radio frames from any client) and adds the one capability
  the bridge has never had: **transmitting from a remote microphone**.
- **The bridge** needs nothing installed, works from any browser, and has explicit
  support for Winlink, history and aircraft that the fork does not replicate.
- **Both** share the `0xF1` audio framing, so audio code is portable between them.

A note on the bridge's missing uplink: it is unimplemented, not impossible.
Browsers can capture the microphone through `getUserMedia`, but only in a secure
context — HTTPS or `localhost`. That ties browser TX to the TLS question below.

---

## Toward a plan

The goal is to grow the web server and to support remote HTCommanders without
ending up with two diverging remote protocols. Below is a starting outline, not a
decision.

### Phase 1 — Harden the existing web server

Most of this can be lifted from the fork's self-contained modules (Apache-2.0,
same license as upstream).

1. **Authentication** — per-device tokens, checked before the WebSocket upgrade,
   held in the platform secret store, never in a URL. For the browser, consider a
   one-time pairing step that sets an `HttpOnly` cookie, since a browser cannot
   attach an `Authorization` header to a WebSocket handshake.
   *Source:* `remote_token_store.dart`, the pre-upgrade check in
   `remote_broker_server.dart`.
2. **Loopback by default** with an explicit *allow other devices* option.
   Existing users who rely on LAN access need a migration path.
3. **Operator lock and write gating** — one operator at a time; gate settings,
   channel, region and transmit. The raw `SendRawCommand` path needs care: either
   classify commands (reads vs. writes vs. PTT) or require authority for all of
   them. *Source:* `remote_operator_lock.dart`, `remote_privileged.dart`.
4. **Audit trail** — attach, reject, detach, refused writes, transmissions.
   *Source:* `remote_audit.dart`, `remote_audit_dao.dart`,
   `remote_client_address.dart`.
5. **Multicast playback tap** — the fork's change to `pcm_player.dart` lets more
   than one consumer (web bridge, remote host, recorder) attach to playback.

### Phase 2 — Better audio

1. **Audio tiers** with anti-alias filtering and a jitter buffer
   (`remote_audio_resample.dart`, `remote_audio_player.dart`) so remote listening
   works over thin links.
2. **Browser microphone uplink** via `getUserMedia`, behind the operator lock and
   PTT, with the fork's stall-watchdog injector (`remote_tx_injector.dart`).
   Requires HTTPS or `localhost`.
3. **TLS** — decide between documenting a reverse proxy (the fork's choice) and
   serving HTTPS in-app with a self-signed or user-supplied certificate.

### Phase 3 — Remote HTCommanders

Let a native HTCommander attach to another HTCommander with no local radio. Two
options:

- **A. Native app speaks the existing bridge protocol.** `WebSocketRadioTransport`
  already implements `RadioTransport` over a WebSocket and uses a cross-platform
  client, so a native build could reuse it with the hosted-mode text messages.
  One protocol for browsers and native clients; Winlink, history and aircraft
  support come along for free. Downside: raw radio frames are hard to gate.
- **B. Adopt the fork's DataBroker mirror** as a second endpoint. Cleaner
  authority model, already tested, but a second protocol to maintain, and the
  web-only features would need re-implementing on it.
- **C. Converge.** Make `/websocket.aspx` carry DataBroker `dispatch`/`onData`
  alongside the existing messages, so browsers and native clients share one
  endpoint, one auth model and one operator lock.

Whichever is chosen, the client role needs a settings UI (host address, token),
a remote PTT control, and clear "control-only" behaviour on platforms without
audio.

### Phase 4 — Phones as hosts

The fork shows an Android or iOS device can host, since it only needs
`dart:io` sockets. The current web server is desktop-only. Background execution
limits, battery and network changes on mobile need investigation before this is
offered.

---

## Open questions

- Should LAN exposure stay the default for existing users, or flip to loopback
  with a one-time prompt?
- Which raw radio commands are safe for a non-operator browser (status reads,
  VFO tuning) and which must be gated?
- Is a five-minute operator hold right for both browsers and native clients?
- In-app TLS, or reverse proxy only?
- Does the remote role need regulatory guidance in-app? The fork warns that
  whoever holds a token transmits under the host operator's licence.
- What to do with the fork's Firebase removal and separate Android
  `applicationId` — neither is needed upstream, but both explain why the fork
  exists as a separate install.

---

## References

- Fork: [Xixixiao2007/HTCommander-Remote](https://github.com/Xixixiao2007/HTCommander-Remote) —
  see its `REMOTE-CONTROL.md` and `docs/adr/0001-remote-transmit-target-radio.md`
- [The Same App, Two Homes: Running HTCommander's Web UI Inside the Desktop](web-hosted-in-desktop.md)
- Existing bridge code: `src/lib/services/web/web_server_io.dart`,
  `src/lib/handlers/web_server_handler.dart`, `src/lib/radio/websocket_transport.dart`,
  `src/lib/services/host_bridge.dart`
