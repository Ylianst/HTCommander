/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Demodulator for Meteomodem M10 radiosondes from FM-discriminator audio.

M10 transmits at 9615 baud, Manchester-coded (two chips per bit) with a
differential (NRZI-style) layer on top, which makes the recovered bitstream
invariant to overall signal inversion. This class locates the frame via a
matched filter built from the fixed 0x64 0x9F sync, integrate-and-dump slices
each chip, Manchester- then differential-decodes, and packs bytes MSB-first.
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Recovers Meteomodem M10/M20 frames from FM-demodulated audio. Both share the
/// same modem (9600/9615-baud Manchester + differential); only the sync bytes,
/// frame length and chip rate differ.
class M10Demodulator {
  M10Demodulator(
    this.sampleRate, {
    this.chipRate = 9615,
    this.frameBytes = 101,
    this.sync0 = 0x64,
    this.sync1 = 0x9F,
  });

  final int sampleRate;
  final int chipRate;
  final int frameBytes;
  final int sync0;
  final int sync1;

  int get _frameBits => frameBytes * 8;
  int get _frameChips => _frameBits * 2;

  /// Demodulates [pcm] and returns candidate frames in time order.
  List<Uint8List> demodulate(Int16List pcm) {
    final n = pcm.length;
    final nominalSps = sampleRate / chipRate;
    if (n < (_frameChips * nominalSps).ceil()) return const [];

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

    final headerChips = _headerChips();
    final hlen = headerChips.length;
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
        acc += headerChips[j] * (prefix[e] - prefix[s]);
      }
      score[off] = acc * norm;
    }

    const double thr = 0.35;
    final int minGap = (_frameChips * sps * 0.5).round();
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
    final targetFrame = _frameChips * sps;
    for (int i = 1; i < peaks.length; i++) {
      final d = peaks[i] - peaks[i - 1];
      if (d > targetFrame * 0.8 && d < targetFrame * 1.2) diffs.add(d);
    }
    if (diffs.isNotEmpty) {
      diffs.sort();
      refinedSps = diffs[diffs.length ~/ 2] / _frameChips;
    }

    final frames = <Uint8List>[];
    for (int p = 0; p < peaks.length; p++) {
      final f = _sliceFrame(prefix, n, peaks[p], refinedSps, peakPol[p]);
      if (f != null) frames.add(f);
    }
    return frames;
  }

  Uint8List? _sliceFrame(
    Float64List prefix,
    int n,
    int p0,
    double sps,
    int pol,
  ) {
    final raw = List<int>.filled(_frameBits, 0);
    for (int i = 0; i < _frameBits; i++) {
      final s1 = (p0 + (2 * i) * sps).round();
      final m = (p0 + (2 * i + 1) * sps).round();
      final e = (p0 + (2 * i + 2) * sps).round();
      if (s1 < 0 || e > n || m <= s1 || e <= m) return null;
      final c1 = (prefix[m] - prefix[s1]) / (m - s1);
      final c2 = (prefix[e] - prefix[m]) / (e - m);
      raw[i] = (pol * (c2 - c1)) >= 0 ? 1 : 0;
    }
    // Differential decode (invariant to inversion), then pack MSB-first.
    final frame = Uint8List(frameBytes);
    int prev = 0;
    final out = List<int>.filled(_frameBits, 0);
    for (int i = 0; i < _frameBits; i++) {
      out[i] = raw[i] == prev ? 1 : 0;
      prev = raw[i];
    }
    for (int byteIdx = 0; byteIdx < frameBytes; byteIdx++) {
      int b = 0;
      for (int k = 0; k < 8; k++) {
        b = (b << 1) | out[byteIdx * 8 + k];
      }
      frame[byteIdx] = b;
    }
    if (frame[0] != sync0 || frame[1] != sync1) return null;
    return frame;
  }

  // Chip pattern (+1/-1) for the sync bytes: MSB-first bits -> differential
  // encode -> Manchester (raw 1 => [-1,+1], raw 0 => [+1,-1]).
  List<double> _headerChips() {
    final bits = <int>[];
    for (final byte in [sync0, sync1]) {
      for (int k = 7; k >= 0; k--) {
        bits.add((byte >> k) & 1);
      }
    }
    int prev = 0;
    final chips = <double>[];
    for (final outBit in bits) {
      final r = outBit == 1 ? prev : 1 - prev;
      prev = r;
      if (r == 1) {
        chips
          ..add(-1)
          ..add(1);
      } else {
        chips
          ..add(1)
          ..add(-1);
      }
    }
    return chips;
  }
}
