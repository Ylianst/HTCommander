/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Frame parser for Meteomodem M20 radiosondes. Ported from the reference
`mXXmod.c` (M18/M20) decoder in projecthorus/radiosonde_auto_rx (author
zilog80). M20 shares the M10 modem but uses a different, more compact frame
layout (69 payload bytes, big-endian GPS scaled by 1e6).
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A decoded M20 fix.
class M20Frame {
  M20Frame({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalSpeed,
    required this.verticalSpeed,
    required this.heading,
    required this.dateTimeUtc,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double altitude;
  final double horizontalSpeed;
  final double verticalSpeed;
  final double heading;
  final DateTime dateTimeUtc;

  @override
  String toString() =>
      'M20 $id lat=$latitude lon=$longitude alt=${altitude.toStringAsFixed(1)} '
      'vH=${horizontalSpeed.toStringAsFixed(1)} $dateTimeUtc';
}

/// Parses M20 frames (verifies the custom checksum, decodes the GPS block).
class M20Decoder {
  M20Decoder();

  static const int frameLen = 70; // frame[0]=0x45 => 0x46 bytes
  static const int stdFLen = 0x45;
  static const int typeM20 = 0x20;

  static const int _posTOW = 0x0F; // 3 byte, seconds
  static const int _posLat = 0x1C; // 4 byte
  static const int _posLon = 0x20; // 4 byte
  static const int _posAlt = 0x08; // 3 byte
  static const int _posWeek = 0x1A; // 2 byte
  static const int _posVE = 0x0B;
  static const int _posVN = 0x0D;
  static const int _posVU = 0x18;
  static const int _posSN = 0x12; // 3 byte
  static const int _posCheck = stdFLen - 1; // 0x44

  static const double _scale = 1e6; // M20 lat/lon scale

  M20Frame? decodeFrame(Uint8List f) {
    if (f.length < frameLen) return null;
    if (f[0] != stdFLen || f[1] != typeM20) return null;

    final cs = (f[_posCheck] << 8) | f[_posCheck + 1];
    if (cs != _checkM10(f, _posCheck)) return null;

    final week = _wnro((f[_posWeek] << 8) | f[_posWeek + 1]);
    if (week < 0) return null;
    final gpssec = (f[_posTOW] << 16) | (f[_posTOW + 1] << 8) | f[_posTOW + 2];
    if (gpssec ~/ 86400 > 6) return null;
    final dt = _gpsToDate(week, gpssec);
    if (dt == null) return null;

    final lat = _i32be(f, _posLat) / _scale;
    final lon = _i32be(f, _posLon) / _scale;
    final alt = ((f[_posAlt] << 16) | (f[_posAlt + 1] << 8) | f[_posAlt + 2]) /
        100.0;
    if (lat == 0 && lon == 0) return null;
    if (alt < -1000 || alt > 80000) return null;

    final vE = _i16be(f, _posVE) / 100.0;
    final vN = _i16be(f, _posVN) / 100.0;
    final vU = _i16be(f, _posVU) / 100.0;
    final vH = math.sqrt(vE * vE + vN * vN);
    var vD = math.atan2(vE, vN) * 180 / math.pi;
    if (vD < 0) vD += 360;

    return M20Frame(
      id: _serial(f),
      latitude: lat,
      longitude: lon,
      altitude: alt,
      horizontalSpeed: vH,
      verticalSpeed: vU,
      heading: vD,
      dateTimeUtc: dt,
    );
  }

  String _serial(Uint8List f) {
    final sn24 = (f[_posSN + 2] << 16) | (f[_posSN + 1] << 8) | f[_posSN];
    final ym = sn24 & 0x7F;
    final y = ym ~/ 12;
    final m = (ym % 12) + 1;
    final d = ((sn24 >> 7) & 0x7) + 1;
    final a = (sn24 >> 23) & 0x1;
    final nnnn = (sn24 >> 10) & 0x1FFF;
    return '$y${m.toString().padLeft(2, '0')}-$d-$a${nnnn.toString().padLeft(4, '0')}';
  }

  static int _u32be(Uint8List f, int p) =>
      (f[p] << 24) | (f[p + 1] << 16) | (f[p + 2] << 8) | f[p + 3];

  static int _i32be(Uint8List f, int p) {
    final v = _u32be(f, p);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  static int _i16be(Uint8List f, int p) {
    final v = (f[p] << 8) | f[p + 1];
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  static int _wnro(int week) {
    if (week > 4000) return -1;
    return week < 1304 ? week + 1024 : week;
  }

  static int _checkM10(Uint8List msg, int len) {
    int c = 0;
    for (int i = 0; i < len; i++) {
      c = _update(c, msg[i]);
    }
    return c & 0xFFFF;
  }

  static int _update(int c, int b) {
    final c1 = c & 0xFF;
    b = ((b >> 1) | ((b & 1) << 7)) & 0xFF;
    b ^= (b >> 2) & 0xFF;
    final t6 = (c & 1) ^ ((c >> 2) & 1) ^ ((c >> 4) & 1);
    final t7 = ((c >> 1) & 1) ^ ((c >> 3) & 1) ^ ((c >> 5) & 1);
    final t = (c & 0x3F) | (t6 << 6) | (t7 << 7);
    int s = (c >> 7) & 0xFF;
    s ^= (s >> 2) & 0xFF;
    return ((c1 << 8) | ((b ^ t ^ s) & 0xFF)) & 0xFFFF;
  }

  DateTime? _gpsToDate(int week, int gpssec) {
    final gpsDays = week * 7 + gpssec ~/ 86400;
    final mjd = 44244 + gpsDays;
    int j = mjd + 2468570;
    final c = 4 * j ~/ 146097;
    j = j - (146097 * c + 3) ~/ 4;
    final y = 4000 * (j + 1) ~/ 1461001;
    j = j - 1461 * y ~/ 4 + 31;
    final mo = 80 * j ~/ 2447;
    final tag = j - 2447 * mo ~/ 80;
    final j2 = mo ~/ 11;
    final monat = mo + 2 - 12 * j2;
    final jahr = 100 * (c - 49) + y + j2;
    final sod = gpssec % 86400;
    try {
      return DateTime.utc(jahr, monat, tag, sod ~/ 3600, (sod % 3600) ~/ 60,
          sod % 60);
    } catch (_) {
      return null;
    }
  }
}
