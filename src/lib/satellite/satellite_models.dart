/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Data models for the amateur-satellite feature: parsed orbital elements
/// (TLEs), FM transponder catalog entries, the combined per-satellite record,
/// and the live computed position / pass snapshots dispatched on the Data
/// Broker for the satellite tab and map overlay.
library;

/// Speed of light in kilometres per second, used for Doppler correction.
const double _cKmPerS = 299792.458;

/// A parsed Two-Line Element set for a single satellite.
class SatelliteTle {
  /// Human-readable object name (line 0 of a 3LE), e.g. `ISS (ZARYA)`.
  final String name;

  /// NORAD catalog number parsed from line 1.
  final int noradId;

  /// TLE line 1 (starts with `1 `).
  final String line1;

  /// TLE line 2 (starts with `2 `).
  final String line2;

  const SatelliteTle({
    required this.name,
    required this.noradId,
    required this.line1,
    required this.line2,
  });

  /// Parses a Celestrak/AMSAT three-line-element (3LE) text block into a list
  /// of [SatelliteTle]. Lines that don't form a valid name+line1+line2 triple
  /// are skipped. Never throws on malformed input.
  static List<SatelliteTle> parseThreeLine(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();

    final result = <SatelliteTle>[];
    for (var i = 0; i + 2 < lines.length + 1 && i + 2 <= lines.length; i++) {
      final name = lines[i];
      if (name.startsWith('1 ') || name.startsWith('2 ')) continue;
      if (i + 2 >= lines.length) break;
      final l1 = lines[i + 1];
      final l2 = lines[i + 2];
      if (!l1.startsWith('1 ') || !l2.startsWith('2 ')) continue;
      final id = _parseNoradId(l1);
      if (id == null) continue;
      result.add(
        SatelliteTle(name: name, noradId: id, line1: l1, line2: l2),
      );
      i += 2;
    }
    return result;
  }

  /// Extracts the 5-digit NORAD catalog number from TLE line 1 (columns 3-7).
  static int? _parseNoradId(String line1) {
    if (line1.length < 7) return null;
    final field = line1.substring(2, 7).trim();
    return int.tryParse(field);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'noradId': noradId,
    'line1': line1,
    'line2': line2,
  };

  factory SatelliteTle.fromJson(Map<String, dynamic> json) => SatelliteTle(
    name: (json['name'] as String?) ?? '',
    noradId: (json['noradId'] as num?)?.toInt() ?? 0,
    line1: (json['line1'] as String?) ?? '',
    line2: (json['line2'] as String?) ?? '',
  );
}

/// An FM transponder / cross-band repeater on an amateur satellite.
///
/// [uplinkHz] is the ground-to-satellite frequency the radio transmits on;
/// [downlinkHz] is the satellite-to-ground frequency the radio receives on.
class SatelliteTransponder {
  final int noradId;
  final String name;

  /// Ground-to-satellite (radio TX) frequency in Hz.
  final int? uplinkHz;

  /// Satellite-to-ground (radio RX) frequency in Hz.
  final int? downlinkHz;

  /// Modulation, e.g. `FM`.
  final String mode;

  /// CTCSS tone (Hz) required on the uplink to open the repeater, or null.
  final double? ctcssHz;

  /// Whether the transponder inverts (linear birds); false for FM repeaters.
  final bool inverting;

  /// Operational status, e.g. `active`.
  final String status;

  const SatelliteTransponder({
    required this.noradId,
    required this.name,
    required this.uplinkHz,
    required this.downlinkHz,
    required this.mode,
    required this.ctcssHz,
    required this.inverting,
    required this.status,
  });

  /// True when both up- and downlink are defined FM frequencies for an active
  /// bird (the only kind this radio can actually work).
  bool get isWorkableFm =>
      status.toLowerCase() == 'active' &&
      mode.toUpperCase().contains('FM') &&
      uplinkHz != null &&
      downlinkHz != null;

  Map<String, dynamic> toJson() => {
    'noradId': noradId,
    'name': name,
    'uplinkHz': uplinkHz,
    'downlinkHz': downlinkHz,
    'mode': mode,
    'ctcssHz': ctcssHz,
    'inverting': inverting,
    'status': status,
  };

  factory SatelliteTransponder.fromJson(Map<String, dynamic> json) {
    int? toIntOrNull(Object? v) =>
        v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    double? toDoubleOrNull(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    return SatelliteTransponder(
      noradId: toIntOrNull(json['noradId']) ?? 0,
      name: (json['name'] as String?) ?? '',
      uplinkHz: toIntOrNull(json['uplinkHz']),
      downlinkHz: toIntOrNull(json['downlinkHz']),
      mode: (json['mode'] as String?) ?? '',
      ctcssHz: toDoubleOrNull(json['ctcssHz']),
      inverting: json['inverting'] == true,
      status: (json['status'] as String?) ?? '',
    );
  }
}

/// A satellite the user can track: its orbital elements paired with the FM
/// transponder used to work it.
class SatelliteInfo {
  final SatelliteTle tle;
  final SatelliteTransponder transponder;

  const SatelliteInfo({required this.tle, required this.transponder});

  int get noradId => tle.noradId;
  String get name => tle.name;

  Map<String, dynamic> toJson() => {
    'tle': tle.toJson(),
    'transponder': transponder.toJson(),
  };

  factory SatelliteInfo.fromJson(Map<String, dynamic> json) => SatelliteInfo(
    tle: SatelliteTle.fromJson(
      Map<String, dynamic>.from(json['tle'] as Map? ?? const {}),
    ),
    transponder: SatelliteTransponder.fromJson(
      Map<String, dynamic>.from(json['transponder'] as Map? ?? const {}),
    ),
  );

  /// Returns [downlinkHz] shifted for the receiver Doppler at the given
  /// line-of-sight [rangeRateKmS] (positive = receding). This is the frequency
  /// the radio should tune its RX to so the incoming signal lands on channel.
  int? correctedDownlinkHz(double rangeRateKmS) {
    final base = transponder.downlinkHz;
    if (base == null) return null;
    return (base * (1 - rangeRateKmS / _cKmPerS)).round();
  }

  /// Returns [uplinkHz] pre-compensated for Doppler at the given line-of-sight
  /// [rangeRateKmS] (positive = receding), so the satellite receives its
  /// nominal uplink frequency. This is the frequency the radio should TX on.
  int? correctedUplinkHz(double rangeRateKmS) {
    final base = transponder.uplinkHz;
    if (base == null) return null;
    return (base * (1 + rangeRateKmS / _cKmPerS)).round();
  }
}

/// A live computed snapshot of a satellite as seen from the observer, produced
/// every tick by the satellite handler and dispatched for the UI.
class SatellitePosition {
  final int noradId;
  final String name;

  /// Sub-satellite geodetic latitude in degrees (positive north).
  final double latitudeDeg;

  /// Sub-satellite geodetic longitude in degrees (positive east, [-180, 180)).
  final double longitudeDeg;

  /// Height above the ellipsoid in kilometres.
  final double altitudeKm;

  /// Topocentric azimuth in degrees (0 = north, clockwise).
  final double azimuthDeg;

  /// Elevation above the horizon in degrees; negative = below the horizon.
  final double elevationDeg;

  /// Slant range from the observer in kilometres.
  final double rangeKm;

  /// Line-of-sight range rate in km/s (positive = receding).
  final double rangeRateKmS;

  /// The UTC instant this snapshot was computed for.
  final DateTime utc;

  const SatellitePosition({
    required this.noradId,
    required this.name,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.altitudeKm,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.rangeKm,
    required this.rangeRateKmS,
    required this.utc,
  });

  /// True when the satellite is above the observer's horizon.
  bool get isVisible => elevationDeg > 0;

  Map<String, dynamic> toJson() => {
    'noradId': noradId,
    'name': name,
    'latitudeDeg': latitudeDeg,
    'longitudeDeg': longitudeDeg,
    'altitudeKm': altitudeKm,
    'azimuthDeg': azimuthDeg,
    'elevationDeg': elevationDeg,
    'rangeKm': rangeKm,
    'rangeRateKmS': rangeRateKmS,
    'utc': utc.toUtc().toIso8601String(),
  };

  factory SatellitePosition.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0.0 : 0.0);
    return SatellitePosition(
      noradId: (json['noradId'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      latitudeDeg: toDouble(json['latitudeDeg']),
      longitudeDeg: toDouble(json['longitudeDeg']),
      altitudeKm: toDouble(json['altitudeKm']),
      azimuthDeg: toDouble(json['azimuthDeg']),
      elevationDeg: toDouble(json['elevationDeg']),
      rangeKm: toDouble(json['rangeKm']),
      rangeRateKmS: toDouble(json['rangeRateKmS']),
      utc: DateTime.tryParse((json['utc'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// A predicted overhead pass of a satellite for the observer.
class SatellitePass {
  final int noradId;
  final String name;

  /// Acquisition of signal (rise above the elevation threshold), UTC.
  final DateTime aos;

  /// Loss of signal (set below the elevation threshold), UTC.
  final DateTime los;

  /// Maximum elevation reached during the pass, in degrees.
  final double maxElevationDeg;

  /// Azimuth at AOS, in degrees.
  final double aosAzimuthDeg;

  /// Azimuth at LOS, in degrees.
  final double losAzimuthDeg;

  const SatellitePass({
    required this.noradId,
    required this.name,
    required this.aos,
    required this.los,
    required this.maxElevationDeg,
    required this.aosAzimuthDeg,
    required this.losAzimuthDeg,
  });

  /// Pass duration.
  Duration get duration => los.difference(aos);

  Map<String, dynamic> toJson() => {
    'noradId': noradId,
    'name': name,
    'aos': aos.toUtc().toIso8601String(),
    'los': los.toUtc().toIso8601String(),
    'maxElevationDeg': maxElevationDeg,
    'aosAzimuthDeg': aosAzimuthDeg,
    'losAzimuthDeg': losAzimuthDeg,
  };

  factory SatellitePass.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0.0 : 0.0);
    DateTime toUtc(Object? v) =>
        DateTime.tryParse((v as String?) ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return SatellitePass(
      noradId: (json['noradId'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      aos: toUtc(json['aos']),
      los: toUtc(json['los']),
      maxElevationDeg: toDouble(json['maxElevationDeg']),
      aosAzimuthDeg: toDouble(json['aosAzimuthDeg']),
      losAzimuthDeg: toDouble(json['losAzimuthDeg']),
    );
  }
}
