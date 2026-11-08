/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// BbsMonitor: the live list of BBS sessions (radio, local and web) and the
// recorded traffic history the BBS tab follows.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/bbs_monitor.dart';
import 'package:htcommander/handlers/bbs_store.dart';
import 'package:htcommander/handlers/web_bbs_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

class _TestLink extends BbsLink {
  @override
  final String remoteCallsign;
  @override
  final Map<String, Object?> sessionState = {};
  bool closed = false;

  _TestLink(this.remoteCallsign);

  @override
  String get protocol => 'Local';

  @override
  bool get isConnected => !closed;

  @override
  void send(Uint8List data) {}

  @override
  void disconnect() => closed = true;
}

List<BbsSessionInfo> _published() => [
  for (final s in DataBroker.getValueDynamic(1, 'BbsActiveSessions') as List)
    BbsSessionInfo.fromJson(s)!,
];

void main() {
  late BbsMonitor monitor;
  late DataBrokerClient broker;
  late List<BbsTrafficRecord> live;

  setUp(() {
    DataBroker.reset();
    broker = DataBrokerClient();
    broker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    monitor = BbsMonitor()..init();
    BbsMonitor.instance = monitor;
    live = [];
    broker.subscribe(
      deviceId: 1,
      name: 'BbsTrafficEntry',
      callback: (_, _, data) => live.add(BbsTrafficRecord.fromJson(data)!),
    );
  });

  tearDown(() {
    monitor.dispose();
    BbsMonitor.instance = BbsMonitor();
    broker.dispose();
    DataBroker.reset();
  });

  test('tracks sessions, counting repeated connections once', () {
    monitor.sessionStarted(0, 'w1aw', 'Web');
    monitor.sessionStarted(205, 'N0CALL', 'Local');
    monitor.sessionStarted(0, 'W1AW', 'Web');
    expect(_published().map((s) => s.key), ['0|W1AW', '205|N0CALL']);
    expect(_published().first.protocol, 'Web');

    monitor.sessionEnded(0, 'W1AW');
    expect(_published().length, 2, reason: 'one browser is still connected');
    monitor.sessionEnded(0, 'w1aw');
    expect(_published().map((s) => s.key), ['205|N0CALL']);
    monitor.sessionEnded(0, 'W1AW');
    expect(_published().length, 1);
  });

  test('records traffic, republishes it and serves the history', () {
    broker.dispatch(
      deviceId: 0,
      name: 'BbsTraffic',
      data: BbsTrafficData(
        deviceId: 430,
        callsign: 'n1abc',
        outgoing: true,
        message: 'Hello',
      ),
      store: false,
    );
    broker.dispatch(
      deviceId: 0,
      name: 'BbsControlMessage',
      data: BbsControlMessageData(deviceId: 430, message: 'BBS-wide'),
      store: false,
    );
    broker.dispatch(
      deviceId: 0,
      name: 'BbsError',
      data: BbsErrorEventData(deviceId: 430, callsign: 'N1ABC', error: 'Oops'),
      store: false,
    );
    expect(live.map((r) => r.seq), [1, 2, 3]);
    expect(live[0].key, '430|N1ABC');
    expect(live[0].outgoing, isTrue);
    expect(live[1].key, isNull);
    expect(live[2].kind, BbsTrafficKind.error);

    List<BbsTrafficRecord>? history;
    broker.subscribe(
      deviceId: 1,
      name: 'BbsTrafficHistory',
      callback: (_, _, data) => history = [
        for (final r in data! as List) BbsTrafficRecord.fromJson(r)!,
      ],
    );
    broker.dispatch(
      deviceId: 1,
      name: 'RequestBbsTraffic',
      data: null,
      store: false,
    );
    expect(history!.map((r) => r.message), ['Hello', 'BBS-wide', 'Oops']);

    broker.dispatch(
      deviceId: 1,
      name: 'ClearBbsTraffic',
      data: null,
      store: false,
    );
    expect(monitor.history, isEmpty);
  });

  test('the radio and local BBS report their sessions', () async {
    final bbs = Bbs(205)..enabled = true;
    bbs.menu = BbsMenu(store: BbsStore());
    final a = _TestLink('K7ABC-5');
    final b = _TestLink('N1XYZ');
    bbs.openLink(a, cmsRelay: false);
    bbs.openLink(b, cmsRelay: false);
    expect(_published().map((s) => s.key), ['205|K7ABC-5', '205|N1XYZ']);
    expect(_published().first.protocol, 'Local');

    bbs.linkReceived(a, Uint8List.fromList(utf8.encode('S\r')));
    expect(
      monitor.history
          .where((r) => r.key == '205|K7ABC-5')
          .map((r) => r.message),
      containsAll(['S', contains('open source')]),
    );

    bbs.closeLink(a);
    expect(_published().map((s) => s.key), ['205|N1XYZ']);
    bbs.enabled = false;
    expect(_published(), isEmpty);
    bbs.dispose();
  });

  test('the web BBS reports its sessions', () async {
    DataBroker.dispatch(deviceId: 0, name: 'bbsWebServerPort', data: 0);
    DataBroker.dispatch(deviceId: 0, name: 'bbsWebServerEnabled', data: 1);
    final handler = WebBbsHandler()..init();
    handler.menu = BbsMenu(store: BbsStore());
    for (var i = 0; i < 100 && handler.server?.boundPort == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${handler.server!.boundPort}/bbs?callsign=w1aw-7',
    );
    final messages = StreamIterator<Object?>(ws);
    expect(await messages.moveNext(), isTrue);
    expect(_published().single.key, '0|W1AW-7');
    expect(_published().single.protocol, 'Web');

    await ws.close();
    for (var i = 0; i < 100 && _published().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(_published(), isEmpty);
    handler.dispose();
  });
}
