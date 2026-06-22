/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `GpsTool.Nmea.NmeaParser` class.
*/

/// Result of parsing a raw NMEA line into its identifier and data fields.
class NmeaParseResult {
  final String sentenceId;
  final List<String> fields;

  const NmeaParseResult(this.sentenceId, this.fields);
}

/// Validates and splits raw NMEA 0183 sentences.
class NmeaParser {
  NmeaParser._();

  /// Tries to parse a raw NMEA line into its sentence identifier and data
  /// fields. Returns `null` when the line is malformed or the checksum is
  /// invalid.
  static NmeaParseResult? tryParse(String line) {
    if (line.trim().isEmpty) return null;

    line = line.trim();

    // Must start with '$' or '!'
    if (line.length < 6 || (line[0] != '\$' && line[0] != '!')) return null;

    // Split off the checksum (after '*')
    final starIndex = line.lastIndexOf('*');
    String body;
    if (starIndex > 0 && starIndex < line.length - 1) {
      final checksumHex = line.substring(starIndex + 1);
      body = line.substring(1, starIndex); // skip leading '$'

      if (!_validateChecksum(body, checksumHex)) return null;
    } else {
      // No checksum – accept but tolerate.
      body = line.substring(1);
    }

    final parts = body.split(',');
    if (parts.isEmpty) return null;

    return NmeaParseResult(parts[0], parts); // e.g. "GPGGA", "GNGGA"
  }

  /// Computes XOR checksum over the body (between '$' and '*') and compares it
  /// with the provided two-character hex value.
  static bool _validateChecksum(String body, String expectedHex) {
    if (expectedHex.length < 2) return false;

    var computed = 0;
    for (final c in body.codeUnits) {
      computed ^= c;
    }

    final expected = int.tryParse(expectedHex, radix: 16);
    return expected != null && computed == expected;
  }
}
