/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Frame parser for Meteomodem M10 radiosondes. Ported from the reference
`m10mod.c` decoder in projecthorus/radiosonde_auto_rx (author zilog80).

An M10 frame is 100 payload bytes + a 2-byte custom checksum. Byte 0 is the
frame length (0x64), byte 1 the type (0x9F = M10). Position comes from an
embedded Trimble Copernicus GPS packet (big-endian, scaled integers).
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A decoded M10 fix.
class M10Frame {
  M10Frame({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalSpeed,
    required this.verticalSpeed,
    required this.heading,
    required this.satellites,
    required this.dateTimeUtc,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double altitude;
  final double horizontalSpeed;
  final double verticalSpeed;
  final double heading;
  final int satellites;
  final DateTime dateTimeUtc;

  @override
  String toString() =>
      'M10 $id lat=$latitude lon=$longitude alt=${altitude.toStringAsFixed(1)} '
      'vH=${horizontalSpeed.toStringAsFixed(1)} sats=$satellites $dateTimeUtc';
}

/// Parses M10 frames (verifies the custom checksum, decodes the Trimble GPS).
class M10Decoder {
  M10Decoder();

  static const int frameLen = 101; // 100 payload + type/len already inside
  static const int stdFLen = 0x64;
  static const int typeM10 = 0x9F;

  // Trimble GPS field offsets (big-endian).
  static const int _posTOW = 0x0A;
  static const int _posLat = 0x0E;
  static const int _posLon = 0x12;
  static const int _posAlt = 0x16;
  static const int _posSats = 0x1E;
  static const int _posWeek = 0x20;
  static const int _posVE = 0x04;
  static const int _posVN = 0x06;
  static const int _posVU = 0x08;
  static const int _posSN = 0x5D;
  static const int _posCheck = stdFLen - 1; // 0x63

  static final double _b60b60 = (1 << 30) / 90.0; // 2^32/360

  /// Decodes a full M10 frame (>= 101 bytes). Returns null on checksum failure
  /// or an unexpected type/length.
  M10Frame? decodeFrame(Uint8List f) {
    if (f.length < frameLen) return null;
    if (f[0] != stdFLen || f[1] != typeM10) return null;

    final cs = (f[_posCheck] << 8) | f[_posCheck + 1];
    if (cs != _checkM10(f, _posCheck)) return null;

    final week = _wnro((f[_posWeek] << 8) | f[_posWeek + 1]);
    if (week < 0) return null;
    final tow = _u32be(f, _posTOW);
    final dt = _gpsToDate(week, tow);
    if (dt == null) return null;

    final lat = _i32be(f, _posLat) / _b60b60;
    final lon = _i32be(f, _posLon) / _b60b60;
    final alt = _i32be(f, _posAlt) / 1000.0;
    if (lat == 0 && lon == 0) return null;
    if (alt < -1000 || alt > 80000) return null;

    final vE = _i16be(f, _posVE) / 200.0;
    final vN = _i16be(f, _posVN) / 200.0;
    final vU = _i16be(f, _posVU) / 200.0;
    final vH = math.sqrt(vE * vE + vN * vN);
    var vD = math.atan2(vE, vN) * 180 / math.pi;
    if (vD < 0) vD += 360;

    return M10Frame(
      id: _serial(f),
      latitude: lat,
      longitude: lon,
      altitude: alt,
      horizontalSpeed: vH,
      verticalSpeed: vU,
      heading: vD,
      satellites: f[_posSats],
      dateTimeUtc: dt,
    );
  }

  String _serial(Uint8List f) {
    final sn = [
      f[_posSN],
      f[_posSN + 1],
      f[_posSN + 2],
      f[_posSN + 3],
      f[_posSN + 4],
    ];
    final b2 = sn[2];
    final p1 = '${((b2 >> 4) & 0xF).toRadixString(16).toUpperCase()}'
        '${(b2 & 0xF).toString().padLeft(2, '0')}';
    final w = sn[3] | (sn[4] << 8);
    final p2 = '${(sn[0] & 0xF).toRadixString(16).toUpperCase()} '
        '${(w >> 13) & 0x7}${(w & 0x1FFF).toString().padLeft(4, '0')}';
    return '$p1 $p2';
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

  // M10 custom linear checksum.
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
    final c0 = (b ^ t ^ s) & 0xFF;
    return ((c1 << 8) | c0) & 0xFFFF;
  }

  DateTime? _gpsToDate(int week, int towMs) {
    final ms = towMs % 1000;
    final gpssec = towMs ~/ 1000;
    final gpsDays = week * 7 + gpssec ~/ 86400;
    final mjd = 44244 + gpsDays;
    int j = mjd + 2468570;
    final c = 4 * j ~/ 146097;
    j = j - (146097 * c + 3) ~/ 4;
    final y = 4000 * (j + 1) ~/ 1461001;
    j = j - 1461 * y ~/ 4 + 31;
    final m = 80 * j ~/ 2447;
    final tag = j - 2447 * m ~/ 80;
    final j2 = m ~/ 11;
    final monat = m + 2 - 12 * j2;
    final jahr = 100 * (c - 49) + y + j2;
    final sod = gpssec % 86400;
    try {
      return DateTime.utc(jahr, monat, tag, sod ~/ 3600, (sod % 3600) ~/ 60,
          sod % 60, ms);
    } catch (_) {
      return null;
    }
  }
}
