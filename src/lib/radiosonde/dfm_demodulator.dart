/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Demodulator for Graw DFM radiosondes from FM-discriminator audio.

DFM sondes transmit 2-FSK, Manchester-2 encoded at 2500 baud (so each data bit
spans two Manchester symbols; the effective data rate is 1250 bps). After FM
demodulation the two tones become two bipolar levels, i.e. the audio is a
Manchester-coded bipolar NRZ waveform. This class recovers 280-bit frames from
that waveform by:

  1. removing DC and normalising,
  2. locating the fixed 0x45CF frame header with a symbol-block matched filter
     (also recovering the signal polarity),
  3. refining the symbol rate from the spacing between successive headers,
  4. integrate-and-dump slicing each symbol and Manchester-decoding to bits.

The 280 hard bits are handed to [DfmDecoder] for framing/ECC/parsing.
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Recovers DFM 280-bit frames from FM-demodulated audio.
class DfmDemodulator {
  DfmDemodulator(this.sampleRate);

  final int sampleRate;

  static const int _baudRate = 2500; // Manchester symbol rate
  static const int _headerSymbols = 32; // 32 Manchester symbols = 16 bits
  static const int _frameSymbols = 560; // 280 data bits * 2 symbols
  static const int _frameBits = 280;
  static const int _headerValue = 0x45CF;

  // Raw Manchester header symbols ('1' -> +1, '0' -> -1).
  static const String _rawHeader = '10011010100110010101101001010101';

  /// Demodulates [pcm] (16-bit signed mono) and returns the recovered 280-bit
  /// frames in time order. Frame integrity (header/ECC) is validated here only
  /// to the extent of the 16-bit sync word; deeper checks are the decoder's.
  List<List<int>> demodulate(Int16List pcm) {
    final n = pcm.length;
    final nominalSps = sampleRate / _baudRate;
    if (n < (_frameSymbols * nominalSps).ceil()) return const [];

    // 1. DC-block (remove mean) into doubles + prefix sums for O(1) block sums.
    final x = Float64List(n);
    double mean = 0;
    for (int i = 0; i < n; i++) {
      mean += pcm[i];
    }
    mean /= n;
    double sumSq = 0;
    for (int i = 0; i < n; i++) {
      final v = pcm[i] - mean;
      x[i] = v;
      sumSq += v * v;
    }
    final std = sumSq > 0 ? math.sqrt(sumSq / n) : 1.0;
    if (std <= 0) return const [];

    final prefix = Float64List(n + 1);
    for (int i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + x[i];
    }

    // Header sign pattern.
    final sign = Float64List(_headerSymbols);
    for (int j = 0; j < _headerSymbols; j++) {
      sign[j] = _rawHeader.codeUnitAt(j) == 0x31 ? 1.0 : -1.0;
    }

    // 2. Correlate the header block matched filter across the signal.
    final sps = nominalSps;
    final hdrSpan = (_headerSymbols * sps).ceil();
    final lastOffset = n - hdrSpan - 1;
    if (lastOffset <= 0) return const [];

    final score = Float64List(lastOffset);
    final norm = 1.0 / (_headerSymbols * sps * std);
    for (int off = 0; off < lastOffset; off++) {
      double acc = 0;
      for (int j = 0; j < _headerSymbols; j++) {
        final s = (off + j * sps).round();
        final e = (off + (j + 1) * sps).round();
        acc += sign[j] * (prefix[e] - prefix[s]);
      }
      score[off] = acc * norm;
    }

    // 3. Pick header peaks (local maxima of |score| above a threshold).
    const double thr = 0.35;
    final int minGap = (_frameSymbols * sps * 0.5).round();
    final peaks = <int>[];
    final peakPol = <int>[];
    final window = (sps * 2).round();
    for (int i = 1; i < lastOffset - 1; i++) {
      final a = score[i].abs();
      if (a < thr) continue;
      // Local maximum within +/- window.
      bool isMax = true;
      final lo = i - window < 0 ? 0 : i - window;
      final hi = i + window >= lastOffset ? lastOffset - 1 : i + window;
      for (int k = lo; k <= hi; k++) {
        if (score[k].abs() > a) {
          isMax = false;
          break;
        }
      }
      if (!isMax) continue;
      if (peaks.isNotEmpty && (i - peaks.last) < minGap) {
        // Keep the stronger of two close peaks.
        if (a > score[peaks.last].abs()) {
          peaks[peaks.length - 1] = i;
          peakPol[peakPol.length - 1] = score[i] >= 0 ? 1 : -1;
        }
        continue;
      }
      peaks.add(i);
      peakPol.add(score[i] >= 0 ? 1 : -1);
    }
    if (peaks.isEmpty) return const [];

    // 4. Refine symbol rate from median header spacing.
    double refinedSps = sps;
    final diffs = <int>[];
    final targetFrame = _frameSymbols * sps;
    for (int i = 1; i < peaks.length; i++) {
      final d = peaks[i] - peaks[i - 1];
      if (d > targetFrame * 0.8 && d < targetFrame * 1.2) diffs.add(d);
    }
    if (diffs.isNotEmpty) {
      diffs.sort();
      final medFrame = diffs[diffs.length ~/ 2].toDouble();
      refinedSps = medFrame / _frameSymbols;
    }

    // 5. Slice each detected frame into 280 bits.
    final frames = <List<int>>[];
    for (int p = 0; p < peaks.length; p++) {
      final frame = _sliceFrame(prefix, n, peaks[p], refinedSps, peakPol[p]);
      if (frame != null) frames.add(frame);
    }
    return frames;
  }

  // Integrate-and-dump 560 symbols from [p0], Manchester-decode to 280 bits.
  // Returns null unless the recovered 16-bit sync word matches the header.
  List<int>? _sliceFrame(
    Float64List prefix,
    int n,
    int p0,
    double sps,
    int pol,
  ) {
    final syms = Float64List(_frameSymbols);
    for (int j = 0; j < _frameSymbols; j++) {
      final s = (p0 + j * sps).round();
      final e = (p0 + (j + 1) * sps).round();
      if (s < 0 || e > n || e <= s) return null;
      syms[j] = (prefix[e] - prefix[s]) / (e - s);
    }
    final bits = List<int>.filled(_frameBits, 0);
    for (int i = 0; i < _frameBits; i++) {
      final d = pol * (syms[2 * i + 1] - syms[2 * i]);
      bits[i] = d >= 0 ? 1 : 0;
    }
    // Validate the 16-bit sync word.
    int hdr = 0;
    for (int i = 0; i < 16; i++) {
      hdr = (hdr << 1) | bits[i];
    }
    if (hdr != _headerValue) return null;
    return bits;
  }
}
