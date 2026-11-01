/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/xara-modem/xara), crates/xara/src/resample.rs
Copyright (c) the XARA authors, MIT License.

Streaming windowed-sinc sample-rate converter with a polyphase Kaiser kernel.
*/

import 'dart:math' as math;
import 'dart:typed_data';

const double _half = 24.0;
const double _phases = 512.0;
const double _beta = 8.0;
const double minRate = 1000.0;
const double maxRate = 1000000.0;

double _bessel(double v) {
  double s = 1.0, term = 1.0;
  for (int k = 1; k < 30; k++) {
    term *= (v / 2.0) / k;
    s += term * term;
  }
  return s;
}

double _kaiser(double x, double norm) => x.abs() >= 1.0 ? 0.0 : _bessel(_beta * math.sqrt(1.0 - x * x)) / norm;

class _Kernel {
  final int half;
  final int phases;
  final Float64List table;

  _Kernel(this.half, this.phases, double cutoff) : table = Float64List((phases + 1) * 2 * half) {
    final int n = 2 * half;
    final double norm = _bessel(_beta);
    for (int p = 0; p <= phases; p++) {
      final double frac = p / phases;
      final int o = p * n;
      for (int k = 0; k < n; k++) {
        final double u = frac + (half - 1) - k;
        final double a = math.pi * cutoff * u;
        final double s = a.abs() < 1e-12 ? 1.0 : math.sin(a) / a;
        table[o + k] = s * _kaiser(u / half, norm);
      }
      double sum = 0.0;
      for (int k = 0; k < n; k++) {
        sum += table[o + k];
      }
      for (int k = 0; k < n; k++) {
        table[o + k] /= sum;
      }
    }
  }

  double apply(List<double> x, int start, double frac) {
    final int n = 2 * half;
    final double pos = frac * phases;
    final int p = math.min(pos.toInt(), phases - 1);
    final double w = pos - p;
    final int a = p * n, b = a + n;
    double acc = 0.0;
    for (int k = 0; k < n; k++) {
      final double c0 = table[a + k], c1 = table[b + k];
      acc += x[start + k] * (c0 + w * (c1 - c0));
    }
    return acc;
  }
}

class _Stream {
  final _Kernel kernel;
  final List<double> buf;
  int i;
  double frac = 0.0;

  _Stream(this.kernel)
      : i = kernel.half - 1,
        buf = List<double>.filled(kernel.half - 1, 0.0, growable: true);

  void run(List<double> x, int whole, double part, List<double> out) {
    buf.addAll(x);
    final int half = kernel.half;
    while (i + half < buf.length) {
      out.add(kernel.apply(buf, i + 1 - half, frac));
      i += whole;
      frac += part;
      if (frac >= 1.0) {
        frac -= 1.0;
        i += 1;
      }
    }
    final int used = i + 1 - half;
    buf.removeRange(0, used);
    i -= used;
  }
}

class Resampler {
  final int _whole;
  final double _part;
  final _Stream _stream;

  Resampler._(this._whole, this._part, this._stream);

  /// Throws [ArgumentError] unless both rates are within [minRate]..[maxRate].
  factory Resampler(double rateIn, double rateOut) {
    _checkRate(rateIn);
    _checkRate(rateOut);
    final double cutoff = 0.95 * math.min(rateOut / rateIn, 1.0);
    final int half = (_half / cutoff).ceil();
    final _Kernel kernel = _Kernel(half, (_phases * cutoff).ceil(), cutoff);
    final double step = rateIn / rateOut;
    final double whole = step.floorToDouble();
    return Resampler._(whole.toInt(), step - whole, _Stream(kernel));
  }

  static void _checkRate(double rate) {
    if (!(rate >= minRate && rate <= maxRate)) {
      throw ArgumentError('sample rate $rate Hz: must be $minRate-$maxRate Hz');
    }
  }

  bool get identity => _whole == 1 && _part == 0.0;

  List<double> process(List<double> x) {
    if (identity) return List<double>.of(x);
    final List<double> out = <double>[];
    _stream.run(x, _whole, _part, out);
    return out;
  }

  List<double> flush() => identity ? <double>[] : process(List<double>.filled(_stream.kernel.half + 1, 0.0));
}
