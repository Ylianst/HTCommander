// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:typed_data';

import '../services/decoder_worker.dart';
import 'sstv_monitor.dart';

class SstvReceiveContext {
  const SstvReceiveContext(this.deviceId, this.channelName, this.muted);
  final int deviceId;
  final String channelName;
  final bool muted;
}

class SstvWorker {
  SstvWorker({
    int sampleRate = 32000,
    required void Function(Object, StackTrace) onError,
  }) {
    _worker = DecoderWorker(
      name: 'sstv-rx',
      factory: _createSstv,
      config: sampleRate,
      maxPendingBytes: sampleRate * 2 * 4,
      onEvent: _onEvent,
      onError: onError,
    );
  }

  late final DecoderWorker _worker;
  final _started = StreamController<SstvDecodingStarted>.broadcast(sync: true);
  final _progress = StreamController<SstvDecodingProgress>.broadcast(
    sync: true,
  );
  final _complete = StreamController<SstvDecodingComplete>.broadcast(
    sync: true,
  );
  SstvImage? _partial;
  SstvReceiveContext? context;

  Stream<SstvDecodingStarted> get onDecodingStarted => _started.stream;
  Stream<SstvDecodingProgress> get onDecodingProgress => _progress.stream;
  Stream<SstvDecodingComplete> get onDecodingComplete => _complete.stream;

  void _onEvent(Object? message) {
    final event = message as _SstvEvent;
    context = event.context;
    _partial = event.partial;
    switch (event.value) {
      case SstvDecodingStarted value:
        _started.add(value);
      case SstvDecodingProgress value:
        _progress.add(value);
      case SstvDecodingComplete value:
        _complete.add(value);
    }
  }

  void processPcm16(
    Uint8List pcm,
    int offset,
    int length, {
    required SstvReceiveContext context,
  }) {
    if (length <= 1) return;
    _worker.add(
      DecoderPcm(pcm, offset, length, context: context),
      bytes: length,
    );
  }

  /// Ordered after the last PCM block, including detection still in flight.
  void end(int deviceId) => _worker.add(deviceId);
  SstvImage? getPartialImage() => _partial;
  Future<void> get idle => _worker.idle;

  void reset() {
    _partial = null;
    _worker.reset();
  }

  void dispose() {
    _worker.dispose();
    _started.close();
    _progress.close();
    _complete.close();
  }
}

class _SstvEvent {
  _SstvEvent(this.context, this.value, [this.partial]);
  final SstvReceiveContext context;
  final Object value;
  final SstvImage? partial;
}

DecoderProcessor _createSstv(Object? config, void Function(Object?) emit) =>
    _SstvDecoder(config as int, emit);

class _SstvDecoder implements DecoderProcessor {
  _SstvDecoder(int rate, this.emit) : monitor = SstvMonitor(sampleRate: rate) {
    monitor.onDecodingStarted.listen((event) {
      _active = true;
      _mode = event.modeName;
      emit(_SstvEvent(_context!, event));
    });
    monitor.onDecodingProgress.listen((event) {
      emit(_SstvEvent(_context!, event, monitor.getPartialImage()));
    });
    monitor.onDecodingComplete.listen((event) {
      _active = false;
      emit(_SstvEvent(_context!, event));
    });
  }

  final SstvMonitor monitor;
  final void Function(Object?) emit;
  SstvReceiveContext? _context;
  bool _active = false;
  String _mode = '';

  @override
  Future<void> process(Object? command) async {
    if (command is DecoderPcm) {
      final context = command.context as SstvReceiveContext;
      if (_active && context.deviceId != _context?.deviceId) return;
      if (context.deviceId != _context?.deviceId) monitor.reset();
      if (!_active) _context = context;
      final pcm = command.materialize();
      monitor.processPcm16(pcm, 0, pcm.length);
      // The reference monitor's streams are asynchronous. Drain them before
      // acknowledging this block or changing its source attribution.
      await Future<void>.delayed(Duration.zero);
    } else if (command is int && command == _context?.deviceId && _active) {
      final image = monitor.getPartialImage();
      monitor.reset();
      _active = false;
      emit(
        _SstvEvent(
          _context!,
          SstvDecodingComplete(
            modeName: _mode,
            width: image?.width ?? 0,
            height: image?.height ?? 0,
            image: image,
          ),
        ),
      );
    }
  }

  @override
  void dispose() => monitor.dispose();
}
