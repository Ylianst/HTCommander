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

  /// How long to wait for the host to report a ready radio before failing the
  /// connect attempt.
  static const Duration _connectTimeout = Duration(seconds: 15);

  final _stateController = StreamController<TransportState>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _scanController = StreamController<DiscoveredDevice>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  TransportState _state = TransportState.disconnected;
  DiscoveredDevice? _connectedDevice;

  /// Completes once the host reports a ready radio (`wasconnected`), or with
  /// `false` if the socket closes / times out first.
  Completer<bool>? _connectCompleter;

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

  /// Connects to the host bridge. [device.id] must be the WebSocket URL
  /// (`ws://host:port/websocket.aspx`). Returns `true` once the host reports a
  /// ready radio, or `false` if the socket fails or no radio becomes available
  /// within [_connectTimeout].
  @override
  Future<bool> connect(DiscoveredDevice device) async {
    if (_state == TransportState.connected ||
        _state == TransportState.connecting) {
      return _state == TransportState.connected;
    }

    _setState(TransportState.connecting);
    final completer = Completer<bool>();
    _connectCompleter = completer;

    final Uri uri;
    try {
      uri = Uri.parse(device.id);
    } catch (_) {
      _setState(TransportState.disconnected);
      return false;
    }

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      // `ready` throws if the handshake fails; guard so connect returns false
      // rather than propagating.
      await channel.ready;

      _sub = channel.stream.listen(
        _onMessage,
        onError: (Object _) => _onSocketClosed(),
        onDone: _onSocketClosed,
        cancelOnError: false,
      );
      _connectedDevice = device;
    } catch (_) {
      _cleanupChannel();
      _setState(TransportState.disconnected);
      _completeConnect(false);
      return false;
    }

    // Fail the connect if the host never reports a ready radio in time.
    unawaited(
      Future<void>.delayed(_connectTimeout).then((_) {
        if (!completer.isCompleted) {
          _completeConnect(false);
          disconnect();
        }
      }),
    );

    return completer.future;
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
    if (message == _kWasConnected) {
      _setState(TransportState.connected);
      _completeConnect(true);
    } else if (message == _kDisconnected) {
      // Only tear down once we were actually connected to a host radio. The
      // host sends the current state right after the socket opens, so an early
      // `disconnected` simply means no radio is shared yet - keep waiting for
      // the connect timeout instead of dropping the socket immediately.
      if (_state == TransportState.connected) {
        _setState(TransportState.disconnected);
        _cleanupChannel();
      }
    }
    // `connecting` is ignored: the transport only reports connected once the
    // host radio is ready (`wasconnected`), so early command frames are not
    // lost.
  }

  void _onSocketClosed() {
    _completeConnect(false);
    if (_state != TransportState.disconnected) {
      _setState(TransportState.disconnected);
    }
    _cleanupChannel();
  }

  void _completeConnect(bool success) {
    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(success);
    }
  }

  @override
  Future<void> disconnect() async {
    // Closing the browser socket only detaches this client; it deliberately
    // does not tell the host to disconnect its (shared) radio.
    _completeConnect(false);
    _setState(TransportState.disconnecting);
    _cleanupChannel();
    _setState(TransportState.disconnected);
  }

  void _cleanupChannel() {
    _sub?.cancel();
    _sub = null;
    final channel = _channel;
    _channel = null;
    _connectedDevice = null;
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
    _cleanupChannel();
    await _stateController.close();
    await _dataController.close();
    await _scanController.close();
  }
}
