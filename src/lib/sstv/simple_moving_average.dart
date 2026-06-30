/*
Simple Moving Average
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'simple_moving_sum.dart';

class SimpleMovingAverage extends SimpleMovingSum {
  SimpleMovingAverage(super.length);

  double avg(double input) => sumInput(input) / length;
}
