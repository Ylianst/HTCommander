/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.Sentences.GllSentence` class.
*/

import '../nmea_convert.dart';

/// GLL – Geographic Position – Latitude/Longitude.
class GllSentence {
  final double? latitude;
  final double? longitude;
  final Duration? utcTime;
  final String? status;
  final String? mode;

  const GllSentence({
    this.latitude,
    this.longitude,
    this.utcTime,
    this.status,
    this.mode,
  });

  bool get isValid => status == 'A';

  /// Fields: $--GLL,lat,N/S,lon,E/W,hhmmss.ss,status,mode*cs
  static GllSentence parse(List<String> fields) => GllSentence(
    latitude: NmeaConvert.toDecimalDegrees(
      NmeaConvert.at(fields, 1),
      NmeaConvert.at(fields, 2),
    ),
    longitude: NmeaConvert.toDecimalDegrees(
      NmeaConvert.at(fields, 3),
      NmeaConvert.at(fields, 4),
    ),
    utcTime: NmeaConvert.toUtcTime(NmeaConvert.at(fields, 5)),
    status: fields.length > 6 ? fields[6] : null,
    mode: fields.length > 7 ? fields[7] : null,
  );

  @override
  String toString() =>
      '[GLL] Lat=${NmeaConvert.fixed(latitude, 6)}°  '
      'Lon=${NmeaConvert.fixed(longitude, 6)}°  '
      'Time=${NmeaConvert.formatTime(utcTime)}  '
      'Status=${isValid ? 'Valid' : 'Void'}';
}
