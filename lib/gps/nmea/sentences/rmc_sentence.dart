/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.Sentences.RmcSentence` class.
*/

import '../nmea_convert.dart';

/// RMC – Recommended Minimum Specific GNSS Data.
class RmcSentence {
  final Duration? utcTime;
  final String? status;
  final double? latitude;
  final double? longitude;
  final double? speedKnots;
  final double? trackAngle;
  final DateTime? date;
  final double? magneticVariation;
  final String? magneticDirection;
  final String? mode;

  const RmcSentence({
    this.utcTime,
    this.status,
    this.latitude,
    this.longitude,
    this.speedKnots,
    this.trackAngle,
    this.date,
    this.magneticVariation,
    this.magneticDirection,
    this.mode,
  });

  double? get speedKph => speedKnots != null ? speedKnots! * 1.852 : null;

  bool get isActive => status == 'A';

  /// Fields: $--RMC,hhmmss.ss,status,lat,N/S,lon,E/W,spd,cog,ddmmyy,mv,mvE/W,mode*cs
  static RmcSentence parse(List<String> fields) => RmcSentence(
    utcTime: NmeaConvert.toUtcTime(NmeaConvert.at(fields, 1)),
    status: fields.length > 2 ? fields[2] : null,
    latitude: NmeaConvert.toDecimalDegrees(
      NmeaConvert.at(fields, 3),
      NmeaConvert.at(fields, 4),
    ),
    longitude: NmeaConvert.toDecimalDegrees(
      NmeaConvert.at(fields, 5),
      NmeaConvert.at(fields, 6),
    ),
    speedKnots: NmeaConvert.toDouble(NmeaConvert.at(fields, 7)),
    trackAngle: NmeaConvert.toDouble(NmeaConvert.at(fields, 8)),
    date: NmeaConvert.toDate(NmeaConvert.at(fields, 9)),
    magneticVariation: NmeaConvert.toDouble(NmeaConvert.at(fields, 10)),
    magneticDirection: fields.length > 11 ? fields[11] : null,
    mode: fields.length > 12 ? fields[12] : null,
  );

  @override
  String toString() {
    final dateStr = date == null
        ? ''
        : '${date!.year.toString().padLeft(4, '0')}-'
              '${date!.month.toString().padLeft(2, '0')}-'
              '${date!.day.toString().padLeft(2, '0')}';
    return '[RMC] Time=${NmeaConvert.formatTime(utcTime)}  Date=$dateStr  '
        'Status=${isActive ? 'Active' : 'Void'}  '
        'Lat=${NmeaConvert.fixed(latitude, 6)}°  '
        'Lon=${NmeaConvert.fixed(longitude, 6)}°  '
        'Speed=${NmeaConvert.fixed(speedKnots, 1)}kn '
        '(${NmeaConvert.fixed(speedKph, 1)}km/h)  '
        'Track=${NmeaConvert.fixed(trackAngle, 1)}°';
  }
}
