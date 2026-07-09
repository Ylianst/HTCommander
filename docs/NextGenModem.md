# DART — Data Adaptive Rate Transport

A coherent, adaptive, single-carrier frequency-domain modem designed for the
VHF/UHF FM audio channel over Bluetooth (SBC codec). Targets 1–6 kbps net
throughput with automatic rate adaptation — a significant step up from AFSK1200
and PSK2400.

---

## Channel parameters

| Parameter | Value |
| --- | --- |
| Audio sample rate | 32 kHz, 16-bit, mono PCM |
| Usable bandwidth | ~400–2600 Hz (flat within ~2 dB) |
| Band edges (unusable) | < 300 Hz (AC-coupled), > 3000 Hz (SBC rolloff) |
| Channel type | Static band-pass filter (no fading, no multipath) |
| Amplitude behavior | Mildly compressed (AGC + limiter + SBC); linear enough for QAM |
| Noise floor | FM noise + SBC quantization; in-band SNR ~20–25 dB |
| Delay spread | Negligible |

The channel is static — a single training preamble is sufficient to estimate and
equalize it. No continuous adaptive equalization is needed.

---

## Waveform: DFT-spread OFDM (SC-FDMA)

The primary waveform is DFT-spread OFDM, which provides:

- OFDM's frequency-domain equalization (simple 1-tap per subcarrier)
- Single-carrier-like low peak-to-average power ratio (PAPR)
- Ability to concentrate energy only in the usable 400–2600 Hz band

### Parameters (tentative, to be refined by measurement)

| Parameter | Value |
| --- | --- |
| FFT size | 64 or 128 (at 32 kHz sample rate → 500 or 250 Hz subcarrier spacing) |
| Active subcarriers | Only those within 400–2600 Hz |
| Cyclic prefix | Short (~2–4 samples); channel has negligible delay spread |
| Symbol rate | Determined by FFT size + CP length |
| Frequency band | 400–2600 Hz; zero energy outside this range |

### Transmit processing chain

```
Input bits
  → CRC-32 append
  → LDPC encode (rate per mode table)
  → bit interleaver (block interleave to break SBC burst errors)
  → constellation mapper (BPSK / QPSK / 8PSK / 16QAM per mode)
  → DFT-spread (N-point DFT across data symbols)
  → subcarrier mapping (place in active bins, zero inactive bins)
  → IFFT → add cyclic prefix
  → prepend preamble
  → output 32 kHz / 16-bit / mono PCM
```

### Receive processing chain

```
Input PCM
  → preamble detection (correlation)
  → timing and frequency offset estimation (from preamble)
  → strip cyclic prefix → FFT
  → channel estimation (from preamble known sequence)
  → 1-tap frequency-domain equalization (H⁻¹ per subcarrier)
  → subcarrier demapping
  → IDFT (undo DFT-spread)
  → soft demapping (LLR computation for each bit)
  → deinterleave
  → LDPC soft decode (iterative, e.g. sum-product or min-sum)
  → CRC check
```

---

## Frame structure

```
┌──────────────────┬───────────────────┬────────────────────────────┐
│    Preamble      │   Header          │   Payload                  │
│    (fixed)       │   (mode 0)        │   (variable mode)          │
└──────────────────┴───────────────────┴────────────────────────────┘
```

### Preamble

- **Sequence:** Zadoff-Chu (constant envelope, sharp autocorrelation) or chirp.
- **Purpose:** frame detection, symbol timing, carrier frequency offset estimation,
  and one-shot channel estimation.
- **Properties:** constant envelope (survives AGC/limiter), known a priori by the
  receiver, same for all modes.
- **Length:** ~20–50 ms (to be optimized; longer = better channel estimate,
  shorter = less overhead).

### Header

- **Always transmitted at mode 0** (BPSK, LDPC rate 1/2) so any receiver can
  decode it regardless of channel quality.
- **Contents:**

| Field | Bits | Description |
| --- | --- | --- |
| Mode index | 4 | Payload modulation/coding mode (0–5, F) |
| Frame length | 12 | Payload length in bytes |
| Source address | 48 | Callsign (6 chars × 7-bit + SSID, AX.25 compatible) |
| Destination address | 48 | Callsign (6 chars × 7-bit + SSID, AX.25 compatible) |
| Sequence number | 8 | For ARQ |
| Flags | 8 | ACK/NACK/data/control/broadcast |
| Header CRC | 16 | CRC-16 over header fields |

Total: ~144 bits → 288 coded bits at rate 1/2 → transmitted as BPSK SC-FDMA
symbols.

### Payload

- Modulated and coded according to the mode index in the header.
- Maximum payload size: TBD (limited by interleaver depth and acceptable latency;
  likely 256–1024 bytes per frame).
- Protected by CRC-32 (appended before FEC encoding).

---

## Mode table

| Mode | Constellation | LDPC rate | Bits/symbol | Net throughput (est.) |
| --- | --- | --- | --- | --- |
| 0 | BPSK | 1/2 | 1 | ~0.8–1.0 kbps |
| 1 | QPSK | 1/2 | 2 | ~1.5–2.0 kbps |
| 2 | QPSK | 2/3 | 2 | ~2.5–3.0 kbps |
| 3 | 8PSK | 2/3 | 3 | ~3.5–4.0 kbps |
| 4 | 16QAM | 3/4 | 4 | ~4.5–5.5 kbps |
| 5 | 16QAM | 5/6 | 4 | ~5.5–6.5 kbps |
| F | 4-CPM (fallback) | 1/2 | ~1 | ~1.0–1.5 kbps |

Modes 0–5 use the same SC-FDMA modulator/demodulator — only the constellation
lookup table and LDPC code rate parameter change. Mode F uses a separate
constant-envelope CPM modulator but shares all other layers.

---

## Forward error correction: LDPC

- **Code family:** Regular or irregular LDPC (e.g. IEEE 802.11n/ac style, or
  DVB-S2 style codes).
- **Block lengths:** 648, 1296, or 1944 bits (matching 802.11 LDPC) — or a custom
  length tuned to frame sizes.
- **Rates:** 1/2, 2/3, 3/4, 5/6 (selected per mode).
- **Decoding:** Iterative belief-propagation (sum-product or min-sum approximation),
  soft-input from LLR demapper.
- **Interleaving:** Block bit-interleaver between LDPC output and constellation
  mapper. Breaks up burst errors from SBC codec artifacts so the decoder sees
  approximately random errors.

### Optional outer code

An outer Reed-Solomon code (e.g. RS(255,239)) may be added over multiple LDPC
blocks to handle residual burst errors that survive the interleaver. This is a
concatenated scheme: inner LDPC (corrects most errors) + outer RS (catches
residual bursts).

---

## Synchronization

### Preamble detection

Cross-correlate incoming samples with the known preamble sequence. A correlation
peak above a threshold indicates frame start. Zadoff-Chu sequences have ideal
periodic autocorrelation (zero sidelobes), giving sharp unambiguous detection.

### Frequency offset estimation

The preamble contains two identical halves (or a repeated pattern). The phase
rotation between them gives the fractional frequency offset:

```
Δf = angle(R) / (2π · T_half)
```

where `R` is the correlation between the two halves and `T_half` is the duration
of one half. Correction is applied by multiplying the received signal by
`exp(-j·2π·Δf·t)`.

### Channel estimation

The preamble is a known sequence. After timing/frequency sync, divide the
received preamble's frequency-domain representation by the known transmitted
preamble to get the channel frequency response `H[k]` at each active subcarrier:

```
H[k] = Y_preamble[k] / X_preamble[k]
```

This is a one-shot estimate — valid for the entire frame because the channel is
static.

### Equalization

One-tap zero-forcing (or MMSE) per subcarrier:

```
X̂[k] = Y[k] / H[k]                          (zero-forcing)
X̂[k] = H*[k]·Y[k] / (|H[k]|² + σ²)         (MMSE)
```

No decision-feedback or adaptive tracking is needed.

---

## CPM fallback mode (mode F)

For radios with severe amplitude distortion (hard limiting, aggressive
companding), a constant-envelope waveform is available.

| Parameter | Value |
| --- | --- |
| Modulation | 4-CPM (4 frequency states, continuous phase) |
| Symbol rate | 2400–3200 symbols/s |
| Modulation index | h = 1/4 or 1/3 (spectrally compact) |
| Pulse shaping | Gaussian or raised-cosine, L=2 or L=3 symbol spans |
| FEC | Same LDPC rate 1/2 as mode 0 |
| Bandwidth | Fits within 400–2600 Hz |

Detection: coherent Viterbi on the CPM trellis (optimal) or differential
detection (simpler, ~1–2 dB loss).

The preamble for mode F is also constant-envelope (same Zadoff-Chu, which is
already constant-envelope). The header signals mode F, after which the receiver
switches to the CPM demodulator for the payload.

---

## Rate adaptation

### Per-frame self-describing

Every frame's header (decoded at mode 0) contains the payload mode index. A
receiver can decode any frame without prior negotiation — enabling broadcast,
monitoring, and first-contact.

### ARQ-driven rate selection (connected sessions)

```
State: current_mode = 1

On TX:
  Send frame at current_mode

On RX of ACK:
  ack_streak += 1
  if ack_streak >= N_UP (e.g. 4):
    current_mode = min(current_mode + 1, max_mode)
    ack_streak = 0

On RX of NACK or timeout:
  current_mode = max(current_mode - 2, 0)
  ack_streak = 0
  retransmit frame at new mode
```

### Mode F fallback trigger

If the channel estimate from the preamble shows severe amplitude distortion
(e.g. the equalized constellation scatter exceeds a threshold), the transmitter
drops to mode F and signals this in the header. The receiver's CPM demodulator
activates for that frame's payload.

---

## Link layer

### ARQ: Selective repeat with hybrid ARQ

- **Window size:** 8–16 frames.
- **ACK/NACK:** Sent as short mode-0 frames (maximally robust).
- **Incremental redundancy:** On NACK, retransmit with a lower code rate (more
  parity bits). The receiver soft-combines the original and retransmission for
  better decoding probability.
- **Timeout:** If no ACK within T_timeout, retransmit at a lower mode.

### Addressing

Reuse AX.25-compatible callsign addressing (source + destination + SSID) so the
modem can coexist with existing packet radio infrastructure and the current
AFSK1200/PSK2400 stack.

### Compression

Optional payload compression (e.g. zlib/deflate) applied before FEC encoding.
Signaled by a flag in the header. Useful for text and telemetry; skipped for
already-compressed data.

---

## Audio output specification

| Parameter | Value |
| --- | --- |
| Sample rate | 32000 Hz |
| Bit depth | 16-bit signed integer |
| Channels | Mono |
| Format | PCM (WAV for offline, raw PCM for streaming) |
| Peak amplitude | ~80% of full scale (leave headroom for AGC/limiter) |
| Frequency content | Strictly within 400–2600 Hz |

---

## Coexistence with existing modem

The next-gen modem operates alongside the current AFSK1200 / PSK2400 software
modem:

- Different preamble signatures allow the receiver to distinguish frame types.
- The existing AX.25/FX.25 framing is preserved at the link layer.
- Stations can negotiate up from PSK2400 to DART during session setup,
  falling back if the peer does not support it.
- Both modems can listen simultaneously (same audio stream, different decoders).

---

## Test and validation approach

1. **Offline WAV round-trip:** Encode → WAV → decode. Verify bit-perfect at all
   modes with no channel impairment.
2. **SBC round-trip:** Encode → SBC compress → SBC decompress → decode. Validates
   against the real Bluetooth codec distortion.
3. **Band-pass + noise:** Add simulated FM noise and band-pass filtering to the
   WAV test path. Measure BER vs. SNR for each mode.
4. **Over-the-air:** Transmit and receive through actual radios. Compare measured
   throughput and error rates against offline predictions.
5. **Mode sweep:** Verify that all modes 0–5 and F decode correctly through the
   SBC round-trip path.

All tests reuse the existing `soft_modem_tool.dart` harness and `sbc`/`sbctest`
tooling.
