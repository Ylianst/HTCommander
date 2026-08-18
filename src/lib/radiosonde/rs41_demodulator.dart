/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Demodulator for Vaisala RS41 radiosondes from FM-discriminator audio.

RS41 transmits GFSK at 4800 baud, NRZ (one symbol per bit, no Manchester). After
FM demodulation the two tones become two bipolar levels. This class recovers the
320-byte dewhitened frames by locating the fixed 64-bit sync header with a
matched filter, integrate-and-dump slicing each bit, packing bytes LSB-first and
XORing the whitening mask. The frames are handed to [Rs41Decoder].
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'rs41_decoder.dart';

/// Recovers RS41 dewhitened frames from FM-demodulated audio.
class Rs41Demodulator {
  Rs41Demodulator(this.sampleRate);

  final int sampleRate;

  static const int _baudRate = 4800;
  static const int _headerBits = 64;
  static const int _frameBytes = 320; // std NDATA_LEN
  static const int _frameBits = _frameBytes * 8; // 2560

  /// Demodulates [pcm] and returns dewhitened 320-byte frames in time order.
  List<Uint8List> demodulate(Int16List pcm) {
    final n = pcm.length;
    final nominalSps = sampleRate / _baudRate;
    if (n < (_frameBits * nominalSps).ceil()) return const [];

    // DC-block + prefix sums.
    double mean = 0;
    for (int i = 0; i < n; i++) {
      mean += pcm[i];
    }
    mean /= n;
    final prefix = Float64List(n + 1);
    double sumSq = 0;
    for (int i = 0; i < n; i++) {
      final v = pcm[i] - mean;
      prefix[i + 1] = prefix[i] + v;
      sumSq += v * v;
    }
    final std = sumSq > 0 ? math.sqrt(sumSq / n) : 1.0;
    if (std <= 0) return const [];

    final sign = Float64List(_headerBits);
    for (int j = 0; j < _headerBits; j++) {
      sign[j] = rs41HeaderBits.codeUnitAt(j) == 0x31 ? 1.0 : -1.0;
    }

    final sps = nominalSps;
    final hdrSpan = (_headerBits * sps).ceil();
    final lastOffset = n - hdrSpan - 1;
    if (lastOffset <= 0) return const [];

    final score = Float64List(lastOffset);
    final norm = 1.0 / (_headerBits * sps * std);
    for (int off = 0; off < lastOffset; off++) {
      double acc = 0;
      for (int j = 0; j < _headerBits; j++) {
        final s = (off + j * sps).round();
        final e = (off + (j + 1) * sps).round();
        acc += sign[j] * (prefix[e] - prefix[s]);
      }
      score[off] = acc * norm;
    }

    const double thr = 0.4;
    final int minGap = (_frameBits * sps * 0.5).round();
    final peaks = <int>[];
    final peakPol = <int>[];
    final window = (sps * 2).round();
    for (int i = 1; i < lastOffset - 1; i++) {
      final a = score[i].abs();
      if (a < thr) continue;
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

    // Refine sps from median header spacing.
    double refinedSps = sps;
    final diffs = <int>[];
    final targetFrame = _frameBits * sps;
    for (int i = 1; i < peaks.length; i++) {
      final d = peaks[i] - peaks[i - 1];
      if (d > targetFrame * 0.8 && d < targetFrame * 1.2) diffs.add(d);
    }
    if (diffs.isNotEmpty) {
      diffs.sort();
      refinedSps = diffs[diffs.length ~/ 2] / _frameBits;
    }

    final frames = <Uint8List>[];
    for (int p = 0; p < peaks.length; p++) {
      final f = _sliceFrame(prefix, n, peaks[p], refinedSps, peakPol[p]);
      if (f != null) frames.add(f);
    }
    return frames;
  }

  // Integrate-and-dump 2560 bits, pack LSB-first, dewhiten.
  Uint8List? _sliceFrame(
    Float64List prefix,
    int n,
    int p0,
    double sps,
    int pol,
  ) {
    final frame = Uint8List(_frameBytes);
    for (int byteIdx = 0; byteIdx < _frameBytes; byteIdx++) {
      int b = 0;
      for (int bit = 0; bit < 8; bit++) {
        final j = byteIdx * 8 + bit;
        final s = (p0 + j * sps).round();
        final e = (p0 + (j + 1) * sps).round();
        if (s < 0 || e > n || e <= s) return null;
        final v = pol * (prefix[e] - prefix[s]);
        if (v >= 0) b |= 1 << bit; // LSB-first
      }
      frame[byteIdx] = b ^ rs41Mask[byteIdx % rs41Mask.length];
    }
    // Sanity: dewhitened header must match.
    for (int i = 0; i < rs41DewhitenedHeader.length; i++) {
      if (frame[i] != rs41DewhitenedHeader[i]) return null;
    }
    return frame;
  }
}
