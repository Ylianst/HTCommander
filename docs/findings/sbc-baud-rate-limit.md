# Does the Bluetooth SBC audio link limit the software modem's baud rate?

**Date:** 2026-07-07
**Tool:** `src/test/soft_modem_tool.dart` (subcommand `sbctest`)
**Question:** AFSK1200 and PSK2400 work over the software modem, but PSK4800 and
G3RUH9600 do not. Is the radio's Bluetooth **SBC** audio codec losing enough
information to make the higher speeds impossible?

**Short answer:** **No. SBC is not the cause.**

- SBC compression is essentially *lossless* for the modem's tones: every mode
  decodes 100% of clean packets through one **and** two SBC round-trips.
- **9600 fails because of the 32 kHz sample rate** the SBC/Bluetooth link runs
  at, not because of compression loss. **Enabling the demodulator's built-in
  polyphase upsampler restores 9600 to 100%** (see Findings 4 and 5).
- **4800 works on a clean signal**; SBC only narrows its noise margin (8PSK is
  inherently noise-sensitive), so weak real-world signals drop out sooner.

---

## Method

A new `sbctest` subcommand runs the exact pipeline described in the
investigation and measures how many packets decode **bit-exact** over 25 trials
at each noise level:

```
encode AX.25 frame -> PCM
  Path A (no SBC):  PCM ------------------> [+noise] -> demodulate
  Path B (1x SBC):  PCM -> SBC -----------> [+noise] -> demodulate
  Path C (2x SBC):  PCM -> SBC -> [+noise] -> SBC ----> demodulate
```

Path C models the real over-the-air chain: the transmitting radio's
`app -> radio` Bluetooth link SBC-encodes the tones, RF/FM adds noise on air,
then the receiving radio's `radio -> app` Bluetooth link SBC-encodes again
before the app demodulates.

- **SBC config:** 32 kHz mono, 16 blocks, 8 subbands, loudness allocation,
  bitpool 18 (44-byte frames, 88 kbps) — matches
  `lib/radio/radio_audio.dart`.
- **Noise:** additive white Gaussian noise (AWGN), standard deviation swept
  0 → 6000 in 16-bit sample units.
- **Packet:** a 66-byte AX.25 frame
  (`WB2OSZ-15>APDW17,WIDE1-1:The quick brown fox jumps over the lazy dog`).

Reproduce with:

```
dart run test/soft_modem_tool.dart sbctest -B 4800 -r 32000 --trials 25
dart run test/soft_modem_tool.dart sbctest -B 9600 -r 44100 --trials 25
```

To test upsampling the 32 kHz link audio to 48 kHz before demodulation:

```
dart run test/soft_modem_tool.dart sbctest -B 9600 -r 32000 --upsample 48000 --trials 25
```

---

## Results at 32 kHz (the production sample rate)

Each cell = % of packets decoded bit-exact over 25 trials.

| noise stddev | 1200 A/B/C | 2400 A/B/C | 4800 A/B/C | 9600 A/B/C |
|-------------:|:----------:|:----------:|:----------:|:----------:|
| 0            | 100/100/100 | 100/100/100 | 100/100/100 | **0/0/0** |
| 1000         | 100/100/100 | 100/100/100 | 100/100/100 | 0/0/0 |
| 1500         | 100/100/100 | 100/100/100 | 100/100/**88** | 0/0/0 |
| 2000         | 100/100/100 | 100/100/100 | 100/**96**/88 | 0/0/0 |
| 2500         | 100/100/100 | 100/100/100 | 100/92/**72** | 0/0/0 |
| 3000         | 100/100/100 | 100/100/100 | 100/**80**/32 | 0/0/0 |
| 4000         | 100/100/100 | 100/100/100 | **44**/12/0 | 0/0/0 |
| 5000         | 100/100/100 | 100/100/100 | 0/0/0 | 0/0/0 |
| 6000         | 100/100/100 | 100/100/**92** | 0/0/0 | 0/0/0 |

**Noise margin (stddev at which decoding first drops below 100%):**

| baud | A: no SBC | B: 1x SBC | C: 2x SBC |
|------|:---------:|:---------:|:---------:|
| 1200 AFSK   | none in sweep | none in sweep | none in sweep |
| 2400 QPSK   | none in sweep | none in sweep | ~6000 |
| **4800 8PSK** | ~4000 | ~2000 | ~1500 |
| **9600 G3RUH** | **fails at 0** | fails at 0 | fails at 0 |

---

## Finding 1 — SBC compression is effectively lossless for modem tones

On a clean signal, **every** mode decodes 100% of packets through both one and
two SBC round-trips. SBC never destroys a strong/clean packet; it only slightly
reduces the noise margin. This directly contradicts the theory that SBC "loses a
bunch of information" and makes higher speeds impossible.

## Finding 2 — 9600 is limited by the sample rate, not SBC

The production soft modem runs the demodulator at **32000 Hz**
(`lib/radio/software_modem.dart` — `samplesPerSec = 32000` and
`Demod9600.init(32000, 1, 9600, ...)`).

At 32 kHz, 9600 baud is only **~3.3 samples per bit**, which is too few for the
G3RUH demodulator: it decodes **0% even on a perfectly clean signal with zero
SBC and zero noise**. The identical signal decodes fine at higher rates:

| sample rate | 9600 clean decode (no SBC) |
|------------:|:--------------------------:|
| 32000 Hz | **0% (fails)** |
| 44100 Hz | 100% |
| 48000 Hz | 100% |

At 44.1 kHz, 9600 also passes cleanly through **two** SBC round-trips (100% up to
noise ~5000), confirming SBC is not the blocker:

| noise stddev | 9600 @ 44.1 kHz A/B/C |
|-------------:|:---------------------:|
| 0–4000 | 100/100/100 |
| 5000 | 100/100/**92** |
| 6000 | 100/**92**/88 |

So 9600 is broken by the **32 kHz rate the SBC/Bluetooth link forces**, not by
compression loss.

## Finding 3 — 4800 works on a clean signal but has a thin noise margin

PSK4800 decodes **100% clean** through two SBC round-trips at 32 kHz. But 8PSK
packs 3 bits per symbol, so its constellation is noise-sensitive. Here SBC does
have a measurable effect: it roughly **halves** the tolerable noise (no-SBC
fails ~4000, 2x SBC ~1500). The low 32 kHz rate compounds this — at 44.1 kHz the
2x-SBC margin widens back to ~3000.

So on a weak or noisy real channel, 4800 drops out sooner than 1200/2400, and
SBC is a contributing factor — but not a hard blocker on a decent signal.

## Finding 4 — Upsampling the 32 kHz link audio to 48 kHz fixes 9600

The radio delivers audio to the app at 32 kHz over the SBC/Bluetooth link. If
the app **upsamples that 32 kHz stream to 48 kHz (linear interpolation) before
demodulating**, the 9600 samples-per-symbol starvation disappears. Same signal
chain (encode at 32 kHz → SBC → noise → SBC), only the demodulator now runs at
48 kHz:

| noise stddev | 9600 @ 32 kHz demod A/B/C | 9600 @ 32 kHz → **upsampled 48 kHz** A/B/C |
|-------------:|:-------------------------:|:------------------------------------------:|
| 0            | **0/0/0** | **100/100/100** |
| 1000         | 0/0/0 | 100/100/100 |
| 2000         | 0/0/0 | 100/100/100 |
| 3000         | 0/0/0 | 100/100/100 |
| 4000         | 0/0/0 | 96/100/**80** |
| 5000         | 0/0/0 | 84/88/36 |
| 6000         | 0/0/0 | 56/44/4 |

**9600 goes from completely dead (0%) to fully working (100% clean, 100% up to
noise ~3000)** just by upsampling before the demodulator — with the audio still
having passed through one or two SBC round-trips. Noise margin after upsampling:
A ~4000, B ~5000, C ~4000, i.e. SBC has little effect once the sample rate is
adequate.

For **4800**, upsampling is roughly neutral (it already worked at 32 kHz):
margins stay A ~4000, B ~2500, C ~1500.

This is the clinching evidence: 9600's failure was purely the 32 kHz sample rate
(too few samples per symbol for the G3RUH demodulator), not SBC compression.
Upsampling the received audio recovers essentially the same performance as
sampling natively at 48 kHz.

### Does upsampling help the other modes too?

Only 9600 needs it. At 32 kHz the samples-per-symbol are already ample for the
lower modes (1200 ≈ 27, 2400 ≈ 27, 4800 ≈ 20 samples/symbol) but only ~3.3 for
9600, so upsampling is transformative for 9600 and essentially neutral for the
rest:

| baud | @ 32 kHz (no upsample) | @ 32 kHz → 48 kHz upsampled |
|------|------------------------|-----------------------------|
| 1200 AFSK  | 100% everywhere | 100% everywhere (no change) |
| 2400 QPSK  | 100%, one drop (2× SBC @6000 → 92%) | 100% everywhere (marginally better) |
| 4800 8PSK  | works clean; A ~4000 / B ~2000 / C ~1500 | ~neutral; A ~4000 / B ~2500 / C ~1500 |
| 9600 G3RUH | **0% — dead** | **100% clean, 100% to noise ~3000** |

Upsampling all modes uniformly is therefore safe (no downside — it slightly
closed 2400's single 92% cell and left 1200/4800 unchanged); only 9600 actually
requires it.

## Finding 5 — The decoder's built-in polyphase upsampler is the better fix

The `Demod9600` code (a Direwolf port) already has an internal **`upsample`
factor (1–4)**: it interpolates using the low-pass FIR filter the demodulator
needs anyway (polyphase branches `lpPolyphase1..4`), and sets the PLL step for
the upsampled rate. Production was calling it with `upsample = 1`.

Using this internal upsampler instead of resampling the audio beforehand is:

- **More efficient** — it reuses the existing FIR, allocates no separate
  resampling buffer, and needs no extra streaming-resampler state.
- **Higher quality** — proper polyphase anti-imaging, versus crude linear
  interpolation.
- **The Direwolf-proven path** — Direwolf's `demod.c` picks the factor from
  `ratio = sample_rate / baud`: `< 4 → 4`, `< 10 → 3`, `< 15 → 2`, else `1`.
  For the radio's 32000 / 9600 = 3.33, that is **factor 4**.

Measured at 32 kHz with internal `upsample = 4` (no external resampling):

| noise stddev | external linear 48 kHz A/B/C | internal polyphase ×4 A/B/C |
|-------------:|:---------------------------:|:---------------------------:|
| 0–3000       | 100/100/100 | 100/100/100 |
| 4000         | 96/100/**80** | **100/100/100** |
| 5000         | 84/88/36 | 100/92/88 |
| 6000         | 56/44/4 | 68/84/48 |
| **margin**   | A ~4000 / B ~5000 / C ~4000 | **A ~6000 / B ~5000 / C ~5000** |

The internal upsampler both fixes 9600 (0% → 100%) **and** gives a wider noise
margin than external linear upsampling.

## Finding 6 — PSK/AFSK need no upsampling, and their profile is already optimal

The internal upsampler is unique to the 9600 baseband demodulator, and 9600 is
the only mode starved for samples per symbol at 32 kHz:

| mode | symbol rate | samples/symbol @ 32 kHz |
|------|------------:|------------------------:|
| AFSK1200 | 1200 | ~27 |
| PSK2400 (QPSK) | 1200 | ~27 |
| PSK4800 (8PSK) | 1600 | 20 |
| G3RUH9600 | 9600 | **3.3** ← the only starved one |

PSK4800 already has 20 samples/symbol, so upsampling gains nothing (the external
48 kHz test was neutral for 4800). Its limiter is the 8PSK constellation (3 bits
per symbol, packed tightly), which is a fundamental SNR requirement, not a
sample-density problem — and the PSK demodulator has no upsample knob.

The PSK demodulator does expose **profiles** (prefilter on/off + PLL inertia).
The app passes `'B'`, which falls through to the `default`: LO-mix, no prefilter
(`V` for 8PSK, `R` for QPSK). Sweeping all four 8PSK profiles at 32 kHz:

| 8PSK profile | noise margin A / B / C |
|--------------|------------------------|
| **V** (current default: LO, no prefilter) | **~4000 / ~2000 / ~1500** ← best |
| W (LO + prefilter) | ~4000 / ~2000 / ~1500 (tied, mixed) |
| U (self-correlation + prefilter) | ~2500 / ~2000 / ~750 (worse) |
| T (self-correlation) | ~2500 / ~2000 / ~1500 (worse) |

The app already uses the best-performing profile; the prefilter and
self-correlation variants do not help (some are worse). This matches Direwolf's
own default choice. So there is no PSK/AFSK tuning win for the 32 kHz case — the
real lever for PSK4800 robustness is FEC (FX.25), which the app already supports.

---

## How much does SBC limit us?

| baud | SBC impact |
|------|------------|
| 1200 AFSK  | Effectively none. |
| 2400 QPSK  | Negligible (only 2x SBC at very high noise). |
| 4800 8PSK  | Clean signals always decode; SBC ≈ halves the noise margin, contributing to weak-signal dropouts. |
| 9600 G3RUH | Not the limiter at all — the **32 kHz sample rate** is. |

## Recommendations

1. **9600:** run the demodulator's built-in polyphase upsampler (Finding 5)
   rather than resampling the audio first. **Implemented** in
   `lib/radio/software_modem.dart`: `_initializeG3ruh9600` now calls
   `Demod9600.init(32000, _g3ruhUpsampleFor(32000, 9600), 9600, ...)` (factor 4)
   and `_processPcmData` feeds the 32 kHz samples straight through with that
   factor. This takes 9600 from 0% to 100% clean decode with the widest noise
   margin, at lower cost than an external resampler. Changing SBC would not help.
2. **4800:** already functional on clean/strong signals, and already using the
   best-performing demodulator profile (Finding 6) — no upsampling or profile
   change helps. The limit is the 8PSK SNR requirement, so use FX.25 FEC for
   weak links.
3. **1200 / 2400:** no action needed — ample samples per symbol and essentially
   immune to SBC.
4. **SBC itself needs no change** for packet-modem purposes; it is not the
   bottleneck.
