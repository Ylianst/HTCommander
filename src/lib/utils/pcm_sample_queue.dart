// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:collection';
import 'dart:typed_data';

/// An owned PCM chunk queue. Consuming samples never shifts the queued audio.
class PcmSampleQueue {
  final Queue<Int16List> _chunks = Queue();
  int _head = 0;
  int _length = 0;

  int get length => _length;
  bool get isNotEmpty => _length != 0;

  /// Transfers ownership of [samples]; the caller must not modify them.
  void add(Int16List samples) {
    if (samples.isEmpty) return;
    _chunks.add(samples);
    _length += samples.length;
  }

  Int16List take(int count) {
    RangeError.checkValueInInterval(count, 0, _length, 'count');
    final result = Int16List(count);
    var written = 0;
    while (written < count) {
      final chunk = _chunks.first;
      final available = chunk.length - _head;
      final n = (count - written).clamp(0, available);
      result.setRange(written, written + n, chunk, _head);
      written += n;
      _head += n;
      if (_head == chunk.length) {
        _chunks.removeFirst();
        _head = 0;
      }
    }
    _length -= count;
    return result;
  }

  void clear() {
    _chunks.clear();
    _head = 0;
    _length = 0;
  }
}
