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

/// Persists the BBS message board (`bbs_board`) and the log of stations that
/// connected to the BBS (`bbs_visits`, one row per station).
///
/// Rows are exchanged as plain maps so callers (see `BbsStore`) do not import
/// this file, which keeps sqflite out of the web bundle.
class BbsDao {
  BbsDao(this._db);

  final Database _db;

  static const String _board = 'bbs_board';
  static const String _visits = 'bbs_visits';

  static Future<void> createSchema(DatabaseExecutor db) async {
    // AUTOINCREMENT so message numbers are never reused after a delete.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_board (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time_ms INTEGER NOT NULL,
        callsign TEXT NOT NULL,
        text TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_visits (
        callsign TEXT PRIMARY KEY,
        first_ms INTEGER NOT NULL,
        last_ms INTEGER NOT NULL,
        protocol TEXT NOT NULL,
        count INTEGER NOT NULL
      )
    ''');
  }

  /// All board messages (`id`, `time_ms`, `callsign`, `text`), oldest first.
  Future<List<Map<String, Object?>>> boardMessages() =>
      _db.query(_board, orderBy: 'id ASC');

  /// The highest message number ever assigned, including deleted messages.
  Future<int> lastBoardId() async {
    final rows = await _db.rawQuery(
      'SELECT seq FROM sqlite_sequence WHERE name = ?',
      [_board],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['seq'] as num?)?.toInt() ?? 0;
  }

  Future<void> insertBoardMessage(
    int id,
    int timeMs,
    String callsign,
    String text,
  ) async {
    await _db.insert(_board, {
      'id': id,
      'time_ms': timeMs,
      'callsign': callsign,
      'text': text,
    });
  }

  Future<void> deleteBoardMessage(int id) async {
    await _db.delete(_board, where: 'id = ?', whereArgs: [id]);
  }

  /// Every logged station (`callsign`, `first_ms`, `last_ms`, `protocol`,
  /// `count`), most recent visit first. A replaced row gets a new rowid, which
  /// orders visits made within the same millisecond.
  Future<List<Map<String, Object?>>> visits() =>
      _db.query(_visits, orderBy: 'last_ms DESC, rowid DESC');

  Future<void> upsertVisit(
    String callsign,
    int firstMs,
    int lastMs,
    String protocol,
    int count,
  ) async {
    await _db.insert(_visits, {
      'callsign': callsign,
      'first_ms': firstMs,
      'last_ms': lastMs,
      'protocol': protocol,
      'count': count,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteVisit(String callsign) async {
    await _db.delete(_visits, where: 'callsign = ?', whereArgs: [callsign]);
  }
}
