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
// aprsis_history_store.dart - Append-only, self-compacting on-disk store for
// APRS-IS (internet-gated) messages.
//
// Internet APRS traffic is deliberately kept out of the RF packet store so the
// two sources stay unmixed. To let internet history survive an app restart,
// each received packet is appended here as a single line
// `{microsecondsSinceEpoch}\t{tnc2Line}`. Appending is O(1) and never rewrites
// the whole file. On startup the last [_maxEntries] records are loaded. The
// file is compacted (rewritten to the last [_maxEntries] records) only
// occasionally - after [_compactEvery] appends, or when found oversized on
// load - so trimming cost stays amortized and rare.
//
// No-op on the web, where dart:io file access is unavailable.
//

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One persisted APRS-IS record: the receive time and the raw TNC2 line.
class AprsIsHistoryRecord {
  final DateTime time;
  final String tnc2Line;

  const AprsIsHistoryRecord(this.time, this.tnc2Line);
}

/// Persists APRS-IS messages to `aprsis_history.txt` in the application support
/// directory, appending one line per message and self-compacting occasionally.
class AprsIsHistoryStore {
  /// Filename for the persisted internet history.
  static const String _fileName = 'aprsis_history.txt';

  /// Maximum number of records retained on disk (and returned on load).
  static const int _maxEntries = 1000;

  /// Compact the file after this many appends since the last compaction.
  static const int _compactEvery = 500;

  /// Only compact once the file grows past this many lines, so a file hovering
  /// near the cap is not rewritten needlessly.
  static const int _compactThreshold = _maxEntries * 2;

  /// The on-disk file, or null when persistence is unavailable (web / error).
  File? _file;

  /// Best-effort count of lines currently in the file.
  int _lineCount = 0;

  /// Appends since the last compaction, used to trigger periodic trimming.
  int _appendsSinceCompact = 0;

  /// Opens the store and returns the most recent [_maxEntries] records in the
  /// order they were written (oldest first). Returns an empty list on web or on
  /// any error. Compacts the file if it is found well past the cap.
  Future<List<AprsIsHistoryRecord>> init() async {
    if (kIsWeb) return const [];
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      final records = await _load();
      if (_lineCount > _compactThreshold) _compactSync();
      return records;
    } catch (e) {
      debugPrint('AprsIsHistoryStore: init failed: $e');
      _file = null;
      return const [];
    }
  }

  /// Reads the file and returns the last [_maxEntries] parsed records.
  Future<List<AprsIsHistoryRecord>> _load() async {
    final file = _file;
    if (file == null || !await file.exists()) return const [];

    List<String> lines;
    try {
      lines = await file.readAsLines();
    } catch (e) {
      debugPrint('AprsIsHistoryStore: read failed: $e');
      return const [];
    }
    _lineCount = lines.length;

    final start = lines.length > _maxEntries ? lines.length - _maxEntries : 0;
    final records = <AprsIsHistoryRecord>[];
    for (var i = start; i < lines.length; i++) {
      final rec = _parseLine(lines[i]);
      if (rec != null) records.add(rec);
    }
    return records;
  }

  /// Parses a stored line `{microsecondsSinceEpoch}\t{tnc2Line}`, or null when
  /// malformed.
  static AprsIsHistoryRecord? _parseLine(String line) {
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

  /// Appends one record to the file, occasionally compacting back to the last
  /// [_maxEntries] records. Writes are flushed to the OS immediately so records
  /// survive an abrupt process kill (common on mobile), where [dispose] never
  /// runs.
  void append(DateTime time, String tnc2Line) {
    final file = _file;
    if (file == null) return;

    // Keep each record on exactly one line: the TNC2 field must not contain the
    // tab separator or a line break.
    final clean = tnc2Line
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\t', ' ');
    if (clean.isEmpty) return;

    try {
      file.writeAsStringSync(
        '${time.microsecondsSinceEpoch}\t$clean\n',
        mode: FileMode.append,
        flush: true,
      );
      _lineCount++;
      _appendsSinceCompact++;
      if (_appendsSinceCompact >= _compactEvery &&
          _lineCount > _compactThreshold) {
        _compactSync();
      }
    } catch (e) {
      debugPrint('AprsIsHistoryStore: append failed: $e');
    }
  }

  /// Rewrites the file to the last [_maxEntries] raw lines. Done synchronously
  /// so it cannot interleave with the synchronous appends that share the file.
  void _compactSync() {
    final file = _file;
    if (file == null) return;
    try {
      final lines = file.readAsLinesSync();
      if (lines.length <= _maxEntries) {
        _lineCount = lines.length;
        _appendsSinceCompact = 0;
        return;
      }
      final kept = lines.sublist(lines.length - _maxEntries);
      file.writeAsStringSync('${kept.join('\n')}\n', flush: true);
      _lineCount = kept.length;
      _appendsSinceCompact = 0;
    } catch (e) {
      debugPrint('AprsIsHistoryStore: compact failed: $e');
    }
  }
}
