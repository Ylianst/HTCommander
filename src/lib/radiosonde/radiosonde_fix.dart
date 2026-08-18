/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Unified radiosonde fix + persistable details, shared across sonde families
(DFM, RS41, ...). The comms/map layers consume these instead of the
family-specific frame types.
*/

library;

/// A decoded radiosonde position/telemetry fix, independent of sonde family.
class RadiosondeFix {
  const RadiosondeFix({
    required this.sondeType,
    required this.id,
    required this.frameNumber,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalSpeed,
    required this.verticalSpeed,
    required this.heading,
    required this.satellites,
    required this.dateTimeUtc,
    this.temperatureC,
  });

  /// Sonde family/type label, e.g. "RS41" or "DFM09".
  final String sondeType;

  /// Sonde identifier/serial (may be empty until resolved).
  final String id;
  final int frameNumber;
  final double latitude;
  final double longitude;
  final double altitude;
  final double horizontalSpeed;
  final double verticalSpeed;
  final double heading;
  final int satellites;
  final DateTime dateTimeUtc;
  final double? temperatureC;

  /// Key used to coalesce repeated fixes for the same sonde.
  String get key => id.isNotEmpty ? id : sondeType;

  @override
  String toString() =>
      '$sondeType[$frameNumber] $id lat=$latitude lon=$longitude '
      'alt=${altitude.toStringAsFixed(1)} sats=$satellites $dateTimeUtc';
}

/// Persistable, structured record of a decoded radiosonde fix (stored on a
/// comms message and serialized to disk). Also carries coalescing metadata.
class RadiosondeDetails {
  const RadiosondeDetails({
    required this.sondeId,
    required this.sondeType,
    required this.frameNumber,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalSpeed,
    required this.verticalSpeed,
    required this.heading,
    required this.satellites,
    required this.dateTimeUtc,
    this.temperatureC,
    this.count = 1,
    this.lastReceivedTime,
  });

  final String sondeId;
  final String sondeType;
  final int frameNumber;
  final double latitude;
  final double longitude;
  final double altitude;
  final double horizontalSpeed;
  final double verticalSpeed;
  final double heading;
  final int satellites;
  final DateTime dateTimeUtc;
  final double? temperatureC;

  /// Number of fixes for this sonde coalesced into one bubble (>= 1).
  final int count;

  /// Time the most recent fix in the bubble was received (wall clock).
  final DateTime? lastReceivedTime;

  factory RadiosondeDetails.fromFix(
    RadiosondeFix f, {
    int count = 1,
    DateTime? lastReceivedTime,
  }) {
    return RadiosondeDetails(
      sondeId: f.id,
      sondeType: f.sondeType,
      frameNumber: f.frameNumber,
      latitude: f.latitude,
      longitude: f.longitude,
      altitude: f.altitude,
      horizontalSpeed: f.horizontalSpeed,
      verticalSpeed: f.verticalSpeed,
      heading: f.heading,
      satellites: f.satellites,
      dateTimeUtc: f.dateTimeUtc,
      temperatureC: f.temperatureC,
      count: count,
      lastReceivedTime: lastReceivedTime,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sondeId': sondeId,
    // Key kept as 'dfmType' for backward compatibility with earlier records.
    'dfmType': sondeType,
    'frameNumber': frameNumber,
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'horizontalSpeed': horizontalSpeed,
    'verticalSpeed': verticalSpeed,
    'heading': heading,
    'satellites': satellites,
    'dateTimeUtc': dateTimeUtc.millisecondsSinceEpoch,
    'temperatureC': temperatureC,
    'count': count,
    'lastReceivedTime': lastReceivedTime?.millisecondsSinceEpoch,
  };

  factory RadiosondeDetails.fromJson(Map<dynamic, dynamic> json) {
    double d(Object? v) => v is num ? v.toDouble() : 0.0;
    final dtMs = json['dateTimeUtc'];
    final lastMs = json['lastReceivedTime'];
    return RadiosondeDetails(
      sondeId: json['sondeId'] as String? ?? '',
      sondeType: json['sondeType'] as String? ?? json['dfmType'] as String? ?? '',
      frameNumber: json['frameNumber'] as int? ?? 0,
      latitude: d(json['latitude']),
      longitude: d(json['longitude']),
      altitude: d(json['altitude']),
      horizontalSpeed: d(json['horizontalSpeed']),
      verticalSpeed: d(json['verticalSpeed']),
      heading: d(json['heading']),
      satellites: json['satellites'] as int? ?? 0,
      dateTimeUtc: dtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(dtMs, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      temperatureC: json['temperatureC'] is num
          ? (json['temperatureC'] as num).toDouble()
          : null,
      count: json['count'] as int? ?? 1,
      lastReceivedTime: lastMs is int
          ? DateTime.fromMillisecondsSinceEpoch(lastMs)
          : null,
    );
  }
}
