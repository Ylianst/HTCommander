/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
HF constellations and bit gathering.
*/

import 'dart:math' as math;

import 'complex.dart';

const List<double> _qam16 = <double>[-0.7778175, -0.2592725, 0.7778175, 0.2592725];
const List<double> _qam32 = <double>[0.2121320, 0.6363961, 1.0606602];

final List<List<Cx>> _tables = () {
  const double h = math.sqrt1_2;
  final List<Cx> base = const <(int, int)>[(0, 0), (1, 0), (1, 2), (2, 0), (0, 1), (1, 1), (0, 2), (2, 1)]
      .map((p) => Cx(_qam32[p.$1], _qam32[p.$2]))
      .toList();
  return <List<Cx>>[
    const <Cx>[],
    const <Cx>[Cx(1.0, 0.0), Cx(-1.0, 0.0)],
    const <Cx>[Cx(1.0, 0.0), Cx(0.0, 1.0), Cx(0.0, -1.0), Cx(-1.0, 0.0)],
    const <Cx>[Cx(1.0, 0.0), Cx(h, h), Cx(-h, h), Cx(0.0, 1.0), Cx(h, -h), Cx(0.0, -1.0), Cx(-1.0, 0.0), Cx(-h, -h)],
    <Cx>[for (int v = 0; v < 16; v++) Cx(_qam16[v >> 2], _qam16[v & 3])],
    <Cx>[...base, ...base.map((z) => z.conj()), ...base.map((z) => -z.conj()), ...base.map((z) => -z)],
  ];
}();

List<Cx> constellation(int bps) => bps >= 0 && bps < _tables.length ? _tables[bps] : const <Cx>[];

/// Gathers [n] bits MSB-first from [tx] starting at [ptr] (missing bits are 0).
/// Returns the value; [ptr] is advanced through the returned record.
int takeBits(List<int> tx, List<int> ptr, int n) {
  int v = 0;
  int p = ptr[0];
  for (int i = 0; i < n; i++) {
    v = 2 * v + (p < tx.length ? tx[p] : 0);
    p++;
  }
  ptr[0] = p;
  return v;
}
