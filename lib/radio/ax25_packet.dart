/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';
import 'dart:convert';
import 'ax25_address.dart';
import 'tnc_data_fragment.dart';

/// Authentication state for packets
enum AuthState { unknown, failed, success, none }

/// AX.25 frame types
class FrameType {
  static const int iFrame = 0;
  static const int iFrameMask = 1;
  static const int sFrame = 1;
  static const int sFrameRr = 1; // Receive Ready
  static const int sFrameRnr = 1 | (1 << 2); // Receive Not Ready
  static const int sFrameRej = 1 | (1 << 3); // Reject
  static const int sFrameSrej = 1 | (1 << 2) | (1 << 3); // Selective Reject
  static const int sFrameMask = 1 | (1 << 2) | (1 << 3);
  static const int uFrame = 3;
  static const int uFrameSabm =
      3 | (1 << 2) | (1 << 3) | (1 << 5); // Set Async Balanced Mode
  static const int uFrameSabme =
      3 | (1 << 3) | (1 << 5) | (1 << 6); // SABM Extended
  static const int uFrameDisc = 3 | (1 << 6); // Disconnect
  static const int uFrameDm = 3 | (1 << 2) | (1 << 3); // Disconnected Mode
  static const int uFrameUa = 3 | (1 << 5) | (1 << 6); // Acknowledge
  static const int uFrameFrmr = 3 | (1 << 2) | (1 << 7); // Frame Reject
  static const int uFrameUi = 3; // UI (Information)
  static const int uFrameXid =
      3 | (1 << 2) | (1 << 3) | (1 << 5) | (1 << 7); // Exchange ID
  static const int uFrameTest = 3 | (1 << 5) | (1 << 6) | (1 << 7); // Test
  static const int uFrameMask =
      3 | (1 << 2) | (1 << 3) | (1 << 5) | (1 << 6) | (1 << 7);
}

/// AX.25 protocol definitions
class AX25Defs {
  static const int pf = 1 << 4; // Poll/Final
  static const int ns = (1 << 1) | (1 << 2) | (1 << 3); // N(S)
  static const int nr = (1 << 5) | (1 << 6) | (1 << 7); // N(R)
  static const int pfModulo128 = 1 << 8;
  static const int nsModulo128 = 127 << 1;
  static const int nrModulo128 = 127 << 9;
  static const int pidNone =
      (1 << 4) | (1 << 5) | (1 << 6) | (1 << 7); // No L3 protocol
}

/// AX.25 Packet - represents a complete AX.25 frame
class AX25Packet {
  DateTime time;
  bool confirmed = false;
  int messageId = 0;
  int channelId = -1;
  String channelName = '';
  int frameSize = 0;
  bool incoming = false;
  bool sent = false;
  AuthState authState = AuthState.unknown;

  // Content of the packet
  List<AX25Address> addresses;
  bool pollFinal = false;
  bool command = false;
  int type;
  int nr = 0; // Receive sequence number (0-7 or 0-127 for modulo128)
  int ns = 0; // Send sequence number
  int pid = 240; // Protocol ID (default: no L3 protocol)
  bool modulo128 = false;
  String? dataStr;
  Uint8List? data;

  // Tag and deadline for transmission control
  String? tag;
  DateTime deadline = DateTime.fromMillisecondsSinceEpoch(0x7FFFFFFFFFFFF);

  AX25Packet({
    required this.addresses,
    this.nr = 0,
    this.ns = 0,
    this.pollFinal = false,
    this.command = false,
    this.type = FrameType.uFrameUi,
    this.data,
    this.dataStr,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  /// Create a UI packet with addresses and data string
  factory AX25Packet.ui(
    List<AX25Address> addresses,
    String dataStr, [
    DateTime? time,
  ]) {
    return AX25Packet(
      addresses: addresses,
      dataStr: dataStr,
      type: FrameType.uFrameUi,
      time: time,
    );
  }

  /// Create a UI packet with addresses and binary data
  factory AX25Packet.uiBytes(
    List<AX25Address> addresses,
    Uint8List data, [
    DateTime? time,
  ]) {
    return AX25Packet(
      addresses: addresses,
      data: data,
      type: FrameType.uFrameUi,
      time: time,
    );
  }

  /// Check if two packets are the same (for deduplication)
  bool isSame(AX25Packet p) {
    if (p.dataStr != dataStr) return false;
    if (addresses.length < 2 || p.addresses.length < 2) return false;
    for (int i = 0; i < 2; i++) {
      if (!p.addresses[i].isSame(addresses[i])) return false;
    }
    if (p.pollFinal != pollFinal) return false;
    if (p.command != command) return false;
    if (p.nr != nr) return false;
    if (p.ns != ns) return false;
    if (p.pid != pid) return false;
    if (p.modulo128 != modulo128) return false;
    return true;
  }

  /// Decode an AX.25 packet from a TNC data fragment
  static AX25Packet? decode(TncDataFragment frame) {
    final data = frame.data;
    if (data.length < 6) return null;

    // Decode the addresses
    int i = 0;
    bool done = false;
    final addresses = <AX25Address>[];

    while (!done) {
      final result = AX25Address.decodeAX25Address(data, i);
      if (result.address == null) return null;
      addresses.add(result.address!);
      done = result.last;
      i += 7;
    }

    if (addresses.isEmpty) return null;
    final command = addresses[0].crBit1;
    final modulo128 = !addresses[0].crBit2;
    if (data.length < (i + 1)) return null;

    // Decode control and pid
    int control = data[i++];
    bool pollFinal = false;
    int frameType;
    int pid = 0;
    int nr = 0;
    int ns = 0;

    if ((control & FrameType.uFrame) == FrameType.uFrame) {
      // U-frame
      pollFinal = ((control & AX25Defs.pf) >> 4) != 0;
      frameType = control & FrameType.uFrameMask;
      if (frameType == FrameType.uFrameUi) {
        pid = data[i++];
      }
    } else if ((control & FrameType.uFrame) == FrameType.sFrame) {
      // S-frame
      frameType = control & FrameType.sFrameMask;
      if (modulo128) {
        control |= (data[i++] << 8);
        nr = (control & AX25Defs.nrModulo128) >> 8;
        pollFinal = ((control & AX25Defs.pf) >> 7) != 0;
      } else {
        nr = (control & AX25Defs.nr) >> 5;
        pollFinal = ((control & AX25Defs.pf) >> 4) != 0;
      }
    } else if ((control & 1) == FrameType.iFrame) {
      // I-frame
      frameType = FrameType.iFrame;
      if (modulo128) {
        control |= (data[i++] << 8);
        nr = (control & AX25Defs.nrModulo128) >> 8;
        ns = (control & AX25Defs.nsModulo128) >> 1;
        pollFinal = ((control & AX25Defs.pf) >> 7) != 0;
      } else {
        nr = (control & AX25Defs.nr) >> 5;
        ns = (control & AX25Defs.ns) >> 1;
        pollFinal = ((control & AX25Defs.pf) >> 4) != 0;
      }
      pid = data[i++];
    } else {
      return null;
    }

    String? xdataStr;
    Uint8List? xdata;
    if (data.length > i) {
      xdataStr = utf8.decode(data.sublist(i), allowMalformed: true);
      xdata = Uint8List.fromList(data.sublist(i));
    }

    final packet = AX25Packet(
      addresses: addresses,
      dataStr: xdataStr,
      time: frame.time,
    );
    packet.data = xdata;
    packet.command = command;
    packet.modulo128 = modulo128;
    packet.pollFinal = pollFinal;
    packet.type = frameType;
    packet.pid = pid;
    packet.nr = nr;
    packet.ns = ns;
    packet.channelId = frame.channelId;
    packet.channelName = frame.channelName;
    packet.incoming = frame.incoming;
    packet.frameSize = data.length;

    return packet;
  }

  int _getControl() {
    int control = type;
    if (type == FrameType.iFrame ||
        (type & FrameType.uFrame) == FrameType.sFrame) {
      control |= (nr << (modulo128 ? 9 : 5));
    }
    if (type == FrameType.iFrame) {
      control |= (ns << 1);
    }
    if (pollFinal) {
      control |= (1 << (modulo128 ? 8 : 4));
    }
    return control;
  }

  /// Encode this packet to bytes for transmission
  Uint8List toByteArray() {
    if (addresses.isEmpty) return Uint8List(0);

    Uint8List? dataBytes;
    int dataBytesLen = 0;
    if (data != null) {
      dataBytes = data;
      dataBytesLen = data!.length;
    } else if (dataStr != null && dataStr!.isNotEmpty) {
      dataBytes = Uint8List.fromList(utf8.encode(dataStr!));
      dataBytesLen = dataBytes.length;
    }

    // Compute packet size
    int packetSize =
        (7 * addresses.length) + (modulo128 ? 2 : 1) + dataBytesLen;
    if (type == FrameType.iFrame || type == FrameType.uFrameUi) {
      packetSize++; // PID
    }

    final rdata = Uint8List(packetSize);
    final control = _getControl();

    // Put the addresses
    int i = 0;
    for (int j = 0; j < addresses.length; j++) {
      final a = addresses[j];
      a.crBit1 = false;
      a.crBit2 = true;
      a.crBit3 = true;
      if (j == 0) a.crBit1 = command;
      if (j == 1) {
        a.crBit1 = !command;
        a.crBit2 = !modulo128;
      }
      final ab = a.toByteArray(j == addresses.length - 1);
      for (int k = 0; k < 7; k++) {
        rdata[i + k] = ab[k];
      }
      i += 7;
    }

    // Put the control
    rdata[i++] = control & 0xFF;
    if (modulo128) rdata[i++] = control >> 8;

    // Put the PID if needed
    if (type == FrameType.iFrame || type == FrameType.uFrameUi) {
      rdata[i++] = pid;
    }

    // Put the data
    if (dataBytesLen > 0 && dataBytes != null) {
      for (int k = 0; k < dataBytes.length; k++) {
        rdata[i + k] = dataBytes[k];
      }
    }

    return rdata;
  }

  @override
  String toString() {
    final buf = StringBuffer();
    for (final a in addresses) {
      buf.write('[${a.toString()}]');
    }
    if (data != null) {
      buf.write(': ${utf8.decode(data!, allowMalformed: true)}');
    } else if (dataStr != null) {
      buf.write(': $dataStr');
    }
    return buf.toString();
  }

  /// Get the source address (second address in the list)
  AX25Address? get source => addresses.length > 1 ? addresses[1] : null;

  /// Get the destination address (first address in the list)
  AX25Address? get destination => addresses.isNotEmpty ? addresses[0] : null;

  /// Get the digipeater path (addresses after the first two)
  List<AX25Address> get path =>
      addresses.length > 2 ? addresses.sublist(2) : [];

  /// Get the frame type as a readable string
  String get frameTypeName {
    switch (type) {
      case FrameType.iFrame:
        return 'I-FRAME';
      case FrameType.sFrameRr:
        return 'S-FRAME-RR';
      case FrameType.sFrameRnr:
        return 'S-FRAME-RNR';
      case FrameType.sFrameRej:
        return 'S-FRAME-REJ';
      case FrameType.sFrameSrej:
        return 'S-FRAME-SREJ';
      case FrameType.uFrameSabm:
        return 'U-FRAME-SABM';
      case FrameType.uFrameSabme:
        return 'U-FRAME-SABME';
      case FrameType.uFrameDisc:
        return 'U-FRAME-DISC';
      case FrameType.uFrameDm:
        return 'U-FRAME-DM';
      case FrameType.uFrameUa:
        return 'U-FRAME-UA';
      case FrameType.uFrameFrmr:
        return 'U-FRAME-FRMR';
      case FrameType.uFrameUi:
        return 'U-FRAME-UI';
      case FrameType.uFrameXid:
        return 'U-FRAME-XID';
      case FrameType.uFrameTest:
        return 'U-FRAME-TEST';
      default:
        return 'UNKNOWN';
    }
  }
}
