// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/satellite/native_satellite.dart';
import 'package:htcommander/satellite/satellite_coefficients.dart';
import 'package:htcommander/satellite/satellite_computation.dart';
import 'package:htcommander/satellite/satellite_globe_worker.dart';
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:htcommander/satellite/satellite_predictor.dart';
import 'package:satellite_observer/satellite_observer.dart' as so;

import 'support/satellite_cases.dart';

double _distance(so.Vector3 a, so.Vector3 b) {
  final x = a.x - b.x, y = a.y - b.y, z = a.z - b.z;
  return math.sqrt(x * x + y * y + z * z);
}

void _stateNear(so.EciState actual, so.EciState expected) {
  expect(actual.utc, expected.utc);
  expect(_distance(actual.position, expected.position), lessThan(1e-6));
  expect(_distance(actual.velocity, expected.velocity), lessThan(1e-9));
}

void _passesNear(List<so.Pass> actual, List<so.Pass> expected) {
  expect(actual.length, expected.length);
  for (var i = 0; i < actual.length; i++) {
    final a = actual[i], e = expected[i];
    expect(
      a.rise.utc.difference(e.rise.utc).inMicroseconds.abs(),
      lessThanOrEqualTo(100000),
    );
    expect(
      a.set.utc.difference(e.set.utc).inMicroseconds.abs(),
      lessThanOrEqualTo(100000),
    );
    expect(
      a.culmination.utc.difference(e.culmination.utc).inMicroseconds.abs(),
      lessThanOrEqualTo(50000),
    );
    expect(a.peakElevationDeg, closeTo(e.peakElevationDeg, 1e-5));
    expect(
      a.rise.lookAngle.azimuthDeg,
      closeTo(e.rise.lookAngle.azimuthDeg, 0.01),
    );
    expect(
      a.set.lookAngle.azimuthDeg,
      closeTo(e.set.lookAngle.azimuthDeg, 0.01),
    );
  }
}

void main() {
  final observer = so.Observer(
    latitudeDeg: 37.4,
    longitudeDeg: -122.1,
    altitudeMeters: 135,
  );

  test('explicit Dart path is exact; default selects supported backend', () {
    final elements = elementsFor(satelliteCases.first);
    final engine = SatelliteComputation(elements, useNative: false);
    addTearDown(engine.dispose);
    expect(engine.isNative, isFalse);
    final reference = so.Sgp4Engine(elements);
    final times = [
      elements.epoch,
      elements.epoch.add(const Duration(days: 3, microseconds: 123)),
    ];
    expect(engine.propagateBatch(times), [
      for (final t in times) reference.propagate(t),
    ]);
    final selected = SatelliteComputation(elements);
    addTearDown(selected.dispose);
    expect(selected.isNative, NativeSatellite.supported);
    final actual = selected.propagateBatch(times);
    final expected = engine.propagateBatch(times);
    for (var i = 0; i < times.length; i++) {
      _stateNear(actual[i], expected[i]);
    }
    final observation = SatelliteObservation(
      elements: elements,
      observer: observer,
    );
    addTearDown(observation.dispose);
    expect(observation.isNative, NativeSatellite.supported);
    if (!NativeSatellite.supported) {
      expect(NativeSatellite.create(Float64List(0)), isNull);
      expect(actual, expected);
    }
  });

  group('native numerical parity', () {
    test('incompatible coefficient ABI is an explicit creation error', () {
      expect(() => NativeSatellite.create(Float64List(0)), throwsStateError);
    });

    test(
      'flat native look grids match package geometry and endpoint times',
      () {
        final cases = [
          for (final tle in satelliteCases) elementsFor(tle),
          so.GpElements.fromMeanElements(
            epoch: DateTime.utc(1960, 1, 1, 23, 59, 59, 123, 456),
            inclinationDeg: 51.6,
            raanDeg: 98,
            eccentricity: 0.001,
            argPerigeeDeg: 12,
            meanAnomalyDeg: 52,
            meanMotionRevPerDay: 15,
          ),
        ];
        for (final elements in cases) {
          final native = NativeSatellite.create(
            satelliteCoefficients(elements),
          )!;
          try {
            for (final site in [
              observer,
              so.Observer(
                latitudeDeg: 90,
                longitudeDeg: 180,
                altitudeMeters: 500,
              ),
              so.Observer(
                latitudeDeg: -47,
                longitudeDeg: -179.9,
                altitudeMeters: -50,
              ),
            ]) {
              final reference = so.SatelliteObserver(
                elements: elements,
                observer: site,
              );
              final from = elements.epoch.subtract(
                const Duration(days: 4, microseconds: 1234567),
              );
              const step = Duration(seconds: 30, microseconds: 123);
              final to = from.add(
                Duration(microseconds: step.inMicroseconds * 512 + 7000001),
              );
              final rows = native.lookGrid(
                epochUs: elements.epoch.microsecondsSinceEpoch,
                fromUs: from.microsecondsSinceEpoch,
                toUs: to.microsecondsSinceEpoch,
                stepUs: step.inMicroseconds,
                latitudeDeg: site.latitudeDeg,
                longitudeDeg: site.longitudeDeg,
                altitudeMeters: site.altitudeMeters,
              );
              expect(rows.length, 514 * 5);
              for (var i = 0; i < 514; i++) {
                final t = i == 513
                    ? to
                    : from.add(Duration(microseconds: step.inMicroseconds * i));
                final expected = reference.lookAngleAt(t);
                final row = i * 5;
                expect(rows[row], 0);
                expect(rows[row + 1], closeTo(expected.azimuthDeg, 1e-7));
                expect(rows[row + 2], closeTo(expected.elevationDeg, 1e-7));
                expect(rows[row + 3], closeTo(expected.rangeKm, 1e-6));
                expect(rows[row + 4], closeTo(expected.rangeRateKmS, 1e-9));
              }
            }
          } finally {
            native.dispose();
          }
        }
      },
    );

    for (final tle in satelliteCases) {
      test('${tle.name}: batch/scalar, rewinds, microseconds, +/-30 days', () {
        final elements = elementsFor(tle);
        final engine = SatelliteComputation(elements, useNative: true);
        addTearDown(engine.dispose);
        // Never allow a missing asset to silently turn a native test into
        // a comparison of the Dart reference with itself.
        expect(engine.isNative, isTrue, reason: 'Native asset must be loaded');
        final reference = so.Sgp4Engine(elements);
        final random = math.Random(25544);
        final times = [
          for (final minutes in [
            0,
            360,
            720,
            1440,
            4320,
            -5184,
            -4896,
            43200,
            -43200,
            0,
          ])
            elements.epoch.add(Duration(minutes: minutes)),
          // Cross the 256-row FFI boundary twice in non-monotonic order.
          for (var i = 0; i < 513; i++)
            elements.epoch.add(
              Duration(
                microseconds: random.nextInt(86400000) * 60000 - 2592000000000,
              ),
            ),
          elements.epoch.toLocal(),
          elements.epoch.add(const Duration(microseconds: 1234567)),
          elements.epoch.subtract(const Duration(microseconds: 1)),
        ];
        final batch = engine.propagateBatch(times);
        for (var i = 0; i < times.length; i++) {
          _stateNear(batch[i], reference.propagate(times[i]));
        }
        for (final t in times.take(12)) {
          _stateNear(engine.propagate(t), reference.propagate(t));
        }
        expect(engine.propagateBatch([]), isEmpty);
      });
    }

    test('Vallado independent epoch and +360 minute verification vectors', () {
      final elements = elementsFor(satelliteCases.first);
      final engine = SatelliteComputation(elements, useNative: true);
      addTearDown(engine.dispose);
      expect(engine.isNative, isTrue);
      final states = engine.propagateBatch([
        elements.epoch,
        elements.epoch.add(const Duration(minutes: 360)),
      ]);
      final positions = [
        const so.Vector3(7022.46529266, -1400.08296755, 0.03995155),
        const so.Vector3(-7154.03120202, -3783.17682504, -3536.19412294),
      ];
      final velocities = [
        const so.Vector3(1.893841015, 6.405893759, 4.534807250),
        const so.Vector3(4.741887409, -4.151817765, -2.093935425),
      ];
      for (var i = 0; i < states.length; i++) {
        expect(_distance(states[i].position, positions[i]), lessThan(1e-6));
        expect(_distance(states[i].velocity, velocities[i]), lessThan(1e-9));
      }
    });

    test('circular/equatorial, retrograde and 225-minute branch boundary', () {
      for (final (inclination, eccentricity, period) in [
        (0.0, 0.0, 95.0),
        (179.999, 0.01, 100.0),
        (47.0, 0.005, 224.9),
        (47.0, 0.005, 225.1),
      ]) {
        final elements = so.GpElements.fromMeanElements(
          epoch: DateTime.utc(2026, 6, 1, 0, 0, 0, 123, 456),
          inclinationDeg: inclination,
          raanDeg: 271,
          eccentricity: eccentricity,
          argPerigeeDeg: 83,
          meanAnomalyDeg: 14,
          meanMotionRevPerDay: 1440 / period,
        );
        final engine = SatelliteComputation(elements, useNative: true);
        final reference = so.Sgp4Engine(elements);
        try {
          expect(engine.isNative, isTrue);
          for (final days in [-30, -1, 0, 1, 30, 0]) {
            final t = elements.epoch.add(Duration(days: days));
            _stateNear(engine.propagate(t), reference.propagate(t));
          }
        } finally {
          engine.dispose();
        }
      }
    });

    test('pass/geometry parity across LEO, HEO, MEO and GEO', () {
      for (final tle in satelliteCases) {
        final elements = elementsFor(tle);
        final accelerated = SatelliteObservation(
          elements: elements,
          observer: observer,
          useNative: true,
        );
        final reference = so.SatelliteObserver(
          elements: elements,
          observer: observer,
        );
        try {
          expect(accelerated.isNative, isTrue);
          final from = elements.epoch.subtract(const Duration(hours: 12));
          final to = from.add(const Duration(hours: 48, seconds: 7));
          for (final horizon in [0.0, 10.0, 40.0]) {
            _passesNear(
              accelerated.passes(from: from, to: to, minElevationDeg: horizon),
              reference.passes(from: from, to: to, minElevationDeg: horizon),
            );
          }
          // Geometry remains exactly the package implementation, including
          // Earth rotation's contribution to range rate/Doppler.
          for (final t in [from, to, elements.epoch]) {
            final a = accelerated.lookAngleAt(t), e = reference.lookAngleAt(t);
            expect(a.azimuthDeg, closeTo(e.azimuthDeg, 1e-7));
            expect(a.elevationDeg, closeTo(e.elevationDeg, 1e-7));
            expect(a.rangeKm, closeTo(e.rangeKm, 1e-6));
            expect(a.rangeRateKmS, closeTo(e.rangeRateKmS, 1e-9));
            final sub = accelerated.subPointAt(t),
                expected = reference.subPointAt(t);
            expect(sub.latitudeDeg, closeTo(expected.latitudeDeg, 1e-7));
            expect(sub.longitudeDeg, closeTo(expected.longitudeDeg, 1e-7));
            expect(sub.altitudeKm, closeTo(expected.altitudeKm, 1e-6));
          }
        } finally {
          accelerated.dispose();
        }
      }
    });

    test(
      'pass edges, custom grid and input errors retain package policies',
      () {
        final elements = elementsFor(satelliteCases[1]);
        final accelerated = SatelliteObservation(
          elements: elements,
          observer: observer,
          useNative: true,
        );
        addTearDown(accelerated.dispose);
        final reference = so.SatelliteObserver(
          elements: elements,
          observer: observer,
        );
        final from = DateTime.utc(2026, 7, 28);
        final to = from.add(const Duration(hours: 48));
        final pass = reference.passes(from: from, to: to).first;
        final windows = [
          (pass.culmination.utc, to), // Already in progress.
          (from, pass.culmination.utc), // Still in progress.
          (pass.culmination.utc, pass.set.utc), // Neither edge fully bracketed.
          (from, to),
        ];
        for (final (start, end) in windows) {
          _passesNear(
            accelerated.passes(
              from: start,
              to: end,
              sampleStep: const Duration(seconds: 17),
            ),
            reference.passes(
              from: start,
              to: end,
              sampleStep: const Duration(seconds: 17),
            ),
          );
        }
        for (final horizon in [-1.0, 90.0, double.infinity]) {
          expect(
            () => accelerated.passes(
              from: from,
              to: to,
              minElevationDeg: horizon,
            ),
            throwsArgumentError,
          );
        }
        expect(
          () => accelerated.passes(from: to, to: from),
          throwsArgumentError,
        );
        expect(
          () =>
              accelerated.passes(from: from, to: to, sampleStep: Duration.zero),
          throwsArgumentError,
        );
      },
    );

    test(
      'Vallado errors survive batching/prefetch and disposal is idempotent',
      () {
        final elements = elementsFor(decayingSatellite);
        final engine = SatelliteComputation(elements, useNative: true);
        final reference = so.Sgp4Engine(elements);
        final failureTime = elements.epoch.add(const Duration(minutes: 60));
        final times = [elements.epoch, failureTime];
        final code6 = throwsA(
          isA<so.PropagationException>().having(
            (error) => error.code,
            'code',
            6,
          ),
        );
        expect(() => reference.propagate(failureTime), code6);
        expect(() => engine.propagateBatch(times), code6);
        engine.prefetch(times);
        _stateNear(
          engine.propagate(times.first),
          reference.propagate(times.first),
        );
        expect(() => engine.propagate(failureTime), code6);
        engine.clearPrefetch();
        engine.dispose();
        engine.dispose();
        expect(() => engine.propagate(times.first), throwsStateError);
        expect(() => engine.propagateBatch([]), throwsStateError);
        final accelerated = SatelliteObservation(
          elements: elements,
          observer: observer,
        );
        addTearDown(accelerated.dispose);
        expect(
          () => accelerated.passes(from: elements.epoch, to: failureTime),
          code6,
        );
      },
    );

    test(
      'worker pass cache, horizon LOS and orbit epochs retain parity',
      () async {
        final tle = satelliteCases[1];
        final now = DateTime.utc(2026, 7, 28);
        final native = SatellitePredictor(
          observer: observer,
          satellites: [SatelliteInfo(tle: tle)],
        );
        final dart = SatellitePredictor(
          observer: observer,
          satellites: [SatelliteInfo(tle: tle)],
          useNative: false,
        );
        final globe = SatelliteGlobeWorker();
        final dartGlobe = SatelliteGlobeWorker(useNative: false);
        addTearDown(native.dispose);
        addTearDown(dart.dispose);
        addTearDown(globe.dispose);
        addTearDown(dartGlobe.dispose);
        final future = native.passes(tle.noradId, now, 10);
        expect(identical(future, native.passes(tle.noradId, now, 10)), isTrue);
        final passes = await future,
            expected = await dart.passes(tle.noradId, now, 10);
        expect(passes.length, expected.length);
        expect(passes, isNotEmpty);
        for (var i = 0; i < passes.length; i++) {
          expect(
            passes[i].aos.difference(expected[i].aos).inMilliseconds.abs(),
            lessThanOrEqualTo(100),
          );
          expect(
            passes[i].los.difference(expected[i].los).inMilliseconds.abs(),
            lessThanOrEqualTo(100),
          );
          expect(
            passes[i].maxElevationDeg,
            closeTo(expected[i].maxElevationDeg, 1e-5),
          );
        }
        expect(
          identical(
            future,
            native.passes(tle.noradId, now.add(const Duration(minutes: 4)), 10),
          ),
          isTrue,
        );
        final reference = so.SatelliteObserver(
          elements: elementsFor(tle),
          observer: observer,
        );
        final peak = reference
            .passes(from: now, to: now.add(const Duration(hours: 48)))
            .first
            .culmination
            .utc;
        expect(
          await native.los(tle.noradId, peak),
          await dart.los(tle.noradId, peak),
        );
        expect(
          await native.los(tle.noradId, now),
          await dart.los(tle.noradId, now),
        ); // Also preserve below-horizon policy.
        for (final seconds in [0, 119, 120, -1]) {
          final t = now.add(Duration(seconds: seconds));
          final a = (await globe.snapshot([tle], t))[tle.noradId]!;
          final e = (await dartGlobe.snapshot([tle], t))[tle.noradId]!;
          expect(a.orbitEpoch, e.orbitEpoch);
          expect(a.points.length, e.points.length);
          for (var i = 0; i < a.points.length; i++) {
            expect(a.points[i], closeTo(e.points[i], 1e-6));
          }
        }
      },
    );

    test(
      'native worker disposal and malformed-TLE errors remain observable',
      () async {
        final now = DateTime.utc(2026, 7, 28);
        final worker = SatellitePredictor(
          observer: observer,
          satellites: [SatelliteInfo(tle: satelliteCases[1])],
          useNative: true,
        );
        final pending = worker.passes(25544, now, 10);
        final rejected = expectLater(pending, throwsStateError);
        worker.dispose();
        worker.dispose();
        await rejected;
        await expectLater(worker.los(25544, now), throwsStateError);
        final malformed = SatellitePredictor(
          observer: observer,
          satellites: [
            SatelliteInfo(
              tle: const SatelliteTle(
                name: 'Malformed',
                noradId: 1,
                line1: '',
                line2: '',
              ),
            ),
          ],
          useNative: true,
        );
        addTearDown(malformed.dispose);
        await expectLater(malformed.passes(1, now, 10), throwsStateError);
      },
    );
  }, skip: !NativeSatellite.supported);
}
