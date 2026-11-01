/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
OFDM symbol synthesis and data-cell mapping shared by HF and FM.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'constellation.dart';
import 'ofdm_const.dart';

export 'ofdm_const.dart';

List<double> fall(int n) =>
    <double>[for (int k = 1; k <= n; k++) 0.5 * (1.0 + math.cos((k - 0.5) * math.pi / n))];

/// Synthesises OFDM symbols. Each row holds interleaved (re, im) bins that are
/// placed starting at bin [first]; output is `2 * re(IFFT) * scale` with a
/// cyclic prefix and raised-cosine overlap between symbols.
Float64List synth(int first, List<Float64List> rows, double scale) {
  final List<double> f = fall(nwin);
  final Float64List out = Float64List(rows.length * (nfft + ncp));
  final Float64List saved = Float64List(nwin);
  final Float64List re = Float64List(nfft);
  final Float64List im = Float64List(nfft);
  final Fft ifft = Fft.plan(nfft);
  int start = 0;
  for (final Float64List row in rows) {
    re.fillRange(0, nfft, 0.0);
    im.fillRange(0, nfft, 0.0);
    final int len = row.length ~/ 2;
    for (int i = 0; i < len; i++) {
      re[first + i] = row[2 * i];
      im[first + i] = row[2 * i + 1];
    }
    ifft.transform(re, im, inverse: true);
    for (int i = 0; i < ncp; i++) {
      out[start + i] = 2.0 * re[nfft - ncp + i] * scale;
    }
    for (int i = 0; i < nfft; i++) {
      out[start + ncp + i] = 2.0 * re[i] * scale;
    }
    for (int k = 0; k < nwin; k++) {
      out[start + k] = f[nwin - 1 - k] * out[start + k] + f[k] * saved[k];
    }
    for (int k = 0; k < nwin; k++) {
      saved[k] = out[start + ncp + k];
    }
    start += nfft + ncp;
  }
  if (out.length >= nwin) {
    final int tail = out.length - nwin;
    for (int i = 0; i < nwin; i++) {
      out[tail + i] *= f[i];
    }
  }
  return out;
}

/// Data/pilot/marker cell layout of one OFDM frame.
class OfdmLayout {
  final int spf;
  final int bps;
  final int n;
  final bool qam;
  final List<Cx> cst;
  final List<List<bool>> map;

  const OfdmLayout({
    required this.spf,
    required this.bps,
    required this.n,
    required this.qam,
    required this.cst,
    required this.map,
  });

  /// Walks every cell, calling [put] with (bin index, bin, symbol row, cell).
  void cells(
    Iterable<int> bins,
    bool Function(int bin, int s) pilot,
    List<int> tx,
    void Function(int bi, int b, int r, Cx cell) put,
  ) {
    final List<int> ptr = <int>[0];
    int bi = 0;
    for (final int b in bins) {
      Cx cell = Cx.one;
      for (int s = 2; s <= spf; s++) {
        final bool marker = map[bi][s - 2];
        if (qam) {
          if (pilot(b, s)) {
            cell = Cx.one;
          } else if (marker) {
            final double nm = cell.norm;
            cell = nm > 0.0 ? cell.div(nm) : Cx.one;
          } else {
            cell = cst[takeBits(tx, ptr, bps)];
          }
        } else if (s > 2) {
          if (marker) {
            cell = cell.div(cell.norm);
          } else {
            cell = cell * cst[takeBits(tx, ptr, bps)];
          }
        }
        put(bi, b, s - 2, cell);
      }
      bi++;
    }
    if (ptr[0] != n) throw StateError('cell mapping consumed ${ptr[0]} of $n bits');
  }
}
