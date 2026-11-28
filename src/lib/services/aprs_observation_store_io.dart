/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import '../aprs/aprs_observation.dart';
import 'db/app_database_io.dart';

class AprsObservationStore {
  Future<List<AprsObservation>> load() async {
    final db = AppDatabase.instance?.db;
    if (db == null) throw StateError('APRS observation database is unavailable');
    final rows = await db.query('aprs_observations',
      orderBy: 'sequence DESC', limit: AprsObservation.capacity);
    return rows.reversed.map((row) => AprsObservation.fromJson(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>)
      .withStatus(live: false, persisted: true)).toList();
  }

  Future<void> save(AprsObservation observation) async {
    final db = AppDatabase.instance?.db;
    if (db == null) throw StateError('APRS observation database is unavailable');
    await db.transaction((txn) async {
      await txn.insert('aprs_observations', {'id': observation.id,
        'payload': jsonEncode(observation.toJson())});
      await txn.rawDelete('DELETE FROM aprs_observations WHERE sequence NOT IN '
        '(SELECT sequence FROM aprs_observations ORDER BY sequence DESC LIMIT ?)',
        [AprsObservation.capacity]);
    });
  }
}
