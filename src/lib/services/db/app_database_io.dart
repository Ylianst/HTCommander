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
// app_database_io.dart - Real SQLite implementation of [AppDatabase], used on
// every platform that has dart:io (desktop + mobile). The web build gets
// app_database_stub.dart instead via the conditional export in
// app_database.dart, so sqflite / dart:ffi are never pulled into the web bundle.
//

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
// Provides the native databaseFactory default on Android/iOS/macOS; the ffi
// package only supplies the desktop factory.
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'aprsis_dao.dart';
import 'comms_dao.dart';
import 'legacy_import.dart';
import 'packets_dao.dart';

/// Owns the shared SQLite connection and exposes one DAO per stored table.
class AppDatabase {
  AppDatabase._(this.db)
    : comms = CommsDao(db),
      packets = PacketsDao(db),
      aprsis = AprsisDao(db);

  /// The open database handle. DAOs run their statements against this.
  final Database db;

  /// Comms tab decoded-text / APRS message history.
  final CommsDao comms;

  /// RF packet capture history.
  final PacketsDao packets;

  /// Internet-gated (APRS-IS) message history.
  final AprsisDao aprsis;

  /// Current schema version. Bump and add an [onUpgrade] branch when the schema
  /// changes.
  static const int _schemaVersion = 1;

  static const String _dbFileName = 'htcommander.db';

  static AppDatabase? _instance;

  /// The open database, or null on web / when opening failed (callers then keep
  /// their in-memory behaviour).
  static AppDatabase? get instance => _instance;

  /// Opens (or creates) the database, verifies its integrity, and imports any
  /// legacy flat-file history. Idempotent and safe to call once at startup from
  /// the host/main process. No-op on web.
  static Future<void> open() async {
    if (kIsWeb || _instance != null) return;

    // sqflite ships native SQLite on Android/iOS/macOS; Windows and Linux
    // (including Raspberry Pi) use the FFI backend with sqlite3_flutter_libs.
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    try {
      final dir = await getApplicationSupportDirectory();
      final path = '${dir.path}${Platform.pathSeparator}$_dbFileName';

      var db = await _openAt(path);
      if (!await _isHealthy(db)) {
        await db.close();
        await _quarantine(path);
        db = await _openAt(path);
      }

      final instance = AppDatabase._(db);
      await LegacyImport.run(instance, dir.path);
      _instance = instance;
    } catch (e) {
      debugPrint('AppDatabase: open failed: $e');
      _instance = null;
    }
  }

  static Future<Database> _openAt(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) async {
          // WAL: durable per-transaction commits with far fewer fsyncs than the
          // old flush-on-every-write flat files.
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=NORMAL');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // No migrations yet (v1). Future schema changes branch on oldVersion.
        },
      ),
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE comms_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time_ms INTEGER NOT NULL,
        encoding TEXT NOT NULL,
        channel TEXT,
        is_received INTEGER NOT NULL,
        text TEXT,
        source TEXT,
        destination TEXT,
        lat REAL NOT NULL DEFAULT 0,
        lon REAL NOT NULL DEFAULT 0,
        filename TEXT,
        duration INTEGER NOT NULL DEFAULT 0,
        wpm INTEGER,
        key_type TEXT,
        sarsat_json TEXT,
        radiosonde_json TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_comms_time ON comms_events(time_ms)');
    await db.execute(
      'CREATE INDEX idx_comms_enc_time ON comms_events(encoding, time_ms)',
    );

    await db.execute('''
      CREATE TABLE packets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time_us INTEGER NOT NULL,
        incoming INTEGER NOT NULL,
        channel_id INTEGER NOT NULL,
        region_id INTEGER NOT NULL,
        channel_name TEXT NOT NULL,
        data BLOB NOT NULL,
        encoding INTEGER NOT NULL,
        frame_type INTEGER NOT NULL,
        corrections INTEGER NOT NULL,
        radio_mac TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_pkt_time ON packets(time_us)');
    await db.execute(
      'CREATE INDEX idx_pkt_chan_time ON packets(channel_name, time_us)',
    );

    await db.execute('''
      CREATE TABLE aprsis_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time_us INTEGER NOT NULL,
        tnc2 TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_aprsis_time ON aprsis_history(time_us)');
  }

  /// Runs a quick integrity check so a corrupt database is rebuilt rather than
  /// throwing on every query (mirrors the shared_preferences corruption path).
  static Future<bool> _isHealthy(Database db) async {
    try {
      final rows = await db.rawQuery('PRAGMA quick_check');
      if (rows.isEmpty) return false;
      final first = rows.first.values.first;
      return first is String && first.toLowerCase() == 'ok';
    } catch (e) {
      debugPrint('AppDatabase: integrity check failed: $e');
      return false;
    }
  }

  /// Renames a corrupt database (and its WAL sidecars) to `.corrupt` so a fresh
  /// one is created on the next open.
  static Future<void> _quarantine(String path) async {
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      try {
        if (await file.exists()) {
          final backup = File('$path$suffix.corrupt');
          if (await backup.exists()) await backup.delete();
          await file.rename(backup.path);
        }
      } catch (e) {
        debugPrint('AppDatabase: failed to quarantine $path$suffix: $e');
      }
    }
  }

  /// Closes the database. Intended for tests; the app keeps it open for its
  /// whole lifetime.
  static Future<void> close() async {
    final instance = _instance;
    _instance = null;
    if (instance != null) await instance.db.close();
  }

  /// Opens a fresh in-memory database with the current schema for tests, and
  /// installs it as [instance]. Does not touch the filesystem or run the legacy
  /// import.
  @visibleForTesting
  static Future<AppDatabase> openInMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );
    final instance = AppDatabase._(db);
    _instance = instance;
    return instance;
  }
}
