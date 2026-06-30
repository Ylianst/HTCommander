/*
Numerically controlled oscillator
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;
import 'complex.dart';

class Phasor {
  final Complex _value;
  final Complex _delta;

  Phasor(double freq, double rate)
    : _value = Complex(1, 0),
      _delta = Complex(
        math.cos(2 * math.pi * freq / rate),
        math.sin(2 * math.pi * freq / rate),
      );

  Complex rotate() => _value.divS(_value.mulC(_delta).abs());
}
