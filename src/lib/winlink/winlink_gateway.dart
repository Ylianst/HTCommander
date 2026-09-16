/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math' as math;

/// A single Winlink 1200-baud packet gateway (RMS): a callsign-stationid, a
/// location, and one or more frequencies to reach it on. Mode/baud are implied
/// — every gateway in the offline directory is Packet 1200.
class WinlinkGateway {
  /// Callsign with AX.25 SSID, e.g. `KG4MRA-10` (bare when the SSID is 0).
  final String callsign;

  final double latitude;
  final double longitude;

  /// Frequencies this gateway listens on, in Hz, ascending.
  final List<int> frequenciesHz;

  const WinlinkGateway({
    required this.callsign,
    required this.latitude,
    required this.longitude,
    required this.frequenciesHz,
  });

  /// The frequencies formatted as `MHz` strings, e.g. `145.030`.
  List<String> get frequenciesMHz =>
      frequenciesHz.map((hz) => (hz / 1e6).toStringAsFixed(3)).toList();

  /// Great-circle distance in kilometres from ([lat], [lon]) to this gateway.
  double distanceKmTo(double lat, double lon) =>
      _haversineKm(lat, lon, latitude, longitude);
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _deg2rad(double d) => d * (math.pi / 180.0);
