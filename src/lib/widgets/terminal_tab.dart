/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'tab_visibility.dart';

import '../dialogs/active_station_selector_dialog.dart';
import '../dialogs/add_station_dialog.dart';
import '../handlers/terminal_handler.dart';
import '../l10n/app_localizations.dart';
import '../models/radio_models.dart';
import '../models/station_info.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';

/// Represents a piece of text with a specific color in the terminal.
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

/// Terminal tab - a packet-radio terminal ported from the C#
/// `TerminalTabUserControl`.
///
/// The connection engine lives in [TerminalHandler]; this tab picks the radio
/// and station, sends `Terminal*` commands over the DataBroker (device 1), and
/// renders the handler's `TerminalState`, `TerminalText` and `TerminalNotice`
/// events. The same engine serves detached windows and test agents.
class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key});

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

/// A line of terminal output, tracking the originating/target callsigns so that
/// consecutive fragments from the same source are merged (port of the C#
/// `TerminalText` helper used by `AppendTerminalString`).
class _TerminalLine {
  String? from; // null for outgoing/system lines
  final String? to;
  final bool outgoing;
  final bool system;

  /// Whether this visual line should be prefixed with the sender's callsign
  /// (when the "Show Callsign" option is enabled). Computed at append time,
  /// mirroring the C# `AppendTerminalString` logic.
  bool showCallsignPrefix;
  String text;

  _TerminalLine({
    this.from,
    this.to,
    this.outgoing = false,
    this.system = false,
    this.showCallsignPrefix = false,
    this.text = '',
  });
}

class _TerminalTabState extends State<TerminalTab>
    with AutomaticKeepAliveClientMixin, TabVisibilityStateMixin {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  // Radios, for choosing one that is free.
  final List<int> _connectedRadios = [];
  final Map<int, RadioLockState> _lockStates = {};

  // The engine's published state (see TerminalHandler).
  Map<Object?, Object?> _state = const {};

  // Set while a connect this tab requested has not been answered, so contact
  // problems reported by the engine open the fix dialog only here.
  bool _awaitingConnect = false;

  // Settings (persisted on broker device 0).
  bool _showCallsign = false;
  bool _wordWrap = false;

  // Terminal content.
  final List<_TerminalLine> _lines = [];

  // Per-line callsign tracking, mirroring the C# `AppendTerminalString` state:
  // the last sender whose callsign was shown, and whether the cursor is at the
  // start of a fresh line.
  String? _lastFrom;
  bool _atLineStart = true;

  @override
  bool get wantKeepAlive => true;

  String get _status => (_state['status'] as String?) ?? 'idle';

  bool get _isConnected => _status != TerminalStatus.idle.name;

  bool get _pendingDisconnect => _state['pendingDisconnect'] == true;

  Map<Object?, Object?>? get _transfer =>
      _state['transfer'] is Map ? _state['transfer']! as Map : null;

  @override
  void initState() {
    super.initState();

    _showCallsign =
        _broker.getValue<bool>(0, 'TerminalShowCallsign', false) ?? false;
    _wordWrap = _broker.getValue<bool>(0, 'TerminalWordWrap', false) ?? false;

    _loadConnectedRadios();
    _applyState(_broker.getValueDynamic(1, 'TerminalState', null));

    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadios,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockState',
      callback: _onLockState,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'TerminalState',
      callback: (_, _, data) {
        if (mounted) setState(() => _applyState(data));
      },
    );
    _broker.subscribe(deviceId: 1, name: 'TerminalText', callback: _onText);
    _broker.subscribe(deviceId: 1, name: 'TerminalNotice', callback: _onNotice);
    _broker.subscribe(
      deviceId: 1,
      name: 'TerminalFileReceived',
      callback: _onFileReceived,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _applyState(Object? data) {
    _state = data is Map ? data : const {};
  }

  void _command(String name, [Object? data]) =>
      _broker.dispatch(deviceId: 1, name: name, data: data, store: false);

  // ---------------------------------------------------------------------------
  // Radios
  // ---------------------------------------------------------------------------

  void _loadConnectedRadios() {
    _connectedRadios.clear();
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (radios is List) {
      for (final item in radios) {
        if (item is! Map) continue;
        final deviceId = item['DeviceId'] ?? item['deviceId'];
        if (deviceId is int && deviceId > 0) {
          _connectedRadios.add(deviceId);
          final lock = _broker.getJsonValue<RadioLockState>(
            deviceId,
            'LockState',
            (json) => RadioLockState.fromJson(json),
          );
          if (lock != null) _lockStates[deviceId] = lock;
        }
      }
    }
  }

  void _onConnectedRadios(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _loadConnectedRadios();
      _lockStates.removeWhere((id, _) => !_connectedRadios.contains(id));
    });
  }

  void _onLockState(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      if (data is Map<String, dynamic>) {
        _lockStates[deviceId] = RadioLockState.fromJson(data);
      } else if (data == null) {
        _lockStates.remove(deviceId);
      }
    });
  }

  List<int> get _availableRadios {
    final result = <int>[];
    for (final radioId in _connectedRadios) {
      final lock = _lockStates[radioId];
      if (lock == null || !lock.isLocked) result.add(radioId);
    }
    return result;
  }

  String _friendlyName(int radioId) {
    return _broker.getValue<String>(
          radioId,
          'FriendlyName',
          'Radio $radioId',
        ) ??
        'Radio $radioId';
  }

  Future<int?> _chooseRadio() async {
    final available = _availableRadios;
    if (available.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).terminalNoRadio)),
      );
      return null;
    }
    if (available.length == 1) return available.first;
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).stateSelectRadio),
        children: [
          for (final radioId in available)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(radioId),
              child: Text(_friendlyName(radioId)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _onConnectPressed() async {
    if (_isConnected) {
      _command('TerminalDisconnect');
      return;
    }
    final radioId = await _chooseRadio();
    if (radioId == null || !mounted) return;
    final station = await showActiveStationSelector(
      context,
      stationType: StationType.terminal,
    );
    if (station == null) return;
    _awaitingConnect = true;
    _command('TerminalConnect', <String, Object?>{
      'RadioId': radioId,
      'Station': station.toJson(),
    });
    _awaitingConnect = false;
    _inputFocus.requestFocus();
  }

  Future<void> _onWaitForConnectionPressed() async {
    if (_isConnected) return;
    final radioId = await _chooseRadio();
    if (radioId == null || !mounted) return;
    _command('TerminalWait', <String, Object?>{'RadioId': radioId});
    _inputFocus.requestFocus();
  }

  void _onSend() {
    final text = _inputController.text;
    if (text.isEmpty) return;
    _command('TerminalSend', <String, Object?>{'Text': text});
    _inputController.clear();
    _inputFocus.requestFocus();
  }

  /// Prompts the user to pick a file and sends it over the active session using
  /// the YAPP protocol.
  Future<void> _onSendFilePressed() async {
    if (_state['canSendFile'] != true) {
      _appendSystem(
        '*** ${AppLocalizations.of(context).terminalNotConnected} ***',
      );
      return;
    }
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    Uint8List? bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (!mounted) return;
    if (bytes == null) {
      _appendSystem(
        '*** ${AppLocalizations.of(context).terminalFileTransferError(file.name)} ***',
      );
      return;
    }
    _command('TerminalSendFile', <String, Object?>{
      'Name': file.name,
      'Data': bytes,
    });
  }

  // ---------------------------------------------------------------------------
  // Engine events
  // ---------------------------------------------------------------------------

  void _onText(int deviceId, String name, Object? data) {
    if (!mounted || data is! Map) return;
    _appendString(
      outgoing: data['outgoing'] == true,
      from: data['from'] as String?,
      to: data['to'] as String?,
      text: (data['text'] as String?) ?? '',
    );
  }

  void _onNotice(int deviceId, String name, Object? data) {
    if (!mounted || data is! Map) return;
    final l10n = AppLocalizations.of(context);
    final kind = data['kind'] as String?;
    String arg(String key) => '${data[key] ?? ''}';

    // Contact problems: offer to fix the contact when this tab asked for the
    // connection; otherwise (an agent or another window) just report it.
    if (kind == TerminalNotices.regionMissing ||
        kind == TerminalNotices.channelMissing) {
      final station = data['station'];
      if (station is! Map) return;
      final info = StationInfo.fromJson(station.cast<String, dynamic>());
      final message = kind == TerminalNotices.regionMissing
          ? l10n.stationConnectErrorRegion(info.channelRegion)
          : l10n.stationConnectErrorChannel(info.channel);
      if (_awaitingConnect) {
        showStationConnectErrorDialog(context, station: info, message: message);
      } else {
        _appendSystem('*** $message ***');
      }
      return;
    }

    final String? text = switch (kind) {
      TerminalNotices.connecting => l10n.terminalConnectingTo(arg('callsign')),
      TerminalNotices.connected => l10n.stateConnected,
      TerminalNotices.connectedTo => l10n.terminalConnectedTo(arg('callsign')),
      TerminalNotices.connectedFrom => l10n.terminalConnectedFrom(
        arg('callsign'),
      ),
      TerminalNotices.disconnecting => l10n.statusDisconnecting,
      TerminalNotices.disconnected => l10n.stateDisconnected,
      TerminalNotices.waiting => l10n.terminalWaitingForConnection,
      TerminalNotices.notConnected => l10n.terminalNotConnected,
      TerminalNotices.busy => l10n.terminalBusy,
      TerminalNotices.invalidCallsignDest => l10n.terminalInvalidCallsignDest,
      TerminalNotices.invalidCallsign => l10n.terminalInvalidCallsign,
      TerminalNotices.brotli => l10n.terminalBrotli,
      TerminalNotices.error => l10n.terminalError(
        '${_errorText(arg('error'))}'
        '${data['details'] is String ? ' [${arg('details')}]' : ''}',
      ),
      TerminalNotices.transferInProgress => l10n.terminalTransferInProgress,
      TerminalNotices.sendingFile => l10n.terminalSendingFile(arg('filename')),
      TerminalNotices.fileSent => l10n.terminalFileSent(arg('filename')),
      TerminalNotices.fileReceived => l10n.terminalFileReceived(
        arg('filename'),
        (data['size'] as num?)?.toInt() ?? 0,
      ),
      TerminalNotices.fileTransferError => l10n.terminalFileTransferError(
        arg('message'),
      ),
      _ => null,
    };
    if (text != null) _appendSystem('*** $text ***');
  }

  /// Localizes engine error codes; other errors (e.g. AX.25) pass through.
  String _errorText(String error) {
    final l10n = AppLocalizations.of(context);
    return switch (error) {
      TerminalNotices.xaraRequiresAudio => l10n.terminalXaraRequiresAudio,
      TerminalNotices.xaraNoAnswer => l10n.terminalXaraNoAnswer,
      TerminalNotices.xaraLockTimeout => l10n.terminalXaraLockTimeout,
      TerminalNotices.xaraDisconnectTimeout =>
        l10n.terminalXaraDisconnectTimeout,
      TerminalNotices.invalidCallsignDest => l10n.terminalInvalidCallsignDest,
      _ => error,
    };
  }

  /// Prompts the user to save a file received over YAPP.
  Future<void> _onFileReceived(int deviceId, String name, Object? data) async {
    if (!mounted || data is! Map) return;
    final fileName = data['Name'];
    final raw = data['Data'];
    if (fileName is! String || raw is! List) return;
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw.cast<int>());
    try {
      await FilePicker.saveFile(
        dialogTitle: AppLocalizations.of(context).terminalSaveFileTitle,
        fileName: fileName,
        bytes: bytes,
      );
    } catch (_) {
      // User cancelled the save dialog or the platform threw; the file bytes
      // are simply discarded.
    }
  }

  // ---------------------------------------------------------------------------
  // Terminal text model (port of AppendTerminalString)
  // ---------------------------------------------------------------------------

  void _appendSystem(String text) {
    setState(() {
      _lines.add(_TerminalLine(system: true, text: text));
      // A system line is always on its own line and breaks the callsign run.
      _atLineStart = true;
      _lastFrom = null;
    });
    _scrollToBottom();
  }

  /// Appends received/sent [text] to the terminal, split into visual lines and
  /// prefixed with the sender's callsign per line when "Show Callsign" is on.
  ///
  /// This is a direct port of the C# `AppendTerminalString`: it tracks
  /// [_lastFrom] and [_atLineStart] across calls so the callsign is shown only
  /// when the sender changes or a new line begins, and consecutive fragments
  /// from the same sender on the same unfinished line are merged.
  void _appendString({
    required bool outgoing,
    required String? from,
    required String? to,
    required String text,
  }) {
    if (text.isEmpty) return;

    // Normalize line endings, then strip C0 control characters (0x00-0x1F) and
    // DEL (0x7F) - keeping only Tab (0x09) and newline (0x0A) - so non-printable
    // codes can't hide or clip surrounding characters in the renderer. Done via
    // code units so no literal control bytes appear in this source file.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = String.fromCharCodes(
      text.codeUnits.where((c) {
        if (c == 0x0A) return true; // keep newline (line separator)
        if (c == 0x09) return true; // keep tab
        if (c < 0x20) return false; // drop other C0 controls
        if (c == 0x7F) return false; // drop DEL
        return true;
      }),
    );

    final lines = text.split('\n');

    setState(() {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final isLastLine = (i == lines.length - 1);

        // Skip a trailing empty fragment (the text ended with a newline).
        if (line.isEmpty && isLastLine) continue;

        // Decide whether to show the callsign for this line, mirroring the C#
        // rule: only when the sender changed or we're at the start of a line.
        var showPrefix = false;
        if (_showCallsign && from != null && from.isNotEmpty) {
          if (_lastFrom != from || _atLineStart) {
            showPrefix = true;
            _lastFrom = from;
          }
        }

        // Append the line text. When we're mid-line (not at line start) and not
        // forcing a new callsign prefix, merge onto the current visual line;
        // otherwise start a new line.
        final canMerge =
            !_atLineStart &&
            !showPrefix &&
            _lines.isNotEmpty &&
            !_lines.last.system &&
            _lines.last.outgoing == outgoing &&
            _lines.last.from == from;
        if (canMerge) {
          _lines.last.text += line;
        } else {
          _lines.add(
            _TerminalLine(
              from: from,
              to: to,
              outgoing: outgoing,
              showCallsignPrefix: showPrefix,
              text: line,
            ),
          );
        }

        if (!isLastLine) {
          // The line is terminated; the next text starts a fresh line.
          _atLineStart = true;
        } else {
          // For the last fragment we're at line start only if it was empty.
          _atLineStart = line.isEmpty;
        }
      }
    });
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

  /// Recomputes [showCallsignPrefix] for every existing line, mirroring the
  /// append-time logic. Called when "Show Callsign" is toggled so that all
  /// existing lines immediately reflect the new setting.
  void _recomputeCallsignPrefixes() {
    for (final line in _lines) {
      if (line.system) {
        line.showCallsignPrefix = false;
        continue;
      }
      line.showCallsignPrefix =
          _showCallsign && line.from != null && line.from!.isNotEmpty;
    }
  }

  /// Builds the colored spans for a single line, honoring "Show Callsign".
  List<TerminalTextSpan> _spansForLine(_TerminalLine line) {
    if (line.system) {
      return [TerminalTextSpan(line.text, color: Colors.yellow, bold: true)];
    }

    final spans = <TerminalTextSpan>[];
    if (_showCallsign && line.showCallsignPrefix && line.from != null) {
      spans.add(
        TerminalTextSpan(
          '${line.from}: ',
          color: line.outgoing ? Colors.lightBlueAccent : Colors.greenAccent,
          bold: true,
        ),
      );
    }
    spans.add(
      TerminalTextSpan(
        line.text,
        color: line.outgoing ? Colors.lightBlueAccent : Colors.white70,
      ),
    );
    return spans;
  }

  // ---------------------------------------------------------------------------
  // Menu
  // ---------------------------------------------------------------------------

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
              Text(AppLocalizations.of(context).terminalShowCallsign),
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
              Text(AppLocalizations.of(context).terminalWordWrap),
            ],
          ),
        ),
        // "Wait for Connection" listens for an incoming connected-mode AX.25
        // session. Available only when not already connected/waiting and a free
        // radio exists.
        PopupMenuItem<String>(
          value: 'waitForConnection',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: !_isConnected && _availableRadios.isNotEmpty,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).terminalWaitForConnection),
            ],
          ),
        ),
        // "Send File" transfers a file to the connected station using the YAPP
        // protocol. Available only over a connected AX.25 session that is not
        // already busy with a transfer.
        PopupMenuItem<String>(
          value: 'sendFile',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _state['canSendFile'] == true,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).terminalSendFile),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).tabClear),
            ],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Text(AppLocalizations.of(context).tabDetach),
              ],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'showCallsign':
          setState(() {
            _showCallsign = !_showCallsign;
            _recomputeCallsignPrefixes();
          });
          _broker.dispatch(
            deviceId: 0,
            name: 'TerminalShowCallsign',
            data: _showCallsign,
            store: true,
          );
          break;
        case 'wordWrap':
          setState(() => _wordWrap = !_wordWrap);
          _broker.dispatch(
            deviceId: 0,
            name: 'TerminalWordWrap',
            data: _wordWrap,
            store: true,
          );
          break;
        case 'waitForConnection':
          _onWaitForConnectionPressed();
          break;
        case 'sendFile':
          _onSendFilePressed();
          break;
        case 'clear':
          setState(() {
            _lines.clear();
            _lastFrom = null;
            _atLineStart = true;
          });
          break;
        case 'detach':
          windowService.createWindow('terminal');
          break;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Container(color: Colors.black, child: _buildTerminalText()),
        ),
        _buildTransferPanel(),
        _buildInputPanel(),
      ],
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final connected = _isConnected;
    final remote = _state['remote'] as String?;
    final String title;
    if (connected && _status == TerminalStatus.waiting.name) {
      title = l10n.terminalWaitingForConnection;
    } else if (connected && remote != null && remote.isNotEmpty) {
      title = l10n.terminalHeaderWith(remote);
    } else {
      title = l10n.tabTerminal;
    }
    return Container(
      height: 40,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButton = constraints.maxWidth > 220;
          return Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (showButton) ...[
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed:
                        _pendingDisconnect ||
                            (_connectedRadios.isEmpty && !connected)
                        ? null
                        : _onConnectPressed,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(
                      _pendingDisconnect
                          ? l10n.statusDisconnecting
                          : connected
                          ? l10n.commonDisconnect
                          : l10n.commonConnect,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
          );
        },
      ),
    );
  }

  Widget _buildTerminalText() {
    final spans = <TerminalTextSpan>[];
    for (var i = 0; i < _lines.length; i++) {
      // Separate each terminal line with a newline, mirroring the C#
      // AppendTerminalString which prepends Environment.NewLine before every
      // line except the first. Without this, all lines render concatenated on
      // a single visual line.
      if (i > 0) spans.add(const TerminalTextSpan('\n'));
      spans.addAll(_spansForLine(_lines[i]));
    }

    final richText = SelectableText.rich(
      TextSpan(
        children: spans
            .map(
              (span) => TextSpan(
                text: span.text,
                style: TextStyle(
                  color: span.color,
                  fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            )
            .toList(),
      ),
      style: const TextStyle(
        fontFamily: 'Courier New',
        fontFamilyFallback: ['monospace', 'Courier'],
        fontSize: 14,
        height: 1.3,
      ),
    );

    // When word wrap is on, let the text fill the available width and wrap.
    if (_wordWrap) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        child: SizedBox(width: double.infinity, child: richText),
      );
    }

    // When word wrap is off, allow horizontal scrolling of long lines while
    // still stretching the content to at least the full viewport width so the
    // terminal occupies the entire tab width.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Subtract the horizontal padding so the min-width matches the
        // available content area exactly.
        final minWidth = constraints.maxWidth - 16;
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minWidth > 0 ? minWidth : 0,
              ),
              child: IntrinsicWidth(child: richText),
            ),
          ),
        );
      },
    );
  }

  /// Shows the current YAPP file-transfer progress, or nothing when idle.
  Widget _buildTransferPanel() {
    final transfer = _transfer;
    if (transfer == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final filename = '${transfer['filename'] ?? ''}';
    final size = (transfer['fileSize'] as num?)?.toInt() ?? 0;
    final done = (transfer['bytesTransferred'] as num?)?.toInt() ?? 0;
    final fraction = size > 0 ? (done / size).clamp(0.0, 1.0) : 0.0;
    final sending = transfer['direction'] == 'send';
    final label = sending
        ? l10n.terminalSendingFile(filename)
        : l10n.terminalReceivingFile(filename);
    final pct = (fraction * 100).toStringAsFixed(0);
    return Container(
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Icon(
            sending ? Icons.upload_file : Icons.download,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: size > 0 ? fraction : null,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      sending ? Colors.lightBlue : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('$done/$size ($pct%)', style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.terminalCancelTransfer,
            visualDensity: VisualDensity.compact,
            onPressed: () => _command('TerminalCancelTransfer'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputPanel() {
    final scheme = Theme.of(context).colorScheme;
    // The engine reports when text can be sent (connected, no transfer).
    final enabled = _isConnected && _state['canSend'] == true;
    return Container(
      height: 50,
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: enabled
                    ? scheme.surface
                    : scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                enabled: enabled,
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
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: enabled ? _onSend : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(AppLocalizations.of(context).terminalSend),
            ),
          ),
        ],
      ),
    );
  }
}
