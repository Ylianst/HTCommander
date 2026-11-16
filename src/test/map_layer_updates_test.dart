/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/meshcore/meshcore_manager.dart';
import 'package:htcommander/models/aircraft.dart';
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/utils/map_tile_source.dart';
import 'package:htcommander/widgets/map_tab.dart';
import 'package:htcommander/widgets/tab_visibility.dart';
import 'package:latlong2/latlong.dart';

void _send(int deviceId, String name, Object? data) =>
    DataBroker.dispatch(deviceId: deviceId, name: name, data: data);

Map<String, Object> _voice(double latitude) => {
  'source': 'TEST',
  'latitude': latitude,
  'longitude': -98.0,
  'time': DateTime.now().millisecondsSinceEpoch,
  'completed': true,
};

SatellitePosition _satellite(double latitude) => SatellitePosition(
  noradId: 25544,
  name: 'ISS',
  latitudeDeg: latitude,
  longitudeDeg: -98,
  altitudeKm: 420,
  azimuthDeg: 135,
  elevationDeg: 30,
  rangeKm: 800,
  rangeRateKmS: 1,
  utc: DateTime.now().toUtc(),
);

Widget _app({bool visible = true, bool dark = false}) => MaterialApp(
  theme: dark ? ThemeData.dark() : ThemeData.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: TabVisibility(visible: visible, child: const MapTab()),
  ),
);

List<Marker> _markers(WidgetTester tester, String key) =>
    tester.widget<MarkerLayer>(find.byKey(ValueKey(key))).markers;

List<Polyline> _tracks(WidgetTester tester, String key) =>
    tester.widget<PolylineLayer>(find.byKey(ValueKey(key))).polylines;

void main() {
  setUp(() {
    for (final id in [0, 1, meshCoreDeviceId]) {
      DataBroker.clearDevice(id);
    }
    // Disable raster tiles so these layer tests need neither disk nor network.
    _send(0, customMapEnabledKey, 1);
    _send(0, customMapUrlKey, '');
    _send(0, 'ShowAirplanesOnMap', 1);
    _send(0, 'ShowSatellitesOnMap', 1);
    _send(0, 'SatelliteSupport', 1);
    _send(0, 'MeshCoreSupport', 1);
    _send(meshCoreDeviceId, 'MeshCoreInfo', {
      'publicKey': 'self',
      'name': 'Companion',
      'lat': 40.0,
      'lon': -98.0,
    });
    _send(1, 'DecodedTextHistory', [_voice(38), _voice(39)]);
  });

  tearDown(() {
    for (final id in [0, 1, meshCoreDeviceId]) {
      DataBroker.clearDevice(id);
    }
  });

  testWidgets('live layers update without rebuilding unrelated collections', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final stations = _markers(tester, 'mapStationMarkers');
    final mesh = stations.first;
    final tracks = _tracks(tester, 'mapStationTracks');
    expect(stations.map((m) => m.point.latitude), [40, 39]);

    _send(0, 'Airplanes', [
      const Aircraft(flight: 'TEST FLIGHT', latitude: 39, longitude: -97),
    ]);
    _send(0, 'SatelliteGroundTrack', [
      [38.0, 179.0],
      [39.0, 179.5],
      [40.0, -179.5],
      [41.0, -179.0],
    ]);
    _send(0, 'SatellitePositions', [_satellite(39)]);
    await tester.pump();
    final airplanes = _markers(tester, 'mapAirplaneMarkers');
    final satTrack = _tracks(tester, 'mapSatelliteTrack');
    expect(satTrack, hasLength(2));
    expect(_markers(tester, 'mapSatelliteMarkers').single.point.latitude, 39);
    expect(
      tester
          .widget<CircleLayer>(
            find.byKey(const ValueKey('mapSatelliteFootprints')),
          )
          .circles
          .single
          .point
          .latitude,
      39,
    );

    _send(0, 'SatellitePositions', [_satellite(40)]);
    _send(0, 'SelectedSatelliteId', 25544);
    await tester.pump();
    expect(tester.widget<FlutterMap>(find.byType(FlutterMap)), same(map));
    expect(_markers(tester, 'mapStationMarkers'), same(stations));
    expect(_tracks(tester, 'mapStationTracks'), same(tracks));
    expect(_markers(tester, 'mapAirplaneMarkers'), same(airplanes));
    expect(_tracks(tester, 'mapSatelliteTrack'), same(satTrack));
    expect(_markers(tester, 'mapSatelliteMarkers').single.point.latitude, 40);
    final satelliteIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('mapSatelliteMarkers')),
        matching: find.byIcon(Icons.satellite_alt),
      ),
    );
    expect(satelliteIcon.color, Colors.amber);

    final satellites = _markers(tester, 'mapSatelliteMarkers');
    _send(0, 'Airplanes', [
      const Aircraft(flight: 'TEST FLIGHT', latitude: 41, longitude: -97),
    ]);
    await tester.pump();
    expect(_markers(tester, 'mapAirplaneMarkers').single.point.latitude, 41);
    expect(_markers(tester, 'mapSatelliteMarkers'), same(satellites));
    expect(_markers(tester, 'mapStationMarkers'), same(stations));
    expect(tester.widget<FlutterMap>(find.byType(FlutterMap)), same(map));

    _send(1, 'TextReady', _voice(42));
    await tester.pump();
    final updated = _markers(tester, 'mapStationMarkers');
    expect(updated.map((m) => m.point.latitude), [42, 40]);
    expect(updated.last, same(mesh));
    expect(_tracks(tester, 'mapStationTracks').single.points.last.latitude, 42);
    expect(_markers(tester, 'mapSatelliteMarkers'), same(satellites));
    expect(_tracks(tester, 'mapSatelliteTrack'), same(satTrack));

    _send(0, 'SatellitePositions', []);
    _send(0, 'SatelliteGroundTrack', []);
    _send(0, 'Airplanes', []);
    await tester.pump();
    expect(_markers(tester, 'mapSatelliteMarkers'), isEmpty);
    expect(_markers(tester, 'mapAirplaneMarkers'), isEmpty);
    expect(_tracks(tester, 'mapSatelliteTrack'), isEmpty);
    expect(_markers(tester, 'mapStationMarkers'), same(updated));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cached collections follow contacts, theme and mesh updates', (
    tester,
  ) async {
    _send(0, 'MapShowContactsOnly', 1);
    _send(0, 'Stations', [
      {'Callsign': 'TEST'},
    ]);
    await tester.pumpWidget(_app());
    await tester.pump();
    final stations = _markers(tester, 'mapStationMarkers');
    final tracks = _tracks(tester, 'mapStationTracks');

    _send(1, 'WinlinkBusy', true);
    await tester.pump();
    expect(_markers(tester, 'mapStationMarkers'), same(stations));
    expect(_tracks(tester, 'mapStationTracks'), same(tracks));

    await tester.pumpWidget(_app(dark: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_markers(tester, 'mapStationMarkers'), isNot(same(stations)));
    expect(_tracks(tester, 'mapStationTracks'), same(tracks));

    _send(0, 'Stations', []);
    await tester.pump();
    expect(_markers(tester, 'mapStationMarkers').single.point.latitude, 40);
    expect(find.byKey(const ValueKey('mapStationTracks')), findsNothing);
    _send(0, 'Stations', [
      {'Callsign': 'TEST'},
    ]);
    _send(meshCoreDeviceId, 'MeshCoreInfo', {
      'publicKey': 'self',
      'name': 'Companion',
      'lat': 43.0,
      'lon': -98.0,
    });
    await tester.pump();
    expect(_markers(tester, 'mapStationMarkers').map((m) => m.point.latitude), [
      43,
      39,
    ]);
    expect(_tracks(tester, 'mapStationTracks').single.points, [
      const LatLng(38, -98),
      const LatLng(39, -98),
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden live layers resume with their latest snapshots', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    _send(0, 'SatellitePositions', [_satellite(39)]);
    await tester.pump();
    await tester.pumpWidget(_app(visible: false));
    await tester.pump();
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    _send(0, 'SatellitePositions', [_satellite(41)]);
    _send(0, 'Airplanes', [
      const Aircraft(flight: 'LATEST', latitude: 42, longitude: -97),
    ]);
    await tester.pump();
    expect(tester.widget<FlutterMap>(find.byType(FlutterMap)), same(map));
    expect(find.byKey(const ValueKey('mapSatelliteMarkers')), findsNothing);
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_markers(tester, 'mapSatelliteMarkers').single.point.latitude, 41);
    expect(_markers(tester, 'mapAirplaneMarkers').single.point.latitude, 42);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('APRS caches follow movement, internet filtering and clearing', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    final mesh = _markers(tester, 'mapStationMarkers').first;
    void beacon(String latitude) {
      final packet = Tnc2Codec.decode(
        'W1AW-9>APRS:!${latitude}N/09800.00W>Test',
      )!;
      final aprs = AprsPacket.parse(packet)!..fromAprsIs = true;
      _send(1, 'AprsFrame', AprsFrameEventArgs(aprs, packet, null));
    }

    beacon('4100.00');
    await tester.pump();
    beacon('4200.00');
    await tester.pump();
    final stations = _markers(tester, 'mapStationMarkers');
    expect(stations.map((m) => m.point.latitude), [42, 40, 39]);
    expect(stations[1], same(mesh));
    final tracks = _tracks(tester, 'mapStationTracks');
    expect(tracks, hasLength(2));
    expect(tracks.first.points.map((p) => p.latitude), [41, 42]);

    _send(0, 'SatellitePositions', [_satellite(43)]);
    await tester.pump();
    expect(_markers(tester, 'mapStationMarkers'), same(stations));
    expect(_tracks(tester, 'mapStationTracks'), same(tracks));

    _send(0, 'AprsShowAprsIs', 0);
    await tester.pump();
    expect(_markers(tester, 'mapStationMarkers').map((m) => m.point.latitude), [
      40,
      39,
    ]);
    expect(_tracks(tester, 'mapStationTracks'), hasLength(1));
    _send(0, 'AprsShowAprsIs', 1);
    await tester.pump();
    expect(_markers(tester, 'mapStationMarkers'), hasLength(3));
    _send(1, 'AprsPacketsCleared', null);
    await tester.pump();
    expect(_markers(tester, 'mapStationMarkers').map((m) => m.point.latitude), [
      40,
      39,
    ]);
    expect(_tracks(tester, 'mapStationTracks'), hasLength(1));
    expect(_markers(tester, 'mapStationMarkers').first, same(mesh));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
