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
  /// Upper frequency (Hz) of the sync chirp sweep. Capped below the data band's
  /// top edge because real radio audio paths roll off / distort toward the top
  /// of the passband; a lower cap gives a stronger over-the-air correlation
  /// peak. The data carriers and channel-estimation symbol still use the full
  /// band — only the sync chirp is narrowed.
  static const double _preambleSweepHighHz = 1900.0;

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

    // The constant-envelope ZC sequence has amplitude ~1.0, while an OFDM
    // symbol's IFFT output is much smaller. If left unscaled, the whole frame's
    // peak normalization is dominated by the ZC, leaving the OFDM data at only
    // a few percent of full scale — inaudible and destroyed by channel noise.
    // Scale the ZC halves so their RMS matches the OFDM symbol RMS, giving the
    // whole transmission a uniform amplitude. Detection is unaffected because
    // the correlator normalizes by energy.
    final double zcRms = _rms(zcHalf);
    final double ceRms = _rms(ceSymbol);
    final double zcScale = zcRms > 1e-12 ? ceRms / zcRms : 1.0;

    // Assemble: [ZC half 1][ZC half 2][CE symbol]
    final output = Float64List(preambleSamples);
    for (int i = 0; i < zcLen; i++) {
      final double v = zcHalf[i] * zcScale;
      output[i] = v;
      output[zcLen + i] = v;
    }
    output.setRange(2 * zcLen, 2 * zcLen + ceSymbol.length, ceSymbol);

    return output;
  }

  /// Root-mean-square of a sample buffer.
  static double _rms(Float64List x) {
    if (x.isEmpty) return 0;
    double s = 0;
    for (final v in x) {
      s += v * v;
    }
    return math.sqrt(s / x.length);
  }

  /// Detect preamble in received samples. Returns the sample index of the
  /// detected preamble start, or -1 if not found.
  /// [threshold] is the normalized correlation threshold (0..1).
  /// [searchStart] skips the first that-many sample positions; callers that
  /// stream audio use it to avoid re-correlating samples already checked in a
  /// previous pass (positions before it are known to contain no preamble).
  int detect(Float64List rxSamples,
      {double threshold = 0.6, int searchStart = 0}) {
    return detectDetailed(rxSamples,
            threshold: threshold, searchStart: searchStart)
        .position;
  }

  /// Detect preamble and also report the correlation peak (detection
  /// confidence). Returns position -1 and correlation 0 when not found.
  ///
  /// Returns the peak of the *earliest* preamble lobe that passes the two-half
  /// verification, not the globally strongest peak. This matters for the
  /// streaming receiver: when several frames are buffered at once (frames
  /// arriving faster than the decode throttle), the oldest frame must be
  /// decoded first. Picking the global maximum could lock onto a later frame —
  /// whose payload is not fully buffered yet — and silently drop the earlier,
  /// already-complete frame. For a single buffered frame this is identical to
  /// taking the global maximum, so the over-the-air path is unchanged.
  PreambleDetection detectDetailed(
    Float64List rxSamples, {
    double threshold = 0.6,
    int searchStart = 0,
  }) {
    final int refLen = _corrReference.length;
    if (rxSamples.length < preambleSamples) {
      return const PreambleDetection(position: -1, correlation: 0);
    }

    // Search range: last offset where both halves + CE symbol still fit.
    final int searchLen = rxSamples.length - preambleSamples;

    // Reference energy (constant).
    double refEnergy = 0;
    for (int i = 0; i < refLen; i++) {
      refEnergy += _corrReference[i] * _corrReference[i];
    }

    // Normalized correlation of the reference against the half starting at
    // [start]. Returns 0 when the window energy is negligible.
    double halfCorr(int start) {
      double corr = 0;
      double rxEnergy = 0;
      for (int i = 0; i < refLen; i++) {
        final double s = rxSamples[start + i];
        corr += s * _corrReference[i];
        rxEnergy += s * s;
      }
      final double denom = math.sqrt(rxEnergy * refEnergy);
      if (denom < 1e-10) return 0;
      return corr.abs() / denom;
    }

    int start = searchStart < 0 ? 0 : searchStart;
    // Collect the peak of every above-threshold run whose second half also
    // correlates (a genuine preamble lobe), in ascending position order.
    final List<PreambleDetection> lobes = <PreambleDetection>[];
    double bestCorr = 0;
    while (start <= searchLen) {
      final double normCorr = halfCorr(start);
      if (normCorr <= threshold) {
        start++;
        continue;
      }

      // Rising edge of a candidate lobe: walk the contiguous above-threshold
      // run and remember its peak (the true frame timing).
      double peakCorr = normCorr;
      int peakIdx = start;
      int j = start + 1;
      while (j <= searchLen) {
        final double c = halfCorr(j);
        if (c <= threshold) break;
        if (c > peakCorr) {
          peakCorr = c;
          peakIdx = j;
        }
        j++;
      }

      // Verify the second half also correlates at the lobe peak. If it does,
      // this is a genuine preamble lobe. Otherwise it was noise/a sidelobe.
      final double secondHalf = halfCorr(peakIdx + refLen);
      if (secondHalf > threshold * 0.8) {
        lobes.add(PreambleDetection(position: peakIdx, correlation: peakCorr));
        if (peakCorr > bestCorr) bestCorr = peakCorr;
      }
      start = j + 1;
    }

    if (lobes.isEmpty) {
      return const PreambleDetection(position: -1, correlation: 0);
    }

    // Return the EARLIEST lobe that is nearly as strong as the strongest one.
    // A genuine preamble correlates far higher than noise, so requiring the
    // chosen lobe to be within 75% of the best rejects spurious early noise
    // lobes (preserving the old global-maximum's robustness) while still
    // decoding buffered frames oldest-first when several genuine frames are
    // present at once (streaming FIFO).
    final double cutoff = bestCorr * 0.75;
    for (final lobe in lobes) {
      if (lobe.correlation >= cutoff) return lobe;
    }
    return lobes.first;
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

  /// Default sync-sequence length. A longer sequence gives a higher
  /// time-bandwidth product and sharper autocorrelation. 256 samples at 32 kHz
  /// is 8 ms, spanning the ~2.2 kHz usable band for a TBP of ~18.
  static int _defaultZcLength(DartOfdmParams params) {
    return 256;
  }

  /// Generate a band-limited linear chirp confined to the OFDM passband, in the
  /// time domain (real). The classic Zadoff-Chu chirp sweeps past Nyquist and
  /// near DC, so most of its energy falls outside the radio's ~300–2900 Hz audio
  /// passband and the radio's filtering destroys the correlation. A chirp that
  /// sweeps only within the passband survives the radio audio path while keeping
  /// the sharp autocorrelation needed for timing sync.
  ///
  /// The sweep is intentionally capped below the data band's upper edge: real
  /// UV-Pro captures showed the radio audio path rolls off / distorts toward the
  /// top of the band, so a chirp reaching 2600 Hz correlated at only ~0.80,
  /// while one capped at 1900 Hz reached ~0.88 over the air. The channel-
  /// estimation symbol and data carriers still use the full band — only the
  /// sync chirp is narrowed, so timing robustness improves with no loss of data
  /// frequency diversity.
  Float64List _generateZcTimeDomain() {
    final int n = zcLength;
    final output = Float64List(n);
    final double fs = ofdmParams.sampleRate.toDouble();
    final double f0 = ofdmParams.freqLow;
    // Cap the sweep at the radio's clean passband ceiling (see above).
    final double f1 = math.min(ofdmParams.freqHigh, _preambleSweepHighHz);
    final double dur = n / fs;
    final double kRate = (f1 - f0) / dur; // Hz per second
    for (int i = 0; i < n; i++) {
      final double t = i / fs;
      // Instantaneous frequency sweeps linearly f0 → f1.
      final double phase = 2 * math.pi * (f0 * t + 0.5 * kRate * t * t);
      output[i] = math.cos(phase);
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
