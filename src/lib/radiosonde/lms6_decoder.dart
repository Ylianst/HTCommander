/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Frame parser for Lockheed Martin LMS6 (403 MHz) radiosondes. Ported from the
reference `lms6Xmod.c` decoder (author zilog80).

The LMS6 physical layer is a rate-1/2 convolutional code (transmitted as
(c0, inv(c1))) wrapping a Reed-Solomon(255,223) CCSDS block. This decoder takes
the transmitted bit stream, undoes the odd-bit inversion, deconvolves it, packs
bytes (LSB-first), corrects the RS block and parses the big-endian GPS frame.
*/

library;

import 'dart:math' as math;

import 'convolutional.dart';
import 'reed_solomon.dart';

/// A decoded LMS6 fix (position + time-of-day; LMS6 frames carry no date).
class Lms6Frame {
  Lms6Frame({
    required this.serial,
    required this.frameNumber,
    required this.hour,
    required this.minute,
    required this.second,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalSpeed,
    required this.verticalSpeed,
    required this.heading,
  });

  final int serial;
  final int frameNumber;
  final int hour;
  final int minute;
  final int second;
  final double latitude;
  final double longitude;
  final double altitude;
  final double horizontalSpeed;
  final double verticalSpeed;
  final double heading;

  @override
  String toString() =>
      'LMS6 $serial [$frameNumber] '
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}'
      ':${second.toString().padLeft(2, '0')} lat=$latitude lon=$longitude '
      'alt=${altitude.toStringAsFixed(1)}';
}

/// Parses LMS6 transmitted bit streams into fixes.
class Lms6Decoder {
  Lms6Decoder();

  static const List<int> syncBytes = [0x00, 0x58, 0xF3, 0x3F, 0xB8];
  static const List<int> frmSync6 = [0x24, 0x54, 0x00, 0x00];
  static const int _syncLen = 5;
  static const int _frmLen = 223;
  static const int _ofs = 4;

  // Frame field offsets (relative to frame start; big-endian).
  static const int _posSN = _ofs + 0x00;
  static const int _posFrameNb = _ofs + 0x04;
  static const int _posTOW = _ofs + 0x06;
  static const int _posLat = _ofs + 0x0E;
  static const int _posLon = _ofs + 0x12;
  static const int _posAlt = _ofs + 0x16;
  static const int _posVE = _ofs + 0x1A;
  static const int _posVN = _ofs + 0x1D;
  static const int _posVU = _ofs + 0x20;

  static final double _b60b60 = (1 << 30) / 90.0;

  final ReedSolomon _rs =
      ReedSolomon(nroots: 32, fcr: 112, prim: 0x187, primPow: 11);

  /// Decodes a transmitted LMS6 bit stream (starting at the block sync).
  Lms6Frame? decodeRawBits(List<int> transmitted) {
    if (transmitted.length < 4000) return null;

    // Undo the (c0, inv(c1)) odd-bit inversion.
    final raw = List<int>.generate(
      transmitted.length,
      (i) => transmitted[i] ^ (i & 1),
    );

    final messageBits = ConvCodec.deconv(raw);
    if (messageBits == null) return null;

    // Pack bytes LSB-first.
    final nBytes = messageBits.length ~/ 8;
    if (nBytes < 260) return null;
    final block = List<int>.filled(260, 0);
    for (int i = 0; i < 260; i++) {
      int b = 0;
      for (int k = 0; k < 8; k++) {
        if (messageBits[i * 8 + k] == 1) b |= 1 << k;
      }
      block[i] = b;
    }

    // Verify the 5-byte block sync.
    for (int i = 0; i < _syncLen; i++) {
      if (block[i] != syncBytes[i]) return null;
    }

    // Reed-Solomon over the 255 bytes after the block sync (reversed).
    final cw = List<int>.filled(255, 0);
    for (int j = 0; j < 255; j++) {
      cw[254 - j] = block[_syncLen + j];
    }
    if (_rs.decode(cw) < 0) return null;
    for (int j = 0; j < 255; j++) {
      block[_syncLen + j] = cw[254 - j];
    }

    // The data frame starts right after the block sync.
    final frame = block.sublist(_syncLen, _syncLen + _frmLen);
    if (frame[0] != frmSync6[0] || frame[1] != frmSync6[1]) return null;

    final crc = (frame[221] << 8) | frame[222];
    if (crc != crc16Zero(frame, 221)) return null;

    return _parse(frame);
  }

  Lms6Frame? _parse(List<int> f) {
    final sn = _u32be(f, _posSN) & 0xFFFFFF;
    final frnr = (f[_posFrameNb] << 8) | f[_posFrameNb + 1];
    final tow = _u32be(f, _posTOW);
    final gpssec = tow ~/ 1000;
    final ms = tow % 1000;
    final sod = gpssec % 86400;

    final lat = _i32be(f, _posLat) / _b60b60;
    final lon = _i32be(f, _posLon) / _b60b60;
    final alt = _i32be(f, _posAlt) / 1000.0;
    if (lat == 0 && lon == 0) return null;
    if (alt < -400 || alt > 60000) return null;

    final vE = _i24be(f, _posVE) / 1e3;
    final vN = _i24be(f, _posVN) / 1e3;
    final vU = _i24be(f, _posVU) / 1e3;
    final vH = math.sqrt(vE * vE + vN * vN);
    var vD = math.atan2(vE, vN) * 180 / math.pi;
    if (vD < 0) vD += 360;

    return Lms6Frame(
      serial: sn,
      frameNumber: frnr,
      hour: sod ~/ 3600,
      minute: (sod % 3600) ~/ 60,
      second: sod % 60 + (ms >= 500 ? 1 : 0),
      latitude: lat,
      longitude: lon,
      altitude: alt,
      horizontalSpeed: vH,
      verticalSpeed: vU,
      heading: vD,
    );
  }

  static int _u32be(List<int> f, int p) =>
      (f[p] << 24) | (f[p + 1] << 16) | (f[p + 2] << 8) | f[p + 3];

  static int _i32be(List<int> f, int p) {
    final v = _u32be(f, p);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  static int _i24be(List<int> f, int p) {
    final v = (f[p] << 16) | (f[p + 1] << 8) | f[p + 2];
    return v >= 0x800000 ? v - 0x1000000 : v;
  }

  /// CRC16-CCITT with init 0x0000 (LMS6).
  static int crc16Zero(List<int> b, int len) {
    int rem = 0;
    for (int i = 0; i < len; i++) {
      rem ^= b[i] << 8;
      for (int j = 0; j < 8; j++) {
        rem = (rem & 0x8000) != 0 ? ((rem << 1) ^ 0x1021) & 0xFFFF : (rem << 1) & 0xFFFF;
      }
    }
    return rem;
  }
}
