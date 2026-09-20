/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'satellite_models.dart';

/// Persistent store for the user's own satellite edits.
///
/// The [TleRepository] and [TransponderRepository] mirror upstream data
/// (Celestrak / SatNOGS) and periodically refresh, overwriting their caches. To
/// let the user add, edit and delete satellites and their usages without those
/// refreshes clobbering the changes, every user edit is kept here in a separate
/// file and re-applied as the top-priority overlay each time the catalog is
/// rebuilt.
///
/// Precedence when the handler builds the catalog:
///  - A satellite in [overrides] replaces the online/seed usages entirely and
///    always appears (even receive-only birds the radio can't transmit to).
///  - Its orbit uses the stored TLE when [isOrbitPinned] (a user-added bird, or
///    one whose orbit the user explicitly edited); otherwise the live TLE from
///    the online catalog is used so orbital elements keep auto-updating.
///  - A NORAD id in [hidden] is suppressed from the catalog even if the online
///    catalog still carries it.
class UserSatelliteStore {
  static const int _formatVersion = 1;

  final Map<int, SatelliteInfo> _overrides = {};
  final Set<int> _orbitPinned = {};
  final Set<int> _hidden = {};
  File? _file;

  /// User-edited/added satellites keyed by NORAD id.
  Map<int, SatelliteInfo> get overrides =>
      Map<int, SatelliteInfo>.unmodifiable(_overrides);

  /// NORAD ids the user has deleted from the catalog.
  Set<int> get hidden => Set<int>.unmodifiable(_hidden);

  /// True when the stored orbit for [noradId] should win over the live TLE.
  bool isOrbitPinned(int noradId) => _orbitPinned.contains(noradId);

  /// True when [noradId] has a user override (edited or added).
  bool isOverridden(int noradId) => _overrides.containsKey(noradId);

  /// Reads the persisted store into memory. Safe to call once at startup; never
  /// throws.
  Future<void> load() async {
    await _resolveFile();
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      _applyJson(jsonDecode(await file.readAsString()));
    } catch (e) {
      debugPrint('UserSatelliteStore: failed to load: $e');
    }
  }

  /// Adds or replaces the user override for [info]. When [pinOrbit] is true the
  /// stored TLE becomes authoritative (a user-added bird or an explicit orbit
  /// edit); otherwise only the usages are pinned and the orbit keeps tracking
  /// the online TLE. Un-hides the satellite if it had been deleted. Persists.
  Future<void> upsert(SatelliteInfo info, {required bool pinOrbit}) async {
    final id = info.noradId;
    if (id == 0) return;
    _overrides[id] = info;
    if (pinOrbit) {
      _orbitPinned.add(id);
    } else {
      _orbitPinned.remove(id);
    }
    _hidden.remove(id);
    await _save();
  }

  /// Deletes [noradId] from the catalog. A user-added bird is removed outright;
  /// an online/seed bird is added to the hidden set so it stays suppressed
  /// across refreshes. Persists.
  Future<void> delete(int noradId) async {
    _overrides.remove(noradId);
    _orbitPinned.remove(noradId);
    _hidden.add(noradId);
    await _save();
  }

  /// Clears any user override and un-hides [noradId], restoring the online/seed
  /// data for that satellite. Persists.
  Future<void> restore(int noradId) async {
    _overrides.remove(noradId);
    _orbitPinned.remove(noradId);
    _hidden.remove(noradId);
    await _save();
  }

  /// Serializes the whole store for export/backup.
  Map<String, dynamic> toJson() => {
    'version': _formatVersion,
    'satellites': _overrides.values
        .map(
          (info) => {
            ...info.toJson(),
            'orbitPinned': _orbitPinned.contains(info.noradId),
          },
        )
        .toList(),
    'hidden': _hidden.toList()..sort(),
  };

  /// Merges an exported/imported payload into the store as user overrides, then
  /// persists. Returns the number of satellites applied. Never throws.
  Future<int> importJson(Object? json) async {
    final applied = _applyJson(json);
    await _save();
    return applied;
  }

  int _applyJson(Object? json) {
    if (json is! Map) return 0;
    var applied = 0;
    final sats = json['satellites'];
    if (sats is List) {
      for (final entry in sats.whereType<Map>()) {
        try {
          final map = Map<String, dynamic>.from(entry);
          final info = SatelliteInfo.fromJson(map);
          if (info.noradId == 0) continue;
          _overrides[info.noradId] = info;
          if (map['orbitPinned'] == true) {
            _orbitPinned.add(info.noradId);
          }
          _hidden.remove(info.noradId);
          applied++;
        } catch (e) {
          debugPrint('UserSatelliteStore: skipped bad entry: $e');
        }
      }
    }
    final hidden = json['hidden'];
    if (hidden is List) {
      for (final id in hidden) {
        final n = id is num ? id.toInt() : int.tryParse('$id');
        if (n != null && !_overrides.containsKey(n)) _hidden.add(n);
      }
    }
    return applied;
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode(toJson()), flush: true);
    } catch (e) {
      debugPrint('UserSatelliteStore: failed to save: $e');
    }
  }

  Future<void> _resolveFile() async {
    if (kIsWeb) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}HTCommander'
        '${Platform.pathSeparator}Satellites',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      _file = File('${dir.path}${Platform.pathSeparator}user_satellites.json');
    } catch (e) {
      debugPrint('UserSatelliteStore: failed to resolve dir: $e');
      _file = null;
    }
  }
}
