/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Captures live microphone audio as a stream of little-endian 16-bit signed
/// mono PCM samples.
///
/// This is used to feed the Audio tab's spectrogram with the user's
/// microphone, mirroring the continuous capture the C# RadioAudioForm did with
/// WASAPI. Capture only runs while [start] has been called and is released by
/// [stop] / [dispose] so the operating-system microphone indicator turns off
/// when the spectrogram no longer needs it.
class MicrophoneCapture {
  MicrophoneCapture({this.sampleRate = 32000, this.gain = 1.0});

  /// Requested capture sample rate (Hz). Chosen to match the spectrogram so
  /// frequencies map correctly.
  final int sampleRate;

  /// Linear gain multiplier applied to every captured sample before it is
  /// delivered (1.0 = unchanged). Boosts a quiet microphone for both the
  /// spectrograph and push-to-talk transmit. May be changed at any time while
  /// capture is running.
  double gain;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  bool _starting = false;

  /// Whether microphone capture is supported on the current platform.
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Whether capture is currently running.
  bool get isCapturing => _subscription != null;

  /// Starts microphone capture, invoking [onData] for each chunk of 16-bit PCM.
  ///
  /// Returns true once capture has started, or false if permission was denied
  /// or capture could not be started. Safe to call repeatedly; subsequent calls
  /// while already capturing return true without restarting.
  Future<bool> start(void Function(Uint8List pcm16) onData) async {
    if (isCapturing) return true;
    if (_starting) return false;
    _starting = true;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return false;

      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );
      _subscription = stream.listen(
        (chunk) => onData(_applyGain(chunk)),
        onError: (_) {},
        cancelOnError: false,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      _starting = false;
    }
  }

  /// Applies [gain] in place to a chunk of little-endian 16-bit PCM, clamping
  /// to the signed 16-bit range to avoid overflow/wrap-around on loud peaks.
  Uint8List _applyGain(Uint8List pcm16) {
    final double g = gain;
    if (g == 1.0) return pcm16;
    final data = ByteData.sublistView(pcm16);
    final int n = pcm16.lengthInBytes & ~1; // whole samples only
    for (int i = 0; i < n; i += 2) {
      int s = (data.getInt16(i, Endian.little) * g).round();
      if (s > 32767) {
        s = 32767;
      } else if (s < -32768) {
        s = -32768;
      }
      data.setInt16(i, s, Endian.little);
    }
    return pcm16;
  }

  /// Stops capture and releases the microphone.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  /// Stops capture and disposes the underlying recorder.
  Future<void> dispose() async {
    await stop();
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
