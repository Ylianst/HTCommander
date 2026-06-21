import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'chat_widget.dart';
import '../dialogs/image_view_dialog.dart';
import '../dialogs/recording_playback_dialog.dart';
import '../dialogs/sstv_send_dialog.dart';
import '../sstv/encoder.dart';
import '../services/window_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// Voice transmit mode
enum VoiceTransmitMode { chat, speak, morse, dtmf }

/// Voice tab - audio communication controls
class VoiceTab extends StatefulWidget {
  const VoiceTab({super.key});

  @override
  State<VoiceTab> createState() => _VoiceTabState();
}

class _VoiceTabState extends State<VoiceTab>
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

  /// Absolute path to the application-support directory, resolved on init. Used
  /// to locate decoded SSTV pictures saved by the voice handler.
  String? _appSupportPath;

  /// True while a file is being dragged over the chat area.
  bool _dragOver = false;

  @override
  bool get wantKeepAlive => true;

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

    // Initialize from current broker values.
    _currentRadioDeviceId = _resolveCurrentRadioId();
    _allowTransmit = _broker.getValue<bool>(0, 'AllowTransmit', true) ?? true;
    _speechToTextEnabled =
        _broker.getValue<bool>(0, 'SpeechToTextEnabled', true) ?? true;
    _recordAudio = _broker.getValue<bool>(0, 'RecordingState', false) ?? false;
    _audioEnabled = _readAudioState();
    _loadDecodedTextHistory();

    // Resolve the application-support path so decoded SSTV pictures can be
    // shown inline; reload history once it is known to attach image paths.
    _resolveAppSupportPath();
  }

  /// Resolves the application-support directory path and re-attaches SSTV image
  /// paths to any already-loaded history entries.
  Future<void> _resolveAppSupportPath() async {
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

  /// Handles files dropped onto the chat area. Only a single image file is
  /// accepted; everything else is ignored.
  void _onFilesDropped(DropDoneDetails details) {
    if (_dragOver) setState(() => _dragOver = false);
    if (!_canSendMedia) return;
    final files = details.files;
    if (files.length != 1) return;
    final path = files.first.path;
    if (!_isImageFile(path)) return;
    _loadAndSendImage(path);
  }

  /// Opens a file picker to choose an image, then shows the SSTV send dialog.
  Future<void> _pickAndSendImage() async {
    if (!_canSendMedia) return;
    final result = await FilePicker.platform.pickFiles(
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
  }

  void _onSelectedRadioChanged(int deviceId, String name, Object? data) {
    if (data is! int) return;
    setState(() {
      _currentRadioDeviceId = data;
      _audioEnabled = _readAudioState();
    });
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
    if (data is bool) setState(() => _audioEnabled = data);
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
    if (data is bool) setState(() => _allowTransmit = data);
  }

  void _onSpeechToTextEnabledChanged(int deviceId, String name, Object? data) {
    if (data is bool) setState(() => _speechToTextEnabled = data);
  }

  void _onRecordingStateChanged(int deviceId, String name, Object? data) {
    if (data is bool) setState(() => _recordAudio = data);
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
    if (text.isEmpty || !_canSend) return;

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
        _broker.dispatch(deviceId: 1, name: 'Speak', data: text, store: false);
        break;
      case VoiceTransmitMode.morse:
        _broker.dispatch(deviceId: 1, name: 'Morse', data: text, store: false);
        break;
      case VoiceTransmitMode.dtmf:
        // DTMF tone generation is not implemented in this build.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DTMF transmit not implemented yet')),
        );
        break;
    }

    _messageController.clear();
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

  void _onEnable() {
    // Toggle the audio channel of the radio shown in the Radio Panel. The UI
    // updates when the 'AudioState' broker value changes in response.
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SetAudio',
      data: !_audioEnabled,
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

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);
    final messenger = ScaffoldMessenger.of(context);

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
        // Mode selection
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
        const PopupMenuDivider(height: 8),
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
          setState(() => _currentMode = VoiceTransmitMode.chat);
          break;
        case 'modeSpeak':
          setState(() => _currentMode = VoiceTransmitMode.speak);
          break;
        case 'modeMorse':
          setState(() => _currentMode = VoiceTransmitMode.morse);
          break;
        case 'modeDtmf':
          setState(() => _currentMode = VoiceTransmitMode.dtmf);
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
          messenger.showSnackBar(
            const SnackBar(content: Text('Send audio not implemented yet')),
          );
          break;
        case 'clear':
          _confirmClearHistory();
          break;
        case 'detach':
          windowService.createWindow('voice');
          break;
      }
    });
  }

  Color _getIndicatorColor() {
    if (_isProcessing) return Colors.red;
    if (_isListening) return Colors.green;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
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
        if (_allowTransmit) _buildInputPanel(),
      ],
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
                'Voice',
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
              if (showButton)
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
              if (showButton) const SizedBox(width: 8),
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
                enabled: _canSend,
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
            child: ElevatedButton(
              onPressed: _canSend ? _sendMessage : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Send'),
            ),
          ),
          // Cancel button (visible during transmission)
          if (_isTransmitting)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: _cancelTransmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ),
        ],
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
