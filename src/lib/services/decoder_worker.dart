// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

abstract interface class DecoderProcessor {
  FutureOr<void> process(Object? command);
  void dispose();
}

typedef DecoderFactory =
    DecoderProcessor Function(Object? config, void Function(Object?) emit);

/// A persistent decoder with one command in flight. Both the mailbox and the
/// host queue are bounded, including during isolate startup.
///
/// Overflow invalidates outstanding results and recreates the decoder before
/// accepting more audio: samples on opposite sides of a gap must not be joined.
/// Web has no isolate support and uses the same ordered protocol locally.
class DecoderWorker {
  DecoderWorker({
    required this.name,
    required this.factory,
    required this.onEvent,
    required this.onError,
    this.config,
    this.maxPendingBytes = 256000,
    this.maxPendingCommands = 256,
  });

  final String name;
  final DecoderFactory factory;
  final Object? config;
  final void Function(Object?) onEvent;
  final void Function(Object, StackTrace) onError;
  final int maxPendingBytes;
  final int maxPendingCommands;
  final Queue<_Command> _queue = Queue<_Command>();
  final List<Completer<void>> _waiters = [];
  ReceivePort? _receive;
  SendPort? _port;
  DecoderProcessor? _local;
  bool _started = false;
  bool _busy = false;
  bool _disposed = false;
  bool _needsReset = false;
  int _generation = 0;
  int _localGeneration = 0;
  int _bytes = 0;
  int _inFlightBytes = 0;

  static const bool usesIsolates = bool.fromEnvironment('dart.library.io');

  /// [bytes] accounts for retained command data, including the in-flight block.
  void add(Object? command, {int bytes = 0}) {
    if (_disposed) return;
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    if (_bytes + bytes > maxPendingBytes ||
        _queue.length + (_busy ? 1 : 0) >= maxPendingCommands) {
      reset();
      onError(
        StateError('$name receive queue overflow; decoder stream reset'),
        StackTrace.current,
      );
      if (_disposed) return;
    }
    if (_bytes + bytes > maxPendingBytes) {
      onError(
        StateError('$name block exceeds $maxPendingBytes-byte receive limit'),
        StackTrace.current,
      );
      return;
    }
    _queue.add(_Command(command, bytes));
    _bytes += bytes;
    if (!_started) {
      _started = true;
      unawaited(_start());
    }
    _pump();
  }

  /// Discards queued work and stale replies. The active call is allowed to
  /// finish so native resources can be released on the owning isolate.
  void reset() {
    if (_disposed) return;
    _generation++;
    _queue.clear();
    _bytes = _inFlightBytes;
    _needsReset = _started;
    _pump();
    if (!_started) _finishWaiters();
  }

  /// Completes after all commands and their events have been delivered.
  Future<void> get idle {
    if (_disposed || (!_busy && _queue.isEmpty && !_needsReset)) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  Future<void> _start() async {
    try {
      await Future<void>.delayed(Duration.zero);
      if (_disposed) return;
      if (!usesIsolates) {
        _local = factory(config, _emitLocal);
        _pump();
        return;
      }
      final receive = ReceivePort();
      _receive = receive;
      receive.listen(_receiveMessage);
      await Isolate.spawn(
        _entry,
        (receive.sendPort, factory, config),
        debugName: name,
        onError: receive.sendPort,
        onExit: receive.sendPort,
        errorsAreFatal: true,
      );
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _receiveMessage(Object? message) {
    if (message is SendPort) {
      if (_disposed) {
        message.send(null);
        _receive?.close();
      } else {
        _port = message;
        _pump();
      }
    } else if (message is _Event) {
      if (!_disposed && message.generation == _generation) {
        onEvent(message.value);
      }
    } else if (message is _Done) {
      if (_disposed) return;
      _busy = false;
      _bytes -= _inFlightBytes;
      _inFlightBytes = 0;
      if (message.error != null) {
        reset();
        onError(
          StateError('$name: ${message.error}'),
          StackTrace.fromString(message.stack!),
        );
      }
      _pump();
    } else if (!_disposed) {
      _fail(
        StateError('$name worker exited unexpectedly: $message'),
        StackTrace.current,
      );
    } else {
      _receive?.close();
    }
  }

  void _pump() {
    if (_disposed || _busy || (_port == null && _local == null)) return;
    if (_queue.isEmpty && !_needsReset) {
      _finishWaiters();
      return;
    }
    final command = _queue.isEmpty ? _Command(null, 0) : _queue.removeFirst();
    final work = _Work(_generation, _needsReset, command.value);
    _needsReset = false;
    _busy = true;
    _inFlightBytes = command.bytes;
    if (_port != null) {
      _port!.send(work);
    } else {
      unawaited(_processLocal(work));
    }
  }

  Future<void> _processLocal(_Work work) async {
    try {
      _localGeneration = work.generation;
      if (work.reset) {
        _local?.dispose();
        _local = null;
        try {
          _local = factory(config, _emitLocal);
        } catch (error, stack) {
          _fail(error, stack);
          return;
        }
      }
      await _local!.process(work.value);
      _receiveMessage(_Done());
    } catch (error, stack) {
      _receiveMessage(_Done(error.toString(), stack.toString()));
    }
  }

  void _emitLocal(Object? event) {
    if (!_disposed && _localGeneration == _generation) onEvent(event);
  }

  void _fail(Object error, StackTrace stack) {
    if (_disposed) return;
    dispose();
    _receive?.close();
    onError(error, stack);
  }

  void _finishWaiters() {
    for (final waiter in _waiters) {
      waiter.complete();
    }
    _waiters.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _local?.dispose();
    _local = null;
    // Startup can still be in flight; its handshake sends shutdown instead.
    _port?.send(null);
    _port = null;
    if (!_started || !usesIsolates) _receive?.close();
    _finishWaiters();
  }
}

class _Command {
  _Command(this.value, this.bytes);
  final Object? value;
  final int bytes;
}

class _Work {
  _Work(this.generation, this.reset, this.value);
  final int generation;
  final bool reset;
  final Object? value;
}

class _Event {
  _Event(this.generation, this.value);
  final int generation;
  final Object? value;
}

class _Done {
  _Done([this.error, this.stack]);
  final String? error;
  final String? stack;
}

/// PCM is copied before returning to the broker; callers may reuse its storage.
class DecoderPcm {
  DecoderPcm(Uint8List pcm, int offset, int length, {this.context})
    : data = DecoderWorker.usesIsolates
          ? TransferableTypedData.fromList([
              Uint8List.sublistView(pcm, offset, offset + length),
            ])
          : Uint8List.fromList(
              Uint8List.sublistView(pcm, offset, offset + length),
            );

  final Object data;
  final Object? context;

  Uint8List materialize() {
    final value = data;
    return value is TransferableTypedData
        ? value.materialize().asUint8List()
        : value as Uint8List;
  }
}

Future<void> _entry((SendPort, DecoderFactory, Object?) start) async {
  final (host, factory, config) = start;
  final commands = ReceivePort();
  int generation = 0;
  void emit(Object? event) => host.send(_Event(generation, event));
  DecoderProcessor? processor;
  try {
    processor = factory(config, emit);
    host.send(commands.sendPort);
    await for (final message in commands) {
      if (message == null) break;
      final work = message as _Work;
      generation = work.generation;
      if (work.reset) {
        processor?.dispose();
        processor = null;
        processor = factory(config, emit);
      }
      try {
        await processor!.process(work.value);
        host.send(_Done());
      } catch (error, stack) {
        host.send(_Done(error.toString(), stack.toString()));
      }
    }
  } finally {
    processor?.dispose();
    commands.close();
  }
}
