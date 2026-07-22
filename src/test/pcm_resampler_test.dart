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
// pcm_resampler_test.dart - Tests for the streaming linear PCM resampler.
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/echolink/pcm_resampler.dart';

void main() {
  group('LinearResampler', () {
    test('DC (constant) input is preserved exactly', () {
      final LinearResampler up = LinearResampler.up8kTo32k();
      final Int16List input = Int16List(64)..fillRange(0, 64, 1234);
      final Int16List out = up.process(input);
      expect(out, isNotEmpty);
      expect(out.every((int v) => v == 1234), isTrue);
    });

    test('upsampling 8k->32k grows length by ~4x over a long stream', () {
      final LinearResampler up = LinearResampler.up8kTo32k();
      int total = 0;
      for (int i = 0; i < 10; i++) {
        total += up.process(Int16List(800)).length; // 100 ms chunks
      }
      // 8000 input samples -> ~32000 output samples.
      expect(total, closeTo(32000, 8));
    });

    test('downsampling 32k->8k shrinks length by ~4x over a long stream', () {
      final LinearResampler down = LinearResampler.down32kTo8k();
      int total = 0;
      for (int i = 0; i < 10; i++) {
        total += down.process(Int16List(3200)).length;
      }
      expect(total, closeTo(8000, 8));
    });

    test('chunk boundaries do not change the result (streaming continuity)', () {
      final Int16List input = Int16List(200);
      for (int i = 0; i < input.length; i++) {
        input[i] = ((i * 211) % 4000) - 2000; // deterministic pattern
      }

      final LinearResampler whole = LinearResampler.up8kTo32k();
      final Int16List outWhole = whole.process(input);

      final LinearResampler split = LinearResampler.up8kTo32k();
      final Int16List a = split.process(Int16List.sublistView(input, 0, 73));
      final Int16List b = split.process(Int16List.sublistView(input, 73, 128));
      final Int16List c = split.process(Int16List.sublistView(input, 128));

      final List<int> joined = <int>[...a, ...b, ...c];
      expect(joined, orderedEquals(outWhole));
    });

    test('reset clears carried state', () {
      final LinearResampler up = LinearResampler.up8kTo32k();
      up.process(Int16List.fromList(<int>[100, 200, 300]));
      up.reset();
      final Int16List out = up.process(Int16List.fromList(<int>[500, 500, 500]));
      expect(out.every((int v) => v == 500), isTrue);
    });
  });
}
