// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';

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
      final Map<String, Object?> page;
      switch (data['source']) {
        case 'comms':
          page = await db.comms.page(before: before);
        case 'rf':
          page = await db.packets.page(before: before);
        case 'internet':
          page = await db.aprsis.page(before: before);
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
