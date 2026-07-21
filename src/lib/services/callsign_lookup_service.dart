/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../callsign/callsign_database.dart';
import '../callsign/callsign_record.dart';
import 'data_broker.dart';
import 'data_broker_client.dart';

/// Progress callback for the database download: `(bytesReceived, bytesTotal)`.
/// [total] may be 0 when the size is not known ahead of time.
typedef CallsignDownloadProgress = void Function(int received, int total);

/// Metadata describing a hosted callsign database (from the manifest JSON).
class CallsignDbManifest {
  /// Human-readable database version (e.g. a date like `2026.07.15`).
  final String version;

  /// FCC source date as `YYYYMMDD`, or 0 when unknown.
  final int sourceDate;

  /// URL of the database file to download (may be a `.zip`).
  final String url;

  /// Whether [url] points to a zip archive containing the `.cdb` file.
  final bool compressed;

  /// Size of the download in bytes (0 when unknown).
  final int sizeBytes;

  /// Lower-case hex MD5 of the downloaded file, or empty to skip verification.
  final String md5;

  /// Number of records in the database (0 when unknown).
  final int recordCount;

  const CallsignDbManifest({
    required this.version,
    required this.sourceDate,
    required this.url,
    required this.compressed,
    required this.sizeBytes,
    required this.md5,
    required this.recordCount,
  });

  factory CallsignDbManifest.fromJson(Map<String, dynamic> json) {
    return CallsignDbManifest(
      version: (json['version'] ?? '').toString(),
      sourceDate: (json['sourceDate'] as num?)?.toInt() ?? 0,
      url: (json['url'] ?? '').toString(),
      compressed: json['compressed'] == true,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      md5: (json['md5'] ?? '').toString().toLowerCase(),
      recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Manages the offline US amateur callsign database: download, storage, and
/// lookups. Singleton, initialized once at startup via [instance].`init()`.
///
/// The database is a self-hosted compact binary file (see [CallsignDatabase]).
/// On desktop and mobile it is stored under the application support directory;
/// the web platform is unsupported (no persistent file system).
class CallsignLookupService {
  CallsignLookupService._();

  /// The shared instance.
  static final CallsignLookupService instance = CallsignLookupService._();

  /// URL of the hosted database manifest JSON.
  static const String manifestUrl =
      'https://ylianst.github.io/HTCommander/callsign/fcc_amateur_manifest.json';

  /// File name of the stored database.
  static const String _dbFileName = 'fcc_amateur.cdb';

  /// DataBroker device id used for callsign database state.
  static const int deviceId = 0;

  final DataBrokerClient _broker = DataBrokerClient();

  CallsignDatabase? _db;
  String? _filePath;
  bool _initialized = false;

  /// Whether offline callsign lookup is supported on this platform.
  bool get isSupported => !kIsWeb;

  /// Whether a database is currently loaded and ready for lookups.
  bool get isAvailable => _db != null;

  /// Installed database version, or empty when none is installed.
  String get installedVersion =>
      DataBroker.getValue<String>(deviceId, 'CallsignDbVersion', '') ?? '';

  /// Number of records in the installed database (0 when none).
  int get recordCount =>
      DataBroker.getValue<int>(deviceId, 'CallsignDbRecordCount', 0) ?? 0;

  /// FCC source date (`YYYYMMDD`) of the installed database (0 when none).
  int get sourceDate =>
      DataBroker.getValue<int>(deviceId, 'CallsignDbSourceDate', 0) ?? 0;

  /// Size of the installed database on disk in bytes (0 when none).
  int get sizeBytes =>
      DataBroker.getValue<int>(deviceId, 'CallsignDbSizeBytes', 0) ?? 0;

  /// Resolves the database file, opening it when present. Safe to call once at
  /// startup; subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized || !isSupported) {
      _initialized = true;
      return;
    }
    _initialized = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _filePath = '${dir.path}${Platform.pathSeparator}$_dbFileName';
      final file = File(_filePath!);
      if (await file.exists()) {
        await _openDatabase();
      }
    } catch (e) {
      debugPrint('CallsignLookupService: init failed: $e');
    }
  }

  Future<void> _openDatabase() async {
    final path = _filePath;
    if (path == null) return;
    await _db?.close();
    _db = null;
    try {
      _db = await CallsignDatabase.open(path);
    } catch (e) {
      debugPrint('CallsignLookupService: failed to open database: $e');
      _db = null;
    }
  }

  /// Looks up [callsign] (SSID ignored). Returns null when no database is
  /// loaded or the callsign is not found.
  Future<CallsignRecord?> lookup(String callsign) async {
    final db = _db;
    if (db == null || callsign.trim().isEmpty) return null;
    try {
      return await db.lookup(callsign);
    } catch (e) {
      debugPrint('CallsignLookupService: lookup failed: $e');
      return null;
    }
  }

  /// Fetches the hosted [CallsignDbManifest]. Throws on network / parse errors.
  Future<CallsignDbManifest> fetchManifest() async {
    final response = await http.get(Uri.parse(manifestUrl));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Manifest download failed (${response.statusCode})',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CallsignDbManifest.fromJson(json);
  }

  /// Downloads and installs the database described by [manifest], replacing any
  /// existing database. Reports progress via [progress].
  ///
  /// Throws on network errors, MD5 mismatch, or an invalid database file.
  Future<void> download(
    CallsignDbManifest manifest, {
    CallsignDownloadProgress? progress,
  }) async {
    if (!isSupported) {
      throw StateError('Callsign lookup is not supported on this platform');
    }
    if (manifest.url.isEmpty) {
      throw const FormatException('Manifest has no download URL');
    }

    final bytes = await _fetch(manifest.url, progress);

    if (manifest.md5.isNotEmpty) {
      final digest = md5.convert(bytes).toString();
      if (digest.toLowerCase() != manifest.md5) {
        throw const FormatException('Downloaded database failed MD5 check');
      }
    }

    Uint8List dbBytes = bytes;
    if (manifest.compressed) {
      dbBytes = _extractDatabase(bytes);
    }

    // Validate the database parses before committing it to disk.
    CallsignDatabase.openBytes(dbBytes);

    final path = _filePath ??= await _resolvePath();
    final file = File(path);
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(dbBytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(path);

    await _openDatabase();

    // Persist metadata for the UI and multi-window sync.
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbVersion',
      data: manifest.version,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbRecordCount',
      data: manifest.recordCount,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbSourceDate',
      data: manifest.sourceDate,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbSizeBytes',
      data: dbBytes.length,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbUpdated',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );
  }

  /// Deletes the installed database and clears its metadata.
  Future<void> delete() async {
    await _db?.close();
    _db = null;
    final path = _filePath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    DataBroker.removeValue(deviceId, 'CallsignDbVersion');
    DataBroker.removeValue(deviceId, 'CallsignDbRecordCount');
    DataBroker.removeValue(deviceId, 'CallsignDbSourceDate');
    DataBroker.removeValue(deviceId, 'CallsignDbSizeBytes');
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbUpdated',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );
  }

  Future<String> _resolvePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}$_dbFileName';
  }

  /// Decompresses the downloaded xz (LZMA) stream into the raw database bytes.
  static Uint8List _extractDatabase(Uint8List xzBytes) {
    return Uint8List.fromList(XZDecoder().decodeBytes(xzBytes));
  }

  static Future<Uint8List> _fetch(
    String url,
    CallsignDownloadProgress? progress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Download failed (${response.statusCode}) for $url',
        );
      }
      final total = response.contentLength ?? 0;
      final builder = BytesBuilder(copy: false);
      int received = 0;
      await for (final chunk in response.stream) {
        builder.add(chunk);
        received += chunk.length;
        progress?.call(received, total);
      }
      return builder.toBytes();
    } finally {
      client.close();
    }
  }
}
