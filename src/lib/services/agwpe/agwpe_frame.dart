/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AgwpeFrame` class.

Protocol: AGW Packet Engine (AGWPE) TCP API
Reference: https://www.on7lds.net/42/sites/default/files/AGWPEAPI.HTM
*/

import 'dart:typed_data';

/// AGWPE `DataKind` values used by the protocol. Stored as the ASCII code of
/// the corresponding command/response character so frames serialize exactly
/// like the C# implementation.
class AgwpeDataKind {
  AgwpeDataKind._();

  static const int registerCallsign = 0x58; // 'X'
  static const int unregisterCallsign = 0x78; // 'x'
  static const int getPortInfo = 0x47; // 'G'
  static const int askPortCaps = 0x67; // 'g'
  static const int monitorToggle = 0x6D; // 'm'
  static const int rawMonitorToggle = 0x6B; // 'k'
  static const int version = 0x52; // 'R'
  static const int callsignHeard = 0x48; // 'H'
  static const int sendUnproto = 0x4D; // 'M'
  static const int unprotoResponse = 0x54; // 'T'
  static const int monitorUnproto = 0x55; // 'U'
  static const int connect = 0x43; // 'C'
  static const int disconnect = 0x64; // 'd'
  static const int connectedData = 0x44; // 'D'
}

/// Represents the 36-byte AGW PE API frame header and its optional payload.
///
/// The header layout (little-endian for the 32-bit fields) is:
///   * byte  0       : port
///   * bytes 1..3    : reserved
///   * byte  4       : dataKind
///   * byte  5       : reserved
///   * byte  6       : pid
///   * byte  7       : reserved
///   * bytes 8..17   : callFrom  (ASCII, NUL padded to 10 bytes)
///   * bytes 18..27  : callTo    (ASCII, NUL padded to 10 bytes)
///   * bytes 28..31  : dataLen   (uint32)
///   * bytes 32..35  : user      (uint32)
///   * bytes 36..    : payload
class AgwpeFrame {
  AgwpeFrame({
    this.port = 0,
    this.dataKind = 0,
    this.pid = 0,
    this.callFrom = '',
    this.callTo = '',
    this.user = 0,
    Uint8List? data,
  }) : data = data ?? Uint8List(0);

  /// Total size of the fixed AGWPE header in bytes.
  static const int headerLength = 36;

  int port;
  int dataKind;
  int pid;
  String callFrom;
  String callTo;
  int user;
  Uint8List data;

  /// The `dataKind` value as its ASCII character (for logging / debugging).
  String get dataKindChar =>
      (dataKind >= 0x20 && dataKind < 0x7F) ? String.fromCharCode(dataKind) : '?';

  /// Serializes this frame (header + payload) into a byte buffer ready to be
  /// written to a socket.
  Uint8List toBytes() {
    final payload = data;
    final buffer = Uint8List(headerLength + payload.length);
    buffer[0] = port & 0xFF;
    // bytes 1..3 reserved (already zero)
    buffer[4] = dataKind & 0xFF;
    // byte 5 reserved
    buffer[6] = pid & 0xFF;
    // byte 7 reserved
    _writeCallsign(buffer, 8, callFrom);
    _writeCallsign(buffer, 18, callTo);

    final bd = ByteData.sublistView(buffer);
    bd.setUint32(28, payload.length, Endian.little);
    bd.setUint32(32, user & 0xFFFFFFFF, Endian.little);

    if (payload.isNotEmpty) {
      buffer.setRange(headerLength, headerLength + payload.length, payload);
    }
    return buffer;
  }

  /// Attempts to parse a single AGWPE frame from the front of [buffer].
  ///
  /// Returns `null` when [buffer] does not yet contain a complete frame
  /// (header + declared payload). On success returns the parsed [frame] and the
  /// number of [consumed] bytes so the caller can drop them from its receive
  /// buffer.
  static ({AgwpeFrame frame, int consumed})? tryParse(Uint8List buffer) {
    if (buffer.length < headerLength) return null;

    final bd = ByteData.sublistView(buffer);
    final dataLen = bd.getUint32(28, Endian.little);
    final total = headerLength + dataLen;
    if (buffer.length < total) return null;

    final frame = AgwpeFrame(
      port: buffer[0],
      dataKind: buffer[4],
      pid: buffer[6],
      callFrom: _readCallsign(buffer, 8),
      callTo: _readCallsign(buffer, 18),
      user: bd.getUint32(32, Endian.little),
      data: dataLen > 0
          ? Uint8List.sublistView(buffer, headerLength, total)
          : Uint8List(0),
    );
    return (frame: frame, consumed: total);
  }

  /// Writes [callsign] as ASCII into [buffer] starting at [offset], padded with
  /// NUL bytes to a fixed 10-byte field and truncated if too long.
  static void _writeCallsign(Uint8List buffer, int offset, String callsign) {
    final maxLen = callsign.length > 10 ? 10 : callsign.length;
    for (int i = 0; i < maxLen; i++) {
      final c = callsign.codeUnitAt(i);
      buffer[offset + i] = c < 0x80 ? c : 0x3F; // '?' for non-ASCII
    }
    // Remaining bytes stay zero (NUL padding).
  }

  /// Reads a 10-byte ASCII callsign field at [offset], trimming trailing NUL
  /// and space characters.
  static String _readCallsign(Uint8List buffer, int offset) {
    final sb = StringBuffer();
    for (int i = 0; i < 10; i++) {
      final c = buffer[offset + i];
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString().replaceAll(RegExp(r'[\s\u0000]+$'), '');
  }
}
