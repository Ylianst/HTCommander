/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Web stub for [WebServer]. The web build cannot open listening sockets, so the
web server is unavailable. Every method is an inert no-op and [start] reports
failure. The public surface is kept identical to the `dart:io` implementation so
shared code keeps compiling.
*/

import 'dart:typed_data';

/// Callback raised when a WebSocket [client] connects or disconnects.
typedef WebSocketClientCallback = void Function(WebSocketClient client);

/// Callback raised when a text message is received from a WebSocket [client].
typedef WebSocketTextCallback =
    void Function(WebSocketClient client, String message);

/// Callback raised when a binary message is received from a WebSocket [client].
typedef WebSocketBinaryCallback =
    void Function(WebSocketClient client, Uint8List data);

/// Inert web stub of a connected WebSocket client.
class WebSocketClient {
  WebSocketClient(this.id);

  final int id;

  void sendText(String message) {}

  void sendBinary(List<int> data) {}
}

/// Inert web stub of the static web + WebSocket server.
class WebServer {
  WebServer(this.port);

  final int port;

  WebSocketClientCallback? onClientConnected;
  WebSocketClientCallback? onClientDisconnected;
  WebSocketTextCallback? onTextMessage;
  WebSocketBinaryCallback? onBinaryMessage;

  bool get isRunning => false;

  int? get boundPort => null;

  int get clientCount => 0;

  Future<bool> start() async => false;

  void stop() {}

  void dispose() {}

  void broadcastText(String message) {}

  void broadcastBinary(List<int> data) {}
}
