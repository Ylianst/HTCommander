/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/winlink_gateway_relay.dart';

void main() {
  test(
    'disposing a pending login closes the socket and completes connect',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      final subscription = server.listen(accepted.complete);
      final broker = DataBrokerClient();
      final relay = WinlinkGatewayRelay(
        420,
        broker,
        server: server.address.address,
        port: server.port,
        useTls: false,
      );
      final connection = relay.connectAsync('N1ABC');
      final socket = await accepted.future.timeout(const Duration(seconds: 5));
      final closed = Completer<void>();
      socket.listen((_) {}, onDone: closed.complete);
      addTearDown(() async {
        relay.dispose();
        socket.destroy();
        await subscription.cancel();
        await server.close();
        broker.dispose();
      });
      relay.dispose();
      expect(await connection.timeout(const Duration(seconds: 1)), isFalse);
      await closed.future.timeout(const Duration(seconds: 1));
      expect(relay.isConnected, isFalse);
    },
  );

  test('disposing during TCP connection never leaves a live relay', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final subscription = server.listen(sockets.add);
    final broker = DataBrokerClient();
    final relay = WinlinkGatewayRelay(
      420,
      broker,
      server: server.address.address,
      port: server.port,
      useTls: false,
    );
    addTearDown(() async {
      relay.dispose();
      for (final socket in sockets) {
        socket.destroy();
      }
      await subscription.cancel();
      await server.close();
      broker.dispose();
    });
    final connection = relay.connectAsync('N1ABC');
    relay.dispose();
    expect(await connection.timeout(const Duration(seconds: 1)), isFalse);
    expect(relay.isConnected, isFalse);
    expect(await relay.connectAsync('N1ABC'), isFalse);
  });
}
