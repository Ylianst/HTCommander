/*
Complex Convolution
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'complex.dart';

class ComplexConvolution {
  final int length;
  final Float64List taps;
  final Float64List _real;
  final Float64List _imag;
  final Complex _sum = Complex();
  int _pos = 0;

  ComplexConvolution(this.length)
    : taps = Float64List(length),
      _real = Float64List(length),
      _imag = Float64List(length);

  Complex push(Complex input) {
    _real[_pos] = input.real;
    _imag[_pos] = input.imag;
    if (++_pos >= length) _pos = 0;
    _sum.real = 0;
    _sum.imag = 0;
    for (int i = 0; i < taps.length; ++i) {
      _sum.real += taps[i] * _real[_pos];
      _sum.imag += taps[i] * _imag[_pos];
      if (++_pos >= length) _pos = 0;
    }
    return _sum;
  }
}
