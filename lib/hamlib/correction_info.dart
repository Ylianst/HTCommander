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
// correction_info.dart - Detailed information about packet error correction
//
// Ported from C# HamLib/CorrectionInfo.cs
//

import 'hdlc_rec2.dart' show RetryType;
import 'multi_modem.dart' show FecType;

/// Detailed information about error correction applied to a packet.
class CorrectionInfo {
  /// Type of error correction applied (see [RetryType]).
  int correctionType;

  /// Forward Error Correction type used (if any).
  FecType fecType;

  /// Bit positions that were inverted (for HDLC bit-flip corrections).
  List<int> correctedBitPositions;

  /// Number of Reed-Solomon symbols/bytes corrected (for FX.25/IL2P).
  /// -1 if not applicable or RS decoding failed.
  int rsSymbolsCorrected;

  /// FX.25 correlation tag number (-1 if not FX.25).
  int fx25CorrelationTag;

  /// Total frame length in bits (for BER calculation).
  int frameLengthBits;

  /// Total frame length in bytes.
  int frameLengthBytes;

  /// Original CRC value from received frame.
  int originalCrc;

  /// Expected CRC value after correction.
  int expectedCrc;

  /// Whether the CRC matched (true) or was passed through with bad CRC (false).
  bool crcValid;

  CorrectionInfo()
    : correctionType = RetryType.none,
      fecType = FecType.none,
      correctedBitPositions = <int>[],
      rsSymbolsCorrected = -1,
      fx25CorrelationTag = -1,
      frameLengthBits = 0,
      frameLengthBytes = 0,
      originalCrc = 0,
      expectedCrc = 0,
      crcValid = true;

  /// Calculate bit error rate (BER) based on corrections.
  double calculateBER() {
    if (frameLengthBits <= 0) return 0.0;

    int bitsFlipped = correctedBitPositions.length;

    // For FX.25, estimate bits corrected (8 bits per symbol)
    if (fecType == FecType.fx25 && rsSymbolsCorrected > 0) {
      bitsFlipped = rsSymbolsCorrected * 8;
    }

    return bitsFlipped / frameLengthBits;
  }

  /// Get a human-readable description of the correction.
  String getDescription() {
    if (fecType == FecType.fx25) {
      if (rsSymbolsCorrected == 0) {
        return 'FX.25: No errors detected';
      } else if (rsSymbolsCorrected > 0) {
        return 'FX.25: Corrected $rsSymbolsCorrected symbol(s), Tag=0x${_hex2(fx25CorrelationTag)}';
      } else {
        return 'FX.25: Too many errors to correct';
      }
    } else if (fecType == FecType.il2p) {
      if (rsSymbolsCorrected == 0) {
        return 'IL2P: No errors detected';
      } else if (rsSymbolsCorrected > 0) {
        return 'IL2P: Corrected $rsSymbolsCorrected symbol(s)';
      } else {
        return 'IL2P: Too many errors to correct';
      }
    } else {
      switch (correctionType) {
        case RetryType.none:
          return crcValid ? 'No correction needed' : 'Bad CRC (passed through)';
        case RetryType.invertSingle:
          return 'Fixed by inverting 1 bit at position ${correctedBitPositions.isEmpty ? 0 : correctedBitPositions.first}';
        case RetryType.invertDouble:
          return 'Fixed by inverting 2 adjacent bits at positions ${correctedBitPositions.join(",")}';
        case RetryType.invertTriple:
          return 'Fixed by inverting 3 adjacent bits at positions ${correctedBitPositions.join(",")}';
        case RetryType.invertTwoSep:
          return 'Fixed by inverting 2 separated bits at positions ${correctedBitPositions.join(",")}';
        case RetryType.max:
          return 'Bad CRC (passed through)';
        default:
          return 'Unknown correction type';
      }
    }
  }

  /// Get statistics summary for logging.
  @override
  String toString() {
    final String fecInfo = fecType != FecType.none
        ? ', FEC=${fecType.name}'
        : '';
    final String berInfo = frameLengthBits > 0
        ? ', BER=${calculateBER().toStringAsExponential(2)}'
        : '';
    return 'Correction: ${getDescription()}$fecInfo$berInfo';
  }

  static String _hex2(int v) =>
      v.toRadixString(16).padLeft(2, '0').toUpperCase();
}
