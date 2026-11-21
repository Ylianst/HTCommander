/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Speech-to-text engine abstraction for the CommsHandler.

Desktop uses sherpa-onnx; Android 13+ feeds PCM to its on-device recognizer.
Web and iOS do not support radio audio streams and must not run recognition.
*/

import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

// The sherpa-onnx engine depends on dart:ffi and must never be compiled into
// the web build. Resolve to the native factory only on dart:io platforms; web
// falls back to the no-op stub so speech-to-text is fully removed there.
import 'speech_to_text_engine_stub.dart'
    if (dart.library.io) 'speech_to_text_engine_native.dart';

bool get isRadioSpeechSupported =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

/// A single speech-recognition result for the current voice segment.
class SpeechResult {
  final int segmentId;

  /// The recognized text so far (cumulative for the active segment).
  final String text;

  /// True when this is the final result for the segment; further results
  /// belong to a new segment.
  final bool isFinal;

  const SpeechResult(this.text, this.isFinal, {required this.segmentId});
}

class SpeechDiagnostics {
  final int segmentId;
  final int queuedAudioMs;
  final int decodeMs;
  final bool overloaded;
  final String? error;

  const SpeechDiagnostics({
    required this.segmentId,
    this.queuedAudioMs = 0,
    this.decodeMs = 0,
    this.overloaded = false,
    this.error,
  });
}

/// Streaming speech-to-text engine. Implementations transcribe 16-bit signed
/// little-endian mono PCM that is pushed in via [processPcm16].
abstract class SpeechToTextEngine {
  /// Whether this platform provides a real recognition backend.
  bool get isSupported;

  /// True once [initialize] has succeeded and recognition can run.
  bool get isReady;

  /// Partial and final recognition results for the active segment.
  Stream<SpeechResult> get results;

  /// Emits true while audio is being actively recognized, false otherwise.
  Stream<bool> get processing;

  Stream<SpeechDiagnostics> get diagnostics;

  /// Prepares the engine (permissions, locale, model). Returns true if speech
  /// recognition is available and authorized. Safe to call more than once.
  ///
  /// [localeId] is a BCP-47 identifier (e.g. "en-US"); an empty string or
  /// "auto" uses the device default locale.
  Future<bool> initialize({String localeId = ''});

  /// Begins a new voice segment. Any in-progress segment is discarded.
  Future<void> startSegment({
    required int segmentId,
    List<String> hotwords = const [],
  });

  /// Pushes a chunk of 16-bit signed little-endian mono PCM at [sampleRate]
  /// (Hz) into the active segment.
  Future<void> processPcm16(
    Uint8List data,
    int offset,
    int length,
    int sampleRate,
  );

  /// Finishes the active segment, forcing the engine to emit a final result.
  Future<void> completeSegment();

  /// Flushes an internal recognition chunk without ending the transmission.
  /// Results remain cumulative and retain the same segment ID.
  Future<void> splitSegment();

  /// Discards the active segment without emitting a final result.
  Future<void> resetSegment();

  /// Releases all engine resources.
  Future<void> dispose();
}

/// Returns the speech-to-text engine appropriate for the current platform.
///
/// Web and iOS are unsupported; desktop and Android accept radio PCM.
SpeechToTextEngine createSpeechToTextEngine() {
  if (!isRadioSpeechSupported) return UnsupportedSpeechToTextEngine();
  return createPlatformSpeechToTextEngine();
}

/// No-op engine for platforms without radio audio streams.
class UnsupportedSpeechToTextEngine implements SpeechToTextEngine {
  final StreamController<SpeechResult> _results =
      StreamController<SpeechResult>.broadcast();
  final StreamController<bool> _processing = StreamController<bool>.broadcast();

  @override
  bool get isSupported => false;

  @override
  bool get isReady => false;

  @override
  Stream<SpeechResult> get results => _results.stream;

  @override
  Stream<bool> get processing => _processing.stream;

  @override
  Stream<SpeechDiagnostics> get diagnostics => const Stream.empty();

  @override
  Future<bool> initialize({String localeId = ''}) async => false;

  @override
  Future<void> startSegment({
    required int segmentId,
    List<String> hotwords = const [],
  }) async {}

  @override
  Future<void> processPcm16(
    Uint8List data,
    int offset,
    int length,
    int sampleRate,
  ) async {}

  @override
  Future<void> completeSegment() async {}

  @override
  Future<void> splitSegment() async {}

  @override
  Future<void> resetSegment() async {}

  @override
  Future<void> dispose() async {
    await _results.close();
    await _processing.close();
  }
}

/// Apple (macOS / iOS) engine backed by a native `SFSpeechRecognizer` plugin
/// that accepts PCM buffers. The native side is implemented in Swift in the
/// macOS and iOS runners and bridged over the channels below.
class AppleSpeechToTextEngine implements SpeechToTextEngine {
  int _segmentId = 0;
  static const MethodChannel _channel = MethodChannel(
    'com.htcommander/speech_to_text',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.htcommander/speech_to_text_events',
  );

  final StreamController<SpeechResult> _results =
      StreamController<SpeechResult>.broadcast();
  final StreamController<bool> _processing = StreamController<bool>.broadcast();

  StreamSubscription<dynamic>? _eventSub;
  bool _ready = false;
  bool _disposed = false;

  @override
  bool get isSupported => true;

  @override
  bool get isReady => _ready;

  @override
  Stream<SpeechResult> get results => _results.stream;

  @override
  Stream<bool> get processing => _processing.stream;

  @override
  Stream<SpeechDiagnostics> get diagnostics => const Stream.empty();

  @override
  Future<bool> initialize({String localeId = ''}) async {
    if (_disposed) return false;
    _listenEvents();
    try {
      final available = await _channel.invokeMethod<bool>('initialize', {
        'localeId': localeId,
      });
      _ready = available ?? false;
      return _ready;
    } on PlatformException catch (e) {
      _ready = false;
      _emitError('initialize failed: ${e.message}');
      return false;
    } on MissingPluginException {
      _ready = false;
      return false;
    }
  }

  void _listenEvents() {
    _eventSub ??= _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final type = event['event'] as String?;
      switch (type) {
        case 'result':
          final text = (event['text'] as String?) ?? '';
          final isFinal = (event['isFinal'] as bool?) ?? false;
          if (!_results.isClosed) {
            _results.add(SpeechResult(text, isFinal, segmentId: _segmentId));
          }
          break;
        case 'processing':
          final active = (event['active'] as bool?) ?? false;
          if (!_processing.isClosed) _processing.add(active);
          break;
        case 'error':
          _emitError((event['message'] as String?) ?? 'unknown error');
          break;
      }
    }, onError: (Object error) => _emitError('event stream error: $error'));
  }

  void _emitError(String message) {
    // Errors surface as a final empty result so callers can end the segment;
    // detailed diagnostics are logged by the CommsHandler.
    if (!_processing.isClosed) _processing.add(false);
  }

  @override
  Future<void> startSegment({
    required int segmentId,
    List<String> hotwords = const [],
  }) async {
    _segmentId = segmentId;
    if (!_ready || _disposed) return;
    try {
      await _channel.invokeMethod('startSegment');
    } on PlatformException catch (e) {
      _emitError('startSegment failed: ${e.message}');
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<void> processPcm16(
    Uint8List data,
    int offset,
    int length,
    int sampleRate,
  ) async {
    if (!_ready || _disposed || length <= 0) return;
    // Copy the relevant slice so the native side gets a standalone buffer and
    // the caller's array can be reused immediately.
    final chunk = Uint8List.sublistView(data, offset, offset + length);
    try {
      await _channel.invokeMethod('appendAudio', {
        'data': chunk,
        'sampleRate': sampleRate,
      });
    } on PlatformException catch (e) {
      _emitError('appendAudio failed: ${e.message}');
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<void> completeSegment() async {
    if (!_ready || _disposed) return;
    try {
      await _channel.invokeMethod('completeSegment');
    } on PlatformException catch (e) {
      _emitError('completeSegment failed: ${e.message}');
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<void> splitSegment() async {
    // Apple engine has no native split; just complete and restart.
    await completeSegment();
    await startSegment(segmentId: _segmentId);
  }

  @override
  Future<void> resetSegment() async {
    if (!_ready || _disposed) return;
    try {
      await _channel.invokeMethod('resetSegment');
    } on PlatformException catch (e) {
      _emitError('resetSegment failed: ${e.message}');
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {
      // Ignore disposal errors.
    }
    await _eventSub?.cancel();
    _eventSub = null;
    await _results.close();
    await _processing.close();
  }
}
