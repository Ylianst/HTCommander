import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/utils/pcm_sample_queue.dart';

void main() {
  test('drains frames across chunks and preserves a partial tail', () {
    final queue = PcmSampleQueue()
      ..add(Int16List.fromList([1, 2, 3]))
      ..add(Int16List(0))
      ..add(Int16List.fromList([4, 5, 6, 7]));
    expect(queue.take(2), [1, 2]);
    expect(queue.take(4), [3, 4, 5, 6]);
    expect(queue.length, 1);
    expect(queue.take(1), [7]);
    expect(queue.length, 0);
    queue.add(Int16List.fromList([8]));
    expect(queue.take(1), [8]);
  });

  test('clearing releases partially consumed chunks', () {
    final queue = PcmSampleQueue()..add(Int16List.fromList([1, 2, 3]));
    queue.take(1);
    queue.clear();
    expect(queue.length, 0);
    queue.add(Int16List.fromList([-32768, 32767]));
    expect(queue.take(2), [-32768, 32767]);
    expect(() => queue.take(1), throwsRangeError);
  });

  test(
    'a long recording has identical 20 ms frames without modifying input',
    () {
      final recording = Int16List.fromList(
        List.generate(480000, (i) => i % 32768),
      );
      final queue = PcmSampleQueue()..add(recording);
      for (var offset = 0; offset < recording.length; offset += 160) {
        expect(queue.take(160), recording.sublist(offset, offset + 160));
      }
      expect(queue.length, 0);
      expect(recording[479999], 479999 % 32768);
    },
  );
}
