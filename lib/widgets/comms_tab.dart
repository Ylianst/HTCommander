import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'chat_widget.dart';
import '../dialogs/image_view_dialog.dart';
import '../dialogs/recording_playback_dialog.dart';
import '../dialogs/sstv_send_dialog.dart';
import '../sstv/encoder.dart';
import '../radio/dtmf_engine.dart';
import '../services/window_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/microphone_capture.dart';

/// Voice transmit mode
enum VoiceTransmitMode { chat, speak, morse, dtmf, ptt }

/// Voice tab - audio communication controls
class CommsTab extends StatefulWidget {
  const CommsTab({super.key});

  @override
  State<CommsTab> createState() => _CommsTabState();
}

class _CommsTabState extends State<CommsTab>
    with AutomaticKeepAliveClientMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final DataBrokerClient _broker = DataBrokerClient();

  /// Sentinel id used for the single in-progress (partial) decoded entry so it
  /// can be replaced as more text arrives and finalized when completed.
  static const String _partialMessageId = '__voice_partial__';

  int _currentRadioDeviceId = -1;
  VoiceTransmitMode _currentMode = VoiceTransmitMode.chat;
  bool _audioEnabled = false;
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isTransmitting = false;
  bool _speechToTextEnabled = true;
  bool _recordAudio = false;
  bool _allowTransmit = true;

  /// Live microphone capture used by the push-to-talk (PTT) mode.
  MicrophoneCapture? _micCapture;

  /// Linear microphone gain applied to transmitted PTT audio. Shared with the
  /// Audio tab via DataBroker device 0 ('MicrophoneGain').
  double _micGain = 1.0;

  /// True while the PTT button is held down and the microphone is streaming.
  bool _pttActive = false;

  /// True while microphone capture is being started, to avoid double-starts.
  bool _pttStarting = false;

  /// Absolute path to the application-support directory, resolved on init. Used
  /// to locate decoded SSTV pictures saved by the voice handler.
  String? _appSupportPath;

  /// True while a file is being dragged over the chat area.
  bool _dragOver = false;

  @override
  bool get wantKeepAlive => true;

  /// Whether the radio's audio channel is available on this platform. Web and
  /// iOS talk to the radio over the BLE control channel only (no audio
  /// channel), so the Voice tab is restricted to data-only "Chat" mode: the
  /// Enable button and the audio transmit modes (PTT/Speak/Morse/DTMF) plus the
  /// speech-to-text, recording and SSTV/audio send features are hidden.
  bool get _audioChannelSupported => !kIsWeb && !Platform.isIOS;

  @override
  void initState() {
    super.initState();

    // Decoded/transmitted text, processing and transmit state (all devices).
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'ProcessingVoice',
      callback: _onProcessingVoice,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'TextReady',
      callback: _onTextReady,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'VoiceTransmitStateChanged',
      callback: _onVoiceTransmitStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioState',
      callback: _onAudioStateChanged,
    );

    // Global voice handler state and history events (device 1).
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'SelectedRadioDeviceId',
      callback: _onSelectedRadioChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'VoiceTextCleared',
      callback: _onVoiceTextCleared,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'VoiceTextHistoryLoaded',
      callback: _onVoiceTextHistoryLoaded,
    );

    // Persisted settings (device 0).
    _broker.subscribe(
      deviceId: 0,
      name: 'AllowTransmit',
      callback: _onAllowTransmitChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'SpeechToTextEnabled',
      callback: _onSpeechToTextEnabledChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'RecordingState',
      callback: _onRecordingStateChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MicrophoneGain',
      callback: _onMicGainChanged,
    );

    // Initialize from current broker values.
    _currentRadioDeviceId = _resolveCurrentRadioId();
    _currentMode = _modeFromName(
      _broker.getValue<String>(0, 'VoiceTransmitMode', null),
    );
    // Web and iOS have no audio channel, so only the data-only "Chat" mode
    // (which uses the radio's internal modem over the control channel) is
    // available. Force it regardless of any previously stored mode.
    if (!_audioChannelSupported) _currentMode = VoiceTransmitMode.chat;
    _allowTransmit = (_broker.getValue<int>(0, 'AllowTransmit', 1) ?? 1) != 0;
    _speechToTextEnabled =
        _broker.getValue<bool>(0, 'SpeechToTextEnabled', true) ?? true;
    _recordAudio = _broker.getValue<bool>(0, 'RecordingState', false) ?? false;
    _micGain = (_broker.getValue<double>(0, 'MicrophoneGain', 1.0) ?? 1.0)
        .clamp(1.0, 8.0);
    _audioEnabled = _readAudioState();
    _loadDecodedTextHistory();

    // Resolve the application-support path so decoded SSTV pictures can be
    // shown inline; reload history once it is known to attach image paths.
    _resolveAppSupportPath();

    // If the restored mode is PTT and a radio is ready, warm up the microphone.
    _updatePttMic();
  }

  /// Resolves the application-support directory path and re-attaches SSTV image
  /// paths to any already-loaded history entries.
  Future<void> _resolveAppSupportPath() async {
    if (kIsWeb) return;
    try {
      final base = await getApplicationSupportDirectory();
      if (!mounted) return;
      _appSupportPath = base.path;
      _loadDecodedTextHistory();
    } catch (_) {
      // Image previews simply won't be shown if the path can't be resolved.
    }
  }

  /// Builds the absolute path of a decoded SSTV picture, or null when the
  /// entry is not a picture or the support path is not yet known.
  String? _sstvImagePath(String encoding, String? filename) {
    if (encoding != 'Picture' || filename == null || filename.isEmpty) {
      return null;
    }
    final base = _appSupportPath;
    if (base == null) return null;
    return '$base${Platform.pathSeparator}SSTV${Platform.pathSeparator}$filename';
  }

  // ---------------------------------------------------------------------------
  // SSTV image transmission
  // ---------------------------------------------------------------------------

  /// Supported image file extensions for SSTV transmission (lowercase, no dot).
  static const Set<String> _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'bmp',
    'gif',
    'tif',
    'tiff',
    'ico',
    'webp',
  };

  /// Whether image/audio media may be sent right now (audio active and not
  /// already transmitting).
  bool get _canSendMedia => _audioEnabled && !_isTransmitting;

  bool _isImageFile(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Handles files dropped onto the chat area. A single image file is sent via
  /// SSTV; a single WAV file is converted and transmitted as audio. Everything
  /// else is ignored.
  void _onFilesDropped(DropDoneDetails details) {
    if (_dragOver) setState(() => _dragOver = false);
    if (!_canSendMedia) return;
    final files = details.files;
    if (files.length != 1) return;
    final path = files.first.path;
    if (_isImageFile(path)) {
      _loadAndSendImage(path);
    } else if (_isWavFile(path)) {
      _loadAndSendWav(path);
    }
  }

  /// Opens a file picker to choose an image, then shows the SSTV send dialog.
  Future<void> _pickAndSendImage() async {
    if (!_canSendMedia) return;
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Image for SSTV',
      type: FileType.custom,
      allowedExtensions: _imageExtensions.toList(),
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || !_isImageFile(path)) return;
    await _loadAndSendImage(path);
  }

  /// Decodes the image at [path] and presents the SSTV send dialog.
  Future<void> _loadAndSendImage(String path) async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    ui.Image image;
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to load image: $e')),
      );
      return;
    }
    if (!mounted) {
      image.dispose();
      return;
    }

    final result = await showDialog<SstvSendResult>(
      context: context,
      builder: (context) => SstvSendDialog(
        sourceImage: image,
        sourceName: path.split(Platform.pathSeparator).last,
      ),
    );
    image.dispose();
    if (result == null || !mounted) return;
    await _transmitSstv(result);
  }

  /// Saves the scaled image, records the transmission in history and sends the
  /// encoded SSTV audio to the radio.
  Future<void> _transmitSstv(SstvSendResult result) async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0 || !_isCurrentRadioConnected) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No radio is connected for voice transmission.'),
        ),
      );
      return;
    }

    // Save the scaled image to the SSTV application folder.
    String? filename;
    try {
      if (kIsWeb) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('SSTV image save/transmit is not available on web.'),
          ),
        );
        return;
      }
      final base =
          _appSupportPath ?? (await getApplicationSupportDirectory()).path;
      _appSupportPath = base;
      final dir = Directory('$base${Platform.pathSeparator}SSTV');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final now = DateTime.now();
      final safeMode = result.modeName
          .replaceAll(' ', '_')
          .replaceAll('\u2013', '-');
      filename = 'SSTV_${_formatDate(now)}_${_formatTime(now)}_$safeMode.png';
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      await file.writeAsBytes(result.pngBytes);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to save image: $e')),
      );
      return;
    }

    // Notify the voice handler to record the picture transmission in history.
    _broker.dispatch(
      deviceId: deviceId,
      name: 'PictureTransmitted',
      data: <String, Object?>{
        'modeName': result.modeName,
        'filename': filename,
      },
      store: false,
    );

    // Encode to PCM on a background isolate to keep the UI responsive.
    Uint8List pcm;
    try {
      pcm = await compute(_encodeSstvPcm, <String, Object?>{
        'pixels': result.pixels,
        'width': result.width,
        'height': result.height,
        'modeName': result.modeName,
        'sampleRate': 32000,
      });
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to encode SSTV audio: $e')),
      );
      return;
    }

    // Send the PCM data to the radio for transmission.
    _broker.dispatch(
      deviceId: deviceId,
      name: 'TransmitVoicePCM',
      data: <String, Object?>{'data': pcm, 'playLocally': false},
      store: false,
    );
  }

  bool _isWavFile(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return path.substring(dot + 1).toLowerCase() == 'wav';
  }

  /// Opens a file picker to choose a WAV file, then converts and sends it.
  Future<void> _pickAndSendAudio() async {
    if (!_canSendMedia) return;
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select WAV Audio',
      type: FileType.custom,
      allowedExtensions: const ['wav'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || !_isWavFile(path)) return;
    await _loadAndSendWav(path);
  }

  /// Reads the WAV file at [path], converts it to 32000 Hz mono 16-bit PCM and
  /// sends it to the radio for transmission.
  Future<void> _loadAndSendWav(String path) async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0 || !_isCurrentRadioConnected) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No radio is connected for voice transmission.'),
        ),
      );
      return;
    }

    Uint8List pcm;
    try {
      final bytes = await File(path).readAsBytes();
      // Decode + resample on a background isolate to keep the UI responsive.
      pcm = await compute(_decodeWavToPcm32k, bytes);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to load audio: $e')),
      );
      return;
    }
    if (pcm.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Unsupported or empty WAV file.')),
      );
      return;
    }
    if (!mounted) return;

    // Send the PCM data to the radio for transmission.
    _broker.dispatch(
      deviceId: deviceId,
      name: 'TransmitVoicePCM',
      data: <String, Object?>{'data': pcm, 'playLocally': false},
      store: false,
    );
  }

  static String _formatDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
  }

  @override
  void dispose() {
    _micCapture?.dispose();
    _broker.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  /// Resolve the device ID of the radio shown in the Radio Panel.
  /// Prefers the explicitly selected radio, falling back to the first connected one.
  int _resolveCurrentRadioId() {
    final connected = DataBroker.getValueDynamic(1, 'ConnectedRadios');
    final connectedIds = _radioIds(connected);
    final selected =
        DataBroker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;
    if (selected > 0 && connectedIds.contains(selected)) return selected;
    return connectedIds.isNotEmpty ? connectedIds.first : -1;
  }

  /// Extract all connected radio device IDs from a ConnectedRadios list.
  List<int> _radioIds(Object? data) {
    final ids = <int>[];
    if (data is List) {
      for (final radio in data) {
        if (radio is Map && radio['DeviceId'] != null) {
          ids.add(radio['DeviceId'] as int);
        }
      }
    }
    return ids;
  }

  /// Whether the radio currently shown in the Radio Panel is connected.
  bool get _isCurrentRadioConnected {
    if (_currentRadioDeviceId <= 0) return false;
    final connected = _radioIds(
      DataBroker.getValueDynamic(1, 'ConnectedRadios'),
    );
    return connected.contains(_currentRadioDeviceId);
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    setState(() {
      _currentRadioDeviceId = _resolveCurrentRadioId();
      _audioEnabled = _readAudioState();
    });
    _updatePttMic();
  }

  void _onSelectedRadioChanged(int deviceId, String name, Object? data) {
    if (data is! int) return;
    setState(() {
      _currentRadioDeviceId = data;
      _audioEnabled = _readAudioState();
    });
    _updatePttMic();
  }

  /// Reads the current AudioState of the radio shown in the Radio Panel.
  bool _readAudioState() {
    if (_currentRadioDeviceId <= 0) return false;
    return _broker.getValue<bool>(_currentRadioDeviceId, 'AudioState', false) ??
        false;
  }

  // ---------------------------------------------------------------------------
  // Audio channel / processing / transmit
  // ---------------------------------------------------------------------------

  void _onAudioStateChanged(int deviceId, String name, Object? data) {
    if (deviceId != _currentRadioDeviceId) return;
    if (data is bool) {
      setState(() => _audioEnabled = data);
      _updatePttMic();
    }
  }

  void _onProcessingVoice(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    setState(() {
      _isListening = data['listening'] as bool? ?? false;
      _isProcessing = data['processing'] as bool? ?? false;
    });
  }

  void _onVoiceTransmitStateChanged(int deviceId, String name, Object? data) {
    if (data is bool) setState(() => _isTransmitting = data);
  }

  void _onAllowTransmitChanged(int deviceId, String name, Object? data) {
    final int v = data is int ? data : int.tryParse('$data') ?? 1;
    setState(() => _allowTransmit = v != 0);
    _updatePttMic();
  }

  void _onSpeechToTextEnabledChanged(int deviceId, String name, Object? data) {
    if (data is bool) setState(() => _speechToTextEnabled = data);
  }

  void _onRecordingStateChanged(int deviceId, String name, Object? data) {
    if (data is bool) setState(() => _recordAudio = data);
  }

  void _onMicGainChanged(int deviceId, String name, Object? data) {
    final double? gain = data is double
        ? data
        : (data is int ? data.toDouble() : null);
    if (gain == null) return;
    _micGain = gain.clamp(1.0, 8.0);
    // Apply live so an in-progress PTT transmission picks up the new gain.
    _micCapture?.gain = _micGain;
  }

  // ---------------------------------------------------------------------------
  // Decoded text history
  // ---------------------------------------------------------------------------

  void _onVoiceTextCleared(int deviceId, String name, Object? data) {
    setState(() => _messages.clear());
  }

  void _onVoiceTextHistoryLoaded(int deviceId, String name, Object? data) {
    // Only (re)load if we have nothing yet, to avoid duplicating entries.
    if (_messages.isEmpty) _loadDecodedTextHistory();
  }

  /// Handles a TextReady event by appending (or updating) a history entry.
  void _onTextReady(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final text = data['text'] as String?;
    final encoding = data['encoding'] as String? ?? 'Voice';
    final allowEmpty =
        encoding == 'Recording' || encoding == 'Picture' || encoding == 'Ident';
    if ((text == null || text.isEmpty) && !allowEmpty) return;

    _appendVoiceHistory(
      text: text ?? '',
      channel: data['channel'] as String? ?? '',
      time: _parseTime(data['time']),
      completed: data['completed'] as bool? ?? false,
      isReceived: data['isReceived'] as bool? ?? true,
      encoding: encoding,
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      source: data['source'] as String?,
      destination: data['destination'] as String?,
      duration: data['duration'] as int? ?? 0,
      filename: data['filename'] as String?,
    );
  }

  /// Appends a completed entry, or updates the single in-progress entry.
  void _appendVoiceHistory({
    required String text,
    required String channel,
    required DateTime time,
    required bool completed,
    required bool isReceived,
    required String encoding,
    double latitude = 0,
    double longitude = 0,
    String? source,
    String? destination,
    int duration = 0,
    String? filename,
  }) {
    final hasLocation = latitude != 0 || longitude != 0;
    final message = ChatMessage(
      id: completed
          ? '${time.millisecondsSinceEpoch}_${_messages.length}'
          : _partialMessageId,
      route: _formatRoute(
        channel,
        encoding,
        source: source,
        destination: destination,
        duration: duration,
      ),
      senderCallsign: source ?? '',
      message: text,
      time: time,
      isSender: !isReceived,
      latitude: hasLocation ? latitude : null,
      longitude: hasLocation ? longitude : null,
      icon: _iconForEncoding(encoding),
      filename: filename,
      imagePath: _sstvImagePath(encoding, filename),
    );
    setState(() {
      _messages.removeWhere((m) => m.id == _partialMessageId);
      _messages.add(message);
    });
  }

  /// Loads the persisted decoded text history (and any in-progress entry) from
  /// the Data Broker into the message list.
  void _loadDecodedTextHistory() {
    final loaded = <ChatMessage>[];

    final history = DataBroker.getValueDynamic(1, 'DecodedTextHistory');
    if (history is List) {
      for (final raw in history) {
        if (raw is! Map) continue;
        final entry = _entryToMessage(
          raw,
          completed: true,
          index: loaded.length,
        );
        if (entry != null) loaded.add(entry);
      }
    }

    final current = DataBroker.getValueDynamic(1, 'CurrentDecodedTextEntry');
    if (current is Map) {
      final entry = _entryToMessage(
        current,
        completed: false,
        index: loaded.length,
      );
      if (entry != null) loaded.add(entry);
    }

    setState(() {
      _messages
        ..clear()
        ..addAll(loaded);
    });
  }

  /// Converts a stored history entry map into a [ChatMessage], or null if it
  /// should be skipped (empty text for a textual encoding).
  ChatMessage? _entryToMessage(
    Map raw, {
    required bool completed,
    required int index,
  }) {
    final text = (raw['text'] as String?)?.trim() ?? '';
    final encoding = raw['encoding'] as String? ?? 'Voice';
    if (text.isEmpty && encoding != 'Recording' && encoding != 'Ident') {
      return null;
    }
    final channel = raw['channel'] as String? ?? '';
    final isReceived = raw['isReceived'] as bool? ?? true;
    final source = raw['source'] as String?;
    final destination = raw['destination'] as String?;
    final duration = raw['duration'] as int? ?? 0;
    final latitude = (raw['latitude'] as num?)?.toDouble() ?? 0;
    final longitude = (raw['longitude'] as num?)?.toDouble() ?? 0;
    final time = _parseTime(raw['time']);
    final hasLocation = latitude != 0 || longitude != 0;
    final filename = raw['filename'] as String?;

    return ChatMessage(
      id: completed
          ? '${time.millisecondsSinceEpoch}_$index'
          : _partialMessageId,
      route: _formatRoute(
        channel,
        encoding,
        source: source,
        destination: destination,
        duration: duration,
      ),
      senderCallsign: source ?? '',
      message: text,
      time: time,
      isSender: !isReceived,
      latitude: hasLocation ? latitude : null,
      longitude: hasLocation ? longitude : null,
      icon: _iconForEncoding(encoding),
      filename: filename,
      imagePath: _sstvImagePath(encoding, filename),
    );
  }

  DateTime _parseTime(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  /// Builds the route/header string for a history entry (mirrors the C# FormatRoute).
  String _formatRoute(
    String channel,
    String encoding, {
    String? source,
    String? destination,
    int duration = 0,
  }) {
    var encodingStr = _encodingDisplayName(encoding);
    if (encoding == 'Recording') {
      encodingStr = duration > 0
          ? 'Recording ${_formatDuration(duration)}'
          : 'Recording';
      // Recordings show the channel name after the duration, e.g.
      // "Recording 10s - MyHomeChannel".
      return channel.isNotEmpty ? '$encodingStr - $channel' : encodingStr;
    }
    var callsignPart = '';
    if (source != null && source.isNotEmpty) {
      callsignPart = (destination != null && destination.isNotEmpty)
          ? ' $source > $destination'
          : ' $source';
    }
    if (channel.isEmpty) return '$encodingStr$callsignPart';
    if (encoding == 'Ident') callsignPart = '$callsignPart ⚑';
    return '[$channel] $encodingStr$callsignPart';
  }

  String _encodingDisplayName(String encoding) {
    switch (encoding) {
      case 'VoiceClip':
        return 'Clip';
      case 'AX25':
        return 'AX.25';
      case 'BSS':
        return 'Chat';
      case 'Picture':
        return 'SSTV';
      default:
        return encoding;
    }
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) return '${totalSeconds}s';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  }

  IconData? _iconForEncoding(String encoding) {
    switch (encoding) {
      case 'Recording':
        return Icons.play_circle;
      case 'Picture':
        return Icons.image;
      default:
        return null;
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (!_canSend) {
      _showSendDisabledHint();
      return;
    }

    switch (_currentMode) {
      case VoiceTransmitMode.chat:
        // Chat uses the radio's internal modem, so send directly to the
        // connected radio device (works even when audio is not enabled).
        _broker.dispatch(
          deviceId: _currentRadioDeviceId,
          name: 'Chat',
          data: text,
          store: false,
        );
        break;
      case VoiceTransmitMode.speak:
        // The voice handler synthesizes the speech PCM and transmits it.
        // Dispatch to the connected radio device (100+) directly, because the
        // voice handler is never "enabled" in this build so it has no target
        // radio of its own (same as Morse).
        _broker.dispatch(
          deviceId: _currentRadioDeviceId,
          name: 'Speak',
          data: text,
          store: false,
        );
        break;
      case VoiceTransmitMode.morse:
        // The voice handler generates the Morse tone PCM and transmits it.
        // Dispatch to the connected radio device (100+) directly, because the
        // voice handler is never "enabled" in this build so it has no target
        // radio of its own.
        _broker.dispatch(
          deviceId: _currentRadioDeviceId,
          name: 'Morse',
          data: text,
          store: false,
        );
        break;
      case VoiceTransmitMode.dtmf:
        _sendDtmf(text);
        break;
      case VoiceTransmitMode.ptt:
        // PTT has no text input; transmission is handled by the hold button.
        break;
    }

    _messageController.clear();
  }

  /// Shows a brief hint explaining why a message can't be sent in the current
  /// mode, so pressing Send is never silently ignored.
  void _showSendDisabledHint() {
    if (!mounted) return;
    final String message;
    if (_isTransmitting) {
      message = 'Please wait for the current transmission to finish.';
    } else if (_currentMode == VoiceTransmitMode.chat) {
      message = 'Connect a radio before sending a chat message.';
    } else {
      message = 'Enable audio (the Enable button) before sending in this mode.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// Generates DTMF dual-tone PCM for [digits] locally and transmits it to the
  /// connected radio. Mirrors the C# DMTF case in `VoiceTabUserControl`.
  void _sendDtmf(String digits) {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;

    // Generate 8-bit unsigned PCM, then convert to little-endian 16-bit signed.
    final pcm8 = DtmfEngine.generateDtmfPcm(digits);
    if (pcm8.isEmpty) return;
    final pcm16 = Uint8List(pcm8.length * 2);
    for (int i = 0; i < pcm8.length; i++) {
      final int s = (pcm8[i] - 128) << 8;
      pcm16[i * 2] = s & 0xFF;
      pcm16[i * 2 + 1] = (s >> 8) & 0xFF;
    }

    _broker.dispatch(
      deviceId: deviceId,
      name: 'TransmitVoicePCM',
      data: <String, Object?>{'data': pcm16, 'playLocally': true},
      store: false,
    );
  }

  /// Whether the input field and Send button should be enabled. In Chat mode
  /// the radio's internal modem is used, so a connected radio is sufficient;
  /// the other modes require the audio channel to be enabled.
  bool get _canSend {
    if (_isTransmitting) return false;
    if (_currentMode == VoiceTransmitMode.chat) {
      return _isCurrentRadioConnected;
    }
    return _audioEnabled;
  }

  // ---------------------------------------------------------------------------
  // PTT (push-to-talk) live microphone transmission
  // ---------------------------------------------------------------------------

  /// Whether push-to-talk can be used right now (audio channel enabled, a radio
  /// connected, the platform supports microphone capture, and no other
  /// transmission is in progress).
  bool get _canPtt =>
      _audioEnabled &&
      _isCurrentRadioConnected &&
      MicrophoneCapture.isSupported &&
      (!_isTransmitting || _pttActive);

  /// Whether the microphone should be kept warm: while PTT mode is selected and
  /// usable. Keeping it running avoids the audio-input warm-up latency on the
  /// first press, which would otherwise truncate (and discard) the first
  /// recording.
  bool get _shouldWarmPttMic =>
      _currentMode == VoiceTransmitMode.ptt &&
      _allowTransmit &&
      _audioEnabled &&
      _isCurrentRadioConnected &&
      MicrophoneCapture.isSupported;

  /// Starts or stops the warm microphone to match the current PTT state.
  void _updatePttMic() {
    if (_shouldWarmPttMic) {
      _startPttMic();
    } else {
      _stopPttMic();
    }
  }

  /// Starts (warms up) microphone capture so the first press transmits without
  /// the audio-input start-up delay. Audio is only forwarded to the radio while
  /// the PTT button is held (see [_onPttPcm]).
  Future<void> _startPttMic() async {
    if (!MicrophoneCapture.isSupported) return;
    final capture = _micCapture ??= MicrophoneCapture(sampleRate: 32000);
    capture.gain = _micGain;
    if (capture.isCapturing || _pttStarting) return;
    _pttStarting = true;
    final ok = await capture.start(_onPttPcm);
    _pttStarting = false;
    if (!mounted) {
      if (ok) await capture.stop();
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone unavailable. Grant access in System Settings > '
            'Privacy & Security > Microphone.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Stops the warm microphone (e.g. when leaving PTT mode or disconnecting).
  Future<void> _stopPttMic() async {
    if (_pttActive) {
      // End any in-progress transmission first.
      _pttActive = false;
      _releasePttHold();
    }
    await _micCapture?.stop();
  }

  /// Begins transmitting captured microphone audio. Called when the PTT button
  /// is pressed and held. The microphone is already warm in PTT mode, so the
  /// first chunk is sent without start-up latency.
  Future<void> _startPtt() async {
    if (_pttActive) return;
    if (!_canPtt) {
      _showPttDisabledHint();
      return;
    }
    // Ensure the microphone is running (normally already warm in PTT mode).
    await _startPttMic();
    if (!mounted || !(_micCapture?.isCapturing ?? false)) return;
    setState(() => _pttActive = true);
  }

  /// Stops transmitting (the button was released) while keeping the microphone
  /// warm for the next press.
  Future<void> _stopPtt() async {
    if (!_pttActive) return;
    _releasePttHold();
    if (mounted) {
      setState(() => _pttActive = false);
    } else {
      _pttActive = false;
    }
  }

  /// Releases the radio transmission hold so the radio finalizes the single
  /// audio run once any remaining queued PCM has been sent.
  void _releasePttHold() {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'TransmitVoicePCM',
      data: <String, Object?>{'hold': false},
      store: false,
    );
  }

  /// Streams a chunk of captured 32 kHz / 16-bit / mono microphone PCM to the
  /// radio. The microphone runs continuously while in PTT mode, but audio is
  /// only forwarded to the radio while the PTT button is held.
  void _onPttPcm(Uint8List pcm16) {
    if (!_pttActive) return;
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'TransmitVoicePCM',
      data: <String, Object?>{
        'data': pcm16,
        'playLocally': false,
        'hold': true,
      },
      store: false,
    );
  }

  /// Shows a brief hint explaining why PTT can't be used right now.
  void _showPttDisabledHint() {
    if (!mounted) return;
    final String message;
    if (!MicrophoneCapture.isSupported) {
      message = 'Microphone capture is not supported on this platform.';
    } else if (!_isCurrentRadioConnected) {
      message = 'Connect a radio before using push-to-talk.';
    } else if (!_audioEnabled) {
      message = 'Enable audio (the Enable button) before using push-to-talk.';
    } else {
      message = 'Please wait for the current transmission to finish.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// Serializes a [VoiceTransmitMode] to its stored string name.
  static String _modeToName(VoiceTransmitMode mode) {
    switch (mode) {
      case VoiceTransmitMode.chat:
        return 'chat';
      case VoiceTransmitMode.speak:
        return 'speak';
      case VoiceTransmitMode.morse:
        return 'morse';
      case VoiceTransmitMode.dtmf:
        return 'dtmf';
      case VoiceTransmitMode.ptt:
        return 'ptt';
    }
  }

  /// Parses a [VoiceTransmitMode] from its stored string name, defaulting to
  /// chat when unknown or absent.
  static VoiceTransmitMode _modeFromName(String? name) {
    switch (name) {
      case 'speak':
        return VoiceTransmitMode.speak;
      case 'morse':
        return VoiceTransmitMode.morse;
      case 'dtmf':
        return VoiceTransmitMode.dtmf;
      case 'ptt':
        return VoiceTransmitMode.ptt;
      case 'chat':
      default:
        return VoiceTransmitMode.chat;
    }
  }

  /// Updates the current transmit mode and persists it (device 0) so it is
  /// restored the next time the application loads.
  void _setMode(VoiceTransmitMode mode) {
    if (_currentMode != mode) setState(() => _currentMode = mode);
    _broker.dispatch(
      deviceId: 0,
      name: 'VoiceTransmitMode',
      data: _modeToName(mode),
      store: true,
    );
    // Start/stop the warm microphone to match the new mode.
    _updatePttMic();
  }

  void _onEnable() {
    // Toggle the audio channel of the radio shown in the Radio Panel. The UI
    // updates when the 'AudioState' broker value changes in response.
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    final desired = !_audioEnabled;
    // Persist the user's audio-enabled preference (device 0) so the audio
    // channel is automatically enabled when a radio connects.
    _broker.dispatch(
      deviceId: 0,
      name: 'AudioEnabled',
      data: desired,
      store: true,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SetAudio',
      data: desired,
      store: false,
    );
  }

  void _cancelTransmit() {
    final target = _currentRadioDeviceId;
    if (target <= 0) return;
    _broker.dispatch(
      deviceId: target,
      name: 'CancelVoiceTransmit',
      data: null,
      store: false,
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Are you sure you want to clear the voice history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _broker.dispatch(
        deviceId: 1,
        name: 'ClearVoiceText',
        data: null,
        store: false,
      );
    }
  }

  void _onMessageTap(ChatMessage message) {
    // A recording header was tapped: open the playback dialog.
    if (message.icon == Icons.play_circle && message.filename != null) {
      _openRecordingPlayback(message.filename!);
      return;
    }
    // An SSTV picture was tapped: open it larger in a dialog.
    if (message.imagePath != null) {
      showDialog<void>(
        context: context,
        builder: (context) => ImageViewDialog(
          filePath: message.imagePath!,
          title: message.message.isNotEmpty ? message.message : null,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message from ${message.senderCallsign}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _onMessageDoubleTap(ChatMessage message) {
    // Double-clicking a recording opens the playback dialog and starts playing.
    if (message.icon == Icons.play_circle && message.filename != null) {
      _openRecordingPlayback(message.filename!, autoPlay: true);
    }
  }

  /// Resolves the full path of a recording (in the application-support
  /// "recordings" folder) and shows the playback dialog.
  Future<void> _openRecordingPlayback(
    String filename, {
    bool autoPlay = false,
  }) async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording playback from files is unavailable on web.'),
        ),
      );
      return;
    }
    final base = await getApplicationSupportDirectory();
    final fullPath =
        '${base.path}${Platform.pathSeparator}recordings'
        '${Platform.pathSeparator}$filename';
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) =>
          RecordingPlaybackDialog(filePath: fullPath, autoPlay: autoPlay),
    );
  }

  void _onMessageLongPress(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy message'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Message copied')));
              },
            ),
            if (message.hasLocation)
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Show on map'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Location: ${message.latitude}, ${message.longitude}',
                      ),
                    ),
                  );
                },
              ),
            if (message.icon == Icons.play_circle)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Play recording'),
                onTap: () {
                  Navigator.pop(context);
                  if (message.filename != null) {
                    _openRecordingPlayback(message.filename!);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Shows a small context menu (anchored at [globalPosition]) that lets the
  /// user switch the transmit mode directly from the Send / PTT button.
  void _showModeMenu(BuildContext context, Offset globalPosition) {
    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    PopupMenuItem<VoiceTransmitMode> modeItem(
      VoiceTransmitMode mode,
      String label,
    ) {
      return PopupMenuItem<VoiceTransmitMode>(
        value: mode,
        height: menuItemHeight,
        padding: menuItemPadding,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: _currentMode == mode
                  ? const Text('✓', style: TextStyle(fontSize: 14))
                  : null,
            ),
            Text(label),
          ],
        ),
      );
    }

    showMenu<VoiceTransmitMode>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        if (!kIsWeb) modeItem(VoiceTransmitMode.ptt, 'PTT'),
        modeItem(VoiceTransmitMode.chat, 'Chat'),
        if (!kIsWeb) modeItem(VoiceTransmitMode.speak, 'Speak'),
        if (!kIsWeb) modeItem(VoiceTransmitMode.morse, 'Morse'),
        if (!kIsWeb) modeItem(VoiceTransmitMode.dtmf, 'DTMF'),
      ],
    ).then((mode) {
      if (mode == null || !mounted) return;
      _setMode(mode);
    });
  }

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        // Mode selection (only the data-only Chat mode is offered on web/iOS).
        // Hidden entirely when transmitting is not allowed.
        if (_audioChannelSupported && _allowTransmit)
          PopupMenuItem<String>(
            value: 'modePtt',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _currentMode == VoiceTransmitMode.ptt
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('PTT'),
              ],
            ),
          ),
        if (_allowTransmit)
          PopupMenuItem<String>(
            value: 'modeChat',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _currentMode == VoiceTransmitMode.chat
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Chat'),
              ],
            ),
          ),
        if (_audioChannelSupported && _allowTransmit)
          PopupMenuItem<String>(
            value: 'modeSpeak',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _currentMode == VoiceTransmitMode.speak
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Speak'),
              ],
            ),
          ),
        if (_audioChannelSupported && _allowTransmit)
          PopupMenuItem<String>(
            value: 'modeMorse',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _currentMode == VoiceTransmitMode.morse
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Morse'),
              ],
            ),
          ),
        if (_audioChannelSupported && _allowTransmit)
          PopupMenuItem<String>(
            value: 'modeDtmf',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _currentMode == VoiceTransmitMode.dtmf
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('DTMF'),
              ],
            ),
          ),
        // Speech-to-text, recording and SSTV/audio send all require the audio
        // channel, which does not exist on web or iOS.
        if (_audioChannelSupported) ...[
          // Only draw the separating divider when mode items precede it.
          if (_allowTransmit) const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'speechToText',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _speechToTextEnabled
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Speech-to-Text'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'recordAudio',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _recordAudio
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Record Audio'),
              ],
            ),
          ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'sendImage',
            height: menuItemHeight,
            padding: menuItemPadding,
            enabled: _audioEnabled && !_isTransmitting,
            child: const Row(
              children: [SizedBox(width: 20), Text('Send Image...')],
            ),
          ),
          PopupMenuItem<String>(
            value: 'sendAudio',
            height: menuItemHeight,
            padding: menuItemPadding,
            enabled: _audioEnabled && !_isTransmitting,
            child: const Row(
              children: [SizedBox(width: 20), Text('Send Audio...')],
            ),
          ),
        ],
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Clear History')],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: const Row(
              children: [SizedBox(width: 20), Text('Detach...')],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      switch (value) {
        case 'modeChat':
          _setMode(VoiceTransmitMode.chat);
          break;
        case 'modeSpeak':
          _setMode(VoiceTransmitMode.speak);
          break;
        case 'modeMorse':
          _setMode(VoiceTransmitMode.morse);
          break;
        case 'modeDtmf':
          _setMode(VoiceTransmitMode.dtmf);
          break;
        case 'modePtt':
          _setMode(VoiceTransmitMode.ptt);
          break;
        case 'speechToText':
          _broker.dispatch(
            deviceId: 0,
            name: 'SpeechToTextEnabled',
            data: !_speechToTextEnabled,
            store: true,
          );
          break;
        case 'recordAudio':
          _broker.dispatch(
            deviceId: 1,
            name: _recordAudio ? 'RecordingDisable' : 'RecordingEnable',
            data: null,
            store: false,
          );
          break;
        case 'sendImage':
          _pickAndSendImage();
          break;
        case 'sendAudio':
          _pickAndSendAudio();
          break;
        case 'clear':
          _confirmClearHistory();
          break;
        case 'detach':
          windowService.createWindow('comms');
          break;
      }
    });
  }

  Color _getIndicatorColor() {
    if (_isProcessing) return Colors.red;
    if (_isListening) return Colors.green;
    return Colors.transparent;
  }

  /// Maps the space bar to push-to-talk while the PTT mode is selected, so the
  /// space bar behaves the same as holding the on-screen PTT button.
  KeyEventResult _handlePttKey(FocusNode node, KeyEvent event) {
    if (_currentMode != VoiceTransmitMode.ptt) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (!_pttActive) _startPtt();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      if (_pttActive) _stopPtt();
      return KeyEventResult.handled;
    }
    // Swallow auto-repeat events while the key is held down.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _handlePttKey,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) {
                if (_canSendMedia) setState(() => _dragOver = true);
              },
              onDragExited: (_) {
                if (_dragOver) setState(() => _dragOver = false);
              },
              onDragDone: _onFilesDropped,
              child: Container(
                foregroundDecoration: _dragOver
                    ? BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 2),
                        color: Colors.blue.withValues(alpha: 0.08),
                      )
                    : null,
                child: ChatWidget(
                  messages: _messages,
                  onMessageTap: _onMessageTap,
                  onMessageDoubleTap: _onMessageDoubleTap,
                  onMessageLongPress: _onMessageLongPress,
                ),
              ),
            ),
          ),
          if (_allowTransmit && _currentMode == VoiceTransmitMode.ptt)
            _buildPttPanel()
          else if (_allowTransmit && !_isTransmitting)
            _buildInputPanel(),
          if (_isTransmitting) _buildCancelPanel(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButton = constraints.maxWidth > 180;
          return Row(
            children: [
              const Text(
                'Communications',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              // Processing indicator
              if (_audioEnabled)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getIndicatorColor(),
                    ),
                  ),
                ),
              const Spacer(),
              if (showButton && _audioChannelSupported)
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: (_audioEnabled || _isCurrentRadioConnected)
                        ? _onEnable
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                      backgroundColor: _audioEnabled
                          ? Colors.red.shade100
                          : null,
                    ),
                    child: Text(_audioEnabled ? 'Disable' : 'Enable'),
                  ),
                ),
              if (showButton && _audioChannelSupported)
                const SizedBox(width: 8),
              Builder(
                builder: (context) => InkWell(
                  onTap: () => _showMenu(context),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/MenuIcon.png',
                      width: 24,
                      height: 24,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.menu, size: 24);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Full-width "hold to transmit" button shown at the bottom of the tab when
  /// the PTT transmit mode is selected. Sized to match the Send button.
  Widget _buildPttPanel() {
    final bool enabled = _canPtt || _pttActive;
    final Color background = _pttActive
        ? Colors.red
        : (enabled ? Colors.red.shade400 : Colors.grey.shade400);
    return Container(
      height: 50,
      color: const Color(0xFFC0C0C0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: GestureDetector(
        // Only a real secondary (right) click opens the mode menu. We do NOT
        // use onLongPressStart here because holding the PTT button to transmit
        // would otherwise pop the menu and cancel the hold.
        onSecondaryTapDown: (details) =>
            _showModeMenu(context, details.globalPosition),
        child: Listener(
          onPointerDown: (event) {
            // Only the primary (left) button starts transmitting; the
            // secondary (right) button opens the mode menu instead.
            if (event.buttons == kPrimaryButton) _startPtt();
          },
          onPointerUp: (_) => _stopPtt(),
          onPointerCancel: (_) => _stopPtt(),
          child: SizedBox(
            height: 34,
            width: double.infinity,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _pttActive ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _pttActive ? 'Transmitting...' : 'PTT - Hold to Transmit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputPanel() {
    return Container(
      height: 50,
      color: const Color(0xFFC0C0C0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Text input
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                enabled: !_isTransmitting,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: _currentMode == VoiceTransmitMode.dtmf
                      ? 'Enter DTMF digits (0-9, *, #)...'
                      : 'Type a message...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                keyboardType: _currentMode == VoiceTransmitMode.dtmf
                    ? TextInputType.phone
                    : TextInputType.text,
                onSubmitted: (_) => _sendMessage(),
                onChanged: (value) {
                  // Filter DTMF input
                  if (_currentMode == VoiceTransmitMode.dtmf) {
                    final filtered = value.replaceAll(RegExp(r'[^0-9*#]'), '');
                    if (filtered != value) {
                      _messageController.text = filtered;
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: filtered.length),
                      );
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          SizedBox(
            height: 34,
            child: GestureDetector(
              onSecondaryTapDown: (details) =>
                  _showModeMenu(context, details.globalPosition),
              onLongPressStart: (details) =>
                  _showModeMenu(context, details.globalPosition),
              child: ElevatedButton(
                onPressed: _canSend ? _sendMessage : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Send'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Full-width Cancel bar shown at the bottom of the tab while audio is being
  /// transmitted (e.g. a WAV file, SSTV image or generated tones), so playback
  /// can be stopped at any time regardless of the current transmit mode.
  Widget _buildCancelPanel() {
    return Container(
      height: 50,
      color: const Color(0xFFC0C0C0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        height: 34,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _cancelTransmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Cancel'),
        ),
      ),
    );
  }
}

/// Encodes scaled ARGB image pixels into 16-bit little-endian PCM bytes using
/// the SSTV [Encoder]. Runs on a background isolate via `compute`.
Uint8List _encodeSstvPcm(Map<String, Object?> args) {
  final pixels = args['pixels'] as Int32List;
  final width = args['width'] as int;
  final height = args['height'] as int;
  final modeName = args['modeName'] as String;
  final sampleRate = args['sampleRate'] as int;

  final encoder = Encoder(sampleRate);
  final samples = encoder.encode(pixels, width, height, modeName);

  final pcm = Uint8List(samples.length * 2);
  final view = ByteData.view(pcm.buffer);
  for (int i = 0; i < samples.length; i++) {
    var s = samples[i];
    if (s > 1.0) {
      s = 1.0;
    } else if (s < -1.0) {
      s = -1.0;
    }
    view.setInt16(i * 2, (s * 32767).round(), Endian.little);
  }
  return pcm;
}

/// Decodes WAV file [bytes] and converts the audio to 32000 Hz mono signed
/// 16-bit little-endian PCM (the format the radio expects). Runs on a
/// background isolate via `compute`. Returns an empty list if the data is not
/// a valid PCM/float WAV file.
Uint8List _decodeWavToPcm32k(Uint8List bytes) {
  const int targetSampleRate = 32000;
  if (bytes.length < 12) return Uint8List(0);
  // 'RIFF' .... 'WAVE'
  if (!(bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45)) {
    return Uint8List(0);
  }
  final bd = ByteData.sublistView(bytes);
  int pos = 12;
  int format = 1;
  int channels = 1;
  int sampleRate = 22050;
  int bits = 16;
  int dataOffset = -1;
  int dataLen = 0;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = bd.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = bd.getUint16(body, Endian.little);
      channels = bd.getUint16(body + 2, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
      // WAVE_FORMAT_EXTENSIBLE: the real format tag is in the sub-format GUID.
      if (format == 0xFFFE && size >= 40 && body + 26 <= bytes.length) {
        format = bd.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      dataOffset = body;
      dataLen = size;
      break;
    }
    // Chunks are word-aligned.
    pos = body + size + (size & 1);
  }
  if (dataOffset < 0) return Uint8List(0);
  if (dataOffset + dataLen > bytes.length) dataLen = bytes.length - dataOffset;

  // Decode interleaved PCM into mono float samples in the range [-1, 1].
  final int bytesPerSample = bits ~/ 8;
  if (bytesPerSample == 0 || channels <= 0) return Uint8List(0);
  final int frameSize = bytesPerSample * channels;
  final int frames = dataLen ~/ frameSize;
  final mono = Float32List(frames);
  for (int f = 0; f < frames; f++) {
    double sum = 0;
    for (int c = 0; c < channels; c++) {
      final int p = dataOffset + f * frameSize + c * bytesPerSample;
      double v = 0;
      if (format == 3) {
        v = bits == 64
            ? bd.getFloat64(p, Endian.little)
            : bd.getFloat32(p, Endian.little);
      } else {
        switch (bits) {
          case 8:
            v = (bd.getUint8(p) - 128) / 128.0;
            break;
          case 16:
            v = bd.getInt16(p, Endian.little) / 32768.0;
            break;
          case 24:
            final b0 = bd.getUint8(p);
            final b1 = bd.getUint8(p + 1);
            final b2 = bd.getUint8(p + 2);
            int val = b0 | (b1 << 8) | (b2 << 16);
            if ((val & 0x800000) != 0) val -= 0x1000000;
            v = val / 8388608.0;
            break;
          case 32:
            v = bd.getInt32(p, Endian.little) / 2147483648.0;
            break;
        }
      }
      sum += v;
    }
    mono[f] = sum / channels;
  }

  // Resample to the target rate and pack into signed 16-bit little-endian PCM.
  Float32List resampled;
  if (sampleRate == targetSampleRate) {
    resampled = mono;
  } else if (sampleRate <= 0) {
    return Uint8List(0);
  } else {
    final int outLen = (mono.length * targetSampleRate / sampleRate).floor();
    resampled = Float32List(outLen);
    final double ratio = sampleRate / targetSampleRate;
    for (int i = 0; i < outLen; i++) {
      final double srcPos = i * ratio;
      final int i0 = srcPos.floor();
      final int i1 = (i0 + 1 < mono.length) ? i0 + 1 : i0;
      final double frac = srcPos - i0;
      resampled[i] = mono[i0] * (1 - frac) + mono[i1] * frac;
    }
  }
  final out = Uint8List(resampled.length * 2);
  final outView = ByteData.sublistView(out);
  for (int i = 0; i < resampled.length; i++) {
    double s = resampled[i];
    if (s > 1) s = 1;
    if (s < -1) s = -1;
    outView.setInt16(i * 2, (s * 32767).round(), Endian.little);
  }
  return out;
}
