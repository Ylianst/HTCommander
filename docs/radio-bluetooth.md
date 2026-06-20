# Radio Bluetooth (macOS) — what we actually know

This document captures the **verified, hardware-tested** facts about how the
BTech/Benshi-style radios (UV-PRO and relatives) expose Bluetooth Classic, as
observed on macOS via IOBluetooth. It supersedes the theory in
[csharp-bluetooth-reference.md](csharp-bluetooth-reference.md) wherever they
disagree — in particular **the audio channel is NOT the advertised Generic Audio
(`0x1203`) service**.

Test radio: UV-PRO, MAC `38:D2:00:00:FA:F9`. Evidence gathered with
`tools/bttest` (`scan`, `probe`, `both` modes) while a NOAA weather channel
provided constant audio.

## TL;DR

- The radio exposes **two independent RFCOMM endpoints** we care about:
  - **Control** — GAIA-framed commands & status (SPP `0x1101`).
  - **Audio** — `0x7E`-framed SBC audio (the vendor **"BS AOC"** service, a
    custom 128-bit UUID).
- **Audio streams on the "BS AOC" vendor service, channel 2 — NOT on Generic
  Audio `0x1203`.** On this radio `0x1203` resolves to the same channel as a
  control endpoint and answers GAIA control traffic; it does **not** carry audio.
- **RFCOMM channel numbers are unstable** across SDP queries. Always resolve a
  service by its **UUID**, never a hardcoded channel number.
- **The radio only starts streaming audio after it has received the GAIA control
  handshake.** No audio flows on a cold connection until control commands are
  sent.
- On macOS, the **control and audio RFCOMM channels coexist fine** when they are
  genuinely different channels. The long-standing "macOS can't open a second
  RFCOMM channel" symptom was actually a **channel collision** (`0x1203` and
  `0x1101` both resolving to channel 1), not an OS limitation.

## SDP service map (ground truth, UV-PRO `38:D2:00:00:FA:F9`)

From `swift run bttest 38:D2:00:00:FA:F9 scan`:

| Service name    | RFCOMM ch | Service-class UUID                       | Role                         |
| --------------- | --------- | ---------------------------------------- | ---------------------------- |
| `BS AOC`        | **2**     | `39144315-32FA-40DB-85ED-FBFEBA2D86E6`   | **AUDIO** (SBC stream)       |
| `(no name)`     | 1 or 4 *  | `00001101`                               | **CONTROL** (SPP / GAIA)     |
| `Voice Gateway` | 1         | `00001203`                               | Generic Audio — acts CONTROL |
| `Voice Gateway` | 1         | `0000111F` + `0000111E`                  | HFP Audio Gateway            |
| `(no name)`     | none      | `00001200`                               | PnP / Device ID              |
| `(no name)`     | none      | `00001000`                               | SDP server                   |

\* The SPP (`0x1101`) channel number is **unstable**: it appeared as ch 1 in one
SDP query and ch 4 in another. `BS AOC` has consistently been ch 2 and Generic
Audio consistently ch 1, but do not rely on those numbers either — resolve by
UUID.

(`00000100` = L2CAP and `00000003` = RFCOMM are protocol UUIDs, not service
classes.)

## The probe that proved it

`tools/bttest probe` opens each RFCOMM channel `0..8` one at a time, listens for a
few seconds, and (with `--handshake`) sends the GAIA control handshake on each.
With NOAA audio playing:

```
=== PROBE SUMMARY ===
  ch1  frames=5    bytes=131     ← CONTROL responses (GAIA)
  ch2  frames=181  bytes=56733   ← AUDIO STREAM (7E 00 9C 71 12 ... SBC, ~45/sec)
  ch4  frames=5    bytes=131     ← CONTROL responses (GAIA)
  ch0/3/5/6/7/8 = 0
```

- **ch2** streamed continuous `0x7E`-framed SBC audio.
- **ch1 and ch4** answered the GAIA handshake (control), returning device info,
  settings, BSS settings (callsign), HT status, and event notifications.
- Without `--handshake`, **every** channel returned 0 frames — confirming the
  radio only streams audio after it receives control commands.

`bttest both --control-ch 4 --audio-ch 2 --handshake` then confirmed control
(ch4) and audio (ch2) **open simultaneously** on macOS — both
`openComplete error=0, MTU=666, isOpen=true`, no spurious close on the control
channel, and ch2 streamed continuous SBC.

## Control channel — GAIA framing

Commands are wrapped in a GAIA frame:

```
0xFF 0x01 0x00 <payloadLen> <group_hi group_lo cmd_hi cmd_lo> <data...>
```

- The handshake that primes the radio sends, in order: `GET_DEV_INFO`
  (group 2, cmd 4), `READ_SETTINGS` (2, 10), `READ_BSS_SETTINGS` (2, 33),
  `GET_HT_STATUS` (2, 20), `REGISTER_NOTIFICATION` (2, 6).
- Responses set the high bit on the command: response `cmd == request cmd | 0x8000`
  (e.g. request `0x0004` → response `0x8004`).
- Example responses observed on the control channel:
  - `FF01000B 0002 8004 ...` — GET_DEV_INFO
  - `FF010017 0002 800A ...` — READ_SETTINGS
  - `FF01002F 0002 8021 ...` — READ_BSS_SETTINGS (contains callsign)
  - `FF010005 0002 8014 00 ........` — GET_HT_STATUS
  - `FF010005 0002 0009 01 ........` — EVENT_NOTIFICATION (HT_STATUS_CHANGED)

## Audio channel — `0x7E` framing + SBC

Audio frames on the **BS AOC** channel use byte-stuffed `0x7E` delimiters (the
same format as the Windows C# `RadioAudio` path):

- Frame markers: `0x7E ... 0x7E`.
- Escape byte `0x7D`: the following byte is XOR'd with `0x20`.
- After unescaping, `frame[0]` is the opcode:

| Opcode | Meaning              |
| ------ | -------------------- |
| `0x00` | Received audio (SBC) |
| `0x03` | Received audio (SBC) |
| `0x01` | Audio end            |
| `0x02` | Audio ACK (ignored)  |
| `0x09` | Transmit audio (SBC) |

- The payload after the opcode is an SBC frame: **32 kHz, 16 blocks, mono,
  Loudness allocation, 8 subbands, bitpool 18** (SBC sync `0x9C`). A real frame
  on the wire looks like `7E 00 9C 71 12 ...`.
- The radio **streams audio on its own** once primed; the app sends nothing to
  "start" audio. Silence (no frames) is normal when there is no FM audio.

## Implications for the macOS implementation

1. **Resolve the audio channel by the vendor UUID**
   `39144315-32FA-40DB-85ED-FBFEBA2D86E6` ("BS AOC"), not by `0x1203` and not by
   a hardcoded channel number.
2. **Resolve the control channel from the `0x1101` SPP record** (its channel
   number varies — never assume ch 1 or ch 4).
3. **Send the GAIA control handshake** on the control channel before expecting
   audio. In practice the existing radio control layer already does this on
   connect; audio simply needs the control channel up and primed.
4. Control + audio coexist on macOS as long as they are distinct channels, which
   they are when audio uses BS AOC (ch 2) and control uses SPP.
5. After any change to the native Swift layer, do a full `flutter run -d macos`
   restart — hot reload/restart does **not** rebuild native macOS code.

## Tooling

`tools/bttest` (SwiftPM, IOBluetooth) — modes:

- `scan <MAC>` — list SDP services with RFCOMM channel + class UUIDs.
- `probe <MAC> [--probe-range A B] [--dwell S] [--handshake]` — open each channel
  in a range one at a time and tally received frames/bytes; print a summary.
- `control` / `audio` / `both <MAC> [--control-ch N] [--audio-ch N] [--handshake]
  [--close-audio S]` — open specific channels and dump labeled frames.

Run with an absolute package path, e.g.:

```
swift run --package-path /path/to/HTCommanderEx/tools/bttest bttest 38:D2:00:00:FA:F9 scan
```
