import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/radio.dart' show SetUnlockData;
import 'package:htcommander/radio/radio_models.dart' show kSatelliteLockUsage;
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/satellite_globe.dart';
import 'package:htcommander/widgets/satellite_tab.dart';

void main() {
  for (final (locale, use24Hour, dayOffset, expected) in [
    (const Locale('en', 'US'), false, 0, '1:05 PM \u2192 1:15 PM'),
    (const Locale('de'), false, 0, '13:05 \u2192 13:15'),
    (const Locale('en', 'US'), true, 0, '13:05 \u2192 13:15'),
    (const Locale('en', 'US'), false, 1, '1:05 PM \u2192 1:15 PM (+1 day)'),
    (const Locale('en', 'US'), false, 2, '1:05 PM \u2192 1:15 PM (+2 days)'),
  ]) {
    testWidgets(
      'upcoming pass times use $locale with 24h=$use24Hour day=$dayOffset',
      (tester) async {
        final broker = DataBrokerClient();
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          broker.dispose();
          DataBroker.clearDevice(0);
          tester.view.reset();
        });
        final tle = SatelliteTle.parseThreeLine(
          File('assets/satellites/amateur.tle').readAsStringSync(),
        ).first;
        broker.dispatch(
          deviceId: 0,
          name: 'SelectedSatelliteId',
          data: tle.noradId,
        );
        broker.dispatch(deviceId: 0, name: 'SatelliteShowGlobe', data: 0);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(alwaysUse24HourFormat: use24Hour),
              child: child!,
            ),
            home: const Scaffold(body: SatelliteTab()),
          ),
        );
        broker.dispatch(
          deviceId: 0,
          name: 'SatelliteCatalog',
          data: [SatelliteInfo(tle: tle)],
          store: false,
        );
        final today = DateTime.now();
        broker.dispatch(
          deviceId: 0,
          name: 'SatellitePasses',
          data: [
            SatellitePass(
              noradId: tle.noradId,
              name: tle.name,
              aos: DateTime(
                today.year,
                today.month,
                today.day + dayOffset,
                13,
                5,
              ).toUtc(),
              los: DateTime(
                today.year,
                today.month,
                today.day + dayOffset,
                13,
                15,
              ).toUtc(),
              maxElevationDeg: 45,
              aosAzimuthDeg: 90,
              losAzimuthDeg: 270,
            ),
          ],
          store: false,
        );
        await tester.pump();
        final titles = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data?.replaceAll(RegExp(r'\s+'), ' '));
        expect(titles, contains(expected));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final usage in ['Satellite', 'APRSSat']) {
    testWidgets('tapping an active $usage usage stops tracking', (
      tester,
    ) async {
      const radioId = 9401;
      final broker = DataBrokerClient();
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        broker.dispose();
        DataBroker.clearDevice(0);
        DataBroker.clearDevice(1);
        DataBroker.clearDevice(radioId);
        tester.view.reset();
      });
      final tle = SatelliteTle.parseThreeLine(
        File('assets/satellites/amateur.tle').readAsStringSync(),
      ).first;
      final sat = SatelliteInfo(
        tle: tle,
        transponder: SatelliteTransponder(
          noradId: tle.noradId,
          name: 'Test usage',
          usage: usage == 'APRSSat' ? 'APRS' : 'Voice',
          uplinkHz: 145990000,
          downlinkHz: 437800000,
          mode: 'FM',
          ctcssHz: null,
          inverting: false,
          status: 'active',
        ),
      );
      broker.dispatch(
        deviceId: 1,
        name: 'SelectedRadioDeviceId',
        data: radioId,
      );
      broker.dispatch(
        deviceId: 0,
        name: 'SelectedSatelliteId',
        data: sat.noradId,
      );
      broker.dispatch(deviceId: 0, name: 'SatelliteShowGlobe', data: 0);
      broker.dispatch(
        deviceId: radioId,
        name: 'LockState',
        data: {'isLocked': true, 'usage': usage},
      );
      broker.dispatch(
        deviceId: 0,
        name: 'SatelliteTrackingMarker',
        data: {'noradId': sat.noradId, 'usageIndex': 0},
      );
      final unlocks = <SetUnlockData>[];
      final targets = <Object?>[];
      broker.subscribe(
        deviceId: radioId,
        name: 'SetUnlock',
        callback: (_, _, data) {
          unlocks.add(data as SetUnlockData);
          broker.dispatch(
            deviceId: radioId,
            name: 'LockState',
            data: {'isLocked': false, 'usage': usage},
          );
        },
      );
      broker.subscribe(
        deviceId: 0,
        name: 'SatelliteTrackTarget',
        callback: (_, _, data) => targets.add(data),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SatelliteTab()),
        ),
      );
      broker.dispatch(
        deviceId: 0,
        name: 'SatelliteCatalog',
        data: [sat],
        store: false,
      );
      broker.dispatch(deviceId: 0, name: 'SatelliteObserverKnown', data: true);
      await tester.pump();
      expect(find.text('Tracking'), findsOneWidget);
      await tester.tap(find.text('Tap to stop tracking'));
      await tester.pump();
      expect(unlocks.single.usage, usage);
      expect(targets, [null]);
      expect(
        DataBroker.getValue<Object>(0, 'SatelliteTrackingMarker', null),
        isNull,
      );
      expect(find.text('Tracking'), findsNothing);
      expect(find.text('Tap to track on the radio'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Tap to track on the radio'),
            matching: find.byType(InkWell),
          ),
          matching: find.byIcon(Icons.satellite_alt),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('land fill never floods the globe', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(300, 300);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: const SizedBox(
            width: 300,
            height: 300,
            child: SatelliteGlobe(
              satellites: [],
              positions: {},
              observerLatDeg: null,
              observerLonDeg: null,
              minElevationDeg: 10,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    for (var step = 0; step < 150; step++) {
      final dy = (step % 30) < 15 ? 19.0 : -19.0;
      await tester.dragFrom(const Offset(150, 150), Offset(37, dy));
      await tester.pump();
      final frac = await tester.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage();
        final data = (await img.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var ocean = 0, total = 0;
        for (var y = 60; y < 240; y += 3) {
          for (var x = 60; x < 240; x += 3) {
            final dx = x - 150, dy = y - 150;
            if (dx * dx + dy * dy > 90 * 90) continue;
            final o = (y * 300 + x) * 4;
            final g = data.getUint8(o + 1), bl = data.getUint8(o + 2);
            total++;
            if (bl > g) ocean++;
          }
        }
        return ocean / total;
      });
      // Earth's land hemisphere is ~47% land, so ocean never drops near 0
      // unless a mis-clipped polygon floods the whole disk.
      expect(frac!, greaterThan(0.2), reason: 'step $step');
    }
  });

  testWidgets('single tap selects, double tap opens a satellite', (
    tester,
  ) async {
    final tles = SatelliteTle.parseThreeLine(
      File('assets/satellites/amateur.tle').readAsStringSync(),
    );
    final sat = SatelliteInfo(tle: tles.first);
    final taps = <int>[];
    final doubleTaps = <int>[];
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: SatelliteGlobe(
            satellites: [sat],
            positions: const {},
            observerLatDeg: null,
            observerLonDeg: null,
            minElevationDeg: 10,
            onSatelliteTap: taps.add,
            onSatelliteDoubleTap: doubleTaps.add,
          ),
        ),
      ),
    );

    // Find the satellite by probing; empty-space taps are spaced out so they
    // never pair up into a double tap.
    Offset? found;
    for (var y = 5.0; y < 360 && found == null; y += 9) {
      for (var x = 5.0; x < 395 && found == null; x += 9) {
        await tester.tapAt(Offset(x, y));
        await tester.pump();
        if (taps.isNotEmpty) found = Offset(x, y);
      }
    }
    if (found == null) {
      // Satellite is behind the Earth at this instant; nothing to assert.
      markTestSkipped('satellite hidden behind the globe');
      return;
    }
    expect(taps, [sat.noradId]);
    expect(doubleTaps, isEmpty);

    // Let the double-tap window lapse, then a fresh single tap selects only.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    taps.clear();
    await tester.tapAt(found);
    await tester.pump();
    expect(taps, [sat.noradId]);
    expect(doubleTaps, isEmpty);

    // A quick second tap on the same satellite is a double tap.
    await tester.tapAt(found);
    await tester.pump();
    expect(taps, [sat.noradId]);
    expect(doubleTaps, [sat.noradId]);
  });

  testWidgets('header globe button toggles a full-tab globe', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => DataBroker.clearDevice(0));
    final tles = SatelliteTle.parseThreeLine(
      File('assets/satellites/amateur.tle').readAsStringSync(),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SatelliteTab()),
      ),
    );
    DataBrokerClient().dispatch(
      deviceId: 0,
      name: 'SatelliteCatalog',
      data: [for (final t in tles.take(3)) SatelliteInfo(tle: t)],
      store: false,
    );
    await tester.pump();

    final list = find.byType(ListView);
    final globe = find.byType(SatelliteGlobe);
    final button = find.byTooltip('Full-tab globe');
    expect(list, findsOneWidget);
    expect(globe, findsOneWidget);
    final dockedSize = tester.getSize(globe);

    await tester.tap(button);
    await tester.pump();
    expect(list, findsNothing);
    expect(globe, findsOneWidget);
    expect(tester.getSize(globe).width, greaterThan(dockedSize.width));

    await tester.tap(find.byTooltip('Exit full-tab globe'));
    await tester.pump();
    expect(list, findsOneWidget);
    expect(tester.getSize(globe), dockedSize);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('globe shows only the tracked satellite in Satellite mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      DataBroker.clearDevice(0);
      DataBroker.clearDevice(1);
      DataBroker.clearDevice(9400);
    });
    final tles = SatelliteTle.parseThreeLine(
      File('assets/satellites/amateur.tle').readAsStringSync(),
    );
    final sats = [for (final t in tles.take(3)) SatelliteInfo(tle: t)];
    final tracked = sats[1].noradId;
    final broker = DataBrokerClient();
    broker.dispatch(deviceId: 1, name: 'SelectedRadioDeviceId', data: 9400);
    broker.dispatch(
      deviceId: 9400,
      name: 'LockState',
      data: {'isLocked': true, 'usage': kSatelliteLockUsage},
    );
    broker.dispatch(
      deviceId: 0,
      name: 'SatelliteTrackingMarker',
      data: {'noradId': tracked, 'usageIndex': 0},
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SatelliteTab()),
      ),
    );
    broker.dispatch(
      deviceId: 0,
      name: 'SatelliteCatalog',
      data: sats,
      store: false,
    );
    await tester.pump();

    List<int> globeIds() => tester
        .widget<SatelliteGlobe>(find.byType(SatelliteGlobe))
        .satellites
        .map((s) => s.noradId)
        .toList();
    expect(globeIds(), [tracked]);

    // Leaving Satellite mode brings every bird back.
    broker.dispatch(
      deviceId: 9400,
      name: 'LockState',
      data: {'isLocked': false, 'usage': kSatelliteLockUsage},
    );
    await tester.pump();
    expect(globeIds(), unorderedEquals(sats.map((s) => s.noradId)));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
