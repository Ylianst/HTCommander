/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';

/// Converts between the APRS-IS wire format (TNC2 text) and the app's internal
/// [AX25Packet] model.
///
/// A TNC2 line looks like:
///
///   `SRC>DEST,DIGI1,DIGI2:information field`
///
/// The app stores addresses in AX.25 wire order: `addresses[0]` is the
/// destination, `addresses[1]` is the source, and any remaining addresses are
/// the digipeater path. This is exactly the layout the rest of the APRS stack
/// ([AprsPacket.parse], the APRS tab, the map tab) already expects, so a decoded
/// TNC2 line flows through the existing pipeline unchanged.
class Tnc2Codec {
  Tnc2Codec._();

  /// Parses a single TNC2 text line into an [AX25Packet], or returns null when
  /// the line is not a valid APRS packet (a comment, a malformed header, or an
  /// empty information field).
  ///
  /// A trailing CR/LF, if present, is ignored. Used-path markers (`*`) on
  /// digipeater callsigns are stripped — they are not representable in the
  /// simple address model and are not needed for display or parsing.
  static AX25Packet? decode(String line, {DateTime? time}) {
    if (line.isEmpty) return null;

    // Strip a trailing CR/LF.
    var text = line;
    while (text.isNotEmpty &&
        (text.codeUnitAt(text.length - 1) == 0x0D ||
            text.codeUnitAt(text.length - 1) == 0x0A)) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) return null;

    // Comment / server keep-alive lines start with '#'.
    if (text.codeUnitAt(0) == 0x23) return null;

    // Split header from the information field on the first ':'.
    final colon = text.indexOf(':');
    if (colon < 1) return null;
    final header = text.substring(0, colon);
    final info = text.substring(colon + 1);
    if (info.isEmpty) return null;

    // Split "SRC>DEST,path" on the first '>'.
    final gt = header.indexOf('>');
    if (gt < 1) return null;
    final srcStr = header.substring(0, gt);
    final rest = header.substring(gt + 1);
    if (rest.isEmpty) return null;

    final hops = rest.split(',');
    final destStr = hops.isNotEmpty ? hops[0] : '';
    if (destStr.isEmpty) return null;

    final srcAddr = _parseHop(srcStr);
    final destAddr = _parseHop(destStr);
    if (srcAddr == null || destAddr == null) return null;

    // AX.25 order: [destination, source, ...digipeaters].
    final addresses = <AX25Address>[destAddr, srcAddr];
    for (var i = 1; i < hops.length; i++) {
      final hop = hops[i];
      if (hop.isEmpty) continue;
      final digi = _parseHop(hop);
      if (digi != null) addresses.add(digi);
    }

    final packet = AX25Packet.ui(addresses, info, time ?? DateTime.now());
    packet.pid = 240;
    packet.incoming = true;
    packet.sent = false;
    return packet;
  }

  /// Serializes an [AX25Packet] back into a TNC2 text line (without the trailing
  /// CR/LF). Returns null when the packet has no source/destination or no
  /// information field.
  static String? encode(AX25Packet packet) {
    if (packet.addresses.length < 2) return null;
    final dataStr = packet.dataStr;
    if (dataStr == null || dataStr.isEmpty) return null;

    final dest = packet.addresses[0].toString();
    final src = packet.addresses[1].toString();
    final buffer = StringBuffer('$src>$dest');
    for (var i = 2; i < packet.addresses.length; i++) {
      buffer.write(',');
      buffer.write(packet.addresses[i].toString());
    }
    buffer.write(':');
    buffer.write(dataStr);
    return buffer.toString();
  }

  /// Parses a single callsign hop, stripping a trailing used-path marker (`*`).
  static AX25Address? _parseHop(String hop) {
    var h = hop.trim();
    if (h.endsWith('*')) h = h.substring(0, h.length - 1);
    if (h.isEmpty) return null;
    return AX25Address.parse(h);
  }
}
