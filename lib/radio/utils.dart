/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';

/// Utility functions for radio protocol handling
class RadioUtils {
  /// Decodes a short binary message format used by BSS protocol
  /// Format: [01] [len][key][value...] [len][key][value...] ...
  static Map<int, Uint8List> decodeShortBinaryMessage(Uint8List data) {
    final result = <int, Uint8List>{};
    if (data.isEmpty) return result;

    int index = 0;

    // Ignore the leading 01 if present
    if (data[0] == 0x01) index = 1;

    while (index < data.length) {
      // Need at least length + key
      if (index + 1 >= data.length) break;

      final length = data[index];
      final key = data[index + 1];

      // Length must allow key(1) + value(?)
      if (length < 1) break;

      final valueLen = length - 1;

      // Check if we have enough bytes for value
      if (index + 2 + valueLen > data.length) break;

      final value = Uint8List(valueLen);
      for (int i = 0; i < valueLen; i++) {
        value[i] = data[index + 2 + i];
      }

      result[key] = value;

      // Move index to next block
      index += (2 + valueLen);
    }

    return result;
  }

  /// Converts bytes to hex string
  static String bytesToHex(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    const hexAlphabet = '0123456789ABCDEF';
    final result = StringBuffer();
    for (final b in bytes) {
      result.write(hexAlphabet[b >> 4]);
      result.write(hexAlphabet[b & 0xF]);
    }
    return result.toString();
  }

  /// Converts bytes at offset to hex string
  static String bytesToHexRange(Uint8List bytes, int offset, int length) {
    if (bytes.isEmpty) return '';
    const hexAlphabet = '0123456789ABCDEF';
    final result = StringBuffer();
    for (int i = offset; i < length + offset && i < bytes.length; i++) {
      result.write(hexAlphabet[bytes[i] >> 4]);
      result.write(hexAlphabet[bytes[i] & 0xF]);
    }
    return result.toString();
  }

  /// Converts hex string to byte array
  static Uint8List? hexStringToByteArray(String hex) {
    try {
      if (hex.length % 2 != 0) return null;
      final bytes = Uint8List(hex.length ~/ 2);
      const hexValue = [
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, //
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
        0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
      ];
      for (int i = 0, x = 0; i < hex.length; i += 2, x++) {
        final c1 = hex[i].toUpperCase().codeUnitAt(0) - '0'.codeUnitAt(0);
        final c2 = hex[i + 1].toUpperCase().codeUnitAt(0) - '0'.codeUnitAt(0);
        if (c1 < 0 ||
            c1 >= hexValue.length ||
            c2 < 0 ||
            c2 >= hexValue.length) {
          return null;
        }
        bytes[x] = (hexValue[c1] << 4) | hexValue[c2];
      }
      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// Gets a big-endian short (2 bytes) from data at position
  static int getShort(Uint8List d, int p) {
    return (d[p] << 8) + d[p + 1];
  }

  /// Gets a big-endian int (4 bytes) from data at position
  static int getInt(Uint8List d, int p) {
    return (d[p] << 24) + (d[p + 1] << 16) + (d[p + 2] << 8) + d[p + 3];
  }

  /// Sets a big-endian short (2 bytes) in data at position
  static void setShort(Uint8List d, int p, int v) {
    d[p] = (v >> 8) & 0xFF;
    d[p + 1] = v & 0xFF;
  }

  /// Sets a big-endian int (4 bytes) in data at position
  static void setInt(Uint8List d, int p, int v) {
    d[p] = (v >> 24) & 0xFF;
    d[p + 1] = (v >> 16) & 0xFF;
    d[p + 2] = (v >> 8) & 0xFF;
    d[p + 3] = v & 0xFF;
  }

  /// Removes surrounding quotes from a string
  static String removeQuotes(String value) {
    if (value.length < 2) return value;
    if (value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    if (value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Try to parse a double from string
  static double? tryParseDouble(String value) {
    return double.tryParse(value);
  }

  /// Try to parse an int from string
  static int? tryParseInt(String value) {
    return int.tryParse(value);
  }

  /// Compare two byte arrays for equality
  static bool byteArrayCompare(Uint8List a1, Uint8List a2) {
    if (a1.length != a2.length) return false;
    for (int i = 0; i < a1.length; i++) {
      if (a1[i] != a2[i]) return false;
    }
    return true;
  }

  /// Check if two DateTimes are within a specified number of seconds
  static bool areDateTimesWithinSeconds(
    DateTime dt1,
    DateTime dt2,
    double seconds,
  ) {
    final difference = dt1.difference(dt2).abs();
    return difference.inMilliseconds <= (seconds * 1000);
  }

  /// Parse a callsign with station ID (e.g., "K7VZT-5")
  static ({String callsign, int stationId})? parseCallsignWithId(
    String callsignWithId,
  ) {
    final dashIndex = callsignWithId.indexOf('-');
    if (dashIndex == -1) {
      // No SSID, return callsign with ID 0
      if (callsignWithId.isEmpty || callsignWithId.length > 6) return null;
      return (callsign: callsignWithId.toUpperCase(), stationId: 0);
    }

    final callsign = callsignWithId.substring(0, dashIndex).toUpperCase();
    final idStr = callsignWithId.substring(dashIndex + 1);
    final stationId = int.tryParse(idStr);

    if (callsign.isEmpty || callsign.length > 6) return null;
    if (stationId == null || stationId < 0 || stationId > 15) return null;

    return (callsign: callsign, stationId: stationId);
  }

  /// Convert Unix timestamp to DateTime (UTC)
  static DateTime unixTimeStampToDateTime(int unixTimestamp) {
    return DateTime.fromMillisecondsSinceEpoch(
      unixTimestamp * 1000,
      isUtc: true,
    );
  }

  /// Convert Unix timestamp to local DateTime
  static DateTime unixTimeStampToLocalDateTime(int unixTimestamp) {
    return DateTime.fromMillisecondsSinceEpoch(
      unixTimestamp * 1000,
      isUtc: true,
    ).toLocal();
  }

  /// Get current Unix timestamp
  static int getCurrentUnixTimestamp() {
    return DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  /// Haversine formula - calculate distance in meters between two lat/lon points
  static double haversineMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double r = 6371000; // Earth radius in metres
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;

  /// Decode UTF-8 string from bytes, trimming null characters
  static String decodeUtf8Trimmed(Uint8List data, int offset, int length) {
    final subData = data.sublist(offset, offset + length);
    String result = utf8.decode(subData, allowMalformed: true);
    final nullIndex = result.indexOf('\x00');
    if (nullIndex >= 0) {
      result = result.substring(0, nullIndex);
    }
    return result.trim();
  }

  /// Encode string to UTF-8 bytes, padded to specified length with nulls
  static Uint8List encodeUtf8Padded(String value, int length) {
    final encoded = utf8.encode(value);
    final result = Uint8List(length);
    final copyLen = math.min(encoded.length, length);
    for (int i = 0; i < copyLen; i++) {
      result[i] = encoded[i];
    }
    return result;
  }
}
