# HTCommander Technology Blog

Field notes and deep dives on the technology behind **HTCommander** — the
cross-platform app for controlling Benshi handheld radios (BTech UV-Pro,
RadioOddity GA-5WB, Vero VR-N76 / VR-N7500, and friends).

These posts document the engineering as it happens: real-world findings,
protocol reverse-engineering, DSP experiments, and the honest ledger of what
works, what doesn't, and what we still don't know. New topics are added as we go.

---

## DART Modem

Building and tuning **DART** (Data Adaptive Rate Transport), an adaptive OFDM
modem for sending data over ordinary VHF/UHF **FM voice** radios (2 m / 70 cm)
across a Bluetooth (SBC) audio link. Best read in order — each post builds on the
last, walking from the first over-the-air observation down to the root-cause
diagnosis and fix.

1. **[Pushing Data Through FM Voice Radios: Real-World Findings](dart-over-the-air-findings.md)**
   The first over-the-air test on two UV-Pro radios. Which modes work, which fail,
   and the first evidence that the quality ceiling lives in the *audio path* — not
   the RF, band, or transmit level.

2. **[Does SBC Bitpool Matter?](dart-sbc-bitpool.md)**
   The Bluetooth SBC codec adds a small noise floor under the signal. We measure
   how much, and show that raising the bitpool saturates quickly and never moves
   the ceiling.

3. **[Inside SBC: Loudness vs. SNR Bit Allocation](dart-sbc-allocation.md)**
   How SBC spends its bits across subbands, and why its default *loudness*
   allocation is the wrong choice for data — a free quality gain from switching
   data frames to *SNR* allocation.

4. **[Chasing a Ghost: Proving (and Fixing) the Real Limiter](dart-phase-noise-and-pilots.md)**
   Building a phase-noise channel model and a phase-drift meter to turn "it's
   probably phase noise" into a measurement — then fixing it with pilot-aided
   phase tracking, recovering a rung of throughput, and showing the remaining
   ceiling is raw SNR (a link-budget problem), not DSP.

5. **[The Bits You Already Know: Code Shortening for Short Frames](dart-code-shortening.md)**
   A lopsided constellation reveals that short frames are mostly known
   zero-padding. Telling the decoder those bits are known (code shortening) buys
   5+ dB of margin on short frames — for free, and scaling exactly with how short
   the frame is.

6. **[Is 125 Microseconds Enough? A Look at Inter-Symbol Interference](dart-inter-symbol-interference.md)**
   Building a multipath echo channel to test whether DART's deliberately-short
   cyclic prefix is big enough. It finds the classic ISI knee at the CP boundary,
   confirms the SBC/audio path adds no dispersion the CP misses, and shows the
   short-CP bet was safe.

**Related:** [DART Implementation Report](../DART-Implementation-Report.md) ·
[Next-Gen Modem design spec](../NextGenModem.md) ·
[Proposal / rationale](../findings/next-gen-modem-proposal.md)

---

## Firmware Updates

FIguring out the radio's firmware-update path — from
the cloud check that finds an update to the two-phase Bluetooth flash that writes
it into the radio.

1. **[How a Benshi Radio Updates Its Firmware, Step by Step](benshi-firmware-update.md)**
   A walk through the firmware-update path — from the cloud update check and
   patch-based download to the device-paced, two-phase GAIA transfer that streams
   a new image into the radio over Bluetooth.

2. **[Where Does the Firmware Come From? Inside the Benshi Update Server](benshi-firmware-server.md)**
   A field report on the online side — the gRPC check, the patch-based download,
   and the honest ledger of what we've proven and the DID puzzle we still can't
   crack.

---

*More topics coming as the project grows.*
