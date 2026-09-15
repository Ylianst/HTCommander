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
// legacy_import.dart - One-time migration of the old flat-file history stores
// into the SQLite database.
//
// For each legacy file that still exists, its tail (up to the same cap the
// in-memory store used) is parsed and batch-inserted, then the file is renamed
// to `<name>.imported`. The rename makes the whole thing idempotent: once a file
// has been migrated it is never seen again, and re-running is a no-op. The
// renamed files are kept as a backup rather than deleted.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../aprsis/aprsis_history_store.dart' show AprsIsHistoryRecord;
import '../../handlers/comms_handler.dart' show DecodedTextEntry;
import '../../handlers/packet_store.dart' show PacketStore;
import '../../radio/tnc_data_fragment.dart' show TncDataFragment;
import 'app_database_io.dart';

/// Migrates the legacy `voicetext.json`, `packets.ptcap` and
/// `aprsis_history.txt` files into [AppDatabase].
class LegacyImport {
  static const String _voiceTextFile = 'voicetext.json';
  static const String _packetsFile = 'packets.ptcap';
  static const String _aprsIsFile = 'aprsis_history.txt';

  // Import caps mirror each store's in-memory limit so a large legacy file is
  // not fully replayed; user retention settings trim further afterwards.
  static const int _maxComms = 1000;
  static const int _maxPackets = 2000;
  static const int _maxAprsIs = 1000;

  /// Imports any legacy files found in [supportDirPath], then renames them.
  static Future<void> run(AppDatabase db, String supportDirPath) async {
    await _importComms(db, supportDirPath);
    await _importPackets(db, supportDirPath);
    await _importAprsIs(db, supportDirPath);
  }

  static Future<void> _importComms(AppDatabase db, String dir) async {
    final file = File('$dir${Platform.pathSeparator}$_voiceTextFile');
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          var maps = decoded.whereType<Map<String, dynamic>>().toList();
          if (maps.length > _maxComms) {
            maps = maps.sublist(maps.length - _maxComms);
          }
          final entries = maps
              .map(DecodedTextEntry.fromJson)
              .toList(growable: false);
          await db.comms.importAll(entries);
        }
      }
      await _markImported(file);
    } catch (e) {
      debugPrint('LegacyImport: comms import failed: $e');
    }
  }

  static Future<void> _importPackets(AppDatabase db, String dir) async {
    final file = File('$dir${Platform.pathSeparator}$_packetsFile');
    if (!await file.exists()) return;
    try {
      var lines = await file.readAsLines();
      if (lines.length > _maxPackets) {
        lines = lines.sublist(lines.length - _maxPackets);
      }
      final frames = <TncDataFragment>[
        for (final line in lines)
          if (line.isNotEmpty) ?PacketStore.parsePacketLine(line),
      ];
      await db.packets.importAll(frames);
      await _markImported(file);
    } catch (e) {
      debugPrint('LegacyImport: packets import failed: $e');
    }
  }

  static Future<void> _importAprsIs(AppDatabase db, String dir) async {
    final file = File('$dir${Platform.pathSeparator}$_aprsIsFile');
    if (!await file.exists()) return;
    try {
      var lines = await file.readAsLines();
      if (lines.length > _maxAprsIs) {
        lines = lines.sublist(lines.length - _maxAprsIs);
      }
      final records = <AprsIsHistoryRecord>[
        for (final line in lines) ?_parseAprsIsLine(line),
      ];
      await db.aprsis.importAll(records);
      await _markImported(file);
    } catch (e) {
      debugPrint('LegacyImport: aprsis import failed: $e');
    }
  }

  /// Parses a legacy line `{microsecondsSinceEpoch}\t{tnc2Line}`.
  static AprsIsHistoryRecord? _parseAprsIsLine(String line) {
    if (line.isEmpty) return null;
    final tab = line.indexOf('\t');
    if (tab < 1) return null;
    final micros = int.tryParse(line.substring(0, tab));
    if (micros == null) return null;
    final tnc2 = line.substring(tab + 1);
    if (tnc2.isEmpty) return null;
    return AprsIsHistoryRecord(
      DateTime.fromMicrosecondsSinceEpoch(micros),
      tnc2,
    );
  }

  static Future<void> _markImported(File file) async {
    try {
      final target = File('${file.path}.imported');
      if (await target.exists()) await target.delete();
      await file.rename(target.path);
    } catch (e) {
      debugPrint('LegacyImport: failed to rename ${file.path}: $e');
    }
  }
}
