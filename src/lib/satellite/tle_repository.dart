/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'satellite_models.dart';

/// Loads and refreshes amateur-satellite orbital elements (TLEs).
///
/// On [load] the cached TLE file on disk is read; if absent, the bundled seed
/// asset (`assets/satellites/amateur.tle`) is used so the feature works offline
/// on first run. [refresh] fetches the current Celestrak `amateur` group, but
/// only when the cache is older than [minRefreshInterval] — CelesTrak
/// firewall-blocks clients that re-download unchanged data, so this gate is
/// mandatory, not an optimisation.
class TleRepository {
  /// Celestrak GP query for the amateur-radio satellite group (3LE format).
  static const String _celestrakUrl =
      'https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=TLE';

  /// Bundled seed used when there is no cache yet.
  static const String _seedAsset = 'assets/satellites/amateur.tle';

  /// CelesTrak updates GP data only every ~2 hours; never refetch more often.
  static const Duration minRefreshInterval = Duration(hours: 2);

  final List<SatelliteTle> _tles = [];
  File? _cacheFile;

  /// The TLEs currently loaded in memory.
  List<SatelliteTle> get tles => List<SatelliteTle>.unmodifiable(_tles);

  /// Reads the cached TLE file (or the seed asset if there is no cache yet)
  /// into memory. Safe to call once at startup; never throws.
  Future<void> load() async {
    await _resolveCacheFile();

    String? text;
    final cache = _cacheFile;
    if (cache != null) {
      try {
        if (await cache.exists()) text = await cache.readAsString();
      } catch (e) {
        debugPrint('TleRepository: failed to read cache: $e');
      }
    }

    text ??= await _readSeed();
    _parseInto(text);
  }

  /// Fetches fresh TLEs from CelesTrak when the cache is stale, replacing the
  /// in-memory list and cache file on success. Returns true when new data was
  /// downloaded and applied. Never throws.
  ///
  /// Refuses to run when the cache is younger than [minRefreshInterval], even
  /// for a user-initiated refresh, to respect CelesTrak's usage policy.
  Future<bool> refresh() async {
    if (kIsWeb) return false;
    if (!await _isCacheStale()) return false;

    http.Client? client;
    try {
      client = http.Client();
      final response = await client
          .get(Uri.parse(_celestrakUrl))
          .timeout(const Duration(seconds: 20));

      // Any non-2xx (301 redirect, 403 block, 404, 5xx) must not be retried in
      // a loop; log and keep the existing data. See CelesTrak usage policy.
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'TleRepository: refresh got HTTP ${response.statusCode}; '
          'keeping cached TLEs.',
        );
        return false;
      }

      final body = response.body;
      final parsed = SatelliteTle.parseThreeLine(body);
      if (parsed.isEmpty) {
        debugPrint('TleRepository: refresh returned no valid TLEs.');
        return false;
      }

      await _writeCache(body);
      _tles
        ..clear()
        ..addAll(parsed);
      return true;
    } catch (e) {
      debugPrint('TleRepository: refresh failed: $e');
      return false;
    } finally {
      client?.close();
    }
  }

  Future<void> _resolveCacheFile() async {
    if (kIsWeb) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}HTCommander'
        '${Platform.pathSeparator}Satellites',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      _cacheFile = File('${dir.path}${Platform.pathSeparator}amateur.tle');
    } catch (e) {
      debugPrint('TleRepository: failed to resolve cache dir: $e');
      _cacheFile = null;
    }
  }

  Future<bool> _isCacheStale() async {
    final cache = _cacheFile;
    if (cache == null) return true;
    try {
      if (!await cache.exists()) return true;
      final age = DateTime.now().difference(await cache.lastModified());
      return age >= minRefreshInterval;
    } catch (_) {
      return true;
    }
  }

  Future<void> _writeCache(String text) async {
    final cache = _cacheFile;
    if (cache == null) return;
    try {
      await cache.writeAsString(text, flush: true);
    } catch (e) {
      debugPrint('TleRepository: failed to write cache: $e');
    }
  }

  Future<String> _readSeed() async {
    try {
      return await rootBundle.loadString(_seedAsset);
    } catch (e) {
      debugPrint('TleRepository: failed to load seed asset: $e');
      return '';
    }
  }

  void _parseInto(String text) {
    final parsed = SatelliteTle.parseThreeLine(text);
    _tles
      ..clear()
      ..addAll(parsed);
  }
}
