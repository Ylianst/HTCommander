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
// fx25_encode.dart - FX.25 Reed-Solomon encoding
//
// Ported from C# HamLib/Fx25Encode.cs (direct port of fx25_encode.c)
//

import 'dart:typed_data';

import 'fx25.dart';

/// FX.25 Reed-Solomon encoding operations.
class Fx25Encode {
  Fx25Encode._();

  /// Encode [data] with Reed-Solomon forward error correction, writing the
  /// check bytes (parity symbols) into [bb].
  ///
  /// After encoding, transmit: [correlation_tag][data][bb].
  static void encodeRs(ReedSolomonCodec rs, Uint8List data, Uint8List bb) {
    // Clear out the FEC data area (check bytes buffer)
    bb.fillRange(0, rs.nRoots, 0);

    // Process each data symbol.
    for (int i = 0; i < rs.nn - rs.nRoots; i++) {
      // Compute feedback term by XORing current data byte with first check byte
      // and converting to index form using logarithm lookup table.
      final int feedback = rs.indexOf[data[i] ^ bb[0]];

      // If feedback term is non-zero (not A0 which represents log of zero)
      if (feedback != rs.nn) {
        for (int j = 1; j < rs.nRoots; j++) {
          bb[j] ^= rs.alphaTo[rs.modNN(feedback + rs.genPoly[rs.nRoots - j])];
        }
      }

      // Shift check bytes left by one position.
      bb.setRange(0, rs.nRoots - 1, bb.sublist(1, rs.nRoots));

      // Compute new last check byte.
      if (feedback != rs.nn) {
        bb[rs.nRoots - 1] = rs.alphaTo[rs.modNN(feedback + rs.genPoly[0])];
      } else {
        bb[rs.nRoots - 1] = 0;
      }
    }
  }
}
