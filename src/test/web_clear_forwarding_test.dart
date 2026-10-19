import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_conversation.dart';
import 'package:htcommander/handlers/web_server_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/host_bridge.dart';

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

  setUp(() async {
    received.clear();
    final port = await _freePort();
    DataBroker.dispatch(deviceId: 0, name: 'webServerPort', data: port);
    DataBroker.dispatch(deviceId: 0, name: 'webServerEnabled', data: 1);
    handler = WebServerHandler()..init();

    listener = DataBrokerClient();
    for (final name in [
      ...HostBridge.forwardedClearEvents,
      'ClearPackets',
    ]) {
      listener.subscribe(
        deviceId: 1,
        name: name,
        callback: (_, n, data) => received.add((n, data)),
      );
    }

    // The server binds asynchronously; retry until it accepts connections.
    for (var i = 0; ; i++) {
      try {
        socket = await WebSocket.connect(
          'ws://127.0.0.1:$port/websocket.aspx',
        );
        break;
      } catch (_) {
        if (i > 50) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    // Drain the host's on-connect snapshot messages.
    socket.listen((_) {});
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
    socket.add(
      'clear:{"event":"$clearAprsConversationEvent","peer":"W1AW-9"}',
    );
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
}
