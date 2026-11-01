/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Visual Basic compatible 24-bit Rnd generator.
*/

import 'numeric.dart';

class VbRnd {
  static const int _mask = 0xFFFFFF;
  static const int _mul = 0xFD43FD;
  static const int _inc = 0xC39EC3;
  static final int _mulInv = _inverse(_mul);
  static const int startState = 0x050000;

  int _state;

  VbRnd() : _state = startState;

  VbRnd.fromState(int state) : _state = state & _mask;

  factory VbRnd.stream(double seed) {
    final VbRnd r = VbRnd();
    r.rnd(-1.0);
    r.randomize(seed);
    return r;
  }

  static int _inverse(int m) {
    int x = m;
    for (int i = 0; i < 5; i++) {
      x = (x * ((2 - m * x) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    }
    return x & _mask;
  }

  int get state => _state;

  VbRnd copy() => VbRnd.fromState(_state);

  /// VB `Rnd(x)`; [x] is treated as an f32.
  double rnd(double x) {
    final double v = toF32(x);
    if (v < 0) {
      final int b = f32Bits(v);
      _state = (b + (b >> 24)) & _mask;
    }
    if (v != 0) advance();
    return _value;
  }

  double nextF32() {
    advance();
    return _value;
  }

  /// VB `Randomize d`.
  void randomize(double d) {
    final int hi = (f64Bits(d) >>> 32) & 0xFFFFFFFF;
    final int mid = ((hi & 0xFFFF) ^ (hi >>> 16)) & 0xFFFF;
    _state = (_state & 0xFF0000FF) | (mid << 8);
  }

  /// `(Rnd * m) as u32` computed in f32.
  int draw(int m) => asU32(toF32(nextF32() * toF32(m.toDouble())));

  int randInt(int n) => draw(n + 1);

  void seedRnd(int x) => seedRndWide(x);

  void seedRndWide(int x) {
    rnd(-1.0);
    randomize((x % 32768).toDouble());
    for (int i = 0; i <= x ~/ 32768; i++) {
      advance();
    }
  }

  void advance() {
    _state = (_state * _mul + _inc) & _mask;
  }

  void retreat() {
    _state = ((_state - _inc) * _mulInv) & _mask;
  }

  double get _value => _state / 16777216.0;
}
