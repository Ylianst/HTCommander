/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AgwpeSocketServer` and `TcpClientHandler`
classes. A TCP server implementing the AGW Packet Engine (AGWPE) API. It accepts
client connections, frames the AGWPE protocol (36-byte header + payload), and
surfaces connect / disconnect / received-frame events. The protocol logic that
acts on those frames (registration, monitoring, UNPROTO, connected sessions)
lives in [AgwpeHandler]; this class is only responsible for transport and
framing.
*/

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../data_broker_client.dart';
import 'agwpe_frame.dart';

/// Callback raised when an AGWPE client connects or disconnects.
typedef AgwpeClientCallback = void Function(int clientId);

/// Callback raised when a complete AGWPE frame is received from a client.
typedef AgwpeFrameCallback = void Function(int clientId, AgwpeFrame frame);

/// A TCP server that listens for AGWPE clients, frames the protocol, and
/// broadcasts monitoring frames. Bound to all interfaces (`anyIPv4`) to match
/// the C# `IPAddress.Any` behaviour.
class AgwpeServer {
  AgwpeServer(this.port) : _broker = DataBrokerClient();

  final int port;
  final DataBrokerClient _broker;

  ServerSocket? _listener;
  bool _running = false;
  int _nextClientId = 1;
  final Map<int, _AgwpeClient> _clients = <int, _AgwpeClient>{};

  /// Raised when a new client connects.
  AgwpeClientCallback? onClientConnected;

  /// Raised when a client disconnects.
  AgwpeClientCallback? onClientDisconnected;

  /// Raised when a complete AGWPE frame is received from a client.
  AgwpeFrameCallback? onFrameReceived;

  /// Whether the server is currently listening.
  bool get isRunning => _running;

  /// Starts the AGWPE server. Returns `true` on success.
  Future<bool> start() async {
    if (_running) return true;
    try {
      _listener = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _running = true;
      _listener!.listen(
        _onConnection,
        onError: (Object _) {
          // Ignore accept errors while running.
        },
      );
      _broker.logInfo('[AgwpeServer] Started on port $port');
      return true;
    } catch (ex) {
      _broker.logError('[AgwpeServer] Failed to start on port $port: $ex');
      _running = false;
      return false;
    }
  }

  void _onConnection(Socket socket) {
    if (!_running) {
      socket.destroy();
      return;
    }
    final clientId = _nextClientId++;
    final client = _AgwpeClient(this, clientId, socket);
    _clients[clientId] = client;
    client.run();
    _broker.logInfo(
      '[AgwpeServer] Client $clientId connected: '
      '${socket.remoteAddress.address}:${socket.remotePort}',
    );
    onClientConnected?.call(clientId);
  }

  /// Stops the server and closes all active client connections.
  void stop() {
    if (!_running && _listener == null) return;
    _running = false;
    _listener?.close();
    _listener = null;
    final clients = List<_AgwpeClient>.from(_clients.values);
    for (final client in clients) {
      client.close();
    }
    _clients.clear();
    _broker.logInfo('[AgwpeServer] Stopped');
  }

  void dispose() {
    stop();
    _broker.dispose();
  }

  /// Enables or disables monitoring-frame delivery for a single client.
  void setClientMonitoring(int clientId, bool enabled) {
    _clients[clientId]?.sendMonitoringFrames = enabled;
  }

  /// Sends a monitoring [frame] to every client that has monitoring enabled.
  void broadcastMonitorFrame(AgwpeFrame frame) {
    final bytes = frame.toBytes();
    for (final client in _clients.values) {
      if (client.sendMonitoringFrames) client.send(bytes);
    }
  }

  /// Sends [frame] to a single client identified by [clientId].
  void sendFrameToClient(int clientId, AgwpeFrame frame) {
    _clients[clientId]?.send(frame.toBytes());
  }

  // --- called by client handlers -------------------------------------------

  void _onFrame(int clientId, AgwpeFrame frame) {
    onFrameReceived?.call(clientId, frame);
  }

  void _removeClient(int clientId) {
    if (_clients.remove(clientId) != null) {
      _broker.logInfo('[AgwpeServer] Client $clientId disconnected');
      onClientDisconnected?.call(clientId);
    }
  }
}

/// Manages a single connected AGWPE TCP client: byte accumulation, frame
/// parsing, and writing responses.
class _AgwpeClient {
  _AgwpeClient(this._server, this.id, this._socket);

  final AgwpeServer _server;
  final int id;
  final Socket _socket;

  StreamSubscription<Uint8List>? _sub;
  Uint8List _rx = Uint8List(0);
  bool _closed = false;

  /// Whether monitoring frames should be forwarded to this client.
  bool sendMonitoringFrames = false;

  void run() {
    _sub = _socket.listen(
      _onData,
      onError: (Object _) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  void _onData(Uint8List chunk) {
    if (_closed) return;
    // Append the new chunk to any buffered bytes.
    if (_rx.isEmpty) {
      _rx = Uint8List.fromList(chunk);
    } else {
      final combined = Uint8List(_rx.length + chunk.length)
        ..setRange(0, _rx.length, _rx)
        ..setRange(_rx.length, _rx.length + chunk.length, chunk);
      _rx = combined;
    }

    // Parse as many complete frames as are available.
    while (true) {
      final result = AgwpeFrame.tryParse(_rx);
      if (result == null) break;
      _rx = Uint8List.fromList(
        Uint8List.sublistView(_rx, result.consumed),
      );
      _server._onFrame(id, result.frame);
    }
  }

  void send(Uint8List data) {
    if (_closed) return;
    try {
      _socket.add(data);
    } catch (_) {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _sub?.cancel();
    try {
      _socket.destroy();
    } catch (_) {
      // Ignore.
    }
    _server._removeClient(id);
  }
}
