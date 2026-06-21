/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import '../sbc/sbc_decoder.dart';
import '../sbc/sbc_frame.dart';
import '../services/bluetooth_classic_macos.dart';
import '../services/data_broker_client.dart';
import 'radio.dart';

/// Receives (and decodes) SBC-compressed audio from the radio's Generic Audio
/// RFCOMM channel and pushes the resulting 32 kHz / 16-bit / mono PCM to the
/// speaker and to the DataBroker.
///
/// This is a Dart port of the C# `RadioAudio` class (receive path only).
/// Transmit (encode) support is intentionally not implemented in this build.
class RadioAudio {
  // Audio format: 32 kHz, 16-bit, mono (matches the radio's SBC stream).
  static const int _sampleRate = 32000;

  // Bound playback latency: drop incoming PCM if we are more than this many
  // frames (~800 ms) behind real time, mirroring the C# buffer catch-up logic.
  static const int _maxBufferedFrames = (_sampleRate * 800) ~/ 1000;

  // Safety cap on the receive accumulator before it is reset (64 KB).
  static const int _maxAccumulatorSize = 64 * 1024;

  final Radio radio;
  final int deviceId;
  final String macAddress;

  final DataBrokerClient _broker = DataBrokerClient();
  final SbcDecoder _sbcDecoder = SbcDecoder();

  StreamSubscription<Uint8List>? _audioDataSub;
  StreamSubscription<BluetoothClassicEvent>? _audioConnSub;

  final List<int> _accumulator = <int>[];

  bool _running = false;
  bool _connecting = false;
  bool _pcmSoundReady = false;

  // Estimated number of PCM frames currently buffered in the audio engine.
  int _bufferedFrames = 0;

  // Volume (0.0 - 1.0+) applied in software, and mute state.
  double _outputVolume = 1.0;
  bool _isMuted = false;

  // Audio-run state tracking (a "run" is a continuous burst of audio).
  bool _inAudioRun = false;
  bool _inAudioRunIsTransmit = false;
  DateTime _audioRunStartTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Current channel name (used in event payloads).
  String currentChannelName = '';

  // Optional WAV recording of received audio.
  _WavRecorder? _recorder;

  RadioAudio({
    required this.radio,
    required this.deviceId,
    required this.macAddress,
  }) {
    // Enable/disable the audio path. Audio is disabled by default and is only
    // started when 'SetAudio' true is dispatched through the DataBroker.
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetAudio',
      callback: _onSetAudio,
    );

    // Subscribe to Data Broker commands for audio control.
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetOutputVolume',
      callback: _onSetOutputVolume,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetMute',
      callback: _onSetMute,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetOutputAudioDevice',
      callback: _onSetOutputAudioDevice,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'StartRecording',
      callback: _onStartRecording,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'StopRecording',
      callback: _onStopRecording,
    );
    // Transmit commands are accepted but not implemented in this build.
    _broker.subscribe(
      deviceId: deviceId,
      name: 'TransmitVoicePCM',
      callback: _onTransmitVoicePCM,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'CancelVoiceTransmit',
      callback: _onCancelVoiceTransmit,
    );

    // Initialize output volume / mute from stored values.
    _outputVolume =
        _broker.getValue<double>(deviceId, 'OutputVolume', 1.0) ?? 1.0;
    _isMuted = _broker.getValue<bool>(deviceId, 'Mute', false) ?? false;
  }

  bool get isAudioEnabled => _running;
  bool get isRecording => _recorder != null;

  void _debug(String msg) {
    _broker.dispatch(
      deviceId: 1,
      name: 'LogInfo',
      data: '[RadioAudio/$deviceId]: $msg',
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Data Broker command handlers
  // ---------------------------------------------------------------------------

  void _onSetAudio(int deviceId, String name, Object? data) {
    if (data is! bool) return;
    if (data) {
      start();
    } else {
      stop();
    }
  }

  void _onSetOutputVolume(int deviceId, String name, Object? data) {
    double? vol;
    if (data is double) {
      vol = data;
    } else if (data is int) {
      vol = data / 100.0;
    } else if (data is num) {
      vol = data.toDouble();
    }
    if (vol == null) return;
    _outputVolume = vol;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'OutputVolume',
      data: vol,
      store: true,
    );
  }

  void _onSetMute(int deviceId, String name, Object? data) {
    if (data is bool) {
      _isMuted = data;
      _broker.dispatch(
        deviceId: deviceId,
        name: 'Mute',
        data: data,
        store: true,
      );
    }
  }

  void _onSetOutputAudioDevice(int deviceId, String name, Object? data) {
    // flutter_pcm_sound plays on the system default output device and does not
    // expose device selection. Echo the request so UI state stays consistent.
    if (data is String) {
      _broker.dispatch(
        deviceId: deviceId,
        name: 'OutputAudioDevice',
        data: data,
        store: true,
      );
    }
  }

  void _onStartRecording(int deviceId, String name, Object? data) {
    if (data is String && data.isNotEmpty) {
      startRecording(data);
      _broker.dispatch(
        deviceId: deviceId,
        name: 'Recording',
        data: true,
        store: true,
      );
    }
  }

  void _onStopRecording(int deviceId, String name, Object? data) {
    stopRecording();
    _broker.dispatch(
      deviceId: deviceId,
      name: 'Recording',
      data: false,
      store: true,
    );
  }

  void _onTransmitVoicePCM(int deviceId, String name, Object? data) {
    _debug('TransmitVoicePCM ignored (transmit not implemented in this build)');
  }

  void _onCancelVoiceTransmit(int deviceId, String name, Object? data) {
    // No-op: transmit is not implemented in this build.
  }

  // ---------------------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------------------

  void startRecording(String filename) {
    _recorder?.close();
    _recorder = _WavRecorder(filename, _sampleRate);
  }

  void stopRecording() {
    _recorder?.close();
    _recorder = null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Connect to the radio's audio RFCOMM channel and begin receiving audio.
  Future<void> start() async {
    if (_running || _connecting) return;
    _connecting = true;

    try {
      await _initPcmSound();

      // Listen for audio-channel connection events so we can react to drops.
      _audioConnSub = BluetoothClassicMacOS.instance.audioConnectionEvents
          .listen(_onAudioConnectionEvent);

      _debug('Connecting to audio RFCOMM channel...');
      final ok = await BluetoothClassicMacOS.instance.connectAudio(macAddress);
      if (!ok) {
        _debug('Failed to open audio RFCOMM channel.');
        _connecting = false;
        await _audioConnSub?.cancel();
        _audioConnSub = null;
        _dispatchAudioStateChanged(false);
        return;
      }

      _sbcDecoder.reset();
      _accumulator.clear();

      _audioDataSub = BluetoothClassicMacOS.instance
          .getAudioDataStream(macAddress)
          .listen(
            _onAudioData,
            onError: (Object e) {
              _debug('Audio data stream error: $e');
            },
          );

      _running = true;
      _connecting = false;
      _dispatchAudioStateChanged(true);
      _debug('Ready to receive audio.');
    } catch (e) {
      _debug('Audio start error: $e');
      _running = false;
      _connecting = false;
      _dispatchAudioStateChanged(false);
    }
  }

  /// Stop receiving audio and release the audio RFCOMM channel.
  Future<void> stop() async {
    if (!_running && !_connecting) return;
    _running = false;
    _connecting = false;

    await _audioDataSub?.cancel();
    _audioDataSub = null;
    await _audioConnSub?.cancel();
    _audioConnSub = null;

    try {
      await BluetoothClassicMacOS.instance.disconnectAudio(macAddress);
    } catch (_) {}

    if (_inAudioRun) {
      _inAudioRun = false;
      _dispatchAudioDataEnd();
    }

    _accumulator.clear();
    _dispatchAudioStateChanged(false);
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    await stop();
    stopRecording();
    if (_pcmSoundReady) {
      try {
        FlutterPcmSound.setFeedCallback(null);
        await FlutterPcmSound.release();
      } catch (_) {}
      _pcmSoundReady = false;
    }
    _broker.dispose();
  }

  void _onAudioConnectionEvent(BluetoothClassicEvent event) {
    final eventAddr = event.address.toUpperCase().replaceAll('-', ':');
    final ourAddr = macAddress.toUpperCase().replaceAll('-', ':');
    if (eventAddr != ourAddr) return;
    if (event.type == BluetoothClassicEventType.disconnected) {
      _debug('Audio channel disconnected by remote.');
      stop();
    }
  }

  // ---------------------------------------------------------------------------
  // Audio playback (flutter_pcm_sound)
  // ---------------------------------------------------------------------------

  Future<void> _initPcmSound() async {
    if (_pcmSoundReady) return;
    FlutterPcmSound.setLogLevel(LogLevel.error);
    await FlutterPcmSound.setup(sampleRate: _sampleRate, channelCount: 1);
    // ~125 ms threshold; the plugin signals us when it drains below this.
    await FlutterPcmSound.setFeedThreshold(_sampleRate ~/ 8);
    FlutterPcmSound.setFeedCallback(_onFeed);
    FlutterPcmSound.start();
    _pcmSoundReady = true;
  }

  // Invoked by flutter_pcm_sound when the buffer drains below the threshold.
  void _onFeed(int remainingFrames) {
    _bufferedFrames = remainingFrames;
  }

  Future<void> _playPcm(Int16List pcm) async {
    if (!_pcmSoundReady) return;
    // If we are too far behind real time, drop this chunk to catch up.
    if (_bufferedFrames > _maxBufferedFrames) return;

    _bufferedFrames += pcm.length;
    try {
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(pcm));
    } catch (e) {
      _debug('PCM feed error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Receive loop
  // ---------------------------------------------------------------------------

  void _onAudioData(Uint8List data) {
    if (!_running) return;

    _accumulator.addAll(data);

    if (_accumulator.length > _maxAccumulatorSize) {
      _debug('Accumulator overflow (${_accumulator.length} bytes), resetting.');
      _accumulator.clear();
      return;
    }

    Uint8List? frame;
    while ((frame = _extractData()) != null) {
      final Uint8List uframe = _unescapeBytes(frame!);
      if (uframe.isEmpty) break;

      switch (uframe[0]) {
        case 0x00: // Received audio (odd)
        case 0x03: // Received audio
          if (_inAudioRun && _inAudioRunIsTransmit) return;
          if (!_inAudioRun) {
            _inAudioRun = true;
            _inAudioRunIsTransmit = false;
            _dispatchAudioDataStart(false);
          }
          _decodeSbcFrame(uframe, 1, uframe.length - 1, false);
          break;
        case 0x01: // Audio end
          if (_inAudioRun) {
            _inAudioRun = false;
            _dispatchAudioDataEnd();
          }
          break;
        case 0x02: // Audio ACK
          break;
        case 0x09: // Transmit audio (echo) - decoded for metering, not played
          if (_inAudioRun && !_inAudioRunIsTransmit) return;
          if (!_inAudioRun) {
            _inAudioRun = true;
            _inAudioRunIsTransmit = true;
            _dispatchAudioDataStart(true);
          }
          _decodeSbcFrame(uframe, 1, uframe.length - 1, true);
          break;
        default:
          _debug('Unknown command: ${uframe[0]}');
          break;
      }
    }
  }

  /// Extract the next `0x7e`-delimited frame from [_accumulator], consuming the
  /// bytes up to and including the closing marker. Returns null if no complete
  /// frame is available yet.
  Uint8List? _extractData() {
    while (true) {
      final int len = _accumulator.length;
      if (len < 2) return null;

      // Skip past leading consecutive 0x7e bytes, keeping the last as start.
      int scanFrom = 0;
      if (len >= 2 && _accumulator[0] == 0x7e && _accumulator[1] == 0x7e) {
        scanFrom = 1;
      }

      int start = -1;
      int end = -1;
      for (int i = scanFrom; i < len; i++) {
        if (_accumulator[i] == 0x7e) {
          if (start == -1) {
            start = i;
          } else {
            end = i;
            break;
          }
        }
      }

      if (start != -1 && end != -1 && end > start + 1) {
        final Uint8List extracted = Uint8List.fromList(
          _accumulator.sublist(start + 1, end),
        );
        _accumulator.removeRange(0, end + 1);
        return extracted;
      } else if (start != -1 && end != -1 && end == start + 1) {
        // Two consecutive 0x7e: discard everything up to the first, keep the
        // second as a potential start marker for the next frame.
        _accumulator.removeRange(0, end);
        continue;
      } else if (start > 0) {
        // Discard garbage bytes before the first 0x7e marker.
        _accumulator.removeRange(0, start);
        continue;
      } else if (start == -1) {
        // No marker at all - discard everything as garbage.
        _accumulator.clear();
        return null;
      } else {
        // Only a start marker found, no end yet - wait for more data.
        return null;
      }
    }
  }

  /// Unescape `0x7d`-escaped bytes (next byte XOR 0x20) into a new buffer.
  Uint8List _unescapeBytes(Uint8List buffer) {
    if (buffer.isEmpty) return buffer;
    final Uint8List out = Uint8List(buffer.length);
    int dst = 0;
    int src = 0;
    final int end = buffer.length;
    while (src < end) {
      if (buffer[src] == 0x7d) {
        src++;
        if (src < end) {
          out[dst++] = buffer[src] ^ 0x20;
        } else {
          break;
        }
      } else {
        out[dst++] = buffer[src];
      }
      src++;
    }
    return Uint8List.sublistView(out, 0, dst);
  }

  /// Decode one or more concatenated SBC frames starting at [start] for
  /// [length] bytes, play/record/emit the resulting PCM.
  void _decodeSbcFrame(
    Uint8List sbcFrame,
    int start,
    int length,
    bool isTransmit,
  ) {
    if (sbcFrame.isEmpty) return;

    try {
      int offset = start;
      int remaining = length;
      final List<int> samples = <int>[];

      while (remaining > 0) {
        // SBC frames start with 0x9C, mSBC with 0xAD.
        final int syncByte = sbcFrame[offset];
        if (syncByte != 0x9C && syncByte != 0xAD) break;

        if (remaining < SbcFrame.headerSize) break;
        final Uint8List header = Uint8List.sublistView(
          sbcFrame,
          offset,
          offset + SbcFrame.headerSize,
        );
        final SbcFrame? probed = _sbcDecoder.probe(header);
        if (probed == null) break;
        final int frameSize = probed.getFrameSize();
        if (frameSize <= 0 || frameSize > remaining) break;

        final Uint8List sbcData = Uint8List.sublistView(
          sbcFrame,
          offset,
          offset + frameSize,
        );
        final result = _sbcDecoder.decode(sbcData);
        if (!result.success) break;
        if (result.frame.getFrameSize() != frameSize) break;

        samples.addAll(result.pcmLeft);

        offset += frameSize;
        remaining -= frameSize;
      }

      if (samples.isEmpty) return;

      // Resolve the channel currently being received (the active VFO) and
      // whether it is muted. Audio on a muted channel is neither played on the
      // speaker nor recorded, but it is still reported on the Data Broker so
      // subscribers can tell which channel/VFO the frames came from.
      currentChannelName = radio.currentChannelName;
      final bool isOnMuteChannel = radio.isOnMuteChannel();

      // Scale by output volume for playback (software volume control).
      final Int16List playbackPcm = Int16List(samples.length);
      for (int i = 0; i < samples.length; i++) {
        int v = (samples[i] * _outputVolume).round();
        if (v > 32767) {
          v = 32767;
        } else if (v < -32768) {
          v = -32768;
        }
        playbackPcm[i] = v;
      }

      if (!isOnMuteChannel) {
        if (!_isMuted && !isTransmit) {
          _playPcm(playbackPcm);
        }
        _recorder?.write(Int16List.fromList(samples));
      }

      // Emit raw (unscaled) PCM bytes to the broker.
      final Uint8List pcmBytes = Int16List.fromList(
        samples,
      ).buffer.asUint8List();
      _dispatchAudioDataAvailable(
        pcmBytes,
        pcmBytes.length,
        isTransmit,
        isOnMuteChannel,
      );

      // Output amplitude (after conceptual volume) for metering.
      final double amplitude = _calculatePcmAmplitude(samples) * _outputVolume;
      _broker.dispatch(
        deviceId: deviceId,
        name: 'OutputAmplitude',
        data: amplitude,
        store: false,
      );
    } catch (e) {
      _debug('SBC decode error: $e');
    }
  }

  static double _calculatePcmAmplitude(List<int> samples) {
    if (samples.isEmpty) return 0.0;
    int max = 0;
    for (final s in samples) {
      final int a = s < 0 ? -s : s;
      if (a > max) max = a;
    }
    final double amp = max / 32768.0;
    return amp > 1.0 ? 1.0 : amp;
  }

  // ---------------------------------------------------------------------------
  // Data Broker event dispatch
  // ---------------------------------------------------------------------------

  void _dispatchAudioStateChanged(bool enabled) {
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioState',
      data: enabled,
      store: true,
    );
  }

  void _dispatchAudioDataStart(bool transmit) {
    _audioRunStartTime = DateTime.now();
    currentChannelName = radio.currentChannelName;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataStart',
      data: <String, Object?>{
        'startTime': _audioRunStartTime.millisecondsSinceEpoch,
        'channelName': currentChannelName,
        'transmit': transmit,
        'muted': radio.isOnMuteChannel(),
        'usage': radio.lockUsage,
      },
      store: false,
    );
  }

  void _dispatchAudioDataAvailable(
    Uint8List data,
    int length,
    bool transmit,
    bool muted,
  ) {
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataAvailable',
      data: <String, Object?>{
        'data': data,
        'offset': 0,
        'length': length,
        'channelName': currentChannelName,
        'transmit': transmit,
        'muted': muted,
        'audioRunStartTime': _audioRunStartTime.millisecondsSinceEpoch,
        'usage': radio.lockUsage,
      },
      store: false,
    );
  }

  void _dispatchAudioDataEnd() {
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataEnd',
      data: <String, Object?>{
        'startTime': _audioRunStartTime.millisecondsSinceEpoch,
        'transmit': _inAudioRunIsTransmit,
        'usage': radio.lockUsage,
      },
      store: false,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'OutputAmplitude',
      data: 0.0,
      store: false,
    );
  }
}

/// Minimal incremental WAV (PCM 16-bit) file writer.
class _WavRecorder {
  final RandomAccessFile? _raf;
  final int _sampleRate;
  int _dataBytes = 0;

  _WavRecorder(String filename, this._sampleRate) : _raf = _openFile(filename) {
    if (_raf != null) {
      _raf.writeFromSync(_header(0, _sampleRate));
    }
  }

  static RandomAccessFile? _openFile(String filename) {
    try {
      final file = File(filename);
      return file.openSync(mode: FileMode.write);
    } catch (e) {
      debugPrint('RadioAudio: Failed to open recording file: $e');
      return null;
    }
  }

  void write(Int16List samples) {
    final raf = _raf;
    if (raf == null) return;
    try {
      final bytes = samples.buffer.asUint8List(
        samples.offsetInBytes,
        samples.lengthInBytes,
      );
      raf.writeFromSync(bytes);
      _dataBytes += bytes.length;
    } catch (e) {
      debugPrint('RadioAudio: Recording write error: $e');
    }
  }

  void close() {
    final raf = _raf;
    if (raf == null) return;
    try {
      // Patch the RIFF/data sizes in the header.
      raf.setPositionSync(0);
      raf.writeFromSync(_header(_dataBytes, _sampleRate));
      raf.closeSync();
    } catch (e) {
      debugPrint('RadioAudio: Recording close error: $e');
    }
  }

  // 44-byte canonical WAV header for 16-bit mono PCM.
  static Uint8List _header(int dataBytes, int sampleRate) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const int blockAlign = channels * bitsPerSample ~/ 8;
    final int riffSize = 36 + dataBytes;

    final bytes = Uint8List(44);
    final bd = ByteData.sublistView(bytes);
    bytes.setAll(0, 'RIFF'.codeUnits);
    bd.setUint32(4, riffSize, Endian.little);
    bytes.setAll(8, 'WAVE'.codeUnits);
    bytes.setAll(12, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little); // fmt chunk size
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    bytes.setAll(36, 'data'.codeUnits);
    bd.setUint32(40, dataBytes, Endian.little);
    return bytes;
  }
}
