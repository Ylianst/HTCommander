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

import '../../meshcore/meshcore_message.dart';

/// Persists MeshCore direct and group message history (`meshcore_messages`).
/// The companion radio deletes messages once they are synced, so this is the
/// only copy after they reach HTCommander.
class MeshCoreDao {
  MeshCoreDao(this._db);

  final Database _db;

  static const String _table = 'meshcore_messages';

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time_ms INTEGER NOT NULL,
        sender_time INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL,
        peer TEXT NOT NULL,
        outgoing INTEGER NOT NULL,
        sender TEXT,
        text TEXT NOT NULL,
        path_len INTEGER,
        snr REAL,
        state TEXT NOT NULL,
        ack_tag INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_meshcore_time ON $_table(time_ms)',
    );
  }

  /// Inserts [message] and returns its row id.
  Future<int> insert(MeshCoreMessage message) =>
      _db.insert(_table, message.toRow());

  Future<void> updateState(int id, String state, int? ackTag) async {
    await _db.update(
      _table,
      {'state': state, 'ack_tag': ackTag},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns the most recent [limit] messages, oldest first.
  Future<List<MeshCoreMessage>> recent(int limit) async {
    final rows = await _db.query(
      _table,
      orderBy: 'time_ms DESC, id DESC',
      limit: limit,
    );
    return rows.reversed.map(MeshCoreMessage.fromRow).toList();
  }

  /// Deletes one conversation, or everything when [kind] is null.
  Future<void> clear({String? kind, String? peer}) async {
    if (kind == null || peer == null) {
      await _db.delete(_table);
    } else {
      await _db.delete(
        _table,
        where: 'kind = ? AND peer = ?',
        whereArgs: [kind, peer],
      );
    }
  }

  /// Keeps only the newest [maxEntries] messages. A value <= 0 means unlimited.
  Future<void> enforceLimit(int maxEntries) async {
    if (maxEntries <= 0) return;
    await _db.rawDelete(
      'DELETE FROM $_table WHERE id NOT IN '
      '(SELECT id FROM $_table ORDER BY time_ms DESC, id DESC LIMIT ?)',
      [maxEntries],
    );
  }
}
