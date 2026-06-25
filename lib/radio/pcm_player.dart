/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Called when the audio engine drains, reporting the number of PCM frames
/// still buffered for playback.
typedef PcmFeedCallback = void Function(int remainingFrames);

/// Cross-platform 16-bit PCM playback sink.
///
/// flutter_pcm_sound only ships Android / iOS / macOS implementations, so on
/// Windows we use a native waveOut player (see windows/runner/pcm_player_plugin)
/// exposing the same small surface. Unsupported platforms (Linux / web) are
/// no-ops so callers degrade gracefully instead of crashing.
abstract class PcmPlayer {
  factory PcmPlayer() {
    if (!kIsWeb && Platform.isWindows) return _WindowsPcmPlayer();
    if (!kIsWeb &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return _FlutterPcmSoundPlayer();
    }
    return _NoopPcmPlayer();
  }

  /// Lower plugin log verbosity where supported; never throws.
  Future<void> setLogLevelError();

  /// Configure the output format and open the audio device.
  Future<void> setup({required int sampleRate, required int channelCount});

  /// Set the buffered-frame threshold below which [setFeedCallback] fires.
  Future<void> setFeedThreshold(int frames);

  /// Register (or clear, with null) the drain callback.
  void setFeedCallback(PcmFeedCallback? callback);

  /// Begin playback.
  void start();

  /// Queue 16-bit PCM samples for playback.
  Future<void> feed(Int16List pcm);

  /// Stop playback and release the audio device.
  Future<void> release();
}

/// Android / iOS / macOS implementation backed by flutter_pcm_sound.
class _FlutterPcmSoundPlayer implements PcmPlayer {
  @override
  Future<void> setLogLevelError() async {
    try {
      await FlutterPcmSound.setLogLevel(LogLevel.error);
    } catch (_) {
      // Not implemented on every platform; ignore.
    }
  }

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
  }) {
    return FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: channelCount,
    );
  }

  @override
  Future<void> setFeedThreshold(int frames) {
    return FlutterPcmSound.setFeedThreshold(frames);
  }

  @override
  void setFeedCallback(PcmFeedCallback? callback) {
    FlutterPcmSound.setFeedCallback(
      callback == null ? null : (remaining) => callback(remaining),
    );
  }

  @override
  void start() => FlutterPcmSound.start();

  @override
  Future<void> feed(Int16List pcm) {
    return FlutterPcmSound.feed(PcmArrayInt16.fromList(pcm));
  }

  @override
  Future<void> release() => FlutterPcmSound.release();
}

/// Windows implementation backed by the native waveOut plugin.
class _WindowsPcmPlayer implements PcmPlayer {
  static const MethodChannel _method =
      MethodChannel('com.htcommander/pcm_player');
  static const EventChannel _feedEvents =
      EventChannel('com.htcommander/pcm_player_feed');

  StreamSubscription<dynamic>? _feedSub;
  PcmFeedCallback? _callback;

  @override
  Future<void> setLogLevelError() async {}

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
  }) async {
    await _method.invokeMethod<bool>('setup', {
      'sampleRate': sampleRate,
      'channels': channelCount,
    });
  }

  @override
  Future<void> setFeedThreshold(int frames) async {
    await _method.invokeMethod<void>('setFeedThreshold', {'threshold': frames});
  }

  @override
  void setFeedCallback(PcmFeedCallback? callback) {
    _callback = callback;
    _feedSub?.cancel();
    if (callback == null) {
      _feedSub = null;
      return;
    }
    _feedSub = _feedEvents.receiveBroadcastStream().listen((event) {
      if (event is int) _callback?.call(event);
    });
  }

  @override
  void start() {
    _method.invokeMethod<void>('start');
  }

  @override
  Future<void> feed(Int16List pcm) async {
    final bytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
    await _method.invokeMethod<bool>('feed', {'buffer': bytes});
  }

  @override
  Future<void> release() async {
    await _feedSub?.cancel();
    _feedSub = null;
    await _method.invokeMethod<void>('release');
  }
}

/// No-op implementation for platforms without PCM playback support.
class _NoopPcmPlayer implements PcmPlayer {
  @override
  Future<void> setLogLevelError() async {}

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
  }) async {}

  @override
  Future<void> setFeedThreshold(int frames) async {}

  @override
  void setFeedCallback(PcmFeedCallback? callback) {}

  @override
  void start() {}

  @override
  Future<void> feed(Int16List pcm) async {}

  @override
  Future<void> release() async {}
}
