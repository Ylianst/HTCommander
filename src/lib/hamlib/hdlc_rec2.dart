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
// hdlc_rec2.dart - HDLC frame extraction with error correction
// This file extracts HDLC frames from a block of bits after someone
// else has done the work of pulling it out from between the
// special "flag" sequences.
//
// Ported from C# HamLib/HdlcRec2.cs
//

import 'dart:typed_data';

import 'audio_config.dart';
import 'correction_info.dart';
import 'fcs_calc.dart';
import 'hdlc_rec.dart';
import 'ihdlc_receiver.dart';
import 'multi_modem.dart';

/// Retry/fix-up attempt levels for bad CRC frames.
///
/// Ported as an int-constant holder (rather than an enum) because the
/// surrounding code stores and compares these as plain integers.
class RetryType {
  RetryType._();
  static const int none = 0;
  static const int invertSingle = 1;
  static const int invertDouble = 2;
  static const int invertTriple = 3;
  static const int invertTwoSep = 4;
  static const int max = 5;
}

/// Sanity test levels to apply after fixing bits.
enum SanityTest {
  aprs, // Must look like APRS
  ax25, // Must have valid AX.25 addresses
  none, // No checking
}

/// Retry mode - how bits are modified.
enum RetryMode {
  contiguous, // Modify adjacent bits
  separated, // Modify non-adjacent bits
}

/// Type of retry operation.
enum RetryOperation {
  none,
  swap, // Invert bits
}

/// Configuration for retry/fix-up attempts.
class RetryConfig {
  int retry = RetryType.none;
  RetryMode mode = RetryMode.contiguous;
  RetryOperation type = RetryOperation.none;

  // For separated mode
  int bitIdxA = 0;
  int bitIdxB = 0;
  int bitIdxC = 0;

  // For contiguous mode
  int bitIdx = 0;
  int numBits = 0;

  int insertValue = 0;
}

/// Audio configuration for HDLC decoder.
class HdlcAudioConfig {
  int fixBits = RetryType.none;
  SanityTest sanityTest = SanityTest.aprs;
  bool passAll = false;
  ModemType modemType = ModemType.afsk;
  int numSubchan = 1;
}

/// HDLC state for decoding a single frame.
class _HdlcState2 {
  int prevRaw = 0; // Previous raw bit for transition detection
  bool isScrambled = false; // G3RUH scrambling flag
  int lfsr = 0; // Descrambler shift register
  int prevDescram = 0; // Previous descrambled bit
  int patDet = 0; // 8-bit pattern detector
  int oAcc = 0; // Octet accumulator
  int oLen = 0; // Number of bits in accumulator
  late Uint8List frameBuffer; // Frame being assembled
  int frameLen = 0; // Current frame length

  static const int _maxFrameLen = 2048 + 2;

  _HdlcState2() {
    frameBuffer = Uint8List(_maxFrameLen);
  }
}

/// Event arguments for decoded HDLC frame (legacy event).
class HdlcFrameEventArgs {
  int channel = 0;
  int subchannel = 0;
  int slice = 0;
  late Uint8List frame;
  int frameLength = 0;
  AudioLevel audioLevel = AudioLevel();
  int retries = RetryType.none;
  CorrectionInfo? correctionInfo;
}

/// HDLC frame receiver with advanced error correction (Version 2).
class HdlcRec2 implements IHdlcReceiver {
  static const int _minFrameLen = 8 + 2; // AX25_MIN_PACKET_LEN + 2 for FCS
  static const int _maxFrameLen = 2048 + 2; // AX25_MAX_PACKET_LEN + 2 for FCS

  List<HdlcAudioConfig>? _audioConfig;
  RawReceivedBitBuffer? _currentBlock;
  late _HdlcState2 _currentState;
  final List<int> _allReceivedBits = <int>[];
  final List<int> _allDecodedBits = <int>[];

  final List<void Function(FrameReceivedEventArgs)> _frameReceivedListeners =
      [];
  final List<void Function(HdlcFrameEventArgs)> _frameDecodedListeners = [];

  /// Register a frame received handler (mirror of C# `FrameReceived +=`).
  void addFrameReceived(void Function(FrameReceivedEventArgs) handler) {
    _frameReceivedListeners.add(handler);
  }

  /// Register a legacy frame decoded handler (mirror of C# `FrameDecoded +=`).
  void addFrameDecoded(void Function(HdlcFrameEventArgs) handler) {
    _frameDecodedListeners.add(handler);
  }

  /// Initialize HDLC receiver with audio configuration (compatible with HdlcRec).
  void init(AudioConfig audioConfig) {
    _audioConfig = List<HdlcAudioConfig>.generate(
      AudioConfig.maxRadioChannels,
      (i) => HdlcAudioConfig()
        ..fixBits = RetryType
            .invertTwoSep // Enable bit error correction
        ..sanityTest = SanityTest.aprs
        ..passAll = false
        ..modemType = audioConfig.channels[i].modemType
        ..numSubchan = audioConfig.channels[i].numSubchan,
    );

    _currentState = _HdlcState2();
  }

  /// Initialize HDLC receiver with audio configuration (legacy).
  void initWithConfig(List<HdlcAudioConfig> audioConfig) {
    _audioConfig = audioConfig;
    _currentState = _HdlcState2();
  }

  /// Process a single received bit (IHdlcReceiver interface).
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
    // Store raw bits for debugging
    _allReceivedBits.add(raw);

    // Initialize block if needed
    _currentBlock ??= RawReceivedBitBuffer(
      chan,
      subchan,
      slice,
      isScrambled,
      0,
      0,
    );

    // NRZI decode for debugging
    final int dbit = (raw == _currentState.prevRaw) ? 1 : 0;
    _currentState.prevRaw = raw;
    _allDecodedBits.add(dbit);

    // Check for flag pattern by accumulating bits
    _currentState.patDet = (_currentState.patDet >> 1) & 0xFF;
    if (dbit != 0) _currentState.patDet |= 0x80;

    // Append raw bit to buffer (TryDecode will do NRZI again)
    _currentBlock!.appendBit(raw);

    // Check for flag pattern 01111110 (0x7e)
    if (_currentState.patDet == 0x7e) {
      // Remove last 8 bits (the flag itself)
      _currentBlock!.chop8();

      if (_currentBlock!.length >= _minFrameLen * 8) {
        // Process the frame (C# uses a thread pool; here it is synchronous).
        _currentBlock!.audioLevel = AudioLevel(0, 0, 0);
        final RawReceivedBitBuffer blockToProcess = _currentBlock!;
        processBlock(blockToProcess);

        // Create a NEW buffer for the next frame with preserved scrambler state.
        _currentBlock = RawReceivedBitBuffer(
          chan,
          subchan,
          slice,
          isScrambled,
          _currentState.lfsr,
          _currentState.prevDescram,
        );
      } else {
        // Start of frame - clear buffer
        _currentBlock!.clear(
          isScrambled,
          _currentState.lfsr,
          _currentState.prevDescram,
        );
      }

      // Append the last bit of the flag to the new/cleared buffer.
      _currentBlock!.appendBit(_currentState.prevRaw);
    }
    // Check for loss of signal (7-8 ones)
    else if (_currentState.patDet == 0xfe) {
      _currentBlock!.clear(isScrambled, 0, 0);
      _currentState.prevRaw = raw;
    }
  }

  /// DCD change notification (IHdlcReceiver interface).
  @override
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    // Not used in HdlcRec2
  }

  /// Get all bits received (for debugging compatibility with HdlcRec).
  List<int> getAllReceivedBits() => _allReceivedBits;

  /// Get all bits after NRZI decoding (for debugging compatibility with HdlcRec).
  List<int> getAllDecodedBits() => _allDecodedBits;

  /// Process a block of raw bits extracted between flag patterns.
  void processBlock(RawReceivedBitBuffer block) {
    final int chan = block.chan;
    final int subchan = block.subchan;
    final int slice = block.slice;
    final AudioLevel alevel = block.audioLevel;

    final List<HdlcAudioConfig>? cfg = _audioConfig;
    if (cfg == null || chan >= cfg.length) return;

    // Simple HDLC frame decoding (like HdlcRec.ProcessRawBits)
    final Uint8List frame = Uint8List(_maxFrameLen);
    int frameLen = 0;
    int acc = 0;
    int bitCount = 0;
    int onesCount = 0;
    int prevRaw = block.getBit(0); // Initialize with first bit
    bool skipNext = false;

    for (int i = 1; i < block.length; i++) {
      final int raw = block.getBit(i);

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
        _processReceivedFrame(
          chan,
          subchan,
          slice,
          frame,
          frameLen - 2,
          alevel,
          RetryType.none,
          null,
        );
      } else {
        // CRC failed - try to fix errors by flipping bits
        final int fixBits = cfg[chan].fixBits;

        if (fixBits > RetryType.none) {
          if (!_tryToFixQuickNow(block, chan, subchan, slice, alevel)) {
            if (cfg[chan].passAll) {
              _processReceivedFrame(
                chan,
                subchan,
                slice,
                frame,
                frameLen - 2,
                alevel,
                RetryType.max,
                null,
              );
            }
          }
        }
      }
    }
  }

  /// Attempt quick fix-up techniques.
  bool _tryToFixQuickNow(
    RawReceivedBitBuffer block,
    int chan,
    int subchan,
    int slice,
    AudioLevel alevel,
  ) {
    final int len = block.length;
    final int fixBits = _audioConfig![chan].fixBits;

    final RetryConfig retryConfig = RetryConfig()..mode = RetryMode.contiguous;

    // Try inverting one bit
    if (fixBits < RetryType.invertSingle) return false;

    retryConfig.type = RetryOperation.swap;
    retryConfig.retry = RetryType.invertSingle;
    retryConfig.numBits = 1;

    for (int i = 0; i < len; i++) {
      retryConfig.bitIdx = i;
      if (_tryDecode(block, chan, subchan, slice, alevel, retryConfig, false)) {
        return true;
      }
    }

    // Try inverting two adjacent bits
    if (fixBits < RetryType.invertDouble) return false;

    retryConfig.retry = RetryType.invertDouble;
    retryConfig.numBits = 2;

    for (int i = 0; i < len - 1; i++) {
      retryConfig.bitIdx = i;
      if (_tryDecode(block, chan, subchan, slice, alevel, retryConfig, false)) {
        return true;
      }
    }

    /*
    // Try inverting three adjacent bits
    if (fixBits < RetryType.invertTriple) return false;

    retryConfig.retry = RetryType.invertTriple;
    retryConfig.numBits = 3;

    for (int i = 0; i < len - 2; i++) {
      retryConfig.bitIdx = i;
      if (_tryDecode(block, chan, subchan, slice, alevel, retryConfig, false)) {
        return true;
      }
    }

    // Try inverting two non-adjacent bits
    if (fixBits < RetryType.invertTwoSep) return false;

    retryConfig.mode = RetryMode.separated;
    retryConfig.type = RetryOperation.swap;
    retryConfig.retry = RetryType.invertTwoSep;
    retryConfig.bitIdxC = -1;

    for (int i = 0; i < len - 2; i++) {
      retryConfig.bitIdxA = i;

      for (int j = i + 2; j < len; j++) {
        retryConfig.bitIdxB = j;
        if (_tryDecode(block, chan, subchan, slice, alevel, retryConfig, false)) {
          return true;
        }
      }
    }
    */

    return false;
  }

  /// Check if a bit is modified in contiguous mode.
  static bool _isContigBitModified(int bitIdx, RetryConfig retryConfig) {
    return bitIdx >= retryConfig.bitIdx &&
        bitIdx < retryConfig.bitIdx + retryConfig.numBits;
  }

  /// Check if a bit is modified in separated mode.
  static bool _isSepBitModified(int bitIdx, RetryConfig retryConfig) {
    return bitIdx == retryConfig.bitIdxA ||
        bitIdx == retryConfig.bitIdxB ||
        bitIdx == retryConfig.bitIdxC;
  }

  /// Try to decode a frame with specified bit modifications.
  bool _tryDecode(
    RawReceivedBitBuffer block,
    int chan,
    int subchan,
    int slice,
    AudioLevel alevel,
    RetryConfig retryConfig,
    bool passall,
  ) {
    final _HdlcState2 h2 = _HdlcState2();
    final int blen = block.length;

    // Track which bits were corrected
    final List<int> correctedBits = <int>[];

    if (retryConfig.type == RetryOperation.swap) {
      if (retryConfig.mode == RetryMode.contiguous) {
        for (int b = 0; b < retryConfig.numBits; b++) {
          correctedBits.add(retryConfig.bitIdx + b);
        }
      } else if (retryConfig.mode == RetryMode.separated) {
        correctedBits.add(retryConfig.bitIdxA);
        correctedBits.add(retryConfig.bitIdxB);
        if (retryConfig.bitIdxC >= 0) {
          correctedBits.add(retryConfig.bitIdxC);
        }
      }
    }

    h2.isScrambled = block.isScrambled;
    h2.prevDescram = block.prevDescram;
    h2.lfsr = block.descramState;
    h2.prevRaw = block.getBit(0); // Last bit of opening flag

    // Check if first bit should be modified
    if ((retryConfig.mode == RetryMode.contiguous &&
            _isContigBitModified(0, retryConfig)) ||
        (retryConfig.mode == RetryMode.separated &&
            _isSepBitModified(0, retryConfig))) {
      h2.prevRaw = h2.prevRaw == 0 ? 1 : 0;
    }

    h2.patDet = 0;
    h2.oAcc = 0;
    h2.oLen = 0;
    h2.frameLen = 0;

    final RetryMode retryMode = retryConfig.mode;
    final RetryOperation retryOp = retryConfig.type;
    final int retry = retryConfig.retry;

    // Process all bits
    for (int i = 1; i < blen; i++) {
      int raw = block.getBit(i);

      // Apply bit modifications if needed
      if (retry == RetryType.invertTwoSep) {
        if (_isSepBitModified(i, retryConfig)) {
          raw = raw == 0 ? 1 : 0;
        }
      } else if (retryMode == RetryMode.contiguous) {
        if (retryOp == RetryOperation.swap) {
          if (_isContigBitModified(i, retryConfig)) {
            raw = raw == 0 ? 1 : 0;
          }
        }
      }

      // Shift through pattern detector
      h2.patDet = (h2.patDet >> 1) & 0xFF;

      // NRZI decoding
      int dbit;
      if (h2.isScrambled) {
        final int descram = _descramble(raw, h2);
        dbit = (descram == h2.prevDescram) ? 1 : 0;
        h2.prevDescram = descram;
        h2.prevRaw = raw;
      } else {
        dbit = (raw == h2.prevRaw) ? 1 : 0;
        h2.prevRaw = raw;
      }

      if (dbit != 0) {
        h2.patDet |= 0x80;

        // Abort pattern: 7 ones in a row
        if (h2.patDet == 0xfe) return false;

        h2.oAcc = (h2.oAcc >> 1) & 0xFF;
        h2.oAcc |= 0x80;
      } else {
        // Flag pattern: 01111110
        if (h2.patDet == 0x7e) return false;

        // Bit stuffing: 5 ones followed by 0
        if ((h2.patDet >> 2) == 0x1f) continue;

        h2.oAcc = (h2.oAcc >> 1) & 0xFF;
      }

      // Accumulate bits into octets
      h2.oLen++;

      if ((h2.oLen & 8) != 0) {
        h2.oLen = 0;

        if (h2.frameLen < _maxFrameLen) {
          h2.frameBuffer[h2.frameLen] = h2.oAcc;
          h2.frameLen++;
        }
      }
    }

    // Check if we have a complete frame
    if (h2.oLen == 0 && h2.frameLen >= _minFrameLen) {
      final int actualFcs =
          (h2.frameBuffer[h2.frameLen - 2] |
              (h2.frameBuffer[h2.frameLen - 1] << 8)) &
          0xFFFF;
      final int expectedFcs = FcsCalc.calculate(
        h2.frameBuffer,
        h2.frameLen - 2,
      );

      // Create correction info
      final CorrectionInfo corrInfo = CorrectionInfo()
        ..correctionType = retryConfig.retry
        ..fecType = FecType.none
        ..correctedBitPositions = correctedBits
        ..rsSymbolsCorrected = -1
        ..fx25CorrelationTag = -1
        ..frameLengthBits = blen
        ..frameLengthBytes = h2.frameLen - 2
        ..originalCrc = actualFcs
        ..expectedCrc = expectedFcs
        ..crcValid = (actualFcs == expectedFcs);

      if (actualFcs == expectedFcs &&
          _audioConfig![chan].modemType == ModemType.ais) {
        // AIS sanity check
        final int msgType = (h2.frameBuffer[0] >> 2) & 0x3f;
        if (_aisCheckLength(msgType, h2.frameLen - 2)) {
          _processReceivedFrame(
            chan,
            subchan,
            slice,
            h2.frameBuffer,
            h2.frameLen - 2,
            alevel,
            retryConfig.retry,
            corrInfo,
          );
          return true;
        }
        return false;
      } else if (actualFcs == expectedFcs &&
          _sanityCheck(
            h2.frameBuffer,
            h2.frameLen - 2,
            retryConfig.retry,
            _audioConfig![chan].sanityTest,
          )) {
        _processReceivedFrame(
          chan,
          subchan,
          slice,
          h2.frameBuffer,
          h2.frameLen - 2,
          alevel,
          retryConfig.retry,
          corrInfo,
        );
        return true;
      } else if (passall) {
        if (retry == RetryType.none && retryOp == RetryOperation.none) {
          corrInfo.correctionType = RetryType.max;
          corrInfo.crcValid = false;
          _processReceivedFrame(
            chan,
            subchan,
            slice,
            h2.frameBuffer,
            h2.frameLen - 2,
            alevel,
            RetryType.max,
            corrInfo,
          );
          return true;
        }
      }
    }

    return false;
  }

  /// Descramble a bit for G3RUH/K9NG scrambling.
  int _descramble(int input, _HdlcState2 h) {
    final int bit16 = (h.lfsr >> 16) & 1;
    final int bit11 = (h.lfsr >> 11) & 1;
    final int output = (input ^ bit16 ^ bit11) & 1;
    h.lfsr = ((h.lfsr << 1) | (input & 1)) & 0x1ffff;
    return output;
  }

  /// Perform sanity check on decoded frame.
  bool _sanityCheck(
    Uint8List buf,
    int blen,
    int bitsFlipped,
    SanityTest sanityTest,
  ) {
    // No sanity check if we didn't try fixing the data
    if (bitsFlipped == RetryType.none) return true;

    // No sanity check requested
    if (sanityTest == SanityTest.none) return true;

    // Check address part is multiple of 7
    int alen = 0;
    for (int j = 0; j < blen && alen == 0; j++) {
      if ((buf[j] & 0x01) != 0) {
        alen = j + 1;
      }
    }

    if (alen % 7 != 0) return false;

    // Need at least 2 addresses, max 10 (dest, source, 8 digipeaters)
    if (alen ~/ 7 < 2 || alen ~/ 7 > 10) return false;

    // Check addresses contain only valid characters
    for (int j = 0; j < alen; j += 7) {
      final List<int> addr = List<int>.filled(6, 0);
      for (int k = 0; k < 6; k++) {
        addr[k] = buf[j + k] >> 1;
      }

      // First character must be letter or digit
      if (!_isUpper(addr[0]) && !_isDigit(addr[0])) return false;

      // Rest can be letter, digit, or space
      for (int k = 1; k < 6; k++) {
        if (!_isUpper(addr[k]) && !_isDigit(addr[k]) && addr[k] != 0x20) {
          return false;
        }
      }
    }

    // That's good enough for AX.25
    if (sanityTest == SanityTest.ax25) return true;

    // APRS requires 0x03 and 0xf0
    if (alen >= blen || buf[alen] != 0x03 || buf[alen + 1] != 0xf0) {
      return false;
    }

    // Check for valid characters in info field
    for (int j = alen + 2; j < blen; j++) {
      final int ch = buf[j];

      if (!((ch >= 0x1c && ch <= 0x7f) ||
          ch == 0x0a ||
          ch == 0x0d ||
          ch == 0x80 ||
          ch == 0x9f ||
          ch == 0xc2 ||
          ch == 0xb0 ||
          ch == 0xf8)) {
        return false;
      }
    }

    return true;
  }

  static bool _isUpper(int ch) => ch >= 0x41 && ch <= 0x5a;
  static bool _isDigit(int ch) => ch >= 0x30 && ch <= 0x39;

  /// Simple AIS message length check.
  bool _aisCheckLength(int msgType, int len) {
    // Simplified - actual implementation would have proper AIS message length table
    return len >= 14 && len <= 256;
  }

  /// Process successfully decoded frame.
  void _processReceivedFrame(
    int chan,
    int subchan,
    int slice,
    Uint8List frame,
    int frameLen,
    AudioLevel alevel,
    int retries,
    CorrectionInfo? correctionInfo,
  ) {
    _onFrameReceived(
      FrameReceivedEventArgs()
        ..channel = chan
        ..subchannel = subchan
        ..slice = slice
        ..frame = frame
        ..frameLength = frameLen
        ..audioLevel = alevel
        ..correctionInfo = correctionInfo,
    );
  }

  void _onFrameReceived(FrameReceivedEventArgs e) {
    for (final l in List.of(_frameReceivedListeners)) {
      l(e);
    }
  }

  /// Raise the legacy frame decoded event.
  void onFrameDecoded(HdlcFrameEventArgs e) {
    for (final l in List.of(_frameDecodedListeners)) {
      l(e);
    }
  }
}
