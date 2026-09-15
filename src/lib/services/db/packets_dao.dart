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

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../radio/tnc_data_fragment.dart';

/// Persists RF packet capture history (`packets`). Stores the same fields the
/// old `packets.ptcap` line format round-tripped, with raw bytes as a BLOB.
class PacketsDao {
  PacketsDao(this._db);

  final Database _db;

  static const String _table = 'packets';

  /// Appends one captured packet.
  Future<void> insert(TncDataFragment frame) async {
    await _db.insert(_table, _toRow(frame));
  }

  /// Batch-inserts packets in a single transaction (used by legacy import).
  Future<void> importAll(List<TncDataFragment> frames) async {
    if (frames.isEmpty) return;
    final batch = _db.batch();
    for (final frame in frames) {
      batch.insert(_table, _toRow(frame));
    }
    await batch.commit(noResult: true);
  }

  /// Returns the most recent [limit] packets in chronological order (oldest
  /// first).
  Future<List<TncDataFragment>> recent(int limit) async {
    final rows = await _db.query(
      _table,
      orderBy: 'time_us DESC, id DESC',
      limit: limit,
    );
    return rows.reversed.map(_fromRow).toList(growable: false);
  }

  /// Deletes all packets.
  Future<void> clear() async {
    await _db.delete(_table);
  }

  /// Counts packets on the APRS channel ([aprs] true) or all other channels
  /// ([aprs] false).
  Future<int> count({required bool aprs}) async {
    final op = aprs ? '=' : '<>';
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) AS n FROM $_table WHERE channel_name $op 'APRS'",
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Enforces retention caps independently for APRS-channel packets and all
  /// others (channel name `APRS`), matching the old file trimming. A value <= 0
  /// means unlimited.
  Future<void> enforceLimits({
    required int maxNonAprs,
    required int maxAprs,
  }) async {
    if (maxAprs > 0) {
      await _db.rawDelete(
        "DELETE FROM $_table WHERE channel_name = 'APRS' AND id NOT IN "
        "(SELECT id FROM $_table WHERE channel_name = 'APRS' "
        "ORDER BY time_us DESC, id DESC LIMIT ?)",
        [maxAprs],
      );
    }
    if (maxNonAprs > 0) {
      await _db.rawDelete(
        "DELETE FROM $_table WHERE channel_name <> 'APRS' AND id NOT IN "
        "(SELECT id FROM $_table WHERE channel_name <> 'APRS' "
        "ORDER BY time_us DESC, id DESC LIMIT ?)",
        [maxNonAprs],
      );
    }
  }

  static Map<String, Object?> _toRow(TncDataFragment f) => <String, Object?>{
    'time_us': f.time.microsecondsSinceEpoch,
    'incoming': f.incoming ? 1 : 0,
    'channel_id': f.channelId,
    'region_id': f.regionId,
    'channel_name': f.channelName,
    'data': f.data,
    'encoding': f.encoding.index,
    'frame_type': f.frameType.index,
    'corrections': f.corrections,
    'radio_mac': f.radioMac,
  };

  static TncDataFragment _fromRow(Map<String, Object?> row) {
    final data = row['data'];
    final bytes = data is Uint8List
        ? data
        : Uint8List.fromList((data as List).cast<int>());
    final encIndex = row['encoding'] as int? ?? 0;
    final frameIndex = row['frame_type'] as int? ?? 0;
    return TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: bytes,
      channelId: row['channel_id'] as int? ?? -1,
      regionId: row['region_id'] as int? ?? -1,
      channelName: row['channel_name'] as String? ?? '',
      incoming: (row['incoming'] as int? ?? 0) != 0,
      time: DateTime.fromMicrosecondsSinceEpoch(row['time_us'] as int? ?? 0),
      encoding: encIndex >= 0 && encIndex < FragmentEncodingType.values.length
          ? FragmentEncodingType.values[encIndex]
          : FragmentEncodingType.unknown,
      frameType: frameIndex >= 0 && frameIndex < FragmentFrameType.values.length
          ? FragmentFrameType.values[frameIndex]
          : FragmentFrameType.unknown,
      corrections: row['corrections'] as int? ?? -1,
      radioMac: row['radio_mac'] as String?,
    );
  }
}
