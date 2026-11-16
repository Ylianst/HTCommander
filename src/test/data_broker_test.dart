import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

const _platform = MethodChannel('mixin.one/desktop_multi_window/channels');
const _host = 'htcmd.broker.host';
const _codec = StandardMethodCodec();

Future<Object?> _receive(
  String channel,
  String method, [
  Object? arguments,
]) async {
  final reply = Completer<ByteData?>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _platform.name,
        _codec.encodeMethodCall(
          MethodCall('methodCall', {
            'channel': channel,
            'method': method,
            'arguments': arguments,
          }),
        ),
        reply.complete,
      );
  return _codec.decodeEnvelope((await reply.future)!);
}

Future<void> _interests(
  String windowId,
  List<(int, String)> subscriptions,
) async {
  await _receive(_host, 'subscriptions', {
    'windowId': windowId,
    'subscriptions': [
      for (final (deviceId, name) in subscriptions)
        {'deviceId': deviceId, 'name': name},
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <Map<Object?, Object?>>[];
  final clients = <DataBrokerClient>[];
  Object? snapshotReply;

  DataBrokerClient client() {
    final result = DataBrokerClient();
    clients.add(result);
    return result;
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_platform, (call) async {
          if (call.method == 'invokeMethod') {
            sent.add(call.arguments as Map);
            if ((call.arguments as Map)['method'] == 'snapshot') {
              return snapshotReply;
            }
          }
          return null;
        });
    DataBroker.reset();
    await DataBroker.becomeHost();
    sent.clear();
    snapshotReply = null;
  });

  tearDown(() async {
    for (final c in clients) {
      c.dispose();
    }
    clients.clear();
    if (DataBroker.isClient) await DataBroker.shutdownClient();
    for (final id in ['audio', 'map', 'wild', 'client']) {
      DataBroker.unregisterChildWindow(id);
    }
    DataBroker.reset();
    await DataBroker.becomeHost();
  });

  test('indexed subscriptions retain wildcard and registration order', () {
    final calls = <String>[];
    final c = client();
    for (var i = 0; i < 2000; i++) {
      c.subscribe(
        deviceId: i + 10,
        name: 'unrelated$i',
        callback: (_, _, _) => fail('unrelated subscription'),
      );
    }
    for (final (device, name, label) in [
      (-1, '*', 'all'),
      (2, 'PCM', 'exact'),
      (-1, 'PCM', 'name'),
      (2, '*', 'device'),
      (2, 'PCM', 'duplicate'),
    ]) {
      c.subscribe(
        deviceId: device,
        name: name,
        callback: (_, _, _) => calls.add(label),
      );
    }
    for (var i = 0; i < 2; i++) {
      DataBroker.dispatch(deviceId: 2, name: 'PCM', data: null, store: false);
    }
    expect(calls, [
      'all',
      'exact',
      'name',
      'device',
      'duplicate',
      'all',
      'exact',
      'name',
      'device',
      'duplicate',
    ]);
  });

  test('wildcard-valued dispatches do not call subscriptions twice', () {
    var count = 0;
    client().subscribeAll(callback: (_, _, _) => count++);
    DataBroker.dispatch(deviceId: -1, name: '*', data: null, store: false);
    DataBroker.dispatch(deviceId: 2, name: '*', data: null, store: false);
    DataBroker.dispatch(deviceId: -1, name: 'PCM', data: null, store: false);
    expect(count, 3);
  });

  test('subscription changes preserve the current dispatch snapshot', () {
    final calls = <String>[];
    final first = client();
    final second = client();
    final added = client();
    var changed = false;
    first.subscribe(
      deviceId: 2,
      name: 'PCM',
      callback: (_, _, _) {
        calls.add('first');
        if (changed) return;
        changed = true;
        second.dispose();
        added.subscribe(
          deviceId: 2,
          name: 'PCM',
          callback: (_, _, _) {
            calls.add('added');
          },
        );
        DataBroker.dispatch(deviceId: 2, name: 'PCM', data: null, store: false);
      },
    );
    second.subscribe(
      deviceId: 2,
      name: 'PCM',
      callback: (_, _, _) {
        calls.add('second');
      },
    );
    DataBroker.dispatch(deviceId: 2, name: 'PCM', data: null, store: false);
    expect(calls, ['first', 'first', 'added', 'second']);
  });

  test('unsubscribe and reset invalidate cached matches', () {
    final events = <String>[];
    final c = client();
    for (final name in ['a', 'b']) {
      c.subscribe(
        deviceId: 2,
        name: name,
        callback: (_, n, _) => events.add(n),
      );
      DataBroker.dispatch(deviceId: 2, name: name, data: null, store: false);
    }
    c.unsubscribe(2, 'a');
    DataBroker.dispatch(deviceId: 2, name: 'a', data: null, store: false);
    DataBroker.dispatch(deviceId: 2, name: 'b', data: null, store: false);
    c.unsubscribeAll();
    DataBroker.dispatch(deviceId: 2, name: 'b', data: null, store: false);
    c.subscribe(deviceId: 2, name: 'b', callback: (_, n, _) => events.add(n));
    DataBroker.reset();
    DataBroker.dispatch(deviceId: 2, name: 'b', data: null, store: false);
    expect(events, ['a', 'b', 'b']);
  });

  test(
    'transient streams route by device and name; stored values mirror',
    () async {
      await _interests('audio', [(2, 'AudioDataAvailable')]);
      await _interests('map', [(2, 'Position')]);
      await _interests('wild', [(-1, '*')]);
      // Late parent-side registration must not overwrite an early handshake.
      DataBroker.registerChildWindow('audio');
      sent.clear();
      DataBroker.dispatch(
        deviceId: 2,
        name: 'AudioDataAvailable',
        data: null,
        store: false,
      );
      DataBroker.dispatch(
        deviceId: 3,
        name: 'AudioDataAvailable',
        data: null,
        store: false,
      );
      DataBroker.dispatch(deviceId: 2, name: 'Settings', data: {'value': 1});
      expect(sent.map((e) => e['channel']), [
        'htcmd.broker.win.audio',
        'htcmd.broker.win.wild',
        'htcmd.broker.win.wild',
        'htcmd.broker.win.audio',
        'htcmd.broker.win.map',
        'htcmd.broker.win.wild',
      ]);
    },
  );

  test('updated interests and detach stop stream forwarding', () async {
    await _interests('audio', [(-1, 'PCM')]);
    DataBroker.dispatch(deviceId: 99, name: 'PCM', data: null, store: false);
    await _interests('audio', [(2, '*')]);
    DataBroker.dispatch(deviceId: 99, name: 'PCM', data: null, store: false);
    DataBroker.dispatch(deviceId: 2, name: 'Other', data: null, store: false);
    await _interests('audio', []);
    DataBroker.dispatch(deviceId: 2, name: 'Other', data: null, store: false);
    await _receive(_host, 'detach', {'windowId': 'audio'});
    DataBroker.dispatch(deviceId: 2, name: 'Settings', data: 1);
    expect(sent.length, 2);
  });

  test('unconsumed streams are not serialized', () async {
    var encodes = 0;
    DataBroker.registerSerializer<_Value>('testValue', (value) {
      encodes++;
      return {'value': value.value};
    }, (json) => _Value(json['value'] as int));
    DataBroker.registerChildWindow('map');
    DataBroker.dispatch(
      deviceId: 2,
      name: 'Stream',
      data: _Value(7),
      store: false,
    );
    expect(encodes, 0);
    await _interests('audio', [(2, 'Stream')]);
    await _interests('wild', [(2, 'Stream')]);
    DataBroker.dispatch(
      deviceId: 2,
      name: 'Stream',
      data: _Value(7),
      store: false,
    );
    expect(encodes, 1);
    expect(sent.length, 2);
  });

  test(
    'PCM uses binary buffers with intact metadata and snapshot values',
    () async {
      await _interests('audio', [(-1, '*')]);
      final pcm = Uint8List.sublistView(
        Uint8List.fromList([9, 0, 128, 255, 7]),
        1,
        4,
      );
      DataBroker.dispatch(
        deviceId: 2,
        name: 'AudioDataAvailable',
        data: {
          'data': pcm,
          'offset': 1,
          'length': 2,
          'channelName': 'VFO',
          'transmit': false,
          'muted': true,
          'audioRunStartTime': 123,
        },
        store: false,
      );
      final args = sent.single['arguments'] as Map;
      expect(args['bytes'], isA<Uint8List>());
      expect(args['bytes'], [0, 128, 255]);
      expect(jsonDecode(args['payload'] as String), {
        'offset': 1,
        'length': 2,
        'channelName': 'VFO',
        'transmit': false,
        'muted': true,
        'audioRunStartTime': 123,
      });
      DataBroker.dispatch(deviceId: 2, name: 'SavedPCM', data: pcm);
      final snapshot = await _receive(_host, 'snapshot') as List;
      final stored = snapshot.single as Map;
      expect(stored['bytes'], isA<Uint8List>());
      expect(stored['bytes'], pcm);
      expect(stored.containsKey('payload'), isFalse);
    },
  );

  test(
    'child-originated PCM is decoded and not echoed to its source',
    () async {
      await _interests('audio', [(2, 'TransmitVoicePCM')]);
      await _interests('wild', [(2, '*')]);
      Object? received;
      client().subscribe(
        deviceId: 2,
        name: 'TransmitVoicePCM',
        callback: (_, _, d) {
          received = d;
        },
      );
      await _receive(_host, 'dispatch', {
        'deviceId': 2,
        'name': 'TransmitVoicePCM',
        'store': false,
        'from': 'audio',
        'bytes': Uint8List.fromList([1, 255]),
        'payload': jsonEncode({'hold': true, 'playLocally': false}),
      });
      expect(received, {
        'data': isA<Uint8List>().having((v) => v.toList(), 'bytes', [1, 255]),
        'hold': true,
        'playLocally': false,
      });
      expect(sent.single['channel'], 'htcmd.broker.win.wild');
    },
  );

  test(
    'snapshot handshake registers interests before forwarding begins',
    () async {
      await _receive(_host, 'snapshot', {
        'windowId': 'audio',
        'subscriptions': [
          {'deviceId': 2, 'name': 'PCM'},
        ],
      });
      DataBroker.dispatch(deviceId: 2, name: 'PCM', data: null, store: false);
      expect(sent.single['channel'], 'htcmd.broker.win.audio');
    },
  );

  test(
    'snapshots preserve binary, registered, plain, and null values',
    () async {
      DataBroker.registerSerializer<_Value>(
        'testValue',
        (value) => {'value': value.value},
        (json) => _Value(json['value'] as int),
      );
      final values = <String, Object?>{
        'PCM': Uint8List.fromList([128, 255]),
        'Audio': {
          'data': Uint8List.fromList([0, 7]),
          'offset': 0,
          'length': 2,
        },
        'Typed': [_Value(42)],
        'Plain': {
          'text': 'hello',
          'list': [1, true, null],
        },
        'Null': null,
      };
      for (final entry in values.entries) {
        DataBroker.dispatch(deviceId: 2, name: entry.key, data: entry.value);
      }
      snapshotReply = await _receive(_host, 'snapshot');
      await DataBroker.becomeClient('client');
      DataBroker.clearDevice(2);
      await DataBroker.requestSnapshot();
      for (final name in ['PCM', 'Audio', 'Plain', 'Null']) {
        expect(DataBroker.hasValue(2, name), isTrue);
        expect(DataBroker.getValueDynamic(2, name), values[name]);
      }
      expect(DataBroker.getValueDynamic(2, 'PCM'), isA<Uint8List>());
      expect(
        (DataBroker.getValueDynamic(2, 'Audio') as Map)['data'],
        isA<Uint8List>(),
      );
      final typed = DataBroker.getValueDynamic(2, 'Typed') as List;
      expect(typed.single, isA<_Value>().having((v) => v.value, 'value', 42));
    },
  );

  test('client advertises unique interests and receives binary PCM', () async {
    await DataBroker.becomeClient('client');
    final a = client();
    final b = client();
    Object? received;
    a.subscribe(deviceId: 2, name: 'PCM', callback: (_, _, _) {});
    b.subscribe(deviceId: 2, name: 'PCM', callback: (_, _, d) => received = d);
    a.dispose();
    final updates = sent.where((e) => e['method'] == 'subscriptions').toList();
    expect(updates.length, 2); // Initial empty set and first subscriber.
    expect((updates.last['arguments'] as Map)['subscriptions'], [
      {'deviceId': 2, 'name': 'PCM'},
    ]);
    await _receive('htcmd.broker.win.client', 'onData', {
      'deviceId': 2,
      'name': 'PCM',
      'store': false,
      'bytes': Uint8List.fromList([128, 255]),
    });
    expect(received, isA<Uint8List>());
    expect(received, [128, 255]);
    b.unsubscribeAll();
    expect((sent.last['arguments'] as Map)['subscriptions'], isEmpty);
    client().subscribe(deviceId: 3, name: 'Other', callback: (_, _, _) {});
    DataBroker.reset();
    expect((sent.last['arguments'] as Map)['subscriptions'], isEmpty);
    sent.clear();
    DataBroker.dispatch(
      deviceId: 2,
      name: 'TransmitVoicePCM',
      data: {
        'data': Uint8List.fromList([1, 2]),
        'hold': true,
      },
      store: false,
    );
    expect(sent.single['method'], 'dispatch');
    expect((sent.single['arguments'] as Map)['bytes'], isA<Uint8List>());
  });
}

class _Value {
  final int value;
  _Value(this.value);
}
