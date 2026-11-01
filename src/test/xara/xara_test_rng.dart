/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Test helpers ported from XARA's `tests/common` (xorshift* RNG, random frames).
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:htcommander/hamlib/xara/crc.dart';

class TestRng {
  int _s;

  TestRng(int seed) : _s = (seed * -7046029254386353131) | 1;

  int nextU64() {
    _s ^= _s >>> 12;
    _s ^= _s << 25;
    _s ^= _s >>> 27;
    return _s * 0x2545F4914F6CDD1D;
  }

  double uniform() => (nextU64() >>> 11) / 9007199254740992.0;

  int below(int n) => (uniform() * n).toInt();

  double gauss() {
    final double u = math.max(uniform(), 1e-300);
    final double v = uniform();
    return math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
  }

  Uint8List bytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => nextU64() & 0xFF));
}

Uint8List randomFrame(TestRng rng, int nbytes) {
  final Uint8List f = Uint8List(nbytes)..setAll(0, rng.bytes(nbytes - 2));
  final int crc = crc16Genibus(f, 0, nbytes - 2);
  f[nbytes - 2] = crc >> 8;
  f[nbytes - 1] = crc & 0xFF;
  return f;
}
