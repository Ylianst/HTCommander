/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Serialization for the "all regions" channel file — a proprietary HTCommander
/// format that stores every region of a radio and every channel slot in each
/// region (including channels that are not set, so a full radio can be exported
/// and later re-programmed exactly).
///
/// The file is JSON so it stays human-readable and forward-compatible:
///
/// ```json
/// {
///   "format": "htcommander-regions",
///   "version": 1,
///   "regionCount": 8,
///   "channelCount": 32,
///   "regions": [
///     { "index": 0, "name": "Region 1", "channels": [ { ...channel... }, ... ] },
///     ...
///   ]
/// }
/// ```
///
/// Each channel object is the same map produced by [RadioChannelInfo.toJson],
/// so every field (including the channel number) is preserved verbatim.
library;

import 'dart:convert';

import '../radio/radio_models.dart';

/// A single region: its name plus every channel slot (empty slots included).
class RegionChannelData {
  final int index;
  final String name;
  final List<RadioChannelInfo> channels;

  RegionChannelData({
    required this.index,
    required this.name,
    required this.channels,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'name': name,
    'channels': channels.map((c) => c.toJson()).toList(),
  };

  static RegionChannelData fromJson(Map<String, dynamic> map) {
    final rawChannels = map['channels'];
    final channels = <RadioChannelInfo>[];
    if (rawChannels is List) {
      for (final c in rawChannels) {
        if (c is Map) {
          channels.add(RadioChannelInfo.fromJson(c.cast<String, dynamic>()));
        }
      }
    }
    return RegionChannelData(
      index: (map['index'] as int?) ?? 0,
      name: (map['name'] as String?) ?? '',
      channels: channels,
    );
  }
}

/// A parsed / buildable all-regions file.
class AllRegionsFile {
  /// Identifier stored in the `format` field so importers can recognise the
  /// file without relying on the extension.
  static const String formatId = 'htcommander-regions';
  static const int formatVersion = 1;

  final int regionCount;
  final int channelCount;
  final List<RegionChannelData> regions;

  AllRegionsFile({
    required this.regionCount,
    required this.channelCount,
    required this.regions,
  });

  /// Serializes to an indented JSON string suitable for saving to a file.
  String toJsonString() {
    final map = <String, dynamic>{
      'format': formatId,
      'version': formatVersion,
      'regionCount': regionCount,
      'channelCount': channelCount,
      'regions': regions.map((r) => r.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Attempts to parse [content] as an all-regions file. Returns null if the
  /// content is not valid JSON or does not carry the expected format marker, so
  /// callers can fall back to other (CSV) import parsers.
  static AllRegionsFile? tryParse(String content) {
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
        if (r is Map) regions.add(RegionChannelData.fromJson(r.cast<String, dynamic>()));
      }
    }
    return AllRegionsFile(
      regionCount: (decoded['regionCount'] as int?) ?? regions.length,
      channelCount: (decoded['channelCount'] as int?) ?? 0,
      regions: regions,
    );
  }
}
