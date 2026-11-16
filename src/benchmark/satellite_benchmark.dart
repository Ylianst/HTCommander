// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:io';
import 'dart:math' as math;

import 'package:htcommander/satellite/satellite_computation.dart';
import 'package:satellite_observer/satellite_observer.dart' as so;

import '../test/support/satellite_cases.dart';

double _checksum = 0;

double _distance(so.Vector3 a, so.Vector3 b) {
  final x = a.x - b.x, y = a.y - b.y, z = a.z - b.z;
  return math.sqrt(x * x + y * y + z * z);
}

void _checkStates(List<so.EciState> actual, List<so.EciState> expected) {
  if (actual.length != expected.length) {
    throw StateError('Sample count changed');
  }
  for (var i = 0; i < actual.length; i++) {
    final p = _distance(actual[i].position, expected[i].position);
    final v = _distance(actual[i].velocity, expected[i].velocity);
    if (!p.isFinite ||
        !v.isFinite ||
        p > 1e-6 ||
        v > 1e-9 ||
        actual[i].utc != expected[i].utc) {
      throw StateError('State parity failed at $i: $p km, $v km/s');
    }
  }
}

void _checkPasses(List<so.Pass> actual, List<so.Pass> expected) {
  if (actual.length != expected.length) throw StateError('Pass count changed');
  for (var i = 0; i < actual.length; i++) {
    final a = actual[i], e = expected[i];
    if (a.rise.utc.difference(e.rise.utc).inMicroseconds.abs() > 100000 ||
        a.set.utc.difference(e.set.utc).inMicroseconds.abs() > 100000 ||
        a.culmination.utc.difference(e.culmination.utc).inMicroseconds.abs() >
            50000 ||
        !a.peakElevationDeg.isFinite ||
        (a.peakElevationDeg - e.peakElevationDeg).abs() > 1e-5 ||
        (a.rise.lookAngle.azimuthDeg - e.rise.lookAngle.azimuthDeg).abs() >
            0.01 ||
        (a.set.lookAngle.azimuthDeg - e.set.lookAngle.azimuthDeg).abs() >
            0.01) {
      throw StateError('Pass parity failed at $i');
    }
  }
}

double _measure(void Function() operation, int iterations) {
  for (var i = 0; i < 3; i++) {
    operation();
  }
  final timings = <double>[];
  for (var trial = 0; trial < 7; trial++) {
    final timer = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      operation();
    }
    timer.stop();
    timings.add(timer.elapsedMicroseconds / iterations / 1000);
  }
  timings.sort();
  return timings[timings.length ~/ 2];
}

void _report(
  String label,
  void Function() reference,
  void Function() native,
  int iterations,
) {
  final dartMs = _measure(reference, iterations);
  final nativeMs = _measure(native, iterations);
  stdout.writeln(
    '$label: Dart ${dartMs.toStringAsFixed(3)} ms, '
    'native ${nativeMs.toStringAsFixed(3)} ms, '
    '${(dartMs / nativeMs).toStringAsFixed(2)}x',
  );
}

void main() {
  stdout.writeln(
    'Satellite SGP4/SDP4: medians of 7 trials; '
    'times include Dart conversion/allocation and FFI copies. '
    'Correctness is checked before timing; no network or new TLE data.',
  );
  final observer = so.Observer(
    latitudeDeg: 37.4,
    longitudeDeg: -122.1,
    altitudeMeters: 135,
  );
  for (final tle in satelliteCases) {
    final elements = elementsFor(tle);
    final native = SatelliteComputation(elements, useNative: true);
    final reference = so.Sgp4Engine(elements);
    final accelerated = SatelliteObservation(
      elements: elements,
      observer: observer,
      useNative: true,
    );
    final original = so.SatelliteObserver(
      elements: elements,
      observer: observer,
    );
    try {
      if (!native.isNative || !accelerated.isNative) {
        throw UnsupportedError(
          'Native satellite benchmark requires desktop or Android',
        );
      }
      final random = math.Random(20066753);
      final validationTimes = [
        for (var i = 0; i < 1025; i++)
          elements.epoch.add(
            Duration(
              microseconds: random.nextInt(86400000) * 60000 - 2592000000000,
            ),
          ),
        elements.epoch.add(const Duration(microseconds: 1234567)),
      ];
      _checkStates(native.propagateBatch(validationTimes), [
        for (final t in validationTimes) reference.propagate(t),
      ]);
      final from = elements.epoch.subtract(const Duration(hours: 12));
      final to = from.add(const Duration(hours: 48, seconds: 7));
      for (final horizon in [0.0, 10.0, 40.0]) {
        _checkPasses(
          accelerated.passes(from: from, to: to, minElevationDeg: horizon),
          original.passes(from: from, to: to, minElevationDeg: horizon),
        );
      }
      final periodMinutes = 2 * math.pi / elements.meanMotionRadPerMin;
      final samples = periodMinutes > 300 ? 240 : 160;
      final times = [
        for (var i = 0; i <= samples; i++)
          from.add(
            Duration(
              milliseconds: (periodMinutes * 60000 * i / samples).round(),
            ),
          ),
      ];
      _checkStates(native.propagateBatch(times), [
        for (final t in times) reference.propagate(t),
      ]);
      _report(
        '${tle.name} orbit (${times.length} samples)',
        () {
          for (final t in times) {
            _checksum += reference.propagate(t).position.x;
          }
        },
        () {
          for (final state in native.propagateBatch(times)) {
            _checksum += state.position.x;
          }
        },
        40,
      );
      _report(
        '${tle.name} 48h passes (30 s grid, 10 deg)',
        () {
          _checksum += original.passes(from: from, to: to).length;
        },
        () {
          _checksum += accelerated.passes(from: from, to: to).length;
        },
        1,
      );
      // Scalar numbers expose FFI overhead separately from batching benefit.
      _report(
        '${tle.name} scalar (varying time)',
        () {
          for (final t in times) {
            _checksum += reference.propagate(t).velocity.z;
          }
        },
        () {
          for (final t in times) {
            _checksum += native.propagate(t).velocity.z;
          }
        },
        20,
      );
    } finally {
      native.dispose();
      accelerated.dispose();
    }
  }
  if (!_checksum.isFinite) throw StateError('Non-finite benchmark checksum');
  stdout.writeln(
    'All position/velocity/pass parity checks passed; '
    'checksum ${_checksum.toStringAsFixed(6)}',
  );
}
