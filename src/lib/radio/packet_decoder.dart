/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'ax25_packet.dart';
import 'bss_packet.dart';
import 'tnc_data_fragment.dart';
import 'utils.dart';

/// A named section of decoded packet detail lines.
class PacketDecodeSection {
  final String title;
  final List<MapEntry<String, String>> lines = [];

  PacketDecodeSection(this.title);

  bool get isEmpty => lines.isEmpty;
}

/// Decodes [TncDataFragment]s into human-readable summaries and detail sections.
/// Ported from the C# PacketCaptureTabUserControl decode logic.
class PacketDecoder {
  /// Converts a fragment to a short single-line summary for the packet list.
  static String fragmentToShortString(TncDataFragment fragment) {
    final data = fragment.data;

    // BSS Protocol - decode packets starting with 0x01.
    if (BSSPacket.isBSSPacket(data)) {
      final bss = BSSPacket.decode(data);
      if (bss != null) {
        return bss.toString();
      }
      // Fall through if decode fails.
    }

    final packet = AX25Packet.decode(fragment);
    if (packet == null) {
      return RadioUtils.bytesToHex(data);
    }

    final sb = StringBuffer();
    if (packet.addresses.length > 1) {
      sb.write('${packet.addresses[1]}>');
    }
    if (packet.addresses.isNotEmpty) {
      sb.write(packet.addresses[0].toString());
    }
    for (int i = 2; i < packet.addresses.length; i++) {
      final addr = packet.addresses[i];
      sb.write(',$addr${addr.crBit1 ? '*' : ''}');
    }

    if (sb.isNotEmpty) sb.write(': ');

    final isUFrame = (packet.type & FrameType.uFrame) == FrameType.uFrame;
    if (fragment.channelName == 'APRS' && isUFrame) {
      sb.write(packet.dataStr ?? '');
    } else if (isUFrame) {
      sb.write(packet.frameTypeName);
      final hex = packet.data != null
          ? RadioUtils.bytesToHex(packet.data!)
          : '';
      if (hex.isNotEmpty) sb.write(': $hex');
    } else {
      sb.write('${packet.frameTypeName}, NR:${packet.nr}, NS:${packet.ns}');
      final hex = packet.data != null
          ? RadioUtils.bytesToHex(packet.data!)
          : '';
      if (hex.isNotEmpty) sb.write(': $hex');
    }

    return sb.toString().replaceAll('\r', '').replaceAll('\n', '');
  }

  /// Builds the full set of decode detail sections for a fragment.
  static List<PacketDecodeSection> decode(TncDataFragment fragment) {
    final frame = PacketDecodeSection('Frame');
    final packetSection = PacketDecodeSection('Packet');
    final ax25 = PacketDecodeSection('AX.25');
    final payload = PacketDecodeSection('Payload');
    final bssSection = PacketDecodeSection('BSS');

    // Packet group.
    if (fragment.channelId >= 0) {
      packetSection.lines.add(
        MapEntry(
          'Channel',
          '${fragment.incoming ? 'Received' : 'Sent'} on ${fragment.channelId + 1}',
        ),
      );
    }
    packetSection.lines.add(MapEntry('Time', fragment.time.toString()));
    final len = fragment.data.length;
    packetSection.lines.add(MapEntry('Size', '$len byte${len > 1 ? 's' : ''}'));
    packetSection.lines.add(MapEntry('Data', _toAscii(fragment.data)));
    packetSection.lines.add(
      MapEntry('Data HEX', RadioUtils.bytesToHex(fragment.data)),
    );

    // Frame group (encoding).
    final encoding = _encodingString(fragment);
    if (encoding.isNotEmpty) {
      frame.lines.add(MapEntry('Encoding', encoding));
    }

    if (BSSPacket.isBSSPacket(fragment.data)) {
      _decodeBss(fragment.data, bssSection);
    } else {
      _decodeAx25(fragment, ax25, payload);
    }

    return [
      frame,
      packetSection,
      ax25,
      payload,
      bssSection,
    ].where((s) => !s.isEmpty).toList();
  }

  static void _decodeBss(Uint8List data, PacketDecodeSection bss) {
    final packet = BSSPacket.decode(data);
    if (packet == null) {
      bss.lines.add(
        const MapEntry('Decode', 'BSS Decoder failed to decode packet.'),
      );
      return;
    }

    if (packet.callsign != null && packet.callsign!.isNotEmpty) {
      bss.lines.add(MapEntry('Callsign', packet.callsign!));
    }
    if (packet.messageId != 0) {
      bss.lines.add(MapEntry('Message ID', packet.messageId.toString()));
    }
    if (packet.destination != null && packet.destination!.isNotEmpty) {
      bss.lines.add(MapEntry('Destination', packet.destination!));
    }
    if (packet.message != null && packet.message!.isNotEmpty) {
      bss.lines.add(MapEntry('Message', packet.message!));
    }
    if (packet.location != null) {
      bss.lines.add(
        MapEntry('Location HEX', RadioUtils.bytesToHex(packet.location!)),
      );
    }
    if (packet.locationRequest != null && packet.locationRequest!.isNotEmpty) {
      bss.lines.add(MapEntry('Location Request', packet.locationRequest!));
    }
    if (packet.callRequest != null && packet.callRequest!.isNotEmpty) {
      bss.lines.add(MapEntry('Call Request', packet.callRequest!));
    }

    // Display any unknown/future field types.
    for (final field in packet.rawFields.entries) {
      if (BSSPacket.isKnownField(field.key)) continue;
      final hexKey = field.key.toRadixString(16).padLeft(2, '0').toUpperCase();
      bss.lines.add(
        MapEntry('Field 0x$hexKey', RadioUtils.bytesToHex(field.value)),
      );
    }
  }

  static void _decodeAx25(
    TncDataFragment fragment,
    PacketDecodeSection ax25,
    PacketDecodeSection payload,
  ) {
    final packet = AX25Packet.decode(fragment);
    if (packet == null) {
      ax25.lines.add(
        const MapEntry('Decode', 'AX25 Decoder failed to decode packet.'),
      );
      return;
    }

    for (int i = 0; i < packet.addresses.length; i++) {
      final addr = packet.addresses[i];
      final sb = StringBuffer();
      sb.write(addr.callSignWithId);
      sb.write('  ');
      sb.write(addr.crBit1 ? 'X' : '-');
      sb.write(addr.crBit2 ? 'X' : '-');
      sb.write(addr.crBit3 ? 'X' : '-');
      ax25.lines.add(MapEntry('Address ${i + 1}', sb.toString()));
    }

    ax25.lines.add(MapEntry('Type', packet.frameTypeName));

    final control = StringBuffer();
    control.write('NS:${packet.ns}, NR:${packet.nr}');
    if (packet.command) control.write(', Command');
    if (packet.pollFinal) control.write(', PollFinal');
    if (packet.modulo128) control.write(', Modulo128');
    ax25.lines.add(MapEntry('Control', control.toString()));

    if (packet.pid > 0) {
      ax25.lines.add(MapEntry('Protocol ID', packet.pid.toString()));
    }

    if (packet.dataStr != null && packet.dataStr!.isNotEmpty) {
      payload.lines.add(MapEntry('Data', packet.dataStr!));
    }
    if (packet.data != null && packet.data!.isNotEmpty) {
      payload.lines.add(
        MapEntry('Data HEX', RadioUtils.bytesToHex(packet.data!)),
      );
    }
  }

  /// Human-readable DART level suffix, e.g. " Level 4 (16QAM, LDPC 3/4)".
  /// Returns '' when the fragment carries no DART mode.
  static String _dartLevelString(int mode) {
    switch (mode) {
      case 0:
        return ' Level 0 (BPSK, LDPC 1/2)';
      case 1:
        return ' Level 1 (QPSK, LDPC 1/2)';
      case 2:
        return ' Level 2 (QPSK, LDPC 2/3)';
      case 3:
        return ' Level 3 (8PSK, LDPC 2/3)';
      case 4:
        return ' Level 4 (16QAM, LDPC 3/4)';
      case 5:
        return ' Level 5 (16QAM, LDPC 5/6)';
      case 6:
        return ' Level F (4-FSK, LDPC 1/2)';
      default:
        return '';
    }
  }

  static String _encodingString(TncDataFragment fragment) {
    String encoding = '';
    switch (fragment.encoding) {
      case FragmentEncodingType.loopback:
        encoding = 'Loopback';
        break;
      case FragmentEncodingType.hardwareAfsk1200:
        encoding = 'Hardware AFSK 1200 baud';
        break;
      case FragmentEncodingType.softwareAfsk1200:
        encoding = 'Software AFSK 1200 baud';
        break;
      case FragmentEncodingType.softwarePsk2400:
        encoding = 'Software PSK 2400 baud';
        break;
      case FragmentEncodingType.softwareDart:
        encoding = 'Software DART${_dartLevelString(fragment.dartMode)}';
        break;
      case FragmentEncodingType.unknown:
        return '';
    }

    if (fragment.frameType == FragmentFrameType.ax25) encoding += ', AX.25';
    if (fragment.frameType == FragmentFrameType.fx25) encoding += ', FX.25';
    if (fragment.corrections == 0) {
      encoding += ', No Corrections';
    } else if (fragment.corrections == 1) {
      encoding += ', 1 Correction';
    } else if (fragment.corrections > 1) {
      encoding += ', ${fragment.corrections} Corrections';
    }
    return encoding;
  }

  /// Converts raw bytes to a printable ASCII string (non-printable bytes shown
  /// as '.').
  static String _toAscii(Uint8List data) {
    return String.fromCharCodes(data.map((b) => (b >= 32 && b < 127) ? b : 46));
  }
}
