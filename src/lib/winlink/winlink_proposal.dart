/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';

import '../services/data_broker_client.dart';

/// Compression applied to the payload of a Winlink B2F message.
enum WinlinkCompressionType {
  /// Standard B2F LZHUF compression, sent with an `FC` proposal.
  lzhuf,

  /// GZIP compression, sent with an `FD` proposal. This is the experimental
  /// wl2k-go/Pat extension and is only used when both stations advertise it.
  gzip,
}

/// Negotiation of the GZIP B2F extension.
///
/// A station advertises GZIP support with a `G` in the capability field of its
/// SID (for example `[Pat-0.16-B2FHMG$]`). GZIP is only sent to a station that
/// advertised it; every other station keeps receiving standard LZHUF mail.
class WinlinkGzip {
  WinlinkGzip._();

  /// Persisted setting (1 = enabled, the default; 0 = disabled).
  static const String settingName = 'WinlinkGzipCompression';

  static const String sidFlag = 'G';

  static bool isEnabled(DataBrokerClient broker) =>
      (broker.getValue<int>(0, settingName, 1) ?? 1) == 1;

  /// Returns the upper-cased capability field of a SID line, e.g. `B2FHM$` for
  /// `[RMS Express-1.7.28.0-B2FHM$]`, or null when [line] is not a SID.
  static String? sidCapabilities(String line) {
    final sid = line.trim();
    if (sid.length < 3 || !sid.startsWith('[') || !sid.endsWith(']')) {
      return null;
    }
    final dash = sid.lastIndexOf('-');
    if (dash < 0) return null;
    return sid.substring(dash + 1, sid.length - 1).toUpperCase();
  }

  /// Whether [line] is a SID that advertises GZIP support.
  static bool sidSupportsGzip(String line) =>
      sidCapabilities(line)?.contains(sidFlag) ?? false;

  /// Adds the GZIP flag to [sid], keeping `$` as the last capability.
  static String addGzipFlag(String sid) {
    final capabilities = sidCapabilities(sid);
    if (capabilities == null || capabilities.contains(sidFlag)) return sid;
    final insertAt = sid.endsWith('\$]') ? sid.length - 2 : sid.length - 1;
    return '${sid.substring(0, insertAt)}$sidFlag${sid.substring(insertAt)}';
  }
}

/// A Winlink B2F `FC` (LZHUF) or `FD` (GZIP) message proposal line.
class WinlinkProposal {
  WinlinkProposal._(
    this.line,
    this.compression,
    this.mid,
    this.uncompressedSize,
    this.compressedSize,
  );

  /// The proposal line exactly as received, without the trailing CR.
  final String line;
  final WinlinkCompressionType compression;
  final String mid;
  final int uncompressedSize;
  final int compressedSize;

  static String commandFor(WinlinkCompressionType compression) =>
      compression == WinlinkCompressionType.gzip ? 'FD' : 'FC';

  /// Builds a proposal line (without the trailing CR).
  static String format({
    required WinlinkCompressionType compression,
    required String mid,
    required int uncompressedSize,
    required int compressedSize,
  }) =>
      '${commandFor(compression)} EM $mid $uncompressedSize $compressedSize 0';

  /// Parses an `FC` or `FD` proposal for an `EM` message with a 12 character
  /// MID. Returns null for any other or malformed line.
  static WinlinkProposal? parse(String line) {
    final parts = line.split(' ');
    if (parts.length < 6) return null;
    final WinlinkCompressionType compression;
    switch (parts[0].toUpperCase()) {
      case 'FC':
        compression = WinlinkCompressionType.lzhuf;
      case 'FD':
        compression = WinlinkCompressionType.gzip;
      default:
        return null;
    }
    if (parts[1] != 'EM' || parts[2].length != 12) return null;
    final uncompressedSize = int.tryParse(parts[3]);
    final compressedSize = int.tryParse(parts[4]);
    if (uncompressedSize == null ||
        compressedSize == null ||
        int.tryParse(parts[5]) == null) {
      return null;
    }
    return WinlinkProposal._(
      line,
      compression,
      parts[2],
      uncompressedSize,
      compressedSize,
    );
  }

  /// Sum of the bytes of [lines], each followed by a CR, as used by the B2F
  /// `F> XX` proposal block checksum (before negation).
  static int byteSum(Iterable<String> lines) {
    int sum = 0;
    for (final line in lines) {
      for (final b in utf8.encode('$line\r')) {
        sum += b;
      }
    }
    return sum;
  }
}
