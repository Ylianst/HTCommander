/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.Sentences.VtgSentence` class.
*/

import '../nmea_convert.dart';

/// VTG – Track Made Good and Ground Speed.
class VtgSentence {
  final double? trackTrue;
  final double? trackMagnetic;
  final double? speedKnots;
  final double? speedKph;
  final String? mode;

  const VtgSentence({
    this.trackTrue,
    this.trackMagnetic,
    this.speedKnots,
    this.speedKph,
    this.mode,
  });

  /// Fields: $--VTG,trackT,T,trackM,M,spdN,N,spdK,K,mode*cs
  static VtgSentence parse(List<String> fields) => VtgSentence(
    trackTrue: NmeaConvert.toDouble(NmeaConvert.at(fields, 1)),
    trackMagnetic: NmeaConvert.toDouble(NmeaConvert.at(fields, 3)),
    speedKnots: NmeaConvert.toDouble(NmeaConvert.at(fields, 5)),
    speedKph: NmeaConvert.toDouble(NmeaConvert.at(fields, 7)),
    mode: fields.length > 9 ? fields[9] : null,
  );

  @override
  String toString() =>
      '[VTG] TrackTrue=${NmeaConvert.fixed(trackTrue, 1)}°  '
      'TrackMag=${NmeaConvert.fixed(trackMagnetic, 1)}°  '
      'Speed=${NmeaConvert.fixed(speedKnots, 1)}kn '
      '(${NmeaConvert.fixed(speedKph, 1)}km/h)  Mode=${mode ?? ''}';
}
