// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:typed_data';

import '../services/decoder_worker.dart';
import 'radiosonde_fix.dart';
import 'radiosonde_monitor.dart';

typedef RadiosondeReception = ({
  int deviceId,
  String channelName,
  RadiosondeFix fix,
});

class RadiosondeWorker {
  RadiosondeWorker({
    int sampleRate = 48000,
    required void Function(Object, StackTrace) onError,
  }) {
    _worker = DecoderWorker(
      name: 'radiosonde-rx',
      factory: _createRadiosonde,
      config: sampleRate,
      maxPendingBytes: sampleRate * 2 * 12,
      maxPendingCommands: 512,
      onEvent: (event) => _decoded.add(event as RadiosondeReception),
      onError: onError,
    );
  }

  late final DecoderWorker _worker;
  final _decoded = StreamController<RadiosondeReception>.broadcast(sync: true);
  Stream<RadiosondeReception> get onDecoded => _decoded.stream;

  void processPcm16(
    Uint8List pcm,
    int offset,
    int length, {
    required int deviceId,
    required String channelName,
  }) {
    if (length <= 1) return;
    _worker.add(
      DecoderPcm(pcm, offset, length, context: (deviceId, channelName)),
      bytes: length,
    );
  }

  void flush(int deviceId) => _worker.add(deviceId);
  Future<void> get idle => _worker.idle;

  void dispose() {
    _worker.dispose();
    _decoded.close();
  }
}

DecoderProcessor _createRadiosonde(
  Object? config,
  void Function(Object?) emit,
) => _RadiosondeDecoder(config as int, emit);

class _RadiosondeDecoder implements DecoderProcessor {
  _RadiosondeDecoder(int rate, void Function(Object?) emit)
    : monitor = RadiosondeMonitor(sampleRate: rate) {
    monitor.onDecoded.listen(
      (fix) => emit((deviceId: _deviceId, channelName: _channelName, fix: fix)),
    );
  }

  final RadiosondeMonitor monitor;
  int _deviceId = -1;
  String _channelName = '';

  @override
  Future<void> process(Object? command) async {
    if (command is DecoderPcm) {
      final (deviceId, channelName) = command.context as (int, String);
      if (_deviceId != deviceId && _deviceId > 0) {
        monitor.flush();
        await Future<void>.delayed(Duration.zero);
      }
      _deviceId = deviceId;
      _channelName = channelName;
      final pcm = command.materialize();
      monitor.processPcm16(pcm, 0, pcm.length);
    } else if (command is int && command == _deviceId) {
      monitor.flush();
    }
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void dispose() => monitor.dispose();
}
