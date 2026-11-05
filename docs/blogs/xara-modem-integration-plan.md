# Bringing XARA Into HTCommander: A Direct Modem Integration Plan

*Design proposal, October 31, 2026, updated with port and integration progress
below. XARA FM now runs inside HTCommander's software modem and carries Winlink
sessions; it has not yet been tested over the air.
This post records the pure-Dart port we intend to build after reviewing XARA
and HTCommander's existing DART and audio pipelines. It replaces the initial
Rust/FFI proposal: portability and ordinary Flutter builds are requirements.*

HTCommander already turns radio audio into data with AFSK, PSK, and DART. The
next candidate is [XARA](https://github.com/x0rro/xara), an MIT-licensed Rust modem
whose README reports compatibility testing against VARA HF 4.9.0 and VARA FM
4.4.0. That offers something different from another HTCommander-specific
waveform: a route to communicating with existing VARA stations.

We want the modem **inside HTCommander**, not a separately installed executable
with localhost command and data sockets. HTCommander should continue to own the
radio, Bluetooth, audio devices, and user interface. XARA should supply the
modulation, decoding, and link protocol.

**The XARA modem will be implemented entirely in Dart.** No Rust toolchain,
FFI bridge, native modem binaries, or per-platform modem build steps will be
required to build or run HTCommander. This does not remove existing native
Flutter plugins; the new modem must not introduce another native dependency.
Throughout this post, **Dart** means the language, while **DART** is the existing
Data Adaptive Rate Transport modem. XARA will coexist with DART, not replace it.

The source review used XARA 0.1.3, commit
`09a9201381b00499ada9d9c816bd05bb8f175705`. Compatibility claims below are
upstream claims, not results from an HTCommander interoperability test.

## Progress update: no transmitting while the radio receives

Software modems used the radio's RSSI to decide whether the channel was clear.
RSSI ignores the radio's squelch setting, so the user had no way to tune it. They
now use the Bluetooth audio stream instead: the radio counts as **receiving**
from a received-audio `AudioDataStart` until its `AudioDataEnd` (the echo of our
own transmit audio is ignored), which follows the squelch exactly. No software
modem keys up while that flag is set:

- **AFSK/PSK packet and DART** treat the channel as clear only when the radio is
  neither receiving nor transmitting, then run the usual p-persistent slot
  timing. If reception starts while a bundle is still being modulated off the
  UI isolate, the encoded audio is held (DART sequence numbers are already
  assigned) and sent once the channel clears.
- **XARA** gets the flag in its isolate. While it is set, the transmit scheduler
  starts no new burst of any kind (session data, ACK/control replies, connect
  requests, digipeats or broadcasts); a burst already playing finishes. XARA
  times its reply windows from when a burst actually ends, so a deferred burst
  stays valid on our side.

The radio's hardware TNC path still uses RSSI, because it can run with Bluetooth
audio off. A test checks each modem holds a frame while the radio receives
(with a non-zero RSSI) and sends it once reception ends.

### Improvements to look at next

Recorded from a review after the receive gate landed, most impactful first.
None of these has been tested on air yet.

**High priority**

1. **Warn when the squelch is fully open (level 0).** At level 0 the radio
   streams receive audio continuously, so the new gate blocks XARA forever and
   links time out. The XARA and lock flows should warn about this, or require a
   squelch of at least 1.
2. **Use real PTT timing from the radio.** XARA estimates its transmit timing
   from fixed settings (800 ms latency plus 100 ms key-up by default). The radio echoes our
   transmit audio over Bluetooth and reports when it is actually transmitting,
   which gives the real start and end of each burst. Feeding the real end time to
   XARA would replace guesswork with measurement and avoid dropped ACKs on
   radios slower than the defaults.
3. **Auto-calibrate latency from the capture.** Every received control code is
   already logged with its delay, reply window and verdict. If replies keep
   arriving late, the app could suggest a better `XaraTxLatencyMs`, or adjust it
   within limits. This is a lighter alternative to item 2.
4. **Shorten the squelch tail before our ACKs.** Our ACKs now wait for the
   squelch to close, so a long squelch tail delays every reply and can push it
   past the far station's window. The radio's `tailElim` setting could be
   enabled while a XARA channel is locked, just as the lock already turns off
   scan and dual-watch.

**Medium priority**

5. **Make drive level adjustable.** `driveDb` is fixed in code. HTs vary a lot
   in deviation, and clipping hurts the fastest speed levels most. A drive
   setting plus a calibration tone (the station already supports `tune`) would
   help.
6. **Require the channel lock for XARA, or warn without it.** The lock is what
   disables scan and dual-watch. Without it the radio can switch to the other
   watched channel, feed that audio to the decoder and block transmit through
   the gate.
7. **Close the last ~10 ms race.** The receiving flag reaches the XARA isolate
   asynchronously, so a burst prepared just before reception starts can still
   go out. XARA could tag each burst with the moment it was prepared so the host
   can skip and resend it if reception began after that.
8. **Protect the start of incoming frames.** Our squelch opening and the
   Bluetooth audio startup clip the start of the far station's signal, and real
   VARA stations do not add our key-up pre-roll. If logs show failures
   concentrated at frame starts, try a lower squelch or the radio's squelch
   delay options.

**Lower priority**

9. **Check wide mode on HTs.** It is not yet confirmed that the radio's audio
   filtering and the SBC codec pass the 2750 Hz wide waveform cleanly. Compare
   error rates per speed level, narrow versus wide, on air.
10. **Add a watchdog for the receiving flag.** If the radio ever missed its
    end-of-audio marker, transmit would stay blocked. A fallback could clear the
    flag after a few seconds with no audio frames.
11. **Test against real VARA FM stations.** Current tests run XARA against
    itself. A few captured sessions with real VARA FM stations, kept as
    regression tests, would catch timing differences between implementations.

The suggested order is items 1 and 4 first (quick safety fixes for the gate),
then item 2, the biggest gain this closer radio integration makes possible.

## Progress update: XARA FM is wired into HTCommander

XARA FM is now a software modem mode beside DART. Choose **Software Modem >
XARA FM** (with a **Narrow/Wide** bandwidth submenu), and the radio's audio is
handled by the Dart port of XARA instead of DART.

The **XARA FM** submenu also has **Settings...** below a separator after
**Narrow/Wide**. This dialog edits the global key-up pre-roll (default **100 ms**)
and transmit latency (default **800 ms**, excluding the pre-roll) in whole
milliseconds from **0 to 5000**. Each field shows its default; **Restore Defaults**
resets both fields, and **Save** applies and persists the changes. **Cancel**
discards edits. Saving changed timings rebuilds live XARA modems and disconnects
active links; saving unchanged values leaves links alone.

**How it is wired.** The modem runs in its own isolate (`src/lib/radio/xara_modem.dart`)
so its DSP never touches the UI isolate. `SoftwareModem` feeds it the radio's
32 kHz receive audio and sends whatever it transmits to the radio through the
same `TransmitVoicePCM` path DART uses.

**Bridging two notions of time.** HTCommander's radio audio arrives in
squelch-gated runs, and transmissions leave as whole PCM buffers. XARA expects a
continuous 48 kHz timeline with sample-accurate transmit timing. A small driver
(`src/lib/hamlib/xara/xara_driver.dart`) reconciles the two:

- The station clock follows the wall clock 250 ms behind, as a jitter buffer.
  Silence between receive runs is filled with zeros, and late audio inside a
  run is waited for.
- When XARA starts a transmission, the driver runs the station ahead until the
  burst is complete, resamples it to 32 kHz and sends it as one buffer. The
  radio hears nothing while it transmits, so no receive audio is lost.
- The delay from "PCM handed to the radio" to "remote audio heard" is passed to
  XARA as its transmit latency (800 ms by default, setting `XaraTxLatencyMs`),
  plus the key-up pre-roll below, since that silence delays every frame's
  content by the same amount. XARA times its ARQ reply windows and transmit
  holds from this latency, and the radio's receive path (squelch, SBC decode,
  Bluetooth) adds delay XARA's soundcard-based windows do not expect. If the
  latency is under-estimated, replies arrive after the window and control
  codes (ACKs, connect replies) are dropped while data frames still decode. If
  it is over-estimated nothing breaks, so the default leaves headroom: in
  simulation it keeps links clean from 0 to about 1 s of one-way radio lag.
  The packet capture shows each received control code's reply delay, window
  and verdict (`accepted`, `late`, `early`, `transmitting`).
- The radio keys up on the arriving audio, so the start of every burst is lost
  while it keys and the far squelch opens (about 240 ms was measured, followed
  by a loud squelch-open noise burst). The driver therefore leads each burst
  with silence (100 ms by default, setting `XaraTxKeyUpMs`) to protect the
  lead-in. Increase this on slower radios; a path losing 240 ms needs a longer
  pre-roll, such as 300 ms, to keep that loss and noise ahead of the lead-in.

**Bluetooth transmit continuity.** XARA already hands the audio engine a complete
burst, tagged as data, so it uses the existing 10-second transmit pacing lead.
This streams ahead into the available OS/radio buffers; it does not preload the
radio before keying, and there is no separate firmware preload/start command in
this path. The experimental SBC bitpool 40 has been restored to the radio's
default 18: at 32 kHz mono each 4 ms frame now occupies 44 bytes rather than 88
bytes (88 rather than 176 kbit/s before transport overhead). Modem audio retains
SNR bit allocation; voice retains loudness allocation. Packets contain complete
SBC frames and stay within the 300-byte unescaped SBC payload limit.

The audio engine logs each data chunk's audio duration, elapsed send time,
longest Bluetooth write and wire byte count. Rejected native Bluetooth writes
now terminate and log the failed transmission instead of silently discarding
audio. These are host-side diagnostics, not radio buffer acknowledgements:
hardware testing is still needed to establish whether the link sustains the
stream. Increasing the lead cannot compensate for sustained insufficient
throughput, and native platform-thread stalls can still delay writes.

**Two data paths.**

- **Unconnected frames.** AX.25 frames HTCommander sends while XARA is selected
  go out as VARA FM unconnected (record 16) broadcasts. Received broadcasts
  re-enter the normal packet path as AX.25 `DataFrame`s tagged "Software XARA
  FM", so APRS, the packet capture and other frame consumers work unchanged.
- **Connected ARQ links.** These are exposed on the data broker per radio. The
  commands are `XaraConnect` (`{Remote, Vias}`), `XaraSend`, `XaraDisconnect`
  and `XaraAbort`. The events are `XaraLinkState` (stored: state, level, peer,
  bandwidth), `XaraDataReceived` and `XaraEvent` (connected, disconnected, PTT,
  busy, bit rate, SNR).

**Verification.**

- Driver tests run two stations over a simulated radio path with key-up and
  receive latency, squelch-gated 32 kHz audio and half-duplex radios.
- An app-level test puts the real `SoftwareModem` and data broker on one side
  and a second XARA isolate on the other, connected through a real-time audio
  bridge. In about 30 s of wall time the two connect, exchange data in both
  directions and disconnect, and an unconnected AX.25 beacon from the peer
  arrives as a normal decoded frame.

**Still to do.**

- Calibration of the transmit latency on real radios.
- The first over-the-air test against VARA FM.

## Progress update: Winlink over XARA

The first user-facing consumer of the connected link is Winlink. A Winlink
gateway contact has **AX.25 Session**, **XARA Narrow** and **XARA Wide** choices
in its protocol list, matching the XARA choices for Terminal contacts. AX.25
sessions retain the hardware TNC, AFSK 1200, PSK 2400 and DART modem choices.
XARA contacts hide that modem list and store the bandwidth in the contact's
protocol. Older contacts with the `XARA` modem value still connect using the
global bandwidth; editing them adopts that bandwidth as an explicit protocol.

Connecting to such a contact works like any radio Winlink session:

1. The radio is locked to the gateway's channel, and the lock's modem override
   switches that radio to XARA with the contact's narrow or wide bandwidth for
   the duration of the session. The user's global software-modem and bandwidth
   settings are left alone.
2. Once the lock is in place, the Winlink client asks XARA to call the gateway,
   passing up to two digipeaters taken from the contact's path.
3. The B2F exchange is unchanged; only the byte transport differs. The client
   already had separate AX.25 and Internet transports, and XARA is a third
   one.
4. The status line shows XARA's speed level as it climbs or falls. A gateway
   that does not answer, a link that times out, a user cancel and the gateway's
   `FQ` each end the session cleanly and release the radio.

XARA needs the radio's audio channel, so the client refuses with a clear
message when audio is off. New XARA choices are not offered on web and iOS,
where the software modems cannot run.

Tests drive the Winlink client against a simulated radio that applies the
lock and plays the gateway over the XARA broker events. They cover a full
session start and `FQ` close, no answer, cancel while connecting, audio
off, per-contact bandwidth, and invalid digipeater paths. Contact editor tests
cover creating, editing, and round-tripping both bandwidths through persistence.

## Progress update: a complete FM modem runs in Dart

The port has started, layer by layer, in `src/lib/hamlib/xara/`, with tests in
`src/test/xara/`. Every layer is checked against XARA's own reference vectors
(copied with the MIT notice into `src/test/xara/vectors/`), so the tests run
with the normal Flutter toolchain and never need Rust. Where upstream had no
vector, an independent oracle stands in: a Python big-integer model for the
64-bit generator, Python `zlib` for DEFLATE, and a textbook max-log BCJR
decoder for the turbo code.

| Layer | What is ported | How it is verified |
|-------|----------------|--------------------|
| 1. Primitives | CRC-16, callsign hash/packing, VB `Rnd`, whitening and phasor sequences, bit codecs, Rust `f32`/`u64` semantics | All upstream vectors; Python model for XorShift |
| 2. Levels and tables | HF and FM speed levels, puncturing, the generated permutation/marker `.dat` tables | Every level field; full HF and FM table files are **byte-identical** (SHA-256) |
| 3. FM transmit | Frames, constellations, OFDM synthesis, phasors, control-tone codebooks, modulator | Output PCM is **bit-identical** for 99 lab transmissions, 39 level transmissions and 72 control frames |
| 4. Decode and FM receive | Turbo decoder, soft demapper, equaliser, front end, control detector, OFDM receiver, frame assembly | Turbo bits and iteration counts equal an independent BCJR; all five upstream FM receiver loopback tests pass |
| 5. ARQ wire codecs | KISS fragmentation/reassembly, AX.25 field compressor, VARA text compression, CQ frames, FM broadcasts, FILES compression | All upstream KISS, broadcast and text-compression tests, 1,300+ VARA black-box text cases, bit-exact HF-coded KISS/CQ frames |
| 6. FM connected sessions | Session state machine, ACK/NACK rate adaptation, timing windows, queue hints, compression negotiation, B2F end detection, watchdogs, digipeater | VARA-derived ACK, hint and timing tables; four VARA lab-capture replays; 74/74 lab queue hints and 68/68 lab ACK decisions; simulated links (600 lossy seeds); golden transcripts |
| 7. FM station | Station that joins receiver, session, digipeater, broadcasts and modulator; sample-timed transmit scheduler with PTT latency handling; channel-busy detector; streaming resampler | All upstream FM audio-link, digipeated-link and scheduler tests; busy-detector vectors; resampler accuracy and chunking tests (including 32 kHz to and from 48 kHz) |

That is 193 passing tests over about 9,500 non-blank lines of Dart, with no analyzer
findings. The tests earned their keep: three upstream vectors caught real
porting bugs before anything left the bench.

The station layer gave the first end-to-end result. Two complete Dart modems,
each running the full receive and transmit chain at 48 kHz, connect over a
simulated audio channel and exchange data in both directions. They climb to
high speed levels on registered links, survive added noise, cope with up to a
second of PTT delay at each end, exchange unconnected KISS frames and CQ
beacons, and relay a whole session through a third station acting as a
digipeater. These are XARA's own station tests, ported unchanged in intent.

The session layer is checked the way XARA checks itself: a discrete-event
simulator, ported to Dart, joins two sessions over a channel that drops
control frames, corrupts data frames, or misses whole transmissions. Every
session output is written to a transcript in Rust's debug format and compared
line by line with the transcripts XARA keeps in its repository. The
digipeater's 700-step randomized transcript matches byte for byte. The link
transcript has 43 scenarios; 36 match exactly. The seven that differ all use
FILES compression, where XARA's DEFLATE encoder and the Dart one produce
different (equally valid) compressed bytes, so the conversation drifts once the
first compressed frame goes out. Those scenarios still have to deliver every
byte intact in the simulated-link tests.

A few findings worth recording:

- **Speed is fine on desktop.** An AOT build decodes FM narrow at 2.56x real
  time and wide at 1.77x while listening for *every* speed level at once, which
  is the worst case. Phones still need to be measured.
- **Floating point needed care, not luck.** Rust mixes `f32` and `f64`, rounds
  ties to even, and saturates casts; the Dart port reproduces each deliberately,
  which is why the transmitted audio hashes match exactly.
- **Small traps.** Dart's `double.nan` is a *negative* NaN on x86, its list
  sort is not stable, and `Iterable.map` is lazy. Each would have silently
  changed behaviour.
- **One intentional difference.** Outgoing FILES-mode chunks are compressed
  with the pure-Dart `archive` package, so the compressed bytes differ from
  XARA's while remaining standard DEFLATE. Incoming chunks use a small strict
  decoder that rejects malformed streams and caps output at 50 KB, matching
  XARA's protection against decompression bombs.

Not done yet: the HF waveforms and session, and the fixed-point turbo kernel
(upstream uses it only on Linux ARM). The busy
detector's HF PSK test waits for the HF modulator. Nothing has been tested
against real VARA
recordings or over the air: the VARA lab captures behind XARA's capture tests
are not part of its repository.

## What we found in XARA

XARA is already divided into useful components:

| Component | Responsibility | Integration decision |
|-----------|----------------|----------------------|
| `xara-phy` | HF/FM waveforms, receivers, coding, FFTs, turbo decoding | Port algorithms and tables to pure Dart |
| `xara-arq` | Sans-IO HF/FM sessions, rate adaptation, compression, broadcasts, AX.25 codecs | Port state machines and wire codecs to pure Dart |
| `xara/src/station` | Connects receivers, sessions, waveform generation, busy detection, and timed transmission | Port into a host-independent Dart engine |
| `xara/src/resample.rs` | Streaming sample-rate conversion | Port with its streaming tests |
| `xara-host` | VARA command/data TCP and KISS TCP hosting | Do not include |
| `xara-ui` | Web UI and telemetry delivery | Do not include; replace required status types |
| Remaining executable services | Device audio, native PTT, CLI, recording, process management | Leave to HTCommander |

The PHY and ARQ crates are independent of audio devices and network sockets,
which gives us a useful porting boundary. The orchestration boundary is the
**station** layer. It
already has a `Modem` trait with `process`, `connect`, `send`, `disconnect`,
`abort`, `kiss`, and a queue of `Report` events.

However, the station code currently imports `xara_host::command::Bw` and
`xara_ui::telemetry::Link`. The `xara` library also includes platform audio and
PTT modules. Port only the relevant station behavior, replace those small
host/UI types with Dart core types, and preserve its scheduling semantics.
The TCP-oriented `Tnc` wrapper is not needed.

## Decision: a pure-Dart port

Port XARA's DSP, wire codecs, ARQ sessions, and station scheduler into Dart.
Keep the engine independent of Flutter, audio devices, DataBroker, and wall-clock
timers so it can be exercised with deterministic sample-driven tests. Add a
small integration adapter alongside the existing software modems.

This keeps the modem portable through Dart/Flutter's normal compilation path.
The cost is maintaining a substantial port and validating its numerical behavior
and performance. We accept that tradeoff. Rust remains a reference implementation
for development comparisons, not code linked into HTCommander.

Mirror upstream's logical layers and retain recognizable names where practical.
Port FM first with only the shared code it needs; add HF after the FM path is
verified. Keep XARA-specific framing and coding separate from DART's protocol.

Proposed layout, not files that exist today:

```text
src/lib/hamlib/xara/          pure-Dart PHY, codecs, ARQ, station, resampler
src/lib/radio/xara_modem.dart software-modem adapter and worker lifecycle
src/test/xara/               ported tests and checked-in reference fixtures
```

Record the upstream revision and source-to-port mapping, preserve its MIT
notices, and review upstream fixes against that map. Check in the small reference
fixtures needed by ordinary Dart tests; running those tests must not require
Cargo or the developer's C:\Code\xara checkout. A maintainer may regenerate
fixtures with the pinned Rust source as a separate, optional workflow.

## Port fidelity before optimization

Use upstream behavior as the oracle rather than redesigning the modem during
translation. Verify encoded bytes and deterministic sequences exactly; compare
floating-point DSP output with explicit tolerances and decode outcomes. Two
Dart engines passing self-loopback is necessary but insufficient: they can
share the same porting mistake.

- Preserve bit ordering, CRCs, framing, interleaving, puncturing, code tables,
  compression headers, and quantization/rounding rules.
- Explicitly reproduce Rust's unsigned shifts and fixed-width wrapping math.
  XARA has both a 24-bit VB-compatible random generator and a 64-bit XorShift
  generator. Do not substitute Dart's `Random`; verify their known sequences.
- Dart `double` matches the intended double-precision storage, but upstream
  also uses `f32`, float bit reinterpretation, and ties-to-even rounding. Port
  these operations deliberately rather than assuming casts or `round()` match.
- Keep sample timestamps as integer counts at 48 kHz, not elapsed milliseconds.
  Test signed/unsigned boundary behavior and avoid assuming browser integer
  arithmetic has the same precision as the Dart VM; use exact representations
  where needed if the engine is later enabled in a browser.
- Evaluate [DART's existing OFDM implementation](../../src/lib/hamlib/dart_ofdm.dart)
  for reusable FFT/complex arithmetic, but first verify XARA's transform sizes,
  normalization, sign conventions, and performance. Do not change DART's
  waveform or force XARA through an incompatible FFT helper.
- Port compression semantics separately. Any reused Dart compression code must
  match the wire format and pass reference fixtures, and must not add a native
  dependency. Equivalent decompressed bytes alone may not prove identical
  compressed output where exact encoding matters.

Start with scalar algorithms and `Float64List`/integer typed buffers, reusable
FFT plans, bounded ring buffers, and precomputed tables. Avoid object allocation
per sample and repeated large-buffer copies. Profile turbo decoding and receiver
search in release/AOT builds, not only debug mode. Optimize only after parity
tests pass; performance problems do not silently authorize falling back to FFI.

## Where it belongs beside DART

The owning abstraction is
[SoftwareModem](../../src/lib/radio/software_modem.dart), not
[MultiModem](../../src/lib/hamlib/multi_modem.dart). The latter coordinates
Direwolf-style AX.25 decoder candidates; it is not a general session-modem host.

`SoftwareModem` already owns per-radio general/APRS modem instances, lock
overrides, PCM routing, external receive sources, and decoded packet dispatch.
DART bypasses the HDLC/FX.25 chain there, using its own frame decoder and the
[background TX encoder](../../src/lib/radio/modem_tx_encoder.dart).

XARA should be another **general software-modem choice alongside DART**, with
an independent settings group. Start with XARA FM and a narrow/wide setting;
keep HF bandwidth settings separate when HF is added. The dedicated APRS
AFSK modem remains unchanged. Selecting XARA does not mean running every
general modem simultaneously against the same audio.

Unlike DART's current packet encoder, XARA needs a long-lived engine that keeps
both receive and transmit session state. Use a dedicated worker isolate owning
the Dart engine, with bounded PCM and command queues. Keep Flutter platform
channels and UI updates on their existing host side. Do not run the DSP
decoder synchronously inside the main-isolate DataBroker audio callback.

```text
Radio SBC decode / external audio capture
    -> timestamped, ordered PCM blocks
    -> XARA worker: Dart resampling + station + ARQ
        -> received packet or connected stream bytes -> DataBroker / transport
        -> timed TX PCM + key transitions -> existing radio audio engine
        -> batched link status -> UI
```

Initially the adapter can consume existing PCM events. If measured broker
delivery jitter exceeds the timing budget, add a direct PCM handoff from the
audio isolate to the XARA worker. That is an adjacent audio change, not a reason
to redesign all existing modems in the first patch.

## Two data paths, not one

XARA exposes both unconnected broadcasts and connected ARQ traffic. They must
stay distinct in HTCommander.

### Unconnected packet traffic

XARA's `kiss` API takes a command and payload directly. Its AX.25 encoding,
compression, fragmentation, and reassembly remain useful even though we do not
want the KISS TCP server or the socket-level KISS framing.

For AX.25 broadcasts, send raw frames through that API and return decoded
AX.25 frames to HTCommander's existing `DataFrame` workflow. Validate the exact
frame/FCS convention at the adapter boundary. Only AX.25 command types belong
in the packet decoder; XARA's generic broadcast payloads need a separate event.

Add XARA-specific encoding metadata in
[TncDataFragment](../../src/lib/radio/tnc_data_fragment.dart) and packet display
labels. Append enum values rather than reorder them: existing captures serialize
encoding and frame-type indexes. Preserve radio/channel/region attribution,
lock usage, and existing deduplication behavior. XARA's coding is not FX.25, and
its waveform must not be wrapped in the DART or HDLC transmit chain.

This provides a small first user-facing integration. It does **not** make XARA
packets decodable by ordinary AFSK APRS receivers.

### Connected traffic

XARA owns connection setup, acknowledgements, retransmission, rate adaptation,
and disconnect timing. `HostEvent::Data` delivers connected application bytes,
not AX.25 packets. Do not fabricate `TncDataFragment` objects from those bytes
or put a second AX.25 link session around them.

Introduce a narrow connected-transport adapter with connect, byte send/receive,
disconnect, abort, connection state, and buffer/backpressure reporting. Prove
it first with a simple terminal session. Then adapt selected application
protocols, such as Winlink's B2F exchange, to consume that transport.

The current [Winlink client](../../src/lib/winlink/winlink_client.dart) supports
TCP and AX.25 radio sessions. Its application-protocol logic should remain in
HTCommander; XARA's internal compression/B2F helpers should remain responsible
only for the modem's own behavior. The
[gateway directory](winlink-gateway-directory.md) currently filters to Packet
1200, so Winlink-over-XARA also needs VARA gateway mode data and selection.
That is a later milestone, not something achieved by adding a modem menu item.

## The hard part: audio and time

XARA's station input/output uses normalized `f64` PCM at **48 kHz**. Its ARQ
`Time` unit is one 48 kHz sample, with `SECOND = 48_000`. HTCommander's Bluetooth
PCM is little-endian, signed 16-bit mono at **32 kHz**; external receive-device
pipelines can already use 48 kHz.

We need stateful conversion in both directions: 32 -> 48 kHz for RX and
48 -> 32 kHz for Bluetooth TX. Port XARA's tested streaming resampler or use
an equivalently tested band-limited implementation. Account for filter delay,
retain fractional state across blocks, and test clipping and gain. Do not reset
the resampler on each broker event or assume DART's linear resampler is enough.

The station advances time when `process` consumes samples. Feeding it only
when RX audio arrives will freeze retries and queued transmissions during
squelched silence or TX. Define one continuous monotonic audio timeline:
consume real input once, fill confirmed gaps with silence, and keep clocking
through half-duplex TX. Silence must not trigger a second clock advance when
late audio arrives. On a major dropout, fail or reset the session explicitly
rather than accumulating unbounded stale audio.

XARA's TX scheduler produces timed samples and PTT reports, then informs ARQ
when a burst finishes. Its station options include `tx_latency`, `rx_lag`, and
`ptt_tail`; FM also has waveform-specific tail accounting. Keep these semantics
and measure the actual Bluetooth/radio delays before changing constants.

The existing [radio audio path](../../src/lib/radio/radio_audio.dart) accepts
streamed `TransmitVoicePCM` blocks with `Hold` and `IsDataFrame`. The latter
selects SBC SNR allocation, which we should retain. This is a useful starting
point, but not yet a complete timed-modem output contract:

- `VoiceTransmitStateChanged` reports the engine's state, not measured RF end.
- The [audio engine](../../src/lib/radio/audio_engine.dart) waits up to 100 ms
  for another chunk before closing a non-held transmission.
- TX pacing currently starts a new stopwatch for each PCM chunk. Tiny worker
  output blocks must not repeatedly consume a fresh run-ahead allowance.
- Partial SBC frames need explicit final padding/drain handling so waveform
  tails are not dropped when a burst ends.

Add a narrowly scoped timed-data TX contract: burst identifiers, sample offsets
for key transitions, acknowledged acceptance/start/drain or equivalent latency
accounting, continuous pacing across chunks, bounded output buffering, and an
explicit end-of-burst. Never equate generating the last sample with transmitting
it over RF. Block-level PTT booleans alone lose transitions inside a block.

Use HTCommander's radio locks and a per-radio transmit arbiter to prevent voice,
APRS, SSTV, DART, and XARA from overlapping. Do not put every XARA ARQ reply
through the existing random packet-CSMA queue: XARA already schedules protocol
turnaround. Initial/broadcast channel access and radio ownership still need
coordination. Abort, audio disconnect, worker failure, or a PTT watchdog must
cancel queued audio and release the radio. Channel/mode changes must not silently
carry an active session onto a different frequency.

External Audio Receive Devices must remain **receive-only**. Disabling listen
alone is not a transmission prohibition; the adapter must reject connect/send/
tune and suppress all TX output. Passive decoding of other stations' connected
HF traffic is a separate XARA monitor feature, not automatically provided by
the ordinary station receiver.

## Dart engine interface and platform scope

Expose typed Dart configuration, process PCM, drain events, packet send,
connect/send bytes/disconnect/abort, reset/dispose, and capability queries.
Events carry received data, link state, SNR, bitrate, busy state, buffer usage,
errors, and sample-timed TX transitions. Use simple transferable worker messages
and `TransferableTypedData` where appropriate. Define buffer ownership and
length limits; avoid sending a per-sample event across an isolate boundary.

The worker is the sole owner of the engine. Mode changes, device removal, and
shutdown must cancel pending work and dispose the worker; generation identifiers
must prevent late events from targeting a new engine on the same radio. UI
diagnostics should be batched, while payloads and critical TX events remain
ordered and lossless or fail explicitly.

Use HTCommander's existing Dart/Flutter builds on Windows, macOS, Linux,
Android, and iOS. There are no new modem DLLs, shared libraries, Rust targets,
or linker configuration. Start integration testing on Windows, then exercise
the same engine on the other platforms with particular attention to mobile
CPU use, memory, background lifecycle, and audio delivery.

Pure Dart removes native modem packaging work, not the need for platform tests.
Do not promise usable mobile speeds before release-build performance and audio
tests pass. Initially the desktop-hosted web UI controls the host-side modem
through its existing bridge. Browser-side DSP is a separate milestone requiring
integer-precision, worker, performance, and audio checks; pure Dart alone does
not imply that VM isolate/audio integration works unchanged on the web.

Retain XARA's MIT attribution in redistributed sources and binaries. Upstream
documents higher speeds behind its `registered` build feature and runtime
setting, for operators with a registered VARA copy. The ARQ core also has a
`HostSettings.registered` field, so bypassing the executable could bypass its
feature guard. Default to unregistered operation, preserve the restriction in
the Dart engine's configuration API, and resolve the policy before shipping any
higher-speed option.

## Delivery plan and acceptance gates

1. **Establish reference fixtures and Dart foundations.** Pin upstream and port
  the smallest shared primitives FM needs: bit/CRC operations, deterministic
  generators, numeric conversions, coding tables, and FFT/resampling support.
  Check exact byte/sequence fixtures and explicit numerical tolerances with
  ordinary Dart tests, without requiring Rust to run them.

2. **Port and prove the FM PHY.** Port FM framing, modulation, coding/turbo
  decoding, receiver detection, and busy detection. Match reference waveforms
  and decode upstream captures, including malformed and noisy inputs. Test
  arbitrary PCM chunk boundaries. Benchmark time per audio block, worst-case
  receiver search, and decoder memory before proceeding to live integration.

3. **Port and prove FM ARQ and station orchestration.** Port wire codecs,
  compression, broadcasts/reassembly, session transitions, adaptation, and TX
  scheduling. Two Dart engines must connect, transfer binary data byte-for-byte
  in both directions, and disconnect over deterministic simulated audio.
  Compare event traces and deadlines against upstream fixtures. Exercise
  Dart-to-Rust and Rust-to-Dart audio interoperability in the optional reference
  harness so shared porting errors cannot hide behind self-loopback.

4. **Prove the HTCommander audio path.** Add the worker and resampling adapter
   behind an experimental capability. Test silence, squelch gaps, chunk-size
   variation, latency, RX lag, cancellation, and queue limits. Round-trip the
   waveform through HTCommander's actual SBC encoder/decoder and a modeled FM
   voice channel. Establish a measured timing budget before enabling RF TX.

5. **Ship experimental XARA FM packets beside DART.** Start with FM narrow,
   direct AX.25 broadcasts, packet metadata, settings/lock overrides, and
   receive-only external sources. Validate against another XARA instance and
   VARA FM 4.4.0 in both directions. Test wide separately; its useful passband
   may exceed the handheld's voice/SBC path. Keep APRS AFSK routing intact.

6. **Add connected FM sessions.** Wire the connected transport to a terminal,
   including retries, busy state, rate changes, buffer pressure, timeout,
   disconnect, and abort. Require binary identity and RF timing tests with VARA,
   not just self-loopback. Then extend Winlink transport and gateway metadata
   in a separately scoped change with end-to-end mail-transfer tests.

7. **Port HF and complete platform validation.** Apply the same primitive,
  waveform/capture, ARQ-trace, and cross-implementation gates to HF. Validate
  HF 500/2300/2750 modes on a
   suitable HF radio/audio path; our FM handheld integration is not an HF radio
  interface. Validate existing desktop and mobile builds without a Rust install,
  and measure sustained audio processing and lifecycle behavior on each.
   Defer digipeating, blind HF monitoring, and rich constellation diagnostics
   until the basic packet/session paths are stable.

Port upstream PHY capture/vector tests, ARQ link/timing tests, and station
audio-link tests rather than inventing a new compatibility oracle. Especially
use the existing `fm_audio_link`, `station_tx`, and latency-test patterns. Add
focused adapter tests to HTCommander's existing modem tests for sample counts,
FCS conventions, metadata, persistence, source teardown, and receive-only safety.
The original hardware latency loopback test requires an actual loopback and is
not a substitute for Bluetooth/radio latency measurements.

Success means **interoperability and reliable timing**, not achieving VARA's
advertised top speed on every handheld. SBC, the FM audio passband, squelch,
pre/de-emphasis, and radio buffering may limit useful modes. Measure those
limits and let XARA's adaptation work within them.

## The next implementation step

The FM modem is complete in Dart, wired into HTCommander's software modem, and
usable for Winlink over VARA FM (see the progress updates above). Next is
calibrating the transmit latency on real radios and the first over-the-air
session against a VARA FM gateway. Keep each step testable before transmitting
over RF.

**Pure Dart is the implementation constraint, not an optional optimization.**
The timing budget, higher-speed policy, and validated platform performance remain
decisions to settle as the port and prototypes produce evidence. The end goal
is a VARA-compatible XARA modem alongside DART that builds with HTCommander's
normal Flutter toolchain.