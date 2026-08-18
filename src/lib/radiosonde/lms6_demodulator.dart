/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Demodulator for Lockheed Martin LMS6 (403 MHz) radiosondes from FM-discriminator
audio. LMS6 is 4800-baud NRZ (rate-1/2 convolutional coded). This class locates
the block via a matched filter built from the fixed sync, integrate-and-dump
slices each bit, and hands the transmitted bit stream to [Lms6Decoder].
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'convolutional.dart';
import 'lms6_decoder.dart';

/// Recovers LMS6 transmitted-bit blocks from FM-demodulated audio.
class Lms6Demodulator {
  Lms6Demodulator(this.sampleRate);

  final int sampleRate;

  static const int _baud = 4800;
  static const int _blockBits = 260 * 8 * 2; // 4160 transmitted bits

  final List<double> _header = _buildHeader();

  /// Demodulates [pcm] and returns candidate transmitted-bit blocks.
  List<List<int>> demodulate(Int16List pcm) {
    final n = pcm.length;
    final nominalSps = sampleRate / _baud;
    if (n < (_blockBits * nominalSps).ceil()) return const [];

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

    final hlen = _header.length;
    final sps = nominalSps;
    final hdrSpan = (hlen * sps).ceil();
    final lastOffset = n - hdrSpan - 1;
    if (lastOffset <= 0) return const [];

    final score = Float64List(lastOffset);
    final norm = 1.0 / (hlen * sps * std);
    for (int off = 0; off < lastOffset; off++) {
      double acc = 0;
      for (int j = 0; j < hlen; j++) {
        final s = (off + j * sps).round();
        final e = (off + (j + 1) * sps).round();
        acc += _header[j] * (prefix[e] - prefix[s]);
      }
      score[off] = acc * norm;
    }

    const double thr = 0.35;
    final int minGap = (_blockBits * sps * 0.5).round();
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

    double refinedSps = sps;
    final diffs = <int>[];
    final target = _blockBits * sps;
    for (int i = 1; i < peaks.length; i++) {
      final d = peaks[i] - peaks[i - 1];
      if (d > target * 0.8 && d < target * 1.2) diffs.add(d);
    }
    if (diffs.isNotEmpty) {
      diffs.sort();
      refinedSps = diffs[diffs.length ~/ 2] / _blockBits;
    }

    final blocks = <List<int>>[];
    for (int p = 0; p < peaks.length; p++) {
      final b = _slice(prefix, n, peaks[p], refinedSps, peakPol[p]);
      if (b != null) blocks.add(b);
    }
    return blocks;
  }

  List<int>? _slice(Float64List prefix, int n, int p0, double sps, int pol) {
    final bits = List<int>.filled(_blockBits, 0);
    for (int i = 0; i < _blockBits; i++) {
      final s = (p0 + i * sps).round();
      final e = (p0 + (i + 1) * sps).round();
      if (s < 0 || e > n || e <= s) return null;
      final v = pol * (prefix[e] - prefix[s]);
      bits[i] = v >= 0 ? 1 : 0;
    }
    return bits;
  }

  // Matched-filter chips (+1/-1) from the first 64 transmitted sync bits.
  static List<double> _buildHeader() {
    final msg = <int>[];
    for (final byte in Lms6Decoder.syncBytes) {
      for (int k = 0; k < 8; k++) {
        msg.add((byte >> k) & 1);
      }
    }
    final raw = ConvCodec.encode(msg);
    final hdr = <double>[];
    for (int i = 0; i < 64 && i < raw.length; i++) {
      final t = raw[i] ^ (i & 1); // (c0, inv(c1))
      hdr.add(t == 1 ? 1.0 : -1.0);
    }
    return hdr;
  }
}
