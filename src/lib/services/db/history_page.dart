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
}) async {
  const pageSize = 200;
  final predicates = [
    if (filter != null) '($filter)',
    if (before != null) '($timeColumn < ? OR ($timeColumn = ? AND id < ?))',
  ];
  final rows = await db.query(
    table,
    where: predicates.isEmpty ? null : predicates.join(' AND '),
    whereArgs: before == null ? null : [before[0], before[0], before[1]],
    orderBy: '$timeColumn DESC, id DESC',
    limit: pageSize + 1,
  );
  final page = rows.take(pageSize).toList(growable: false);
  return {
    'entries': [
      for (final row in page.reversed) {'id': row['id'], 'data': decode(row)},
    ],
    'before': page.isEmpty ? null : [page.last[timeColumn], page.last['id']],
    'hasMore': rows.length > pageSize,
  };
}
