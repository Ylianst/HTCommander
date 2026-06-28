/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../dialogs/add_torrent_file_dialog.dart';
import '../models/radio_models.dart';
import '../models/torrent_file.dart';
import '../radio/radio.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';
import '../utils/compression.dart';
import 'torrent_blocks_view.dart';

/// A read-only view of a torrent file decoded from the DataBroker map
/// (`TorrentFile.toBrokerMap`).
///
/// The UI never holds the actual block data; only enough metadata to render the
/// list, the details panel and the block grid. Commands sent back to the
/// [TorrentHandler] are keyed by [id].
class _TorrentView {
  _TorrentView({
    required this.id,
    required this.key,
    required this.fileName,
    required this.description,
    required this.callsign,
    required this.stationId,
    required this.size,
    required this.compressedSize,
    required this.compression,
    required this.mode,
    required this.completed,
    required this.totalBlocks,
    required this.receivedBlocks,
  });

  final Uint8List? id;
  final String key;
  final String fileName;
  final String description;
  final String callsign;
  final int stationId;
  final int size;
  final int compressedSize;
  final TorrentCompression compression;
  final TorrentMode mode;
  final bool completed;
  final int totalBlocks;
  final int receivedBlocks;

  String get source => stationId > 0 ? '$callsign-$stationId' : callsign;

  double get progress => totalBlocks > 0 ? receivedBlocks / totalBlocks : 0.0;

  static _TorrentView? fromMap(Object? data) {
    if (data is! Map) return null;
    final id = _decodeBytes(data['Id']);
    final callsign = (data['Callsign'] as String?) ?? '';
    final stationId = _toInt(data['StationId']);
    final fileName = (data['FileName'] as String?) ?? '';
    final key = id != null && id.isNotEmpty
        ? _bytesToHex(id)
        : '$callsign-$stationId-$fileName';
    return _TorrentView(
      id: id,
      key: key,
      fileName: fileName,
      description: (data['Description'] as String?) ?? '',
      callsign: callsign,
      stationId: stationId,
      size: _toInt(data['Size']),
      compressedSize: _toInt(data['CompressedSize']),
      compression: _compressionFromName(data['Compression'] as String?),
      mode: _modeFromName(data['Mode'] as String?),
      completed: (data['Completed'] as bool?) ?? false,
      totalBlocks: _toInt(data['TotalBlocks']),
      receivedBlocks: _toInt(data['ReceivedBlocks']),
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static Uint8List? _decodeBytes(Object? value) {
    if (value == null) return null;
    if (value is String) {
      try {
        return Uint8List.fromList(base64Decode(value));
      } catch (_) {
        return null;
      }
    }
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static TorrentCompression _compressionFromName(String? name) {
    switch (name) {
      case 'None':
        return TorrentCompression.none;
      case 'Deflate':
        return TorrentCompression.deflate;
      case 'Brotli':
        return TorrentCompression.brotli;
      default:
        return TorrentCompression.unknown;
    }
  }

  static TorrentMode _modeFromName(String? name) {
    switch (name) {
      case 'Sharing':
        return TorrentMode.sharing;
      case 'Request':
        return TorrentMode.request;
      case 'Error':
        return TorrentMode.error;
      case 'Pause':
      default:
        return TorrentMode.pause;
    }
  }
}

/// Torrent tab - file transfer functionality.
///
/// Port of the C# `TorrentTabUserControl`. All torrent state lives in the
/// [TorrentHandler]; this tab is a thin view that:
///   * subscribes to `TorrentFiles` / `TorrentFileUpdate` (device 0) and
///     `ConnectedRadios` / `LockState` to drive the Activate button,
///   * dispatches `TorrentGetFiles`, `TorrentAddFile`, `TorrentRemoveFile`,
///     `TorrentSetFileMode`, `TorrentSaveFile`,
///   * locks/unlocks a connected radio to `Torrent` usage via `SetLock` /
///     `SetUnlock`.
class TorrentTab extends StatefulWidget {
  const TorrentTab({super.key});

  @override
  State<TorrentTab> createState() => _TorrentTabState();
}

class _TorrentTabState extends State<TorrentTab>
    with AutomaticKeepAliveClientMixin {
  final DataBrokerClient _broker = DataBrokerClient();

  // Torrent files keyed by [_TorrentView.key], preserving insertion order.
  final List<_TorrentView> _torrents = [];
  String? _selectedKey;

  // Radio / lock state used to drive the Activate button.
  final List<int> _connectedRadios = [];
  final Map<int, RadioLockState> _lockStates = {};

  bool _showDetails = true;
  bool _dragging = false;
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  double _detailsHeightRatio = 0.35;
  static const double _minDetailsRatio = 0.15;
  static const double _maxDetailsRatio = 0.60;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _showDetails =
        _broker.getValue<bool>(0, 'TorrentShowDetails', true) ?? true;

    _loadConnectedRadios();

    _broker.subscribe(deviceId: 0, name: 'TorrentFiles', callback: _onFiles);
    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentFileUpdate',
      callback: _onFileUpdate,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'TorrentSaveFileResult',
      callback: _onSaveFileResult,
    );
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

    // Request the current state from the handler.
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentGetFiles',
      data: null,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // DataBroker subscriptions
  // ---------------------------------------------------------------------------

  void _onFiles(int deviceId, String name, Object? data) {
    if (!mounted || data is! List) return;
    final views = <_TorrentView>[];
    for (final item in data) {
      final view = _TorrentView.fromMap(item);
      if (view != null) views.add(view);
    }
    setState(() {
      _torrents
        ..clear()
        ..addAll(views);
      _sortTorrents();
      if (_selectedKey != null &&
          !_torrents.any((t) => t.key == _selectedKey)) {
        _selectedKey = null;
      }
    });
  }

  void _onFileUpdate(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final view = _TorrentView.fromMap(data);
    if (view == null) return;
    setState(() {
      final index = _torrents.indexWhere((t) => t.key == view.key);
      if (index >= 0) {
        _torrents[index] = view;
      } else {
        _torrents.add(view);
      }
      _sortTorrents();
    });
  }

  void _onSaveFileResult(int deviceId, String name, Object? data) {
    if (!mounted || data is! Map) return;
    final success = (data['Success'] as bool?) ?? false;
    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(const SnackBar(content: Text('File saved.')));
    } else {
      final error = (data['Error'] as String?) ?? 'Unknown error';
      messenger.showSnackBar(
        SnackBar(content: Text('Error saving file: $error')),
      );
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

  // ---------------------------------------------------------------------------
  // Activate / Deactivate (radio lock to "Torrent" usage)
  // ---------------------------------------------------------------------------

  /// The single connected radio currently locked to Torrent usage, or -1.
  int get _activeRadioId {
    for (final radioId in _connectedRadios) {
      final lock = _lockStates[radioId];
      if (lock != null && lock.isLocked && lock.usage == 'Torrent') {
        return radioId;
      }
    }
    return -1;
  }

  bool get _isActivated => _activeRadioId > 0;

  /// Mirrors the C# `UpdateActivateButtonState` single-radio logic: the button
  /// is enabled only when exactly one radio is connected and it is either free
  /// or already locked to Torrent.
  bool get _activateEnabled {
    if (_connectedRadios.length != 1) return false;
    final lock = _lockStates[_connectedRadios.first];
    if (lock != null && lock.isLocked && lock.usage == 'Torrent') return true;
    return lock == null || !lock.isLocked;
  }

  void _onActivate() {
    if (_connectedRadios.isEmpty) {
      _showInfo('No radios connected. Connect a radio first.');
      return;
    }
    if (_connectedRadios.length > 1) {
      _showInfo('Multi-radio torrent mode is not yet supported.');
      return;
    }
    final radioId = _connectedRadios.first;
    final lock = _lockStates[radioId];
    if (lock != null && lock.isLocked && lock.usage == 'Torrent') {
      _broker.dispatch(
        deviceId: radioId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: 'Torrent'),
        store: false,
      );
      _broker.logInfo('[TorrentTab] Deactivating radio $radioId');
    } else if (lock == null || !lock.isLocked) {
      _broker.dispatch(
        deviceId: radioId,
        name: 'SetLock',
        data: SetLockData(usage: 'Torrent', regionId: -1, channelId: -1),
        store: false,
      );
      _broker.logInfo('[TorrentTab] Activating radio $radioId');
    }
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // File commands
  // ---------------------------------------------------------------------------

  Future<void> _onAddFile() async {
    final file = await showAddTorrentFileDialog(context);
    if (file == null) return;
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentAddFile',
      data: file,
      store: false,
    );
  }

  Future<void> _onDropFile(String path) async {
    final file = await showAddTorrentFileDialog(context, initialPath: path);
    if (file == null) return;
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentAddFile',
      data: file,
      store: false,
    );
  }

  void _setMode(_TorrentView view, TorrentMode mode) {
    if (view.id == null) return;
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentSetFileMode',
      data: {'FileId': view.id, 'Mode': _modeCommandName(mode)},
      store: false,
    );
  }

  Future<void> _onSaveAs(_TorrentView view) async {
    if (!view.completed) return;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save Torrent File',
      fileName: view.fileName,
    );
    if (path == null) return;
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentSaveFile',
      data: {'FileId': view.id, 'Path': path},
      store: false,
    );
  }

  Future<void> _onDelete(_TorrentView view) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Torrent'),
        content: const Text('Delete selected torrent file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentRemoveFile',
      data: {'Id': view.id},
      store: false,
    );
    if (_selectedKey == view.key) {
      setState(() => _selectedKey = null);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  _TorrentView? get _selectedTorrent {
    if (_selectedKey == null) return null;
    for (final t in _torrents) {
      if (t.key == _selectedKey) return t;
    }
    return null;
  }

  void _sortTorrents() {
    _torrents.sort((a, b) {
      int result;
      switch (_sortColumnIndex) {
        case 1:
          result = a.mode.index.compareTo(b.mode.index);
          break;
        case 2:
          result = a.description.compareTo(b.description);
          break;
        case 0:
        default:
          result = a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
          break;
      }
      if (result == 0) result = a.source.compareTo(b.source);
      return _sortAscending ? result : -result;
    });
  }

  void _sort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = true;
      }
      _sortTorrents();
    });
  }

  void _toggleShowDetails() {
    setState(() => _showDetails = !_showDetails);
    _broker.dispatch(
      deviceId: 0,
      name: 'TorrentShowDetails',
      data: _showDetails,
      store: true,
    );
  }

  static String _modeCommandName(TorrentMode mode) {
    switch (mode) {
      case TorrentMode.pause:
        return 'Pause';
      case TorrentMode.sharing:
        return 'Sharing';
      case TorrentMode.request:
        return 'Request';
      case TorrentMode.error:
        return 'Error';
    }
  }

  String _modeToString(TorrentMode mode) {
    switch (mode) {
      case TorrentMode.pause:
        return 'Paused';
      case TorrentMode.sharing:
        return 'Sharing';
      case TorrentMode.request:
        return 'Requesting';
      case TorrentMode.error:
        return 'Error';
    }
  }

  String _compressionToString(TorrentCompression compression) {
    switch (compression) {
      case TorrentCompression.unknown:
        return 'Unknown';
      case TorrentCompression.none:
        return 'None';
      case TorrentCompression.brotli:
        return 'Brotli';
      case TorrentCompression.deflate:
        return 'Deflate';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _showDetails
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final totalHeight = constraints.maxHeight;
                    final detailsHeight = totalHeight * _detailsHeightRatio;
                    final listHeight = totalHeight - detailsHeight - 8;
                    return Column(
                      children: [
                        SizedBox(
                          height: listHeight,
                          child: _buildTorrentList(),
                        ),
                        _buildSplitter(totalHeight),
                        SizedBox(
                          height: detailsHeight,
                          child: _buildDetailsPanel(),
                        ),
                      ],
                    );
                  },
                )
              : _buildTorrentList(),
        ),
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
          final showButtons = constraints.maxWidth > 300;
          return Row(
            children: [
              const Text(
                'Torrent',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (showButtons) ...[
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _onAddFile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Add File'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _activateEnabled ? _onActivate : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(_isActivated ? 'Deactivate' : 'Activate'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Builder(
                builder: (context) => InkWell(
                  onTap: () => _showHeaderMenu(context),
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

  void _showHeaderMenu(BuildContext context) {
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
          value: 'showDetails',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showDetails
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show Details'),
            ],
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
      if (value == null) return;
      switch (value) {
        case 'showDetails':
          _toggleShowDetails();
          break;
        case 'detach':
          windowService.createWindow('torrent');
          break;
      }
    });
  }

  void _showRowMenu(_TorrentView view, Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    );

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    final notError = view.mode != TorrentMode.error;
    final canPause = notError;
    final canShare = view.completed && notError;
    final canRequest =
        !view.completed && notError && view.mode != TorrentMode.sharing;
    final canSaveAs = view.completed && notError;

    PopupMenuItem<String> item(
      String value,
      String label, {
      required bool enabled,
      bool checked = false,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: menuItemHeight,
        padding: menuItemPadding,
        enabled: enabled,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: checked
                  ? const Text('✓', style: TextStyle(fontSize: 14))
                  : null,
            ),
            Text(label),
          ],
        ),
      );
    }

    showMenu<String>(
      context: context,
      position: position,
      items: [
        item(
          'pause',
          'Pause',
          enabled: canPause,
          checked: view.mode == TorrentMode.pause,
        ),
        item(
          'share',
          'Share',
          enabled: canShare,
          checked: view.mode == TorrentMode.sharing,
        ),
        item(
          'request',
          'Request',
          enabled: canRequest,
          checked: view.mode == TorrentMode.request,
        ),
        const PopupMenuDivider(height: 8),
        item('saveAs', 'Save As...', enabled: canSaveAs),
        const PopupMenuDivider(height: 8),
        item('delete', 'Delete', enabled: true),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'pause':
          _setMode(view, TorrentMode.pause);
          break;
        case 'share':
          _setMode(view, TorrentMode.sharing);
          break;
        case 'request':
          _setMode(view, TorrentMode.request);
          break;
        case 'saveAs':
          _onSaveAs(view);
          break;
        case 'delete':
          _onDelete(view);
          break;
      }
    });
  }

  Widget _buildSplitter(double totalHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          setState(() {
            final delta = details.delta.dy;
            final newRatio = _detailsHeightRatio - (delta / totalHeight);
            _detailsHeightRatio = newRatio.clamp(
              _minDetailsRatio,
              _maxDetailsRatio,
            );
          });
        },
        child: Container(
          height: 8,
          color: const Color(0xFFC0C0C0),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTorrentList() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        if (detail.files.length == 1) {
          _onDropFile(detail.files.first.path);
        } else if (detail.files.length > 1) {
          _showInfo('Please drop a single file.');
        }
      },
      child: Container(
        color: _dragging ? Colors.blue.shade50 : Colors.white,
        child: Column(
          children: [
            _buildTorrentListHeaders(),
            Expanded(
              child: _torrents.isEmpty
                  ? Center(
                      child: Text(
                        _dragging
                            ? 'Drop a file to share'
                            : 'No torrent files. Add or drop a file to share.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : _buildGroupedList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList() {
    // Build a flat list of group headers + rows, preserving the (already
    // sorted) torrent order within each source group.
    final groups = <String, List<_TorrentView>>{};
    for (final torrent in _torrents) {
      groups.putIfAbsent(torrent.source, () => []).add(torrent);
    }
    final sourceKeys = groups.keys.toList()..sort();

    final rows = <Widget>[];
    for (final source in sourceKeys) {
      rows.add(_buildGroupHeader(source));
      for (final torrent in groups[source]!) {
        rows.add(_buildTorrentRow(torrent));
      }
    }

    return ListView(children: rows);
  }

  Widget _buildGroupHeader(String source) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey.shade100,
      child: Text(
        source.isEmpty ? 'Unknown' : source,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildTorrentRow(_TorrentView torrent) {
    final isSelected = _selectedKey == torrent.key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        setState(() => _selectedKey = torrent.key);
        _showRowMenu(torrent, details.globalPosition);
      },
      onLongPressStart: (details) {
        setState(() => _selectedKey = torrent.key);
        _showRowMenu(torrent, details.globalPosition);
      },
      child: InkWell(
        onTap: () => setState(() => _selectedKey = torrent.key),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade100 : null,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Icon(
                    torrent.completed ? Icons.check_circle : Icons.downloading,
                    size: 18,
                    color: torrent.completed ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    torrent.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    _modeToString(torrent.mode),
                    style: TextStyle(
                      fontSize: 12,
                      color: torrent.mode == TorrentMode.error
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    torrent.description,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTorrentListHeaders() {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32), // Icon column
          _buildColumnHeader('File', 0, flex: 2),
          _buildColumnHeader('Mode', 1, width: 80),
          _buildColumnHeader('Description', 2, flex: 2),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(
    String title,
    int index, {
    double? width,
    int? flex,
  }) {
    final content = InkWell(
      onTap: () => _sort(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_sortColumnIndex == index)
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
              ),
          ],
        ),
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return Expanded(flex: flex ?? 1, child: content);
  }

  Widget _buildDetailsPanel() {
    final torrent = _selectedTorrent;
    if (torrent == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'Select a torrent to view details',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final details = <MapEntry<String, String>>[
      MapEntry('File name', torrent.fileName),
      if (torrent.description.isNotEmpty)
        MapEntry('Description', torrent.description),
      if (torrent.source.isNotEmpty) MapEntry('Source', torrent.source),
      if (torrent.size != 0) MapEntry('File size', '${torrent.size} bytes'),
      if (torrent.compression != TorrentCompression.unknown)
        MapEntry(
          'Compression',
          torrent.compressedSize > 0
              ? '${_compressionToString(torrent.compression)}, ${torrent.compressedSize} bytes'
              : _compressionToString(torrent.compression),
        ),
      MapEntry('Mode', _modeToString(torrent.mode)),
      if (torrent.totalBlocks > 0)
        MapEntry(
          'Blocks',
          '${torrent.receivedBlocks} / ${torrent.totalBlocks}',
        ),
    ];

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 28,
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Torrent Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          if (torrent.totalBlocks > 0) _buildProgressBar(torrent),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in details)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              entry.value,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (torrent.totalBlocks > 0) ...[
                    Container(
                      height: 24,
                      color: Colors.grey.shade100,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Blocks',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TorrentBlocksView(
                        totalBlocks: torrent.totalBlocks,
                        receivedBlocks: torrent.receivedBlocks,
                        scrollable: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(_TorrentView torrent) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: torrent.progress,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                  torrent.completed ? Colors.green : Colors.blue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(torrent.progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
