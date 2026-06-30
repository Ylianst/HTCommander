/*
Frequency Modulation
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;
import 'complex.dart';

class FrequencyModulation {
  double _prev = 0;
  final double _scale;
  static const double _pi = math.pi;
  static const double _twoPi = 2 * math.pi;

  FrequencyModulation(double bandwidth, double sampleRate)
    : _scale = sampleRate / (bandwidth * math.pi);

  double _wrap(double value) {
    if (value < -_pi) return value + _twoPi;
    if (value > _pi) return value - _twoPi;
    return value;
  }

  double demod(Complex input) {
    final phase = input.arg();
    final delta = _wrap(phase - _prev);
    _prev = phase;
    return _scale * delta;
  }
}
