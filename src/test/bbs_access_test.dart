/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// BBS station access list and the Winlink gateway setting (bbs_settings.dart).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/bbs_settings.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

class _TestLink extends BbsLink {
  @override
  final String remoteCallsign;
  @override
  final Map<String, Object?> sessionState = {};
  final sent = <int>[];
  bool closed = false;

  _TestLink(this.remoteCallsign);

  String get text => utf8.decode(sent, allowMalformed: true);

  @override
  String get protocol => 'Test';

  @override
  bool get isConnected => !closed;

  @override
  void send(Uint8List data) => sent.addAll(data);

  @override
  void disconnect() => closed = true;
}

void main() {
  group('isStationAllowed', () {
    test('deny list matches a base call on every SSID', () {
      final s = BbsSettings(deniedStations: ['N1ABC', 'K7XYZ-7']);
      expect(s.isStationAllowed('N1ABC'), isFalse);
      expect(s.isStationAllowed('n1abc-9'), isFalse);
      expect(s.isStationAllowed('K7XYZ-7'), isFalse);
      expect(s.isStationAllowed('K7XYZ'), isTrue);
      expect(s.isStationAllowed('K7XYZ-1'), isTrue);
      expect(s.isStationAllowed('W1AW'), isTrue);
    });

    test('allow list only lets listed stations in', () {
      final s = BbsSettings(
        allowListOnly: true,
        allowedStations: ['W1AW', 'K7XYZ-7'],
        deniedStations: ['W1AW'],
      );
      expect(s.isStationAllowed('W1AW-3'), isTrue);
      expect(s.isStationAllowed('K7XYZ-7'), isTrue);
      expect(s.isStationAllowed('K7XYZ'), isFalse);
      expect(s.isStationAllowed('N1ABC'), isFalse);
      expect(BbsSettings(allowListOnly: true).isStationAllowed('W1AW'), false);
    });

    test('SSID 0 is the same as no SSID', () {
      final s = BbsSettings(deniedStations: ['K7XYZ-0']);
      expect(s.isStationAllowed('K7XYZ'), isFalse);
      expect(s.isStationAllowed('K7XYZ-0'), isFalse);
      expect(s.isStationAllowed('K7XYZ-1'), isFalse);
    });

    test('settings survive JSON and default to open with the gateway on', () {
      final d = BbsSettings.fromJson({});
      expect(d.winlinkGatewayEnabled, isTrue);
      expect(d.allowListOnly, isFalse);
      expect(d.isStationAllowed('W1AW'), isTrue);

      final s = BbsSettings.fromJson(
        jsonDecode(
              jsonEncode(
                BbsSettings(
                  winlinkGatewayEnabled: false,
                  allowListOnly: true,
                  allowedStations: ['w1aw'],
                  deniedStations: ['N1ABC-0'],
                ).toJson(),
              ),
            )
            as Map<String, dynamic>,
      );
      expect(s.winlinkGatewayEnabled, isFalse);
      expect(s.allowListOnly, isTrue);
      expect(s.allowedStations, ['W1AW']);
      expect(s.deniedStations, ['N1ABC']);
    });
  });

  group('Bbs', () {
    const id = 461;
    late DataBrokerClient broker;
    late Bbs bbs;
    late int relayAttempts;
    final originalFactory = Bbs.relayFactory;

    setUp(() {
      broker = DataBrokerClient();
      broker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
      broker.dispatch(deviceId: 0, name: 'WinlinkPassword', data: '');
      relayAttempts = 0;
      Bbs.relayFactory = (deviceId, client) {
        relayAttempts++;
        throw StateError('no CMS in tests');
      };
      bbs = Bbs(id)..enabled = true;
    });

    tearDown(() {
      bbs.dispose();
      Bbs.relayFactory = originalFactory;
      BbsSettings().save(broker);
      broker.dispose();
      DataBroker.clearDevice(id);
      DataBroker.clearDevice(0);
    });

    test('turns away denied stations', () async {
      BbsSettings(deniedStations: ['N1ABC']).save(broker);
      final denied = _TestLink('N1ABC-5');
      bbs.openLink(denied);
      expect(denied.text, contains('Access denied'));
      expect(bbs.links, isEmpty);
      expect(relayAttempts, 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(denied.closed, isTrue);

      final other = _TestLink('W1AW');
      bbs.openLink(other);
      expect(bbs.links, [other]);
    });

    test('allow list mode only serves listed stations', () {
      BbsSettings(allowListOnly: true, allowedStations: ['W1AW']).save(broker);
      final stranger = _TestLink('N1ABC');
      bbs.openLink(stranger);
      expect(stranger.text, contains('Access denied'));
      final friend = _TestLink('W1AW-7');
      bbs.openLink(friend);
      expect(bbs.links, [friend]);
      expect(friend.text, isNot(contains('Access denied')));
    });

    test('the sysop local link skips the access list', () {
      BbsSettings(allowListOnly: true).save(broker);
      final local = _TestLink('N0CALL');
      bbs.openLink(local, cmsRelay: false, checkAccess: false);
      expect(bbs.links, [local]);
    });

    test('the Winlink gateway setting controls the CMS relay', () async {
      final a = _TestLink('W1AW');
      bbs.openLink(a);
      await Future<void>.delayed(Duration.zero);
      expect(relayAttempts, 1);
      expect(a.text, contains('[WL2K-'));

      BbsSettings(winlinkGatewayEnabled: false).save(broker);
      final b = _TestLink('K7XYZ');
      bbs.openLink(b);
      await Future<void>.delayed(Duration.zero);
      expect(relayAttempts, 1);
      expect(b.text, contains('[WL2K-'));
      expect(b.sessionState['wlRelayMode'], isFalse);
    });
  });
}
