/// Aircraft data model ported from the C# `HTCommander.Airplanes.Aircraft`.
///
/// Represents a single aircraft as reported by a Dump1090 `aircraft.json`
/// endpoint. Field names mirror the JSON keys used by Dump1090.
library;

class Aircraft {
  /// ICAO 24-bit hex identifier.
  final String? hex;

  /// Callsign / flight number.
  final String? flight;

  /// Latitude in degrees.
  final double? latitude;

  /// Longitude in degrees.
  final double? longitude;

  /// Altitude in feet (`altitude` field; may be a number or "ground").
  final Object? altitude;

  /// Altitude (geometric / GNSS) in feet.
  final int? altitudeGeometric;

  /// Barometric altitude in feet (`alt_baro`; may be a number or "ground").
  final Object? altitudeBaro;

  /// Ground speed in knots (`speed` field).
  final double? speed;

  /// Ground speed in knots (`gs` field used by some builds).
  final double? groundSpeed;

  /// Track angle in degrees (0 = north).
  final double? track;

  /// Squawk transponder code.
  final String? squawk;

  /// Vertical rate in feet/minute.
  final int? verticalRate;

  /// Barometric vertical rate in feet/minute.
  final int? baroRate;

  /// Number of messages received for this aircraft.
  final int? messages;

  /// Seconds since last message was received.
  final double? seen;

  /// Seconds since last position update.
  final double? seenPos;

  /// Received signal strength in dBFS.
  final double? rssi;

  /// Aircraft category (A0-D7).
  final String? category;

  /// Emergency/priority status.
  final String? emergency;

  const Aircraft({
    this.hex,
    this.flight,
    this.latitude,
    this.longitude,
    this.altitude,
    this.altitudeGeometric,
    this.altitudeBaro,
    this.speed,
    this.groundSpeed,
    this.track,
    this.squawk,
    this.verticalRate,
    this.baroRate,
    this.messages,
    this.seen,
    this.seenPos,
    this.rssi,
    this.category,
    this.emergency,
  });

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory Aircraft.fromJson(Map<String, dynamic> json) {
    return Aircraft(
      hex: json['hex'] as String?,
      flight: (json['flight'] as String?)?.trim(),
      latitude: _toDouble(json['lat']),
      longitude: _toDouble(json['lon']),
      altitude: json['altitude'],
      altitudeGeometric: _toInt(json['alt_geom']),
      altitudeBaro: json['alt_baro'],
      speed: _toDouble(json['speed']),
      groundSpeed: _toDouble(json['gs']),
      track: _toDouble(json['track']),
      squawk: json['squawk'] as String?,
      verticalRate: _toInt(json['vert_rate']),
      baroRate: _toInt(json['baro_rate']),
      messages: _toInt(json['messages']),
      seen: _toDouble(json['seen']),
      seenPos: _toDouble(json['seen_pos']),
      rssi: _toDouble(json['rssi']),
      category: json['category'] as String?,
      emergency: json['emergency'] as String?,
    );
  }

  /// Whether this aircraft has a usable position.
  bool get hasPosition => latitude != null && longitude != null;

  /// Serializes to a Dump1090-style JSON map. Used to send aircraft to
  /// detached windows via the data broker.
  Map<String, dynamic> toJson() => {
    'hex': hex,
    'flight': flight,
    'lat': latitude,
    'lon': longitude,
    'altitude': altitude,
    'alt_geom': altitudeGeometric,
    'alt_baro': altitudeBaro,
    'speed': speed,
    'gs': groundSpeed,
    'track': track,
    'squawk': squawk,
    'vert_rate': verticalRate,
    'baro_rate': baroRate,
    'messages': messages,
    'seen': seen,
    'seen_pos': seenPos,
    'rssi': rssi,
    'category': category,
    'emergency': emergency,
  };

  /// Returns the best available altitude value for display.
  String getAltitudeDisplay() {
    if (altitudeBaro != null) return altitudeBaro.toString();
    if (altitude != null) return altitude.toString();
    if (altitudeGeometric != null) return altitudeGeometric.toString();
    return '—';
  }

  /// Returns the best available speed value.
  double? getSpeed() => groundSpeed ?? speed;

  /// Returns the best available vertical rate.
  int? getVerticalRate() => baroRate ?? verticalRate;
}
