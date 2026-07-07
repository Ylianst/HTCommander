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
// fx25_rec.dart - FX.25 codeblock extraction and processing from bit stream
//
// Ported from C# HamLib/Fx25Rec.cs
//

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'ax25_pad.dart';
import 'correction_info.dart';
import 'fcs_calc.dart';
import 'fx25.dart';
import 'multi_modem.dart';
import 'reed_solomon_codec.dart';

/// FX.25 receiver state.
enum Fx25State {
  fxTag, // Looking for correlation tag
  fxData, // Accumulating data bytes
  fxCheck, // Accumulating check bytes
}

/// FX.25 receiver context for a single channel/subchannel/slicer.
class _Fx25Context {
  Fx25State state = Fx25State.fxTag;
  int accum = 0; // Accumulate bits for matching to correlation tag
  int ctagNum = -1; // Correlation tag number, CTAG_MIN to CTAG_MAX if match
  int kDataRadio = 0; // Expected size of "data" sent over radio
  int coffs = 0; // Starting offset of the check part
  int nRoots = 0; // Expected number of check bytes
  int dlen = 0; // Accumulated length in "data" below
  int clen = 0; // Accumulated length in "check" below
  int iMask = 0; // Mask for storing a bit
  late Uint8List block; // RS codeblock buffer
  int fence = 0x55; // Fence value for buffer overflow detection

  _Fx25Context() {
    block = Uint8List(Fx25.fx25BlockSize + 1);
    block[Fx25.fx25BlockSize] = fence;
  }
}

/// FX.25 receiver - extracts and decodes FX.25 frames from bit stream.
class Fx25Rec {
  static const int _maxRadioChans = 6;
  static const int _maxSubchans = 9;
  static const int _maxSlicers = 9;
  static const int _fence = 0x55;

  // Context for each channel/subchannel/slicer combination
  final List<List<List<_Fx25Context?>>> _contexts;

  // Reference to MultiModem for frame processing
  final MultiModem? _multiModem;

  Fx25Rec([this._multiModem])
    : _contexts = List.generate(
        _maxRadioChans,
        (_) => List.generate(
          _maxSubchans,
          (_) => List<_Fx25Context?>.filled(_maxSlicers, null),
        ),
      );

  /// Process a single received bit for FX.25 decoding.
  ///
  /// [dbit] is the data bit (after NRZI and descrambling); non-zero = logic '1'.
  void recBit(int chan, int subchan, int slice, int dbit) {
    assert(chan >= 0 && chan < _maxRadioChans);
    assert(subchan >= 0 && subchan < _maxSubchans);
    assert(slice >= 0 && slice < _maxSlicers);

    // Allocate context blocks only as needed
    _Fx25Context? f = _contexts[chan][subchan][slice];
    if (f == null) {
      f = _Fx25Context();
      _contexts[chan][subchan][slice] = f;
    }

    // State machine to identify correlation tag then gather appropriate number
    // of data and check bytes.
    switch (f.state) {
      case Fx25State.fxTag:
        f.accum = f.accum >>> 1;
        if (dbit != 0) f.accum |= 1 << 63;

        final int c = Fx25.tagFindMatch(f.accum);
        if (c >= Fx25.ctagMin && c <= Fx25.ctagMax) {
          f.ctagNum = c;
          f.kDataRadio = Fx25.getKDataRadio(f.ctagNum);
          f.nRoots = Fx25.getNRoots(f.ctagNum);
          f.coffs = Fx25.getKDataRs(f.ctagNum);
          assert(f.coffs == Fx25.fx25BlockSize - f.nRoots);

          // final int bitErrors = _popCount(f.accum ^ Fx25.getCtagValue(c));
          // print(
          //   'FX.25[$chan.$slice]: Matched correlation tag '
          //   '0x${c.toRadixString(16).padLeft(2, '0')} with $bitErrors bit errors. '
          //   'Expecting ${f.kDataRadio} data & ${f.nRoots} check bytes.',
          // );

          f.iMask = 0x01;
          f.dlen = 0;
          f.clen = 0;
          f.block.fillRange(0, f.block.length - 1, 0);
          f.block[Fx25.fx25BlockSize] = _fence;
          f.state = Fx25State.fxData;
        }
        break;

      case Fx25State.fxData:
        if (dbit != 0) f.block[f.dlen] |= f.iMask;

        f.iMask = (f.iMask << 1) & 0xFF;
        if (f.iMask == 0) {
          f.iMask = 0x01;
          f.dlen++;
          if (f.dlen >= f.kDataRadio) {
            f.state = Fx25State.fxCheck;
          }
        }
        break;

      case Fx25State.fxCheck:
        if (dbit != 0) f.block[f.coffs + f.clen] |= f.iMask;

        f.iMask = (f.iMask << 1) & 0xFF;
        if (f.iMask == 0) {
          f.iMask = 0x01;
          f.clen++;
          if (f.clen >= f.nRoots) {
            _processRsBlock(chan, subchan, slice, f);

            f.ctagNum = -1;
            f.accum = 0;
            f.state = Fx25State.fxTag;
          }
        }
        break;
    }
  }

  /// Check if FX.25 reception is currently in progress for a channel.
  bool isBusy(int chan) {
    assert(chan >= 0 && chan < _maxRadioChans);

    for (int i = 0; i < _maxSubchans; i++) {
      for (int j = 0; j < _maxSlicers; j++) {
        if (_contexts[chan][i][j] != null) {
          if (_contexts[chan][i][j]!.state != Fx25State.fxTag) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Process a complete Reed-Solomon block.
  void _processRsBlock(int chan, int subchan, int slice, _Fx25Context f) {
    if (Fx25.getDebugLevel() >= 3) {
      print('FX.25[$chan.$slice]: Received RS codeblock.');
      Fx25.hexDump(f.block, Fx25.fx25BlockSize);
    }

    assert(f.block[Fx25.fx25BlockSize] == _fence);

    final ReedSolomonCodec rs = Fx25.getRs(f.ctagNum);

    final int derrors = ReedSolomon.decode(rs, f.block, null, 0);

    if (derrors >= 0) {
      // Success: -1 for failure, >= 0 for success with number of bytes corrected
      // print(
      //   'FX.25[$chan.$slice]: RS FEC OK, corrected '
      //   '${derrors.toString().padLeft(2)} byte(s) '
      //   '(tag 0x${f.ctagNum.toRadixString(16).padLeft(2, '0')}).',
      // );

      final Uint8List frameBuf = Uint8List(Fx25.fx25MaxData + 1);
      final int frameLen = _unstuff(
        chan,
        subchan,
        slice,
        f.block,
        f.dlen,
        frameBuf,
      );

      if (frameLen == 0) {
        // _unstuff already printed the specific reason (bad start flag, no
        // terminating flag, seven ones, or not a whole number of bytes).
        // print(
        //   'FX.25[$chan.$slice]: REJECT - HDLC unstuffing failed, frame dropped.',
        // );
        return;
      }

      if (frameLen >= 14 + 1 + 2) {
        // Minimum: Two addresses & control & FCS
        final int actualFcs =
            (frameBuf[frameLen - 2] | (frameBuf[frameLen - 1] << 8)) & 0xFFFF;
        final int expectedFcs = FcsCalc.calculate(frameBuf, frameLen - 2);

        if (actualFcs == expectedFcs) {
          // print(
          //   'FX.25[$chan.$slice]: ACCEPT - delivering ${frameLen - 2}-byte '
          //   'frame: ${_hexInline(frameBuf, frameLen - 2)}',
          // );
          if (Fx25.getDebugLevel() >= 3) {
            print('FX.25[$chan.$slice]: Extracted AX.25 frame:');
            Fx25.hexDump(frameBuf, frameLen);
          }

          // Create correction info for FX.25
          final CorrectionInfo corrInfo = CorrectionInfo()
            ..correctionType = derrors
            ..fecType = FecType.fx25
            ..correctedBitPositions = <int>[]
            ..rsSymbolsCorrected = derrors
            ..fx25CorrelationTag = f.ctagNum
            ..frameLengthBits = f.kDataRadio * 8
            ..frameLengthBytes = frameLen - 2
            ..originalCrc = actualFcs
            ..expectedCrc = expectedFcs
            ..crcValid = true;

          // Pass to MultiModem for further processing
          if (_multiModem != null) {
            // Create a simple audio level (would be from demod in real implementation)
            final ALevel alevel = ALevel();

            _multiModem.processRecFrame(
              chan,
              subchan,
              slice,
              frameBuf,
              frameLen - 2,
              alevel,
              derrors,
              FecType.fx25,
              f.ctagNum,
              corrInfo,
            );
          } else {
            // print(
            //   'FX.25[$chan.$slice]: REJECT - no MultiModem sink to deliver '
            //   'frame to.',
            // );
          }
        } else {
          // Most likely cause is defective sender software
          // print(
          //   'FX.25[$chan.$slice]: REJECT - Bad FCS on extracted frame '
          //   '(got 0x${actualFcs.toRadixString(16).padLeft(4, '0')}, '
          //   'expected 0x${expectedFcs.toRadixString(16).padLeft(4, '0')}), '
          //   'frame: ${_hexInline(frameBuf, frameLen - 2)}',
          // );
          if (Fx25.getDebugLevel() >= 3) {
            Fx25.hexDump(f.block, f.dlen);
            Fx25.hexDump(frameBuf, frameLen);
          }
        }
      } else {
        // Most likely cause is defective sender software
        // print(
        //   'FX.25[$chan.$slice]: REJECT - extracted frame ($frameLen bytes) is '
        //   'shorter than the minimum length (17), frame dropped.',
        // );
        if (Fx25.getDebugLevel() >= 3) {
          Fx25.hexDump(f.block, f.dlen);
          Fx25.hexDump(frameBuf, frameLen);
        }
      }
    } else {
      // print(
      //   'FX.25[$chan.$slice]: REJECT - RS FEC failed, too many errors '
      //   '(tag 0x${f.ctagNum.toRadixString(16).padLeft(2, '0')}), block dropped.',
      // );
    }
  }

  /// Remove HDLC bit stuffing and surrounding flag delimiters.
  ///
  /// Returns the number of bytes in [frameBuf] including FCS, or 0 if error.
  int _unstuff(
    int chan,
    int subchan,
    int slice,
    Uint8List pin,
    int ilen,
    Uint8List frameBuf,
  ) {
    int patDet = 0; // Pattern detector
    int oacc = 0; // Accumulator for a byte out
    int olen = 0; // Number of good bits in oacc
    int frameLen = 0; // Number of bytes accumulated, including CRC
    int pinIndex = 0;

    if (pin[0] != 0x7e) {
      // print(
      //   'FX.25[$chan.$slice]: REJECT - data section did not start with 0x7e '
      //   'flag.',
      // );
      if (Fx25.getDebugLevel() >= 3) Fx25.hexDump(pin, ilen);
      return 0;
    }

    // Skip over leading flag byte(s)
    while (ilen > 0 && pin[pinIndex] == 0x7e) {
      ilen--;
      pinIndex++;
    }

    for (int i = 0; i < ilen; pinIndex++, i++) {
      for (int imask = 0x01; imask != 0; imask = (imask << 1) & 0xFF) {
        final int dbit = (pin[pinIndex] & imask) != 0 ? 1 : 0;

        // Shift the most recent eight bits through the pattern detector
        patDet = (patDet >> 1) & 0xFF;
        patDet |= (dbit << 7);

        if (patDet == 0xfe) {
          // print(
          //   'FX.25[$chan.$slice]: REJECT - invalid frame, seven \'1\' bits in a '
          //   'row.',
          // );
          if (Fx25.getDebugLevel() >= 3) Fx25.hexDump(pin, ilen);
          return 0;
        }

        if (dbit != 0) {
          oacc = (oacc >> 1) & 0xFF;
          oacc |= 0x80;
        } else {
          if (patDet == 0x7e) {
            // "flag" pattern - End of frame
            if (olen == 7) {
              return frameLen; // Whole number of bytes in result including CRC
            } else {
              // print(
              //   'FX.25[$chan.$slice]: REJECT - not a whole number of bytes '
              //   '(olen=$olen).',
              // );
              if (Fx25.getDebugLevel() >= 3) Fx25.hexDump(pin, ilen);
              return 0;
            }
          } else if ((patDet >> 2) == 0x1f) {
            // Five '1' bits in a row, followed by '0'. Discard the '0'
            continue;
          }
          oacc = (oacc >> 1) & 0xFF;
        }

        olen++;
        if ((olen & 8) != 0) {
          olen = 0;
          frameBuf[frameLen++] = oacc;
        }
      }
    }

    // print(
    //   'FX.25[$chan.$slice]: REJECT - terminating flag not found before end of '
    //   'block.',
    // );
    if (Fx25.getDebugLevel() >= 3) Fx25.hexDump(pin, ilen);
    return 0;
  }

  /// Count number of '1' bits in a 64-bit integer.
  int _popCount(int x) {
    int count = 0;
    while (x != 0) {
      count++;
      x &= x - 1; // Clear the least significant bit set
    }
    return count;
  }

  /// Compact single-line hex dump of the first [len] bytes of [b], for logging.
  static String _hexInline(Uint8List b, int len) {
    final StringBuffer sb = StringBuffer();
    final int n = len < b.length ? len : b.length;
    for (int i = 0; i < n; i++) {
      sb.write(b[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString().toUpperCase();
  }
}
