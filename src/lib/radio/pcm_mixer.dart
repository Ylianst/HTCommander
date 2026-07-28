/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'pcm_player.dart';

/// Process-wide software mixer that sums several PCM sources into the single
/// real output device.
///
/// Every audio owner (each connected radio, EchoLink, the Morse sidetone) opens
/// its own [PcmPlayer]; behind them there is only ONE native output stream per
/// platform. Without a mixer, concurrent owners just push their chunks into that
/// one stream in arrival order, so the samples are interleaved (garbled), not
/// summed. This mixer instead gives every owner a [PcmMixerSource] with its own
/// ring buffer and, on a periodic clock, pulls the same number of frames from
/// every source, sums them (clamping to 16-bit) and feeds ONE mixed block to the
/// device — so multiple sources play at the same time correctly.
///
/// All sources in this app are 32 kHz mono (the radio engine is 32 kHz; EchoLink
/// resamples 8 kHz→32 kHz before playback; Morse/DTMF synthesise at 32 kHz), so
/// no resampling is needed here; mixing is a straight per-sample sum.
///
/// The mixer is self-clocked by a periodic timer that only runs while at least
/// one source has audio queued. Each tick it tops the device up towards a small
/// target backlog (~30 ms) using the device's reported backlog as feedback, then
/// stops once every source has drained and the device has emptied — so a long
/// silent gap costs nothing, matching the previous "feed only when there is
/// audio" behaviour.
class PcmMixer {
  PcmMixer(this._device);

  final PcmPlayer _device;

  // ---- sources & device lifecycle (serialized) ----
  final Set<PcmMixerSource> _sources = <PcmMixerSource>{};
  int _openCount = 0;
  bool _deviceOpen = false;
  int _rate = 32000;
  int _channels = 1;
  String _deviceId = '';
  int? _threshold;
  // Serializes setup()/release()/reconfigure so the device lifecycle and the
  // open count are only ever mutated one operation at a time.
  Future<void> _opQueue = Future<void>.value();

  // ---- pump clock / backlog tracking ----
  Timer? _pumpTimer;
  // Last device backlog (frames) reported by the drain callback.
  int _deviceRemaining = 0;
  // Frames fed to the device since that report (dead-reckoning between reports).
  int _fedSinceReport = 0;
  int _idleTicks = 0;
  // Prevents overlapping async feeds into the device.
  bool _feeding = false;

  static const Duration _tickInterval = Duration(milliseconds: 5);

  // Target device backlog to maintain while playing (~30 ms) and the most we
  // will feed in a single tick (used to prime the device and to catch up). The
  // 5 ms pump clock lets this stay low without starving the device on jitter.
  int get _targetFrames => (_rate * 30) ~/ 1000;
  int get _maxBlockFrames => _targetFrames;
  // Per-source ring capacity (~500 ms of audio); older samples are dropped if a
  // source ever runs that far ahead of real time.
  int get _sourceCapacitySamples => (_rate * 500 ~/ 1000) * _channels;

  /// Creates a new source handle bound to this mixer. Register it with
  /// [addSource] before feeding.
  PcmMixerSource createSource() => PcmMixerSource._(this, _sourceCapacitySamples);

  Future<void> setLogLevelError() => _device.setLogLevelError();

  /// Registers [s] and opens (or reconfigures) the shared device. The first
  /// source opens the device; a later source that requests a different format /
  /// output device reconfigures it in place.
  Future<void> addSource(
    PcmMixerSource s, {
    required int sampleRate,
    required int channelCount,
    String? deviceId,
  }) {
    final String dev = deviceId ?? '';
    return _serialize(() async {
      if (!s._active) {
        s._active = true;
        _sources.add(s);
        _openCount++;
      }
      final bool changed = _deviceOpen &&
          (_rate != sampleRate ||
              _channels != channelCount ||
              _deviceId != dev);
      _rate = sampleRate;
      _channels = channelCount;
      _deviceId = dev;
      if (!_deviceOpen) {
        await _openDevice();
      } else if (changed) {
        await _device.release();
        _deviceOpen = false;
        await _openDevice();
      }
    });
  }

  /// Deregisters [s]; the last source closes the shared device.
  Future<void> removeSource(PcmMixerSource s) {
    return _serialize(() async {
      if (!s._active) return;
      s._active = false;
      _sources.remove(s);
      s._callback = null;
      s._ring.clear();
      _openCount--;
      if (_openCount <= 0) {
        _openCount = 0;
        _stopPump();
        if (_deviceOpen) {
          await _device.release();
          _deviceOpen = false;
        }
      }
    });
  }

  Future<void> setFeedThreshold(int frames) async {
    _threshold = frames;
    if (_deviceOpen) {
      await _device.setFeedThreshold(frames);
    }
  }

  Future<void> _openDevice() async {
    await _device.setup(
      sampleRate: _rate,
      channelCount: _channels,
      deviceId: _deviceId.isEmpty ? null : _deviceId,
    );
    if (_threshold != null) {
      await _device.setFeedThreshold(_threshold!);
    }
    _device.setFeedCallback(_onDeviceDrain);
    _device.start();
    _deviceOpen = true;
    _deviceRemaining = 0;
    _fedSinceReport = 0;
  }

  // The device drained a buffer and reports how many frames remain queued in it.
  void _onDeviceDrain(int remaining) {
    _deviceRemaining = remaining;
    _fedSinceReport = 0;
  }

  // Called by a source when it receives audio, to (re)start the pump clock.
  void _onSourceData() => _startPump();

  void _startPump() {
    if (_pumpTimer != null || !_deviceOpen) return;
    _idleTicks = 0;
    _pumpTimer = Timer.periodic(_tickInterval, (_) => _pump());
  }

  void _stopPump() {
    _pumpTimer?.cancel();
    _pumpTimer = null;
  }

  // Reports each source its OWN queued backlog (in frames) so per-source
  // back-pressure (e.g. RadioAudio dropping when it falls behind) stays correct
  // and independent of the other sources.
  void _reportBacklogs() {
    for (final PcmMixerSource s in _sources.toList(growable: false)) {
      s._callback?.call(s._ring.length ~/ _channels);
    }
  }

  void _pump() {
    if (_feeding || !_deviceOpen) return;

    int maxAvailSamples = 0;
    for (final PcmMixerSource s in _sources) {
      if (s._ring.length > maxAvailSamples) maxAvailSamples = s._ring.length;
    }

    if (maxAvailSamples == 0) {
      // Nothing queued anywhere. Let the device empty out, then stop the clock
      // so a silent gap is free; it restarts on the next fed sample.
      _idleTicks++;
      for (final PcmMixerSource s in _sources.toList(growable: false)) {
        s._callback?.call(0);
      }
      if ((_deviceRemaining + _fedSinceReport) <= 0 && _idleTicks > 3) {
        _stopPump();
      }
      return;
    }
    _idleTicks = 0;

    final int backlogNow = _deviceRemaining + _fedSinceReport;
    int toFeed = _targetFrames - backlogNow;
    if (toFeed <= 0) {
      // Device already has enough queued; hold the audio in the rings and feed
      // it on a later tick as the device drains.
      _reportBacklogs();
      return;
    }
    if (toFeed > _maxBlockFrames) toFeed = _maxBlockFrames;

    // Advance the shared timeline by at most what the most-buffered source has,
    // so we never inject silence into the middle of an ongoing transmission.
    final int maxAvailFrames = maxAvailSamples ~/ _channels;
    final int n = toFeed < maxAvailFrames ? toFeed : maxAvailFrames;
    if (n <= 0) {
      _reportBacklogs();
      return;
    }

    final int samples = n * _channels;
    final Int32List acc = Int32List(samples);
    for (final PcmMixerSource s in _sources.toList(growable: false)) {
      s._ring.mixInto(acc, samples);
    }
    final Int16List out = Int16List(samples);
    for (int i = 0; i < samples; i++) {
      int v = acc[i];
      if (v > 32767) {
        v = 32767;
      } else if (v < -32768) {
        v = -32768;
      }
      out[i] = v;
    }

    _fedSinceReport += n;
    _feeding = true;
    _device.feed(out).whenComplete(() => _feeding = false);

    _reportBacklogs();
  }

  Future<void> _serialize(Future<void> Function() action) {
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

  /// Test-only: performs one synchronous mix step over [sources], pulling and
  /// summing [frames] frames from each source's ring exactly as [_pump] does
  /// (per-sample sum, 16-bit clamp, silence where a source has run dry). Exposed
  /// so the mixing maths can be verified without the real-time timer or device.
  @visibleForTesting
  Int16List debugMix(List<PcmMixerSource> sources, int frames) {
    final int samples = frames * _channels;
    final Int32List acc = Int32List(samples);
    for (final PcmMixerSource s in sources) {
      s._ring.mixInto(acc, samples);
    }
    final Int16List out = Int16List(samples);
    for (int i = 0; i < samples; i++) {
      int v = acc[i];
      if (v > 32767) {
        v = 32767;
      } else if (v < -32768) {
        v = -32768;
      }
      out[i] = v;
    }
    return out;
  }
}

/// A single input into [PcmMixer]. Owned 1:1 by a [PcmPlayer] handle; audio fed
/// here is summed with every other active source.
class PcmMixerSource {
  PcmMixerSource._(this._mixer, int capacitySamples)
      : _ring = _SampleRing(capacitySamples);

  final PcmMixer _mixer;
  final _SampleRing _ring;
  PcmFeedCallback? _callback;
  bool _active = false;

  /// Registers (or clears, with null) this source's back-pressure callback,
  /// which is invoked with THIS source's own queued frame count.
  void setCallback(PcmFeedCallback? callback) => _callback = callback;

  /// Queues 16-bit PCM for mixing and (re)starts the mixer clock.
  void feed(Int16List pcm) {
    if (pcm.isEmpty) return;
    _ring.write(pcm);
    _mixer._onSourceData();
  }
}

/// Fixed-capacity circular buffer of 16-bit samples. On overflow the oldest
/// samples are dropped so a runaway producer cannot grow memory without bound.
class _SampleRing {
  _SampleRing(this._capacity) : _buf = Int16List(_capacity);

  final int _capacity;
  final Int16List _buf;
  int _head = 0; // index of the oldest sample
  int _count = 0; // number of queued samples

  int get length => _count;

  void clear() {
    _head = 0;
    _count = 0;
  }

  void write(Int16List data) {
    for (int i = 0; i < data.length; i++) {
      if (_count == _capacity) {
        // Drop the oldest sample to make room.
        _head = (_head + 1) % _capacity;
        _count--;
      }
      final int tail = (_head + _count) % _capacity;
      _buf[tail] = data[i];
      _count++;
    }
  }

  /// Adds up to [count] queued samples into [acc] (element-wise), advancing the
  /// read cursor. If fewer than [count] samples are queued, only what is
  /// available is added (the remainder of [acc] is left untouched — i.e. this
  /// source contributes silence there).
  void mixInto(Int32List acc, int count) {
    final int take = count < _count ? count : _count;
    for (int i = 0; i < take; i++) {
      acc[i] += _buf[_head];
      _head = (_head + 1) % _capacity;
    }
    _count -= take;
  }
}
