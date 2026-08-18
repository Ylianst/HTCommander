/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Frame parser for Vaisala RS41 radiosondes. Ported from the reference `rs41mod.c`
decoder in projecthorus/radiosonde_auto_rx (author zilog80).

An RS41 standard frame is 320 dewhitened bytes: an 8-byte sync header, two
interleaved Reed-Solomon(255,231) codewords for error correction, and a series
of length-tagged, CRC-16 protected blocks carrying the sonde ID, GPS ECEF
position/velocity and GPS time.
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'reed_solomon.dart';

/// 64-byte whitening/scrambling mask (frame[i] = wire[i] ^ mask[i % 64]).
const List<int> rs41Mask = [
  0x96, 0x83, 0x3E, 0x51, 0xB1, 0x49, 0x08, 0x98, //
  0x32, 0x05, 0x59, 0x0E, 0xF9, 0x44, 0xC6, 0x26,
  0x21, 0x60, 0xC2, 0xEA, 0x79, 0x5D, 0x6D, 0xA1,
  0x54, 0x69, 0x47, 0x0C, 0xDC, 0xE8, 0x5C, 0xF1,
  0xF7, 0x76, 0x82, 0x7F, 0x07, 0x99, 0xA2, 0x2C,
  0x93, 0x7C, 0x30, 0x63, 0xF5, 0x10, 0x2E, 0x61,
  0xD0, 0xBC, 0xB4, 0xB6, 0x06, 0xAA, 0xF4, 0x23,
  0x78, 0x6E, 0x3B, 0xAE, 0xBF, 0x7B, 0x4C, 0xC1,
];

/// Transmitted (whitened) 64-bit header, LSB-first bit string. This is the raw
/// wire sync pattern the demodulator correlates against.
const String rs41HeaderBits =
    '0000100001101101010100111000100001000100011010010100100000011111';

/// Dewhitened frame header bytes (frame[0..7] after XOR with the mask). Used as
/// a sanity gate by the demodulator; not used by ECC or parsing.
const List<int> rs41DewhitenedHeader = [
  0x86, 0x35, 0xF4, 0x40, 0x93, 0xDF, 0x1A, 0x60,
];

/// A decoded RS41 fix.
class Rs41Frame {
  Rs41Frame({
    required this.frameNumber,
    required this.id,
    required this.batteryVolts,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalSpeed,
    required this.verticalSpeed,
    required this.heading,
    required this.satellites,
    required this.dateTimeUtc,
  });

  final int frameNumber;
  final String id;
  final double batteryVolts;
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
      'RS41[$frameNumber] $id lat=$latitude lon=$longitude '
      'alt=${altitude.toStringAsFixed(1)} vH=${horizontalSpeed.toStringAsFixed(1)} '
      'vV=${verticalSpeed.toStringAsFixed(1)} dir=${heading.toStringAsFixed(1)} '
      'sats=$satellites batt=${batteryVolts.toStringAsFixed(1)}V $dateTimeUtc';
}

/// Parses dewhitened 320-byte RS41 frames (runs Reed-Solomon ECC + CRC checks).
class Rs41Decoder {
  Rs41Decoder();

  static const int ndataLen = 320;
  static const int frameLen = 518; // with xdata padding, for RS

  // Block positions (dewhitened frame byte offsets).
  static const int _posFrame = 0x039;
  static const int _posFrameNb = 0x03B;
  static const int _posSondeId = 0x03D;
  static const int _posBattVolts = 0x045;
  static const int _posGps1 = 0x093;
  static const int _posGpsWeek = 0x095;
  static const int _posGpsITOW = 0x097;
  static const int _posGps3 = 0x112;
  static const int _posEcefX = 0x114;
  static const int _posEcefY = 0x118;
  static const int _posEcefZ = 0x11C;
  static const int _posEcefV = 0x120;
  static const int _posNumSats = 0x126;

  static const int _pckFrame = 0x7928;
  static const int _pckGps1 = 0x7C1E;
  static const int _pckGps3 = 0x7B15;

  // RS layout.
  static const int _rsR = 24;
  static const int _rsK = 231;
  static const int _parPos = 8;
  static const int _msgPos = 56;

  final ReedSolomon _rs = ReedSolomon(nroots: 24, fcr: 0);

  /// Decodes one dewhitened frame (>=320 bytes). Applies RS ECC in place, then
  /// parses the fixed blocks. Returns null if the essential CRCs fail.
  Rs41Frame? decodeFrame(Uint8List frameIn) {
    if (frameIn.length < ndataLen) return null;
    // Work on a 518-byte buffer, zero-padded (shortened RS code).
    final frame = Uint8List(frameLen);
    final copyLen = frameIn.length < frameLen ? frameIn.length : frameLen;
    frame.setRange(0, copyLen, frameIn);

    _rsEcc(frame);

    // Frame-conf block: sonde ID + frame number + battery.
    if (!_crcOk(frame, _posFrame, _pckFrame)) return null;
    final id = _readId(frame);
    if (id == null) return null;
    final frnr = frame[_posFrameNb] | (frame[_posFrameNb + 1] << 8);
    final battery = frame[_posBattVolts] / 10.0;

    // GPS position block (ECEF).
    if (!_crcOk(frame, _posGps3, _pckGps3)) return null;
    final pos = _ecefToGeodetic(frame);
    if (pos == null) return null;

    // GPS time block.
    if (!_crcOk(frame, _posGps1, _pckGps1)) return null;
    final week = frame[_posGpsWeek] | (frame[_posGpsWeek + 1] << 8);
    final itow = _u32(frame, _posGpsITOW);
    final dt = _gpsToDate(week, itow);
    if (dt == null) return null;

    return Rs41Frame(
      frameNumber: frnr,
      id: id,
      batteryVolts: battery,
      latitude: pos.lat,
      longitude: pos.lon,
      altitude: pos.alt,
      horizontalSpeed: pos.vH,
      verticalSpeed: pos.vV,
      heading: pos.vD,
      satellites: frame[_posNumSats],
      dateTimeUtc: dt,
    );
  }

  // Two interleaved RS(255,231) codewords over the frame.
  void _rsEcc(Uint8List frame) {
    final cw1 = List<int>.filled(255, 0);
    final cw2 = List<int>.filled(255, 0);
    for (int i = 0; i < _rsR; i++) {
      cw1[i] = frame[_parPos + i];
      cw2[i] = frame[_parPos + _rsR + i];
    }
    for (int i = 0; i < _rsK; i++) {
      cw1[_rsR + i] = frame[_msgPos + 2 * i];
      cw2[_rsR + i] = frame[_msgPos + 2 * i + 1];
    }
    final e1 = _rs.decode(cw1);
    final e2 = _rs.decode(cw2);
    if (e1 < 0 && e2 < 0) return; // leave frame as-is; CRCs will reject
    if (e1 >= 0) {
      for (int i = 0; i < _rsR; i++) {
        frame[_parPos + i] = cw1[i];
      }
      for (int i = 0; i < _rsK; i++) {
        frame[_msgPos + 2 * i] = cw1[_rsR + i];
      }
    }
    if (e2 >= 0) {
      for (int i = 0; i < _rsR; i++) {
        frame[_parPos + _rsR + i] = cw2[i];
      }
      for (int i = 0; i < _rsK; i++) {
        frame[_msgPos + 2 * i + 1] = cw2[_rsR + i];
      }
    }
  }

  static int _crc16(Uint8List data, int start, int len) {
    int rem = 0xFFFF;
    for (int i = 0; i < len; i++) {
      rem ^= data[start + i] << 8;
      for (int j = 0; j < 8; j++) {
        if (rem & 0x8000 != 0) {
          rem = ((rem << 1) ^ 0x1021) & 0xFFFF;
        } else {
          rem = (rem << 1) & 0xFFFF;
        }
      }
    }
    return rem;
  }

  bool _crcOk(Uint8List frame, int pos, int pck) {
    if (((pck >> 8) & 0xFF) != frame[pos]) return false;
    final len = frame[pos + 1];
    if (pos + len + 4 > frame.length) return false;
    final crc = frame[pos + 2 + len] | (frame[pos + 2 + len + 1] << 8);
    return crc == _crc16(frame, pos + 2, len);
  }

  String? _readId(Uint8List frame) {
    final sb = StringBuffer();
    for (int i = 0; i < 8; i++) {
      final b = frame[_posSondeId + i];
      if (b < 0x20 || b > 0x7E) return null;
      sb.writeCharCode(b);
    }
    return sb.toString();
  }

  static int _u32(Uint8List f, int p) =>
      f[p] | (f[p + 1] << 8) | (f[p + 2] << 16) | (f[p + 3] << 24);

  static int _i32(Uint8List f, int p) {
    final v = _u32(f, p);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  static int _i16(Uint8List f, int p) {
    final v = f[p] | (f[p + 1] << 8);
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  _Pos? _ecefToGeodetic(Uint8List frame) {
    final x = _i32(frame, _posEcefX) / 100.0;
    final y = _i32(frame, _posEcefY) / 100.0;
    final z = _i32(frame, _posEcefZ) / 100.0;
    if (x == 0 && y == 0 && z == 0) return null;

    const a = 6378137.0;
    const b = 6356752.31424518;
    const a2b2 = a * a - b * b;
    const e2 = a2b2 / (a * a);
    const ee2 = a2b2 / (b * b);

    final lam = math.atan2(y, x);
    final p = math.sqrt(x * x + y * y);
    final t = math.atan2(z * a, p * b);
    final st = math.sin(t), ct = math.cos(t);
    final phi = math.atan2(
      z + ee2 * b * st * st * st,
      p - e2 * a * ct * ct * ct,
    );
    final sphi = math.sin(phi);
    final r = a / math.sqrt(1 - e2 * sphi * sphi);
    final alt = p / math.cos(phi) - r;
    final lat = phi * 180 / math.pi;
    final lon = lam * 180 / math.pi;
    if (alt < -1000 || alt > 80000) return null;

    final vx = _i16(frame, _posEcefV) / 100.0;
    final vy = _i16(frame, _posEcefV + 2) / 100.0;
    final vz = _i16(frame, _posEcefV + 4) / 100.0;
    final lamr = lam, phir = phi;
    final vN = -vx * math.sin(phir) * math.cos(lamr) -
        vy * math.sin(phir) * math.sin(lamr) +
        vz * math.cos(phir);
    final vE = -vx * math.sin(lamr) + vy * math.cos(lamr);
    final vU = vx * math.cos(phir) * math.cos(lamr) +
        vy * math.cos(phir) * math.sin(lamr) +
        vz * math.sin(phir);
    final vH = math.sqrt(vN * vN + vE * vE);
    var vD = math.atan2(vE, vN) * 180 / math.pi;
    if (vD < 0) vD += 360;

    return _Pos(lat, lon, alt, vH, vU, vD);
  }

  DateTime? _gpsToDate(int week, int itowMs) {
    if (week <= 0) return null;
    final ms = itowMs % 1000;
    final gpssec = itowMs ~/ 1000;
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
    final std = sod ~/ 3600;
    final min = (sod % 3600) ~/ 60;
    final sek = sod % 60;
    try {
      return DateTime.utc(jahr, monat, tag, std, min, sek, ms);
    } catch (_) {
      return null;
    }
  }
}

class _Pos {
  _Pos(this.lat, this.lon, this.alt, this.vH, this.vV, this.vD);
  final double lat, lon, alt, vH, vV, vD;
}
