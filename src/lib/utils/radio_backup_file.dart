/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Serialization for a full radio backup — every region and channel (as in an
/// all-regions export) plus the radio's settings, BSS/APRS settings and beacon
/// path. Data that is specific to this pairing (the list of trusted/paired
/// Bluetooth devices) is intentionally excluded so a backup can be restored to
/// the same or a different radio without touching its pairings.
///
/// The file is JSON, e.g.:
///
/// ```json
/// {
///   "format": "htcommander-radio-backup",
///   "version": 1,
///   "regionCount": 8,
///   "channelCount": 32,
///   "regions": [ { "index": 0, "name": "...", "channels": [ ... ] }, ... ],
///   "settingsRaw": "<base64 of the raw settings frame>",
///   "bssSettings": { ... },
///   "aprsPath": "WIDE1-1,WIDE2-1"
/// }
/// ```
///
/// `settingsRaw` is the raw settings frame the radio reports; restoring it byte
/// for byte preserves every setting, including ones the parsed model omits.
library;

import 'dart:convert';

import 'all_regions_file.dart';

class RadioBackupFile {
  /// Identifier stored in the `format` field so importers can recognise the
  /// file without relying on the extension.
  static const String formatId = 'htcommander-radio-backup';
  static const int formatVersion = 1;

  final int regionCount;
  final int channelCount;
  final List<RegionChannelData> regions;

  /// Base64 of the raw settings frame (as reported by the radio). Null when the
  /// radio never reported its settings.
  final String? settingsRaw;

  /// BSS/APRS settings as produced by `RadioBssSettings.toJson`. Null when
  /// unavailable.
  final Map<String, dynamic>? bssSettings;

  /// The APRS beacon digipeater path (e.g. "WIDE1-1,WIDE2-1"). Null when
  /// unavailable.
  final String? aprsPath;

  /// The programmable-function button table (`PfTable`): one map per slot as
  /// produced by the radio. Null when the table was never read.
  final List<Map<String, dynamic>>? pfTable;

  RadioBackupFile({
    required this.regionCount,
    required this.channelCount,
    required this.regions,
    this.settingsRaw,
    this.bssSettings,
    this.aprsPath,
    this.pfTable,
  });

  /// Serializes to an indented JSON string suitable for saving to a file.
  String toJsonString() {
    final map = <String, dynamic>{
      'format': formatId,
      'version': formatVersion,
      'regionCount': regionCount,
      'channelCount': channelCount,
      'regions': regions.map((r) => r.toJson()).toList(),
      if (settingsRaw != null) 'settingsRaw': settingsRaw,
      if (bssSettings != null) 'bssSettings': bssSettings,
      if (aprsPath != null) 'aprsPath': aprsPath,
      if (pfTable != null) 'pfTable': pfTable,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Attempts to parse [content] as a full radio backup file. Returns null if
  /// the content is not valid JSON or does not carry the expected format
  /// marker, so callers can fall back to other import parsers.
  static RadioBackupFile? tryParse(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['format'] != formatId) return null;

    final rawRegions = decoded['regions'];
    final regions = <RegionChannelData>[];
    if (rawRegions is List) {
      for (final r in rawRegions) {
        if (r is Map) {
          regions.add(RegionChannelData.fromJson(r.cast<String, dynamic>()));
        }
      }
    }
    final bss = decoded['bssSettings'];
    final rawPf = decoded['pfTable'];
    final pfTable = rawPf is List
        ? rawPf
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList()
        : null;
    return RadioBackupFile(
      regionCount: (decoded['regionCount'] as int?) ?? regions.length,
      channelCount: (decoded['channelCount'] as int?) ?? 0,
      regions: regions,
      settingsRaw: decoded['settingsRaw'] as String?,
      bssSettings: bss is Map ? bss.cast<String, dynamic>() : null,
      aprsPath: decoded['aprsPath'] as String?,
      pfTable: pfTable,
    );
  }

  /// The regions, exposed as an [AllRegionsFile] so the shared region-write
  /// dialog can program them.
  AllRegionsFile toAllRegionsFile() => AllRegionsFile(
    regionCount: regionCount,
    channelCount: channelCount,
    regions: regions,
  );
}
