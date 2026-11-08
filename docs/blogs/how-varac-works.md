# How VarAC Works: A Chat Application on Top of the VARA Modem

*November 8, 2026*

[VarAC](https://www.varac-hamradio.com/) is one way to
hold a live, keyboard-to-keyboard conversation over amateur radio on HF, and it
also runs over VHF/UHF FM and the QO-100 satellite. Since HTCommander now carries
a VARA-compatible modem ([XARA](xara-fm-how-it-works.md)), a common question is
how VarAC fits together, and what part of it a modem actually provides.

This post explains VarAC's architecture and features, and where the line falls
between the **modem** (VARA, or XARA) and the **chat application** (VarAC).

## The big picture: two programs and a radio

VarAC does not modulate anything itself. It is a *host application* that
drives a separate modem program, VARA, over a local TCP connection. VARA turns
bytes into audio and back, and VarAC handles everything a person sees:
callsigns, CQ calls, the chat window, mailboxes, logs and rig control.

```text
            +------------------+   TCP (commands + data)   +-------------------+
 Operator ->|      VarAC       |<------------------------->|  VARA modem (main) |
            |  chat, CQ, VMail |                           +---------+---------+
            |  logs, rig ctrl  |<---- TCP ---->+-------------------+  | audio
            +---+----------+---+               | VARA modem (mon.) |  |
                |          |                   +---------+---------+  |
   CAT / PTT    |          | TCP/UDP                     | audio      |
   (freq + key) v          v                             v            v
             +------+   Loggers,                     +------------------+
             | Rig  |   PSK Reporter                 |   Radio audio    |
             +------+                                +------------------+
```

The official architecture slide shows exactly these pieces: VarAC in the
middle, a **main** VARA modem for the conversation, an optional **monitor**
VARA modem, the rig (PTT and frequency control), loggers over TCP/UDP, and
PSK Reporter.

VARA itself comes in three flavours, all with the same host interface:

| Modem | Use | Published top speed |
|---|---|---|
| VARA HF | HF SSB | 1,543 bps at 500 Hz, 7,050 bps at 2300 Hz |
| VARA SAT | QO-100 | Like HF, with extra latency handling |
| VARA FM | VHF/UHF FM | 12,750 bps narrow, 25,210 bps wide |

The free VARA licence is limited to about 170 bps, which is still plenty for
typed conversation.

## The layer VarAC stands on: the VARA host interface

This is the part that matters most for HTCommander, because it is the layer a
VARA-compatible modem must provide. It is openly documented by VARA's author.

A host application opens two TCP connections to the modem:

- **Command port** (default 8300): text commands and events, each ending in a
  carriage return.
- **Data port** (default 8301): the raw byte stream carried over the radio
  link. The modem makes it error-free with ARQ (automatic repeat request) and
  does not interpret it.

The commands that matter for a chat application are:

| Command (host -> modem) | Purpose |
|---|---|
| `MYCALL Call1 ... Call5` | Up to five callsigns the station answers to. SSIDs `-1`..`-15`, `-T` and `-R` are allowed. |
| `LISTEN ON` / `LISTEN OFF` | Accept or refuse incoming connections. |
| `CHAT ON` / `CHAT OFF` | Select keyboard-to-keyboard timing or Winlink-style timing (details below). |
| `CQFRAME Source BW` (HF), `CQFRAME Source` (SAT), `CQFRAME Source Digi1 Digi2` (FM) | Send a CQ frame: a short, unconnected "I'm here" announcement. |
| `CONNECT Source Destination` (FM adds `via Digi1 Digi2`) | Start an ARQ link. |
| `DISCONNECT` / `ABORT` | End a link gracefully, or immediately. |
| `COMPRESSION OFF / TEXT / FILES` | Link-level compression for the data stream. |
| `BW500` / `BW2300` / `BW2750` | VARA HF bandwidth. |

The modem reports back with events:

| Event (modem -> host) | Meaning |
|---|---|
| `CONNECTED Source Destination BW` | A link is up. |
| `DISCONNECTED` | The link is closed. |
| `PTT ON` / `PTT OFF` | Key or unkey the transmitter. The host does this through CAT or RTS/DTR. |
| `BUFFER Bytes` | How many bytes are still queued to send. A chat client uses this for its progress bar. |
| `PENDING` / `CANCELPENDING` | Someone is trying to connect, so stop scanning. |
| `BUSY ON` / `BUSY OFF` | The channel is occupied or clear. |
| `CQFRAME Source BW` | A CQ frame was heard. This is how a chat client fills its list of heard stations. |
| `SN value` | Signal-to-noise ratio of a received frame. Sent only in chat mode. |
| `IAMALIVE` | Keep-alive. |

### What `CHAT ON` changes

The VARA documentation says chat mode was added for "chat type apps like VARA
Chat, VarAC, vARIM". Compared with the Winlink-oriented default it:

- **Listens for CQ frames.** `CHAT ON` includes `LISTEN ON`.
- **Idles forever.** Two stations stay in sync "until the path dies". A Winlink
  session is the opposite: it drops a link that has nothing left to send.
- **Reports SNR** with an `SN` event for every data block received, so the
  application can show and exchange signal reports.
- **Optimizes the handover** (whose turn it is to transmit) for keyboard-to-keyboard
  use, where either side may start typing at any time.
- **Tolerates higher latency**, even with SDRs at both ends of the link.

This is an important point. Much of what makes VarAC *feel* like a live chat,
including the infinite idle, quick turn-taking and per-frame SNR, is
**implemented in the modem**. VarAC selects it with one command.

## Being seen: beacons

A VarAC station can announce that it is on the air by sending a periodic
**beacon**. According to the official slides:

- The minimum beacon interval is **15 minutes**.
- A beacon is sent only if the frequency has been clear for at least **30
  seconds**.
- Beacons and CQs heard by VarAC are uploaded to **PSK Reporter**, which makes
  them useful for propagation analysis.

Since 2025 VarAC has had two kinds of beacon
([official post](https://www.varac-hamradio.com/post/advanced-beacon)):

- **Standard beacon:** minimal information, decodable down to about **-22 dB**
  SNR.
- **Advanced beacon:** sent with the AX.25 KISS protocol (like VarAC
  broadcasts) at VARA speed level 2. It carries more data, including your grid
  locator and announcements such as e-mail gateway and EmComm station status.
  It needs about -18/-19 dB to decode.

Both use VARA's unconnected (no-ARQ) transmission paths: the CQ frame, and
VARA's KISS interface for broadcasts.

## Finding each other: calling frequencies and slots

On HF, VarAC solves the "where is everyone?" problem with one **calling
frequency (CF)** per band:

| Band | Calling frequency |
|---|---|
| 80 m | 3.595 MHz |
| 40 m | 7.105 MHz (primary, night time) |
| 30 m | 10.133 MHz |
| 20 m | 14.105 MHz (primary, day time) |
| 17 m | 18.106 MHz |
| 15 m | 21.105 MHz |
| 12 m | 24.927 MHz |
| 10 m | 28.105 MHz |
| 6 m | 50.330 MHz |

Users can add their own frequencies in `VarAC_frequencies.conf`.

One calling frequency would quickly jam if every conversation happened on it.
VarAC adds a **slot system**: ten slots around the CF, five below and five
above, spaced **750 Hz** apart. The published CQ flow is:

1. Pick a slot.
2. Check that it is free, using the *slot sniffer*: the rig briefly tunes there
   to listen, without transmitting.
3. Call CQ **on the calling frequency**.
4. VarAC automatically tunes (QSYs) the rig to the chosen slot.
5. Anyone who double-clicks the CQ is taken to the same slot and connects.
6. If no one answers, the rig returns to the calling frequency.

The CQ itself is the modem's `CQFRAME`. VarAC's contribution is the convention
built around it, so that the station hearing the CQ knows where to follow.

The *code of behaviour* asks operators to use **500 Hz** bandwidth on the
calling frequency and its slots, and to keep 2300 Hz for frequencies outside
the slot range.

## Ping: a connection that only exchanges signal reports

A **ping** checks whether you can reach a station and how well each side hears
the other. VarAC connects, the two sides exchange SNR reports (built from the
modem's `SN` events), and it disconnects immediately. The code of behaviour
asks operators not to use pings for DXCC or grid hunting, because doing so
clutters the calling frequency.

## The QSO itself

Once connected, VarAC provides what users expect from a modern chat app, on top
of VARA's error-free byte stream:

- An **"is typing" indicator**.
- Incoming messages **unfold as they are received**, with a progress bar driven
  by the modem's buffer reports.
- A **message queue**: you can type ahead while the link is busy.
- Full **multilingual and emoji** support, including 4-byte UTF-8 characters.
- **Two-way SNR exchange**, so each side knows how it is being heard.
- A **periodic callsign ID** to satisfy station-identification rules.
- Automatic **QSO logging** to VarAC's ADIF file, and forwarding to common
  loggers (N1MM, Log4OM, HRD, DX Keeper, and others).

### Tags and gestures

VarAC adds a small set of **tags**: keywords in angle brackets that you type,
or put in canned messages, to automate common exchanges. The published main
tags are:

| Tag | Effect |
|---|---|
| `<NAME>`, `<QTH>`, `<LOC>`, `<RIG>` | Insert your name, QTH, location or rig info. |
| `<LHR>` | Ask for your partner's *last heard* list on this band. |
| `<FSR>` | Ask for your partner's frequency schedule (where they park during the day). |
| `<QSYU>` / `<QSYD>` | Invite your partner to move up or down 750 Hz. |
| `<QSF>14105000</QSYF>` | Free-form QSY invitation to a given frequency. |
| `<VER>` | Ask for your partner's VarAC version. |
| `<INFO>` | Ask for your partner's info (name, QTH, locator...). |
| `<AWAY>` | Open the "send message" dialog on your partner's side. |
| `<SND>` | Automatically press *Enter* to queue the message. |
| `<DISC>` | Disconnect automatically once the message is delivered. |

The slides note that "more are listed in the VarAC interface". **Gestures**
play sounds or show emojis on the other side.

The important design choice is that tags are **in-band**: they travel inside
the chat text over the ordinary VARA data stream. The modem has no idea they
exist.

## Changing frequency without dropping the link: QSY

VarAC can move a conversation to another frequency, even another band,
**while keeping the link up**. One side sends a QSY invitation, either
up/down 750 Hz or to any chosen frequency. Both operators see a confirmation
prompt, and both rigs re-tune automatically once they agree. Users are asked to
use the QSY *sniffer* first, which briefly tunes to the target without
transmitting, to check that the new frequency is free.

This works because rig control belongs to VarAC, not to VARA. The modem keeps
its link state while the application re-tunes the radio under it.

## VMail: messages for stations that aren't there

VarAC has a built-in mailbox called **VMail**:

- Connecting to a station that is marked **AWAY** offers to leave it a VMail.
- VMails can be **queued in an outbox** and forwarded the next time you connect
  to that station.
- A message can be **relayed to a third party through a mediator** station.

Community guides describe store-and-forward "parking", where a waiting VMail is
delivered automatically once its recipient's beacon is heard. That again is
application behaviour triggered by events the modem already reports.

## Files, broadcasts and monitoring

- **File transfer:** any binary file can be sent. Images (PNG, JPG, GIF) are
  shown inline, files are compressed before sending, and a size limit can be
  set for incoming files. The code of behaviour recommends 5-10 KB at high
  speed, 1-2 KB at low speed, and never on the calling frequency.
- **Broadcasts:** short unconnected messages to a specific station or to "ALL"
  on the frequency. Like the advanced beacon, they use VARA's KISS path rather
  than a connected link.
- **Monitoring:** a second VARA instance can run as a *monitor*, so VarAC can
  show traffic heard on the frequency, alongside the main modem used for your
  own conversation.

## On the wire: what third-party projects have reconstructed

The rest of this post so far comes from published sources. This section gives
the byte-level formats from the open-source
[`hfmodem`](https://github.com/sstjohn/hfmodem) project
(`packages/hfmodem/hfmodem/contact/varac.py`, AGPL-3.0). Its author built
them from VarAC's manuals, its release notes, and bench sessions against stock
VarAC. We describe the formats in our own words. Treat them as evidence-based
reconstructions, not as an official specification.

### Command-port session setup

`hfmodem` brings up a VARA HF modem the way VarAC does, with this sequence on
the command port. Each line ends in `\r`, and VARA answers `OK` or `WRONG`.

```text
LISTEN OFF
PUBLIC ON
CWID OFF
COMPRESSION TEXT
MYCALL <call>
BW500                    (or BW2300 / BW2750)
VERSION                  -> VERSION <name> <version>
CHAT ON                  (this also turns listening on...)
LISTEN OFF               (...so it is switched off again)
```

When the operator wants to be callable, the client sends `LISTEN CQ`, which
listens for CQ frames only. It falls back to `LISTEN ON` if the modem rejects
that. `PUBLIC`, `CWID`, `VERSION` and `LISTEN CQ` are not in the 2022 VARA
command document, but VARA builds that VarAC drives accept them.

VarAC keeps one bandwidth for the whole session, because a VARA station answers
a connect only at its own bandwidth. A CQ's bandwidth is therefore also the
bandwidth used on the slot.

### CQ frames: the slot is in the SSID

A VarAC CQ is a plain VARA `CQFRAME`. The **slot** the caller will move to is
encoded as a numeric SSID on the callsign:

| SSID | Meaning | Offset from the calling frequency |
|---|---|---|
| `-1` .. `-5` | Slot below the CF | -750 Hz x n (-750 .. -3750 Hz) |
| `-11` .. `-15` | Slot above the CF | +750 Hz x (n - 10) (+750 .. +3750 Hz) |
| `-9` | Standard beacon | None; the station is on the CF |
| none | CQ without a slot | None; answer on the CF |

For example, `CQFRAME N0CALL-12 500` means "N0CALL calling CQ at 500 Hz, and
moving to the CF + 1500 Hz". The VARA HF CQ frame carries the bandwidth as a
code: 1 = 500, 2 = 2300, 3 = 2750 Hz. The receiving modem reports it back in
hertz.

Observed timing:

- Stock VarAC sends each CQ **twice** on the CF, about **10 s** apart.
- The caller then waits up to about **2 minutes** on the slot for a connection.
- Standard beacons (`-9`) repeat every 15 minutes from the previous beacon, and
  need the channel clear first.

### Advanced beacon layout

The advanced beacon is not a `CQFRAME`. It is a **20-byte ASCII payload sent as
a KISS frame with KISS command 2** through VARA's KISS port (default 8100, when
KISS is enabled in VARA). VARA drops command-0 text frames on this path.

```text
offset  0    '2'
        1    '0' or '1'      (constant per station; meaning not yet known)
        2    status letter   '@' + service bits
        3-8  grid locator    6-character Maidenhead, e.g. FN35fl
        9-   callsign        3-7 characters, then space padding to 20 bytes
```

For example: `20AFN35flN0CALL` followed by five spaces, 20 bytes in total.
Here `A` is the status letter, and the subsquare may arrive in either case.

The status letter is `'@'` (0x40) plus a bitmask of services the station
offers:

| Bit | Service |
|---|---|
| 1 | VMail (set by essentially every station) |
| 2 | E-mail gateway |
| 4 | AI gateway |
| 8 | BBS (probable) |

So `A` means VMail only, and `C` means VMail plus an e-mail gateway.

### Chat messages: length-prefixed UTF-8

On the data port, each application message is framed as:

```text
<decimal byte count><space><UTF-8 payload>
```

For example, `12 Hello there!`. The count is in **bytes**, not characters,
which matters for emoji and non-Latin scripts. There is no line terminator.
The length alone delimits messages, independently of how VARA or TCP splits
the stream. A receiver accumulates bytes until it has a full `<count> <payload>`.

### Opening signal report

Right after connecting, each side sends a signal report built from the modem's
`SN` events:

```text
de N0CALL <R-07>
```

`<R±NN>` is the received SNR in dB, always signed and two digits, clamped to
±99. This is followed by an optional services tag, `<S:...>`. Profile tags
such as `<NAME:Bob>`, `<QTH:Ottawa>` and `<LOC:FN25>` can follow as a second
message, joined by CRLF. A **ping** is just this exchange followed by a
disconnect.

### Tag forms on the wire

Beyond the user-facing tags in the table above, tags take these forms on the
wire:

| Form | Examples | Notes |
|---|---|---|
| Bare tag | `<AWAY>`, `<DISC>`, `<INFO>`, `<QSYR>`, `<SM>`, `<TL>`, `<LHR>`, `<BLR>` | Request or trigger. |
| Value tag | `<NAME:...>`, `<QTH:...>`, `<LOC:...>`, `<EM:...>`, `<SBJ:...>`, `<MSG:...>`, `<S:...>` | Values may not contain `<`, `>`, CR or LF. No escaping is known. |
| Signal report | `<R+09>`, `<R-12>` | |
| Presence / auto-QSY | `<Q>` or `<Q:-120>` | The value is an offset in tens of hertz. |
| Frequency notice | `<QF:14105000>` | Frequency in Hz. |
| Connected QSY | `<QSYF>014105000000</QSYF>` | 12-digit, zero-padded Hz (manual v16.1.8). The slides show the older `<QSF>...</QSYF>` form. |
| Typing indicator | `&IT&` | Not bracketed. It can appear anywhere in the stream, so parsers must handle it split across reads. |

A receiver should tokenize the text incrementally, splitting on `<...>` and
`&IT&`, and show unknown tags as plain text rather than dropping them.

### VMail envelope

A VMail is one framed message with this envelope:

```text
<SM><TME:2026-11-08 18:30:00><FRM:N0CALL><TO:N1CALL><SBJ:Hello><MSG:Body text>
```

- `<TME:...>` (UTC, `YYYY-MM-DD HH:MM:SS`), `<FRM:...>` and `<TO:...>` are
  optional. They appear when a mail is relayed, so that the original author and
  recipient differ from the stations on the link. Addresses may be e-mail
  addresses.
- `<SBJ:...>` and `<MSG:...>` are always present. The body may contain CRLF
  line breaks but no angle brackets.
- A relayed VMail may be preceded by `<QSYR>` or `<TL>` and CRLF in the same
  message.
- Bodies are capped at 500 characters (350 in older versions at 500 Hz).
- **Length quirk:** in at least one captured session, VarAC's length prefix
  left out the closing `>` of `<MSG:...>`, which arrived as one extra byte.
  A robust receiver accepts both.

### BBS file directory

The VarAC manual (v16.1.8) documents a directory listing reply, one file per
line, as `name|date|size`, with the closing `>` on its own line:

```text
<BL:report.txt|2026-11-01|1532
photo.jpg|2026-11-02|8840
>
```

### Still unknown

No public source documents:

- The file-transfer chunking and compression format.
- The byte layout of unconnected broadcasts (the 91-byte "ALL" or
  directed messages).
- The meaning of the second character of the advanced beacon.

## So what does a modem provide, and what does VarAC?

| Provided by the modem (VARA / XARA) | Provided by VarAC |
|---|---|
| Waveforms, coding, ARQ, error-free byte stream | Chat UI, typing indicator, message queue |
| `CHAT ON` timing: infinite idle, fast handover | Calling-frequency and slot conventions, CQ flow |
| CQ frames sent and decoded (`CQFRAME`) | Heard-station list, PSK Reporter spots |
| Per-frame SNR (`SN`), buffer level (`BUFFER`) | Signal-report exchange, progress bars, ping |
| Link compression (`COMPRESSION TEXT/FILES`) | Tags, gestures, VMail, relay, file handling |
| KISS / unconnected broadcast frames | Advanced beacon and broadcast content |
| `PTT ON/OFF` requests | Rig control: PTT, frequency, QSY, scheduler |

## What this means for HTCommander

HTCommander's XARA port already implements most of the **modem column** for
VARA FM:

- FM ARQ links with VARA's text compression.
- The chat-mode session timing described above.
- Sending and decoding CQ frames. On FM, a CQ is an AX.25 UI frame addressed to
  `VCHAT`, carried in a broadcast frame (`fm_broadcast.dart`).
- KISS broadcast frames.

Two gaps stand out:

- HTCommander does not yet switch the modem into **chat mode**, so links use
  Winlink-style idle timing, and heard CQ frames are not passed up to the app.
- HTCommander has **no VARA-style TCP host interface**. XARA is built directly
  into the app rather than exposed on ports 8300/8301.

The **application column** is VarAC's own design. With the formats above, a
VarAC-interoperable chat in HTCommander would need:

1. **Chat mode in XARA.** Set the modem's chat flag, and pass heard CQ frames
   and per-frame SNR up to the app.
2. **A chat layer on the ARQ data stream.** It would add the length-prefix
   framing, an incremental tag parser, the opening `de CALL <R±NN>` report,
   and VMail envelopes.
3. **Slot-aware CQ and beacons.** CQ frames would use the SSID slot encoding,
   and advanced beacons would be KISS command-2 frames. On HF this also needs
   rig QSY control, but HTCommander's FM handhelds have no 750 Hz slots, so
   FM use would need its own convention for slots.

Alternatively, HTCommander could **expose a VARA-style host interface** from
XARA, and let existing chat programs drive it. Either way, the formats above
are untested against real VarAC, so on-air interoperability tests are the next
step.

## Sources

- VarAC *Technical overview* slides, Irad Deutsch (4Z1AC) and Gary Mitchelson
  (NC3Z), September 21, 2022:
  <https://k0rv.org/wp-content/uploads/2024/02/VarAC_slide_show.pdf>
- VarAC, *Advanced Beacon*, July 21, 2025:
  <https://www.varac-hamradio.com/post/advanced-beacon>
- VarAC user manuals: <https://www.varac-hamradio.com/post/varac-user-manuals>
- VarAC Terms of Use: <https://www.varac-hamradio.com/varac-terms-of-use>
- *VARA Protocol Native TNC Commands*, Jose Alberto Nieto Ros (EA5HVK),
  February 13, 2022 (mirrored by the Pat project):
  <https://github.com/n8jja/Pat-Vara/blob/main/VARA%20Protocol%20Native%20TNC%20Commands.pdf>
- VARA modems: <https://rosmodem.wordpress.com/>
- `hfmodem` by Saul St John (W9SSJ), AGPL-3.0, VarAC reconstruction in
  `packages/hfmodem/hfmodem/contact/varac.py`:
  <https://github.com/sstjohn/hfmodem>
- VarAC user manual v16.1.8 (ON2AD), as cited by `hfmodem`:
  <https://download-files.wixmp.com/ugd/288b5d_124e2927d3324571a2016b69e780d159.pdf>

---

**Related:** [How XARA-FM Works](xara-fm-how-it-works.md) ·
[Bringing XARA Into HTCommander](xara-modem-integration-plan.md)
