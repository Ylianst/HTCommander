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
// hdlc_send.dart - HDLC frame encoding and transmission
//
// Ported from C# HamLib/HdlcSend.cs
//

import 'dart:typed_data';

import 'audio_config.dart';
import 'fcs_calc.dart';
import 'gen_tone.dart';

/// HDLC frame encoder for transmitting data.
class HdlcSend {
  final GenTone _genTone;
  // ignore: unused_field
  final AudioConfig _audioConfig;
  late List<int> _stuff;
  late List<int> _output;
  late List<int> _numberBitsSent;

  HdlcSend(this._genTone, this._audioConfig) {
    _stuff = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _output = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _numberBitsSent = List<int>.filled(AudioConfig.maxRadioChannels, 0);
  }

  /// Send a complete frame (wrapper for different layer 2 protocols).
  int sendFrame(int chan, Uint8List frameBuffer, int frameLen, bool badFcs) {
    // For now, we only support standard AX.25 HDLC.
    // FX.25 and IL2P could be added later.
    return _sendAx25Frame(chan, frameBuffer, frameLen, badFcs);
  }

  /// Send an AX.25 HDLC frame.
  int _sendAx25Frame(int chan, Uint8List fbuf, int flen, bool badFcs) {
    _numberBitsSent[chan] = 0;

    // Start flag
    _sendControlNrzi(chan, 0x7e);

    // Data bytes
    for (int j = 0; j < flen; j++) {
      _sendDataNrzi(chan, fbuf[j]);
    }

    // FCS (Frame Check Sequence)
    final int fcs = FcsCalc.calculate(fbuf, flen);

    if (badFcs) {
      // For testing - corrupt the FCS
      _sendDataNrzi(chan, (~fcs) & 0xff);
      _sendDataNrzi(chan, ((~fcs) >> 8) & 0xff);
    } else {
      _sendDataNrzi(chan, fcs & 0xff);
      _sendDataNrzi(chan, (fcs >> 8) & 0xff);
    }

    // End flag
    _sendControlNrzi(chan, 0x7e);

    return _numberBitsSent[chan];
  }

  /// Send preamble or postamble flags.
  int sendFlags(
    int chan,
    int numFlags,
    bool finish,
    void Function(int)? audioFlushCallback,
  ) {
    _numberBitsSent[chan] = 0;

    // For AX.25, send 0x7e flags
    for (int j = 0; j < numFlags; j++) {
      _sendControlNrzi(chan, 0x7e);
    }

    // Flush audio buffer if this is the end
    if (finish && audioFlushCallback != null) {
      audioFlushCallback(AudioConfig.channelToDevice(chan));
    }

    return _numberBitsSent[chan];
  }

  /// Send a control byte (like flags) - no bit stuffing, uses NRZI.
  void _sendControlNrzi(int chan, int x) {
    for (int i = 0; i < 8; i++) {
      _sendBitNrzi(chan, x & 1);
      x >>= 1;
    }
    _stuff[chan] = 0;
  }

  /// Send a data byte with bit stuffing and NRZI encoding.
  void _sendDataNrzi(int chan, int x) {
    for (int i = 0; i < 8; i++) {
      _sendBitNrzi(chan, x & 1);
      if ((x & 1) != 0) {
        _stuff[chan]++;
        if (_stuff[chan] == 5) {
          // Insert a 0 bit after five consecutive 1 bits
          _sendBitNrzi(chan, 0);
          _stuff[chan] = 0;
        }
      } else {
        _stuff[chan] = 0;
      }
      x >>= 1;
    }
  }

  /// Send a single bit with NRZI encoding.
  ///
  /// NRZI: data 1 bit -> no change, data 0 bit -> invert signal.
  void _sendBitNrzi(int chan, int b) {
    if (b == 0) {
      _output[chan] = _output[chan] == 0 ? 1 : 0;
    }

    // Generate the tone
    _genTone.putBit(chan, _output[chan]);

    _numberBitsSent[chan]++;
  }
}
