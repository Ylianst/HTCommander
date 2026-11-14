/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// The BBS serves many clients at once: one AX.25 session per calling station,
// the XARA link and any generic BbsLink, each with its own conversation state
// and Winlink CMS relay.
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/ax25_session.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/winlink_gateway_relay.dart';

class _Relay extends WinlinkGatewayRelay {
  final String station;
  final result = Completer<bool>();
  bool disposed = false;

  _Relay(super.deviceId, super.broker, this.station);

  @override
  Future<bool> connectAsync(String stationCallsign, {int timeoutMs = 15000}) =>
      result.future;

  @override
  bool get isConnected => result.isCompleted && !disposed;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _TestLink extends BbsLink {
  @override
  final String remoteCallsign;
  @override
  final Map<String, Object?> sessionState = {};
  final sent = <int>[];
  bool closed = false;
  bool aborted = false;

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

  @override
  void abort() => aborted = closed = true;
}

void main() {
  const id = 430;
  late DataBrokerClient broker;
  late Bbs bbs;
  late List<_Relay> relays;
  late List<AX25Packet> out;
  late List<BbsControlMessageData> control;
  final originalFactory = Bbs.relayFactory;

  /// Delivers a frame from [from] to [to] as if heard on the radio.
  void frame(
    String from,
    int type, {
    String to = 'N0CALL',
    int ns = 0,
    int nr = 0,
    String? text,
    bool command = true,
  }) {
    final packet = AX25Packet(
      addresses: [AX25Address.parse(to)!, AX25Address.parse(from)!],
      type: type,
      command: command,
      pollFinal: type != FrameType.iFrame,
      ns: ns,
      nr: nr,
      data: text == null ? null : Uint8List.fromList(utf8.encode(text)),
    );
    broker.dispatch(
      deviceId: id,
      name: 'UniqueDataFrame',
      data: TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: packet.toByteArray(),
        channelId: 14,
        regionId: 0,
        incoming: true,
        radioDeviceId: id,
        encoding: FragmentEncodingType.hardwareAfsk1200,
      ),
      store: false,
    );
  }

  List<AX25Packet> sentTo(String call) =>
      out.where((p) => p.addresses[0].toString() == call).toList();

  List<AX25Packet> iFramesTo(String call) =>
      sentTo(call).where((p) => p.type == FrameType.iFrame).toList();

  String textTo(String call) =>
      iFramesTo(call).map((p) => utf8.decode(p.data ?? Uint8List(0))).join();

  /// Sends a line of text from [from] as its next in-sequence I-frame.
  final sentCounts = <String, int>{};
  void say(String from, String line) {
    final ns = sentCounts[from] ?? 0;
    sentCounts[from] = ns + 1;
    frame(
      from,
      FrameType.iFrame,
      ns: ns % 8,
      nr: iFramesTo(from).length % 8,
      text: line,
    );
  }

  _Relay relayFor(String station) =>
      relays.lastWhere((r) => r.station == station);

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    broker = DataBrokerClient();
    broker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    broker.dispatch(deviceId: 0, name: 'StationId', data: 0);
    broker.dispatch(deviceId: 0, name: 'AllowTransmit', data: 1);
    broker.dispatch(deviceId: 0, name: 'WinlinkPassword', data: '');
    relays = [];
    out = [];
    control = [];
    sentCounts.clear();
    Bbs.relayFactory = (deviceId, client) {
      // The relay is created right after the "Connected to" notice.
      final relay = _Relay(deviceId, client, control.last.callsign);
      relays.add(relay);
      return relay;
    };
    broker.subscribe(
      deviceId: id,
      name: 'TransmitDataFrame',
      callback: (_, _, data) =>
          out.add((data! as TransmitDataFrameData).packet!),
    );
    broker.subscribe(
      deviceId: 0,
      name: 'BbsControlMessage',
      callback: (_, _, data) => control.add(data! as BbsControlMessageData),
    );
    broker.dispatch(
      deviceId: id,
      name: 'LockState',
      data: {'isLocked': true, 'usage': 'BBS', 'lockId': 12},
    );
    bbs = Bbs(id)..enabled = true;
  });

  tearDown(() {
    bbs.dispose();
    for (final relay in relays) {
      if (!relay.result.isCompleted) relay.result.complete(false);
    }
    Bbs.relayFactory = originalFactory;
    broker.dispose();
    DataBroker.clearDevice(id);
    DataBroker.clearDevice(0);
  });

  test('several AX.25 stations are served independently', () async {
    frame('N1ABC', FrameType.uFrameSabm);
    frame('N2XYZ-3', FrameType.uFrameSabm);
    expect(bbs.links.map((l) => l.remoteCallsign), ['N1ABC', 'N2XYZ-3']);
    expect(sentTo('N1ABC').single.type, FrameType.uFrameUa);
    expect(sentTo('N2XYZ-3').single.type, FrameType.uFrameUa);

    for (final relay in relays) {
      relay.result.complete(false);
    }
    await settle();
    expect(textTo('N1ABC'), contains('[M] for menu'));
    expect(textTo('N2XYZ-3'), contains('[M] for menu'));

    say('N1ABC', 'S\r');
    say('N2XYZ-3', 'M\r');
    await settle();
    expect(textTo('N1ABC'), contains('open source'));
    expect(textTo('N1ABC'), isNot(contains('[D]isconnect')));
    expect(textTo('N2XYZ-3'), contains('[D]isconnect'));
    expect(textTo('N2XYZ-3'), isNot(contains('open source')));

    frame('N1ABC', FrameType.uFrameDisc);
    expect(sentTo('N1ABC').last.type, FrameType.uFrameUa);
    expect(bbs.links.map((l) => l.remoteCallsign), ['N2XYZ-3']);
    expect(
      control.where((c) => c.message == 'Disconnected').map((c) => c.callsign),
      ['N1ABC'],
    );
    await settle();
    expect(bbs.ax25Session('N1ABC'), isNull);

    say('N2XYZ-3', 'S\r');
    await settle();
    expect(textTo('N2XYZ-3'), contains('open source'));
    expect(
      bbs.ax25Session('N2XYZ-3')!.currentState,
      AX25ConnectionState.connected,
    );
  });

  test('status identifies only stations on its owning radio', () {
    const otherId = id + 1;
    broker.dispatch(
      deviceId: otherId,
      name: 'LockState',
      data: {'isLocked': true, 'usage': 'BBS', 'lockId': 13},
    );
    final other = Bbs(otherId)..enabled = true;
    addTearDown(() {
      other.dispose();
      DataBroker.clearDevice(otherId);
    });
    final messages = <int, SetLockStatusData>{};
    broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'SetLockStatus',
      callback: (radioId, _, data) => messages[radioId] = data! as SetLockStatusData,
    );
    final one = _TestLink('N1ABC');
    final two = _TestLink('N2XYZ');
    bbs.openLink(one, cmsRelay: false);
    bbs.openLink(two, cmsRelay: false);
    expect(messages[id]!.text, contains('N2XYZ'));
    expect(messages[id]!.lockId, 12);
    final saved = messages[id];
    other.openLink(_TestLink('N3XYZ'), cmsRelay: false);
    expect(messages[otherId]!.text, contains('N3XYZ'));
    expect(messages[otherId]!.lockId, 13);
    expect(messages[id], same(saved));
    bbs.closeLink(one);
    expect(messages[id]!.text, 'N1ABC: Disconnected');
    expect(messages[otherId]!.text, contains('N3XYZ'));
  });

  test('frames addressed to other stations are left alone', () async {
    frame('N1ABC', FrameType.uFrameSabm, to: 'W1AW');
    expect(out, isEmpty);
    expect(bbs.ax25Sessions, isEmpty);

    // A different SSID of our callsign is another station too.
    frame('N1ABC', FrameType.uFrameSabm, to: 'N0CALL-7');
    expect(out, isEmpty);

    frame('N1ABC', FrameType.uFrameSabm);
    relays.single.result.complete(false);
    await settle();
    final before = out.length;

    // N1ABC talking to someone else must not disturb its link with us.
    frame('N1ABC', FrameType.iFrame, to: 'W1AW', text: 'hello\r');
    frame('N1ABC', FrameType.uFrameDisc, to: 'W1AW');
    expect(out.length, before);
    expect(bbs.links, hasLength(1));

    // A stray command from an unknown station gets a DM and no session.
    frame('N3QRP', FrameType.sFrameRr);
    expect(sentTo('N3QRP').single.type, FrameType.uFrameDm);
    expect(bbs.ax25Session('N3QRP'), isNull);
    expect(bbs.ax25Sessions, hasLength(1));
  });

  test('each client gets its own Winlink CMS relay', () async {
    frame('N1ABC', FrameType.uFrameSabm);
    frame('N2XYZ', FrameType.uFrameSabm);
    expect(relays.map((r) => r.station), ['N1ABC', 'N2XYZ']);

    relayFor('N1ABC').result.complete(true);
    relayFor('N2XYZ').result.complete(false);
    await settle();
    expect(bbs.links.first.sessionState['wlRelayMode'], isTrue);
    expect(bbs.links.last.sessionState['wlRelayMode'], isFalse);
    expect(relayFor('N1ABC').disposed, isFalse);
    expect(relayFor('N2XYZ').disposed, isTrue);

    // A BBS command from one client only drops that client's relay.
    frame('N3OTH', FrameType.uFrameSabm);
    relayFor('N3OTH').result.complete(true);
    await settle();
    say('N3OTH', 'M\r');
    expect(relayFor('N3OTH').disposed, isTrue);
    expect(relayFor('N1ABC').disposed, isFalse);

    frame('N1ABC', FrameType.uFrameDisc);
    expect(relayFor('N1ABC').disposed, isTrue);
  });

  test('clients beyond maxLinks are told the BBS is busy', () async {
    bbs.maxLinks = 2;
    frame('N1ABC', FrameType.uFrameSabm);
    frame('N2XYZ', FrameType.uFrameSabm);
    frame('N3OTH', FrameType.uFrameSabm);
    expect(bbs.links.map((l) => l.remoteCallsign), ['N1ABC', 'N2XYZ']);
    expect(relays, hasLength(2));
    await settle();
    expect(textTo('N3OTH'), contains('BBS busy'));
    expect(sentTo('N3OTH').last.type, FrameType.iFrame);

    // The busy notice is delivered before the link is dropped.
    frame('N3OTH', FrameType.sFrameRr, nr: 1, command: false);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (sentTo('N3OTH').last.type != FrameType.uFrameDisc &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(sentTo('N3OTH').last.type, FrameType.uFrameDisc);

    // Once N3OTH has left and a slot frees up, a new caller is served.
    frame('N3OTH', FrameType.uFrameUa, command: false);
    frame('N1ABC', FrameType.uFrameDisc);
    frame('N3OTH', FrameType.uFrameSabm);
    expect(bbs.links.map((l) => l.remoteCallsign), ['N2XYZ', 'N3OTH']);
  });

  test('XARA and AX.25 clients are served at the same time', () async {
    broker.dispatch(
      deviceId: id,
      name: 'XaraEvent',
      data: {'evt': 'connected', 'caller': 'N5XAR', 'incoming': true},
      store: false,
    );
    frame('N1ABC', FrameType.uFrameSabm);
    expect(bbs.links.map((l) => l.protocol), ['XARA', 'Stream']);

    broker.dispatch(
      deviceId: id,
      name: 'XaraEvent',
      data: {'evt': 'disconnected'},
      store: false,
    );
    expect(bbs.links.map((l) => l.remoteCallsign), ['N1ABC']);
  });

  test('generic links can be attached, served and closed', () async {
    final local = _TestLink('LOCAL');
    bbs.openLink(local);
    frame('N1ABC', FrameType.uFrameSabm);
    for (final relay in relays) {
      relay.result.complete(false);
    }
    await settle();
    expect(local.text, contains('[M] for menu'));

    bbs.linkReceived(local, Uint8List.fromList(utf8.encode('S\r')));
    expect(local.text, contains('open source'));
    expect(textTo('N1ABC'), isNot(contains('open source')));

    bbs.closeLink(local);
    expect(bbs.links.map((l) => l.remoteCallsign), ['N1ABC']);
    bbs.linkReceived(local, Uint8List.fromList(utf8.encode('M\r')));
    expect(local.text, isNot(contains('[D]isconnect')));

    final other = _TestLink('OTHER');
    bbs.openLink(other);
    bbs.enabled = false;
    expect(other.aborted, isTrue);
    expect(bbs.links, isEmpty);
    expect(bbs.ax25Sessions, isEmpty);
  });
}
