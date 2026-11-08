/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.BbsHandler` and `HTCommander.BBS` classes.

This is a two-part port:
  * [Bbs] is the per-radio BBS engine. It serves many clients at once (one
    [AX25Session] per calling station, the radio's XARA link, and any other
    [BbsLink] attached through [Bbs.openLink]), runs the bulletin-board
    conversation (M / S / D commands), and acts as a Winlink server,
    exchanging mail with connecting stations (either locally or by relaying
    each client to the Winlink CMS gateway). The menu itself ([BbsMenu]) lives
    in bbs_menu.dart, its games in bbs_games.dart.
  * [BbsHandler] is the manager (device 1). It creates/removes [Bbs] instances
    on `CreateBbs` / `RemoveBbs`, locks/unlocks the radio for "BBS" usage, and
    aggregates per-station statistics into a merged table broadcast as
    `BbsMergedStats`.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/ax25_session.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../radio/yapp_transfer.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/notification_service.dart';
import '../winlink/mail_store.dart';
import '../winlink/winlink_gateway_relay.dart';
import '../winlink/winlink_mail.dart';
import '../winlink/winlink_utils.dart';
import 'bbs_files.dart';
import 'bbs_menu.dart';
import 'bbs_monitor.dart';

export 'bbs_menu.dart' show BbsMenu, BbsMenuReply, BbsFileTransfer;

// ---------------------------------------------------------------------------
// Data classes (broker payloads)
// ---------------------------------------------------------------------------

/// Statistics for a station that has connected to a single BBS instance.
class StationStats {
  String callsign = '';
  DateTime lastseen = DateTime.now();
  String protocol = '';
  int packetsIn = 0;
  int packetsOut = 0;
  int bytesIn = 0;
  int bytesOut = 0;
}

/// Per-device statistics for a station, used to build [MergedStationStats].
class DeviceStationStats {
  int packetsIn = 0;
  int packetsOut = 0;
  int bytesIn = 0;
  int bytesOut = 0;

  Map<String, dynamic> toJson() => {
    'packetsIn': packetsIn,
    'packetsOut': packetsOut,
    'bytesIn': bytesIn,
    'bytesOut': bytesOut,
  };

  static DeviceStationStats fromJson(Map<String, dynamic> json) {
    final d = DeviceStationStats();
    d.packetsIn = (json['packetsIn'] as num?)?.toInt() ?? 0;
    d.packetsOut = (json['packetsOut'] as num?)?.toInt() ?? 0;
    d.bytesIn = (json['bytesIn'] as num?)?.toInt() ?? 0;
    d.bytesOut = (json['bytesOut'] as num?)?.toInt() ?? 0;
    return d;
  }
}

/// Station statistics aggregated across all BBS instances.
class MergedStationStats {
  String callsign = '';
  DateTime lastSeen = DateTime.now();
  String protocol = '';
  int totalPacketsIn = 0;
  int totalPacketsOut = 0;
  int totalBytesIn = 0;
  int totalBytesOut = 0;
  final Map<int, DeviceStationStats> deviceStats = {};

  /// Human-readable summary matching the C# BBS tab stats column.
  String get statsString =>
      '$protocol, $totalPacketsIn in / $totalPacketsOut out, '
      '$totalBytesIn in / $totalBytesOut out';

  Map<String, dynamic> toJson() => {
    'callsign': callsign,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
    'protocol': protocol,
    'totalPacketsIn': totalPacketsIn,
    'totalPacketsOut': totalPacketsOut,
    'totalBytesIn': totalBytesIn,
    'totalBytesOut': totalBytesOut,
    'deviceStats': deviceStats.map(
      (k, v) => MapEntry(k.toString(), v.toJson()),
    ),
  };

  static MergedStationStats fromJson(Map<String, dynamic> json) {
    final m = MergedStationStats();
    m.callsign = json['callsign'] as String? ?? '';
    m.lastSeen = DateTime.fromMillisecondsSinceEpoch(
      (json['lastSeen'] as num?)?.toInt() ?? 0,
    );
    m.protocol = json['protocol'] as String? ?? '';
    m.totalPacketsIn = (json['totalPacketsIn'] as num?)?.toInt() ?? 0;
    m.totalPacketsOut = (json['totalPacketsOut'] as num?)?.toInt() ?? 0;
    m.totalBytesIn = (json['totalBytesIn'] as num?)?.toInt() ?? 0;
    m.totalBytesOut = (json['totalBytesOut'] as num?)?.toInt() ?? 0;
    final ds = json['deviceStats'];
    if (ds is Map) {
      ds.forEach((k, v) {
        final key = int.tryParse(k.toString());
        if (key != null && v is Map) {
          m.deviceStats[key] = DeviceStationStats.fromJson(
            Map<String, dynamic>.from(v),
          );
        }
      });
    }
    return m;
  }
}

/// Request payload for the `CreateBbs` command (device 1).
class CreateBbsData {
  final int radioDeviceId;
  final int channelId;
  final int regionId;

  CreateBbsData({
    required this.radioDeviceId,
    required this.channelId,
    required this.regionId,
  });
}

/// Request payload for the `RemoveBbs` command (device 1).
class RemoveBbsData {
  final int radioDeviceId;

  RemoveBbsData({required this.radioDeviceId});
}

/// Status of a single BBS instance (`BbsCreated` / `BbsList`).
class BbsStatusData {
  final int radioDeviceId;
  final int channelId;
  final int regionId;
  final bool enabled;

  BbsStatusData({
    required this.radioDeviceId,
    required this.channelId,
    required this.regionId,
    required this.enabled,
  });
}

/// Payload for the `BbsRemoved` event.
class BbsRemovedData {
  final int radioDeviceId;

  BbsRemovedData({required this.radioDeviceId});
}

/// Payload for the `BbsCreateFailed` / `BbsRemoveFailed` events.
class BbsErrorData {
  final int radioDeviceId;
  final String error;

  BbsErrorData({required this.radioDeviceId, required this.error});
}

/// Payload for the `BbsTraffic` event (a single line of BBS conversation).
class BbsTrafficData {
  final int deviceId;
  final String callsign;
  final bool outgoing;
  final String message;

  BbsTrafficData({
    required this.deviceId,
    required this.callsign,
    required this.outgoing,
    required this.message,
  });
}

/// Payload for the `BbsControlMessage` event (status / informational text).
/// [callsign] names the client the message concerns, or is empty when it
/// concerns the BBS as a whole.
class BbsControlMessageData {
  final int deviceId;
  final String callsign;
  final String message;

  BbsControlMessageData({
    required this.deviceId,
    required this.message,
    this.callsign = '',
  });
}

/// Payload for the `BbsError` event (a session-level error).
class BbsErrorEventData {
  final int deviceId;
  final String callsign;
  final String error;

  BbsErrorEventData({
    required this.deviceId,
    required this.error,
    this.callsign = '',
  });
}

/// Payload for the `BbsStatsUpdated` event from an individual BBS instance.
class BbsStatsUpdatedData {
  final int deviceId;
  final StationStats stats;

  BbsStatsUpdatedData({required this.deviceId, required this.stats});
}

/// Payload for the `BbsStatsCleared` event from an individual BBS instance.
class BbsStatsClearedData {
  final int deviceId;

  BbsStatsClearedData({required this.deviceId});
}

// ---------------------------------------------------------------------------
// BbsLink: a connected client, over AX.25 or XARA
// ---------------------------------------------------------------------------

/// A connected BBS client. The BBS conversation and Winlink mail exchange run
/// identically over any transport (AX.25 connected mode, XARA, ...). The BBS
/// serves many links at once; each keeps its own [sessionState].
abstract class BbsLink {
  /// Per-connection scratch state (mode, Winlink proposals, relay flags...).
  Map<String, Object?> get sessionState;

  /// Remote callsign including any SSID, for display and statistics.
  String get remoteCallsign;

  /// Remote callsign without SSID, used for Winlink addressing.
  String get remoteAddress {
    final call = remoteCallsign;
    final dash = call.indexOf('-');
    return dash > 0 ? call.substring(0, dash) : call;
  }

  /// Protocol label shown in the BBS statistics.
  String get protocol;

  bool get isConnected;

  void send(Uint8List data);

  /// Gracefully ends the link; the transport reports back when it is closed.
  void disconnect();

  /// Whether sent data is still waiting to be delivered or acknowledged.
  bool get hasPendingData => false;

  /// Drops the link immediately and silently when the BBS shuts down. The BBS
  /// has already forgotten the link, so no closing notification is expected.
  void abort() => disconnect();
}

class _Ax25BbsLink extends BbsLink {
  final AX25Session session;

  // Captured from the first frame so they survive the session forgetting its
  // addresses on disconnect.
  @override
  final String remoteCallsign;
  @override
  final String remoteAddress;

  _Ax25BbsLink(this.session, AX25Address peer)
    : remoteCallsign = peer.toString(),
      remoteAddress = peer.address;

  @override
  Map<String, Object?> get sessionState => session.sessionState;

  @override
  String get protocol => 'Stream';

  @override
  bool get isConnected => session.currentState == AX25ConnectionState.connected;

  @override
  void send(Uint8List data) => session.send(data);

  @override
  void disconnect() => session.disconnect();

  @override
  bool get hasPendingData => session.sendBufferLength > 0;

  @override
  void abort() => session.dispose();
}

/// An incoming XARA ARQ link, driven through the software modem's per-radio
/// `XaraSend` / `XaraDisconnect` commands.
class _XaraBbsLink extends BbsLink {
  final int deviceId;
  final DataBrokerClient broker;
  @override
  final String remoteCallsign;
  @override
  final Map<String, Object?> sessionState = {};
  bool connected = true;

  _XaraBbsLink(this.deviceId, this.broker, this.remoteCallsign);

  @override
  String get protocol => 'XARA';

  @override
  bool get isConnected => connected;

  @override
  void send(Uint8List data) {
    if (!connected || data.isEmpty) return;
    broker.dispatch(
      deviceId: deviceId,
      name: 'XaraSend',
      data: data,
      store: false,
    );
  }

  @override
  void disconnect() {
    if (!connected) return;
    broker.dispatch(
      deviceId: deviceId,
      name: 'XaraDisconnect',
      data: null,
      store: false,
    );
  }

  @override
  void abort() {
    connected = false;
    sessionState.clear();
  }
}

// ---------------------------------------------------------------------------
// Bbs: per-radio BBS engine
// ---------------------------------------------------------------------------

/// BBS (Bulletin Board System) engine for a specific radio device.
///
/// Serves many clients at once: one [AX25Session] per calling station, plus
/// the radio's XARA link when XARA is its software modem. Incoming AX.25
/// frames addressed to our callsign are routed here to the session for their
/// source station. When a station connects it is greeted with a banner, after
/// which it can drive the menu (M / S / D) or speak the Winlink B2F protocol
/// to exchange mail. When possible each client is relayed to the Winlink CMS
/// gateway over its own connection; otherwise mail is exchanged locally.
class Bbs {
  final int _deviceId;
  final int channelId;
  final int regionId;
  final DataBrokerClient _broker = DataBrokerClient();

  /// AX.25 links keyed by the peer's `callSignWithId`, including stations that
  /// are still handshaking or disconnecting.
  final Map<String, _Ax25BbsLink> _ax25Links = {};
  _XaraBbsLink? _xaraLink;

  /// Clients currently being served, in connection order.
  final List<BbsLink> _links = [];
  final Map<BbsLink, WinlinkGatewayRelay> _cmsRelays = {};

  /// YAPP file transfer engines of AX.25 clients.
  final Map<BbsLink, YappTransfer> _yapps = {};
  bool _disposed = false;

  /// Default cap on simultaneously served clients.
  static const int defaultMaxLinks = 16;

  /// Clients beyond this many are told the BBS is busy and disconnected.
  int maxLinks = defaultMaxLinks;

  /// Longest unterminated "[..." fragment held back while waiting for the rest
  /// of a Winlink SID; longer fragments are processed as regular input.
  static const int _maxPartialSidLength = 128;

  /// Creates the Winlink CMS relay for a connecting client; replaceable in tests.
  static WinlinkGatewayRelay Function(int deviceId, DataBrokerClient broker)
  relayFactory = WinlinkGatewayRelay.new;

  /// The text menu served to clients that are not exchanging Winlink mail.
  BbsMenu menu = BbsMenu();

  bool _enabled = false;

  /// Disabling immediately drops links and cancels this radio's transmissions.
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    if (!value) _abortAllLinks();

    _broker.dispatch(
      deviceId: _deviceId,
      name: 'BbsEnabled',
      data: value,
      store: true,
    );
    if (!value) {
      _broker.dispatch(
        deviceId: _deviceId,
        name: 'CancelDataTransmit',
        data: null,
        store: false,
      );
    }
  }

  /// Statistics for stations that have connected to this BBS.
  final Map<String, StationStats> stats = {};

  int get deviceId => _deviceId;

  /// Clients currently being served (AX.25, XARA, ...), in connection order.
  List<BbsLink> get links => List.unmodifiable(_links);

  /// The AX.25 session for [callsign] (e.g. `N1ABC-5`), if one exists.
  AX25Session? ax25Session(String callsign) {
    final key = AX25Address.parse(callsign.trim())?.callSignWithId;
    return key == null ? null : _ax25Links[key]?.session;
  }

  /// All live AX.25 sessions, including ones still handshaking.
  List<AX25Session> get ax25Sessions => [
    for (final l in _ax25Links.values) l.session,
  ];

  Bbs(this._deviceId, {this.channelId = -1, this.regionId = -1}) {
    // XARA links are only reported when XARA is this radio's software modem.
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'XaraEvent',
      callback: _onXaraEvent,
    );
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'XaraDataReceived',
      callback: _onXaraData,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );

    _broker.logInfo(
      '[BBS/$_deviceId] BBS handler created for device $_deviceId',
    );
  }

  // ---- broker helpers -------------------------------------------------------

  void _dispatchTraffic(String callsign, bool outgoing, String message) {
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsTraffic',
      data: BbsTrafficData(
        deviceId: _deviceId,
        callsign: callsign,
        outgoing: outgoing,
        message: message,
      ),
      store: false,
    );
  }

  void _dispatchControl(String message, [String callsign = '']) {
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsControlMessage',
      data: BbsControlMessageData(
        deviceId: _deviceId,
        callsign: callsign,
        message: message,
      ),
      store: false,
    );
  }

  // ---- generic link API -----------------------------------------------------

  /// Starts serving [link], greeting it with the BBS banner. Transports other
  /// than the built-in AX.25 and XARA ones attach their clients through this,
  /// then report input with [linkReceived] and closure with [closeLink].
  /// With [cmsRelay] false the client is served locally right away, skipping
  /// the Winlink CMS gateway relay attempt.
  void openLink(BbsLink link, {bool cmsRelay = true}) =>
      _onLinkConnected(link, cmsRelay: cmsRelay);

  /// Feeds data received from a served [link] into the BBS.
  void linkReceived(BbsLink link, Uint8List data) {
    if (!_enabled || _disposed || !_links.contains(link)) return;
    _processStream(link, data);
  }

  /// Stops serving [link] after its transport closed.
  void closeLink(BbsLink link) => _onLinkDisconnected(link);

  // ---- AX.25 routing --------------------------------------------------------

  /// Routes an incoming AX.25 frame addressed to us to the session for its
  /// source station, creating a session for a new caller.
  void _onUniqueDataFrame(int sourceDeviceId, String name, Object? data) {
    if (!_enabled || _disposed) return;
    if (data is! TncDataFragment) return;
    if (data.radioDeviceId != _deviceId || !data.incoming) return;
    final packet = AX25Packet.decode(data);
    if (packet == null || packet.addresses.length < 2) return;

    // Only answer frames addressed to this station; other traffic on the
    // channel belongs to other stations' links.
    final us = AX25Address.getAddress(
      (_broker.getValue<String>(0, 'CallSign', '') ?? '').trim(),
      _broker.getValue<int>(0, 'StationId', 0) ?? 0,
    );
    if (us == null ||
        packet.addresses[0].callSignWithId.toUpperCase() != us.callSignWithId) {
      return;
    }

    final peer = AX25Address.parse(packet.addresses[1].toString());
    if (peer == null) return;
    final key = peer.callSignWithId;
    final existing = _ax25Links[key];
    if (existing != null) {
      existing.session.receive(packet, encoding: data.encoding);
      return;
    }

    final session = AX25Session(_deviceId, listen: false);
    final link = _Ax25BbsLink(session, peer);
    session.onStateChanged = (_, state) => _onAx25StateChanged(link, state);
    session.onDataReceived = (_, d) => linkReceived(link, d);
    session.onUiDataReceived = _onSessionUiDataReceived;
    session.onError = (_, error) => _onSessionError(link, error);
    _ax25Links[key] = link;
    session.receive(packet, encoding: data.encoding);

    // A stray frame (not a connect request) only earns a DM/UA reply and
    // leaves the session unbound; don't keep it around.
    if (identical(_ax25Links[key], link) &&
        session.currentState == AX25ConnectionState.disconnected) {
      _ax25Links.remove(key);
      session.dispose();
    }
  }

  void _onAx25StateChanged(_Ax25BbsLink link, AX25ConnectionState state) {
    if (!_enabled || _disposed) return;
    switch (state) {
      case AX25ConnectionState.connected:
        _onLinkConnected(link);
        break;
      case AX25ConnectionState.disconnected:
        final key = AX25Address.parse(link.remoteCallsign)?.callSignWithId;
        if (key != null && identical(_ax25Links[key], link)) {
          _ax25Links.remove(key);
          // Called from inside the session's state machine; let it unwind
          // before tearing it down.
          scheduleMicrotask(link.session.dispose);
        }
        _onLinkDisconnected(link);
        break;
      case AX25ConnectionState.connecting:
        _dispatchControl('Connecting...', link.remoteCallsign);
        break;
      case AX25ConnectionState.disconnecting:
        if (_links.contains(link)) {
          _dispatchControl('Disconnecting...', link.remoteCallsign);
        }
        break;
    }
  }

  void _onSessionUiDataReceived(AX25Session sender, Uint8List data) {
    if (!enabled) return;
    _broker.logInfo('[BBS/$_deviceId] Received UI data: ${data.length} bytes');
  }

  void _onSessionError(BbsLink link, String error) {
    _broker.logError(
      '[BBS/$_deviceId] Session error (${link.remoteCallsign}): $error',
    );
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsError',
      data: BbsErrorEventData(
        deviceId: _deviceId,
        callsign: link.remoteCallsign,
        error: error,
      ),
      store: false,
    );
  }

  // ---- XARA -----------------------------------------------------------------

  void _onXaraEvent(int deviceId, String name, Object? data) {
    if (!enabled || _disposed || data is! Map) return;
    switch (data['evt']) {
      case 'connected':
        final caller = (data['caller'] as String?)?.trim().toUpperCase() ?? '';
        if (caller.isEmpty) return;
        // Only answer incoming links; ignore connects we dialed ourselves. The
        // caller may share our callsign (two stations of one licensee), so rely
        // on the modem's flag rather than comparing callsigns.
        final incoming = data['incoming'];
        if (incoming == false) return;
        if (incoming == null) {
          final myCall = (_broker.getValue<String>(0, 'CallSign', '') ?? '')
              .trim()
              .toUpperCase();
          if (caller == myCall) return;
        }
        // The modem carries one ARQ link at a time, so a new connect means
        // any previous link is gone.
        final previous = _xaraLink;
        if (previous != null) {
          previous.connected = false;
          _onLinkDisconnected(previous);
        }
        final link = _XaraBbsLink(_deviceId, _broker, caller);
        _xaraLink = link;
        _broker.logInfo(
          '[BBS/$_deviceId] XARA link from $caller'
          '${data['wide'] == true ? ' (wide)' : ' (narrow)'}',
        );
        _onLinkConnected(link);
      case 'disconnected':
      case 'timedOut':
      case 'unableToConnect':
        final link = _xaraLink;
        if (link == null) return;
        link.connected = false;
        _xaraLink = null;
        _onLinkDisconnected(link);
    }
  }

  void _onXaraData(int deviceId, String name, Object? data) {
    if (data is! Uint8List) return;
    final link = _xaraLink;
    if (link != null) linkReceived(link, data);
  }

  // ---- connection state -----------------------------------------------------

  void _onLinkConnected(BbsLink link, {bool cmsRelay = true}) {
    if (!_enabled || _disposed || _links.contains(link)) return;
    if (_links.length >= maxLinks) {
      _dispatchControl(
        'Busy, rejecting ${link.remoteCallsign}',
        link.remoteCallsign,
      );
      link.send(
        Uint8List.fromList(utf8.encode('BBS busy, please try again later\r')),
      );
      _disconnectWhenSent(link);
      return;
    }
    _links.add(link);
    BbsMonitor.instance.sessionStarted(
      _deviceId,
      link.remoteCallsign,
      link.protocol == 'Stream' ? 'AX.25' : link.protocol,
    );
    link.sessionState.clear();
    if (link is _Ax25BbsLink) _attachYapp(link);
    link.sessionState['bbsWelcome'] = menu.welcome(
      link.remoteCallsign,
      link.protocol,
    );
    _dispatchControl(
      'Connected to ${link.remoteCallsign}'
      '${link.protocol == 'XARA' ? ' (XARA)' : ''}',
      link.remoteCallsign,
    );
    if (cmsRelay) {
      unawaited(_attemptCmsRelayConnect(link, link.remoteAddress));
    } else {
      _sendLocalBanner(link);
    }
  }

  void _onLinkDisconnected(BbsLink link) {
    if (!_links.remove(link)) return;
    _cleanupCmsRelay(link);
    _yapps.remove(link)?.dispose();
    _dispatchControl('Disconnected', link.remoteCallsign);
    BbsMonitor.instance.sessionEnded(_deviceId, link.remoteCallsign);
  }

  /// Disconnects [link] once its queued data is delivered (an AX.25 disconnect
  /// discards unsent frames), giving up on waiting after [limit].
  void _disconnectWhenSent(
    BbsLink link, {
    Duration limit = const Duration(seconds: 30),
  }) {
    final deadline = DateTime.now().add(limit);
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_disposed || !_enabled || !link.isConnected) {
        timer.cancel();
      } else if (!link.hasPendingData || DateTime.now().isAfter(deadline)) {
        timer.cancel();
        link.disconnect();
      }
    });
  }

  /// Silently drops every client, as when the BBS is disabled.
  void _abortAllLinks() {
    final served = List<BbsLink>.of(_links);
    final all = <BbsLink>{...served, ..._ax25Links.values};
    final xara = _xaraLink;
    if (xara != null) all.add(xara);
    _links.clear();
    _ax25Links.clear();
    _xaraLink = null;
    for (final link in _cmsRelays.keys.toList()) {
      _cleanupCmsRelay(link);
    }
    for (final yapp in _yapps.values) {
      yapp.dispose();
    }
    _yapps.clear();
    for (final link in all) {
      link.abort();
      link.sessionState.clear();
    }
    for (final link in served) {
      _dispatchControl('Disconnected', link.remoteCallsign);
      BbsMonitor.instance.sessionEnded(_deviceId, link.remoteCallsign);
    }
  }

  // ---- statistics -----------------------------------------------------------

  void _updateStats(
    String callsign,
    String protocol,
    int packetIn,
    int packetOut,
    int bytesIn,
    int bytesOut,
  ) {
    if (!enabled) return;
    final s = stats[callsign] ?? StationStats();
    s.callsign = callsign;
    s.lastseen = DateTime.now();
    s.protocol = protocol;
    s.packetsIn += packetIn;
    s.packetsOut += packetOut;
    s.bytesIn += bytesIn;
    s.bytesOut += bytesOut;
    stats[callsign] = s;

    _broker.dispatch(
      deviceId: 0,
      name: 'BbsStatsUpdated',
      data: BbsStatsUpdatedData(deviceId: _deviceId, stats: s),
      store: false,
    );
  }

  /// Clears the statistics for this BBS instance.
  void clearStats() {
    stats.clear();
    _broker.dispatch(
      deviceId: 0,
      name: 'BbsStatsCleared',
      data: BbsStatsClearedData(deviceId: _deviceId),
      store: false,
    );
  }

  // ---- outbound text --------------------------------------------------------

  void _sessionSend(BbsLink session, String output) {
    if (!enabled) return;
    if (output.isEmpty) return;
    final dataStrs = output
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    for (int i = 0; i < dataStrs.length; i++) {
      if (dataStrs[i].trim().isEmpty && i == dataStrs.length - 1) continue;
      _dispatchTraffic(session.remoteCallsign, true, dataStrs[i].trim());
    }
    _updateStats(
      session.remoteCallsign,
      session.protocol,
      0,
      1,
      0,
      output.length,
    );
    session.send(Uint8List.fromList(utf8.encode(output)));
  }

  // ---- Winlink CMS relay ----------------------------------------------------

  Future<void> _attemptCmsRelayConnect(
    BbsLink session,
    String stationCallsign,
  ) async {
    if (!enabled || _disposed || !_links.contains(session)) return;
    final call = session.remoteCallsign;
    WinlinkGatewayRelay? relay;
    try {
      relay = relayFactory(_deviceId, _broker);
      _cmsRelays[session] = relay;
      _broker.logInfo(
        '[BBS/$_deviceId] Attempting CMS relay connection for $stationCallsign',
      );
      _dispatchControl('Connecting to Winlink gateway...', call);

      final connected = await relay.connectAsync(
        stationCallsign,
        timeoutMs: 15000,
      );

      // The client may have left while the gateway was being reached.
      if (!enabled ||
          _disposed ||
          !identical(_cmsRelays[session], relay) ||
          !_links.contains(session) ||
          !session.isConnected) {
        relay.dispose();
        return;
      }

      if (connected && relay.isConnected) {
        _broker.logInfo(
          '[BBS/$_deviceId] CMS relay connected for $call, relay mode active',
        );
        _dispatchControl('Winlink gateway connected (relay mode)', call);

        session.sessionState['wlRelayMode'] = true;

        relay.lineReceived = (line) => _onCmsRelayLineReceived(session, line);
        relay.binaryDataReceived = (data) =>
            _onCmsRelayBinaryReceived(session, data);
        relay.disconnected = () => _onCmsRelayDisconnected(session);

        final sb = StringBuffer();
        sb.write(BbsMenu.banner);
        sb.write(session.sessionState['bbsWelcome'] ?? '');
        if (relay.wl2kBanner != null && relay.wl2kBanner!.isNotEmpty) {
          sb.write('${relay.wl2kBanner}\r');
        } else {
          sb.write('[WL2K-5.0-B2FWIHJM\$]\r');
        }
        if (relay.pqChallenge != null && relay.pqChallenge!.isNotEmpty) {
          sb.write(';PQ: ${relay.pqChallenge}\r');
        }
        sb.write('>\r');
        _sessionSend(session, sb.toString());
      } else {
        _broker.logInfo(
          '[BBS/$_deviceId] CMS relay failed for $call, falling back to local mode',
        );
        _dispatchControl('Winlink gateway unavailable (local mode)', call);
        _cleanupCmsRelay(session);
        _sendLocalBanner(session);
      }
    } catch (ex) {
      if (!enabled ||
          _disposed ||
          !identical(_cmsRelays[session], relay) ||
          !_links.contains(session)) {
        relay?.dispose();
        return;
      }
      _broker.logError('[BBS/$_deviceId] CMS relay connect error: $ex');
      _dispatchControl('Winlink gateway error (local mode)', call);
      _cleanupCmsRelay(session);
      _sendLocalBanner(session);
    }
  }

  void _sendLocalBanner(BbsLink session) {
    session.sessionState['wlRelayMode'] = false;
    session.sessionState['wlChallenge'] = WinlinkSecurity.generateChallenge();

    final sb = StringBuffer();
    sb.write(BbsMenu.banner);
    sb.write(session.sessionState['bbsWelcome'] ?? '');
    sb.write('[WL2K-5.0-B2FWIHJM\$]\r');

    final winlinkPassword =
        _broker.getValue<String>(0, 'WinlinkPassword', '') ?? '';
    if (winlinkPassword.isNotEmpty) {
      sb.write(';PQ: ${session.sessionState["wlChallenge"]}\r');
    }
    sb.write('>\r');
    _sessionSend(session, sb.toString());
  }

  void _onCmsRelayLineReceived(BbsLink session, String line) {
    if (!enabled || _disposed || !_links.contains(session)) return;
    if (!session.isConnected) return;

    _broker.logInfo('[BBS/$_deviceId] CMS->${session.remoteCallsign}: $line');
    _dispatchControl(
      'Gateway->Radio: ${utf8.encode(line).length} bytes',
      session.remoteCallsign,
    );

    String key = line.toUpperCase();
    String value = '';
    final i = line.indexOf(' ');
    if (i > 0) {
      key = line.substring(0, i).toUpperCase();
      value = line.substring(i + 1);
    }

    final relay = _cmsRelays[session];
    if (key == 'FS' && value.toUpperCase().contains('Y')) {
      session.sessionState['wlRelayBinary'] = true;
      relay?.binaryMode = true;
    }
    if (key == 'FF' || key == 'FQ') {
      session.sessionState['wlRelayBinary'] = false;
      relay?.binaryMode = false;
    }

    _sessionSend(session, '$line\r');
  }

  void _onCmsRelayBinaryReceived(BbsLink session, Uint8List data) {
    if (!enabled || _disposed || !_links.contains(session)) return;
    if (!session.isConnected) return;

    _broker.logInfo(
      '[BBS/$_deviceId] CMS->${session.remoteCallsign}: '
      '${data.length} binary bytes',
    );
    _dispatchControl(
      'Gateway->Radio: ${data.length} bytes (binary)',
      session.remoteCallsign,
    );
    _updateStats(
      session.remoteCallsign,
      session.protocol,
      0,
      1,
      0,
      data.length,
    );
    session.send(data);
  }

  void _onCmsRelayDisconnected(BbsLink session) {
    if (!enabled || _disposed || !_links.contains(session)) return;
    _broker.logInfo(
      '[BBS/$_deviceId] CMS relay disconnected for ${session.remoteCallsign}',
    );
    _dispatchControl('Winlink gateway disconnected', session.remoteCallsign);

    final isRelayMode = session.sessionState['wlRelayMode'] == true;
    if (isRelayMode && session.isConnected) {
      session.disconnect();
    }
  }

  void _cleanupCmsRelay(BbsLink session) {
    final relay = _cmsRelays.remove(session);
    if (relay != null) {
      relay.lineReceived = null;
      relay.binaryDataReceived = null;
      relay.disconnected = null;
      relay.dispose();
    }
  }

  // ---- inbound data ---------------------------------------------------------

  void _processStream(BbsLink session, Uint8List data) {
    if (!enabled) return;
    if (data.isEmpty) return;
    _updateStats(
      session.remoteCallsign,
      session.protocol,
      1,
      0,
      data.length,
      0,
    );

    final mode = session.sessionState['mode'] as String?;
    if (mode == 'mail') {
      _processMailStream(session, data);
      return;
    }
    // Winlink B2F blocks also start with YAPP control bytes, so YAPP is only
    // offered outside of mail mode.
    final yapp = _yapps[session];
    if (yapp != null) {
      if (yapp.isAwaitingReceiver && !YappTransfer.isProtocolData(data)) {
        // The client typed instead of accepting the download; it probably
        // has no YAPP support. Drop the offer silently and carry on.
        yapp.reset();
        yapp.enableAutoReceive();
        _dispatchControl('Download not accepted', session.remoteCallsign);
        final queued = session.sessionState.remove('bbsQueue');
        _sessionSend(session, 'Download cancelled.\r');
        if (queued is List<String> && queued.isNotEmpty) {
          _processBbsLines(session, queued);
        }
      } else if (yapp.processIncomingData(data)) {
        return;
      }
    }
    _processBbsStream(session, data);
  }

  void _processBbsStream(BbsLink session, Uint8List data) {
    if (!enabled) return;

    final pending = session.sessionState.remove('bbsPartialLine') as String?;
    final dataStr = (pending ?? '') + utf8.decode(data, allowMalformed: true);
    final dataStrs = dataStr
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');

    // A Winlink client SID (e.g. "[RMS Express-1.7.28.0-B2FHM$]") may arrive
    // split across several frames. Hold back an unterminated line that could
    // be the start of a SID so we don't mistake the fragment for a BBS
    // command and drop the CMS relay.
    final last = dataStrs.last;
    if (last.isNotEmpty &&
        last.startsWith('[') &&
        last.length < _maxPartialSidLength) {
      session.sessionState['bbsPartialLine'] = last;
      dataStrs.removeLast();
    }

    // While a reply is still being prepared (e.g. a callsign lookup), queue
    // new lines so that replies keep their order.
    final queued = session.sessionState['bbsQueue'];
    if (queued is List<String>) {
      queued.addAll(dataStrs);
      return;
    }
    _processBbsLines(session, dataStrs);
  }

  void _processBbsLines(BbsLink session, List<String> dataStrs) {
    if (!enabled) return;

    // Replies to several lines received together go out in one send.
    final out = StringBuffer();
    void flush() {
      if (out.isEmpty) return;
      _sessionSend(session, out.toString());
      out.clear();
    }

    for (int lineIndex = 0; lineIndex < dataStrs.length; lineIndex++) {
      final str = dataStrs[lineIndex];
      if (str.isEmpty) continue;
      _dispatchTraffic(session.remoteCallsign, false, str.trim());

      // Switch to Winlink mail mode when the station sends a WL2K SID.
      if (!session.sessionState.containsKey('mode') &&
          str.length > 6 &&
          str.indexOf('-') > 0 &&
          str.startsWith('[') &&
          str.endsWith('\$]')) {
        flush();
        session.sessionState['mode'] = 'mail';
        final remainingData = StringBuffer();
        remainingData.write(str);
        for (int j = lineIndex + 1; j < dataStrs.length; j++) {
          remainingData.write('\r');
          remainingData.write(dataStrs[j]);
        }
        _processMailStream(
          session,
          Uint8List.fromList(utf8.encode(remainingData.toString())),
        );
        return;
      } else if (_cmsRelays.containsKey(session)) {
        // First command is not a Winlink SID — they want BBS features, so
        // drop the CMS relay and continue locally.
        _broker.logInfo(
          '[BBS/$_deviceId] ${session.remoteCallsign} sent a BBS command, disconnecting Winlink gateway relay',
        );
        _dispatchControl(
          'Disconnecting Winlink gateway (BBS mode)',
          session.remoteCallsign,
        );
        session.sessionState['wlRelayMode'] = false;
        _cleanupCmsRelay(session);
      }

      final transfer = _yapps.containsKey(session)
          ? BbsFileTransfer.yapp
          : BbsFileTransfer.none;
      final reply = menu.handleLine(
        session.remoteCallsign,
        str,
        transfer: transfer,
        session: session.sessionState,
      );
      if (reply is BbsMenuReply) {
        if (reply.disconnect) {
          if (out.isEmpty) {
            session.disconnect();
          } else {
            flush();
            _disconnectWhenSent(session);
          }
          return;
        }
        out.write(reply.text);
        final file = reply.download;
        if (file != null && transfer == BbsFileTransfer.yapp) {
          flush();
          // Lines after the download wait until the transfer is over.
          session.sessionState['bbsQueue'] = dataStrs.sublist(lineIndex + 1);
          _startDownload(session, file);
          return;
        }
        continue;
      }

      // Hold the remaining lines until this reply is ready.
      flush();
      session.sessionState['bbsQueue'] = dataStrs.sublist(lineIndex + 1);
      reply.then(
        (r) => _onAsyncMenuReply(session, r),
        onError: (Object e) {
          _broker.logError('[BBS/$_deviceId] BBS command failed: $e');
          _onAsyncMenuReply(
            session,
            const BbsMenuReply('Command failed.\r${BbsMenu.prompt}'),
          );
        },
      );
      return;
    }
    flush();
  }

  void _onAsyncMenuReply(BbsLink session, BbsMenuReply reply) {
    final queued = session.sessionState.remove('bbsQueue');
    if (!enabled || _disposed || !_links.contains(session)) return;
    if (!session.isConnected) return;
    if (reply.disconnect) {
      session.disconnect();
      return;
    }
    _sessionSend(session, reply.text);
    if (queued is List<String> && queued.isNotEmpty) {
      _processBbsLines(session, queued);
    }
  }

  // ---- YAPP file transfer ---------------------------------------------------

  /// Inactivity timeout of a YAPP transfer, retried [_yappRetries] times.
  static const int _yappTimeoutMs = 30000;
  static const int _yappRetries = 2;

  void _attachYapp(_Ax25BbsLink link) {
    final call = link.remoteCallsign;
    final yapp = YappTransfer(
      link.session,
      send: (packet) {
        _updateStats(call, link.protocol, 0, 1, 0, packet.length);
        link.send(packet);
      },
    );
    yapp
      ..timeoutMs = _yappTimeoutMs
      ..maxRetries = _yappRetries
      ..maxReceiveBytes = BbsFileStore.maxUploadBytes
      ..onReceiveRequest = (name, size) {
        final refusal = menu.files.checkUpload(size);
        // Refusals are reported through onError.
        if (refusal == null) {
          _dispatchControl('Receiving file $name ($size bytes)', call);
        }
        return refusal;
      }
      ..onReceiveComplete = (name, data) {
        final result = menu.files.upload(call, name, data);
        final file = result.file;
        final message = file == null
            ? 'Upload of $name failed: ${result.error}.\r'
            : 'Received ${file.name} (${data.length} bytes), '
                  'saved as file #${file.id}.\r';
        _dispatchControl(message.trim(), call);
        final pending = link.sessionState['yappMessages'];
        if (pending is List<String>) {
          pending.add(message);
        } else {
          link.sessionState['yappMessages'] = <String>[message];
        }
      }
      // The sender only reads text again once its session is over.
      ..onReceiveSessionEnd = () {
        final messages = link.sessionState.remove('yappMessages');
        if (messages is List<String>) {
          _endTransfer(link, messages.join());
        }
      }
      ..onSendComplete = (name) {
        _dispatchControl('Sent file $name', call);
        _endTransfer(link, 'Transfer complete.\r');
      }
      ..onError = (message) {
        _dispatchControl('File transfer failed: $message', call);
        link.sessionState.remove('yappMessages');
        _endTransfer(link, 'File transfer failed: $message.\r');
      }
      ..enableAutoReceive();
    _yapps[link] = yapp;
  }

  void _startDownload(BbsLink session, BbsFile file) {
    final yapp = _yapps[session];
    final data = menu.files.read(file);
    if (yapp == null || data == null) {
      _endTransfer(session, 'File #${file.id} could not be read.\r');
      return;
    }
    _dispatchControl(
      'Sending file ${file.name} (${data.length} bytes)',
      session.remoteCallsign,
    );
    if (!yapp.sendFile(file.name, data)) {
      _endTransfer(session, 'A file transfer is already in progress.\r');
    }
  }

  /// Reports the end of a transfer, prompts, and runs the commands that
  /// arrived during it.
  void _endTransfer(BbsLink session, String message) {
    if (!enabled || _disposed || !_links.contains(session)) return;
    if (!session.isConnected) return;
    final queued = session.sessionState.remove('bbsQueue');
    _sessionSend(session, '$message${BbsMenu.prompt}');
    if (queued is List<String> && queued.isNotEmpty) {
      _processBbsLines(session, queued);
    }
  }

  // ---- Winlink mail server --------------------------------------------------

  void _processMailStream(BbsLink session, Uint8List data) {
    if (!enabled) return;

    // In relay mode, forward all data to the CMS gateway.
    final isRelayMode = session.sessionState['wlRelayMode'] == true;
    if (isRelayMode && (_cmsRelays[session]?.isConnected ?? false)) {
      _processMailStreamRelay(session, data);
      return;
    }

    // --- Local P2P mode (fallback) ---

    // Compressed mail blocks being received from the station.
    if (session.sessionState.containsKey('wlMailBinary')) {
      final blocks = session.sessionState['wlMailBinary'] as List<int>;
      blocks.addAll(data);
      _dispatchControl(
        'Receiving mail, ${blocks.length}${blocks.length < 2 ? " byte" : " bytes"}',
        session.remoteCallsign,
      );
      if (_extractMail(session, blocks)) {
        session.sessionState.remove('wlMailBinary');
        session.sessionState.remove('wlMailBlocks');
        session.sessionState.remove('wlMailProp');
        _sendProposals(session, false);
      }
      return;
    }

    final dataStr = utf8.decode(data, allowMalformed: true);
    final dataStrs = dataStr
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    for (final str in dataStrs) {
      if (str.isEmpty) continue;
      _dispatchTraffic(session.remoteCallsign, false, str.trim());

      String key = str.toUpperCase();
      String value = '';
      final i = str.indexOf(' ');
      if (i > 0) {
        key = str.substring(0, i).toUpperCase();
        value = str.substring(i + 1);
      }

      final winlinkPassword =
          _broker.getValue<String>(0, 'WinlinkPassword', '') ?? '';

      if (key == ';PR:' && winlinkPassword.isNotEmpty) {
        // Winlink authentication response.
        final challenge = session.sessionState['wlChallenge'] as String? ?? '';
        if (WinlinkSecurity.secureLoginResponse(challenge, winlinkPassword) ==
            value) {
          session.sessionState['wlAuth'] = 'OK';
          _dispatchControl('Authentication Success', session.remoteCallsign);
          _broker.logInfo('[BBS/$_deviceId] Winlink Auth Success');
        } else {
          _dispatchControl('Authentication Failed', session.remoteCallsign);
          _broker.logInfo('[BBS/$_deviceId] Winlink Auth Failed');
        }
      } else if (key == 'FC') {
        // Winlink mail proposal.
        final proposals =
            (session.sessionState['wlMailProp'] as List<String>?) ?? <String>[];
        proposals.add(value);
        session.sessionState['wlMailProp'] = proposals;
      } else if (key == 'F>') {
        // Proposals completed — respond with accept/reject for each.
        if (session.sessionState.containsKey('wlMailProp') &&
            !session.sessionState.containsKey('wlMailBinary')) {
          final proposals = session.sessionState['wlMailProp'] as List<String>;
          final proposals2 = <String>[];
          if (proposals.isNotEmpty) {
            int checksum = 0;
            for (final proposal in proposals) {
              final proposalBin = ascii.encode('FC $proposal\r');
              for (final b in proposalBin) {
                checksum += b;
              }
            }
            checksum = (-checksum) & 0xFF;
            if (_hex2(checksum) == value) {
              final response = StringBuffer();
              int acceptedProposalCount = 0;
              for (final proposal in proposals) {
                final proposalSplit = proposal.split(' ');
                if (proposalSplit.length >= 5 &&
                    proposalSplit[0] == 'EM' &&
                    proposalSplit[1].length == 12) {
                  final mFullLen = int.tryParse(proposalSplit[2]);
                  final mCompLen = int.tryParse(proposalSplit[3]);
                  final mUnknown = int.tryParse(proposalSplit[4]);
                  if (mFullLen != null &&
                      mCompLen != null &&
                      mUnknown != null) {
                    if (_weHaveEmail(proposalSplit[1])) {
                      response.write('N');
                    } else {
                      response.write('Y');
                      proposals2.add(proposal);
                      acceptedProposalCount++;
                    }
                  } else {
                    response.write('H');
                  }
                } else {
                  response.write('H');
                }
              }
              _sessionSend(session, 'FS $response\r');
              if (acceptedProposalCount > 0) {
                session.sessionState['wlMailBinary'] = <int>[];
                session.sessionState['wlMailProp'] = proposals2;
              }
            } else {
              _dispatchControl('Checksum Failed', session.remoteCallsign);
              session.disconnect();
            }
          }
        }
      } else if (key == 'FF') {
        // Station has no more mail for us — send ours back.
        _updateEmails(session);
        _sendProposals(session, true);
      } else if (key == 'FQ') {
        // Winlink session close.
        session.disconnect();
      } else if (key == 'FS') {
        // Station responded to our proposals — send the accepted mails.
        if (session.sessionState.containsKey('OutMails') &&
            session.sessionState.containsKey('OutMailBlocks')) {
          final proposedMails =
              session.sessionState['OutMails'] as List<WinLinkMail>;
          final proposedMailsBinary =
              session.sessionState['OutMailBlocks'] as List<List<Uint8List>>;
          session.sessionState['MailProposals'] = value;

          int sentMails = 0;
          final proposalResponses = _parseProposalResponses(value);
          if (proposalResponses.length == proposedMails.length) {
            int totalSize = 0;
            for (int j = 0; j < proposalResponses.length; j++) {
              if (proposalResponses[j] == 'Y') {
                sentMails++;
                for (final block in proposedMailsBinary[j]) {
                  session.send(block);
                  totalSize += block.length;
                }
              }
            }
            if (sentMails == 1) {
              _dispatchControl(
                'Sending mail, $totalSize bytes...',
                session.remoteCallsign,
              );
            } else if (sentMails > 1) {
              _dispatchControl(
                'Sending $sentMails mails, $totalSize bytes...',
                session.remoteCallsign,
              );
            } else {
              _updateEmails(session);
              _dispatchControl(
                'No emails to transfer.',
                session.remoteCallsign,
              );
              _sessionSend(session, 'FQ');
            }
          } else {
            _dispatchControl(
              'Incorrect proposal response.',
              session.remoteCallsign,
            );
            _sessionSend(session, 'FQ');
          }
        } else {
          _dispatchControl(
            'Unexpected proposal response.',
            session.remoteCallsign,
          );
          _sessionSend(session, 'FQ');
        }
      } else if (key == 'ECHO') {
        _sessionSend(session, '$value\r');
      }
    }
  }

  void _processMailStreamRelay(BbsLink session, Uint8List data) {
    if (!enabled) return;
    final relay = _cmsRelays[session];
    if (relay == null || !relay.isConnected) return;

    // Binary relay mode: forward raw bytes to CMS.
    if (session.sessionState['wlRelayBinary'] == true) {
      _broker.logInfo(
        '[BBS/$_deviceId] Radio->CMS (binary): ${data.length} bytes',
      );
      _dispatchControl(
        'Radio->Gateway: ${data.length} bytes (binary)',
        session.remoteCallsign,
      );
      relay.sendBinary(data);
      _updateStats(
        session.remoteCallsign,
        session.protocol,
        1,
        0,
        data.length,
        0,
      );
      return;
    }

    // Text mode: parse lines and forward to CMS.
    _dispatchControl(
      'Radio->Gateway: ${data.length} bytes',
      session.remoteCallsign,
    );
    final dataStr = utf8.decode(data, allowMalformed: true);
    final dataStrs = dataStr
        .replaceAll('\r\n', '\r')
        .replaceAll('\n', '\r')
        .split('\r');
    for (final str in dataStrs) {
      if (str.isEmpty) continue;
      _dispatchTraffic(session.remoteCallsign, false, str.trim());
      _broker.logInfo('[BBS/$_deviceId] Radio->CMS: $str');

      String key = str.toUpperCase();
      final i = str.indexOf(' ');
      if (i > 0) {
        key = str.substring(0, i).toUpperCase();
      }

      if (key == 'FS') {
        final value = i > 0 ? str.substring(i + 1) : '';
        if (value.toUpperCase().contains('Y')) {
          session.sessionState['wlRelayBinary'] = true;
          relay.binaryMode = true;
        }
      }
      if (key == 'FF') {
        session.sessionState['wlRelayBinary'] = false;
        relay.binaryMode = false;
      }
      if (key == 'FQ') {
        session.sessionState['wlRelayBinary'] = false;
        relay.binaryMode = false;
      }

      relay.sendLine(str);
    }
  }

  void _sendProposals(BbsLink session, bool lastExchange) {
    if (!enabled) return;

    final sb = StringBuffer();
    final proposedMails = <WinLinkMail>[];
    final proposedMailsBinary = <List<Uint8List>>[];
    int checksum = 0;
    int mailSendCount = 0;

    String connectedCallsign = session.remoteAddress;

    final mailStore = DataBroker.getDataHandler<MailStore>('MailStore');
    final mails = mailStore?.getAllMails() ?? <WinLinkMail>[];

    for (final mail in mails) {
      if (mail.mailbox != 'Outbox' ||
          mail.mid == null ||
          mail.mid!.length != 12) {
        continue;
      }
      final isForStation = WinLinkMail.isMailForStation(
        connectedCallsign,
        mail.to,
        mail.cc,
        onOthers: (_) {},
      );
      if (!isForStation) continue;

      final enc = WinLinkMail.encodeMailToBlocks(mail);
      final blocks = enc.blocks;
      if (blocks != null) {
        proposedMails.add(mail);
        proposedMailsBinary.add(blocks);
        final proposal =
            'FC EM ${mail.mid} ${enc.uncompressedSize} ${enc.compressedSize} 0\r';
        sb.write(proposal);
        final proposalBin = ascii.encode(proposal);
        for (final b in proposalBin) {
          checksum += b;
        }
        mailSendCount++;
        _broker.logInfo(
          '[BBS/$_deviceId] Proposing mail ${mail.mid} for ${mail.to} to $connectedCallsign',
        );
      }
    }

    if (mailSendCount > 0) {
      checksum = (-checksum) & 0xFF;
      sb.write('F> ${_hex2(checksum)}\r');
      session.sessionState['OutMails'] = proposedMails;
      session.sessionState['OutMailBlocks'] = proposedMailsBinary;
      _broker.logInfo(
        '[BBS/$_deviceId] Proposing $mailSendCount mail(s) to $connectedCallsign, checksum: ${_hex2(checksum)}',
      );
    } else {
      sb.write(lastExchange ? 'FQ\r' : 'FF\r');
    }
    _sessionSend(session, sb.toString());
  }

  List<String> _parseProposalResponses(String value) {
    value = value
        .toUpperCase()
        .replaceAll('+', 'Y')
        .replaceAll('R', 'N')
        .replaceAll('-', 'N')
        .replaceAll('=', 'L')
        .replaceAll('H', 'L')
        .replaceAll('!', 'A');
    final responses = <String>[];
    String r = '';
    for (int i = 0; i < value.length; i++) {
      final c = value[i];
      if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) {
        if (r.isNotEmpty) r += c;
      } else {
        if (r.isNotEmpty) {
          responses.add(r);
          r = '';
        }
        r += c;
      }
    }
    if (r.isNotEmpty) responses.add(r);
    return responses;
  }

  bool _extractMail(BbsLink session, List<int> blocks) {
    if (!session.sessionState.containsKey('wlMailProp')) return false;
    final proposals = session.sessionState['wlMailProp'] as List<String>?;
    if (proposals == null) return false;
    if (proposals.isEmpty || blocks.isEmpty) return true;

    // Decode the proposal.
    final proposalSplit = proposals[0].split(' ');
    if (proposalSplit.length < 4) return true; // Invalid proposal format.
    final mid = proposalSplit[1];

    final result = WinLinkMail.decodeBlocksToEmail(Uint8List.fromList(blocks));
    if (result.fail) {
      _dispatchControl('Failed to decode mail.', session.remoteCallsign);
      _broker.logError('[BBS/$_deviceId] Failed to decode mail $mid');
      return true;
    }
    final mail = result.mail;
    if (mail == null) return false;

    final dataConsumed = result.dataConsumed;
    if (dataConsumed > 0) {
      if (dataConsumed >= blocks.length) {
        blocks.clear();
      } else {
        blocks.removeRange(0, dataConsumed);
      }
    }
    proposals.removeAt(0);

    // Decide which mailbox to file the message under.
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final isForUs = WinLinkMail.isMailForStation(
      callsign,
      mail.to,
      mail.cc,
      onOthers: (_) {},
    );
    mail.mailbox = isForUs ? 'Inbox' : 'Outbox';

    _broker.dispatch(deviceId: 0, name: 'MailAdd', data: mail, store: false);
    if (isForUs) {
      NotificationService.instance.showMessage(
        title: (mail.from != null && mail.from!.isNotEmpty)
            ? 'Winlink mail from ${mail.from}'
            : 'New Winlink mail',
        body: (mail.subject != null && mail.subject!.isNotEmpty)
            ? mail.subject!
            : 'You have new mail.',
        payload: 'mail',
      );
    }
    _dispatchControl('Got mail for ${mail.to}.', session.remoteCallsign);
    _broker.logInfo(
      '[BBS/$_deviceId] Received mail ${mail.mid} for ${mail.to}',
    );

    return proposals.isEmpty;
  }

  bool _weHaveEmail(String mid) {
    final mailStore = DataBroker.getDataHandler<MailStore>('MailStore');
    return mailStore?.mailExists(mid) ?? false;
  }

  void _updateEmails(BbsLink session) {
    if (!enabled) return;

    if (session.sessionState.containsKey('OutMails') &&
        session.sessionState.containsKey('OutMailBlocks') &&
        session.sessionState.containsKey('MailProposals')) {
      final proposedMails =
          session.sessionState['OutMails'] as List<WinLinkMail>;
      final proposalResponses = _parseProposalResponses(
        session.sessionState['MailProposals'] as String,
      );

      int mailsChanges = 0;
      if (proposalResponses.length == proposedMails.length) {
        for (int j = 0; j < proposalResponses.length; j++) {
          if (proposalResponses[j] == 'Y' || proposalResponses[j] == 'N') {
            proposedMails[j].mailbox = 'Sent';
            // TODO: Persist the mailbox change via the broker when supported.
            mailsChanges++;
          }
        }
      }

      if (mailsChanges > 0) {
        _broker.dispatch(
          deviceId: 0,
          name: 'BbsMailUpdated',
          data: {'deviceId': _deviceId, 'mailChanges': mailsChanges},
          store: false,
        );
      }
    }
  }

  static String _hex2(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(2, '0');

  /// Disposes this BBS instance, tearing down the session and any relay.
  void dispose() {
    if (_disposed) return;
    enabled = false;
    _disposed = true;
    _broker.logInfo('[BBS/$_deviceId] BBS handler disposing');

    _broker.dispose();
  }
}

// ---------------------------------------------------------------------------
// BbsHandler: manager (device 1)
// ---------------------------------------------------------------------------

/// A data handler that manages BBS instances for radios.
///
/// Listens for BBS control commands on device 1 and creates/removes [Bbs]
/// instances for specific radios, locking each radio to a dedicated channel
/// while its BBS is active. Also aggregates station statistics from all BBS
/// instances into a merged table broadcast as `BbsMergedStats`.
class BbsHandler {
  static const int _bbsDeviceId = 1;

  final DataBrokerClient _broker = DataBrokerClient();
  final Map<int, Bbs> _bbsInstances = {};
  final Map<String, MergedStationStats> _mergedStats = {};
  bool _disposed = false;

  bool get isDisposed => _disposed;
  int get activeBbsCount => _bbsInstances.length;

  /// Initializes the handler and subscribes to broker events.
  void init() {
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'CreateBbs',
      callback: _onCreateBbs,
    );
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'RemoveBbs',
      callback: _onRemoveBbs,
    );
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'GetBbsStatus',
      callback: _onGetBbsStatus,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'State',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'BbsStatsUpdated',
      callback: _onBbsStatsUpdated,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'BbsStatsCleared',
      callback: _onBbsStatsCleared,
    );
    _broker.subscribe(
      deviceId: _bbsDeviceId,
      name: 'BbsClearAllStats',
      callback: _onBbsClearAllStats,
    );

    _broker.logInfo('[BbsHandler] BBS Handler initialized');
  }

  // ---- create / remove ------------------------------------------------------

  void _onCreateBbs(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! CreateBbsData) return;

    final radioDeviceId = data.radioDeviceId;
    final channelId = data.channelId;
    final regionId = data.regionId;

    if (_bbsInstances.containsKey(radioDeviceId)) {
      _broker.logError(
        '[BbsHandler] BBS instance already exists for radio $radioDeviceId',
      );
      _broker.dispatch(
        deviceId: _bbsDeviceId,
        name: 'BbsCreateFailed',
        data: BbsErrorData(
          radioDeviceId: radioDeviceId,
          error: 'BBS instance already exists for this radio',
        ),
        store: false,
      );
      return;
    }

    // Lock the radio for BBS usage.
    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'SetLock',
      data: SetLockData(usage: 'BBS', regionId: regionId, channelId: channelId),
      store: false,
    );

    final bbsInstance = Bbs(
      radioDeviceId,
      channelId: channelId,
      regionId: regionId,
    );
    bbsInstance.enabled = true;
    _bbsInstances[radioDeviceId] = bbsInstance;

    _broker.logInfo(
      '[BbsHandler] Created BBS instance for radio $radioDeviceId on channel $channelId, region $regionId',
    );

    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsCreated',
      data: BbsStatusData(
        radioDeviceId: radioDeviceId,
        channelId: channelId,
        regionId: regionId,
        enabled: true,
      ),
      store: false,
    );

    _dispatchBbsList();
  }

  void _onRemoveBbs(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! RemoveBbsData) return;

    final radioDeviceId = data.radioDeviceId;
    final bbsInstance = _bbsInstances[radioDeviceId];
    if (bbsInstance == null) {
      _broker.logError(
        '[BbsHandler] No BBS instance exists for radio $radioDeviceId',
      );
      _broker.dispatch(
        deviceId: _bbsDeviceId,
        name: 'BbsRemoveFailed',
        data: BbsErrorData(
          radioDeviceId: radioDeviceId,
          error: 'No BBS instance exists for this radio',
        ),
        store: false,
      );
      return;
    }

    bbsInstance.enabled = false;
    bbsInstance.dispose();
    _bbsInstances.remove(radioDeviceId);

    _broker.logInfo(
      '[BbsHandler] Removed BBS instance for radio $radioDeviceId',
    );

    // Unlock the radio.
    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'SetUnlock',
      data: SetUnlockData(usage: 'BBS'),
      store: false,
    );

    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsRemoved',
      data: BbsRemovedData(radioDeviceId: radioDeviceId),
      store: false,
    );

    _dispatchBbsList();
  }

  void _onGetBbsStatus(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _dispatchBbsList();
  }

  // ---- statistics aggregation ----------------------------------------------

  void _onBbsStatsUpdated(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! BbsStatsUpdatedData) return;

    final stats = data.stats;
    final sourceDeviceId = data.deviceId;
    if (stats.callsign.isEmpty) return;

    final key = stats.callsign.toUpperCase();
    var mergedStats = _mergedStats[key];
    if (mergedStats != null) {
      if (stats.lastseen.isAfter(mergedStats.lastSeen)) {
        mergedStats.lastSeen = stats.lastseen;
      }
      mergedStats.protocol = stats.protocol;
      final deviceStats = mergedStats.deviceStats[sourceDeviceId] ??=
          DeviceStationStats();
      deviceStats.packetsIn = stats.packetsIn;
      deviceStats.packetsOut = stats.packetsOut;
      deviceStats.bytesIn = stats.bytesIn;
      deviceStats.bytesOut = stats.bytesOut;
      _recalculateTotals(mergedStats);
    } else {
      mergedStats = MergedStationStats()
        ..callsign = stats.callsign
        ..lastSeen = stats.lastseen
        ..protocol = stats.protocol;
      mergedStats.deviceStats[sourceDeviceId] = DeviceStationStats()
        ..packetsIn = stats.packetsIn
        ..packetsOut = stats.packetsOut
        ..bytesIn = stats.bytesIn
        ..bytesOut = stats.bytesOut;
      _recalculateTotals(mergedStats);
      _mergedStats[key] = mergedStats;
    }

    _dispatchMergedStats();
  }

  void _recalculateTotals(MergedStationStats mergedStats) {
    mergedStats.totalPacketsIn = 0;
    mergedStats.totalPacketsOut = 0;
    mergedStats.totalBytesIn = 0;
    mergedStats.totalBytesOut = 0;
    for (final deviceStats in mergedStats.deviceStats.values) {
      mergedStats.totalPacketsIn += deviceStats.packetsIn;
      mergedStats.totalPacketsOut += deviceStats.packetsOut;
      mergedStats.totalBytesIn += deviceStats.bytesIn;
      mergedStats.totalBytesOut += deviceStats.bytesOut;
    }
  }

  void _onBbsStatsCleared(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! BbsStatsClearedData) return;

    final sourceDeviceId = data.deviceId;
    final keysToRemove = <String>[];
    _mergedStats.forEach((key, value) {
      if (value.deviceStats.containsKey(sourceDeviceId)) {
        value.deviceStats.remove(sourceDeviceId);
        if (value.deviceStats.isEmpty) {
          keysToRemove.add(key);
        } else {
          _recalculateTotals(value);
        }
      }
    });
    for (final key in keysToRemove) {
      _mergedStats.remove(key);
    }

    _dispatchMergedStats();
  }

  void _onBbsClearAllStats(int deviceId, String name, Object? data) {
    if (_disposed) return;

    _mergedStats.clear();
    for (final bbs in _bbsInstances.values) {
      bbs.clearStats();
    }

    _dispatchMergedStats();
  }

  void _dispatchMergedStats() {
    final statsList = List<MergedStationStats>.from(_mergedStats.values);
    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsMergedStats',
      data: statsList,
      store: true,
    );
  }

  // ---- radio lifecycle ------------------------------------------------------

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! String) return;
    if (data != 'Disconnected') return;

    final bbsInstance = _bbsInstances[deviceId];
    if (bbsInstance != null) {
      _broker.logInfo(
        '[BbsHandler] Radio $deviceId disconnected, removing BBS instance',
      );
      bbsInstance.enabled = false;
      bbsInstance.dispose();
      _bbsInstances.remove(deviceId);

      _broker.dispatch(
        deviceId: _bbsDeviceId,
        name: 'BbsRemoved',
        data: BbsRemovedData(radioDeviceId: deviceId),
        store: false,
      );

      _dispatchBbsList();
    }
  }

  void _dispatchBbsList() {
    final bbsList = <BbsStatusData>[];
    _bbsInstances.forEach((radioDeviceId, bbs) {
      bbsList.add(
        BbsStatusData(
          radioDeviceId: radioDeviceId,
          channelId: bbs.channelId,
          regionId: bbs.regionId,
          enabled: bbs.enabled,
        ),
      );
    });
    _broker.dispatch(
      deviceId: _bbsDeviceId,
      name: 'BbsList',
      data: bbsList,
      store: true,
    );
  }

  /// Returns the BBS instance for [radioDeviceId], or null if none is active.
  Bbs? getBbsInstance(int radioDeviceId) => _bbsInstances[radioDeviceId];

  /// Returns the list of radio device IDs that currently have a BBS instance.
  List<int> getActiveBbsRadioIds() => List<int>.from(_bbsInstances.keys);

  /// Disposes the handler, cleaning up all BBS instances and unlocking radios.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _broker.logInfo('[BbsHandler] BBS Handler disposing');

    _bbsInstances.forEach((radioDeviceId, bbs) {
      bbs.enabled = false;
      bbs.dispose();
      _broker.dispatch(
        deviceId: radioDeviceId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: 'BBS'),
        store: false,
      );
    });
    _bbsInstances.clear();

    _broker.dispose();
  }
}
