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

import 'package:sqflite/sqflite.dart';

import '../../aprsis/aprsis_history_store.dart' show AprsIsHistoryRecord;

/// Persists internet-gated (APRS-IS) message history (`aprsis_history`), kept
/// separate from the RF packet store just like the old `aprsis_history.txt`.
class AprsisDao {
  AprsisDao(this._db);

  final Database _db;

  static const String _table = 'aprsis_history';

  /// Appends one internet APRS record. The raw TNC2 line is kept on one logical
  /// field; newlines/tabs are collapsed to spaces for parity with the old file.
  Future<void> insert(DateTime time, String tnc2Line) async {
    final clean = tnc2Line
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\t', ' ');
    if (clean.isEmpty) return;
    await _db.insert(_table, <String, Object?>{
      'time_us': time.microsecondsSinceEpoch,
      'tnc2': clean,
    });
  }

  /// Batch-inserts records in a single transaction (used by legacy import).
  Future<void> importAll(List<AprsIsHistoryRecord> records) async {
    if (records.isEmpty) return;
    final batch = _db.batch();
    for (final record in records) {
      final clean = record.tnc2Line
          .replaceAll('\r', ' ')
          .replaceAll('\n', ' ')
          .replaceAll('\t', ' ');
      if (clean.isEmpty) continue;
      batch.insert(_table, <String, Object?>{
        'time_us': record.time.microsecondsSinceEpoch,
        'tnc2': clean,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Returns the most recent [limit] records in chronological order (oldest
  /// first).
  Future<List<AprsIsHistoryRecord>> recent(int limit) async {
    final rows = await _db.query(
      _table,
      orderBy: 'time_us DESC, id DESC',
      limit: limit,
    );
    return rows.reversed
        .map(
          (row) => AprsIsHistoryRecord(
            DateTime.fromMicrosecondsSinceEpoch(row['time_us'] as int? ?? 0),
            row['tnc2'] as String? ?? '',
          ),
        )
        .toList(growable: false);
  }

  /// Deletes all internet APRS history.
  Future<void> clear() async {
    await _db.delete(_table);
  }

  /// Keeps only the newest [maxEntries] records. A value <= 0 means unlimited.
  Future<void> enforceLimit(int maxEntries) async {
    if (maxEntries <= 0) return;
    await _db.rawDelete(
      'DELETE FROM $_table WHERE id NOT IN '
      '(SELECT id FROM $_table ORDER BY time_us DESC, id DESC LIMIT ?)',
      [maxEntries],
    );
  }
}
