/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'winlink_gateway.dart';

/// Reader for the HTCommander offline Winlink packet-gateway directory (`.wdb`).
///
/// The directory is tiny (~1200 gateways, ~18 KB), so the whole file is parsed
/// into memory. Each 14-byte record is one gateway-frequency pair; records
/// sharing a callsign key are contiguous and are grouped into a single
/// [WinlinkGateway] carrying all of that station's frequencies.
///
/// The layout matches `src/tools/build_winlink_db.py` (see
/// `docs/Winlink-Gateways.md`). The 32-byte header is little-endian; the
/// multi-byte fields inside each record are big-endian.
///
/// ```
/// Header (32 bytes)
///   0  u32  magic         = "WLGW" (0x57474C57)
///   4  u16  formatVersion = 1
///   6  u16  flags         = 0
///   8  u32  recordCount
///   12 u32  sourceDate    (YYYYMMDD, UTC)
///   16 u32  recordsOffset (= 32)
///   20 …    reserved
///
/// Record (14 bytes), sorted ascending:
///   0  u40 BE  callsignKey = base37(call) * 16 + ssid
///   5  u24 BE  latQ        = round((lat + 90)  * 10000)
///   8  u24 BE  lonQ        = round((lon + 180) * 10000)
///   11 u24 BE  freqQ       = round(freqHz / 100)
/// ```
class WinlinkGatewayDatabase {
  /// File magic: ASCII "WLGW" little-endian.
  static const int magic = 0x57474C57;

  /// Current supported format version.
  static const int formatVersion = 1;

  static const int headerSize = 32;
  static const int recordSize = 14;

  static const int _coordScale = 10000;
  static const int _latOffset = 90;
  static const int _lonOffset = 180;
  static const int _freqScale = 100;

  /// Data date as `YYYYMMDD` (UTC), or 0 when unknown.
  final int sourceDate;

  /// All gateways, grouped by callsign, in ascending callsign-key order.
  final List<WinlinkGateway> gateways;

  const WinlinkGatewayDatabase._(this.sourceDate, this.gateways);

  /// Number of distinct gateways.
  int get gatewayCount => gateways.length;

  /// Parses a decompressed `.wdb` image. Throws [FormatException] on a bad
  /// header, unsupported version, or truncated body.
  factory WinlinkGatewayDatabase.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw const FormatException('Winlink gateway database is too small');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != magic) {
      throw const FormatException('Not a Winlink gateway database (bad magic)');
    }
    final version = data.getUint16(4, Endian.little);
    if (version != formatVersion) {
      throw FormatException('Unsupported .wdb version $version');
    }
    final count = data.getUint32(8, Endian.little);
    final sourceDate = data.getUint32(12, Endian.little);
    final recordsOffset = data.getUint32(16, Endian.little);
    if (recordsOffset + count * recordSize > bytes.length) {
      throw const FormatException('Winlink gateway database is truncated');
    }

    final gateways = <WinlinkGateway>[];
    int? curKey;
    late String curCall;
    late double curLat;
    late double curLon;
    List<int> curFreqs = <int>[];

    void flush() {
      if (curKey != null) {
        gateways.add(WinlinkGateway(
          callsign: curCall,
          latitude: curLat,
          longitude: curLon,
          frequenciesHz: curFreqs,
        ));
      }
    }

    int off = recordsOffset;
    for (int i = 0; i < count; i++) {
      final callKey = _readUintBE(bytes, off, 5);
      final latQ = _readUintBE(bytes, off + 5, 3);
      final lonQ = _readUintBE(bytes, off + 8, 3);
      final freqQ = _readUintBE(bytes, off + 11, 3);
      off += recordSize;

      final freqHz = freqQ * _freqScale;
      if (callKey != curKey) {
        flush();
        curKey = callKey;
        curCall = _decodeCallKey(callKey);
        curLat = latQ / _coordScale - _latOffset;
        curLon = lonQ / _coordScale - _lonOffset;
        curFreqs = <int>[freqHz];
      } else {
        curFreqs.add(freqHz);
      }
    }
    flush();

    return WinlinkGatewayDatabase._(sourceDate, gateways);
  }

  /// The [count] gateways nearest to ([lat], [lon]), closest first.
  List<WinlinkGateway> nearest(double lat, double lon, {int count = 20}) {
    final sorted = List<WinlinkGateway>.of(gateways)
      ..sort((a, b) =>
          a.distanceKmTo(lat, lon).compareTo(b.distanceKmTo(lat, lon)));
    return sorted.take(count).toList();
  }

  /// Gateways whose location falls inside the given bounding box (for viewport
  /// culling). Handles a box that crosses the antimeridian.
  List<WinlinkGateway> withinBounds(
    double minLat,
    double minLon,
    double maxLat,
    double maxLon,
  ) {
    final crossesAntimeridian = minLon > maxLon;
    return gateways.where((g) {
      if (g.latitude < minLat || g.latitude > maxLat) return false;
      if (crossesAntimeridian) {
        return g.longitude >= minLon || g.longitude <= maxLon;
      }
      return g.longitude >= minLon && g.longitude <= maxLon;
    }).toList();
  }

  static int _readUintBE(Uint8List b, int off, int len) {
    int v = 0;
    for (int i = 0; i < len; i++) {
      v = (v << 8) | b[off + i];
    }
    return v;
  }

  /// Reverses `base37(call) * 16 + ssid` back into a display callsign.
  static String _decodeCallKey(int callKey) {
    final ssid = callKey & 0xF;
    int k = callKey >> 4;
    final chars = <int>[];
    while (k > 0) {
      final code = k % 37;
      k ~/= 37;
      if (code >= 1 && code <= 26) {
        chars.add(0x41 + code - 1); // 'A'..'Z'
      } else {
        chars.add(0x30 + code - 27); // '0'..'9'
      }
    }
    final base = String.fromCharCodes(chars.reversed);
    return ssid == 0 ? base : '$base-$ssid';
  }
}
