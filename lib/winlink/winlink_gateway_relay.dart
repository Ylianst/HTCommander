/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../services/data_broker_client.dart';

/// Manages a TCP/TLS connection to the Winlink CMS gateway
/// (server.winlink.org:8773) for relaying Winlink protocol traffic between a BBS
/// radio client and the internet gateway. The relay logs in using the connecting
/// station's callsign, obtains the ;PQ: challenge, and then transparently relays
/// all Winlink B2F protocol traffic.
class WinlinkGatewayRelay {
  WinlinkGatewayRelay(
    this._deviceId,
    this._broker, {
    this.server = 'server.winlink.org',
    this.port = 8773,
    this.useTls = true,
  });

  final int _deviceId;
  final DataBrokerClient _broker;
  final String server;
  final int port;
  final bool useTls;

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  bool _tcpRunning = false;
  bool _disposed = false;

  // Handshake state.
  Completer<bool>? _handshakeCompleter;
  bool _handshaking = false;
  String _lineBuffer = '';
  String? _stationCallsign;

  /// The ;PQ: challenge string received from the CMS gateway during login.
  String? pqChallenge;

  /// The [WL2K-...] banner string received from the CMS gateway.
  String? wl2kBanner;

  /// Whether the relay is currently connected to the CMS gateway.
  bool get isConnected => _socket != null && _tcpRunning;

  /// Fired when line-based data is received from the CMS gateway.
  void Function(String line)? lineReceived;

  /// Fired when raw binary data is received from the CMS gateway.
  void Function(Uint8List data)? binaryDataReceived;

  /// Fired when the CMS gateway connection is lost or closed.
  void Function()? disconnected;

  /// When true, incoming data is forwarded as raw binary via [binaryDataReceived].
  /// When false, incoming data is parsed as lines and forwarded via [lineReceived].
  bool binaryMode = false;

  /// Connects to the CMS gateway and performs the initial login handshake using
  /// the specified station callsign. Returns true if the connection and login
  /// succeed and a session prompt is received.
  Future<bool> connectAsync(
    String stationCallsign, {
    int timeoutMs = 15000,
  }) async {
    try {
      _broker.logInfo(
        '[BBS/$_deviceId/Relay] Connecting to CMS gateway $server:$port for station $stationCallsign',
      );

      final timeout = Duration(milliseconds: timeoutMs);
      try {
        _socket = useTls
            ? await SecureSocket.connect(server, port).timeout(timeout)
            : await Socket.connect(server, port).timeout(timeout);
      } on TimeoutException {
        _broker.logError('[BBS/$_deviceId/Relay] Connection timed out');
        _cleanupTcp();
        return false;
      }

      _tcpRunning = true;
      _stationCallsign = stationCallsign;
      _handshaking = true;
      _handshakeCompleter = Completer<bool>();

      _subscription = _socket!.listen(
        _onData,
        onError: (Object error) {
          if (_tcpRunning) {
            _broker.logError('[BBS/$_deviceId/Relay] Receive error: $error');
          }
          _handleDisconnect();
        },
        onDone: _handleDisconnect,
        cancelOnError: true,
      );

      // Wait for the handshake to complete or time out.
      final handshakeOk = await _handshakeCompleter!.future.timeout(
        timeout,
        onTimeout: () => false,
      );
      _handshaking = false;

      if (!handshakeOk) {
        _broker.logError('[BBS/$_deviceId/Relay] Handshake failed');
        disconnect();
        return false;
      }

      _broker.logInfo(
        '[BBS/$_deviceId/Relay] Connected and handshake complete. PQ=${pqChallenge ?? "(none)"}',
      );
      return true;
    } catch (ex) {
      _broker.logError('[BBS/$_deviceId/Relay] Connection failed: $ex');
      _cleanupTcp();
      return false;
    }
  }

  void _onData(Uint8List data) {
    if (_handshaking) {
      _processHandshakeData(data);
    } else if (binaryMode) {
      binaryDataReceived?.call(data);
    } else {
      final chunk = utf8.decode(data, allowMalformed: true);
      final lines = chunk
          .replaceAll('\r\n', '\r')
          .replaceAll('\n', '\r')
          .split('\r');
      for (final line in lines) {
        if (line.isEmpty) continue;
        _broker.logInfo('[BBS/$_deviceId/Relay] CMS << $line');
        lineReceived?.call(line);
      }
    }
  }

  void _processHandshakeData(Uint8List data) {
    _lineBuffer += utf8.decode(data, allowMalformed: true);

    while (true) {
      final crIdx = _lineBuffer.indexOf('\r');
      final nlIdx = _lineBuffer.indexOf('\n');
      int lineEnd = -1;
      int skipLen = 0;

      if (crIdx >= 0 && nlIdx >= 0) {
        if (crIdx < nlIdx) {
          lineEnd = crIdx;
          skipLen = (nlIdx == crIdx + 1) ? 2 : 1;
        } else {
          lineEnd = nlIdx;
          skipLen = 1;
        }
      } else if (crIdx >= 0) {
        lineEnd = crIdx;
        skipLen = 1;
      } else if (nlIdx >= 0) {
        lineEnd = nlIdx;
        skipLen = 1;
      } else {
        break;
      }

      final line = _lineBuffer.substring(0, lineEnd);
      _lineBuffer = _lineBuffer.substring(lineEnd + skipLen);

      _broker.logInfo('[BBS/$_deviceId/Relay] CMS << $line');

      final trimmed = line.trim();

      if (trimmed.toLowerCase() == 'callsign :') {
        _broker.logInfo(
          '[BBS/$_deviceId/Relay] Sending callsign: $_stationCallsign',
        );
        sendRaw('$_stationCallsign\r');
        continue;
      }

      if (trimmed.toLowerCase() == 'password :') {
        _broker.logInfo('[BBS/$_deviceId/Relay] Sending password');
        sendRaw('CMSTelnet\r');
        continue;
      }

      // Capture [WL2K-...] banner
      if (trimmed.startsWith('[WL2K-') && trimmed.endsWith(r'$]')) {
        wl2kBanner = trimmed;
        _broker.logInfo('[BBS/$_deviceId/Relay] Got WL2K banner: $wl2kBanner');
        continue;
      }

      // Capture ;PQ: challenge
      if (trimmed.startsWith(';PQ:')) {
        pqChallenge = trimmed.substring(4).trim();
        _broker.logInfo(
          '[BBS/$_deviceId/Relay] Got PQ challenge: $pqChallenge',
        );
        continue;
      }

      // Check for session prompt (ends with >)
      if (trimmed.endsWith('>')) {
        if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
          _handshakeCompleter!.complete(true);
        }
        return;
      }
    }
  }

  /// Sends a string to the CMS gateway (a trailing \r is appended).
  void sendLine(String line) {
    if (!isConnected) return;
    _broker.logInfo('[BBS/$_deviceId/Relay] CMS >> $line');
    sendRaw('$line\r');
  }

  /// Sends raw string data to the CMS gateway (no \r appended).
  void sendRaw(String data) {
    if (_socket == null || !_tcpRunning) return;
    try {
      _socket!.add(utf8.encode(data));
    } catch (ex) {
      _broker.logError('[BBS/$_deviceId/Relay] Send error: $ex');
      disconnect();
    }
  }

  /// Sends raw binary data to the CMS gateway.
  void sendBinary(Uint8List data) {
    if (_socket == null || !_tcpRunning) return;
    try {
      _socket!.add(data);
    } catch (ex) {
      _broker.logError('[BBS/$_deviceId/Relay] Binary send error: $ex');
      disconnect();
    }
  }

  /// Disconnects from the CMS gateway.
  void disconnect() {
    if (!_tcpRunning && _socket == null) return;
    _broker.logInfo('[BBS/$_deviceId/Relay] Disconnecting from CMS gateway');
    _tcpRunning = false;
    _cleanupTcp();
    disconnected?.call();
  }

  void _handleDisconnect() {
    if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
      _handshakeCompleter!.complete(false);
    }
    if (_tcpRunning) {
      _broker.logInfo('[BBS/$_deviceId/Relay] CMS connection closed');
      _tcpRunning = false;
      _cleanupTcp();
      disconnected?.call();
    }
  }

  void _cleanupTcp() {
    try {
      _subscription?.cancel();
      _subscription = null;
      _socket?.destroy();
      _socket = null;
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tcpRunning = false;
    _cleanupTcp();
  }
}
