import 'package:flutter/material.dart';
import '../services/window_service.dart';

/// Represents a piece of text with a specific color in the terminal
class TerminalTextSpan {
  final String text;
  final Color color;
  final bool bold;

  const TerminalTextSpan(
    this.text, {
    this.color = Colors.white70,
    this.bold = false,
  });
}

/// Terminal tab - command line interface
class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key});

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isConnected = false;
  bool _showCallsign = false;
  bool _wordWrap = false;

  // Terminal text content with colors
  final List<TerminalTextSpan> _terminalContent = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Add sample terminal text
    _addSampleText();
  }

  void _addSampleText() {
    _terminalContent.addAll([
      const TerminalTextSpan(
        '*** Terminal Ready ***\n',
        color: Colors.green,
        bold: true,
      ),
      const TerminalTextSpan(
        'System initialized at 2026-06-17 10:30:00\n',
        color: Colors.white70,
      ),
      const TerminalTextSpan('\n'),
      const TerminalTextSpan('> ', color: Colors.cyan),
      const TerminalTextSpan('CONNECT KK7VZT-1\n', color: Colors.white),
      const TerminalTextSpan(
        'Attempting connection to KK7VZT-1...\n',
        color: Colors.yellow,
      ),
      const TerminalTextSpan(
        '*** CONNECTED to KK7VZT-1 ***\n',
        color: Colors.green,
        bold: true,
      ),
      const TerminalTextSpan('\n'),
      const TerminalTextSpan('KK7VZT-1> ', color: Colors.cyan),
      const TerminalTextSpan(
        'Welcome to the packet radio BBS!\n',
        color: Colors.white,
      ),
      const TerminalTextSpan('KK7VZT-1> ', color: Colors.cyan),
      const TerminalTextSpan(
        'Type HELP for available commands.\n',
        color: Colors.white,
      ),
      const TerminalTextSpan('\n'),
      const TerminalTextSpan('> ', color: Colors.cyan),
      const TerminalTextSpan('HELP\n', color: Colors.white),
      const TerminalTextSpan('Available commands:\n', color: Colors.white70),
      const TerminalTextSpan(
        '  LIST   - List available files\n',
        color: Colors.white70,
      ),
      const TerminalTextSpan(
        '  READ   - Read a message\n',
        color: Colors.white70,
      ),
      const TerminalTextSpan(
        '  SEND   - Send a message\n',
        color: Colors.white70,
      ),
      const TerminalTextSpan('  BYE    - Disconnect\n', color: Colors.white70),
      const TerminalTextSpan('\n'),
      const TerminalTextSpan(
        '*** Error: Connection timeout ***\n',
        color: Colors.red,
        bold: true,
      ),
      const TerminalTextSpan('Reconnecting...\n', color: Colors.yellow),
      const TerminalTextSpan(
        '*** CONNECTED ***\n',
        color: Colors.green,
        bold: true,
      ),
    ]);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onConnect() {
    setState(() {
      _isConnected = !_isConnected;
      if (_isConnected) {
        _terminalContent.add(
          const TerminalTextSpan(
            '\n*** Connection established ***\n',
            color: Colors.green,
            bold: true,
          ),
        );
      } else {
        _terminalContent.add(
          const TerminalTextSpan(
            '\n*** Disconnected ***\n',
            color: Colors.red,
            bold: true,
          ),
        );
      }
    });
    _scrollToBottom();
  }

  void _onSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _terminalContent.add(const TerminalTextSpan('> ', color: Colors.cyan));
      _terminalContent.add(TerminalTextSpan('$text\n', color: Colors.white));
    });
    _inputController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
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
        PopupMenuItem<String>(
          value: 'showCallsign',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showCallsign
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show Callsign'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'wordWrap',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _wordWrap
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Word Wrap'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'waitForConnection',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Wait for Connection...')],
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
      if (value == null) return;
      switch (value) {
        case 'showCallsign':
          setState(() => _showCallsign = !_showCallsign);
          break;
        case 'wordWrap':
          setState(() => _wordWrap = !_wordWrap);
          break;
        case 'clear':
          setState(() => _terminalContent.clear());
          break;
        case 'detach':
          windowService.createWindow('terminal');
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      children: [
        // Header bar
        _buildHeader(),
        // Terminal text area
        Expanded(
          child: Container(color: Colors.black, child: _buildTerminalText()),
        ),
        // Bottom input panel
        _buildInputPanel(),
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
          final showButton = constraints.maxWidth > 200;
          return Row(
            children: [
              // Terminal label
              const Text(
                'Terminal',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              // Connect button
              if (showButton) ...[
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _onConnect,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Menu icon
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

  Widget _buildTerminalText() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        child: SelectableText.rich(
          TextSpan(
            children: _terminalContent.map((span) {
              return TextSpan(
                text: span.text,
                style: TextStyle(
                  color: span.color,
                  fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          style: TextStyle(
            fontFamily: 'Courier New',
            fontFamilyFallback: const ['monospace', 'Courier'],
            fontSize: 14,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildInputPanel() {
    return Container(
      height: 50,
      color: const Color(0xFFC0C0C0), // Silver color
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Input text field
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
                controller: _inputController,
                enabled: _isConnected,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onSubmitted: (_) => _onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _isConnected ? _onSend : null,
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
