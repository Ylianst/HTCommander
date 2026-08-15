/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Android speech-to-text engine backed by the platform on-device recognizer.

Unlike the desktop sherpa-onnx engine, this engine downloads no model into the
APK: it feeds raw PCM into Android's own `SpeechRecognizer` through the
`RecognizerIntent.EXTRA_AUDIO_SOURCE` file descriptor added in API 33
(Android 13). The recognizer reads audio from a pipe instead of opening the
microphone, so received radio audio can be transcribed with the OS-managed
language model.

The recognizer's audio source is fixed at 16 kHz mono 16-bit PCM (the
`EXTRA_AUDIO_SOURCE` defaults), so incoming radio PCM (typically 32 kHz) is
resampled to 16 kHz here before being handed to the native side. The Kotlin
plugin (AndroidSpeechToTextPlugin) implements the channel contract below.
*/

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'speech_to_text_engine.dart';

/// Android engine that streams PCM into the platform on-device recognizer via
/// `RecognizerIntent.EXTRA_AUDIO_SOURCE`. Requires Android 13 (API 33) or newer
/// with an on-device recognizer available; [initialize] returns false
/// otherwise.
class AndroidSpeechToTextEngine implements SpeechToTextEngine {
  static const MethodChannel _channel = MethodChannel(
    'com.htcommander/android_speech_to_text',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.htcommander/android_speech_to_text_events',
  );

  /// Fixed sample rate the native recognizer expects (matches the
  /// `EXTRA_AUDIO_SOURCE_SAMPLING_RATE` default).
  static const int _targetSampleRate = 16000;

  final StreamController<SpeechResult> _results =
      StreamController<SpeechResult>.broadcast();
  final StreamController<bool> _processing = StreamController<bool>.broadcast();

  /// Streaming resampler that converts the incoming PCM to [_targetSampleRate].
  final _LinearResampler _resampler = _LinearResampler(_targetSampleRate);

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
  Future<bool> initialize({String localeId = ''}) async {
    if (_disposed) return false;

    // SpeechRecognizer requires RECORD_AUDIO to be granted even when audio is
    // fed via a file descriptor rather than the microphone.
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _ready = false;
      return false;
    }

    _listenEvents();
    try {
      final available = await _channel.invokeMethod<bool>('initialize', {
        'localeId': localeId,
      });
      _ready = available ?? false;
      return _ready;
    } on PlatformException {
      _ready = false;
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
          if (!_results.isClosed) _results.add(SpeechResult(text, isFinal));
          break;
        case 'processing':
          final active = (event['active'] as bool?) ?? false;
          if (!_processing.isClosed) _processing.add(active);
          break;
        case 'error':
          if (!_processing.isClosed) _processing.add(false);
          break;
      }
    }, onError: (Object _) {
      if (!_processing.isClosed) _processing.add(false);
    });
  }

  @override
  Future<void> startSegment() async {
    if (!_ready || _disposed) return;
    _resampler.reset();
    try {
      await _channel.invokeMethod('startSegment');
    } on PlatformException {
      // Ignore; a failed start simply produces no results for this segment.
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
    final chunk = _resampler.process(data, offset, length, sampleRate);
    if (chunk.isEmpty) return;
    try {
      await _channel.invokeMethod('appendAudio', {
        'data': chunk,
        'sampleRate': _targetSampleRate,
      });
    } on PlatformException {
      // Ignore transient write errors (e.g. session already finalized).
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<void> completeSegment() async {
    if (!_ready || _disposed) return;
    try {
      await _channel.invokeMethod('completeSegment');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      _ready = false;
    }
  }

  @override
  Future<void> splitSegment() async {
    // No native split; complete the current session and open a new one.
    await completeSegment();
    await startSegment();
  }

  @override
  Future<void> resetSegment() async {
    if (!_ready || _disposed) return;
    try {
      await _channel.invokeMethod('resetSegment');
    } on PlatformException {
      // Ignore.
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

/// Linear-interpolation resampler that converts a stream of 16-bit signed
/// little-endian mono PCM at an arbitrary input rate to [outRate], preserving
/// fractional phase across chunk boundaries. [reset] clears the state at the
/// start of each new segment.
class _LinearResampler {
  _LinearResampler(this.outRate);

  final int outRate;
  int _inRate = 0;
  double _pos = 0.0;
  int _prevSample = 0;
  bool _hasPrev = false;

  void reset() {
    _pos = 0.0;
    _prevSample = 0;
    _hasPrev = false;
  }

  /// Resamples [length] bytes of PCM starting at [offset] in [data]. Returns a
  /// freshly allocated 16-bit LE PCM buffer at [outRate].
  Uint8List process(Uint8List data, int offset, int length, int inRate) {
    if (inRate != _inRate) {
      _inRate = inRate;
    }
    if (_inRate <= 0) return Uint8List(0);

    final int sampleCount = length ~/ 2;
    if (sampleCount == 0) return Uint8List(0);

    final view = ByteData.sublistView(data, offset, offset + sampleCount * 2);

    // Pass-through when the rates already match.
    if (_inRate == outRate) {
      final out = Uint8List(sampleCount * 2);
      out.setRange(0, out.length, data, offset);
      return out;
    }

    final double step = _inRate / outRate;
    // Estimate output capacity generously, then trim.
    final estimate = ((sampleCount / step) + 2).ceil();
    final outData = ByteData(estimate * 2);
    int outCount = 0;

    // Absolute sample index within the concatenated input stream. _pos is kept
    // relative to the first sample of the current chunk.
    while (_pos < sampleCount) {
      final int idx = _pos.floor();
      final double frac = _pos - idx;

      final int cur = view.getInt16(idx * 2, Endian.little);
      final int prev = idx == 0
          ? (_hasPrev ? _prevSample : cur)
          : view.getInt16((idx - 1) * 2, Endian.little);

      // Interpolate between the previous and current input sample.
      final double interpolated = prev + (cur - prev) * frac;
      int s = interpolated.round();
      if (s > 32767) s = 32767;
      if (s < -32768) s = -32768;
      outData.setInt16(outCount * 2, s, Endian.little);
      outCount++;

      _pos += step;
    }

    // Carry the fractional position and last sample into the next chunk.
    _pos -= sampleCount;
    _prevSample = view.getInt16((sampleCount - 1) * 2, Endian.little);
    _hasPrev = true;

    return Uint8List.view(outData.buffer, 0, outCount * 2);
  }
}
