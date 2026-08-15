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
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../callsign/callsign_database.dart';
import '../callsign/callsign_record.dart';
import 'data_broker.dart';
import 'data_broker_client.dart';
import 'tls_ca_bundle.dart';

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

  /// Optional incremental overlay published on top of this (baseline) database.
  /// Present from manifest schema version 2 onward; null for legacy manifests.
  final CallsignDbOverlay? overlay;

  const CallsignDbManifest({
    required this.version,
    required this.sourceDate,
    required this.url,
    required this.compressed,
    required this.sizeBytes,
    required this.md5,
    required this.recordCount,
    this.overlay,
  });

  factory CallsignDbManifest.fromJson(Map<String, dynamic> json) {
    final overlayJson = json['overlay'];
    return CallsignDbManifest(
      version: (json['version'] ?? '').toString(),
      sourceDate: (json['sourceDate'] as num?)?.toInt() ?? 0,
      url: (json['url'] ?? '').toString(),
      compressed: json['compressed'] == true,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      md5: (json['md5'] ?? '').toString().toLowerCase(),
      recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
      overlay: overlayJson is Map<String, dynamic>
          ? CallsignDbOverlay.fromJson(overlayJson)
          : null,
    );
  }
}

/// Metadata describing the small incremental overlay database that carries the
/// changes made since the baseline was published (manifest schema v2+). The
/// overlay is itself a `.cdb` in the same format, searched before the baseline.
class CallsignDbOverlay {
  /// Human-readable overlay version (e.g. a date like `2026.07.19`).
  final String version;

  /// Data date of the overlay as `YYYYMMDD`, or 0 when unknown.
  final int sourceDate;

  /// URL of the overlay file to download.
  final String url;

  /// Whether [url] points to an xz-compressed `.cdb`.
  final bool compressed;

  /// Size of the overlay download in bytes (0 when unknown).
  final int sizeBytes;

  /// Lower-case hex MD5 of the overlay download, or empty to skip verification.
  final String md5;

  /// Number of records the overlay carries. 0 means "no overlay" (e.g. right
  /// after a fresh baseline was promoted).
  final int recordCount;

  const CallsignDbOverlay({
    required this.version,
    required this.sourceDate,
    required this.url,
    required this.compressed,
    required this.sizeBytes,
    required this.md5,
    required this.recordCount,
  });

  factory CallsignDbOverlay.fromJson(Map<String, dynamic> json) {
    return CallsignDbOverlay(
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
    overlayFileName: 'fcc_amateur_overlay.cdb',
    keyPrefix: 'CallsignDb',
  ),

  /// Canada — ISED amateur radio data extract.
  canada(
    id: 'ca',
    manifestUrl:
        'https://ylianst.github.io/HTCommander/callsign/ised_amateur_manifest.json',
    fileName: 'ised_amateur.cdb',
    overlayFileName: 'ised_amateur_overlay.cdb',
    keyPrefix: 'CallsignDbCa',
  );

  const CallsignDbSource({
    required this.id,
    required this.manifestUrl,
    required this.fileName,
    required this.overlayFileName,
    required this.keyPrefix,
  });

  /// Stable short identifier (`us`, `ca`).
  final String id;

  /// URL of this source's hosted manifest JSON.
  final String manifestUrl;

  /// File name the baseline database is stored under in the application support
  /// dir.
  final String fileName;

  /// File name the incremental overlay database is stored under, alongside the
  /// baseline.
  final String overlayFileName;

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

/// Outcome of an [CallsignLookupService.update] call.
enum CallsignUpdateResult {
  /// Nothing to do; the installed baseline and overlay already match the
  /// manifest.
  upToDate,

  /// A fresh full baseline was downloaded (and its overlay reconciled).
  updatedBaseline,

  /// Only the incremental overlay was downloaded; the baseline was unchanged.
  updatedOverlay,
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

  /// Loaded incremental overlays, keyed by source. Searched before the matching
  /// baseline in [_dbs]. Absent entries mean no overlay is installed.
  final Map<CallsignDbSource, CallsignDatabase> _overlays = {};

  /// Resolved on-disk baseline file path per source.
  final Map<CallsignDbSource, String> _filePaths = {};

  /// Resolved on-disk overlay file path per source.
  final Map<CallsignDbSource, String> _overlayFilePaths = {};

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
      DataBroker.getValue<int>(deviceId, '${source.keyPrefix}SizeBytes', 0) ??
      0;

  /// Data date (`YYYYMMDD`) of the installed incremental overlay for [source],
  /// or 0 when no overlay is tracked.
  int overlaySourceDate(CallsignDbSource source) =>
      DataBroker.getValue<int>(
        deviceId,
        '${source.keyPrefix}OverlaySourceDate',
        0,
      ) ??
      0;

  /// Number of records in the installed overlay for [source] (0 when none).
  int overlayRecordCount(CallsignDbSource source) =>
      DataBroker.getValue<int>(
        deviceId,
        '${source.keyPrefix}OverlayRecordCount',
        0,
      ) ??
      0;

  /// Size on disk (bytes) of the installed overlay for [source] (0 when none).
  int overlaySizeBytes(CallsignDbSource source) =>
      DataBroker.getValue<int>(
        deviceId,
        '${source.keyPrefix}OverlaySizeBytes',
        0,
      ) ??
      0;

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
      final sep = Platform.pathSeparator;
      for (final source in CallsignDbSource.values) {
        final path = '${dir.path}$sep${source.fileName}';
        _filePaths[source] = path;
        if (await File(path).exists()) {
          await _openDatabase(source);
        }
        final overlayPath = '${dir.path}$sep${source.overlayFileName}';
        _overlayFilePaths[source] = overlayPath;
        if (await File(overlayPath).exists()) {
          await _openOverlay(source);
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

  Future<void> _openOverlay(CallsignDbSource source) async {
    final path = _overlayFilePaths[source];
    if (path == null) return;
    await _overlays.remove(source)?.close();
    try {
      _overlays[source] = await CallsignDatabase.open(path);
    } catch (e) {
      debugPrint(
        'CallsignLookupService: failed to open ${source.id} overlay: $e',
      );
    }
  }

  /// Looks up [callsign] (SSID ignored) across all loaded databases, returning
  /// the first match with its source. For each source the incremental overlay
  /// is searched **before** the baseline, so an updated record shadows the
  /// baseline one. US and Canadian call sign spaces do not overlap, so at most
  /// one source matches. Returns null when nothing is loaded or no match.
  Future<CallsignLookupResult?> lookup(String callsign) async {
    if (callsign.trim().isEmpty) return null;
    for (final source in CallsignDbSource.values) {
      // Overlay first (fresher), then the baseline it sits on top of.
      final record = await lookupInOrder(
        [_overlays[source], _dbs[source]],
        callsign,
        onError: (e) => debugPrint(
          'CallsignLookupService: lookup failed (${source.id}): $e',
        ),
      );
      if (record != null) {
        return CallsignLookupResult(source, record);
      }
    }
    return null;
  }

  /// Looks up [callsign] across [dbs] in order, returning the first match. Null
  /// entries are skipped and per-database errors are reported via [onError] and
  /// otherwise ignored. Exposed for testing the overlay-before-baseline order.
  @visibleForTesting
  static Future<CallsignRecord?> lookupInOrder(
    List<CallsignDatabase?> dbs,
    String callsign, {
    void Function(Object error)? onError,
  }) async {
    for (final db in dbs) {
      if (db == null) continue;
      try {
        final record = await db.lookup(callsign);
        if (record != null) return record;
      } catch (e) {
        onError?.call(e);
      }
    }
    return null;
  }

  /// Fetches the hosted [CallsignDbManifest] for [source]. Throws on network /
  /// parse errors.
  Future<CallsignDbManifest> fetchManifest(CallsignDbSource source) async {
    final body = await _getManifestBody(source.manifestUrl);
    final json = jsonDecode(body) as Map<String, dynamic>;
    return CallsignDbManifest.fromJson(json);
  }

  /// GETs [url] as text, retrying with the bundled CA roots if the machine's own
  /// trust store can't verify the TLS chain (see [_bundledRootsContext]).
  static Future<String> _getManifestBody(String url) async {
    try {
      return await _getWith(null, url);
    } on HandshakeException {
      final context = await _bundledRootsContext();
      if (context == null) rethrow;
      return await _getWith(context, url);
    }
  }

  static Future<String> _getWith(SecurityContext? context, String url) async {
    final client = _clientFor(context);
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Manifest download failed (${response.statusCode})',
        );
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  /// Brings the [source] databases in line with [manifest], downloading only
  /// what changed: a fresh full baseline when the baseline moved (its overlay is
  /// reconciled afterwards), otherwise just the small incremental overlay.
  /// Reports progress via [progress]. Returns what, if anything, was updated.
  ///
  /// Throws on network errors, MD5 mismatch, or an invalid database file.
  Future<CallsignUpdateResult> update(
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

    // A promotion (or a first install) means the baseline itself moved; pull it
    // and then reconcile the overlay against the new baseline.
    final needBaseline =
        !isSourceAvailable(source) || sourceDate(source) != manifest.sourceDate;
    if (needBaseline) {
      await _installBaseline(source, manifest, progress);
      // The overlay is small; skip the progress-bar churn for it here.
      await _reconcileOverlay(source, manifest, null);
      _dispatchUpdatedPing();
      return CallsignUpdateResult.updatedBaseline;
    }

    // Baseline is current; the overlay may still have advanced.
    final wantedOverlayDate =
        manifest.overlay?.sourceDate ?? manifest.sourceDate;
    if (overlaySourceDate(source) != wantedOverlayDate) {
      await _reconcileOverlay(source, manifest, progress);
      _dispatchUpdatedPing();
      return CallsignUpdateResult.updatedOverlay;
    }

    return CallsignUpdateResult.upToDate;
  }

  /// Installs the overlay described by [manifest] when it carries records, or
  /// removes any installed overlay when the manifest has none (e.g. just after a
  /// baseline promotion). Records the overlay's data date either way.
  Future<void> _reconcileOverlay(
    CallsignDbSource source,
    CallsignDbManifest manifest,
    CallsignDownloadProgress? progress,
  ) async {
    final overlay = manifest.overlay;
    if (overlay != null && overlay.recordCount > 0 && overlay.url.isNotEmpty) {
      await _installOverlay(source, overlay, progress);
    } else {
      await _removeOverlayFile(source);
      final prefix = source.keyPrefix;
      _broker.dispatch(
        deviceId: deviceId,
        name: '${prefix}OverlaySourceDate',
        data: overlay?.sourceDate ?? manifest.sourceDate,
      );
      _broker.dispatch(
        deviceId: deviceId,
        name: '${prefix}OverlayRecordCount',
        data: 0,
      );
      _broker.dispatch(
        deviceId: deviceId,
        name: '${prefix}OverlaySizeBytes',
        data: 0,
      );
    }
  }

  Future<void> _installBaseline(
    CallsignDbSource source,
    CallsignDbManifest manifest,
    CallsignDownloadProgress? progress,
  ) async {
    final dbBytes = await _downloadVerifyExtract(
      manifest.url,
      manifest.md5,
      manifest.compressed,
      progress,
    );
    final path = _filePaths[source] ??= await _resolvePath(source);
    // Release the open handle first; Windows won't let us replace a file that
    // is still mapped by the running instance.
    await _dbs.remove(source)?.close();
    await _writeDbFile(path, dbBytes);
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
  }

  Future<void> _installOverlay(
    CallsignDbSource source,
    CallsignDbOverlay overlay,
    CallsignDownloadProgress? progress,
  ) async {
    final dbBytes = await _downloadVerifyExtract(
      overlay.url,
      overlay.md5,
      overlay.compressed,
      progress,
    );
    final path = _overlayFilePaths[source] ??= await _resolveOverlayPath(
      source,
    );
    // Release the open handle first; Windows won't let us replace a file that
    // is still mapped by the running instance.
    await _overlays.remove(source)?.close();
    await _writeDbFile(path, dbBytes);
    await _openOverlay(source);

    final prefix = source.keyPrefix;
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}OverlayVersion',
      data: overlay.version,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}OverlaySourceDate',
      data: overlay.sourceDate,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}OverlayRecordCount',
      data: overlay.recordCount,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: '${prefix}OverlaySizeBytes',
      data: dbBytes.length,
    );
  }

  /// Downloads [url], verifies [md5hex] (when set), decompresses when
  /// [compressed], and validates the result parses as a database. Returns the
  /// raw `.cdb` bytes ready to write.
  Future<Uint8List> _downloadVerifyExtract(
    String url,
    String md5hex,
    bool compressed,
    CallsignDownloadProgress? progress,
  ) async {
    final bytes = await _fetch(url, progress);
    if (md5hex.isNotEmpty) {
      final digest = md5.convert(bytes).toString();
      if (digest.toLowerCase() != md5hex) {
        throw const FormatException('Downloaded database failed MD5 check');
      }
    }
    final dbBytes = compressed ? _extractDatabase(bytes) : bytes;
    // Validate the database parses before committing it to disk.
    CallsignDatabase.openBytes(dbBytes);
    return dbBytes;
  }

  /// Atomically writes [bytes] to [path] via a temp file and rename.
  Future<void> _writeDbFile(String path, Uint8List bytes) async {
    final file = File(path);
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(path);
  }

  Future<void> _removeOverlayFile(CallsignDbSource source) async {
    await _overlays.remove(source)?.close();
    final path = _overlayFilePaths[source];
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _dispatchUpdatedPing() {
    _broker.dispatch(
      deviceId: deviceId,
      name: 'CallsignDbUpdated',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );
  }

  /// Deletes the installed [source] database (baseline and overlay) and clears
  /// its metadata.
  Future<void> delete(CallsignDbSource source) async {
    await _dbs.remove(source)?.close();
    final path = _filePaths[source];
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _removeOverlayFile(source);
    final prefix = source.keyPrefix;
    DataBroker.removeValue(deviceId, '${prefix}Version');
    DataBroker.removeValue(deviceId, '${prefix}RecordCount');
    DataBroker.removeValue(deviceId, '${prefix}SourceDate');
    DataBroker.removeValue(deviceId, '${prefix}SizeBytes');
    DataBroker.removeValue(deviceId, '${prefix}OverlayVersion');
    DataBroker.removeValue(deviceId, '${prefix}OverlaySourceDate');
    DataBroker.removeValue(deviceId, '${prefix}OverlayRecordCount');
    DataBroker.removeValue(deviceId, '${prefix}OverlaySizeBytes');
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

  Future<String> _resolveOverlayPath(CallsignDbSource source) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}${source.overlayFileName}';
  }

  /// Decompresses the downloaded xz (LZMA) stream into the raw database bytes.
  static Uint8List _extractDatabase(Uint8List xzBytes) {
    return Uint8List.fromList(XZDecoder().decodeBytes(xzBytes));
  }

  static Future<Uint8List> _fetch(
    String url,
    CallsignDownloadProgress? progress,
  ) async {
    try {
      return await _fetchWith(null, url, progress);
    } on HandshakeException {
      // The machine's own trust store couldn't verify the chain (outdated OS
      // roots, etc.); retry trusting the bundled Mozilla CA roots. The handshake
      // fails before any bytes stream, so no progress is double-counted.
      final context = await _bundledRootsContext();
      if (context == null) rethrow;
      return await _fetchWith(context, url, progress);
    }
  }

  static Future<Uint8List> _fetchWith(
    SecurityContext? context,
    String url,
    CallsignDownloadProgress? progress,
  ) async {
    final client = _clientFor(context);
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

  /// A client bound to [context], or the plain default client when null.
  static http.Client _clientFor(SecurityContext? context) =>
      context == null ? http.Client() : IOClient(HttpClient(context: context));

  /// Fallback context trusting the bundled Mozilla CA roots (see
  /// [bundledCaRootsContext]).
  static Future<SecurityContext?> _bundledRootsContext() =>
      bundledCaRootsContext();
}
