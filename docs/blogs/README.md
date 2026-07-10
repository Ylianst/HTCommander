# DART Modem — Field Notes & Blog Series

A running series on building and tuning **DART** (Data Adaptive Rate Transport),
an adaptive OFDM modem for sending data over ordinary VHF/UHF **FM voice** radios
(2 m / 70 cm) across a Bluetooth (SBC) audio link, in HTCommander.

The posts are best read in order — each builds on the last, walking from the first
real-world observation down to the root-cause diagnosis and fix.

## Posts

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

## Related

- [DART Implementation Report](../DART-Implementation-Report.md) — architecture,
  test results, and over-the-air validation.
- [Next-Gen Modem design spec](../NextGenModem.md)
- [Proposal / rationale](../findings/next-gen-modem-proposal.md)
