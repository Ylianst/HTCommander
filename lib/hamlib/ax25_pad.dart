/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// ax25_pad.dart - AX.25 packet assembler and disassembler
//
// Ported from C# HamLib/Ax25Pad.cs
//

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'fcs_calc.dart';

// =============================================================================
// Constants and Enums
// =============================================================================

class Ax25Constants {
  Ax25Constants._();

  static const int maxRepeaters = 8;
  static const int minAddrs = 2; // Destination & Source
  static const int maxAddrs = 10; // Destination, Source, 8 digipeaters

  static const int destination = 0;
  static const int source = 1;
  static const int repeater1 = 2;
  static const int repeater2 = 3;
  static const int repeater3 = 4;
  static const int repeater4 = 5;
  static const int repeater5 = 6;
  static const int repeater6 = 7;
  static const int repeater7 = 8;
  static const int repeater8 = 9;

  static const int maxAddrLen = 12;
  static const int minInfoLen = 0;
  static const int maxInfoLen = 2048;

  static const int minPacketLen = 2 * 7 + 1;
  static const int maxPacketLen = maxAddrs * 7 + 2 + 3 + maxInfoLen;

  static const int uiFrame = 0x03;
  static const int pidNoLayer3 = 0xF0;
  static const int pidNetrom = 0xCF;
  static const int pidSegmentationFragment = 0x08;
  static const int pidEscapeCharacter = 0xFF;

  // SSID bit masks
  static const int ssidHMask = 0x80;
  static const int ssidHShift = 7;
  static const int ssidRrMask = 0x60;
  static const int ssidRrShift = 5;
  static const int ssidSsidMask = 0x1E;
  static const int ssidSsidShift = 1;
  static const int ssidLastMask = 0x01;

  static const int alevelToTextSize = 40;
}

/// AX.25 frame types. (Underscores follow the original C# naming.)
enum Ax25FrameType {
  i, // Information
  sRr, // Receive Ready
  sRnr, // Receive Not Ready
  sRej, // Reject Frame
  sSrej, // Selective Reject
  uSabme, // Set Async Balanced Mode, Extended
  uSabm, // Set Async Balanced Mode
  uDisc, // Disconnect
  uDm, // Disconnect Mode
  uUa, // Unnumbered Acknowledge
  uFrmr, // Frame Reject
  uUi, // Unnumbered Information
  uXid, // Exchange Identification
  uTest, // Test
  u, // Other Unnumbered
  notAX25, // Could not get control byte
}

/// Command/response. Modeled as int constants because the original C# enum is
/// cast to/from int.
class CmdRes {
  CmdRes._();
  static const int res = 0;
  static const int cmd = 1;
  static const int cr00 = 2;
  static const int cr11 = 3;
}

/// AX.25 modulo. Int constants because the original C# enum is cast from int.
class Ax25Modulo {
  Ax25Modulo._();
  static const int unknown = 0;
  static const int modulo8 = 8;
  static const int modulo128 = 128;
}

// =============================================================================
// Audio Level Structure
// =============================================================================

class ALevel {
  int rec;
  int mark;
  int space;

  ALevel([this.rec = -1, this.mark = -1, this.space = -1]);
}

/// Result of [Packet.getFrameType].
class Ax25FrameInfo {
  Ax25FrameType type = Ax25FrameType.notAX25;
  int cr = CmdRes.cr11;
  String desc = '????';
  int pf = -1;
  int nr = -1;
  int ns = -1;
}

/// Result of [Packet.parseAddr].
class ParsedAddr {
  bool ok;
  String addr;
  int ssid;
  bool heard;
  ParsedAddr(this.ok, this.addr, this.ssid, this.heard);
}

// =============================================================================
// Character helpers (mirror System.Char behavior used by the original)
// =============================================================================

bool _isLetterOrDigit(int ch) =>
    (ch >= 0x30 && ch <= 0x39) ||
    (ch >= 0x41 && ch <= 0x5A) ||
    (ch >= 0x61 && ch <= 0x7A);

bool _isDigit(int ch) => ch >= 0x30 && ch <= 0x39;

bool _isLower(int ch) => ch >= 0x61 && ch <= 0x7A;

int _toUpper(int ch) => (ch >= 0x61 && ch <= 0x7A) ? ch - 0x20 : ch;

Uint8List _asciiBytes(String s) {
  final Uint8List b = Uint8List(s.length);
  for (int i = 0; i < s.length; i++) {
    b[i] = s.codeUnitAt(i) & 0xFF;
  }
  return b;
}

String _trimEndSpaces(String s) {
  int end = s.length;
  while (end > 0 && s.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return s.substring(0, end);
}

/// memmove-style copy that tolerates overlapping source/destination.
void _copy(List<int> src, int srcOff, List<int> dst, int dstOff, int len) {
  if (len <= 0) return;
  final List<int> tmp = src.sublist(srcOff, srcOff + len);
  dst.setRange(dstOff, dstOff + len, tmp);
}

// =============================================================================
// Packet Class
// =============================================================================

/// Represents an AX.25 packet.
class Packet {
  int _seq = 0;
  double releaseTime = 0;
  Packet? nextP;
  int numAddr = -1;
  int frameLen = 0;
  int modulo = Ax25Modulo.unknown;
  late Uint8List frameData;

  static int _lastSeqNum = 0;

  int get seq => _seq;

  Packet() {
    _lastSeqNum++;
    _seq = _lastSeqNum;
    frameData = Uint8List(Ax25Constants.maxPacketLen + 1);
    numAddr = -1;
    frameLen = 0;
    modulo = Ax25Modulo.unknown;
  }

  /// Create a new packet from text monitor format.
  static Packet? fromText(String monitor, bool strict) {
    if (monitor.isEmpty) return null;

    final Packet packet = Packet();

    // Initialize with two addresses and control/pid for APRS
    for (int i = 0; i < 6; i++) {
      packet.frameData[Ax25Constants.destination * 7 + i] = (0x20 << 1) & 0xFF;
      packet.frameData[Ax25Constants.source * 7 + i] = (0x20 << 1) & 0xFF;
    }
    packet.frameData[Ax25Constants.destination * 7 + 6] =
        (Ax25Constants.ssidHMask | Ax25Constants.ssidRrMask) & 0xFF;
    packet.frameData[Ax25Constants.source * 7 + 6] =
        (Ax25Constants.ssidRrMask | Ax25Constants.ssidLastMask) & 0xFF;

    packet.frameData[14] = Ax25Constants.uiFrame;
    packet.frameData[15] = Ax25Constants.pidNoLayer3;

    packet.frameLen = 7 + 7 + 1 + 1;
    packet.numAddr = -1;
    packet.getNumAddr(); // Sets numAddr properly

    // Separate the addresses from the rest
    final int colonPos = monitor.indexOf(':');
    if (colonPos < 0) return null;

    final String addrPart = monitor.substring(0, colonPos);
    final String infoPart = monitor.substring(colonPos + 1);

    // Parse source address
    final int gtPos = addrPart.indexOf('>');
    if (gtPos < 0) {
      print('Failed to create packet from text. No source address');
      return null;
    }

    final String srcAddr = addrPart.substring(0, gtPos);
    ParsedAddr p =
        parseAddr(Ax25Constants.source, srcAddr, strict);
    if (!p.ok) {
      print('Failed to create packet from text. Bad source address');
      return null;
    }

    packet.setAddr(Ax25Constants.source, p.addr);
    packet.setH(Ax25Constants.source);
    packet.setSsid(Ax25Constants.source, p.ssid);

    // Parse destination and digipeaters
    final List<String> parts = addrPart.substring(gtPos + 1).split(',');
    if (parts.isEmpty) {
      print('Failed to create packet from text. No destination address');
      return null;
    }

    // Destination
    p = parseAddr(Ax25Constants.destination, parts[0], strict);
    if (!p.ok) {
      print('Failed to create packet from text. Bad destination address');
      return null;
    }

    packet.setAddr(Ax25Constants.destination, p.addr);
    packet.setH(Ax25Constants.destination);
    packet.setSsid(Ax25Constants.destination, p.ssid);

    // Digipeaters
    for (int i = 1;
        i < parts.length && packet.numAddr < Ax25Constants.maxAddrs;
        i++) {
      final int k = packet.numAddr;
      String digiAddr = parts[i];

      // Hack for q construct from APRS-IS
      if (!strict &&
          digiAddr.length >= 2 &&
          digiAddr.codeUnitAt(0) == 0x71 /* q */ &&
          digiAddr.codeUnitAt(1) == 0x41 /* A */) {
        digiAddr =
            'Q${digiAddr.substring(1, 2)}${String.fromCharCode(_toUpper(digiAddr.codeUnitAt(2)))}${digiAddr.substring(3)}';
      }

      final ParsedAddr pd = parseAddr(k, digiAddr, strict);
      if (!pd.ok) {
        print('Failed to create packet from text. Bad digipeater address');
        return null;
      }

      packet.setAddr(k, pd.addr);
      packet.setSsid(k, pd.ssid);

      if (pd.heard) {
        for (int j = k; j >= Ax25Constants.repeater1; j--) {
          packet.setH(j);
        }
      }
    }

    // Process information part - translate <0xNN> to bytes
    final Uint8List infoBytes = Uint8List(Ax25Constants.maxInfoLen);
    int infoLen = 0;
    int idx = 0;

    while (idx < infoPart.length && infoLen < Ax25Constants.maxInfoLen) {
      if (idx + 5 < infoPart.length &&
          infoPart[idx] == '<' &&
          infoPart[idx + 1] == '0' &&
          infoPart[idx + 2] == 'x' &&
          infoPart[idx + 5] == '>') {
        final String hexStr = infoPart.substring(idx + 3, idx + 5);
        final int? b = int.tryParse(hexStr, radix: 16);
        if (b != null) {
          infoBytes[infoLen++] = b & 0xFF;
          idx += 6;
          continue;
        }
      }

      infoBytes[infoLen++] = infoPart.codeUnitAt(idx) & 0xFF;
      idx++;
    }

    // Append info part
    _copy(infoBytes, 0, packet.frameData, packet.frameLen, infoLen);
    packet.frameLen += infoLen;

    return packet;
  }

  /// Create a packet from frame data.
  static Packet? fromFrame(Uint8List fbuf, int flen, ALevel alevel) {
    if (flen < Ax25Constants.minPacketLen ||
        flen > Ax25Constants.maxPacketLen) {
      print(
          'Frame length $flen not in allowable range of ${Ax25Constants.minPacketLen} to ${Ax25Constants.maxPacketLen}.');
      return null;
    }

    final Packet packet = Packet();
    _copy(fbuf, 0, packet.frameData, 0, flen);
    packet.frameData[flen] = 0;
    packet.frameLen = flen;

    packet.numAddr = -1;
    packet.getNumAddr();

    return packet;
  }

  /// Duplicate a packet.
  Packet dup() {
    final Packet newPacket = Packet();
    _copy(frameData, 0, newPacket.frameData, 0, frameData.length);
    newPacket.frameLen = frameLen;
    newPacket.numAddr = numAddr;
    newPacket.modulo = modulo;
    newPacket.releaseTime = releaseTime;
    return newPacket;
  }

  /// Parse an address with optional SSID.
  static ParsedAddr parseAddr(int position, String inAddr, bool strict) {
    String outAddr = '';
    int outSsid = 0;
    bool outHeard = false;

    if (inAddr.isEmpty) {
      print('Address "$inAddr" is empty.');
      return ParsedAddr(false, outAddr, outSsid, outHeard);
    }

    // Check for q-construct in strict mode
    if (strict && inAddr.length >= 2 && inAddr.substring(0, 2) == 'qA') {
      print('Address "$inAddr" is a "q-construct" used for communicating with');
      print(
          'APRS Internet Servers. It should never appear when going over the radio.');
    }

    final int maxLen = strict ? 6 : (Ax25Constants.maxAddrLen - 1);
    final StringBuffer addr = StringBuffer();

    int i = 0;
    while (i < inAddr.length &&
        inAddr[i] != '-' &&
        inAddr[i] != '*') {
      if (addr.length >= maxLen) {
        print(
            'Address is too long. "$inAddr" has more than $maxLen characters.');
        return ParsedAddr(false, outAddr, outSsid, outHeard);
      }

      final int ch = inAddr.codeUnitAt(i);
      if (!_isLetterOrDigit(ch)) {
        print(
            'Address, "$inAddr" contains character other than letter or digit in character position ${i + 1}.');
        return ParsedAddr(false, outAddr, outSsid, outHeard);
      }

      if (strict && _isLower(ch) && !inAddr.startsWith('qA')) {
        print(
            'Address has lower case letters. "$inAddr" must be all upper case.');
        return ParsedAddr(false, outAddr, outSsid, outHeard);
      }

      addr.writeCharCode(ch);
      i++;
    }

    outAddr = addr.toString();

    // Parse SSID
    if (i < inAddr.length && inAddr[i] == '-') {
      i++;
      final StringBuffer ssidStr = StringBuffer();

      while (i < inAddr.length && _isLetterOrDigit(inAddr.codeUnitAt(i))) {
        if (ssidStr.length >= 2) {
          print(
              'SSID is too long. SSID part of "$inAddr" has more than 2 characters.');
          return ParsedAddr(false, outAddr, outSsid, outHeard);
        }

        if (strict && !_isDigit(inAddr.codeUnitAt(i))) {
          print('SSID must be digits. "$inAddr" has letters in SSID.');
          return ParsedAddr(false, outAddr, outSsid, outHeard);
        }

        ssidStr.writeCharCode(inAddr.codeUnitAt(i));
        i++;
      }

      final int? ssid = int.tryParse(ssidStr.toString());
      if (ssid != null) {
        if (ssid < 0 || ssid > 15) {
          print('SSID out of range. SSID of "$inAddr" not in range of 0 to 15.');
          return ParsedAddr(false, outAddr, outSsid, outHeard);
        }
        outSsid = ssid;
      }
    }

    // Check for asterisk
    if (i < inAddr.length && inAddr[i] == '*') {
      outHeard = true;
      i++;

      if (strict == true) {
        print('"*" is not allowed at end of address "$inAddr" here.');
        return ParsedAddr(false, outAddr, outSsid, outHeard);
      }
    }

    // Should be at end
    if (i < inAddr.length) {
      print('Invalid character "${inAddr[i]}" found in address "$inAddr".');
      return ParsedAddr(false, outAddr, outSsid, outHeard);
    }

    return ParsedAddr(true, outAddr, outSsid, outHeard);
  }

  /// Get number of addresses in packet.
  int getNumAddr() {
    if (numAddr >= 0) return numAddr;

    numAddr = 0;
    int addrBytes = 0;

    for (int a = 0; a < frameLen && addrBytes == 0; a++) {
      if ((frameData[a] & Ax25Constants.ssidLastMask) != 0) {
        addrBytes = a + 1;
      }
    }

    if (addrBytes % 7 == 0) {
      final int addrs = addrBytes ~/ 7;
      if (addrs >= Ax25Constants.minAddrs && addrs <= Ax25Constants.maxAddrs) {
        numAddr = addrs;
      }
    }

    return numAddr;
  }

  /// Get number of repeater addresses.
  int getNumRepeaters() {
    if (numAddr >= 2) return numAddr - 2;
    return 0;
  }

  /// Get address with SSID.
  String getAddrWithSsid(int n) {
    if (n < 0 || n >= numAddr) {
      print('Internal error: GetAddrWithSsid($n), num_addr=$numAddr');
      return '??????';
    }

    final StringBuffer station = StringBuffer();
    for (int i = 0; i < 6; i++) {
      station.writeCharCode((frameData[n * 7 + i] >> 1) & 0x7F);
    }

    String result = _trimEndSpaces(station.toString());

    if (result.isEmpty) {
      print(
          'Station address, in position $n, is empty! This is not a valid AX.25 frame.');
    }

    final int ssid = getSsid(n);
    if (ssid != 0) {
      result += '-$ssid';
    }

    return result;
  }

  /// Get address without SSID.
  String getAddrNoSsid(int n) {
    if (n < 0 || n >= numAddr) {
      print('Internal error: GetAddrNoSsid($n), num_addr=$numAddr');
      return '??????';
    }

    final StringBuffer station = StringBuffer();
    for (int i = 0; i < 6; i++) {
      station.writeCharCode((frameData[n * 7 + i] >> 1) & 0x7F);
    }

    final String result = _trimEndSpaces(station.toString());

    if (result.isEmpty) {
      print(
          'Station address, in position $n, is empty! This is not a valid AX.25 frame.');
    }

    return result;
  }

  /// Get SSID of address.
  int getSsid(int n) {
    if (n >= 0 && n < numAddr) {
      return (frameData[n * 7 + 6] & Ax25Constants.ssidSsidMask) >>
          Ax25Constants.ssidSsidShift;
    }

    print('Internal error: GetSsid($n), num_addr=$numAddr');
    return 0;
  }

  /// Set SSID of address.
  void setSsid(int n, int ssid) {
    if (n >= 0 && n < numAddr) {
      frameData[n * 7 + 6] = ((frameData[n * 7 + 6] &
                  ~Ax25Constants.ssidSsidMask) |
              ((ssid << Ax25Constants.ssidSsidShift) &
                  Ax25Constants.ssidSsidMask)) &
          0xFF;
    } else {
      print('Internal error: SetSsid($n,$ssid), num_addr=$numAddr');
    }
  }

  /// Get "has been repeated" flag.
  bool getH(int n) {
    if (n >= 0 && n < numAddr) {
      return ((frameData[n * 7 + 6] & Ax25Constants.ssidHMask) >>
              Ax25Constants.ssidHShift) !=
          0;
    }

    print('Internal error: GetH($n), num_addr=$numAddr');
    return false;
  }

  /// Set "has been repeated" flag.
  void setH(int n) {
    if (n >= 0 && n < numAddr) {
      frameData[n * 7 + 6] =
          (frameData[n * 7 + 6] | Ax25Constants.ssidHMask) & 0xFF;
    } else {
      print('Internal error: SetH($n), num_addr=$numAddr');
    }
  }

  /// Get index of station we heard.
  int getHeard() {
    int result = Ax25Constants.source;
    for (int i = Ax25Constants.repeater1; i < getNumAddr(); i++) {
      if (getH(i)) {
        result = i;
      }
    }
    return result;
  }

  /// Get first repeater that has not been repeated.
  int getFirstNotRepeated() {
    for (int i = Ax25Constants.repeater1; i < getNumAddr(); i++) {
      if (!getH(i)) {
        return i;
      }
    }
    return -1;
  }

  /// Get RR bits.
  int getRr(int n) {
    if (n >= 0 && n < numAddr) {
      return (frameData[n * 7 + 6] & Ax25Constants.ssidRrMask) >>
          Ax25Constants.ssidRrShift;
    }

    print('Internal error: GetRr($n), num_addr=$numAddr');
    return 0;
  }

  /// Set address.
  void setAddr(int n, String ad) {
    if (ad.isEmpty) {
      print('Set address error! Station address for position $n is empty!');
      return;
    }

    if (n >= 0 && n < numAddr) {
      // Set existing address
      final ParsedAddr p = parseAddr(n, ad, false);
      if (!p.ok) return;

      for (int i = 0; i < 6; i++) {
        frameData[n * 7 + i] = (0x20 << 1) & 0xFF;
      }

      for (int i = 0; i < p.addr.length && i < 6; i++) {
        frameData[n * 7 + i] = (p.addr.codeUnitAt(i) << 1) & 0xFF;
      }

      setSsid(n, p.ssid);
    } else if (n == numAddr) {
      // Append new address
      insertAddr(n, ad);
    } else {
      print("Internal error, SetAddr, bad position $n for '$ad'");
    }
  }

  /// Insert address at position.
  void insertAddr(int n, String ad) {
    if (ad.isEmpty) {
      print('Set address error! Station address for position $n is empty!');
      return;
    }

    if (numAddr >= Ax25Constants.maxAddrs) return;
    if (n < Ax25Constants.repeater1 || n >= Ax25Constants.maxAddrs) return;

    // Clear last address flag
    frameData[numAddr * 7 - 1] =
        frameData[numAddr * 7 - 1] & (~Ax25Constants.ssidLastMask & 0xFF);

    numAddr++;

    // Shift addresses
    _copy(frameData, n * 7, frameData, (n + 1) * 7, frameLen - (n * 7));
    for (int i = 0; i < 6; i++) {
      frameData[n * 7 + i] = (0x20 << 1) & 0xFF;
    }
    frameData[n * 7 + 6] = Ax25Constants.ssidRrMask;
    frameLen += 7;

    // Set last address flag
    frameData[numAddr * 7 - 1] =
        (frameData[numAddr * 7 - 1] | Ax25Constants.ssidLastMask) & 0xFF;

    // Parse and set address
    final ParsedAddr p = parseAddr(n, ad, false);
    if (!p.ok) return;

    for (int i = 0; i < p.addr.length && i < 6; i++) {
      frameData[n * 7 + i] = (p.addr.codeUnitAt(i) << 1) & 0xFF;
    }

    setSsid(n, p.ssid);
  }

  /// Remove address at position.
  void removeAddr(int n) {
    if (n < Ax25Constants.repeater1 || n >= Ax25Constants.maxAddrs) return;

    // Clear last address flag
    frameData[numAddr * 7 - 1] =
        frameData[numAddr * 7 - 1] & (~Ax25Constants.ssidLastMask & 0xFF);

    numAddr--;

    // Shift addresses down
    _copy(frameData, (n + 1) * 7, frameData, n * 7, frameLen - ((n + 1) * 7));
    frameLen -= 7;

    // Set last address flag
    frameData[numAddr * 7 - 1] =
        (frameData[numAddr * 7 - 1] | Ax25Constants.ssidLastMask) & 0xFF;
  }

  /// Get information field.
  Uint8List getInfo() {
    if (numAddr >= 2) {
      final int offset = _getInfoOffset();
      final int length = _getNumInfo();
      final Uint8List info = Uint8List(length);
      _copy(frameData, offset, info, 0, length);
      return info;
    }

    // Not AX.25, treat whole packet as info
    final int length = frameLen;
    final Uint8List allInfo = Uint8List(length);
    _copy(frameData, 0, allInfo, 0, length);
    return allInfo;
  }

  /// Set information field.
  void setInfo(Uint8List newInfo, int newInfoLen) {
    final Uint8List oldInfo = getInfo();
    frameLen -= oldInfo.length;

    if (newInfoLen < 0) newInfoLen = 0;
    if (newInfoLen > Ax25Constants.maxInfoLen) {
      newInfoLen = Ax25Constants.maxInfoLen;
    }

    final int offset = _getInfoOffset();
    _copy(newInfo, 0, frameData, offset, newInfoLen);
    frameLen += newInfoLen;
  }

  /// Truncate info at first CR or LF.
  int cutAtCrlf() {
    final Uint8List info = getInfo();
    final int infoLen = info.length;

    for (int j = 0; j < infoLen; j++) {
      if (info[j] == 0x0D || info[j] == 0x0A) {
        final int chop = infoLen - j;
        frameLen -= chop;
        return chop;
      }
    }

    return 0;
  }

  /// Get data type identifier.
  int getDti() {
    if (numAddr >= 2) {
      return frameData[_getInfoOffset()];
    }
    return 0x20; // ' '
  }

  /// Get control byte.
  int getControl() {
    if (frameLen == 0) return -1;
    if (numAddr >= 2) {
      return frameData[_getControlOffset()];
    }
    return -1;
  }

  /// Get second control byte.
  int getC2() {
    if (frameLen == 0) return -1;
    if (numAddr >= 2) {
      final int offset2 = _getControlOffset() + 1;
      if (offset2 < frameLen) {
        return frameData[offset2];
      }
    }
    return -1;
  }

  /// Get protocol ID.
  int getPid() {
    if (frameLen == 0) return -1;
    if (numAddr >= 2) {
      return frameData[_getPidOffset()];
    }
    return -1;
  }

  /// Set protocol ID.
  void setPid(int pid) {
    if (pid == 0) pid = Ax25Constants.pidNoLayer3;
    if (frameLen == 0) return;

    // Check if it's I or UI frame
    final Ax25FrameInfo info = getFrameType();
    if (info.type != Ax25FrameType.i && info.type != Ax25FrameType.uUi) {
      print('SetPid(0x${pid.toRadixString(16)}): Packet type is not I or UI.');
      return;
    }

    if (numAddr >= 2) {
      frameData[_getPidOffset()] = pid & 0xFF;
    }
  }

  /// Format all addresses for display.
  String formatAddrs() {
    if (numAddr == 0) return '';

    final StringBuffer result = StringBuffer();
    result.write(getAddrWithSsid(Ax25Constants.source));
    result.write('>');
    result.write(getAddrWithSsid(Ax25Constants.destination));

    final int heard = getHeard();
    for (int i = Ax25Constants.repeater1; i < numAddr; i++) {
      result.write(',');
      result.write(getAddrWithSsid(i));
      if (i == heard) {
        result.write('*');
      }
    }

    result.write(':');
    return result.toString();
  }

  /// Format via path for display.
  String formatViaPath() {
    if (numAddr == 0) return '';

    final StringBuffer result = StringBuffer();
    final int heard = getHeard();

    for (int i = Ax25Constants.repeater1; i < numAddr; i++) {
      if (i > Ax25Constants.repeater1) {
        result.write(',');
      }
      result.write(getAddrWithSsid(i));
      if (i == heard) {
        result.write('*');
      }
    }

    return result.toString();
  }

  /// Pack frame for transmission.
  int pack(Uint8List result) {
    _copy(frameData, 0, result, 0, frameLen);
    return frameLen;
  }

  /// Get frame type.
  Ax25FrameInfo getFrameType() {
    final Ax25FrameInfo r = Ax25FrameInfo();

    final int c = getControl();
    if (c < 0) {
      r.desc = 'Not AX.25';
      r.type = Ax25FrameType.notAX25;
      return r;
    }

    int c2 = 0;

    // Attempt to determine modulo
    if (modulo == Ax25Modulo.unknown && (c & 3) == 1 && getC2() != -1) {
      modulo = Ax25Modulo.modulo128;
    } else if (modulo == Ax25Modulo.unknown &&
        (c & 1) == 0 &&
        _getInfoOffset() < frameLen &&
        frameData[_getInfoOffset()] == 0xF0) {
      modulo = Ax25Modulo.modulo128;
    }

    if (modulo == Ax25Modulo.modulo128) {
      c2 = getC2();
    }

    final int dstC = (frameData[Ax25Constants.destination * 7 + 6] &
                Ax25Constants.ssidHMask) !=
            0
        ? 1
        : 0;
    final int srcC = (frameData[Ax25Constants.source * 7 + 6] &
                Ax25Constants.ssidHMask) !=
            0
        ? 1
        : 0;

    String crText, pfText;
    if (dstC != 0) {
      if (srcC != 0) {
        r.cr = CmdRes.cr11;
        crText = 'cc=11';
        pfText = 'p/f';
      } else {
        r.cr = CmdRes.cmd;
        crText = 'cmd';
        pfText = 'p';
      }
    } else {
      if (srcC != 0) {
        r.cr = CmdRes.res;
        crText = 'res';
        pfText = 'f';
      } else {
        r.cr = CmdRes.cr00;
        crText = 'cc=00';
        pfText = 'p/f';
      }
    }

    if ((c & 1) == 0) {
      // Information frame
      if (modulo == Ax25Modulo.modulo128) {
        r.ns = (c >> 1) & 0x7F;
        r.pf = c2 & 1;
        r.nr = (c2 >> 1) & 0x7F;
      } else {
        r.ns = (c >> 1) & 7;
        r.pf = (c >> 4) & 1;
        r.nr = (c >> 5) & 7;
      }

      r.desc =
          'I $crText, n(s)=${r.ns}, n(r)=${r.nr}, $pfText=${r.pf}, pid=0x${getPid().toRadixString(16).padLeft(2, '0').toUpperCase()}';
      r.type = Ax25FrameType.i;
      return r;
    } else if ((c & 2) == 0) {
      // Supervisory frame
      if (modulo == Ax25Modulo.modulo128) {
        r.pf = c2 & 1;
        r.nr = (c2 >> 1) & 0x7F;
      } else {
        r.pf = (c >> 4) & 1;
        r.nr = (c >> 5) & 7;
      }

      switch ((c >> 2) & 3) {
        case 0:
          r.desc = 'RR $crText, n(r)=${r.nr}, $pfText=${r.pf}';
          r.type = Ax25FrameType.sRr;
          return r;
        case 1:
          r.desc = 'RNR $crText, n(r)=${r.nr}, $pfText=${r.pf}';
          r.type = Ax25FrameType.sRnr;
          return r;
        case 2:
          r.desc = 'REJ $crText, n(r)=${r.nr}, $pfText=${r.pf}';
          r.type = Ax25FrameType.sRej;
          return r;
        case 3:
          r.desc = 'SREJ $crText, n(r)=${r.nr}, $pfText=${r.pf}';
          r.type = Ax25FrameType.sSrej;
          return r;
      }
    } else {
      // Unnumbered frame
      r.pf = (c >> 4) & 1;

      switch (c & 0xEF) {
        case 0x6F:
          r.desc = 'SABME $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uSabme;
          return r;
        case 0x2F:
          r.desc = 'SABM $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uSabm;
          return r;
        case 0x43:
          r.desc = 'DISC $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uDisc;
          return r;
        case 0x0F:
          r.desc = 'DM $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uDm;
          return r;
        case 0x63:
          r.desc = 'UA $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uUa;
          return r;
        case 0x87:
          r.desc = 'FRMR $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uFrmr;
          return r;
        case 0x03:
          r.desc = 'UI $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uUi;
          return r;
        case 0xAF:
          r.desc = 'XID $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uXid;
          return r;
        case 0xE3:
          r.desc = 'TEST $crText, $pfText=${r.pf}';
          r.type = Ax25FrameType.uTest;
          return r;
        default:
          r.desc = 'U other???';
          r.type = Ax25FrameType.u;
          return r;
      }
    }

    r.type = Ax25FrameType.notAX25;
    return r;
  }

  /// Check if packet is APRS format.
  bool isAprs() {
    if (frameLen == 0) return false;

    final int ctrl = getControl();
    final int pid = getPid();

    return numAddr >= 2 &&
        ctrl == Ax25Constants.uiFrame &&
        pid == Ax25Constants.pidNoLayer3;
  }

  /// Check if packet is null/empty.
  bool isNullFrame() {
    return frameLen == 0;
  }

  /// Calculate dedupe CRC (excludes digipeaters).
  int dedupeCrc() {
    final String src = getAddrWithSsid(Ax25Constants.source);
    final String dest = getAddrWithSsid(Ax25Constants.destination);
    final Uint8List info = getInfo();
    int infoLen = info.length;

    // Remove trailing CR/LF/space
    while (infoLen >= 1 &&
        (info[infoLen - 1] == 0x0D ||
            info[infoLen - 1] == 0x0A ||
            info[infoLen - 1] == 0x20)) {
      infoLen--;
    }

    int crc = 0xFFFF;
    crc = FcsCalc.crc16(_asciiBytes(src), src.length, crc);
    crc = FcsCalc.crc16(_asciiBytes(dest), dest.length, crc);
    crc = FcsCalc.crc16(info, infoLen, crc);

    return crc;
  }

  /// Calculate CRC for entire frame (for multimodem duplicate detection).
  int multiModemCrc() {
    final Uint8List fbuf = Uint8List(Ax25Constants.maxPacketLen);
    final int flen = pack(fbuf);

    int crc = 0xFFFF;
    crc = FcsCalc.crc16(fbuf, flen, crc);

    return crc;
  }

  /// Convert audio level to text.
  static bool alevelToText(ALevel alevel, List<String> textOut) {
    if (alevel.rec < 0) {
      textOut[0] = '';
      return false;
    }

    if (alevel.mark >= 0 && alevel.space < 0) {
      // Baseband
      textOut[0] =
          '${alevel.rec}(${_signed(alevel.mark)}/${_signed(alevel.space)})';
    } else if ((alevel.mark == -1 && alevel.space == -1) ||
        (alevel.mark == -99 && alevel.space == -99)) {
      // PSK or FM demodulator
      textOut[0] = '${alevel.rec}';
    } else if (alevel.mark == -2 && alevel.space == -2) {
      // DTMF
      textOut[0] = '${alevel.rec}';
    } else {
      // AFSK
      textOut[0] = '${alevel.rec}(${alevel.mark}/${alevel.space})';
    }

    return true;
  }

  static String _signed(int v) => v >= 0 ? '+$v' : '-${v.abs()}';

  // Helper methods for offset calculations
  int _getControlOffset() {
    return numAddr * 7;
  }

  int _getNumControl() {
    final int c = frameData[_getControlOffset()];

    if ((c & 0x01) == 0) {
      // I frame
      return (modulo == Ax25Modulo.modulo128) ? 2 : 1;
    }

    if ((c & 0x03) == 1) {
      // S frame
      return (modulo == Ax25Modulo.modulo128) ? 2 : 1;
    }

    return 1; // U frame
  }

  int _getPidOffset() {
    return _getControlOffset() + _getNumControl();
  }

  int _getNumPid() {
    final int c = frameData[_getControlOffset()];

    if ((c & 0x01) == 0 || c == 0x03 || c == 0x13) {
      // I or UI frame
      final int pidOffset = _getPidOffset();
      if (pidOffset < frameLen) {
        final int pid = frameData[pidOffset];
        if (pid == Ax25Constants.pidEscapeCharacter) {
          return 2;
        }
        return 1;
      }
    }

    return 0;
  }

  int _getInfoOffset() {
    return _getControlOffset() + _getNumControl() + _getNumPid();
  }

  int _getNumInfo() {
    int len = frameLen - numAddr * 7 - _getNumControl() - _getNumPid();
    if (len < 0) len = 0;
    return len;
  }
}
