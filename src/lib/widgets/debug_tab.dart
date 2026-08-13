import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'tab_visibility.dart';
import '../dialogs/aprs_symbols_dialog.dart';
import '../dialogs/radio_settings_dialog.dart';
import '../echolink/echolink_client.dart' show echoLinkDeviceId;
import '../l10n/app_localizations.dart';
import '../dialogs/raw_command_dialog.dart';
import '../models/radio_models.dart';
import '../services/bluetooth_service.dart';
import '../services/crash_logger.dart';
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
    with AutomaticKeepAliveClientMixin, TabVisibilityStateMixin {
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

  /// Resolves the device id of a currently connected radio, or -1 if none.
  /// Prefers the user's selected radio, falling back to the first connected
  /// radio instance.
  int _resolveConnectedRadioId() {
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
    if (id <= 0 || bt.radioInstance(id) == null) return -1;
    return id;
  }

  /// Test helper: plays a WAV file into the app as if it were received audio on
  /// VFO A of the connected radio, so the SSTV / Morse / SARSAT decoders (and
  /// the UI) process it. Only 32 kHz / 16-bit / mono PCM WAV is accepted, since
  /// that is the format the receive pipeline uses (no resampling).
  Future<void> _onPlayWavToVfoA() async {
    final deviceId = _resolveConnectedRadioId();
    if (deviceId < 0) {
      _snack('Connect a radio first — audio is replayed on its VFO A.');
      return;
    }
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select a 32 kHz / 16-bit / mono WAV',
      type: FileType.custom,
      allowedExtensions: const ['wav'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      _snack('Could not read the file: $e');
      return;
    }
    if (!mounted) return;

    final wav = _parseWav(bytes);
    if (wav == null) {
      _snack('Not a valid PCM WAV file.');
      return;
    }
    if (wav.sampleRate != 32000 || wav.channels != 1 || wav.bits != 16) {
      _snack(
        'WAV must be 32000 Hz, 16-bit, mono — got '
        '${wav.sampleRate} Hz, ${wav.channels} ch, ${wav.bits}-bit.',
      );
      return;
    }

    final channelName = _vfoAChannelName(deviceId);
    final durationMs = (wav.pcm.length / 2 / 32.0).round(); // 32 samples/ms
    _broker.logInfo(
      "[Debug] Replaying '${path.split(Platform.pathSeparator).last}' "
      "(${durationMs}ms) as received audio on device $deviceId VFO A "
      "channel '${channelName.isEmpty ? '(none)' : channelName}'",
    );
    _snack(
      "Playing ${durationMs}ms to VFO A "
      "(channel '${channelName.isEmpty ? '(none)' : channelName}')",
    );
    await _injectReceivedAudio(deviceId, wav.pcm, channelName);
  }

  /// Dispatches [pcm] as a received-audio run on [deviceId], mirroring the
  /// radio's own AudioDataStart / AudioDataAvailable / AudioDataEnd sequence.
  Future<void> _injectReceivedAudio(
    int deviceId,
    Uint8List pcm,
    String channelName,
  ) async {
    final startMs = DateTime.now().millisecondsSinceEpoch;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataStart',
      data: <String, Object?>{
        'startTime': startMs,
        'channelName': channelName,
        'transmit': false,
        'muted': false,
        'usage': null,
      },
      store: false,
    );
    const chunk = 2048; // bytes (even), ~32 ms at 32 kHz
    for (int off = 0; off < pcm.length; off += chunk) {
      final len = (off + chunk <= pcm.length) ? chunk : pcm.length - off;
      _broker.dispatch(
        deviceId: deviceId,
        name: 'AudioDataAvailable',
        data: <String, Object?>{
          'data': pcm,
          'offset': off,
          'length': len,
          'channelName': channelName,
          'transmit': false,
          'muted': false,
          'audioRunStartTime': startMs,
          'usage': null,
        },
        store: false,
      );
      // Yield so a long file doesn't freeze the UI while decoders run.
      await Future<void>.delayed(Duration.zero);
    }
    _broker.dispatch(
      deviceId: deviceId,
      name: 'AudioDataEnd',
      data: <String, Object?>{
        'startTime': startMs,
        'transmit': false,
        'usage': null,
      },
      store: false,
    );
  }

  /// Resolves the VFO A channel name for [deviceId] from the cached radio state.
  String _vfoAChannelName(int deviceId) {
    final settings = _broker.getValueDynamic(deviceId, 'Settings');
    if (settings is! Map) return '';
    final channelA = settings['channelA'];
    if (channelA is! int) return '';
    final channels = _broker.getValueDynamic(deviceId, 'Channels');
    if (channels is! List) return '';
    for (final ch in channels) {
      if (ch is Map && ch['channelId'] == channelA) {
        final name = ch['name'];
        if (name is String) return name;
      }
    }
    return '';
  }

  /// Parses a PCM WAV header, returning its raw sample bytes and format.
  ({Uint8List pcm, int sampleRate, int channels, int bits})? _parseWav(
    Uint8List bytes,
  ) {
    if (bytes.length < 44) return null;
    final bd = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;
    int pos = 12;
    int audioFormat = 0, channels = 0, sampleRate = 0, bits = 0;
    int dataOffset = -1, dataLen = 0;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      if (id == 'fmt ') {
        audioFormat = bd.getUint16(pos + 8, Endian.little);
        channels = bd.getUint16(pos + 10, Endian.little);
        sampleRate = bd.getUint32(pos + 12, Endian.little);
        bits = bd.getUint16(pos + 22, Endian.little);
      } else if (id == 'data') {
        dataOffset = pos + 8;
        dataLen = size;
        break;
      }
      pos += 8 + size + (size & 1);
    }
    if (dataOffset < 0 || audioFormat != 1) return null;
    if (dataOffset + dataLen > bytes.length) dataLen = bytes.length - dataOffset;
    final pcm = Uint8List.sublistView(bytes, dataOffset, dataOffset + dataLen);
    return (pcm: pcm, sampleRate: sampleRate, channels: channels, bits: bits);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the raw command test dialog for the currently connected radio.
  void _onRawCommand() {
    final id = _resolveConnectedRadioId();
    if (id < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).commonNoRadioConnected),
        ),
      );
      return;
    }
    showRawCommandDialog(context, id);
  }

  /// Resolves the radio the experimental Radio Settings dialog should target.
  /// Returns -1 (menu item disabled) when the preferred radio is EchoLink or
  /// when no connected Bluetooth radio is available. EchoLink has no radio
  /// instance, so it can never be the resolved target.
  int _radioSettingsTargetId() {
    final selected =
        _broker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;
    // If the user's preferred radio is EchoLink, this dialog does not apply.
    if (selected == echoLinkDeviceId) return -1;
    final bt = BluetoothService();
    if (selected > 0 && bt.radioInstance(selected) != null) return selected;
    return _resolveConnectedRadioId();
  }

  /// Opens the experimental Radio Settings dialog for the preferred radio.
  void _onRadioSettings() {
    final id = _radioSettingsTargetId();
    if (id < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).commonNoRadioConnected),
        ),
      );
      return;
    }
    showRadioSettingsDialog(context, id);
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
        dialogTitle: AppLocalizations.of(context).debugSaveTitle,
        fileName: defaultFileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).errorOpeningFileDialog(e.toString()),
            ),
          ),
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
            SnackBar(
              content: Text(
                AppLocalizations.of(context).debugLogSavedTo(outputPath),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).errorSavingFile(e.toString()),
              ),
            ),
          );
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

  /// Opens the user's browser to a pre-filled GitHub "New Issue" so a crash can
  /// be reported with no server and no telemetry: the user reviews and submits
  /// it under their own GitHub account, attaching the full crash log file.
  Future<void> _onReportCrash() async {
    // In-memory Debug log fallback for platforms without an on-disk crash log
    // (e.g. web); the on-disk log tail is preferred when available.
    final StringBuffer fallback = StringBuffer();
    for (final entry in _logEntries) {
      final t = _formatTime(entry.time);
      fallback.writeln(
        entry.isError
            ? '[$t] [Error] ${entry.message}'
            : '[$t] ${entry.message}',
      );
    }

    final Uri uri = await CrashLogger.instance.buildGithubIssueUri(
      fallbackLog: fallback.toString(),
    );

    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Opening a pre-filled crash report in your browser. Please attach the crash log file before submitting.'
              : 'Could not open the browser. Please file an issue at github.com/${CrashLogger.githubRepo}/issues.',
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    // The experimental Radio Settings dialog is only available when the
    // preferred radio is a connected Bluetooth radio (never EchoLink).
    final bool radioSettingsEnabled = _radioSettingsTargetId() >= 0;

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
            children: [const SizedBox(width: 20), Text(l10n.tabSaveToFile)],
          ),
        ),
        PopupMenuItem<String>(
          value: 'reportCrash',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text('Report a Crash...')],
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
              Text(l10n.debugShowBluetoothFrames),
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
              Text(l10n.debugLoopbackMode),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'queryDeviceNames',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.debugQueryDeviceNames)],
          ),
        ),
        PopupMenuItem<String>(
          value: 'rawCommand',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.debugRawCommand)],
          ),
        ),
        PopupMenuItem<String>(
          value: 'radioSettings',
          enabled: radioSettingsEnabled,
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(
                'Radio Settings...',
                style: radioSettingsEnabled
                    ? null
                    : TextStyle(color: Theme.of(context).disabledColor),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'aprsSymbols',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text('APRS Symbols...')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'playWavRx',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text('Play WAV to VFO A (Test RX)...'),
            ],
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
              Text(l10n.debugAutoScroll),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(children: [const SizedBox(width: 20), Text(l10n.tabClear)]),
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
                Text(l10n.debugShowBuiltInMenus),
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
            child: Row(
              children: [const SizedBox(width: 20), Text(l10n.tabDetach)],
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
        case 'reportCrash':
          await _onReportCrash();
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
        case 'rawCommand':
          _onRawCommand();
          break;
        case 'radioSettings':
          _onRadioSettings();
          break;
        case 'aprsSymbols':
          if (context.mounted) showAprsSymbolsDialog(context);
          break;
        case 'playWavRx':
          await _onPlayWavToVfoA();
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context).tabDebug,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  colorBlendMode: BlendMode.srcIn,
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
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
                        color: scheme.onSurfaceVariant,
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
                        color: entry.isError ? Colors.red : scheme.onSurface,
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
