/*
Short Time Fourier Transform
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'complex.dart';
import 'fast_fourier_transform.dart';
import 'filter.dart';
import 'hann.dart';

class ShortTimeFourierTransform {
  final FastFourierTransform _fft;
  final List<Complex> _prev;
  final List<Complex> _fold;
  final List<Complex> _freq;
  final Float64List _weight;
  final Complex _temp = Complex();
  int _index = 0;

  final Float64List power;

  ShortTimeFourierTransform(int length, int overlap)
    : _fft = FastFourierTransform(length),
      _prev = List<Complex>.generate(length * overlap, (_) => Complex()),
      _fold = List<Complex>.generate(length, (_) => Complex()),
      _freq = List<Complex>.generate(length, (_) => Complex()),
      power = Float64List(length),
      _weight = Float64List(length * overlap) {
    for (int i = 0; i < length * overlap; ++i) {
      _weight[i] =
          Filter.lowPass(1, length, i, length * overlap) *
          Hann.window(i, length * overlap);
    }
  }

  bool push(Complex input) {
    _prev[_index].setC(input);
    _index = (_index + 1) % _prev.length;
    if (_index % _fold.length != 0) return false;
    for (int i = 0; i < _fold.length; ++i) {
      _fold[i].setC(_prev[_index]).mulS(_weight[i]);
      _index = (_index + 1) % _prev.length;
    }
    for (int i = _fold.length; i < _prev.length; ++i) {
      _fold[i % _fold.length].add(_temp.setC(_prev[_index]).mulS(_weight[i]));
      _index = (_index + 1) % _prev.length;
    }
    _fft.forward(_freq, _fold);
    for (int i = 0; i < power.length; ++i) {
      power[i] = _freq[i].norm();
    }
    return true;
  }
}
