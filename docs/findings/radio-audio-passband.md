# What audio bandwidth can the radio actually pass?

**Date:** 2026-07-07
**Tool:** `src/test/soft_modem_tool.dart` (subcommands `sweep` and `sweepanalyze`)
**Question:** What is the *true* usable audio passband of the radio's audio
link end to end? The software modem's higher speeds (PSK4800, G3RUH9600) need a
wider, flatter audio channel than the lower speeds — so knowing the real
passband tells us what the radio can and cannot carry.

**Short answer:** The end-to-end audio channel is a **~300–3000 Hz band-pass**.

- **−3 dB passband: 300–3100 Hz** (2800 Hz wide).
- **−6 dB passband: 300–3400 Hz** (3100 Hz wide).
- Everything **below 300 Hz is strongly attenuated** (100/200 Hz ≈ −23 dB): the
  link is AC-coupled / high-passed.
- Above **~3000 Hz the response rolls off** and by ~3500 Hz the tones sink into
  the noise floor (the readings above ~3700 Hz are erratic because the analyzer
  is picking up noise/intermodulation, not the transmitted tone).

This is a textbook **narrowband-FM voice** audio channel, and it matches the
earlier conclusion in [sbc-baud-rate-limit.md](sbc-baud-rate-limit.md): 4800/9600
need a wider, flatter audio path than this voice link provides.

---

## Method

The idea: build a known reference signal, play it out of one radio, record it on
a second radio, and compare. The whole audio chain (TX app → TX radio's
Bluetooth SBC link → RF/FM over the air → RX radio → RX radio's SBC link →
recording) is measured at once, so the result reflects what the modem really has
to work with.

### 1. Generate the test file

```
dart run test/soft_modem_tool.dart sweep -o sweep.wav
```

`sweep.wav` is **32 kHz / 16-bit / mono** (matching the radio's SBC link) and
contains:

- a **1 s, 1000 Hz** lead tone (an audible "recording is running" / level cue),
  then
- **60 stepped tones** from **100 Hz to 6000 Hz in 100 Hz steps**, each **250 ms**
  long with a **100 ms** silent gap, at 50 % amplitude (−6 dBFS, for headroom).

Only **one tone is present at a time**. That lets the analyzer recover each
tone's level with a sliding-window Goertzel **peak** detector, which is immune to
the radio's AGC/limiter (it only sets one overall gain) and needs **no time
alignment** — the recording can be any length, sample rate, or channel count.

### 2. Transmit and record

Play `sweep.wav` out of radio A; record the received audio on radio B as
`sweep-r1.wav`.

### 3. Analyze the recording

```
dart run test/soft_modem_tool.dart sweepanalyze --f0 100 --f1 6000 --fstep 100 sweep-r1.wav
```

The analyzer prints, for each tone, its level relative to the strongest tone
(**Rel dB**), its absolute level (**dBFS**), and an ASCII bar, then estimates the
−3 dB and −6 dB passband edges.

---

## Results

Recording `sweep-r1.wav`: 32 kHz, 16-bit, mono, 22.7 s. Peak tone 1100 Hz at
−14.5 dBFS (used as the 0 dB reference below).

> ⚠️ The analyzer flagged **450 samples near full scale** — the recording is
> mildly clipped. This can nudge the absolute levels but does not change the
> passband shape or the edge estimates. For a cleaner absolute measurement,
> lower the play/record level and re-record.

```
  Freq(Hz)   Rel(dB)   dBFS   Response
     100     -23.1    -38   #########################
     200     -23.1    -38   #########################
     300      -1.4    -16   #######################################
     400      -0.6    -15   ########################################
     500      -0.5    -15   ########################################
     600      -0.8    -15   #######################################
     700      -0.6    -15   ########################################
     800      -0.3    -15   ########################################
     900      -0.1    -15   ########################################
    1000      -0.0    -15   ########################################
    1100       0.0    -14   ########################################   <- peak
    1200      -0.0    -14   ########################################
    1300      -0.0    -14   ########################################
    1400      -0.1    -15   ########################################
    1500      -0.2    -15   ########################################
    1600      -0.3    -15   ########################################
    1700      -0.5    -15   ########################################
    1800      -0.7    -15   ########################################
    1900      -0.8    -15   #######################################
    2000      -1.1    -16   #######################################
    2100      -1.2    -16   #######################################
    2200      -1.3    -16   #######################################
    2300      -1.4    -16   #######################################
    2400      -1.5    -16   #######################################
    2500      -1.5    -16   #######################################
    2600      -1.6    -16   #######################################
    2700      -1.7    -16   #######################################
    2800      -1.8    -16   #######################################
    2900      -2.0    -17   #######################################
    3000      -2.4    -17   ######################################
    3100      -2.9    -17   ######################################   <- -3 dB edge
    3200      -3.6    -18   ######################################
    3300      -4.6    -19   #####################################
    3400      -5.8    -20   ####################################    <- -6 dB edge
    3500      -7.4    -22   ###################################
    3600      -9.1    -24   ##################################
    3700     -11.5    -26   ################################
    3800     -12.3    -27   ################################
    3900      -6.7    -21   ####################################    } readings above
    4000     -14.7    -29   ##############################          } ~3700 Hz are
    4100      -8.0    -22   ###################################     } erratic: tones
    4200      -9.3    -24   ##################################      } are below the
    4300     -10.7    -25   #################################       } noise floor, so
    4400     -15.3    -30   ##############################          } the peak detector
    4500     -11.5    -26   ################################        } is measuring
    4600     -10.2    -25   #################################       } noise / IMD,
    4700     -13.9    -28   ###############################         } not the tone
    4800     -13.2    -28   ###############################
    4900     -14.4    -29   ##############################
    5000     -13.7    -28   ###############################
    5100     -10.3    -25   #################################
    5200     -14.8    -29   ##############################
    5300     -13.7    -28   ###############################
    5400     -17.0    -31   #############################
    5500     -15.8    -30   #############################
    5600     -17.3    -32   ############################
    5700     -12.8    -27   ###############################
    5800     -12.8    -27   ###############################
    5900     -14.6    -29   ##############################
    6000     -15.3    -30   ##############################

  -3 dB passband: 300..3100 Hz (2800 Hz wide)
  -6 dB passband: 300..3400 Hz (3100 Hz wide)
```

---

## Interpretation

- **High-pass at ~300 Hz.** 100 Hz and 200 Hz are ~23 dB down while 300 Hz is
  already within 1.4 dB of the peak. The link removes sub-300 Hz content (typical
  of AC-coupled/FM voice audio). Any modem scheme needing DC / very low
  frequencies (e.g. G3RUH baseband) cannot survive this.
- **Flat mid-band, ~300–2900 Hz.** Response is within ~2 dB across this range —
  this is the reliable working region.
- **Roll-off above ~3000 Hz.** −3 dB by 3100 Hz, −6 dB by 3400 Hz, and buried in
  noise by ~3500–3700 Hz.
- **Erratic values above ~3700 Hz** are not real response bumps — those tones are
  below the noise floor, so the sliding-peak Goertzel latches onto noise and
  intermodulation products instead of the transmitted tone.

### Consequences for the software modem

| Mode | Approx. audio occupancy | Fits 300–3000 Hz? |
| --- | --- | --- |
| AFSK1200 (1200/2200 Hz) | ~1000–2500 Hz | ✅ Yes |
| PSK2400 (QPSK, 1800 Hz carrier) | ~1200–2400 Hz | ✅ Yes |
| PSK4800 (8PSK, 1800 Hz carrier) | ~200–3400 Hz | ❌ Falls off the top edge |
| G3RUH9600 (baseband) | DC–~4800 Hz | ❌ Killed by the 300 Hz high-pass and the top roll-off |

This is a **physical channel-bandwidth limit**, not a modem/DSP bug. It confirms
why only **AFSK1200** and **PSK2400** are viable over this radio's Bluetooth SBC
voice link, and it agrees with the offline `--bandpass` modeling in
[sbc-baud-rate-limit.md](sbc-baud-rate-limit.md).

---

## Reproduce

```
# 1. Build the reference sweep (32 kHz / 16-bit / mono)
dart run test/soft_modem_tool.dart sweep -o sweep.wav

# 2. Play sweep.wav out of radio A, record it on radio B as sweep-r1.wav

# 3. Measure the passband
dart run test/soft_modem_tool.dart sweepanalyze --f0 100 --f1 6000 --fstep 100 sweep-r1.wav
```

Tips for a clean run: keep the play/record level moderate to avoid the clipping
warning, and use the same `--f0/--f1/--fstep` you generated the sweep with. The
recording may be any sample rate, length, or channel count.
