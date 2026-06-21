/*
Fast Fourier Transform
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;
import 'complex.dart';

class FastFourierTransform {
  final List<Complex> _tf;
  final Complex _tmpA = Complex(),
      _tmpB = Complex(),
      _tmpC = Complex(),
      _tmpD = Complex(),
      _tmpE = Complex(),
      _tmpF = Complex(),
      _tmpG = Complex(),
      _tmpH = Complex(),
      _tmpI = Complex(),
      _tmpJ = Complex(),
      _tmpK = Complex(),
      _tmpL = Complex(),
      _tmpM = Complex();
  final Complex _tin0 = Complex(),
      _tin1 = Complex(),
      _tin2 = Complex(),
      _tin3 = Complex(),
      _tin4 = Complex(),
      _tin5 = Complex(),
      _tin6 = Complex();

  FastFourierTransform(int length)
    : _tf = List<Complex>.filled(length, Complex()) {
    int rest = length;
    while (rest > 1) {
      if (rest % 2 == 0) {
        rest ~/= 2;
      } else if (rest % 3 == 0) {
        rest ~/= 3;
      } else if (rest % 5 == 0) {
        rest ~/= 5;
      } else if (rest % 7 == 0) {
        rest ~/= 7;
      } else {
        break;
      }
    }
    if (rest != 1) {
      throw ArgumentError(
        'Transform length must be a composite of 2, 3, 5 and 7, but was: $length',
      );
    }
    for (int i = 0; i < length; ++i) {
      final x = -(2.0 * math.pi * i) / length;
      _tf[i] = Complex(math.cos(x), math.sin(x));
    }
  }

  static bool _isPowerOfTwo(int n) => n > 0 && (n & (n - 1)) == 0;

  static bool _isPowerOfFour(int n) =>
      _isPowerOfTwo(n) && (n & 0x55555555) != 0;

  static double _cos(int n, int N) => math.cos(n * 2.0 * math.pi / N);

  static double _sin(int n, int N) => math.sin(n * 2.0 * math.pi / N);

  void _dft2(Complex out0, Complex out1, Complex in0, Complex in1) {
    out0.setC(in0).add(in1);
    out1.setC(in0).sub(in1);
  }

  void _radix2(
    List<Complex> output,
    List<Complex> input,
    int O,
    int I,
    int N,
    int S,
    bool F,
  ) {
    if (N == 2) {
      _dft2(output[O], output[O + 1], input[I], input[I + S]);
    } else {
      final int Q = N ~/ 2;
      _dit(output, input, O, I, Q, 2 * S, F);
      _dit(output, input, O + Q, I + S, Q, 2 * S, F);
      for (int k0 = O, k1 = O + Q, l1 = 0; k0 < O + Q; ++k0, ++k1, l1 += S) {
        _tin1.setC(_tf[l1]);
        if (!F) _tin1.conj();
        _tin0.setC(output[k0]);
        _tin1.mulC(output[k1]);
        _dft2(output[k0], output[k1], _tin0, _tin1);
      }
    }
  }

  void _fwd3(
    Complex out0,
    Complex out1,
    Complex out2,
    Complex in0,
    Complex in1,
    Complex in2,
  ) {
    _tmpA.setC(in1).add(in2);
    _tmpB.setRI(in1.imag - in2.imag, in2.real - in1.real);
    _tmpC.setC(_tmpA).mulS(_cos(1, 3));
    _tmpD.setC(_tmpB).mulS(_sin(1, 3));
    out0.setC(in0).add(_tmpA);
    out1.setC(in0).add(_tmpC).add(_tmpD);
    out2.setC(in0).add(_tmpC).sub(_tmpD);
  }

  void _radix3(
    List<Complex> output,
    List<Complex> input,
    int O,
    int I,
    int N,
    int S,
    bool F,
  ) {
    if (N == 3) {
      if (F) {
        _fwd3(
          output[O],
          output[O + 1],
          output[O + 2],
          input[I],
          input[I + S],
          input[I + 2 * S],
        );
      } else {
        _fwd3(
          output[O],
          output[O + 2],
          output[O + 1],
          input[I],
          input[I + S],
          input[I + 2 * S],
        );
      }
    } else {
      final int Q = N ~/ 3;
      _dit(output, input, O, I, Q, 3 * S, F);
      _dit(output, input, O + Q, I + S, Q, 3 * S, F);
      _dit(output, input, O + 2 * Q, I + 2 * S, Q, 3 * S, F);
      for (
        int k0 = O, k1 = O + Q, k2 = O + 2 * Q, l1 = 0, l2 = 0;
        k0 < O + Q;
        ++k0, ++k1, ++k2, l1 += S, l2 += 2 * S
      ) {
        _tin1.setC(_tf[l1]);
        _tin2.setC(_tf[l2]);
        if (!F) {
          _tin1.conj();
          _tin2.conj();
        }
        _tin0.setC(output[k0]);
        _tin1.mulC(output[k1]);
        _tin2.mulC(output[k2]);
        if (F) {
          _fwd3(output[k0], output[k1], output[k2], _tin0, _tin1, _tin2);
        } else {
          _fwd3(output[k0], output[k2], output[k1], _tin0, _tin1, _tin2);
        }
      }
    }
  }

  void _fwd4(
    Complex out0,
    Complex out1,
    Complex out2,
    Complex out3,
    Complex in0,
    Complex in1,
    Complex in2,
    Complex in3,
  ) {
    _tmpA.setC(in0).add(in2);
    _tmpB.setC(in0).sub(in2);
    _tmpC.setC(in1).add(in3);
    _tmpD.setRI(in1.imag - in3.imag, in3.real - in1.real);
    out0.setC(_tmpA).add(_tmpC);
    out1.setC(_tmpB).add(_tmpD);
    out2.setC(_tmpA).sub(_tmpC);
    out3.setC(_tmpB).sub(_tmpD);
  }

  void _radix4(
    List<Complex> output,
    List<Complex> input,
    int O,
    int I,
    int N,
    int S,
    bool F,
  ) {
    if (N == 4) {
      if (F) {
        _fwd4(
          output[O],
          output[O + 1],
          output[O + 2],
          output[O + 3],
          input[I],
          input[I + S],
          input[I + 2 * S],
          input[I + 3 * S],
        );
      } else {
        _fwd4(
          output[O],
          output[O + 3],
          output[O + 2],
          output[O + 1],
          input[I],
          input[I + S],
          input[I + 2 * S],
          input[I + 3 * S],
        );
      }
    } else {
      final int Q = N ~/ 4;
      _radix4(output, input, O, I, Q, 4 * S, F);
      _radix4(output, input, O + Q, I + S, Q, 4 * S, F);
      _radix4(output, input, O + 2 * Q, I + 2 * S, Q, 4 * S, F);
      _radix4(output, input, O + 3 * Q, I + 3 * S, Q, 4 * S, F);
      for (
        int k0 = O,
            k1 = O + Q,
            k2 = O + 2 * Q,
            k3 = O + 3 * Q,
            l1 = 0,
            l2 = 0,
            l3 = 0;
        k0 < O + Q;
        ++k0, ++k1, ++k2, ++k3, l1 += S, l2 += 2 * S, l3 += 3 * S
      ) {
        _tin1.setC(_tf[l1]);
        _tin2.setC(_tf[l2]);
        _tin3.setC(_tf[l3]);
        if (!F) {
          _tin1.conj();
          _tin2.conj();
          _tin3.conj();
        }
        _tin0.setC(output[k0]);
        _tin1.mulC(output[k1]);
        _tin2.mulC(output[k2]);
        _tin3.mulC(output[k3]);
        if (F) {
          _fwd4(
            output[k0],
            output[k1],
            output[k2],
            output[k3],
            _tin0,
            _tin1,
            _tin2,
            _tin3,
          );
        } else {
          _fwd4(
            output[k0],
            output[k3],
            output[k2],
            output[k1],
            _tin0,
            _tin1,
            _tin2,
            _tin3,
          );
        }
      }
    }
  }

  void _fwd5(
    Complex out0,
    Complex out1,
    Complex out2,
    Complex out3,
    Complex out4,
    Complex in0,
    Complex in1,
    Complex in2,
    Complex in3,
    Complex in4,
  ) {
    _tmpA.setC(in1).add(in4);
    _tmpB.setC(in2).add(in3);
    _tmpC.setRI(in1.imag - in4.imag, in4.real - in1.real);
    _tmpD.setRI(in2.imag - in3.imag, in3.real - in2.real);
    _tmpF.setC(_tmpA).mulS(_cos(1, 5)).add(_tmpE.setC(_tmpB).mulS(_cos(2, 5)));
    _tmpG.setC(_tmpC).mulS(_sin(1, 5)).add(_tmpE.setC(_tmpD).mulS(_sin(2, 5)));
    _tmpH.setC(_tmpA).mulS(_cos(2, 5)).add(_tmpE.setC(_tmpB).mulS(_cos(1, 5)));
    _tmpI.setC(_tmpC).mulS(_sin(2, 5)).sub(_tmpE.setC(_tmpD).mulS(_sin(1, 5)));
    out0.setC(in0).add(_tmpA).add(_tmpB);
    out1.setC(in0).add(_tmpF).add(_tmpG);
    out2.setC(in0).add(_tmpH).add(_tmpI);
    out3.setC(in0).add(_tmpH).sub(_tmpI);
    out4.setC(in0).add(_tmpF).sub(_tmpG);
  }

  void _radix5(
    List<Complex> output,
    List<Complex> input,
    int O,
    int I,
    int N,
    int S,
    bool F,
  ) {
    if (N == 5) {
      if (F) {
        _fwd5(
          output[O],
          output[O + 1],
          output[O + 2],
          output[O + 3],
          output[O + 4],
          input[I],
          input[I + S],
          input[I + 2 * S],
          input[I + 3 * S],
          input[I + 4 * S],
        );
      } else {
        _fwd5(
          output[O],
          output[O + 4],
          output[O + 3],
          output[O + 2],
          output[O + 1],
          input[I],
          input[I + S],
          input[I + 2 * S],
          input[I + 3 * S],
          input[I + 4 * S],
        );
      }
    } else {
      final int Q = N ~/ 5;
      _dit(output, input, O, I, Q, 5 * S, F);
      _dit(output, input, O + Q, I + S, Q, 5 * S, F);
      _dit(output, input, O + 2 * Q, I + 2 * S, Q, 5 * S, F);
      _dit(output, input, O + 3 * Q, I + 3 * S, Q, 5 * S, F);
      _dit(output, input, O + 4 * Q, I + 4 * S, Q, 5 * S, F);
      for (
        int k0 = O,
            k1 = O + Q,
            k2 = O + 2 * Q,
            k3 = O + 3 * Q,
            k4 = O + 4 * Q,
            l1 = 0,
            l2 = 0,
            l3 = 0,
            l4 = 0;
        k0 < O + Q;
        ++k0,
        ++k1,
        ++k2,
        ++k3,
        ++k4,
        l1 += S,
        l2 += 2 * S,
        l3 += 3 * S,
        l4 += 4 * S
      ) {
        _tin1.setC(_tf[l1]);
        _tin2.setC(_tf[l2]);
        _tin3.setC(_tf[l3]);
        _tin4.setC(_tf[l4]);
        if (!F) {
          _tin1.conj();
          _tin2.conj();
          _tin3.conj();
          _tin4.conj();
        }
        _tin0.setC(output[k0]);
        _tin1.mulC(output[k1]);
        _tin2.mulC(output[k2]);
        _tin3.mulC(output[k3]);
        _tin4.mulC(output[k4]);
        if (F) {
          _fwd5(
            output[k0],
            output[k1],
            output[k2],
            output[k3],
            output[k4],
            _tin0,
            _tin1,
            _tin2,
            _tin3,
            _tin4,
          );
        } else {
          _fwd5(
            output[k0],
            output[k4],
            output[k3],
            output[k2],
            output[k1],
            _tin0,
            _tin1,
            _tin2,
            _tin3,
            _tin4,
          );
        }
      }
    }
  }

  void _fwd7(
    Complex out0,
    Complex out1,
    Complex out2,
    Complex out3,
    Complex out4,
    Complex out5,
    Complex out6,
    Complex in0,
    Complex in1,
    Complex in2,
    Complex in3,
    Complex in4,
    Complex in5,
    Complex in6,
  ) {
    _tmpA.setC(in1).add(in6);
    _tmpB.setC(in2).add(in5);
    _tmpC.setC(in3).add(in4);
    _tmpD.setRI(in1.imag - in6.imag, in6.real - in1.real);
    _tmpE.setRI(in2.imag - in5.imag, in5.real - in2.real);
    _tmpF.setRI(in3.imag - in4.imag, in4.real - in3.real);
    _tmpH
        .setC(_tmpA)
        .mulS(_cos(1, 7))
        .add(_tmpG.setC(_tmpB).mulS(_cos(2, 7)))
        .add(_tmpG.setC(_tmpC).mulS(_cos(3, 7)));
    _tmpI
        .setC(_tmpD)
        .mulS(_sin(1, 7))
        .add(_tmpG.setC(_tmpE).mulS(_sin(2, 7)))
        .add(_tmpG.setC(_tmpF).mulS(_sin(3, 7)));
    _tmpJ
        .setC(_tmpA)
        .mulS(_cos(2, 7))
        .add(_tmpG.setC(_tmpB).mulS(_cos(3, 7)))
        .add(_tmpG.setC(_tmpC).mulS(_cos(1, 7)));
    _tmpK
        .setC(_tmpD)
        .mulS(_sin(2, 7))
        .sub(_tmpG.setC(_tmpE).mulS(_sin(3, 7)))
        .sub(_tmpG.setC(_tmpF).mulS(_sin(1, 7)));
    _tmpL
        .setC(_tmpA)
        .mulS(_cos(3, 7))
        .add(_tmpG.setC(_tmpB).mulS(_cos(1, 7)))
        .add(_tmpG.setC(_tmpC).mulS(_cos(2, 7)));
    _tmpM
        .setC(_tmpD)
        .mulS(_sin(3, 7))
        .sub(_tmpG.setC(_tmpE).mulS(_sin(1, 7)))
        .add(_tmpG.setC(_tmpF).mulS(_sin(2, 7)));
    out0.setC(in0).add(_tmpA).add(_tmpB).add(_tmpC);
    out1.setC(in0).add(_tmpH).add(_tmpI);
    out2.setC(in0).add(_tmpJ).add(_tmpK);
    out3.setC(in0).add(_tmpL).add(_tmpM);
    out4.setC(in0).add(_tmpL).sub(_tmpM);
    out5.setC(in0).add(_tmpJ).sub(_tmpK);
    out6.setC(in0).add(_tmpH).sub(_tmpI);
  }

  void _radix7(
    List<Complex> output,
    List<Complex> input,
    int O,
    int I,
    int N,
    int S,
    bool F,
  ) {
    if (N == 7) {
      if (F) {
        _fwd7(
          output[O],
          output[O + 1],
          output[O + 2],
          output[O + 3],
          output[O + 4],
          output[O + 5],
          output[O + 6],
          input[I],
          input[I + S],
          input[I + 2 * S],
          input[I + 3 * S],
          input[I + 4 * S],
          input[I + 5 * S],
          input[I + 6 * S],
        );
      } else {
        _fwd7(
          output[O],
          output[O + 6],
          output[O + 5],
          output[O + 4],
          output[O + 3],
          output[O + 2],
          output[O + 1],
          input[I],
          input[I + S],
          input[I + 2 * S],
          input[I + 3 * S],
          input[I + 4 * S],
          input[I + 5 * S],
          input[I + 6 * S],
        );
      }
    } else {
      final int Q = N ~/ 7;
      _dit(output, input, O, I, Q, 7 * S, F);
      _dit(output, input, O + Q, I + S, Q, 7 * S, F);
      _dit(output, input, O + 2 * Q, I + 2 * S, Q, 7 * S, F);
      _dit(output, input, O + 3 * Q, I + 3 * S, Q, 7 * S, F);
      _dit(output, input, O + 4 * Q, I + 4 * S, Q, 7 * S, F);
      _dit(output, input, O + 5 * Q, I + 5 * S, Q, 7 * S, F);
      _dit(output, input, O + 6 * Q, I + 6 * S, Q, 7 * S, F);
      for (
        int k0 = O,
            k1 = O + Q,
            k2 = O + 2 * Q,
            k3 = O + 3 * Q,
            k4 = O + 4 * Q,
            k5 = O + 5 * Q,
            k6 = O + 6 * Q,
            l1 = 0,
            l2 = 0,
            l3 = 0,
            l4 = 0,
            l5 = 0,
            l6 = 0;
        k0 < O + Q;
        ++k0,
        ++k1,
        ++k2,
        ++k3,
        ++k4,
        ++k5,
        ++k6,
        l1 += S,
        l2 += 2 * S,
        l3 += 3 * S,
        l4 += 4 * S,
        l5 += 5 * S,
        l6 += 6 * S
      ) {
        _tin1.setC(_tf[l1]);
        _tin2.setC(_tf[l2]);
        _tin3.setC(_tf[l3]);
        _tin4.setC(_tf[l4]);
        _tin5.setC(_tf[l5]);
        _tin6.setC(_tf[l6]);
        if (!F) {
          _tin1.conj();
          _tin2.conj();
          _tin3.conj();
          _tin4.conj();
          _tin5.conj();
          _tin6.conj();
        }
        _tin0.setC(output[k0]);
        _tin1.mulC(output[k1]);
        _tin2.mulC(output[k2]);
        _tin3.mulC(output[k3]);
        _tin4.mulC(output[k4]);
        _tin5.mulC(output[k5]);
        _tin6.mulC(output[k6]);
        if (F) {
          _fwd7(
            output[k0],
            output[k1],
            output[k2],
            output[k3],
            output[k4],
            output[k5],
            output[k6],
            _tin0,
            _tin1,
            _tin2,
            _tin3,
            _tin4,
            _tin5,
            _tin6,
          );
        } else {
          _fwd7(
            output[k0],
            output[k6],
            output[k5],
            output[k4],
            output[k3],
            output[k2],
            output[k1],
            _tin0,
            _tin1,
            _tin2,
            _tin3,
            _tin4,
            _tin5,
            _tin6,
          );
        }
      }
    }
  }

  void _dit(
    List<Complex> output,
    List<Complex> input,
    int O,
    int I,
    int N,
    int S,
    bool F,
  ) {
    if (N == 1) {
      output[O].setC(input[I]);
    } else if (_isPowerOfFour(N)) {
      _radix4(output, input, O, I, N, S, F);
    } else if (N % 7 == 0) {
      _radix7(output, input, O, I, N, S, F);
    } else if (N % 5 == 0) {
      _radix5(output, input, O, I, N, S, F);
    } else if (N % 3 == 0) {
      _radix3(output, input, O, I, N, S, F);
    } else if (N % 2 == 0) {
      _radix2(output, input, O, I, N, S, F);
    }
  }

  void forward(List<Complex> output, List<Complex> input) {
    if (input.length != _tf.length) {
      throw ArgumentError(
        'Input array length (${input.length}) must be equal '
        'to Transform length (${_tf.length})',
      );
    }
    if (output.length != _tf.length) {
      throw ArgumentError(
        'Output array length (${output.length}) must be equal '
        'to Transform length (${_tf.length})',
      );
    }
    _dit(output, input, 0, 0, _tf.length, 1, true);
  }

  void backward(List<Complex> output, List<Complex> input) {
    if (input.length != _tf.length) {
      throw ArgumentError(
        'Input array length (${input.length}) must be equal '
        'to Transform length (${_tf.length})',
      );
    }
    if (output.length != _tf.length) {
      throw ArgumentError(
        'Output array length (${output.length}) must be equal '
        'to Transform length (${_tf.length})',
      );
    }
    _dit(output, input, 0, 0, _tf.length, 1, false);
  }
}
