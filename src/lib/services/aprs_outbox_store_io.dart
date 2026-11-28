/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../aprs/aprs_outbox.dart';
import 'db/app_database_io.dart';

class AprsOutboxStore {
  Database get _db {
    final db = AppDatabase.instance?.db;
    if (db == null) throw StateError('APRS outbox database is unavailable');
    return db;
  }

  Future<List<AprsOutgoingMessage>> load() async {
    final rows = await _db.query('aprs_outbox', orderBy: 'created_ms');
    return rows.map((r) => AprsOutgoingMessage.fromJson(
      jsonDecode(r['payload'] as String) as Map<String, dynamic>,
    )).toList();
  }

  Future<void> save(AprsOutgoingMessage message) async {
    await _db.insert('aprs_outbox', {
      'id': message.id, 'created_ms': message.created.millisecondsSinceEpoch,
      'active': message.active ? 1 : 0, 'payload': jsonEncode(message.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(List<String> ids) async {
    final batch = _db.batch();
    for (final id in ids) {
      batch.delete('aprs_outbox', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }
}
