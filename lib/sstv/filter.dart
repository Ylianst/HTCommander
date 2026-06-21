/*
FIR Filter
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;

class Filter {
  static double sinc(double x) {
    if (x == 0) return 1;
    x *= math.pi;
    return math.sin(x) / x;
  }

  static double lowPass(num cutoff, num rate, int n, int N) {
    final f = 2 * cutoff / rate;
    final x = n - (N - 1) / 2.0;
    return f * sinc(f * x);
  }
}
