/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'coordinate.dart';

/// Utility functions for APRS coordinate and grid-square conversions.
/// Mirrors the C# `AprsUtil` static class (NMEA + Maidenhead helpers).
class AprsUtil {
  /// Computes the APRS-IS passcode (validation code) for a callsign.
  static String aprsValidationCode(String callsign) {
    int hash = 0x73e2; // magic number
    String cs = callsign.toUpperCase().trim();
    // get just the callsign, no ssid
    cs = cs.split('-')[0];
    final int len = cs.length;
    // in case callsign is odd length add null
    cs += '\u0000';
    int i = 0;
    while (i < len) {
      hash = (cs.codeUnitAt(i) << 8) ^ hash;
      i += 1;
      hash = cs.codeUnitAt(i) ^ hash;
      i += 1;
    }
    return (hash & 0x7fff).toString();
  }

  static String latLonToGridSquare(double lat, double lon) {
    final sb = StringBuffer();
    lat += 90;
    lon += 180;
    int v = (lon / 20).floor();
    lon -= v * 20;
    sb.writeCharCode('A'.codeUnitAt(0) + v);
    v = (lat / 10).floor();
    lat -= v * 10;
    sb.writeCharCode('A'.codeUnitAt(0) + v);
    sb.write((lon / 2).floor().toString());
    sb.write(lat.floor().toString());
    lon -= (lon / 2).floor() * 2;
    lat -= lat.floor();
    sb.writeCharCode('A'.codeUnitAt(0) + (lon * 12).floor());
    sb.writeCharCode('A'.codeUnitAt(0) + (lat * 24).floor());
    return sb.toString();
  }

  static String latLonToGridSquareSet(CoordinateSet set) =>
      latLonToGridSquare(set.latitude.value, set.longitude.value);

  /// Convert to NMEA format: DDMM.MMN/S or DDDMM.MME/W.
  static String _convertToNmea(double d, String direction, bool isLat) {
    final double l = d.abs();
    final int degrees = l.floor();
    final double minutes = (l - degrees) * 60;
    final String sD = isLat
        ? degrees.toString().padLeft(2, '0')
        : degrees.toString().padLeft(3, '0');
    // minutes formatted as 00.00
    String sM = minutes.toStringAsFixed(2);
    final dotIndex = sM.indexOf('.');
    final intPart = dotIndex == -1 ? sM : sM.substring(0, dotIndex);
    final fracPart = dotIndex == -1 ? '00' : sM.substring(dotIndex + 1);
    sM = '${intPart.padLeft(2, '0')}.$fracPart';
    return '$sD$sM$direction';
  }

  static String convertLatToNmea(double lat) =>
      _convertToNmea(lat, lat < 0 ? 'S' : 'N', true);

  static String convertLonToNmea(double lon) =>
      _convertToNmea(lon, lon < 0 ? 'W' : 'E', false);

  static Coordinate convertNmea(String? nmea) {
    final c = Coordinate.empty();
    if (nmea == null || nmea.isEmpty) {
      c.clear();
    } else {
      c.nmea = nmea;
      c.value = convertNmeaToFloat(nmea);
    }
    return c;
  }

  static double convertNmeaToFloat(String? nmea) {
    try {
      if (nmea == null || nmea.isEmpty) return 0;
      double d;
      // lat
      if (nmea.length == 8) {
        d = double.parse(nmea.substring(0, 2)); // hours
        d += double.parse(nmea.substring(2, 7)) / 60; // decimal minutes
        if (nmea.toUpperCase().endsWith('S')) d = -d;
        return d;
      }
      // lon
      if (nmea.length == 9) {
        d = double.parse(nmea.substring(0, 3)); // hours
        d += double.parse(nmea.substring(3, 8)) / 60; // decimal minutes
        if (nmea.toUpperCase().endsWith('W')) d = -d;
        return d;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
