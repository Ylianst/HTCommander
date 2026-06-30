/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.Sentences.ZdaSentence` class.
*/

import '../nmea_convert.dart';

/// ZDA – Time & Date.
class ZdaSentence {
  final Duration? utcTime;
  final int? day;
  final int? month;
  final int? year;
  final int? localZoneHours;
  final int? localZoneMinutes;

  const ZdaSentence({
    this.utcTime,
    this.day,
    this.month,
    this.year,
    this.localZoneHours,
    this.localZoneMinutes,
  });

  /// Fields: $--ZDA,hhmmss.ss,day,month,year,ltzh,ltzm*cs
  static ZdaSentence parse(List<String> fields) => ZdaSentence(
    utcTime: NmeaConvert.toUtcTime(NmeaConvert.at(fields, 1)),
    day: NmeaConvert.toInt(NmeaConvert.at(fields, 2)),
    month: NmeaConvert.toInt(NmeaConvert.at(fields, 3)),
    year: NmeaConvert.toInt(NmeaConvert.at(fields, 4)),
    localZoneHours: NmeaConvert.toInt(NmeaConvert.at(fields, 5)),
    localZoneMinutes: NmeaConvert.toInt(NmeaConvert.at(fields, 6)),
  );

  @override
  String toString() {
    final y = (year ?? 0).toString().padLeft(4, '0');
    final mo = (month ?? 0).toString().padLeft(2, '0');
    final d = (day ?? 0).toString().padLeft(2, '0');
    final offH = localZoneHours == null
        ? ''
        : (localZoneHours! >= 0 ? '+$localZoneHours' : '$localZoneHours');
    final offM = (localZoneMinutes ?? 0).toString().padLeft(2, '0');
    return '[ZDA] $y-$mo-$d  ${NmeaConvert.formatTime(utcTime)} UTC  '
        'LocalOffset=$offH:$offM';
  }
}
