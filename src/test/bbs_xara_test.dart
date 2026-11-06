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
import 'package:htcommander/hamlib/xara/fm_ctrl.dart' show FmCode;
import 'package:htcommander/radio/packet_decoder.dart';
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/radio/xara_capture.dart';
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
  int cancellations = 0;

  FakeXara(this.id) {
    b.subscribe(
      deviceId: id,
      name: 'CancelDataTransmit',
      callback: (_, _, _) => cancellations++,
    );
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

  test('a Winlink SID split across XARA frames still reaches the mail server', () async {
    final xara = FakeXara(409);
    final bbs = Bbs(409)..enabled = true;
    try {
      xara.connectFrom('N1ABC');
      expect(await waitFor(() => xara.text.endsWith('>\r')), isTrue);
      xara.sent.clear();
      xara.receive('[RMS Express');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(xara.sent, isEmpty);
      xara.receive('-1.7.28.0-B2F');
      xara.receive('HM\$]\rFF\r');
      expect(await waitFor(() => xara.text.contains('FQ\r')), isTrue);
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
      xara.event({'evt': 'connected', 'caller': 'N1ABC', 'incoming': false});
      other.connectFrom('N1ABC');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bbs.activeLink, isNull);
      expect(xara.sent, isEmpty);

      // A station sharing our callsign is still answered when the modem says
      // the link is incoming.
      xara.event({'evt': 'connected', 'caller': 'N0CALL', 'incoming': true});
      expect(await waitFor(() => xara.text.contains('[M] for menu')), isTrue);
      expect(bbs.activeLink?.remoteCallsign, 'N0CALL');
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

  test('link timeout ends the session; disposing cancels without a handshake', () async {
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
      expect(xara.disconnects, 0);
      expect(xara.cancellations, 1);
    } finally {
      bbs.dispose();
      xara.dispose();
    }
  });

  test(
    'a real XARA station connects to the BBS through SoftwareModem',
    () => runOverTheAir(
      radio: 407,
      peerCall: 'N1ABC',
      target: 'N0CALL',
      stationId: 0,
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'same-callsign station dialing CALL-SSID reaches the BBS and is captured',
    () => runOverTheAir(
      radio: 408,
      peerCall: 'N0CALL',
      target: 'N0CALL-1',
      stationId: 1,
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'disabling a real XARA BBS stops replies and automatic reconnect responses',
    () => runOverTheAir(
      radio: 421,
      peerCall: 'N1ABC',
      target: 'N0CALL',
      stationId: 0,
      disableWhileConnected: true,
    ),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// Runs a real XARA peer modem against SoftwareModem (XARA mode) hosting a BBS
/// on [radio]: connect, read the banner, use the menu, disconnect. Also checks
/// the session is reported to the packet capture.
Future<void> runOverTheAir({
  required int radio,
  required String peerCall,
  required String target,
  required int stationId,
  bool disableWhileConnected = false,
}) async {
  final client = DataBrokerClient();
  client.dispatch(deviceId: 0, name: 'XaraTxLatencyMs', data: 400, store: true);
  client.dispatch(deviceId: 0, name: 'XaraWide', data: false, store: true);
  client.dispatch(deviceId: 0, name: 'StationId', data: stationId, store: true);
  final captured = <TncDataFragment>[];
  client.subscribe(
    deviceId: radio,
    name: 'CaptureFrame',
    callback: (_, _, d) => captured.add(d! as TncDataFragment),
  );
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
  final peerFrames = <Map<String, Object?>>[];
  late final Playout toPeer, toRadio;
  final peer = XaraModem(
    config: XaraModemConfig(callsign: peerCall, txLatencyMs: 400),
    onTransmit: (pcm) => toRadio.add(pcm),
    onEvent: (e) {
      if (e['evt'] == 'data') {
        peerData.addAll(e['data']! as Uint8List);
      } else if (e['evt'] == 'frame') {
        peerFrames.add(e);
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
  var transmissions = 0;
  client.subscribe(
    deviceId: radio,
    name: 'TransmitVoicePCM',
    callback: (_, _, d) {
      transmissions++;
      toPeer.add((d! as Map)['Data'] as Uint8List);
    },
  );
  final clock = Timer.periodic(const Duration(milliseconds: 20), (_) {
    toPeer.tick();
    toRadio.tick();
  });
  String peerText() => utf8.decode(peerData, allowMalformed: true);

  try {
    peer.connect(target, const []);
    expect(
      await waitFor(
        () => peerText().contains('>\r'),
        limit: const Duration(seconds: 60),
      ),
      isTrue,
      reason: '$peerEvents ${peerText()}',
    );
    expect(peerText(), contains('Handy-Talky Commander BBS'));
    expect(bbs.activeLink?.remoteCallsign, peerCall);

    peer.send(Uint8List.fromList(utf8.encode('S\r')));
    expect(
      await waitFor(
        () => peerText().contains('open source'),
        limit: const Duration(seconds: 60),
      ),
      isTrue,
    );

    if (disableWhileConnected) {
      bbs.enabled = false;
      final before = transmissions;
      expect(bbs.activeLink, isNull);
      expect(bbs.session, isNull);
      peer.send(Uint8List.fromList(utf8.encode('M\r')));
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(transmissions, before, reason: 'disabled BBS answered the old link');

      final attempted = Completer<void>();
      final newcomer = XaraModem(
        config: XaraModemConfig(callsign: 'N2ABC', txLatencyMs: 400),
        onTransmit: (pcm) {
          toRadio.add(pcm);
          if (!attempted.isCompleted) attempted.complete();
        },
        onEvent: (_) {},
      );
      try {
        newcomer.connect(target, const []);
        await attempted.future.timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(seconds: 5));
        expect(transmissions, before, reason: 'disabled BBS answered a new caller');
      } finally {
        newcomer.dispose();
      }
      return;
    }

    peer.send(Uint8List.fromList(utf8.encode('D\r')));
    expect(
      await waitFor(
        () => peerEvents.contains('disconnected') && bbs.activeLink == null,
        limit: const Duration(seconds: 60),
      ),
      isTrue,
      reason: '$peerEvents',
    );

    // The packet capture saw the connect request, our reply and session data.
    final frames = [for (final f in captured) (f, XaraCapture.parse(f.data)!)];
    expect(
      captured.every((f) => f.frameType == FragmentFrameType.xara),
      isTrue,
    );
    final connect = frames.firstWhere((f) => f.$2.connect != null);
    expect(connect.$1.incoming, isTrue);
    expect(connect.$2.connect!.source, peerCall);
    expect(connect.$2.connect!.target, target);
    expect(
      PacketDecoder.fragmentToShortString(connect.$1),
      '$peerCall>$target: XARA connect request (narrow)',
    );
    expect(
      frames.any(
        (f) =>
            !f.$1.incoming &&
            f.$2.isControl &&
            f.$2.code == FmCode.connectReplyNarrow,
      ),
      isTrue,
    );
    expect(
      frames.any(
        (f) =>
            !f.$1.incoming &&
            !f.$2.isControl &&
            !f.$2.isListen &&
            f.$2.record > 0,
      ),
      isTrue,
    );
    expect(
      frames.any(
        (f) =>
            f.$1.incoming &&
            !f.$2.isControl &&
            !f.$2.isListen &&
            f.$2.record > 0,
      ),
      isTrue,
    );

    // Every session frame carries debugging metadata from the live link.
    final rxData = frames.where(
      (f) => f.$1.incoming && !f.$2.isControl && !f.$2.isListen && f.$2.ok,
    );
    final txData = frames.where(
      (f) => !f.$1.incoming && !f.$2.isControl && !f.$2.isListen,
    );
    expect(rxData, isNotEmpty);
    expect(txData, isNotEmpty);
    expect(rxData.every((f) => f.$2.meta['bw'] == 'narrow'), isTrue);
    expect(rxData.every((f) => f.$2.meta['snr'] is num), isTrue);
    expect(rxData.every((f) => f.$2.meta['iter'] is num), isTrue);
    expect(txData.every((f) => f.$2.meta['lead'] is num), isTrue);
    expect(txData.every((f) => f.$2.meta['burstMs'] is num), isTrue);
    expect(
      txData.every(
        (f) => PacketDecoder.encodingLabel(
          f.$1,
        ).startsWith('Software XARA FM Narrow '),
      ),
      isTrue,
    );
    expect(
      frames.any(
        (f) =>
            f.$1.incoming &&
            PacketDecoder.fragmentToShortString(f.$1).contains('S'),
      ),
      isTrue,
    );

    // The BBS coded its connect reply with the key the caller listened for,
    // and both captures show it.
    final reply = frames.firstWhere(
      (f) =>
          !f.$1.incoming &&
          f.$2.isControl &&
          XaraCapture.usesCallerKey(f.$2.code),
    );
    expect(reply.$2.keyU, XaraCapture.callKey(peerCall));
    expect(reply.$2.codeTones, hasLength(10));
    expect(reply.$2.meta['rows'], isA<num>());
    expect(reply.$2.meta['burstMs'], isA<num>());
    final callerListen = peerFrames.firstWhere(
      (e) =>
          e['record'] == -2 &&
          ((e['meta']! as Map)['codes'] as List).contains(
            FmCode.connectReplyNarrow,
          ),
    );
    expect((callerListen['meta']! as Map)['keyU'], reply.$2.keyU);
    final heardReply = peerFrames.firstWhere(
      (e) => e['record'] == -1 && e['code'] == FmCode.connectReplyNarrow,
    );
    final heardMeta = heardReply['meta']! as Map;
    expect(heardMeta['keyU'], reply.$2.keyU);
    expect(heardMeta['hits'], isA<num>());
    expect(
      frames.any(
        (f) =>
            f.$2.isListen &&
            PacketDecoder.fragmentToShortString(
              f.$1,
            ).startsWith('XARA listening'),
      ),
      isTrue,
    );
  } finally {
    clock.cancel();
    bbs.dispose();
    peer.dispose();
    modem.dispose();
    client.dispatch(deviceId: 0, name: 'StationId', data: 0, store: true);
    client.dispose();
  }
}
