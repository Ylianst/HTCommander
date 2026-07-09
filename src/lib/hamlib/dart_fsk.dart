/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// dart_fsk.dart - Constant-envelope 4-CPFSK modem for DART "Mode F".
//
// This is the amplitude-hostile fallback waveform. It transmits one of four
// tones per symbol with continuous phase, so the signal is strictly constant
// envelope — immune to the AGC / limiter / companding / SBC amplitude damage
// that attacks the QAM/PSK modes. Detection is non-coherent (per-symbol tone
// energy), so it needs neither channel estimation nor phase tracking.
//
// 2 bits/symbol (4 tones). Soft-output demodulation feeds the shared LDPC
// decoder. Framing, CRC, interleaving, and ARQ are all shared with the OFDM
// path — only the modulator/demodulator differs.
//

import 'dart:math' as math;
import 'dart:typed_data';

/// Parameters for the constant-envelope 4-CPFSK waveform.
class DartFskParams {
  /// Audio sample rate (Hz).
  final int sampleRate;

  /// Symbol rate (symbols/second).
  final int symbolRate;

  /// The four tone frequencies (Hz), one per 2-bit symbol. Kept inside the
  /// flat part of the radio passband (~400–2600 Hz) and spaced by the symbol
  /// rate for non-coherent orthogonality.
  final List<double> tones;

  DartFskParams({
    this.sampleRate = 32000,
    this.symbolRate = 400,
    List<double>? tones,
  }) : tones = tones ?? const [600.0, 1000.0, 1400.0, 1800.0];

  /// Samples per symbol.
  int get samplesPerSymbol => sampleRate ~/ symbolRate;

  /// Bits per symbol (4 tones → 2 bits).
  int get bitsPerSymbol => 2;
}

/// Constant-envelope 4-CPFSK modulator/demodulator.
class DartFsk {
  final DartFskParams params;

  DartFsk(this.params);

  /// Modulate a bit stream into continuous-phase FSK audio samples.
  /// Bits are packed 2 per symbol (MSB first); a trailing odd bit is padded 0.
  Float64List modulate(Uint8List bits) {
    final int sps = params.samplesPerSymbol;
    final int numSymbols = (bits.length + 1) ~/ 2;
    final out = Float64List(numSymbols * sps);

    double phase = 0.0;
    int idx = 0;
    for (int s = 0; s < numSymbols; s++) {
      final int b0 = (2 * s < bits.length) ? bits[2 * s] : 0;
      final int b1 = (2 * s + 1 < bits.length) ? bits[2 * s + 1] : 0;
      final int sym = (b0 << 1) | b1;
      final double f = params.tones[sym];
      final double dphi = 2 * math.pi * f / params.sampleRate;
      for (int i = 0; i < sps; i++) {
        out[idx++] = math.cos(phase);
        phase += dphi;
        // Keep phase bounded to avoid precision loss on long frames.
        if (phase > 2 * math.pi) phase -= 2 * math.pi;
      }
    }
    return out;
  }

  /// Hard-decision demodulate [numBits] bits from [samples] starting at
  /// [startSample]. Non-coherent per-symbol tone-energy detection.
  Uint8List demodulate(Float64List samples, int startSample, int numBits) {
    final int numSymbols = (numBits + 1) ~/ 2;
    final bits = Uint8List(numSymbols * 2);
    for (int s = 0; s < numSymbols; s++) {
      final energies = _toneEnergies(samples, startSample + s * params.samplesPerSymbol);
      int bestSym = 0;
      double bestE = -1;
      for (int t = 0; t < 4; t++) {
        if (energies[t] > bestE) {
          bestE = energies[t];
          bestSym = t;
        }
      }
      bits[2 * s] = (bestSym >> 1) & 1;
      bits[2 * s + 1] = bestSym & 1;
    }
    return Uint8List.sublistView(bits, 0, numBits);
  }

  /// Soft-decision demodulate: return per-bit LLRs for [numBits] bits.
  /// Positive LLR → bit is likely 0, negative → likely 1 (min-sum convention).
  Float64List demodulateSoft(Float64List samples, int startSample, int numBits) {
    final int numSymbols = (numBits + 1) ~/ 2;
    final llrs = Float64List(numSymbols * 2);
    const double scale = 4.0;
    for (int s = 0; s < numSymbols; s++) {
      final energies = _toneEnergies(samples, startSample + s * params.samplesPerSymbol);
      // Amplitudes, normalized to the strongest tone for a stable LLR scale.
      double maxA = 1e-12;
      final a = List<double>.filled(4, 0);
      for (int t = 0; t < 4; t++) {
        a[t] = math.sqrt(energies[t]);
        if (a[t] > maxA) maxA = a[t];
      }
      for (int t = 0; t < 4; t++) {
        a[t] /= maxA;
      }
      // Bit 0 (MSB): 0 for tones {0,1}, 1 for tones {2,3}.
      llrs[2 * s] = scale * (math.max(a[0], a[1]) - math.max(a[2], a[3]));
      // Bit 1 (LSB): 0 for tones {0,2}, 1 for tones {1,3}.
      if (2 * s + 1 < llrs.length) {
        llrs[2 * s + 1] = scale * (math.max(a[0], a[2]) - math.max(a[1], a[3]));
      }
    }
    return Float64List.sublistView(llrs, 0, numBits);
  }

  /// Estimate a coarse SNR (dB) across a run of symbols from the ratio of the
  /// winning tone energy to the runner-up (a tone-separation quality metric).
  double estimateSnrDb(Float64List samples, int startSample, int numSymbols) {
    double ratioSum = 0;
    int count = 0;
    for (int s = 0; s < numSymbols; s++) {
      final int off = startSample + s * params.samplesPerSymbol;
      if (off + params.samplesPerSymbol > samples.length) break;
      final energies = _toneEnergies(samples, off);
      energies.sort();
      final double best = energies[3];
      final double second = energies[2];
      if (second > 1e-12) {
        ratioSum += best / second;
        count++;
      }
    }
    if (count == 0) return 0;
    final double avgRatio = ratioSum / count;
    return 10 * (math.log(avgRatio) / math.ln10);
  }

  /// Compute the non-coherent energy at each of the four tones for the symbol
  /// beginning at [offset].
  List<double> _toneEnergies(Float64List samples, int offset) {
    final int sps = params.samplesPerSymbol;
    final energies = List<double>.filled(4, 0);
    for (int t = 0; t < 4; t++) {
      final double f = params.tones[t];
      final double w = 2 * math.pi * f / params.sampleRate;
      double re = 0;
      double im = 0;
      for (int i = 0; i < sps; i++) {
        final int n = offset + i;
        if (n >= samples.length) break;
        final double ph = w * i;
        re += samples[n] * math.cos(ph);
        im += samples[n] * math.sin(ph);
      }
      energies[t] = re * re + im * im;
    }
    return energies;
  }

  /// Number of audio samples a bit stream of [numBits] bits will occupy.
  int samplesForBits(int numBits) {
    final int numSymbols = (numBits + 1) ~/ 2;
    return numSymbols * params.samplesPerSymbol;
  }
}
