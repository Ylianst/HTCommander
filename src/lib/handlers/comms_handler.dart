/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Dart port of the C# VoiceHandler. This Data Broker handler listens to audio
data from radios and maintains a history of decoded/transmitted voice text.

Scope of this port (core handler + broker contract):
  - Enable / Disable lifecycle, target-radio tracking and state dispatch.
  - Decoded text history (in-memory + JSON persistence on disk).
  - Recording-enabled flag and RecordingState dispatch.
  - Clear-history command and the related broadcast events.
  - Auto-disable when the target radio disconnects or its audio is turned off.

The following heavy features from the original C# are intentionally STUBBED
here as clean extension points and produce no functional behaviour yet:
  - Speech-to-text (Whisper) decoding of incoming audio frames.
  - Text-to-speech synthesis (Speak command).

Morse-code transmit is implemented: the Morse command generates tone PCM via
MorseCodeEngine and transmits it through the radio audio path.

SSTV image reception is implemented: while the handler is enabled, incoming
audio is fed to an SstvMonitor that auto-detects and decodes SSTV images. The
decoded picture is saved as a PNG under the application-support "SSTV" folder
and added to the decoded-text history as a Picture entry.

Received data-packet decoding (UniqueDataFrame) is implemented: AX.25 / BSS /
APRS / Ident packets that arrive on a non-APRS channel are decoded and added to
the decoded-text history.

WAV file recording of audio runs is fully implemented: when recording is
enabled, each audio run is captured to a 32 kHz 16-bit mono WAV file under the
application-support "recordings" folder and added to the decoded-text history.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../aprs/aprs_packet.dart';
import '../echolink/echolink_client.dart' show echoLinkDeviceId;
import '../radio/ax25_packet.dart';
import '../radio/bss_packet.dart';
import '../radio/morse_code_engine.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/tts_service.dart';
import '../sstv/sstv_monitor.dart';
import 'speech_to_text_engine.dart';

/// Encoding type for voice text entries. Mirrors the C# `VoiceTextEncodingType`.
enum VoiceTextEncodingType {
  voice,
  morse,
  voiceClip,
  ax25,
  bss,
  recording,
  picture,
  aprs,
  ident,
  echolink,
}

/// Serializes a [VoiceTextEncodingType] to its C#-compatible name (PascalCase).
String _encodingToString(VoiceTextEncodingType e) {
  switch (e) {
    case VoiceTextEncodingType.voice:
      return 'Voice';
    case VoiceTextEncodingType.morse:
      return 'Morse';
    case VoiceTextEncodingType.voiceClip:
      return 'VoiceClip';
    case VoiceTextEncodingType.ax25:
      return 'AX25';
    case VoiceTextEncodingType.bss:
      return 'BSS';
    case VoiceTextEncodingType.recording:
      return 'Recording';
    case VoiceTextEncodingType.picture:
      return 'Picture';
    case VoiceTextEncodingType.aprs:
      return 'APRS';
    case VoiceTextEncodingType.ident:
      return 'Ident';
    case VoiceTextEncodingType.echolink:
      return 'EchoLink';
  }
}

/// Parses a [VoiceTextEncodingType] from its string name (case-insensitive).
VoiceTextEncodingType _encodingFromString(Object? value) {
  final s = (value is String ? value : 'Voice').toLowerCase();
  switch (s) {
    case 'morse':
      return VoiceTextEncodingType.morse;
    case 'voiceclip':
      return VoiceTextEncodingType.voiceClip;
    case 'ax25':
      return VoiceTextEncodingType.ax25;
    case 'bss':
      return VoiceTextEncodingType.bss;
    case 'recording':
      return VoiceTextEncodingType.recording;
    case 'picture':
      return VoiceTextEncodingType.picture;
    case 'aprs':
      return VoiceTextEncodingType.aprs;
    case 'ident':
      return VoiceTextEncodingType.ident;
    case 'echolink':
      return VoiceTextEncodingType.echolink;
    case 'voice':
    default:
      return VoiceTextEncodingType.voice;
  }
}

/// Represents a voice text entry (received or transmitted).
class DecodedTextEntry {
  String? text;
  String? channel;
  DateTime time;

  /// True if received (decoded), false if sent (transmitted).
  bool isReceived;
  VoiceTextEncodingType encoding;

  /// Source callsign (for BSS packets).
  String? source;

  /// Destination callsign (for BSS packets, may be null for broadcast).
  String? destination;
  double latitude;
  double longitude;

  /// Filename for picture (SSTV) and recording entries.
  String? filename;

  /// Duration in seconds (for recording entries).
  int duration;

  DecodedTextEntry({
    this.text,
    this.channel,
    DateTime? time,
    this.isReceived = true,
    this.encoding = VoiceTextEncodingType.voice,
    this.source,
    this.destination,
    this.latitude = 0,
    this.longitude = 0,
    this.filename,
    this.duration = 0,
  }) : time = time ?? DateTime.now();

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'channel': channel,
    'time': time.millisecondsSinceEpoch,
    'isReceived': isReceived,
    'encoding': _encodingToString(encoding),
    'source': source,
    'destination': destination,
    'latitude': latitude,
    'longitude': longitude,
    'filename': filename,
    'duration': duration,
  };

  factory DecodedTextEntry.fromJson(Map<String, dynamic> json) {
    final rawTime = json['time'];
    DateTime time;
    if (rawTime is int) {
      time = DateTime.fromMillisecondsSinceEpoch(rawTime);
    } else if (rawTime is String) {
      time = DateTime.tryParse(rawTime) ?? DateTime.now();
    } else {
      time = DateTime.now();
    }
    double toDouble(Object? v) => v is num ? v.toDouble() : 0.0;
    return DecodedTextEntry(
      text: json['text'] as String?,
      channel: json['channel'] as String?,
      time: time,
      isReceived: json['isReceived'] as bool? ?? true,
      encoding: _encodingFromString(json['encoding']),
      source: json['source'] as String?,
      destination: json['destination'] as String?,
      latitude: toDouble(json['latitude']),
      longitude: toDouble(json['longitude']),
      filename: json['filename'] as String?,
      duration: json['duration'] as int? ?? 0,
    );
  }
}

/// Comms Handler - listens to audio data from radios and maintains a history of
/// decoded/transmitted voice text. Registered as a Data Broker handler.
class CommsHandler {
  static const String _voiceTextFileName = 'voicetext.json';
  static const int _maxHistorySize = 1000;

  final DataBrokerClient _broker = DataBrokerClient();
  bool _disposed = false;
  bool _initialized = false;

  // Handler state.
  bool _enabled = false;
  int _targetDeviceId = -1; // -1 means disabled.
  String _voiceLanguage = 'auto';
  String? _voiceModel;

  // Recording state.
  bool _recordingEnabled = false;
  static const String _recordingsFolderName = 'recordings';
  static const int _recordingSampleRate = 32000;
  Directory? _recordingsDir;

  // Active recording context (set while an audio run is being captured).
  _WavClipRecorder? _recorder;
  int _recordingDeviceId = -1;
  DateTime _recordingStartTime = DateTime.now();
  String _recordingChannel = '';
  String _recordingFilename = '';
  bool _recordingIsTransmit = false;

  // Outgoing (transmit) audio recording. Outgoing voice is captured directly
  // from the TransmitVoicePCM stream (PTT / spoken text / Morse / DTMF) so it
  // works uniformly for radios and EchoLink, independent of any radio transmit
  // "echo". A one-shot blob (spoken text / Morse / DTMF) has no explicit end, so
  // the run is finalized after a short period of silence.
  Timer? _txRecordTimer;
  static const int _txRecordEndMs = 800;

  // Current audio-run context (updated from AudioDataStart events).
  String _currentChannelName = '';
  // ignore: unused_field
  bool _currentAudioIsTransmit = false;

  // Speech-to-text state. STT is always-on (gated by the persisted
  // `SpeechToTextEnabled` setting), independent of the voice-handler enable
  // state, mirroring the recording and SSTV features. It tracks whichever radio
  // device is currently streaming received audio.
  static const int _sttSampleRate = 32000;
  // Force a split/final if a single segment accumulates more than ~27s of new
  // audio (32000 Hz * 2 bytes/sample * 27 s). After a split the worker retains
  // a 2-second overlap tail, so the total decode buffer is at most 29s — safely
  // under the Whisper 30-second hard limit.
  static const int _sttMaxSegmentBytes = 32000 * 2 * 27;
  SpeechToTextEngine? _sttEngine;
  StreamSubscription<SpeechResult>? _sttResultSub;
  StreamSubscription<bool>? _sttProcessingSub;
  bool _speechToTextEnabled = true;
  bool _sttReady = false;
  int _sttDeviceId = -1;
  bool _sttSegmentActive = false;
  int _sttSegmentBytes = 0;
  String _sttChannel = '';
  DecodedTextEntry? _sttCurrentEntry;

  // SSTV auto-decode state.
  static const String _sstvFolderName = 'SSTV';
  static const int _sstvSampleRate = 32000;
  SstvMonitor? _sstvMonitor;
  StreamSubscription<SstvDecodingStarted>? _sstvStartedSub;
  StreamSubscription<SstvDecodingProgress>? _sstvProgressSub;
  StreamSubscription<SstvDecodingComplete>? _sstvCompleteSub;
  bool _sstvDecodingActive = false;

  /// Whether an SSTV image is currently being received/decoded. Setting this
  /// publishes an `SstvReceiving` flag on the SSTV device so the software modem
  /// can ignore the audio (the SSTV tones are not packet data).
  bool get _sstvDecoding => _sstvDecodingActive;
  set _sstvDecoding(bool value) {
    if (_sstvDecodingActive == value) return;
    _sstvDecodingActive = value;
    _broker.dispatch(
      deviceId: _sstvDeviceId,
      name: 'SstvReceiving',
      data: value,
      store: true,
    );
  }

  bool _sstvAutoMuted = false;
  // Whether the channel currently feeding the SSTV monitor is flagged as muted
  // (per-channel mute). While muted the radio audio is already silenced, so the
  // SSTV auto-mute must not engage.
  bool _sstvChannelMuted = false;
  DateTime _sstvStartTime = DateTime.now();
  DecodedTextEntry? _currentSstvEntry;
  Directory? _sstvImagesDir;
  // The radio device whose received audio is currently being scanned/decoded.
  int _sstvDeviceId = -1;

  // Filename used for the in-progress SSTV picture; partial frames and the
  // final image are written to the same path so the bubble updates in place.
  String? _sstvFilename;
  bool _sstvImageSaved = false;
  bool _sstvPartialSaveInFlight = false;
  DateTime _lastSstvPartialSave = DateTime.fromMillisecondsSinceEpoch(0);

  // Decoded text history.
  final List<DecodedTextEntry> _decodedTextHistory = <DecodedTextEntry>[];
  DecodedTextEntry? _currentEntry;
  bool _voiceTextHistoryLoaded = false;

  File? _historyFile;

  /// Initializes the handler: subscribes to broker events, loads persisted
  /// state and dispatches the initial handler state. Safe to call once.
  void init() {
    if (_initialized || _disposed) return;
    _initialized = true;

    // Commands directed at the handler (device 1 / global).
    _broker.subscribe(
      deviceId: 1,
      name: 'CommsHandlerEnable',
      callback: _onCommsHandlerEnable,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'CommsHandlerDisable',
      callback: _onCommsHandlerDisable,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'RecordingEnable',
      callback: _onRecordingEnable,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'RecordingDisable',
      callback: _onRecordingDisable,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'ClearVoiceText',
      callback: _onClearVoiceText,
    );

    // Radio / audio state across all devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'State',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioState',
      callback: _onAudioStateChanged,
    );

    // Audio-run lifecycle and frames across all devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioDataStart',
      callback: _onAudioDataStart,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioDataEnd',
      callback: _onAudioDataEnd,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioDataAvailable',
      callback: _onAudioDataAvailable,
    );

    // Outgoing voice PCM (PTT / spoken text / Morse / DTMF) so the recorder can
    // capture transmitted audio for radios and EchoLink alike.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'TransmitVoicePCM',
      callback: _onTransmitVoicePcmRecord,
    );

    // Received data packets (AX.25 / BSS / APRS / Ident) across all devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );

    // Outgoing chat (BSS) messages from the voice panel across all devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Chat',
      callback: _onChat,
    );

    // EchoLink text chat (sent + received), surfaced by the EchoLink manager.
    // Recorded in history so it persists across restarts like other messages.
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkChat',
      callback: _onEchoLinkChat,
    );

    // Outgoing Morse-code transmissions from the voice panel across all
    // devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Morse',
      callback: _onMorse,
    );

    // Outgoing text-to-speech transmissions from the voice panel across all
    // devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Speak',
      callback: _onSpeak,
    );

    // SSTV picture transmissions recorded in history across all devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'PictureTransmitted',
      callback: _onPictureTransmitted,
    );

    // Speech-to-text on/off setting (device 0 = global settings).
    _broker.subscribe(
      deviceId: 0,
      name: 'SpeechToTextEnabled',
      callback: _onSpeechToTextEnabledChanged,
    );
    _speechToTextEnabled =
        _broker.getValue<bool>(0, 'SpeechToTextEnabled', true) ?? true;

    // Restore persisted recording flag (device 0 = settings).
    _recordingEnabled =
        _broker.getValue<bool>(0, 'RecordingState', false) ?? false;
    _dispatchRecordingState();

    // Pre-resolve the recordings folder so clip capture can start synchronously.
    unawaited(_ensureRecordingsDir());

    // Pre-resolve the SSTV images folder so decoded pictures can be saved.
    unawaited(_ensureSstvImagesDir());

    // Start the always-on SSTV monitor that auto-detects incoming images.
    _initializeSstvMonitor();

    // Initialize the speech-to-text engine if speech-to-text is enabled.
    // Speech-to-text is not available on Android (reduces APK size) or web.
    if (_speechToTextEnabled && !kIsWeb && !Platform.isAndroid) {
      unawaited(_initializeSpeechEngine());
    }

    // Dispatch initial handler state.
    _dispatchCommsHandlerState();

    // Load the persisted text history asynchronously.
    unawaited(_loadVoiceTextHistory());

    _broker.logInfo('[CommsHandler] Initialized');
  }

  // ---------------------------------------------------------------------------
  // Enable / Disable
  // ---------------------------------------------------------------------------

  /// Handles the CommsHandlerEnable command.
  /// Expected data: { deviceId/DeviceId, language/Language, model/Model }.
  void _onCommsHandlerEnable(int deviceId, String name, Object? data) {
    if (data is! Map) {
      _broker.logError('[CommsHandler] Invalid CommsHandlerEnable data format');
      return;
    }
    final map = data;
    final targetDevice = _readInt(map['deviceId'] ?? map['DeviceId']);
    final language = (map['language'] ?? map['Language']) as String? ?? 'auto';
    final model = (map['model'] ?? map['Model']) as String?;
    if (targetDevice == null) {
      _broker.logError('[CommsHandler] CommsHandlerEnable missing deviceId');
      return;
    }
    enable(targetDevice, language, model);
  }

  /// Handles the CommsHandlerDisable command.
  void _onCommsHandlerDisable(int deviceId, String name, Object? data) {
    disable();
  }

  /// Enables the voice handler to listen to a specific radio device.
  void enable(int deviceId, String language, String? model) {
    if (_enabled &&
        _targetDeviceId == deviceId &&
        _voiceLanguage == language &&
        _voiceModel == model) {
      return; // Already enabled with the same settings.
    }

    // Validate that the radio is connected before enabling.
    final radioState = _broker.getValue<String>(deviceId, 'State');
    if (radioState != 'Connected') {
      _broker.logError(
        '[CommsHandler] Cannot enable for device $deviceId: radio not connected (state: ${radioState ?? 'unknown'})',
      );
      return;
    }

    // Voice processing requires audio streaming; turn it on if necessary.
    final audioEnabled =
        _broker.getValue<bool>(deviceId, 'AudioState', false) ?? false;
    if (!audioEnabled) {
      _broker.logInfo(
        '[CommsHandler] Audio not enabled for device $deviceId, enabling audio streaming',
      );
      _broker.dispatch(
        deviceId: deviceId,
        name: 'SetAudio',
        data: true,
        store: false,
      );
    }

    if (_enabled) disable();

    _targetDeviceId = deviceId;
    _voiceLanguage = language;
    _voiceModel = model;
    _enabled = true;

    _broker.logInfo(
      '[CommsHandler] Enabled for device $deviceId, language: $language',
    );

    // Speech-to-text engine initialization is deferred in this build.
    // TODO(stt): initialize the speech-to-text engine here when available.

    _dispatchCommsHandlerState();
  }

  /// Disables the voice handler.
  void disable() {
    if (!_enabled) return;

    final previousDeviceId = _targetDeviceId;
    _enabled = false;
    _targetDeviceId = -1;

    // Speech-to-text cleanup is deferred in this build.

    // Indicate we are no longer listening/processing.
    if (previousDeviceId > 0) {
      _broker.dispatch(
        deviceId: previousDeviceId,
        name: 'ProcessingVoice',
        data: <String, Object?>{'listening': false, 'processing': false},
        store: false,
      );
    }

    _dispatchCommsHandlerState();
    _broker.logInfo('[CommsHandler] Disabled');
  }

  // ---------------------------------------------------------------------------
  // Speech-to-text (always-on, gated by the SpeechToTextEnabled setting)
  // ---------------------------------------------------------------------------

  /// Handles changes to the persisted `SpeechToTextEnabled` setting (device 0).
  void _onSpeechToTextEnabledChanged(int deviceId, String name, Object? data) {
    final enabled = data is bool ? data : true;
    if (_speechToTextEnabled == enabled) return;
    _speechToTextEnabled = enabled;
    _broker.logInfo('[CommsHandler] SpeechToTextEnabled changed to: $enabled');
    // Speech-to-text is not available on Android or web.
    if (kIsWeb || Platform.isAndroid) return;
    if (enabled) {
      unawaited(_initializeSpeechEngine());
    } else {
      unawaited(_cleanupSpeechEngine());
    }
    _dispatchCommsHandlerState();
  }

  /// Creates and initializes the platform speech-to-text engine. Safe to call
  /// repeatedly; only the first successful initialization takes effect.
  Future<void> _initializeSpeechEngine() async {
    if (_disposed || _sttEngine != null) return;
    final engine = createSpeechToTextEngine();
    _sttEngine = engine;
    if (!engine.isSupported) {
      _broker.logInfo(
        '[CommsHandler] Speech-to-text is not supported on this platform',
      );
      return;
    }
    _sttResultSub = engine.results.listen(_onSpeechResult);
    _sttProcessingSub = engine.processing.listen(_onSpeechProcessing);
    try {
      final localeId = (_voiceLanguage == 'auto') ? '' : _voiceLanguage;
      final ready = await engine.initialize(localeId: localeId);
      // The engine may have been disposed while we awaited initialization.
      if (_disposed || _sttEngine != engine) return;
      _sttReady = ready;
      if (ready) {
        _broker.logInfo('[CommsHandler] Speech-to-text engine ready');
      } else {
        _broker.logError(
          '[CommsHandler] Speech-to-text unavailable (not authorized or '
          'no recognizer)',
        );
      }
      _dispatchCommsHandlerState();
    } catch (e) {
      _broker.logError('[CommsHandler] Failed to initialize speech engine: $e');
      _sttReady = false;
    }
  }

  /// Tears down the speech-to-text engine and any in-progress segment.
  Future<void> _cleanupSpeechEngine() async {
    final engine = _sttEngine;
    _sttEngine = null;
    _sttReady = false;
    _sttSegmentActive = false;
    _sttSegmentBytes = 0;
    _sttDeviceId = -1;
    _sttCurrentEntry = null;
    await _sttResultSub?.cancel();
    _sttResultSub = null;
    await _sttProcessingSub?.cancel();
    _sttProcessingSub = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (e) {
        _broker.logError('[CommsHandler] Error disposing speech engine: $e');
      }
    }
  }

  /// Handles a partial or final recognition result from the speech engine.
  void _onSpeechResult(SpeechResult result) {
    if (_disposed || _sttDeviceId <= 0) return;
    final text = result.text.trim();
    final now = DateTime.now();
    final channel = _sttChannel.isNotEmpty ? _sttChannel : _currentChannelName;

    if (!result.isFinal) {
      // In-progress text: update or create the current STT entry.
      if (text.isEmpty) return;
      final entry = _sttCurrentEntry ?? DecodedTextEntry();
      entry.text = text;
      entry.channel = channel;
      entry.time = now;
      entry.isReceived = true;
      entry.encoding = VoiceTextEncodingType.voice;
      _sttCurrentEntry = entry;
      _currentEntry = entry;
      _dispatchCurrentEntry();
      _dispatchSttTextReady(text, channel, now, false);
    } else {
      // Final text: commit a non-empty result to history.
      _sttCurrentEntry = null;
      _currentEntry = null;
      if (text.isNotEmpty) {
        final entry = DecodedTextEntry(
          text: text,
          channel: channel,
          time: now,
          isReceived: true,
          encoding: VoiceTextEncodingType.voice,
        );
        _decodedTextHistory.add(entry);
        _trimHistory();
        unawaited(_saveVoiceTextHistory());
        _dispatchDecodedTextHistory();
        _dispatchSttTextReady(text, channel, now, true);
      }
      _dispatchCurrentEntry();
    }
  }

  /// Handles the engine's processing (listening/recognizing) indicator.
  void _onSpeechProcessing(bool active) {
    if (_disposed) return;
    // When the model is actively decoding, show red (processing=true).
    // When decoding finishes and no segment is active, hide the indicator.
    // When decoding finishes but a segment is still active (split), show green.
    if (active) {
      _dispatchSttProcessing(listening: false, processing: true);
    } else if (_sttSegmentActive) {
      _dispatchSttProcessing(listening: true, processing: false);
    } else {
      _dispatchSttProcessing(listening: false, processing: false);
    }
  }

  /// Dispatches a TextReady event directly to the radio device whose audio is
  /// being transcribed. Mirrors [_dispatchSstvTextReady] / the recording path:
  /// the voice tab subscribes to TextReady on all devices, but the gated
  /// [_dispatchTextReady] only fires for an enabled target radio (never set in
  /// this build).
  void _dispatchSttTextReady(
    String text,
    String channel,
    DateTime time,
    bool completed,
  ) {
    if (_sttDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _sttDeviceId,
      name: 'TextReady',
      data: <String, Object?>{
        'text': text,
        'channel': channel,
        'time': time.millisecondsSinceEpoch,
        'completed': completed,
        'isReceived': true,
        'encoding': _encodingToString(VoiceTextEncodingType.voice),
        'latitude': 0,
        'longitude': 0,
        'source': null,
        'destination': null,
        'filename': null,
        'duration': 0,
      },
      store: false,
    );
  }

  void _dispatchSttProcessing({
    required bool listening,
    required bool processing,
  }) {
    if (_sttDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _sttDeviceId,
      name: 'ProcessingVoice',
      data: <String, Object?>{'listening': listening, 'processing': processing},
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Recording (flag-only; WAV capture is stubbed)
  // ---------------------------------------------------------------------------

  void _onRecordingEnable(int deviceId, String name, Object? data) {
    if (_recordingEnabled) return;
    _recordingEnabled = true;
    _dispatchRecordingState();
    _broker.logInfo('[CommsHandler] Recording enabled');
  }

  void _onRecordingDisable(int deviceId, String name, Object? data) {
    if (!_recordingEnabled) return;
    // Finalize any in-progress recording before turning recording off.
    if (_recorder != null) _finalizeRecording();
    _recordingEnabled = false;
    _dispatchRecordingState();
    _broker.logInfo('[CommsHandler] Recording disabled');
  }

  void _dispatchRecordingState() {
    _broker.dispatch(
      deviceId: 0,
      name: 'RecordingState',
      data: _recordingEnabled,
      store: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Radio / audio state monitoring (auto-disable)
  // ---------------------------------------------------------------------------

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    if (deviceId != _targetDeviceId || !_enabled) return;
    final state = data is String ? data : null;
    if (state == null) return;
    if (state == 'Disconnected' ||
        state == 'UnableToConnect' ||
        state == 'BluetoothNotAvailable' ||
        state == 'AccessDenied') {
      _broker.logInfo(
        '[CommsHandler] Target radio $deviceId disconnected (state: $state), disabling voice handler',
      );
      disable();
    }
  }

  void _onAudioStateChanged(int deviceId, String name, Object? data) {
    if (deviceId != _targetDeviceId || !_enabled) return;
    final audioEnabled = data is bool ? data : false;
    if (!audioEnabled) {
      _broker.logInfo(
        '[CommsHandler] Audio disabled on target radio $deviceId, disabling voice handler',
      );
      disable();
    }
  }

  // ---------------------------------------------------------------------------
  // Audio-run lifecycle and frames
  // ---------------------------------------------------------------------------

  void _onAudioDataStart(int deviceId, String name, Object? data) {
    // Recording is independent of the voice-handler enable state: it captures
    // whichever radio is streaming audio while recording is turned on.
    if (_recordingEnabled) {
      _handleRecordingStart(deviceId, data);
    }

    // Speech-to-text segment start (deferred) for the enabled target radio.
    if (deviceId == _targetDeviceId && _enabled) {
      if (data is Map) {
        final cn =
            (data['channelName'] ?? data['ChannelName']) as String? ?? '';
        if (cn.isNotEmpty) _currentChannelName = cn;
        _currentAudioIsTransmit =
            (data['transmit'] ?? data['Transmit']) as bool? ?? false;
      }
      // TODO(stt): begin a new speech segment.
    }

    // Speech-to-text: begin a new recognition segment for received audio.
    _handleSttStart(deviceId, data);
  }

  /// Starts a new speech-to-text segment for received (non-transmit) audio on
  /// [deviceId]. Locks onto a single device for the duration of the segment.
  void _handleSttStart(int deviceId, Object? data) {
    if (!_speechToTextEnabled || !_sttReady || deviceId <= 0) return;
    // Don't run speech-to-text while an SSTV image is being received: the SSTV
    // tones aren't speech and the recognizer would compete for CPU with the
    // image decoder, stalling reception.
    if (_sstvDecoding) return;
    final engine = _sttEngine;
    if (engine == null) return;

    String channel = _currentChannelName;
    bool transmit = false;
    Object? usage;
    if (data is Map) {
      final cn = (data['channelName'] ?? data['ChannelName']) as String? ?? '';
      if (cn.isNotEmpty) channel = cn;
      transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
      usage = data['usage'] ?? data['Usage'];
    }

    // Only transcribe received audio on a normal channel (not APRS, not when
    // the radio is locked to a usage).
    if (transmit || usage != null || channel == 'APRS') return;

    // If a segment is already active on another device, leave it alone.
    if (_sttSegmentActive && deviceId != _sttDeviceId) return;

    _beginSttSegment(deviceId, channel);
  }

  /// Opens a fresh recognition segment locked to [deviceId]. Shared by the
  /// AudioDataStart path and the lazy start in [_handleSttFrame].
  void _beginSttSegment(int deviceId, String channel) {
    final engine = _sttEngine;
    if (engine == null) return;
    _sttDeviceId = deviceId;
    _sttChannel = channel;
    _sttSegmentActive = true;
    _sttSegmentBytes = 0;
    _sttCurrentEntry = null;
    if (channel.isNotEmpty) _currentChannelName = channel;
    unawaited(engine.startSegment());
    _dispatchSttProcessing(listening: true, processing: false);
  }

  void _onAudioDataEnd(int deviceId, String name, Object? data) {
    // Finalize the active received recording when its audio run ends. A
    // transmit recording is driven by the TransmitVoicePCM stream and finalized
    // separately, so don't let a received audio-run end cut it short.
    if (_recorder != null &&
        deviceId == _recordingDeviceId &&
        !_recordingIsTransmit) {
      _finalizeRecording();
    }

    // Finalize any in-progress SSTV decoding when the audio stream ends.
    if (_sstvDecoding && deviceId == _sstvDeviceId) {
      _finalizeSstvOnAudioEnd();
    }

    // Speech-to-text flush (deferred) for the enabled target radio.
    if (deviceId == _targetDeviceId && _enabled) {
      // TODO(stt): flush the current speech segment.
    }

    // Speech-to-text: complete the active segment to force a final result.
    if (_sttSegmentActive && deviceId == _sttDeviceId) {
      _handleSttEnd();
    }
  }

  /// Completes the active speech-to-text segment, forcing a final result. The
  /// device lock is kept so the trailing final result still dispatches to the
  /// correct radio.
  void _handleSttEnd() {
    final engine = _sttEngine;
    _sttSegmentActive = false;
    _sttSegmentBytes = 0;
    if (engine != null) unawaited(engine.completeSegment());
    // Don't dispatch here — the worker will emit processing events around
    // the actual decode, which _onSpeechProcessing handles.
  }

  /// Discards any in-progress speech-to-text segment without emitting a final
  /// result. Called when SSTV reception starts so the recognizer stops trying
  /// to transcribe the SSTV tones and frees CPU for the image decoder.
  void _abortSttForSstv() {
    if (!_sttSegmentActive) return;
    final engine = _sttEngine;
    _sttSegmentActive = false;
    _sttSegmentBytes = 0;
    _sttCurrentEntry = null;
    _currentEntry = null;
    if (engine != null) unawaited(engine.resetSegment());
    _dispatchSttProcessing(listening: false, processing: false);
  }

  /// Feeds a received PCM frame into the active speech-to-text segment. Bounds
  /// the segment size by forcing a final result and restarting if it grows too
  /// large.
  void _handleSttFrame(int deviceId, Map data) {
    if (!_speechToTextEnabled || !_sttReady || deviceId <= 0) return;
    // Suspend speech-to-text while an SSTV image is being received so the
    // recognizer doesn't process the SSTV tones or starve the image decoder.
    if (_sstvDecoding) return;
    final engine = _sttEngine;
    if (engine == null) return;

    final usage = data['usage'] ?? data['Usage'];
    final transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
    final muted = (data['muted'] ?? data['Muted']) as bool? ?? false;
    final channelName =
        (data['channelName'] ?? data['ChannelName']) as String? ?? '';
    if (usage != null || transmit || muted || channelName == 'APRS') return;

    // If a segment is active on a different device, leave it alone.
    if (_sttSegmentActive && deviceId != _sttDeviceId) return;

    final bytes = data['data'] ?? data['Data'];
    if (bytes is! Uint8List) return;
    final offset = _readInt(data['offset'] ?? data['Offset']) ?? 0;
    final length =
        _readInt(data['length'] ?? data['Length']) ?? (bytes.length - offset);
    if (length <= 0) return;

    // Lazily begin a segment if none is active. Continuous broadcasts (e.g.
    // NOAA weather) fire AudioDataStart only once — possibly before the engine
    // became ready or before the user enabled STT — so the start event can be
    // missed. Starting here from the audio frames (like the SSTV monitor) keeps
    // recognition working mid-stream.
    if (!_sttSegmentActive) {
      final channel = channelName.isNotEmpty
          ? channelName
          : _currentChannelName;
      _beginSttSegment(deviceId, channel);
    }

    unawaited(engine.processPcm16(bytes, offset, length, _sttSampleRate));
    _sttSegmentBytes += length;

    if (_sttSegmentBytes >= _sttMaxSegmentBytes) {
      // Segment ran too long: decode and keep a short overlap tail so words
      // at the boundary are not lost.
      _broker.logInfo(
        '[CommsHandler] Speech segment split due to length limit',
      );
      unawaited(engine.splitSegment());
      _sttSegmentBytes = 0;
      _sttCurrentEntry = null;
    }
  }

  void _onAudioDataAvailable(int deviceId, String name, Object? data) {
    if (data is! Map) return;

    // Recording: append PCM frames to the active recording.
    final recorder = _recorder;
    if (recorder != null &&
        deviceId == _recordingDeviceId &&
        !_recordingIsTransmit) {
      final usage = data['usage'] ?? data['Usage'];
      final muted = (data['muted'] ?? data['Muted']) as bool? ?? false;
      final transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
      // Received-audio recording only. Transmitted audio is captured from the
      // TransmitVoicePCM stream (see _onTransmitVoicePcmRecord), so a radio's
      // transmit "echo" frames are ignored here to avoid double-recording.
      if (usage == null && !muted && !transmit) {
        // Capture the channel name from the audio frames; this resolves the
        // recording's channel even when it wasn't known at the audio-run start.
        final frameChannel =
            (data['channelName'] ?? data['ChannelName']) as String? ?? '';
        if (frameChannel.isNotEmpty && frameChannel != 'APRS') {
          _currentChannelName = frameChannel;
          if (_recordingChannel.isEmpty) _recordingChannel = frameChannel;
        }
        final bytes = data['data'] ?? data['Data'];
        if (bytes is Uint8List) {
          final offset = _readInt(data['offset'] ?? data['Offset']) ?? 0;
          final length =
              _readInt(data['length'] ?? data['Length']) ??
              (bytes.length - offset);
          recorder.write(bytes, offset, length);
        }
      }
    }

    // Speech-to-text (deferred) for the enabled target radio.
    if (deviceId == _targetDeviceId && _enabled) {
      // TODO(stt): feed PCM frames to the speech-to-text engine.
    }

    // Speech-to-text: feed received PCM frames into the active segment.
    _handleSttFrame(deviceId, data);

    // SSTV auto-detection: feed received (non-transmit) PCM to the monitor.
    // This runs independently of the voice-handler enable state, tracking the
    // radio device that is currently streaming received audio.
    final monitor = _sstvMonitor;
    if (monitor != null && deviceId > 0) {
      final usage = data['usage'] ?? data['Usage'];
      final transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
      final muted = (data['muted'] ?? data['Muted']) as bool? ?? false;
      final channelName =
          (data['channelName'] ?? data['ChannelName']) as String? ?? '';
      // Decode SSTV even on muted channels: muting silences playback but we
      // still want to detect and decode incoming SSTV images.
      if (usage == null && !transmit && channelName != 'APRS') {
        // Lock onto a single device for the duration of a decode.
        if (!_sstvDecoding) _sstvDeviceId = deviceId;
        if (deviceId == _sstvDeviceId) {
          // Remember whether this channel is flagged as muted so the auto-mute
          // can be skipped: a muted channel's audio is already silenced.
          _sstvChannelMuted = muted;
          if (channelName.isNotEmpty) _currentChannelName = channelName;
          final bytes = data['data'] ?? data['Data'];
          if (bytes is Uint8List) {
            final offset = _readInt(data['offset'] ?? data['Offset']) ?? 0;
            final length =
                _readInt(data['length'] ?? data['Length']) ??
                (bytes.length - offset);
            monitor.processPcm16(bytes, offset, length);
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // WAV recording
  // ---------------------------------------------------------------------------

  Future<Directory?> _ensureRecordingsDir() async {
    if (_recordingsDir != null) return _recordingsDir;
    // The web build has no audio channel and no file-system access through
    // path_provider, so audio recordings are not supported there.
    if (kIsWeb) return null;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}$_recordingsFolderName',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _recordingsDir = dir;
      return dir;
    } catch (e) {
      _broker.logError('[CommsHandler] Failed to resolve recordings dir: $e');
      return null;
    }
  }

  void _handleRecordingStart(int deviceId, Object? data) {
    if (data is! Map) return;
    // Skip if the radio is locked to a usage.
    final usage = data['usage'] ?? data['Usage'];
    if (usage != null) return;
    // Transmitted audio is captured from the TransmitVoicePCM stream instead of
    // the radio's transmit "echo", so ignore transmit audio runs here.
    if ((data['transmit'] ?? data['Transmit']) as bool? ?? false) return;
    // Don't record audio coming in on a muted channel.
    final muted = (data['muted'] ?? data['Muted']) as bool? ?? false;
    if (muted) return;
    var channel = (data['channelName'] ?? data['ChannelName']) as String? ?? '';
    // Fall back to the last known channel name if this event didn't carry one
    // (e.g. channel info had not finished loading when the audio run started).
    if (channel.isEmpty) channel = _currentChannelName;
    if (channel.isNotEmpty) _currentChannelName = channel;
    // Don't record the APRS channel.
    if (channel == 'APRS') return;
    final transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
    final startMs = _readInt(data['startTime'] ?? data['StartTime']);
    final startTime = startMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startMs)
        : DateTime.now();
    _startNewRecording(deviceId, startTime, channel, transmit);
  }

  /// Captures outgoing voice (PTT / spoken text / Morse / DTMF) into a
  /// recording so transmitted audio is recorded alongside received audio. Both
  /// radios and EchoLink transmit via the TransmitVoicePCM stream, so this works
  /// uniformly for either.
  void _onTransmitVoicePcmRecord(int deviceId, String name, Object? data) {
    if (!_recordingEnabled || data is! Map) return;

    final bytes = data['data'] ?? data['Data'];
    final bool hold = (data['hold'] ?? data['Hold']) as bool? ?? true;

    if (bytes is! Uint8List) {
      // End-of-transmission marker (e.g. PTT released): finalize the run.
      if (!hold) _finalizeTransmitRecording();
      return;
    }

    // Start a fresh transmit recording if none is active, or the active one is
    // a received recording / for a different device (half-duplex, so it has
    // effectively ended).
    if (_recorder == null ||
        !_recordingIsTransmit ||
        _recordingDeviceId != deviceId) {
      var channel = _getVfoAChannelName(deviceId);
      if (channel.isEmpty) channel = _currentChannelName;
      _startNewRecording(deviceId, DateTime.now(), channel, true);
    }

    final recorder = _recorder;
    if (recorder == null || !_recordingIsTransmit) return;

    final offset = _readInt(data['offset'] ?? data['Offset']) ?? 0;
    final length =
        _readInt(data['length'] ?? data['Length']) ?? (bytes.length - offset);
    if (length > 0) recorder.write(bytes, offset, length);

    // A one-shot blob (spoken text / Morse / DTMF) has no explicit end, so
    // finalize after a short silence. A held PTT keeps streaming and sends
    // hold:false on release, which finalizes immediately.
    _txRecordTimer?.cancel();
    if (!hold) {
      _finalizeTransmitRecording();
    } else {
      _txRecordTimer = Timer(
        const Duration(milliseconds: _txRecordEndMs),
        _finalizeTransmitRecording,
      );
    }
  }

  /// Finalizes the active transmit recording (if any).
  void _finalizeTransmitRecording() {
    _txRecordTimer?.cancel();
    _txRecordTimer = null;
    if (_recorder != null && _recordingIsTransmit) {
      _finalizeRecording();
    }
  }

  void _startNewRecording(
    int deviceId,
    DateTime startTime,
    String channel,
    bool transmit,
  ) {
    // Finalize any previous recording first.
    if (_recorder != null) _finalizeRecording();

    final dir = _recordingsDir;
    if (dir == null) {
      // Folder not resolved yet; trigger resolution and skip this clip.
      unawaited(_ensureRecordingsDir());
      return;
    }

    final filename =
        'Recording_${_formatTimestamp(startTime)}_${_sanitizeChannel(channel)}.wav';
    final fullPath = '${dir.path}${Platform.pathSeparator}$filename';
    final recorder = _WavClipRecorder.open(fullPath, _recordingSampleRate);
    if (recorder == null) {
      _broker.logError('[CommsHandler] Failed to start recording: $filename');
      return;
    }

    _recorder = recorder;
    _recordingDeviceId = deviceId;
    _recordingStartTime = startTime;
    _recordingChannel = channel;
    _recordingFilename = filename;
    _recordingIsTransmit = transmit;
  }

  void _finalizeRecording() {
    final recorder = _recorder;
    if (recorder == null) return;
    _txRecordTimer?.cancel();
    _txRecordTimer = null;
    _recorder = null;
    final dataBytes = recorder.dataBytes;
    recorder.close();

    var filename = _recordingFilename;
    final channel = _recordingChannel;
    final startTime = _recordingStartTime;
    final isReceived = !_recordingIsTransmit;
    final deviceId = _recordingDeviceId;
    final dir = _recordingsDir;

    _recordingDeviceId = -1;
    _recordingFilename = '';
    _recordingChannel = '';

    // 32000 Hz * 2 bytes/sample (16-bit mono) = 64000 bytes per second.
    final durationSeconds = dataBytes / 64000.0;
    if (durationSeconds >= 0.5) {
      // The channel may have been resolved from the audio frames after the file
      // was created; rename the file so it reflects the correct channel name.
      if (dir != null && channel.isNotEmpty) {
        final desired =
            'Recording_${_formatTimestamp(startTime)}_${_sanitizeChannel(channel)}.wav';
        if (desired != filename) {
          try {
            final oldFile = File(
              '${dir.path}${Platform.pathSeparator}$filename',
            );
            if (oldFile.existsSync()) {
              oldFile.renameSync(
                '${dir.path}${Platform.pathSeparator}$desired',
              );
              filename = desired;
            }
          } catch (e) {
            _broker.logError('[CommsHandler] Failed to rename recording: $e');
          }
        }
      }
      final durationInt = durationSeconds.round();
      final entry = DecodedTextEntry(
        text: null,
        channel: channel,
        time: startTime,
        isReceived: isReceived,
        encoding: VoiceTextEncodingType.recording,
        filename: filename,
        duration: durationInt,
      );
      _decodedTextHistory.add(entry);
      _trimHistory();
      unawaited(_saveVoiceTextHistory());
      _dispatchDecodedTextHistory();
      _dispatchRecordingTextReady(
        deviceId,
        channel,
        startTime,
        isReceived,
        filename,
        durationInt,
      );
      _broker.logInfo(
        '[CommsHandler] Completed recording: $filename (${durationSeconds.toStringAsFixed(1)} sec)',
      );
    } else {
      // Discard recordings that are too short to be useful.
      if (dir != null) {
        try {
          File('${dir.path}${Platform.pathSeparator}$filename').deleteSync();
        } catch (_) {}
      }
      _broker.logInfo('[CommsHandler] Discarded short recording: $filename');
    }
  }

  void _dispatchRecordingTextReady(
    int deviceId,
    String channel,
    DateTime time,
    bool isReceived,
    String filename,
    int duration,
  ) {
    if (deviceId <= 0) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'TextReady',
      data: <String, Object?>{
        'text': null,
        'channel': channel,
        'time': time.millisecondsSinceEpoch,
        'completed': true,
        'isReceived': isReceived,
        'encoding': _encodingToString(VoiceTextEncodingType.recording),
        'latitude': 0,
        'longitude': 0,
        'source': null,
        'destination': null,
        'filename': filename,
        'duration': duration,
      },
      store: false,
    );
  }

  String _sanitizeChannel(String channel) {
    if (channel.isEmpty) return 'Unknown';
    final sanitized = channel.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    return sanitized.isEmpty ? 'Unknown' : sanitized;
  }

  String _formatTimestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date =
        '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
    final clock = '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
    return '${date}_$clock';
  }

  // ---------------------------------------------------------------------------
  // SSTV image reception
  // ---------------------------------------------------------------------------

  Future<Directory?> _ensureSstvImagesDir() async {
    if (_sstvImagesDir != null) return _sstvImagesDir;
    // The web build has no audio channel and no file-system access through
    // path_provider, so SSTV image reception is not supported there.
    if (kIsWeb) return null;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}$_sstvFolderName',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _sstvImagesDir = dir;
      return dir;
    } catch (e) {
      _broker.logError('[CommsHandler] Failed to resolve SSTV dir: $e');
      return null;
    }
  }

  /// Creates a fresh SSTV monitor and subscribes to its decoding events.
  void _initializeSstvMonitor() {
    _cleanupSstvMonitor();
    final monitor = SstvMonitor(sampleRate: _sstvSampleRate);
    _sstvStartedSub = monitor.onDecodingStarted.listen(_onSstvDecodingStarted);
    _sstvProgressSub = monitor.onDecodingProgress.listen(
      _onSstvDecodingProgress,
    );
    _sstvCompleteSub = monitor.onDecodingComplete.listen(
      _onSstvDecodingComplete,
    );
    _sstvMonitor = monitor;
    _broker.logInfo('[CommsHandler] SSTV monitor initialized');
  }

  /// Cancels the SSTV monitor subscriptions and disposes the monitor.
  void _cleanupSstvMonitor() {
    _sstvStartedSub?.cancel();
    _sstvProgressSub?.cancel();
    _sstvCompleteSub?.cancel();
    _sstvStartedSub = null;
    _sstvProgressSub = null;
    _sstvCompleteSub = null;
    _sstvMonitor?.dispose();
    _sstvMonitor = null;
    _sstvDecoding = false;
    _sstvAutoMuted = false;
    _sstvChannelMuted = false;
    _currentSstvEntry = null;
    _sstvFilename = null;
    _sstvImageSaved = false;
    _sstvPartialSaveInFlight = false;
    _lastSstvPartialSave = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Called when the monitor detects the start of an SSTV image.
  void _onSstvDecodingStarted(SstvDecodingStarted e) {
    _broker.logInfo(
      '[CommsHandler] SSTV decoding started: ${e.modeName} (${e.width}x${e.height})',
    );
    _sstvDecoding = true;
    _sstvStartTime = DateTime.now();
    _sstvFilename =
        'SSTV_${_formatTimestamp(_sstvStartTime)}_${_sanitizeChannel(e.modeName)}.png';
    _sstvImageSaved = false;
    _lastSstvPartialSave = DateTime.fromMillisecondsSinceEpoch(0);

    // Stop any in-progress speech-to-text so it doesn't transcribe the SSTV
    // tones and compete for CPU with the image decoder during reception.
    _abortSttForSstv();

    // Auto-mute the radio so the user doesn't hear the raw SSTV tones. If the
    // channel is already muted — either by the user (device Mute) or because the
    // channel itself is flagged as muted — the audio is already silenced, so the
    // auto-mute is unnecessary. Leave the mute state untouched and don't flag an
    // auto-mute (so the UI won't show a redundant "Audio is muted." banner).
    if (_sstvDeviceId > 0) {
      final alreadyMuted =
          (_broker.getValue<bool>(_sstvDeviceId, 'Mute', false) ?? false) ||
          _sstvChannelMuted;
      if (!alreadyMuted) {
        _sstvAutoMuted = true;
        _broker.dispatch(
          deviceId: _sstvDeviceId,
          name: 'SetMute',
          data: true,
          store: false,
        );
      } else {
        _sstvAutoMuted = false;
      }
      _broker.dispatch(
        deviceId: _sstvDeviceId,
        name: 'SstvAutoMute',
        data: _sstvAutoMuted,
        store: true,
      );
    }

    final channelName = _currentChannelName;
    _currentSstvEntry = DecodedTextEntry(
      text: 'Receiving ${e.modeName}...',
      channel: channelName,
      time: _sstvStartTime,
      isReceived: true,
      encoding: VoiceTextEncodingType.picture,
    );

    // Dispatch a partial TextReady so the UI shows the in-progress entry.
    _dispatchSstvTextReady(
      'Receiving ${e.modeName}...',
      channelName,
      _sstvStartTime,
      false,
    );
  }

  /// Called when the monitor has decoded more scan lines (progress update).
  void _onSstvDecodingProgress(SstvDecodingProgress e) {
    final progressText =
        'Receiving ${e.modeName}... ${e.percentComplete.toStringAsFixed(0)}%';
    _currentSstvEntry?.text = progressText;

    // Periodically save the partial image so it can be shown in the bubble as
    // it is received. Saving on every scan line would be too costly, so the
    // saves are throttled; text-only updates are dispatched in between.
    final now = DateTime.now();
    final due = now.difference(_lastSstvPartialSave).inMilliseconds >= 600;
    if (due && !_sstvPartialSaveInFlight) {
      _lastSstvPartialSave = now;
      unawaited(_saveSstvPartialImage(progressText));
    } else {
      _dispatchSstvTextReady(
        progressText,
        _currentChannelName,
        _sstvStartTime,
        false,
        filename: _sstvImageSaved ? _sstvFilename : null,
      );
    }
  }

  /// Encodes and saves the partial SSTV image decoded so far, then notifies the
  /// UI so the in-progress picture updates in its chat bubble.
  Future<void> _saveSstvPartialImage(String progressText) async {
    _sstvPartialSaveInFlight = true;
    try {
      final monitor = _sstvMonitor;
      final filename = _sstvFilename;
      if (monitor == null || filename == null) return;
      final partial = monitor.getPartialImage();
      if (partial == null) return;
      final dir = await _ensureSstvImagesDir();
      if (dir == null) return;
      final pngBytes = await _encodeSstvPng(partial);
      if (pngBytes == null) return;
      final fullPath = '${dir.path}${Platform.pathSeparator}$filename';
      await File(fullPath).writeAsBytes(pngBytes, flush: true);
      _sstvImageSaved = true;
      _dispatchSstvTextReady(
        progressText,
        _currentChannelName,
        _sstvStartTime,
        false,
        filename: filename,
        imageUpdated: true,
      );
    } catch (e) {
      _broker.logError('[CommsHandler] Error saving partial SSTV image: $e');
    } finally {
      _sstvPartialSaveInFlight = false;
    }
  }

  /// Called when the monitor has completed decoding an image.
  void _onSstvDecodingComplete(SstvDecodingComplete e) {
    unawaited(_handleSstvComplete(e.modeName, e.image));
  }

  /// Finalizes any in-progress SSTV decoding when the audio stream ends,
  /// saving whatever partial image has been decoded so far.
  void _finalizeSstvOnAudioEnd() {
    try {
      _broker.logInfo(
        '[CommsHandler] Audio ended during SSTV decoding, finalizing partial reception',
      );
      final monitor = _sstvMonitor;
      SstvImage? partialImage;
      if (monitor != null) {
        partialImage = monitor.getPartialImage();
        monitor.reset();
      }
      final modeName = (_currentSstvEntry?.text ?? 'SSTV')
          .replaceAll('Receiving ', '')
          .replaceAll('...', '');
      unawaited(_handleSstvComplete(modeName, partialImage));
    } catch (e) {
      _broker.logError('[CommsHandler] Error finalizing SSTV on audio end: $e');
      _sstvDecoding = false;
    }
  }

  /// Saves a decoded SSTV image to disk and records it in the text history.
  Future<void> _handleSstvComplete(String modeName, SstvImage? image) async {
    _broker.logInfo(
      '[CommsHandler] SSTV image decoded: $modeName (${image?.width ?? 0}x${image?.height ?? 0})',
    );
    _sstvDecoding = false;

    // Restore the mute state if we auto-muted for SSTV reception.
    if (_sstvAutoMuted && _sstvDeviceId > 0) {
      _broker.dispatch(
        deviceId: _sstvDeviceId,
        name: 'SetMute',
        data: false,
        store: false,
      );
    }
    if (_sstvDeviceId > 0) {
      _broker.dispatch(
        deviceId: _sstvDeviceId,
        name: 'SstvAutoMute',
        data: false,
        store: true,
      );
    }
    _sstvAutoMuted = false;

    if (image == null) {
      _currentSstvEntry = null;
      _dispatchSstvTextReady(
        '$modeName - Reception failed',
        _currentChannelName,
        _sstvStartTime,
        true,
      );
      return;
    }

    final now = _sstvStartTime;
    final channelName = _currentChannelName;
    final safeMode = _sanitizeChannel(modeName);
    final filename =
        _sstvFilename ?? 'SSTV_${_formatTimestamp(now)}_$safeMode.png';

    try {
      final dir = await _ensureSstvImagesDir();
      if (dir == null) {
        _currentSstvEntry = null;
        return;
      }
      final pngBytes = await _encodeSstvPng(image);
      if (pngBytes == null) {
        _broker.logError('[CommsHandler] Failed to encode SSTV image');
        _currentSstvEntry = null;
        return;
      }
      final fullPath = '${dir.path}${Platform.pathSeparator}$filename';
      await File(fullPath).writeAsBytes(pngBytes, flush: true);
      _broker.logInfo('[CommsHandler] SSTV image saved: $filename');

      // Finalize the partial entry (or create one) in the text history.
      final entry = _currentSstvEntry;
      if (entry != null) {
        entry.text = modeName;
        entry.filename = filename;
        _decodedTextHistory.add(entry);
      } else {
        _decodedTextHistory.add(
          DecodedTextEntry(
            text: modeName,
            channel: channelName,
            time: now,
            isReceived: true,
            encoding: VoiceTextEncodingType.picture,
            filename: filename,
          ),
        );
      }
      _currentSstvEntry = null;
      _trimHistory();
      unawaited(_saveVoiceTextHistory());
      _dispatchDecodedTextHistory();

      _dispatchSstvTextReady(
        modeName,
        channelName,
        now,
        true,
        filename: filename,
        imageUpdated: true,
      );
    } catch (e) {
      _broker.logError('[CommsHandler] Error saving SSTV image: $e');
      _currentSstvEntry = null;
    }
  }

  /// Dispatches a TextReady event for an SSTV picture to the radio device that
  /// is currently being decoded. Mirrors [_dispatchRecordingTextReady] so the
  /// voice tab shows the entry regardless of the voice-handler enable state.
  void _dispatchSstvTextReady(
    String? text,
    String? channel,
    DateTime time,
    bool completed, {
    String? filename,
    bool imageUpdated = false,
  }) {
    if (_sstvDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _sstvDeviceId,
      name: 'TextReady',
      data: <String, Object?>{
        'text': text,
        'channel': channel,
        'time': time.millisecondsSinceEpoch,
        'completed': completed,
        'isReceived': true,
        'encoding': _encodingToString(VoiceTextEncodingType.picture),
        'latitude': 0,
        'longitude': 0,
        'source': null,
        'destination': null,
        'filename': filename,
        'duration': 0,
        'imageUpdated': imageUpdated,
      },
      store: false,
    );
  }

  /// Handles the `PictureTransmitted` command to record an SSTV picture
  /// transmission in history. Expected data: `{ modeName, filename }`.
  ///
  /// Dispatches a TextReady event directly to the transmitting device so the
  /// voice tab shows the sent picture regardless of the enable state, mirroring
  /// [_dispatchSstvTextReady] on the receive side.
  void _onPictureTransmitted(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    try {
      final modeName =
          (data['modeName'] ?? data['ModeName']) as String? ?? 'SSTV';
      final filename = (data['filename'] ?? data['Filename']) as String? ?? '';
      if (filename.isEmpty) {
        _broker.logError(
          '[CommsHandler] PictureTransmitted: Filename is empty',
        );
        return;
      }

      final now = DateTime.now();
      final channel = _currentChannelName;

      _broker.logInfo(
        '[CommsHandler] SSTV picture transmitted on device $deviceId: '
        '$modeName, file: $filename',
      );

      final entry = DecodedTextEntry(
        text: modeName,
        channel: channel,
        time: now,
        isReceived: false,
        encoding: VoiceTextEncodingType.picture,
        filename: filename,
      );
      _decodedTextHistory.add(entry);
      _trimHistory();
      unawaited(_saveVoiceTextHistory());
      _dispatchDecodedTextHistory();

      if (deviceId > 0) {
        _broker.dispatch(
          deviceId: deviceId,
          name: 'TextReady',
          data: <String, Object?>{
            'text': modeName,
            'channel': channel,
            'time': now.millisecondsSinceEpoch,
            'completed': true,
            'isReceived': false,
            'encoding': _encodingToString(VoiceTextEncodingType.picture),
            'latitude': 0,
            'longitude': 0,
            'source': null,
            'destination': null,
            'filename': filename,
            'duration': 0,
          },
          store: false,
        );
      }
    } catch (e) {
      _broker.logError('[CommsHandler] Error in _onPictureTransmitted: $e');
    }
  }

  Future<Uint8List?> _encodeSstvPng(SstvImage image) async {
    final w = image.width;
    final h = image.height;
    if (w <= 0 || h <= 0) return null;
    final px = image.pixels;
    final count = w * h;
    final rgba = Uint8List(count * 4);
    for (int i = 0; i < count; i++) {
      final p = i < px.length ? px[i] : 0xFF000000;
      final o = i * 4;
      rgba[o] = (p >> 16) & 0xff; // R
      rgba[o + 1] = (p >> 8) & 0xff; // G
      rgba[o + 2] = p & 0xff; // B
      rgba[o + 3] = (p >> 24) & 0xff; // A
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final uiImage = await completer.future;
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    uiImage.dispose();
    return byteData?.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // Decoded text history
  // ---------------------------------------------------------------------------

  /// Adds a transmitted entry to history and dispatches a TextReady event.
  void addTransmittedTextToHistory(
    String? text,
    String? channel,
    VoiceTextEncodingType encoding, {
    String? source,
    String? destination,
    String? filename,
    double latitude = 0,
    double longitude = 0,
  }) {
    final entry = DecodedTextEntry(
      text: text,
      channel: channel,
      time: DateTime.now(),
      isReceived: false,
      encoding: encoding,
      source: source,
      destination: destination,
      filename: filename,
      latitude: latitude,
      longitude: longitude,
    );
    _decodedTextHistory.add(entry);
    _trimHistory();
    unawaited(_saveVoiceTextHistory());
    _dispatchTextReady(
      text,
      channel,
      entry.time,
      true,
      isReceived: false,
      encoding: encoding,
      latitude: latitude,
      longitude: longitude,
      source: source,
      destination: destination,
      filename: filename,
    );
  }

  /// Updates the decoded text history with new (possibly in-progress) text.
  void updateDecodedTextHistory(
    String? text,
    String? channel,
    DateTime time,
    bool completed,
    bool isReceived,
    VoiceTextEncodingType encoding,
  ) {
    if (!completed) {
      // In-progress text: update or create the current entry.
      final entry = _currentEntry ?? DecodedTextEntry();
      entry.text = text;
      entry.channel = channel;
      entry.time = time;
      entry.isReceived = isReceived;
      entry.encoding = encoding;
      _currentEntry = entry;
      _dispatchCurrentEntry();
    } else {
      // Completed text: finalize the entry.
      final entry = _currentEntry ?? DecodedTextEntry();
      entry.text = text;
      entry.channel = channel;
      entry.time = time;
      entry.isReceived = isReceived;
      entry.encoding = encoding;
      _decodedTextHistory.add(entry);
      _currentEntry = null;
      _trimHistory();
      unawaited(_saveVoiceTextHistory());
      _dispatchCurrentEntry();
    }

    _dispatchTextReady(
      text,
      channel,
      time,
      completed,
      isReceived: isReceived,
      encoding: encoding,
    );
  }

  void _trimHistory() {
    while (_decodedTextHistory.length > _maxHistorySize) {
      _decodedTextHistory.removeAt(0);
    }
  }

  void _onClearVoiceText(int deviceId, String name, Object? data) {
    _decodedTextHistory.clear();
    _currentEntry = null;
    unawaited(_saveVoiceTextHistory());
    _dispatchDecodedTextHistory();
    _dispatchCurrentEntry();
    _broker.dispatch(
      deviceId: 1,
      name: 'VoiceTextCleared',
      data: null,
      store: false,
    );
    _broker.logInfo('[CommsHandler] Decoded text history cleared');
  }

  // ---------------------------------------------------------------------------
  // Received data-packet decoding (UniqueDataFrame)
  // ---------------------------------------------------------------------------

  /// Handles incoming UniqueDataFrame events and processes unassigned data
  /// packets that did NOT arrive on the APRS channel. Mirrors the C#
  /// `OnUniqueDataFrame`: decodes BSS / Ident / APRS / AX.25 packets and adds
  /// them to the decoded-text history.
  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! TncDataFragment) return;
    final frame = data;

    // Only process frames with no usage (unassigned packets).
    final usage = frame.usage;
    if (usage != null && usage.isNotEmpty) return;

    // Skip frames from the APRS channel (handled by the APRS handler).
    if (frame.channelName == 'APRS') return;

    // Try to decode the frame as a BSS packet first.
    final bssPacket = BSSPacket.decode(frame.data);
    if (bssPacket != null) {
      // Only add to history if this is an incoming BSS packet. Outgoing BSS
      // packets are already recorded by the send path.
      if (!frame.incoming) return;

      var encoding = VoiceTextEncodingType.bss;
      var message = bssPacket.message ?? '';
      final callsign = bssPacket.callsign ?? '';
      final locationRequest = bssPacket.locationRequest ?? '';
      final callRequest = bssPacket.callRequest ?? '';

      // Don't create an entry if there is no message and no callsign.
      if (message.isEmpty && callsign.isEmpty) return;

      if (message.isEmpty && locationRequest.isNotEmpty) {
        message = 'Location request: $locationRequest';
      } else if (message.isEmpty && callRequest.isNotEmpty) {
        message = 'Call request: $callRequest';
      } else if (message.isEmpty && callsign.isNotEmpty) {
        encoding = VoiceTextEncodingType.ident;
        message = '';
      }

      // Note: the Flutter BSS decoder exposes the raw location bytes only, so
      // latitude/longitude are not extracted here (left at 0).
      if (message.isNotEmpty || encoding == VoiceTextEncodingType.ident) {
        _addDataPacketEntry(
          deviceId: deviceId,
          text: message,
          channel: frame.channelName,
          time: frame.time,
          encoding: encoding,
          source: bssPacket.callsign,
          destination: bssPacket.destination,
        );
      }
      return;
    }

    // Decode the frame as AX.25.
    final ax25Packet = AX25Packet.decode(frame);
    if (ax25Packet == null) return;

    // Only process U_FRAME_UI or U_FRAME (unnumbered information frames).
    if (ax25Packet.type != FrameType.uFrameUi &&
        ax25Packet.type != FrameType.uFrame) {
      return;
    }

    // Extract source and destination from the AX.25 packet.
    if (ax25Packet.addresses.length < 2) return;
    final destination = ax25Packet.addresses[0].callSignWithId;
    final source = ax25Packet.addresses[1].callSignWithId;

    // Try to interpret the AX.25 packet as an APRS packet.
    final aprsPacket = AprsPacket.parse(ax25Packet);
    if (aprsPacket != null) {
      final latitude = aprsPacket.position.coordinateSet.latitude.value;
      final longitude = aprsPacket.position.coordinateSet.longitude.value;

      if (aprsPacket.comment.isNotEmpty) {
        _addDataPacketEntry(
          deviceId: deviceId,
          text: aprsPacket.comment,
          channel: frame.channelName,
          time: frame.time,
          encoding: VoiceTextEncodingType.aprs,
          source: source,
          destination: null,
          latitude: latitude,
          longitude: longitude,
        );
        return;
      }

      if (aprsPacket.messageData.msgText.isNotEmpty) {
        _addDataPacketEntry(
          deviceId: deviceId,
          text: aprsPacket.messageData.msgText,
          channel: frame.channelName,
          time: frame.time,
          encoding: VoiceTextEncodingType.aprs,
          source: source,
          destination: aprsPacket.messageData.addressee,
          latitude: latitude,
          longitude: longitude,
        );
        return;
      }
    }

    // Fall back to a raw AX.25 entry.
    var messageText = ax25Packet.dataStr ?? '';
    final rawData = ax25Packet.data;
    if (messageText.isEmpty && rawData != null && rawData.isNotEmpty) {
      try {
        messageText = ascii.decode(rawData, allowInvalid: false);
      } catch (_) {
        messageText = '[Binary data]';
      }
    }

    _addDataPacketEntry(
      deviceId: deviceId,
      text: messageText,
      channel: frame.channelName,
      time: frame.time,
      encoding: VoiceTextEncodingType.ax25,
      source: source,
      destination: destination,
    );
  }

  /// Adds a data-packet entry (received or transmitted) to history, persists
  /// it and dispatches both the updated history and a TextReady event to the
  /// given radio [deviceId].
  void _addDataPacketEntry({
    required int deviceId,
    required String? text,
    required String channel,
    required DateTime time,
    required VoiceTextEncodingType encoding,
    bool isReceived = true,
    String? source,
    String? destination,
    double latitude = 0,
    double longitude = 0,
  }) {
    final entry = DecodedTextEntry(
      text: text,
      channel: channel,
      time: time,
      isReceived: isReceived,
      encoding: encoding,
      source: source,
      destination: destination,
      latitude: latitude,
      longitude: longitude,
    );
    _decodedTextHistory.add(entry);
    _trimHistory();
    unawaited(_saveVoiceTextHistory());
    _dispatchDecodedTextHistory();

    // Dispatch a TextReady event for the radio device. Unlike
    // _dispatchTextReady (which targets the enabled voice device), data
    // packets are surfaced regardless of whether the voice handler is enabled,
    // mirroring how recordings dispatch to their own device.
    if (deviceId <= 0) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'TextReady',
      data: <String, Object?>{
        'text': text,
        'channel': channel,
        'time': time.millisecondsSinceEpoch,
        'completed': true,
        'isReceived': isReceived,
        'encoding': _encodingToString(encoding),
        'latitude': latitude,
        'longitude': longitude,
        'source': source,
        'destination': destination,
        'filename': null,
        'duration': 0,
      },
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // EchoLink text chat
  // ---------------------------------------------------------------------------

  /// Records an EchoLink text-chat message (sent or received) in the decoded
  /// text history so it persists across restarts, and surfaces it to the Comms
  /// tab. The actual send is performed by the EchoLink manager; this only owns
  /// the history entry.
  void _onEchoLinkChat(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! Map) return;
    final text = (data['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return;
    _addDataPacketEntry(
      deviceId: echoLinkDeviceId,
      text: text,
      channel: '',
      time: DateTime.now(),
      encoding: VoiceTextEncodingType.echolink,
      isReceived: data['isReceived'] as bool? ?? true,
      source: data['source'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // Chat (BSS) transmit
  // ---------------------------------------------------------------------------

  /// Handles the Chat command to transmit a BSS chat message on VFO A. Mirrors
  /// the C# `OnChat`. Dispatched on device 1 (uses the voice-enabled radio) or
  /// directly on a radio device (100+) which is used as-is.
  void _onChat(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! String) return;
    // EchoLink (device 200) has its own text-chat path handled by the EchoLink
    // manager; do not also send it as a radio BSS packet.
    if (deviceId == echoLinkDeviceId) return;
    final message = data;
    // Validate message length (must be between 1 and 254 characters).
    if (message.isEmpty || message.length >= 255) {
      _broker.logError(
        '[CommsHandler] Cannot send chat: message length must be between 1 '
        'and 254 characters (got ${message.length})',
      );
      return;
    }

    // Determine the target radio device for transmission.
    int transmitDeviceId;
    if (deviceId == 1) {
      transmitDeviceId = _targetDeviceId;
      if (transmitDeviceId <= 0) {
        _broker.logError('[CommsHandler] Cannot send chat: no radio selected');
        return;
      }
    } else if (deviceId >= 100) {
      transmitDeviceId = deviceId;
    } else {
      return;
    }

    // Resolve our callsign from settings (device 0).
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    if (callsign.isEmpty) {
      _broker.logError(
        '[CommsHandler] Cannot send chat: callsign not configured',
      );
      return;
    }

    // Resolve the VFO A channel name for the history entry.
    final channelName = _getVfoAChannelName(transmitDeviceId);

    _broker.logInfo(
      '[CommsHandler] Sending chat on device $transmitDeviceId: '
      '$callsign: $message',
    );

    // Build the BSS packet (location is not currently encoded).
    final bssPacket = BSSPacket.create(callsign: callsign, message: message);

    // Add to history as a transmitted BSS entry and echo it to the radio's
    // device so the voice panel shows it immediately.
    _addDataPacketEntry(
      deviceId: transmitDeviceId,
      text: message,
      channel: channelName,
      time: DateTime.now(),
      encoding: VoiceTextEncodingType.bss,
      isReceived: false,
      source: callsign,
    );

    // Dispatch the packet to the radio for transmission. channelId -1 makes the
    // radio transmit on the current VFO A channel using its internal modem.
    _broker.dispatch(
      deviceId: transmitDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        bssPacket: bssPacket,
        channelId: -1,
        regionId: -1,
      ),
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Morse transmit
  // ---------------------------------------------------------------------------

  /// Handles the Morse command to generate and transmit Morse code. Mirrors the
  /// C# `OnMorse`. Dispatched on device 1 (uses the voice-enabled radio) or
  /// directly on a radio device (100+) which is used as-is.
  void _onMorse(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! String) return;
    final textToMorse = data;
    if (textToMorse.isEmpty) return;

    // Determine the target radio device for transmission.
    int transmitDeviceId;
    if (deviceId == 1) {
      transmitDeviceId = _targetDeviceId;
      if (transmitDeviceId <= 0) {
        _broker.logError(
          '[CommsHandler] Cannot transmit morse: no radio is voice-enabled',
        );
        return;
      }
    } else if (deviceId >= 100) {
      transmitDeviceId = deviceId;
    } else {
      return;
    }

    try {
      final channelName = _getVfoAChannelName(transmitDeviceId);

      _broker.logInfo(
        '[CommsHandler] Generating morse code on device $transmitDeviceId: '
        '$textToMorse',
      );

      // Generate morse code PCM (8-bit unsigned, 32 kHz).
      final morsePcm8bit = MorseCodeEngine.generateMorsePcm(textToMorse);
      if (morsePcm8bit.isEmpty) {
        _broker.logError('[CommsHandler] Failed to generate morse code PCM');
        return;
      }

      // Add to history as a transmitted morse entry and echo it to the radio's
      // device so the voice panel shows it immediately.
      _addDataPacketEntry(
        deviceId: transmitDeviceId,
        text: textToMorse,
        channel: channelName,
        time: DateTime.now(),
        encoding: VoiceTextEncodingType.morse,
        isReceived: false,
      );

      // Convert 8-bit unsigned PCM (center 128) to 16-bit signed PCM (center 0).
      final pcm16 = _pcm8ToPcm16(morsePcm8bit);

      // Send PCM to the radio for transmission. PlayLocally=true lets the user
      // hear the morse output locally.
      _broker.dispatch(
        deviceId: transmitDeviceId,
        name: 'TransmitVoicePCM',
        data: <String, Object?>{'data': pcm16, 'playLocally': true},
        store: false,
      );
      _broker.logInfo(
        '[CommsHandler] Transmitted ${pcm16.length} bytes of morse PCM to '
        'device $transmitDeviceId',
      );
    } catch (e) {
      _broker.logError('[CommsHandler] Error generating morse code: $e');
    }
  }

  /// Converts 8-bit unsigned PCM (0-255, center 128) to little-endian 16-bit
  /// signed PCM (center 0).
  static Uint8List _pcm8ToPcm16(Uint8List pcm8) {
    final pcm16 = Uint8List(pcm8.length * 2);
    for (int i = 0; i < pcm8.length; i++) {
      final int s = (pcm8[i] - 128) * 256;
      pcm16[i * 2] = s & 0xFF;
      pcm16[i * 2 + 1] = (s >> 8) & 0xFF;
    }
    return pcm16;
  }

  // ---------------------------------------------------------------------------
  // Text-to-speech transmit
  // ---------------------------------------------------------------------------

  /// Handles the Speak command: synthesizes [data] to speech, converts it to
  /// 32 kHz / mono / 16-bit PCM and transmits it through the radio audio path.
  /// Mirrors the target-resolution logic of [_onMorse]: dispatched on device 1
  /// (uses the voice-enabled radio) or directly on a radio device (100+).
  Future<void> _onSpeak(int deviceId, String name, Object? data) async {
    if (_disposed) return;
    if (data is! String) return;
    final textToSpeak = data.trim();
    if (textToSpeak.isEmpty) return;

    // Determine the target radio device for transmission.
    int transmitDeviceId;
    if (deviceId == 1) {
      transmitDeviceId = _targetDeviceId;
      if (transmitDeviceId <= 0) {
        _broker.logError(
          '[CommsHandler] Cannot speak: no radio is voice-enabled',
        );
        return;
      }
    } else if (deviceId >= 100) {
      transmitDeviceId = deviceId;
    } else {
      return;
    }

    try {
      final channelName = _getVfoAChannelName(transmitDeviceId);

      _broker.logInfo(
        '[CommsHandler] Synthesizing speech on device $transmitDeviceId: '
        '$textToSpeak',
      );

      // Read text-to-speech settings (device 0 = settings).
      final voiceJson = _broker.getValue<String>(0, 'Voice', '') ?? '';
      final rate = _broker.getValue<double>(0, 'VoiceSpeechRate', 0.5) ?? 0.5;
      final pitch = _broker.getValue<double>(0, 'VoicePitch', 1.0) ?? 1.0;

      final pcm16 = await TtsService.instance.synthesizeToPcm(
        textToSpeak,
        voiceJson: voiceJson.isEmpty ? null : voiceJson,
        rate: rate,
        pitch: pitch,
      );

      if (_disposed) return;
      if (pcm16 == null || pcm16.isEmpty) {
        _broker.logError(
          '[CommsHandler] Failed to synthesize speech (no audio produced)',
        );
        return;
      }

      // Add to history as a transmitted voice entry and echo it to the radio's
      // device so the voice panel shows it immediately.
      _addDataPacketEntry(
        deviceId: transmitDeviceId,
        text: textToSpeak,
        channel: channelName,
        time: DateTime.now(),
        encoding: VoiceTextEncodingType.voice,
        isReceived: false,
      );

      // Send PCM to the radio for transmission. PlayLocally=true lets the user
      // hear the spoken output locally.
      _broker.dispatch(
        deviceId: transmitDeviceId,
        name: 'TransmitVoicePCM',
        data: <String, Object?>{'data': pcm16, 'playLocally': true},
        store: false,
      );
      _broker.logInfo(
        '[CommsHandler] Transmitted ${pcm16.length} bytes of speech PCM to '
        'device $transmitDeviceId',
      );
    } catch (e) {
      _broker.logError('[CommsHandler] Error synthesizing speech: $e');
    }
  }

  /// Resolves the VFO A channel name for a radio device from the broker
  /// `Settings` (channelA id) and `Channels` (list of channel maps). Returns an
  /// empty string when the channel information is not yet available.
  String _getVfoAChannelName(int deviceId) {
    final settings = _broker.getValueDynamic(deviceId, 'Settings');
    if (settings is! Map) return '';
    final channelA = settings['channelA'];
    if (channelA is! int) return '';

    final channels = _broker.getValueDynamic(deviceId, 'Channels');
    if (channels is! List) return '';
    for (final channel in channels) {
      if (channel is Map && channel['channelId'] == channelA) {
        final channelName = channel['name'];
        if (channelName is String && channelName.isNotEmpty) {
          return channelName;
        }
      }
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<File?> _resolveHistoryFile() async {
    if (_historyFile != null) return _historyFile;
    // The web build has no file-system access through path_provider, so the
    // decoded-text history is kept in memory only.
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      _historyFile = File(
        '${dir.path}${Platform.pathSeparator}$_voiceTextFileName',
      );
      return _historyFile;
    } catch (e) {
      _broker.logError('[CommsHandler] Failed to resolve history file: $e');
      return null;
    }
  }

  Future<void> _loadVoiceTextHistory() async {
    try {
      final file = await _resolveHistoryFile();
      if (file != null && await file.exists()) {
        final json = await file.readAsString();
        if (json.trim().isNotEmpty) {
          final decoded = jsonDecode(json);
          if (decoded is List) {
            _decodedTextHistory
              ..clear()
              ..addAll(
                decoded.whereType<Map<String, dynamic>>().map(
                  DecodedTextEntry.fromJson,
                ),
              );
            _trimHistory();
          }
        }
      }
    } catch (e) {
      // Ignore load errors - start with empty history.
      _broker.logError('[CommsHandler] Failed to load history: $e');
    }

    _voiceTextHistoryLoaded = true;
    _dispatchDecodedTextHistory();
    _dispatchVoiceTextHistoryLoaded();
  }

  Future<void> _saveVoiceTextHistory() async {
    try {
      final file = await _resolveHistoryFile();
      if (file == null) return;
      final list = _decodedTextHistory
          .map((e) => e.toJson())
          .toList(growable: false);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(list),
      );
    } catch (e) {
      // Ignore save errors.
      _broker.logError('[CommsHandler] Failed to save history: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Broker event dispatch
  // ---------------------------------------------------------------------------

  void _dispatchDecodedTextHistory() {
    final historyCopy = _decodedTextHistory
        .map((e) => e.toJson())
        .toList(growable: false);
    _broker.dispatch(
      deviceId: 1,
      name: 'DecodedTextHistory',
      data: historyCopy,
      store: true,
    );
  }

  void _dispatchCurrentEntry() {
    final entry = _currentEntry;
    _broker.dispatch(
      deviceId: 1,
      name: 'CurrentDecodedTextEntry',
      data: entry == null
          ? null
          : <String, Object?>{
              'text': entry.text,
              'channel': entry.channel,
              'time': entry.time.millisecondsSinceEpoch,
            },
      store: true,
    );
  }

  void _dispatchVoiceTextHistoryLoaded() {
    _broker.dispatch(
      deviceId: 1,
      name: 'VoiceTextHistoryLoaded',
      data: _voiceTextHistoryLoaded,
      store: true,
    );
  }

  void _dispatchTextReady(
    String? text,
    String? channel,
    DateTime time,
    bool completed, {
    bool isReceived = true,
    VoiceTextEncodingType encoding = VoiceTextEncodingType.voice,
    double latitude = 0,
    double longitude = 0,
    String? source,
    String? destination,
    String? filename,
    int duration = 0,
  }) {
    if (_targetDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _targetDeviceId,
      name: 'TextReady',
      data: <String, Object?>{
        'text': text,
        'channel': channel,
        'time': time.millisecondsSinceEpoch,
        'completed': completed,
        'isReceived': isReceived,
        'encoding': _encodingToString(encoding),
        'latitude': latitude,
        'longitude': longitude,
        'source': source,
        'destination': destination,
        'filename': filename,
        'duration': duration,
      },
      store: false,
    );
  }

  // ignore: unused_element
  void _dispatchProcessingVoice(bool listening, bool processing) {
    if (_targetDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _targetDeviceId,
      name: 'ProcessingVoice',
      data: <String, Object?>{'listening': listening, 'processing': processing},
      store: false,
    );
  }

  void _dispatchCommsHandlerState() {
    _broker.dispatch(
      deviceId: 1,
      name: 'CommsHandlerState',
      data: <String, Object?>{
        'enabled': _enabled,
        'targetDeviceId': _targetDeviceId,
        'language': _voiceLanguage,
        'model': _voiceModel,
        'engineReady': _sttReady,
      },
      store: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Disposes the handler and releases broker subscriptions.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _txRecordTimer?.cancel();
    if (_recorder != null) _finalizeRecording();
    _cleanupSstvMonitor();
    unawaited(_cleanupSpeechEngine());
    if (_enabled) disable();
    _broker.logInfo('[CommsHandler] Voice Handler disposing');
    _broker.dispose();
  }
}

/// Minimal incremental WAV (PCM 16-bit mono) writer for recorded audio clips.
/// Writes a 44-byte header up front and patches the size fields on close.
class _WavClipRecorder {
  final RandomAccessFile _raf;
  final int _sampleRate;
  int _dataBytes = 0;

  _WavClipRecorder._(this._raf, this._sampleRate) {
    _raf.writeFromSync(_header(0, _sampleRate));
  }

  int get dataBytes => _dataBytes;

  static _WavClipRecorder? open(String path, int sampleRate) {
    try {
      final raf = File(path).openSync(mode: FileMode.write);
      return _WavClipRecorder._(raf, sampleRate);
    } catch (e) {
      return null;
    }
  }

  void write(Uint8List bytes, int offset, int length) {
    try {
      if (offset == 0 && length == bytes.length) {
        _raf.writeFromSync(bytes);
      } else {
        _raf.writeFromSync(bytes, offset, offset + length);
      }
      _dataBytes += length;
    } catch (_) {}
  }

  void close() {
    try {
      // Patch the RIFF/data sizes now that the total length is known.
      _raf.setPositionSync(0);
      _raf.writeFromSync(_header(_dataBytes, _sampleRate));
      _raf.closeSync();
    } catch (_) {}
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
