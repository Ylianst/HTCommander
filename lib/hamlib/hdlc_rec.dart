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
// hdlc_rec.dart - HDLC frame reception and decoding
// https://www.ietf.org/rfc/rfc1549.txt
//
// Ported from C# HamLib/HdlcRec.cs
//

import 'dart:typed_data';

import 'audio_config.dart';
import 'correction_info.dart';
import 'fcs_calc.dart';
import 'ihdlc_receiver.dart';

/// Audio level information for received frames.
class AudioLevel {
  int rec; // Received signal level
  int mark; // Mark tone level
  int space; // Space tone level

  AudioLevel([this.rec = 9999, this.mark = 9999, this.space = 9999]);
}

/// Holder used in place of the C# `ref long pllNudgeTotal, ref int pllSymbolCount`.
class PllNudge {
  int total;
  int count;
  PllNudge([this.total = 0, this.count = 0]);
}

/// Raw Received Bit Buffer - stores raw bits from demodulator.
class RawReceivedBitBuffer {
  RawReceivedBitBuffer? next;
  int chan;
  int subchan;
  int slice;
  AudioLevel audioLevel = AudioLevel();
  double speedError = 0;
  int length = 0;
  bool isScrambled = false;
  int descramState = 0;
  int prevDescram = 0;

  static const int _maxNumBits =
      ((AudioConfig.maxRadioChannels * 2048 + 2) * 8 * 6 ~/ 5);
  final Uint8List _data = Uint8List(_maxNumBits);

  RawReceivedBitBuffer(
    this.chan,
    this.subchan,
    this.slice,
    bool isScrambled,
    int descramState,
    int prevDescram,
  ) {
    clear(isScrambled, descramState, prevDescram);
  }

  void clear(bool isScrambled, int descramState, int prevDescram) {
    next = null;
    audioLevel = AudioLevel();
    speedError = 0;
    length = 0;
    this.isScrambled = isScrambled;
    this.descramState = descramState;
    this.prevDescram = prevDescram;
  }

  void appendBit(int val) {
    if (length >= _maxNumBits) return; // Silently discard if full
    _data[length] = val & 0xFF;
    length++;
  }

  int getBit(int index) {
    if (index >= length) return 0;
    return _data[index];
  }

  void chop8() {
    if (length >= 8) length -= 8;
  }

  Uint8List getData() {
    return Uint8List.sublistView(_data, 0, length);
  }
}

/// HDLC frame receiver state for a single channel/subchannel/slice.
class _HdlcState {
  int prevRaw = 0; // Previous raw bit for NRZI
  int lfsr = 0; // Descrambler shift register for 9600 baud
  int prevDescram = 0; // Previous descrambled bit for 9600 baud
  int patDet = 0; // 8-bit pattern detector shift register
  int flag4Det = 0; // Last 32 raw bits for flag detection
  int oAcc = 0; // Octet accumulator
  int oLen = -1; // Number of bits in accumulator (-1 = disabled)
  late Uint8List frameBuffer; // Frame being assembled
  int frameLen = 0; // Length of frame
  RawReceivedBitBuffer? rrbb; // Raw bit buffer
  int easAcc = 0; // EAS accumulator (64 bits)
  bool easGathering = false; // EAS decoding in progress
  bool easPlusFound = false; // "+" seen in EAS
  int easFieldsAfterPlus = 0; // Fields after "+" in EAS

  _HdlcState() {
    frameBuffer = Uint8List(AudioConfig.maxRadioChannels * 2048 + 2);
    oLen = -1;
  }
}

/// Event arguments for frame received event.
class FrameReceivedEventArgs {
  int channel = 0;
  int subchannel = 0;
  int slice = 0;
  late Uint8List frame;
  int frameLength = 0;
  AudioLevel audioLevel = AudioLevel();
  CorrectionInfo? correctionInfo;
}

/// Event arguments for DCD changed event.
class DcdChangedEventArgs {
  int channel = 0;
  bool state = false;
}

/// HDLC frame receiver - extracts frames from bit stream.
class HdlcRec implements IHdlcReceiver {
  static const int _minFrameLen = 15 + 2; // AX25_MIN_PACKET_LEN + 2 for FCS
  static const int _maxFrameLen = 2048 + 2; // AX25_MAX_PACKET_LEN + 2 for FCS

  late List<List<List<_HdlcState?>>> _hdlcState;
  late List<int> _numSubchan;
  late List<List<int>> _compositeDcd;
  late AudioConfig _audioConfig;
  bool _wasInit = false;

  // Random number generator for BER injection
  int _seed = 1;
  static const int _myRandMax = 0x7fffffff;

  // Frame received listeners (mirror C# event with += semantics).
  final List<void Function(FrameReceivedEventArgs)> _frameReceivedListeners =
      [];
  final List<void Function(DcdChangedEventArgs)> _dcdChangedListeners = [];

  final List<int> _allReceivedBits = <int>[]; // raw bits for debugging
  final List<int> _allDecodedBits = <int>[]; // bits after NRZI decoding

  HdlcRec() {
    _hdlcState = List.generate(
      AudioConfig.maxRadioChannels,
      (_) => List.generate(
        AudioConfig.maxSubchannels,
        (_) => List<_HdlcState?>.filled(AudioConfig.maxSlicers, null),
      ),
    );
    _numSubchan = List<int>.filled(AudioConfig.maxRadioChannels, 0);
    _compositeDcd = List.generate(
      AudioConfig.maxRadioChannels,
      (_) => List<int>.filled(AudioConfig.maxSubchannels + 1, 0),
    );
  }

  /// Register a frame received handler (mirror of C# `FrameReceived +=`).
  void addFrameReceived(void Function(FrameReceivedEventArgs) handler) {
    _frameReceivedListeners.add(handler);
  }

  /// Register a DCD changed handler (mirror of C# `DcdChanged +=`).
  void addDcdChanged(void Function(DcdChangedEventArgs) handler) {
    _dcdChangedListeners.add(handler);
  }

  /// Initialize the HDLC receiver.
  void init(AudioConfig audioConfig) {
    _audioConfig = audioConfig;

    for (final row in _compositeDcd) {
      for (int i = 0; i < row.length; i++) {
        row[i] = 0;
      }
    }

    for (int ch = 0; ch < AudioConfig.maxRadioChannels; ch++) {
      if (_audioConfig.channelMedium[ch] == Medium.radio) {
        _numSubchan[ch] = _audioConfig.channels[ch].numSubchan;
        assert(
          _numSubchan[ch] >= 1 && _numSubchan[ch] <= AudioConfig.maxSubchannels,
        );

        for (int sub = 0; sub < _numSubchan[ch]; sub++) {
          for (int slice = 0; slice < AudioConfig.maxSlicers; slice++) {
            final _HdlcState h = _HdlcState();
            _hdlcState[ch][sub][slice] = h;
            h.oLen = -1;
            h.rrbb = RawReceivedBitBuffer(
              ch,
              sub,
              slice,
              _audioConfig.channels[ch].modemType == ModemType.scramble,
              h.lfsr,
              h.prevDescram,
            );
          }
        }
      }
    }

    _wasInit = true;
  }

  // ignore: unused_element
  int _myRand() {
    _seed = ((_seed * 1103515245 + 12345) & _myRandMax);
    return _seed;
  }

  /// Process a single received bit (main entry point).
  @override
  void recBit(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool isScrambled,
    int notUsedRemove,
  ) {
    recBitNew(
      chan,
      subchan,
      slice,
      raw,
      isScrambled,
      notUsedRemove,
      PllNudge(),
    );
  }

  /// Get all bits received (for debugging).
  List<int> getAllReceivedBits() => _allReceivedBits;

  /// Get all bits after NRZI decoding (for debugging).
  List<int> getAllDecodedBits() => _allDecodedBits;

  /// Process a single received bit with PLL tracking.
  void recBitNew(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool isScrambled,
    int notUsedRemove,
    PllNudge pll,
  ) {
    assert(_wasInit);
    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    assert(subchan >= 0 && subchan < AudioConfig.maxSubchannels);
    assert(slice >= 0 && slice < AudioConfig.maxSlicers);

    _allReceivedBits.add(raw);

    // EAS does not use HDLC
    if (_audioConfig.channels[chan].modemType == ModemType.eas) {
      _easRecBit(chan, subchan, slice, raw, notUsedRemove);
      return;
    }

    final _HdlcState h = _hdlcState[chan][subchan][slice]!;

    // NRZI decoding: 0 bit = transition, 1 bit = no change
    int dbit;
    if (isScrambled) {
      final int descram = _descramble(raw, h);
      dbit = (descram == h.prevDescram) ? 1 : 0;
      h.prevDescram = descram;
      h.prevRaw = raw;
    } else {
      dbit = (raw == h.prevRaw) ? 1 : 0;
      h.prevRaw = raw;
    }

    _allDecodedBits.add(dbit);

    // Shift bit through pattern detector
    h.patDet = (h.patDet >> 1) & 0xFF;
    if (dbit != 0) h.patDet |= 0x80;

    h.flag4Det = (h.flag4Det >> 1) & 0xFFFFFFFF;
    if (dbit != 0) h.flag4Det |= 0x80000000;

    h.rrbb!.appendBit(raw);

    // Check for flag pattern 01111110 (0x7e)
    if (h.patDet == 0x7e) {
      h.rrbb!.chop8();

      if (h.rrbb!.length >= _minFrameLen * 8) {
        // End of frame - calculate speed error if available
        double speedError = 0;
        if (pll.count > 0) {
          speedError =
              pll.total * 100.0 / (256.0 * 256.0 * 256.0 * 256.0) / pll.count +
              0.02;
        }
        h.rrbb!.speedError = speedError;

        h.rrbb!.audioLevel = AudioLevel(0, 0, 0); // Placeholder

        _processRawBits(h.rrbb!);
        h.rrbb = null;

        h.rrbb = RawReceivedBitBuffer(
          chan,
          subchan,
          slice,
          isScrambled,
          h.lfsr,
          h.prevDescram,
        );
      } else {
        // Start of frame
        pll.total = 0;
        pll.count = -1;
        h.rrbb!.clear(isScrambled, h.lfsr, h.prevDescram);
      }

      h.oLen = 0;
      h.frameLen = 0;
      h.rrbb!.appendBit(h.prevRaw);
    }
    // Check for loss of signal pattern (7 or 8 ones in a row)
    else if (h.patDet == 0xfe) {
      h.oLen = -1;
      h.frameLen = 0;
      h.rrbb!.clear(isScrambled, h.lfsr, h.prevDescram);
    }
    // Check for bit stuffing pattern (5 ones followed by 0)
    else if ((h.patDet & 0xfc) == 0x7c) {
      // Discard the stuffed 0 bit
    } else {
      // Accumulate bits into octets
      if (h.oLen >= 0) {
        h.oAcc = (h.oAcc >> 1) & 0xFF;
        if (dbit != 0) h.oAcc |= 0x80;
        h.oLen++;

        if (h.oLen == 8) {
          h.oLen = 0;
          if (h.frameLen < _maxFrameLen) {
            h.frameBuffer[h.frameLen] = h.oAcc;
            h.frameLen++;
          }
        }
      }
    }
  }

  /// Descramble a bit for 9600 baud G3RUH/K9NG scrambling.
  int _descramble(int input, _HdlcState h) {
    // Polynomial: x^17 + x^12 + 1
    final int bit16 = (h.lfsr >> 16) & 1;
    final int bit11 = (h.lfsr >> 11) & 1;
    final int output = (input ^ bit16 ^ bit11) & 1;
    h.lfsr = ((h.lfsr << 1) | (input & 1)) & 0x1ffff;
    return output;
  }

  /// Process raw bits buffer (simplified version).
  void _processRawBits(RawReceivedBitBuffer rrbb) {
    final Uint8List frame = Uint8List(_maxFrameLen);
    int frameLen = 0;
    int acc = 0;
    int bitCount = 0;
    int onesCount = 0;
    int prevRaw = rrbb.getBit(0); // Initialize with first bit
    bool skipNext = false;

    for (int i = 1; i < rrbb.length; i++) {
      final int raw = rrbb.getBit(i);

      // NRZI decode: no transition = 1, transition = 0
      final int dbit = (raw == prevRaw) ? 1 : 0;
      prevRaw = raw;

      if (skipNext) {
        skipNext = false;
        onesCount = 0;
        continue;
      }

      // Check for bit stuffing (5 ones in a row means next 0 is stuffed)
      if (dbit == 1) {
        onesCount++;
        if (onesCount == 5) {
          skipNext = true;
        }
      } else {
        onesCount = 0;
      }

      // Accumulate bits (LSB first)
      acc = (acc >> 1) & 0xFF;
      if (dbit != 0) acc |= 0x80;
      bitCount++;

      if (bitCount == 8) {
        if (frameLen < _maxFrameLen) frame[frameLen++] = acc;
        bitCount = 0;
        acc = 0;
      }
    }

    // Check if we have a valid frame
    if (frameLen >= _minFrameLen) {
      final int actualFcs =
          (frame[frameLen - 2] | (frame[frameLen - 1] << 8)) & 0xFFFF;
      final int expectedFcs = FcsCalc.calculate(frame, frameLen - 2);

      if (actualFcs == expectedFcs) {
        _onFrameReceived(
          rrbb.chan,
          rrbb.subchan,
          rrbb.slice,
          frame,
          frameLen - 2,
          rrbb.audioLevel,
        );
      }
    }
  }

  /// EAS (Emergency Alert System) bit receiver.
  void _easRecBit(int chan, int subchan, int slice, int raw, int futureUse) {
    final _HdlcState h = _hdlcState[chan][subchan][slice]!;

    // Accumulate most recent 64 bits
    h.easAcc = h.easAcc >>> 1;
    if (raw != 0) h.easAcc |= 0x8000000000000000;

    const int preambleZczc = 0x435a435aabababab;
    const int preambleNnnn = 0x4e4e4e4eabababab;
    const int easMaxLen = 268;

    bool done = false;

    if (h.easAcc == preambleZczc) {
      h.oLen = 0;
      h.easGathering = true;
      h.easPlusFound = false;
      h.easFieldsAfterPlus = 0;
      h.frameBuffer.fillRange(0, h.frameBuffer.length, 0);
      h.frameBuffer.setRange(0, 4, 'ZCZC'.codeUnits);
      h.frameLen = 4;
    } else if (h.easAcc == preambleNnnn) {
      h.oLen = 0;
      h.easGathering = true;
      h.frameBuffer.fillRange(0, h.frameBuffer.length, 0);
      h.frameBuffer.setRange(0, 4, 'NNNN'.codeUnits);
      h.frameLen = 4;
      done = true;
    } else if (h.easGathering) {
      h.oLen++;
      if (h.oLen == 8) {
        h.oLen = 0;
        final int ch = (h.easAcc >>> 56) & 0xFF;
        h.frameBuffer[h.frameLen++] = ch & 0xFF;

        // Validate character
        if (!((ch >= 0x20 && ch <= 0x7f) || ch == 0x0D || ch == 0x0A)) {
          h.easGathering = false;
          return;
        }
        if (h.frameLen > easMaxLen) {
          h.easGathering = false;
          return;
        }
        if (ch == 0x2B /* '+' */ ) {
          h.easPlusFound = true;
          h.easFieldsAfterPlus = 0;
        }
        if (h.easPlusFound && ch == 0x2D /* '-' */ ) {
          h.easFieldsAfterPlus++;
          if (h.easFieldsAfterPlus == 3) done = true;
        }
      }
    }

    if (done) {
      _onFrameReceived(
        chan,
        subchan,
        slice,
        h.frameBuffer,
        h.frameLen,
        AudioLevel(0, 0, 0),
      );
      h.easGathering = false;
    }
  }

  /// DCD (Data Carrier Detect) state change.
  @override
  void dcdChange(int chan, int subchan, int slice, bool state) {
    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    assert(subchan >= 0 && subchan <= AudioConfig.maxSubchannels);
    assert(slice >= 0 && slice < AudioConfig.maxSlicers);

    final bool old = dataDetectAny(chan);

    if (state) {
      _compositeDcd[chan][subchan] |= (1 << slice);
    } else {
      _compositeDcd[chan][subchan] &= ~(1 << slice);
    }

    final bool newState = dataDetectAny(chan);

    if (newState != old) {
      _onDcdChanged(chan, newState);
    }
  }

  /// Check if any decoder on this channel detects data.
  bool dataDetectAny(int chan) {
    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    for (int sc = 0; sc < _numSubchan[chan]; sc++) {
      if (_compositeDcd[chan][sc] != 0) return true;
    }
    return false;
  }

  void _onFrameReceived(
    int chan,
    int subchan,
    int slice,
    Uint8List frame,
    int frameLen,
    AudioLevel alevel,
  ) {
    if (_frameReceivedListeners.isEmpty) return;
    final FrameReceivedEventArgs e = FrameReceivedEventArgs()
      ..channel = chan
      ..subchannel = subchan
      ..slice = slice
      ..frame = frame
      ..frameLength = frameLen
      ..audioLevel = alevel;
    for (final l in List.of(_frameReceivedListeners)) {
      l(e);
    }
  }

  void _onDcdChanged(int chan, bool state) {
    if (_dcdChangedListeners.isEmpty) return;
    final DcdChangedEventArgs e = DcdChangedEventArgs()
      ..channel = chan
      ..state = state;
    for (final l in List.of(_dcdChangedListeners)) {
      l(e);
    }
  }
}
