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

import 'pcm_mixer.dart';

/// Called when the audio engine drains, reporting the number of PCM frames
/// still buffered for playback.
typedef PcmFeedCallback = void Function(int remainingFrames);

/// Cross-platform 16-bit PCM playback sink.
///
/// flutter_pcm_sound only ships Android / iOS implementations that route to the
/// OS default device, so on Windows, Linux and macOS we use a native player
/// (see windows/runner/pcm_player_plugin, linux/runner/pcm_player_plugin and the
/// macOS PcmPlayerHandler) exposing the same small surface over the
/// `com.htcommander/pcm_player` channels, which also supports output-device
/// selection. Unsupported platforms (web) are
/// no-ops so callers degrade gracefully instead of crashing.
abstract class PcmPlayer {
  /// Returns a reference-counted handle onto the single process-wide audio
  /// Returns a handle onto the single process-wide audio device.
  ///
  /// Both the radio audio path and EchoLink each construct their own
  /// [PcmPlayer] and independently drive setup / start / feed / release. On
  /// every desktop platform (and via the global flutter_pcm_sound API on
  /// mobile) those calls land on ONE shared native output device. The returned
  /// handle is a [PcmMixer] source, so several owners playing at once are summed
  /// into that single device (instead of interleaved), and the device is opened
  /// once and torn down only when the last owner releases — see
  /// [_MixerPcmPlayer].
  factory PcmPlayer() => _MixerPcmPlayer();

  /// Constructs the real platform-specific player. Exactly one instance is
  /// created for the whole process and is driven by the shared [PcmMixer] (see
  /// [_MixerPcmPlayer._mixer]).
  static PcmPlayer _createReal() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return _NativeChannelPcmPlayer();
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return _FlutterPcmSoundPlayer();
    }
    return _NoopPcmPlayer();
  }

  /// Lower plugin log verbosity where supported; never throws.
  Future<void> setLogLevelError();

  /// Configure the output format and open the audio device.
  ///
  /// [deviceId] selects a specific output device where supported (currently the
  /// native Linux player, using a PulseAudio sink name); null or empty means the
  /// operating-system default device. Implementations that cannot select a
  /// device ignore it and use the default.
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
    String? deviceId,
  });

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
    String? deviceId,
  }) {
    // flutter_pcm_sound always plays on the OS default device; deviceId ignored.
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

/// Windows / Linux implementation backed by a native plugin exposing the
/// `com.htcommander/pcm_player` method channel and `..._feed` event channel.
class _NativeChannelPcmPlayer implements PcmPlayer {
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
    String? deviceId,
  }) async {
    await _method.invokeMethod<bool>('setup', {
      'sampleRate': sampleRate,
      'channels': channelCount,
      'deviceId': deviceId ?? '',
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
    String? deviceId,
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

/// Process-wide handle onto the single real [PcmPlayer], routed through the
/// shared [PcmMixer].
///
/// The radio audio path, each connected radio, EchoLink and the Morse sidetone
/// each construct their own [PcmPlayer], but there is only one native output
/// device behind them (the desktop plugins share a single method/event channel;
/// flutter_pcm_sound is a global singleton on mobile). Each handle is registered
/// as an independent [PcmMixerSource]:
///  * The device is opened only on the first owner's setup() and closed only
///    when the last owner releases, so it is never torn down while another owner
///    is still streaming.
///  * All setup() / release() / reconfigure bookkeeping is serialized inside the
///    mixer, so two owners can never race the device lifecycle.
///  * Audio from every active owner is SUMMED by the mixer into one stream, so
///    simultaneous sources play at the same time instead of interleaving; each
///    owner's drain callback reports only its own queued backlog.
class _MixerPcmPlayer implements PcmPlayer {
  // One mixer for the whole process, driving the one real output device.
  static final PcmMixer _mixer = PcmMixer(PcmPlayer._createReal());

  late final PcmMixerSource _source = _mixer.createSource();

  @override
  Future<void> setLogLevelError() => _mixer.setLogLevelError();

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
    String? deviceId,
  }) {
    return _mixer.addSource(
      _source,
      sampleRate: sampleRate,
      channelCount: channelCount,
      deviceId: deviceId,
    );
  }

  @override
  Future<void> setFeedThreshold(int frames) => _mixer.setFeedThreshold(frames);

  @override
  void setFeedCallback(PcmFeedCallback? callback) =>
      _source.setCallback(callback);

  @override
  void start() {
    // The device is started when the mixer opens it; the mixer's pump clock is
    // (re)started automatically when audio is fed, so this is a no-op.
  }

  @override
  Future<void> feed(Int16List pcm) {
    _source.feed(pcm);
    return Future<void>.value();
  }

  @override
  Future<void> release() => _mixer.removeSource(_source);
}

