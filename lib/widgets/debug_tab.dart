import 'dart:io' show File, Platform;
import 'dart:ui' as ui show BoxWidthStyle;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../dialogs/about_dialog.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
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
  final ScrollController _scrollController = ScrollController();
  final DataBrokerClient _broker = DataBrokerClient();

  // Log entries are stored in DataBroker to persist across widget rebuilds
  List<DebugLogEntry> _logEntries = [];

  bool _showBluetoothFrames = false;
  bool _loopbackMode = false;
  bool _autoScroll = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Load existing log entries from DataBroker
    _loadExistingLogEntries();

    // Subscribe to log messages (LogInfo and LogError from device 1)
    _broker.subscribeMultiple(
      deviceId: 1,
      names: ['LogInfo', 'LogError'],
      callback: _onLogMessage,
    );

    // Subscribe to debug log entries changes (for sync across widgets)
    _broker.subscribe(
      deviceId: 1,
      name: 'DebugLogEntries',
      callback: _onDebugLogEntriesChanged,
    );

    // Subscribe to Bluetooth frames debug setting changes (persisted, device 0)
    _broker.subscribe(
      deviceId: 0,
      name: 'BluetoothFramesDebug',
      callback: _onBluetoothFramesDebugChanged,
    );

    // Subscribe to loopback mode changes (device 1, not persisted)
    _broker.subscribe(
      deviceId: 1,
      name: 'LoopbackMode',
      callback: _onLoopbackModeChanged,
    );

    // Initialize states from current broker values
    _initializeStates();

    // Add startup log only if this is a fresh start (no existing entries)
    if (_logEntries.isEmpty) {
      _broker.logInfo('HTCommander ${HTAboutDialog.version} started');
    }
  }

  void _loadExistingLogEntries() {
    final storedEntries = DataBroker.getValue<List<dynamic>>(
      1,
      'DebugLogEntries',
    );
    if (storedEntries != null) {
      _logEntries = storedEntries
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => DebugLogEntry(
              time:
                  DateTime.tryParse(e['time'] as String? ?? '') ??
                  DateTime.now(),
              message: e['message'] as String? ?? '',
              isError: e['isError'] as bool? ?? false,
            ),
          )
          .toList();
    }
  }

  void _onDebugLogEntriesChanged(int deviceId, String name, Object? data) {
    if (data is List) {
      final newEntries = data
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => DebugLogEntry(
              time:
                  DateTime.tryParse(e['time'] as String? ?? '') ??
                  DateTime.now(),
              message: e['message'] as String? ?? '',
              isError: e['isError'] as bool? ?? false,
            ),
          )
          .toList();

      if (newEntries.length != _logEntries.length) {
        setState(() {
          _logEntries = newEntries;
        });
        if (_autoScroll && newEntries.length > _logEntries.length) {
          _scrollToBottom();
        }
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _broker.dispose();
    super.dispose();
  }

  /// Initialize menu item states from current broker values
  void _initializeStates() {
    _showBluetoothFrames =
        DataBroker.getValue<bool>(0, 'BluetoothFramesDebug', false) ?? false;
    _loopbackMode =
        DataBroker.getValue<bool>(1, 'LoopbackMode', false) ?? false;
  }

  /// Handle log messages from DataBroker
  void _onLogMessage(int deviceId, String name, Object? data) {
    if (data is String) {
      final isError = name == 'LogError';
      _appendLog(data, isError: isError);
    }
  }

  /// Handle Bluetooth frames debug setting changes
  void _onBluetoothFramesDebugChanged(int deviceId, String name, Object? data) {
    if (data is bool && _showBluetoothFrames != data) {
      setState(() {
        _showBluetoothFrames = data;
      });
    }
  }

  /// Handle loopback mode setting changes
  void _onLoopbackModeChanged(int deviceId, String name, Object? data) {
    if (data is bool && _loopbackMode != data) {
      setState(() {
        _loopbackMode = data;
      });
    }
  }

  void _appendLog(String message, {bool isError = false}) {
    final entry = DebugLogEntry(
      time: DateTime.now(),
      message: message,
      isError: isError,
    );
    setState(() {
      _logEntries.add(entry);
    });

    // Persist to DataBroker
    _persistLogEntries();

    if (_autoScroll) {
      _scrollToBottom();
    }
  }

  void _clearLogs() {
    setState(() {
      _logEntries.clear();
    });
    // Clear from DataBroker
    DataBroker.dispatch(
      deviceId: 1,
      name: 'DebugLogEntries',
      data: <Map<String, dynamic>>[],
      store: true,
    );
  }

  void _persistLogEntries() {
    // Convert entries to JSON-serializable format
    final entriesJson = _logEntries
        .map(
          (e) => {
            'time': e.time.toIso8601String(),
            'message': e.message,
            'isError': e.isError,
          },
        )
        .toList();

    // Store in DataBroker (not persisted to disk, just in-memory)
    DataBroker.dispatch(
      deviceId: 1,
      name: 'DebugLogEntries',
      data: entriesJson,
      store: true,
    );
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

  /// Toggle Bluetooth frames debug setting (persisted to device 0)
  void _toggleBluetoothFrames() {
    final newValue = !_showBluetoothFrames;
    // Dispatch the new value (persists via broker)
    DataBroker.dispatch(
      deviceId: 0,
      name: 'BluetoothFramesDebug',
      data: newValue,
      store: true,
    );
    // Local state will be updated via subscription callback
  }

  /// Toggle loopback mode setting (device 1, not persisted)
  void _toggleLoopbackMode() {
    final newValue = !_loopbackMode;
    // Dispatch the new value (device 1, not persisted)
    DataBroker.dispatch(
      deviceId: 1,
      name: 'LoopbackMode',
      data: newValue,
      store: false,
    );
    // Local state will be updated via subscription callback
  }

  Future<void> _onSaveToFile() async {
    // Build the log content as text
    final StringBuffer buffer = StringBuffer();
    for (final entry in _logEntries) {
      final timeStr = _formatTime(entry.time);
      if (entry.isError) {
        buffer.writeln('[$timeStr] [Error] ${entry.message}');
      } else {
        buffer.writeln('[$timeStr] ${entry.message}');
      }
    }
    final logContent = buffer.toString();

    // Generate filename with current date/time
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final defaultFileName = 'debug_log_${dateStr}_$timeStr.txt';

    // Show file save dialog
    String? outputPath;
    try {
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Debug Log',
        fileName: defaultFileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file dialog: $e')),
        );
      }
      return;
    }

    if (outputPath != null) {
      try {
        final file = File(outputPath);
        await file.writeAsString(logContent);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Debug log saved to $outputPath')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error saving file: $e')));
        }
      }
    }
  }

  Future<void> _onQueryDeviceNames() async {
    _broker.logInfo('Querying Bluetooth device names...');

    try {
      final bluetoothService = BluetoothService();
      final devices = await bluetoothService.findCompatibleDevices(
        timeout: const Duration(seconds: 3),
      );

      _broker.logInfo('List of devices:');
      if (devices.isEmpty) {
        _broker.logInfo('  No compatible devices found');
      } else {
        for (final device in devices) {
          _broker.logInfo('  ${device.name} (${device.id})');
        }
      }
    } catch (e) {
      _broker.logError('Error querying devices: $e');
    }
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
          child: const Row(
            children: [SizedBox(width: 20), Text('Save to File...')],
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
        // macOS-only option to show built-in menus (skip on web)
        if (!kIsWeb && Platform.isMacOS) ...[
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
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'saveToFile':
          await _onSaveToFile();
          break;
        case 'showBluetoothFrames':
          _toggleBluetoothFrames();
          break;
        case 'loopbackMode':
          _toggleLoopbackMode();
          break;
        case 'queryDeviceNames':
          await _onQueryDeviceNames();
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
            textWidthBasis: TextWidthBasis.parent,
            selectionWidthStyle: ui.BoxWidthStyle.max,
          ),
        ),
      ),
    );
  }
}
