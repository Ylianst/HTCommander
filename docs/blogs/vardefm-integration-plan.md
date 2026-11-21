# Bringing VardeFM Into HTCommander: An Open FM Modem With Its Own Waveform

*Design proposal, November 18, 2026. Based on VardeFM revision `0061388`
and HTCommander revision `537a731`. This is an integration plan, not an
announcement of working VardeFM support or an over-the-air test report.*

HTCommander already has several ways to move data through a handheld radio:
the radio's hardware TNC, AFSK/PSK software modems, DART, and XARA FM.
[VardeFM](https://github.com/notepid/vardeFM) offers another interesting
option: an open, documented FM data modem, implemented in Rust, with adaptive
OFDM modulation and a reliable connected byte stream.

The attractive part is not just another modulation scheme. VardeFM separates
its modem and link state machines from sound cards, sockets, and PTT. That
gives us a reasonable integration boundary for HTCommander's existing
Bluetooth audio path.

There is one distinction we need to make before discussing any implementation:

> **VardeFM speaks a VARA-compatible host interface. It does not speak the
> VARA FM waveform over the air.**

Both ends need VardeFM. Selecting it would not let HTCommander connect to an
ordinary VARA FM Winlink gateway or an XARA station. It must be a separate
modem choice, not a different implementation hidden behind the XARA setting.

## What actually runs inside VardeFM?

The [upstream workspace][varde-workspace] breaks down into three useful layers:

```text
Host application: Winlink, terminal, or another byte-stream client
                    |
        Commands, events, and binary data
                    |
    Station + ARQ link: connect, deliver reliably, disconnect
                    |
    Modem + FEC + DSP: bytes <-> 48 kHz mono floating-point audio
                    |
        Radio adapter: audio devices and PTT
                    |
                  FM radio
```

The DSP crate generates and receives OFDM. The FEC crate supplies LDPC
error correction, checksums, scrambling, and interleaving. The modem crate
assembles complete bursts and detects them in a stream of audio. The link
crate makes those bursts into a reliable, bidirectional connection.

Finally, the TNC crate supplies a `Station`, the TCP host interface, a
sound-card radio engine, and a simulated radio pair. These are related
components, not one inseparable executable.

### From bytes to audio

VardeFM's [protocol specification][varde-protocol] defines two modes:

| Property | Narrow | Wide |
|---|---:|---:|
| Intended radio connection | Microphone/speaker | Flat 9600-data port |
| Audio sample rate | 48 kHz | 48 kHz |
| Active carrier band | About 422-2672 Hz | About 281-6000 Hz |
| FFT size | 1024 | 512 |
| Cyclic prefix | 128 samples / 2.67 ms | 64 samples / 1.33 ms |
| Data carriers | 40 | 50 |
| Published full-burst net rates | About 0.7-7.4 kbit/s | About 1.9-18.7 kbit/s |

These are **audio bands**, not RF channel widths. The published rates include
FEC and burst overhead, but precede link-layer overhead, acknowledgments,
turnaround, and retransmissions. They are not promised Winlink throughput,
and they have not been measured through HTCommander's Bluetooth path.

A transmission has this shape:

```text
Leader | Preamble A | Preamble B | Robust header | Payload codewords
```

The leader is real modem audio that covers transmitter key-up and receiver
squelch opening. Preamble A has a repeating structure for burst detection;
preamble B provides more precise timing and a channel estimate.

The header contains the burst type, session ID, speed selection,
acknowledgments, and routing flags. Its 96 information bits, including a
CRC-16, become 400 LDPC-coded bits sent with BPSK.

The payload uses one of seven speed levels, from BPSK with rate-1/2 coding
to 64QAM with rate-5/6 coding. Each payload codeword has 2400 coded bits
and its own CRC-32. Information bits are scrambled before encoding, and
coded bits are interleaved before modulation. Those operations spread
error patterns and avoid pathological repetitive waveforms; they are
**not encryption**.

The modem limits a burst to 24 codewords and four seconds of payload.
That bounds clock drift within a burst, as well as how long one station
occupies the channel. The transmitter also applies mode-specific spectral
shaping and level-dependent drive, then controlled clipping/filtering to
contain peaks. We should preserve this waveform behavior rather than
substitute DART or XARA's gain conventions.

### From audio back to bytes

The [streaming receiver][varde-receiver] accepts arbitrary chunks of audio.
It detects the preambles, decodes the robust header, waits for the full
payload, and returns a burst with a success/failure result for each codeword.

The receiver uses the decoded header as additional known training data.
Pilots track the channel across the burst and help estimate noise, reducing
confidence in symbols damaged by clicks or squelch transients. The result
includes SNR and audio levels, useful for an eventual HTCommander diagnostic
display even though the TCP interface does not currently publish `SN` reports.

This is not XARA with a new constellation table. VardeFM has its own
preambles, headers, LDPC codes, and link protocol. Existing FFT or resampler
experience is useful; existing XARA wire codecs are not interchangeable.

### How the reliable connection works

The [link layer][varde-link] numbers bytes independently in each direction.
Each payload segment contains a 24-bit byte offset, a length, and data.
Every burst carries both a cumulative acknowledgment and a bitmap identifying
which codewords of the peer's last burst decoded.

That means a single damaged codeword need not force every successfully
received codeword to be retransmitted. The receiver holds out-of-order data
and delivers the reconstructed byte stream in order, exactly once.

A connection starts with callsigns and a session ID in a `ConnectReq`,
answered by a `ConnectAck`. Direct connections use a `VFM1` connect payload;
routed connections use `VFM2` and name up to two VardeFM digipeaters.
Digipeating here is part of VardeFM's protocol, not AX.25 digipeating.

The normal response turnaround is 200 ms. The base response timeout is
1.2 seconds, with busy-channel deferral and randomized retry backoff.
Rate adaptation uses measured SNR, the different drive levels, and observed
failures to request the peer's next speed. A quiet connection uses keepalives;
graceful disconnect waits for outstanding data to be acknowledged.

Those details matter because the modem, not Winlink or a terminal, owns
retransmission and radio turn-taking.

## What HTCommander already gives us

Our closest architectural example is
[the XARA integration](xara-modem-integration-plan.md), but we should copy its
**placement**, not its radio protocol.

| Existing component | What we can reuse |
|---|---|
| [Software modem broker](../../src/lib/radio/software_modem.dart) | Per-radio modem ownership, audio routing, effective modem selection, and channel-lock integration |
| [XARA isolate wrapper](../../src/lib/radio/xara_modem.dart) | Pattern for moving PCM, commands, and events off the UI isolate |
| [XARA audio driver](../../src/lib/hamlib/xara/xara_driver.dart) | Reference for sample-rate conversion, squelch-gated runs, jitter, and key-up handling |
| [Radio audio adapter](../../src/lib/radio/radio_audio.dart) | Receive PCM events and `TransmitVoicePCM` submission |
| [Audio engine](../../src/lib/radio/audio_engine.dart) | SBC encoding/decoding and paced Bluetooth transmission |
| [Winlink client](../../src/lib/winlink/winlink_client.dart) | Existing connected-stream integration alongside AX.25 and Internet transports |
| [Station/contact model](../../src/lib/models/station_info.dart) | Explicit protocol selection and persistent contact configuration |

Radio Bluetooth audio is **32 kHz, signed 16-bit mono PCM** after SBC decoding.
Audio-device receive pipelines can instead use 48 kHz, and are receive-only
in the existing software-modem integration.

VardeFM expects **48 kHz floating-point samples**. We therefore need proper
streaming sample-rate conversion at the boundary, not a sample-rate label
change. A 32 kHz source has enough sampling bandwidth for the narrow waveform;
that alone says nothing about how well SBC or the radio will preserve it.

For connected traffic, HTCommander already treats XARA data as a byte stream
instead of feeding it through `AX25Session`. VardeFM should follow that split.
We do not need to rewrite Winlink's B2F mail protocol.

## Three possible integration approaches

### 1. External modem over TCP: the quickest reference path

VardeFM already offers a command port, normally 8300, and a raw data port,
normally 8301. Commands and asynchronous events are CR-terminated ASCII.
The [host command parser][varde-host] supports callsign configuration,
listening, connect, disconnect, abort, and version queries.

Adding a small, explicit external-VardeFM transport to HTCommander would
let us validate terminal and Winlink stream handling against the unmodified
upstream executable.

But **those sockets do not carry PCM**. Running `vardefm modem` uses its
own sound-card input/output and PTT adapter. This is a useful desktop setup
with a physical audio interface, or a software-only setup with `sim-pair`.
It does not automatically connect VardeFM to a Benshi radio's Bluetooth
audio inside HTCommander.

A virtual sound-card bridge could be a desktop experiment, but it would add
device routing, latency, and deployment complexity. It is not the recommended
product architecture.

### 2. Embed the Rust modem: the recommended product direction

Keep the upstream DSP, FEC, and ARQ implementations, and expose a small
C-compatible boundary to Dart FFI. Run that adapter in a dedicated modem
isolate. Let HTCommander continue owning the radio.

```text
Winlink / Terminal
        |
HTCommander per-radio stream events and commands
        |
VardeFM isolate -> C ABI wrapper -> Rust Station / modem / link
        |                                  |
        +-------- RX/TX PCM conversion ----+
                         |
              Existing radio audio engine
                         |
                 Bluetooth SBC / radio
```

The important existing boundary is [VardeFM's `Station`][varde-station]:
it has no clock or threads of its own. Its caller supplies time, host
commands, received audio, and transmission-completion notifications.
It returns host output and complete floating-point transmit bursts.
The modem's decoder can still use worker threads internally; embedding
does not make DSP free or automatically single-threaded.

This is a good starting point, **not an FFI API that already exists**.
We would need to add the wrapper, native packaging, and Dart bindings.
Also, the current TNC crate unconditionally depends on audio, PTT, and
simulation crates. A clean mobile embedding should feature-gate or extract
the host-independent station rather than drag desktop device backends into
every build.

HTCommander already bundles C/C++ DSP through its
[native-assets build hook](../../src/hook/build.dart). That provides a
packaging pattern, not an existing Rust build pipeline. Rust targets,
Android NDK linking, native artifact generation, and CI coverage would all
be new work. The first target should be Windows desktop, then the existing
supported radio-audio platforms. Neither Rust portability nor FFI alone
enables the current radio audio path on web or iOS.

### 3. Port the modem to Dart: possible, but a larger maintenance commitment

We could reproduce VardeFM's protocol in Dart, retaining native numerical
kernels where benchmarks justify them, much as XARA now does.

The public specification and upstream tests make that feasible. However,
we would own another implementation of burst detection, LDPC graph
construction/decoding, interleaving, framing, ARQ, and adaptation. Shared
mathematical operations do not make DART's FEC or XARA's turbo coding
wire-compatible with VardeFM's LDPC.

Unless avoiding a Rust build dependency is a hard requirement, retaining
the reference implementation is the lower protocol-risk first step.
A Dart port could be reconsidered once interoperability fixtures exist.

## The hard part is the radio clock

The [upstream radio engine][varde-radio] keys PTT before queuing audio,
waits until its sound-card output has consumed the burst, applies a tail,
and only then calls `Station.tx_done(now)`. A watchdog limits overruns.

HTCommander's path is longer:

```text
Generate burst -> resample -> encode SBC -> queue Bluetooth writes
              -> radio buffers -> radio plays audio -> RF ends
```

Completing an FFI call, dispatching `TransmitVoicePCM`, or completing a
Bluetooth write is **not** evidence that the transmission has finished.
Calling `tx_done` there would start the response timer too early and could
make the modem retry while the previous transmission is still on the air.

The adapter needs an explicit lifecycle:

1. **One monotonic timeline.** Drive timers while idle as well as while
   receiving. Do not copy the sound-card engine's input-sample clock literally:
   Bluetooth receive audio stops when squelch closes.
2. **Preserve receive timing.** Use a bounded jitter buffer, streaming
   resampling, and deliberate silence handling between receive runs. Missing
   audio within a burst must be treated as a discontinuity, not spliced away
   as if the surviving samples were adjacent.
3. **Request and track a transmit job.** Preserve VardeFM's leader, convert
   its burst to host-rate PCM, and send through `TransmitVoicePCM` with
   `IsDataFrame: true` and local playback disabled.
4. **Account for actual completion.** Track sender completion/cancellation,
   expected audio duration, buffering, and measured radio latency. Existing
   `AudioDataEnd` and `VoiceTransmitStateChanged` events are useful signals,
   but their RF timing must be measured; they are not documented RF-drain
   acknowledgments. Add job correlation/completion reporting where needed.
5. **Notify the station once.** Call `tx_done` only at the adapter's
   validated end-of-transmission boundary. Resume RX without feeding local
   transmit echo back into the decoder.

Cancellation, Bluetooth loss, native errors, and watchdog expiry must fail
the transfer visibly, cancel queued audio, and release radio ownership.
They must not be reported as a successful completed burst.

We should also preserve radio-global transmit arbitration: a connected modem
cannot race APRS, voice, or another queued data job for the same transmitter.
Feed the radio's receive-run state into that scheduling decision as well as
using VardeFM's own in-band busy detector.

XARA's driver is useful prior art, not a drop-in timing adapter. In
particular, its render-ahead model advances its own station while producing
a burst; VardeFM explicitly waits for a later `tx_done` notification.

For the first radio tests, use **narrow mode**. Wide mode is intended for
flat 9600-data audio, not an ordinary filtered microphone/speaker path.
A higher PCM sample rate cannot undo radio filtering or codec distortion.
Leave wide mode experimental until the complete path has been characterized.

## Application integration: reuse streams, keep capabilities honest

The minimal embedded adapter needs operations to create/dispose a station,
submit commands and bytes, feed RX samples, advance time, obtain a transmit
burst, signal its completion, and drain events. Use opaque handles and
explicit buffer ownership; keep Rust collections and panics behind the ABI.
Return actionable native errors instead of silent fallback or process crashes.
Batch audio and events rather than making one FFI call per sample.

Above it, use a small shared connected-stream contract for connect, send,
disconnect, abort, data, buffer progress, and link state. Adapt XARA and
VardeFM separately. Do not publish VardeFM as `XaraDataReceived` or label
its diagnostics XARA merely to reuse existing listeners.

There are several concrete application changes:

- Add a distinct software-modem selection and contact protocol, with
  narrow/wide configuration. Append persisted enum values; do not renumber
  existing contact protocols.
- Extend the radio lock override so a VardeFM contact temporarily selects
  VardeFM, then restores the previous modem after release.
- Route terminal and Winlink bytes directly through the connected stream,
  preserving binary data. Do not wrap them in AX.25.
- Identify VardeFM separately in logs and captures. Its session bursts must
  not enter the normal AX.25 packet-consumer path.
- Expose drive, leader/key-up, tail/latency, and maximum speed settings only
  where the backend implements them. Benchmark decoding on target devices:
  upstream defaults to using available CPU cores for payload decoding.

Not every XARA feature has an equivalent:

| Capability | Current VardeFM behavior | HTCommander consequence |
|---|---|---|
| Reliable connected stream | Implemented | Suitable transport for terminal or Winlink application bytes |
| Up to two digipeaters | Implemented, VardeFM-specific | Validate paths and allow longer routed-session timeouts |
| Unconnected AX.25/KISS broadcast | No equivalent in the current exposed interface | Do not advertise APRS/packet broadcast through this modem |
| CQ frames and TCP `SN` reports | Not implemented | Disable unsupported discovery/reporting controls |
| `CHAT`, `COMPRESSION`, `CWID`, and `BW...` commands | Accepted but have no effect | `OK` does not mean these features were enabled |
| Encryption and modem compression | Not implemented | Do not inherit XARA capability flags |

The modem's narrow/wide mode is selected at construction/startup; the accepted
VARA bandwidth commands do not change it.

Winlink's application-level compression is a different layer from modem
compression. It can remain in the existing B2F client. However, the far end
must run both VardeFM **and an appropriate Winlink server/gateway application**.
The current packet/VARA-FM gateway directory does not establish that a station
supports VardeFM. Initially, use explicitly configured contacts rather than
relabelling existing VARA-FM gateways.

### If we use the TCP adapter during bring-up

The two-socket interface has some important edge cases documented
[upstream][varde-protocol]:

- Parse command replies and asynchronous events independently. `VERSION`
  currently returns `OK` followed by a version line.
- Open both sockets before connecting over the air. Never send payload until
  `CONNECTED`; bytes written while disconnected are dropped.
- Serialize command transactions. TCP reads can split one line or combine
  many, and binary payloads are not line-oriented.
- Track a **fresh** `BUFFER 0` after the last write, not a stale zero already
  in flight. Preserve the documented disconnect ordering, and continue reading
  final data briefly after `DISCONNECTED` because the sockets are independent.
- Each port accepts one client; another connection replaces it. Losing the
  command connection aborts the radio session. Surface either socket's failure.

Those socket-ordering concerns do not need to be recreated inside an embedded
adapter with one ordered command/data queue.

## A staged implementation and proof plan

### Stage 1: prove the application boundary without radios

Use the unmodified upstream simulator:

```powershell
Set-Location C:\Code\vardeFM
cargo run --release -p vardefm-cli -- sim-pair --mode narrow --cnr 18 --ppm -40
```

It exposes station A on 8300/8301 and B on 8310/8311 by default.
This is a future integration-test setup, not something needed to read this
article. A new HTCommander TCP adapter would connect to one side and a
test peer to the other.

Transfer binary fixtures in both directions, including zeros and all byte
values. Require exact byte equality, correct buffer drain, graceful shutdown,
and visible failure on either socket closing. Upstream's
[sim-pair tests][varde-tests] provide a useful reference.

A random-byte peer is not a Winlink server: test real B2F exchanges separately
with an appropriate peer application.

### Stage 2: embed and interoperate with upstream

Build the Rust wrapper and a Windows native artifact first. Test the FFI
lifecycle, error propagation, buffer ownership, repeated create/dispose,
and cancellation. Then connect the embedded station to an unmodified
upstream station through deterministic audio fixtures or the simulator.

Cover both calling directions, lost/corrupt bursts, speed changes, multiple
bursts, and disconnect with data outstanding. Require byte-for-byte recovery
with no duplicates or reordering. Pin the upstream revision: its protocol
document is still marked draft, and a package version alone is not a
sufficient interoperability fixture.

### Stage 3: exercise HTCommander's real audio pipeline

Include 48-to-32-to-48 kHz conversion and SBC encode/decode, then inject
the bursty delivery, silence gaps, and loss seen on Bluetooth. Test that
the radio scheduler never overlaps jobs and that `tx_done` follows completion,
not enqueue. Explicitly cover canceled jobs, stalled senders, closed squelch,
and disconnection while keyed.

Measure decode latency, CPU, memory, and audio underruns on desktop and
Android. Choose a safe maximum level from those measurements rather than
assuming every phone should run the highest rate.

### Stage 4: narrow-mode radio trials

Start with two controlled stations and conservative levels. Measure PTT/key-up,
leader loss, receiver opening, end-to-end delay, and tail before tuning timers.
Log recovered bytes per second, codeword failures, retransmissions, and
session completion, not just the selected constellation.

Only claim interoperability and supported rates after repeated transfers
through the intended radios. Add digipeaters and investigate wide mode
after the direct narrow link is reliable.

## Packaging and licensing

The inspected source declares **MIT OR Apache-2.0**. Its README says releases
through 0.3.2 were published under GPL-3.0-or-later, while the inspected
workspace still reports version 0.3.2. Therefore, a version string does not
tell us which license accompanies a particular archive.

Pin and audit the exact source/artifacts we distribute, retain the applicable
license and attribution notices, and review transitive dependencies. Do not
assume an older downloaded binary has the same licensing as this checkout.

## The practical recommendation

Treat VardeFM as a **new connected-stream modem**, alongside XARA rather
than underneath its name. Use the existing TCP interface to establish a
reference, then embed the Rust station behind a small FFI adapter for the
Bluetooth product path.

Most of the app infrastructure already exists: per-radio ownership, PCM
transport, isolates, connected terminal sessions, and Winlink's mail engine.
The new work is preserving VardeFM's protocol, building and packaging its
native core, making capabilities explicit, and getting the radio timing right.
The first meaningful milestone is a reliable narrow-mode transfer against
an unmodified VardeFM peer, not a new modem entry in the settings menu.

### Source trail

VardeFM links below are pinned to the inspected revision. HTCommander links
throughout the article point into this repository.

- [Workspace overview and licensing][varde-workspace]
- [Physical, link, and host protocol specification][varde-protocol]
- [Burst construction, FEC, and speed levels][varde-modem]
- [Streaming burst receiver][varde-receiver]
- [Reliable link state machine and timing defaults][varde-link]
- [Host command parsing and compatibility no-ops][varde-host]
- [Host-independent station API][varde-station]
- [Sound-card engine and transmission-completion handling][varde-radio]
- [End-to-end TCP/simulator tests][varde-tests]
- [Radio setup, levels, and timing guidance][varde-radio-guide]

[varde-workspace]: https://github.com/notepid/vardeFM/blob/0061388/README.md
[varde-protocol]: https://github.com/notepid/vardeFM/blob/0061388/docs/PROTOCOL.md
[varde-modem]: https://github.com/notepid/vardeFM/blob/0061388/crates/vardefm-modem/src/lib.rs
[varde-receiver]: https://github.com/notepid/vardeFM/blob/0061388/crates/vardefm-modem/src/receiver.rs
[varde-link]: https://github.com/notepid/vardeFM/blob/0061388/crates/vardefm-link/src/lib.rs
[varde-host]: https://github.com/notepid/vardeFM/blob/0061388/crates/vardefm-tnc/src/host.rs
[varde-station]: https://github.com/notepid/vardeFM/blob/0061388/crates/vardefm-tnc/src/station.rs
[varde-radio]: https://github.com/notepid/vardeFM/blob/0061388/crates/vardefm-tnc/src/radio.rs
[varde-tests]: https://github.com/notepid/vardeFM/blob/0061388/crates/vardefm-tnc/tests/simpair.rs
[varde-radio-guide]: https://github.com/notepid/vardeFM/blob/0061388/docs/RADIO.md
