/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Web stub for [MqttClientFacade]. The web build cannot open the plain TCP
sockets MQTT requires, so the client is unavailable. Every method is an inert
no-op and [connect] / [testConnection] report failure. The public surface is
kept identical to the `dart:io` implementation so shared code keeps compiling.
*/

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

/// Inert web stub of the MQTT client. See the `_io` implementation for the real
/// behaviour.
class MqttClientFacade {
  MqttClientFacade({
    required String url,
    String? username,
    String? password,
    String? clientId,
  });

  bool get isConnected => false;

  MqttMessageCallback? onMessage;

  void Function()? onDisconnected;

  void Function()? onConnected;

  Future<MqttConnectResult> connect() async =>
      const MqttConnectResult(ok: false, error: 'MQTT is not supported on web');

  void disconnect() {}

  void publish(String topic, String payload, {bool retain = false}) {}

  void subscribe(String topic) {}

  void dispose() {}

  /// Attempts a short-lived connection to verify the broker URL and
  /// credentials, then disconnects. Always fails on web.
  static Future<MqttConnectResult> testConnection({
    required String url,
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const MqttConnectResult(ok: false, error: 'MQTT is not supported on web');
}
