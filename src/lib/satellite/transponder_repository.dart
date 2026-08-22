/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'satellite_models.dart';
import '../utils/num_parsing.dart';

/// Loads and refreshes the FM transponder catalog for amateur satellites.
///
/// On [load] the cached catalog (or the bundled seed
/// `assets/satellites/transponders.json`) is read into memory. [refresh] pulls
/// the SatNOGS DB transmitters list and keeps only active FM cross-band
/// repeaters whose up- and downlink both fall inside a frequency range this
/// radio can tune, so the result is limited to satellites the radio can
/// actually work.
class TransponderRepository {
  /// SatNOGS DB transmitters endpoint (JSON).
  static const String _satnogsUrl =
      'https://db.satnogs.org/api/transmitters/?format=json';

  /// Bundled seed used when there is no cache yet.
  static const String _seedAsset = 'assets/satellites/transponders.json';

  /// Refresh no more than once per day; the transponder catalog rarely changes.
  static const Duration minRefreshInterval = Duration(hours: 24);

  /// Frequency ranges (Hz) this radio can tune in FM: 2 m and 70 cm segments.
  static const List<List<int>> _radioFmRangesHz = [
    [136000000, 174000000],
    [300000000, 550000000],
  ];

  final Map<int, List<SatelliteTransponder>> _byNorad = {};
  File? _cacheFile;

  /// The transponder catalog keyed by NORAD catalog number. Each value is the
  /// list of amateur usages for that satellite (FM repeater, APRS, SSTV, …).
  Map<int, List<SatelliteTransponder>> get byNorad =>
      Map<int, List<SatelliteTransponder>>.unmodifiable(_byNorad);

  /// True when [hz] is within a frequency range this radio can tune in FM.
  static bool isRadioTunable(int? hz) {
    if (hz == null) return false;
    for (final range in _radioFmRangesHz) {
      if (hz >= range[0] && hz <= range[1]) return true;
    }
    return false;
  }

  /// Index of the radio FM band (2 m vs 70 cm) containing [hz], or null.
  static int? _bandIndex(int? hz) {
    if (hz == null) return null;
    for (var i = 0; i < _radioFmRangesHz.length; i++) {
      final range = _radioFmRangesHz[i];
      if (hz >= range[0] && hz <= range[1]) return i;
    }
    return null;
  }

  /// True when up- and downlink fall in different radio FM bands — the mark of
  /// a real cross-band repeater rather than a same-band split (e.g. a voice or
  /// packet channel that shares the 2 m band).
  static bool _isCrossBand(SatelliteTransponder t) {
    final up = _bandIndex(t.uplinkHz);
    final down = _bandIndex(t.downlinkHz);
    return up != null && down != null && up != down;
  }

  /// Reads the cached catalog (or seed asset) into memory. Never throws.
  Future<void> load() async {
    await _resolveCacheFile();

    String? text;
    final cache = _cacheFile;
    if (cache != null) {
      try {
        if (await cache.exists()) text = await cache.readAsString();
      } catch (e) {
        debugPrint('TransponderRepository: failed to read cache: $e');
      }
    }

    text ??= await _readSeed();
    _parseOwnFormat(text);

    // Overlay the bundled seed so every curated usage (and any curated bird the
    // cache predates, e.g. added in an app update) is present; online data
    // already loaded above wins per usage, so this only fills gaps.
    _mergeSeed(_byNorad, await _readSeed());
  }

  /// Fetches the SatNOGS transmitter list when the cache is stale, filters it
  /// to radio-workable FM repeaters, and replaces the in-memory catalog and
  /// cache on success. Returns true when new data was applied. Never throws.
  Future<bool> refresh() async {
    if (kIsWeb) return false;
    if (!await _isCacheStale()) return false;

    http.Client? client;
    try {
      client = http.Client();
      final response = await client
          .get(Uri.parse(_satnogsUrl))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'TransponderRepository: refresh got HTTP ${response.statusCode}; '
          'keeping cached catalog.',
        );
        return false;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        debugPrint('TransponderRepository: unexpected SatNOGS payload.');
        return false;
      }

      // One FM cross-band repeater per satellite (the qualifying usage that
      // decides which birds appear in the list).
      final repeaters = <int, SatelliteTransponder>{};
      for (final entry in decoded.whereType<Map>()) {
        final t = _fromSatnogs(Map<String, dynamic>.from(entry));
        if (t == null || !t.isWorkableFm) continue;
        if (!isRadioTunable(t.uplinkHz) || !isRadioTunable(t.downlinkHz)) {
          continue;
        }
        // Prefer a true cross-band repeater; only upgrade a same-band pick to a
        // cross-band one, never the reverse. Otherwise a same-band split (e.g.
        // the ISS crew-voice 144.49/145.80 channel) can be picked first and,
        // labeled 'Repeater', override the curated cross-band repeater.
        final existing = repeaters[t.noradId];
        if (existing != null && (_isCrossBand(existing) || !_isCrossBand(t))) {
          continue;
        }
        // Carry over a CTCSS tone from the seed/previous catalog, which SatNOGS
        // omits.
        repeaters[t.noradId] = _withCarriedTone(t);
      }

      if (repeaters.isEmpty) {
        debugPrint('TransponderRepository: no workable FM birds in payload.');
        return false;
      }

      // Overlay the bundled seed so curated usages (APRS/SSTV/voice) and any
      // curated bird SatNOGS didn't return survive the refresh; the online
      // repeater above wins per usage.
      final next = <int, List<SatelliteTransponder>>{
        for (final e in repeaters.entries) e.key: [e.value],
      };
      _mergeSeed(next, await _readSeed());

      await _writeCache(next);
      _byNorad
        ..clear()
        ..addAll(next);
      return true;
    } catch (e) {
      debugPrint('TransponderRepository: refresh failed: $e');
      return false;
    } finally {
      client?.close();
    }
  }

  /// Copies [t] but preserves an existing CTCSS tone for the same satellite
  /// when the fresh SatNOGS record has none.
  SatelliteTransponder _withCarriedTone(SatelliteTransponder t) {
    if (t.ctcssHz != null) return t;
    final priorList = _byNorad[t.noradId];
    final prior = (priorList == null || priorList.isEmpty) ? null : priorList.first;
    if (prior?.ctcssHz == null) return t;
    return SatelliteTransponder(
      noradId: t.noradId,
      name: t.name,
      usage: t.usage,
      uplinkHz: t.uplinkHz,
      downlinkHz: t.downlinkHz,
      mode: t.mode,
      ctcssHz: prior!.ctcssHz,
      inverting: t.inverting,
      status: t.status,
    );
  }

  /// Overlays the bundled seed onto [target]: adds curated birds the catalog
  /// lacks, appends any curated usage not already listed for a bird it has, and
  /// corrects a usage the online/cached catalog already carries. The seed is
  /// hand-verified, so for a usage it curates its frequencies, tone and mode
  /// win — otherwise a same-band SatNOGS entry mislabeled 'Repeater' (e.g. the
  /// ISS crew-voice split) would keep overriding the curated cross-band
  /// repeater in the cache. Idempotent, so it is safe to call on both the
  /// cached catalog and a fresh online one.
  void _mergeSeed(
    Map<int, List<SatelliteTransponder>> target,
    String seedText,
  ) {
    final seed = _seedGrouped(seedText);
    seed.forEach((noradId, usages) {
      final existing = target[noradId];
      if (existing == null) {
        target[noradId] = List<SatelliteTransponder>.of(usages);
        return;
      }
      for (final usage in usages) {
        final index = existing.indexWhere(
          (t) => t.usage.toLowerCase() == usage.usage.toLowerCase(),
        );
        if (index < 0) {
          existing.add(usage);
          continue;
        }
        // Curated seed wins; keep an online helpful link only if the seed
        // lacks one (SatNOGS entries carry no infoUrl today, so this is rare).
        existing[index] =
            usage.infoUrl == null && existing[index].infoUrl != null
                ? usage.copyWith(infoUrl: existing[index].infoUrl)
                : usage;
      }
    });
  }

  /// Parses the bundled seed into radio-tunable usages grouped by NORAD.
  Map<int, List<SatelliteTransponder>> _seedGrouped(String text) {
    final result = <int, List<SatelliteTransponder>>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return result;
      final list = decoded['transponders'];
      if (list is! List) return result;
      for (final entry in list.whereType<Map>()) {
        final t = SatelliteTransponder.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (t.noradId == 0) continue;
        // Keep only usages the radio can at least receive or transmit.
        if (!isRadioTunable(t.downlinkHz) && !isRadioTunable(t.uplinkHz)) {
          continue;
        }
        result.putIfAbsent(t.noradId, () => []).add(t);
      }
    } catch (e) {
      debugPrint('TransponderRepository: failed to parse seed: $e');
    }
    return result;
  }

  static SatelliteTransponder? _fromSatnogs(Map<String, dynamic> json) {
    final noradId = asIntOrNull(json['norad_cat_id']);
    if (noradId == null) return null;
    return SatelliteTransponder(
      noradId: noradId,
      name: (json['description'] as String?) ?? '',
      uplinkHz: asIntOrNull(json['uplink_low']),
      downlinkHz: asIntOrNull(json['downlink_low']),
      mode: (json['mode'] as String?) ?? '',
      ctcssHz: null,
      inverting: json['invert'] == true,
      status: (json['status'] as String?) ?? '',
    );
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
      _cacheFile =
          File('${dir.path}${Platform.pathSeparator}transponders.json');
    } catch (e) {
      debugPrint('TransponderRepository: failed to resolve cache dir: $e');
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

  Future<void> _writeCache(Map<int, List<SatelliteTransponder>> catalog) async {
    final cache = _cacheFile;
    if (cache == null) return;
    try {
      final payload = {
        'transponders': catalog.values
            .expand((usages) => usages)
            .map((t) => t.toJson())
            .toList(),
      };
      await cache.writeAsString(jsonEncode(payload), flush: true);
    } catch (e) {
      debugPrint('TransponderRepository: failed to write cache: $e');
    }
  }

  Future<String> _readSeed() async {
    try {
      return await rootBundle.loadString(_seedAsset);
    } catch (e) {
      debugPrint('TransponderRepository: failed to load seed asset: $e');
      return '{}';
    }
  }

  void _parseOwnFormat(String text) {
    _byNorad.clear();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final list = decoded['transponders'];
      if (list is! List) return;
      for (final entry in list.whereType<Map>()) {
        final t = SatelliteTransponder.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (t.noradId != 0) {
          _byNorad.putIfAbsent(t.noradId, () => []).add(t);
        }
      }
    } catch (e) {
      debugPrint('TransponderRepository: failed to parse catalog: $e');
    }
  }
}
