/*
Digital delay line
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';

class Delay {
  final int length;
  final Float64List _buf;
  int _pos = 0;

  Delay(this.length) : _buf = Float64List(length);

  double push(double input) {
    final tmp = _buf[_pos];
    _buf[_pos] = input;
    if (++_pos >= length) _pos = 0;
    return tmp;
  }
}
