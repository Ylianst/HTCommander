import 'package:flutter/material.dart';
import 'chat_widget.dart';
import '../services/window_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// Voice transmit mode
enum VoiceTransmitMode { chat, speak, morse, dtmf }

/// Voice encoding type
enum VoiceEncodingType { voice, morse, dtmf, recording, picture, ident }

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
  int _currentRadioDeviceId = -1;
  VoiceTransmitMode _currentMode = VoiceTransmitMode.chat;
  bool _isEnabled = false;
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isTransmitting = false;
  bool _speechToTextEnabled = true;
  bool _recordAudio = false;
  final bool _allowTransmit = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _addSampleMessages();

    // Track the currently connected radio so we can target SetAudio at it.
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );

    // Track which radio the Radio Panel is currently showing.
    _broker.subscribe(
      deviceId: 1,
      name: 'SelectedRadioDeviceId',
      callback: _onSelectedRadioChanged,
    );

    // Sync the Enable/Disable button with the audio path state.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioState',
      callback: _onAudioStateChanged,
    );

    // Initialize from current broker values.
    _currentRadioDeviceId = _resolveCurrentRadioId();
    _isEnabled = _readAudioState(_currentRadioDeviceId);
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

  /// Read the stored AudioState for the given radio device.
  bool _readAudioState(int deviceId) {
    if (deviceId <= 0) return false;
    return DataBroker.getValue<bool>(deviceId, 'AudioState', false) ?? false;
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    final id = _resolveCurrentRadioId();
    setState(() {
      _currentRadioDeviceId = id;
      _applyAudioEnabled(_readAudioState(id));
    });
  }

  void _onSelectedRadioChanged(int deviceId, String name, Object? data) {
    if (data is! int) return;
    setState(() {
      _currentRadioDeviceId = data;
      _applyAudioEnabled(_readAudioState(data));
    });
  }

  void _onAudioStateChanged(int deviceId, String name, Object? data) {
    if (deviceId == _currentRadioDeviceId && data is bool) {
      setState(() => _applyAudioEnabled(data));
    }
  }

  /// Apply the enabled state, keeping derived UI flags in sync.
  void _applyAudioEnabled(bool enabled) {
    _isEnabled = enabled;
    if (enabled) {
      _isListening = true;
    } else {
      _isListening = false;
      _isProcessing = false;
    }
  }

  void _addSampleMessages() {
    _messages.addAll([
      ChatMessage(
        id: '1',
        route: 'Voice - Channel 1',
        senderCallsign: 'KC3SLD',
        message: 'Good morning, this is KC3SLD checking in.',
        time: DateTime.now().subtract(const Duration(hours: 1)),
        isSender: false,
        latitude: 40.3954,
        longitude: -79.9718,
      ),
      ChatMessage(
        id: '2',
        route: '→ Voice',
        senderCallsign: 'ME',
        message: 'Good morning! Reading you five by five.',
        time: DateTime.now().subtract(const Duration(hours: 1)),
        isSender: true,
        icon: Icons.check,
      ),
      ChatMessage(
        id: '3',
        route: 'Voice - Channel 1',
        senderCallsign: 'KK7VZT',
        message: 'Hello all, KK7VZT mobile.',
        time: DateTime.now().subtract(const Duration(minutes: 30)),
        isSender: false,
      ),
      ChatMessage(
        id: '4',
        route: 'Morse',
        senderCallsign: 'N0CALL',
        message: 'CQ CQ CQ DE N0CALL',
        time: DateTime.now().subtract(const Duration(minutes: 15)),
        isSender: false,
      ),
      ChatMessage(
        id: '5',
        route: 'Recording (0:15)',
        senderCallsign: 'KC3SLD',
        message: '🎙️ Audio recording',
        time: DateTime.now().subtract(const Duration(minutes: 5)),
        isSender: false,
        icon: Icons.play_circle,
      ),
    ]);
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || !_isEnabled) return;

    // In DTMF mode, filter to valid characters
    final messageText = _currentMode == VoiceTransmitMode.dtmf
        ? text.replaceAll(RegExp(r'[^0-9*#]'), '')
        : text;

    if (messageText.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          route: '→ ${_getModeLabel(_currentMode)}',
          senderCallsign: 'ME',
          message: messageText,
          time: DateTime.now(),
          isSender: true,
          icon: Icons.schedule,
        ),
      );
      _messageController.clear();
    });
  }

  String _getModeLabel(VoiceTransmitMode mode) {
    switch (mode) {
      case VoiceTransmitMode.chat:
        return 'Chat';
      case VoiceTransmitMode.speak:
        return 'Speak';
      case VoiceTransmitMode.morse:
        return 'Morse';
      case VoiceTransmitMode.dtmf:
        return 'DTMF';
    }
  }

  void _onEnable() {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    // Toggle the audio path: read the current state and dispatch the opposite.
    // The actual UI state updates when the 'AudioState' broker value changes
    // in response.
    final currentlyEnabled = _readAudioState(deviceId);
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SetAudio',
      data: !currentlyEnabled,
      store: false,
    );
  }

  void _onMessageTap(ChatMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message from ${message.senderCallsign}'),
        duration: const Duration(seconds: 1),
      ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Playback not implemented yet'),
                    ),
                  );
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
          enabled: _isEnabled && !_isTransmitting,
          child: const Row(
            children: [SizedBox(width: 20), Text('Send Image...')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'sendAudio',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _isEnabled && !_isTransmitting,
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
          setState(() => _speechToTextEnabled = !_speechToTextEnabled);
          break;
        case 'recordAudio':
          setState(() => _recordAudio = !_recordAudio);
          break;
        case 'sendImage':
          messenger.showSnackBar(
            const SnackBar(content: Text('Send image not implemented yet')),
          );
          break;
        case 'sendAudio':
          messenger.showSnackBar(
            const SnackBar(content: Text('Send audio not implemented yet')),
          );
          break;
        case 'clear':
          setState(() => _messages.clear());
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
          child: ChatWidget(
            messages: _messages,
            onMessageTap: _onMessageTap,
            onMessageLongPress: _onMessageLongPress,
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
              if (_isEnabled)
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
                    onPressed: _onEnable,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                      backgroundColor: _isEnabled ? Colors.red.shade100 : null,
                    ),
                    child: Text(_isEnabled ? 'Disable' : 'Enable'),
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
                enabled: _isEnabled && !_isTransmitting,
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
              onPressed: _isEnabled && !_isTransmitting ? _sendMessage : null,
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
                  onPressed: () {
                    setState(() => _isTransmitting = false);
                  },
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
