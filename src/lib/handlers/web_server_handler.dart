/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Owns the [WebServer] and starts / stops it based on the `webServerEnabled` /
`webServerPort` settings (DataBroker device 0). Beyond serving the Flutter web
build, it bridges the browser to the radio over a WebSocket:

  * Raw radio response frames (`RawCommandRx`) are forwarded to all browsers as
    binary messages, which the Flutter web client decodes with the same radio
    code via `WebSocketRadioTransport`.
  * Binary messages from a browser are the raw GATT command frames the radio
    expects; they are dispatched to the radio as `SendRawCommand`.
  * Text control messages (`connect` / `disconnect`) drive the desktop radio
    connection, and the radio state is reported back as `wasconnected` /
    `connecting` / `disconnected`.

The web server feature is desktop-only; on the web the [WebServer] facade
resolves to an inert stub.
*/

import 'dart:convert';
import 'dart:typed_data';

import '../aprs/aprs_packet.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';
import '../services/web/web_server.dart';

/// Manages the lifecycle of the [WebServer] and bridges WebSocket clients to the
/// radio, based on app settings.
class WebServerHandler {
  WebServerHandler() : _broker = DataBrokerClient();

  final DataBrokerClient _broker;

  WebServer? _server;
  bool _enabled = false;
  int _port = 8080;
  bool _disposed = false;

  /// Latest APRS packet list seen on the broker, cached so it can be snapshotted
  /// to a browser on connect. Refreshed on demand via `RequestAprsPackets`.
  List<AprsPacket>? _lastAprsPacketList;

  /// Device IDs of the currently connected radios. The first entry is the radio
  /// bridged to WebSocket clients.
  final List<int> _connectedRadios = <int>[];

  /// Initializes the handler: loads settings, subscribes to changes, and starts
  /// the server if enabled.
  void init() {
    _enabled = (_broker.getValue<int>(0, 'webServerEnabled', 0) ?? 0) == 1;
    _port = _broker.getValue<int>(0, 'webServerPort', 8080) ?? 8080;

    _refreshConnectedRadios();

    _broker.subscribeMultiple(
      deviceId: 0,
      names: <String>['webServerEnabled', 'webServerPort'],
      callback: _onSettingChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    // Cache the APRS packet list so it can be snapshotted to browsers on
    // connect (it is dispatched on demand via `RequestAprsPackets`).
    _broker.subscribe(
      deviceId: 1,
      name: 'AprsPacketList',
      callback: _onAprsPacketList,
    );
    // Mirror device-0 setting changes to connected browsers so the hosted web
    // UI stays in sync with the desktop app's settings.
    _broker.subscribe(
      deviceId: 0,
      name: DataBroker.allNames,
      callback: _onHostSettingChanged,
    );
    // Radio state changes (per radio device) drive the web UI status.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'State',
      callback: _onRadioState,
    );
    // Raw radio response frames are relayed to browsers as binary messages.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'RawCommandRx',
      callback: _onRawCommandRx,
    );

    if (_enabled) _startServer();
  }

  /// The radio device bridged to WebSocket clients, or `-1` if none.
  int get _targetRadioDeviceId =>
      _connectedRadios.isNotEmpty ? _connectedRadios.first : -1;

  // ---------------------------------------------------------------------------
  // Settings / radio tracking
  // ---------------------------------------------------------------------------

  void _onSettingChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (name == 'webServerEnabled') {
      final enabled = (data is int ? data : 0) == 1;
      if (enabled == _enabled) return;
      _enabled = enabled;
      if (_enabled) {
        _startServer();
      } else {
        _stopServer();
      }
    } else if (name == 'webServerPort') {
      final port = data is int ? data : _port;
      if (port == _port) return;
      _port = port;
      // Rebind on the new port if currently running.
      if (_enabled) {
        _stopServer();
        _startServer();
      }
    }
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final previousTarget = _targetRadioDeviceId;
    _refreshConnectedRadios();
    if (_targetRadioDeviceId != previousTarget) {
      // The bridged radio changed; refresh every browser's status.
      _server?.broadcastText(_stateMessageFor(_currentRadioState));
    }
  }

  void _refreshConnectedRadios() {
    _connectedRadios.clear();
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (radios is List) {
      for (final item in radios) {
        if (item is! Map) continue;
        final deviceId = item['DeviceId'] ?? item['deviceId'];
        if (deviceId is int && deviceId > 0) {
          _connectedRadios.add(deviceId);
        }
      }
    }
  }

  /// The current state string of the bridged radio (e.g. `Connected`).
  String get _currentRadioState {
    final target = _targetRadioDeviceId;
    if (target < 0) return 'Disconnected';
    final state = _broker.getValueDynamic(target, 'State', 'Disconnected');
    return state is String ? state : 'Disconnected';
  }

  /// Maps a radio state string to the control message the browser expects.
  /// `Connected` becomes `wasconnected` so the page (re)fetches device info,
  /// channels, settings and status through the bridge.
  String _stateMessageFor(String radioState) {
    switch (radioState) {
      case 'Connected':
        return 'wasconnected';
      case 'Connecting':
        return 'connecting';
      default:
        return 'disconnected';
    }
  }

  // ---------------------------------------------------------------------------
  // Radio -> browser
  // ---------------------------------------------------------------------------

  void _onRadioState(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (deviceId != _targetRadioDeviceId) return;
    final state = data is String ? data : 'Disconnected';
    _server?.broadcastText(_stateMessageFor(state));
  }

  void _onRawCommandRx(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (deviceId != _targetRadioDeviceId) return;
    if (data is! Uint8List) return;
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    server.broadcastBinary(data);
  }

  // ---------------------------------------------------------------------------
  // Browser -> radio
  // ---------------------------------------------------------------------------

  void _onClientConnected(WebSocketClient client) {
    if (_disposed) return;
    // Report the current radio status to the freshly connected browser.
    client.sendText(_stateMessageFor(_currentRadioState));
    // Sync the host's device-0 settings so the web UI matches the desktop app.
    _sendSettingsTo(client);
    // Seed the browser's Comms/APRS tabs with the host's stored history.
    _sendHistoryTo(client);
  }

  void _onAprsPacketList(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is List) {
      _lastAprsPacketList = data.whereType<AprsPacket>().toList(growable: false);
    }
  }

  /// Broadcasts a device-0 setting change to every connected browser so the web
  /// UI tracks the desktop app's settings live. Transient UI selection state is
  /// excluded (see [HostBridge.isSyncedSetting]).
  void _onHostSettingChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (!HostBridge.isSyncedSetting(name)) return;
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    final encoded = _encodeSetting(name, data);
    if (encoded == null) return;
    server.broadcastText('setting:$encoded');
  }

  /// Sends the host's full device-0 settings snapshot to [client].
  void _sendSettingsTo(WebSocketClient client) {
    try {
      final safe = <String, Object?>{};
      DataBroker.getDeviceValues(0).forEach((name, value) {
        if (!HostBridge.isSyncedSetting(name)) return;
        try {
          jsonEncode(value); // Only include JSON-serializable settings.
          safe[name] = value;
        } catch (_) {
          // Skip values that cannot be represented on the wire.
        }
      });
      if (safe.isEmpty) return;
      client.sendText('settings:${jsonEncode(safe)}');
    } catch (ex) {
      _broker.logError('[WebServer] Failed to send settings: $ex');
    }
  }

  /// Encodes a single device-0 setting as `{"name":...,"value":...}`, or null
  /// if the value is not JSON-serializable.
  String? _encodeSetting(String name, Object? data) {
    try {
      return jsonEncode(<String, Object?>{'name': name, 'value': data});
    } catch (_) {
      return null;
    }
  }

  /// Applies a device-0 setting change pushed by a browser, persisting it on the
  /// host (which also re-broadcasts it to the other clients).
  void _applyClientSetting(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map) return;
      final name = data['name'];
      if (name is! String || !HostBridge.isSyncedSetting(name)) return;
      Object? value = data['value'];
      if (value is List && value.every((e) => e is String)) {
        value = value.cast<String>();
      }
      _broker.dispatch(deviceId: 0, name: name, data: value, store: true);
    } catch (ex) {
      _broker.logError('[WebServer] Failed to apply client setting: $ex');
    }
  }

  /// Sends a one-shot snapshot of the host's comms/APRS history to [client] so
  /// past events appear in the browser's tabs. The comms history is read from
  /// the broker; the APRS list is refreshed on demand (a synchronous dispatch
  /// updates [_lastAprsPacketList]) and serialized.
  void _sendHistoryTo(WebSocketClient client) {
    try {
      final decoded = _broker.getValueDynamic(1, 'DecodedTextHistory', null);

      // Ask the APRS handler to (re)publish its list; the callback is invoked
      // synchronously, refreshing the cache before we read it below.
      _broker.dispatch(
        deviceId: 1,
        name: 'RequestAprsPackets',
        data: null,
        store: false,
      );
      final aprs = _lastAprsPacketList
          ?.map((p) => p.toJson())
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

      final payload = <String, Object?>{
        if (decoded is List) 'decodedText': decoded,
        if (aprs != null && aprs.isNotEmpty) 'aprs': aprs,
      };
      if (payload.isEmpty) return;
      client.sendText('history:${jsonEncode(payload)}');
    } catch (ex) {
      _broker.logError('[WebServer] Failed to send history: $ex');
    }
  }

  void _onTextMessage(WebSocketClient client, String message) {
    if (_disposed) return;
    if (message.startsWith('setsetting:')) {
      _applyClientSetting(message.substring('setsetting:'.length));
      return;
    }
    final target = _targetRadioDeviceId;
    switch (message) {
      case 'connect':
        if (target < 0) {
          client.sendText(
            'log:No radio connected. Connect a radio from the desktop '
            'HTCommander application.',
          );
        } else {
          // Already connected; resend status so the browser fetches state.
          client.sendText(_stateMessageFor(_currentRadioState));
        }
        break;
      case 'disconnect':
        if (target >= 0) {
          // Fire-and-forget; state changes propagate via the `State` event.
          BluetoothService().disconnectRadio(target);
        }
        break;
    }
  }

  void _onBinaryMessage(WebSocketClient client, Uint8List data) {
    if (_disposed) return;
    final target = _targetRadioDeviceId;
    if (target < 0 || data.length < 4) return;
    // The browser sends raw GATT command frames; hand them to the radio.
    _broker.dispatch(
      deviceId: target,
      name: 'SendRawCommand',
      data: data,
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Server lifecycle
  // ---------------------------------------------------------------------------

  void _startServer() {
    if (_server != null) return;
    final server = WebServer(_port);
    server.onClientConnected = _onClientConnected;
    server.onTextMessage = _onTextMessage;
    server.onBinaryMessage = _onBinaryMessage;
    _server = server;
    server.start();
  }

  void _stopServer() {
    final server = _server;
    if (server == null) return;
    _server = null;
    server.dispose();
  }

  /// Stops the server and releases all resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopServer();
    _broker.dispose();
  }
}
