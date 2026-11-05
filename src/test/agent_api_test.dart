/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// The agent automation protocol over the web server's WebSocket: opt-in,
// token-authenticated, read-only access to the packet capture, logs, events
// and selected values (see docs/blogs/ai-agent-radio-testing.md).
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart' show FmCode;
import 'package:htcommander/handlers/agent_api.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/packet_store.dart';
import 'package:htcommander/handlers/terminal_handler.dart';
import 'package:htcommander/handlers/web_server_handler.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/radio/radio.dart' show SetLockData, SetUnlockData;
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/radio/xara_capture.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/host_bridge.dart';
import 'package:htcommander/utils/map_tile_source.dart';

const String token = 'test-token-0123456789';

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// A minimal agent client: sends `agent:` requests and collects replies,
/// pushed events and the web UI's own messages.
class Agent {
  Agent(this.socket) {
    socket.listen((m) {
      if (m is! String) return;
      if (!m.startsWith('agent:')) {
        other.add(m);
        return;
      }
      final body = jsonDecode(m.substring(6)) as Map<String, dynamic>;
      if (body.containsKey('event')) {
        events.add(body);
      } else {
        replies.add(body);
      }
    });
  }

  final WebSocket socket;
  final replies = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];
  final other = <String>[];
  int _id = 0;

  Future<Map<String, dynamic>> call(String op, [Map<String, Object?>? args]) {
    final id = ++_id;
    socket.add('agent:${jsonEncode({'id': id, 'op': op, ...?args})}');
    return waitFor(() => replies.where((r) => r['id'] == id).firstOrNull);
  }

  void close() => socket.close();
}

Future<T> waitFor<T>(T? Function() find) async {
  for (var i = 0; i < 200; i++) {
    final v = find();
    if (v != null) return v;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('no result');
}

/// Records what agent commands ask of a radio and plays its lock state.
class FakeRadio {
  FakeRadio(this.id) {
    DataBroker.dispatch(
      deviceId: id,
      name: 'LockState',
      data: {'isLocked': false},
    );
    DataBroker.dispatch(
      deviceId: id,
      name: 'HtStatus',
      data: {'currRegion': 0, 'isInTx': false},
    );
    DataBroker.dispatch(
      deviceId: id,
      name: 'RegionNames',
      data: ['Home', 'Away'],
    );
    DataBroker.dispatch(
      deviceId: id,
      name: 'Channels',
      data: [
        {'name': 'APRS', 'channelId': 0},
        {'name': 'BBS', 'channelId': 4},
      ],
    );
    DataBroker.dispatch(deviceId: id, name: 'Settings', data: {'channelA': 2});
    _b.subscribe(
      deviceId: id,
      name: 'SetLock',
      callback: (_, _, d) {
        final l = d! as SetLockData;
        locks.add(l);
        DataBroker.dispatch(
          deviceId: id,
          name: 'LockState',
          data: {'isLocked': true, 'usage': l.usage},
        );
      },
    );
    _b.subscribe(
      deviceId: id,
      name: 'SetUnlock',
      callback: (_, _, d) {
        commands.add('SetUnlock:${(d! as SetUnlockData).usage}');
        DataBroker.dispatch(
          deviceId: id,
          name: 'LockState',
          data: {'isLocked': false},
        );
      },
    );
    for (final n in [
      'XaraConnect',
      'XaraSend',
      'XaraDisconnect',
      'XaraAbort',
    ]) {
      _b.subscribe(
        deviceId: id,
        name: n,
        callback: (_, _, d) {
          commands.add(n);
          payloads[n] = d;
        },
      );
    }
  }

  final int id;
  final _b = DataBrokerClient();
  final locks = <SetLockData>[];
  final commands = <String>[];
  final payloads = <String, Object?>{};

  void dispose() => _b.dispose();
}

void main() {
  late WebServerHandler handler;
  late int port;
  final store = PacketStore();

  setUpAll(() async {
    await store.init();
    DataBroker.addDataHandler('PacketStore', store);
  });

  setUp(() async {
    port = await _freePort();
    DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    DataBroker.dispatch(deviceId: 0, name: 'StationId', data: 1);
    DataBroker.dispatch(deviceId: 0, name: AgentApi.tokenSetting, data: token);
    DataBroker.dispatch(deviceId: 0, name: AgentApi.enabledSetting, data: 1);
    DataBroker.dispatch(deviceId: 0, name: 'RepeaterBookToken', data: 'rb');
    DataBroker.dispatch(deviceId: 0, name: 'webServerPort', data: port);
    DataBroker.dispatch(deviceId: 0, name: 'webServerEnabled', data: 1);
    handler = WebServerHandler()..init();
  });

  tearDown(() {
    handler.dispose();
    DataBroker.dispatch(deviceId: 0, name: 'webServerEnabled', data: 0);
  });

  Future<Agent> connect() async {
    for (var i = 0; ; i++) {
      try {
        return Agent(
          await WebSocket.connect('ws://127.0.0.1:$port/websocket.aspx'),
        );
      } catch (_) {
        if (i > 50) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<Agent> authenticated() async {
    final a = await connect();
    final hello = await a.call('hello', {'token': token});
    expect(hello['ok'], isTrue, reason: '$hello');
    return a;
  }

  test('is off unless the operator enables it', () async {
    DataBroker.dispatch(deviceId: 0, name: AgentApi.enabledSetting, data: 0);
    final a = await connect();
    final r = await a.call('hello', {'token': token});
    expect(r['ok'], isFalse);
    expect(r['error'], 'agent API disabled');
    a.close();
  });

  test('requires the token before anything else', () async {
    final a = await connect();
    expect((await a.call('packets'))['error'], contains('not authenticated'));
    expect((await a.call('hello', {'token': 'wrong'}))['error'], 'bad token');
    expect((await a.call('hello'))['error'], 'bad token');

    final hello = await a.call('hello', {'token': token});
    expect(hello['ok'], isTrue);
    expect(hello['station'], 'N0CALL-1');
    expect(hello['readOnly'], isFalse);
    expect(hello['commands'], contains('xara.connect'));
    expect(hello['events'], contains('PacketStored'));
    expect(DateTime.parse(hello['hostTime'] as String).isUtc, isTrue);
    expect((await a.call('ping'))['ok'], isTrue);
    a.close();
  });

  test('stops answering after repeated bad tokens', () async {
    final a = await connect();
    for (var i = 0; i < AgentApi.maxAuthFailures; i++) {
      await a.call('hello', {'token': 'guess$i'});
    }
    a.socket.add(
      'agent:${jsonEncode({'id': 99, 'op': 'hello', 'token': token})}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(a.replies.where((r) => r['id'] == 99), isEmpty);
    a.close();
  });

  test('streams subscribed events, with XARA frames decoded', () async {
    final a = await authenticated();
    final bad = await a.call('subscribe', {
      'events': ['SendRawCommand'],
    });
    expect(bad['ok'], isFalse);
    expect(bad['error'], contains('unknown events'));

    final sub = await a.call('subscribe', {
      'events': ['PacketStored', 'LogInfo', 'XaraEvent'],
    });
    expect(
      sub['events'],
      containsAll(['PacketStored', 'LogInfo', 'XaraEvent']),
    );

    final frame = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: XaraCapture.encode(
        record: -1,
        code: FmCode.connectReplyNarrow,
        ok: true,
        data: Uint8List(0),
        meta: {'hits': 9, 'verdict': 'late', 'ticks': 980, 'window': 942},
      ),
      channelId: 2,
      regionId: 0,
      incoming: true,
      encoding: FragmentEncodingType.softwareXara,
      frameType: FragmentFrameType.xara,
      radioDeviceId: 101,
    );
    DataBroker.dispatch(
      deviceId: 101,
      name: 'CaptureFrame',
      data: frame,
      store: false,
    );
    DataBroker.dispatch(
      deviceId: 1,
      name: 'LogInfo',
      data: 'hello agent',
      store: false,
    );
    DataBroker.dispatch(
      deviceId: 101,
      name: 'XaraEvent',
      data: {'evt': 'connected', 'caller': 'N1ABC', 'wide': false},
      store: false,
    );
    // Not subscribed: must not be pushed.
    DataBroker.dispatch(
      deviceId: 1,
      name: 'LogError',
      data: 'nope',
      store: false,
    );

    final packet = await waitFor(
      () => a.events.where((e) => e['event'] == 'PacketStored').firstOrNull,
    );
    final data = packet['data'] as Map<String, dynamic>;
    expect(data['frameType'], 'xara');
    expect(data['radio'], 101);
    expect(data['incoming'], isTrue);
    expect(
      data['summary'],
      startsWith(
        'XARA control: Connect reply (narrow) (9 hits) - dropped: late',
      ),
    );
    expect(data['encoding'], contains('Session control'));
    final xara = (data['decode'] as List).firstWhere(
      (s) => s['title'] == 'XARA',
    );
    expect(
      (xara['lines'] as Map)['Session verdict'],
      startsWith('dropped: late'),
    );

    final log = await waitFor(
      () => a.events.where((e) => e['event'] == 'LogInfo').firstOrNull,
    );
    expect(log['data'], 'hello agent');
    final xaraEvent = await waitFor(
      () => a.events.where((e) => e['event'] == 'XaraEvent').firstOrNull,
    );
    expect(xaraEvent['device'], 101);
    expect((xaraEvent['data'] as Map)['caller'], 'N1ABC');
    expect(a.events.where((e) => e['event'] == 'LogError'), isEmpty);

    await a.call('unsubscribe', {
      'events': ['LogInfo'],
    });
    DataBroker.dispatch(
      deviceId: 1,
      name: 'LogInfo',
      data: 'second',
      store: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(a.events.where((e) => e['data'] == 'second'), isEmpty);
    a.close();
  });

  test('reads the packet capture and logs', () async {
    final a = await authenticated();
    final before = DateTime.now().toUtc();
    // `since` is exclusive; step past the clock tick it was taken in.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 0; i < 3; i++) {
      DataBroker.dispatch(
        deviceId: 102,
        name: 'CaptureFrame',
        data: TncDataFragment(
          finalFragment: true,
          fragmentId: 0,
          data: XaraCapture.encode(
            record: 15,
            code: -1,
            ok: true,
            data: Uint8List.fromList([0x41 + i, 0x42]),
            meta: {'bw': 'narrow'},
          ),
          channelId: 1,
          regionId: 0,
          incoming: false,
          encoding: FragmentEncodingType.softwareXara,
          frameType: FragmentFrameType.xara,
          radioDeviceId: 102,
        ),
        store: false,
      );
    }
    final r = await a.call('packets', {
      'since': before.toIso8601String(),
      'limit': 2,
      'details': true,
    });
    final packets = (r['packets'] as List).cast<Map<String, dynamic>>();
    expect(packets, hasLength(2));
    expect(packets.last['hex'], '4342');
    expect(
      packets.last['encoding'],
      startsWith('Software XARA FM Narrow Start'),
    );
    expect(packets.last['decode'], isA<List>());

    DataBroker.dispatch(
      deviceId: 1,
      name: 'DebugLogEntries',
      data: [
        {
          'time': '2026-11-01T07:00:00.000Z',
          'message': 'old',
          'isError': false,
        },
        {
          'time': '2026-11-01T08:00:00.000Z',
          'message': 'boom',
          'isError': true,
        },
        {
          'time': '2026-11-01T08:00:01.000Z',
          'message': 'fine',
          'isError': false,
        },
      ],
    );
    final all = await a.call('logs', {'since': '2026-11-01T07:30:00Z'});
    expect((all['logs'] as List).map((l) => l['message']), ['boom', 'fine']);
    final errors = await a.call('logs', {'level': 'error'});
    expect((errors['logs'] as List).single['level'], 'error');
    a.close();
  });

  test('reads selected values but never secrets', () async {
    final a = await authenticated();
    DataBroker.dispatch(
      deviceId: 103,
      name: 'LockState',
      data: {'isLocked': true, 'usage': 'BBS'},
    );
    final lock = await a.call('get', {'device': 103, 'name': 'LockState'});
    expect(lock['value'], {'isLocked': true, 'usage': 'BBS'});
    expect(
      (await a.call('get', {'device': 0, 'name': 'CallSign'}))['value'],
      'N0CALL',
    );

    for (final name in [
      AgentApi.tokenSetting,
      'RepeaterBookToken',
      'WinlinkPassword',
      'AprsIsPasscode',
    ]) {
      final r = await a.call('get', {'device': 0, 'name': name});
      expect(r['ok'], isFalse, reason: name);
    }
    expect(
      (await a.call('get', {'device': 103, 'name': 'Settings'}))['ok'],
      isFalse,
    );
    expect(
      (await a.call('get', {'device': 1, 'name': 'DebugLogEntries'}))['ok'],
      isFalse,
    );
    a.close();
  });

  test('browsers can neither read nor change the agent settings', () async {
    final a = await connect();
    final settings = await waitFor(
      () => a.other.where((m) => m.startsWith('settings:')).firstOrNull,
    );
    final snapshot = jsonDecode(settings.substring('settings:'.length)) as Map;
    expect(snapshot.containsKey('webServerPort'), isTrue);
    expect(snapshot.containsKey(AgentApi.tokenSetting), isFalse);
    expect(snapshot.containsKey(AgentApi.enabledSetting), isFalse);

    a.socket.add(
      'setsetting:${jsonEncode({'name': AgentApi.tokenSetting, 'value': 'mine'})}',
    );
    a.socket.add(
      'setsetting:${jsonEncode({'name': AgentApi.enabledSetting, 'value': 0})}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(DataBroker.getValue<String>(0, AgentApi.tokenSetting), token);
    expect(DataBroker.getValue<int>(0, AgentApi.enabledSetting), 1);
    a.close();
  });

  test('browsers never receive or change credentials', () async {
    DataBroker.dispatch(deviceId: 0, name: 'WinlinkPassword', data: 'wl');
    DataBroker.dispatch(deviceId: 0, name: 'AprsIsPasscode', data: '');
    final a = await connect();
    final settings = await waitFor(
      () => a.other.where((m) => m.startsWith('settings:')).firstOrNull,
    );
    final snapshot = jsonDecode(settings.substring('settings:'.length)) as Map;
    expect(snapshot.containsKey('CallSign'), isTrue);
    for (final name in [
      'WinlinkPassword',
      'RepeaterBookToken',
      'AprsIsPasscode',
    ]) {
      expect(snapshot.containsKey(name), isFalse, reason: name);
    }
    expect(snapshot.values.any((v) => '$v'.contains('wl')), isFalse);
    // Only the names of configured credentials are shared.
    expect(snapshot[HostBridge.hostCredentialsValue], [
      'RepeaterBookToken',
      'WinlinkPassword',
    ]);

    // A live change sends the new list, never the value.
    a.other.clear();
    DataBroker.dispatch(deviceId: 0, name: 'AprsIsPasscode', data: '12345');
    final update = await waitFor(
      () => a.other.where((m) => m.startsWith('setting:')).firstOrNull,
    );
    expect(update, isNot(contains('12345')));
    expect(jsonDecode(update.substring('setting:'.length)), {
      'name': HostBridge.hostCredentialsValue,
      'value': ['AprsIsPasscode', 'RepeaterBookToken', 'WinlinkPassword'],
    });

    for (final name in ['WinlinkPassword', HostBridge.hostCredentialsValue]) {
      a.socket.add('setsetting:${jsonEncode({'name': name, 'value': 'evil'})}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(DataBroker.getValue<String>(0, 'WinlinkPassword'), 'wl');
    expect(DataBroker.hasValue(0, HostBridge.hostCredentialsValue), isFalse);
    expect(HostBridge.isSecretSetting('AllStarWtToken'), isTrue);
    expect(HostBridge.isSecretSetting('preDeEmphBypass'), isFalse);
    a.close();
  });

  test('custom map settings never sync with connected browsers', () async {
    const url = 'https://example.com/{z}/{x}/{y}.png?key=private-map-key';
    final values = <String, Object>{
      customMapEnabledKey: 1,
      customMapUrlKey: url,
      customMapAttributionKey: 'Private source',
    };
    for (final entry in values.entries) {
      DataBroker.dispatch(deviceId: 0, name: entry.key, data: entry.value);
    }
    final a = await connect();
    final settings = await waitFor(
      () => a.other.where((m) => m.startsWith('settings:')).firstOrNull,
    );
    final snapshot = jsonDecode(settings.substring('settings:'.length)) as Map;
    for (final name in values.keys) {
      expect(snapshot.containsKey(name), isFalse);
      a.socket.add(
        'setsetting:${jsonEncode({'name': name, 'value': 'browser-value'})}',
      );
    }
    expect(settings, isNot(contains('private-map-key')));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    for (final entry in values.entries) {
      expect(DataBroker.getValueDynamic(0, entry.key), entry.value);
    }
    a.other.clear();
    DataBroker.dispatch(
      deviceId: 0,
      name: customMapUrlKey,
      data: '$url&another-private-key=2',
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(a.other.join(), isNot(contains('another-private-key')));
    a.close();
  });

  test('turning the API off drops agent sessions', () async {
    final a = await authenticated();
    await a.call('subscribe', {
      'events': ['LogInfo'],
    });
    DataBroker.dispatch(deviceId: 0, name: AgentApi.enabledSetting, data: 0);
    DataBroker.dispatch(
      deviceId: 1,
      name: 'LogInfo',
      data: 'after off',
      store: false,
    );
    DataBroker.dispatch(deviceId: 0, name: AgentApi.enabledSetting, data: 1);
    expect((await a.call('packets'))['error'], contains('not authenticated'));
    expect(a.events.where((e) => e['data'] == 'after off'), isEmpty);
    a.close();
  });

  group('commands', () {
    late FakeRadio r1, r2;
    final recorded = <String, Object?>{};
    final recorder = DataBrokerClient();

    setUpAll(() {
      for (final n in [
        'CreateBbs',
        'RemoveBbs',
        'ClearPackets',
        'SetXaraTxLatencyMs',
      ]) {
        recorder.subscribe(
          deviceId: DataBroker.allDevices,
          name: n,
          callback: (_, name, d) => recorded[name] = d ?? 'null',
        );
      }
    });

    setUp(() {
      recorded.clear();
      r1 = FakeRadio(501);
      r2 = FakeRadio(502);
      DataBroker.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': 501, 'FriendlyName': 'A'},
          {'DeviceId': 502, 'FriendlyName': 'B'},
        ],
      );
      DataBroker.dispatch(deviceId: 0, name: 'AllowTransmit', data: 1);
      DataBroker.dispatch(deviceId: 0, name: AgentApi.txLimitSetting, data: 45);
    });

    tearDown(() {
      r1.dispose();
      r2.dispose();
    });

    Map<Object?, Object?> control() =>
        DataBroker.getValueDynamic(1, AgentApi.controlValue, null)! as Map;

    Future<Map<String, dynamic>> run(
      Agent a,
      String command, [
      Map<String, Object?> args = const {},
    ]) => a.call('command', {'command': command, 'args': args});

    test('transmitting needs AllowTransmit and a known command', () async {
      final a = await authenticated();
      DataBroker.dispatch(deviceId: 0, name: 'AllowTransmit', data: 0);
      final r = await run(a, 'radio.lock', {'radio': 501});
      expect(r['error'], contains('AllowTransmit is off'));
      expect(r1.locks, isEmpty);
      expect(
        (await run(a, 'radio.reboot'))['error'],
        contains('unknown command'),
      );
      expect(
        (await run(a, 'xara.connect', {'radio': 999, 'remote': 'X'}))['ok'],
        isFalse,
      );
      a.close();
    });

    test('locks a radio for XARA and drives the link', () async {
      final a = await authenticated();
      expect(control()['active'], isTrue);

      final lock = await run(a, 'radio.lock', {
        'radio': 501,
        'channel': 'BBS',
        'region': 'Away',
        'modem': 'XARA',
        'xaraWide': true,
      });
      expect(lock['ok'], isTrue, reason: '$lock');
      final l = r1.locks.single;
      expect(l.usage, 'Agent');
      expect(l.channelName, 'BBS');
      expect(l.regionId, 1);
      expect(l.modem, 'XARA');
      expect(l.xaraWide, isTrue);
      expect(control()['radios'], [501]);

      expect(
        (await run(a, 'radio.lock', {'radio': 501}))['error'],
        contains('already locked'),
      );
      expect(
        (await run(a, 'radio.lock', {'radio': 502, 'modem': 'Turbo'}))['error'],
        contains('modem must be'),
      );
      expect(
        (await run(a, 'xara.connect', {
          'radio': 502,
          'remote': 'N0CALL',
        }))['error'],
        contains('not controlled by an agent'),
      );

      final c = await run(a, 'xara.connect', {
        'radio': 501,
        'remote': 'n0call-1',
        'vias': ['n9dig'],
      });
      expect(c['remote'], 'N0CALL-1');
      expect(r1.payloads['XaraConnect'], {
        'Remote': 'N0CALL-1',
        'Vias': ['N9DIG'],
      });
      expect(
        (await run(a, 'xara.send', {'radio': 501, 'text': 'S\r'}))['bytes'],
        2,
      );
      expect(r1.payloads['XaraSend'], Uint8List.fromList([0x53, 0x0D]));
      await run(a, 'xara.send', {'radio': 501, 'hex': '4142'});
      expect(r1.payloads['XaraSend'], Uint8List.fromList([0x41, 0x42]));
      await run(a, 'xara.disconnect', {'radio': 501});
      expect(
        r1.commands,
        containsAllInOrder(['XaraConnect', 'XaraSend', 'XaraDisconnect']),
      );

      expect((await run(a, 'radio.unlock', {'radio': 501}))['ok'], isTrue);
      expect(r1.commands, containsAllInOrder(['XaraAbort', 'SetUnlock:Agent']));
      expect(control()['radios'], isEmpty);
      a.close();
    });

    test('starts and stops only agent BBSes', () async {
      final a = await authenticated();
      final s = await run(a, 'bbs.start', {'radio': 502, 'channel': 'BBS'});
      expect(s['channel'], 4);
      final create = recorded['CreateBbs']! as CreateBbsData;
      expect(create.radioDeviceId, 502);
      expect(create.channelId, 4);
      expect(create.regionId, 0);

      expect(
        (await run(a, 'bbs.stop', {'radio': 501}))['error'],
        contains('not started by an agent'),
      );
      expect(
        (await run(a, 'bbs.start', {'radio': 501, 'region': 'Away'}))['error'],
        contains('current region'),
      );
      expect((await run(a, 'bbs.stop', {'radio': 502}))['ok'], isTrue);
      expect((recorded['RemoveBbs']! as RemoveBbsData).radioDeviceId, 502);

      // Defaults to the radio's current channel A.
      await run(a, 'bbs.stop', {'radio': 502}); // already stopped -> error
      final d = await run(a, 'bbs.start', {'radio': 501});
      expect(d['channel'], 2);
      a.close();
    });

    test('changes only allowlisted settings and clears the capture', () async {
      final a = await authenticated();
      final r = await run(a, 'setting.set', {
        'name': 'XaraTxLatencyMs',
        'value': 1000,
      });
      expect(r['ok'], isTrue);
      expect(recorded['SetXaraTxLatencyMs'], 1000);
      for (final name in [
        'CallSign',
        'AllowTransmit',
        'webServerEnabled',
        AgentApi.enabledSetting,
      ]) {
        expect(
          (await run(a, 'setting.set', {'name': name, 'value': 0}))['ok'],
          isFalse,
          reason: name,
        );
      }
      await run(a, 'packets.clear');
      expect(recorded.containsKey('ClearPackets'), isTrue);
      a.close();
    });

    test('drives the host terminal over XARA from a contact', () async {
      final terminal = TerminalHandler()..init();
      addTearDown(() {
        terminal.abort();
        terminal.dispose();
      });
      DataBroker.dispatch(
        deviceId: 0,
        name: 'Stations',
        data: [
          StationInfo(
            callsign: 'N1BBS-1',
            stationType: StationType.terminal,
            terminalProtocol: TerminalProtocol.xaraNarrow,
            channel: 'BBS',
          ).toJson(),
          StationInfo(
            callsign: 'N1APR',
            stationType: StationType.aprs,
          ).toJson(),
        ],
      );
      DataBroker.dispatch(deviceId: 501, name: 'AudioState', data: true);
      DataBroker.dispatch(
        deviceId: 501,
        name: 'HtStatus',
        data: {'currRegion': 0, 'currChId': 4, 'isInTx': false},
      );
      final a = await authenticated();
      a.call('subscribe', {
        'events': ['TerminalState', 'TerminalText', 'TerminalNotice'],
      });
      expect(
        (await run(a, 'terminal.send', {'text': 'x'}))['error'],
        contains('terminal.connect first'),
      );
      expect(
        (await run(a, 'terminal.connect', {
          'radio': 501,
          'contact': 'N1APR',
        }))['error'],
        contains('no terminal contact'),
      );
      // A missing channel is reported and leaves nothing held.
      final bad = await run(a, 'terminal.connect', {
        'radio': 501,
        'station': {
          'Callsign': 'N2XYZ',
          'TerminalProtocol': TerminalProtocol.xaraWide.index,
          'Channel': 'NOPE',
        },
      });
      expect(bad['error'], contains('channelMissing'));
      expect(control()['radios'], isEmpty);

      final c = await run(a, 'terminal.connect', {
        'radio': 501,
        'contact': 'n1bbs-1',
      });
      expect(c['ok'], isTrue, reason: '$c');
      expect(c['protocol'], 'xaraNarrow');
      expect(r1.locks.single.modem, 'XARA');
      expect(r1.locks.single.usage, 'Terminal');
      await waitFor(() => r1.commands.contains('XaraConnect') ? true : null);
      expect(control()['radios'], [501]);
      expect(
        (await run(a, 'terminal.wait', {'radio': 502}))['error'],
        contains('terminal is busy'),
      );
      expect(
        (await run(a, 'terminal.send', {'text': 'x'}))['error'],
        contains('cannot send yet'),
      );

      DataBroker.dispatch(
        deviceId: 501,
        name: 'XaraEvent',
        data: {'evt': 'connected'},
        store: false,
      );
      expect((await run(a, 'terminal.send', {'text': 'L'}))['ok'], isTrue);
      expect(r1.payloads['XaraSend'], Uint8List.fromList(utf8.encode('L\r')));
      await waitFor(
        () =>
            a.events.any(
              (e) =>
                  e['event'] == 'TerminalText' && e['data']['outgoing'] == true,
            )
            ? true
            : null,
      );
      expect(
        a.events
            .where((e) => e['event'] == 'TerminalState')
            .last['data']['status'],
        'connected',
      );
      final got = await a.call('get', {'device': 1, 'name': 'TerminalState'});
      expect(got['value']['remote'], 'N1BBS-1');

      // Dropping the agent stops the terminal and frees the radio.
      a.close();
      await waitFor(() => control()['active'] == false ? true : null);
      expect(
        r1.commands,
        containsAllInOrder(['XaraAbort', 'SetUnlock:Terminal']),
      );
      expect(terminal.status.name, 'idle');
    });

    test('a dropped agent releases everything it held', () async {
      final a = await authenticated();
      await run(a, 'radio.lock', {'radio': 501, 'modem': 'XARA'});
      await run(a, 'xara.connect', {'radio': 501, 'remote': 'N0CALL'});
      await run(a, 'bbs.start', {'radio': 502});
      a.close();
      await waitFor(() => control()['active'] == false ? true : null);
      expect(r1.commands, containsAllInOrder(['XaraAbort', 'SetUnlock:Agent']));
      expect((recorded['RemoveBbs']! as RemoveBbsData).radioDeviceId, 502);
      expect(control()['radios'], isEmpty);
    });

    test('stop releases every agent', () async {
      final a = await authenticated();
      final b = await authenticated();
      await run(a, 'radio.lock', {'radio': 501});
      await run(b, 'radio.lock', {'radio': 502, 'usage': 'Terminal'});
      final r = await a.call('stop');
      expect(
        r['released'],
        containsAll(['unlocked radio 501', 'unlocked radio 502']),
      );
      expect(r2.commands, contains('SetUnlock:Terminal'));
      expect(control()['radios'], isEmpty);
      expect(control()['active'], isTrue); // still connected
      a.close();
      b.close();
    });

    test('the operator Stop releases agents and turns the API off', () async {
      final a = await authenticated();
      await a.call('subscribe', {
        'events': ['LockState'],
      });
      await run(a, 'radio.lock', {'radio': 501});
      DataBroker.dispatch(
        deviceId: 1,
        name: AgentApi.stopEvent,
        data: null,
        store: false,
      );
      final stopped = await waitFor(
        () => a.events.where((e) => e['event'] == 'AgentStopped').firstOrNull,
      );
      expect((stopped['data'] as Map)['reason'], 'stopped by the operator');
      expect(r1.commands, contains('SetUnlock:Agent'));
      expect(DataBroker.getValue<int>(0, AgentApi.enabledSetting), 0);
      expect(control()['active'], isFalse);
      expect((await a.call('ping'))['error'], 'agent API disabled');
      a.close();
    });

    test('the transmit limit releases the radio and blocks it', () async {
      DataBroker.dispatch(deviceId: 0, name: AgentApi.txLimitSetting, data: 1);
      final a = await authenticated();
      await run(a, 'radio.lock', {'radio': 501, 'modem': 'XARA'});
      DataBroker.dispatch(
        deviceId: 501,
        name: 'HtStatus',
        data: {'currRegion': 0, 'isInTx': true},
      );
      final limit = await waitFor(
        () => a.events.where((e) => e['event'] == 'AgentLimit').firstOrNull,
      ).timeout(const Duration(seconds: 5));
      expect((limit['data'] as Map)['radio'], 501);
      expect((limit['data'] as Map)['limit'], 1);
      expect(r1.commands, contains('SetUnlock:Agent'));
      DataBroker.dispatch(
        deviceId: 501,
        name: 'HtStatus',
        data: {'currRegion': 0, 'isInTx': false},
      );

      final again = await run(a, 'radio.lock', {'radio': 501});
      expect(again['error'], contains('transmit limit'));
      // Other radios are unaffected.
      expect((await run(a, 'radio.lock', {'radio': 502}))['ok'], isTrue);
      a.close();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('forgets locks someone else released', () async {
      final a = await authenticated();
      await run(a, 'radio.lock', {'radio': 501});
      expect(control()['radios'], [501]);
      DataBroker.dispatch(
        deviceId: 501,
        name: 'LockState',
        data: {'isLocked': false},
      );
      expect(control()['radios'], isEmpty);
      expect(
        (await run(a, 'radio.unlock', {'radio': 501}))['error'],
        contains('not locked by an agent'),
      );
      a.close();
    });
  });

  test('XARA timing changes reach the software modem live', () {
    final modem = SoftwareModem()..init();
    try {
      DataBroker.dispatch(
        deviceId: 0,
        name: 'SetXaraTxLatencyMs',
        data: 950,
        store: false,
      );
      DataBroker.dispatch(
        deviceId: 0,
        name: 'SetXaraTxKeyUpMs',
        data: 9999,
        store: false,
      );
      expect(DataBroker.getValue<int>(0, 'XaraTxLatencyMs'), 950);
      expect(DataBroker.getValue<int>(0, 'XaraTxKeyUpMs'), 5000);
    } finally {
      modem.dispose();
    }
  });
}
