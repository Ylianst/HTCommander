/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// BBS over XARA: incoming VARA FM links reach the BBS menu and Winlink server.
// The first group fakes the software modem's per-radio XARA broker API; the
// last test runs a real XARA peer modem against SoftwareModem in XARA mode.
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/xara_modem.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/winlink_gateway_relay.dart';

Future<bool> waitFor(
  bool Function() done, {
  Duration limit = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(limit);
  while (!done()) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return true;
}

/// Records what the BBS asks the XARA modem to do on one radio.
class FakeXara {
  final int id;
  final b = DataBrokerClient();
  final sent = <int>[];
  int disconnects = 0;

  FakeXara(this.id) {
    b.subscribe(
      deviceId: id,
      name: 'XaraSend',
      callback: (_, _, d) => sent.addAll(d! as Uint8List),
    );
    b.subscribe(
      deviceId: id,
      name: 'XaraDisconnect',
      callback: (_, _, _) {
        disconnects++;
        event({'evt': 'disconnected'});
      },
    );
  }

  void event(Map<String, Object?> e) =>
      b.dispatch(deviceId: id, name: 'XaraEvent', data: e, store: false);

  void connectFrom(String caller) => event({
    'evt': 'connected',
    'caller': caller,
    'answerer': 'N0CALL',
    'vias': <String>[],
    'wide': false,
  });

  void receive(String s) => b.dispatch(
    deviceId: id,
    name: 'XaraDataReceived',
    data: Uint8List.fromList(utf8.encode(s)),
    store: false,
  );

  String get text => utf8.decode(sent, allowMalformed: true);

  void dispose() => b.dispose();
}

/// A queued PCM burst played to the other side in real time after a lag.
class Playout {
  final int lagMs;
  final void Function(Uint8List chunk) deliver;
  final _queue = <(DateTime, Uint8List)>[];
  Uint8List? _cur;
  int _pos = 0;

  Playout(this.lagMs, this.deliver);

  void add(Uint8List pcm) =>
      _queue.add((DateTime.now().add(Duration(milliseconds: lagMs)), pcm));

  void tick() {
    if (_cur == null &&
        _queue.isNotEmpty &&
        !DateTime.now().isBefore(_queue.first.$1)) {
      _cur = _queue.removeAt(0).$2;
      _pos = 0;
    }
    final cur = _cur;
    if (cur == null) return;
    final end = (_pos + 1280).clamp(0, cur.length);
    deliver(Uint8List.fromList(cur.sublist(_pos, end)));
    _pos = end;
    if (_pos >= cur.length) _cur = null;
  }
}

void main() {
  final ui = DataBrokerClient();
  ui.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL', store: true);
  ui.dispatch(deviceId: 0, name: 'WinlinkPassword', data: '', store: true);
  // Keep the Winlink CMS relay off the network: it fails fast to local mode.
  Bbs.relayFactory = (id, broker) => WinlinkGatewayRelay(
    id,
    broker,
    server: '127.0.0.1',
    port: 1,
    useTls: false,
  );

  final control = <String>[];
  ui.subscribe(
    deviceId: 0,
    name: 'BbsControlMessage',
    callback: (_, _, d) => control.add((d! as BbsControlMessageData).message),
  );
  final stats = <StationStats>[];
  ui.subscribe(
    deviceId: 0,
    name: 'BbsStatsUpdated',
    callback: (_, _, d) => stats.add((d! as BbsStatsUpdatedData).stats),
  );
  setUp(() {
    control.clear();
    stats.clear();
  });

  test('an incoming XARA link gets the BBS banner and menu', () async {
    final xara = FakeXara(401);
    final bbs = Bbs(401)..enabled = true;
    try {
      xara.connectFrom('N1ABC-5');
      expect(await waitFor(() => xara.text.contains('[M] for menu')), isTrue);
      expect(xara.text, contains('[WL2K-5.0-B2FWIHJM\$]'));
      expect(bbs.activeLink?.remoteCallsign, 'N1ABC-5');
      expect(bbs.activeLink?.remoteAddress, 'N1ABC');
      expect(control, contains('Connected to N1ABC-5 (XARA)'));
      expect(stats.last.protocol, 'XARA');

      xara.receive('S\r');
      expect(await waitFor(() => xara.text.contains('open source')), isTrue);
      xara.receive('D\r');
      expect(await waitFor(() => xara.disconnects == 1), isTrue);
      expect(bbs.activeLink, isNull);
      expect(control.last, 'Disconnected');
    } finally {
      bbs.dispose();
      xara.dispose();
    }
  });

  test('a Winlink SID over XARA switches to the mail server', () async {
    final xara = FakeXara(402);
    final bbs = Bbs(402)..enabled = true;
    try {
      xara.connectFrom('N1ABC');
      expect(await waitFor(() => xara.text.endsWith('>\r')), isTrue);
      xara.sent.clear();
      xara.receive('[RMS Express-1.7.0-B2FHM\$]\rFF\r');
      expect(await waitFor(() => xara.text.contains('FQ\r')), isTrue);
      xara.receive('FQ\r');
      expect(await waitFor(() => xara.disconnects == 1), isTrue);
    } finally {
      bbs.dispose();
      xara.dispose();
    }
  });

  test('our own outgoing XARA connects and other radios are ignored', () async {
    final xara = FakeXara(403);
    final other = FakeXara(404);
    final bbs = Bbs(403)..enabled = true;
    try {
      xara.connectFrom('N0CALL');
      other.connectFrom('N1ABC');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bbs.activeLink, isNull);
      expect(xara.sent, isEmpty);
    } finally {
      bbs.dispose();
      xara.dispose();
      other.dispose();
    }
  });

  test('a disabled BBS does not answer XARA', () async {
    final xara = FakeXara(405);
    final bbs = Bbs(405);
    try {
      xara.connectFrom('N1ABC');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bbs.activeLink, isNull);
      expect(xara.sent, isEmpty);
    } finally {
      bbs.dispose();
      xara.dispose();
    }
  });

  test('link timeout ends the session; disposing hangs up', () async {
    final xara = FakeXara(406);
    var bbs = Bbs(406)..enabled = true;
    try {
      xara.connectFrom('N1ABC');
      expect(await waitFor(() => bbs.activeLink != null), isTrue);
      xara.event({'evt': 'timedOut'});
      expect(bbs.activeLink, isNull);
      expect(control.last, 'Disconnected');

      xara.connectFrom('N1ABC');
      expect(await waitFor(() => xara.text.contains('[M] for menu')), isTrue);
      bbs.dispose();
      expect(xara.disconnects, 1);
    } finally {
      bbs.dispose();
      xara.dispose();
    }
  });

  test(
    'a real XARA station connects to the BBS through SoftwareModem',
    () async {
      const radio = 407;
      final client = DataBrokerClient();
      client.dispatch(
        deviceId: 0,
        name: 'XaraTxLatencyMs',
        data: 400,
        store: true,
      );
      client.dispatch(deviceId: 0, name: 'XaraWide', data: false, store: true);
      final modem = SoftwareModem()..init();
      client.dispatch(
        deviceId: 0,
        name: 'SetSoftwareModemMode',
        data: 'XARA',
        store: false,
      );
      final bbs = Bbs(radio)..enabled = true;

      final peerEvents = <String>[];
      final peerData = <int>[];
      late final Playout toPeer, toRadio;
      final peer = XaraModem(
        config: const XaraModemConfig(callsign: 'N1ABC', txLatencyMs: 400),
        onTransmit: (pcm) => toRadio.add(pcm),
        onEvent: (e) {
          if (e['evt'] == 'data') {
            peerData.addAll(e['data']! as Uint8List);
          } else {
            peerEvents.add(e['evt']! as String);
          }
        },
      );
      toPeer = Playout(250, (c) => peer.pushRx(c, 0, c.length));
      toRadio = Playout(
        250,
        (c) => client.dispatch(
          deviceId: radio,
          name: 'AudioDataAvailable',
          data: {
            'data': c,
            'offset': 0,
            'length': c.length,
            'channelName': 'Data',
            'transmit': false,
          },
          store: false,
        ),
      );
      client.subscribe(
        deviceId: radio,
        name: 'TransmitVoicePCM',
        callback: (_, _, d) => toPeer.add((d! as Map)['Data'] as Uint8List),
      );
      final clock = Timer.periodic(const Duration(milliseconds: 20), (_) {
        toPeer.tick();
        toRadio.tick();
      });
      String peerText() => utf8.decode(peerData, allowMalformed: true);

      try {
        peer.connect('N0CALL', const []);
        expect(
          await waitFor(
            () => peerText().contains('>\r'),
            limit: const Duration(seconds: 60),
          ),
          isTrue,
          reason: '$peerEvents ${peerText()}',
        );
        expect(peerText(), contains('Handy-Talky Commander BBS'));
        expect(bbs.activeLink?.remoteCallsign, 'N1ABC');

        peer.send(Uint8List.fromList(utf8.encode('S\r')));
        expect(
          await waitFor(
            () => peerText().contains('open source'),
            limit: const Duration(seconds: 60),
          ),
          isTrue,
        );

        peer.send(Uint8List.fromList(utf8.encode('D\r')));
        expect(
          await waitFor(
            () => peerEvents.contains('disconnected') && bbs.activeLink == null,
            limit: const Duration(seconds: 60),
          ),
          isTrue,
          reason: '$peerEvents',
        );
      } finally {
        clock.cancel();
        bbs.dispose();
        peer.dispose();
        modem.dispose();
        client.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
