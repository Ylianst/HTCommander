/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// audio_rx_manager.dart - Runs the user-configured Audio Receive Devices.
//
// Each configured device captures one sound-card input at 32 kHz mono and feeds
// it into a receive-only decode pipeline on the shared [SoftwareModem]. Decoded
// frames are dispatched as if they arrived on the device's own DataBroker id, or
// - when the device is paired to a radio - as if that radio received them. The
// existing FrameDeduplicator then collapses a packet heard by both the radio and
// the audio device. Receive-only; the device is never a selectable radio.
//

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../echolink/pcm_resampler.dart';
import '../radio/software_modem.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/microphone_capture.dart';
import 'audio_rx_device.dart';

/// A currently-running capture + decode pipeline for one Audio Receive Device.
class _RunningCapture {
  final MicrophoneCapture capture;

  /// Signature of the configuration this capture was started for; a change means
  /// the pipeline must be rebuilt.
  final String signature;

  /// Input-device id this capture opened, so the manager can publish the set of
  /// ports currently in use.
  final String inputDeviceId;

  /// Non-null when this device routes its audio through the paired radio's own
  /// receive pipeline instead of a fixed software-modem external source.
  final _RadioPipelineFeeder? feeder;

  _RunningCapture(this.capture, this.signature,
      {required this.inputDeviceId, this.feeder});
}

/// Owns every Audio Receive Device: reads the persisted list, opens each input
/// port, and bridges its audio into the [SoftwareModem]. Registered as a Data
/// Broker handler in `main()` on platforms with a dart:io audio stack.
class AudioRxManager {
  AudioRxManager(this._softwareModem);

  final SoftwareModem _softwareModem;
  final DataBrokerClient _broker = DataBrokerClient();

  bool _initialized = false;
  bool _disposed = false;

  /// Running captures keyed by each device's own (source) id.
  final Map<int, _RunningCapture> _running = <int, _RunningCapture>{};

  /// Source ids that already logged a decode error, so a recurring failure on a
  /// noisy input is reported once rather than on every captured block.
  final Set<int> _decodeErrorLogged = <int>{};

  /// Own id of the audio receive device the Audio tab spectrograph is currently
  /// visualizing, or -1 for none. Only that device's captured PCM is republished
  /// on the broker (for the spectrograph) to avoid a needless live stream.
  int _spectrogramDeviceId = -1;

  /// Whether this platform runs Audio Receive Devices. The software modem's
  /// audio path is unavailable on the web and iOS builds, matching the menu
  /// gating in `main.dart`.
  static bool get _supported =>
      !kIsWeb && !Platform.isIOS && MicrophoneCapture.isSupported;

  void init() {
    if (_initialized || _disposed) return;
    _initialized = true;
    if (!_supported) return;

    _broker.subscribe(
      deviceId: 0,
      name: audioRxDevicesKey,
      callback: (_, _, _) => _reconcile(),
    );
    // Paired devices only run while their radio is connected, and are attributed
    // to that radio's live device id, so reconcile whenever the radio list moves.
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: (_, _, _) => _reconcile(),
    );
    // A radio-pipeline device only runs while the paired radio's own Bluetooth
    // audio path is off, so reconcile whenever any radio's audio toggles.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioState',
      callback: (_, _, _) => _reconcile(),
    );
    // Track which device (if any) the Audio tab spectrograph is showing so its
    // captured audio is republished for visualization.
    _spectrogramDeviceId = _parseSpectrogramDeviceId(
        _broker.getValue<String>(0, 'SpectrogramSource', 'none'));
    _broker.subscribe(
      deviceId: 0,
      name: 'SpectrogramSource',
      callback: (_, _, Object? data) => _spectrogramDeviceId =
          _parseSpectrogramDeviceId(data?.toString()),
    );

    _reconcile();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _running.entries) {
      _softwareModem.unregisterExternalSource(entry.key);
      await entry.value.capture.dispose();
    }
    _running.clear();
    _publishActivePorts();
    _broker.dispose();
  }

  // ---------------------------------------------------------------------------
  // Reconciliation
  // ---------------------------------------------------------------------------

  /// Start, stop, or rebuild capture pipelines so the running set matches the
  /// current configuration and connected-radio state.
  Future<void> _reconcile() async {
    if (_disposed || !_supported) return;

    final List<AudioRxDevice> devices = _readDevices();
    final Map<String, int> connected = _connectedRadioIdsByMac();

    // Compute the desired running set (source id -> resolved plan).
    final Map<int, _Plan> desired = <int, _Plan>{};
    final Set<String> usedPorts = <String>{};
    for (final AudioRxDevice d in devices) {
      if (d.inputDeviceId.isEmpty) continue;
      // Enforce port uniqueness defensively (the editor already prevents it).
      if (!usedPorts.add(d.inputDeviceId.toLowerCase())) continue;

      int attributeDeviceId = d.deviceId;
      String radioMac = '';
      if (d.usage == AudioRxUsage.paired) {
        if (d.pairedRadioMac.isEmpty) continue; // no radio chosen yet
        final int? radioId = connected[d.pairedRadioMac.toUpperCase()];
        if (radioId == null) continue; // paired radio not connected -> stay silent
        // A paired device replays audio through the radio's own pipeline; only
        // do so while the radio's Bluetooth audio path is off, otherwise the
        // radio is already decoding this audio and we would duplicate it.
        final bool radioAudioOn =
            _broker.getValue<bool>(radioId, 'AudioState', false) ?? false;
        if (radioAudioOn) continue;
        attributeDeviceId = radioId;
        radioMac = d.pairedRadioMac.toUpperCase();
      }
      desired[d.deviceId] = _Plan(
        config: d,
        attributeDeviceId: attributeDeviceId,
        radioMac: radioMac,
      );
    }

    // Stop pipelines that are no longer desired.
    for (final int sourceId in _running.keys.toList()) {
      if (!desired.containsKey(sourceId)) {
        await _stop(sourceId);
      }
    }

    // Start or rebuild the desired pipelines.
    for (final MapEntry<int, _Plan> entry in desired.entries) {
      final int sourceId = entry.key;
      final _Plan plan = entry.value;
      final String signature = plan.signature;
      final _RunningCapture? existing = _running[sourceId];
      if (existing != null && existing.signature == signature) continue;
      if (existing != null) await _stop(sourceId);
      await _start(sourceId, plan);
    }

    _publishActivePorts();
  }

  Future<void> _start(int sourceId, _Plan plan) async {
    _RadioPipelineFeeder? feeder;
    if (plan.useRadioPipeline) {
      // Replay the captured audio as the paired radio's own receive stream so
      // its configured decoders (speech-to-text, Morse, SSTV, APRS, ...) run.
      final int radioId = plan.attributeDeviceId;
      feeder = _RadioPipelineFeeder(
        broker: _broker,
        radioDeviceId: radioId,
        resolveChannel: () => _resolveRadioChannelName(radioId),
        resolveUsage: () => _resolveRadioUsage(radioId),
      );
    } else {
      final SoftwareModemMode mode = plan.mode;
      if (mode == SoftwareModemMode.none) return;
      _softwareModem.registerExternalSource(
        sourceId: sourceId,
        mode: mode,
        fecEnabled: plan.config.fecEnabled,
        attributeDeviceId: plan.attributeDeviceId,
        channelName: plan.channelName,
        radioMac: plan.radioMac,
        sampleRate: audioRxSampleRate,
      );
    }

    final MicrophoneCapture capture = MicrophoneCapture(
      sampleRate: audioRxSampleRate,
      deviceId: plan.config.inputDeviceId,
      // Stereo TNC/audio interfaces usually carry the radio's receive audio on
      // one channel; capture both and pick per the device's channel setting
      // rather than letting the OS average in the unused (often noisy) channel.
      requestedChannels: 2,
      monoReduction: _monoReductionFor(plan.config.audioChannel),
      gain: plan.config.audioGain,
    );
    final bool ok = await capture.start(
      (Uint8List pcm16) => _onCapturePcm(sourceId, pcm16),
    );
    if (!ok || _disposed) {
      await capture.dispose();
      _softwareModem.unregisterExternalSource(sourceId);
      if (!_disposed) {
        _log('could not open input for "${plan.config.name}"');
      }
      return;
    }
    _running[sourceId] =
        _RunningCapture(capture, plan.signature,
            inputDeviceId: plan.config.inputDeviceId, feeder: feeder);
    feeder?.start();
    _log(
      'started "${plan.config.name}" '
      '(${plan.useRadioPipeline ? 'radio pipeline' : plan.mode.name}) on device '
      '${plan.attributeDeviceId}',
    );
  }

  Future<void> _stop(int sourceId) async {
    final _RunningCapture? running = _running.remove(sourceId);
    _decodeErrorLogged.remove(sourceId);
    running?.feeder?.close();
    _softwareModem.unregisterExternalSource(sourceId);
    if (running != null) {
      await running.capture.dispose();
    }
  }

  /// Publishes the set of input-device ids currently being captured so the
  /// editor can avoid opening a second recorder on a port already in use.
  void _publishActivePorts() {
    final List<String> ports = _running.values
        .map((_RunningCapture r) => r.inputDeviceId.toLowerCase())
        .where((String s) => s.isNotEmpty)
        .toList();
    _broker.dispatch(
      deviceId: 0,
      name: audioRxActivePortsKey,
      data: ports,
      store: true,
    );
  }

  /// Maps a device's channel preference to the capture reduction strategy.
  static MonoReduction _monoReductionFor(AudioRxChannel c) {
    switch (c) {
      case AudioRxChannel.left:
        return MonoReduction.left;
      case AudioRxChannel.right:
        return MonoReduction.right;
      case AudioRxChannel.mix:
        return MonoReduction.mix;
      case AudioRxChannel.auto:
        return MonoReduction.auto;
    }
  }

  /// Feed captured PCM to the decoder and, when this device is the one the Audio
  /// tab spectrograph is showing, republish it on the broker so every Audio tab
  /// (including detached windows) can visualize the input level.
  void _onCapturePcm(int sourceId, Uint8List pcm16) {
    // Republish for the spectrograph first and independently of decoding: the
    // live visualization the user is watching must never be suppressed by a
    // decode error on a noisy input.
    if (sourceId == _spectrogramDeviceId) {
      _broker.dispatch(
        deviceId: sourceId,
        name: 'AudioRxAudioData',
        data: pcm16,
        store: false,
      );
    }
    try {
      final _RadioPipelineFeeder? feeder = _running[sourceId]?.feeder;
      if (feeder != null) {
        feeder.onPcm48(pcm16);
      } else {
        _softwareModem.feedExternalSamples(sourceId, pcm16);
      }
    } catch (e) {
      if (_decodeErrorLogged.add(sourceId)) {
        _log('decode error on device $sourceId: $e');
      }
    }
  }

  /// The paired radio's current channel name, resolved live from its `HtStatus`
  /// (current channel id) and `Channels` list on the broker. Empty when unknown.
  String _resolveRadioChannelName(int radioId) {
    final Object? ht = _broker.getValueDynamic(radioId, 'HtStatus');
    int? chId;
    if (ht is Map) {
      chId = _asInt(ht['currChId'] ?? ht['curr_ch_id'] ?? ht['CurrChId']);
    }
    if (chId == null) return '';
    final Object? channels = _broker.getValueDynamic(radioId, 'Channels');
    if (channels is List) {
      for (final Object? e in channels) {
        if (e is Map && _asInt(e['channelId'] ?? e['ChannelId']) == chId) {
          return (e['name'] ?? e['Name'] ?? '').toString();
        }
      }
    }
    return '';
  }

  /// The paired radio's active channel-lock usage, or null when not locked, so
  /// the replayed audio carries the same usage tag the radio would emit.
  String? _resolveRadioUsage(int radioId) {
    final Object? lock = _broker.getValueDynamic(radioId, 'LockState');
    if (lock is Map) {
      final bool locked =
          (lock['isLocked'] ?? lock['IsLocked']) as bool? ?? false;
      final String usage = (lock['usage'] ?? lock['Usage'] ?? '').toString();
      if (locked && usage.isNotEmpty) return usage;
    }
    return null;
  }

  /// Parses the own device id from a 'SpectrogramSource' value of the form
  /// `audiorx:<id>`, or -1 when the spectrograph is not showing an audio device.
  static int _parseSpectrogramDeviceId(String? source) {
    if (source == null || !source.startsWith('audiorx:')) return -1;
    return int.tryParse(source.substring('audiorx:'.length)) ?? -1;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<AudioRxDevice> _readDevices() {
    final Object? raw = _broker.getValueDynamic(0, audioRxDevicesKey);
    if (raw is! List) return <AudioRxDevice>[];
    final List<AudioRxDevice> devices = <AudioRxDevice>[];
    for (final Object? e in raw) {
      if (e is Map) devices.add(AudioRxDevice.fromMap(e));
    }
    return devices;
  }

  /// The connected radios' live device ids keyed by their upper-cased MAC.
  Map<String, int> _connectedRadioIdsByMac() {
    final Map<String, int> byMac = <String, int>{};
    final Object? raw = _broker.getValueDynamic(1, 'ConnectedRadios');
    if (raw is List) {
      for (final Object? e in raw) {
        if (e is! Map) continue;
        final String mac =
            (e['MacAddress'] ?? e['macAddress'] ?? '').toString().toUpperCase();
        if (mac.isEmpty) continue;
        final int? id = _asInt(e['DeviceId'] ?? e['deviceId']);
        if (id != null) byMac[mac] = id;
      }
    }
    return byMac;
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  void _log(String msg) {
    _broker.dispatch(
      deviceId: 1,
      name: 'LogInfo',
      data: '[AudioRx] $msg',
      store: false,
    );
  }
}

/// A resolved run plan for one device in a single reconcile pass.
class _Plan {
  final AudioRxDevice config;
  final int attributeDeviceId;
  final String radioMac;

  _Plan({
    required this.config,
    required this.attributeDeviceId,
    required this.radioMac,
  });

  /// Paired devices replay audio through the radio's own receive pipeline
  /// (voice + data) rather than a single fixed software-modem source.
  bool get useRadioPipeline => config.usage == AudioRxUsage.paired;

  SoftwareModemMode get mode {
    if (config.usage == AudioRxUsage.aprs) return SoftwareModemMode.afsk1200;
    switch (config.modem) {
      case AudioRxModem.psk2400:
        return SoftwareModemMode.psk2400;
      case AudioRxModem.dart:
        return SoftwareModemMode.dart;
      case AudioRxModem.afsk1200:
        return SoftwareModemMode.afsk1200;
    }
  }

  /// APRS must route on the "APRS" channel; a Comms device uses its name as the
  /// received channel.
  String get channelName {
    if (config.usage == AudioRxUsage.aprs) return 'APRS';
    if (config.usage == AudioRxUsage.paired) return '';
    return config.name;
  }

  String get signature =>
      '${config.inputDeviceId}|${mode.name}|${config.fecEnabled}|'
      '$attributeDeviceId|$channelName|$radioMac|$useRadioPipeline|'
      '${config.audioChannel.name}|${config.audioGain}';
}

/// Replays a captured 48 kHz audio stream as the paired radio's own receive
/// audio: it downsamples to the 32 kHz the radio audio path uses and publishes
/// `AudioDataStart` / `AudioDataAvailable` / `AudioDataEnd` on the radio's
/// device id, so the software modem (APRS / data) and the comms handler
/// (speech-to-text, Morse, SSTV, ...) decode it with the radio's own
/// configuration.
///
/// A soundcard capture has no squelch, so a simple RMS gate synthesizes the
/// audio-run boundaries the radio firmware would otherwise provide: a run opens
/// when the level rises above [_openRms] and closes after [_hangMs] below
/// [_closeRms]. Audio frames are only published while a run is open.
class _RadioPipelineFeeder {
  _RadioPipelineFeeder({
    required this.broker,
    required this.radioDeviceId,
    required this.resolveChannel,
    required this.resolveUsage,
  });

  final DataBrokerClient broker;
  final int radioDeviceId;
  final String Function() resolveChannel;
  final String? Function() resolveUsage;

  static const int _outputSampleRate = 32000;
  static const double _openRms = 500.0;
  static const double _closeRms = 250.0;
  static const int _hangMs = 500;

  final LinearResampler _resampler = LinearResampler(
    inputRate: audioRxSampleRate,
    outputRate: _outputSampleRate,
  );

  bool _open = false;
  int _startMs = 0;
  DateTime _lastVoice = DateTime.fromMillisecondsSinceEpoch(0);
  String _channelName = '';

  /// Marks the audio path as active so the radio panel drives its RSSI bar from
  /// the replayed audio amplitude ('RxLevel') instead of the radio's own RSSI.
  void start() {
    broker.dispatch(
      deviceId: radioDeviceId,
      name: 'AudioPathActive',
      data: true,
      store: true,
    );
  }

  void onPcm48(Uint8List pcm48) {
    final Int16List in16 = _bytesToInt16(pcm48);
    final Int16List out32 = _resampler.process(in16);
    if (out32.isEmpty) return;

    final double rms = _rms(out32);
    final DateTime now = DateTime.now();
    if (rms >= _openRms) {
      _lastVoice = now;
      if (!_open) _openRun(now);
    } else if (_open && rms >= _closeRms) {
      _lastVoice = now; // hold the run open through brief dips
    }

    if (!_open) return;
    _channelName = resolveChannel();
    _publishAvailable(out32);
    if (now.difference(_lastVoice).inMilliseconds > _hangMs) {
      _closeRun();
    }
  }

  void _openRun(DateTime now) {
    _open = true;
    _startMs = now.millisecondsSinceEpoch;
    _channelName = resolveChannel();
    broker.dispatch(
      deviceId: radioDeviceId,
      name: 'AudioDataStart',
      store: false,
      data: <String, Object?>{
        'startTime': _startMs,
        'channelName': _channelName,
        'transmit': false,
        'muted': false,
        'usage': resolveUsage(),
      },
    );
  }

  void _publishAvailable(Int16List pcm32) {
    final Uint8List bytes = _int16ToBytes(pcm32);
    broker.dispatch(
      deviceId: radioDeviceId,
      name: 'AudioDataAvailable',
      store: false,
      data: <String, Object?>{
        'data': bytes,
        'offset': 0,
        'length': bytes.length,
        'channelName': _channelName,
        'transmit': false,
        'muted': false,
        'audioRunStartTime': _startMs,
        'usage': resolveUsage(),
      },
    );
    // Feed the panel's RSSI-style bar with the received audio's peak level.
    broker.dispatch(
      deviceId: radioDeviceId,
      name: 'RxLevel',
      data: _peak(pcm32),
      store: false,
    );
  }

  void _closeRun() {
    if (!_open) return;
    _open = false;
    broker.dispatch(
      deviceId: radioDeviceId,
      name: 'AudioDataEnd',
      store: false,
      data: <String, Object?>{
        'startTime': _startMs,
        'transmit': false,
        'usage': resolveUsage(),
      },
    );
    // Drop the RSSI-style bar back to zero at the end of a run.
    broker.dispatch(
      deviceId: radioDeviceId,
      name: 'RxLevel',
      data: 0.0,
      store: false,
    );
  }

  /// Ends any open run (so trailing decoders flush), clears the audio-path
  /// active flag, and resets the resampler.
  void close() {
    _closeRun();
    broker.dispatch(
      deviceId: radioDeviceId,
      name: 'AudioPathActive',
      data: false,
      store: true,
    );
    _resampler.reset();
  }

  static Int16List _bytesToInt16(Uint8List bytes) {
    final int n = bytes.length ~/ 2;
    final ByteData bd = ByteData.sublistView(bytes, 0, n * 2);
    final Int16List out = Int16List(n);
    for (int i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  static Uint8List _int16ToBytes(Int16List samples) {
    final Uint8List bytes = Uint8List(samples.length * 2);
    final ByteData bd = ByteData.sublistView(bytes);
    for (int i = 0; i < samples.length; i++) {
      bd.setInt16(i * 2, samples[i], Endian.little);
    }
    return bytes;
  }

  static double _rms(Int16List samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (final int s in samples) {
      sum += s.toDouble() * s.toDouble();
    }
    return math.sqrt(sum / samples.length);
  }

  static double _peak(Int16List samples) {
    int peak = 0;
    for (final int s in samples) {
      final int a = s < 0 ? -s : s;
      if (a > peak) peak = a;
    }
    return (peak / 32768.0).clamp(0.0, 1.0);
  }
}
