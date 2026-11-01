# How XARA-FM Works: From Bytes to Radio Audio and Back

*October 31, 2026*

How does an email become a burst of sound that another FM radio can turn back
into exactly the same email? XARA-FM does it by combining three things: a
multi-carrier audio waveform, error-correcting codes, and a conversation between
two modems about what arrived and how fast to send the next burst.

This post walks through those pieces and a complete connection, without assuming
that you already know digital signal processing.

**A note on names and status.** [XARA](https://github.com/x0rro/xara) is an
MIT-licensed modem written in Rust. Its upstream documentation reports VARA
compatibility; HTCommander ports the FM modem into pure Dart and runs it inside
the app. Here, **XARA-FM** means that FM implementation, not a new, separate
over-the-air protocol. It is also distinct from HTCommander's **DART** modem;
**Dart** is the programming language.

The explanation below follows HTCommander's port of XARA 0.1.3. Its FM transmit,
receive, and connected-link behavior have been checked with reference vectors
and simulated audio links. **HTCommander's port has not yet been tested over the
air against VARA FM.** Those are different levels of evidence, and we should not
confuse them.

## The basics: an audio modem, not a replacement radio

XARA-FM does not generate VHF or UHF radio-frequency signals itself. It generates
ordinary audio samples. The radio sends that audio using its normal FM
transmitter, and the receiving radio converts the RF signal back into audio.
XARA then decodes that audio.

```text
Application bytes
    -> XARA framing, coding, and modulation
    -> audio -> FM transmitter -> radio channel -> FM receiver -> audio
    -> XARA detection, decoding, and link handling
    -> Application bytes
```

There are two different kinds of modulation in that diagram:

- **The radio uses FM** to carry the audio over the air.
- **The modem uses OFDM and phase/amplitude constellations** to represent bits
  inside that audio.

That second point is important. XARA-FM is not simply switching between two
audio tones for zero and one, as a basic AFSK modem does.

It also has two operating paths:

| Path | What it carries | Delivery behavior |
|------|-----------------|-------------------|
| Connected link | A byte stream between two named stations, such as a Winlink session | Acknowledgments, retries, rate adaptation, and turn-taking |
| Unconnected broadcast | Packet data, including AX.25 frames and CQ announcements | No connected-session acknowledgment or retry guarantee |

We will follow the connected path first.

## Step 1: prepare the audio path and choose a bandwidth

Both stations need a usable radio audio path and appropriate channel settings.
For the connected link, they also need callsigns so the modem can identify the
caller and the station being called.

XARA-FM supports **Narrow** and **Wide** modem bandwidths. These describe the
waveform's use of the audio channel, not an automatic change to the radio's
channel spacing or FM deviation. The radio settings and audio hardware must
support the chosen waveform too.

The narrow profile has **11 data speed levels**; the wide profile has **13**.
The lowest levels use the same sparse set of carriers. Higher levels can use
more carriers, carry more bits on each carrier, or spend less capacity on
error-correction redundancy.

Wide is not automatically better. If the audio path filters out the additional
carriers or distorts them badly, their theoretical capacity is not useful.

## Step 2: call the other station and establish the link

The caller sends a specially formatted **connect frame**, known internally as
**record 0**. It carries the station identities and connection options, including
the requested bandwidth and, when used, a path through up to two digipeaters.

The target checks that the call is addressed to it and replies with a compact
control signal indicating narrow or wide operation. Wide is selected only when
both the request and the target's configuration permit it; otherwise the session
uses narrow.

The caller then sends a **go-ahead** control signal to complete the initial
turn-taking arrangement. In this implementation, the answering station gets
the first sending turn.

The modems derive reproducible sequence keys from callsign hashes. These select
control codewords and phase-rotation sequences that both ends can reproduce.
They are **not encryption keys or proof of identity**. A callsign-derived
sequence helps a modem recognize the expected conversation; it does not make
that conversation private or authenticated.

## Step 3: turn application bytes into frames

An application supplies bytes, not OFDM symbols. The session buffers those bytes
and divides them into frames that fit the current speed level.

Besides payload, a data frame includes compact control information: whether
compression was used, whether this is the end of a turn, and a hint about the
amount of queued traffic. Its trailer can report lead-in timing and, in relevant
frame types, speed or relay information.

The modem appends a **CRC-16** checksum. The receiver later uses this to check
whether the decoded frame is intact. A CRC detects accidental corruption; it
does not correct errors by itself or authenticate the sender.

XARA has several frame layouts, called **records**:

- **0:** connection setup.
- **1 through 13:** data speed-level layouts; narrow sessions use levels 1-11.
- **14:** a short frame.
- **15:** a start frame.
- **16:** an unconnected broadcast.

These are modem frame types, not Winlink commands or AX.25 packet types.
Special short and start layouts let the protocol handle traffic that does not
fit the pattern of a long, steady transfer.

Compression is another separate layer. XARA supports text-oriented compression
and a FILES mode using DEFLATE. When enabled and applicable, compression reduces
the bytes that need to cross the link; it does not change how the radio carries
the resulting bits.

## Step 4: whiten, error-correct, and interleave the bits

Before modulation, the physical-layer encoder performs three transformations:

1. **Whitening.** It combines the frame bits with a deterministic pseudo-random
   sequence. Repetitive input then looks less repetitive to the modulation
   system. The receiver knows the same sequence and reverses this operation.
   Whitening is not compression or encryption.
2. **Turbo coding.** It adds redundant information so the receiver can recover
   the original bits even when some observations are noisy. The turbo code
   combines convolutional coding paths, one of which sees a permuted version of
   the input.
3. **Channel interleaving.** It rearranges the coded bits before transmission.
   A localized disturbance is consequently spread across positions in the
   decoder's input instead of remaining one concentrated run of damage.

Speed levels also specify **puncturing**: selected coded bits are not transmitted.
Keeping more redundancy improves robustness; transmitting less redundancy
leaves more capacity for useful data but requires a cleaner channel.

All of these transformations have to agree exactly at both ends. A different
bit order or permutation table is enough to make an otherwise plausible
waveform undecodable.

## Step 5: distribute the coded bits across many audio carriers

**OFDM** stands for *orthogonal frequency-division multiplexing*. Think of it as
many carefully spaced audio carriers transmitting in parallel.

Each carrier carries a symbol representing a small group of bits. At the low
levels, XARA-FM uses differential QPSK: information is represented by changes in
phase between successive symbols. At higher levels it uses QAM constellations,
which represent information through both phase and amplitude.

A **constellation** is the set of allowed symbol values:

- Four possible values represent **2 coded bits**.
- Sixteen possible values represent **4 coded bits**.
- Sixty-four possible values represent **6 coded bits**.
- Two hundred fifty-six possible values represent **8 coded bits**.

More values mean more bits per symbol, but the values are closer together.
Noise or distortion that is harmless for a four-point constellation may push a
256-point symbol toward the wrong value.

Some concrete layouts from the FM tables:

| Profile and data level | Active carriers | Coded bits per data symbol on each carrier |
|------------------------|-----------------|------------------------------------------------|
| Narrow or Wide, level 1 | 14 | 2 |
| Narrow or Wide, level 3 | 58 | 2 |
| Narrow, level 11 | 58 | 7 |
| Wide, level 4 | 98 | 2 |
| Wide, level 13 | 116 | 8 |

These numbers are **not application throughput**. Error-correction redundancy,
markers, pilots, frame metadata, lead-in, control replies, and retries all cost
time or capacity.

Not every carrier symbol carries payload:

- **Markers** provide recognizable structure for frame detection and alignment.
- **Pilots** provide reference values for the QAM receiver to estimate how the
  channel has changed amplitude and phase. The FM QAM layout inserts pilots on a
  nine-symbol cycle, staggered between carriers.
- **Deterministic phase rotations** are applied across carriers and symbols.
  The receiver reproduces and removes them using the appropriate sequence.

## Step 6: synthesize the audio and key the radio

The transmitter uses an **inverse FFT** to combine all carrier values into one
real audio waveform.

The FM waveform uses these constants:

| Quantity | Value |
|----------|-------|
| Internal audio sample rate | 48,000 samples/second |
| FFT size | 1,024 samples |
| Carrier-grid spacing | 46.875 Hz |
| Cyclic prefix | 128 samples, about 2.67 ms |
| OFDM symbol including prefix | 1,152 samples, or 24 ms |

The carrier spacing comes from `48000 / 1024`. The prefix is a copy of the end
of the symbol placed at its beginning. With suitable receiver alignment, it
provides a guard against delayed copies of the audio interfering with the next
symbol. It is not extra payload.

The transmitter also blends symbol boundaries with a short window and scales
the waveform. Many carriers can add together into large peaks, so transmit
level is not simply a matter of making the audio as loud as possible. Clipping
or overdriving the radio can damage the constellation.

A burst starts with **lead-in audio** before the useful frames. Real radios
need time to key their transmitters, and receivers may need time to open
squelch. Without enough lead-in, the beginning of a valid frame can disappear.
The protocol reports what lead-in was heard and uses that information in its
timing.

HTCommander's radio path adds another practical detail: radio PCM runs at
**32 kHz**, while XARA runs at **48 kHz**. The app resamples between them and
hands each outgoing burst to the radio as one PCM buffer.

## Step 7: find and decode the incoming burst

The receiving modem reverses the process, but first it has to discover where
the transmission starts and which frame layout it is seeing.

Its front end filters the 48 kHz real audio and reduces it to a **6 kHz complex
representation**. Complex samples preserve the amplitude and phase information
needed by the decoder; they are an internal DSP representation, not another
radio mode.

From there, the receiver:

1. **Searches for control signals and OFDM structure.** A sliding spectral
   analysis compares successive symbols and looks for expected marker patterns.
2. **Refines symbol timing.** FFT windows must line up with the received symbols
   closely enough to separate the carriers.
3. **Extracts the carriers and undoes the phase rotations.**
4. **Compensates for the channel.** Low-level differential reception compares
   successive symbols. QAM reception uses pilot-based equalization to correct
   amplitude and phase changes.
5. **Produces soft bit estimates.** Rather than immediately declaring each bit
   zero or one, the demapper reports how strongly the received symbol supports
   each possibility.
6. **De-interleaves and turbo-decodes.** The decoder iteratively combines the
   soft evidence with the code's redundancy.
7. **Removes whitening and checks the CRC.**

The turbo decoder can stop early after a successful CRC check; this port allows
up to ten iterations. If the CRC does not pass, the frame is reported as failed
rather than delivered as valid application data.

That is the physical layer's job: turn noisy audio into either a checked frame
or an explicit decoding failure.

## Step 8: acknowledge, retry, and adjust the speed

Error correction cannot fix every damaged frame. The connected session adds
**ARQ**, or *automatic repeat request*.

After a data burst, the receiving station returns a compact control codeword.
FM control signals use **three simultaneous tones per control symbol**, with
ten symbols making a codeword, plus any lead-in. They do not use the same
payload-frame layout as OFDM data.

The replies can mean:

- Accepted: stay at the same level.
- Accepted: move up one, two, three, or six levels.
- Accepted: move down.
- Not accepted: retry.
- In a two-frame burst: only the first or only the second frame was accepted.

The sender keeps bytes buffered until acknowledgment confirms acceptance.
Missing replies trigger protocol timers and acknowledgment requests. Alternating
request codes help distinguish the current exchange from a repeated one.
Persistent failure eventually ends the link rather than pretending delivery
succeeded.

Rate selection is more careful than "one good frame means go faster." It uses
recent SNR observations, margins for candidate levels, failed climbs, and the
history of good and lost frames. Queue hints also matter: sending a small amount
of data is a different optimization problem from moving a large backlog.

Under suitable conditions, the session can put two data frames in a burst,
reducing the number of radio turnarounds. Partial acknowledgments let it retain
only the data that still needs delivery.

**The goal is useful, reliable throughput, not the highest displayed level.**
A lower level that works consistently can beat a higher one that repeatedly
retransmits.

## Step 9: reverse direction, idle, or disconnect

Ordinary handheld radio operation is **half-duplex**: a station cannot receive
the other station while it is transmitting. XARA therefore coordinates who has
the sending turn.

A **break** request and **go-ahead** response transfer that turn. Idle and
no-traffic controls maintain the conversation when there is nothing to send.
A QRT control ends the modem link; timeout and abort paths handle conversations
that cannot finish normally.

This is why a connected XARA link can look like a bidirectional byte stream to
an application even though the radio is carrying alternating bursts.

## Where Winlink and AX.25 fit

For **Winlink**, XARA supplies the connected byte transport. Winlink's B2F
exchange still handles its own message negotiation and transfer above that
transport. XARA does not need to understand the email it carries.

In HTCommander, choosing **VARA FM (XARA)** for a Winlink contact temporarily
selects XARA for the locked radio channel. The session status shows the speed
level, and ending or cancelling the contact releases the radio.

For **unconnected AX.25 packets**, the app uses record 16 broadcasts instead.
The modem encodes and, when necessary, fragments the packet buffer; a receiver
reassembles it and returns the AX.25 frame to HTCommander's normal packet path.
APRS and packet-capture consumers can then process it as a decoded frame.

This does **not** make the waveform AFSK-compatible, and it does not turn the
connected XARA session into AX.25 connected mode. AX.25 is the packet being
carried in the broadcast case; XARA supplies the audio transport.

## What makes this challenging on a real handheld?

The algorithms are only part of a working modem. The entire audio path matters:

- **Filtering and distortion:** radio audio processing can attenuate carriers or
  change their phase and amplitude.
- **Bluetooth audio coding:** the app's radio audio transport adds another
  signal-processing stage between the modem and the radio.
- **Transmit latency and squelch:** useful audio must not arrive before the
  transmitter or receiver is ready.
- **Discontinuous receive audio:** squelch-gated chunks must be reconciled with
  the modem's continuous sample clock.

HTCommander runs the modem in its own isolate so DSP does not block the UI. Its
driver maintains a 48 kHz timeline, fills gaps between receive runs with silence,
and compensates for transmit-path latency. The current default compensation is
500 ms, which still needs calibration on real radios.

Reference-vector tests show that the Dart port can reproduce the expected FM
transmit audio. Simulated station and app tests exercise connection setup,
two-way data, retries, relaying, broadcasts, and disconnect. Those establish an
important foundation, but real-radio and VARA interoperability tests remain
necessary before making field-performance claims.

## The whole system in one sentence

**XARA-FM turns bytes into error-protected symbols on many audio carriers, turns
received audio back into checked frames, and uses a half-duplex control
conversation to retry failures and choose a sensible speed.**

The waveform moves the bits. Error correction repairs what it can. ARQ handles
what it cannot. The application gets the resulting data without having to manage
every radio burst itself.

## Further reading and implementation references

- [Bringing XARA Into HTCommander](xara-modem-integration-plan.md): porting,
  integration, and the current verification status.
- [Upstream XARA](https://github.com/x0rro/xara): the original implementation and
  upstream compatibility information.
- [FM levels and layouts](../../src/lib/hamlib/xara/fm_level.dart) and
  [OFDM constants](../../src/lib/hamlib/xara/ofdm_const.dart).
- [Frame formatting](../../src/lib/hamlib/xara/fm_frame.dart),
  [coding and whitening](../../src/lib/hamlib/xara/fm_code.dart), and
  [audio modulation](../../src/lib/hamlib/xara/fm_tx.dart).
- [Receive front end](../../src/lib/hamlib/xara/fm_rx_frontend.dart),
  [OFDM receiver](../../src/lib/hamlib/xara/fm_rx.dart), and
  [frame decoding](../../src/lib/hamlib/xara/decode.dart).
- [Control codewords](../../src/lib/hamlib/xara/fm_ctrl.dart),
  [connected session](../../src/lib/hamlib/xara/fm_session.dart), and
  [rate adaptation](../../src/lib/hamlib/xara/fm_adapt.dart).
- [Broadcast framing](../../src/lib/hamlib/xara/fm_broadcast.dart) and
  [HTCommander audio driver](../../src/lib/hamlib/xara/xara_driver.dart).
