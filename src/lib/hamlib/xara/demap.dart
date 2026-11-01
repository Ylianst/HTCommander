/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Max-log soft demapping. Positive LLR means bit 0.
*/

import 'complex.dart';

const int _candCount = 4;

int _trailingZeros(int v) {
  if (v == 0) return 64;
  int n = 0;
  while ((v & 1) == 0) {
    v >>= 1;
    n++;
  }
  return n;
}

double _d2(Cx a, Cx b) {
  final double dr = a.re - b.re, di = a.im - b.im;
  return dr * dr + di * di;
}

class Demapper {
  final List<Cx> cst;
  final int bps;
  final List<List<int>> _cand;

  Demapper._(this.cst, this.bps, this._cand);

  factory Demapper(List<Cx> cst) {
    final int bps = _trailingZeros(cst.length);
    final List<List<int>> cand = <List<int>>[];
    for (int h = 0; h < cst.length; h++) {
      for (int b = 0; b < bps; b++) {
        final int sh = bps - 1 - b;
        final List<int> c = <int>[
          for (int j = 0; j < cst.length; j++)
            if (((j ^ h) >> sh) & 1 == 1) j,
        ];
        // Stable by distance, as upstream's sort_by: ties keep index order.
        c.sort((x, y) {
          final int r = _d2(cst[x], cst[h]).compareTo(_d2(cst[y], cst[h]));
          return r != 0 ? r : x.compareTo(y);
        });
        cand.add(List<int>.generate(_candCount, (i) => c[i < c.length - 1 ? i : c.length - 1]));
      }
    }
    return Demapper._(List<Cx>.unmodifiable(cst), bps, cand);
  }

  (int, double) nearest(Cx z) {
    int bi = 0;
    double bd = double.infinity;
    for (int i = 0; i < cst.length; i++) {
      final double d = _d2(z, cst[i]);
      if (d < bd) {
        bi = i;
        bd = d;
      }
    }
    return (bi, bd);
  }

  void softBits(List<Cx> z, double nvar, List<double>? w, List<double> out) {
    for (int i = 0; i < z.length; i++) {
      final Cx zi = z[i];
      final (int h, double dh) = nearest(zi);
      final double s = (w == null ? 1.0 : w[i]) / nvar;
      for (int b = 0; b < bps; b++) {
        double dalt = double.infinity;
        for (final int j in _cand[h * bps + b]) {
          final double d = _d2(zi, cst[j]);
          if (d < dalt) dalt = d;
        }
        final double v = (dalt - dh) * s;
        out.add(((h >> (bps - 1 - b)) & 1) == 0 ? v : -v);
      }
    }
  }
}

final List<Demapper> _cache = <Demapper>[];

bool _same(List<Cx> a, List<Cx> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Demapper demapper(List<Cx> cst) {
  for (final Demapper d in _cache) {
    if (_same(d.cst, cst)) return d;
  }
  final Demapper d = Demapper(cst);
  _cache.add(d);
  return d;
}

void softBits(List<Cx> z, List<Cx> cst, double nvar, List<double> out) {
  if (cst.length > 2 * _candCount) {
    demapper(cst).softBits(z, nvar, null, out);
    return;
  }
  final int bps = _trailingZeros(cst.length);
  final List<double> d = List<double>.filled(cst.length, 0.0);
  for (final Cx zi in z) {
    for (int i = 0; i < cst.length; i++) {
      d[i] = -_d2(zi, cst[i]) / nvar;
    }
    energyLlrs(d, bps, out);
  }
}

void energyLlrs(List<double> m, int bps, List<double> out) {
  for (int k = 0; k < bps; k++) {
    final int sh = bps - 1 - k;
    double m0 = double.negativeInfinity, m1 = double.negativeInfinity;
    for (int idx = 0; idx < m.length; idx++) {
      final double v = m[idx];
      if (((idx >> sh) & 1) == 0) {
        m0 = _fmax(m0, v);
      } else {
        m1 = _fmax(m1, v);
      }
    }
    out.add(m0 - m1);
  }
}

/// Rust f64::max: NaN is ignored in favour of the other operand.
double _fmax(double a, double b) {
  if (a.isNaN) return b;
  if (b.isNaN) return a;
  return a > b ? a : b;
}
