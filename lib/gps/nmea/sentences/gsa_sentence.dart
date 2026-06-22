/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.Sentences.GsaSentence` class.
*/

import '../nmea_convert.dart';

/// GSA – GNSS DOP and Active Satellites.
class GsaSentence {
  final String? selectionMode;
  final int? fixType;
  final List<int> satellitePrns;
  final double? pdop;
  final double? hdop;
  final double? vdop;

  const GsaSentence({
    this.selectionMode,
    this.fixType,
    this.satellitePrns = const [],
    this.pdop,
    this.hdop,
    this.vdop,
  });

  String get fixDescription {
    switch (fixType) {
      case 1:
        return 'No Fix';
      case 2:
        return '2D Fix';
      case 3:
        return '3D Fix';
      default:
        return 'Unknown';
    }
  }

  /// Fields: $--GSA,mode,fixType,sv1..sv12,PDOP,HDOP,VDOP*cs
  static GsaSentence parse(List<String> fields) {
    final prns = <int>[];
    for (var i = 3; i <= 14 && i < fields.length; i++) {
      final prn = NmeaConvert.toInt(fields[i]);
      if (prn != null) prns.add(prn);
    }

    return GsaSentence(
      selectionMode: fields.length > 1 ? fields[1] : null,
      fixType: NmeaConvert.toInt(NmeaConvert.at(fields, 2)),
      satellitePrns: prns,
      pdop: NmeaConvert.toDouble(NmeaConvert.at(fields, 15)),
      hdop: NmeaConvert.toDouble(NmeaConvert.at(fields, 16)),
      vdop: NmeaConvert.toDouble(NmeaConvert.at(fields, 17)),
    );
  }

  @override
  String toString() =>
      '[GSA] Fix=$fixDescription  Mode=${selectionMode ?? ''}  '
      'PDOP=${NmeaConvert.fixed(pdop, 1)}  '
      'HDOP=${NmeaConvert.fixed(hdop, 1)}  '
      'VDOP=${NmeaConvert.fixed(vdop, 1)}  '
      'SVs=[${satellitePrns.join(',')}]';
}
