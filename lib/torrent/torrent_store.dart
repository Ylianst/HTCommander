/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Flutter equivalent of the C# `TorrentFile` disk persistence
(`ReadTorrentFiles` / `WriteTorrentFile` / `DeleteTorrentFile`). Instead of the
C# binary `.httorrent` record format, each torrent is stored as a single JSON
file produced by [TorrentFile.toStorageMap].
*/

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/torrent_file.dart';

/// Persists shared/downloaded [TorrentFile]s to disk under
/// `<appSupportDir>/HTCommander/Torrents/`, one JSON file per torrent.
class TorrentStore {
  Directory? _dir;
  final List<TorrentFile> _loaded = [];

  /// Files loaded from disk during [init].
  List<TorrentFile> get loadedFiles => List<TorrentFile>.from(_loaded);

  /// Resolves the storage directory (creating it if needed) and loads all
  /// persisted torrent files into [loadedFiles]. Must be awaited before the
  /// handler reads [loadedFiles].
  Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}HTCommander'
        '${Platform.pathSeparator}Torrents',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
      await _loadAll();
    } catch (e) {
      debugPrint('TorrentStore: failed to initialize: $e');
      _dir = null;
    }
  }

  Future<void> _loadAll() async {
    final dir = _dir;
    if (dir == null) return;
    _loaded.clear();
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final text = await entity.readAsString();
        final map = jsonDecode(text);
        if (map is Map<String, dynamic>) {
          _loaded.add(TorrentFile.fromStorageMap(map));
        }
      } catch (e) {
        debugPrint('TorrentStore: failed to read ${entity.path}: $e');
      }
    }
  }

  /// Writes [file] to disk (overwriting any existing file with the same id).
  /// No-op when the file has no id or the store failed to initialize.
  Future<void> save(TorrentFile file) async {
    final path = _pathFor(file);
    if (path == null) return;
    try {
      final text = jsonEncode(file.toStorageMap());
      await File(path).writeAsString(text, flush: false);
    } catch (e) {
      debugPrint('TorrentStore: failed to save ${file.fileName}: $e');
    }
  }

  /// Deletes [file] from disk if present.
  Future<void> delete(TorrentFile file) async {
    final path = _pathFor(file);
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('TorrentStore: failed to delete ${file.fileName}: $e');
    }
  }

  String? _pathFor(TorrentFile file) {
    final dir = _dir;
    final id = file.id;
    if (dir == null || id == null) return null;
    final name = '${file.callsign}-${file.stationId}-${_hex(id)}.json';
    return '${dir.path}${Platform.pathSeparator}$name';
  }

  static String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
