/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

The BBS file area: a folder on disk whose files BBS users can list, download
and upload (YAPP over AX.25, or HTTP for web visitors).

The sysop can drop files straight into the folder; they are picked up on the
next listing. A hidden index file keeps each file's number (stable across
restarts and never reused), who uploaded it and when.

The store lives in the host process. The BBS tab (possibly in a detached
window) talks to it over the DataBroker on device 1:
  BbsFilesRefresh        -> republishes `BbsFiles`
  BbsFileAdd {Name, Data}
  BbsFileDelete id
  BbsFileOpenFolder
and `BbsFiles` (stored) holds the current list as maps.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// A file offered by the BBS.
class BbsFile {
  const BbsFile({
    required this.id,
    required this.name,
    required this.size,
    required this.time,
    this.uploader = '',
  });

  /// File number shown to users; never reused.
  final int id;
  final String name;
  final int size;

  /// When the file was uploaded (or last modified, for files the sysop added).
  final DateTime time;

  /// Callsign that uploaded the file, empty when added by the sysop.
  final String uploader;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'time': time.millisecondsSinceEpoch,
    'uploader': uploader,
  };

  static BbsFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;
    return BbsFile(
      id: id,
      name: name,
      size: (json['size'] as num?)?.toInt() ?? 0,
      time: DateTime.fromMillisecondsSinceEpoch(
        (json['time'] as num?)?.toInt() ?? 0,
      ),
      uploader: json['uploader'] as String? ?? '',
    );
  }
}

/// Result of [BbsFileStore.upload].
class BbsUploadResult {
  const BbsUploadResult.ok(BbsFile this.file) : error = null;
  const BbsUploadResult.failed(String this.error) : file = null;

  final BbsFile? file;
  final String? error;
}

class _IndexEntry {
  _IndexEntry(this.id, this.name, this.uploader, this.timeMs);

  final int id;
  final String name;
  final String uploader;
  final int timeMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'uploader': uploader,
    'time': timeMs,
  };
}

/// The BBS file area.
class BbsFileStore {
  /// A store over [directory]; null keeps it unavailable (e.g. on the web).
  BbsFileStore({String? directory}) : _dirPath = directory;

  /// The store shared by every BBS. Replaceable in tests.
  static BbsFileStore instance = BbsFileStore();

  /// Largest file a station may upload.
  static const int maxUploadBytes = 25 * 1024;

  /// Uploads are refused once uploaded files take this much space in total.
  static const int maxUploadedTotalBytes = 20 * 1024 * 1024;

  /// DataBroker setting (device 0, 1 = on) allowing users to upload files.
  static const String uploadsSetting = 'BbsFileUploads';

  static const String _indexName = '.bbsfiles.json';

  String? _dirPath;
  final Map<String, _IndexEntry> _index = {};
  int _lastId = 0;
  bool _indexLoaded = false;
  DataBrokerClient? _broker;

  /// Whether the file area has a folder (not on the web).
  bool get isAvailable => _dirPath != null;

  /// The folder holding the files, or null when unavailable.
  String? get directory => _dirPath;

  /// Whether stations may upload files.
  bool get uploadsEnabled =>
      (DataBroker.getValue<int>(0, uploadsSetting, 1) ?? 1) == 1;

  /// Creates the default folder, loads the index and starts answering the BBS
  /// tab over the broker. Host process only.
  Future<void> init() async {
    if (_dirPath == null && !kIsWeb) {
      try {
        final dir = await getApplicationSupportDirectory();
        final sep = Platform.pathSeparator;
        _dirPath = '${dir.path}${sep}HTCommander${sep}BbsFiles';
      } catch (e) {
        debugPrint('BbsFileStore: no storage folder: $e');
      }
    }
    final path = _dirPath;
    if (path != null) {
      try {
        Directory(path).createSync(recursive: true);
      } catch (e) {
        debugPrint('BbsFileStore: cannot create $path: $e');
        _dirPath = null;
      }
    }
    _loadIndex();

    final broker = DataBrokerClient();
    _broker = broker;
    broker.subscribeMultiple(
      deviceId: 1,
      names: const [
        'BbsFilesRefresh',
        'BbsFileAdd',
        'BbsFileDelete',
        'BbsFileOpenFolder',
      ],
      callback: _onCommand,
    );
    _publish();
  }

  void dispose() {
    _broker?.dispose();
    _broker = null;
  }

  // ---- listing --------------------------------------------------------------

  /// Every file in the folder, by number (oldest first). Files the sysop added
  /// or removed in the folder are picked up here.
  List<BbsFile> list() {
    final path = _dirPath;
    if (path == null) return const [];
    if (!_indexLoaded) _loadIndex();
    final found = <String, File>{};
    try {
      for (final entity in Directory(path).listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = _baseName(entity.path);
        if (name.startsWith('.')) continue;
        found[name] = entity;
      }
    } catch (e) {
      debugPrint('BbsFileStore: cannot list $path: $e');
      return const [];
    }

    var changed = false;
    _index.removeWhere((name, _) {
      final gone = !found.containsKey(name);
      changed |= gone;
      return gone;
    });
    final files = <BbsFile>[];
    // Number new files in name order so a batch dropped in is numbered sensibly.
    for (final name in found.keys.toList()..sort()) {
      final file = found[name]!;
      FileStat stat;
      try {
        stat = file.statSync();
      } catch (_) {
        continue;
      }
      var entry = _index[name];
      if (entry == null) {
        entry = _IndexEntry(
          ++_lastId,
          name,
          '',
          stat.modified.millisecondsSinceEpoch,
        );
        _index[name] = entry;
        changed = true;
      }
      files.add(
        BbsFile(
          id: entry.id,
          name: name,
          size: stat.size,
          time: DateTime.fromMillisecondsSinceEpoch(entry.timeMs),
          uploader: entry.uploader,
        ),
      );
    }
    if (changed) _saveIndex();
    files.sort((a, b) => a.id.compareTo(b.id));
    return files;
  }

  /// The file numbered [id], or named [name] (case-insensitive).
  BbsFile? find(String idOrName) {
    final s = idOrName.trim();
    final hash = s.startsWith('#') ? s.substring(1) : s;
    final id = int.tryParse(hash);
    for (final f in list()) {
      if (id != null ? f.id == id : f.name.toLowerCase() == s.toLowerCase()) {
        return f;
      }
    }
    return null;
  }

  /// The content of [file], or null if it can no longer be read.
  Uint8List? read(BbsFile file) {
    final path = _dirPath;
    if (path == null) return null;
    try {
      return File(_join(path, file.name)).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  // ---- changes --------------------------------------------------------------

  /// Checks whether [uploader] may upload [size] bytes; null when allowed,
  /// otherwise the reason it is refused.
  String? checkUpload(int size) {
    if (!isAvailable) return 'File storage is not available on this BBS';
    if (!uploadsEnabled) return 'Uploads are disabled on this BBS';
    if (size <= 0) return 'The file is empty';
    if (size > maxUploadBytes) {
      return 'File too large ($size bytes, max $maxUploadBytes)';
    }
    final used = list()
        .where((f) => f.uploader.isNotEmpty)
        .fold<int>(0, (sum, f) => sum + f.size);
    if (used + size > maxUploadedTotalBytes) {
      return 'The BBS file area is full';
    }
    return null;
  }

  /// Saves a file uploaded by [uploader], subject to [checkUpload].
  BbsUploadResult upload(String uploader, String name, Uint8List data) {
    final refusal = checkUpload(data.length);
    if (refusal != null) return BbsUploadResult.failed(refusal);
    final file = add(name, data, uploader: uploader.toUpperCase());
    return file == null
        ? const BbsUploadResult.failed('The file could not be saved')
        : BbsUploadResult.ok(file);
  }

  /// Saves [data] as [name] (sanitized and made unique). Sysop additions leave
  /// [uploader] empty. Returns null on failure.
  BbsFile? add(String name, Uint8List data, {String uploader = ''}) {
    final path = _dirPath;
    if (path == null) return null;
    list(); // Sync the index with the folder first.
    final safe = _uniqueName(sanitizeName(name));
    final now = DateTime.now();
    try {
      File(_join(path, safe)).writeAsBytesSync(data, flush: true);
    } catch (e) {
      debugPrint('BbsFileStore: cannot save $safe: $e');
      return null;
    }
    final entry = _IndexEntry(
      ++_lastId,
      safe,
      uploader,
      now.millisecondsSinceEpoch,
    );
    _index[safe] = entry;
    _saveIndex();
    _publish();
    return BbsFile(
      id: entry.id,
      name: safe,
      size: data.length,
      time: now,
      uploader: uploader,
    );
  }

  /// Deletes the file numbered [id]. Returns false if it does not exist.
  bool delete(int id) {
    final path = _dirPath;
    if (path == null) return false;
    final file = list().where((f) => f.id == id).firstOrNull;
    if (file == null) return false;
    try {
      File(_join(path, file.name)).deleteSync();
    } catch (e) {
      debugPrint('BbsFileStore: cannot delete ${file.name}: $e');
      return false;
    }
    _index.remove(file.name);
    _saveIndex();
    _publish();
    return true;
  }

  // ---- names ----------------------------------------------------------------

  /// A safe file name: no path, only letters, digits, `.`, `_` and `-`, no
  /// leading dot, at most 64 characters.
  static String sanitizeName(String name) {
    var base = _baseName(name.trim());
    base = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    base = base.replaceAll(RegExp(r'^[._]+'), '');
    base = base.replaceAll(RegExp(r'_{2,}'), '_');
    if (base.length > 64) {
      final dot = base.lastIndexOf('.');
      final ext = dot > 0 && base.length - dot <= 10 ? base.substring(dot) : '';
      base = base.substring(0, 64 - ext.length) + ext;
    }
    return base.isEmpty ? 'file' : base;
  }

  String _uniqueName(String name) {
    final path = _dirPath!;
    bool taken(String n) =>
        _index.keys.any((k) => k.toLowerCase() == n.toLowerCase()) ||
        File(_join(path, n)).existsSync();
    if (!taken(name)) return name;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; ; i++) {
      final candidate = '$stem-$i$ext';
      if (!taken(candidate)) return candidate;
    }
  }

  static String _baseName(String path) {
    final p = path.replaceAll('\\', '/');
    final slash = p.lastIndexOf('/');
    return slash >= 0 ? p.substring(slash + 1) : p;
  }

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  // ---- index ----------------------------------------------------------------

  void _loadIndex() {
    _indexLoaded = true;
    _index.clear();
    _lastId = 0;
    final path = _dirPath;
    if (path == null) return;
    try {
      final file = File(_join(path, _indexName));
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return;
      _lastId = (json['lastId'] as num?)?.toInt() ?? 0;
      final files = json['files'];
      if (files is List) {
        for (final f in files) {
          if (f is! Map) continue;
          final id = f['id'];
          final name = f['name'];
          if (id is! int || name is! String) continue;
          _index[name] = _IndexEntry(
            id,
            name,
            f['uploader'] as String? ?? '',
            (f['time'] as num?)?.toInt() ?? 0,
          );
          if (id > _lastId) _lastId = id;
        }
      }
    } catch (e) {
      debugPrint('BbsFileStore: cannot read the index: $e');
    }
  }

  void _saveIndex() {
    final path = _dirPath;
    if (path == null) return;
    try {
      File(_join(path, _indexName)).writeAsStringSync(
        jsonEncode({
          'lastId': _lastId,
          'files': [for (final e in _index.values) e.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('BbsFileStore: cannot write the index: $e');
    }
  }

  // ---- BBS tab --------------------------------------------------------------

  void _publish() {
    _broker?.dispatch(
      deviceId: 1,
      name: 'BbsFiles',
      data: [for (final f in list()) f.toJson()],
    );
  }

  void _onCommand(int deviceId, String name, Object? data) {
    switch (name) {
      case 'BbsFilesRefresh':
        _publish();
      case 'BbsFileAdd':
        if (data is Map && data['Name'] is String && data['Data'] is List) {
          final bytes = data['Data'];
          add(
            data['Name'] as String,
            bytes is Uint8List
                ? bytes
                : Uint8List.fromList((bytes as List).cast<int>()),
          );
        }
      case 'BbsFileDelete':
        if (data is int) delete(data);
      case 'BbsFileOpenFolder':
        final path = _dirPath;
        if (path != null) {
          unawaited(
            launchUrl(Uri.directory(path)).catchError((Object _) => false),
          );
        }
    }
  }
}
