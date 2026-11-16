// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/satellite_handler.dart';
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:htcommander/satellite/satellite_predictor.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:satellite_observer/satellite_observer.dart' as so;

const _tle = SatelliteTle(
  name: 'ISS',
  noradId: 25544,
  line1:
      '1 25544U 98067A   26209.15252568  .00010831  00000+0  20282-3 0  9992',
  line2:
      '2 25544  51.6320  97.3682 0007093 345.6120  14.4666 15.49220842578109',
);

void main() {
  final observer = so.Observer(latitudeDeg: 37.4, longitudeDeg: -122.1);
  final now = DateTime.utc(2026, 7, 28);
  final reference = so.SatelliteObserver(
    elements: so.GpElements.fromTle(_tle.line1, _tle.line2),
    observer: observer,
  );
  SatellitePredictor predictor() => SatellitePredictor(
    observer: observer,
    satellites: [SatelliteInfo(tle: _tle)],
  );

  test(
    'worker preserves 48-hour results and shares in-flight/cache searches',
    () async {
      final worker = predictor();
      addTearDown(worker.dispose);
      final expected = reference.passes(
        from: now,
        to: now.add(const Duration(hours: 48)),
      );
      final first = worker.passes(25544, now, 10);
      expect(identical(first, worker.passes(25544, now, 10)), isTrue);
      var heartbeat = false;
      Timer.run(() => heartbeat = true);
      final passes = await first;
      expect(heartbeat, isTrue);
      expect(passes.length, expected.length);
      expect(passes, isNotEmpty);
      for (var i = 0; i < passes.length; i++) {
        expect(passes[i].aos, expected[i].rise.utc);
        expect(passes[i].los, expected[i].set.utc);
        expect(passes[i].maxElevationDeg, expected[i].peakElevationDeg);
        expect(passes[i].aosAzimuthDeg, expected[i].rise.lookAngle.azimuthDeg);
        expect(passes[i].losAzimuthDeg, expected[i].set.lookAngle.azimuthDeg);
      }
      expect(
        identical(
          first,
          worker.passes(25544, now.add(const Duration(minutes: 4)), 10),
        ),
        isTrue,
      );
      final refreshed = worker.passes(
        25544,
        now.add(const Duration(minutes: 5)),
        10,
      );
      expect(identical(first, refreshed), isFalse);
      await refreshed;
      final higher = await worker.passes(25544, now, 30);
      expect(higher.every((p) => p.maxElevationDeg >= 30), isTrue);
      expect(higher.length, lessThan(passes.length));
      final noPass = worker.passes(25544, now, 89.999);
      expect(await noPass, isEmpty);
      expect(
        identical(
          noPass,
          worker.passes(25544, now.add(const Duration(seconds: 1)), 89.999),
        ),
        isTrue,
      );
    },
  );

  test('horizon LOS stays independent of the minimum pass elevation', () async {
    final worker = predictor();
    addTearDown(worker.dispose);
    final pass = reference
        .passes(from: now, to: now.add(const Duration(hours: 48)))
        .first;
    final peak = pass.culmination.utc;
    final los = await worker.los(25544, peak);
    expect(los, isNotNull);
    expect(los!.isAfter(pass.set.utc), isTrue);
    expect(reference.lookAngleAt(los).elevationDeg, lessThanOrEqualTo(0));
    expect(
      reference
          .lookAngleAt(los.subtract(const Duration(seconds: 1)))
          .elevationDeg,
      greaterThan(0),
    );
  });

  test(
    'dispose rejects outstanding replies; malformed TLEs surface errors',
    () async {
      final worker = predictor();
      final pending = worker.passes(25544, now, 10);
      final rejected = expectLater(pending, throwsStateError);
      worker.dispose();
      await rejected;
      final bad = SatellitePredictor(
        observer: observer,
        satellites: [
          SatelliteInfo(
            tle: const SatelliteTle(
              name: 'Bad',
              noradId: 1,
              line1: '',
              line2: '',
            ),
          ),
        ],
      );
      addTearDown(bad.dispose);
      await expectLater(bad.passes(1, now, 10), throwsStateError);
    },
  );

  testWidgets(
    'tracking reuses tick positions at the unchanged one-second cadence',
    (tester) async {
      const radioId = 9501;
      DataBroker.clearDevice(0);
      final broker = DataBrokerClient();
      final handler = SatelliteHandler();
      addTearDown(() {
        handler.dispose();
        broker.dispose();
        DataBroker.clearDevice(0);
        DataBroker.clearDevice(radioId);
      });
      broker.dispatch(deviceId: 0, name: 'SatelliteSupport', data: 1);
      broker.dispatch(deviceId: 0, name: 'SatObserverLat', data: 37.4);
      broker.dispatch(deviceId: 0, name: 'SatObserverLon', data: -122.1);
      await tester.runAsync(handler.init);
      // Restart with already-loaded seed data so the tick timer uses fake time.
      broker.dispatch(deviceId: 0, name: 'SatelliteSupport', data: 0);
      broker.dispatch(deviceId: 0, name: 'SatelliteSupport', data: 1);
      SatellitePosition? tickPosition;
      final updates = <SatelliteTrackParams>[];
      final tickSnapshots = <SatellitePosition?>[];
      broker.subscribe(
        deviceId: 0,
        name: 'SatellitePositions',
        callback: (_, _, data) {
          tickPosition = (data as List<SatellitePosition>)
              .where((p) => p.noradId == 25544)
              .firstOrNull;
        },
      );
      var isTick = false;
      broker.subscribe(
        deviceId: radioId,
        name: 'SatelliteTrackUpdate',
        callback: (_, _, data) {
          final update = data as SatelliteTrackParams;
          updates.add(update);
          if (isTick) tickSnapshots.add(tickPosition);
        },
      );
      broker.dispatch(
        deviceId: 0,
        name: 'SatelliteTrackTarget',
        data: {'radioDeviceId': radioId, 'noradId': 25544, 'usageIndex': 0},
      );
      expect(
        updates,
        hasLength(1),
      ); // Immediate tuning does not await prediction.
      isTick = true;
      await tester.pump(const Duration(milliseconds: 999));
      expect(updates, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(updates, hasLength(2));
      broker.dispatch(deviceId: 0, name: 'SatMinElevationDeg', data: 30);
      await tester.pump(const Duration(seconds: 1));
      expect(updates, hasLength(3));
      expect(tickSnapshots, hasLength(2));
      for (var i = 0; i < tickSnapshots.length; i++) {
        final position = tickSnapshots[i];
        final update = updates[i + 1];
        expect(position, isNotNull);
        expect(update.azimuthDeg, position!.azimuthDeg);
        expect(update.elevationDeg, position.elevationDeg);
        expect(update.rangeKm, position.rangeKm);
        expect(update.altitudeKm, position.altitudeKm);
      }

      final latePasses = <List<SatellitePass>>[];
      broker.subscribe(
        deviceId: 0,
        name: 'SatellitePasses',
        callback: (_, _, data) => latePasses.add(data as List<SatellitePass>),
      );
      broker.dispatch(deviceId: 0, name: 'SelectSatellite', data: 25544);
      broker.dispatch(deviceId: 0, name: 'SelectSatellite', data: null);
      broker.dispatch(deviceId: 0, name: 'SatelliteSupport', data: 0);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(updates, hasLength(3));
      expect(latePasses.every((passes) => passes.isEmpty), isTrue);
    },
  );
}
