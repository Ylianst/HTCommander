/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Max-log BCJR turbo decoder (floating-point kernel). The windowed/segmented
schedule mirrors upstream, so decoded bits and iteration counts are identical
to the multi-threaded original even though this runs on one thread.
*/

import 'dart:typed_data';

import 'crc.dart';
import 'fec.dart';

const int _len = 1024;
const int _segments = 4;
const double _neg = -1e9;

final (List<List<int>>, List<List<bool>>) _trellis = () {
  final List<List<int>> next = List<List<int>>.generate(8, (_) => List<int>.filled(2, 0));
  final List<List<bool>> par = List<List<bool>>.generate(8, (_) => List<bool>.filled(2, false));
  for (int s = 0; s < 8; s++) {
    final int r0 = (s >> 2) & 1, r1 = (s >> 1) & 1, r2 = s & 1;
    for (int u = 0; u < 2; u++) {
      final int a = u ^ r0 ^ r1;
      par[s][u] = (a ^ r2 ^ r0) == 1;
      next[s][u] = (r1 << 2) | (r2 << 1) | a;
    }
  }
  return (next, par);
}();

final List<List<int>> trellisNext = _trellis.$1;
final List<List<bool>> trellisPar = _trellis.$2;

int _gi(int s, int u) => (u << 1) | (trellisPar[s][u] ? 1 : 0);

// Edge j (0/1) into state d comes from _edgeS[2d+j] with gamma _edgeG[2d+j].
final Int32List _edgeS = Int32List(16);
final Int32List _edgeG = Int32List(16);
final Int32List _gis = Int32List(16);
final Int32List _next = Int32List(16);
bool _tablesReady = false;

void _initTables() {
  if (_tablesReady) return;
  for (int s = 0; s < 8; s++) {
    for (int u = 0; u < 2; u++) {
      _gis[2 * s + u] = _gi(s, u);
      _next[2 * s + u] = trellisNext[s][u];
      final int n = trellisNext[s][u];
      _edgeS[2 * n + (s >> 2)] = s;
      _edgeG[2 * n + (s >> 2)] = _gi(s, u);
    }
  }
  _tablesReady = true;
}

class Split {
  final Float64List ls;
  final Float64List lp1;
  final Float64List ls2;
  final Float64List lp2;

  Split(this.ls, this.lp1, this.ls2, this.lp2);
}

int usedLen(int k, int p) => puncturedLen(k, p);

Split split(List<double> llr, List<int> perm, int p) {
  final int k = perm.length;
  final int tLen = k + 3;
  final Split s = Split(Float64List(tLen), Float64List(tLen), Float64List(tLen), Float64List(tLen));
  int i = 0;
  double next() {
    if (i >= llr.length) throw StateError('too few LLRs');
    final double v = llr[i++];
    return v.isFinite ? v : 0.0;
  }

  for (int t = 0; t < k; t++) {
    s.ls[t] = next();
    if (p == 1 || t % p == 0) s.lp1[t] = next();
    if (p == 1 || t % p == p ~/ 2) s.lp2[t] = next();
  }
  for (int t = k; t < tLen; t++) {
    s.ls[t] = next();
    s.lp1[t] = next();
    s.ls2[t] = next();
    s.lp2[t] = next();
  }
  for (int j = 0; j < k; j++) {
    s.ls2[j] = s.ls[perm[j]];
  }
  return s;
}

class Decoded {
  final Uint8List bits;
  final int iterations;

  const Decoded(this.bits, this.iterations);
}

class CrcCheck {
  final List<int> white;
  final int nbytes;

  const CrcCheck(this.white, this.nbytes);

  Uint8List bytes(List<int> bits) {
    final Uint8List out = Uint8List(nbytes);
    for (int i = 0; i < nbytes; i++) {
      int v = 0;
      for (int j = 0; j < 8; j++) {
        final int idx = 8 * i + j;
        final int w = idx < white.length ? white[idx] : 0;
        v = (v << 1) | ((bits[idx] ^ w) & 1);
      }
      out[i] = v;
    }
    return out;
  }

  bool ok(List<int> bits) => crcOk(bytes(bits));
}

class TurboDecoder {
  const TurboDecoder();

  Decoded decode(Split sp, List<int> perm, int iters, double scale, (int, CrcCheck)? early) {
    _initTables();
    return _run(scale, sp, perm, iters, early);
  }
}

double _g(int i, double g0, double g1) => switch (i) { 0 => g0, 1 => g1, 2 => -g1, _ => -g0 };

/// Forward recursion over one window: stores each step's alpha in [cells] and
/// leaves the alpha after the window in [a].
void _alpha(Float64List x, int xOff, Float64List p, int pOff, int n, Float64List a, Float64List cells,
    Float64List nb) {
  for (int t = 0; t < n; t++) {
    final int c = 8 * t;
    for (int s = 0; s < 8; s++) {
      cells[c + s] = a[s];
    }
    final double xv = x[xOff + t], pv = p[pOff + t];
    final double g0 = 0.5 * (xv + pv), g1 = 0.5 * (xv - pv);
    for (int d = 0; d < 8; d++) {
      final double va = a[_edgeS[2 * d]] + _g(_edgeG[2 * d], g0, g1);
      final double vb = a[_edgeS[2 * d + 1]] + _g(_edgeG[2 * d + 1], g0, g1);
      nb[d] = va > vb ? va : vb;
    }
    final double n0 = nb[0];
    for (int d = 0; d < 8; d++) {
      a[d] = nb[d] - n0;
    }
  }
}

/// Backward recursion over one window; writes extrinsic LLRs for its first
/// [outLen] steps to `out[outOff..]` and leaves the boundary beta in [b].
void _beta(double scale, Float64List x, int xOff, Float64List p, int pOff, int n, Float64List b,
    Float64List cells, Float64List out, int outOff, int outLen, Float64List bs, Float64List nb) {
  for (int t = n - 1; t >= 0; t--) {
    final double xv = x[xOff + t], pv = p[pOff + t];
    final double g0 = 0.5 * (xv + pv), g1 = 0.5 * (xv - pv);
    for (int s = 0; s < 8; s++) {
      bs[2 * s] = b[_next[2 * s]] + _g(_gis[2 * s], g0, g1);
      bs[2 * s + 1] = b[_next[2 * s + 1]] + _g(_gis[2 * s + 1], g0, g1);
    }
    if (t < outLen) {
      final int c = 8 * t;
      double m0 = double.negativeInfinity, m1 = double.negativeInfinity;
      for (int s = 0; s < 8; s++) {
        final double v0 = cells[c + s] + bs[2 * s];
        final double v1 = cells[c + s] + bs[2 * s + 1];
        if (v0 > m0) m0 = v0;
        if (v1 > m1) m1 = v1;
      }
      out[outOff + t] = scale * ((m0 - m1) - xv);
    }
    for (int s = 0; s < 8; s++) {
      nb[s] = bs[2 * s] > bs[2 * s + 1] ? bs[2 * s] : bs[2 * s + 1];
    }
    final double n0 = nb[0];
    for (int s = 0; s < 8; s++) {
      b[s] = nb[s] - n0;
    }
  }
}

final Float64List _term = Float64List.fromList(<double>[0.0, _neg, _neg, _neg, _neg, _neg, _neg, _neg]);

Decoded _run(double scale, Split sp, List<int> perm, int iters, (int, CrcCheck)? early) {
  final int k = perm.length;
  final int tLen = k + 3;
  final List<Float64List> ls = <Float64List>[sp.ls, sp.ls2];
  final List<Float64List> lp = <Float64List>[sp.lp1, sp.lp2];
  final int nwin = (tLen + _len - 1) ~/ _len;
  final int seg = ((nwin + _segments - 1) ~/ _segments) * _len;
  final int nseg = (tLen + seg - 1) ~/ seg;
  final Int32List inv = Int32List(k);
  for (int i = 0; i < k; i++) {
    inv[perm[i]] = i;
  }
  final List<Float64List> ext = <Float64List>[Float64List(k), Float64List(k)];
  final Float64List le21 = Float64List(k);
  final Uint8List bits = Uint8List(k);
  // pb[d][parity] holds 8 states per window; ap[d][parity] 8 per segment.
  final List<List<Float64List>> pb =
      List.generate(2, (_) => List<Float64List>.generate(2, (_) => Float64List(8 * (nwin + 1))));
  final List<List<Float64List>> ap =
      List.generate(2, (_) => List<Float64List>.generate(2, (_) => Float64List(8 * (nseg + 1))));
  final Float64List x = Float64List(seg);
  final Float64List cells = Float64List(8 * _len);
  final Float64List a = Float64List(8);
  final Float64List b = Float64List(8);
  final Float64List bs = Float64List(16);
  final Float64List nb = Float64List(8);
  int ran = 0;
  for (int it = 1; it <= iters; it++) {
    final int old = (it + 1) % 2, nw = it % 2;
    for (int d = 0; d < 2; d++) {
      final Float64List src = d == 0 ? le21 : ext[0];
      final Float64List lsd = ls[d];
      for (int i = 0; i < nseg; i++) {
        final int s0 = i * seg;
        final int s1 = (i + 1) * seg < tLen ? (i + 1) * seg : tLen;
        for (int t = s0; t < s1; t++) {
          x[t - s0] = t >= k ? lsd[t] : (d == 0 ? ls[0][t] + src[t] : ls[1][t] + src[perm[t]]);
        }
        if (i == 0) {
          a.setAll(0, _term);
        } else {
          a.setRange(0, 8, ap[d][old], 8 * i);
        }
        for (int s = s0; s < s1; s += _len) {
          final int e = s + _len < s1 ? s + _len : s1;
          _alpha(x, s - s0, lp[d], s, e - s, a, cells, nb);
          if (e == tLen) {
            b.setAll(0, _term);
          } else {
            b.setRange(0, 8, pb[d][old], 8 * (e ~/ _len));
          }
          final int kk = (k < e ? k : e) - s;
          _beta(scale, x, s - s0, lp[d], s, e - s, b, cells, ext[d], s, kk > 0 ? kk : 0, bs, nb);
          pb[d][nw].setRange(8 * (s ~/ _len), 8 * (s ~/ _len) + 8, b);
        }
        if (i + 1 < nseg) ap[d][nw].setRange(8 * (i + 1), 8 * (i + 2), a);
      }
    }
    bool changed = false;
    for (int j = 0; j < k; j++) {
      le21[j] = ext[1][inv[j]];
      final int bit = (ls[0][j] + ext[0][j]) + le21[j] < 0.0 ? 1 : 0;
      if (bit != bits[j]) changed = true;
      bits[j] = bit;
    }
    ran = it;
    if (early != null && it >= early.$1 && it < iters && !changed && early.$2.ok(bits)) break;
  }
  return Decoded(bits, ran);
}
