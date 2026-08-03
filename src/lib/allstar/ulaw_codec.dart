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
// ulaw_codec.dart - G.711 mu-law (PCMU) codec. 8 kHz, 1 byte per 16-bit sample.
//
// Standard ITU-T G.711 mu-law companding, matching the encoding Asterisk uses
// for the "ulaw" IAX2 media format. Lookup tables make the conversion
// allocation-free and branch-light.
//

import 'dart:typed_data';

const int _muBias = 0x84;
const int _muClip = 32635;

/// Precomputed 16-bit linear -> 8-bit mu-law table (indexed by unsigned 16-bit
/// sample value).
final Uint8List _linearToMu = _buildLinearToMu();

/// Precomputed 8-bit mu-law -> 16-bit linear table.
final Int16List _muToLinear = _buildMuToLinear();

Uint8List _buildLinearToMu() {
  final Uint8List table = Uint8List(65536);
  for (int i = 0; i < 65536; i++) {
    table[i] = _encodeSample(i >= 32768 ? i - 65536 : i);
  }
  return table;
}

Int16List _buildMuToLinear() {
  final Int16List table = Int16List(256);
  for (int i = 0; i < 256; i++) {
    table[i] = _decodeSample(i);
  }
  return table;
}

int _encodeSample(int sample) {
  int sign = (sample >> 8) & 0x80;
  if (sign != 0) sample = -sample;
  if (sample > _muClip) sample = _muClip;
  sample += _muBias;
  int exponent = 7;
  for (int mask = 0x4000; (sample & mask) == 0 && exponent > 0; mask >>= 1) {
    exponent--;
  }
  final int mantissa = (sample >> (exponent + 3)) & 0x0F;
  return (~(sign | (exponent << 4) | mantissa)) & 0xFF;
}

int _decodeSample(int u) {
  u = (~u) & 0xFF;
  final int sign = u & 0x80;
  final int exponent = (u >> 4) & 0x07;
  final int mantissa = u & 0x0F;
  int sample = ((mantissa << 3) + _muBias) << exponent;
  sample -= _muBias;
  return sign != 0 ? -sample : sample;
}

/// G.711 mu-law codec. Stateless; a single instance may be shared.
class UlawCodec {
  /// Encodes 16-bit PCM into one mu-law byte per sample.
  Uint8List encode(Int16List pcm) {
    final Uint8List out = Uint8List(pcm.length);
    for (int i = 0; i < pcm.length; i++) {
      out[i] = _linearToMu[pcm[i] & 0xFFFF];
    }
    return out;
  }

  /// Decodes mu-law bytes into 16-bit PCM (one sample per byte).
  Int16List decode(Uint8List ulaw, [int offset = 0, int? length]) {
    final int n = length ?? (ulaw.length - offset);
    final Int16List out = Int16List(n);
    for (int i = 0; i < n; i++) {
      out[i] = _muToLinear[ulaw[offset + i] & 0xFF];
    }
    return out;
  }
}
