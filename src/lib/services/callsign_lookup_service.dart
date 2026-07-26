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

/// A hosted offline callsign database source (country/regulator).
enum CallsignDbSource {
  /// United States — FCC ULS amateur license data.
  us(
    id: 'us',
    manifestUrl:
        'https://ylianst.github.io/HTCommander/callsign/fcc_amateur_manifest.json',
    fileName: 'fcc_amateur.cdb',
    keyPrefix: 'CallsignDb',
  ),

  /// Canada — ISED amateur radio data extract.
  canada(
    id: 'ca',
    manifestUrl:
        'https://ylianst.github.io/HTCommander/callsign/ised_amateur_manifest.json',
    fileName: 'ised_amateur.cdb',
    keyPrefix: 'CallsignDbCa',
  );

  const CallsignDbSource({
    required this.id,
    required this.manifestUrl,
    required this.fileName,
    required this.keyPrefix,
  });

  /// Stable short identifier (`us`, `ca`).
  final String id;

  /// URL of this source's hosted manifest JSON.
  final String manifestUrl;

  /// File name the database is stored under in the application support dir.
  final String fileName;

  /// DataBroker key prefix for this source's persisted metadata. The US prefix
  /// is kept as `CallsignDb` for backward compatibility with existing installs.
  final String keyPrefix;
}

/// A single successful callsign lookup: the matching [record] and the
/// [source] database it came from.
class CallsignLookupResult {
  final CallsignDbSource source;
  final CallsignRecord record;
  const CallsignLookupResult(this.source, this.record);
}

/// Manages the offline US and Canadian amateur callsign databases: download,
/// storage, and lookups. Singleton, initialized once at startup via
/// [instance].`init()`.
///
/// Each database is a self-hosted compact binary file (see [CallsignDatabase]).
/// On desktop and mobile they are stored under the application support
/// directory; the web platform is unsupported (no persistent file system).
class CallsignLookupService {
  CallsignLookupService._();

  /// The shared instance.
  static final CallsignLookupService instance = CallsignLookupService._();

  /// DataBroker device id used for callsign database state.
  static const int deviceId = 0;

  final DataBrokerClient _broker = DataBrokerClient();

  /// Loaded databases, keyed by source. Absent entries are not installed.
  final Map<CallsignDbSource, CallsignDatabase> _dbs = {};

  /// Resolved on-disk file path per source.
  final Map<CallsignDbSource, String> _filePaths = {};

  bool _initialized = false;

  /// Whether offline callsign lookup is supported on this platform.
  bool get isSupported => !kIsWeb;

  /// Whether at least one database is loaded and ready for lookups.
  bool get isAvailable => _dbs.isNotEmpty;

  /// Whether the database for [source] is loaded and ready.
  bool isSourceAvailable(CallsignDbSource source) => _dbs.containsKey(source);

  /// Installed database version for [source], or empty when not installed.
  String installedVersion(CallsignDbSource source) =>
      DataBroker.getValue<String>(deviceId, '${source.keyPrefix}Version', '') ??
      '';

  /// Number of records in the installed [source] database (0 when none).
  int recordCount(CallsignDbSource source) =>
      DataBroker.getValue<int>(deviceId, '${source.keyPrefix}RecordCount', 0) ??
      0;

  /// Source date (`YYYYMMDD`) of the installed [source] database (0 when none).
  int sourceDate(CallsignDbSource source) =>
      DataBroker.getValue<int>(deviceId, '${source.keyPrefix}SourceDate', 0) ??
      0;

  /// Size on disk (bytes) of the installed [source] database (0 when none).
  int sizeBytes(CallsignDbSource source) =>
      DataBroker.getValue<int>(deviceId, '${source.keyPrefix}SizeBytes', 0) ?? 0;

  /// Resolves and opens every installed database. Safe to call once at startup;
  /// subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized || !isSupported) {
      _initialized = true;
      return;
    }
    _initialized = true;
    try {
      final dir = await getApplicationSupportDirectory();
      for (final source in CallsignDbSource.values) {
        final path = '${dir.path}${Platform.pathSeparator}${source.fileName}';
        _filePaths[source] = path;
        if (await File(path).exists()) {
          await _openDatabase(source);
        }
      }
    } catch (e) {
      debugPrint('CallsignLookupService: init failed: $e');
    }
  }

  Future<void> _openDatabase(CallsignDbSource source) async {
    final path = _filePaths[source];
    if (path == null) return;
    await _dbs.remove(source)?.close();
    try {
      _dbs[source] = await CallsignDatabase.open(path);
    } catch (e) {
      debugPrint('CallsignLookupService: failed to open ${source.id} db: $e');
    }
  }

  /// Looks up [callsign] (SSID ignored) across all loaded databases, returning
  /// the first match with its source. US and Canadian call sign spaces do not
  /// overlap, so at most one database matches. Returns null when no database is
  /// loaded or the callsign is not found in any of them.
  Future<CallsignLookupResult?> lookup(String callsign) async {
    if (callsign.trim().isEmpty) return null;
    for (final entry in _dbs.entries) {
      try {
        final record = await entry.value.lookup(callsign);
        if (record != null) {
          return CallsignLookupResult(entry.key, record);
        }
      } catch (e) {
        debugPrint('CallsignLookupService: lookup failed (${entry.key.id}): $e');
      }
    }
    return null;
  }

  /// Fetches the hosted [CallsignDbManifest] for [source]. Throws on network /
  /// parse errors.
  Future<CallsignDbManifest> fetchManifest(CallsignDbSource source) async {
    final response = await http.get(Uri.parse(source.manifestUrl));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Manifest download failed (${response.statusCode})',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CallsignDbManifest.fromJson(json);
  }

  /// Downloads and installs the [source] database described by [manifest],
  /// replacing any existing one. Reports progress via [progress].
  ///
  /// Throws on network errors, MD5 mismatch, or an invalid database file.
  Future<void> download(
    CallsignDbSource source,
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

    final path = _filePaths[source] ??= await _resolvePath(source);
    final file = File(path);
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(dbBytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(path);

    await _openDatabase(source);

    // Persist metadata for the UI and multi-window sync.
    final prefix = source.keyPrefix;
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}Version',
      data: manifest.version,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}RecordCount',
      data: manifest.recordCount,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}SourceDate',
      data: manifest.sourceDate,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}SizeBytes',
      data: dbBytes.length,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbUpdated',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );
  }

  /// Deletes the installed [source] database and clears its metadata.
  Future<void> delete(CallsignDbSource source) async {
    await _dbs.remove(source)?.close();
    final path = _filePaths[source];
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    final prefix = source.keyPrefix;
    DataBroker.removeValue(deviceId, '${prefix}Version');
    DataBroker.removeValue(deviceId, '${prefix}RecordCount');
    DataBroker.removeValue(deviceId, '${prefix}SourceDate');
    DataBroker.removeValue(deviceId, '${prefix}SizeBytes');
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbUpdated',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );
  }

  Future<String> _resolvePath(CallsignDbSource source) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}${source.fileName}';
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
