/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// aprsis_manager.dart - Wires the internet-only APRS-IS client (device 201)
// into the running application.
//
// APRS-IS is a full IGate: packets heard on RF are gated up to the internet
// (with a ,qAR,IGATECALL construct), and text messages addressed to stations
// heard locally on RF are gated down. Received internet packets are flagged as
// `fromAprsIs` and re-dispatched as `AprsFrame` events so the APRS and Map tabs
// can display them - and, crucially, filter them out - without mixing them into
// the RF packet store (which only persists `UniqueDataFrame` events).
//
// Like EchoLink, APRS-IS is deliberately NOT a physical radio: it is never
// added to device 1's `ConnectedRadios` aggregate and never participates in the
// radio lock mechanism. No-op on the web (dart:io sockets are unavailable).
//

import 'dart:async';
import 'dart:math' as math;

import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_util.dart';
import '../gps/gps_data.dart';
import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/radio.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'aprsis_client.dart';
import 'aprsis_network_io.dart';
import 'tnc2_codec.dart';

/// Owns the [AprsIsClient] and bridges it to the app's Data Broker. Registered
/// as a Data Broker handler in `main()` on platforms with a dart:io socket
/// stack (desktop / mobile).
class AprsIsManager {
  AprsIsManager();

  /// Software name/version reported in the APRS-IS login line.
  static const String _softwareName = 'HTCommander';

  /// Default APRS-IS server + port when the user has not configured one.
  static const String _defaultServer = 'rotate.aprs2.net';
  static const int _defaultPort = 14580;

  /// A station is considered "locally heard" (and therefore eligible for
  /// message down-gating) for this long after its last RF packet.
  static const Duration _heardWindow = Duration(hours: 1);

  /// Reconnect backoff bounds.
  static const Duration _minRetry = Duration(seconds: 5);
  static const Duration _maxRetry = Duration(minutes: 2);

  final DataBrokerClient _broker = DataBrokerClient();

  AprsIsClient? _client;
  bool _initialized = false;
  bool _opened = false;
  bool _reconciling = false;

  /// The connection parameters (callsign, server, port) of the currently open
  /// session. Used to avoid tearing down and re-establishing an identical
  /// connection when settings are re-dispatched without any relevant change.
  String? _connectedCallsign;
  String? _connectedServer;
  int? _connectedPort;

  /// Incremented on every (re)connect so a stale `network.done` handler for a
  /// previous session does not schedule a reconnect for the current one.
  int _generation = 0;

  Timer? _retryTimer;
  Duration _retryDelay = _minRetry;

  /// Application version, read once at init for the login line.
  String _appVersion = '';

  /// Callsigns heard on RF recently, mapped to the last time they were heard.
  final Map<String, DateTime> _heardStations = {};

  /// Subscribes to settings + RF frames and opens the client when enabled.
  void init() {
    if (_initialized) return;
    _initialized = true;

    _appVersion = _broker.getValue<String>(0, 'AppVersion', '') ?? '';

    // React to any setting that affects the connection or gating.
    _broker.subscribeMultiple(
      deviceId: 0,
      names: const [
        'CallSign',
        'StationId',
        'AprsIsEnabled',
        'AprsIsServer',
        'AprsIsPort',
        'AprsIsGateToRf',
      ],
      callback: (_, _, _) => unawaited(_reconcile()),
    );

    // The range setting changes the server-side filter but not the connection;
    // apply it live without reconnecting.
    _broker.subscribe(
      deviceId: 0,
      name: 'AprsIsRangeKm',
      callback: (_, _, _) => _updateLiveFilter(),
    );

    // Track the last confirmed GPS position (radio GPS or serial GPS) and keep
    // it on device 0 so it can center the APRS-IS range filter. Active whether
    // or not APRS-IS is connected, so a position is ready when the user enables
    // it.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Position',
      callback: _onRadioPosition,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'GpsData',
      callback: _onSerialGps,
    );

    // RF frames (from the AprsHandler on device 1) feed the heard list and the
    // RF -> internet up-gate. Internet frames we re-dispatch here carry
    // `fromAprsIs` and are ignored by the gating logic.
    _broker.subscribe(
      deviceId: 1,
      name: 'AprsFrame',
      callback: _onAprsFrame,
    );

    unawaited(_reconcile());
  }

  bool _readEnabled() =>
      (_broker.getValue<int>(0, 'AprsIsEnabled', 0) ?? 0) == 1;

  bool _readGateToRf() =>
      (_broker.getValue<int>(0, 'AprsIsGateToRf', 0) ?? 0) == 1;

  String _readCallsignWithId() {
    final callsign = (_broker.getValue<String>(0, 'CallSign', '') ?? '')
        .trim()
        .toUpperCase();
    if (callsign.isEmpty) return '';
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    return stationId > 0 ? '$callsign-$stationId' : callsign;
  }

  String _readServer() {
    final server = (_broker.getValue<String>(0, 'AprsIsServer', '') ?? '')
        .trim();
    return server.isEmpty ? _defaultServer : server;
  }

  int _readPort() {
    final port = _broker.getValue<int>(0, 'AprsIsPort', 0) ?? 0;
    return (port > 0 && port < 65536) ? port : _defaultPort;
  }

  String _readFilter() {
    final km = _broker.getValue<int>(0, 'AprsIsRangeKm', 0) ?? 0;
    if (km <= 0) return '';
    final valid =
        (_broker.getValue<int>(0, 'AprsIsPositionValid', 0) ?? 0) == 1;
    if (!valid) return '';
    final lat = _broker.getValue<double>(0, 'AprsIsLat', 0) ?? 0;
    final lon = _broker.getValue<double>(0, 'AprsIsLon', 0) ?? 0;
    return 'r/${lat.toStringAsFixed(4)}/${lon.toStringAsFixed(4)}/$km';
  }

  /// Enables or disables APRS-IS to match the current settings. Enabled only
  /// when the feature is turned on and a callsign is configured; otherwise any
  /// live client is closed.
  Future<void> _reconcile() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      final callsign = _readCallsignWithId();
      final shouldEnable = _readEnabled() && callsign.isNotEmpty;

      if (!shouldEnable) {
        if (_client != null || _opened) {
          await _closeClient();
          _broker.logInfo('[APRS-IS] Disabled');
        }
        _publishAvailable(false);
        return;
      }

      // Already connected with the same connection parameters: nothing to do.
      // This avoids resetting a healthy connection when settings are
      // re-dispatched without any change that affects it (e.g. pressing OK in
      // the settings dialog). The range filter is applied live elsewhere and
      // gating settings are read on demand, so neither requires a reconnect.
      final server = _readServer();
      final port = _readPort();
      if (_opened &&
          callsign == _connectedCallsign &&
          server == _connectedServer &&
          port == _connectedPort) {
        _publishAvailable(true);
        return;
      }

      // Connection parameters changed while enabled -> reconnect so the new
      // server/port/callsign take effect.
      if (_opened) {
        await _closeClient();
      }

      await _openClient(callsign);
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _openClient(String callsign) async {
    _retryTimer?.cancel();
    final passcode = AprsUtil.aprsValidationCode(callsign);
    final gen = ++_generation;

    final client = AprsIsClient(
      callsign: callsign,
      passcode: passcode,
      softwareName: _softwareName,
      softwareVersion: _appVersion.isEmpty ? '0' : _appVersion,
      filter: _readFilter(),
      network: DartIoAprsIsNetwork(),
    )
      ..onPacketLine = _onServerPacketLine
      ..onLogin = _onLogin
      ..onDiagnostic = _broker.logInfo;

    _client = client;
    _publishState('Connecting');
    _publishAvailable(true);

    final server = _readServer();
    final port = _readPort();
    try {
      await client.open(server, port);
      _opened = true;
      _connectedCallsign = callsign;
      _connectedServer = server;
      _connectedPort = port;
      // Schedule a reconnect if this session drops while still enabled.
      unawaited(client.network.done.then((_) => _onSessionClosed(gen)));
    } catch (e) {
      _broker.logError('[APRS-IS] Connection to $server:$port failed: $e');
      _client = null;
      _opened = false;
      _connectedCallsign = null;
      _connectedServer = null;
      _connectedPort = null;
      _publishState('Disconnected');
      _scheduleReconnect(gen);
    }
  }

  Future<void> _closeClient() async {
    _retryTimer?.cancel();
    _generation++; // Invalidate any pending reconnect for the old session.
    final client = _client;
    _client = null;
    _opened = false;
    _connectedCallsign = null;
    _connectedServer = null;
    _connectedPort = null;
    _publishState('Disconnected');
    if (client != null) {
      try {
        await client.close();
      } catch (_) {
        // Ignore errors while closing.
      }
    }
  }

  void _onSessionClosed(int gen) {
    if (gen != _generation) return; // Superseded by a newer session.
    if (!_opened) return;
    _broker.logInfo('[APRS-IS] Connection closed');
    _opened = false;
    _connectedCallsign = null;
    _connectedServer = null;
    _connectedPort = null;
    _client = null;
    _publishState('Disconnected');
    _scheduleReconnect(gen);
  }

  void _scheduleReconnect(int gen) {
    if (!_readEnabled()) return;
    if (_readCallsignWithId().isEmpty) return;
    _retryTimer?.cancel();
    final delay = _retryDelay;
    _retryDelay = Duration(
      seconds: (_retryDelay.inSeconds * 2).clamp(
        _minRetry.inSeconds,
        _maxRetry.inSeconds,
      ),
    );
    _broker.logInfo('[APRS-IS] Reconnecting in ${delay.inSeconds}s');
    _retryTimer = Timer(delay, () {
      if (gen != _generation) return;
      unawaited(_reconcile());
    });
  }

  void _onLogin(bool verified) {
    _retryDelay = _minRetry; // Reset backoff on a successful login.
    _publishState(verified ? 'Connected (verified)' : 'Connected (read-only)');
    _broker.dispatch(
      deviceId: aprsIsDeviceId,
      name: 'AprsIsVerified',
      data: verified,
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Internet -> app (received packets) + internet -> RF down-gate
  // ---------------------------------------------------------------------------

  void _onServerPacketLine(String tnc2Line) {
    final ax25 = Tnc2Codec.decode(tnc2Line);
    if (ax25 == null) return;
    final aprs = AprsPacket.parse(ax25);
    if (aprs == null) return;
    aprs.fromAprsIs = true;

    // Surface to the APRS + Map tabs. Dispatched on device 1 (where both tabs
    // listen) but NOT as a UniqueDataFrame, so the RF packet store never
    // persists it and the two sources stay unmixed.
    _broker.dispatch(
      deviceId: 1,
      name: 'AprsFrame',
      data: AprsFrameEventArgs(aprs, ax25, null),
      store: false,
    );

    _maybeGateToRf(aprs);
  }

  void _maybeGateToRf(AprsPacket aprs) {
    if (!_readGateToRf()) return;
    _pruneHeard();
    if (!AprsIsClient.shouldGateToRf(aprs, _heardStations.keys.toSet())) {
      return;
    }
    final packet = aprs.packet;
    if (packet == null || packet.addresses.length < 2) return;

    final radioDeviceId = _firstRadioWithAprsChannel();
    if (radioDeviceId == null) return;
    final aprsChannelId = _aprsChannelId(radioDeviceId);
    if (aprsChannelId < 0) return;

    // Transmit the message on RF with the original source callsign and a
    // minimal WIDE1-1 path, per IGate convention.
    final src = packet.addresses[1];
    final dest = AX25Address.parse('APRS');
    final wide = AX25Address.parse('WIDE1-1');
    if (dest == null || wide == null) return;

    final txPacket = AX25Packet(
      addresses: [dest, src, wide],
      dataStr: packet.dataStr,
      type: FrameType.uFrameUi,
      command: true,
      time: DateTime.now(),
    );
    txPacket.pid = 240;
    txPacket.incoming = false;
    txPacket.sent = false;
    txPacket.channelId = aprsChannelId;
    txPacket.channelName = 'APRS';

    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        packet: txPacket,
        channelId: aprsChannelId,
        regionId: -1,
      ),
      store: false,
    );
    _broker.logInfo(
      '[APRS-IS] Gated message to RF for ${aprs.messageData.addressee}',
    );
  }

  // ---------------------------------------------------------------------------
  // RF -> internet up-gate + heard-list maintenance
  // ---------------------------------------------------------------------------

  void _onAprsFrame(int deviceId, String name, Object? data) {
    if (data is! AprsFrameEventArgs) return;
    final aprs = data.aprsPacket;
    // Ignore the internet packets we ourselves re-dispatched.
    if (aprs.fromAprsIs) return;

    _recordHeard(aprs);

    final client = _client;
    if (client == null) return;
    if (client.state != AprsIsConnectionState.connected) return;
    if (!client.canTransmit || !client.isVerified) return;
    if (!AprsIsClient.shouldGateToInternet(aprs)) return;

    final igateCall = _readCallsignWithId();
    if (igateCall.isEmpty) return;
    final line = AprsIsClient.buildGateUpLine(aprs, igateCall);
    if (line == null) return;
    client.sendPacketLine(line);
  }

  void _recordHeard(AprsPacket aprs) {
    final packet = aprs.packet;
    if (packet == null || packet.addresses.length < 2) return;
    final call = packet.addresses[1].callSignWithId.toUpperCase();
    if (call.isEmpty) return;
    _heardStations[call] = DateTime.now();
    // Also index by base callsign so a message to "CALL" (no SSID) matches a
    // station heard as "CALL-7".
    final base = packet.addresses[1].address.toUpperCase();
    if (base.isNotEmpty) _heardStations[base] = DateTime.now();
  }

  void _pruneHeard() {
    final cutoff = DateTime.now().subtract(_heardWindow);
    _heardStations.removeWhere((_, time) => time.isBefore(cutoff));
  }

  // ---------------------------------------------------------------------------
  // GPS position tracking (centers the APRS-IS range filter)
  // ---------------------------------------------------------------------------

  /// A stored position is only replaced once the station moves at least this
  /// far, so GPS jitter does not churn persisted settings or re-send filters.
  static const double _minMoveKm = 0.1;

  void _onRadioPosition(int deviceId, String name, Object? data) {
    if (deviceId <= 0) return; // Ignore device 0 (settings) and pseudo-radios.
    RadioPosition? pos;
    if (data is RadioPosition) {
      pos = data;
    } else if (data is Map) {
      pos = RadioPosition.fromJson(Map<String, dynamic>.from(data));
    }
    if (pos == null) return;
    final hasFix = pos.locked || pos.latitude != 0 || pos.longitude != 0;
    if (!hasFix) return;
    if (pos.latitude == 0 && pos.longitude == 0) return;
    _onGpsFix(pos.latitude, pos.longitude);
  }

  void _onSerialGps(int deviceId, String name, Object? data) {
    GpsData? gps;
    if (data is GpsData) {
      gps = data;
    } else if (data is Map) {
      gps = GpsData.fromJson(Map<String, dynamic>.from(data));
    }
    if (gps == null || !gps.isFixed) return;
    if (gps.latitude == 0 && gps.longitude == 0) return;
    _onGpsFix(gps.latitude, gps.longitude);
  }

  /// Records a confirmed GPS fix as the APRS-IS filter center on device 0 and
  /// updates the live server filter if the station has moved appreciably.
  void _onGpsFix(double lat, double lon) {
    final valid =
        (_broker.getValue<int>(0, 'AprsIsPositionValid', 0) ?? 0) == 1;
    if (valid) {
      final oldLat = _broker.getValue<double>(0, 'AprsIsLat', 0) ?? 0;
      final oldLon = _broker.getValue<double>(0, 'AprsIsLon', 0) ?? 0;
      if (_distanceKm(oldLat, oldLon, lat, lon) < _minMoveKm) return;
    }
    _broker.dispatch(deviceId: 0, name: 'AprsIsLat', data: lat, store: true);
    _broker.dispatch(deviceId: 0, name: 'AprsIsLon', data: lon, store: true);
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsIsPositionValid',
      data: 1,
      store: true,
    );
    _updateLiveFilter();
  }

  /// Applies the current range filter to a live connection without reconnecting.
  void _updateLiveFilter() {
    final client = _client;
    if (client == null) return;
    if (client.state != AprsIsConnectionState.connected) return;
    client.sendFilterCommand(_readFilter());
  }

  /// Great-circle distance in km (equirectangular approximation, accurate at
  /// the sub-100 km scale used here).
  static double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthR = 6371.0;
    const d2r = math.pi / 180.0;
    final dLat = (lat2 - lat1) * d2r;
    final dLon = (lon2 - lon1) * d2r;
    final x = dLon * math.cos(((lat1 + lat2) / 2) * d2r);
    return earthR * math.sqrt(dLat * dLat + x * x);
  }

  // ---------------------------------------------------------------------------
  // Radio / channel helpers (for down-gating)
  // ---------------------------------------------------------------------------

  int? _firstRadioWithAprsChannel() {
    final raw = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (raw is! List) return null;
    for (final item in raw) {
      if (item is Map) {
        final id = item['DeviceId'];
        if (id is int && _aprsChannelId(id) >= 0) return id;
      }
    }
    return null;
  }

  int _aprsChannelId(int radioDeviceId) {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      radioDeviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return -1;
    for (final channel in channels) {
      if (channel.name == 'APRS') return channel.channelId;
    }
    return -1;
  }

  // ---------------------------------------------------------------------------
  // Status publishing
  // ---------------------------------------------------------------------------

  void _publishAvailable(bool available) {
    _broker.dispatch(
      deviceId: aprsIsDeviceId,
      name: 'AprsIsAvailable',
      data: available,
      store: false,
    );
  }

  void _publishState(String label) {
    _broker.dispatch(
      deviceId: aprsIsDeviceId,
      name: 'AprsIsState',
      data: label,
      store: false,
    );
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _closeClient();
    _broker.dispose();
  }
}
