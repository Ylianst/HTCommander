/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// Manual ("Send Beacon Now") software beacon outcomes (issue #96): the beacon
// falls back to the radio's built-in GPS and reports a specific reason when no
// location fix is available.
//

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/gps/gps_data.dart';
import 'package:htcommander/handlers/software_beacon_config.dart';
import 'package:htcommander/handlers/software_beacon_handler.dart';
import 'package:htcommander/services/data_broker_client.dart';

const int radioId = 961;

void main() {
  late SoftwareBeaconHandler handler;
  late DataBrokerClient bus;
  final results = <Object?>[];
  final frames = <AprsFrameEventArgs>[];

  void configure(SoftwareBeaconConfig config) => bus.dispatch(
    deviceId: 0,
    name: 'SoftwareBeaconConfig',
    data: jsonEncode(config.toJson()),
  );

  Object? sendNow() {
    results.clear();
    bus.dispatch(
      deviceId: 0,
      name: 'SendSoftwareBeacon',
      data: true,
      store: false,
    );
    expect(results, hasLength(1));
    return results.single;
  }

  setUp(() {
    results.clear();
    frames.clear();
    bus = DataBrokerClient();
    bus.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    bus.dispatch(deviceId: 0, name: 'StationId', data: 0);
    bus.dispatch(deviceId: 1, name: 'GpsData', data: null);
    bus.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: [
        {'DeviceId': radioId},
      ],
    );
    bus.dispatch(deviceId: radioId, name: 'Position', data: null);
    bus.subscribe(
      deviceId: 0,
      name: 'SoftwareBeaconSent',
      callback: (_, _, data) => results.add(data),
    );
    bus.subscribe(
      deviceId: 1,
      name: 'AprsFrame',
      callback: (_, _, data) {
        if (data is AprsFrameEventArgs) frames.add(data);
      },
    );
    configure(const SoftwareBeaconConfig(manual: true));
    handler = SoftwareBeaconHandler()..init();
  });

  tearDown(() {
    handler.dispose();
    bus.dispose();
  });

  test('reports NoLocation when location is on but there is no fix', () {
    expect(sendNow(), SoftwareBeaconHandler.failNoLocation);
    expect(frames, isEmpty);
  });

  test('falls back to the radio GPS position', () {
    bus.dispatch(
      deviceId: radioId,
      name: 'Position',
      data: {'latitude': 45.5, 'longitude': -122.25, 'locked': true},
    );
    expect(sendNow(), isTrue);
    expect(frames, hasLength(1));
    expect(frames.single.ax25Packet.dataStr, startsWith('=4530.00N/12215.00W'));
  });

  test('ignores an unlocked radio GPS position', () {
    bus.dispatch(
      deviceId: radioId,
      name: 'Position',
      data: {'latitude': 45.5, 'longitude': -122.25, 'locked': false},
    );
    expect(sendNow(), SoftwareBeaconHandler.failNoLocation);
  });

  test('prefers the device 1 GPS fix over the radio position', () {
    bus.dispatch(
      deviceId: radioId,
      name: 'Position',
      data: {'latitude': 45.5, 'longitude': -122.25, 'locked': true},
    );
    bus.dispatch(
      deviceId: 1,
      name: 'GpsData',
      data: GpsData(latitude: 10.5, longitude: 20.25, isFixed: true),
    );
    expect(sendNow(), isTrue);
    expect(frames.single.ax25Packet.dataStr, startsWith('=1030.00N/02015.00E'));
  });

  test('accepts a JSON-mirrored device 1 GPS fix', () {
    bus.dispatch(
      deviceId: 1,
      name: 'GpsData',
      data: GpsData(latitude: 10.5, longitude: 20.25, isFixed: true).toJson(),
    );
    expect(sendNow(), isTrue);
    expect(frames.single.ax25Packet.dataStr, startsWith('=1030.00N/02015.00E'));
  });

  test('sends a status report without a fix when a message is set', () {
    configure(const SoftwareBeaconConfig(manual: true, message: 'Hello'));
    expect(sendNow(), isTrue);
    expect(frames.single.ax25Packet.dataStr, '>Hello');
  });

  test('reports NotConfigured without a callsign', () {
    bus.dispatch(deviceId: 0, name: 'CallSign', data: '');
    expect(sendNow(), SoftwareBeaconHandler.failNotConfigured);
  });
}
