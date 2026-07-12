import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../dialogs/firmware_update_dialog.dart';
import '../models/radio_models.dart';
import '../services/bluetooth_service.dart';
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
  /// Device id under which application log messages are published/stored.
  static const int _logDeviceId = 1;

  final List<DebugLogEntry> _logEntries = [];
  final ScrollController _scrollController = ScrollController();
  final DataBrokerClient _broker = DataBrokerClient();
  bool _showBluetoothFrames = false;
  bool _loopbackMode = false;
  bool _autoScroll = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Restore the persisted 'Show Bluetooth Frames' toggle. The Radio layer
    // reads this same broker value ('BluetoothFramesDebug' on device 0) to
    // decide whether to log every incoming/outgoing control-channel frame.
    _showBluetoothFrames =
        _broker.getValue<bool>(0, 'BluetoothFramesDebug') ?? false;
    // The Debug tab renders the application log captured by the DebugLogHandler
    // into the broker's 'DebugLogEntries' value. Load whatever has accumulated
    // since startup, then keep in sync with future changes.
    _logEntries.addAll(
      _parseEntries(_broker.getValueDynamic(_logDeviceId, 'DebugLogEntries')),
    );
    _broker.subscribe(
      deviceId: _logDeviceId,
      name: 'DebugLogEntries',
      callback: _onDebugLogEntriesChanged,
    );
    _scrollToBottomIfNeeded();
  }

  @override
  void dispose() {
    _broker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Converts the broker's serialized 'DebugLogEntries' payload into the
  /// strongly-typed [DebugLogEntry] list used for rendering.
  List<DebugLogEntry> _parseEntries(Object? raw) {
    final entries = <DebugLogEntry>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final timeStr = item['time'];
          final time = timeStr is String
              ? (DateTime.tryParse(timeStr) ?? DateTime.now())
              : DateTime.now();
          entries.add(
            DebugLogEntry(
              time: time,
              message: item['message']?.toString() ?? '',
              isError: item['isError'] == true,
            ),
          );
        }
      }
    }
    return entries;
  }

  void _onDebugLogEntriesChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _logEntries
        ..clear()
        ..addAll(_parseEntries(data));
    });
    _scrollToBottomIfNeeded();
  }

  void _scrollToBottomIfNeeded() {
    if (!_autoScroll) return;
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

  void _clearLogs() {
    // The DebugLogHandler owns the log; ask it to clear and it will publish the
    // emptied list back through 'DebugLogEntries'.
    _broker.dispatch(
      deviceId: _logDeviceId,
      name: 'ClearDebugLog',
      data: null,
      store: false,
    );
  }

  /// Opens the firmware update dialog for the currently connected radio.
  /// (Experimental — lives in the Debug tab while the online update check is
  /// still being worked out.)
  void _onFirmwareUpdate() {
    final bt = BluetoothService();
    int id = _broker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;
    if (id <= 0 || bt.radioInstance(id) == null) {
      final radios =
          _broker.getJsonListValue<ConnectedRadioInfo>(
            1,
            'ConnectedRadios',
            (json) => ConnectedRadioInfo.fromJson(json),
          ) ??
          const [];
      id = -1;
      for (final r in radios) {
        if (bt.radioInstance(r.deviceId) != null) {
          id = r.deviceId;
          break;
        }
      }
    }
    if (id <= 0 || bt.radioInstance(id) == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No radio connected.')),
      );
      return;
    }
    showFirmwareUpdateDialog(context, id);
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
      outputPath = await FilePicker.saveFile(
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

  void _onQueryDeviceNames() {
    // Publish through the broker so the message flows back into the Debug tab
    // via 'DebugLogEntries' like every other application log message.
    _broker.logInfo('Querying device names...');
    // Simulate device query
    Future.delayed(const Duration(milliseconds: 500), () {
      _broker.logInfo('List of devices:');
      _broker.logInfo('  No devices found');
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
        // Firmware update is only supported over Bluetooth Classic transports.
        if (!kIsWeb &&
            (Platform.isWindows ||
                Platform.isMacOS ||
                Platform.isAndroid)) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'firmwareUpdate',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: const Row(
              children: [SizedBox(width: 20), Text('Firmware Update...')],
            ),
          ),
        ],
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
          setState(() => _showBluetoothFrames = !_showBluetoothFrames);
          // Publish the toggle so the Radio layer starts/stops logging every
          // incoming and outgoing control-channel Bluetooth frame. Persisted
          // so the setting survives across launches.
          _broker.dispatch(
            deviceId: 0,
            name: 'BluetoothFramesDebug',
            data: _showBluetoothFrames,
            store: true,
          );
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
        case 'firmwareUpdate':
          _onFirmwareUpdate();
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
