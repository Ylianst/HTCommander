/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

sherpa-onnx (SenseVoice) speech-to-text engine.

This implements the shared [SpeechToTextEngine] contract used by the
CommsHandler. SenseVoice is a non-streaming model, but the engine still
delivers live partial text by re-decoding the growing in-memory audio buffer
of the active segment, then emitting a final result when the segment ends.

All heavy recognition work runs in a dedicated background isolate so the main
isolate (UI + Bluetooth) never blocks. Audio is resampled from the radio rate
(32 kHz) down to the 16 kHz mono float the model expects, entirely in memory —
nothing is written to disk except the model files themselves.
*/

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../services/sherpa_model_manager.dart';
import 'speech_to_text_engine.dart';

/// Speech-to-text engine backed by sherpa-onnx with the SenseVoice model.
///
/// Works on every native platform (macOS, iOS, Android, Windows, Linux). The
/// model must be downloaded by the user in Settings before use.
class SherpaSpeechToTextEngine implements SpeechToTextEngine {
  final StreamController<SpeechResult> _results =
      StreamController<SpeechResult>.broadcast();
  final StreamController<bool> _processing = StreamController<bool>.broadcast();

  Isolate? _isolate;
  SendPort? _workerSend;
  ReceivePort? _receivePort;
  Completer<bool>? _readyCompleter;

  bool _ready = false;
  bool _disposed = false;

  /// Streaming 32 kHz -> 16 kHz resampler state for the active segment.
  final _LinearResampler _resampler = _LinearResampler(16000);

  @override
  bool get isSupported => true;

  @override
  bool get isReady => _ready;

  @override
  Stream<SpeechResult> get results => _results.stream;

  @override
  Stream<bool> get processing => _processing.stream;

  @override
  Future<bool> initialize({String localeId = ''}) async {
    if (_disposed) return false;
    if (_ready) return true;

    // Do not auto-download models here. The user must explicitly download
    // from Settings -> Voice -> Speech-to-Text.
    final modelId = SherpaModelManager.selectedModelId();
    final installed = await SherpaModelManager.isInstalled(modelId);
    if (!installed) {
      await SherpaModelManager.refreshStatus(modelId);
      debugPrint(
        '[SherpaSTT] initialize skipped: model "$modelId" not installed. '
        'Use Settings -> Voice -> Download.',
      );
      _ready = false;
      return false;
    }

    final model = SherpaModelManager.modelById(modelId);
    final modelDir = await SherpaModelManager.modelDirectory(model);
    final paths = SherpaModelManager.resolveInstalledModelPaths(model, modelDir);
    if (_disposed) return false;

    try {
      _receivePort = ReceivePort();
      _readyCompleter = Completer<bool>();
      _receivePort!.listen(_onWorkerMessage);

      _isolate = await Isolate.spawn(
        _sherpaWorkerEntry,
        _receivePort!.sendPort,
        debugName: 'sherpa-stt-worker',
      );

      // The worker hands back its command port, then we send the init request
      // and wait for the ready handshake.
      final initArgs = <String, Object?>{
        'cmd': 'init',
        'family': paths.family.name,
        'files': paths.files,
        'language': _languageFromLocale(localeId),
        'numThreads': 2,
      };
      _pendingInit = initArgs;

      _ready = await _readyCompleter!.future;
      return _ready;
    } catch (e) {
      debugPrint('[SherpaSTT] initialize failed: $e');
      _ready = false;
      return false;
    }
  }

  Map<String, Object?>? _pendingInit;

  void _onWorkerMessage(dynamic message) {
    if (message is! Map) return;
    final event = message['event'] as String?;
    switch (event) {
      case 'port':
        _workerSend = message['port'] as SendPort?;
        // Now that we have the command port, kick off initialization.
        final init = _pendingInit;
        if (init != null) {
          _pendingInit = null;
          _workerSend?.send(init);
        }
        break;
      case 'ready':
        final ok = (message['ok'] as bool?) ?? false;
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter!.complete(ok);
        }
        break;
      case 'result':
        final text = (message['text'] as String?) ?? '';
        final isFinal = (message['isFinal'] as bool?) ?? false;
        if (!_results.isClosed) _results.add(SpeechResult(text, isFinal));
        break;
      case 'processing':
        final active = (message['active'] as bool?) ?? false;
        if (!_processing.isClosed) _processing.add(active);
        break;
      case 'error':
        debugPrint('[SherpaSTT] worker error: ${message['message']}');
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter!.complete(false);
        }
        break;
    }
  }

  @override
  Future<void> startSegment() async {
    if (!_ready || _disposed) return;
    _resampler.reset();
    _workerSend?.send(const <String, Object?>{'cmd': 'start'});
  }

  @override
  Future<void> processPcm16(
    Uint8List data,
    int offset,
    int length,
    int sampleRate,
  ) async {
    if (!_ready || _disposed || length <= 0) return;
    final samples = _resampler.process(data, offset, length, sampleRate);
    if (samples.isEmpty) return;
    _workerSend?.send(<String, Object?>{'cmd': 'audio', 'samples': samples});
  }

  @override
  Future<void> completeSegment() async {
    if (!_ready || _disposed) return;
    _workerSend?.send(const <String, Object?>{'cmd': 'complete'});
  }

  @override
  Future<void> resetSegment() async {
    if (!_ready || _disposed) return;
    _resampler.reset();
    _workerSend?.send(const <String, Object?>{'cmd': 'reset'});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _workerSend?.send(const <String, Object?>{'cmd': 'dispose'});
    _workerSend = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    if (!_results.isClosed) await _results.close();
    if (!_processing.isClosed) await _processing.close();
  }

  /// Maps a BCP-47 locale (e.g. "en-US") to a SenseVoice language code.
  /// SenseVoice accepts: auto, zh, en, ja, ko, yue. Anything else -> auto.
  static String _languageFromLocale(String localeId) {
    if (localeId.isEmpty || localeId == 'auto') return 'auto';
    final lang = localeId.split(RegExp('[-_]')).first.toLowerCase();
    const supported = {'zh', 'en', 'ja', 'ko', 'yue'};
    return supported.contains(lang) ? lang : 'auto';
  }
}

/// Streaming linear resampler that converts arbitrary-rate 16-bit signed
/// little-endian mono PCM into 16 kHz mono float in `[-1, 1]`. State is kept
/// between calls so frame boundaries do not introduce clicks; [reset] clears it
/// at the start of each segment.
class _LinearResampler {
  _LinearResampler(this.targetRate);

  final int targetRate;

  // Position (in source samples, fractional) of the next output sample,
  // relative to the start of the current input chunk.
  double _nextPos = 0;
  // Last source sample of the previous chunk (source index -1 for this chunk).
  double _prev = 0;
  bool _hasPrev = false;

  void reset() {
    _nextPos = 0;
    _prev = 0;
    _hasPrev = false;
  }

  Float32List process(Uint8List data, int offset, int length, int sourceRate) {
    // Whole 16-bit samples available in this chunk.
    final sampleCount = length ~/ 2;
    if (sampleCount <= 0) return Float32List(0);

    final view = ByteData.sublistView(data, offset, offset + sampleCount * 2);
    double srcAt(int i) {
      // i == -1 refers to the carried-over tail of the previous chunk.
      if (i < 0) {
        return _hasPrev ? _prev : view.getInt16(0, Endian.little) / 32768.0;
      }
      return view.getInt16(i * 2, Endian.little) / 32768.0;
    }

    final ratio = sourceRate / targetRate; // source samples per output sample
    final out = <double>[];
    var pos = _nextPos;
    // Produce outputs while the upper interpolation neighbour exists.
    while (pos <= sampleCount - 1) {
      final i0 = pos.floor();
      final frac = pos - i0;
      final s0 = srcAt(i0);
      final s1 = srcAt(i0 + 1);
      out.add(s0 + (s1 - s0) * frac);
      pos += ratio;
    }

    // Carry state to the next chunk: shift positions back by this chunk's
    // length so the next chunk starts at source index 0 again.
    _nextPos = pos - sampleCount;
    _prev = srcAt(sampleCount - 1);
    _hasPrev = true;

    return Float32List.fromList(out);
  }
}

// ---------------------------------------------------------------------------
// Worker isolate
// ---------------------------------------------------------------------------

/// Entry point for the recognition isolate. Owns the sherpa-onnx recognizer
/// and the accumulated audio buffer for the active segment.
void _sherpaWorkerEntry(SendPort mainSend) {
  final commands = ReceivePort();
  mainSend.send(<String, Object?>{'event': 'port', 'port': commands.sendPort});

  sherpa.OfflineRecognizer? recognizer;
  // Accumulated 16 kHz mono float samples for the active segment.
  final List<double> buffer = <double>[];
  // Samples appended since the last partial decode.
  var sinceLastPartial = 0;
  // ~1 s of 16 kHz audio between partial re-decodes.
  const partialThreshold = 16000;
  const sampleRate = 16000;

  String decode() {
    final rec = recognizer;
    if (rec == null || buffer.isEmpty) return '';
    final stream = rec.createStream();
    try {
      stream.acceptWaveform(
        samples: Float32List.fromList(buffer),
        sampleRate: sampleRate,
      );
      rec.decode(stream);
      return rec.getResult(stream).text;
    } finally {
      stream.free();
    }
  }

  commands.listen((message) {
    if (message is! Map) return;
    final cmd = message['cmd'] as String?;
    switch (cmd) {
      case 'init':
        try {
          sherpa.initBindings();
          final family = message['family'] as String?;
          final files = (message['files'] as Map).cast<String, String>();
          final lang = (message['language'] as String?) ?? 'auto';
          final threads = (message['numThreads'] as int?) ?? 2;
          final tokens = files['tokens.txt'] ?? '';

          final sherpa.OfflineModelConfig modelConfig;
          if (family == 'whisper') {
            modelConfig = sherpa.OfflineModelConfig(
              whisper: sherpa.OfflineWhisperModelConfig(
                encoder: files['encoder.int8.onnx'] ?? '',
                decoder: files['decoder.int8.onnx'] ?? '',
                // These models are English-only; let it auto otherwise.
                language: lang == 'auto' ? '' : lang,
                task: 'transcribe',
              ),
              tokens: tokens,
              numThreads: threads,
              provider: 'cpu',
              debug: false,
            );
          } else {
            modelConfig = sherpa.OfflineModelConfig(
              senseVoice: sherpa.OfflineSenseVoiceModelConfig(
                model: files['model.int8.onnx'] ?? '',
                language: lang,
                useInverseTextNormalization: true,
              ),
              tokens: tokens,
              numThreads: threads,
              provider: 'cpu',
              debug: false,
            );
          }
          recognizer = sherpa.OfflineRecognizer(
            sherpa.OfflineRecognizerConfig(model: modelConfig),
          );
          mainSend.send(<String, Object?>{'event': 'ready', 'ok': true});
        } catch (e) {
          mainSend.send(<String, Object?>{
            'event': 'error',
            'message': 'init failed: $e',
          });
          mainSend.send(<String, Object?>{'event': 'ready', 'ok': false});
        }
        break;

      case 'start':
        buffer.clear();
        sinceLastPartial = 0;
        mainSend.send(<String, Object?>{'event': 'processing', 'active': true});
        break;

      case 'audio':
        final samples = message['samples'];
        if (samples is Float32List && samples.isNotEmpty) {
          buffer.addAll(samples);
          sinceLastPartial += samples.length;
          if (sinceLastPartial >= partialThreshold) {
            sinceLastPartial = 0;
            try {
              final text = decode();
              mainSend.send(<String, Object?>{
                'event': 'result',
                'text': text,
                'isFinal': false,
              });
            } catch (e) {
              mainSend.send(<String, Object?>{
                'event': 'error',
                'message': 'partial decode failed: $e',
              });
            }
          }
        }
        break;

      case 'complete':
        try {
          final text = decode();
          // Always emit a final (even empty) so the UI clears any partial.
          mainSend.send(<String, Object?>{
            'event': 'result',
            'text': text,
            'isFinal': true,
          });
        } catch (e) {
          mainSend.send(<String, Object?>{
            'event': 'error',
            'message': 'final decode failed: $e',
          });
        }
        buffer.clear();
        sinceLastPartial = 0;
        mainSend.send(<String, Object?>{
          'event': 'processing',
          'active': false,
        });
        break;

      case 'reset':
        buffer.clear();
        sinceLastPartial = 0;
        mainSend.send(<String, Object?>{
          'event': 'processing',
          'active': false,
        });
        break;

      case 'dispose':
        try {
          recognizer?.free();
        } catch (_) {}
        recognizer = null;
        commands.close();
        Isolate.exit();
    }
  });
}
