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
// audio_buffer.dart - Audio sample buffer management
//
// Ported from C# HamLib/AudioBuffer.cs
//
// Note: the original C# used lock objects for thread safety. The Dart port is
// single threaded (per isolate), so the locks are omitted.
//

import 'dart:typed_data';

/// Manages audio sample buffers for encoding/decoding.
class AudioBuffer {
  final List<List<int>> _buffers;

  AudioBuffer(int numDevices)
    : _buffers = List<List<int>>.generate(numDevices, (_) => <int>[]);

  /// Add a sample to the buffer for a specific device.
  void put(int device, int sample) {
    _buffers[device].add(sample);
  }

  /// Get all samples from a device buffer and clear it.
  Int16List getAndClear(int device) {
    final Int16List samples = Int16List.fromList(_buffers[device]);
    _buffers[device].clear();
    return samples;
  }

  /// Get the current number of samples in a buffer.
  int getCount(int device) {
    return _buffers[device].length;
  }

  /// Clear a buffer.
  void clear(int device) {
    _buffers[device].clear();
  }

  /// Clear all buffers.
  void clearAll() {
    for (int i = 0; i < _buffers.length; i++) {
      clear(i);
    }
  }
}
