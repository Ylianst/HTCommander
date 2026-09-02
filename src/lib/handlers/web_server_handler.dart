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

import 'package:flutter/foundation.dart' show kIsWeb;

import '../aprs/aprs_packet.dart';
import '../models/aircraft.dart';
import '../models/station_info.dart';
import '../radio/pcm_player.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';
import '../services/web/web_server.dart';
import '../winlink/winlink_mail.dart';

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

  /// Latest airplane list polled by the host's AirplaneHandler, cached so it can
  /// be snapshotted to a browser on connect. Browsers cannot reach the (LAN)
  /// Dump1090 server, so they mirror the host's polling.
  List<Aircraft>? _lastAirplanes;

  /// Latest Winlink mail list seen on the broker, cached so it can be
  /// snapshotted to a browser on connect. Refreshed on demand via `MailGetAll`.
  List<WinLinkMail>? _lastMailList;

  /// Device IDs of the currently connected radios. The first entry is the radio
  /// bridged to WebSocket clients.
  final List<int> _connectedRadios = <int>[];

  /// Friendly names of the connected radios, keyed by device id.
  final Map<int, String> _radioNames = <int, String>{};

  /// The host's selected radio device id (device 1 `SelectedRadioDeviceId`), or
  /// -1. The bridged radio follows this selection when it is connected.
  int _selectedRadioDeviceId = -1;

  /// Browsers that opted in to receive the host's played audio, keyed by client
  /// id. Populated by `audioon` / cleared by `audiooff` / disconnect.
  final Map<int, WebSocketClient> _audioClients = <int, WebSocketClient>{};

  /// Initializes the handler: loads settings, subscribes to changes, and starts
  /// the server if enabled.
  void init() {
    _enabled = (_broker.getValue<int>(0, 'webServerEnabled', 0) ?? 0) == 1;
    _port = _broker.getValue<int>(0, 'webServerPort', 8080) ?? 8080;

    _refreshConnectedRadios();
    _selectedRadioDeviceId =
        _broker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;

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
    _broker.subscribe(
      deviceId: 1,
      name: 'SelectedRadioDeviceId',
      callback: _onSelectedRadioChanged,
    );
    // Cache the APRS packet list so it can be snapshotted to browsers on
    // connect (it is dispatched on demand via `RequestAprsPackets`).
    _broker.subscribe(
      deviceId: 1,
      name: 'AprsPacketList',
      callback: _onAprsPacketList,
    );
    // Airplanes (Dump1090) polled by the host: cache and push to browsers, which
    // cannot reach the LAN Dump1090 server themselves.
    _broker.subscribe(
      deviceId: 0,
      name: 'Airplanes',
      callback: _onAirplanes,
    );
    // Cache the Winlink mail list (dispatched on demand via `MailGetAll`) and
    // push a fresh snapshot to browsers whenever the host's mail changes.
    _broker.subscribe(
      deviceId: 0,
      name: 'MailList',
      callback: _onMailList,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MailsChanged',
      callback: _onMailsChanged,
    );
    // Relay Winlink transfer status / errors to browsers so the hosted mail tab
    // reflects the sync the host is running on their behalf.
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkStateMessage',
      callback: _onWinlinkStateMessage,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkError',
      callback: _onWinlinkError,
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

  /// The radio device bridged to WebSocket clients, or `-1` if none. Follows the
  /// host's selected radio when it is connected, otherwise the first connected
  /// radio.
  int get _targetRadioDeviceId {
    if (_selectedRadioDeviceId > 0 &&
        _connectedRadios.contains(_selectedRadioDeviceId)) {
      return _selectedRadioDeviceId;
    }
    return _connectedRadios.isNotEmpty ? _connectedRadios.first : -1;
  }

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
    _broadcastRadioList();
    if (_targetRadioDeviceId != previousTarget) {
      _repointBrowsers();
    }
  }

  /// The host's selected radio changed; re-point the bridge if needed and push
  /// the updated radio list / status to browsers.
  void _onSelectedRadioChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final previousTarget = _targetRadioDeviceId;
    _selectedRadioDeviceId = data is int ? data : -1;
    _broadcastRadioList();
    if (_targetRadioDeviceId != previousTarget) {
      _repointBrowsers();
    }
  }

  /// Re-points every browser at the (possibly new) bridged radio. A
  /// disconnect/reconnect cycle makes the client re-fetch the radio's device
  /// info, channels, settings and status.
  void _repointBrowsers() {
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    server.broadcastText('disconnected');
    server.broadcastText(_stateMessageFor(_currentRadioState));
  }

  void _refreshConnectedRadios() {
    _connectedRadios.clear();
    _radioNames.clear();
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (radios is List) {
      for (final item in radios) {
        if (item is! Map) continue;
        final deviceId = item['DeviceId'] ?? item['deviceId'];
        if (deviceId is int && deviceId > 0) {
          _connectedRadios.add(deviceId);
          final n = item['FriendlyName'] ?? item['friendlyName'];
          if (n is String && n.isNotEmpty) _radioNames[deviceId] = n;
        }
      }
    }
  }

  /// Broadcasts the host's radio list (ids + names + which one is bridged) so
  /// browsers can show the current radio name and offer a radio switcher.
  void _broadcastRadioList() {
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    server.broadcastText(_encodeRadioList());
  }

  String _encodeRadioList() {
    final radios = _connectedRadios
        .map(
          (id) => <String, Object?>{
            'deviceId': id,
            'name': _radioNames[id] ?? 'Radio $id',
          },
        )
        .toList(growable: false);
    return 'radiolist:${jsonEncode(<String, Object?>{'selected': _targetRadioDeviceId, 'radios': radios})}';
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
    // Send the host's radio list so the browser shows the current radio name
    // and can offer a radio switcher.
    client.sendText(_encodeRadioList());
    // Sync the host's device-0 settings so the web UI matches the desktop app.
    _sendSettingsTo(client);
    // Seed the browser's Comms/APRS tabs with the host's stored history.
    _sendHistoryTo(client);
    // Send the host's authoritative Winlink mail so the browser's mail tab
    // mirrors the desktop app rather than keeping its own (empty) store.
    _sendMailTo(client);
    // Send the host's latest airplanes so the browser's map shows them.
    _sendAirplanesTo(client);
  }

  void _onAprsPacketList(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is List) {
      _lastAprsPacketList = data.whereType<AprsPacket>().toList(growable: false);
    }
  }

  /// Caches the host's airplane list and broadcasts it to every connected
  /// browser as an `airplanes:` snapshot.
  void _onAirplanes(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! List) return;
    _lastAirplanes = data.whereType<Aircraft>().toList(growable: false);
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    server.broadcastText(_encodeAirplanes(_lastAirplanes!));
  }

  /// Sends the host's cached airplane snapshot to [client].
  void _sendAirplanesTo(WebSocketClient client) {
    final airplanes = _lastAirplanes;
    if (airplanes == null || airplanes.isEmpty) return;
    try {
      client.sendText(_encodeAirplanes(airplanes));
    } catch (ex) {
      _broker.logError('[WebServer] Failed to send airplanes: $ex');
    }
  }

  String _encodeAirplanes(List<Aircraft> airplanes) {
    final list = airplanes.map((a) => a.toJson()).toList(growable: false);
    return 'airplanes:${jsonEncode(list)}';
  }

  void _onMailList(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is List) {
      _lastMailList = data.whereType<WinLinkMail>().toList(growable: false);
    }
  }

  /// Broadcasts the host's Winlink mail snapshot to every connected browser
  /// whenever the host's mail store changes.
  void _onMailsChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    server.broadcastText(_encodeMailSnapshot());
  }

  /// Relays a Winlink transfer status message to browsers (empty clears it).
  void _onWinlinkStateMessage(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    final message = data is String ? data : '';
    server.broadcastText('winlinkstate:$message');
  }

  /// Relays a Winlink error message to browsers.
  void _onWinlinkError(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! String || data.isEmpty) return;
    final server = _server;
    if (server == null || server.clientCount == 0) return;
    server.broadcastText('winlinkerror:$data');
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
      // Software-modem controls must reconfigure the live modem, so dispatch the
      // command the host's SoftwareModem consumes (it persists the setting
      // itself) rather than writing the raw setting value.
      final modemCommand = _modemSettingCommands[name];
      if (modemCommand != null) {
        _broker.dispatch(
          deviceId: 0,
          name: modemCommand,
          data: value,
          store: false,
        );
        return;
      }
      _broker.dispatch(deviceId: 0, name: name, data: value, store: true);
    } catch (ex) {
      _broker.logError('[WebServer] Failed to apply client setting: $ex');
    }
  }

  /// Device-0 software-modem settings a browser can change, mapped to the
  /// command event the host's SoftwareModem consumes to apply them live.
  static const Map<String, String> _modemSettingCommands = <String, String>{
    'SoftwareModemMode': 'SetSoftwareModemMode',
    'SoftwareModemFec': 'SetSoftwareModemFec',
    'DartTxMode': 'SetDartTxMode',
    'AprsSoftwareModemMode': 'SetAprsSoftwareModemMode',
    'AprsSoftwareModemFec': 'SetAprsSoftwareModemFec',
  };

  /// Applies a radio-switch request from a browser: makes the requested radio
  /// the host's preferred (selected) radio, which re-points the bridge.
  void _applyClientSelectRadio(String idStr) {
    if (_disposed) return;
    final id = int.tryParse(idStr.trim());
    if (id == null || id <= 0 || !_connectedRadios.contains(id)) return;
    _broker.dispatch(
      deviceId: 1,
      name: 'SetPreferredRadio',
      data: id,
      store: false,
    );
  }

  /// Applies a mail operation pushed by a browser to the host's mail store. The
  /// store re-emits `MailsChanged`, which broadcasts the updated snapshot back
  /// to every browser.
  void _applyClientMailOp(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map) return;
      switch (data['op']) {
        case 'add':
        case 'update':
          final mail = data['mail'];
          if (mail is Map) {
            _broker.dispatch(
              deviceId: 0,
              name: data['op'] == 'add' ? 'MailAdd' : 'MailUpdate',
              data: WinLinkMail.fromJson(mail.cast<String, dynamic>()),
              store: false,
            );
          }
          break;
        case 'delete':
          final mid = data['mid'];
          if (mid is String && mid.isNotEmpty) {
            _broker.dispatch(
              deviceId: 0,
              name: 'MailDelete',
              data: mid,
              store: false,
            );
          }
          break;
        case 'move':
          final mid = data['mid'];
          final mailbox = data['mailbox'];
          if (mid is String && mailbox is String) {
            _broker.dispatch(
              deviceId: 0,
              name: 'MailMove',
              data: <String, Object?>{'MID': mid, 'Mailbox': mailbox},
              store: false,
            );
          }
          break;
      }
    } catch (ex) {
      _broker.logError('[WebServer] Failed to apply client mail op: $ex');
    }
  }

  /// Applies a Winlink sync request pushed by a browser. Internet syncs are
  /// forwarded verbatim; radio syncs are re-targeted at the host's own bridged
  /// radio (the browser's radio id is meaningless here).
  void _applyClientWinlinkSync(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map) return;
      final server = data['Server'];
      if (server is String && server.isNotEmpty) {
        _broker.dispatch(
          deviceId: 1,
          name: 'WinlinkSync',
          data: <String, Object?>{
            'Server': server,
            'Port': (data['Port'] as num?)?.toInt() ?? 8772,
            'UseTls': data['UseTls'] is bool ? data['UseTls'] : true,
          },
          store: false,
        );
        return;
      }
      final station = data['Station'];
      if (station is Map) {
        final target = _targetRadioDeviceId;
        if (target < 0) return;
        _broker.dispatch(
          deviceId: 1,
          name: 'WinlinkSync',
          data: <String, Object?>{
            'RadioId': target,
            'Station': StationInfo.fromJson(station.cast<String, dynamic>()),
          },
          store: false,
        );
      }
    } catch (ex) {
      _broker.logError('[WebServer] Failed to apply client winlink sync: $ex');
    }
  }

  /// Sends the host's current Winlink mail snapshot to [client].
  void _sendMailTo(WebSocketClient client) {
    try {
      client.sendText(_encodeMailSnapshot());
    } catch (ex) {
      _broker.logError('[WebServer] Failed to send mail: $ex');
    }
  }

  /// Refreshes the cached mail list (a synchronous `MailGetAll` dispatch updates
  /// [_lastMailList]) and encodes it as a `mail:` snapshot message.
  String _encodeMailSnapshot() {
    _broker.dispatch(
      deviceId: 0,
      name: 'MailGetAll',
      data: null,
      store: false,
    );
    final mails = _lastMailList ?? const <WinLinkMail>[];
    final list = mails.map((m) => m.toJson()).toList(growable: false);
    return 'mail:${jsonEncode(list)}';
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
    if (message.startsWith('selectradio:')) {
      _applyClientSelectRadio(message.substring('selectradio:'.length));
      return;
    }
    if (message == 'audioon') {
      _audioClients[client.id] = client;
      return;
    }
    if (message == 'audiooff') {
      _audioClients.remove(client.id);
      return;
    }
    if (message.startsWith('mailop:')) {
      _applyClientMailOp(message.substring('mailop:'.length));
      return;
    }
    if (message.startsWith('winlinksync:')) {
      _applyClientWinlinkSync(message.substring('winlinksync:'.length));
      return;
    }
    if (message.startsWith('winlinkdisconnect:')) {
      _broker.dispatch(
        deviceId: 1,
        name: 'WinlinkDisconnect',
        data: true,
        store: false,
      );
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
    server.onClientDisconnected = _onClientDisconnected;
    server.onTextMessage = _onTextMessage;
    server.onBinaryMessage = _onBinaryMessage;
    _server = server;
    server.start();
    // Mirror all host PCM playback (radio, transmit, EchoLink, AllStarLink) to
    // opted-in browsers. Desktop only; the web build never plays local audio.
    if (!kIsWeb) PcmPlayer.playbackTap = _onHostPcm;
  }

  void _stopServer() {
    final server = _server;
    if (server == null) return;
    if (PcmPlayer.playbackTap == _onHostPcm) PcmPlayer.playbackTap = null;
    _audioClients.clear();
    _server = null;
    server.dispose();
  }

  void _onClientDisconnected(WebSocketClient client) {
    if (_disposed) return;
    _audioClients.remove(client.id);
  }

  /// Mirrors a buffer of host playback audio to every opted-in browser as a
  /// tagged binary frame (`[magic, channels, rateLo, rateHi]` + PCM).
  void _onHostPcm(Int16List pcm, int sampleRate, int channels) {
    if (_disposed || _audioClients.isEmpty) return;
    final pcmBytes = pcm.buffer.asUint8List(
      pcm.offsetInBytes,
      pcm.lengthInBytes,
    );
    final msg = Uint8List(4 + pcmBytes.length);
    msg[0] = HostBridge.audioFrameMagic;
    msg[1] = channels & 0xFF;
    msg[2] = sampleRate & 0xFF;
    msg[3] = (sampleRate >> 8) & 0xFF;
    msg.setRange(4, msg.length, pcmBytes);
    for (final client in _audioClients.values) {
      client.sendBinary(msg);
    }
  }

  /// Stops the server and releases all resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopServer();
    _broker.dispose();
  }
}
