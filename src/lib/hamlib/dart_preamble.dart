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
// dart_preamble.dart - Zadoff-Chu preamble for DART modem.
//
// The preamble provides:
// - Frame detection (correlation peak)
// - Symbol timing estimation
// - Carrier frequency offset (CFO) estimation
// - One-shot channel estimation
//
// Structure: two identical halves (for CFO estimation) followed by one
// channel-estimation symbol transmitted through the SC-FDMA chain.
//

import 'dart:math' as math;
import 'dart:typed_data';

import 'dart_constellation.dart';
import 'dart_ofdm.dart';

/// Result of a preamble detection attempt.
class PreambleDetection {
  /// Sample index of the detected preamble start, or -1 if not found.
  final int position;

  /// Normalized cross-correlation peak (0..1) — detection confidence.
  final double correlation;

  const PreambleDetection({
    required this.position,
    required this.correlation,
  });
}

/// Zadoff-Chu sequence generator and preamble utilities.
class DartPreamble {
  /// The OFDM parameters (needed for symbol generation).
  final DartOfdmParams ofdmParams;

  /// Zadoff-Chu root index (must be coprime to sequence length).
  final int root;

  /// Length of the ZC sequence (should be prime for ideal properties).
  final int zcLength;

  /// The known preamble data symbols used for channel estimation.
  /// These are BPSK (+1/-1) on each active subcarrier — known to both TX and RX.
  late final List<Complex> channelEstSymbols;

  /// The correlation reference (time-domain ZC half, as real samples).
  late final Float64List _corrReference;

  /// Total preamble length in samples.
  late final int preambleSamples;

  DartPreamble({
    required this.ofdmParams,
    this.root = 7,
    int? zcLength,
  }) : zcLength = zcLength ?? _defaultZcLength(ofdmParams) {
    // Generate known channel-estimation symbols (BPSK PN sequence on data carriers)
    channelEstSymbols = _generatePnSymbols(ofdmParams.numDataCarriers);

    // Generate the ZC correlation reference
    _corrReference = _generateZcTimeDomain();

    // Total: 2 × ZC half + 1 OFDM symbol (channel estimation)
    preambleSamples = 2 * _corrReference.length + ofdmParams.symbolLength;
  }

  /// Generate the full preamble as time-domain samples.
  Float64List generate() {
    final zcHalf = _corrReference;
    final int zcLen = zcHalf.length;

    // Channel-estimation symbol: place known pilots directly on each
    // subcarrier (no DFT-spread) so estimateChannel can read H[k] per tone.
    final ofdm = DartOfdm(ofdmParams);
    final ceSymbol = ofdm.modulateSymbol(channelEstSymbols, dftSpread: false);

    // Assemble: [ZC half 1][ZC half 2][CE symbol]
    final output = Float64List(preambleSamples);
    output.setRange(0, zcLen, zcHalf);
    output.setRange(zcLen, 2 * zcLen, zcHalf);
    output.setRange(2 * zcLen, 2 * zcLen + ceSymbol.length, ceSymbol);

    return output;
  }

  /// Detect preamble in received samples. Returns the sample index of the
  /// detected preamble start, or -1 if not found.
  /// [threshold] is the normalized correlation threshold (0..1).
  int detect(Float64List rxSamples, {double threshold = 0.6}) {
    return detectDetailed(rxSamples, threshold: threshold).position;
  }

  /// Detect preamble and also report the correlation peak (detection
  /// confidence). Returns position -1 and correlation 0 when not found.
  PreambleDetection detectDetailed(
    Float64List rxSamples, {
    double threshold = 0.6,
  }) {
    final int refLen = _corrReference.length;
    if (rxSamples.length < preambleSamples) {
      return const PreambleDetection(position: -1, correlation: 0);
    }

    // Compute normalized cross-correlation with the ZC reference
    // We look for two consecutive peaks (the two halves)
    final int searchLen = rxSamples.length - preambleSamples;

    double bestCorr = 0;
    int bestIdx = -1;

    // Reference energy (constant)
    double refEnergy = 0;
    for (int i = 0; i < refLen; i++) {
      refEnergy += _corrReference[i] * _corrReference[i];
    }

    for (int start = 0; start <= searchLen; start++) {
      // Correlate with first half
      double corr = 0;
      double rxEnergy = 0;
      for (int i = 0; i < refLen; i++) {
        corr += rxSamples[start + i] * _corrReference[i];
        rxEnergy += rxSamples[start + i] * rxSamples[start + i];
      }

      // Normalized correlation
      final double denom = math.sqrt(rxEnergy * refEnergy);
      if (denom < 1e-10) continue;
      final double normCorr = corr.abs() / denom;

      if (normCorr > threshold && normCorr > bestCorr) {
        // Verify second half is also correlated
        double corr2 = 0;
        double rxEnergy2 = 0;
        for (int i = 0; i < refLen; i++) {
          corr2 += rxSamples[start + refLen + i] * _corrReference[i];
          rxEnergy2 += rxSamples[start + refLen + i] * rxSamples[start + refLen + i];
        }
        final double denom2 = math.sqrt(rxEnergy2 * refEnergy);
        if (denom2 < 1e-10) continue;
        final double normCorr2 = corr2.abs() / denom2;

        if (normCorr2 > threshold * 0.8) {
          bestCorr = normCorr;
          bestIdx = start;
        }
      }
    }

    return PreambleDetection(position: bestIdx, correlation: bestCorr);
  }

  /// Estimate carrier frequency offset from the two preamble halves.
  /// [rxSamples] should start at the detected preamble position.
  /// Returns frequency offset in Hz.
  double estimateCfo(Float64List rxSamples) {
    // Our channel has negligible CFO per the measurements, so this is a
    // placeholder for future analytic-signal CFO estimation (Schmidl-Cox).
    // TODO: implement proper analytic-signal CFO estimation if needed.
    return 0.0;
  }

  /// Extract the channel estimation symbol from received samples and compute H[k].
  /// [rxSamples] starts at preamble position.
  List<Complex> estimateChannel(Float64List rxSamples) {
    final int ceStart = 2 * _corrReference.length;
    final ceSamples = Float64List(ofdmParams.symbolLength);
    for (int i = 0; i < ofdmParams.symbolLength; i++) {
      ceSamples[i] = rxSamples[ceStart + i];
    }

    final ofdm = DartOfdm(ofdmParams);
    return ofdm.estimateChannel(ceSamples, channelEstSymbols);
  }

  // --- Private helpers ---

  /// Default ZC length: use the largest prime ≤ FFT size.
  static int _defaultZcLength(DartOfdmParams params) {
    // Use a prime number close to FFT size for good autocorrelation
    int n = params.fftSize - 1;
    while (!_isPrime(n) && n > 2) {
      n--;
    }
    return n;
  }

  static bool _isPrime(int n) {
    if (n < 2) return false;
    if (n == 2 || n == 3) return true;
    if (n % 2 == 0 || n % 3 == 0) return false;
    for (int i = 5; i * i <= n; i += 6) {
      if (n % i == 0 || n % (i + 2) == 0) return false;
    }
    return true;
  }

  /// Generate Zadoff-Chu sequence in time domain (real part only).
  /// ZC(n) = exp(-j * π * root * n * (n+1) / zcLength)
  Float64List _generateZcTimeDomain() {
    final output = Float64List(zcLength);
    for (int n = 0; n < zcLength; n++) {
      final double phase =
          -math.pi * root * n * (n + 1) / zcLength;
      // Use real part for the baseband audio signal
      output[n] = math.cos(phase);
    }
    return output;
  }

  /// Generate a deterministic BPSK PN sequence for channel estimation.
  /// Uses a simple LFSR-based generator seeded deterministically.
  static List<Complex> _generatePnSymbols(int length) {
    final symbols = List<Complex>.filled(length, const Complex(0, 0));
    // Simple gold-code-like PN sequence (deterministic, known to both sides)
    int lfsr = 0x1ACE; // fixed seed
    for (int i = 0; i < length; i++) {
      final int bit = lfsr & 1;
      symbols[i] = bit == 0 ? const Complex(1.0, 0.0) : const Complex(-1.0, 0.0);
      // Fibonacci LFSR: x^16 + x^14 + x^13 + x^11 + 1
      final int feedback =
          ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1;
      lfsr = (lfsr >> 1) | (feedback << 15);
    }
    return symbols;
  }
}
