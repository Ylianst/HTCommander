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
// ax25_pad2.dart - AX.25 packet assembler and disassembler, part 2
//
// Ported from C# HamLib/Ax25Pad2.cs
//

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'ax25_pad.dart';

/// Extended AX.25 frame construction methods for U, S, and I frames.
class Ax25Pad2 {
  Ax25Pad2._();

  // ===========================================================================
  // U Frame Construction
  // ===========================================================================

  /// Construct a U (Unnumbered) frame.
  static Packet? uFrame(
    List<String> addrs,
    int numAddr,
    int cr,
    Ax25FrameType ftype,
    int pf,
    int pid,
    Uint8List? pinfo,
    int infoLen,
  ) {
    final Packet thisP = Packet();
    thisP.modulo = Ax25Modulo.unknown;

    if (!_setAddrs(thisP, addrs, numAddr, cr)) {
      print('Internal error in UFrame: Could not set addresses for U frame.');
      return null;
    }

    int ctrl = 0;
    int t = 999; // 1 = must be cmd, 0 = must be response, 2 = can be either
    int i = 0; // Is Info part allowed?

    switch (ftype) {
      case Ax25FrameType.uSabme:
        ctrl = 0x6F;
        t = 1;
        break;
      case Ax25FrameType.uSabm:
        ctrl = 0x2F;
        t = 1;
        break;
      case Ax25FrameType.uDisc:
        ctrl = 0x43;
        t = 1;
        break;
      case Ax25FrameType.uDm:
        ctrl = 0x0F;
        t = 0;
        break;
      case Ax25FrameType.uUa:
        ctrl = 0x63;
        t = 0;
        break;
      case Ax25FrameType.uFrmr:
        ctrl = 0x87;
        t = 0;
        i = 1;
        break;
      case Ax25FrameType.uUi:
        ctrl = 0x03;
        t = 2;
        i = 1;
        break;
      case Ax25FrameType.uXid:
        ctrl = 0xAF;
        t = 2;
        i = 1;
        break;
      case Ax25FrameType.uTest:
        ctrl = 0xE3;
        t = 2;
        i = 1;
        break;
      default:
        print('Internal error in UFrame: Invalid ftype $ftype for U frame.');
        return null;
    }

    if (pf != 0) ctrl |= 0x10;

    // Check command/response validity
    if (t != 2) {
      if (cr != t) {
        print(
          'Internal error in UFrame: U frame, cr is $cr but must be $t. ftype=$ftype',
        );
      }
    }

    // Add control byte
    thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;

    // Add PID for UI frames
    if (ftype == Ax25FrameType.uUi) {
      if (pid < 0 || pid == 0 || pid == 0xFF) {
        print(
          'Internal error in UFrame: U frame, Invalid pid value 0x${pid.toRadixString(16)}.',
        );
        pid = Ax25Constants.pidNoLayer3;
      }
      thisP.frameData[thisP.frameLen++] = pid & 0xFF;
    }

    // Add information field if allowed and provided
    if (i != 0) {
      if (pinfo != null && infoLen > 0) {
        if (infoLen > Ax25Constants.maxInfoLen) {
          print(
            'Internal error in UFrame: U frame, Invalid information field length $infoLen.',
          );
          infoLen = Ax25Constants.maxInfoLen;
        }
        _copyInto(pinfo, thisP.frameData, thisP.frameLen, infoLen);
        thisP.frameLen += infoLen;
      }
    } else {
      if (pinfo != null && infoLen > 0) {
        print(
          'Internal error in UFrame: Info part not allowed for U frame type.',
        );
      }
    }

    thisP.frameData[thisP.frameLen] = 0;
    assert(thisP.frameLen <= Ax25Constants.maxPacketLen);

    return thisP;
  }

  // ===========================================================================
  // S Frame Construction
  // ===========================================================================

  /// Construct an S (Supervisory) frame.
  static Packet? sFrame(
    List<String> addrs,
    int numAddr,
    int cr,
    Ax25FrameType ftype,
    int modulo,
    int nr,
    int pf,
    Uint8List? pinfo,
    int infoLen,
  ) {
    final Packet thisP = Packet();

    if (!_setAddrs(thisP, addrs, numAddr, cr)) {
      print('Internal error in SFrame: Could not set addresses for S frame.');
      return null;
    }

    if (modulo != 8 && modulo != 128) {
      print('Internal error in SFrame: Invalid modulo $modulo for S frame.');
      modulo = 8;
    }
    thisP.modulo = modulo;

    if (nr < 0 || nr >= modulo) {
      print('Internal error in SFrame: Invalid N(R) $nr for S frame.');
      nr &= (modulo - 1);
    }

    if (ftype == Ax25FrameType.sSrej && cr != CmdRes.res) {
      print('Internal error in SFrame: SREJ must be response.');
    }

    int ctrl = 0;
    switch (ftype) {
      case Ax25FrameType.sRr:
        ctrl = 0x01;
        break;
      case Ax25FrameType.sRnr:
        ctrl = 0x05;
        break;
      case Ax25FrameType.sRej:
        ctrl = 0x09;
        break;
      case Ax25FrameType.sSrej:
        ctrl = 0x0D;
        break;
      default:
        print('Internal error in SFrame: Invalid ftype $ftype for S frame.');
        return null;
    }

    if (modulo == 8) {
      // Modulo 8: single control byte
      if (pf != 0) ctrl |= 0x10;
      ctrl |= (nr << 5);
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    } else {
      // Modulo 128: two control bytes
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;

      ctrl = (pf & 1);
      ctrl |= (nr << 1);
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    }

    // Add information field for SREJ if provided
    if (ftype == Ax25FrameType.sSrej) {
      if (pinfo != null && infoLen > 0) {
        if (infoLen > Ax25Constants.maxInfoLen) {
          print(
            'Internal error in SFrame: SREJ frame, Invalid information field length $infoLen.',
          );
          infoLen = Ax25Constants.maxInfoLen;
        }
        _copyInto(pinfo, thisP.frameData, thisP.frameLen, infoLen);
        thisP.frameLen += infoLen;
      }
    } else {
      if (pinfo != null || infoLen != 0) {
        print(
          'Internal error in SFrame: Info part not allowed for RR, RNR, REJ frame.',
        );
      }
    }

    thisP.frameData[thisP.frameLen] = 0;
    assert(thisP.frameLen <= Ax25Constants.maxPacketLen);

    return thisP;
  }

  // ===========================================================================
  // I Frame Construction
  // ===========================================================================

  /// Construct an I (Information) frame.
  static Packet? iFrame(
    List<String> addrs,
    int numAddr,
    int cr,
    int modulo,
    int nr,
    int ns,
    int pf,
    int pid,
    Uint8List? pinfo,
    int infoLen,
  ) {
    final Packet thisP = Packet();

    if (!_setAddrs(thisP, addrs, numAddr, cr)) {
      print('Internal error in IFrame: Could not set addresses for I frame.');
      return null;
    }

    if (modulo != 8 && modulo != 128) {
      print('Internal error in IFrame: Invalid modulo $modulo for I frame.');
      modulo = 8;
    }
    thisP.modulo = modulo;

    if (nr < 0 || nr >= modulo) {
      print('Internal error in IFrame: Invalid N(R) $nr for I frame.');
      nr &= (modulo - 1);
    }

    if (ns < 0 || ns >= modulo) {
      print('Internal error in IFrame: Invalid N(S) $ns for I frame.');
      ns &= (modulo - 1);
    }

    int ctrl = 0;

    if (modulo == 8) {
      // Modulo 8: single control byte
      ctrl = (nr << 5) | (ns << 1);
      if (pf != 0) ctrl |= 0x10;
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    } else {
      // Modulo 128: two control bytes
      ctrl = ns << 1;
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;

      ctrl = nr << 1;
      if (pf != 0) ctrl |= 0x01;
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    }

    // Add PID
    if (pid < 0 || pid == 0 || pid == 0xFF) {
      print(
        'Warning: Client application provided invalid PID value, 0x${pid.toRadixString(16)}, for I frame.',
      );
      pid = Ax25Constants.pidNoLayer3;
    }
    thisP.frameData[thisP.frameLen++] = pid & 0xFF;

    // Add information field
    if (pinfo != null && infoLen > 0) {
      if (infoLen > Ax25Constants.maxInfoLen) {
        print(
          'Internal error in IFrame: I frame, Invalid information field length $infoLen.',
        );
        infoLen = Ax25Constants.maxInfoLen;
      }
      _copyInto(pinfo, thisP.frameData, thisP.frameLen, infoLen);
      thisP.frameLen += infoLen;
    }

    thisP.frameData[thisP.frameLen] = 0;
    assert(thisP.frameLen <= Ax25Constants.maxPacketLen);

    return thisP;
  }

  // ===========================================================================
  // Helper Methods
  // ===========================================================================

  /// Set address fields in the packet.
  static bool _setAddrs(Packet pp, List<String> addrs, int numAddr, int cr) {
    assert(pp.frameLen == 0);
    assert(cr == CmdRes.cmd || cr == CmdRes.res);

    if (numAddr < Ax25Constants.minAddrs || numAddr > Ax25Constants.maxAddrs) {
      print('INTERNAL ERROR: SetAddrs, num_addr = $numAddr');
      return false;
    }

    for (int n = 0; n < numAddr; n++) {
      final int offset = n * 7;
      const bool strict = true;

      final ParsedAddr p = Packet.parseAddr(n, addrs[n], strict);
      if (!p.ok) {
        return false;
      }

      // Fill in address (6 bytes, shifted left 1 bit)
      for (int i = 0; i < 6; i++) {
        if (i < p.addr.length) {
          pp.frameData[offset + i] = (p.addr.codeUnitAt(i) << 1) & 0xFF;
        } else {
          pp.frameData[offset + i] = (0x20 << 1) & 0xFF;
        }
      }

      // Fill in SSID byte
      int ssidByte = 0x60 | ((p.ssid & 0xF) << 1);

      // Set command/response flag
      switch (n) {
        case Ax25Constants.destination:
          if (cr == CmdRes.cmd) ssidByte |= 0x80;
          break;
        case Ax25Constants.source:
          if (cr == CmdRes.res) ssidByte |= 0x80;
          break;
        default:
          // Digipeaters don't set C/R bit
          break;
      }

      // Set last address bit if this is the final address
      if (n == numAddr - 1) {
        ssidByte |= 0x01;
      }

      pp.frameData[offset + 6] = ssidByte & 0xFF;
      pp.frameLen += 7;
    }

    pp.numAddr = numAddr;
    return true;
  }

  static void _copyInto(Uint8List src, Uint8List dst, int dstOff, int len) {
    dst.setRange(dstOff, dstOff + len, src);
  }

  // ===========================================================================
  // Test/Debug Methods
  // ===========================================================================

  /// Test harness for creating various frame types.
  static void runTests() {
    print('=== AX25 Pad2 Test Suite ===\n');

    final List<String> addrs = List<String>.filled(Ax25Constants.maxAddrs, '');
    addrs[0] = 'W2UB';
    addrs[1] = 'WB2OSZ-15';
    int numAddr = 2;

    // Test U frames
    print('\n=== Testing U Frames ===\n');

    for (
      int fi = Ax25FrameType.uSabme.index;
      fi <= Ax25FrameType.uTest.index;
      fi++
    ) {
      final Ax25FrameType ftype = Ax25FrameType.values[fi];
      for (int pf = 0; pf <= 1; pf++) {
        int cmin = 0, cmax = 1;

        switch (ftype) {
          case Ax25FrameType.uSabme:
          case Ax25FrameType.uSabm:
          case Ax25FrameType.uDisc:
            cmin = 1;
            cmax = 1; // Command only
            break;
          case Ax25FrameType.uDm:
          case Ax25FrameType.uUa:
          case Ax25FrameType.uFrmr:
            cmin = 0;
            cmax = 0; // Response only
            break;
          case Ax25FrameType.uUi:
          case Ax25FrameType.uXid:
          case Ax25FrameType.uTest:
            cmin = 0;
            cmax = 1; // Either
            break;
          default:
            break;
        }

        for (int cr = cmin; cr <= cmax; cr++) {
          print('\nConstruct U frame, cr=$cr, ftype=$ftype, pid=0xF0');
          final Packet? pp = uFrame(
            addrs,
            numAddr,
            cr,
            ftype,
            pf,
            0xF0,
            null,
            0,
          );
          if (pp != null) {
            _printFrameInfo(pp);
          }
        }
      }
    }

    // Test S frames
    print('\n\n=== Testing S Frames ===\n');

    addrs[2] = 'DIGI1-1';
    numAddr = 3;

    for (
      int fi = Ax25FrameType.sRr.index;
      fi <= Ax25FrameType.sSrej.index;
      fi++
    ) {
      final Ax25FrameType ftype = Ax25FrameType.values[fi];
      for (int pf = 0; pf <= 1; pf++) {
        // Test modulo 8
        int modulo = 8;
        int nr = modulo ~/ 2 + 1;

        for (int cr = 0; cr <= 1; cr++) {
          print('\nConstruct S frame (mod $modulo), cr=$cr, ftype=$ftype');
          final Packet? pp = sFrame(
            addrs,
            numAddr,
            cr,
            ftype,
            modulo,
            nr,
            pf,
            null,
            0,
          );
          if (pp != null) {
            _printFrameInfo(pp);
          }
        }

        // Test modulo 128
        modulo = 128;
        nr = modulo ~/ 2 + 1;

        for (int cr = 0; cr <= 1; cr++) {
          print('\nConstruct S frame (mod $modulo), cr=$cr, ftype=$ftype');
          final Packet? pp = sFrame(
            addrs,
            numAddr,
            cr,
            ftype,
            modulo,
            nr,
            pf,
            null,
            0,
          );
          if (pp != null) {
            _printFrameInfo(pp);
          }
        }
      }
    }

    // Test SREJ with info field
    print('\n\nConstruct Multi-SREJ S frame with info');
    final Uint8List srejInfo = Uint8List.fromList(<int>[
      1 << 1,
      2 << 1,
      3 << 1,
      4 << 1,
    ]);
    final Packet? srejPacket = sFrame(
      addrs,
      numAddr,
      CmdRes.res,
      Ax25FrameType.sSrej,
      128,
      127,
      1,
      srejInfo,
      srejInfo.length,
    );
    if (srejPacket != null) {
      _printFrameInfo(srejPacket);
    }

    // Test I frames
    print('\n\n=== Testing I Frames ===\n');

    final Uint8List testInfo = Uint8List.fromList(
      'The rain in Spain stays mainly on the plain.'.codeUnits,
    );

    for (int pf = 0; pf <= 1; pf++) {
      // Test modulo 8
      int modulo = 8;
      int nr = 0x55 & (modulo - 1);
      int ns = 0xAA & (modulo - 1);

      for (int cr = 0; cr <= 1; cr++) {
        print('\nConstruct I frame (mod $modulo), cr=$cr, pid=0xF0');
        final Packet? pp = iFrame(
          addrs,
          numAddr,
          cr,
          modulo,
          nr,
          ns,
          pf,
          0xF0,
          testInfo,
          testInfo.length,
        );
        if (pp != null) {
          _printFrameInfo(pp);
        }
      }

      // Test modulo 128
      modulo = 128;
      nr = 0x55 & (modulo - 1);
      ns = 0xAA & (modulo - 1);

      for (int cr = 0; cr <= 1; cr++) {
        print('\nConstruct I frame (mod $modulo), cr=$cr, pid=0xF0');
        final Packet? pp = iFrame(
          addrs,
          numAddr,
          cr,
          modulo,
          nr,
          ns,
          pf,
          0xF0,
          testInfo,
          testInfo.length,
        );
        if (pp != null) {
          _printFrameInfo(pp);
        }
      }
    }

    print('\n\n=== SUCCESS! ===\n');
  }

  /// Print frame information for debugging.
  static void _printFrameInfo(Packet pp) {
    print('  Addresses: ${pp.formatAddrs()}');

    final Ax25FrameInfo info = pp.getFrameType();
    print('  Type: ${info.desc}');

    final Uint8List inf = pp.getInfo();
    final int infoLen = inf.length;
    if (infoLen > 0) {
      final StringBuffer sb = StringBuffer('  Info: ');
      for (int i = 0; i < math.min(infoLen, 50); i++) {
        if (inf[i] >= 32 && inf[i] < 127) {
          sb.writeCharCode(inf[i]);
        } else {
          sb.write(
            '<${inf[i].toRadixString(16).padLeft(2, '0').toUpperCase()}>',
          );
        }
      }
      if (infoLen > 50) sb.write('...');
      print(sb.toString());
    }

    final StringBuffer raw = StringBuffer('  Raw: ');
    for (int i = 0; i < math.min(pp.frameLen, 50); i++) {
      raw.write(
        '${pp.frameData[i].toRadixString(16).padLeft(2, '0').toUpperCase()} ',
      );
    }
    if (pp.frameLen > 50) raw.write('...');
    print(raw.toString());
  }
}
