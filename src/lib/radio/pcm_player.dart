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
/// flutter_pcm_sound only ships Android / iOS implementations that route to the
/// OS default device, so on Windows, Linux and macOS we use a native player
/// (see windows/runner/pcm_player_plugin, linux/runner/pcm_player_plugin and the
/// macOS PcmPlayerHandler) exposing the same small surface over the
/// `com.htcommander/pcm_player` channels, which also supports output-device
/// selection. Unsupported platforms (web) are
/// no-ops so callers degrade gracefully instead of crashing.
abstract class PcmPlayer {
  /// Optional tap invoked with every 16-bit PCM buffer fed to the shared output
  /// device, alongside its current sample rate and channel count. Used to mirror
  /// host playback (radio RX, transmit, EchoLink, AllStarLink, ...) to hosted
  /// web browsers; set by the web server handler on desktop. Kept lightweight —
  /// it runs on the audio feed path.
  static void Function(Int16List pcm, int sampleRate, int channels)?
  playbackTap;

  /// Host application output volume (0.0-1.0), applied to every buffer AFTER
  /// [playbackTap]. This lets the web mirror receive full-volume audio while the
  /// host speaker honors the level, so the two sides can be muted independently.
  static double hostOutputVolume = 1.0;

  /// Returns a reference-counted handle onto the single process-wide audio
  /// device.
  ///
  /// Both the radio audio path and EchoLink each construct their own
  /// [PcmPlayer] and independently drive setup / start / feed / release. On
  /// every desktop platform (and via the global flutter_pcm_sound API on
  /// mobile) those calls land on ONE shared native output device. The returned
  /// handle multiplexes all owners onto that single device so it is opened once
  /// and torn down only when the last owner releases — see
  /// [_RefCountedPcmPlayer].
  factory PcmPlayer() => _RefCountedPcmPlayer();

  /// Constructs the real platform-specific player. Exactly one instance is
  /// created for the whole process (see [_RefCountedPcmPlayer._shared]).
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

/// Process-wide, reference-counted wrapper around the single real [PcmPlayer].
///
/// The radio audio path and EchoLink each construct their own [PcmPlayer], but
/// there is only one native output device behind them (the desktop plugins share
/// a single method/event channel; flutter_pcm_sound is a global singleton on
/// mobile). Previously each owner independently called setup() / release() on
/// that shared device. Because the native `setup()` first *closes* the device
/// and frees its in-flight buffers, one owner opening the device while another
/// was streaming — exactly what happens when the app connects to the radio and
/// EchoLink at the same time on startup — tore the device out from under the
/// other owner's buffers, producing an intermittent native access violation.
///
/// This wrapper fixes that by giving every owner a lightweight handle onto one
/// shared real player:
///  * The device is opened only on the first owner's setup() and closed only
///    when the last owner releases, so it is never torn down while another owner
///    is still streaming.
///  * All setup() / release() / reconfigure bookkeeping is serialized through a
///    single async queue, so two owners can never race the reference count.
///  * The device-wide drain callback is fanned out to every active owner.
///
/// A later setup() that requests a different format or output device (e.g. the
/// user changing the radio's output device) reconfigures the shared device in
/// place — still serialized, so there is no concurrent teardown.
class _RefCountedPcmPlayer implements PcmPlayer {
  _RefCountedPcmPlayer();

  // ---- shared state: one real device for the whole process ----
  static final PcmPlayer _shared = PcmPlayer._createReal();
  static final Set<_RefCountedPcmPlayer> _owners = <_RefCountedPcmPlayer>{};
  static int _refCount = 0;
  static bool _deviceOpen = false;
  static int? _rate;
  static int? _channels;
  static String? _deviceId;
  static int? _threshold;
  // Serializes async setup() / release() / reconfigure across all owners so the
  // reference count and device lifecycle are only ever mutated one op at a time.
  static Future<void> _opQueue = Future<void>.value();

  // ---- per-owner state ----
  bool _active = false;
  PcmFeedCallback? _callback;

  /// Chains [action] after any in-flight setup/release so reference-count and
  /// device-lifecycle mutations never overlap.
  static Future<void> _serialize(Future<void> Function() action) {
    final Completer<void> done = Completer<void>();
    _opQueue = _opQueue.then((_) async {
      try {
        await action();
        done.complete();
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  /// Fans the single device-wide drain callback out to every active owner.
  static void _dispatchFeed(int remaining) {
    for (final owner in _owners.toList(growable: false)) {
      owner._callback?.call(remaining);
    }
  }

  /// Opens (or, after a release(), re-opens) the shared device with the current
  /// [_rate] / [_channels] / [_deviceId] and re-installs the drain callback.
  static Future<void> _openDevice() async {
    await _shared.setup(
      sampleRate: _rate ?? 32000,
      channelCount: _channels ?? 1,
      deviceId: (_deviceId?.isEmpty ?? true) ? null : _deviceId,
    );
    if (_threshold != null) {
      await _shared.setFeedThreshold(_threshold!);
    }
    _shared.setFeedCallback(_dispatchFeed);
    _shared.start();
    _deviceOpen = true;
  }

  @override
  Future<void> setLogLevelError() => _shared.setLogLevelError();

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
    String? deviceId,
  }) {
    final String dev = deviceId ?? '';
    return _serialize(() async {
      if (!_active) {
        _active = true;
        _owners.add(this);
        _refCount++;
      }
      final bool paramsChanged = _deviceOpen &&
          (_rate != sampleRate ||
              _channels != channelCount ||
              (_deviceId ?? '') != dev);
      _rate = sampleRate;
      _channels = channelCount;
      _deviceId = dev;
      if (!_deviceOpen) {
        await _openDevice();
      } else if (paramsChanged) {
        // A different format / output device was requested; reconfigure the one
        // shared device in place. Serialized, so no other owner can be tearing
        // it down at the same time.
        await _shared.release();
        _deviceOpen = false;
        await _openDevice();
      }
    });
  }

  @override
  Future<void> setFeedThreshold(int frames) async {
    _threshold = frames;
    if (_deviceOpen) {
      await _shared.setFeedThreshold(frames);
    }
  }

  @override
  void setFeedCallback(PcmFeedCallback? callback) {
    _callback = callback;
  }

  @override
  void start() {
    // The shared device is started as part of opening it in [_openDevice], so a
    // per-owner start() is a no-op (the device is already playing).
  }

  @override
  Future<void> feed(Int16List pcm) {
    if (!_deviceOpen) return Future<void>.value();
    final tap = PcmPlayer.playbackTap;
    if (tap != null) {
      tap(pcm, _rate ?? 32000, _channels ?? 1);
    }
    // Apply the host output volume after the mirror tap so the browser receives
    // full-volume audio and the two sides mute/adjust independently.
    final vol = PcmPlayer.hostOutputVolume;
    if (vol < 0.999) {
      pcm = _scalePcm(pcm, vol);
    }
    return _shared.feed(pcm);
  }

  static Int16List _scalePcm(Int16List pcm, double volume) {
    final out = Int16List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      var v = (pcm[i] * volume).round();
      if (v > 32767) {
        v = 32767;
      } else if (v < -32768) {
        v = -32768;
      }
      out[i] = v;
    }
    return out;
  }

  @override
  Future<void> release() {
    return _serialize(() async {
      if (!_active) return;
      _active = false;
      _owners.remove(this);
      _callback = null;
      _refCount--;
      if (_refCount <= 0) {
        _refCount = 0;
        if (_deviceOpen) {
          await _shared.release();
          _deviceOpen = false;
          _rate = null;
          _channels = null;
          _deviceId = null;
          _threshold = null;
        }
      }
    });
  }
}
