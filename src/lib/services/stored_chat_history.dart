// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';

import '../aprs/aprs_conversation.dart';
import '../aprs/aprs_packet.dart';
import 'data_broker_client.dart';
import 'db/app_database.dart';

/// Serves bounded archive pages to the main window and detached tabs.
class StoredChatHistory {
  final DataBrokerClient _broker = DataBrokerClient();

  void init() {
    _broker.subscribe(
      deviceId: 1,
      name: 'RequestStoredChatHistory',
      callback: (_, _, data) => unawaited(_request(data)),
    );
    _broker.dispatch(
      deviceId: 1,
      name: 'StoredChatHistoryAvailable',
      data: AppDatabase.instance != null,
    );
  }

  Future<void> _request(Object? data) async {
    final response = await page(data);
    _broker.dispatch(
      deviceId: 1,
      name: 'StoredChatHistoryPage',
      data: response,
      store: false,
    );
  }

  Future<Map<String, Object?>> page(Object? data) async {
    if (data is! Map || data['requestId'] is! String) {
      _broker.logError('Stored chat history: invalid page request');
      return {'error': 'Invalid history page request'};
    }
    final requestId = data['requestId'] as String;
    try {
      final db = AppDatabase.instance;
      if (db == null) throw StateError('Stored chat history is unavailable');
      final raw = data['before'];
      List<int>? before;
      if (raw != null) {
        if (raw is! List || raw.length != 2 || raw.any((v) => v is! int)) {
          throw ArgumentError('Invalid history cursor');
        }
        before = raw.cast<int>();
      }
      final peer = data['peer'];
      if (peer != null && (peer is! String || peer.trim().isEmpty)) {
        throw ArgumentError('Invalid APRS conversation');
      }
      final peerKey = peer is String ? aprsPeerKey(peer) : null;
      final local = AprsLocalStation.fromSettings(
        _broker.getValue<String>(0, 'CallSign', '') ?? '',
        _broker.getValue<int>(0, 'StationId', 0) ?? 0,
      );
      bool matchesPeer(Map<String, Object?> json) {
        if (json['invalid'] == true) return false;
        final aprs = AprsPacket.fromJson(Map<String, dynamic>.from(json));
        final packet = aprs.packet;
        if (packet == null) return false;
        final outgoing =
            !packet.incoming ||
            (aprs.fromAprsIs &&
                local.callsign.isNotEmpty &&
                aprsPeerKey(aprs.sourceCallsignWithId) ==
                    aprsPeerKey(local.callsignWithId));
        return aprsPacketConversationPeer(
              aprs,
              outgoing: outgoing,
              local: local,
            ) ==
            peerKey;
      }

      final Map<String, Object?> page;
      switch (data['source']) {
        case 'comms':
          page = await db.comms.page(before: before);
        case 'rf':
          page = await db.packets.page(
            before: before,
            matches: peer == null ? null : matchesPeer,
          );
        case 'internet':
          page = await db.aprsis.page(
            before: before,
            matches: peer == null ? null : matchesPeer,
          );
        default:
          throw ArgumentError('Invalid history source');
      }
      return {'requestId': requestId, ...page};
    } catch (error) {
      _broker.logError('Stored chat history: $error');
      return {'requestId': requestId, 'error': '$error'};
    }
  }

  void dispose() => _broker.dispose();
}
