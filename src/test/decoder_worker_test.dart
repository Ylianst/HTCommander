// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/decoder_worker.dart';

DecoderProcessor _create(Object? config, void Function(Object?) emit) =>
    _Processor(emit);

DecoderProcessor _failStartup(Object? config, void Function(Object?) emit) =>
    throw StateError('startup failed');

class _Processor implements DecoderProcessor {
  _Processor(this.emit);
  final void Function(Object?) emit;
  int count = 0;

  @override
  Future<void> process(Object? command) async {
    if (command == null) return;
    if (command == 'fail') throw StateError('decode failed');
    if (command == 'cpu') {
      emit('working');
      final timer = Stopwatch()..start();
      while (timer.elapsedMilliseconds < 250) {}
    }
    if (command == 'gate') {
      final gate = ReceivePort();
      emit(gate.sendPort);
      await gate.first;
      gate.close();
    }
    if (command is DecoderPcm) command = command.materialize().toList();
    emit((++count, command, Isolate.current.debugName));
  }

  @override
  void dispose() {}
}

void main() {
  test('CPU-bound decoding leaves the host event loop responsive', () async {
    bool heartbeat = false;
    final worker = DecoderWorker(
      name: 'busy-decoder',
      factory: _create,
      onEvent: (event) {
        if (event == 'working') {
          Timer.run(() => heartbeat = true);
        } else {
          expect(
            heartbeat,
            isTrue,
            reason: 'host timer was blocked by decoding',
          );
        }
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    addTearDown(worker.dispose);
    worker.add('cpu');
    await worker.idle.timeout(const Duration(seconds: 10));
    expect(heartbeat, isTrue);
  });

  test(
    'commands stay ordered off-isolate and borrowed PCM is copied',
    () async {
      final events = <Object?>[];
      final errors = <Object>[];
      final worker = DecoderWorker(
        name: 'test-decoder',
        factory: _create,
        onEvent: events.add,
        onError: (error, _) => errors.add(error),
      );
      addTearDown(worker.dispose);
      worker.reset();
      await worker.idle.timeout(const Duration(seconds: 1));
      final pcm = Uint8List.fromList([99, 1, 2, 3, 4, 99]);
      worker.add(DecoderPcm(pcm, 1, 4), bytes: 4);
      pcm.fillRange(0, pcm.length, 0);
      worker.add('second');
      await worker.idle.timeout(const Duration(seconds: 10));
      expect(errors, isEmpty);
      expect(events, hasLength(2));
      final first = events.first as (int, Object?, String?);
      expect(first.$1, 1);
      expect(first.$2, [1, 2, 3, 4]);
      expect(first.$3, 'test-decoder');
      expect(events.last, (2, 'second', 'test-decoder'));
    },
  );

  for (final byteLimit in [true, false]) {
    test(
      'startup queue bounds ${byteLimit ? "bytes" : "commands"} and resets',
      () async {
        final events = <Object?>[];
        final errors = <Object>[];
        final worker = DecoderWorker(
          name: 'bounded-decoder',
          factory: _create,
          maxPendingBytes: byteLimit ? 8 : 100,
          maxPendingCommands: byteLimit ? 100 : 2,
          onEvent: events.add,
          onError: (error, _) => errors.add(error),
        );
        addTearDown(worker.dispose);
        worker.add('discard one', bytes: 4);
        worker.add('discard two', bytes: 4);
        worker.add('after gap', bytes: 4);
        await worker.idle.timeout(const Duration(seconds: 10));
        expect(errors.single.toString(), contains('queue overflow'));
        expect(events, [(1, 'after gap', 'bounded-decoder')]);
      },
    );
  }

  test(
    'reset suppresses in-flight results and recreates decoder state',
    () async {
      final gate = Completer<SendPort>();
      final events = <Object?>[];
      final errors = <Object>[];
      final worker = DecoderWorker(
        name: 'reset-decoder',
        factory: _create,
        onEvent: (event) {
          if (event is SendPort) {
            gate.complete(event);
          } else {
            events.add(event);
          }
        },
        onError: (error, _) => errors.add(error),
      );
      addTearDown(worker.dispose);
      worker.add('gate');
      final release = await gate.future.timeout(const Duration(seconds: 10));
      worker.add('discard queued');
      worker.reset();
      worker.add('fresh');
      release.send(true);
      await worker.idle.timeout(const Duration(seconds: 10));
      expect(errors, isEmpty);
      expect(events, [(1, 'fresh', 'reset-decoder')]);
    },
  );

  test(
    'decode and startup failures are explicit and cannot hang idle',
    () async {
      for (final factory in [_create, _failStartup]) {
        final errors = <Object>[];
        final events = <Object?>[];
        final worker = DecoderWorker(
          name: 'failing-decoder',
          factory: factory,
          onEvent: events.add,
          onError: (error, _) => errors.add(error),
        );
        addTearDown(worker.dispose);
        worker.add('fail');
        await worker.idle.timeout(const Duration(seconds: 10));
        expect(errors, hasLength(1));
        if (factory == _create) {
          worker.add('recovered');
          await worker.idle.timeout(const Duration(seconds: 10));
          expect(events, [(1, 'recovered', 'failing-decoder')]);
        }
      }
    },
  );

  test('dispose during startup or decoding suppresses late replies', () async {
    final events = <Object?>[];
    final worker = DecoderWorker(
      name: 'disposed-startup',
      factory: _create,
      onEvent: events.add,
      onError: (error, stack) => fail('$error\n$stack'),
    );
    worker.add('never start');
    worker.dispose();
    await worker.idle;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, isEmpty);

    final gate = Completer<SendPort>();
    final active = DecoderWorker(
      name: 'disposed-active',
      factory: _create,
      onEvent: (event) {
        if (event is SendPort) {
          gate.complete(event);
        } else {
          events.add(event);
        }
      },
      onError: (error, stack) => fail('$error\n$stack'),
    );
    active.add('gate');
    final release = await gate.future.timeout(const Duration(seconds: 10));
    active.dispose();
    release.send(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, isEmpty);
  });
}
