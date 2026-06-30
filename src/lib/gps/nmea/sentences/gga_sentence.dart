/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.Sentences.GgaSentence` class.
*/

import '../nmea_convert.dart';

/// GGA – Global Positioning System Fix Data.
class GgaSentence {
  final Duration? utcTime;
  final double? latitude;
  final double? longitude;
  final int? fixQuality;
  final int? satelliteCount;
  final double? hdop;
  final double? altitudeMeters;
  final double? geoidSeparation;

  const GgaSentence({
    this.utcTime,
    this.latitude,
    this.longitude,
    this.fixQuality,
    this.satelliteCount,
    this.hdop,
    this.altitudeMeters,
    this.geoidSeparation,
  });

  String get fixQualityDescription {
    switch (fixQuality) {
      case 0:
        return 'Invalid';
      case 1:
        return 'GPS Fix (SPS)';
      case 2:
        return 'DGPS Fix';
      case 3:
        return 'PPS Fix';
      case 4:
        return 'RTK Fixed';
      case 5:
        return 'RTK Float';
      case 6:
        return 'Estimated (DR)';
      case 7:
        return 'Manual Input';
      case 8:
        return 'Simulation';
      default:
        return 'Unknown';
    }
  }

  /// Parses a GGA sentence from already-split NMEA fields.
  /// Fields: $--GGA,hhmmss.ss,lat,N/S,lon,E/W,quality,numSV,HDOP,alt,M,sep,M,diffAge,diffStation*cs
  static GgaSentence parse(List<String> fields) => GgaSentence(
    utcTime: NmeaConvert.toUtcTime(NmeaConvert.at(fields, 1)),
    latitude: NmeaConvert.toDecimalDegrees(
      NmeaConvert.at(fields, 2),
      NmeaConvert.at(fields, 3),
    ),
    longitude: NmeaConvert.toDecimalDegrees(
      NmeaConvert.at(fields, 4),
      NmeaConvert.at(fields, 5),
    ),
    fixQuality: NmeaConvert.toInt(NmeaConvert.at(fields, 6)),
    satelliteCount: NmeaConvert.toInt(NmeaConvert.at(fields, 7)),
    hdop: NmeaConvert.toDouble(NmeaConvert.at(fields, 8)),
    altitudeMeters: NmeaConvert.toDouble(NmeaConvert.at(fields, 9)),
    geoidSeparation: NmeaConvert.toDouble(NmeaConvert.at(fields, 11)),
  );

  @override
  String toString() =>
      '[GGA] Time=${NmeaConvert.formatTime(utcTime, millis: true)}  '
      'Fix=$fixQualityDescription  '
      'Lat=${NmeaConvert.fixed(latitude, 6)}°  '
      'Lon=${NmeaConvert.fixed(longitude, 6)}°  '
      'Alt=${NmeaConvert.fixed(altitudeMeters, 1)}m  '
      'Sats=${satelliteCount ?? ''}  HDOP=${NmeaConvert.fixed(hdop, 1)}';
}
