/*
Complex math
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:math' as math;

class Complex {
  double real;
  double imag;

  Complex([this.real = 0, this.imag = 0]);

  Complex setC(Complex other) {
    real = other.real;
    imag = other.imag;
    return this;
  }

  Complex setRI(double real, double imag) {
    this.real = real;
    this.imag = imag;
    return this;
  }

  Complex setR(double real) => setRI(real, 0);

  double norm() => real * real + imag * imag;

  double abs() => math.sqrt(norm());

  double arg() => math.atan2(imag, real);

  Complex polar(double a, double b) {
    real = a * math.cos(b);
    imag = a * math.sin(b);
    return this;
  }

  Complex conj() {
    imag = -imag;
    return this;
  }

  Complex add(Complex other) {
    real += other.real;
    imag += other.imag;
    return this;
  }

  Complex sub(Complex other) {
    real -= other.real;
    imag -= other.imag;
    return this;
  }

  Complex mulS(double value) {
    real *= value;
    imag *= value;
    return this;
  }

  Complex mulC(Complex other) {
    final tmp = real * other.real - imag * other.imag;
    imag = real * other.imag + imag * other.real;
    real = tmp;
    return this;
  }

  Complex divS(double value) {
    real /= value;
    imag /= value;
    return this;
  }

  Complex divC(Complex other) {
    final den = other.norm();
    final tmp = (real * other.real + imag * other.imag) / den;
    imag = (imag * other.real - real * other.imag) / den;
    real = tmp;
    return this;
  }
}
