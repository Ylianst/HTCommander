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
// fx25_send.dart - FX.25 frame transmission with Reed-Solomon FEC
//
// Ported from C# HamLib/Fx25Send.cs
//

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'fcs_calc.dart';
import 'fx25.dart';
import 'fx25_encode.dart';
import 'gen_tone.dart';

/// FX.25 frame transmission - converts HDLC frames to FX.25 encoded bit stream.
class Fx25Send {
  static const int _maxRadioChannels = 16;

  GenTone? _genTone;
  late List<int> _numberOfBitsSent;
  late List<int> _nrziOutput;

  Fx25Send() {
    _numberOfBitsSent = List<int>.filled(_maxRadioChannels, 0);
    _nrziOutput = List<int>.filled(_maxRadioChannels, 0);
  }

  /// Initialize the FX.25 send module with a tone generator.
  void init(GenTone genTone) {
    _genTone = genTone;
    _numberOfBitsSent.fillRange(0, _numberOfBitsSent.length, 0);
    _nrziOutput.fillRange(0, _nrziOutput.length, 0);
  }

  /// Convert HDLC frames to a stream of bits with FX.25 encoding.
  int sendFrame(int chan, Uint8List fbuf, int flen, int fxMode) {
    if (_genTone == null) {
      print('FX.25 Send: GenTone not initialized!');
      return -1;
    }

    if (Fx25.getDebugLevel() >= 3) {
      print('------');
      print('FX.25[$chan] send frame: FX.25 mode = $fxMode');
      Fx25.hexDump(fbuf, flen);
    }

    _numberOfBitsSent[chan] = 0;

    // If the frame buffer is not large enough to hold the FCS, expand it
    if (fbuf.length < (flen + 2)) {
      final Uint8List fbuf2 = Uint8List(flen + 2);
      fbuf2.setRange(0, flen, fbuf);
      fbuf = fbuf2;
    }

    final int fcs = FcsCalc.calculate(fbuf, flen);
    fbuf[flen++] = fcs & 0xff;
    fbuf[flen++] = (fcs >> 8) & 0xff;

    final Uint8List data = Uint8List(Fx25.fx25MaxData + 1);
    const int fence = 0xaa;
    data[Fx25.fx25MaxData] = fence;

    final int dlen = _stuffIt(fbuf, flen, data, Fx25.fx25MaxData);

    assert(data[Fx25.fx25MaxData] == fence);
    if (dlen < 0) {
      print(
        'FX.25[$chan]: Frame length of $flen + overhead is too large to encode.',
      );
      return -1;
    }

    final int ctagNum = Fx25.pickMode(fxMode, dlen);

    if (ctagNum < Fx25.ctagMin || ctagNum > Fx25.ctagMax) {
      print(
        'FX.25[$chan]: Could not find suitable format for requested '
        '$fxMode and data length $dlen.',
      );
      return -1;
    }

    final int ctagValue = Fx25.getCtagValue(ctagNum);

    final int kDataRadio = Fx25.getKDataRadio(ctagNum);
    final int kDataRs = Fx25.getKDataRs(ctagNum);
    final int shortenBy = Fx25.fx25MaxData - kDataRadio;
    if (shortenBy > 0) {
      data.fillRange(kDataRadio, kDataRadio + shortenBy, 0);
    }

    final Uint8List check = Uint8List(Fx25.fx25MaxCheck + 1);
    check[Fx25.fx25MaxCheck] = fence;
    final ReedSolomonCodec rs = Fx25.getRs(ctagNum);

    assert(kDataRs + Fx25.getNRoots(ctagNum) == Fx25.fx25BlockSize);

    Fx25Encode.encodeRs(rs, data, check);
    assert(check[Fx25.fx25MaxCheck] == fence);

    if (Fx25.getDebugLevel() >= 3) {
      print(
        'FX.25[$chan]: transmit $kDataRadio data bytes, ctag number '
        '0x${ctagNum.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      );
      Fx25.hexDump(data, kDataRadio);
      print('FX.25[$chan]: transmit ${Fx25.getNRoots(ctagNum)} check bytes:');
      Fx25.hexDump(check, Fx25.getNRoots(ctagNum));
      print('------');
    }

    for (int k = 0; k < 8; k++) {
      final int b = (ctagValue >>> (k * 8)) & 0xff;
      _sendBytes(chan, Uint8List.fromList([b]), 1);
    }

    _sendBytes(chan, data, kDataRadio);
    _sendBytes(chan, check, Fx25.getNRoots(ctagNum));

    return _numberOfBitsSent[chan];
  }

  void _sendBytes(int chan, Uint8List b, int count) {
    for (int j = 0; j < count; j++) {
      int x = b[j];
      for (int k = 0; k < 8; k++) {
        _sendBit(chan, x & 0x01);
        x >>= 1;
      }
    }
  }

  void _sendBit(int chan, int b) {
    if (b == 0) {
      _nrziOutput[chan] = _nrziOutput[chan] == 0 ? 1 : 0;
    }

    _genTone?.putBit(chan, _nrziOutput[chan]);
    _numberOfBitsSent[chan]++;
  }

  int _stuffIt(Uint8List inData, int ilen, Uint8List outData, int osize) {
    const int flag = 0x7e;
    outData.fillRange(0, osize, 0);
    outData[0] = flag;
    int olen = 8;
    final int osizeBits = osize * 8;
    int ones = 0;

    for (int i = 0; i < ilen; i++) {
      for (int imask = 1; imask != 0; imask = (imask << 1) & 0xFF) {
        final int v = (inData[i] & imask) != 0 ? 1 : 0;

        if (olen >= osizeBits) return -1;
        if (v != 0) outData[olen >> 3] |= (1 << (olen & 0x7));
        olen++;

        if (v != 0) {
          ones++;
          if (ones == 5) {
            if (olen >= osizeBits) return -1;
            olen++;
            ones = 0;
          }
        } else {
          ones = 0;
        }
      }
    }

    for (int imask = 1; imask != 0; imask = (imask << 1) & 0xFF) {
      if (olen >= osizeBits) return -1;
      if ((flag & imask) != 0) outData[olen >> 3] |= (1 << (olen & 0x7));
      olen++;
    }

    final int ret = (olen + 7) ~/ 8;

    int imask2 = 1;
    while (olen < osizeBits) {
      if ((flag & imask2) != 0) outData[olen >> 3] |= (1 << (olen & 0x7));
      olen++;
      imask2 = ((imask2 << 1) | (imask2 >> 7)) & 0xFF;
    }

    return ret;
  }
}
