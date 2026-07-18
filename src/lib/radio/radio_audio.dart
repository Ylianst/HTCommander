/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show RootIsolateToken;

import '../services/bluetooth_classic_macos.dart';
import '../services/data_broker_client.dart';
import 'audio_engine.dart';
import 'pcm_player.dart';
import 'radio.dart';

/// Main-isolate host for the radio's Generic Audio RFCOMM channel.
///
/// The CPU-heavy audio DSP (SBC decode/encode, WAV recording and the transmit
/// pacing loop) runs in a dedicated background isolate — see [AudioEngine] — so
/// it no longer competes with the Flutter UI isolate. This class keeps the
/// parts that must stay on the main (root) isolate: the Bluetooth transport and
/// the PCM playback device (background isolates cannot receive messages from
/// the host platform, so plugin channels must live here), plus all DataBroker
/// interaction. It forwards raw received bytes to the engine, feeds the engine's
/// decoded PCM to the speaker, relays the engine's transmit bytes back over
/// Bluetooth, and translates engine events into DataBroker dispatches.
class RadioAudio {
  // Audio format: 32 kHz, 16-bit, mono (matches the radio's SBC stream).
  static const int _sampleRate = 32000;

  // Bound playback latency: drop incoming PCM if we are more than this many
  // frames (~800 ms) behind real time, mirroring the C# buffer catch-up logic.
  static const int _maxBufferedFrames = (_sampleRate * 800) ~/ 1000;

  final Radio radio;
  final int deviceId;
  final String macAddress;

  final DataBrokerClient _broker = DataBrokerClient();

  StreamSubscription<Uint8List>? _audioDataSub;
  StreamSubscription<BluetoothClassicEvent>? _audioConnSub;

  bool _running = false;
  bool _connecting = false;
  bool _recording = false;

  // Volume (0.0 - 1.0+) applied in software, mute state and output device.
  // Tracked here for persistence and passed to the engine on init / change.
  double _outputVolume = 1.0;
  bool _isMuted = false;
  String _outputDeviceId = '';

  // PCM playback sink (native player on desktop, flutter_pcm_sound on mobile).
  // Owned by the host because background isolates cannot receive the player's
  // drain callback from the platform. The engine decodes; the host feeds.
  final PcmPlayer _pcm = PcmPlayer();
  bool _pcmSoundReady = false;
  int _bufferedFrames = 0;

  // --- Audio engine isolate ---
  ReceivePort? _hostReceivePort;
  SendPort? _enginePort;
  Completer<void>? _engineReady;
  bool _engineSpawning = false;

  RadioAudio({
    required this.radio,
    required this.deviceId,
    required this.macAddress,
  }) {
    // Restore the persisted output-device selection (device 0 = global).
    _outputDeviceId = _broker.getValue<String>(0, 'OutputAudioDevice', '') ?? '';

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
    // Track radio status so the engine can tag audio with the current channel
    // and honor the muted-channel state without reaching into [radio].
    _broker.subscribe(
      deviceId: deviceId,
      name: 'HtStatus',
      callback: _onHtStatus,
    );

    // Initialize output volume / mute from stored values. The output volume is
    // persisted globally (device 0) by the Audio tab so it survives restarts.
    _outputVolume = _broker.getValue<double>(0, 'OutputVolume', 1.0) ?? 1.0;
    _isMuted = _broker.getValue<bool>(deviceId, 'Mute', false) ?? false;
  }

  bool get isAudioEnabled => _running;
  bool get isRecording => _recording;

  void _debug(String msg) {
    _broker.dispatch(
      deviceId: 1,
      name: 'LogInfo',
      data: '[RadioAudio/$deviceId]: $msg',
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Audio engine isolate management
  // ---------------------------------------------------------------------------

  bool get _enginePortReady =>
      _enginePort != null && (_engineReady?.isCompleted ?? false);

  /// Spawn the audio-engine isolate (once) and wait until it has opened the
  /// audio device and is ready to receive commands.
  Future<void> _ensureEngine() async {
    if (_enginePortReady) return;
    if (_engineSpawning) {
      await _engineReady?.future;
      return;
    }
    _engineSpawning = true;
    final Completer<void> ready = Completer<void>();
    _engineReady = ready;

    final ReceivePort receivePort = ReceivePort();
    _hostReceivePort = receivePort;
    receivePort.listen(_onEngineMessage);

    // Pass the RootIsolateToken so the engine can write transmit audio straight
    // to Bluetooth (invokeMethod) from its own isolate, keeping the real-time TX
    // path off this (UI) isolate. Null on platforms without one (e.g. web); the
    // engine then falls back to relaying transmit bytes via a `send` event.
    final RootIsolateToken? rootToken = RootIsolateToken.instance;

    await Isolate.spawn(
      audioEngineIsolateEntry,
      <Object?>[receivePort.sendPort, rootToken, macAddress],
      debugName: 'radio-audio-engine-$deviceId',
    );

    await ready.future;
    _engineSpawning = false;
  }

  void _sendToEngine(Map<String, Object?> msg) {
    _enginePort?.send(msg);
  }

  void _onEngineMessage(Object? message) {
    if (message is! Map) return;
    final String evt = (message['evt'] as String?) ?? '';
    switch (evt) {
      case 'port':
        _enginePort = message['port'] as SendPort?;
        // Hand the engine its initial volume / mute state.
        _sendToEngine(<String, Object?>{
          'cmd': 'init',
          'volume': _outputVolume,
          'muted': _isMuted,
        });
        break;
      case 'ready':
        if (!(_engineReady?.isCompleted ?? true)) _engineReady?.complete();
        _pushRadioState();
        break;
      case 'log':
        _debug((message['msg'] as String?) ?? '');
        break;
      case 'send':
        final Object? bytes = message['bytes'];
        Uint8List? data;
        if (bytes is TransferableTypedData) {
          data = bytes.materialize().asUint8List();
        } else if (bytes is Uint8List) {
          data = bytes;
        }
        if (data != null) _sendAudio(data);
        break;
      case 'play':
        final Object? pcm = message['pcm'];
        Uint8List? bytes;
        if (pcm is TransferableTypedData) {
          bytes = pcm.materialize().asUint8List();
        } else if (pcm is Uint8List) {
          bytes = pcm;
        }
        if (bytes != null) _playPcm(_int16FromBytes(bytes));
        break;
      case 'audioStart':
        _dispatchAudioDataStart(
          (message['transmit'] as bool?) ?? false,
          (message['startMs'] as int?) ?? 0,
          (message['channelName'] as String?) ?? '',
          (message['muted'] as bool?) ?? false,
        );
        break;
      case 'audioEnd':
        _dispatchAudioDataEnd(
          (message['transmit'] as bool?) ?? false,
          (message['startMs'] as int?) ?? 0,
        );
        break;
      case 'audioData':
        _dispatchAudioDataAvailable(message);
        break;
      case 'amplitude':
        _broker.dispatch(
          deviceId: deviceId,
          name: 'OutputAmplitude',
          data: (message['value'] as num?)?.toDouble() ?? 0.0,
          store: false,
        );
        break;
      case 'txState':
        _broker.dispatch(
          deviceId: deviceId,
          name: 'VoiceTransmitStateChanged',
          data: <String, Object?>{
            'transmitting': (message['transmitting'] as bool?) ?? false,
            'isDataFrame': (message['isDataFrame'] as bool?) ?? false,
          },
          store: false,
        );
        break;
    }
  }

  /// Push the current radio channel / mute state to the engine so it can tag
  /// audio events correctly. Called on start and on every HtStatus change.
  void _pushRadioState() {
    _sendToEngine(<String, Object?>{
      'cmd': 'radioState',
      'channelName': radio.currentChannelName,
      'muteChannel': radio.isOnMuteChannel(),
    });
  }

  void _onHtStatus(int deviceId, String name, Object? data) {
    if (_enginePortReady) _pushRadioState();
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
    _sendToEngine(<String, Object?>{'cmd': 'setVolume', 'value': vol});
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
      _sendToEngine(<String, Object?>{'cmd': 'setMute', 'value': data});
      _broker.dispatch(
        deviceId: deviceId,
        name: 'Mute',
        data: data,
        store: true,
      );
    }
  }

  void _onSetOutputAudioDevice(int deviceId, String name, Object? data) {
    if (data is! String) return;
    _outputDeviceId = data;
    // Persist globally so the selection is restored on the next launch and
    // shared with the Audio tab UI.
    _broker.dispatch(
      deviceId: 0,
      name: 'OutputAudioDevice',
      data: data,
      store: true,
    );
    // If playback is already running, re-open the audio device so the change
    // takes effect immediately.
    if (_pcmSoundReady) {
      unawaited(_reopenPcmSound());
    }
  }

  void _onStartRecording(int deviceId, String name, Object? data) {
    if (data is String && data.isNotEmpty) {
      _recording = true;
      _sendToEngine(
        <String, Object?>{'cmd': 'startRecording', 'filename': data},
      );
      _broker.dispatch(
        deviceId: deviceId,
        name: 'Recording',
        data: true,
        store: true,
      );
    }
  }

  void _onStopRecording(int deviceId, String name, Object? data) {
    _recording = false;
    _sendToEngine(<String, Object?>{'cmd': 'stopRecording'});
    _broker.dispatch(
      deviceId: deviceId,
      name: 'Recording',
      data: false,
      store: true,
    );
  }

  void _onTransmitVoicePCM(int deviceId, String name, Object? data) {
    if (data == null) return;
    if (!_running) {
      _debug('TransmitVoicePCM ignored: audio is not enabled.');
      return;
    }

    // Accept a raw PCM buffer, or a Map with 'data'/'Data', an optional
    // 'playLocally'/'PlayLocally' flag and an optional 'hold'/'Hold' flag.
    Uint8List? pcm;
    bool playLocally = false;
    bool? hold;
    bool isDataFrame = false;
    if (data is Uint8List) {
      pcm = data;
    } else if (data is List<int>) {
      pcm = Uint8List.fromList(data);
    } else if (data is Map) {
      final Object? d = data['data'] ?? data['Data'];
      if (d is Uint8List) {
        pcm = d;
      } else if (d is List<int>) {
        pcm = Uint8List.fromList(d);
      }
      final Object? p = data['playLocally'] ?? data['PlayLocally'];
      if (p is bool) playLocally = p;
      final Object? h = data['hold'] ?? data['Hold'];
      if (h is bool) hold = h;
      final Object? df = data['isDataFrame'] ?? data['IsDataFrame'];
      if (df is bool) isDataFrame = df;
    }

    if (pcm == null || pcm.isEmpty) {
      // A hold-only update (e.g. the end of a PTT stream).
      if (hold != null) {
        _sendToEngine(<String, Object?>{'cmd': 'txHold', 'hold': hold});
      }
      return;
    }

    _sendToEngine(<String, Object?>{
      'cmd': 'tx',
      'pcm': TransferableTypedData.fromList(<Uint8List>[pcm]),
      'playLocally': playLocally,
      'hold': hold,
      'isDataFrame': isDataFrame,
    });
  }

  void _onCancelVoiceTransmit(int deviceId, String name, Object? data) {
    _sendToEngine(<String, Object?>{'cmd': 'cancelTx'});
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Connect to the radio's audio RFCOMM channel and begin receiving audio.
  Future<void> start() async {
    if (_running || _connecting) return;
    _connecting = true;

    try {
      // Open the audio playback device (root isolate) and spawn the audio
      // engine before we start pumping bytes into it.
      await _initPcmSound();
      await _ensureEngine();

      // Listen for audio-channel connection events so we can react to drops.
      _audioConnSub = BluetoothClassicMacOS.instance.audioConnectionEvents
          .listen(_onAudioConnectionEvent);

      // Opening the audio RFCOMM channel can transiently fail right after the
      // control channel connects, so retry a few times before giving up.
      const maxAudioAttempts = 3;
      bool ok = false;
      for (var attempt = 1; attempt <= maxAudioAttempts; attempt++) {
        ok = await BluetoothClassicMacOS.instance.connectAudio(macAddress);
        if (ok) break;

        // Audio was disabled (stop() called) while we were connecting; abort
        // quietly without disturbing the radio connection.
        if (!_connecting) {
          await _audioConnSub?.cancel();
          _audioConnSub = null;
          return;
        }

        _debug(
          'Failed to open audio RFCOMM channel '
          '(attempt $attempt/$maxAudioAttempts).',
        );

        if (attempt < maxAudioAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (!_connecting) {
            await _audioConnSub?.cancel();
            _audioConnSub = null;
            return;
          }
        }
      }

      if (!ok) {
        // The control channel is up but audio is unusable, leaving the radio in
        // a half-connected state. Do a proper, full disconnect so it does not
        // linger unusable; the BluetoothService transport watcher then tears
        // down all connection state (maps, radio and audio) cleanly.
        _debug(
          'Audio RFCOMM channel failed after $maxAudioAttempts attempts; '
          'disconnecting radio to avoid a half-connected state.',
        );
        _connecting = false;
        await _audioConnSub?.cancel();
        _audioConnSub = null;
        _dispatchAudioStateChanged(false);
        radio.disconnect('Audio RFCOMM channel failed to open');
        return;
      }

      // Reset the engine's decoder / accumulator for a fresh audio session and
      // push the current radio state.
      _sendToEngine(<String, Object?>{'cmd': 'reset'});
      _pushRadioState();

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

    // Abort any in-progress transmission and end any open audio run in the
    // engine (it will emit the matching audioEnd event back to us).
    _sendToEngine(<String, Object?>{'cmd': 'stopAudio'});

    try {
      await BluetoothClassicMacOS.instance.disconnectAudio(macAddress);
    } catch (_) {}

    _dispatchAudioStateChanged(false);
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    await stop();
    _recording = false;
    // Tell the engine to release its resources and exit, then tear down the
    // isolate plumbing.
    _sendToEngine(<String, Object?>{'cmd': 'shutdown'});
    _enginePort = null;
    _hostReceivePort?.close();
    _hostReceivePort = null;
    // Release the audio playback device.
    if (_pcmSoundReady) {
      try {
        _pcm.setFeedCallback(null);
        await _pcm.release();
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
  // Receive: forward raw Bluetooth bytes to the engine (zero-copy)
  // ---------------------------------------------------------------------------

  void _onAudioData(Uint8List data) {
    if (!_running) return;
    _sendToEngine(<String, Object?>{
      'cmd': 'rx',
      'bytes': TransferableTypedData.fromList(<Uint8List>[data]),
    });
  }

  Future<void> _sendAudio(Uint8List data) async {
    try {
      await BluetoothClassicMacOS.instance.sendAudio(macAddress, data);
    } catch (e) {
      _debug('sendAudio error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Audio playback (owned by the host / root isolate)
  // ---------------------------------------------------------------------------

  Future<void> _initPcmSound() async {
    if (_pcmSoundReady) return;
    await _pcm.setLogLevelError();
    await _pcm.setup(
      sampleRate: _sampleRate,
      channelCount: 1,
      deviceId: _outputDeviceId.isEmpty ? null : _outputDeviceId,
    );
    // ~125 ms threshold; the plugin signals us when it drains below this.
    await _pcm.setFeedThreshold(_sampleRate ~/ 8);
    _pcm.setFeedCallback(_onFeed);
    _pcm.start();
    _pcmSoundReady = true;
  }

  /// Releases and re-initializes the PCM player, e.g. after the output device
  /// changed, so subsequent audio plays on the newly selected device.
  Future<void> _reopenPcmSound() async {
    try {
      await _pcm.release();
    } catch (_) {}
    _pcmSoundReady = false;
    _bufferedFrames = 0;
    await _initPcmSound();
  }

  // Invoked by the PCM player when the buffer drains below the threshold.
  void _onFeed(int remainingFrames) {
    _bufferedFrames = remainingFrames;
  }

  Future<void> _playPcm(Int16List pcm) async {
    if (!_pcmSoundReady) return;
    // If we are too far behind real time, drop this chunk to catch up.
    if (_bufferedFrames > _maxBufferedFrames) return;

    _bufferedFrames += pcm.length;
    try {
      await _pcm.feed(pcm);
    } catch (e) {
      _debug('PCM feed error: $e');
    }
  }

  /// Convert little-endian 16-bit PCM bytes to an [Int16List].
  static Int16List _int16FromBytes(Uint8List bytes) {
    // Fast path when the buffer is 2-byte aligned; otherwise copy.
    if (bytes.offsetInBytes.isEven && bytes.lengthInBytes.isEven) {
      return bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
    }
    final int count = bytes.length ~/ 2;
    final Int16List out = Int16List(count);
    final ByteData bd = ByteData.sublistView(bytes);
    for (int i = 0; i < count; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Data Broker event dispatch (translated from engine events)
  // ---------------------------------------------------------------------------

  void _dispatchAudioStateChanged(bool enabled) {
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioState',
      data: enabled,
      store: true,
    );
  }

  void _dispatchAudioDataStart(
    bool transmit,
    int startMs,
    String channelName,
    bool muted,
  ) {
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataStart',
      data: <String, Object?>{
        'startTime': startMs,
        'channelName': channelName,
        'transmit': transmit,
        'muted': muted,
        'usage': radio.lockUsage,
      },
      store: false,
    );
  }

  void _dispatchAudioDataAvailable(Map<Object?, Object?> message) {
    final Object? pcm = message['pcm'];
    Uint8List? data;
    if (pcm is TransferableTypedData) {
      data = pcm.materialize().asUint8List();
    } else if (pcm is Uint8List) {
      data = pcm;
    }
    if (data == null) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataAvailable',
      data: <String, Object?>{
        'data': data,
        'offset': 0,
        'length': (message['length'] as int?) ?? data.length,
        'channelName': (message['channelName'] as String?) ?? '',
        'transmit': (message['transmit'] as bool?) ?? false,
        'muted': (message['muted'] as bool?) ?? false,
        'audioRunStartTime': (message['startMs'] as int?) ?? 0,
        'usage': radio.lockUsage,
      },
      store: false,
    );
  }

  void _dispatchAudioDataEnd(bool transmit, int startMs) {
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataEnd',
      data: <String, Object?>{
        'startTime': startMs,
        'transmit': transmit,
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
