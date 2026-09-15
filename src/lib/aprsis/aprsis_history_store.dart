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
// aprsis_history_store.dart - Persists APRS-IS (internet-gated) messages in the
// shared SQLite database, kept separate from the RF packet store so the two
// sources stay unmixed. Each received packet is one row; the most recent
// [_maxEntries] are loaded on startup. No-op on the web (no database).
//

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/db/app_database.dart';

/// One persisted APRS-IS record: the receive time and the raw TNC2 line.
class AprsIsHistoryRecord {
  final DateTime time;
  final String tnc2Line;

  const AprsIsHistoryRecord(this.time, this.tnc2Line);
}

/// Persists APRS-IS messages to the `aprsis_history` table, appending one row
/// per message. Retention is enforced by [HistoryLimiter] via indexed deletes.
class AprsIsHistoryStore {
  /// Maximum number of records returned on load.
  static const int _maxEntries = 1000;

  /// Opens the store and returns the most recent [_maxEntries] records in the
  /// order they were written (oldest first). Returns an empty list on web (no
  /// database) or on any error.
  Future<List<AprsIsHistoryRecord>> init() async {
    final dao = AppDatabase.instance?.aprsis;
    if (dao == null) return const [];
    try {
      return await dao.recent(_maxEntries);
    } catch (e) {
      debugPrint('AprsIsHistoryStore: init failed: $e');
      return const [];
    }
  }

  /// Appends one record. Fire-and-forget; the row is durably committed by WAL.
  /// No-op when persistence is unavailable (web / error).
  void append(DateTime time, String tnc2Line) {
    final dao = AppDatabase.instance?.aprsis;
    if (dao == null) return;
    unawaited(
      dao
          .insert(time, tnc2Line)
          .catchError(
            (Object e) => debugPrint('AprsIsHistoryStore: append failed: $e'),
          ),
    );
  }

  /// Deletes all persisted records so cleared internet history cannot reload on
  /// the next launch. Safe when persistence is unavailable (web / error).
  void clear() {
    final dao = AppDatabase.instance?.aprsis;
    if (dao == null) return;
    unawaited(
      dao.clear().catchError(
        (Object e) => debugPrint('AprsIsHistoryStore: clear failed: $e'),
      ),
    );
  }
}
