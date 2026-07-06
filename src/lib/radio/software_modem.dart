/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Dart port of the C# SoftwareModem. This Data Broker handler processes PCM audio
from radios and decodes/encodes TNC frames using AFSK 1200, PSK 2400/4800 and
G3RUH 9600 modulation via the hamlib software modem library.
*/

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../hamlib/audio_buffer.dart';
import '../hamlib/audio_config.dart';
import '../hamlib/demod_9600.dart';
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
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'tnc_data_fragment.dart';

/// Software modem mode types.
enum SoftwareModemMode {
  none,
  afsk1200,
  psk2400,
  psk4800,
  g3ruh9600,
}

/// Holds a frame waiting to be transmitted once the channel is clear. The
/// audio is generated at flush time so multiple queued frames can be bundled
/// into a single transmission (one preamble/postamble for all of them).
class _PendingTransmission {
  final Uint8List frameData;
  final FragmentFrameType frameType;
  final DateTime deadline;
  _PendingTransmission(this.frameData, this.frameType, this.deadline);
}

/// Per-radio modem state for handling audio processing.
class _RadioModemState {
  int deviceId;
  String macAddress;
  String currentChannelName = '';
  int currentChannelId = 0;
  int currentRegionId = 0;
  SoftwareModemMode mode;
  bool initialized = false;

  // AFSK 1200 modem state
  DemodAfsk? afskDemodulator;
  DemodulatorState? afskDemodState;

  // PSK modem state (for 2400 and 4800)
  DemodPsk? pskDemodulator;
  PskDemodulatorState? pskDemodState;

  // G3RUH 9600 modem state
  Demod9600State? state9600;
  DemodulatorState? demod9600State;

  // Common modem components
  AudioConfig? audioConfig;
  HdlcRec2? hdlcReceiver;
  Fx25Rec? fx25Receiver;
  _HdlcFx25Bridge? bridge;

  // Packet transmission components
  GenTone? packetGenTone;
  AudioBuffer? packetAudioBuffer;
  HdlcSend? packetHdlcSend;
  Fx25Send? packetFx25Send;

  // Clear-channel transmit queue
  final List<_PendingTransmission> transmitQueue = [];
  bool waitingForChannel = false;
  bool channelIsClear = false;
  Timer? channelWaitTimer;

  _RadioModemState({
    required this.deviceId,
    required this.macAddress,
    required this.mode,
  });

  void dispose() {
    channelWaitTimer?.cancel();
    channelWaitTimer = null;
    transmitQueue.clear();
    waitingForChannel = false;

    afskDemodulator = null;
    afskDemodState = null;
    pskDemodulator = null;
    pskDemodState = null;
    state9600 = null;
    demod9600State = null;
    audioConfig = null;
    hdlcReceiver = null;
    fx25Receiver = null;
    bridge = null;
    packetGenTone = null;
    packetAudioBuffer = null;
    packetHdlcSend = null;
    packetFx25Send = null;

    initialized = false;
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
  bool _disposed = false;
  bool _initialized = false;
  static final math.Random _rng = math.Random();

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

    // Subscribe to mode changes on device 0
    _broker.subscribe(
      deviceId: 0,
      name: 'SetSoftwareModemMode',
      callback: _onSetModeRequested,
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
      case 'PSK4800':
        return SoftwareModemMode.psk4800;
      case 'G3RUH9600':
        return SoftwareModemMode.g3ruh9600;
      default:
        return SoftwareModemMode.none;
    }
  }

  static FragmentEncodingType _getEncodingType(SoftwareModemMode mode) {
    switch (mode) {
      case SoftwareModemMode.afsk1200:
        return FragmentEncodingType.softwareAfsk1200;
      case SoftwareModemMode.psk2400:
        return FragmentEncodingType.softwarePsk2400;
      case SoftwareModemMode.psk4800:
        return FragmentEncodingType.softwarePsk4800;
      case SoftwareModemMode.g3ruh9600:
        return FragmentEncodingType.softwareG3ruh9600;
      default:
        return FragmentEncodingType.unknown;
    }
  }

  /// Sets the software modem mode.
  void setMode(SoftwareModemMode mode) {
    if (_currentMode == mode) return;

    _debug('Changing software modem mode from ${_currentMode.name} to ${mode.name}');

    // Cleanup all existing per-radio modem states
    for (final state in _radioModems.values) {
      state.dispose();
    }
    _radioModems.clear();

    _currentMode = mode;

    // Save to device 0 (settings)
    _broker.dispatch(deviceId: 0, name: 'SoftwareModemMode', data: mode.name, store: true);

    _debug('Software modem mode changed to ${mode.name}');
  }

  void _onSetModeRequested(int deviceId, String name, Object? data) {
    if (_disposed) return;

    final String modeStr = (data is String) ? data : (data?.toString() ?? '');
    final SoftwareModemMode newMode = _parseMode(modeStr);
    setMode(newMode);
  }

  // ---------------------------------------------------------------------------
  // Audio data processing
  // ---------------------------------------------------------------------------

  void _onAudioDataAvailable(int deviceId, String name, Object? data) {
    if (_disposed || deviceId <= 0) return;
    if (_currentMode == SoftwareModemMode.none) return;
    if (data is! Map) return;

    // Don't process transmitted audio
    final transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
    if (transmit) return;

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
    if (_currentMode == SoftwareModemMode.none) return;

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

    // Feed samples to the demodulator
    const int chan = 0;
    const int subchan = 0;

    switch (_currentMode) {
      case SoftwareModemMode.afsk1200:
        if (state.afskDemodulator == null || state.afskDemodState == null) {
          return;
        }
        for (int i = offset; i < offset + length - 1; i += 2) {
          final int sample = (data[i] | (data[i + 1] << 8)).toSigned(16);
          state.afskDemodulator!.processSample(
            chan,
            subchan,
            sample,
            state.afskDemodState!,
          );
        }
        break;

      case SoftwareModemMode.psk2400:
      case SoftwareModemMode.psk4800:
        if (state.pskDemodulator == null || state.pskDemodState == null) return;
        for (int i = offset; i < offset + length - 1; i += 2) {
          final int sample = (data[i] | (data[i + 1] << 8)).toSigned(16);
          state.pskDemodulator!.processSample(
            chan,
            subchan,
            sample,
            state.pskDemodState!,
          );
        }
        break;

      case SoftwareModemMode.g3ruh9600:
        if (state.state9600 == null ||
            state.bridge == null ||
            state.demod9600State == null) {
          return;
        }
        for (int i = offset; i < offset + length - 1; i += 2) {
          final int sample = (data[i] | (data[i + 1] << 8)).toSigned(16);
          Demod9600.processSample(
            chan,
            sample,
            1,
            state.demod9600State!,
            state.state9600!,
            state.bridge!,
          );
        }
        break;

      case SoftwareModemMode.none:
        break;
    }
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
      mode: _currentMode,
    );

    // Get current HtStatus for channel info
    final Object? htStatus =
        _broker.getValue<Object>(deviceId, 'HtStatus', null);
    if (htStatus is Map) {
      state.currentChannelId =
          _readInt(htStatus['curr_ch_id'] ?? htStatus['CurrChId']) ?? 0;
      state.currentRegionId =
          _readInt(htStatus['curr_region'] ?? htStatus['CurrRegion']) ?? 0;
    }

    // Initialize FX.25 subsystem
    Fx25.init(0);

    // Initialize modem based on current mode
    _initializeModemState(state, _currentMode);

    return state;
  }

  void _initializeModemState(_RadioModemState state, SoftwareModemMode mode) {
    // Setup audio configuration for 32kHz, 16-bit, mono
    state.audioConfig = AudioConfig();
    state.audioConfig!.devices[0].defined = true;
    state.audioConfig!.devices[0].samplesPerSec = 32000;
    state.audioConfig!.devices[0].bitsPerSample = 16;
    state.audioConfig!.devices[0].numChannels = 1;
    state.audioConfig!.channelMedium[0] = Medium.radio;
    state.audioConfig!.channels[0].numSubchan = 1;

    switch (mode) {
      case SoftwareModemMode.afsk1200:
        _initializeAfsk1200(state);
        break;
      case SoftwareModemMode.psk2400:
        _initializePsk2400(state);
        break;
      case SoftwareModemMode.psk4800:
        _initializePsk4800(state);
        break;
      case SoftwareModemMode.g3ruh9600:
        _initializeG3ruh9600(state);
        break;
      case SoftwareModemMode.none:
        break;
    }

    state.initialized = true;
    _debug('Initialized ${mode.name} modem for device ${state.deviceId}');
  }

  void _initializeAfsk1200(_RadioModemState state) {
    state.audioConfig!.channels[0].modemType = ModemType.afsk;
    state.audioConfig!.channels[0].markFreq = 1200;
    state.audioConfig!.channels[0].spaceFreq = 2200;
    state.audioConfig!.channels[0].baud = 1200;
    state.audioConfig!.channels[0].txdelay = 30;
    state.audioConfig!.channels[0].txtail = 10;

    // Create HDLC receiver
    state.hdlcReceiver = HdlcRec2();
    state.hdlcReceiver!.addFrameReceived(_onFrameReceived);
    state.hdlcReceiver!.init(state.audioConfig!);

    // Create FX.25 receiver with MultiModem wrapper
    final fx25MultiModem = _Fx25MultiModemWrapper(state, this);
    state.fx25Receiver = Fx25Rec(fx25MultiModem);

    // Create bridge
    state.bridge = _HdlcFx25Bridge(state.hdlcReceiver!, state.fx25Receiver!);

    // Create AFSK demodulator
    state.afskDemodulator = DemodAfsk(state.bridge!);
    state.afskDemodState = DemodulatorState();
    state.afskDemodulator!.init(
      32000,
      1200,
      1200,
      2200,
      'A',
      state.afskDemodState!,
    );

    // Initialize transmitter
    _initializeTransmitter(state);
  }

  void _initializePsk2400(_RadioModemState state) {
    state.audioConfig!.channels[0].modemType = ModemType.qpsk;
    // Direwolf treats achan.baud as bits-per-second for PSK; GenTone derives
    // the 1200 symbol/s rate internally (baud * 0.5). Must match the 2400 bps
    // passed to the demodulator below.
    state.audioConfig!.channels[0].baud = 2400;
    state.audioConfig!.channels[0].v26Alt = V26Alternative.b;
    state.audioConfig!.channels[0].txdelay = 30;
    state.audioConfig!.channels[0].txtail = 10;

    // Create HDLC receiver
    state.hdlcReceiver = HdlcRec2();
    state.hdlcReceiver!.addFrameReceived(_onFrameReceived);
    state.hdlcReceiver!.init(state.audioConfig!);

    // Create FX.25 receiver
    final fx25MultiModem = _Fx25MultiModemWrapper(state, this);
    state.fx25Receiver = Fx25Rec(fx25MultiModem);

    // Create bridge
    state.bridge = _HdlcFx25Bridge(state.hdlcReceiver!, state.fx25Receiver!);

    // Create PSK demodulator
    state.pskDemodulator = DemodPsk(state.bridge!);
    state.pskDemodState = PskDemodulatorState();
    state.pskDemodulator!.init(
      ModemType.qpsk,
      V26Alternative.b,
      32000,
      2400,
      'B',
      state.pskDemodState!,
    );

    // Initialize transmitter
    _initializeTransmitter(state);
  }

  void _initializePsk4800(_RadioModemState state) {
    state.audioConfig!.channels[0].modemType = ModemType.psk8;
    // Bits-per-second for PSK; GenTone derives the 1600 symbol/s rate
    // internally (baud / 3). Must match the 4800 bps passed to the demodulator.
    state.audioConfig!.channels[0].baud = 4800;
    state.audioConfig!.channels[0].v26Alt = V26Alternative.b;
    state.audioConfig!.channels[0].txdelay = 30;
    state.audioConfig!.channels[0].txtail = 10;

    // Create HDLC receiver
    state.hdlcReceiver = HdlcRec2();
    state.hdlcReceiver!.addFrameReceived(_onFrameReceived);
    state.hdlcReceiver!.init(state.audioConfig!);

    // Create FX.25 receiver
    final fx25MultiModem = _Fx25MultiModemWrapper(state, this);
    state.fx25Receiver = Fx25Rec(fx25MultiModem);

    // Create bridge
    state.bridge = _HdlcFx25Bridge(state.hdlcReceiver!, state.fx25Receiver!);

    // Create PSK demodulator
    state.pskDemodulator = DemodPsk(state.bridge!);
    state.pskDemodState = PskDemodulatorState();
    state.pskDemodulator!.init(
      ModemType.psk8,
      V26Alternative.b,
      32000,
      4800,
      'B',
      state.pskDemodState!,
    );

    // Initialize transmitter
    _initializeTransmitter(state);
  }

  void _initializeG3ruh9600(_RadioModemState state) {
    // G3RUH requires the transmit side to scramble the bit stream; the
    // demodulator always descrambles. ModemType.baseband would send
    // un-scrambled data that the receiver cannot decode.
    state.audioConfig!.channels[0].modemType = ModemType.scramble;
    state.audioConfig!.channels[0].baud = 9600;
    state.audioConfig!.channels[0].txdelay = 30;
    state.audioConfig!.channels[0].txtail = 10;

    // Create HDLC receiver
    state.hdlcReceiver = HdlcRec2();
    state.hdlcReceiver!.addFrameReceived(_onFrameReceived);
    state.hdlcReceiver!.init(state.audioConfig!);

    // Create FX.25 receiver
    final fx25MultiModem = _Fx25MultiModemWrapper(state, this);
    state.fx25Receiver = Fx25Rec(fx25MultiModem);

    // Create bridge
    state.bridge = _HdlcFx25Bridge(state.hdlcReceiver!, state.fx25Receiver!);

    // Create 9600 baud demodulator
    state.demod9600State = DemodulatorState();
    state.state9600 = Demod9600State();
    Demod9600.init(32000, 1, 9600, state.demod9600State!, state.state9600!);

    // Initialize transmitter
    _initializeTransmitter(state);
  }

  void _initializeTransmitter(_RadioModemState state) {
    // Create audio buffer
    state.packetAudioBuffer = AudioBuffer(AudioConfig.maxAudioDevices);

    // Create tone generator
    state.packetGenTone = GenTone(state.packetAudioBuffer!);
    state.packetGenTone!.init(state.audioConfig!, 50);

    // Create HDLC sender
    state.packetHdlcSend = HdlcSend(state.packetGenTone!, state.audioConfig!);

    // Create FX.25 sender
    state.packetFx25Send = Fx25Send();
    state.packetFx25Send!.init(state.packetGenTone!);
  }

  // ---------------------------------------------------------------------------
  // Frame reception
  // ---------------------------------------------------------------------------

  void _onFrameReceived(FrameReceivedEventArgs e) {
    // Find which radio state this frame belongs to
    _RadioModemState? state;
    for (final kvp in _radioModems.entries) {
      if (kvp.value.hdlcReceiver != null) {
        // Match by checking if this is the correct receiver
        state = kvp.value;
        break;
      }
    }

    if (state == null) return;

    final Uint8List frameData = Uint8List(e.frameLength);
    frameData.setRange(0, e.frameLength, e.frame);

    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: frameData,
      channelId: state.currentChannelId,
      regionId: state.currentRegionId,
      channelName: state.currentChannelName,
      incoming: true,
      encoding: _getEncodingType(state.mode),
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

  // ---------------------------------------------------------------------------
  // HtStatus tracking
  // ---------------------------------------------------------------------------

  void _onHtStatusChanged(int deviceId, String name, Object? data) {
    if (_disposed || deviceId <= 0) return;

    final state = _radioModems[deviceId];
    if (state == null) return;

    if (data is Map) {
      state.currentChannelId =
          _readInt(data['curr_ch_id'] ?? data['CurrChId']) ?? state.currentChannelId;
      state.currentRegionId =
          _readInt(data['curr_region'] ?? data['CurrRegion']) ?? state.currentRegionId;

      // Track whether the channel is currently clear
      final int rssi = _readInt(data['rssi'] ?? data['Rssi']) ?? 1;
      final bool isInTx =
          (data['is_in_tx'] ?? data['IsInTx']) as bool? ?? false;
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
    if (_currentMode == SoftwareModemMode.none) return;
    if (data is! TncDataFragment) return;

    transmitPacket(deviceId, data);
  }

  /// Transmits a TNC packet through the software modem.
  void transmitPacket(int deviceId, TncDataFragment fragment) {
    if (fragment.data.isEmpty) {
      _debug('TransmitPacket: Invalid fragment');
      return;
    }

    if (_currentMode == SoftwareModemMode.none) return;

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

    if (state.packetAudioBuffer == null || state.packetGenTone == null) {
      _debug('TransmitPacket: Transmitter not initialized');
      return;
    }

    // Queue the frame. The audio is generated at flush time so several queued
    // frames can be bundled into a single transmission (one preamble).
    state.transmitQueue.add(_PendingTransmission(
      Uint8List.fromList(fragment.data),
      fragment.frameType,
      DateTime.now().add(const Duration(seconds: 30)),
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

    // Someone else may have started transmitting during the slot - if so, go
    // back to waiting for the channel to clear again.
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
    // the TXDELAY preamble cost is paid only once for several packets.
    final List<_PendingTransmission> bundle = [];
    while (state.transmitQueue.isNotEmpty && bundle.length < _maxBundleFrames) {
      bundle.add(state.transmitQueue.removeAt(0));
    }

    final Uint8List? pcmData = _buildBundledPcm(state, bundle);
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
      data: {'Data': pcmData, 'PlayLocally': false},
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
  /// then one TXTAIL postamble. Returns little-endian 16-bit mono PCM bytes.
  Uint8List? _buildBundledPcm(
    _RadioModemState state,
    List<_PendingTransmission> frames,
  ) {
    if (frames.isEmpty) return null;
    if (state.packetAudioBuffer == null ||
        state.packetHdlcSend == null ||
        state.audioConfig == null) {
      return null;
    }

    const int chan = 0;
    final buffer = state.packetAudioBuffer!;
    buffer.clearAll();

    final bool is9600 = _currentMode == SoftwareModemMode.g3ruh9600;
    const int silenceSamples = 32000 ~/ 2; // 0.5 s at 32 kHz

    // Pre-silence for G3RUH 9600.
    if (is9600) {
      for (int i = 0; i < silenceSamples; i++) {
        buffer.put(0, 0);
      }
    }

    // Single preamble for the whole transmission.
    final int txdelayFlags = state.audioConfig!.channels[chan].txdelay;
    state.packetHdlcSend!.sendFlags(chan, txdelayFlags, false, null);

    // All frames one after another. Each frame emits its own HDLC flags so
    // consecutive frames stay properly delimited.
    for (final tx in frames) {
      if (tx.frameType == FragmentFrameType.fx25) {
        const int fxMode = 32;
        state.packetFx25Send!
            .sendFrame(chan, tx.frameData, tx.frameData.length, fxMode);
      } else {
        state.packetHdlcSend!
            .sendFrame(chan, tx.frameData, tx.frameData.length, false);
      }
    }

    // Single postamble.
    final int txtailFlags = state.audioConfig!.channels[chan].txtail;
    state.packetHdlcSend!.sendFlags(chan, txtailFlags, true, (device) {});

    // Post-silence for G3RUH 9600.
    if (is9600) {
      for (int i = 0; i < silenceSamples; i++) {
        buffer.put(0, 0);
      }
    }

    final samples = buffer.getAndClear(0);
    if (samples.isEmpty) return null;

    final Uint8List pcmData = Uint8List(samples.length * 2);
    final ByteData bd = ByteData.view(pcmData.buffer);
    for (int i = 0; i < samples.length; i++) {
      bd.setInt16(i * 2, samples[i], Endian.little);
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
  final SoftwareModem _parent;

  _Fx25MultiModemWrapper(this._state, this._parent) {
    addPacketReady(_onPacketReady);
  }

  void _onPacketReady(PacketReadyEventArgs e) {
    if (e.packet == null) return;

    final Uint8List frameData = Uint8List(e.packet!.frameLen);
    frameData.setRange(0, e.packet!.frameLen, e.packet!.frameData);

    if (frameData.isEmpty) return;

    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: frameData,
      channelId: _state.currentChannelId,
      regionId: _state.currentRegionId,
      channelName: _state.currentChannelName,
      incoming: true,
      encoding: SoftwareModem._getEncodingType(_state.mode),
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
