/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Frame parser for InterMet iMet-1-RS / iMet-4 radiosondes. Ported from the
reference `imet1rs_dft.c` decoder (author zilog80).

iMet transmits Bell-202 AFSK at 1200 baud, 8N1. The byte stream carries a
series of SOH (0x01) delimited packets, each protected by a CRC16-CCITT (init
0x1D0F). The GPS packet carries IEEE-754 latitude/longitude and time-of-day.
*/

library;

import 'dart:math' as math;
import 'dart:typed_data';

/// A decoded iMet fix (position + time-of-day; iMet frames carry no date).
class ImetFrame {
  ImetFrame({
    required this.hour,
    required this.minute,
    required this.second,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.satellites,
    this.horizontalSpeed = 0,
    this.verticalSpeed = 0,
    this.heading = 0,
  });

  final int hour;
  final int minute;
  final int second;
  final double latitude;
  final double longitude;
  final int altitude;
  final int satellites;
  final double horizontalSpeed;
  final double verticalSpeed;
  final double heading;

  @override
  String toString() =>
      'iMet ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}'
      ':${second.toString().padLeft(2, '0')} lat=$latitude lon=$longitude '
      'alt=$altitude sats=$satellites';
}

/// Parses an iMet byte stream (SOH-delimited, CRC-checked packets).
class ImetDecoder {
  ImetDecoder();

  static const int _soh = 0x01;
  static const int _pktPtu = 0x01;
  static const int _pktGps = 0x02;
  static const int _pktXdata = 0x03;
  static const int _pktEptu = 0x04;
  static const int _pktEgps = 0x05;

  // GPS packet field offsets (relative to SOH).
  static const int _posLat = 0x02; // float32 LE
  static const int _posLon = 0x06; // float32 LE
  static const int _posAlt = 0x0A; // u16 LE, alt = n - 5000
  static const int _posSats = 0x0C;
  static const int _posGpsTime = 0x0D; // hr,min,sec
  static const int _posGpsCrc = 0x10;
  static const int _posEgpsVE = 0x0D; // float32 LE
  static const int _posEgpsVN = 0x11;
  static const int _posEgpsVU = 0x15;
  static const int _posEgpsTime = 0x19;
  static const int _posEgpsCrc = 0x1C;

  /// Scans [bytes] for valid GPS/eGPS packets and returns the decoded fixes.
  List<ImetFrame> decodeStream(List<int> bytes) {
    final out = <ImetFrame>[];
    final n = bytes.length;
    int i = 0;
    while (i < n - 1) {
      if (bytes[i] != _soh) {
        i++;
        continue;
      }
      final pktId = bytes[i + 1];
      final consumed = _tryPacket(bytes, i, pktId, out);
      if (consumed > 0) {
        i += consumed;
      } else {
        i++;
      }
    }
    return out;
  }

  // Returns the packet length (incl. CRC) if valid/known, else 0.
  int _tryPacket(List<int> b, int pos, int pktId, List<ImetFrame> out) {
    switch (pktId) {
      case _pktGps:
      case _pktEgps:
        final crcOff = pktId == _pktGps ? _posGpsCrc : _posEgpsCrc;
        if (pos + crcOff + 2 > b.length) return 0;
        if (!_crcOk(b, pos, crcOff)) return 0;
        final f = _parseGps(b, pos, pktId);
        if (f != null) out.add(f);
        return crcOff + 2;
      case _pktPtu:
      case _pktEptu:
        final crcOff = pktId == _pktPtu ? 0x0C : 0x12;
        if (pos + crcOff + 2 > b.length) return 0;
        if (!_crcOk(b, pos, crcOff)) return 0;
        return crcOff + 2;
      case _pktXdata:
        final nData = pos + 2 < b.length ? b[pos + 2] : 0;
        final crcLen = 3 + nData;
        if (pos + crcLen + 2 > b.length) return 0;
        if (!_crcOk(b, pos, crcLen)) return 0;
        return crcLen + 2;
      default:
        return 0;
    }
  }

  ImetFrame? _parseGps(List<int> b, int pos, int pktId) {
    final lat = _f32le(b, pos + _posLat);
    final lon = _f32le(b, pos + _posLon);
    final alt = ((b[pos + _posAlt + 1] << 8) | b[pos + _posAlt]) - 5000;
    final sats = b[pos + _posSats];
    if (lat.isNaN || lon.isNaN) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    if (lat == 0 && lon == 0) return null;

    final tOff = pktId == _pktGps ? _posGpsTime : _posEgpsTime;
    final hr = b[pos + tOff];
    final mi = b[pos + tOff + 1];
    final se = b[pos + tOff + 2];
    if (hr > 23 || mi > 59 || se > 60) return null;

    double vH = 0, vV = 0, vD = 0;
    if (pktId == _pktEgps) {
      final vE = _f32le(b, pos + _posEgpsVE);
      final vN = _f32le(b, pos + _posEgpsVN);
      vV = _f32le(b, pos + _posEgpsVU);
      vH = math.sqrt(vE * vE + vN * vN);
      vD = math.atan2(vE, vN) * 180 / math.pi;
      if (vD < 0) vD += 360;
    }

    return ImetFrame(
      hour: hr,
      minute: mi,
      second: se,
      latitude: lat,
      longitude: lon,
      altitude: alt,
      satellites: sats,
      horizontalSpeed: vH,
      verticalSpeed: vV,
      heading: vD,
    );
  }

  bool _crcOk(List<int> b, int pos, int len) {
    final stored = (b[pos + len] << 8) | b[pos + len + 1];
    return stored == crc16(b, pos, len);
  }

  /// CRC16-CCITT with init 0x1D0F, poly 0x1021 (iMet).
  static int crc16(List<int> b, int start, int len) {
    int rem = 0x1D0F;
    for (int i = 0; i < len; i++) {
      rem ^= b[start + i] << 8;
      for (int j = 0; j < 8; j++) {
        rem = (rem & 0x8000) != 0 ? ((rem << 1) ^ 0x1021) & 0xFFFF : (rem << 1) & 0xFFFF;
      }
    }
    return rem;
  }

  static final ByteData _fbuf = ByteData(4);
  static double _f32le(List<int> b, int p) {
    if (p + 4 > b.length) return double.nan;
    _fbuf.setUint8(0, b[p]);
    _fbuf.setUint8(1, b[p + 1]);
    _fbuf.setUint8(2, b[p + 2]);
    _fbuf.setUint8(3, b[p + 3]);
    return _fbuf.getFloat32(0, Endian.little);
  }
}
