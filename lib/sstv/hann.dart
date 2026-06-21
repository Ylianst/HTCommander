/*
Hann window
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;

class Hann {
  static double window(int n, int N) =>
      0.5 * (1.0 - math.cos((2.0 * math.pi * n) / (N - 1)));
}
