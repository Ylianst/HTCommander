/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// audio_rx_device.dart - A user-configured "Audio Receive Device": a computer
// sound-card input that HTCommander decodes data off (AFSK 1200 / PSK 2400 /
// DART), receive-only. Round-tripped to JSON for persistence on Data Broker
// device 0. Kept free of dart:io so the UI and web stub can reference it.
//

/// DataBroker key (device 0, persisted) holding the configured audio receive
/// device list.
const String audioRxDevicesKey = 'AudioReceiveDevices';

/// DataBroker key (device 0, not meaningfully persisted) holding the list of
/// input-device ids the manager is currently capturing. The editor consults it
/// to avoid opening a second recorder on a port already in use (which crashes).
const String audioRxActivePortsKey = 'AudioReceiveActivePorts';

/// First DataBroker device id used for Audio Receive Devices. Each configured
/// device owns a unique id at or above this base so its decoded frames have a
/// stable source identity when it is not paired to a radio. Chosen above the
/// EchoLink (200) and AllStarLink (202/203) pseudo-device ids and the physical
/// radio range (>=100).
const int audioRxDeviceIdBase = 300;

/// Sample rate audio receive devices capture and decode at. Higher than the
/// radio/SBC path's 32 kHz for finer AFSK/PSK timing; DART is downsampled to
/// 32 kHz internally.
const int audioRxSampleRate = 48000;

/// What kind of traffic an audio receive device carries, which decides where its
/// decoded frames are routed:
/// * [aprs]   - frames are received on the "APRS" channel.
/// * [comms]  - frames are received on a channel named after the device.
/// * [paired] - frames are received on the current channel of a paired radio,
///   inheriting that channel's id and name at the moment each frame decodes.
enum AudioRxUsage { aprs, comms, paired }

/// Which software demodulator an audio receive device runs. APRS always uses
/// AFSK 1200; the choice applies to [AudioRxUsage.comms] and
/// [AudioRxUsage.paired] devices.
enum AudioRxModem { afsk1200, psk2400, dart }

/// How a stereo capture is collapsed to the mono stream the decoder and
/// spectrograph use. Stereo TNC/audio interfaces often carry the radio's
/// receive audio on one channel, so [auto] (loudest channel) is the default;
/// [mix] averages both, [left]/[right] force one.
enum AudioRxChannel { auto, left, right, mix }

class AudioRxDevice {
  /// This device's own DataBroker device id (>= [audioRxDeviceIdBase]). Used as
  /// the source identity for decoded frames when the device is not paired.
  final int deviceId;

  /// Friendly name. When the device is not paired to a radio this is shown as
  /// the received channel in the Comms tab.
  final String name;

  /// Operating-system capture device id (record package `InputDevice.id`).
  final String inputDeviceId;

  /// Last-known human-readable label of the input device, for display when the
  /// port list cannot be enumerated (e.g. the device is unplugged).
  final String inputDeviceLabel;

  final AudioRxUsage usage;

  /// Demodulator for Comms usage. Ignored for APRS (always AFSK 1200).
  final AudioRxModem modem;

  /// When true, FX.25 forward error correction is honored on received frames.
  final bool fecEnabled;

  /// MAC address of the radio this device is paired to (only used when [usage]
  /// is [AudioRxUsage.paired]), or empty otherwise. When paired, decoded frames
  /// are attributed to that radio and its currently-tuned channel.
  final String pairedRadioMac;

  /// Which channel of a stereo input to use (or how to combine them).
  final AudioRxChannel audioChannel;

  /// Linear input gain applied to captured audio (1.0 = unchanged). Boosts a
  /// quiet line-in that has no analog gain of its own.
  final double audioGain;

  const AudioRxDevice({
    required this.deviceId,
    required this.name,
    required this.inputDeviceId,
    this.inputDeviceLabel = '',
    this.usage = AudioRxUsage.aprs,
    this.modem = AudioRxModem.afsk1200,
    this.fecEnabled = true,
    this.pairedRadioMac = '',
    this.audioChannel = AudioRxChannel.auto,
    this.audioGain = 1.0,
  });

  bool get isPaired =>
      usage == AudioRxUsage.paired && pairedRadioMac.isNotEmpty;

  AudioRxDevice copyWith({
    int? deviceId,
    String? name,
    String? inputDeviceId,
    String? inputDeviceLabel,
    AudioRxUsage? usage,
    AudioRxModem? modem,
    bool? fecEnabled,
    String? pairedRadioMac,
    AudioRxChannel? audioChannel,
    double? audioGain,
  }) {
    return AudioRxDevice(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      inputDeviceId: inputDeviceId ?? this.inputDeviceId,
      inputDeviceLabel: inputDeviceLabel ?? this.inputDeviceLabel,
      usage: usage ?? this.usage,
      modem: modem ?? this.modem,
      fecEnabled: fecEnabled ?? this.fecEnabled,
      pairedRadioMac: pairedRadioMac ?? this.pairedRadioMac,
      audioChannel: audioChannel ?? this.audioChannel,
      audioGain: audioGain ?? this.audioGain,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'DeviceId': deviceId,
        'Name': name,
        'InputDeviceId': inputDeviceId,
        'InputDeviceLabel': inputDeviceLabel,
        'Usage': _usageToString(usage),
        'Modem': _modemToString(modem),
        'Fec': fecEnabled,
        'PairedRadioMac': pairedRadioMac,
        'AudioChannel': _channelToString(audioChannel),
        'AudioGain': audioGain,
      };

  static AudioRxDevice fromMap(Map<dynamic, dynamic> m) {
    String str(Object? a, Object? b) => (a ?? b ?? '').toString();
    int parseInt(Object? v, int fallback) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return AudioRxDevice(
      deviceId: parseInt(m['DeviceId'] ?? m['deviceId'], audioRxDeviceIdBase),
      name: str(m['Name'], m['name']),
      inputDeviceId: str(m['InputDeviceId'], m['inputDeviceId']),
      inputDeviceLabel: str(m['InputDeviceLabel'], m['inputDeviceLabel']),
      usage: _usageFromMap(
        str(m['Usage'], m['usage']),
        str(m['PairedRadioMac'], m['pairedRadioMac']),
      ),
      modem: _modemFromString(str(m['Modem'], m['modem'])),
      fecEnabled: (m['Fec'] ?? m['fec']) as bool? ?? true,
      pairedRadioMac: str(m['PairedRadioMac'], m['pairedRadioMac']),
      audioChannel: _channelFromString(str(m['AudioChannel'], m['audioChannel'])),
      audioGain: _asDouble(m['AudioGain'] ?? m['audioGain'], 1.0),
    );
  }

  static double _asDouble(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static String _usageToString(AudioRxUsage usage) {
    switch (usage) {
      case AudioRxUsage.comms:
        return 'comms';
      case AudioRxUsage.paired:
        return 'paired';
      case AudioRxUsage.aprs:
        return 'aprs';
    }
  }

  /// Resolves the stored usage, migrating older devices that recorded a paired
  /// radio MAC alongside an 'aprs'/'comms' usage into the [AudioRxUsage.paired]
  /// mode.
  static AudioRxUsage _usageFromMap(String usage, String pairedMac) {
    if (usage == 'paired' || pairedMac.isNotEmpty) return AudioRxUsage.paired;
    if (usage == 'comms') return AudioRxUsage.comms;
    return AudioRxUsage.aprs;
  }

  static String _modemToString(AudioRxModem modem) {
    switch (modem) {
      case AudioRxModem.psk2400:
        return 'psk2400';
      case AudioRxModem.dart:
        return 'dart';
      case AudioRxModem.afsk1200:
        return 'afsk1200';
    }
  }

  static AudioRxModem _modemFromString(String s) {
    switch (s.toLowerCase()) {
      case 'psk2400':
        return AudioRxModem.psk2400;
      case 'dart':
        return AudioRxModem.dart;
      default:
        return AudioRxModem.afsk1200;
    }
  }

  static String _channelToString(AudioRxChannel c) {
    switch (c) {
      case AudioRxChannel.left:
        return 'left';
      case AudioRxChannel.right:
        return 'right';
      case AudioRxChannel.mix:
        return 'mix';
      case AudioRxChannel.auto:
        return 'auto';
    }
  }

  static AudioRxChannel _channelFromString(String s) {
    switch (s.toLowerCase()) {
      case 'left':
        return AudioRxChannel.left;
      case 'right':
        return AudioRxChannel.right;
      case 'mix':
        return AudioRxChannel.mix;
      default:
        return AudioRxChannel.auto;
    }
  }
}
