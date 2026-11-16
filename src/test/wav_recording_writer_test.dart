// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/wav_recording_writer.dart';

// Keep test files in the checkout, not the system temporary directory.
void main() {
  late Directory directory;
  late List<String> errors;
  String path(String name) =>
      '${directory.path}${Platform.pathSeparator}$name.wav';

  setUp(() async {
    directory = await Directory.current.createTemp('wav_writer_test_');
    errors = [];
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'immediate admission preserves PCM order, slices and exact header',
    () async {
      final writer = WavRecordingWriter(onError: errors.add, batchBytes: 4);
      final clip = writer.open(path('ordered'), 32000);
      final input = Uint8List.fromList([99, 1, 2, 3, 4, 99]);
      clip.write(input, 1, 4);
      input.fillRange(0, input.length, 0);
      clip.write(Uint8List.fromList([5, 6]), 0, 2);
      expect(clip.dataBytes, 6);
      final closing = clip.close();
      expect(identical(clip.close(), closing), isTrue);
      expect(await closing, path('ordered'));
      expect(await File(path('ordered')).readAsBytes(), [
        82,
        73,
        70,
        70,
        42,
        0,
        0,
        0,
        87,
        65,
        86,
        69,
        102,
        109,
        116,
        32,
        16,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        125,
        0,
        0,
        0,
        250,
        0,
        0,
        2,
        0,
        16,
        0,
        100,
        97,
        116,
        97,
        6,
        0,
        0,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(errors, isEmpty);
      expect(() => clip.write(input, 0, 2), throwsStateError);
    },
  );

  test('small frames coalesce, then close drains in-flight writes', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    late _ControlledFile file;
    final writer = WavRecordingWriter(
      onError: errors.add,
      batchBytes: 8,
      openFile: (name) async {
        file = _ControlledFile(
          await File(name).open(mode: FileMode.write),
          beforeWrite: (call) async {
            if (call == 2) {
              started.complete();
              await release.future;
            }
          },
        );
        return file;
      },
    );
    final clip = writer.open(path('drain'), 8000);
    clip.write(Uint8List.fromList([1, 2]), 0, 2);
    await Future<void>.delayed(Duration.zero);
    clip.write(Uint8List.fromList([3, 4]), 0, 2);
    var finished = false;
    final closing = clip.close()..then((_) => finished = true);
    await started.future;
    expect(finished, isFalse);
    expect(file.closed, isFalse);
    release.complete();
    await closing;
    expect(file.closed, isTrue);
    expect(file.writes, 3); // Initial header, one PCM batch, final header.
    final bytes = await File(path('drain')).readAsBytes();
    expect(bytes.sublist(44), [1, 2, 3, 4]);
    expect(ByteData.sublistView(bytes).getUint32(24, Endian.little), 8000);
    expect(errors, isEmpty);
  });

  test('rename/discard wait for drain; clips stay ordered', () async {
    final writer = WavRecordingWriter(onError: errors.add);
    final first = writer.open(path('first'), 32000);
    first.write(Uint8List.fromList([1, 2]), 0, 2);
    final renamed = first.close(renameTo: path('renamed'));
    final second = writer.open(path('second'), 32000);
    second.write(Uint8List.fromList([3, 4]), 0, 2);
    final discarded = second.close(discard: true);
    final third = writer.open(path('empty'), 32000);
    final empty = third.close();
    expect(await renamed, path('renamed'));
    expect(await discarded, isNull);
    await empty;
    expect(await File(path('first')).exists(), isFalse);
    expect(await File(path('second')).exists(), isFalse);
    expect((await File(path('renamed')).readAsBytes()).sublist(44), [1, 2]);
    final header = await File(path('empty')).readAsBytes();
    expect(header.length, 44);
    expect(ByteData.sublistView(header).getUint32(4, Endian.little), 36);
    expect(ByteData.sublistView(header).getUint32(40, Endian.little), 0);
    expect(errors, isEmpty);
  });

  test('open errors are logged and never produce successful clips', () async {
    final writer = WavRecordingWriter(onError: errors.add);
    final clip = writer.open(
      path('missing${Platform.pathSeparator}clip'),
      32000,
    );
    clip.write(Uint8List(4), 0, 4);
    expect(await clip.close(), isNull);
    expect(errors.single, contains('open:'));
    final recovered = writer.open(path('recovered'), 32000);
    expect(await recovered.close(), path('recovered'));
  });

  for (final failingWrite in [2, 3]) {
    test(
      'write failure $failingWrite invalidates and deletes partial clip',
      () async {
        final writer = WavRecordingWriter(
          onError: errors.add,
          openFile: (name) async => _ControlledFile(
            await File(name).open(mode: FileMode.write),
            beforeWrite: (call) {
              if (call == failingWrite) {
                throw const FileSystemException('disk full');
              }
            },
          ),
        );
        final clip = writer.open(path('failed'), 32000);
        clip.write(Uint8List(4), 0, 4);
        expect(await clip.close(), isNull);
        expect(errors.single, contains('disk full'));
        expect(await File(path('failed')).exists(), isFalse);
      },
    );
  }

  test(
    'shared byte overflow fails whole clip without truncation fallback',
    () async {
      final writer = WavRecordingWriter(
        onError: errors.add,
        batchBytes: 4,
        maxPendingBytes: 8,
      );
      final first = writer.open(path('first'), 32000);
      first.write(Uint8List(4), 0, 4);
      final second = writer.open(path('overflow'), 32000);
      second.write(Uint8List(4), 0, 4);
      second.write(Uint8List(2), 0, 2);
      expect(second.dataBytes, 4);
      second.write(Uint8List(2), 0, 2);
      expect(await second.close(), isNull);
      expect(await first.close(), path('first'));
      expect(errors.single, contains('queue overflow'));
      expect(await File(path('overflow')).exists(), isFalse);
      final recovered = writer.open(path('recovered'), 32000);
      recovered.write(Uint8List(8), 0, 8);
      expect(await recovered.close(), path('recovered'));
    },
  );

  test('in-flight batches remain charged to the shared budget', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final writer = WavRecordingWriter(
      onError: errors.add,
      batchBytes: 4,
      maxPendingBytes: 4,
      openFile: (name) async => _ControlledFile(
        await File(name).open(mode: FileMode.write),
        beforeWrite: (call) async {
          if (call == 2) {
            started.complete();
            await release.future;
          }
        },
      ),
    );
    final clip = writer.open(path('inflight'), 32000);
    clip.write(Uint8List(4), 0, 4);
    await started.future;
    clip.write(Uint8List(2), 0, 2);
    final closing = clip.close();
    release.complete();
    expect(await closing, isNull);
    expect(errors.single, contains('queue overflow'));
    expect(await File(path('inflight')).exists(), isFalse);
  });

  test('clip-count limit also bounds pending empty clips', () async {
    final writer = WavRecordingWriter(onError: errors.add, maxPendingClips: 1);
    final first = writer.open(path('first'), 32000);
    final rejected = writer.open(path('rejected'), 32000);
    expect(await rejected.close(), isNull);
    expect(errors.single, contains('pending clip limit'));
    await first.close();
    final next = writer.open(path('next'), 32000);
    expect(await next.close(), path('next'));
  });

  test('rename failures log explicitly and retain playable original', () async {
    final writer = WavRecordingWriter(onError: errors.add);
    final clip = writer.open(path('original'), 32000);
    clip.write(Uint8List.fromList([1, 2]), 0, 2);
    expect(
      await clip.close(renameTo: path('missing${Platform.pathSeparator}new')),
      path('original'),
    );
    expect(errors.single, contains('Failed to rename'));
    expect((await File(path('original')).readAsBytes()).sublist(44), [1, 2]);
  });
}

class _ControlledFile implements RandomAccessFile {
  _ControlledFile(this.file, {required this.beforeWrite});
  final RandomAccessFile file;
  final FutureOr<void> Function(int call) beforeWrite;
  int writes = 0;
  bool closed = false;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    await beforeWrite(++writes);
    await file.writeFrom(buffer, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await file.setPosition(position);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await file.flush();
    return this;
  }

  @override
  Future<void> close() async {
    await file.close();
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
