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

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../handlers/comms_handler.dart' show DecodedTextEntry;

/// Persists Comms tab decoded-text / APRS message history (`comms_events`).
class CommsDao {
  CommsDao(this._db);

  final Database _db;

  static const String _table = 'comms_events';

  /// Appends one history entry.
  Future<void> insert(DecodedTextEntry entry) async {
    await _db.insert(_table, _toRow(entry));
  }

  /// Batch-inserts entries in a single transaction (used by legacy import).
  Future<void> importAll(List<DecodedTextEntry> entries) async {
    if (entries.isEmpty) return;
    final batch = _db.batch();
    for (final entry in entries) {
      batch.insert(_table, _toRow(entry));
    }
    await batch.commit(noResult: true);
  }

  /// Returns the most recent [limit] entries in chronological order (oldest
  /// first), matching the order the flat-file store returned.
  Future<List<DecodedTextEntry>> recent(int limit) async {
    final rows = await _db.query(
      _table,
      orderBy: 'time_ms DESC, id DESC',
      limit: limit,
    );
    return rows.reversed.map(_fromRow).toList(growable: false);
  }

  /// Deletes all history.
  Future<void> clear() async {
    await _db.delete(_table);
  }

  /// Returns the total number of stored entries.
  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM $_table');
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Enforces retention caps. A value <= 0 means unlimited for that category.
  /// [maxAprs] limits entries with encoding `APRS`; [maxTotal] limits all
  /// entries. Runs as indexed DELETEs instead of rewriting a whole file.
  Future<void> enforceLimits({
    required int maxTotal,
    required int maxAprs,
  }) async {
    if (maxAprs > 0) {
      await _db.rawDelete(
        "DELETE FROM $_table WHERE encoding = 'APRS' AND id NOT IN "
        "(SELECT id FROM $_table WHERE encoding = 'APRS' "
        "ORDER BY time_ms DESC, id DESC LIMIT ?)",
        [maxAprs],
      );
    }
    if (maxTotal > 0) {
      await _db.rawDelete(
        'DELETE FROM $_table WHERE id NOT IN '
        '(SELECT id FROM $_table ORDER BY time_ms DESC, id DESC LIMIT ?)',
        [maxTotal],
      );
    }
  }

  static Map<String, Object?> _toRow(DecodedTextEntry entry) {
    final j = entry.toJson();
    final sarsat = j['sarsat'];
    final radiosonde = j['radiosonde'];
    return <String, Object?>{
      'time_ms': j['time'],
      'encoding': j['encoding'],
      'channel': j['channel'],
      'is_received': (j['isReceived'] as bool? ?? true) ? 1 : 0,
      'text': j['text'],
      'source': j['source'],
      'destination': j['destination'],
      'lat': j['latitude'],
      'lon': j['longitude'],
      'filename': j['filename'],
      'duration': j['duration'],
      'wpm': j['wpm'],
      'key_type': j['keyType'],
      'sarsat_json': sarsat == null ? null : jsonEncode(sarsat),
      'radiosonde_json': radiosonde == null ? null : jsonEncode(radiosonde),
    };
  }

  static DecodedTextEntry _fromRow(Map<String, Object?> row) {
    final sarsat = row['sarsat_json'] as String?;
    final radiosonde = row['radiosonde_json'] as String?;
    return DecodedTextEntry.fromJson(<String, dynamic>{
      'text': row['text'],
      'channel': row['channel'],
      'time': row['time_ms'],
      'isReceived': (row['is_received'] as int? ?? 1) != 0,
      'encoding': row['encoding'],
      'source': row['source'],
      'destination': row['destination'],
      'latitude': row['lat'],
      'longitude': row['lon'],
      'filename': row['filename'],
      'duration': row['duration'],
      'wpm': row['wpm'],
      'keyType': row['key_type'],
      'sarsat': sarsat == null ? null : jsonDecode(sarsat),
      'radiosonde': radiosonde == null ? null : jsonDecode(radiosonde),
    });
  }
}
