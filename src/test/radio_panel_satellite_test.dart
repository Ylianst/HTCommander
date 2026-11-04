/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/radio_models.dart' as wire;
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/radio_panel.dart';

void main() {
  testWidgets('satellite mode replaces the channel grid with tracking info', (
    tester,
  ) async {
    const deviceId = 9500;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    DataBroker.clearDevice(deviceId);
    final broker = DataBrokerClient();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      broker.dispose();
      DataBroker.clearDevice(deviceId);
      tester.view.reset();
    });
    broker.dispatch(deviceId: deviceId, name: 'State', data: 'Connected');
    broker.dispatch(
      deviceId: deviceId,
      name: 'Channels',
      data: List.generate(
        6,
        (id) => wire.RadioChannelInfo(
          channelId: id,
          name: 'Channel $id',
          rxFreq: 146520000 + id * 25000,
          txFreq: 146520000 + id * 25000,
        ).toJson(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: RadioPanelControl(deviceId: deviceId)),
      ),
    );
    await tester.pump();

    final satPanel = find.byKey(const ValueKey('radioSatellitePanel'));
    expect(find.text('Channel 3'), findsOneWidget);
    expect(satPanel, findsNothing);

    void lock(bool locked) => broker.dispatch(
      deviceId: deviceId,
      name: 'LockState',
      data: {'isLocked': locked, 'usage': wire.kSatelliteLockUsage},
    );
    void track({required double elevation, int toAos = 0, int toLos = 0}) =>
        broker.dispatch(
          deviceId: deviceId,
          name: 'SatelliteTrackUpdate',
          data: SatelliteTrackParams(
            noradId: 25544,
            name: 'ISS',
            rxFreqHz: 437800000,
            txFreqHz: 145990000,
            txCtcssHz: 67.0,
            azimuthDeg: 135.4,
            elevationDeg: elevation,
            rangeKm: 1234.4,
            altitudeKm: 420.2,
            secondsToNextPass: toAos,
            secondsToLos: toLos,
          ),
          store: false,
        );

    lock(true);
    await tester.pump();
    expect(satPanel, findsOneWidget);
    expect(find.text('Channel 3'), findsNothing);
    expect(find.text('—'), findsWidgets); // waiting for the first update

    track(elevation: -12.3, toAos: 3725);
    await tester.pump();
    expect(find.text('Next pass in'), findsOneWidget);
    expect(find.text('1:02:05'), findsOneWidget);
    expect(find.text('135° SE'), findsOneWidget);
    expect(find.text('-12.3°'), findsOneWidget);
    expect(find.text('1234 km'), findsOneWidget);
    expect(find.text('420 km'), findsOneWidget);
    expect(find.text('145.990 MHz'), findsOneWidget);
    expect(find.text('Uplink · 67.0 Hz'), findsOneWidget);

    track(elevation: 23.5, toLos: 305);
    await tester.pump();
    expect(find.text('In view · sets in'), findsOneWidget);
    expect(find.text('5:05'), findsOneWidget);
    expect(find.text('23.5°'), findsOneWidget);

    // Tall tab: six full-width rows, 50 px each.
    final az = find.text('Azimuth');
    final el = find.text('Elevation');
    expect(tester.getSize(satPanel), const Size(400, 300));
    expect(tester.getCenter(az).dx, tester.getCenter(el).dx);
    expect(tester.getCenter(el).dy - tester.getCenter(az).dy, closeTo(50, 5));

    // Short tab: falls back to two rows of three.
    tester.view.physicalSize = const Size(400, 480);
    await tester.pump();
    expect(tester.getSize(satPanel).height, lessThanOrEqualTo(100));
    expect(tester.getCenter(az).dy, closeTo(tester.getCenter(el).dy, 5));
    expect(tester.getCenter(el).dx, greaterThan(tester.getCenter(az).dx));

    lock(false);
    await tester.pump();
    expect(satPanel, findsNothing);
    expect(find.text('Channel 3'), findsOneWidget);
  });
}
