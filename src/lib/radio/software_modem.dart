/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Dart port of the C# SoftwareModem. This Data Broker handler processes PCM audio
from radios and decodes/encodes TNC frames using AFSK 1200 and PSK 2400
modulation via the hamlib software modem library.
*/

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../hamlib/audio_buffer.dart';
import '../hamlib/audio_config.dart';
import '../hamlib/dart_modem.dart';
import '../hamlib/demod_afsk.dart';
import '../hamlib/demod_psk.dart';
import '../hamlib/fx25.dart';
import '../hamlib/fx25_rec.dart';
import '../hamlib/fx25_send.dart';
import '../hamlib/gen_tone.dart';
import '../hamlib/hdlc_rec.dart';
import '../hamlib/hdlc_rec2.dart';
import '../hamlib/hdlc_send.dart';
import '../hamlib/ihdlc_receiver.dart';
import '../hamlib/multi_modem.dart';
import '../models/radio_models.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'tnc_data_fragment.dart';

/// Software modem mode types.
enum SoftwareModemMode {
  none,
  afsk1200,
  psk2400,
  dart,
}

/// Holds a frame waiting to be transmitted once the channel is clear. The
/// audio is generated at flush time so multiple queued frames can be bundled
/// into a single transmission (one preamble/postamble for all of them).
class _PendingTransmission {
  final Uint8List frameData;
  final FragmentFrameType frameType;
  final DateTime deadline;

  /// Which modem instance (general or APRS) should modulate this frame. Frames
  /// are only bundled together when they share the same target instance.
  final _ModemInstance target;
  _PendingTransmission(
    this.frameData,
    this.frameType,
    this.deadline,
    this.target,
  );
}

/// Per-radio modem state. Holds up to two full modem pipelines: a general one
/// (the user-selected mode) and a dedicated APRS one (AFSK 1200), plus the
/// radio-global clear-channel transmit queue.
class _RadioModemState {
  int deviceId;
  String macAddress;
  String currentChannelName = '';
  int currentChannelId = 0;
  int currentRegionId = 0;

  /// Cached id of the channel named "APRS" on this radio (-1 if none). Used to
  /// route received audio and transmits to the APRS modem instance.
  int aprsChannelId = -1;

  /// The user's general software modem (null when the general modem is off).
  _ModemInstance? generalModem;

  /// The dedicated APRS modem, always AFSK 1200 (null when the APRS modem is
  /// off). Used only for audio on / transmits to the APRS channel.
  _ModemInstance? aprsModem;

  // Clear-channel transmit queue (radio-global; one transmission at a time).
  final List<_PendingTransmission> transmitQueue = [];
  bool waitingForChannel = false;
  bool channelIsClear = false;
  Timer? channelWaitTimer;

  _RadioModemState({
    required this.deviceId,
    required this.macAddress,
  });

  void dispose() {
    channelWaitTimer?.cancel();
    channelWaitTimer = null;
    transmitQueue.clear();
    waitingForChannel = false;
    generalModem?.dispose();
    generalModem = null;
    aprsModem?.dispose();
    aprsModem = null;
  }
}

/// One complete software-modem pipeline (receive + transmit) for a single
/// modulation mode. A radio holds up to two of these: one for the user's
/// general mode and one dedicated to the APRS channel (AFSK 1200). Each has its
/// own FX.25 FEC setting.
class _ModemInstance {
  final SoftwareModemMode mode;
  final FragmentEncodingType encoding;

  /// When true, transmitted frames meeting the AX.25 minimum length are wrapped
  /// in FX.25 forward error correction. Independent per instance.
  bool fecEnabled;

  final AudioConfig audioConfig;

  // Receive chain.
  DemodAfsk? afskDemodulator;
  DemodulatorState? afskDemodState;
  DemodPsk? pskDemodulator;
  PskDemodulatorState? pskDemodState;
  HdlcRec2? hdlcReceiver;
  Fx25Rec? fx25Receiver;
  _HdlcFx25Bridge? bridge;

  // Transmit chain.
  GenTone? packetGenTone;
  AudioBuffer? packetAudioBuffer;
  HdlcSend? packetHdlcSend;
  Fx25Send? packetFx25Send;

  // --- DART modem (frame-based; bypasses the HDLC/FX.25/GenTone chain) ---
  /// Non-null only for [SoftwareModemMode.dart]. Encodes/decodes whole frames.
  DartModem? dartModem;

  /// Payload mode used when transmitting DART frames.
  DartMode dartTxMode = DartMode.mode2;

  /// Rolling receive buffer of 16-bit samples awaiting a DART decode.
  final List<int> dartRxSamples = <int>[];

  /// Monotonic sequence number for transmitted DART frames.
  int dartTxSeq = 0;

  /// Called with a decoded DART payload (a raw AX.25 frame) so the owner can
  /// dispatch it. Wired up in _buildInstance for DART instances.
  void Function(Uint8List frame, DartDecodeResult result)? onDartFrame;

  // A valid-FCS frame the plain HDLC receiver decoded from inside an FX.25
  // block, held briefly while we wait to see if the FX.25 Reed-Solomon path
  // delivers the same frame. If it does not (RS decode failed or the block did
  // not complete), this copy is delivered as an AX.25 fallback so a good frame
  // is never lost. See SoftwareModem._onFrameReceived / _flushPendingFrame.
  Uint8List? pendingFrameData;
  int pendingFrameChannel = 0;
  Timer? pendingFrameTimer;

  _ModemInstance({
    required this.mode,
    required this.encoding,
    required this.fecEnabled,
    required this.audioConfig,
  });

  /// Feed a block of little-endian 16-bit mono PCM to this pipeline's
  /// demodulator.
  void processSamples(Uint8List data, int offset, int length) {
    const int chan = 0;
    const int subchan = 0;
    if (dartModem != null) {
      _processDartSamples(data, offset, length);
      return;
    }
    if (afskDemodulator != null && afskDemodState != null) {
      for (int i = offset; i < offset + length - 1; i += 2) {
        final int sample = (data[i] | (data[i + 1] << 8)).toSigned(16);
        afskDemodulator!.processSample(chan, subchan, sample, afskDemodState!);
      }
    } else if (pskDemodulator != null && pskDemodState != null) {
      for (int i = offset; i < offset + length - 1; i += 2) {
        final int sample = (data[i] | (data[i + 1] << 8)).toSigned(16);
        pskDemodulator!.processSample(chan, subchan, sample, pskDemodState!);
      }
    }
  }

  /// Maximum DART receive buffer (~8 s at 32 kHz) before old audio is dropped.
  static const int _dartMaxRxSamples = 32000 * 8;

  /// Attempt a decode roughly every this-many new samples (throttle the O(N)
  /// preamble correlation).
  static const int _dartDecodeStride = 4000;

  int _dartSamplesSinceDecode = 0;

  /// Buffer incoming PCM and attempt to decode complete DART frames.
  void _processDartSamples(Uint8List data, int offset, int length) {
    for (int i = offset; i < offset + length - 1; i += 2) {
      dartRxSamples.add((data[i] | (data[i + 1] << 8)).toSigned(16));
      _dartSamplesSinceDecode++;
    }

    // Throttle decode attempts.
    if (_dartSamplesSinceDecode < _dartDecodeStride) return;
    _dartSamplesSinceDecode = 0;

    // Try to decode from the current buffer; on success, consume the frame.
    while (dartRxSamples.length > 2000) {
      final Int16List buf = Int16List.fromList(dartRxSamples);
      final result = dartModem!.decode(buf);
      if (result == null) break;
      if (result.crcOk) {
        onDartFrame?.call(result.payload, result);
      }
      // Consume everything up to the end of this frame.
      final int consume = result.endSample.clamp(0, dartRxSamples.length);
      if (consume <= 0) break;
      dartRxSamples.removeRange(0, consume);
    }

    // Bound memory: if no frame is completing, drop the oldest half.
    if (dartRxSamples.length > _dartMaxRxSamples) {
      dartRxSamples.removeRange(0, dartRxSamples.length ~/ 2);
    }
  }

  void dispose() {
    pendingFrameTimer?.cancel();
    pendingFrameTimer = null;
    pendingFrameData = null;
    afskDemodulator = null;
    afskDemodState = null;
    pskDemodulator = null;
    pskDemodState = null;
    hdlcReceiver = null;
    fx25Receiver = null;
    bridge = null;
    packetGenTone = null;
    packetAudioBuffer = null;
    packetHdlcSend = null;
    packetFx25Send = null;
    dartModem = null;
    dartRxSamples.clear();
    onDartFrame = null;
  }
}

/// Bridge that feeds bits to both HDLC and FX.25 receivers.
class _HdlcFx25Bridge implements IHdlcReceiver {
  final IHdlcReceiver _hdlcReceiver;
  final Fx25Rec _fx25Receiver;
  int _prevRaw = 0;

  _HdlcFx25Bridge(this._hdlcReceiver, this._fx25Receiver);

  @override
  void recBit(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool isScrambled,
    int notUsedRemove,
  ) {
    _hdlcReceiver.recBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
    // The FX.25 receiver expects the NRZI-decoded data bit (Direwolf calls
    // fx25_rec_bit() with dbit), not the raw bit. A '1' is no change, a '0' is
    // a transition. For 9600 the descrambling already happened in demod_9600.
    final int dbit = (raw == _prevRaw) ? 1 : 0;
    _prevRaw = raw;
    _fx25Receiver.recBit(chan, subchan, slice, dbit);
  }

  @override
  void dcdChange(int chan, int subchan, int slice, bool dcdOn) {
    _hdlcReceiver.dcdChange(chan, subchan, slice, dcdOn);
  }
}

/// Software modem Data Broker handler that processes PCM audio from radios
/// and decodes/encodes TNC frames using various modulation schemes.
class SoftwareModem {
  final DataBrokerClient _broker = DataBrokerClient();
  final Map<int, _RadioModemState> _radioModems = {};
  SoftwareModemMode _currentMode = SoftwareModemMode.none;
  // When true, transmitted packets that meet the AX.25 minimum length are wrapped
  // in FX.25 forward error correction. When false, all packets are sent as plain
  // AX.25 (no FEC). Lets the user test with and without FX.25.
  bool _fecEnabled = true;
  // The APRS modem is an independent pipeline used only for the APRS channel. It
  // is either off or AFSK 1200 and has its own FX.25 FEC setting, separate from
  // the general modem above.
  SoftwareModemMode _aprsMode = SoftwareModemMode.none;
  bool _aprsFecEnabled = true;
  bool _disposed = false;
  bool _initialized = false;
  static final math.Random _rng = math.Random();

  // Per-session modem override (Terminal / Winlink contacts). While a session
  // is active the mode is switched to the contact's modem and the user's
  // regular setting is restored when the session ends.
  SoftwareModemMode? _sessionOverrideSavedMode;
  bool _sessionOverrideActive = false;

  /// Gets the current modem mode.
  SoftwareModemMode get currentMode => _currentMode;

  /// Checks if software modem is enabled.
  bool get isEnabled => _currentMode != SoftwareModemMode.none;

  /// Initialize the software modem handler.
  void init() {
    if (_initialized || _disposed) return;
    _initialized = true;

    // Load saved mode from device 0 (settings)
    final String savedMode =
        _broker.getValue<String>(0, 'SoftwareModemMode', 'None') ?? 'None';
    _currentMode = _parseMode(savedMode);

    // Load saved FX.25 FEC preference (defaults to enabled).
    _fecEnabled = _broker.getValue<bool>(0, 'SoftwareModemFec', true) ?? true;

    // Load the independent APRS modem settings (off or AFSK 1200, own FEC).
    _aprsMode = _parseAprsMode(
        _broker.getValue<String>(0, 'AprsSoftwareModemMode', 'None') ?? 'None');
    _aprsFecEnabled =
        _broker.getValue<bool>(0, 'AprsSoftwareModemFec', true) ?? true;

    // Subscribe to mode changes on device 0
    _broker.subscribe(
      deviceId: 0,
      name: 'SetSoftwareModemMode',
      callback: _onSetModeRequested,
    );

    // Subscribe to FX.25 FEC on/off changes on device 0
    _broker.subscribe(
      deviceId: 0,
      name: 'SetSoftwareModemFec',
      callback: _onSetFecRequested,
    );

    // Subscribe to per-session modem overrides (Terminal / Winlink contacts).
    _broker.subscribe(
      deviceId: 0,
      name: 'SetSessionModem',
      callback: _onSetSessionModem,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'ClearSessionModem',
      callback: _onClearSessionModem,
    );

    // Subscribe to the independent APRS modem mode / FEC changes on device 0.
    _broker.subscribe(
      deviceId: 0,
      name: 'SetAprsSoftwareModemMode',
      callback: _onSetAprsModeRequested,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'SetAprsSoftwareModemFec',
      callback: _onSetAprsFecRequested,
    );

    // Subscribe to audio data from all radios
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioDataAvailable',
      callback: _onAudioDataAvailable,
    );

    // Subscribe to HtStatus changes from all radios to update channel info
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'HtStatus',
      callback: _onHtStatusChanged,
    );

    // Subscribe to transmit packet requests from all radios
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'SoftModemTransmitPacket',
      callback: _onTransmitPacketRequested,
    );

    // Subscribe to channel-clear notifications from all radios
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'ChannelClear',
      callback: _onChannelClear,
    );

    // Publish initial mode
    _broker.dispatch(deviceId: 0, name: 'SoftwareModemMode', data: _currentMode.name, store: true);

    // Publish initial FX.25 FEC state
    _broker.dispatch(deviceId: 0, name: 'SoftwareModemFec', data: _fecEnabled, store: true);

    // Publish initial APRS modem mode and FEC state.
    _broker.dispatch(deviceId: 0, name: 'AprsSoftwareModemMode', data: _aprsMode.name, store: true);
    _broker.dispatch(deviceId: 0, name: 'AprsSoftwareModemFec', data: _aprsFecEnabled, store: true);

    _debug('SoftwareModem initialized with mode: ${_currentMode.name}');
  }

  /// Dispose the software modem handler.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    for (final state in _radioModems.values) {
      state.dispose();
    }
    _radioModems.clear();
    _broker.dispose();
  }

  // ---------------------------------------------------------------------------
  // Mode management
  // ---------------------------------------------------------------------------

  static SoftwareModemMode _parseMode(String mode) {
    switch (mode.toUpperCase()) {
      case 'AFSK1200':
        return SoftwareModemMode.afsk1200;
      case 'PSK2400':
        return SoftwareModemMode.psk2400;
      case 'DART':
        return SoftwareModemMode.dart;
      default:
        return SoftwareModemMode.none;
    }
  }

  /// Parses an APRS modem setting. The APRS modem supports only AFSK 1200
  /// (or off), so any other value maps to [SoftwareModemMode.none].
  static SoftwareModemMode _parseAprsMode(String mode) {
    return mode.toUpperCase() == 'AFSK1200'
        ? SoftwareModemMode.afsk1200
        : SoftwareModemMode.none;
  }

  static FragmentEncodingType _getEncodingType(SoftwareModemMode mode) {
    switch (mode) {
      case SoftwareModemMode.afsk1200:
        return FragmentEncodingType.softwareAfsk1200;
      case SoftwareModemMode.psk2400:
        return FragmentEncodingType.softwarePsk2400;
      case SoftwareModemMode.dart:
        return FragmentEncodingType.softwareDart;
      default:
        return FragmentEncodingType.unknown;
    }
  }

  /// Sets the software modem mode. When [persist] is false the change is
  /// applied live but the stored user preference (device 0 'SoftwareModemMode')
  /// is left untouched - used for temporary per-session overrides.
  void setMode(SoftwareModemMode mode, {bool persist = true}) {
    if (_currentMode == mode) return;

    _debug('Changing software modem mode from ${_currentMode.name} to ${mode.name}');

    // Cleanup all existing per-radio modem states
    for (final state in _radioModems.values) {
      state.dispose();
    }
    _radioModems.clear();

    _currentMode = mode;

    // Save to device 0 (settings). During a session override we do not persist
    // so the user's regular setting is preserved.
    _broker.dispatch(
      deviceId: 0,
      name: 'SoftwareModemMode',
      data: mode.name,
      store: persist,
    );

    _debug('Software modem mode changed to ${mode.name}');
  }

  /// Sets the independent APRS modem mode (off or AFSK 1200). Rebuilds all
  /// per-radio pipelines so the APRS instance is (re)created or removed.
  void setAprsMode(SoftwareModemMode mode, {bool persist = true}) {
    // The APRS modem is only ever off or AFSK 1200.
    final SoftwareModemMode target =
        mode == SoftwareModemMode.afsk1200 ? mode : SoftwareModemMode.none;
    if (_aprsMode == target) return;

    _debug('Changing APRS modem from ${_aprsMode.name} to ${target.name}');

    for (final state in _radioModems.values) {
      state.dispose();
    }
    _radioModems.clear();

    _aprsMode = target;
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsSoftwareModemMode',
      data: _aprsMode.name,
      store: persist,
    );
  }

  void _onSetModeRequested(int deviceId, String name, Object? data) {
    if (_disposed) return;

    final String modeStr = (data is String) ? data : (data?.toString() ?? '');
    final SoftwareModemMode newMode = _parseMode(modeStr);
    // A manual mode change ends any active session override so a later
    // ClearSessionModem does not revert the user's new choice.
    _sessionOverrideActive = false;
    _sessionOverrideSavedMode = null;
    setMode(newMode);
  }

  /// Enable/disable FX.25 forward error correction on transmit. When disabled,
  /// all packets are sent as plain AX.25 (no FEC).
  void _onSetFecRequested(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! bool) return;
    _fecEnabled = data;
    // Apply to any live general instances immediately.
    for (final state in _radioModems.values) {
      state.generalModem?.fecEnabled = _fecEnabled;
    }
    _broker.dispatch(
      deviceId: 0,
      name: 'SoftwareModemFec',
      data: _fecEnabled,
      store: true,
    );
    _debug('Software modem FX.25 FEC ${_fecEnabled ? "enabled" : "disabled"}');
  }

  /// Handle a request to change the independent APRS modem mode (off/AFSK1200).
  void _onSetAprsModeRequested(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final String modeStr = (data is String) ? data : (data?.toString() ?? '');
    setAprsMode(_parseAprsMode(modeStr));
  }

  /// Enable/disable FX.25 FEC for the APRS modem (independent of the general
  /// modem's FEC setting).
  void _onSetAprsFecRequested(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! bool) return;
    _aprsFecEnabled = data;
    // Apply to any live APRS instances immediately.
    for (final state in _radioModems.values) {
      state.aprsModem?.fecEnabled = _aprsFecEnabled;
    }
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsSoftwareModemFec',
      data: _aprsFecEnabled,
      store: true,
    );
    _debug('APRS modem FX.25 FEC ${_aprsFecEnabled ? "enabled" : "disabled"}');
  }
  /// [data] is the contact's modem value: 'Hardware' (radio TNC -> software
  /// modem off), 'AFSK1200' or 'PSK2400'.
  void _onSetSessionModem(int deviceId, String name, Object? data) {
    if (_disposed) return;

    final String modemStr = (data is String) ? data : (data?.toString() ?? '');
    // Software modem modes require the audio channel, which is unavailable on
    // web and iOS - fall back to the radio's hardware TNC there.
    final bool audioSupported = !kIsWeb && !Platform.isIOS;
    final SoftwareModemMode target =
        audioSupported ? _parseMode(modemStr) : SoftwareModemMode.none;

    // Remember the user's regular mode the first time we override.
    if (!_sessionOverrideActive) {
      _sessionOverrideSavedMode = _currentMode;
      _sessionOverrideActive = true;
    }

    _debug('Session modem override -> ${target.name} (was ${_sessionOverrideSavedMode?.name})');
    setMode(target, persist: false);
  }

  /// Restore the user's regular modem mode after a session ends.
  void _onClearSessionModem(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (!_sessionOverrideActive) return;

    final SoftwareModemMode restore =
        _sessionOverrideSavedMode ?? SoftwareModemMode.none;
    _sessionOverrideActive = false;
    _sessionOverrideSavedMode = null;

    _debug('Session modem override cleared, restoring ${restore.name}');
    setMode(restore, persist: false);
  }

  // ---------------------------------------------------------------------------
  // Audio data processing
  // ---------------------------------------------------------------------------

  void _onAudioDataAvailable(int deviceId, String name, Object? data) {
    if (_disposed || deviceId <= 0) return;
    if (_currentMode == SoftwareModemMode.none &&
        _aprsMode == SoftwareModemMode.none) {
      return;
    }
    if (data is! Map) return;

    // Don't process transmitted audio
    final transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
    if (transmit) return;

    // Skip processing while an SSTV image is being received on this device. The
    // SSTV tones are not packet data; feeding them to the modem wastes CPU and
    // can cause spurious decodes. The voice/comms handler publishes this flag.
    if (_broker.getValue<bool>(deviceId, 'SstvReceiving', false) ?? false) {
      return;
    }

    final bytes = data['data'] ?? data['Data'];
    if (bytes is! Uint8List || bytes.isEmpty) return;

    final int offset = _readInt(data['offset'] ?? data['Offset']) ?? 0;
    final int length =
        _readInt(data['length'] ?? data['Length']) ?? (bytes.length - offset);
    final String channelName =
        (data['channelName'] ?? data['ChannelName']) as String? ?? '';

    _processPcmData(deviceId, bytes, offset, length, channelName);
  }

  void _processPcmData(
    int deviceId,
    Uint8List data,
    int offset,
    int length,
    String channelName,
  ) {
    if (_currentMode == SoftwareModemMode.none &&
        _aprsMode == SoftwareModemMode.none) {
      return;
    }

    // Get or create modem state for this radio
    _RadioModemState? state = _radioModems[deviceId];
    if (state == null) {
      state = _createRadioModemState(deviceId);
      if (state == null) return;
      _radioModems[deviceId] = state;
    }

    // Update channel name if provided
    if (channelName.isNotEmpty) {
      state.currentChannelName = channelName;
    }

    // Route the audio to the correct pipeline: the dedicated APRS modem when the
    // radio is currently on the APRS channel, otherwise the general modem. On
    // the APRS channel only the AFSK 1200 APRS modem runs; elsewhere only the
    // general modem runs.
    final _ModemInstance? rx =
        _isAprsChannel(state) ? state.aprsModem : state.generalModem;
    rx?.processSamples(data, offset, length);
  }

  /// Whether [state]'s radio is currently tuned to the APRS channel. The audio
  /// stream's channel name (set from the radio's current channel) is the primary
  /// signal, reinforced by the cached APRS channel id.
  bool _isAprsChannel(_RadioModemState state) {
    if (state.currentChannelName == 'APRS') return true;
    return state.aprsChannelId >= 0 &&
        state.currentChannelId == state.aprsChannelId;
  }

  // ---------------------------------------------------------------------------
  // Radio modem state creation and initialization
  // ---------------------------------------------------------------------------

  _RadioModemState? _createRadioModemState(int deviceId) {
    // Get radio MAC address from connected radios if possible
    String macAddress = '';
    final Object? connectedRadios =
        _broker.getValue<Object>(1, 'ConnectedRadios', null);
    if (connectedRadios is List) {
      for (final radio in connectedRadios) {
        if (radio is Map) {
          final devId = radio['DeviceId'] ?? radio['deviceId'];
          if (devId == deviceId) {
            macAddress =
                (radio['MacAddress'] ?? radio['macAddress'] ?? '') as String;
            break;
          }
        }
      }
    }

    final state = _RadioModemState(
      deviceId: deviceId,
      macAddress: macAddress,
    );

    // Get current HtStatus for channel info
    final Object? htStatus =
        _broker.getValue<Object>(deviceId, 'HtStatus', null);
    if (htStatus is Map) {
      state.currentChannelId =
          _readInt(htStatus['currChId'] ?? htStatus['curr_ch_id'] ?? htStatus['CurrChId']) ?? 0;
      state.currentRegionId =
          _readInt(htStatus['currRegion'] ?? htStatus['curr_region'] ?? htStatus['CurrRegion']) ?? 0;
    }

    // Resolve the id of this radio's APRS channel for routing.
    state.aprsChannelId = _getAprsChannelId(deviceId);

    // Initialize FX.25 subsystem
    Fx25.init(0);

    // Build the two modem pipelines that are enabled.
    if (_currentMode != SoftwareModemMode.none) {
      state.generalModem = _buildInstance(state, _currentMode, _fecEnabled);
    }
    if (_aprsMode != SoftwareModemMode.none) {
      state.aprsModem = _buildInstance(state, _aprsMode, _aprsFecEnabled);
    }

    return state;
  }

  /// Returns the channel id of the "APRS" channel for [deviceId], or -1.
  int _getAprsChannelId(int deviceId) {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      deviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return -1;
    for (final channel in channels) {
      if (channel.name == 'APRS') return channel.channelId;
    }
    return -1;
  }

  /// Builds one complete modem pipeline (receive + transmit) for [mode] with the
  /// given FX.25 [fecEnabled] flag. Frames it decodes are attributed to this
  /// exact instance (correct encoding / FEC) via per-instance callbacks.
  _ModemInstance _buildInstance(
    _RadioModemState state,
    SoftwareModemMode mode,
    bool fecEnabled,
  ) {
    // Audio configuration for 32kHz, 16-bit, mono.
    final audioConfig = AudioConfig();
    audioConfig.devices[0].defined = true;
    audioConfig.devices[0].samplesPerSec = 32000;
    audioConfig.devices[0].bitsPerSample = 16;
    audioConfig.devices[0].numChannels = 1;
    audioConfig.channelMedium[0] = Medium.radio;
    audioConfig.channels[0].numSubchan = 1;

    switch (mode) {
      case SoftwareModemMode.afsk1200:
        audioConfig.channels[0].modemType = ModemType.afsk;
        audioConfig.channels[0].markFreq = 1200;
        audioConfig.channels[0].spaceFreq = 2200;
        audioConfig.channels[0].baud = 1200;
        break;
      case SoftwareModemMode.psk2400:
        audioConfig.channels[0].modemType = ModemType.qpsk;
        // Direwolf treats achan.baud as bits-per-second for PSK; GenTone derives
        // the 1200 symbol/s rate internally (baud * 0.5). Must match the 2400
        // bps passed to the demodulator below.
        audioConfig.channels[0].baud = 2400;
        audioConfig.channels[0].v26Alt = V26Alternative.b;
        break;
      case SoftwareModemMode.dart:
        // DART bypasses the Direwolf modem config entirely.
        break;
      case SoftwareModemMode.none:
        break;
    }
    audioConfig.channels[0].txdelay = 30;
    audioConfig.channels[0].txtail = 10;

    final instance = _ModemInstance(
      mode: mode,
      encoding: _getEncodingType(mode),
      fecEnabled: fecEnabled,
      audioConfig: audioConfig,
    );

    // DART is frame-based: it owns its own preamble/FEC/framing and bypasses the
    // HDLC/FX.25/GenTone/Direwolf-demod chain. Wire up its decode callback and
    // return early.
    if (mode == SoftwareModemMode.dart) {
      instance.dartModem = DartModem();
      instance.onDartFrame = (frame, result) =>
          _onDartFrameReceived(state, instance, frame, result);
      _debug('Built DART modem instance for device ${state.deviceId}');
      return instance;
    }

    // Receive chain: HDLC + FX.25 receivers fed through the NRZI bridge. The
    // frame callbacks capture both the radio state and this instance so decoded
    // frames are attributed to the right pipeline.
    final hdlcReceiver = HdlcRec2();
    hdlcReceiver.addFrameReceived((e) => _onFrameReceived(state, instance, e));
    hdlcReceiver.init(audioConfig);
    final fx25Receiver =
        Fx25Rec(_Fx25MultiModemWrapper(state, instance, this));
    final bridge = _HdlcFx25Bridge(hdlcReceiver, fx25Receiver);
    instance.hdlcReceiver = hdlcReceiver;
    instance.fx25Receiver = fx25Receiver;
    instance.bridge = bridge;

    switch (mode) {
      case SoftwareModemMode.afsk1200:
        final demod = DemodAfsk(bridge);
        final demodState = DemodulatorState();
        demod.init(32000, 1200, 1200, 2200, 'A', demodState);
        instance.afskDemodulator = demod;
        instance.afskDemodState = demodState;
        break;
      case SoftwareModemMode.psk2400:
        final demod = DemodPsk(bridge);
        final demodState = PskDemodulatorState();
        demod.init(
            ModemType.qpsk, V26Alternative.b, 32000, 2400, 'B', demodState);
        instance.pskDemodulator = demod;
        instance.pskDemodState = demodState;
        break;
      case SoftwareModemMode.dart:
        break; // handled by the early return above
      case SoftwareModemMode.none:
        break;
    }

    // Transmit chain.
    final audioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);
    final genTone = GenTone(audioBuffer);
    genTone.init(audioConfig, 50);
    instance.packetAudioBuffer = audioBuffer;
    instance.packetGenTone = genTone;
    instance.packetHdlcSend = HdlcSend(genTone, audioConfig);
    instance.packetFx25Send = Fx25Send()..init(genTone);

    _debug('Built ${mode.name} modem instance for device ${state.deviceId}');
    return instance;
  }

  // ---------------------------------------------------------------------------
  // Frame reception
  // ---------------------------------------------------------------------------

  void _onFrameReceived(
    _RadioModemState state,
    _ModemInstance instance,
    FrameReceivedEventArgs e,
  ) {
    if (_disposed) return;

    // An FX.25 transmission carries a standard HDLC-framed AX.25 frame inside
    // its Reed-Solomon block, so the plain HDLC receiver also decodes it. If the
    // FX.25 receiver is currently mid-block, this is that embedded frame - drop
    // it here so the packet is reported once, via the FX.25 path, with the
    // correct FX.25 frame type and corrected-symbol count. (Matches Direwolf's
    // fx25_rec_busy suppression in hdlc_rec.)
    if (instance.fx25Receiver != null &&
        instance.fx25Receiver!.isBusy(e.channel)) {
      // The plain HDLC receiver decoded this frame (valid FCS) from inside an
      // FX.25 block. Rather than dropping it and relying solely on the FX.25
      // path, buffer it briefly: if the FX.25 Reed-Solomon decode succeeds it
      // delivers the frame (with the FX.25 type) and cancels this copy; if the
      // RS decode fails or the block never completes, the timer delivers this
      // buffered copy as an AX.25 fallback so a valid frame is never lost.
      instance.pendingFrameData = Uint8List(e.frameLength)
        ..setRange(0, e.frameLength, e.frame);
      instance.pendingFrameChannel = e.channel;
      instance.pendingFrameTimer?.cancel();
      instance.pendingFrameTimer = Timer(
        const Duration(milliseconds: 700),
        () => _flushPendingFrame(state, instance),
      );
      _debug(
        'RX AX.25: buffered ${e.frameLength}-byte frame during FX.25 block '
        '(delivered as fallback if FX.25 FEC does not).',
      );
      return;
    }

    final Uint8List frameData = Uint8List(e.frameLength);
    frameData.setRange(0, e.frameLength, e.frame);

    _debug(
      'RX AX.25 (no FEC): decoded ${e.frameLength}-byte frame: '
      '${_hex(frameData)}',
    );

    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: frameData,
      channelId: state.currentChannelId,
      regionId: state.currentRegionId,
      channelName: state.currentChannelName,
      incoming: true,
      encoding: instance.encoding,
      time: DateTime.now(),
      radioMac: state.macAddress,
      radioDeviceId: state.deviceId,
    );

    if (e.correctionInfo != null) {
      if (e.correctionInfo!.fecType == FecType.fx25) {
        fragment.frameType = FragmentFrameType.fx25;
        fragment.corrections = e.correctionInfo!.rsSymbolsCorrected >= 0
            ? e.correctionInfo!.rsSymbolsCorrected
            : 0;
      } else {
        fragment.frameType = FragmentFrameType.ax25;
        fragment.corrections =
            e.correctionInfo!.correctedBitPositions.length;
      }
    } else {
      fragment.frameType = FragmentFrameType.ax25;
      fragment.corrections = 0;
    }

    _dispatchDecodedFrame(state.deviceId, fragment);
  }

  /// Deliver a frame that the plain HDLC receiver decoded inside an FX.25 block
  /// when the FX.25 Reed-Solomon path did not deliver it (RS decode failed or
  /// the block never completed). Called from the timer armed in
  /// _onFrameReceived; the FX.25 delivery path cancels this by clearing
  /// [instance.pendingFrameData] first.
  void _flushPendingFrame(_RadioModemState state, _ModemInstance instance) {
    final Uint8List? pending = instance.pendingFrameData;
    instance.pendingFrameTimer = null;
    if (pending == null) return;
    instance.pendingFrameData = null;

    _debug(
      'RX AX.25 (fallback): FX.25 FEC did not deliver; delivering buffered '
      '${pending.length}-byte frame: ${_hex(pending)}',
    );

    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: pending,
      channelId: state.currentChannelId,
      regionId: state.currentRegionId,
      channelName: state.currentChannelName,
      incoming: true,
      encoding: instance.encoding,
      frameType: FragmentFrameType.ax25,
      time: DateTime.now(),
      radioMac: state.macAddress,
      radioDeviceId: state.deviceId,
    );
    fragment.corrections = 0;
    _dispatchDecodedFrame(state.deviceId, fragment);
  }

  /// Deliver a DART-decoded frame. The DART payload is the raw AX.25 frame
  /// (DART's own CRC-32 has already validated it), so it is dispatched straight
  /// through as an AX.25 fragment tagged with the DART encoding.
  void _onDartFrameReceived(
    _RadioModemState state,
    _ModemInstance instance,
    Uint8List frame,
    DartDecodeResult result,
  ) {
    if (_disposed) return;
    if (frame.isEmpty) return;

    _debug(
      'RX DART: mode ${result.header.modeIndex} '
      '(${result.quality}) ${frame.length}-byte frame: ${_hex(frame)}',
    );

    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: Uint8List.fromList(frame),
      channelId: state.currentChannelId,
      regionId: state.currentRegionId,
      channelName: state.currentChannelName,
      incoming: true,
      encoding: instance.encoding,
      frameType: FragmentFrameType.ax25,
      time: DateTime.now(),
      radioMac: state.macAddress,
      radioDeviceId: state.deviceId,
    );
    fragment.corrections = 0;
    _dispatchDecodedFrame(state.deviceId, fragment);
  }

  // ---------------------------------------------------------------------------
  // HtStatus tracking
  // ---------------------------------------------------------------------------

  void _onHtStatusChanged(int deviceId, String name, Object? data) {
    if (_disposed || deviceId <= 0) return;

    final state = _radioModems[deviceId];
    if (state == null) return;

    if (data is Map) {
      state.currentChannelId =
          _readInt(data['currChId'] ?? data['curr_ch_id'] ?? data['CurrChId']) ?? state.currentChannelId;
      state.currentRegionId =
          _readInt(data['currRegion'] ?? data['curr_region'] ?? data['CurrRegion']) ?? state.currentRegionId;

      // Track whether the channel is currently clear
      final int rssi = _readInt(data['rssi'] ?? data['Rssi']) ?? 1;
      final bool isInTx =
          (data['isInTx'] ?? data['is_in_tx'] ?? data['IsInTx']) as bool? ??
              false;
      final bool isClear = rssi == 0 && !isInTx;
      final bool wasClear = state.channelIsClear;
      state.channelIsClear = isClear;

      // If the channel just became clear while we're waiting, resume the
      // p-persistent channel-access state machine.
      if (isClear &&
          !wasClear &&
          state.waitingForChannel &&
          state.transmitQueue.isNotEmpty) {
        _beginChannelAccess(state);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Packet transmission
  // ---------------------------------------------------------------------------

  void _onTransmitPacketRequested(int deviceId, String name, Object? data) {
    if (_disposed || deviceId <= 0) return;
    if (_currentMode == SoftwareModemMode.none &&
        _aprsMode == SoftwareModemMode.none) {
      return;
    }
    if (data is! TncDataFragment) return;

    transmitPacket(deviceId, data);
  }

  /// Transmits a TNC packet through the software modem.
  void transmitPacket(int deviceId, TncDataFragment fragment) {
    if (fragment.data.isEmpty) {
      _debug('TransmitPacket: Invalid fragment');
      return;
    }

    if (_currentMode == SoftwareModemMode.none &&
        _aprsMode == SoftwareModemMode.none) {
      return;
    }

    // Get or create modem state for this radio
    _RadioModemState? state = _radioModems[deviceId];
    if (state == null) {
      state = _createRadioModemState(deviceId);
      if (state == null) {
        _debug('TransmitPacket: Could not create modem state for device $deviceId');
        return;
      }
      _radioModems[deviceId] = state;
    }

    // Route to the APRS instance for APRS-channel frames, else the general one.
    final bool isAprs = fragment.channelName == 'APRS' ||
        (state.aprsChannelId >= 0 && fragment.channelId == state.aprsChannelId);
    final _ModemInstance? target =
        isAprs ? state.aprsModem : state.generalModem;
    if (target == null) {
      _debug(
        'TransmitPacket: no ${isAprs ? "APRS" : "general"} modem instance for '
        'device $deviceId - dropping frame',
      );
      return;
    }

    if (target.dartModem == null &&
        (target.packetAudioBuffer == null || target.packetGenTone == null)) {
      _debug('TransmitPacket: Transmitter not initialized');
      return;
    }

    // Queue the frame. The audio is generated at flush time so several queued
    // frames can be bundled into a single transmission (one preamble).
    state.transmitQueue.add(_PendingTransmission(
      Uint8List.fromList(fragment.data),
      fragment.frameType,
      DateTime.now().add(const Duration(seconds: 30)),
      target,
    ));
    _debug(
      'Queued ${fragment.frameType == FragmentFrameType.fx25 ? "FX.25" : "AX.25"} '
      'packet (${fragment.data.length} bytes) on device $deviceId '
      '(queue: ${state.transmitQueue.length})',
    );

    _beginChannelAccess(state);
  }

  void _onChannelClear(int deviceId, String name, Object? data) {
    if (_disposed || deviceId <= 0) return;

    final state = _radioModems[deviceId];
    if (state == null) return;
    if (!state.waitingForChannel || state.transmitQueue.isEmpty) return;

    state.channelIsClear = true;
    _beginChannelAccess(state);
  }

  // ---------------------------------------------------------------------------
  // Channel access - p-persistent CSMA (matches Direwolf's wait_for_clear_channel)
  //
  // After the channel is sensed clear (RSSI == 0 and we are not transmitting),
  // wait one "slot time" then transmit with probability persist/256; otherwise
  // wait another slot and try again. Re-checking the channel on every slot and
  // only transmitting probabilistically spreads out stations that were all
  // waiting for a busy channel to clear, which greatly reduces collisions.
  // ---------------------------------------------------------------------------

  static const int _csmaSlotTimeMs = 100; // Direwolf slottime default (10 * 10ms)
  static const int _csmaPersist = 63; // Direwolf persist default (~25%/slot)
  static const int _maxBundleFrames = 8; // frames bundled into a single keyup

  /// Kick off (or resume) the channel-access state machine for [state].
  void _beginChannelAccess(_RadioModemState state) {
    if (_disposed) return;

    _dropExpired(state);
    if (state.transmitQueue.isEmpty) {
      state.waitingForChannel = false;
      return;
    }

    // Sense the actual current channel state. HtStatus is only dispatched on
    // change, so the cached flag can be stale (e.g. still false) when the
    // channel has been steadily free - which previously left the packet queued
    // until the next busy->clear transition. Reading the latest status lets us
    // proceed right away when the channel is already free.
    _refreshChannelClear(state);

    state.waitingForChannel = true;
    if (state.channelWaitTimer != null) return; // persistence already running
    if (!state.channelIsClear) return; // busy: resume on ChannelClear/HtStatus
    _schedulePersistenceSlot(state);
  }

  void _schedulePersistenceSlot(_RadioModemState state) {
    state.channelWaitTimer?.cancel();
    state.channelWaitTimer = Timer(
      const Duration(milliseconds: _csmaSlotTimeMs),
      () => _onPersistenceSlot(state),
    );
  }

  void _onPersistenceSlot(_RadioModemState state) {
    state.channelWaitTimer = null;
    if (_disposed) return;

    _dropExpired(state);
    if (state.transmitQueue.isEmpty) {
      state.waitingForChannel = false;
      return;
    }

    // Re-sense the channel each slot from the latest HtStatus (Direwolf checks
    // the channel on every slot). Someone else may have started transmitting
    // during the slot - if so, go back to waiting for the channel to clear.
    _refreshChannelClear(state);
    if (!state.channelIsClear) {
      state.waitingForChannel = true;
      return;
    }

    // Transmit now with probability persist/256, otherwise try the next slot.
    if (_rng.nextInt(256) <= _csmaPersist) {
      _flushTransmitQueue(state);
    } else {
      _schedulePersistenceSlot(state);
    }
  }

  /// Sense the current channel state from the radio's latest HtStatus and
  /// update [state.channelIsClear]. HtStatus is only dispatched on change, so a
  /// steadily-free channel would otherwise leave the cached flag stale.
  void _refreshChannelClear(_RadioModemState state) {
    final Object? ht =
        _broker.getValue<Object>(state.deviceId, 'HtStatus', null);
    if (ht is Map) {
      final int rssi = _readInt(ht['rssi'] ?? ht['Rssi']) ?? 1;
      final bool isInTx =
          (ht['isInTx'] ?? ht['is_in_tx'] ?? ht['IsInTx']) as bool? ?? false;
      state.channelIsClear = rssi == 0 && !isInTx;
    }
  }

  void _dropExpired(_RadioModemState state) {
    final now = DateTime.now();
    while (state.transmitQueue.isNotEmpty &&
        now.isAfter(state.transmitQueue.first.deadline)) {
      state.transmitQueue.removeAt(0);
      _debug('Dropped expired packet on device ${state.deviceId}');
    }
  }

  void _flushTransmitQueue(_RadioModemState state) {
    if (_disposed) return;

    state.channelWaitTimer?.cancel();
    state.channelWaitTimer = null;

    _dropExpired(state);
    if (state.transmitQueue.isEmpty) {
      state.waitingForChannel = false;
      return;
    }

    // If the channel went busy again, wait for it to clear.
    if (!state.channelIsClear) {
      state.waitingForChannel = true;
      return;
    }

    // Bundle up to _maxBundleFrames queued frames into a single transmission so
    // the TXDELAY preamble cost is paid only once for several packets. Only
    // frames destined for the same modem instance (same modulation) are bundled
    // together; any queued frames for the other instance stay queued and are
    // sent in a following keyup.
    final _ModemInstance target = state.transmitQueue.first.target;
    final List<_PendingTransmission> bundle = [];
    while (state.transmitQueue.isNotEmpty &&
        bundle.length < _maxBundleFrames &&
        identical(state.transmitQueue.first.target, target)) {
      bundle.add(state.transmitQueue.removeAt(0));
    }

    final Uint8List? pcmData = _buildBundledPcm(target, bundle);
    final bool moreQueued = state.transmitQueue.isNotEmpty;

    // Assume the channel is now busy with our own transmission; the next
    // HtStatus / ChannelClear will resume any remaining frames.
    state.channelIsClear = false;
    state.waitingForChannel = moreQueued;

    if (pcmData == null || pcmData.isEmpty) {
      if (moreQueued) _beginChannelAccess(state);
      return;
    }

    _broker.dispatch(
      deviceId: state.deviceId,
      name: 'TransmitVoicePCM',
      data: {'Data': pcmData, 'PlayLocally': false, 'IsDataFrame': true},
      store: false,
    );
    _debug(
      'Transmitted ${bundle.length} bundled packet(s), '
      '${pcmData.length ~/ 2} samples on device ${state.deviceId}'
      '${moreQueued ? " (${state.transmitQueue.length} still queued)" : ""}',
    );
  }

  /// Builds a single PCM transmission containing all [frames] bundled together:
  /// one TXDELAY preamble, each frame back-to-back (HDLC flags delimit them),
  /// then one TXTAIL postamble, modulated by [instance] using its own FX.25 FEC
  /// setting. Returns little-endian 16-bit mono PCM bytes.
  Uint8List? _buildBundledPcm(
    _ModemInstance instance,
    List<_PendingTransmission> frames,
  ) {
    if (frames.isEmpty) return null;

    // DART is frame-based: encode each queued frame with its own preamble/FEC
    // and concatenate, bracketed by PTT lead-in/tail silence.
    if (instance.dartModem != null) {
      return _buildDartPcm(instance, frames);
    }

    if (instance.packetAudioBuffer == null ||
        instance.packetHdlcSend == null ||
        instance.packetFx25Send == null) {
      return null;
    }

    const int chan = 0;
    final buffer = instance.packetAudioBuffer!;
    buffer.clearAll();

    final int sampleRate = instance.audioConfig.devices[0].samplesPerSec;

    // Half a second of leading silence so the radio's PTT is fully keyed
    // up before any data tones start. This covers the delay between the PCM
    // stream starting and PTT actually engaging. It is emitted once per
    // transmission (before the first frame of the bundle), not between bundled
    // frames.
    _appendSilenceSamples(buffer, sampleRate ~/ 2);

    // Single preamble for the whole transmission.
    final int txdelayFlags = instance.audioConfig.channels[chan].txdelay;
    instance.packetHdlcSend!.sendFlags(chan, txdelayFlags, false, null);

    // All frames one after another. Use FX.25 forward error correction
    // (smallest level = 16 check bytes; pickMode selects the smallest RS block
    // that fits) for frames that meet the AX.25 minimum length, so the FX.25
    // frame stays standards-compliant: a strict FX.25 receiver such as Direwolf
    // rejects an unstuffed frame shorter than the AX.25 minimum. A frame that
    // is too small - or too large for any FX.25 block - is sent as plain AX.25
    // instead. Each frame emits its own HDLC flags so consecutive frames stay
    // properly delimited.
    // AX.25 minimum data: two 7-byte addresses + control (FCS added separately).
    const int ax25MinDataLen = 14 + 1;
    for (final tx in frames) {
      const int fx25SmallestFec = 16; // 16 check bytes = smallest FX.25 FEC
      int sent = -1;
      if (instance.fecEnabled && tx.frameData.length >= ax25MinDataLen) {
        _debug(
          'TX FX.25: raw ${tx.frameData.length}-byte frame before FEC: '
          '${_hex(tx.frameData)}',
        );
        sent = instance.packetFx25Send!.sendFrame(
          chan,
          tx.frameData,
          tx.frameData.length,
          fx25SmallestFec,
        );
        if (sent < 0) {
          _debug(
            'TX FX.25: sendFrame rejected the frame (too small/large for any '
            'FX.25 block) - falling back to plain AX.25.',
          );
        } else {
          _debug('TX FX.25: encoded frame into $sent bits.');
        }
      }
      if (sent < 0) {
        // Frame too small or too large for a standards-compliant FX.25 frame -
        // fall back to plain AX.25.
        _debug(
          'TX AX.25 (no FEC): sending ${tx.frameData.length}-byte frame: '
          '${_hex(tx.frameData)}',
        );
        instance.packetHdlcSend!
            .sendFrame(chan, tx.frameData, tx.frameData.length, false);
      }
    }

    // Single postamble.
    final int txtailFlags = instance.audioConfig.channels[chan].txtail;
    instance.packetHdlcSend!.sendFlags(chan, txtailFlags, true, (device) {});

    // 1/10th of a second of trailing silence so the final data tones are fully
    // sent before PTT is released.
    _appendSilenceSamples(buffer, sampleRate ~/ 10);

    final samples = buffer.getAndClear(0);
    if (samples.isEmpty) return null;

    final Uint8List pcmData = Uint8List(samples.length * 2);
    final ByteData bd = ByteData.view(pcmData.buffer);
    for (int i = 0; i < samples.length; i++) {
      bd.setInt16(i * 2, samples[i], Endian.little);
    }
    return pcmData;
  }

  /// Appends [numSamples] of silence (value 0) to device 0 of [buffer].
  void _appendSilenceSamples(AudioBuffer buffer, int numSamples) {
    for (int i = 0; i < numSamples; i++) {
      buffer.put(0, 0);
    }
  }

  /// Build a DART transmission: each queued frame encoded as a full DART frame
  /// (its own preamble/header/payload/FEC), concatenated with PTT lead-in and
  /// tail silence. Returns little-endian 16-bit mono PCM bytes.
  Uint8List? _buildDartPcm(
    _ModemInstance instance,
    List<_PendingTransmission> frames,
  ) {
    final modem = instance.dartModem;
    if (modem == null) return null;

    const int sampleRate = 32000;
    final List<int> samples = [];

    // Half a second of leading silence so PTT is fully keyed before data tones.
    samples.addAll(List<int>.filled(sampleRate ~/ 2, 0));

    for (final tx in frames) {
      final Int16List framePcm = modem.encode(
        payload: tx.frameData,
        mode: instance.dartTxMode,
        seqNum: instance.dartTxSeq & 0xFF,
      );
      instance.dartTxSeq++;
      samples.addAll(framePcm);
      _debug(
        'TX DART: ${instance.dartTxMode.name} '
        '${tx.frameData.length}-byte frame → ${framePcm.length} samples',
      );
    }

    // Tenth of a second of trailing silence before PTT release.
    samples.addAll(List<int>.filled(sampleRate ~/ 10, 0));

    final Uint8List pcmData = Uint8List(samples.length * 2);
    final ByteData bd = ByteData.view(pcmData.buffer);
    for (int i = 0; i < samples.length; i++) {
      bd.setInt16(i * 2, samples[i].clamp(-32768, 32767), Endian.little);
    }
    return pcmData;
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  void _dispatchDecodedFrame(int deviceId, TncDataFragment fragment) {
    _broker.dispatch(deviceId: deviceId, name: 'DataFrame', data: fragment, store: false);
  }

  void _debug(String msg) {
    _broker.dispatch(deviceId: 1, name: 'LogInfo', data: '[SoftwareModem]: $msg', store: false);
  }

  /// Compact single-line uppercase hex string for logging raw frame bytes.
  static String _hex(Uint8List b) {
    final StringBuffer sb = StringBuffer();
    for (final int v in b) {
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString().toUpperCase();
  }

  static int? _readInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// Wrapper for MultiModem to process FX.25 frames.
class _Fx25MultiModemWrapper extends MultiModem {
  final _RadioModemState _state;
  final _ModemInstance _instance;
  final SoftwareModem _parent;

  _Fx25MultiModemWrapper(this._state, this._instance, this._parent) {
    addPacketReady(_onPacketReady);
  }

  void _onPacketReady(PacketReadyEventArgs e) {
    if (e.packet == null) return;

    final Uint8List frameData = Uint8List(e.packet!.frameLen);
    frameData.setRange(0, e.packet!.frameLen, e.packet!.frameData);

    if (frameData.isEmpty) return;

    // FX.25 delivered the frame - cancel the buffered plain-HDLC fallback copy
    // so the same frame is not reported twice.
    _instance.pendingFrameTimer?.cancel();
    _instance.pendingFrameTimer = null;
    _instance.pendingFrameData = null;

    _parent._debug(
      'RX FX.25: delivered ${frameData.length}-byte frame '
      '(${e.correctionInfo?.rsSymbolsCorrected ?? 0} byte(s) corrected): '
      '${SoftwareModem._hex(frameData)}',
    );

    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: frameData,
      channelId: _state.currentChannelId,
      regionId: _state.currentRegionId,
      channelName: _state.currentChannelName,
      incoming: true,
      encoding: _instance.encoding,
      frameType: FragmentFrameType.fx25,
      time: DateTime.now(),
      radioMac: _state.macAddress,
      radioDeviceId: _state.deviceId,
    );

    if (e.correctionInfo != null && e.correctionInfo!.rsSymbolsCorrected >= 0) {
      fragment.corrections = e.correctionInfo!.rsSymbolsCorrected;
    } else {
      fragment.corrections = 0;
    }

    _parent._dispatchDecodedFrame(_state.deviceId, fragment);
  }
}
