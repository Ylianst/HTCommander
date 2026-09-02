/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Plays the desktop host's streamed 16-bit PCM in the browser using the Web Audio
API. Each received buffer is turned into an [web.AudioBuffer] and scheduled
back-to-back on the AudioContext clock; on underrun the clock resets with a
small pre-roll so playback stays gap-tolerant without drifting far behind.

The browser blocks audio until a user gesture, so [resume] must be called from a
tap/click the first time (see the "Play host audio" toggle).
*/

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web Audio playback sink for the host's mirrored audio.
class HostAudioPlayer {
  web.AudioContext? _ctx;

  /// Independent playback volume (0.0-1.0) applied in the browser, saved locally
  /// so it is decoupled from the host's own output volume.
  double volume = 1.0;

  /// The AudioContext time at which the next buffer should start.
  double _nextTime = 0;

  /// Pre-roll applied when (re)starting after an underrun, in seconds.
  static const double _prerollSeconds = 0.12;

  bool get isRunning => _ctx?.state == 'running';

  web.AudioContext _context() => _ctx ??= web.AudioContext();

  /// Resumes (or creates) the AudioContext. Must be called from a user gesture
  /// the first time because of the browser autoplay policy.
  Future<void> resume() async {
    final ctx = _context();
    if (ctx.state != 'running') {
      await ctx.resume().toDart;
    }
  }

  /// Suspends playback without discarding the context.
  Future<void> suspend() async {
    final ctx = _ctx;
    if (ctx != null && ctx.state == 'running') {
      await ctx.suspend().toDart;
    }
  }

  /// Schedules one buffer of interleaved 16-bit PCM for playback.
  void feed(Int16List pcm, int sampleRate, int channels) {
    final ctx = _ctx;
    if (ctx == null || ctx.state != 'running') return;
    if (channels < 1 || sampleRate <= 0) return;
    final frames = pcm.length ~/ channels;
    if (frames <= 0) return;

    final buffer = ctx.createBuffer(channels, frames, sampleRate.toDouble());
    final vol = volume;
    for (var ch = 0; ch < channels; ch++) {
      final data = Float32List(frames);
      for (var i = 0; i < frames; i++) {
        data[i] = (pcm[i * channels + ch] / 32768.0) * vol;
      }
      buffer.copyToChannel(data.toJS, ch);
    }

    final source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);

    final now = ctx.currentTime;
    if (_nextTime < now) {
      _nextTime = now + _prerollSeconds;
    }
    source.start(_nextTime);
    _nextTime += frames / sampleRate;
  }

  Future<void> dispose() async {
    final ctx = _ctx;
    _ctx = null;
    _nextTime = 0;
    if (ctx != null) {
      try {
        await ctx.close().toDart;
      } catch (_) {
        // Already closed.
      }
    }
  }
}
