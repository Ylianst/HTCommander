/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

WebSocket-backed [RadioTransport]. Used by the Flutter web build when it is
served by the desktop HTCommander app: instead of driving the radio directly
over Web Bluetooth, the browser connects back to the host over the existing
`/websocket.aspx` bridge (see services/web/web_server_io.dart and
handlers/web_server_handler.dart) and shares the host's already-connected radio.

The bridge speaks the same un-framed GATT command frames
(`[group_hi, group_lo, cmd_hi, cmd_lo, payload...]`) that the web BLE path uses,
so this transport is a plain byte pipe:

  * Binary messages from the host are the radio's response frames; they are
    emitted on [dataStream] where `Radio._tryHandleWebDirectResponse` decodes
    them exactly as it would web BLE notifications.
  * [send] forwards the browser's raw command frames back to the host, which
    dispatches them to the radio as `SendRawCommand`.
  * Text control messages (`wasconnected` / `connecting` / `disconnected`) report
    the host radio's availability and are mapped to the transport state.

This class is cross-platform at the source level (web_socket_channel works on
both web and dart:io) but is only instantiated on the web build.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'radio_transport.dart';

/// A [RadioTransport] that bridges to a host HTCommander over a WebSocket.
class WebSocketRadioTransport implements RadioTransport {
  WebSocketRadioTransport();

  /// The host control message sent once a radio is connected and ready.
  static const String _kWasConnected = 'wasconnected';

  /// The host control message sent when no radio (or the shared radio) is
  /// available on the host.
  static const String _kDisconnected = 'disconnected';

  /// Prefix of the one-shot history snapshot the host sends on connect (the
  /// remainder is a JSON payload of the host's comms/APRS history).
  static const String _kHistoryPrefix = 'history:';

  /// Prefix of the full device-0 settings snapshot the host sends on connect
  /// (JSON object of name -> value).
  static const String _kSettingsPrefix = 'settings:';

  /// Prefix of a single device-0 setting change pushed by the host
  /// (JSON `{"name":...,"value":...}`).
  static const String _kSettingPrefix = 'setting:';

  /// Prefix the client uses to push a single device-0 setting change to the
  /// host (JSON `{"name":...,"value":...}`).
  static const String _kSetSettingPrefix = 'setsetting:';

  /// Prefix of the host's authoritative Winlink mail snapshot (JSON array of
  /// [WinLinkMail] maps). Sent on connect and whenever the host's mail changes.
  static const String _kMailPrefix = 'mail:';

  /// Prefix of a Winlink transfer status message pushed by the host. The
  /// remainder is the raw status string (empty clears the status).
  static const String _kWinlinkStatePrefix = 'winlinkstate:';

  /// Prefix of a Winlink error message pushed by the host.
  static const String _kWinlinkErrorPrefix = 'winlinkerror:';

  /// Prefix of the host's airplane (Dump1090) snapshot: a JSON array of
  /// `Aircraft` maps. Sent on connect and on each successful host poll. Only the
  /// desktop host can reach the (LAN) Dump1090 server, so the browser mirrors
  /// the host instead of polling itself.
  static const String _kAirplanesPrefix = 'airplanes:';

  /// Prefix of the host's radio list (JSON `{selected, radios:[{deviceId,name}]}`).
  /// Sent on connect and whenever the host's radios or selection change, so the
  /// browser can show the bridged radio's name and offer a radio switcher.
  static const String _kRadioListPrefix = 'radiolist:';

  /// Prefix the client uses to push a mail operation to the host
  /// (JSON `{"op":...}`).
  static const String _kMailOpPrefix = 'mailop:';

  /// Prefix the client uses to ask the host to start a Winlink sync (JSON).
  static const String _kWinlinkSyncPrefix = 'winlinksync:';

  /// Prefix the client uses to ask the host to disconnect an active sync.
  static const String _kWinlinkDisconnectPrefix = 'winlinkdisconnect:';

  /// Invoked with the raw JSON payload when the host sends a `history:` message.
  /// Wired up by [BluetoothService] to seed the comms/APRS tabs.
  void Function(String json)? onHistory;

  /// Invoked with the raw JSON payload for a full device-0 settings snapshot
  /// (`settings:`). Wired up by [BluetoothService].
  void Function(String json)? onSettingsSnapshot;

  /// Invoked with the raw JSON payload for a single device-0 setting change
  /// pushed by the host (`setting:`). Wired up by [BluetoothService].
  void Function(String json)? onSetting;

  /// Invoked with the raw JSON payload (array of mails) for the host's Winlink
  /// mail snapshot (`mail:`). Wired up by [BluetoothService].
  void Function(String json)? onMail;

  /// Invoked with the raw Winlink transfer status string pushed by the host
  /// (`winlinkstate:`). Wired up by [BluetoothService].
  void Function(String message)? onWinlinkState;

  /// Invoked with the raw Winlink error string pushed by the host
  /// (`winlinkerror:`). Wired up by [BluetoothService].
  void Function(String message)? onWinlinkError;

  /// Invoked with the raw JSON payload (array of aircraft) for the host's
  /// airplane snapshot (`airplanes:`). Wired up by [BluetoothService].
  void Function(String json)? onAirplanes;

  /// Invoked when the host reports whether it currently has a shared radio
  /// (`wasconnected` -> true, `disconnected` -> false). The session/socket stays
  /// open across false, so the browser mirrors the host live. Wired up by
  /// [BluetoothService].
  void Function(bool present)? onRadioPresence;

  /// Invoked with the raw JSON payload for the host's radio list (`radiolist:`).
  /// Wired up by [BluetoothService].
  void Function(String json)? onRadioList;

  /// How long to wait before retrying the socket after it drops or fails to
  /// open. The session persists across radio comings and goings.
  static const Duration _reconnectDelay = Duration(seconds: 3);

  final _stateController = StreamController<TransportState>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _scanController = StreamController<DiscoveredDevice>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  TransportState _state = TransportState.disconnected;
  DiscoveredDevice? _connectedDevice;

  /// Whether the session is wanted. While true the transport keeps the socket
  /// open and reconnects it if it drops, independent of whether the host has a
  /// radio to share. Cleared only by [disconnect] / [dispose].
  bool _sessionActive = false;

  /// Pending socket reconnect scheduled after a drop or a failed open.
  Timer? _reconnectTimer;

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateStream => _stateController.stream;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<DiscoveredDevice> get scanStream => _scanController.stream;

  @override
  DiscoveredDevice? get connectedDevice => _connectedDevice;

  void _setState(TransportState state) {
    if (_state == state) return;
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // Nothing to scan: the only "device" is the host itself.
  }

  @override
  Future<void> stopScan() async {}

  /// Establishes the host session. [device.id] must be the WebSocket URL
  /// (`ws://host:port/websocket.aspx`). Returns `true` once the session is
  /// wanted and the socket open has been kicked off; the socket then stays open
  /// (reconnecting if it drops) regardless of whether the host has a radio.
  /// Radio availability is reported separately via [onRadioPresence].
  @override
  Future<bool> connect(DiscoveredDevice device) async {
    if (_sessionActive) {
      return _state == TransportState.connected;
    }
    try {
      Uri.parse(device.id);
    } catch (_) {
      _setState(TransportState.disconnected);
      return false;
    }
    _connectedDevice = device;
    _sessionActive = true;
    _setState(TransportState.connecting);
    await _openSocket();
    return true;
  }

  /// Opens (or reopens) the WebSocket. On failure schedules a reconnect while
  /// the session is still wanted.
  Future<void> _openSocket() async {
    if (!_sessionActive) return;
    final device = _connectedDevice;
    if (device == null) return;
    _cleanupChannel();
    _setState(TransportState.connecting);
    try {
      final channel = WebSocketChannel.connect(Uri.parse(device.id));
      _channel = channel;
      // `ready` throws if the handshake fails; guard so a failure schedules a
      // retry rather than propagating.
      await channel.ready;
      _sub = channel.stream.listen(
        _onMessage,
        onError: (Object _) => _onSocketClosed(),
        onDone: _onSocketClosed,
        cancelOnError: false,
      );
    } catch (_) {
      _cleanupChannel();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_sessionActive) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (_sessionActive) unawaited(_openSocket());
    });
  }

  void _onMessage(dynamic message) {
    if (message is String) {
      _onControlMessage(message);
      return;
    }
    // Binary radio response frame.
    final Uint8List bytes;
    if (message is Uint8List) {
      bytes = message;
    } else if (message is List<int>) {
      bytes = Uint8List.fromList(message);
    } else {
      return;
    }
    if (bytes.isEmpty) return;
    if (!_dataController.isClosed) _dataController.add(bytes);
  }

  void _onControlMessage(String message) {
    // `log:` prefixed messages are host-side diagnostics; ignore here.
    if (message.startsWith(_kHistoryPrefix)) {
      onHistory?.call(message.substring(_kHistoryPrefix.length));
      return;
    }
    if (message.startsWith(_kSettingsPrefix)) {
      onSettingsSnapshot?.call(message.substring(_kSettingsPrefix.length));
      return;
    }
    if (message.startsWith(_kSettingPrefix)) {
      onSetting?.call(message.substring(_kSettingPrefix.length));
      return;
    }
    if (message.startsWith(_kMailPrefix)) {
      onMail?.call(message.substring(_kMailPrefix.length));
      return;
    }
    if (message.startsWith(_kWinlinkStatePrefix)) {
      onWinlinkState?.call(message.substring(_kWinlinkStatePrefix.length));
      return;
    }
    if (message.startsWith(_kWinlinkErrorPrefix)) {
      onWinlinkError?.call(message.substring(_kWinlinkErrorPrefix.length));
      return;
    }
    if (message.startsWith(_kAirplanesPrefix)) {
      onAirplanes?.call(message.substring(_kAirplanesPrefix.length));
      return;
    }
    if (message.startsWith(_kRadioListPrefix)) {
      onRadioList?.call(message.substring(_kRadioListPrefix.length));
      return;
    }
    if (message == _kWasConnected) {
      // The host has a shared radio ready: the pipe can carry radio frames.
      _setState(TransportState.connected);
      onRadioPresence?.call(true);
    } else if (message == _kDisconnected) {
      // The host has no shared radio. Keep the session/socket open (so settings,
      // mail, airplanes and the radio list still sync and a radio can appear
      // later) but report the radio as gone rather than tearing down.
      if (_state != TransportState.connecting) {
        _setState(TransportState.connecting);
      }
      onRadioPresence?.call(false);
    }
    // `connecting` keeps the transport waiting; command frames are only sent
    // once the host reports a ready radio (`wasconnected`).
  }

  void _onSocketClosed() {
    _cleanupChannel();
    if (!_sessionActive) {
      _setState(TransportState.disconnected);
      return;
    }
    // The session is still wanted: report the radio as gone and retry the socket
    // so the browser reconnects automatically once the host is reachable again.
    _setState(TransportState.connecting);
    onRadioPresence?.call(false);
    _scheduleReconnect();
  }

  @override
  Future<void> disconnect() async {
    // Ends the whole browser session. Closing the socket only detaches this
    // client; it deliberately does not tell the host to drop its shared radio.
    _sessionActive = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectedDevice = null;
    _setState(TransportState.disconnecting);
    _cleanupChannel();
    _setState(TransportState.disconnected);
  }

  void _cleanupChannel() {
    _sub?.cancel();
    _sub = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        channel.sink.close();
      } catch (_) {
        // Already closing.
      }
    }
  }

  @override
  Future<bool> send(Uint8List data) async {
    final channel = _channel;
    if (channel == null || _state != TransportState.connected) return false;
    try {
      channel.sink.add(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asks the host to disconnect the radio it is currently sharing. The browser
  /// session stays open; the host reports the radio as gone afterwards.
  bool requestHostDisconnect() => _sendControl('disconnect');

  /// Asks the host to switch the shared (preferred) radio to [hostDeviceId].
  bool selectHostRadio(int hostDeviceId) =>
      _sendControl('selectradio:$hostDeviceId');

  bool _sendControl(String message) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(message);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forwards a device-0 setting change to the host (`setsetting:`). The socket
  /// need only be open (not radio-ready), so settings still sync when no radio
  /// is shared. Returns false if the socket is not available.
  bool sendSetting(String name, Object? value) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(
        '$_kSetSettingPrefix${jsonEncode(<String, Object?>{'name': name, 'value': value})}',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Forwards a mail operation (add / update / delete / move) to the host so it
  /// mutates its authoritative mail store. Returns false if the socket is not
  /// available.
  bool sendMailOp(Map<String, Object?> op) => _sendText(_kMailOpPrefix, op);

  /// Asks the host to start a Winlink sync (internet or radio) on the client's
  /// behalf. Returns false if the socket is not available.
  bool sendWinlinkSync(Map<String, Object?> data) =>
      _sendText(_kWinlinkSyncPrefix, data);

  /// Asks the host to disconnect / cancel an active Winlink sync.
  bool sendWinlinkDisconnect() {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(_kWinlinkDisconnectPrefix);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends [prefix] followed by the JSON encoding of [payload]. The socket need
  /// only be open (not radio-ready). Returns false if unavailable.
  bool _sendText(String prefix, Map<String, Object?> payload) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add('$prefix${jsonEncode(payload)}');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> requestMtu(int mtu) async => 512;

  @override
  Future<void> dispose() async {
    _sessionActive = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupChannel();
    await _stateController.close();
    await _dataController.close();
    await _scanController.close();
  }
}
