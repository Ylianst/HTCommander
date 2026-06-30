/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'aprs_util.dart';

/// A single latitude or longitude coordinate with both a decimal value and
/// its NMEA string representation. Mirrors the C# `Coordinate` class.
class Coordinate {
  double value;
  String nmea;

  Coordinate.empty() : value = 0, nmea = '';

  /// Build from a decimal value (isLat selects lat vs lon NMEA formatting).
  Coordinate.fromValue(this.value, bool isLat)
    : nmea = isLat
          ? AprsUtil.convertLatToNmea(value)
          : AprsUtil.convertLonToNmea(value);

  /// Build from an NMEA string.
  Coordinate.fromNmea(this.nmea) : value = AprsUtil.convertNmeaToFloat(nmea);

  void clear() {
    value = 0;
    nmea = '';
  }
}

/// A latitude/longitude pair. Mirrors the C# `CoordinateSet` class.
class CoordinateSet {
  Coordinate latitude;
  Coordinate longitude;

  CoordinateSet()
    : latitude = Coordinate.empty(),
      longitude = Coordinate.empty();

  CoordinateSet.fromLatLon(double lat, double lon)
    : latitude = Coordinate.fromValue(lat, true),
      longitude = Coordinate.fromValue(lon, false);

  void clear() {
    latitude.clear();
    longitude.clear();
  }

  bool isValid() {
    // Invalid when both are exactly zero.
    if (latitude.value == 0 && longitude.value == 0) return false;
    return true;
  }
}

/// A full APRS position (coordinate plus course, speed, altitude and grid
/// square). Mirrors the C# `Position` class.
class Position {
  CoordinateSet coordinateSet;
  int ambiguity;
  int course;
  int speed;
  int altitude;
  String gridsquare;

  Position()
    : coordinateSet = CoordinateSet(),
      ambiguity = 0,
      course = 0,
      speed = 0,
      altitude = 0,
      gridsquare = '';

  void clear() {
    coordinateSet.clear();
    ambiguity = 0;
    course = 0;
    speed = 0;
    altitude = 0;
    gridsquare = '';
  }

  bool isValid() => coordinateSet.isValid();
}
