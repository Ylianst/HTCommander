/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The country / DXCC entity a callsign belongs to.
///
/// Resolved entirely offline from a small bundled table (see
/// `tools/build_cty.py`), so it is always available on every platform, even
/// without the (large, optional) FCC license database.
@immutable
class CountryInfo {
  /// Entity name, e.g. `Fed. Rep. of Germany` or `United States`.
  final String country;

  /// Two-letter continent abbreviation (`EU`, `NA`, `AS`, ...), may be empty.
  final String continent;

  /// DXCC / ADIF entity number (0 when unknown or synthetic).
  final int dxcc;

  /// CQ zone (0 when unknown or synthetic).
  final int cqZone;

  /// ITU zone (0 when unknown or synthetic).
  final int ituZone;

  const CountryInfo({
    required this.country,
    this.continent = '',
    this.dxcc = 0,
    this.cqZone = 0,
    this.ituZone = 0,
  });

  /// Human-readable continent name for the [continent] abbreviation.
  String get continentName => switch (continent.toUpperCase()) {
        'EU' => 'Europe',
        'NA' => 'North America',
        'SA' => 'South America',
        'AS' => 'Asia',
        'AF' => 'Africa',
        'OC' => 'Oceania',
        'AN' => 'Antarctica',
        _ => '',
      };

  @override
  String toString() => 'CountryInfo($country, $continent, dxcc=$dxcc)';
}

/// Offline callsign -> country/DXCC-entity resolver.
///
/// Loads a compact, gzip-compressed prefix/exception table (bundled as an
/// asset) into memory once at startup and resolves callsigns by dismantling
/// any portable prefixes/suffixes and matching the longest known prefix. The
/// matching logic mirrors the well-known country-files.com / pyhamtools
/// approach.
class CallsignCountryLookup {
  CallsignCountryLookup._();

  /// The shared instance.
  static final CallsignCountryLookup instance = CallsignCountryLookup._();

  /// Asset path of the bundled, gzip-compressed lookup table.
  static const String _assetPath = 'assets/callsign/cty.json.gz';

  /// Synthetic entities for portable maritime / aeronautical mobile stations,
  /// which are not tied to any country.
  static const CountryInfo _maritimeMobile =
      CountryInfo(country: 'Maritime Mobile');
  static const CountryInfo _aircraftMobile =
      CountryInfo(country: 'Aircraft Mobile');

  /// A few odd callsigns that cannot be resolved by prefix rules alone.
  static const Map<String, String> _hardExceptions = {
    '7QAA': '7Q',
    '2SZ': 'G0',
  };

  final List<CountryInfo> _countries = [];
  final Map<String, int> _prefixes = {};
  final Map<String, int> _exact = {};
  bool _loaded = false;

  /// Whether the lookup table has been loaded and is ready for queries.
  bool get isLoaded => _loaded;

  /// Loads and decompresses the bundled table into memory. Safe to call once
  /// at startup; subsequent calls are no-ops.
  Future<void> init() async {
    if (_loaded) return;
    try {
      final data = await rootBundle.load(_assetPath);
      final gz = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final jsonBytes = GZipDecoder().decodeBytes(gz);
      final map = json.decode(utf8.decode(jsonBytes)) as Map<String, dynamic>;

      _countries.clear();
      for (final e in (map['countries'] as List)) {
        final row = e as List;
        _countries.add(CountryInfo(
          country: (row[0] as String),
          continent: (row.length > 1 ? row[1] as String : ''),
          dxcc: (row.length > 2 ? (row[2] as num).toInt() : 0),
          cqZone: (row.length > 3 ? (row[3] as num).toInt() : 0),
          ituZone: (row.length > 4 ? (row[4] as num).toInt() : 0),
        ));
      }

      _prefixes.clear();
      (map['prefixes'] as Map<String, dynamic>).forEach((k, v) {
        _prefixes[k] = (v as num).toInt();
      });

      _exact.clear();
      (map['exact'] as Map<String, dynamic>).forEach((k, v) {
        _exact[k] = (v as num).toInt();
      });

      _loaded = true;
    } catch (e) {
      debugPrint('CallsignCountryLookup: load failed: $e');
    }
  }

  /// Resolves the country / DXCC entity for [callsign], or null when it cannot
  /// be determined. Works entirely offline.
  CountryInfo? lookup(String callsign) {
    if (!_loaded) return null;
    final call = callsign.toUpperCase().trim();
    if (call.isEmpty) return null;

    // A dedicated full-callsign exception always wins.
    final ex = _exact[call];
    if (ex != null) return _countries[ex];

    return _dismantle(call);
  }

  /// Peels portable prefixes/suffixes off a callsign and resolves the entity.
  CountryInfo? _dismantle(String call) {
    // Drop a trailing "-NN" SSID (e.g. APRS style).
    var c = call.replaceAll(RegExp(r'-\d{1,3}$'), '');

    // Reduce a triple form X/CALL/Y down to X/CALL.
    if (RegExp(r'/[A-Z0-9]{1,4}/[A-Z0-9]{1,4}$').hasMatch(c)) {
      c = c.replaceAll(RegExp(r'/[A-Z0-9]{1,4}$'), '');
    }

    // Multi-character appendix: CALL/XXX (2-4 chars).
    final multi = RegExp(r'^[A-Z0-9]{4,10}/[A-Z0-9]{2,4}$');
    if (multi.hasMatch(c)) {
      final m = RegExp(r'/([A-Z0-9]{2,4})$').firstMatch(c)!;
      final appendix = m.group(1)!;
      final base = c.substring(0, m.start);
      switch (appendix) {
        case 'MM':
          return _maritimeMobile;
        case 'AM':
          return _aircraftMobile;
        case 'QRP':
        case 'QRPP':
        case 'BCN':
        case 'LH':
          return _iteratePrefix(base);
      }
      // A three-letter appendix (e.g. US contest county group) is not a
      // country prefix; resolve from the home call instead.
      if (RegExp(r'^[A-Z]{3}$').hasMatch(appendix)) {
        return _iteratePrefix(base);
      }
      // Otherwise the appendix itself is the operating-country prefix.
      return _iteratePrefix(appendix);
    }

    // Single-character appendix: CALL/X.
    final single = RegExp(r'/([A-Z0-9])$').firstMatch(c);
    if (single != null) {
      final appendix = single.group(1)!;
      final base = c.replaceAll(RegExp(r'/[A-Z0-9]$'), '');
      if (appendix == 'B') return _iteratePrefix(base);
      if (RegExp(r'\d').hasMatch(appendix)) {
        // Call-area change (e.g. DH1TW/2). Only meaningful when the base call
        // has a single digit; otherwise the entity is unchanged.
        if (RegExp(r'\d').allMatches(base).length == 1) {
          return _iteratePrefix(base.replaceAll(RegExp(r'\d'), appendix));
        }
        return _iteratePrefix(base);
      }
      return _iteratePrefix(base);
    }

    // Prefix form: PFX/CALL (short prefix before the slash).
    if (c.contains('/')) {
      final pfx = RegExp(r'^([A-Z0-9]{1,4})/').firstMatch(c);
      if (pfx != null) return _iteratePrefix(pfx.group(1)!);
    }

    final direct = _iteratePrefix(c);
    if (direct != null) return direct;

    // Fall back to the handful of hard-coded odd calls.
    final mapped = _hardExceptions[c];
    if (mapped != null) return _iteratePrefix(mapped);
    return null;
  }

  /// Truncates [call] from the right until it matches a known prefix.
  CountryInfo? _iteratePrefix(String call) {
    var prefix = call;
    while (prefix.isNotEmpty) {
      final idx = _prefixes[prefix];
      if (idx != null) return _countries[idx];
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return null;
  }
}
