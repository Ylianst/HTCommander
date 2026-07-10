# DART Modem — Implementation Report

**Date:** 2026-07-08 (updated 2026-07-10 with over-the-air results)
**Status:** Working prototype — validated offline **and over the air** on real radios
**Design spec:** [NextGenModem.md](NextGenModem.md)
**Proposal / rationale:** [findings/next-gen-modem-proposal.md](findings/next-gen-modem-proposal.md)

---

## Summary

DART (Data Adaptive Rate Transport) is a coherent, adaptive OFDM modem for the
VHF/UHF FM audio channel over Bluetooth (SBC codec). A first working prototype
is implemented and validated offline: it encodes text payloads to PCM audio,
survives a round-trip through the **real SBC codec** plus additive noise, and
decodes them back with CRC verification across **six adaptive modes** (BPSK
through 16QAM).

All six modes pass a full encode → SBC → noise → decode round-trip in automated
tests. The adaptive mode table demonstrates correct graceful degradation: robust
modes keep working at low SNR while high-throughput modes drop out — exactly the
behavior the adaptive design is meant to provide.

---

## What was built

### Signal-processing library (`src/lib/hamlib/`)

| File | Responsibility |
| --- | --- |
| [dart_ldpc.dart](../src/lib/hamlib/dart_ldpc.dart) | LDPC encoder/decoder — IEEE 802.11n information-part connections (N=648) with a dual-diagonal (IRA accumulator) parity structure for O(M) encoding at every rate; min-sum belief-propagation soft decoder |
| [dart_constellation.dart](../src/lib/hamlib/dart_constellation.dart) | Gray-coded BPSK / QPSK / 8PSK / 16QAM mappers and soft (LLR) demappers; `Complex` type |
| [dart_ofdm.dart](../src/lib/hamlib/dart_ofdm.dart) | OFDM + DFT-spread (SC-FDMA) modulator/demodulator — radix-2 FFT/IFFT, unitary DFT-spread precoding, subcarrier mapping, cyclic prefix, one-tap zero-forcing equalizer |
| [dart_fsk.dart](../src/lib/hamlib/dart_fsk.dart) | Constant-envelope 4-CPFSK modem for Mode F — continuous-phase tone modulation, non-coherent soft-output detection (amplitude-immune) |
| [dart_preamble.dart](../src/lib/hamlib/dart_preamble.dart) | Zadoff-Chu preamble — frame detection, timing sync, one-shot channel estimation |
| [dart_modem.dart](../src/lib/hamlib/dart_modem.dart) | Full TX/RX chain, frame/header structure, 6-mode table, decision-directed channel refinement, per-frame signal-quality measurement |
| [dart_packet_info.dart](../src/lib/hamlib/dart_packet_info.dart) | Per-packet metadata (`DartPacketInfo`, `DartSignalQuality`, frame types, flags) for the Flutter packet-capture tab |
| [dart_link.dart](../src/lib/hamlib/dart_link.dart) | Link layer — connectionless datagrams (multicast/chat) and sliding-window selective-repeat ARQ with ACK/NACK, in-order delivery, and rate adaptation |

### Test harness (`src/test/`)

| File | Purpose |
| --- | --- |
| [dart_modem_test.dart](../src/test/dart_modem_test.dart) | CLI tool: `encode`, `decode`, `loopback`, and unit tests `ldpc`, `fft`, `constellation`, `papr`, `stream` |
| [dart_debug_test.dart](../src/test/dart_debug_test.dart) | Stage-by-stage pipeline diagnostics (OFDM round-trip, preamble detect, channel estimate, header/payload) |
| [dart_sbc_probe.dart](../src/test/dart_sbc_probe.dart) | Measures SBC codec delay and preamble-correlation degradation |
| [dart_link_test.dart](../src/test/dart_link_test.dart) | Link-layer tests: connectionless datagram, ARQ ACK round-trip, sliding-window selective repeat, rate adaptation |

---

## How the pipeline works

```
TX:  payload → CRC-32 → LDPC encode → interleave → constellation map
        → DFT-spread (SC-FDMA precoding) → OFDM (IFFT + cyclic prefix)
        → prepend Zadoff-Chu preamble → guard padding → 32 kHz / 16-bit mono PCM

RX:  PCM → preamble detect + sync → channel estimate
        → decode header (always BPSK R1/2) → refine channel from header
        → demodulate payload (FFT + equalize + de-spread) → soft demap
        → deinterleave → LDPC decode → CRC-32 check
```

### Frame structure

```
[ guard ][ Zadoff-Chu preamble ][ header (mode 0) ][ payload (variable mode) ][ guard ]
```

- **Preamble** — Zadoff-Chu (root 7, length 127) plus one OFDM channel-estimation
  symbol. Constant-envelope, known to the receiver, identical for every mode.
- **Header** — always sent at mode 0 (BPSK, LDPC rate 1/2) so any receiver can
  decode it regardless of link quality. Carries the payload mode index, length,
  source/destination callsigns, sequence number, flags, and a CRC-16.
- **Payload** — modulated and coded according to the header's mode index.
- **Guard padding** — 256 samples (~2 SBC frames) before and after, so the SBC
  filterbank warms up and flushes without corrupting the frame.

### Mode table (implemented)

| Mode | Constellation | LDPC rate | Net throughput (est.) |
| --- | --- | --- | --- |
| 0 | BPSK | 1/2 | ~1 kbps |
| 1 | QPSK | 1/2 | ~2 kbps |
| 2 | QPSK | 2/3 | ~3 kbps |
| 3 | 8PSK | 2/3 | ~4 kbps |
| 4 | 16QAM | 3/4 | ~5 kbps |
| 5 | 16QAM | 5/6 | ~6 kbps |
| F | 4-CPFSK | 1/2 | ~0.4 kbps (constant-envelope fallback) |

Modes 0–5 share the same OFDM modulator/demodulator; only the constellation
lookup and LDPC rate change. Mode F uses the separate constant-envelope FSK
modulator but shares the header format, LDPC, interleaving, CRC, and ARQ.

### OFDM parameters (current)

| Parameter | Value |
| --- | --- |
| Sample rate | 32 kHz, 16-bit, mono |
| FFT size | 128 (250 Hz subcarrier spacing) |
| Active subcarriers | 9 (indices 2–10, ≈500–2600 Hz) |
| Cyclic prefix | 4 samples |

---

## Mode F: the constant-envelope fallback

Mode F ([dart_fsk.dart](../src/lib/hamlib/dart_fsk.dart)) is the amplitude-hostile
fallback. It transmits one of **four continuous-phase tones per symbol**, so the
signal is strictly **constant envelope** — completely immune to the AGC, limiter,
companding, and SBC amplitude damage that attacks the QAM/PSK modes. Detection is
**non-coherent** (per-symbol tone energy), needing neither channel estimation nor
phase tracking.

| Parameter | Value |
| --- | --- |
| Modulation | 4-CPFSK (continuous phase), 2 bits/symbol |
| Symbol rate | 400 symbols/s |
| Tones | 600 / 1000 / 1400 / 1800 Hz (flat mid-band, spaced by the symbol rate) |
| FEC | LDPC rate 1/2 (soft-decision, shared decoder) |

The entire Mode F frame — header **and** payload — is FSK, so it stays amplitude
immune end to end. The receiver tries the OFDM path first and automatically falls
back to FSK decoding. Mode F shares the header format, LDPC, interleaving, CRC,
and ARQ with the OFDM modes; only the modulator/demodulator differs.

**Demonstrated value.** Under a combined hard-clip (8% of peak) + SBC + 14 dB SNR
audio path — a genuinely hostile radio — the 16QAM modes fail every frame while
Mode F delivers every frame:

```
dart run test/dart_modem_test.dart loopback --modes 4,5,6 --clip 0.08 --sbc --noise 14
  Mode 4 (16QAM R3/4): 0/5   Mode 5 (16QAM R5/6): 0/5   Mode F (4-FSK): 5/5
```

The cost is throughput: a Mode F frame is roughly 3× longer on air than an OFDM
frame, which is why it sits at the bottom of the rate ladder and is only used when
nothing else works. (Interestingly, the SC-FDMA OFDM modes proved highly
clip-tolerant on their own — surviving even 3% clipping without noise — validating
the low-PAPR waveform choice.)

---

## Link layer

The link layer ([dart_link.dart](../src/lib/hamlib/dart_link.dart)) sits on top of
the modem and offers two delivery modes, matching how ham operators actually use
the air:

### Connectionless datagrams (multicast / broadcast / chat)

`sendDatagram()` transmits a fire-and-forget frame with the broadcast flag set. No
ACK is expected, and the rate is whatever the caller picks (fixed or manual). This
is the right model for APRS-style position/status beacons, group chat, and CQ
calls where the packet goes out to everyone.

### Connected ARQ (reliable delivery)

`sendReliable()` sends a data frame and tracks it in a **sliding send window** (up
to `windowSize` frames in flight, default 4). The receiver's `receive()`
automatically:

- delivers payloads **strictly in order**, buffering out-of-order frames until
  the gap fills, and returns an **ACK** for each valid frame,
- returns a **NACK** when a frame's CRC fails (requesting retransmission),
- on receiving a NACK, **selectively retransmits only the lost frame** rather
  than everything after it.

This selective-repeat scheme keeps the pipe full on links with round-trip
latency — several frames are outstanding at once, and a single loss only costs
one retransmission. ACK/NACK control frames are always sent at **mode 0** (the
most robust) so they survive even when the data rate was too aggressive.

### Rate adaptation

When adaptation is enabled, the sender walks a **rate ladder** — bumping **up** one
rung after a run of clean ACKs (default 3) and dropping **down** two rungs on any
NACK or timeout — the same MCS-selection idea used by Wi-Fi, LTE, and VARA. Mode F
sits at the bottom of the ladder (below mode 0), so a link that keeps failing even
at the most robust OFDM mode **automatically drops to the constant-envelope
fallback**. The ladder is `F → 0 → 1 → 2 → 3 → 4 → 5`. Adaptation can be disabled
for fully manual rate control, and Mode F can be excluded from the ladder
(`allowModeF: false`).

### Per-packet metadata

Every transmitted and received frame produces a `DartPacketInfo`
([dart_packet_info.dart](../src/lib/hamlib/dart_packet_info.dart)) capturing
direction, timestamp, mode/constellation/code-rate, frame type, source/destination
callsigns, sequence number, payload length, on-air duration, retransmit count,
CRC status, and — for received frames — a `DartSignalQuality` record (EVM, SNR,
preamble correlation, channel gain). This is the object the Flutter packet-capture
tab will render per packet. Example capture rows:

```
TX DATAGRAM N0CALL→*     seq=0 mode=1 (QPSK R1/2) 39B 622ms
RX DATAGRAM N0CALL→*     seq=0 mode=1 (QPSK R1/2) 39B 624ms CRC=OK [EVM 3.5%, SNR 29.2 dB, corr 0.89, gain -8.0 dB]
TX DATA     ALICE→BOB    seq=0 mode=2 (QPSK R2/3) 42B 474ms
RX ACK      BOB→ALICE    seq=0 mode=0 (BPSK R1/2)  0B 624ms CRC=OK [EVM 0.5%, SNR 46.5 dB, corr 0.89, gain -8.0 dB]
```

---

## Radio integration

DART is selectable from **Audio → Software Modem → DART**, alongside the existing
AFSK 1200 and PSK 2400 options, in [software_modem.dart](../src/lib/radio/software_modem.dart).
It plugs into the exact same broker flow as the other software modems
(`AudioDataAvailable` → decode → `DataFrame` on receive; `SoftModemTransmitPacket`
→ `TransmitVoicePCM` on transmit) at the shared **32 kHz / 16-bit / mono** format,
so it rides the radio's SBC Bluetooth audio link the same way.

Because DART is **frame-based** (whole-frame `encode()` / `decode()`) rather than
the sample-by-sample HDLC/FX.25/GenTone chain the AFSK/PSK modems use, its modem
instance:

- **Receive** — buffers incoming PCM into a rolling window and runs `decode()`
  periodically (throttled), consuming each frame it finds via the decoder's
  `endSample` and dispatching the payload (a raw AX.25 frame) as a `DataFrame`.
  A `stream` test validates this chunked-reception + consumption logic.
- **Transmit** — encodes each queued frame with its own preamble/LDPC/CRC and
  concatenates them with PTT lead-in/tail silence; it bypasses HDLC/FX.25 entirely
  (DART carries its own forward error correction and CRC).

DART frames are tagged with a new `softwareDart` encoding so the packet-capture
tab labels them "Software DART". **APRS is deliberately left on AFSK 1200** — its
dedicated modem instance and channel routing are untouched.

---

## Key engineering result: surviving the SBC codec

The single hardest problem was the Bluetooth **SBC codec**. A single
preamble-based channel estimate left roughly a **29° residual phase error** after
the SBC round-trip. BPSK tolerated it, but QPSK and every higher-order mode
failed on CRC.

**Fix — decision-directed channel refinement.** Because the header always decodes
correctly (it is transmitted at the most robust mode), the receiver re-encodes
the decoded header, treats its 72 OFDM symbols as an extended pilot, and averages
`Y·conj(X)` across them to produce a far more accurate per-subcarrier channel
estimate (especially its phase). Applying that refined estimate to the payload
made **every higher-order constellation survive the SBC codec.**

The probe tool also confirmed the SBC codec introduces a ~73-sample group delay
but preserves preamble correlation at ~0.89 — so detection stays reliable and the
guard interval absorbs the delay.

---

## Test results (automated, verified)

Run from `src/`:

```
dart run test/dart_modem_test.dart loopback                 # clean channel
dart run test/dart_modem_test.dart loopback --noise 25      # + AWGN
dart run test/dart_modem_test.dart loopback --sbc           # + SBC codec
dart run test/dart_modem_test.dart loopback --sbc --noise 30
```

Each run tests 6 modes × 5 payload sizes (2–100 bytes) = 30 cases.

| Condition | Result |
| --- | --- |
| Clean channel | **30 / 30 pass** |
| + 25 dB SNR AWGN | **30 / 30 pass** |
| Through real SBC codec | **30 / 30 pass** |
| SBC + 30 dB SNR | **30 / 30 pass** |
| SBC + 15 dB SNR | 18 / 30 — modes 0–2 pass, modes 3–5 drop out |

The last row is the **desired** behavior: at a low SNR through the codec, the
robust modes still deliver while the high-rate modes fail — validating the
adaptive mode table and the rationale for rate adaptation.

### Component unit tests

| Test | Result |
| --- | --- |
| FFT/IFFT round-trip (sizes 16–128) | 4 / 4 pass (max error ~1e-15) |
| Constellation map/demap + power (all 4 types) | 8 / 8 pass |
| LDPC encode/decode (rates 1/2, 2/3, 3/4, 5/6) | 12 / 12 pass |
| Link layer (datagram, ARQ ACK, sliding window, rate adaptation, Mode F) | 40 / 40 pass |
| Streaming RX (chunked PCM → rolling buffer → consume) | 3 / 3 pass |

### PAPR: plain OFDM vs DFT-spread (SC-FDMA)

`dart run test/dart_modem_test.dart papr` (2000 symbols per constellation,
99th-percentile per-symbol PAPR):

| Constellation | Plain OFDM | SC-FDMA | Reduction |
| --- | --- | --- | --- |
| BPSK | 10.5 dB | 8.5 dB | 2.0 dB |
| QPSK | 10.7 dB | 8.8 dB | 1.9 dB |
| 8PSK | 10.7 dB | 8.8 dB | 2.0 dB |
| 16QAM | 10.6 dB | 9.3 dB | 1.3 dB |

DFT-spread lowers PAPR by ~1.3–2.0 dB, giving extra headroom against the FM
limiter / AGC. The reduction is modest because there are only 9 active
subcarriers; SC-FDMA's PAPR advantage grows with the number of tones.

---

## Known limitations / not yet implemented

- **High modes are SNR-limited on real links** — over the air (see below), 8PSK and
  16QAM need more signal-to-noise than a marginal FM path delivers; they are no
  longer *phase*-limited (pilots handle that) but *link-budget*-limited.
- **Fixed TX mode in the radio path** — the live integration transmits at a fixed
  DART mode (mode 2 by default). The full adaptive rate ladder and ARQ from the
  link layer are implemented but not yet driven from the software-modem handler.

---

## Over-the-air validation (2026-07-10)

Tested with **two UV-Pro handhelds, Bluetooth (SBC) audio on both transmit and
receive, ~50 ft apart**, on 2 m / 70 cm FM. Multiple captures per mode were
decoded with the test tool; results were highly repeatable.

| Level | Mode | EVM | SNR | Phase drift | CRC |
|:---:|:---|:---:|:---:|:---:|:---:|
| 0 | BPSK R1/2 | ~45% | ~7 dB | 1.6°/sym | ✅ OK |
| 1 | QPSK R1/2 | ~42% | ~7.5 dB | 1.3°/sym | ✅ OK |
| 2 | QPSK R2/3 | ~44% | ~7 dB | 1.4°/sym | ✅ OK |
| 3 | 8PSK R2/3 | ~34% | ~9.4 dB | 0.6°/sym | ❌ fail |
| 4 | 16QAM R3/4 | ~28% | ~11 dB | 0.9°/sym | ❌ fail |

**Key findings:**

- **Reliable ceiling on a marginal link: Level 2 (QPSK R2/3, ~3 kbps).** This is
  one rung above the initial ceiling and was unlocked by the receive-side
  improvements below.
- **Carrier phase noise is the *decision-limited* type (0.5–1.6°/symbol) and is
  fully handled** by decision-directed + pilot-aided phase tracking. Phase is no
  longer the limiter.
- **8PSK/16QAM fail on raw SNR, not phase** — at ~9–11 dB SNR / ~28–34% EVM the
  dense constellations cannot resolve (they need roughly 13 dB and 16 dB).
  Unlocking them is a link-budget problem (antenna/range/power), not DSP.

**Receive/transmit improvements that raised the ceiling (this round):**

- **Band-limited preamble chirp retuned to 400–1900 Hz** — over-air preamble
  correlation rose from ~0.80 to ~0.88 (the radio audio path rolls off above the
  data band; a narrower sync chirp survives it). The data carriers and channel-
  estimation symbol still span the full band.
- **Decision-directed common-phase-error tracking** + **pilot-aided phase
  tracking** (known pilot symbols interspersed in the payload every 8 data
  symbols) for decision-independent phase anchoring. The decoder also reports a
  per-symbol phase-drift diagnostic used to confirm the impairment regime.
- **MMSE equalization** (replacing zero-forcing) to limit noise enhancement on
  weak subcarriers.
- **SBC SNR bit-allocation for data frames** (vs. the psychoacoustic "loudness"
  default) — halves the codec's quantization contribution on a clean link.

**SBC bitpool (measured on real UV-Pro hardware):** the transmit (app → radio)
SBC stream is raised to **bitpool 40** (from the default 18) — the radio accepts
40 but **rejects 124** (the codec maximum), and 40 is also where the quantization
quality saturates. The radio's **incoming (radio → app) stream is fixed at
bitpool 18** by its firmware and cannot be changed from the app, so the return
path remains the lower-quality direction. Note this only affects the small clean-
link quantization floor; it does not move the SNR-limited ceiling above.

---

## Suggested next steps

1. Capture 8PSK/16QAM at stronger signal (closer range / better antenna) to map
   the true top of the ladder as a function of SNR now that phase is handled.
2. Drive the adaptive rate ladder and selective-repeat ARQ from the live
   software-modem handler (currently a fixed mode is used on air).
