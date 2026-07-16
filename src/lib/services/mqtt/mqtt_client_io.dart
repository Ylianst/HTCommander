/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Desktop / mobile implementation of [MqttClientFacade], backed by
`package:mqtt_client`'s `MqttServerClient`. Wraps the connect / publish /
subscribe / disconnect surface the Home Assistant bridge needs behind a small,
platform-neutral API, and provides a one-shot [testConnection] used by the
Settings dialog's Test button.

This file references `dart:io` (through `mqtt_client`) and so is only compiled
on platforms that provide it; the web build uses the inert stub instead.
*/

import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Result of an MQTT connection attempt.
class MqttConnectResult {
  const MqttConnectResult({required this.ok, this.error});

  /// Whether the connection succeeded.
  final bool ok;

  /// A human-readable error description when [ok] is false.
  final String? error;
}

/// Callback raised when a message arrives on a subscribed topic. [payload] is
/// the raw UTF-8 string of the MQTT message.
typedef MqttMessageCallback = void Function(String topic, String payload);

/// Parsed pieces of an MQTT broker URL.
class _BrokerEndpoint {
  const _BrokerEndpoint(this.host, this.port, this.secure);

  final String host;
  final int port;
  final bool secure;
}

/// A thin wrapper around [MqttServerClient] exposing only what the Home
/// Assistant bridge needs.
class MqttClientFacade {
  MqttClientFacade({
    required String url,
    String? username,
    String? password,
    String? clientId,
  })  : _username = (username != null && username.isNotEmpty) ? username : null,
        _password = (password != null && password.isNotEmpty) ? password : null,
        _clientId = (clientId != null && clientId.isNotEmpty)
            ? clientId
            : 'htcommander_${DateTime.now().millisecondsSinceEpoch}',
        _endpoint = _parseUrl(url);

  final _BrokerEndpoint _endpoint;
  final String? _username;
  final String? _password;
  final String _clientId;

  MqttServerClient? _client;
  bool _disposed = false;

  /// Raised when a message is received on any subscribed topic.
  MqttMessageCallback? onMessage;

  /// Raised when the broker connection is lost.
  void Function()? onDisconnected;

  /// Raised when the broker connection is (re)established.
  void Function()? onConnected;

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  /// Whether the client is currently connected to the broker.
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// Connects to the broker. Returns a result describing success or the failure
  /// reason. On success, `autoReconnect` keeps the connection alive.
  Future<MqttConnectResult> connect() async {
    if (_disposed) {
      return const MqttConnectResult(ok: false, error: 'Client disposed');
    }
    final client = MqttServerClient.withPort(
      _endpoint.host,
      _clientId,
      _endpoint.port,
    );
    client.logging(on: false);
    client.secure = _endpoint.secure;
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.onConnected = () => onConnected?.call();
    client.onDisconnected = () => onDisconnected?.call();

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .startClean();
    if (_username != null) {
      connMessage.authenticateAs(_username, _password);
    }
    client.connectionMessage = connMessage;
    _client = client;

    try {
      await client.connect(_username, _password);
    } on Exception catch (e) {
      client.disconnect();
      _client = null;
      return MqttConnectResult(ok: false, error: e.toString());
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final status = client.connectionStatus;
      client.disconnect();
      _client = null;
      return MqttConnectResult(
        ok: false,
        error: 'Connection refused (${status?.returnCode})',
      );
    }

    _updatesSub = client.updates?.listen(_onUpdates);
    return const MqttConnectResult(ok: true);
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    final handler = onMessage;
    if (handler == null) return;
    for (final event in events) {
      final message = event.payload;
      if (message is! MqttPublishMessage) continue;
      final payload =
          MqttPublishPayload.bytesToStringAsString(message.payload.message);
      handler(event.topic, payload);
    }
  }

  /// Publishes [payload] to [topic]. Discovery configs and state should be
  /// published with [retain] true so Home Assistant recovers them after a
  /// restart.
  void publish(String topic, String payload, {bool retain = false}) {
    final client = _client;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    final data = builder.payload;
    if (data == null) return;
    client.publishMessage(topic, MqttQos.atLeastOnce, data, retain: retain);
  }

  /// Subscribes to [topic] (command topics from Home Assistant).
  void subscribe(String topic) {
    final client = _client;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    client.subscribe(topic, MqttQos.atLeastOnce);
  }

  /// Disconnects from the broker without disposing the wrapper.
  void disconnect() {
    _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
    _client = null;
  }

  /// Releases all resources. The wrapper cannot be reused afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
  }

  /// Attempts a short-lived connection to verify the broker URL and
  /// credentials, then disconnects. Used by the Settings Test button.
  static Future<MqttConnectResult> testConnection({
    required String url,
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _BrokerEndpoint endpoint;
    try {
      endpoint = _parseUrl(url);
    } on Exception catch (e) {
      return MqttConnectResult(ok: false, error: e.toString());
    }
    if (endpoint.host.isEmpty) {
      return const MqttConnectResult(ok: false, error: 'Invalid broker URL');
    }

    final clientId = 'htcommander_test_${DateTime.now().millisecondsSinceEpoch}';
    final client = MqttServerClient.withPort(
      endpoint.host,
      clientId,
      endpoint.port,
    );
    client.logging(on: false);
    client.secure = endpoint.secure;
    client.keepAlivePeriod = 10;
    client.autoReconnect = false;

    final user = (username != null && username.isNotEmpty) ? username : null;
    final pass = (password != null && password.isNotEmpty) ? password : null;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    if (user != null) {
      connMessage.authenticateAs(user, pass);
    }
    client.connectionMessage = connMessage;

    try {
      await client.connect(user, pass).timeout(timeout);
    } on TimeoutException {
      client.disconnect();
      return const MqttConnectResult(ok: false, error: 'Connection timed out');
    } on Exception catch (e) {
      client.disconnect();
      return MqttConnectResult(ok: false, error: e.toString());
    }

    final connected =
        client.connectionStatus?.state == MqttConnectionState.connected;
    final returnCode = client.connectionStatus?.returnCode;
    client.disconnect();

    if (!connected) {
      return MqttConnectResult(
        ok: false,
        error: 'Connection refused ($returnCode)',
      );
    }
    return const MqttConnectResult(ok: true);
  }

  /// Parses a broker URL into host / port / secure. Accepts `mqtt://host:port`,
  /// `mqtts://host:port`, `tcp://host:port`, a bare `host:port`, or just
  /// `host`. Defaults to port 8883 for secure schemes, 1883 otherwise.
  static _BrokerEndpoint _parseUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return const _BrokerEndpoint('', 1883, false);

    bool secure = false;
    // If there's no scheme, add one so Uri parses host/port reliably.
    if (!text.contains('://')) {
      text = 'mqtt://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      return const _BrokerEndpoint('', 1883, false);
    }

    switch (uri.scheme.toLowerCase()) {
      case 'mqtts':
      case 'ssl':
      case 'tls':
      case 'wss':
        secure = true;
        break;
      default:
        secure = false;
    }

    final port = uri.hasPort ? uri.port : (secure ? 8883 : 1883);
    return _BrokerEndpoint(uri.host, port, secure);
  }
}
