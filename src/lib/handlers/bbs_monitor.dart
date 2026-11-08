/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Live view of BBS sessions for the BBS tab. Host process only.

Every BBS (radio AX.25 / XARA, the terminal's local BBS, and the HTTP BBS)
reports its sessions here with [BbsMonitor.sessionStarted] / [sessionEnded].
The monitor also records the BBS traffic, control and error events into a
bounded history. Everything is published as plain maps so detached windows
receive them too (DataBroker device 1):
  BbsActiveSessions   (stored)  list of session maps, see [BbsSessionInfo]
  BbsTrafficEntry               one recorded entry map (with a `seq` number)
  RequestBbsTraffic   ->        BbsTrafficHistory: list of recorded entries

A session is identified by its BBS device id and the station callsign
([sessionKey]); a station connected twice to the same BBS (e.g. two browser
tabs) counts as one session.
*/

import '../services/data_broker_client.dart';
import 'bbs_handler.dart';

/// The key of the session of [callsign] on the BBS of [deviceId].
String sessionKey(int deviceId, String callsign) =>
    '$deviceId|${callsign.trim().toUpperCase()}';

/// An active BBS session.
class BbsSessionInfo {
  const BbsSessionInfo({
    required this.deviceId,
    required this.callsign,
    required this.protocol,
    required this.since,
  });

  /// The BBS: a radio device id, 205 for the terminal's local BBS, 0 for web.
  final int deviceId;
  final String callsign;

  /// How the station is connected ("AX.25", "XARA", "Local", "Web"...).
  final String protocol;
  final DateTime since;

  String get key => sessionKey(deviceId, callsign);

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'callsign': callsign,
    'protocol': protocol,
    'since': since.millisecondsSinceEpoch,
  };

  static BbsSessionInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final deviceId = json['deviceId'];
    final callsign = json['callsign'];
    if (deviceId is! int || callsign is! String) return null;
    return BbsSessionInfo(
      deviceId: deviceId,
      callsign: callsign,
      protocol: json['protocol'] as String? ?? '',
      since: DateTime.fromMillisecondsSinceEpoch(
        (json['since'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Kind of a recorded traffic entry.
enum BbsTrafficKind { traffic, control, error }

/// A recorded line of BBS traffic.
class BbsTrafficRecord {
  const BbsTrafficRecord({
    required this.seq,
    required this.kind,
    required this.deviceId,
    required this.callsign,
    required this.message,
    this.outgoing = false,
  });

  /// Increasing number used to merge the history with live entries.
  final int seq;
  final BbsTrafficKind kind;
  final int deviceId;

  /// Station the line belongs to; empty for BBS-wide messages.
  final String callsign;
  final String message;
  final bool outgoing;

  /// The session this line belongs to, or null for BBS-wide messages.
  String? get key => callsign.isEmpty ? null : sessionKey(deviceId, callsign);

  Map<String, Object?> toJson() => {
    'seq': seq,
    'kind': kind.name,
    'deviceId': deviceId,
    'callsign': callsign,
    'message': message,
    'outgoing': outgoing,
  };

  static BbsTrafficRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final seq = json['seq'];
    final deviceId = json['deviceId'];
    if (seq is! int || deviceId is! int) return null;
    return BbsTrafficRecord(
      seq: seq,
      kind: BbsTrafficKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => BbsTrafficKind.traffic,
      ),
      deviceId: deviceId,
      callsign: json['callsign'] as String? ?? '',
      message: json['message'] as String? ?? '',
      outgoing: json['outgoing'] == true,
    );
  }
}

/// Tracks BBS sessions and traffic for the BBS tab.
class BbsMonitor {
  /// The monitor used by every BBS. Replaceable in tests.
  static BbsMonitor instance = BbsMonitor();

  /// Most recorded entries kept for views opened later.
  static const int maxHistory = 2000;

  final Map<String, BbsSessionInfo> _sessions = {};

  /// Connections per session key (one station may connect more than once).
  final Map<String, int> _connections = {};
  final List<BbsTrafficRecord> _history = [];
  int _seq = 0;
  DataBrokerClient? _broker;

  DataBrokerClient get _client => _broker ??= DataBrokerClient();

  /// The active sessions, in the order they started.
  List<BbsSessionInfo> get sessions => List.unmodifiable(_sessions.values);

  /// The recorded entries, oldest first.
  List<BbsTrafficRecord> get history => List.unmodifiable(_history);

  /// Starts recording traffic and answering history requests.
  void init() {
    final broker = _client;
    broker.subscribe(
      deviceId: 0,
      name: 'BbsTraffic',
      callback: (_, _, data) {
        if (data is BbsTrafficData) {
          _record(
            BbsTrafficKind.traffic,
            data.deviceId,
            data.callsign,
            data.message,
            outgoing: data.outgoing,
          );
        }
      },
    );
    broker.subscribe(
      deviceId: 0,
      name: 'BbsControlMessage',
      callback: (_, _, data) {
        if (data is BbsControlMessageData) {
          _record(
            BbsTrafficKind.control,
            data.deviceId,
            data.callsign,
            data.message,
          );
        }
      },
    );
    broker.subscribe(
      deviceId: 0,
      name: 'BbsError',
      callback: (_, _, data) {
        if (data is BbsErrorEventData) {
          _record(
            BbsTrafficKind.error,
            data.deviceId,
            data.callsign,
            data.error,
          );
        }
      },
    );
    broker.subscribe(
      deviceId: 1,
      name: 'RequestBbsTraffic',
      callback: (_, _, _) => broker.dispatch(
        deviceId: 1,
        name: 'BbsTrafficHistory',
        data: [for (final r in _history) r.toJson()],
        store: false,
      ),
    );
    broker.subscribe(
      deviceId: 1,
      name: 'ClearBbsTraffic',
      callback: (_, _, _) => _history.clear(),
    );
    _publishSessions();
  }

  void dispose() {
    _broker?.dispose();
    _broker = null;
  }

  /// Records that [callsign] connected to the BBS of [deviceId].
  void sessionStarted(int deviceId, String callsign, String protocol) {
    final call = callsign.trim().toUpperCase();
    if (call.isEmpty) return;
    final key = sessionKey(deviceId, call);
    _connections[key] = (_connections[key] ?? 0) + 1;
    if (_sessions.containsKey(key)) return;
    _sessions[key] = BbsSessionInfo(
      deviceId: deviceId,
      callsign: call,
      protocol: protocol,
      since: DateTime.now(),
    );
    _publishSessions();
  }

  /// Records that a connection of [callsign] to the BBS of [deviceId] ended.
  void sessionEnded(int deviceId, String callsign) {
    final key = sessionKey(deviceId, callsign);
    final left = (_connections[key] ?? 0) - 1;
    if (left > 0) {
      _connections[key] = left;
      return;
    }
    _connections.remove(key);
    if (_sessions.remove(key) != null) _publishSessions();
  }

  void _record(
    BbsTrafficKind kind,
    int deviceId,
    String callsign,
    String message, {
    bool outgoing = false,
  }) {
    final record = BbsTrafficRecord(
      seq: ++_seq,
      kind: kind,
      deviceId: deviceId,
      callsign: callsign.trim().toUpperCase(),
      message: message,
      outgoing: outgoing,
    );
    _history.add(record);
    if (_history.length > maxHistory) {
      _history.removeRange(0, _history.length - maxHistory);
    }
    _client.dispatch(
      deviceId: 1,
      name: 'BbsTrafficEntry',
      data: record.toJson(),
      store: false,
    );
  }

  void _publishSessions() {
    _client.dispatch(
      deviceId: 1,
      name: 'BbsActiveSessions',
      data: [for (final s in _sessions.values) s.toJson()],
    );
  }
}
