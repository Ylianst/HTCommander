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
// pcm_resampler.dart - Streaming linear PCM sample-rate converter.
//
// Bridges EchoLink's 8 kHz GSM audio to/from the app's 32 kHz audio engine.
// Uses linear interpolation with cross-chunk continuity (the last input sample
// and fractional phase are carried between calls), so splitting a stream into
// arbitrary chunks yields the same result as processing it whole.
//
// Note: linear interpolation is a mild low-pass filter. It is adequate for
// 8 kHz narrow-band voice; a higher-order polyphase FIR could replace it later
// for improved 32 kHz -> 8 kHz anti-aliasing.
//

import 'dart:typed_data';

class LinearResampler {
  /// Input samples advanced per output sample (inputRate / outputRate).
  final double ratio;

  double _pos = 0.0; // next output position, in input-sample units
  int? _prev; // last input sample of the previous chunk (index -1)

  LinearResampler({required int inputRate, required int outputRate})
      : assert(inputRate > 0 && outputRate > 0),
        ratio = inputRate / outputRate;

  /// Resampler for EchoLink -> app audio (8 kHz to 32 kHz).
  factory LinearResampler.up8kTo32k() =>
      LinearResampler(inputRate: 8000, outputRate: 32000);

  /// Resampler for app -> EchoLink audio (32 kHz to 8 kHz).
  factory LinearResampler.down32kTo8k() =>
      LinearResampler(inputRate: 32000, outputRate: 8000);

  /// Clears carried state to start a new stream.
  void reset() {
    _pos = 0.0;
    _prev = null;
  }

  /// Resamples [input], returning the output samples produced from it. State is
  /// carried so consecutive calls form one continuous stream.
  Int16List process(Int16List input) {
    final int n = input.length;
    if (n == 0) return Int16List(0);

    final int prev = _prev ?? input[0];
    int sampleAt(int idx) => idx < 0 ? prev : input[idx];

    final List<int> out = <int>[];
    double pos = _pos;

    // Produce outputs while both interpolation neighbours are available in this
    // chunk (i.e. floor(pos)+1 <= n-1).
    while (pos.floor() + 1 < n) {
      final int i0 = pos.floor();
      final double frac = pos - i0;
      final int a = sampleAt(i0);
      final int b = sampleAt(i0 + 1);
      int v = (a + (b - a) * frac).round();
      if (v > 32767) {
        v = 32767;
      } else if (v < -32768) {
        v = -32768;
      }
      out.add(v);
      pos += ratio;
    }

    _prev = input[n - 1];
    _pos = pos - n; // rebase onto the next chunk (index -1 == new _prev)
    return Int16List.fromList(out);
  }
}
