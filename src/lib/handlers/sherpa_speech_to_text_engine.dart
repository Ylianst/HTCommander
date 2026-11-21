/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Desktop offline/streaming recognition and neural VAD share a worker isolate.
Audio stays in memory. Internal utterances belong to one radio transmission.
*/

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../services/sherpa_model_manager.dart';
import 'radio_speech.dart';
import 'speech_to_text_engine.dart';

class SherpaSpeechToTextEngine implements SpeechToTextEngine {
  final _results = StreamController<SpeechResult>.broadcast();
  final _processing = StreamController<bool>.broadcast();
  final _diagnostics = StreamController<SpeechDiagnostics>.broadcast();
  final _backlog = SpeechAudioBacklog();
  final _resampler = _LinearResampler(16000);
  Isolate? _isolate;
  SendPort? _workerSend;
  ReceivePort? _receivePort;
  Completer<bool>? _readyCompleter;
  Map<String, Object?>? _pendingInit;
  bool _ready = false;
  bool _disposed = false;
  int _segmentId = 0;
  int _lastDiagnosticMs = 0;
  int _lastDecodeMs = 0;
  Completer<void>? _exited;

  @override
  bool get isSupported => !Platform.isIOS && !Platform.isAndroid;
  @override
  bool get isReady => _ready;
  @override
  Stream<SpeechResult> get results => _results.stream;
  @override
  Stream<bool> get processing => _processing.stream;
  @override
  Stream<SpeechDiagnostics> get diagnostics => _diagnostics.stream;

  @override
  Future<bool> initialize({String localeId = ''}) async {
    if (_disposed || !isSupported) return false;
    if (_ready) return true;
    final modelId = SherpaModelManager.selectedModelId();
    if (!await SherpaModelManager.isInstalled(modelId)) {
      await SherpaModelManager.refreshStatus(modelId);
      _emitDiagnostics(
        error:
            'Speech model or VAD is not installed. Download it in Settings > Voice.',
      );
      return false;
    }
    final model = SherpaModelManager.modelById(modelId);
    final dir = await SherpaModelManager.modelDirectory(model);
    final paths = SherpaModelManager.resolveInstalledModelPaths(model, dir);
    if (_disposed) return false;
    try {
      await SherpaModelManager.installBundledVocabulary(model, dir);
      _receivePort = ReceivePort();
      _readyCompleter = Completer<bool>();
      _pendingInit = {
        'cmd': 'init',
        'family': paths.family.name,
        'files': paths.files,
        'language': _languageFromLocale(localeId),
      };
      _receivePort!.listen(_onWorkerMessage);
      _isolate = await Isolate.spawn(
        _sherpaWorkerEntry,
        _receivePort!.sendPort,
        debugName: 'sherpa-stt-worker',
        onError: _receivePort!.sendPort,
        onExit: _receivePort!.sendPort,
      );
      _ready = await _readyCompleter!.future.timeout(
        const Duration(seconds: 30),
      );
      return _ready;
    } catch (e) {
      _emitDiagnostics(error: 'Speech initialization failed: $e');
      _isolate?.kill(priority: Isolate.immediate);
      _ready = false;
      return false;
    }
  }

  void _emitDiagnostics({String? error, bool force = false}) {
    if (_disposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (error == null &&
        !force &&
        _backlog.samples != 0 &&
        now - _lastDiagnosticMs < 250) {
      return;
    }
    _lastDiagnosticMs = now;
    _diagnostics.add(
      SpeechDiagnostics(
        segmentId: _segmentId,
        queuedAudioMs: _backlog.milliseconds,
        decodeMs: _lastDecodeMs,
        overloaded: _backlog.overloaded,
        error: error,
      ),
    );
  }

  void _onWorkerMessage(dynamic message) {
    if (_disposed) return;
    if (message == null && _exited != null) {
      if (!_exited!.isCompleted) _exited!.complete();
      return;
    }
    if (message is! Map) {
      _ready = false;
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.complete(false);
      }
      _emitDiagnostics(error: 'Speech worker exited unexpectedly: $message');
      return;
    }
    switch (message['event']) {
      case 'port':
        _workerSend = message['port'] as SendPort;
        _workerSend!.send(_pendingInit);
        _pendingInit = null;
        break;
      case 'ready':
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter!.complete(message['ok'] == true);
        }
        break;
      case 'result':
        _results.add(
          SpeechResult(
            message['text'] as String,
            message['isFinal'] as bool,
            segmentId: message['segmentId'] as int,
          ),
        );
        break;
      case 'processing':
        _processing.add(message['active'] as bool);
        break;
      case 'ack':
        final wasOverloaded = _backlog.overloaded;
        _backlog.acknowledge(message['samples'] as int);
        _emitDiagnostics(force: wasOverloaded != _backlog.overloaded);
        break;
      case 'decode':
        _lastDecodeMs = message['decodeMs'] as int;
        _emitDiagnostics();
        break;
      case 'error':
        _diagnostics.add(
          SpeechDiagnostics(
            segmentId: message['segmentId'] as int? ?? _segmentId,
            queuedAudioMs: _backlog.milliseconds,
            overloaded: _backlog.overloaded,
            error: message['message'] as String,
          ),
        );
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter!.complete(false);
        }
        break;
    }
  }

  @override
  Future<void> startSegment({
    required int segmentId,
    List<String> hotwords = const [],
  }) async {
    if (!_ready || _disposed) return;
    _segmentId = segmentId;
    _resampler.reset();
    _workerSend!.send({
      'cmd': 'start',
      'segmentId': segmentId,
      'hotwords': hotwords,
    });
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
    if (!_backlog.enqueue(samples.length)) {
      _emitDiagnostics(
        error:
            'Speech recognition fell more than 10 seconds behind; this transmission was interrupted.',
        force: true,
      );
      return;
    }
    _workerSend!.send({
      'cmd': 'audio',
      'segmentId': _segmentId,
      'samples': samples,
    });
    _emitDiagnostics();
  }

  @override
  Future<void> completeSegment() async {
    if (_ready && !_disposed) {
      _workerSend!.send({'cmd': 'complete', 'segmentId': _segmentId});
    }
  }

  @override
  Future<void> splitSegment() async {
    if (_ready && !_disposed) {
      _workerSend!.send({'cmd': 'split', 'segmentId': _segmentId});
    }
  }

  @override
  Future<void> resetSegment() async {
    _resampler.reset();
    if (_ready && !_disposed) {
      _workerSend!.send({'cmd': 'reset', 'segmentId': _segmentId});
    }
  }

  @override
  Future<void> dispose() async {
    _ready = false;
    if (!(_readyCompleter?.isCompleted ?? true)) {
      _readyCompleter!.complete(false);
    }
    try {
      if (_workerSend != null) {
        _exited = Completer<void>();
        _workerSend!.send(const {'cmd': 'dispose'});
        await _exited!.future.timeout(const Duration(seconds: 2));
      }
    } finally {
      _disposed = true;
      _receivePort?.close();
      _isolate?.kill(priority: Isolate.beforeNextEvent);
      await _results.close();
      await _processing.close();
      await _diagnostics.close();
    }
  }

  static String _languageFromLocale(String localeId) {
    final lang = localeId.split(RegExp('[-_]')).first.toLowerCase();
    return const {'zh', 'en', 'ja', 'ko', 'yue'}.contains(lang) ? lang : 'auto';
  }
}

class _LinearResampler {
  _LinearResampler(this.targetRate);
  final int targetRate;
  double _nextPos = 0;
  double _prev = 0;
  bool _hasPrev = false;

  void reset() {
    _nextPos = 0;
    _prev = 0;
    _hasPrev = false;
  }

  Float32List process(Uint8List data, int offset, int length, int sourceRate) {
    final count = length ~/ 2;
    if (count == 0) return Float32List(0);
    final view = ByteData.sublistView(data, offset, offset + count * 2);
    double at(int i) => i < 0
        ? (_hasPrev ? _prev : view.getInt16(0, Endian.little) / 32768)
        : view.getInt16(i * 2, Endian.little) / 32768;
    final ratio = sourceRate / targetRate;
    final output = <double>[];
    var pos = _nextPos;
    while (pos <= count - 1) {
      final index = pos.floor();
      final fraction = pos - index;
      output.add(
        fraction == 0
            ? at(index)
            : at(index) + (at(index + 1) - at(index)) * fraction,
      );
      pos += ratio;
    }
    _nextPos = pos - count;
    _prev = at(count - 1);
    _hasPrev = true;
    return Float32List.fromList(output);
  }
}

void _sherpaWorkerEntry(SendPort main) {
  final commands = ReceivePort();
  main.send({'event': 'port', 'port': commands.sendPort});
  sherpa.OfflineRecognizer? offline;
  sherpa.OnlineRecognizer? online;
  sherpa.OnlineStream? stream;
  sherpa.VoiceActivityDetector? vad;
  final gate = SpeechAudioGate();
  final audio = <Float32List>[];
  var pending = Float32List(0);
  var audioSamples = 0;
  var hasNewAudio = false;
  var segmentId = 0;
  var committed = '';
  var lastPartial = '';
  var overlap = false;
  var hotwords = '';
  const rate = 16000;
  const window = 512;

  void emitResult(bool isFinal, [String? hypothesis]) {
    final text = hypothesis ?? committed;
    if (!isFinal && text == lastPartial) return;
    lastPartial = text;
    main.send({
      'event': 'result',
      'segmentId': segmentId,
      'text': text,
      'isFinal': isFinal,
    });
  }

  Float32List flattenAudio() {
    final samples = Float32List(audioSamples);
    var offset = 0;
    for (final chunk in audio) {
      samples.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return samples;
  }

  String drainStreaming() {
    final timer = Stopwatch()..start();
    var decoded = false;
    while (online!.isReady(stream!)) {
      online!.decode(stream!);
      decoded = true;
    }
    if (decoded) {
      main.send({'event': 'decode', 'decodeMs': timer.elapsedMilliseconds});
    }
    return online!.getResult(stream!).text;
  }

  void finishUtterance({bool keepOverlap = false}) {
    if (audioSamples == 0 || !hasNewAudio) return;
    final timer = Stopwatch()..start();
    main.send({'event': 'processing', 'active': true});
    final samples = flattenAudio();
    String text;
    if (online != null) {
      // Flush encoder look-ahead before asking for the final hypothesis.
      stream!.acceptWaveform(samples: Float32List(rate ~/ 3), sampleRate: rate);
      stream!.inputFinished();
      text = drainStreaming();
      stream!.free();
      stream = null;
    } else {
      final utterance = offline!.createStream();
      try {
        utterance.acceptWaveform(samples: samples, sampleRate: rate);
        offline!.decode(utterance);
        text = offline!.getResult(utterance).text;
      } finally {
        utterance.free();
      }
    }
    committed = appendSpeechText(committed, text, overlap: overlap);
    audio.clear();
    audioSamples = 0;
    hasNewAudio = false;
    overlap = keepOverlap;
    if (keepOverlap) {
      final count = online == null ? rate * 2 : rate ~/ 3;
      final start = (samples.length - count).clamp(0, samples.length);
      audio.add(Float32List.sublistView(samples, start));
      audioSamples = samples.length - start;
      if (online != null) {
        stream = online!.createStream(hotwords: hotwords);
        stream!.acceptWaveform(samples: audio.single, sampleRate: rate);
      }
      // Bound the native VAD's active-segment storage as well as ASR audio.
      vad!.reset();
      gate.reset();
    }
    emitResult(false);
    main.send({'event': 'decode', 'decodeMs': timer.elapsedMilliseconds});
    main.send({'event': 'processing', 'active': false});
  }

  void acceptSpeech(Float32List frame) {
    hasNewAudio = true;
    audio.add(frame);
    audioSamples += frame.length;
    if (online != null) {
      stream ??= online!.createStream(hotwords: hotwords);
      stream!.acceptWaveform(samples: frame, sampleRate: rate);
      emitResult(
        false,
        appendSpeechText(committed, drainStreaming(), overlap: overlap),
      );
    }
    // Includes retained overlap, so Whisper never receives >=30 seconds.
    if (audioSamples >= rate * 26) {
      finishUtterance(keepOverlap: true);
    }
  }

  void acceptWindow(Float32List frame) {
    vad!.acceptWaveform(frame);
    final update = gate.process(frame, vad!.isDetected());
    for (final samples in update.audio) {
      acceptSpeech(samples);
    }
    if (update.ended) finishUtterance();
    while (!vad!.isEmpty()) {
      vad!.pop();
    }
  }

  void reset() {
    stream?.free();
    stream = null;
    audio.clear();
    audioSamples = 0;
    hasNewAudio = false;
    pending = Float32List(0);
    gate.reset();
    vad?.reset();
    committed = '';
    lastPartial = '';
    overlap = false;
  }

  commands.listen((dynamic message) {
    if (message is! Map) return;
    final cmd = message['cmd'];
    final timer = Stopwatch()..start();
    try {
      if (cmd == 'init') {
        sherpa.initBindings();
        final files = (message['files'] as Map).cast<String, String>();
        final tokens = files['tokens.txt']!;
        vad = sherpa.VoiceActivityDetector(
          config: sherpa.VadModelConfig(
            sileroVad: sherpa.SileroVadModelConfig(
              model: files['silero_vad.onnx']!,
              threshold: 0.35,
              minSpeechDuration: 0.064,
              minSilenceDuration: 0.65,
              maxSpeechDuration: 27,
            ),
            debug: false,
          ),
          bufferSizeInSeconds: 30,
        );
        if (message['family'] == 'streamingZipformer') {
          online = sherpa.OnlineRecognizer(
            sherpa.OnlineRecognizerConfig(
              model: sherpa.OnlineModelConfig(
                transducer: sherpa.OnlineTransducerModelConfig(
                  encoder: files['encoder.int8.onnx']!,
                  decoder: files['decoder.onnx']!,
                  joiner: files['joiner.int8.onnx']!,
                ),
                tokens: tokens,
                modelingUnit: 'bpe',
                bpeVocab: files['bpe.vocab']!,
                numThreads: 2,
                debug: false,
              ),
              decodingMethod: 'modified_beam_search',
              maxActivePaths: 4,
              hotwordsScore: 0.5,
              enableEndpoint: false,
            ),
          );
        } else {
          final lang = message['language'] as String;
          final model = message['family'] == 'whisper'
              ? sherpa.OfflineModelConfig(
                  whisper: sherpa.OfflineWhisperModelConfig(
                    encoder: files['encoder.int8.onnx']!,
                    decoder: files['decoder.int8.onnx']!,
                    language: lang == 'auto' ? '' : lang,
                    task: 'transcribe',
                  ),
                  tokens: tokens,
                  numThreads: 2,
                  debug: false,
                )
              : sherpa.OfflineModelConfig(
                  senseVoice: sherpa.OfflineSenseVoiceModelConfig(
                    model: files['model.int8.onnx']!,
                    language: lang,
                    useInverseTextNormalization: true,
                  ),
                  tokens: tokens,
                  numThreads: 2,
                  debug: false,
                );
          offline = sherpa.OfflineRecognizer(
            sherpa.OfflineRecognizerConfig(model: model),
          );
        }
        main.send({'event': 'ready', 'ok': true});
      } else if (cmd == 'start') {
        reset();
        segmentId = message['segmentId'] as int;
        hotwords = online == null
            ? ''
            : (message['hotwords'] as List)
                  .cast<String>()
                  .map((phrase) => phrase.toUpperCase())
                  .join('/');
      } else if (cmd == 'dispose') {
        reset();
        vad?.free();
        online?.free();
        offline?.free();
        commands.close();
        Isolate.exit();
      } else if (message['segmentId'] == segmentId) {
        switch (cmd) {
          case 'audio':
            final samples = message['samples'] as Float32List;
            final joined = Float32List(pending.length + samples.length)
              ..setAll(0, pending)
              ..setAll(pending.length, samples);
            var offset = 0;
            while (offset + window <= joined.length) {
              acceptWindow(
                Float32List.sublistView(joined, offset, offset + window),
              );
              offset += window;
            }
            pending = Float32List.fromList(joined.sublist(offset));
            break;
          case 'complete':
            if (pending.isNotEmpty) {
              acceptWindow(Float32List(window)..setAll(0, pending));
            }
            vad!.flush();
            finishUtterance();
            emitResult(true);
            reset();
            break;
          case 'split':
            finishUtterance(keepOverlap: true);
            break;
          case 'reset':
            reset();
            main.send({'event': 'processing', 'active': false});
            break;
        }
      }
    } catch (e) {
      main.send({
        'event': 'error',
        'segmentId': segmentId,
        'message': 'Speech $cmd failed: $e',
      });
      if (cmd == 'init') main.send({'event': 'ready', 'ok': false});
      main.send({'event': 'processing', 'active': false});
    } finally {
      if (cmd == 'audio') {
        main.send({
          'event': 'ack',
          'samples': (message['samples'] as Float32List).length,
          'decodeMs': timer.elapsedMilliseconds,
        });
      }
    }
  });
}
