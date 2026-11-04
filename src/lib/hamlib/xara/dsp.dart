/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Small DSP helpers.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'complex.dart';
import 'numeric.dart';

const double _ulpOne = 4503599627370496.0;

/// Rounds to the 16-bit PCM grid (ties to even) and back to [-1, 1].
double quantise(double x) {
  final double y = x.clamp(-1.0, 1.0) * 32767.0;
  final double m = (y.abs() + _ulpOne) - _ulpOne;
  return (y.isNegative ? -m : m) / 32767.0;
}

double dbAmp(double db) => math.pow(10.0, db / 20.0).toDouble();

const double chiMin = 20.0;

/// Rust `i64::div_euclid` for a positive divisor.
int floorDiv(int a, int b) => (a - (a % b)) ~/ b;

/// A sliding window of real (stride 1) or interleaved complex (stride 2)
/// samples addressed by absolute index. Keeps at least [keep] samples.
class SampleTrack {
  final int stride;
  final int keep;
  int base = 0;
  int _len = 0;
  Float64List _d;

  SampleTrack(this.keep, {this.stride = 1}) : _d = Float64List(stride * 1024);

  int get end => base + _len;
  int get length => _len;

  void restart(int b) {
    base = b;
    _len = 0;
  }

  /// Appends [v] (stride-interleaved) at absolute index [m0]; restarts if
  /// [m0] does not continue the track.
  void append(int m0, List<double> v) {
    if (m0 != end) restart(m0);
    final int n = v.length ~/ stride;
    final int need = stride * (_len + n);
    if (need > _d.length) {
      int cap = _d.length;
      while (cap < need) {
        cap *= 2;
      }
      _d = Float64List(cap)..setRange(0, stride * _len, _d);
    }
    _d.setRange(stride * _len, need, v);
    _len += n;
    if (_len > 2 * keep) {
      final int drop = _len - keep;
      _d.setRange(0, stride * keep, _d, stride * drop);
      _len = keep;
      base += drop;
    }
  }

  bool contains(int i) => i >= base && i < end;

  double at(int i, [int c = 0]) => _d[stride * (i - base) + c];

  /// Copies samples [a, b) into [re] (and [im] for complex tracks) from
  /// offset [off]; positions outside the track read as zero.
  void fill(int a, int b, Float64List re, [Float64List? im, int off = 0]) {
    for (int i = a; i < b; i++) {
      final int o = off + i - a;
      if (i >= base && i < end) {
        final int s = stride * (i - base);
        re[o] = _d[s];
        if (im != null) im[o] = stride == 2 ? _d[s + 1] : 0.0;
      } else {
        re[o] = 0.0;
        if (im != null) im[o] = 0.0;
      }
    }
  }

  /// Mean |z|^2 over [a, b) (zeros outside the track).
  double meanPower(int a, int b) {
    final int n = b > a ? b - a : 0;
    double s = 0.0;
    for (int i = a; i < b; i++) {
      if (i >= base && i < end) {
        final int k = stride * (i - base);
        s += _d[k] * _d[k];
        if (stride == 2) s += _d[k + 1] * _d[k + 1];
      }
    }
    return s / (n > 0 ? n : 1);
  }
}

/// A sliding window of rows addressed by absolute index.
class Track<T> {
  final int keep;
  int base = 0;
  final List<T> buf = <T>[];

  Track(this.keep);

  int get end => base + buf.length;

  void restart(int b) {
    base = b;
    buf.clear();
  }

  void append(int m0, Iterable<T> v) {
    if (m0 != end) restart(m0);
    buf.addAll(v);
    if (buf.length > 2 * keep) {
      final int drop = buf.length - keep;
      buf.removeRange(0, drop);
      base += drop;
    }
  }

  bool contains(int i) => i >= base && i < end;

  T at(int i) => buf[i - base];
}

/// Forward FFT of a zero-padded window taken from a complex [SampleTrack].
class FftWindow {
  final Fft _fft;
  final Float64List re;
  final Float64List im;

  FftWindow(int n)
      : _fft = Fft.plan(n),
        re = Float64List(n),
        im = Float64List(n);

  void at(SampleTrack track, int a, int len) {
    track.fill(a, a + len, re, im);
    re.fillRange(len, re.length, 0.0);
    im.fillRange(len, im.length, 0.0);
    _fft.transform(re, im);
  }
}

/// Peak-hold detector: reports the best candidate once [hold] positions have
/// passed without a better one, then blocks new candidates for [dead].
class Hold<X> {
  final int hold;
  final int dead;
  (int, double, X)? best;
  int _block = -4611686018427387904;

  Hold(this.hold, this.dead);

  (int, double, X)? _push(int pos, double metric, X extra) {
    final (int, double, X)? out = _flushBefore(pos);
    if (out == null && pos >= _block && (best == null || metric > best!.$2)) {
      best = (pos, metric, extra);
    }
    return out;
  }

  (int, double, X)? _flushBefore(int pos) {
    final (int, double, X)? b = best;
    if (b != null && pos - b.$1 > hold) {
      best = null;
      return b;
    }
    return null;
  }

  /// Drops the held candidate unless [f] returns true for it.
  void retain(bool Function(X) f) {
    final (int, double, X)? b = best;
    if (b != null && !f(b.$3)) best = null;
  }

  (int, double, X)? offer(int pos, (double, X)? candidate) {
    final (int, double, X)? out =
        candidate != null ? _push(pos, candidate.$1, candidate.$2) : _flushBefore(pos);
    if (out != null) _block = out.$1 + dead;
    return out;
  }
}

double median(List<double> v) {
  if (v.isEmpty) throw StateError('median of nothing');
  final List<double> a = List<double>.of(v)..sort(totalCmp);
  final int n = a.length;
  return n.isOdd ? a[n ~/ 2] : 0.5 * (a[n ~/ 2 - 1] + a[n ~/ 2]);
}

/// Rust `f64::total_cmp` ordering.
int totalCmp(double a, double b) {
  int key(double x) {
    final int bits = f64Bits(x);
    return bits < 0 ? bits ^ maxI64 : bits;
  }

  final int ka = key(a), kb = key(b);
  return ka < kb ? -1 : (ka > kb ? 1 : 0);
}

int peakMid(List<double> vals, int i, double rel) {
  final double tol = vals.length > 2 ? rel * (vals[i] - median(vals)) : 0.0;
  int j0 = i, j1 = i;
  while (j0 > 0 && vals[j0 - 1] >= vals[i] - tol) {
    j0--;
  }
  while (j1 + 1 < vals.length && vals[j1 + 1] >= vals[i] - tol) {
    j1++;
  }
  return (j0 + j1) ~/ 2;
}

Cx unit(Cx z) => z.div(z.norm + 1e-30);

int argmax(List<double> v) {
  int b = 0;
  for (int i = 0; i < v.length; i++) {
    if (v[i] > v[b]) b = i;
  }
  return b;
}

List<T> thin<T>(List<T> v, int max) {
  if (v.length <= max) return v;
  return List<T>.generate(max, (i) => v[i * v.length ~/ max]);
}

double _besselI0(double x) {
  double sum = 1.0, term = 1.0, k = 1.0;
  while (term > 1e-17 * sum) {
    final double q = x / (2.0 * k);
    term *= q * q;
    sum += term;
    k += 1.0;
  }
  return sum;
}

List<double> kaiserLowpass(int n, double cutoff, double fs, double beta) {
  final double fc = cutoff / (fs / 2.0);
  final double mid = (n - 1) / 2.0;
  final List<double> h = List<double>.generate(n, (i) {
    final double m = i - mid;
    final double sinc = m == 0.0 ? 1.0 : math.sin(math.pi * fc * m) / (math.pi * fc * m);
    final double r = 2.0 * i / (n - 1) - 1.0;
    return fc * sinc * _besselI0(beta * math.sqrt(math.max(1.0 - r * r, 0.0))) / _besselI0(beta);
  });
  final double s = h.fold(0.0, (a, b) => a + b);
  return h.map((v) => v / s).toList();
}
