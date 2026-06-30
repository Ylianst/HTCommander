/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// A parsed APRS callsign with its base callsign and SSID.
/// Mirrors the C# `Callsign` class.
class Callsign {
  String stationCallsign; // callsign plus ssid
  String baseCallsign;
  int ssid = 0;

  Callsign(String callsign) : stationCallsign = '', baseCallsign = '' {
    stationCallsign = callsign.toUpperCase().trim();
    if (stationCallsign.contains('-')) {
      final parts = stationCallsign.split('-');
      baseCallsign = parts[0].toUpperCase();
      final parsed = int.tryParse(parts.length > 1 ? parts[1] : '');
      if (parsed != null && parsed >= 0 && parsed <= 255) {
        ssid = parsed;
      } else {
        // not a valid ssid - must be something else
        baseCallsign = stationCallsign;
        ssid = 0;
      }
    } else {
      baseCallsign = stationCallsign;
    }
  }

  static Callsign parseCallsign(String callsign) => Callsign(callsign);
}
