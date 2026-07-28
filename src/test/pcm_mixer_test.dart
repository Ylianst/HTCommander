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
// pcm_mixer_test.dart - Tests for the software PCM mixer that sums several
// sources into the single output device.
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/pcm_mixer.dart';
import 'package:htcommander/radio/pcm_player.dart';

/// Minimal inert device so a [PcmMixer] can be constructed in a unit test; the
/// mixing maths under test never touch it (see [PcmMixer.debugMix]).
class _FakeDevice implements PcmPlayer {
  @override
  Future<void> setLogLevelError() async {}
  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
    String? deviceId,
  }) async {}
  @override
  Future<void> setFeedThreshold(int frames) async {}
  @override
  void setFeedCallback(PcmFeedCallback? callback) {}
  @override
  void start() {}
  @override
  Future<void> feed(Int16List pcm) async {}
  @override
  Future<void> release() async {}
}

void main() {
  group('PcmMixer.debugMix', () {
    late PcmMixer mixer;

    setUp(() => mixer = PcmMixer(_FakeDevice()));

    test('sums two sources sample-by-sample', () {
      final PcmMixerSource a = mixer.createSource()
        ..feed(Int16List.fromList(<int>[100, 100, 100]));
      final PcmMixerSource b = mixer.createSource()
        ..feed(Int16List.fromList(<int>[10, 20, 30]));

      expect(mixer.debugMix(<PcmMixerSource>[a, b], 3),
          Int16List.fromList(<int>[110, 120, 130]));
    });

    test('clamps the sum to the 16-bit range', () {
      final PcmMixerSource a = mixer.createSource()
        ..feed(Int16List.fromList(<int>[30000, -30000]));
      final PcmMixerSource b = mixer.createSource()
        ..feed(Int16List.fromList(<int>[10000, -10000]));

      // 40000 -> +32767, -40000 -> -32768.
      expect(mixer.debugMix(<PcmMixerSource>[a, b], 2),
          Int16List.fromList(<int>[32767, -32768]));
    });

    test('a shorter source contributes silence for the missing tail', () {
      final PcmMixerSource a = mixer.createSource()
        ..feed(Int16List.fromList(<int>[100, 100]));
      final PcmMixerSource b = mixer.createSource()
        ..feed(Int16List.fromList(<int>[10]));

      // Frame 0: 100+10, frame 1: 100 (b silent), frame 2: both silent.
      expect(mixer.debugMix(<PcmMixerSource>[a, b], 3),
          Int16List.fromList(<int>[110, 100, 0]));
    });

    test('an empty source is pure silence', () {
      final PcmMixerSource a = mixer.createSource();
      expect(mixer.debugMix(<PcmMixerSource>[a], 4),
          Int16List.fromList(<int>[0, 0, 0, 0]));
    });

    test('each mix step advances the read cursor', () {
      final PcmMixerSource a = mixer.createSource()
        ..feed(Int16List.fromList(<int>[1, 2, 3, 4]));

      expect(mixer.debugMix(<PcmMixerSource>[a], 2),
          Int16List.fromList(<int>[1, 2]));
      expect(mixer.debugMix(<PcmMixerSource>[a], 2),
          Int16List.fromList(<int>[3, 4]));
      // Drained: further reads are silence.
      expect(mixer.debugMix(<PcmMixerSource>[a], 2),
          Int16List.fromList(<int>[0, 0]));
    });

    test('ring drops the oldest samples on overflow', () {
      final PcmMixerSource a = mixer.createSource();
      // Default capacity is 500 ms @ 32 kHz mono = 16000 samples. Overfill by 3.
      const int cap = 16000;
      final Int16List ramp = Int16List(cap + 3);
      for (int i = 0; i < ramp.length; i++) {
        ramp[i] = ((i % 200) - 100); // stay in range, non-constant
      }
      a.feed(ramp);

      // Only the newest `cap` samples remain; the first 3 were dropped.
      final Int16List out = mixer.debugMix(<PcmMixerSource>[a], cap);
      expect(out.length, cap);
      expect(out[0], ramp[3]);
      expect(out[cap - 1], ramp[cap + 2]);
    });
  });
}
