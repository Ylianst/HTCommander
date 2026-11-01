/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Differential detection and pilot-interpolating equaliser helpers.
*/

import 'complex.dart';
import 'demap.dart';

/// Differential products `c[r] * conj(c[r-1]) * rot` for rows 1..rows.
List<List<Cx>> eqDiff(List<List<Cx>> c, int rows, int nb, Cx rot) => <List<Cx>>[
      for (int r = 1; r < rows; r++) <Cx>[for (int b = 0; b < nb; b++) c[r][b] * c[r - 1][b].conj() * rot],
    ];

/// Normalises [d] to unit mean magnitude and returns the marker noise variance.
double dpskNvar(List<List<Cx>> d, double eps, Iterable<(int, int)> marks) {
  int n = 0;
  double sum = 0.0;
  for (final List<Cx> row in d) {
    for (final Cx v in row) {
      sum += v.norm;
      n++;
    }
  }
  final double g = sum / n + eps;
  for (final List<Cx> row in d) {
    for (int i = 0; i < row.length; i++) {
      row[i] = row[i].div(g);
    }
  }
  double mk = 0.0;
  int count = 0;
  for (final (int i, int j) in marks) {
    final Cx v = d[i][j];
    mk += Cx(v.re - v.norm, v.im).normSqr;
    count++;
  }
  final double nv = mk / count;
  return nv.isNaN || nv < 1e-3 ? 1e-3 : nv;
}

void derotate(List<List<Cx>> c, double thd) {
  for (int row = 0; row < c.length; row++) {
    final Cx r = Cx.polar(1.0, -thd * row);
    final List<Cx> cr = c[row];
    for (int i = 0; i < cr.length; i++) {
      cr[i] = cr[i] * r;
    }
  }
}

class Equaliser {
  final List<Cx> _zs = <Cx>[];
  final List<double> _ws = <double>[];

  List<Cx> get symbols => _zs;

  void push(Cx y, double x, List<int> xs, List<Cx> ys) {
    final Cx h = _interp(x, xs, ys);
    final Cx z = y.divC(h);
    _zs.add(z.re.isFinite && z.im.isFinite ? z : Cx.zero);
    _ws.add(h.normSqr);
  }

  double llrs(List<Cx> cst, double floor, List<double> llr) {
    final int n = _zs.isEmpty ? 1 : _zs.length;
    final double mw = _ws.fold<double>(0.0, (a, b) => a + b) / (_ws.isEmpty ? 1 : _ws.length) + 1e-30;
    final List<double> wn = _ws.map((w) => w / mw).toList();
    final Demapper dm = demapper(cst);
    double err = 0.0;
    for (int i = 0; i < _zs.length; i++) {
      err += wn[i] * dm.nearest(_zs[i]).$2;
    }
    double nvar = err / n;
    if (nvar.isNaN || nvar < floor) nvar = floor;
    dm.softBits(_zs, nvar, wn, llr);
    return nvar;
  }
}

Cx _interp(double x, List<int> xs, List<Cx> ys) {
  if (xs.isEmpty) return Cx.one;
  if (x <= xs.first) return ys.first;
  if (x >= xs.last) return ys.last;
  int lo = 0, hi = xs.length;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (xs[mid] <= x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  final int i = lo - 1;
  final double x0 = xs[i].toDouble(), x1 = xs[i + 1].toDouble();
  final double f = (x - x0) / (x1 - x0);
  return ys[i].scale(1.0 - f) + ys[i + 1].scale(f);
}
