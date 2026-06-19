import 'package:flutter/material.dart';
import 'chat_widget.dart';
import '../services/window_service.dart';

/// APRS tab - Automatic Packet Reporting System
class AprsTab extends StatefulWidget {
  const AprsTab({super.key});

  @override
  State<AprsTab> createState() => _AprsTabState();
}

class _AprsTabState extends State<AprsTab> with AutomaticKeepAliveClientMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController(
    text: 'APRS',
  );
  final FocusNode _messageFocusNode = FocusNode();
  String _selectedDestination = 'APRS';
  bool _showAllMessages = false;
  final bool _allowTransmit = true;

  // Sample destinations
  final List<String> _destinations = ['APRS', 'KC3SLD', 'KK7VZT', 'N0CALL'];

  // APRS routes for digipeater paths
  final List<String> _aprsRoutes = ['WIDE1-1', 'WIDE1-1,WIDE2-1', 'WIDE2-2'];
  String _selectedRoute = 'WIDE1-1';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _addSampleMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _destinationController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _addSampleMessages() {
    _messages.addAll([
      ChatMessage(
        id: '1',
        route: 'KC3SLD',
        senderCallsign: 'KC3SLD',
        message: 'Good morning! Anyone on frequency?',
        time: DateTime.now().subtract(const Duration(hours: 2)),
        isSender: false,
        authState: ChatAuthState.success,
        latitude: 40.3954,
        longitude: -79.9718,
      ),
      ChatMessage(
        id: '2',
        route: '→ KC3SLD',
        senderCallsign: 'ME',
        message: 'Good morning! Reading you loud and clear.',
        time: DateTime.now().subtract(const Duration(hours: 2)),
        isSender: true,
        icon: Icons.check,
      ),
      ChatMessage(
        id: '3',
        route: 'KK7VZT → APRS',
        senderCallsign: 'KK7VZT',
        message: 'Weather report: Clear skies, 72°F',
        time: DateTime.now().subtract(const Duration(hours: 1)),
        isSender: false,
        latitude: 47.6062,
        longitude: -122.3321,
      ),
      ChatMessage(
        id: '4',
        route: 'N0CALL',
        senderCallsign: 'N0CALL',
        message: 'Test beacon from mobile station',
        time: DateTime.now().subtract(const Duration(minutes: 30)),
        isSender: false,
        authState: ChatAuthState.failed,
      ),
      ChatMessage(
        id: '5',
        route: 'KC3SLD ✓',
        senderCallsign: 'KC3SLD',
        message: 'Thanks for the QSO! 73',
        time: DateTime.now().subtract(const Duration(minutes: 5)),
        isSender: false,
        authState: ChatAuthState.success,
      ),
    ]);
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          route: '→ $_selectedDestination',
          senderCallsign: 'ME',
          message: text,
          time: DateTime.now(),
          isSender: true,
          icon: Icons.schedule, // Pending
        ),
      );
      _messageController.clear();
    });
  }

  void _onMessageTap(ChatMessage message) {
    // Show message details
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message from ${message.senderCallsign}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _onMessageLongPress(ChatMessage message) {
    // Show context menu
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
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selectedDestination = message.senderCallsign;
                  _destinationController.text = message.senderCallsign;
                });
                _messageFocusNode.requestFocus();
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
        PopupMenuItem<String>(
          value: 'showAll',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showAllMessages
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show All Messages'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'sendMessage',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _allowTransmit,
          child: const Row(
            children: [SizedBox(width: 20), Text('Send Message...')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'weatherReport',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _allowTransmit,
          child: const Row(
            children: [SizedBox(width: 20), Text('Weather Report...')],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(children: [SizedBox(width: 20), Text('Clear')]),
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
        case 'showAll':
          setState(() => _showAllMessages = !_showAllMessages);
          break;
        case 'sendMessage':
          _messageFocusNode.requestFocus();
          break;
        case 'weatherReport':
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Weather report dialog not implemented yet'),
              ),
            );
          }
          break;
        case 'clear':
          setState(() => _messages.clear());
          break;
        case 'detach':
          _detachWindow();
          break;
      }
    });
  }

  Future<void> _detachWindow() async {
    await windowService.createWindow('aprs');
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
      color: const Color(0xFFC0C0C0),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Text(
            'APRS',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          // APRS Route dropdown
          if (_aprsRoutes.length > 1)
            Container(
              height: 28,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRoute,
                  isDense: true,
                  style: const TextStyle(fontSize: 14, color: Colors.black),
                  items: _aprsRoutes.map((route) {
                    return DropdownMenuItem(value: route, child: Text(route));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedRoute = value);
                    }
                  },
                ),
              ),
            ),
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
      ),
    );
  }

  Widget _buildInputPanel() {
    return Container(
      height: 50,
      color: const Color(0xFFC0C0C0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Destination combo box (text input with dropdown)
          SizedBox(
            width: 120,
            height: 34,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _destinationController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        border: InputBorder.none,
                        isDense: true,
                        isCollapsed: true,
                      ),
                      onChanged: (value) {
                        _selectedDestination = value.toUpperCase();
                      },
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    height: 32,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        setState(() {
                          _selectedDestination = value;
                          _destinationController.text = value;
                        });
                      },
                      itemBuilder: (context) => _destinations.map((dest) {
                        return PopupMenuItem<String>(
                          value: dest,
                          height: 36,
                          child: Text(
                            dest,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
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
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _sendMessage,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
