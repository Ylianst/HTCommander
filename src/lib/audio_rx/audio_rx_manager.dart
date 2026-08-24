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

import 'package:flutter/foundation.dart';

import '../radio/software_modem.dart';
import '../services/data_broker_client.dart';
import '../services/microphone_capture.dart';
import 'audio_rx_device.dart';

/// A currently-running capture + decode pipeline for one Audio Receive Device.
class _RunningCapture {
  final MicrophoneCapture capture;

  /// Signature of the configuration this capture was started for; a change means
  /// the pipeline must be rebuilt.
  final String signature;

  _RunningCapture(this.capture, this.signature);
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
      if (d.isPaired) {
        final int? radioId = connected[d.pairedRadioMac.toUpperCase()];
        if (radioId == null) continue; // paired radio not connected -> stay silent
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
  }

  Future<void> _start(int sourceId, _Plan plan) async {
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
    _running[sourceId] = _RunningCapture(capture, plan.signature);
    _log(
      'started "${plan.config.name}" (${mode.name}) on device '
      '${plan.attributeDeviceId}',
    );
  }

  Future<void> _stop(int sourceId) async {
    final _RunningCapture? running = _running.remove(sourceId);
    _decodeErrorLogged.remove(sourceId);
    _softwareModem.unregisterExternalSource(sourceId);
    if (running != null) {
      await running.capture.dispose();
    }
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
      _softwareModem.feedExternalSamples(sourceId, pcm16);
    } catch (e) {
      if (_decodeErrorLogged.add(sourceId)) {
        _log('decode error on device $sourceId: $e');
      }
    }
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

  /// APRS must route on the "APRS" channel; an unpaired Comms device uses its
  /// name as the received channel; a paired device inherits the radio's identity
  /// so it carries no channel name of its own.
  String get channelName {
    if (config.usage == AudioRxUsage.aprs) return 'APRS';
    if (radioMac.isNotEmpty) return '';
    return config.name;
  }

  String get signature =>
      '${config.inputDeviceId}|${mode.name}|${config.fecEnabled}|'
      '$attributeDeviceId|$channelName|$radioMac|${config.audioChannel.name}|'
      '${config.audioGain}';
}
