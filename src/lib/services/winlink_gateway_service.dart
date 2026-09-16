/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';

import '../winlink/winlink_gateway.dart';
import '../winlink/winlink_gateway_database.dart';
import 'data_broker.dart';
import 'data_broker_client.dart';
import 'tls_ca_bundle.dart';

/// Progress callback for the directory download: `(received, total)` bytes.
/// [total] may be 0 when the size is unknown.
typedef WinlinkDownloadProgress = void Function(int received, int total);

/// Metadata describing the hosted Winlink gateway directory (from the manifest).
class WinlinkDbManifest {
  final String version;
  final int sourceDate;
  final String url;
  final bool compressed;
  final int sizeBytes;
  final String md5;
  final int recordCount;
  final int gatewayCount;

  /// MD5 of the uncompressed records payload — the change-detection key that is
  /// independent of the feed's ever-changing status timestamps.
  final String recordsMd5;

  const WinlinkDbManifest({
    required this.version,
    required this.sourceDate,
    required this.url,
    required this.compressed,
    required this.sizeBytes,
    required this.md5,
    required this.recordCount,
    required this.gatewayCount,
    required this.recordsMd5,
  });

  factory WinlinkDbManifest.fromJson(Map<String, dynamic> json) {
    return WinlinkDbManifest(
      version: (json['version'] ?? '').toString(),
      sourceDate: (json['sourceDate'] as num?)?.toInt() ?? 0,
      url: (json['url'] ?? '').toString(),
      compressed: json['compressed'] == true,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      md5: (json['md5'] ?? '').toString().toLowerCase(),
      recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
      gatewayCount: (json['gatewayCount'] as num?)?.toInt() ?? 0,
      recordsMd5: (json['recordsMd5'] ?? '').toString().toLowerCase(),
    );
  }
}

/// Outcome of a [WinlinkGatewayService.update] call.
enum WinlinkUpdateResult { upToDate, updated }

/// Manages the offline Winlink 1200-baud packet gateway directory: download,
/// storage, and geographic/callsign queries. Singleton, initialised once at
/// startup via [instance].`init()`.
///
/// The directory is a tiny self-hosted binary (see [WinlinkGatewayDatabase]).
/// On desktop and mobile it is stored under the application support directory;
/// the web platform is unsupported (no persistent file system).
class WinlinkGatewayService {
  WinlinkGatewayService._();

  static final WinlinkGatewayService instance = WinlinkGatewayService._();

  /// DataBroker device id used for Winlink directory state.
  static const int deviceId = 0;

  /// Hosted manifest (GitHub Pages).
  static const String manifestUrl =
      'https://ylianst.github.io/HTCommander/winlink/winlink_packet_manifest.json';

  /// File name the directory is cached under in the app support dir.
  static const String fileName = 'winlink_packet.wdb';

  // DataBroker keys for the installed directory's metadata.
  static const String _versionKey = 'WinlinkDbVersion';
  static const String _sourceDateKey = 'WinlinkDbSourceDate';
  static const String _recordsMd5Key = 'WinlinkDbRecordsMd5';
  static const String _gatewayCountKey = 'WinlinkDbGatewayCount';
  static const String _lastCheckKey = 'WinlinkDbLastCheck';

  /// DataBroker key for the opt-in "auto-download" preference.
  static const String autoUpdateKey = 'WinlinkDbAutoUpdate';

  /// Broadcast (store:false) when the loaded directory changes.
  static const String updatedEvent = 'WinlinkDbUpdated';

  /// Refresh at most once every 3 days in the background.
  static const Duration _autoCheckThrottle = Duration(days: 3);

  final DataBrokerClient _broker = DataBrokerClient();

  bool _initialized = false;
  bool _updating = false;
  WinlinkGatewayDatabase? _db;

  /// Whether the offline directory is supported on this platform.
  bool get isSupported => !kIsWeb;

  /// Whether the directory is loaded and ready to query.
  bool get isAvailable => _db != null;

  /// The loaded directory, or null when none is installed.
  WinlinkGatewayDatabase? get database => _db;

  /// Installed version string (e.g. `2026.09.16`), empty when none.
  String get installedVersion =>
      DataBroker.getValue<String>(deviceId, _versionKey, '') ?? '';

  /// Installed data date (`YYYYMMDD`), 0 when none.
  int get installedSourceDate =>
      DataBroker.getValue<int>(deviceId, _sourceDateKey, 0) ?? 0;

  /// Number of gateways in the installed directory (0 when none).
  int get gatewayCount =>
      DataBroker.getValue<int>(deviceId, _gatewayCountKey, 0) ?? 0;

  /// Whether the directory is refreshed automatically in the background while
  /// the app runs, over a non-metered connection only. Persisted, opt-in.
  bool get autoDownload =>
      DataBroker.getValue<bool>(deviceId, autoUpdateKey, false) ?? false;

  set autoDownload(bool value) {
    _broker.dispatch(
        deviceId: deviceId, name: autoUpdateKey, data: value, store: true);
    if (value) unawaited(_maybeAutoUpdate());
  }

  /// Loads the cached directory (if any) and kicks off a throttled background
  /// refresh. Safe to call once at startup; subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized || !isSupported) {
      _initialized = true;
      return;
    }
    _initialized = true;
    try {
      final path = await _resolvePath();
      final file = File(path);
      if (await file.exists()) {
        _db = WinlinkGatewayDatabase.fromBytes(await file.readAsBytes());
        _notifyUpdated();
      }
    } catch (e) {
      debugPrint('WinlinkGatewayService: failed to load cached directory: $e');
    }
    unawaited(_maybeAutoUpdate());
  }

  /// The [count] gateways nearest to ([lat], [lon]), closest first.
  List<WinlinkGateway> nearest(double lat, double lon, {int count = 20}) =>
      _db?.nearest(lat, lon, count: count) ?? const [];

  /// Gateways inside the given bounding box (for viewport culling).
  List<WinlinkGateway> withinBounds(
    double minLat,
    double minLon,
    double maxLat,
    double maxLon,
  ) =>
      _db?.withinBounds(minLat, minLon, maxLat, maxLon) ?? const [];

  /// Fetches the hosted [WinlinkDbManifest]. Throws on network/parse errors.
  Future<WinlinkDbManifest> fetchManifest() async {
    final body = await _getManifestBody(manifestUrl);
    return WinlinkDbManifest.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Downloads and installs the directory described by [manifest] when it is
  /// newer than what is installed (compared by [WinlinkDbManifest.recordsMd5]),
  /// or always when [force] is set. Returns what happened.
  ///
  /// Throws on network errors, MD5 mismatch, or an invalid file.
  Future<WinlinkUpdateResult> update(
    WinlinkDbManifest manifest, {
    bool force = false,
    WinlinkDownloadProgress? progress,
  }) async {
    if (!isSupported) {
      throw StateError('Winlink directory is not supported on this platform');
    }
    if (manifest.url.isEmpty) {
      throw const FormatException('Winlink manifest has no download URL');
    }
    final installedRecordsMd5 =
        DataBroker.getValue<String>(deviceId, _recordsMd5Key, '') ?? '';
    if (!force &&
        _db != null &&
        manifest.recordsMd5.isNotEmpty &&
        manifest.recordsMd5 == installedRecordsMd5) {
      return WinlinkUpdateResult.upToDate;
    }

    final downloaded = await _fetch(manifest.url, progress);
    if (manifest.md5.isNotEmpty) {
      final got = md5.convert(downloaded).toString();
      if (got != manifest.md5) {
        throw StateError(
            'Winlink directory MD5 mismatch (expected ${manifest.md5}, got $got)');
      }
    }
    final raw = manifest.compressed
        ? Uint8List.fromList(XZDecoder().decodeBytes(downloaded))
        : downloaded;

    // Validate before persisting so a corrupt download can't replace a good file.
    final parsed = WinlinkGatewayDatabase.fromBytes(raw);

    final path = await _resolvePath();
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(raw, flush: true);
    final target = File(path);
    if (await target.exists()) await target.delete();
    await tmp.rename(path);

    _db = parsed;
    _broker.dispatch(
        deviceId: deviceId, name: _versionKey, data: manifest.version, store: true);
    _broker.dispatch(
        deviceId: deviceId,
        name: _sourceDateKey,
        data: manifest.sourceDate,
        store: true);
    _broker.dispatch(
        deviceId: deviceId,
        name: _recordsMd5Key,
        data: manifest.recordsMd5,
        store: true);
    _broker.dispatch(
        deviceId: deviceId,
        name: _gatewayCountKey,
        data: parsed.gatewayCount,
        store: true);
    _notifyUpdated();
    return WinlinkUpdateResult.updated;
  }

  /// Fetches the manifest and installs it if newer. Convenience wrapper used by
  /// the UI's "check for updates" action.
  Future<WinlinkUpdateResult> checkForUpdate({
    bool force = false,
    WinlinkDownloadProgress? progress,
  }) async {
    final manifest = await fetchManifest();
    return update(manifest, force: force, progress: progress);
  }

  /// Background refresh: gated by a 3-day throttle and a non-metered
  /// connection. Never throws; failures are logged and retried next launch.
  Future<void> _maybeAutoUpdate() async {
    if (!isSupported || _updating || !autoDownload) return;
    final last = DataBroker.getValue<int>(deviceId, _lastCheckKey, 0) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_db != null && now - last < _autoCheckThrottle.inMilliseconds) return;
    if (!await _connectionAllowsUpdate()) return;
    _updating = true;
    try {
      final result = await checkForUpdate();
      // Only record a completed check when we actually reached the server.
      _broker.dispatch(
          deviceId: deviceId, name: _lastCheckKey, data: now, store: true);
      if (result == WinlinkUpdateResult.updated) {
        debugPrint('WinlinkGatewayService: directory updated ($installedVersion).');
      }
    } catch (e) {
      debugPrint('WinlinkGatewayService: background refresh failed: $e');
    } finally {
      _updating = false;
    }
  }

  Future<bool> _connectionAllowsUpdate() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
        return false;
      }
      // Refresh over wifi/ethernet/vpn; skip cellular-only to spare mobile data.
      return results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn);
    } catch (_) {
      return false;
    }
  }

  void _notifyUpdated() {
    _broker.dispatch(
        deviceId: deviceId, name: updatedEvent, data: now(), store: false);
  }

  int now() => DateTime.now().millisecondsSinceEpoch;

  Future<String> _resolvePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  // ── HTTP with bundled-CA-roots fallback (mirrors CallsignLookupService) ────

  static Future<String> _getManifestBody(String url) async {
    try {
      return await _getWith(null, url);
    } on HandshakeException {
      final context = await bundledCaRootsContext();
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
            'Manifest download failed (${response.statusCode})');
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  static Future<Uint8List> _fetch(
      String url, WinlinkDownloadProgress? progress) async {
    try {
      return await _fetchWith(null, url, progress);
    } on HandshakeException {
      final context = await bundledCaRootsContext();
      if (context == null) rethrow;
      return await _fetchWith(context, url, progress);
    }
  }

  static Future<Uint8List> _fetchWith(
    SecurityContext? context,
    String url,
    WinlinkDownloadProgress? progress,
  ) async {
    final client = _clientFor(context);
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw http.ClientException('Download failed (${response.statusCode}) for $url');
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

  static http.Client _clientFor(SecurityContext? context) =>
      context == null ? http.Client() : IOClient(HttpClient(context: context));
}
