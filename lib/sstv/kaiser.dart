/*
Kaiser window
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;

class Kaiser {
  // i0(x) converges for x inside -3*Pi:3*Pi in less than 35 iterations
  final List<double> _summands = List<double>.filled(35, 0);

  static double _square(double value) => value * value;

  /*
  i0() implements the zero-th order modified Bessel function of the first kind:
  https://en.wikipedia.org/wiki/Bessel_function#Modified_Bessel_functions:_I%CE%B1,_K%CE%B1
  */
  double _i0(double x) {
    _summands[0] = 1;
    double val = 1;
    for (int n = 1; n < _summands.length; ++n) {
      val *= x / (2 * n);
      _summands[n] = _square(val);
    }
    _summands.sort();
    double sum = 0;
    for (int n = _summands.length - 1; n >= 0; --n) {
      sum += _summands[n];
    }
    return sum;
  }

  double window(double a, int n, int N) =>
      _i0(math.pi * a * math.sqrt(1 - _square((2.0 * n) / (N - 1) - 1))) /
      _i0(math.pi * a);
}
