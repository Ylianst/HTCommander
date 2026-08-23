/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Region Storage dialog. Styled like the channel import dialog, but instead of
moving individual channels it moves entire regions (a region name plus its
channels) between the radio's live regions (left) and a local 32-slot storage
area (right).

Because the radio stores channels per-region, the dialog reads every region on
open by switching the radio through each region and snapshotting its channels
(driven entirely through existing DataBroker events: `SetRegion`, `Channels`,
`AllChannelsLoaded`, `RegionNames`). On OK it re-programs only the regions that
changed by switching to each one, writing its name (`SetRegionName`) and every
channel slot (`WriteChannel`). The 32 storage slots are persisted locally under
the device-0 `RegionStorage` value.
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../radio/radio_models.dart';
import '../services/data_broker_client.dart';
import '../utils/channel_import.dart';
import 'dialog_utils.dart';

/// Number of local storage slots offered for parked regions.
const int _kStorageSlots = 32;

/// Persisted DataBroker value (device 0) holding the storage slots as a JSON
/// list of length [_kStorageSlots]; each element is a region map or null.
const String _kStorageKey = 'RegionStorage';

/// Opens the Region Storage dialog. [deviceId] selects the radio; [regionCount]
/// and [channelCount] come from the radio's device info.
Future<void> showRegionStorageDialog(
  BuildContext context, {
  required int deviceId,
  required String? radioName,
  required int regionCount,
  required int channelCount,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RegionStorageDialog(
      deviceId: deviceId,
      radioName: radioName,
      regionCount: regionCount,
      channelCount: channelCount,
    ),
  );
}

/// A parked region: a name plus its (non-empty) channels. Channel ids are
/// preserved so the region can be re-programmed into the exact same slots.
class _RegionEntry {
  String name;
  List<RadioChannelInfo> channels;
  bool markedForDeletion;

  _RegionEntry({
    required this.name,
    required this.channels,
    this.markedForDeletion = false,
  });

  int get channelCount => channels.length;

  _RegionEntry clone() => _RegionEntry(
    name: name,
    channels: List<RadioChannelInfo>.from(channels),
    markedForDeletion: markedForDeletion,
  );

  Map<String, dynamic> toStorageJson() => {
    'name': name,
    'channels': channels.map((c) => c.toJson()).toList(),
  };

  static _RegionEntry fromStorageJson(Map map) {
    final rawChannels = map['channels'];
    final channels = <RadioChannelInfo>[];
    if (rawChannels is List) {
      for (final c in rawChannels) {
        if (c is Map) {
          channels.add(RadioChannelInfo.fromJson(c.cast<String, dynamic>()));
        }
      }
    }
    return _RegionEntry(
      name: (map['name'] as String?) ?? '',
      channels: channels,
    );
  }

  /// A stable signature used to detect whether a region changed. Ignores the
  /// deletion flag (callers resolve that before comparing).
  String signature() => jsonEncode(toStorageJson());
}

/// Identifies the slot a drag started from.
class _RegionDragData {
  final bool fromStorage;
  final int index;
  const _RegionDragData(this.fromStorage, this.index);
}

enum _Phase { reading, ready, writing }

/// Blue/purple palette for region tiles (distinct from the gold channel tiles).
class _RegionPalette {
  final Color base;
  final Color border;
  final Color onRegion;
  final Color onRegionSecondary;
  final Color deleted;
  final Color pending;
  final Color pendingBorder;

  const _RegionPalette({
    required this.base,
    required this.border,
    required this.onRegion,
    required this.onRegionSecondary,
    required this.deleted,
    required this.pending,
    required this.pendingBorder,
  });

  static const _RegionPalette light = _RegionPalette(
    base: Color(0xFFB9AEE8), // light periwinkle
    border: Color(0xFF6A5ACD), // slate blue
    onRegion: Color(0xDD000000),
    onRegionSecondary: Color(0xFF4A4A6A),
    deleted: Color(0xFFE0A0A0),
    pending: Color(0xFFB5E0B5), // soft green (matches import "staged" tint)
    pendingBorder: Color(0xFF4CAF50),
  );

  static const _RegionPalette dark = _RegionPalette(
    base: Color(0xFF453A6E), // deep indigo
    border: Color(0xFF8577C8),
    onRegion: Color(0xFFEDE9F8),
    onRegionSecondary: Color(0xFFBFB9DC),
    deleted: Color(0xFF6E3A3A),
    pending: Color(0xFF46683F), // dark green
    pendingBorder: Color(0xFF6FBF73),
  );

  static _RegionPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class _RegionStorageDialog extends StatefulWidget {
  final int deviceId;
  final String? radioName;
  final int regionCount;
  final int channelCount;

  const _RegionStorageDialog({
    required this.deviceId,
    required this.radioName,
    required this.regionCount,
    required this.channelCount,
  });

  @override
  State<_RegionStorageDialog> createState() => _RegionStorageDialogState();
}

class _RegionStorageDialogState extends State<_RegionStorageDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  /// Fixed width of each column (radio / storage), like the import dialog.
  static const double _columnWidth = 240;
  static const double _tileHeight = 50;

  /// Width of the tile shown under the pointer while dragging.
  static const double _feedbackWidth = 216;

  _Phase _phase = _Phase.reading;

  /// The radio's regions, editable (index 0..regionCount-1). null == empty.
  late List<_RegionEntry?> _radioRegions;

  /// Snapshot of the radio regions as first read, for change detection.
  late List<_RegionEntry?> _originalRadioRegions;

  /// The 32 local storage slots. null == empty.
  late List<_RegionEntry?> _storage;

  /// Snapshot of the storage slots as loaded, for change detection / revert.
  late List<_RegionEntry?> _originalStorage;

  /// The region the radio was on when the dialog opened; restored on close.
  int _originalRegion = 0;

  // --- Live radio state, tracked via subscriptions. ---
  int _currRegionLive = 0;
  bool _allLoaded = false;
  List<String?> _regionNamesLive = const [];

  // --- Region-switch synchronisation. ---
  Completer<void>? _switchCompleter;
  int? _awaitRegion;
  bool _awaitRequireLoaded = true;

  // --- Progress / abort state. ---
  int _progress = 0;
  int _progressTotal = 0;
  bool _aborted = false;

  @override
  void initState() {
    super.initState();
    _radioRegions = List<_RegionEntry?>.filled(widget.regionCount, null);
    _originalRadioRegions = List<_RegionEntry?>.filled(widget.regionCount, null);
    _storage = List<_RegionEntry?>.filled(_kStorageSlots, null);

    _loadStorage();
    _originalStorage = _storage.map((e) => e?.clone()).toList();
    _seedLiveState();

    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'HtStatus',
      callback: _onHtStatus,
    );
    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'AllChannelsLoaded',
      callback: _onAllChannelsLoaded,
    );
    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'RegionNames',
      callback: _onRegionNames,
    );

    // Start reading regions after the first frame so the progress UI shows.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runRead());
  }

  @override
  void dispose() {
    _broker.unsubscribe(widget.deviceId, 'HtStatus');
    _broker.unsubscribe(widget.deviceId, 'AllChannelsLoaded');
    _broker.unsubscribe(widget.deviceId, 'RegionNames');
    _broker.dispose();
    super.dispose();
  }

  // --- Live state seeding / subscriptions ------------------------------------

  void _seedLiveState() {
    final htStatus = _broker.getValueDynamic(widget.deviceId, 'HtStatus');
    if (htStatus is Map) {
      _currRegionLive = (htStatus['currRegion'] as int?) ?? 0;
    }
    _originalRegion = _currRegionLive;
    _allLoaded =
        (_broker.getValueDynamic(widget.deviceId, 'AllChannelsLoaded') as bool?) ??
        false;
    final names = _broker.getValueDynamic(widget.deviceId, 'RegionNames');
    if (names is List) {
      _regionNamesLive = names.map((e) => e is String ? e : null).toList();
    }
  }

  void _onHtStatus(int deviceId, String name, Object? data) {
    if (data is Map) {
      _currRegionLive = (data['currRegion'] as int?) ?? _currRegionLive;
      _maybeCompleteSwitch();
    }
  }

  void _onAllChannelsLoaded(int deviceId, String name, Object? data) {
    _allLoaded = data == true;
    _maybeCompleteSwitch();
  }

  void _onRegionNames(int deviceId, String name, Object? data) {
    if (data is List) {
      _regionNamesLive = data.map((e) => e is String ? e : null).toList();
    }
  }

  // --- Region switching ------------------------------------------------------

  void _maybeCompleteSwitch() {
    final c = _switchCompleter;
    if (c == null || c.isCompleted) return;
    if (_currRegionLive == _awaitRegion && (!_awaitRequireLoaded || _allLoaded)) {
      c.complete();
    }
  }

  /// Switches the radio to [region] and (optionally) waits until its channels
  /// have finished loading. Returns immediately if already there.
  Future<void> _switchToRegion(int region, {bool requireLoaded = true}) async {
    if (_currRegionLive == region && (!requireLoaded || _allLoaded)) return;
    final c = Completer<void>();
    _switchCompleter = c;
    _awaitRegion = region;
    _awaitRequireLoaded = requireLoaded;
    // Clear the "loaded" flag up front. The radio reports the new region
    // (HtStatus) *before* it clears and reloads its channels, so a stale
    // "loaded" flag from the previous region must not complete this switch —
    // otherwise we'd capture the wrong region's channels.
    if (requireLoaded) _allLoaded = false;
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'SetRegion',
      data: region,
      store: false,
    );
    final timer = Timer(const Duration(seconds: 15), () {
      if (!c.isCompleted) c.complete();
    });
    // In case the state already satisfies the condition synchronously.
    _maybeCompleteSwitch();
    await c.future;
    timer.cancel();
    _switchCompleter = null;
    _awaitRegion = null;
  }

  // --- Reading every region --------------------------------------------------

  Future<void> _runRead() async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.reading;
      _progress = 0;
      _progressTotal = widget.regionCount;
    });
    for (int i = 0; i < widget.regionCount; i++) {
      if (_aborted || !mounted) return;
      setState(() => _progress = i);
      await _switchToRegion(i, requireLoaded: true);
      if (_aborted || !mounted) return;
      _radioRegions[i] = _captureCurrentRegion(i);
    }
    // Restore the radio to the region it was on before reading.
    await _switchToRegion(_originalRegion, requireLoaded: true);
    if (_aborted || !mounted) return;
    _originalRadioRegions = _radioRegions.map((e) => e?.clone()).toList();
    setState(() => _phase = _Phase.ready);
  }

  /// Snapshots the currently loaded channels (non-empty) as a region entry.
  _RegionEntry _captureCurrentRegion(int index) {
    final raw = _broker.getValueDynamic(widget.deviceId, 'Channels');
    final channels = <RadioChannelInfo>[];
    if (raw is List) {
      for (final m in raw) {
        if (m is Map) {
          final ch = RadioChannelInfo.fromJson(m.cast<String, dynamic>());
          if (ch.rxFreq > 0) channels.add(ch);
        }
      }
    }
    final name = index < _regionNamesLive.length
        ? (_regionNamesLive[index] ?? '')
        : '';
    return _RegionEntry(name: name, channels: channels);
  }

  // --- Storage persistence ---------------------------------------------------

  void _loadStorage() {
    final raw = _broker.getValueDynamic(0, _kStorageKey);
    if (raw is List) {
      for (int i = 0; i < _kStorageSlots && i < raw.length; i++) {
        final e = raw[i];
        if (e is Map) _storage[i] = _RegionEntry.fromStorageJson(e);
      }
    }
  }

  void _persistStorage() {
    final list = _storage
        .map((e) => (e == null || e.markedForDeletion) ? null : e.toStorageJson())
        .toList();
    _broker.dispatch(
      deviceId: 0,
      name: _kStorageKey,
      data: list,
      store: true,
    );
  }

  // --- OK: re-program changed regions ----------------------------------------

  /// The region content that should end up in radio slot [i] once applied:
  /// null when the slot is empty or marked for deletion.
  _RegionEntry? _effectiveRadioRegion(int i) {
    final e = _radioRegions[i];
    if (e == null || e.markedForDeletion) return null;
    return e;
  }

  String _signatureOf(_RegionEntry? e) =>
      e == null ? 'null' : e.signature();

  Future<void> _onOk() async {
    // Determine which radio regions actually changed.
    final toWrite = <int>[];
    for (int i = 0; i < widget.regionCount; i++) {
      final effective = _effectiveRadioRegion(i);
      if (_signatureOf(effective) != _signatureOf(_originalRadioRegions[i])) {
        toWrite.add(i);
      }
    }

    if (toWrite.isEmpty) {
      // Nothing to re-program on the radio; just persist storage and close.
      _persistStorage();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _phase = _Phase.writing;
      _progress = 0;
      _progressTotal = toWrite.length;
    });

    for (int w = 0; w < toWrite.length; w++) {
      if (!mounted) return;
      setState(() => _progress = w);
      final idx = toWrite[w];
      await _switchToRegion(idx, requireLoaded: true);
      if (!mounted) return;
      final effective = _effectiveRadioRegion(idx);
      // What the radio currently holds for this region, so identical channels
      // can be skipped.
      final current = _originalRadioRegions[idx];
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'SetRegionName',
        data: {'index': idx, 'name': effective?.name ?? ''},
        store: false,
      );
      await _writeRegionChannels(effective, current);
      // Reflect the applied state so a re-run wouldn't rewrite it.
      _originalRadioRegions[idx] = effective?.clone();
      _radioRegions[idx] = effective?.clone();
    }

    // Restore the radio to its original region.
    await _switchToRegion(_originalRegion, requireLoaded: true);
    _persistStorage();
    if (mounted) Navigator.of(context).pop();
  }

  /// Writes every channel slot of the current region: the entry's channels at
  /// their ids, empty channels everywhere else (clearing removed channels).
  /// Channels already identical to [current] (what the radio holds) are skipped.
  Future<void> _writeRegionChannels(
    _RegionEntry? entry,
    _RegionEntry? current,
  ) async {
    final byId = <int, RadioChannelInfo>{};
    if (entry != null) {
      for (final c in entry.channels) {
        byId[c.channelId] = c;
      }
    }
    final curById = <int, RadioChannelInfo>{};
    if (current != null) {
      for (final c in current.channels) {
        curById[c.channelId] = c;
      }
    }
    for (int c = 0; c < widget.channelCount; c++) {
      if (!mounted) return;
      final ch = byId[c]?.copyWith(channelId: c) ??
          RadioChannelInfo(channelId: c);
      final existing = curById[c]?.copyWith(channelId: c) ??
          RadioChannelInfo(channelId: c);
      // Skip slots the radio already has programmed identically.
      if (_channelBytesEqual(ch, existing)) continue;
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'WriteChannel',
        data: ch,
        store: false,
      );
      await Future.delayed(const Duration(milliseconds: 45));
    }
  }

  /// True when two channels serialize to identical radio bytes.
  bool _channelBytesEqual(RadioChannelInfo a, RadioChannelInfo b) {
    final ba = a.toByteArray();
    final bb = b.toByteArray();
    if (ba.length != bb.length) return false;
    for (int i = 0; i < ba.length; i++) {
      if (ba[i] != bb[i]) return false;
    }
    return true;
  }

  // --- Drag & drop (copy) ----------------------------------------------------

  _RegionEntry? _entryAt(bool fromStorage, int index) =>
      fromStorage ? _storage[index] : _radioRegions[index];

  void _setEntryAt(bool fromStorage, int index, _RegionEntry? entry) {
    if (fromStorage) {
      _storage[index] = entry;
    } else {
      _radioRegions[index] = entry;
    }
  }

  /// Drops a region onto another slot as a *copy*: the source keeps its region
  /// and the target receives a fresh clone (any deletion mark is cleared).
  void _onDrop(_RegionDragData src, bool toStorage, int toIndex) {
    if (src.fromStorage == toStorage && src.index == toIndex) return;
    final source = _entryAt(src.fromStorage, src.index);
    if (source == null) return;
    setState(() {
      final copy = source.clone()..markedForDeletion = false;
      _setEntryAt(toStorage, toIndex, copy);
    });
  }

  _RegionEntry? _originalAt(bool fromStorage, int index) =>
      fromStorage ? _originalStorage[index] : _originalRadioRegions[index];

  /// Whether the slot differs from its original (copied over, loaded, or marked
  /// for deletion) and can therefore be reverted.
  bool _slotChanged(bool fromStorage, int index) {
    final cur = _entryAt(fromStorage, index);
    final orig = _originalAt(fromStorage, index);
    if (cur == null && orig == null) return false;
    if (cur == null || orig == null) return true;
    return cur.signature() != orig.signature() ||
        cur.markedForDeletion != orig.markedForDeletion;
  }

  /// Reverts a slot to the region it held when the dialog opened.
  void _revertSlot(bool fromStorage, int index) {
    setState(() {
      _setEntryAt(fromStorage, index, _originalAt(fromStorage, index)?.clone());
    });
  }

  // --- Context menu actions --------------------------------------------------

  Future<void> _showContextMenu(
    bool fromStorage,
    int index,
    Offset globalPos,
  ) async {
    final entry = _entryAt(fromStorage, index);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final items = <PopupMenuEntry<String>>[];
    if (entry == null) {
      // Empty slot: only loading a region from a file makes sense.
      items.add(
        const PopupMenuItem<String>(value: 'load', child: Text('Load...')),
      );
    } else {
      items.addAll(const [
        PopupMenuItem<String>(value: 'details', child: Text('Details...')),
        PopupMenuItem<String>(value: 'rename', child: Text('Rename...')),
        PopupMenuItem<String>(value: 'load', child: Text('Load...')),
        PopupMenuItem<String>(value: 'save', child: Text('Save...')),
        PopupMenuDivider(),
        PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
      ]);
    }
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'details':
        if (entry != null) await _showRegionDetails(entry, index, fromStorage);
        break;
      case 'rename':
        await _renameRegion(fromStorage, index);
        break;
      case 'load':
        await _loadRegionFromFile(fromStorage, index);
        break;
      case 'save':
        if (entry != null) await _saveRegionToFile(entry);
        break;
      case 'delete':
        await _confirmDelete(fromStorage, index);
        break;
    }
  }

  /// Renames the region in a slot. The name is capped to the radio's 10-byte
  /// region-name field so it survives being programmed back onto the radio.
  Future<void> _renameRegion(bool fromStorage, int index) async {
    final entry = _entryAt(fromStorage, index);
    if (entry == null) return;
    final controller = TextEditingController(text: entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Region'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 10,
          decoration: const InputDecoration(
            hintText: 'Region name',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: DialogStyles.secondaryButtonStyle(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            style: DialogStyles.primaryButtonStyle(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || newName == null) return;
    setState(() => entry.name = newName.trim());
  }

  String _regionDisplayName(int index, _RegionEntry? entry, bool fromStorage) {
    final name = entry?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    if (fromStorage) return 'Storage ${index + 1}';
    return 'Region ${index + 1}';
  }

  Future<void> _showRegionDetails(
    _RegionEntry entry,
    int index,
    bool fromStorage,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final title = _regionDisplayName(index, entry, fromStorage);
        return AlertDialog(
          title: Text('$title — ${entry.channelCount} channels'),
          content: SizedBox(
            width: 360,
            height: 380,
            child: entry.channels.isEmpty
                ? const Center(child: Text('No channels in this region.'))
                : ListView.separated(
                    itemCount: entry.channels.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final ch = entry.channels[i];
                      final freq = ch.rxFreq > 0
                          ? '${(ch.rxFreq / 1000000).toStringAsFixed(4)} MHz'
                          : '--';
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          child: Text(
                            '${ch.channelId + 1}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        title: Text(
                          ch.name.isNotEmpty ? ch.name : 'Ch ${ch.channelId + 1}',
                        ),
                        subtitle: Text(freq),
                      );
                    },
                  ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: DialogStyles.primaryButtonStyle(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(bool fromStorage, int index) async {
    final entry = _entryAt(fromStorage, index);
    if (entry == null) return;
    final name = _regionDisplayName(index, entry, fromStorage);
    final ok = await DialogHelper.showConfirmDialog(
      context,
      title: 'Delete Region',
      message:
          'Mark "$name" for deletion? It will be cleared when you press OK.',
      okText: 'Mark for Deletion',
    );
    if (!mounted || !ok) return;
    setState(() => entry.markedForDeletion = !entry.markedForDeletion);
  }

  // --- File load / save ------------------------------------------------------

  Future<void> _loadRegionFromFile(bool fromStorage, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Load Region',
        type: FileType.any,
        withData: true,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error opening file dialog: $e')),
      );
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    String? content;
    try {
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (!kIsWeb && file.path != null) {
        content = await File(file.path!).readAsString();
      }
    } catch (_) {
      content = null;
    }
    if (content == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read the selected file')),
      );
      return;
    }

    final entry = _parseRegionFile(content, file.name);
    if (entry == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No region found in the selected file')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      if (fromStorage) {
        _storage[index] = entry;
      } else {
        _radioRegions[index] = entry;
      }
    });
  }

  /// Parses a region file: a JSON `{name, channels}` object, or a channel CSV
  /// (with the region name taken from the file name).
  _RegionEntry? _parseRegionFile(String content, String fileName) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          final entry = _RegionEntry.fromStorageJson(decoded);
          // Keep only non-empty channels.
          entry.channels = entry.channels
              .where((c) => c.rxFreq > 0)
              .toList();
          return entry;
        }
      } catch (_) {
        // Fall through to CSV parsing.
      }
    }
    final channels = ChannelImport.parseChannelsFromCsv(content)
        .where((c) => c.rxFreq > 0)
        .toList();
    if (channels.isEmpty) return null;
    var baseName = fileName;
    final dot = baseName.lastIndexOf('.');
    if (dot > 0) baseName = baseName.substring(0, dot);
    return _RegionEntry(name: baseName, channels: channels);
  }

  Future<void> _saveRegionToFile(_RegionEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final content = const JsonEncoder.withIndent('  ')
        .convert(entry.toStorageJson());
    var safeName = entry.name.trim().isEmpty ? 'region' : entry.name.trim();
    safeName = safeName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final defaultFileName = '$safeName.json';
    final needsBytes = kIsWeb || Platform.isAndroid || Platform.isIOS;
    try {
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save Region',
        fileName: defaultFileName,
        type: needsBytes ? FileType.any : FileType.custom,
        allowedExtensions: needsBytes ? null : const ['json'],
        bytes: needsBytes
            ? Uint8List.fromList(utf8.encode(content))
            : null,
      );
      if (outputPath == null) return;
      if (!needsBytes) {
        await File(outputPath).writeAsString(content);
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Region saved to $defaultFileName')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error saving region: $e')),
      );
    }
  }

  // --- Cancel ----------------------------------------------------------------

  void _onCancel() {
    _aborted = true;
    // Best-effort: leave the radio on the region it started on.
    if (_currRegionLive != _originalRegion) {
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'SetRegion',
        data: _originalRegion,
        store: false,
      );
    }
    Navigator.of(context).pop();
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final radio = widget.radioName;
    final title = (radio != null && radio.isNotEmpty)
        ? 'Region Storage — $radio'
        : 'Region Storage';

    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      content: SizedBox(
        width: 512,
        height: 470,
        child: _phase == _Phase.ready ? _buildBody() : _buildProgress(),
      ),
      actions: _buildActions(),
    );
  }

  List<Widget> _buildActions() {
    if (_phase == _Phase.reading) {
      return [
        TextButton(
          onPressed: _onCancel,
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
      ];
    }
    if (_phase == _Phase.writing) {
      return const [];
    }
    return [
      TextButton(
        onPressed: _onCancel,
        style: DialogStyles.secondaryButtonStyle(context),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: _onOk,
        style: DialogStyles.primaryButtonStyle(context),
        child: const Text('OK'),
      ),
    ];
  }

  Widget _buildProgress() {
    final label = _phase == _Phase.reading
        ? 'Reading regions from the radio…'
        : 'Programming regions…';
    final total = _progressTotal == 0 ? 1 : _progressTotal;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: DialogStyles.bodyStyle),
          const SizedBox(height: 16),
          SizedBox(
            width: 320,
            child: LinearProgressIndicator(
              value: (_progress / total).clamp(0.0, 1.0),
            ),
          ),
          const SizedBox(height: 8),
          Text('${_progress + 1} / $_progressTotal'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Drag a region onto the other side to copy it there (the original '
            'stays). Right-click or long-press a region for details, load, save '
            'and delete. Changes are written to the radio only when you press OK.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Keep fixed-width columns on wide layouts, but fall back to
              // flexible columns on narrow screens so they never overflow.
              final bool narrow =
                  constraints.maxWidth < (_columnWidth * 2 + 16);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: narrow
                    ? [
                        Expanded(child: _buildRadioColumn()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStorageColumn()),
                      ]
                    : [
                        SizedBox(
                            width: _columnWidth, child: _buildRadioColumn()),
                        const SizedBox(width: 16),
                        SizedBox(
                            width: _columnWidth, child: _buildStorageColumn()),
                      ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColumnFrame({required String header, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: Text(
              header,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildRadioColumn() {
    return _buildColumnFrame(
      header: 'Radio Regions (${widget.regionCount})',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < widget.regionCount; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildSlot(fromStorage: false, index: i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageColumn() {
    return _buildColumnFrame(
      header: 'Storage ($_kStorageSlots)',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < _kStorageSlots; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildSlot(fromStorage: true, index: i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlot({required bool fromStorage, required int index}) {
    final entry = _entryAt(fromStorage, index);
    return DragTarget<_RegionDragData>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) =>
          _onDrop(details.data, fromStorage, index),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        final changed = _slotChanged(fromStorage, index);
        final tile = _regionTile(
          fromStorage: fromStorage,
          index: index,
          entry: entry,
          highlight: highlight,
          pending: changed,
          onCancel: changed ? () => _revertSlot(fromStorage, index) : null,
        );
        if (entry == null) return tile;
        return Draggable<_RegionDragData>(
          data: _RegionDragData(fromStorage, index),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: Colors.transparent,
            child: _copyFeedback(
              _regionTile(
                fromStorage: fromStorage,
                index: index,
                entry: entry,
                highlight: true,
                pending: changed,
                width: _feedbackWidth,
              ),
            ),
          ),
          // Copy semantics: the source region stays, so keep it fully visible.
          childWhenDragging: tile,
          child: tile,
        );
      },
    );
  }

  /// Wraps a dragged tile with a green "+" badge to signal that dropping makes
  /// a copy rather than moving the region.
  Widget _copyFeedback(Widget tile) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(opacity: 0.95, child: tile),
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(Icons.add, size: 14, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _regionTile({
    required bool fromStorage,
    required int index,
    required _RegionEntry? entry,
    required bool highlight,
    double? width,
    bool pending = false,
    VoidCallback? onCancel,
  }) {
    final palette = _RegionPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isEmpty = entry == null;
    final marked = entry?.markedForDeletion ?? false;
    final name = _regionDisplayName(index, entry, fromStorage);
    final count = entry?.channelCount ?? 0;

    // A pending (changed) region is tinted green to highlight that an operation
    // will run on OK; a delete-marked region keeps its own red tint.
    final Color background = isEmpty
        ? scheme.surfaceContainerHigh
        : (marked
              ? palette.deleted
              : (pending ? palette.pending : palette.base));
    final Color normalBorder = isEmpty
        ? scheme.outlineVariant
        : (marked || !pending ? palette.border : palette.pendingBorder);

    Widget content = Container(
      width: width,
      height: _tileHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: highlight ? scheme.primary : normalBorder,
          width: highlight ? 2 : (isEmpty ? 0.5 : 1),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          isEmpty
              ? Center(
                  child: Text(
                    'Empty',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: onCancel != null ? 16 : 0),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: palette.onRegion,
                          decoration: marked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      marked
                          ? 'Marked for deletion'
                          : '$count channel${count == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: palette.onRegionSecondary,
                      ),
                    ),
                  ],
                ),
          if (onCancel != null && !isEmpty)
            Positioned(
              top: -6,
              right: -6,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 16,
                tooltip: 'Cancel assignment',
                icon: Icon(Icons.cancel, color: palette.onRegion),
                onPressed: onCancel,
              ),
            ),
        ],
      ),
    );

    return GestureDetector(
      onSecondaryTapDown: (d) =>
          _showContextMenu(fromStorage, index, d.globalPosition),
      onLongPressStart: (d) =>
          _showContextMenu(fromStorage, index, d.globalPosition),
      child: content,
    );
  }
}
