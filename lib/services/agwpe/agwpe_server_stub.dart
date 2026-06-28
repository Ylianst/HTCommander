/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Web stub for [AgwpeServer]. The web build cannot open listening sockets, so the
AGWPE server is unavailable. Every method is an inert no-op and [start] reports
failure. The public surface is kept identical to the `dart:io` implementation so
shared code keeps compiling.
*/

import 'agwpe_frame.dart';

/// Callback raised when an AGWPE client connects or disconnects.
typedef AgwpeClientCallback = void Function(int clientId);

/// Callback raised when a complete AGWPE frame is received from a client.
typedef AgwpeFrameCallback = void Function(int clientId, AgwpeFrame frame);

/// Inert web stub of the AGWPE TCP server.
class AgwpeServer {
  AgwpeServer(this.port);

  final int port;

  AgwpeClientCallback? onClientConnected;
  AgwpeClientCallback? onClientDisconnected;
  AgwpeFrameCallback? onFrameReceived;

  bool get isRunning => false;

  Future<bool> start() async => false;

  void stop() {}

  void dispose() {}

  void setClientMonitoring(int clientId, bool enabled) {}

  void broadcastMonitorFrame(AgwpeFrame frame) {}

  void sendFrameToClient(int clientId, AgwpeFrame frame) {}
}
