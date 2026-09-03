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
import 'dart:io' show Platform;
import 'dart:math' as math;

import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_util.dart';
import '../aprs/message_data.dart';
import '../aprs/packet_data_type.dart';
import '../gps/gps_data.dart';
import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/radio.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'aprsfi_client.dart';
import 'aprsis_client.dart';
import 'aprsis_history_store.dart';
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

  /// Maximum number of internet packets kept in memory for late-loading tabs,
  /// mirroring the on-disk history cap.
  static const int _maxHistoryInMemory = 1000;
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

  /// Append-only on-disk store that lets internet APRS history survive restarts.
  final AprsIsHistoryStore _history = AprsIsHistoryStore();

  /// Decoded persisted internet packets, loaded once at startup and served to
  /// the APRS / Map tabs on request. Empty on web (no persistence).
  final List<AprsPacket> _historyPackets = [];

  /// Whether the persisted history has finished loading.
  bool _historyReady = false;

  /// Guards against overlapping aprs.fi backfill requests.
  bool _mergingAprsFi = false;

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
    _broker.subscribe(deviceId: 1, name: 'GpsData', callback: _onSerialGps);

    // RF frames (from the AprsHandler on device 1) feed the heard list and the
    // RF -> internet up-gate. Internet frames we re-dispatch here carry
    // `fromAprsIs` and are ignored by the gating logic.
    _broker.subscribe(deviceId: 1, name: 'AprsFrame', callback: _onAprsFrame);

    // Serve persisted internet history to the APRS / Map tabs on request.
    _broker.subscribe(
      deviceId: 1,
      name: 'RequestAprsIsPackets',
      callback: _onRequestAprsIsPackets,
    );

    // A UI clear must also wipe persisted internet history; otherwise a later
    // duplicate copy of a message would reload from disk on the next launch.
    _broker.subscribe(
      deviceId: 1,
      name: 'ClearAprsPackets',
      callback: _onClearAprsPackets,
    );

    // Messages delivered by the cloud push service (HTCloudServer) are handed
    // here so they are persisted and surfaced exactly like live APRS-IS
    // traffic, instead of being dispatched as transient frames that never
    // survive a restart.
    _broker.subscribe(
      deviceId: 1,
      name: 'IngestCloudMessage',
      callback: _onIngestCloudMessage,
    );

    // Re-run the aprs.fi backfill whenever the API key or our callsign changes
    // (e.g. after the settings dialog is closed). Also re-checked when cloud
    // push is toggled, since it gates whether aprs.fi runs at all.
    _broker.subscribeMultiple(
      deviceId: 0,
      names: const [
        'AprsFiApiKey',
        'CallSign',
        'StationId',
        'AprsCloudNotifications',
      ],
      callback: (_, _, _) => unawaited(_mergeFromAprsFi()),
    );

    // Backfill missed messages from aprs.fi once the persisted history is
    // loaded, so newly fetched messages are de-duplicated against it.
    unawaited(_loadHistory().then((_) => _mergeFromAprsFi()));
    unawaited(_reconcile());
  }

  /// Loads the persisted internet history from disk, decodes it, and announces
  /// readiness so the APRS / Map tabs can request the list. No-op on web.
  Future<void> _loadHistory() async {
    final records = await _history.init();
    for (final rec in records) {
      final aprs = _decodeHistoryRecord(rec);
      if (aprs != null) _historyPackets.add(aprs);
    }
    _historyReady = true;
    _broker.dispatch(
      deviceId: 1,
      name: 'AprsIsStoreReady',
      data: true,
      store: true,
    );
  }

  /// Decodes a persisted TNC2 record back into an [AprsPacket] tagged as coming
  /// from APRS-IS, preserving its original receive time. Returns null when the
  /// stored line no longer parses.
  AprsPacket? _decodeHistoryRecord(AprsIsHistoryRecord rec) {
    final ax25 = Tnc2Codec.decode(rec.tnc2Line, time: rec.time);
    if (ax25 == null) return null;
    // The history file records no direction flag, but a message we sent carries
    // our own callsign as its source, so restore it as outgoing on reload (a
    // received message's source is the peer, so it stays incoming).
    final self = _readCallsignWithId();
    final source = ax25.addresses.length >= 2
        ? ax25.addresses[1].callSignWithId.toUpperCase()
        : '';
    if (self.isNotEmpty && source == self) {
      ax25.incoming = false;
      ax25.sent = true;
    }
    final aprs = AprsPacket.parse(ax25);
    if (aprs == null) return null;
    aprs.fromAprsIs = true;
    return aprs;
  }

  /// Responds to a request for the persisted internet packet list.
  void _onRequestAprsIsPackets(int deviceId, String name, Object? data) {
    if (!_historyReady) return;
    _broker.dispatch(
      deviceId: 1,
      name: 'AprsIsPacketList',
      data: List<AprsPacket>.from(_historyPackets),
      store: false,
    );
  }

  /// Clears in-memory and persisted internet history when the user clears APRS
  /// messages, so a cleared message cannot reload from disk on the next launch.
  void _onClearAprsPackets(int deviceId, String name, Object? data) {
    _historyPackets.clear();
    _history.clear();
  }

  // ---------------------------------------------------------------------------
  // aprs.fi backfill
  // ---------------------------------------------------------------------------

  /// Fetches recent messages from aprs.fi and merges any we do not already have
  /// into the internet history: messages addressed to us (received) and, to
  /// recover local state, messages we sent to those same stations. Runs at
  /// startup and whenever the API key or callsign changes. No-op when no API
  /// key is configured.
  Future<void> _mergeFromAprsFi() async {
    if (_mergingAprsFi || !_historyReady) return;
    // When cloud push (aprs.meshcentral.com) is enabled it supplies the same
    // message backlog more reliably, so skip the redundant aprs.fi backfill.
    if (Platform.isAndroid &&
        (_broker.getValue<int>(0, 'AprsCloudNotifications', 0) ?? 0) == 1) {
      return;
    }
    final apiKey =
        (_broker.getValue<String>(0, 'AprsFiApiKey', '') ?? '').trim();
    final self = _readCallsignWithId();
    if (apiKey.isEmpty || self.isEmpty) return;
    final selfUpper = self.toUpperCase();

    _mergingAprsFi = true;
    try {
      final userAgent = _appVersion.isEmpty
          ? _softwareName
          : '$_softwareName/$_appVersion';

      // 1. Messages addressed to us (received).
      final received = await AprsFiClient.fetchMessages(
        apiKey: apiKey,
        dstCallsign: self,
        userAgent: userAgent,
      );
      if (!received.ok) {
        _broker.logInfo('[aprs.fi] Backfill failed: ${received.error}');
        return;
      }
      var merged = 0;
      // aprs.fi returns newest first; ingest oldest first so the message view
      // keeps chronological order.
      for (final msg in received.messages.reversed) {
        if (_ingestAprsFiMessage(msg)) merged++;
      }

      // 2. Messages we sent to the stations we've talked with (recover local
      // state). aprs.fi only indexes messages by recipient, so we query the
      // peers that messaged us and keep the entries whose source is us.
      final peers = <String>{};
      for (final msg in received.messages) {
        final peer = msg.srcCall.trim().toUpperCase();
        if (peer.isNotEmpty && peer != selfUpper) peers.add(peer);
      }
      if (peers.isNotEmpty) {
        merged += await _mergeSentMessages(apiKey, userAgent, selfUpper, peers);
      }

      if (merged > 0) {
        _broker.logInfo('[aprs.fi] Backfilled $merged message(s)');
      }
    } finally {
      _mergingAprsFi = false;
    }
  }

  /// Fetches messages we sent to [peers] and merges them as outgoing messages.
  /// aprs.fi allows up to 10 recipients per query, so peers are queried in
  /// batches. Returns the number of newly merged messages.
  Future<int> _mergeSentMessages(
    String apiKey,
    String userAgent,
    String selfUpper,
    Set<String> peers,
  ) async {
    var merged = 0;
    final list = peers.toList();
    for (var i = 0; i < list.length; i += 10) {
      final batch = list.sublist(i, math.min(i + 10, list.length));
      final result = await AprsFiClient.fetchMessages(
        apiKey: apiKey,
        dstCallsign: batch.join(','),
        userAgent: userAgent,
      );
      if (!result.ok) continue;
      for (final msg in result.messages.reversed) {
        // Keep only the messages we sent to these peers.
        if (msg.srcCall.trim().toUpperCase() != selfUpper) continue;
        if (_ingestAprsFiMessage(msg, sent: true)) merged++;
      }
    }
    return merged;
  }

  /// Converts a single aprs.fi message into an internet [AprsPacket], skipping
  /// duplicates already present in the internet history. When [sent] is true
  /// the message is one we originated, so it is shown as outgoing. Returns true
  /// when a new message was ingested.
  bool _ingestAprsFiMessage(AprsFiMessage msg, {bool sent = false}) {
    final addressee = msg.dst.trim().toUpperCase();
    final src = msg.srcCall.trim().toUpperCase();
    if (addressee.isEmpty || src.isEmpty) return false;

    if (_isDuplicateAprsFiMessage(src, addressee, msg.message, msg.time)) {
      return false;
    }

    // Build a TNC2 line so the message flows through the same decode pipeline
    // as live APRS-IS traffic. The APRS message info field is a 9-character
    // padded addressee followed by ':' and the message text.
    final paddedAddressee = addressee.padRight(9);
    final tnc2Line = '$src>APRS,TCPIP*,qAC,APRSFI::$paddedAddressee:'
        '${msg.message}';
    final ax25 = Tnc2Codec.decode(tnc2Line, time: msg.time);
    if (ax25 == null) return false;
    if (sent) {
      ax25.incoming = false;
      ax25.sent = true;
    }
    final aprs = AprsPacket.parse(ax25);
    if (aprs == null || aprs.dataType != PacketDataType.message) return false;
    aprs.fromAprsIs = true;

    // Persist received messages so they survive a restart. Sent messages are
    // re-fetched from aprs.fi each run instead (the history store cannot record
    // packet direction, so a persisted sent message would reload as received).
    if (!sent) _history.append(ax25.time, tnc2Line);
    _historyPackets.add(aprs);
    while (_historyPackets.length > _maxHistoryInMemory) {
      _historyPackets.removeAt(0);
    }

    // Surface to the APRS + Map tabs (device 1, non-UniqueDataFrame).
    _broker.dispatch(
      deviceId: 1,
      name: 'AprsFrame',
      data: AprsFrameEventArgs(aprs, ax25, null),
      store: false,
    );
    return true;
  }

  /// Ingests a message delivered out-of-band by the cloud push service
  /// (HTCloudServer). The payload is a map with the TNC2 `line`, its `time`
  /// (epoch ms), and a `sent` flag marking a message we originated. The message
  /// is de-duplicated against the internet history, persisted so it survives a
  /// restart, and surfaced to the APRS + Comms tabs like live APRS-IS traffic.
  /// No ACK or down-gate is attempted here — the cloud server owns those.
  void _onIngestCloudMessage(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final line = (data['line'] as String?)?.trim() ?? '';
    if (line.isEmpty) return;
    final sent = data['sent'] == true;
    final tsRaw = data['time'];
    final time = tsRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(tsRaw)
        : DateTime.now();

    final ax25 = Tnc2Codec.decode(line, time: time);
    if (ax25 == null) return;
    // A message we sent is shown as outgoing; on reload it is recognised as
    // outgoing again because its source is our own callsign (_decodeHistoryRecord).
    if (sent) {
      ax25.incoming = false;
      ax25.sent = true;
    }
    final aprs = AprsPacket.parse(ax25);
    if (aprs == null || aprs.dataType != PacketDataType.message) return;
    aprs.fromAprsIs = true;

    // Drop a copy we already hold (the same message may also have arrived over
    // a live APRS-IS connection, or via an overlapping sync/register pull).
    if (_isLiveMessageDuplicate(aprs, ax25)) return;

    _history.append(ax25.time, line);
    _historyPackets.add(aprs);
    while (_historyPackets.length > _maxHistoryInMemory) {
      _historyPackets.removeAt(0);
    }

    _broker.dispatch(
      deviceId: 1,
      name: 'AprsFrame',
      data: AprsFrameEventArgs(aprs, ax25, null),
      store: false,
    );

    // A message we sent is our own outgoing traffic; only the APRS tab renders
    // it (via the AprsFrame above). The Comms-tab AprsMessageReceived event is
    // for messages addressed to us and must not fire for a sent message.
    if (sent) return;

    final source = ax25.addresses.length >= 2
        ? ax25.addresses[1].callSignWithId
        : '';
    _broker.dispatch(
      deviceId: 1,
      name: 'AprsMessageReceived',
      data: <String, Object?>{
        'text': aprs.messageData.msgText,
        'channel': 'APRS-IS',
        'time': ax25.time.millisecondsSinceEpoch,
        'source': source,
        'destination': aprs.messageData.addressee,
        'suppressNotification': true,
      },
      store: false,
    );
  }

  /// Whether the retained internet history already contains the same message
  /// at or before [time]. A later retransmission must not block an older
  /// aprs.fi copy, because the oldest copy is the canonical one.
  bool _isDuplicateAprsFiMessage(
    String src,
    String addressee,
    String text,
    DateTime time,
  ) {
    for (final p in _historyPackets) {
      if (p.dataType != PacketDataType.message) continue;
      final packet = p.packet;
      if (packet == null || packet.addresses.length < 2) continue;
      if (packet.addresses[1].callSignWithId.toUpperCase() != src) continue;
      if (p.messageData.addressee.toUpperCase() != addressee) continue;
      if (p.messageData.msgText != text) continue;
      if (!packet.time.isAfter(time)) {
        return true;
      }
    }
    return false;
  }

  /// Whether a live APRS-IS message duplicates one already in history (same
  /// source, addressee and text). Used to drop a sender's retransmissions.
  bool _isLiveMessageDuplicate(AprsPacket aprs, AX25Packet ax25) {
    final src = ax25.addresses.length >= 2
        ? ax25.addresses[1].callSignWithId.toUpperCase()
        : '';
    final addressee = aprs.messageData.addressee.trim().toUpperCase();
    if (src.isEmpty || addressee.isEmpty) return false;
    return _isDuplicateAprsFiMessage(
      src,
      addressee,
      aprs.messageData.msgText,
      ax25.time,
    );
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

    final client =
        AprsIsClient(
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

    final messageData = aprs.messageData;

    // A sender that never sees our ACK repeats the same message for hours.
    // Drop those retransmissions so the message keeps its first-seen time
    // instead of resurfacing at each newer copy; the ACK below still fires.
    if (aprs.dataType == PacketDataType.message &&
        messageData.msgType != MessageType.mtAck &&
        messageData.msgType != MessageType.mtRej &&
        messageData.msgText.isNotEmpty &&
        _isLiveMessageDuplicate(aprs, ax25)) {
      _maybeAckOverAprsIs(aprs, ax25);
      return;
    }

    // Persist to the append-only internet history so it survives a restart,
    // and keep it in the in-memory list served to late-loading tabs.
    _history.append(ax25.time, tnc2Line);
    _historyPackets.add(aprs);
    while (_historyPackets.length > _maxHistoryInMemory) {
      _historyPackets.removeAt(0);
    }

    // Surface to the APRS + Map tabs. Dispatched on device 1 (where both tabs
    // listen) but NOT as a UniqueDataFrame, so the RF packet store never
    // persists it and the two sources stay unmixed.
    _broker.dispatch(
      deviceId: 1,
      name: 'AprsFrame',
      data: AprsFrameEventArgs(aprs, ax25, null),
      store: false,
    );

    if (aprs.dataType == PacketDataType.message &&
        messageData.msgType != MessageType.mtAck &&
        messageData.msgType != MessageType.mtRej &&
        messageData.msgText.isNotEmpty) {
      final source = ax25.addresses.length >= 2
          ? ax25.addresses[1].callSignWithId
          : '';
      _broker.dispatch(
        deviceId: 1,
        name: 'AprsMessageReceived',
        data: <String, Object?>{
          'text': messageData.msgText,
          'channel': 'APRS-IS',
          'time': ax25.time.millisecondsSinceEpoch,
          'source': source,
          'destination': messageData.addressee,
          'latitude': aprs.position.coordinateSet.latitude.value,
          'longitude': aprs.position.coordinateSet.longitude.value,
        },
        store: false,
      );
    }

    _maybeGateToRf(aprs);
    _maybeAckOverAprsIs(aprs, ax25);
  }

  /// Sends an APRS message ACK back over APRS-IS when a message with a sequence
  /// number is received addressed to our station. Mirrors [AprsHandler]'s RF
  /// auto-ack, but replies over the internet instead of RF. No-op unless we are
  /// connected with a verified, transmit-capable login.
  void _maybeAckOverAprsIs(AprsPacket aprs, AX25Packet ax25) {
    if (aprs.dataType != PacketDataType.message) return;
    final messageData = aprs.messageData;
    if (messageData.msgType == MessageType.mtAck) return;
    if (messageData.msgType == MessageType.mtRej) return;
    final seqId = messageData.seqId.trim();
    if (seqId.isEmpty) return;

    final client = _client;
    if (client == null) return;
    if (client.state != AprsIsConnectionState.connected) return;
    if (!client.canTransmit || !client.isVerified) return;

    final localCallsign = _readCallsignWithId();
    if (localCallsign.isEmpty) return;

    // Only acknowledge messages actually addressed to us (with or without SSID).
    final addressee = messageData.addressee.trim().toUpperCase();
    if (addressee.isEmpty) return;
    final callsignOnly =
        (_broker.getValue<String>(0, 'CallSign', '') ?? '').trim().toUpperCase();
    final isForUs = addressee == localCallsign.toUpperCase() ||
        (callsignOnly.isNotEmpty && addressee == callsignOnly);
    if (!isForUs) return;

    if (ax25.addresses.length < 2) return;
    final senderCallsign = ax25.addresses[1].callSignWithId;
    if (senderCallsign.isEmpty) return;

    // APRS message ACK format: ":<addressee padded to 9>:ack<seqId>".
    final paddedAddr = senderCallsign.padRight(9);
    final tnc2Line = '$localCallsign>APRS,TCPIP*::$paddedAddr:ack$seqId';
    client.sendPacketLine(tnc2Line);
    _broker.logInfo('[APRS-IS] Sent ack$seqId to $senderCallsign');
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
