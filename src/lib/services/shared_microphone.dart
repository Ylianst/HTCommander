/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'microphone_capture.dart';

/// A handle returned by [SharedMicrophone.acquire]. Cancel it to stop receiving
/// microphone PCM; the underlying hardware is released once the last handle is
/// cancelled.
class MicrophoneHandle {
  MicrophoneHandle._(this._owner, this._onPcm);

  final SharedMicrophone _owner;
  final void Function(Uint8List pcm16) _onPcm;
  bool _active = true;

  /// Stops delivering microphone PCM to this consumer.
  Future<void> cancel() async {
    if (!_active) return;
    _active = false;
    await _owner._release(this);
  }
}

/// Process-wide microphone owner shared by every consumer (the Comms tab's
/// push-to-talk and the Audio tab's spectrograph).
///
/// Only ONE underlying [MicrophoneCapture] (and therefore one native audio
/// recorder) ever runs: opening a second recorder on the same input device
/// fails or crashes on desktop platforms. Consumers [acquire] a [MicrophoneHandle]
/// and the captured PCM is fanned out to all of them; the hardware starts with
/// the first consumer and stops with the last.
class SharedMicrophone {
  SharedMicrophone._();

  /// The single shared instance.
  static final SharedMicrophone instance = SharedMicrophone._();

  /// Whether microphone capture is supported on the current platform.
  static bool get isSupported => MicrophoneCapture.isSupported;

  final MicrophoneCapture _capture = MicrophoneCapture(sampleRate: 32000);
  final List<MicrophoneHandle> _handles = <MicrophoneHandle>[];
  Future<bool>? _startFuture;

  double _gain = 1.0;
  String? _deviceId;

  /// Whether the microphone hardware is currently running.
  bool get isCapturing => _capture.isCapturing;

  /// The linear gain applied to captured PCM before it is delivered.
  double get gain => _gain;
  set gain(double value) {
    _gain = value;
    _capture.gain = value;
  }

  /// Selects the input (microphone) device (null / empty = OS default). A live
  /// capture is restarted so it re-opens on the new device.
  Future<void> setDeviceId(String? id) async {
    final normalized = (id == null || id.isEmpty) ? null : id;
    if (normalized == _deviceId) return;
    _deviceId = normalized;
    _capture.deviceId = normalized;
    if (_capture.isCapturing) {
      await _capture.stop();
      await _capture.start(_fanOut);
    }
  }

  /// Begins delivering microphone PCM to [onPcm]. The first consumer starts the
  /// hardware; subsequent consumers share the same capture. Returns a handle on
  /// success, or null if the microphone could not be started (e.g. permission
  /// denied) and this was the only consumer requesting it.
  Future<MicrophoneHandle?> acquire(void Function(Uint8List pcm16) onPcm) async {
    if (!isSupported) return null;

    final handle = MicrophoneHandle._(this, onPcm);
    _handles.add(handle);

    // Already running (or another acquire is warming it up): just join.
    if (_capture.isCapturing) return handle;

    _capture.gain = _gain;
    _capture.deviceId = _deviceId;
    _startFuture ??= _capture.start(_fanOut);
    final bool ok = await _startFuture!;
    _startFuture = null;

    if (!ok) {
      handle._active = false;
      _handles.remove(handle);
      return null;
    }

    // Everyone cancelled while the hardware was starting up.
    if (_handles.isEmpty) {
      await _capture.stop();
    }
    return handle;
  }

  void _fanOut(Uint8List pcm16) {
    // Iterate a copy so a consumer cancelling during delivery is safe.
    for (final handle in List<MicrophoneHandle>.of(_handles)) {
      if (handle._active) {
        try {
          handle._onPcm(pcm16);
        } catch (e) {
          debugPrint('SharedMicrophone: consumer error: $e');
        }
      }
    }
  }

  Future<void> _release(MicrophoneHandle handle) async {
    _handles.remove(handle);
    if (_handles.isEmpty && _startFuture == null) {
      await _capture.stop();
    }
  }
}
