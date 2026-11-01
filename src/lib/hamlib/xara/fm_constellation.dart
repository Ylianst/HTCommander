/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
FM constellations (BPSK .. 256QAM); QAM points are rounded to f32 as VARA does.
*/

import 'dart:math' as math;

import 'complex.dart';
import 'numeric.dart';

int _ginv(int n) {
  for (int s = 1; s < 8; s <<= 1) {
    n ^= n >> s;
  }
  return n;
}

double _amp(double p, double l, int x) => toF32(p * x / (l * math.sqrt2));

List<Cx> _square(int bps, double p, double l) {
  final int h = bps ~/ 2;
  final int m = (1 << h) - 1;
  int c(int g) => 2 * _ginv(g) - m;
  return <Cx>[for (int v = 0; v < 1 << bps; v++) Cx(_amp(p, l, c(v >> h)), _amp(p, l, c(v & m)))];
}

Cx _signed(int v, int si, int sq, int x, int y, double p, double l) {
  final int sx = (v & si) != 0 ? -x : x;
  final int sy = (v & sq) != 0 ? -y : y;
  return Cx(_amp(p, l, sx), _amp(p, l, sy));
}

int _bit(int v, int b) => (v >> b) & 1;

final List<List<Cx>> _tables = () {
  final double a = toF32(math.sqrt1_2);
  const List<(int, int)> q8 = <(int, int)>[(-1, -1), (-1, 0), (0, -1), (-1, 1), (1, 0), (1, 1), (1, -1), (0, 1)];
  const List<(int, int)> q32 = <(int, int)>[(1, 1), (3, 1), (3, 5), (5, 1), (1, 3), (3, 3), (1, 5), (5, 3)];
  Cx p128(int v) {
    int x = 2 * _ginv(_bit(v, 3) << 2 | _bit(v, 2) << 1 | _bit(v, 0)) + 1;
    int y = 2 * _ginv(_bit(v, 4) << 1 | _bit(v, 1)) + 1;
    if (x >= 13) {
      if (y <= 3) {
        (x, y) = (x - 8, y + 8);
      } else {
        (x, y) = (16 - x, 16 - y);
      }
    }
    return _signed(v, 64, 32, x, y, 1.8, 11.0);
  }

  Cx p256(int v) {
    final int x = 2 * _ginv(_bit(v, 4) << 2 | _bit(v, 2) << 1 | _bit(v, 0)) + 1;
    final int y = 2 * _ginv(_bit(v, 5) << 2 | _bit(v, 3) << 1 | _bit(v, 1)) + 1;
    return _signed(v, 128, 64, x, y, 1.7, 15.0);
  }

  return <List<Cx>>[
    const <Cx>[],
    const <Cx>[Cx(1.0, 0.0), Cx(-1.0, 0.0)],
    const <Cx>[Cx(1.0, 0.0), Cx(0.0, 1.0), Cx(0.0, -1.0), Cx(-1.0, 0.0)],
    <Cx>[for (final (int i, int q) in q8) Cx(a * i, a * q)],
    _square(4, 1.1, 3.0),
    <Cx>[for (int v = 0; v < 32; v++) _signed(v, 16, 8, q32[v & 7].$1, q32[v & 7].$2, 1.5, 5.0)],
    _square(6, 1.6, 7.0),
    <Cx>[for (int v = 0; v < 128; v++) p128(v)],
    <Cx>[for (int v = 0; v < 256; v++) p256(v)],
  ];
}();

List<Cx> fmConstellation(int bps) => bps >= 0 && bps < _tables.length ? _tables[bps] : const <Cx>[];
