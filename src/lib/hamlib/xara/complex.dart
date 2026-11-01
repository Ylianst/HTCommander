/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Complex numbers (num_complex semantics) and a radix-2 FFT.
*/

import 'dart:math' as math;
import 'dart:typed_data';

class Cx {
  final double re;
  final double im;

  const Cx(this.re, this.im);

  static const Cx zero = Cx(0.0, 0.0);
  static const Cx one = Cx(1.0, 0.0);

  factory Cx.polar(double r, double theta) => Cx(r * math.cos(theta), r * math.sin(theta));

  Cx operator +(Cx o) => Cx(re + o.re, im + o.im);
  Cx operator -(Cx o) => Cx(re - o.re, im - o.im);
  Cx operator -() => Cx(-re, -im);
  Cx operator *(Cx o) => Cx(re * o.re - im * o.im, re * o.im + im * o.re);

  Cx scale(double t) => Cx(re * t, im * t);
  Cx div(double t) => Cx(re / t, im / t);

  /// Complex division with num_complex's formula.
  Cx divC(Cx o) {
    final double n = o.re * o.re + o.im * o.im;
    return Cx((re * o.re + im * o.im) / n, (im * o.re - re * o.im) / n);
  }

  double get arg => math.atan2(im, re);

  Cx conj() => Cx(re, -im);

  double get normSqr => re * re + im * im;

  double get norm => hypot(re, im);

  @override
  bool operator ==(Object other) => other is Cx && other.re == re && other.im == im;

  @override
  int get hashCode => Object.hash(re, im);

  @override
  String toString() => '($re, $im)';
}

/// sqrt(x^2 + y^2) without undue overflow or underflow.
double hypot(double x, double y) {
  final double a = x.abs();
  final double b = y.abs();
  if (a.isInfinite || b.isInfinite) return double.infinity;
  if (a.isNaN || b.isNaN) return double.nan;
  final double hi = a > b ? a : b;
  final double lo = a > b ? b : a;
  if (hi == 0.0) return 0.0;
  if (hi > 1e150 || lo < 1e-150) {
    final double r = lo / hi;
    return hi * math.sqrt(1.0 + r * r);
  }
  return math.sqrt(hi * hi + lo * lo);
}

/// In-place iterative radix-2 complex FFT of a power-of-two size. Unnormalised
/// in both directions, matching rustfft.
class Fft {
  final int n;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _rev;

  Fft(this.n)
      : _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2),
        _rev = Int32List(n) {
    if (n < 1 || (n & (n - 1)) != 0) throw ArgumentError('FFT size $n');
    for (int k = 0; k < n ~/ 2; k++) {
      final double a = 2.0 * math.pi * k / n;
      _cos[k] = math.cos(a);
      _sin[k] = math.sin(a);
    }
    final int bits = n.bitLength - 1;
    for (int i = 0; i < n; i++) {
      int r = 0;
      for (int b = 0; b < bits; b++) {
        r |= ((i >> b) & 1) << (bits - 1 - b);
      }
      _rev[i] = r;
    }
  }

  static final Map<int, Fft> _plans = <int, Fft>{};

  static Fft plan(int n) => _plans[n] ??= Fft(n);

  /// Transforms [re]/[im] in place. Forward uses e^{-2 pi i k n / N}.
  void transform(Float64List re, Float64List im, {bool inverse = false}) {
    for (int i = 0; i < n; i++) {
      final int j = _rev[i];
      if (j > i) {
        final double tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final double ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    final double sign = inverse ? 1.0 : -1.0;
    for (int size = 2; size <= n; size <<= 1) {
      final int half = size >> 1;
      final int step = n ~/ size;
      for (int start = 0; start < n; start += size) {
        for (int k = 0; k < half; k++) {
          final double wr = _cos[k * step];
          final double wi = sign * _sin[k * step];
          final int a = start + k;
          final int b = a + half;
          final double xr = re[b] * wr - im[b] * wi;
          final double xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] = re[a] + xr;
          im[a] = im[a] + xi;
        }
      }
    }
  }
}
