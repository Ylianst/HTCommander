/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.Gps.GpsData` class.
*/

/// Represents a decoded GPS position fix, combining data from NMEA sentences
/// (RMC and GGA). Dispatched on the Data Broker as device 1, key `GpsData`.
class GpsData {
  /// Latitude in decimal degrees. Negative values indicate South.
  double latitude;

  /// Longitude in decimal degrees. Negative values indicate West.
  double longitude;

  /// Altitude above mean sea level in metres (from GGA).
  double altitude;

  /// Speed over ground in knots (from RMC).
  double speed;

  /// Track angle / heading in degrees true (from RMC).
  double heading;

  /// GPS fix quality indicator from GGA sentence.
  /// 0 = invalid, 1 = GPS fix, 2 = DGPS fix.
  int fixQuality;

  /// Number of satellites in use (from GGA).
  int satellites;

  /// True when the RMC sentence status field is 'A' (active / valid fix).
  bool isFixed;

  /// UTC date and time of the fix (from RMC).
  DateTime gpsTime;

  GpsData({
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.altitude = 0.0,
    this.speed = 0.0,
    this.heading = 0.0,
    this.fixQuality = 0,
    this.satellites = 0,
    this.isFixed = false,
    DateTime? gpsTime,
  }) : gpsTime = gpsTime ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Serializes to a DataBroker JSON map. Keys match the C# property names so
  /// the value stays compatible with the C# implementation.
  Map<String, dynamic> toJson() => {
    'Latitude': latitude,
    'Longitude': longitude,
    'Altitude': altitude,
    'Speed': speed,
    'Heading': heading,
    'FixQuality': fixQuality,
    'Satellites': satellites,
    'IsFixed': isFixed,
    'GpsTime': gpsTime.toUtc().toIso8601String(),
  };

  /// Reconstructs a [GpsData] from a JSON map produced by [toJson].
  factory GpsData.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(Object? value) {
      if (value is String && value.isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toUtc();
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    double toDouble(Object? v) => v is num
        ? v.toDouble()
        : (v is String ? double.tryParse(v) ?? 0.0 : 0.0);
    int toInt(Object? v) =>
        v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);

    return GpsData(
      latitude: toDouble(json['Latitude']),
      longitude: toDouble(json['Longitude']),
      altitude: toDouble(json['Altitude']),
      speed: toDouble(json['Speed']),
      heading: toDouble(json['Heading']),
      fixQuality: toInt(json['FixQuality']),
      satellites: toInt(json['Satellites']),
      isFixed: json['IsFixed'] == true,
      gpsTime: parseTime(json['GpsTime']),
    );
  }
}
