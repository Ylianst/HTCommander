/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math' as math;

class WinlinkGatewayChannel {
  static const int packetMode = 1;
  static const int varaFmMode = 2;

  final int frequencyHz;
  final int modes;

  const WinlinkGatewayChannel({required this.frequencyHz, required this.modes});

  bool get supportsPacket => (modes & packetMode) != 0;
  bool get supportsVaraFm => (modes & varaFmMode) != 0;

  String get modeLabel => [
    if (supportsPacket) 'Packet 1200',
    if (supportsVaraFm) 'VARA-FM',
  ].join(' / ');
}

/// A Winlink RMS station with a location and mode support per frequency.
class WinlinkGateway {
  /// Callsign with AX.25 SSID, e.g. `KG4MRA-10` (bare when the SSID is 0).
  final String callsign;

  final double latitude;
  final double longitude;

  final List<WinlinkGatewayChannel> channels;

  List<int> get frequenciesHz =>
      channels.map((channel) => channel.frequencyHz).toList();

  const WinlinkGateway({
    required this.callsign,
    required this.latitude,
    required this.longitude,
    required this.channels,
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
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _deg2rad(double d) => d * (math.pi / 180.0);
