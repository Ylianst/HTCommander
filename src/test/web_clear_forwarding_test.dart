import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_conversation.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_outbox.dart';
import 'package:htcommander/aprs/aprs_link_policy.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/handlers/aprs_observation_handler.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/aprs_observation_store.dart';
import 'package:htcommander/handlers/aprs_handler.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/handlers/web_server_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/host_bridge.dart';
import 'package:htcommander/handlers/comms_handler.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/services/stored_chat_history.dart';

/// Picks a free local TCP port.
Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  late WebServerHandler handler;
  late DataBrokerClient listener;
  late WebSocket socket;
  final received = <(String, Object?)>[];
  final messages = <String>[];

  setUp(() async {
    received.clear();
    messages.clear();
    final port = await _freePort();
    DataBroker.dispatch(deviceId: 0, name: 'webServerPort', data: port);
    DataBroker.dispatch(deviceId: 0, name: 'webServerEnabled', data: 1);
    handler = WebServerHandler()..init();

    listener = DataBrokerClient();
    for (final name in [...HostBridge.forwardedClearEvents, 'ClearPackets']) {
      listener.subscribe(
        deviceId: 1,
        name: name,
        callback: (_, n, data) => received.add((n, data)),
      );
    }

    // The server binds asynchronously; retry until it accepts connections.
    for (var i = 0; ; i++) {
      try {
        socket = await WebSocket.connect('ws://127.0.0.1:$port/websocket.aspx');
        break;
      } catch (_) {
        if (i > 50) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    // Drain the host's on-connect snapshot messages.
    socket.listen((message) {
      if (message is String) messages.add(message);
    });
  });

  tearDown(() async {
    await socket.close();
    listener.dispose();
    handler.dispose();
    DataBroker.dispatch(deviceId: 0, name: 'webServerEnabled', data: 0);
  });

  Future<void> waitForEvents(int count) async {
    for (var i = 0; i < 100 && received.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('re-dispatches browser clears on the host', () async {
    socket.add('clear:{"event":"ClearVoiceText"}');
    socket.add('clear:{"event":"ClearAprsPackets"}');
    socket.add('clear:{"event":"$clearAprsConversationEvent","peer":"W1AW-9"}');
    await waitForEvents(3);

    expect(received.map((e) => e.$1), [
      'ClearVoiceText',
      'ClearAprsPackets',
      clearAprsConversationEvent,
    ]);
    expect(received[0].$2, isNull);
    expect(received[2].$2, {'peer': 'W1AW-9'});
  });

  test('ignores events that are not forwardable clears', () async {
    socket.add('clear:{"event":"ClearPackets"}');
    socket.add('clear:not json');
    socket.add('clear:{"event":"ClearVoiceText"}');
    await waitForEvents(1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received.map((e) => e.$1), ['ClearVoiceText']);
  });

  test('host preserves policies and only requires a shared radio for RF requests', () async {
    listener.dispatch(deviceId: 1, name: 'ConnectedRadios', data: []);
    addTearDown(() {
      DataBroker.clearDevice(42);
      listener.dispatch(deviceId: 1, name: 'ConnectedRadios', data: []);
    });
    final requests = <AprsSendMessageData>[];
    listener.subscribe(deviceId: 1, name: 'SendAprsMessage', callback: (_, _, data) {
      if (data is AprsSendMessageData) requests.add(data);
    });
    void send(AprsLinkPolicy policy, int radio) => socket.add('aprsop:${jsonEncode({
      'op': 'SendAprsMessage', 'message': AprsSendMessageData(destination: 'W1AW',
        message: 'policy', radioDeviceId: radio, policy: policy).toJson(),
    })}');
    send(AprsLinkPolicy.internetOnly, 1);
    for (var i = 0; i < 100 && requests.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(requests.single.radioDeviceId, -1);
    expect(requests.single.policy, AprsLinkPolicy.internetOnly);
    send(AprsLinkPolicy.rfOnly, 1);
    for (var i = 0; i < 100 && !messages.any((m) => m.startsWith('aprserror:')); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(messages.any((m) => m.contains('No shared radio available')), isTrue);
    expect(requests, hasLength(1));
    listener.dispatch(deviceId: 1, name: 'ConnectedRadios', data: [{'DeviceId': 42}]);
    send(AprsLinkPolicy.both, 1);
    for (var i = 0; i < 100 && requests.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(requests.last.radioDeviceId, 42);
    expect(requests.last.policy, AprsLinkPolicy.both);
  });

  test('host broadcasts its bounded observation journal without another archive owner', () async {
    await AppDatabase.openInMemory();
    final observations = AprsObservationHandler()..init();
    addTearDown(() async {
      observations.dispose();
      await observations.ready;
      await AppDatabase.close();
    });
    await observations.ready;
    for (final radio in [42, 43]) {
      listener.dispatch(deviceId: radio, name: 'DataFrame', data: TncDataFragment(
        finalFragment: true, fragmentId: 0, data: Tnc2Codec.decode('W1AW>APRS:>hello')!.toByteArray(),
        channelId: 7, regionId: 0, channelName: 'APRS', incoming: true,
        radioMac: 'radio-$radio', radioDeviceId: radio), store: false);
    }
    await observations.ready;
    socket.add('aprsop:{"op":"RequestAprsObservations"}');
    for (var i = 0; i < 100; i++) {
      if (messages.where((m) => m.startsWith('aprsobservations:')).any((m) =>
          (jsonDecode(m.substring('aprsobservations:'.length)) as List).length == 2)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final saved = jsonDecode(messages.lastWhere((m) => m.startsWith('aprsobservations:'))
      .substring('aprsobservations:'.length)) as List;
    expect(saved, hasLength(2));
    expect(saved.map((o) => o['radioMac']), ['radio-42', 'radio-43']);
    expect(await AprsObservationStore().load(), hasLength(2));
  });

  test('host owns browser APRS submissions, outbox snapshots and stop actions', () async {
    await AppDatabase.openInMemory();
    var now = DateTime(2026);
    final aprs = AprsHandler(clock: () => now);
    addTearDown(() async {
      aprs.dispose();
      await aprs.ready;
      await AppDatabase.close();
      DataBroker.clearDevice(42);
      DataBroker.dispatch(deviceId: 1, name: 'ConnectedRadios', data: []);
    });
    listener.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    listener.dispatch(deviceId: 0, name: 'StationId', data: 7);
    listener.dispatch(deviceId: 1, name: 'ConnectedRadios', data: [{'DeviceId': 42}]);
    listener.dispatch(deviceId: 42, name: 'Channels', data: [{'channelId': 7, 'name': 'APRS'}]);
    final requests = <AprsSendMessageData>[];
    final rf = <TransmitDataFrameData>[];
    listener.subscribe(deviceId: 1, name: 'SendAprsMessage', callback: (_, _, data) {
      if (data is AprsSendMessageData) requests.add(data);
    });
    listener.subscribe(deviceId: 42, name: 'TransmitDataFrame', callback: (_, _, data) {
      if (data is TransmitDataFrameData) rf.add(data);
    });
    aprs.init();
    await aprs.ready;
    socket.add('aprsop:${jsonEncode({'op': 'SendAprsMessage', 'message': {
      'destination': 'W1AW', 'message': 'Hello', 'radioDeviceId': 1,
    }})}');
    for (var i = 0; i < 100 && !messages.any((m) => m.startsWith('aprsqueued:')); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await aprs.ready;
    expect(requests.single.radioDeviceId, 42);
    expect(rf, hasLength(1));
    expect(aprs.outgoingMessages, hasLength(1));
    final snapshot = jsonDecode(messages.lastWhere((m) => m.startsWith('aprsoutbox:')).substring('aprsoutbox:'.length)) as List;
    expect(snapshot.single['id'], aprs.outgoingMessages.single.id);
    socket.add('aprsop:${jsonEncode({'op': 'StopAprsMessage', 'id': aprs.outgoingMessages.single.id})}');
    for (var i = 0; i < 100 && aprs.outgoingMessages.single.state != AprsDelivery.stopped; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await aprs.ready;
    expect(aprs.outgoingMessages.single.state, AprsDelivery.stopped);
    now = now.add(const Duration(hours: 1));
    await aprs.processOutbox();
    expect(rf, hasLength(1));
  });

  test(
    'hosted browsers can page stored history without broadcasting it',
    () async {
      final db = await AppDatabase.openInMemory();
      final history = StoredChatHistory()..init();
      DataBroker.addDataHandler('StoredChatHistory', history);
      var broadcasts = 0;
      listener.subscribe(
        deviceId: 1,
        name: 'StoredChatHistoryPage',
        callback: (_, _, _) => broadcasts++,
      );
      addTearDown(() async {
        DataBroker.removeDataHandler('StoredChatHistory');
        history.dispose();
        await AppDatabase.close();
      });
      await db.comms.insert(
        DecodedTextEntry(
          text: 'archived voice',
          time: DateTime(2026),
          isReceived: true,
          encoding: VoiceTextEncodingType.voice,
        ),
      );
      socket.add('storedhistory:{"requestId":"browser","source":"comms"}');
      for (
        var i = 0;
        i < 100 && !messages.any((m) => m.startsWith('storedhistory:'));
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final page =
          jsonDecode(
                messages
                    .firstWhere((m) => m.startsWith('storedhistory:'))
                    .substring('storedhistory:'.length),
              )
              as Map;
      expect(page['requestId'], 'browser');
      expect(
        ((page['entries'] as List).single['data'] as Map)['text'],
        'archived voice',
      );
      expect(broadcasts, 0);
    },
  );
}
