# Catching Weather Balloons: Radiosonde Decoding in HTCommander

*Twice a day, from hundreds of stations around the world, a weather balloon
climbs 35 km into the stratosphere carrying a small transmitter that chirps its
GPS position, temperature, and humidity back to the ground. This post is about
teaching a Benshi handheld to listen in: what a radiosonde is, the six very
different sonde families HTCommander now decodes from a single channel, the
modems and error-correction we built in pure Dart to pull each one apart, why
one popular sonde is impossible to position offline — and how the whole thing
switches itself on the moment you name a channel `Radiosonde`.*

---

## Setting up your radio to receive radiosondes

Before any decoding runs, HTCommander needs to *hear* a sonde on a channel it
recognizes. The rule is the same one used for SARSAT beacons, and it's simple:

> **Name the channel `Radiosonde`.** Case doesn't matter — `Radiosonde`,
> `radiosonde`, and `RADIOSONDE` all work. HTCommander watches for audio arriving
> on a channel whose name is "radiosonde" and feeds only that channel into the
> sonde decoders.

The channel needs a receive-oriented configuration:

- **Receive frequency** — wherever your local sonde is transmitting, somewhere in
  the **400–406 MHz** meteorological band (403 MHz is a common launch frequency).
  Many Benshi-class radios have wideband receive that covers this band.
- **Wide FM** — radiosondes use a wider deviation than 12.5 kHz voice; wideband
  demodulation generally recovers the signal best.
- **Flat / no de-emphasis** — the decoders want the raw demodulated waveform, not
  audio shaped for a human ear.
- **Receive-only** — this is a licensed meteorological band; you listen, you don't
  transmit.
- **Mute** — so the data bursts don't buzz out of the speaker while you work.

### Finding a sonde to hear

Radiosondes launch on a schedule — most stations release one around **00:00 and
12:00 UTC**, and the balloon is in the air (and in radio range) for a couple of
hours as it climbs and then drifts back down under a parachute. To find one near
you and its exact frequency, the community trackers
[SondeHub](https://sondehub.org/) and [radiosondy.info](https://radiosondy.info/)
show live launches, frequencies, and predicted landing sites. Tune your
`Radiosonde` channel to that frequency during a launch window and the decoding
below runs automatically.

---

## What is a radiosonde?

A **radiosonde** is the disposable instrument package on a weather balloon. It's
the single most important source of upper-air data feeding the world's weather
models. The routine goes like this:

1. A meteorological station fills a latex balloon with hydrogen or helium and
   ties on a **sonde** — a foam box the size of a paperback with a GPS receiver,
   temperature and humidity sensors, a battery, and a small **UHF transmitter**.
2. The balloon rises at ~5 m/s to around **35 km**, sending a telemetry frame
   every second or two: **GPS position and altitude**, plus **PTU** (Pressure,
   Temperature, Humidity).
3. The balloon expands until it bursts. The sonde parachutes back down,
   transmitting the whole way.
4. On the ground, a hobby of **sonde chasing** has grown up around recovering the
   landed sondes — which is a big part of why decoding them on a handheld is fun.

Everything HTCommander does here is **receive-only**. We're eavesdropping on a
public transmission, turning a telemetry burst into a position on the map.

---

## What HTCommander supports

The catch with radiosondes is that there is no single standard. Different
manufacturers — Vaisala, Graw, Meteomodem, InterMet, Lockheed Martin — each use
their own modulation, framing, and error-correction. HTCommander decodes **six
families**, ported from the reference C decoders in the
[`radiosonde_auto_rx`](https://github.com/projecthorus/radiosonde_auto_rx) /
[rs1729 RS](https://github.com/rs1729/RS) projects (author zilog80) into pure
Dart:

| Family | Maker | Modem | Error correction |
|---|---|---|---|
| **RS41** | Vaisala | GFSK 4800 baud, NRZ | Reed–Solomon(255,231) ×2 |
| **DFM** (06/09/17) | Graw | 2-FSK, Manchester, 2500 baud | Hamming(8,4) |
| **M10** | Meteomodem | Manchester + differential, 9615 baud | linear checksum |
| **M20** | Meteomodem | Manchester + differential, 9600 baud | linear checksum |
| **iMet-1-RS / iMet-4** | InterMet | Bell-202 AFSK 1200 baud, 8N1 | CRC-16-CCITT |
| **LMS6** | Lockheed Martin | NRZ 4800 baud | convolutional + Reed–Solomon(255,223) |

The one common thread: they all reduce, after FM demodulation, to a stream of
telemetry frames carrying a **GPS position**. That's what we extract — latitude,
longitude, altitude, velocity, satellites, time, and (where available) the sonde
serial number.

**Not supported: RS92.** Vaisala's older RS92 doesn't transmit a computed
position — it sends *raw GPS pseudoranges*, and you need live broadcast
**ephemeris** (the satellites' orbital parameters, fetched from the internet) to
solve them into a lat/lon. Offline, from audio alone, there's simply nothing to
turn into a coordinate, so RS92 is out of scope.

---

## One channel, six modems

You don't pick a sonde type. The **monitor**
([`radiosonde_monitor.dart`](../../src/lib/radiosonde/radiosonde_monitor.dart))
buffers received audio and, on each flush, runs the buffer through *every*
decoder in turn. Each family has its own demodulator + frame parser; whichever
one produces a frame that passes its own error-correction wins. A DFM sonde and
an RS41 sonde look nothing alike on the air, but from your side it's the same
channel — you tune to the frequency, and the right decoder lights up.

Most of the demodulators share the same skeleton, honed first on the DFM decoder
and reused across the FM-baseband families:

1. **DC-block and normalize** the incoming PCM, and build a prefix-sum array so
   any window's mean is an O(1) lookup.
2. **Find the frame** with a matched filter: correlate the sonde's fixed sync
   pattern against the signal to locate frame starts *and* recover polarity
   (whether the FM demod came out inverted).
3. **Refine the symbol rate** from the measured spacing between successive sync
   hits — real transmissions drift, and a symbol clock that's off by 0.1% will
   slip a bit halfway through a long frame.
4. **Integrate-and-dump** each symbol and slice it to a bit.

What differs — and what made each family its own project — is everything *after*
the bits.

---

## The families, and what makes each interesting

### RS41 — Reed–Solomon and a whitening mask

Vaisala's RS41 is the most common sonde in the world, and the most robust. It's
plain 4800-baud NRZ GFSK, but the payload is **scrambled** with a fixed 64-byte
XOR "whitening" mask (so the transmitted signal has plenty of transitions to keep
a receiver's clock locked), and it's protected by **two interleaved
Reed–Solomon(255,231) codewords** — one over the even bytes, one over the odd —
that between them can fix a dozen byte errors per frame. The position is a full
**ECEF** vector (Earth-Centered, Earth-Fixed X/Y/Z in centimetres), which we run
through the WGS-84 ellipsoid math to get lat/lon/alt, plus an ECEF velocity we
rotate into ground speed, heading, and climb rate. Decoder:
[`rs41_decoder.dart`](../../src/lib/radiosonde/rs41_decoder.dart).

### DFM — Manchester and Hamming

Graw's DFM sondes (06/09/17) are 2-FSK, Manchester-coded at 2500 baud. Each frame
is bit-interleaved and protected by a **Hamming(8,4)** code, and the interesting
wrinkle is that the sonde's serial number and calibration are *spread across many
frames* — so the decoder
([`dfm_decoder.dart`](../../src/lib/radiosonde/dfm_decoder.dart)) keeps state and
assembles a complete fix once the GPS sub-packets have all arrived. This was the
first family we built, and its demodulator became the template for the rest.

### M10 & M20 — differential Manchester, and a checksum you have to reverse-engineer

Meteomodem's M10 runs at 9615 baud with **Manchester coding plus a differential
(NRZI-style) layer** on top — which has the neat side effect of making the
recovered bitstream **immune to signal inversion**. M20 is the same modem at
9600 baud with a more compact, differently-laid-out frame. Both are guarded not
by a standard CRC but by a **custom bit-twiddling linear checksum**, ported
verbatim. Because the two share a modem, our M10 demodulator is parameterized
(sync bytes, frame length, baud) and the M20 support is the same code with
different constants. Decoders:
[`m10_decoder.dart`](../../src/lib/radiosonde/m10_decoder.dart),
[`m20_decoder.dart`](../../src/lib/radiosonde/m20_decoder.dart).

### iMet — a different beast entirely: AFSK

InterMet's iMet-1-RS is the odd one out. It doesn't send an FM-baseband bit
stream at all — it's **Bell-202 AFSK**, the same 1200-baud tones as APRS
(1200 Hz for a `1`, 2200 Hz for a `0`), framed as ordinary **8N1 async serial**
bytes. So its demodulator
([`imet_demodulator.dart`](../../src/lib/radiosonde/imet_demodulator.dart)) is a
tone detector: a recursive sliding-DFT compares the energy at the mark and space
frequencies per sample, then the bit stream is rebuilt from tone transitions and
de-framed byte by byte. The bytes carry SOH-delimited packets — a **GPS packet**
with IEEE-754 float latitude/longitude and time-of-day, plus PTU and optional
ozone-sensor packets — each checked with a **CRC-16-CCITT**. (A subtle bug we hit
and fixed: the last byte of a frame has no trailing transition, so the bit
reconstruction has to *flush* the final run or the closing CRC byte goes missing.)

### LMS6 — the deep end: convolutional coding plus Reed–Solomon

Lockheed Martin's LMS6 stacks two layers of error-correction. The 4800-baud NRZ
bits are a **rate-1/2, constraint-length-7 convolutional code** (transmitted with
every other bit inverted — the `(c0, inv(c1))` trick), which wraps a
**Reed–Solomon(255,223) CCSDS** block. Decoding is the whole pipeline in reverse:
undo the odd-bit inversion, **deconvolve** the convolutional code, pack bytes,
verify a 5-byte block sync, run the RS correction (over the byte-reversed
codeword the format uses), check a CRC-16, and finally read a big-endian GPS
frame. Making this work meant extending our Reed–Solomon core to the CCSDS
variant (a different field polynomial and a non-trivial primitive-root offset)
and writing a convolutional codec from scratch. Decoder:
[`lms6_decoder.dart`](../../src/lib/radiosonde/lms6_decoder.dart), codec:
[`convolutional.dart`](../../src/lib/radiosonde/convolutional.dart).

---

## The shared toolbox: error correction

Three families lean on the same **Reed–Solomon** engine
([`reed_solomon.dart`](../../src/lib/radiosonde/reed_solomon.dart)) — a GF(2⁸)
decoder (syndromes → Berlekamp–Massey → Chien search → Forney) that RS41 uses in
its standard form and LMS6 uses in the CCSDS configuration. The others each bring
their own guard: Hamming(8,4) for DFM, CRC-16-CCITT for iMet, the custom linear
checksum for M10/M20. In every case the check does double duty: it corrects (or
at least *detects*) bit errors, and — just as important for a weak, one-shot
signal — it tells the decoder **for certain** when it's holding a real frame
versus noise that happened to look frame-shaped. Nothing reaches the map without
passing its family's check.

---

## How we proved it works — and an honest caveat

Verification here is **synthetic round-trip**. For each family we wrote the
*inverse* of the decoder — a small modulator that renders a known frame (with
valid error-correction and CRC) as ideal audio — and fed it straight back through
the production demodulator, asserting it recovers the exact position, serial, and
time we put in. Those tests also inject byte errors to confirm the Reed–Solomon
and convolutional layers actually correct them, and exercise inversion-immunity
(M10) and the AFSK tone path (iMet). It's all in the test suite —
[`rs41_test.dart`](../../src/test/rs41_test.dart),
[`dfm_test.dart`](../../src/test/dfm_test.dart),
[`m10_test.dart`](../../src/test/m10_test.dart),
[`m20_test.dart`](../../src/test/m20_test.dart),
[`imet_test.dart`](../../src/test/imet_test.dart),
[`lms6_test.dart`](../../src/test/lms6_test.dart), and
[`reed_solomon_test.dart`](../../src/test/reed_solomon_test.dart) — 25 tests in
all, and the whole thing analyzes clean.

The honest part: a round-trip test proves the DSP, framing, error-correction, and
field-parsing are all *internally consistent* and ported faithfully from the
reference decoders — but it does **not** by itself prove bit-for-bit
compatibility with a real over-the-air sonde. The constants (sync words, masks,
field offsets, polynomials) were taken straight from the reference C, so the
odds are good; but the strongest possible test — dropping a real recording
through the production path — is the one piece still outstanding. If you can
capture a 32 kHz mono WAV of a live sonde, it becomes a permanent regression
fixture, exactly as the SARSAT self-test recording did.

---

## How it shows up in HTCommander

When a sonde decodes, it lands in the **Comms tab** as its own message type — a
light-blue icon and a `Radiosonde` label — carrying the sonde family
(`RS41`, `DFM09`, `M20`, `iMet`, `LMS6`, …), the serial, position, altitude, and,
when present, temperature. Opening the message details breaks the frame down
field by field. Repeated fixes from the same sonde **coalesce** into a single,
updating bubble rather than spamming the history.

On the **Map tab**, each sonde with a position gets a marker that tracks its
latest fix, so you can watch a balloon climb, drift, and descend across the map in
real time — and, if you're the chasing type, see where it's headed.

It all self-activates the moment audio arrives on your `Radiosonde` channel and
goes quiet when you switch away — no checkbox, no per-type setting, no assumption
about frequency. Name the channel, tune to a launch, and watch the stratosphere
report in.
