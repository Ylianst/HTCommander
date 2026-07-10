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
// dart_ofdm.dart - OFDM / DFT-spread OFDM (SC-FDMA) modem for DART.
//
// Implements:
// - FFT/IFFT (radix-2 Cooley-Tukey)
// - DFT-spread precoding (SC-FDMA) for low PAPR — optional per symbol
// - Subcarrier mapping (active bins within 400–2600 Hz)
// - Cyclic prefix add/remove
// - Per-subcarrier zero-forcing equalization from a channel estimate
//
// Data-bearing symbols use DFT-spread (SC-FDMA) by default for low PAPR; the
// preamble's channel-estimation symbol disables it so known pilots land
// directly on each subcarrier.
//

import 'dart:math' as math;
import 'dart:typed_data';

import 'dart_constellation.dart';

/// DART OFDM parameters.
class DartOfdmParams {
  /// Sample rate in Hz.
  final int sampleRate;

  /// FFT size (must be power of 2).
  final int fftSize;

  /// Cyclic prefix length in samples.
  final int cpLength;

  /// Lower edge of usable band in Hz.
  final double freqLow;

  /// Upper edge of usable band in Hz.
  final double freqHigh;

  /// Indices of active subcarriers (computed from freq range).
  late final List<int> activeCarriers;

  /// Number of active data subcarriers.
  int get numDataCarriers => activeCarriers.length;

  /// Samples per OFDM symbol (including CP).
  int get symbolLength => fftSize + cpLength;

  /// Subcarrier spacing in Hz.
  double get subcarrierSpacing => sampleRate / fftSize;

  DartOfdmParams({
    this.sampleRate = 32000,
    this.fftSize = 128,
    this.cpLength = 4,
    this.freqLow = 400.0,
    this.freqHigh = 2600.0,
  }) {
    // Compute active subcarrier indices
    final double spacing = subcarrierSpacing;
    activeCarriers = [];
    for (int k = 0; k < fftSize; k++) {
      final double freq = k * spacing;
      if (freq >= freqLow && freq <= freqHigh) {
        activeCarriers.add(k);
      }
    }
  }

  /// Experimental SBC-aligned OFDM profile.
  ///
  /// Confines every active subcarrier to SBC subband 0 (0–2000 Hz at 32 kHz /
  /// 8 subbands) so no subcarrier lands in a bit-starved higher subband or
  /// straddles a subband boundary — which is where SBC quantization noise
  /// concentrates. The FFT stays at 128 (short, phase-noise-robust symbols);
  /// the 400–1900 Hz band yields 6 subcarriers, so throughput is lower than the
  /// default 9-carrier profile. Intended for A/B testing whether SBC alignment
  /// measurably helps a real radio link.
  ///
  /// NOTE: this is NOT wire-compatible with the default profile — both ends of
  /// a link must use the same profile.
  factory DartOfdmParams.sb0Aligned() =>
      DartOfdmParams(freqLow: 400.0, freqHigh: 1900.0);
}

/// DFT-spread OFDM modulator and demodulator.
class DartOfdm {
  final DartOfdmParams params;

  DartOfdm(this.params);

  /// Modulate one OFDM symbol from data symbols.
  /// [dataSymbols] has length == params.numDataCarriers.
  /// When [dftSpread] is true (SC-FDMA), the data symbols are precoded with an
  /// M-point DFT before subcarrier mapping, which spreads each symbol across all
  /// active tones and yields a low-PAPR, single-carrier-like waveform. Set it
  /// false for pilot/channel-estimation symbols that must place known values
  /// directly on each subcarrier.
  /// Returns time-domain samples (length = params.symbolLength) as real values.
  Float64List modulateSymbol(
    List<Complex> dataSymbols, {
    bool dftSpread = true,
  }) {
    if (dataSymbols.length != params.numDataCarriers) {
      throw ArgumentError(
        'Expected ${params.numDataCarriers} symbols, got ${dataSymbols.length}',
      );
    }

    // Optional DFT-spread precoding (SC-FDMA)
    final List<Complex> tones =
        dftSpread ? _dftSpread(dataSymbols, inverse: false) : dataSymbols;

    // Subcarrier mapping — place tones into active FFT bins
    final freqDomain = List<Complex>.filled(params.fftSize, const Complex(0, 0));
    for (int i = 0; i < params.numDataCarriers; i++) {
      freqDomain[params.activeCarriers[i]] = tones[i];
    }

    // IFFT to time domain
    final timeDomain = _fft(freqDomain, inverse: true);

    // Add cyclic prefix
    final output = Float64List(params.symbolLength);
    for (int i = 0; i < params.cpLength; i++) {
      output[i] = timeDomain[params.fftSize - params.cpLength + i].i;
    }
    for (int i = 0; i < params.fftSize; i++) {
      output[params.cpLength + i] = timeDomain[i].i;
    }

    return output;
  }

  /// Demodulate one OFDM symbol from time-domain samples.
  /// [samples] has length == params.symbolLength (real-valued).
  /// [channelEstimate] is H[k] for each active subcarrier (from preamble).
  /// [dftSpread] must match the value used at modulation.
  /// Returns equalized data symbols (length == params.numDataCarriers).
  List<Complex> demodulateSymbol(
    Float64List samples,
    List<Complex> channelEstimate, {
    bool dftSpread = true,
  }) {
    if (samples.length != params.symbolLength) {
      throw ArgumentError(
        'Expected ${params.symbolLength} samples, got ${samples.length}',
      );
    }

    // Step 1: Remove cyclic prefix
    final rxTime = List<Complex>.generate(
      params.fftSize,
      (i) => Complex(samples[params.cpLength + i], 0.0),
    );

    // Step 2: FFT to frequency domain
    final freqDomain = _fft(rxTime, inverse: false);

    // Step 3: Extract active subcarriers and equalize (ZF)
    final equalized = List<Complex>.filled(
      params.numDataCarriers,
      const Complex(0, 0),
    );
    for (int i = 0; i < params.numDataCarriers; i++) {
      final int k = params.activeCarriers[i];
      final Complex rx = freqDomain[k];
      final Complex h = channelEstimate[i];
      // Zero-forcing: X = Y / H
      final double hMagSq = h.magnitudeSquared;
      if (hMagSq > 1e-10) {
        equalized[i] = Complex(
          (rx.i * h.i + rx.q * h.q) / hMagSq,
          (rx.q * h.i - rx.i * h.q) / hMagSq,
        );
      }
    }

    // Step 4: undo DFT-spread (SC-FDMA de-precoding)
    return dftSpread ? _dftSpread(equalized, inverse: true) : equalized;
  }

  /// Demodulate one OFDM symbol returning raw (un-equalized) FFT bins for the
  /// active subcarriers. Used for decision-directed channel estimation.
  List<Complex> demodulateSymbolRaw(Float64List samples) {
    if (samples.length != params.symbolLength) {
      throw ArgumentError(
        'Expected ${params.symbolLength} samples, got ${samples.length}',
      );
    }
    final rxTime = List<Complex>.generate(
      params.fftSize,
      (i) => Complex(samples[params.cpLength + i], 0.0),
    );
    final freqDomain = _fft(rxTime, inverse: false);
    final bins = List<Complex>.filled(
      params.numDataCarriers,
      const Complex(0, 0),
    );
    for (int i = 0; i < params.numDataCarriers; i++) {
      bins[i] = freqDomain[params.activeCarriers[i]];
    }
    return bins;
  }

  /// Estimate channel from a known preamble symbol.
  /// [rxSamples] = received preamble symbol (length = symbolLength).
  /// [txSymbols] = known transmitted data symbols for the preamble.
  /// Returns H[k] for each active subcarrier.
  List<Complex> estimateChannel(
    Float64List rxSamples,
    List<Complex> txSymbols,
  ) {
    // Remove CP and FFT
    final rxTime = List<Complex>.generate(
      params.fftSize,
      (i) => Complex(rxSamples[params.cpLength + i], 0.0),
    );
    final rxFreq = _fft(rxTime, inverse: false);

    // Modulate the known TX symbols (same as modulateSymbol without CP)
    final txFreq = List<Complex>.filled(params.fftSize, const Complex(0, 0));
    for (int i = 0; i < txSymbols.length && i < params.numDataCarriers; i++) {
      txFreq[params.activeCarriers[i]] = txSymbols[i];
    }

    // H[k] = Y[k] / X[k] for active carriers
    final h = List<Complex>.filled(
      params.numDataCarriers,
      const Complex(0, 0),
    );
    for (int i = 0; i < params.numDataCarriers; i++) {
      final int k = params.activeCarriers[i];
      final Complex y = rxFreq[k];
      final Complex x = txFreq[k];
      final double xMagSq = x.magnitudeSquared;
      if (xMagSq > 1e-10) {
        h[i] = Complex(
          (y.i * x.i + y.q * x.q) / xMagSq,
          (y.q * x.i - y.i * x.q) / xMagSq,
        );
      }
    }
    return h;
  }

  /// Convert a sequence of OFDM symbols (time-domain) to PCM audio samples.
  /// Scales to fit within [-amplitude, +amplitude] range for 16-bit output.
  static Int16List toPcm(List<Float64List> symbols, {double amplitude = 0.8}) {
    // Concatenate all symbol samples
    int totalSamples = 0;
    for (final sym in symbols) {
      totalSamples += sym.length;
    }
    final output = Int16List(totalSamples);

    // Find peak for normalization
    double peak = 0;
    for (final sym in symbols) {
      for (final s in sym) {
        final double abs = s.abs();
        if (abs > peak) peak = abs;
      }
    }

    if (peak < 1e-10) return output;
    final double scale = amplitude * 32767.0 / peak;

    int idx = 0;
    for (final sym in symbols) {
      for (final s in sym) {
        output[idx++] = (s * scale).round().clamp(-32767, 32767);
      }
    }
    return output;
  }

  /// Convert PCM audio samples back to floating-point, normalized.
  static Float64List fromPcm(Int16List pcm) {
    final output = Float64List(pcm.length);
    for (int i = 0; i < pcm.length; i++) {
      output[i] = pcm[i] / 32767.0;
    }
    return output;
  }

  // --- FFT implementation (radix-2 Cooley-Tukey) ---

  /// Public DFT-spread precoding for an arbitrary-length symbol vector.
  /// Exposed so the receiver can reconstruct the transmitted subcarrier values
  /// X[k] from known data symbols (for decision-directed channel estimation).
  List<Complex> dftSpread(List<Complex> symbols, {bool inverse = false}) {
    return _dftSpread(symbols, inverse: inverse);
  }

  /// DFT-spread precoding (unitary, arbitrary size).
  ///
  /// Forward (inverse=false): X[k] = (1/√M) Σ_m d[m] e^(-j2πkm/M)
  /// Inverse (inverse=true):  d[m] = (1/√M) Σ_k X[k] e^(+j2πkm/M)
  ///
  /// M = params.numDataCarriers is small (≈9), so a direct O(M²) DFT is exact
  /// and cheap. The 1/√M scaling makes the transform unitary, preserving signal
  /// power so downstream noise-variance/LLR estimates stay consistent.
  static List<Complex> _dftSpread(List<Complex> input, {required bool inverse}) {
    final int m = input.length;
    if (m == 0) return const [];
    final double sign = inverse ? 1.0 : -1.0;
    final double norm = 1.0 / math.sqrt(m);
    final out = List<Complex>.filled(m, const Complex(0, 0));

    for (int k = 0; k < m; k++) {
      double re = 0.0;
      double im = 0.0;
      for (int n = 0; n < m; n++) {
        final double angle = sign * 2 * math.pi * k * n / m;
        final double c = math.cos(angle);
        final double s = math.sin(angle);
        // (input[n].i + j input[n].q) * (c + j s)
        re += input[n].i * c - input[n].q * s;
        im += input[n].i * s + input[n].q * c;
      }
      out[k] = Complex(re * norm, im * norm);
    }
    return out;
  }

  /// Public FFT access for testing.
  static List<Complex> fftPublic(List<Complex> input, {required bool inverse}) {
    return _fft(input, inverse: inverse);
  }

  /// In-place FFT (or IFFT if inverse=true).
  /// Input length must be a power of 2.
  static List<Complex> _fft(List<Complex> input, {required bool inverse}) {
    final int n = input.length;
    if (n == 1) return [input[0]];
    if (n & (n - 1) != 0) {
      throw ArgumentError('FFT size must be a power of 2, got $n');
    }

    // Bit-reversal permutation
    final result = List<Complex>.from(input);
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final temp = result[i];
        result[i] = result[j];
        result[j] = temp;
      }
    }

    // Butterfly stages
    final double sign = inverse ? 1.0 : -1.0;
    for (int len = 2; len <= n; len <<= 1) {
      final double angle = sign * 2 * math.pi / len;
      final Complex wn = Complex(math.cos(angle), math.sin(angle));
      for (int i = 0; i < n; i += len) {
        Complex w = const Complex(1.0, 0.0);
        for (int k = 0; k < len ~/ 2; k++) {
          final Complex t = w * result[i + k + len ~/ 2];
          final Complex u = result[i + k];
          result[i + k] = u + t;
          result[i + k + len ~/ 2] = u - t;
          w = w * wn;
        }
      }
    }

    // Normalize for IFFT
    if (inverse) {
      for (int i = 0; i < n; i++) {
        result[i] = result[i] / n.toDouble();
      }
    }

    return result;
  }
}
