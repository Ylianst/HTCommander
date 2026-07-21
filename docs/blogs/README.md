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

7. **[Whitening the Signal: Why a Modem Scrambles Its Own Data](dart-scrambling.md)**
   Why repetitive data (a frame full of zeros) wrecks spectrum, PAPR, and phase
   tracking — and why the fix is to make the data look like noise first. Compares
   the self-synchronizing G3RUH scrambler against an additive frame-synchronous
   one, and lays out the LDPC-friendly PN15 whitener DART will adopt.

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

## Sharing & Interop

Making HTCommander features portable between operators and radios.

1. **[A Channel You Can Text: The Channel-Share String](channel-share-string.md)**
   A compact, human-readable one-line format that encodes a whole radio channel —
   frequency, offset, tones, bandwidth, modulation, and flags — so you can drag a
   channel into a chat, send it (even over the air), and have the recipient drop
   it straight into their radio.

---

## Home Automation & Integrations

Connecting HTCommander to the wider ecosystem of tools operators already run.

1. **[Your Radio, on the Dashboard: Home Assistant Integration over MQTT](home-assistant-mqtt.md)**
   How HTCommander publishes each connected radio to Home Assistant as its own
   device — battery, GPS, volume, squelch, scan, channels, and incoming APRS —
   using an MQTT broker and Home Assistant's auto-discovery, plus a step-by-step
   setup guide. Desktop-only (Windows / Linux / macOS).

---

## Data & Storage

How HTCommander packs large datasets into small, fast, self-contained files.

1. **[1.6 Million Hams in Your Pocket: Compacting the FCC Callsign Database](fcc-callsign-compaction.md)**
   How the FCC's weekly amateur-license dump becomes a small binary `.cdb` you can
   binary-search offline — and the stack of encoding tricks (base-37 packed keys,
   an offset-free index, epoch-relative dates, state/class/status/city
   dictionaries, numeric ZIPs, and xz) that shrink every record to the bone.

---

## App Architecture

How HTCommander is built under the hood — the threading, plumbing, and design
decisions that keep the radio responsive.

1. **[Getting Audio Off the Main Thread: Moving the Radio Pipeline to Its Own Isolate](audio-isolate-threading.md)**
   Why the whole receive pipeline — SBC decode, software modem, and SSTV — runs on
   the UI thread today and stutters when the interface is busy, and the plan to
   move it into a dedicated background isolate with playback fed straight from the
   worker. Written before the work begins.

---

*More topics coming as the project grows.*
