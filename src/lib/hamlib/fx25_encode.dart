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
import 'reed_solomon_codec.dart';

/// FX.25 Reed-Solomon encoding operations.
class Fx25Encode {
  Fx25Encode._();

  /// Encode [data] with Reed-Solomon forward error correction, writing the
  /// check bytes (parity symbols) into [bb].
  ///
  /// After encoding, transmit: [correlation_tag][data][bb].
  /// Set [useNative] to false to force the Dart reference encoder.
  static void encodeRs(
    ReedSolomonCodec rs,
    Uint8List data,
    Uint8List bb, {
    bool useNative = true,
  }) => ReedSolomon.encode(rs, data, bb, useNative: useNative);
}
