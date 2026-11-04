/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// How a multi-channel capture is reduced to the single mono stream this class
/// emits. Stereo TNC/audio interfaces often carry the radio's receive audio on
/// only one channel, so averaging both ([mix]) halves the level and folds in
/// the unused channel's noise; [auto] tracks and emits the louder channel.
enum MonoReduction { mix, left, right, auto }

/// Why the most recent [MicrophoneCapture.start] failed (or capture was lost).
enum MicrophoneFailure {
  none,

  /// The operating system denied microphone access.
  permissionDenied,

  /// No input device could be opened (missing, unplugged, in use, or it
  /// rejected the capture format), or the device went away mid-capture.
  deviceUnavailable,
}

/// Captures live microphone audio as a stream of little-endian 16-bit signed
/// mono PCM samples.
///
/// This is used to feed the Audio tab's spectrogram with the user's
/// microphone, mirroring the continuous capture the C# RadioAudioForm did with
/// WASAPI. Capture only runs while [start] has been called and is released by
/// [stop] / [dispose] so the operating-system microphone indicator turns off
/// when the spectrogram no longer needs it.
class MicrophoneCapture {
  MicrophoneCapture({
    this.sampleRate = 32000,
    this.gain = 1.0,
    this.deviceId,
    this.requestedChannels = 1,
    this.monoReduction = MonoReduction.mix,
    this.fallbackToDefault = false,
  });

  /// Whether [start] may fall back to the OS default input when the selected
  /// [deviceId] cannot be opened. Leave off for captures bound to a specific
  /// interface (e.g. a TNC), where another device's audio would be wrong.
  final bool fallbackToDefault;

  /// Requested capture sample rate (Hz). Chosen to match the spectrogram so
  /// frequencies map correctly.
  final int sampleRate;

  /// Linear gain multiplier applied to every captured sample before it is
  /// delivered (1.0 = unchanged). Boosts a quiet microphone for both the
  /// spectrograph and push-to-talk transmit. May be changed at any time while
  /// capture is running.
  double gain;

  /// Identifier of the input (microphone) device to capture from, or null to
  /// use the operating-system default device. Matches the `id` reported by
  /// [listInputDevices]. Changing this only takes effect on the next [start];
  /// callers that want it applied immediately should [stop] then [start].
  String? deviceId;

  /// Number of channels to request from the device. Values >1 let a stereo
  /// interface expose its individual channels so [monoReduction] can pick the
  /// active one instead of relying on the OS to downmix. The class always emits
  /// mono regardless.
  final int requestedChannels;

  /// How a [requestedChannels] > 1 capture is collapsed to the emitted mono.
  final MonoReduction monoReduction;

  /// Channel count the capture actually opened with (may fall back to 1 if the
  /// device rejects the requested count).
  int _activeChannels = 1;

  /// Per-channel energy running average used by [MonoReduction.auto].
  final List<double> _chEnergy = List<double>.filled(8, 0);

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<RecordState>? _stateSubscription;
  bool _starting = false;

  /// Set once the native recorder reports [RecordState.record] for the current
  /// capture, so a later [RecordState.stop] we did not request is recognised
  /// as the device going away (e.g. unplugged, or the Windows default device
  /// switched to a headset) rather than a stale event from an earlier session.
  bool _sawRecordState = false;

  /// Why the most recent [start] failed, or why capture was lost.
  MicrophoneFailure lastFailure = MicrophoneFailure.none;

  /// Platform error text for the most recent failure, for diagnostics.
  String? lastErrorDetail;

  /// The device capture actually opened on (null = OS default). May differ
  /// from [deviceId] when the requested device could not be opened and a
  /// fallback was used.
  String? activeDeviceId;

  /// Invoked when a running capture ends without [stop] being called, e.g.
  /// because the input device was removed or the OS default device changed.
  /// [isCapturing] is already false when this runs, so [start] may be called.
  void Function()? onCaptureLost;

  /// Whether microphone capture is supported on the current platform.
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// Enumerates the available input (microphone) devices.
  ///
  /// Returns an empty list on platforms that do not support enumeration or when
  /// it fails, in which case callers should fall back to the OS default device.
  static Future<List<InputDevice>> listInputDevices() async {
    if (!isSupported) return const <InputDevice>[];
    try {
      final recorder = AudioRecorder();
      try {
        return await recorder.listInputDevices();
      } finally {
        await recorder.dispose();
      }
    } catch (_) {
      return const <InputDevice>[];
    }
  }

  /// Whether capture is currently running.
  bool get isCapturing => _subscription != null;

  /// Starts microphone capture, invoking [onData] for each chunk of 16-bit PCM.
  ///
  /// Returns true once capture has started, or false if permission was denied
  /// or capture could not be started ([lastFailure] tells which). Safe to call
  /// repeatedly; subsequent calls while already capturing return true without
  /// restarting.
  ///
  /// When [fallbackToDefault] is set and the selected [deviceId] cannot be
  /// opened (e.g. it was unplugged), the OS default input is used instead.
  Future<bool> start(void Function(Uint8List pcm16) onData) async {
    if (isCapturing) return true;
    if (_starting) return false;
    _starting = true;
    try {
      lastFailure = MicrophoneFailure.none;
      lastErrorDetail = null;
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        lastFailure = MicrophoneFailure.permissionDenied;
        return false;
      }

      _stateSubscription ??= _recorder.onStateChanged().listen(
        _onRecorderState,
        onError: (Object e) => debugPrint('MicrophoneCapture: state error: $e'),
      );

      final String? requested = (deviceId == null || deviceId!.isEmpty)
          ? null
          : deviceId;
      if (await _tryStartOn(requested, onData)) return true;
      if (requested != null &&
          fallbackToDefault &&
          await _tryStartOn(null, onData)) {
        return true;
      }

      lastFailure = MicrophoneFailure.deviceUnavailable;
      return false;
    } finally {
      _starting = false;
    }
  }

  /// Attempts to start capture on [id] (null = OS default), preferring the
  /// requested channel count and falling back to mono.
  Future<bool> _tryStartOn(
    String? id,
    void Function(Uint8List pcm16) onData,
  ) async {
    final InputDevice? device = id == null
        ? null
        : InputDevice(id: id, label: id);
    final List<int> attempts = requestedChannels > 1
        ? <int>[requestedChannels, 1]
        : <int>[1];
    for (final int channels in attempts) {
      try {
        _sawRecordState = false;
        final stream = await _recorder.startStream(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: sampleRate,
            numChannels: channels,
            device: device,
          ),
        );
        _activeChannels = channels;
        for (int i = 0; i < _chEnergy.length; i++) {
          _chEnergy[i] = 0;
        }
        activeDeviceId = id;
        late final StreamSubscription<Uint8List> sub;
        sub = stream.listen(
          (chunk) => onData(_applyGain(_reduceToMono(chunk))),
          onError: (Object e) =>
              debugPrint('MicrophoneCapture: stream error: $e'),
          // Some platforms close the stream when the device goes away.
          onDone: () {
            if (identical(_subscription, sub)) {
              _handleCaptureLost('stream closed');
            }
          },
          cancelOnError: false,
        );
        _subscription = sub;
        if (id != deviceId && !(id == null && (deviceId ?? '').isEmpty)) {
          debugPrint(
            'MicrophoneCapture: requested device unavailable; '
            'using ${id ?? 'system default'} instead.',
          );
        }
        return true;
      } catch (e) {
        lastErrorDetail = e.toString();
        debugPrint(
          'MicrophoneCapture: start on ${id ?? 'default device'} '
          '($channels ch) failed: $e',
        );
      }
    }
    return false;
  }

  void _onRecorderState(RecordState state) {
    if (state == RecordState.record) {
      if (_starting || _subscription != null) _sawRecordState = true;
    } else if (state == RecordState.stop) {
      // Windows (and others) stop the native recorder on a read error, such as
      // the endpoint being invalidated, without closing the PCM stream.
      if (_sawRecordState && _subscription != null && !_starting) {
        _handleCaptureLost('recorder stopped');
      }
    }
  }

  Future<void> _handleCaptureLost(String reason) async {
    final sub = _subscription;
    if (sub == null) return;
    debugPrint('MicrophoneCapture: capture lost ($reason).');
    _subscription = null;
    _sawRecordState = false;
    lastFailure = MicrophoneFailure.deviceUnavailable;
    lastErrorDetail = reason;
    await sub.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    onCaptureLost?.call();
  }

  /// Collapses an interleaved [_activeChannels]-channel block to mono per
  /// [monoReduction]. Returns [pcm16] unchanged for a mono capture.
  Uint8List _reduceToMono(Uint8List pcm16) {
    final int ch = _activeChannels;
    if (ch <= 1) return pcm16;
    final int frames = (pcm16.lengthInBytes ~/ 2) ~/ ch;
    if (frames == 0) return Uint8List(0);
    final ByteData src = ByteData.sublistView(pcm16);
    final Uint8List out = Uint8List(frames * 2);
    final ByteData dst = ByteData.sublistView(out);

    if (monoReduction == MonoReduction.mix) {
      for (int f = 0; f < frames; f++) {
        int sum = 0;
        for (int c = 0; c < ch; c++) {
          sum += src.getInt16((f * ch + c) * 2, Endian.little);
        }
        dst.setInt16(f * 2, (sum / ch).round(), Endian.little);
      }
      return out;
    }

    final int sel = _selectChannel(src, frames, ch);
    for (int f = 0; f < frames; f++) {
      dst.setInt16(
        f * 2,
        src.getInt16((f * ch + sel) * 2, Endian.little),
        Endian.little,
      );
    }
    return out;
  }

  /// Picks the source channel to emit for a non-mixing [monoReduction]. For
  /// [MonoReduction.auto] it tracks a per-channel energy average and returns the
  /// loudest, so a stereo cable carrying audio on one channel selects it.
  int _selectChannel(ByteData src, int frames, int ch) {
    switch (monoReduction) {
      case MonoReduction.left:
      case MonoReduction.mix:
        return 0;
      case MonoReduction.right:
        return ch > 1 ? 1 : 0;
      case MonoReduction.auto:
        for (int c = 0; c < ch && c < _chEnergy.length; c++) {
          double sum = 0;
          for (int f = 0; f < frames; f++) {
            final int s = src.getInt16((f * ch + c) * 2, Endian.little);
            sum += s.toDouble() * s;
          }
          _chEnergy[c] = _chEnergy[c] * 0.9 + (sum / frames) * 0.1;
        }
        int best = 0;
        for (int c = 1; c < ch && c < _chEnergy.length; c++) {
          if (_chEnergy[c] > _chEnergy[best]) best = c;
        }
        return best;
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
    _sawRecordState = false;
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
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
