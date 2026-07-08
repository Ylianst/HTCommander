# Proposal: a next-generation encoder/decoder for the radio's audio channel

**Date:** 2026-07-07
**Status:** Design proposal / discussion — no code yet
**Builds on:** [radio-audio-passband.md](radio-audio-passband.md),
[radio-amplitude-linearity.md](radio-amplitude-linearity.md),
[sbc-baud-rate-limit.md](sbc-baud-rate-limit.md)
**Question:** Given what we now *measured* about the radio, what would the best
possible modem look like using modern techniques, and what are the trade-offs?

---

## TL;DR recommendation

Build a **coherent, training-equalized, adaptive single-carrier-frequency-domain
(DFT-spread-OFDM / "SC-FDMA") waveform with LDPC coding and per-tone bit-loading
driven by the sweep measurement**, plus a **constant-envelope 4-CPM fallback mode**
for radios whose audio path mangles amplitude too badly.

> **Update (2026-07-07):** the amplitude-linearity measurement is now done — see
> [radio-amplitude-linearity.md](radio-amplitude-linearity.md). On the tested
> radio pair the audio path is **fairly linear** (ratio tracks 1:1, slope 1.03,
> IMD3 ≤ −34 dB), so **higher-order QAM (up to ~16-QAM) is viable** and the
> primary SC-FDMA/QAM path is confirmed. The constant-envelope mode drops from a
> likely necessity to a **fallback** for other radios / weak links.

Why this shape:

1. The channel is **almost a fixed linear filter** (a ~300–3000 Hz band-pass) —
   so a short **training preamble can measure and invert it once**, and coherent
   high-order modulation becomes practical (unlike fading HF).
2. The channel's amplitude handling was the main open risk (AGC, limiter,
   companding, lossy SBC). Direct measurement shows it is **only mildly
   compressed** on the tested pair, so amplitude is usable — but we still favor a
   **low peak-to-average power ratio (PAPR)** waveform to protect the finite AGC
   margin. DFT-spread OFDM gives OFDM's adaptivity with single-carrier-like low
   PAPR; constant-envelope CPM eliminates amplitude entirely for the worst radios.
3. **LDPC** replaces Reed–Solomon (FX.25) for ~3–6 dB of coding gain — the single
   biggest, cheapest win.
4. **Adaptive bit-loading** spends bits where the channel is strong (the flat
   500–2500 Hz mid-band) and nothing where it is weak (< 300 Hz, > ~3000 Hz) —
   the sweep already tells us exactly where those are.

---

## What the channel actually is (and what it implies)

From the passband measurement and the SBC study:

| Property | Measured / known | Design implication |
| --- | --- | --- |
| Usable band | Flat within ~2 dB **300–2900 Hz**; −3 dB at 3100 Hz | Put all energy in **~400–2600 Hz**; treat band edges as unusable |
| Low-frequency cutoff | 100/200 Hz ≈ −23 dB (AC-coupled) | **No DC / near-DC content** → rules out baseband G3RUH-style |
| Shape stability | Band-pass shape is **static** (a fixed filter) | **One-shot training equalization** works; no fast adaptive EQ needed |
| Amplitude handling | AGC + limiter + companding + lossy **SBC** at 32 kHz; **measured mildly linear** (slope 1.03, IMD3 ≤ −34 dB) | **Amplitude is usable** → QAM viable; still prefer low-PAPR for margin |
| Phase/frequency handling | FM + SBC preserve frequency/phase well; clocks are ppm-accurate | **Coherent PSK/QAM is feasible**; small fixed frequency offset only |
| Noise | FM noise + SBC quantization noise floor | Finite in-band SNR → cap on constellation order and throughput |
| Delay spread | Negligible (audio baseband, FM capture) | **Little ISI** → equalizer only corrects the static passband tilt |

**Key realization:** this is *not* an HF fading channel. It is a **short, static,
band-limited, mildly amplitude-compressed** channel. That combination points away
from the aggressive adaptive equalizers HF modems use, and toward **train-once,
low-PAPR, coherent, heavily-FEC'd** designs.

### Rough capacity ceiling

Shannon: `C = B · log2(1 + SNR)`. With `B ≈ 2200 Hz` usable and an in-band SNR of
roughly 20–25 dB (limited by SBC + FM noise), the theoretical ceiling is
~15–18 kbps. Realistically, after amplitude distortion, sync/pilot/FEC overhead,
and margin, a robust design should target **3–6 kbps net** in good conditions and
**~1–2 kbps** in a robust fallback — a large step up from AFSK1200 / PSK2400.

---

## Menu of modern techniques (with pros/cons)

### 1. Modulation / waveform

| Technique | Pros | Cons | Fit here |
| --- | --- | --- | --- |
| **OFDM** (many QAM subcarriers) | Per-carrier bit-loading matches our measured passband perfectly; trivial 1-tap equalization; robust to any residual ISI | **High PAPR** → the FM limiter clips peaks; sensitive to frequency offset & phase noise; needs guard interval | Good *idea*, bad *PAPR* on this amplitude-hostile path unless mitigated |
| **DFT-spread OFDM / SC-FDMA** (single-carrier freq-domain) | Keeps OFDM's easy equalization **and** adaptivity, but **PAPR close to single-carrier**; standard in LTE uplink for exactly this reason | Slightly more complex RX; bit-loading is coarser (per-block, not per-tone) | **Recommended primary** — best trade of adaptivity vs. PAPR |
| **Single-carrier PSK/QAM + DFE** (à la MIL-STD-188-110 serial) | Low PAPR; mature; good spectral efficiency | Needs a decision-feedback equalizer; error propagation | Viable; our static channel makes the EQ easy, but no better than SC-FDMA |
| **Constant-envelope CPM / GMSK / 4-FSK** | **Immune to AGC/limiter/companding/SBC amplitude damage**; spectrally compact; great in a hard-limited path | ~1 bit/symbol-class efficiency (lower peak throughput); coherent CPM detection is complex (or accept differential loss) | **Recommended fallback** for the worst radios |
| **High-order QAM (16/64) single carrier** | Highest bits/symbol | Amplitude-dependent → **directly attacked** by AGC/limiter/SBC; needs excellent SNR & linearity | Only usable if a given radio's audio path proves clean |

### 2. Forward error correction (FEC)

| Technique | Pros | Cons | Fit here |
| --- | --- | --- | --- |
| **LDPC** | Near-Shannon (~3–6 dB better than RS); rate-adaptable; well-understood decoders | Iterative decode cost; needs a good soft-decision demod | **Recommended** — biggest single gain |
| **Turbo codes** | Also near-capacity; strong at low SNR | Patented-history baggage; latency; similar cost to LDPC | Fine alternative to LDPC |
| **Polar codes** | Capacity-achieving; modern (5G control) | Best at short blocks; list decoding complexity | Interesting for short ACK/control frames |
| **Convolutional + Viterbi** | Simple; great soft-decision performance; low latency | Weaker than LDPC/Turbo at a given rate | Good inner code, or for tiny frames |
| **Reed–Solomon (current FX.25)** | Already implemented; great for *burst* errors | Hard-decision only; far from capacity | Keep as an **outer** code over bursty SBC artifacts, pair with an inner soft code |
| **Fountain / Raptor codes** | Rateless — elegant for ARQ/broadcast without feedback | Overhead at short lengths | Nice for one-to-many (BBS bulletins) |

A modern **concatenated** scheme — inner **LDPC (soft)** + outer interleaver +
optional **RS** for residual bursts — is the sweet spot.

### 3. Adaptive modulation & coding (AMC) / bit-loading

| Technique | Pros | Cons |
| --- | --- | --- |
| **Water-filling / per-tone bit-loading** from the sweep | Extracts maximum throughput from *this* channel's exact shape; gracefully degrades | Needs a channel estimate (the sweep/preamble already provides it); requires a signalling handshake to agree on the profile |
| **Discrete AMC levels** (pick from a small table of {mod, code-rate}) | Simple, robust, interoperable; easy ARQ fallback | Coarser than continuous water-filling |

The sweep we already built is essentially a **channel sounder** — the same data
that drew the passband curve can directly drive bit-loading.

### 4. Synchronization & channel estimation

| Technique | Pros | Cons |
| --- | --- | --- |
| **Zadoff-Chu / CAZAC or m-sequence preamble** | Sharp autocorrelation → precise timing & frequency offset; constant envelope (limiter-friendly) | Costs airtime up front |
| **Pilot tones / scattered pilots** | Continuous phase & channel tracking; corrects slow drift | Steals a few % of capacity |
| **Chirp / sweep preamble** (we already generate one!) | Doubles as channel sounder for bit-loading; robust detection | Longer than a minimal sync word |

### 5. PAPR reduction (only if using OFDM)

| Technique | Pros | Cons |
| --- | --- | --- |
| **DFT-spread (SC-FDMA)** | Structural low PAPR; no side-info | Coarser bit-loading (already chosen above) |
| **Clipping + filtering** | Trivial | Adds in-band distortion + spectral regrowth |
| **Tone reservation / PTS / SLM** | Real PAPR gains | Complexity; some need side-information |

### 6. Link layer / ARQ

| Technique | Pros | Cons |
| --- | --- | --- |
| **Hybrid ARQ with incremental redundancy** (send more parity on NACK) | Combines FEC + retransmit optimally; adapts to conditions automatically | State machine complexity |
| **Selective-repeat ARQ** (VARA/PACTOR-style) | Efficient; only resends lost blocks | Needs a reliable return path |
| **Rateless/fountain forward-only** | No feedback needed (good for one-way / broadcast) | Overhead vs. ARQ on a good return channel |
| **Payload compression** (before FEC) | Free throughput on text/telemetry | Little help on already-compressed data |
| **Interleaving** | Breaks up SBC/FM burst errors so FEC sees random errors | Adds latency |

### 7. Modern / speculative

- **Probabilistic constellation shaping** — small (~1 dB) gain; complexity likely
  not worth it here.
- **Neural / autoencoder-based modems (learned constellations & equalizers)** —
  can adapt to the SBC + limiter nonlinearity better than hand-designed schemes,
  and could be trained directly on recordings like `sweep-r1.wav`. Cons: heavy,
  hard to make interoperable/deterministic, and overkill for now — but a genuinely
  interesting research direction given we can generate labeled channel data
  cheaply.

---

## Recommended architecture (primary mode)

A layered design, "**HTModem-NG**":

```
Payload
  → compress (optional)
  → CRC + framing
  → LDPC encode (rate adaptive, e.g. 1/2 … 5/6)
  → bit interleave
  → adaptive QAM mapping per DFT-spread-OFDM block (BPSK/QPSK/8PSK/16QAM,
      bits allocated by the sweep/preamble channel estimate, energy kept in
      ~400–2600 Hz)
  → DFT-spread OFDM modulate (low PAPR), short cyclic prefix
  → prepend Zadoff-Chu/chirp preamble (sync + channel sounding)
  → 32 kHz / 16-bit / mono PCM out to the radio
```

Receive path mirrors it: preamble detect → frequency/timing sync → one-shot
channel estimate & equalize (channel is static) → soft demap → deinterleave →
LDPC soft-decode → CRC. A **selective-repeat / hybrid-ARQ** link layer sits on top
(reusing the existing AX.25/FX.25 addressing so it stays interoperable with the
current stack where possible).

### Fallback mode (amplitude-hostile radios)

**Constant-envelope 4-CPM (or GMSK) at ~2400–3200 symbols/s in-band, LDPC-coded.**
It gives up peak throughput but is essentially immune to the AGC/limiter/companding/SBC
amplitude damage that the SBC study showed narrows margins. The link negotiates
down to this automatically when the primary mode's equalizer reports a bad
amplitude channel.

### Expected throughput (order-of-magnitude)

| Condition | Mode | Net throughput (est.) |
| --- | --- | --- |
| Clean, linear audio path | SC-FDMA, 8PSK/16QAM, LDPC 5/6 | ~4–6 kbps |
| Typical | SC-FDMA, QPSK/8PSK, LDPC 2/3 | ~2.5–4 kbps |
| Poor / hostile amplitude | 4-CPM, LDPC 1/2 | ~1–2 kbps |

All comfortably above AFSK1200 and PSK2400, and — crucially — **matched to the
measured channel** instead of fighting it.

---

## How this maps onto the existing code

- Reuse `wav_file.dart`, `gen_tone.dart`, `audio_buffer.dart`, and the
  `soft_modem_tool.dart` harness for offline encode/decode and the `sbc`/`sbctest`
  round-trip so every new waveform is validated through the **real** SBC + noise +
  bandpass chain before it ever touches a radio.
- The `sweep`/`sweepanalyze` tooling already **is** the channel sounder needed for
  bit-loading — extend it to emit a machine-readable per-tone SNR profile.
- Keep the AX.25/FX.25 framing/addressing layer so the new PHY can coexist with the
  current one and negotiate up from PSK2400.
- Cross-validate against **FreeDV/Codec2 OFDM** and **MIL-STD-188-110** references,
  the same way the modem was cross-validated against Direwolf.

---

## Honest caveats & next measurements

- ✅ **Amplitude linearity — DONE.** Measured directly with the two-tone
  `amptest`; the path is fairly linear on the tested pair (slope 1.03,
  IMD3 ≤ −34 dB) → **higher-order QAM is viable**. See
  [radio-amplitude-linearity.md](radio-amplitude-linearity.md). (The earlier
  `sweep-r1.wav` and `amptest-r1.wav` runs were **mildly clipped**; re-record a
  touch quieter for a pristine confirmation, though it does not change the
  conclusion. Re-check per radio family before fixing a constellation order.)
- Measure **phase/group-delay flatness** across 400–2600 Hz (a two-tone or
  multitone phase test), since coherent QAM cares about phase, not just magnitude.
- Characterize the **SBC quantization noise floor** vs. input level to pick the
  optimal operating amplitude (loud enough for SNR, quiet enough to dodge the
  limiter).
- Confirm the residual **frequency offset** between the two audio clocks to size
  the sync/pilot design.
- Probe the **AGC time constant** (an amplitude-*step* transient test) — the
  amplitude test above is static and does not show how fast the gain reacts at
  the start of a burst.

The amplitude question is now answered; the remaining measurements would pin down
the last waveform parameters (phase flatness, operating level, sync budget).
