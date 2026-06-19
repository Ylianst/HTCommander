import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import '../services/window_service.dart';

/// Debug log entry
class DebugLogEntry {
  final DateTime time;
  final String message;
  final bool isError;

  const DebugLogEntry({
    required this.time,
    required this.message,
    this.isError = false,
  });
}

/// Debug tab - debugging and diagnostic information
class DebugTab extends StatefulWidget {
  final bool showBuiltInMenus;
  final ValueChanged<bool>? onShowBuiltInMenusChanged;

  const DebugTab({
    super.key,
    this.showBuiltInMenus = false,
    this.onShowBuiltInMenusChanged,
  });

  @override
  State<DebugTab> createState() => _DebugTabState();
}

class _DebugTabState extends State<DebugTab>
    with AutomaticKeepAliveClientMixin {
  final List<DebugLogEntry> _logEntries = [];
  final ScrollController _scrollController = ScrollController();
  bool _saveToFile = false;
  bool _showBluetoothFrames = false;
  bool _loopbackMode = false;
  bool _autoScroll = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _addSampleLogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _addSampleLogs() {
    // Sample log entries for demonstration
    _logEntries.addAll([
      DebugLogEntry(
        time: DateTime.now().subtract(const Duration(minutes: 5)),
        message: 'HTCommander started',
      ),
      DebugLogEntry(
        time: DateTime.now().subtract(const Duration(minutes: 4)),
        message: 'Initializing radio interface...',
      ),
      DebugLogEntry(
        time: DateTime.now().subtract(const Duration(minutes: 3)),
        message: 'Bluetooth adapter found: Intel AX200',
      ),
      DebugLogEntry(
        time: DateTime.now().subtract(const Duration(minutes: 2)),
        message: 'Scanning for devices...',
      ),
      DebugLogEntry(
        time: DateTime.now().subtract(const Duration(minutes: 1)),
        message: 'Found device: HT-UV98 (AA:BB:CC:DD:EE:FF)',
      ),
      DebugLogEntry(
        time: DateTime.now().subtract(const Duration(seconds: 30)),
        message: 'Connection attempt failed: timeout',
        isError: true,
      ),
      DebugLogEntry(time: DateTime.now(), message: 'Ready for connection'),
    ]);
  }

  void _appendLog(String message, {bool isError = false}) {
    setState(() {
      _logEntries.add(
        DebugLogEntry(time: DateTime.now(), message: message, isError: isError),
      );
    });
    if (_autoScroll) {
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
  }

  void _clearLogs() {
    setState(() {
      _logEntries.clear();
    });
  }

  void _onSaveToFile() {
    setState(() {
      _saveToFile = !_saveToFile;
    });
    if (_saveToFile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save to file not implemented yet')),
      );
    }
  }

  void _onQueryDeviceNames() {
    _appendLog('Querying device names...');
    // Simulate device query
    Future.delayed(const Duration(milliseconds: 500), () {
      _appendLog('List of devices:');
      _appendLog('  No devices found');
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
          value: 'saveToFile',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _saveToFile
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Save to File...'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'showBluetoothFrames',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showBluetoothFrames
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show Bluetooth Frames'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'loopbackMode',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _loopbackMode
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Loopback Mode'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'queryDeviceNames',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Query Device Names')],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'autoScroll',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _autoScroll
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Auto Scroll'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(children: [SizedBox(width: 20), Text('Clear')]),
        ),
        // macOS-only option to show built-in menus
        if (Platform.isMacOS) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'showBuiltInMenus',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: widget.showBuiltInMenus
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                const Text('Show Built-in Menus'),
              ],
            ),
          ),
        ],
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
        case 'saveToFile':
          _onSaveToFile();
          break;
        case 'showBluetoothFrames':
          setState(() => _showBluetoothFrames = !_showBluetoothFrames);
          break;
        case 'loopbackMode':
          setState(() => _loopbackMode = !_loopbackMode);
          break;
        case 'queryDeviceNames':
          _onQueryDeviceNames();
          break;
        case 'autoScroll':
          setState(() => _autoScroll = !_autoScroll);
          break;
        case 'clear':
          _clearLogs();
          break;
        case 'showBuiltInMenus':
          widget.onShowBuiltInMenusChanged?.call(!widget.showBuiltInMenus);
          break;
        case 'detach':
          windowService.createWindow('debug');
          break;
      }
    });
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildLogDisplay()),
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
            'Debug',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
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

  Widget _buildLogDisplay() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: double.infinity,
          child: SelectableText.rich(
            TextSpan(
              children: _logEntries.map((entry) {
                final timeStr = _formatTime(entry.time);
                return TextSpan(
                  children: [
                    TextSpan(
                      text: '[$timeStr] ',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    if (entry.isError)
                      TextSpan(
                        text: '[Error] ',
                        style: const TextStyle(
                          color: Colors.red,
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    TextSpan(
                      text: '${entry.message}\n',
                      style: TextStyle(
                        color: entry.isError ? Colors.red : Colors.black,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
            textAlign: TextAlign.left,
          ),
        ),
      ),
    );
  }
}
