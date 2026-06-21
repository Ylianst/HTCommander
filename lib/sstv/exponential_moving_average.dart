/*
Exponential Moving Average
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;

class ExponentialMovingAverage {
  double _alpha = 1;
  double _prev = 0;

  double avg(double input) => _prev = _prev * (1 - _alpha) + _alpha * input;

  void alpha(double alpha, [int? order]) {
    if (order != null) {
      alpha = math.pow(alpha, 1.0 / order).toDouble();
    }
    _alpha = alpha;
  }

  void cutoff(num freq, num rate, [int order = 1]) {
    final x = math.cos(2 * math.pi * freq / rate);
    alpha(x - 1 + math.sqrt(x * (x - 4) + 3), order);
  }

  void reset() {
    _prev = 0;
  }
}
