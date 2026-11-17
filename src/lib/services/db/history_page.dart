// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'package:sqflite/sqflite.dart';

/// Keyset paging keeps archive memory bounded, including equal timestamps.
Future<Map<String, Object?>> readHistoryPage(
  Database db, {
  required String table,
  required String timeColumn,
  required Map<String, Object?> Function(Map<String, Object?>) decode,
  List<int>? before,
  String? filter,
  bool Function(Map<String, Object?> data)? matches,
}) async {
  const pageSize = 200;
  final entries = <Map<String, Object?>>[];
  final cursors = <List<int>>[];
  var cursor = before;
  while (entries.length <= pageSize) {
    final predicates = [
      if (filter != null) '($filter)',
      if (cursor != null) '($timeColumn < ? OR ($timeColumn = ? AND id < ?))',
    ];
    final rows = await db.query(
      table,
      where: predicates.isEmpty ? null : predicates.join(' AND '),
      whereArgs: cursor == null ? null : [cursor[0], cursor[0], cursor[1]],
      orderBy: '$timeColumn DESC, id DESC',
      limit: pageSize + 1,
    );
    for (final row in rows) {
      cursor = [row[timeColumn] as int, row['id'] as int];
      final data = decode(row);
      if (matches != null && !matches(data)) continue;
      entries.add({'id': row['id'], 'data': data});
      cursors.add(cursor);
      if (entries.length > pageSize) break;
    }
    if (rows.length <= pageSize) break;
  }
  final page = entries.take(pageSize).toList(growable: false);
  return {
    'entries': page.reversed.toList(growable: false),
    'before': page.isEmpty ? null : cursors[page.length - 1],
    'hasMore': entries.length > pageSize,
  };
}
