// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/native_cw.dart';

Float64List _reference(
  List<double> samples,
  Float64List coefficients,
  int start,
  int window,
  int hop,
  int windows,
) {
  final metrics = Float64List(windows * 3);
  final s1 = Float64List(coefficients.length);
  final s2 = Float64List(coefficients.length);
  for (int w = 0; w < windows; w++) {
    s1.fillRange(0, s1.length, 0);
    s2.fillRange(0, s2.length, 0);
    double energy = 0;
    for (int i = 0; i < window; i++) {
      final x = samples[start + w * hop + i];
      energy += x * x;
      for (int p = 0; p < coefficients.length; p++) {
        final next = x + coefficients[p] * s1[p] - s2[p];
        s2[p] = s1[p];
        s1[p] = next;
      }
    }
    double maximum = 0;
    int peak = -1;
    for (int p = 0; p < coefficients.length; p++) {
      final power =
          s1[p] * s1[p] + s2[p] * s2[p] - coefficients[p] * s1[p] * s2[p];
      if (power > maximum) {
        maximum = power;
        peak = p;
      }
    }
    metrics[w * 3] = energy;
    metrics[w * 3 + 1] = maximum;
    metrics[w * 3 + 2] = peak.toDouble();
  }
  return metrics;
}

void main() {
  test('batched native metrics match independent Dart overlapping windows', () {
    const window = 257;
    const hop = 63;
    final coefficients = Float64List.fromList([
      for (final hz in [250, 400, 550, 700, 850, 1000, 1150])
        2 * math.cos(2 * math.pi * hz / 32000),
    ]);
    final native = createNativeCw(coefficients, window, hop)!;
    final random = math.Random(9);
    try {
      for (final windows in [1, 3, 256, 2]) {
        final count = window + (windows - 1) * hop;
        for (final hz in [0.0, 700.0, 712.5, 1200.0, -1.0]) {
          final samples = Float64List(count + 11);
          for (int i = 7; i < 7 + count; i++) {
            samples[i] = hz == 0
                ? 0
                : hz < 0
                ? random.nextDouble() * 2 - 1
                : 0.3 * math.sin(2 * math.pi * hz * i / 32000) +
                      (random.nextDouble() * 2 - 1) * 0.03;
          }
          final actual = native.analyze(samples, 7, windows);
          final expected = _reference(
            samples,
            coefficients,
            7,
            window,
            hop,
            windows,
          );
          for (int i = 0; i < actual.length; i++) {
            if (i % 3 == 2) {
              expect(actual[i], expected[i], reason: 'peak $i, $hz Hz');
            } else {
              expect(
                actual[i],
                closeTo(
                  expected[i],
                  math.max(1e-10, expected[i].abs() * 1e-10),
                ),
                reason: 'metric $i, $hz Hz, $windows windows',
              );
            }
          }
        }
      }
    } finally {
      native.dispose();
    }
  }, skip: !nativeCwEnabled);

  test(
    'native bounds, finite-input errors, reuse and disposal are explicit',
    () {
      final native = createNativeCw(Float64List.fromList([1.5]), 16, 4)!;
      final samples = Float64List(24);
      try {
        expect(() => native.analyze(samples, 0, 0), throwsRangeError);
        expect(() => native.analyze(samples, 0, 257), throwsRangeError);
        expect(() => native.analyze(samples, 10, 1), throwsRangeError);
        samples[0] = double.nan;
        expect(
          () => native.analyze(samples, 0, 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('status -2'),
            ),
          ),
        );
        samples[0] = 0;
        expect(native.analyze(samples, 0, 3), [
          0.0,
          0.0,
          -1.0,
          0.0,
          0.0,
          -1.0,
          0.0,
          0.0,
          -1.0,
        ]);
      } finally {
        native.dispose();
      }
      native.dispose();
      expect(() => native.analyze(samples, 0, 1), throwsStateError);
    },
    skip: !nativeCwEnabled,
  );
}
