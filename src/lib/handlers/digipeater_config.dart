/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Configuration for the APRS digipeater ([DigipeaterHandler]).
///
/// Persisted as a JSON string in the [DataBroker] at device 0 under the key
/// `DigipeaterConfig`. The digipeater re-uses the global station callsign
/// (device 0 `CallSign`) combined with the dedicated [ssid] configured here.
class DigipeaterConfig {
  /// Whether the digipeater is currently active.
  final bool enabled;

  /// The radio device id the digipeater operates on (and locks). -1 = none.
  final int radioDeviceId;

  /// When true, only WIDE1-1 (and exact alias matches) are repeated, acting as
  /// a low-level fill-in digipeater.
  final bool fillInOnly;

  /// When true, WIDEn-N packets are decremented and repeated.
  final bool handleWideN;

  /// Maximum number of hops (N) the digipeater will service. WIDEn-N entries
  /// with N greater than this are treated as their capped value.
  final int maxHops;

  /// When true, the digipeater inserts its own callsign into the path (trace
  /// behaviour) when repeating a WIDEn-N packet.
  final bool substituteOwnCall;

  /// Custom alias callsigns (with optional SSID) that also trigger a repeat
  /// when they appear as the next unused entry in the path.
  final List<String> aliases;

  /// Duplicate/loop suppression window in seconds. Packets seen again within
  /// this window are dropped.
  final int dedupSeconds;

  const DigipeaterConfig({
    this.enabled = false,
    this.radioDeviceId = -1,
    this.fillInOnly = false,
    this.handleWideN = true,
    this.maxHops = 2,
    this.substituteOwnCall = true,
    this.aliases = const [],
    this.dedupSeconds = 30,
  });

  DigipeaterConfig copyWith({
    bool? enabled,
    int? radioDeviceId,
    bool? fillInOnly,
    bool? handleWideN,
    int? maxHops,
    bool? substituteOwnCall,
    List<String>? aliases,
    int? dedupSeconds,
  }) {
    return DigipeaterConfig(
      enabled: enabled ?? this.enabled,
      radioDeviceId: radioDeviceId ?? this.radioDeviceId,
      fillInOnly: fillInOnly ?? this.fillInOnly,
      handleWideN: handleWideN ?? this.handleWideN,
      maxHops: maxHops ?? this.maxHops,
      substituteOwnCall: substituteOwnCall ?? this.substituteOwnCall,
      aliases: aliases ?? this.aliases,
      dedupSeconds: dedupSeconds ?? this.dedupSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'radioDeviceId': radioDeviceId,
    'fillInOnly': fillInOnly,
    'handleWideN': handleWideN,
    'maxHops': maxHops,
    'substituteOwnCall': substituteOwnCall,
    'aliases': aliases,
    'dedupSeconds': dedupSeconds,
  };

  static DigipeaterConfig fromJson(Map<String, dynamic> json) {
    final rawAliases = json['aliases'];
    final aliases = <String>[];
    if (rawAliases is List) {
      for (final a in rawAliases) {
        if (a is String && a.trim().isNotEmpty) aliases.add(a.trim());
      }
    }
    int asInt(Object? v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    bool asBool(Object? v, bool fallback) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      return fallback;
    }

    return DigipeaterConfig(
      enabled: asBool(json['enabled'], false),
      radioDeviceId: asInt(json['radioDeviceId'], -1),
      fillInOnly: asBool(json['fillInOnly'], false),
      handleWideN: asBool(json['handleWideN'], true),
      maxHops: asInt(json['maxHops'], 2).clamp(1, 7),
      substituteOwnCall: asBool(json['substituteOwnCall'], true),
      aliases: aliases,
      dedupSeconds: asInt(json['dedupSeconds'], 30).clamp(0, 3600),
    );
  }
}
