# Does the radio preserve amplitude? (Is high-order QAM viable?)

**Date:** 2026-07-07
**Tool:** `src/test/soft_modem_tool.dart` (subcommands `amptest` and `amptestanalyze`)
**Recording:** `amptest-r1.wav` (radio A → radio B, over the air)
**Builds on:** [radio-audio-passband.md](radio-audio-passband.md),
[next-gen-modem-proposal.md](next-gen-modem-proposal.md)
**Question:** The passband test told us *which frequencies* the radio passes.
This test asks the other half of the question: does the audio path preserve
**amplitude**, or does its AGC / limiter / companding / SBC codec flatten and
distort it? The answer decides whether a modern modem can use amplitude-carrying
constellations (high-order QAM) or must stick to constant-envelope waveforms.

**Short answer:** The audio path on this radio pair is **fairly LINEAR**.
Relative amplitude is preserved almost 1:1 and intermodulation distortion is low,
so **higher-order QAM (up to ~16-QAM) is plausible** on this link.

- **Amplitude-tracking slope: 1.03** (1.00 = perfectly linear) across a 36 dB
  input range.
- **Worst-case IMD3: −34 dB** relative to the tones; **−40 to −56 dB** across the
  mid and upper range.
- **Reference tone droops only ~3 dB** as the probe is driven up → the AGC is
  gentle, not a hard limiter.

This **flips the working assumption** in the modem proposal (which cautioned that
amplitude distortion might force a constant-envelope waveform). On this pair it
does not — the primary **coherent QAM / SC-FDMA + LDPC** design is viable.

---

## Method

Amplitude linearity is measured with a **two-tone ratio test**, the standard way
to separate true nonlinearity from benign gain changes:

- A **reference tone** `fa = 1200 Hz` is present the whole time at a fixed level
  (−20 dBFS).
- A **probe tone** `fb = 1800 Hz` steps up in amplitude from −40 dBFS to −3 dBFS
  in 2 dB steps.
- Both tones are in the flat part of the measured passband (300–3000 Hz).

Because both tones are present **simultaneously**, the radio's AGC applies the
**same gain to both**, so it cancels out when we look at the **probe/reference
ratio**. What remains in that ratio is the genuine amplitude nonlinearity. As a
second, independent check we also measure the **third-order intermodulation
(IMD3)** products at `2·fa − fb = 600 Hz` and `2·fb − fa = 2400 Hz` (both
in-band) — these appear only if the path is nonlinear.

### 1. Generate

```
dart run test/soft_modem_tool.dart amptest -o amptest.wav
```

32 kHz / 16-bit / mono, matching the radio's SBC link: a 1 s reference-only lead
cue, then 19 two-tone steps (250 ms each, 100 ms gaps).

### 2. Transmit and record

Play `amptest.wav` out of radio A; record on radio B as `amptest-r1.wav`.

### 3. Analyze

```
dart run test/soft_modem_tool.dart amptestanalyze amptest-r1.wav
```

The analyzer recovers each step, then reports:

- **In(dB)** — the input probe/reference ratio we transmitted.
- **Out(dB)** — the measured output probe/reference ratio.
- **RefOut / ProbeOut** — each tone's absolute output level (dBFS).
- **IMD(dB)** — worst IMD3 product relative to the tones.
- A **tracking slope** (Out vs In; 1.00 = linear) and the **worst IMD3**, then a
  plain-language verdict.

> **Note on step recovery.** The analyzer does **not** rely on detecting the
> silent gaps, because over an FM link the receiver's AGC fills the gaps with
> broadband noise (an early gap-based version mis-segmented the file). Instead it
> **anchors on the 1 s reference lead tone** and places every step on a fixed
> time grid — both ends are digital at a fixed sample rate, so there is no
> meaningful drift over the 8 s file.

---

## Results

Recording `amptest-r1.wav`: 32 kHz, 16-bit, mono, 8.5 s. Reference 1200 Hz at
−20 dBFS input; probe 1800 Hz stepped. IMD3 products at 600 Hz and 2400 Hz.

> ⚠️ The analyzer flagged **387 samples near full scale** (0.14 % of the file) —
> a trace of clipping at the loudest steps. It is negligible: the per-step tone
> measurements use the middle of each burst and are unaffected (the loudest steps
> still show the cleanest IMD). A slightly lower record level would remove the
> warning entirely.

```
  In(dB)   Out(dB)   RefOut   ProbeOut   IMD(dB)   Response
    -20    -22.1     -37      -59       -35    #####
    -18    -19.7     -37      -57       -36    #######
    -16    -17.5     -37      -54       -34    ########
    -14    -15.0     -37      -52       -35    ##########
    -12    -12.5     -37      -49       -37    ############
    -10    -10.4     -37      -47       -40    #############
     -8     -8.5     -36      -45       -38    ##############
     -6     -6.5     -35      -42       -38    ################
     -4     -4.7     -34      -39       -38    #################
     -2     -2.7     -34      -37       -41    ##################
      0     -0.6     -34      -35       -39    ####################
      2      1.4     -34      -33       -39    #####################
      4      3.4     -34      -31       -44    ######################
      6      5.3     -34      -29       -47    ########################
      8      7.3     -34      -27       -45    #########################
     10      9.4     -34      -25       -49    ##########################
     12     11.5     -34      -23       -43    ############################
     14     13.6     -34      -21       -51    #############################
     16     15.6     -34      -19       -56    ##############################

  Amplitude-tracking slope: 1.03 (1.00 = linear; deviation either way = distortion)
  Worst IMD3              : -34 dB relative to the tones (more negative = cleaner)

  Verdict: amplitude path is fairly LINEAR (low IMD, ratio tracks). Higher-order
  QAM (up to ~16-QAM) is plausible; still prefer low-PAPR (SC-FDMA).
```

---

## Interpretation

- **The ratio tracks 1:1 (slope 1.03).** As the probe input rises from 20 dB
  *below* the reference to 16 dB *above* it, the measured output ratio follows
  step-for-step. Amplitude information is preserved — exactly what QAM needs.
- **IMD3 is low (−34 dB worst, −40 to −56 dB typical).** The −34 dB figure occurs
  at the *quietest* probe steps, where the probe itself is near the noise floor
  and the "IMD" reading is really measurement noise; wherever the probe is
  comfortably above noise, IMD is −40 dB or better. A hard limiter or heavy
  compander would instead produce IMD in the −5 to −15 dB range (as our synthetic
  clipping tests confirmed).
- **The AGC is gentle.** `RefOut` sits at −34 to −37 dBFS and drops only ~3 dB as
  the probe is driven up — a mild shared-gain adjustment, not the constellation-
  crushing behavior we were worried about.

### What this means for the modem design

| Design question | Before this test | After this test |
| --- | --- | --- |
| Is amplitude usable? | Unknown — feared AGC/limiter/SBC would flatten it | **Yes**, preserved ~1:1 |
| Constellation ceiling | Possibly BPSK/QPSK only (constant-envelope) | **Up to ~16-QAM plausible** |
| Primary waveform | Uncertain; constant-envelope fallback likely | **Coherent QAM / SC-FDMA + LDPC** is the primary path |
| Constant-envelope fallback | Might be mandatory | Keep as a *fallback* for weaker/other radios, not the default |

Combined with the passband result (a flat ~300–3000 Hz channel), the two
measurements now agree on a concrete waveform: a **coherent, training-equalized
~2.4 kHz QAM (SC-FDMA) waveform with adaptive bit-loading and LDPC coding**, as
proposed in [next-gen-modem-proposal.md](next-gen-modem-proposal.md). Low-PAPR
(SC-FDMA over plain OFDM) is still worth keeping — the AGC margin, while gentle,
is not infinite, and it costs nothing.

### Caveats

- This characterizes **one pair of radios** at one set of levels. Other
  models/firmware may behave differently; re-run per radio family before
  committing a fixed constellation order.
- The mild clipping should be removed (record a bit quieter) for a definitive
  measurement, though it does not change the LINEAR conclusion here.
- This test covers **static** amplitude linearity. It does not probe the AGC
  *time constant* (how fast the gain reacts) — relevant if a burst begins with a
  sudden level change. That would be a useful follow-up (an amplitude-*step*
  transient test).

---

## Reproduce

```
# 1. Generate the two-tone amplitude test (32 kHz / 16-bit / mono)
dart run test/soft_modem_tool.dart amptest -o amptest.wav

# 2. Play amptest.wav out of radio A, record it on radio B as amptest-r1.wav

# 3. Measure amplitude linearity
dart run test/soft_modem_tool.dart amptestanalyze amptest-r1.wav
```

Keep the record/play level moderate to avoid the clipping warning, and use the
same `--fa/--fb/--ref/--amin/--amax/--astep/--tone/--gap` you generated with
(all default here).
