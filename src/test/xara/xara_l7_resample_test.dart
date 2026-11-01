/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Layer 7 tests: the streaming resampler (XARA `resample.rs` unit tests),
plus the 32 kHz <-> 48 kHz conversions HTCommander's audio path will use.
*/

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/resample.dart';

List<double> tone(double hz, double fs, int n) => List<double>.generate(n, (i) => math.sin(2.0 * math.pi * hz * i / fs));

List<double> runChunked(Resampler r, List<double> x, int chunk) {
  final List<double> y = <double>[];
  for (int i = 0; i < x.length; i += chunk) {
    y.addAll(r.process(x.sublist(i, math.min(i + chunk, x.length))));
  }
  y.addAll(r.flush());
  return y;
}

void check(double rateIn, double rateOut, double hz) {
  final Resampler r = Resampler(rateIn, rateOut);
  final List<double> x = tone(hz, rateIn, rateIn.toInt());
  final List<double> y = <double>[];
  for (int i = 0; i < x.length; i += 4096) {
    y.addAll(r.process(x.sublist(i, math.min(i + 4096, x.length))));
  }
  final List<double> want = tone(hz, rateOut, y.length);
  double err = 0.0;
  for (int i = 400; i < y.length - 400; i++) {
    final double d = y[i] - want[i];
    err += d * d;
  }
  err /= y.length - 800;
  final String at = '$rateIn->$rateOut $hz Hz';
  expect((y.length - rateOut).abs() < 200.0, isTrue, reason: '$at: ${y.length}');
  expect(err < 1e-6, isTrue, reason: '$at: $err');
}

void main() {
  group('resampler', () {
    test('upsampled tone keeps frequency and level', () {
      check(12000.0, 48000.0, 1500.0);
      check(8000.0, 48000.0, 3000.0);
      check(32000.0, 48000.0, 1500.0);
    });

    test('downsampled tone keeps frequency and level', () {
      for (final (double rateIn, double hz) in <(double, double)>[
        (96000.0, 1500.0),
        (96000.0, 20000.0),
        (44100.0, 1500.0),
        (44100.0, 15000.0),
        (1e6, 1500.0),
      ]) {
        check(rateIn, 48000.0, hz);
      }
      check(48000.0, 32000.0, 1500.0);
    });

    test('chunking does not change output', () {
      for (final (double rateIn, double rateOut) in <(double, double)>[
        (12000.0, 48000.0),
        (44100.0, 48000.0),
        (96000.0, 48000.0),
        (32000.0, 48000.0),
        (48000.0, 32000.0),
      ]) {
        final List<double> x = tone(1500.0, rateIn, 5000);
        final List<double> whole = runChunked(Resampler(rateIn, rateOut), x, x.length);
        for (final int chunk in <int>[1, 7, 1000]) {
          expect(runChunked(Resampler(rateIn, rateOut), x, chunk), whole, reason: '$rateIn $chunk');
        }
      }
    });

    test('untrusted rates are refused', () {
      for (final double r in <double>[0.0, -48000.0, double.nan, double.infinity, double.negativeInfinity, 999.0,
          1e6 + 1.0, double.minPositive]) {
        expect(() => Resampler(r, 48000.0), throwsArgumentError, reason: '$r');
        expect(() => Resampler(48000.0, r), throwsArgumentError, reason: '$r');
      }
      expect(Resampler(1000.0, 1e6).identity, isFalse);
    });
  });
}
