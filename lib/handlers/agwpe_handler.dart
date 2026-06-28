/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AgwpeSocketServer` command processing
(`ProcessAgwCommand`, `BroadcastFrame`, and the session helpers). This handler
owns the [AgwpeServer] transport and implements the AGWPE protocol on top of the
Flutter radio stack:

  * It starts / stops the TCP server based on the `agwpeServerEnabled` /
    `agwpeServerPort` settings (DataBroker device 0).
  * It broadcasts received UI frames to monitoring clients (the `U` data kind).
  * It registers callsigns (`X` / `x`), toggles monitoring (`m`), answers port
    info (`G`), sends UNPROTO frames (`M`), and bridges connected-mode sessions
    (`C` / `d` / `D`) to an [AX25Session].

The AGWPE feature is desktop-only; on the web the [AgwpeServer] facade resolves
to an inert stub.
*/

import 'dart:typed_data';

import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/ax25_session.dart';
import '../radio/radio.dart' show TransmitDataFrameData;
import '../radio/tnc_data_fragment.dart';
import '../services/agwpe/agwpe_frame.dart';
import '../services/agwpe/agwpe_server.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// Per-client AGWPE protocol state.
class _AgwpeClientState {
  /// Callsigns this client has registered (via the `X` command).
  final Set<String> registeredCallsigns = <String>{};

  /// Connected-mode session bridged to the radio, if a `C` connect is active.
  AX25Session? session;

  /// The local (our) callsign for the active session (AGWPE `CallFrom`).
  String? sessionFrom;

  /// The remote callsign for the active session (AGWPE `CallTo`).
  String? sessionTo;
}

/// Manages the AGWPE TCP server and bridges it to the radio.
class AgwpeHandler {
  AgwpeHandler() : _broker = DataBrokerClient();

  final DataBrokerClient _broker;

  AgwpeServer? _server;
  bool _enabled = false;
  int _port = 8000;

  /// Device IDs of the currently connected radios. The first entry is used as
  /// the target radio for connected sessions and UNPROTO transmissions.
  final List<int> _connectedRadios = <int>[];

  /// Per-client protocol state keyed by the server's client id.
  final Map<int, _AgwpeClientState> _clients = <int, _AgwpeClientState>{};

  bool _disposed = false;

  /// Initializes the handler: loads settings, subscribes to changes, and starts
  /// the server if enabled.
  void init() {
    _enabled =
        (_broker.getValue<int>(0, 'agwpeServerEnabled', 0) ?? 0) == 1;
    _port = _broker.getValue<int>(0, 'agwpeServerPort', 8000) ?? 8000;

    _refreshConnectedRadios();

    _broker.subscribeMultiple(
      deviceId: 0,
      names: <String>['agwpeServerEnabled', 'agwpeServerPort'],
      callback: _onSettingChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );

    if (_enabled) _startServer();
  }

  /// The radio device used for sessions / transmissions, or `-1` if none.
  int get _targetRadioDeviceId =>
      _connectedRadios.isNotEmpty ? _connectedRadios.first : -1;

  // ---------------------------------------------------------------------------
  // Settings / radio tracking
  // ---------------------------------------------------------------------------

  void _onSettingChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (name == 'agwpeServerEnabled') {
      final enabled = (data is int ? data : 0) == 1;
      if (enabled == _enabled) return;
      _enabled = enabled;
      if (_enabled) {
        _startServer();
      } else {
        _stopServer();
      }
    } else if (name == 'agwpeServerPort') {
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
    _refreshConnectedRadios();
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

  // ---------------------------------------------------------------------------
  // Server lifecycle
  // ---------------------------------------------------------------------------

  void _startServer() {
    if (_server != null) return;
    final server = AgwpeServer(_port);
    server.onClientConnected = _onClientConnected;
    server.onClientDisconnected = _onClientDisconnected;
    server.onFrameReceived = _onFrameReceived;
    _server = server;
    server.start();
  }

  void _stopServer() {
    final server = _server;
    if (server == null) return;
    _server = null;
    // Tear down any active sessions first.
    for (final state in _clients.values) {
      state.session?.dispose();
      state.session = null;
    }
    _clients.clear();
    server.dispose();
  }

  void _onClientConnected(int clientId) {
    _clients[clientId] = _AgwpeClientState();
  }

  void _onClientDisconnected(int clientId) {
    final state = _clients.remove(clientId);
    if (state == null) return;
    state.session?.dispose();
    state.session = null;
  }

  // ---------------------------------------------------------------------------
  // Incoming radio frames -> monitoring broadcast
  // ---------------------------------------------------------------------------

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final server = _server;
    if (server == null || data is! TncDataFragment) return;

    final packet = AX25Packet.decode(data);
    if (packet == null) return;
    if (packet.addresses.length < 2) return;
    if (packet.type != FrameType.uFrameUi) return;

    final src = packet.addresses[1];
    final dest = packet.addresses[0];
    final dataLen = packet.data?.length ?? 0;
    final now = DateTime.now();
    var str =
        '1:Fm ${src.callSignWithId} To ${dest.callSignWithId} '
        '<UI pid=${packet.pid} Len=$dataLen >[${_timestamp(now)}]\r'
        '${packet.dataStr ?? ''}';
    if (!str.endsWith('\r') && !str.endsWith('\n')) str += '\r';

    final frame = AgwpeFrame(
      port: 0,
      dataKind: AgwpeDataKind.monitorUnproto,
      callFrom: src.callSignWithId,
      callTo: dest.callSignWithId,
      data: _asciiBytes(str),
    );
    server.broadcastMonitorFrame(frame);
  }

  // ---------------------------------------------------------------------------
  // Incoming AGWPE commands (ported from C# ProcessAgwCommand)
  // ---------------------------------------------------------------------------

  void _onFrameReceived(int clientId, AgwpeFrame frame) {
    if (_disposed) return;
    final server = _server;
    final state = _clients[clientId];
    if (server == null || state == null) return;

    switch (frame.dataKind) {
      case AgwpeDataKind.getPortInfo: // 'G'
        _handleGetPortInfo(server, clientId, frame);
        break;
      case AgwpeDataKind.registerCallsign: // 'X'
        _handleRegister(server, clientId, state, frame);
        break;
      case AgwpeDataKind.unregisterCallsign: // 'x'
        _handleUnregister(state, frame);
        break;
      case AgwpeDataKind.monitorToggle: // 'm'
        _handleMonitorToggle(server, clientId);
        break;
      case AgwpeDataKind.sendUnproto: // 'M'
        _handleSendUnproto(server, clientId, frame);
        break;
      case AgwpeDataKind.connectedData: // 'D'
        _handleConnectedData(state, frame);
        break;
      case AgwpeDataKind.connect: // 'C'
        _handleConnect(server, clientId, state, frame);
        break;
      case AgwpeDataKind.disconnect: // 'd'
        _handleDisconnect(server, clientId, state, frame);
        break;
      default:
        _broker.logInfo(
          "[AgwpeHandler] Unknown data kind '${frame.dataKindChar}' "
          '(0x${frame.dataKind.toRadixString(16)})',
        );
        break;
    }
  }

  void _handleGetPortInfo(AgwpeServer server, int clientId, AgwpeFrame frame) {
    final info = _asciiBytes('1;Port1 Handi-Talky Commander;');
    server.sendFrameToClient(
      clientId,
      AgwpeFrame(
        port: frame.port,
        dataKind: AgwpeDataKind.getPortInfo,
        data: info,
      ),
    );
  }

  void _handleRegister(
    AgwpeServer server,
    int clientId,
    _AgwpeClientState state,
    AgwpeFrame frame,
  ) {
    var success = false;
    final callsign = frame.callFrom.trim();
    if (callsign.isNotEmpty && !_isCallsignRegistered(callsign)) {
      state.registeredCallsigns.add(callsign);
      _broker.logInfo("[AgwpeHandler] Registered callsign '$callsign'");
      success = true;
    }
    server.sendFrameToClient(
      clientId,
      AgwpeFrame(
        port: frame.port,
        dataKind: AgwpeDataKind.registerCallsign,
        callFrom: frame.callFrom,
        data: Uint8List.fromList(<int>[success ? 1 : 0]),
      ),
    );
  }

  void _handleUnregister(_AgwpeClientState state, AgwpeFrame frame) {
    final callsign = frame.callFrom.trim();
    if (callsign.isNotEmpty && state.registeredCallsigns.remove(callsign)) {
      _broker.logInfo("[AgwpeHandler] Unregistered callsign '$callsign'");
    }
  }

  void _handleMonitorToggle(AgwpeServer server, int clientId) {
    final state = _clients[clientId];
    if (state == null) return;
    final enabled = !_monitoring.contains(clientId);
    if (enabled) {
      _monitoring.add(clientId);
    } else {
      _monitoring.remove(clientId);
    }
    server.setClientMonitoring(clientId, enabled);
    _broker.logInfo(
      enabled
          ? '[AgwpeHandler] Enabled monitoring for client $clientId'
          : '[AgwpeHandler] Disabled monitoring for client $clientId',
    );
  }

  void _handleSendUnproto(AgwpeServer server, int clientId, AgwpeFrame frame) {
    final radioDeviceId = _targetRadioDeviceId;
    if (radioDeviceId < 0) return;
    final dest = AX25Address.parse(frame.callTo);
    final src = AX25Address.parse(frame.callFrom);
    if (dest == null || src == null) return;

    final packet = AX25Packet.uiBytes(<AX25Address>[dest, src], frame.data);
    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        packet: packet,
        channelId: -1,
        regionId: -1,
      ),
      store: false,
    );

    // Echo the UNPROTO back to the client as a 'T' response.
    final now = DateTime.now();
    var str =
        '${frame.port + 1}:Fm ${src.callSignWithId} To ${dest.callSignWithId} '
        '<UI pid=${packet.pid} Len=${frame.data.length} >[${_timestamp(now)}]\r'
        '${_asciiString(frame.data)}';
    if (!str.endsWith('\r') && !str.endsWith('\n')) str += '\r';

    server.sendFrameToClient(
      clientId,
      AgwpeFrame(
        port: frame.port,
        dataKind: AgwpeDataKind.unprotoResponse,
        callFrom: dest.callSignWithId,
        callTo: src.callSignWithId,
        data: _asciiBytes(str),
      ),
    );
  }

  void _handleConnectedData(_AgwpeClientState state, AgwpeFrame frame) {
    final session = state.session;
    if (session == null) return;
    if (session.currentState != AX25ConnectionState.connected) return;
    if (frame.data.isEmpty) return;
    session.send(frame.data);
  }

  void _handleConnect(
    AgwpeServer server,
    int clientId,
    _AgwpeClientState state,
    AgwpeFrame frame,
  ) {
    final radioDeviceId = _targetRadioDeviceId;
    final dest = AX25Address.parse(frame.callTo);
    final src = AX25Address.parse(frame.callFrom);

    // Reject if the radio is unavailable, the addresses are invalid, or a
    // session is already active for this client.
    if (radioDeviceId < 0 ||
        dest == null ||
        src == null ||
        state.session != null) {
      _broker.logInfo('[AgwpeHandler] Rejecting connect request from $clientId');
      server.sendFrameToClient(
        clientId,
        AgwpeFrame(
          port: frame.port,
          dataKind: AgwpeDataKind.disconnect,
          callFrom: frame.callTo,
          callTo: frame.callFrom,
        ),
      );
      return;
    }

    state.sessionFrom = frame.callFrom;
    state.sessionTo = frame.callTo;

    final session = AX25Session(radioDeviceId);
    session.onStateChanged = (sender, sessionState) =>
        _onSessionStateChanged(clientId, sessionState);
    session.onDataReceived = (sender, data) =>
        _onSessionDataReceived(clientId, data);
    session.onUiDataReceived = (sender, data) =>
        _onSessionDataReceived(clientId, data);
    state.session = session;

    _broker.logInfo(
      '[AgwpeHandler] Client $clientId connecting '
      '${frame.callFrom} -> ${frame.callTo} on radio $radioDeviceId',
    );
    session.connect(<AX25Address>[dest, src]);
  }

  void _handleDisconnect(
    AgwpeServer server,
    int clientId,
    _AgwpeClientState state,
    AgwpeFrame frame,
  ) {
    state.session?.disconnect();
    server.sendFrameToClient(
      clientId,
      AgwpeFrame(
        port: frame.port,
        dataKind: AgwpeDataKind.disconnect,
        callFrom: frame.callTo,
        callTo: frame.callFrom,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Session -> client bridging
  // ---------------------------------------------------------------------------

  void _onSessionStateChanged(int clientId, AX25ConnectionState sessionState) {
    final server = _server;
    final state = _clients[clientId];
    if (server == null || state == null) return;

    if (sessionState == AX25ConnectionState.connected) {
      server.sendFrameToClient(
        clientId,
        AgwpeFrame(
          port: 0,
          dataKind: AgwpeDataKind.connect,
          callFrom: state.sessionTo ?? '',
          callTo: state.sessionFrom ?? '',
          data: _asciiBytes('*** CONNECTED With ${state.sessionTo ?? ''}'),
        ),
      );
    } else if (sessionState == AX25ConnectionState.disconnected) {
      server.sendFrameToClient(
        clientId,
        AgwpeFrame(
          port: 0,
          dataKind: AgwpeDataKind.disconnect,
          callFrom: state.sessionTo ?? '',
          callTo: state.sessionFrom ?? '',
        ),
      );
      state.session?.dispose();
      state.session = null;
    }
  }

  void _onSessionDataReceived(int clientId, Uint8List data) {
    final server = _server;
    final state = _clients[clientId];
    if (server == null || state == null || data.isEmpty) return;
    server.sendFrameToClient(
      clientId,
      AgwpeFrame(
        port: 0,
        dataKind: AgwpeDataKind.connectedData,
        callFrom: state.sessionTo ?? '',
        callTo: state.sessionFrom ?? '',
        data: Uint8List.fromList(data),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Client ids that currently have monitoring enabled.
  final Set<int> _monitoring = <int>{};

  bool _isCallsignRegistered(String callsign) {
    for (final state in _clients.values) {
      if (state.registeredCallsigns.contains(callsign)) return true;
    }
    return false;
  }

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Encodes [text] as ASCII bytes, replacing any non-ASCII code unit with '?'.
  static Uint8List _asciiBytes(String text) {
    final out = Uint8List(text.length);
    for (int i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      out[i] = c < 0x80 ? c : 0x3F;
    }
    return out;
  }

  /// Decodes [bytes] as an ASCII/Latin-1 string for echoing in monitor text.
  static String _asciiString(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.writeCharCode(b);
    }
    return sb.toString();
  }

  /// Stops the server and releases all resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopServer();
    _broker.dispose();
  }
}
