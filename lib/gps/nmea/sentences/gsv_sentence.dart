/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.Sentences.GsvSentence` class.
*/

import '../nmea_convert.dart';

/// Information about a single satellite in view (used by [GsvSentence]).
class SatelliteInfo {
  final int prn;
  final int? elevationDeg;
  final int? azimuthDeg;
  final int? snr;

  const SatelliteInfo({
    required this.prn,
    this.elevationDeg,
    this.azimuthDeg,
    this.snr,
  });

  @override
  String toString() =>
      'PRN ${prn.toString().padLeft(2)}: '
      'El=${(elevationDeg?.toString() ?? '').padLeft(3)}°  '
      'Az=${(azimuthDeg?.toString() ?? '').padLeft(3)}°  '
      'SNR=${snr?.toString() ?? '--'}dB';
}

/// GSV – GNSS Satellites in View.
class GsvSentence {
  final int? totalMessages;
  final int? messageNumber;
  final int? satellitesInView;
  final List<SatelliteInfo> satellites;

  const GsvSentence({
    this.totalMessages,
    this.messageNumber,
    this.satellitesInView,
    this.satellites = const [],
  });

  /// Fields: $--GSV,totalMsgs,msgNum,satInView, [prn,elev,az,snr] x 1..4 *cs
  static GsvSentence parse(List<String> fields) {
    final sats = <SatelliteInfo>[];
    var idx = 4;
    while (idx + 3 < fields.length) {
      final prn = NmeaConvert.toInt(fields[idx]);
      if (prn == null) break;

      sats.add(
        SatelliteInfo(
          prn: prn,
          elevationDeg: NmeaConvert.toInt(NmeaConvert.at(fields, idx + 1)),
          azimuthDeg: NmeaConvert.toInt(NmeaConvert.at(fields, idx + 2)),
          snr: NmeaConvert.toInt(NmeaConvert.at(fields, idx + 3)),
        ),
      );
      idx += 4;
    }

    return GsvSentence(
      totalMessages: NmeaConvert.toInt(NmeaConvert.at(fields, 1)),
      messageNumber: NmeaConvert.toInt(NmeaConvert.at(fields, 2)),
      satellitesInView: NmeaConvert.toInt(NmeaConvert.at(fields, 3)),
      satellites: sats,
    );
  }

  @override
  String toString() {
    final satLines = satellites.map((s) => s.toString()).join('  |  ');
    return '[GSV] Msg ${messageNumber ?? ''}/${totalMessages ?? ''}  '
        'InView=${satellitesInView ?? ''}  $satLines';
  }
}
