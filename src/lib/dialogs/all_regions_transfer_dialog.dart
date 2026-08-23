/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Progress dialogs that read every region off a radio (for exporting an all-regions
file) or program every region of a radio (for importing one). Both drive the
radio through the existing DataBroker events used by the Region Storage dialog:
`SetRegion`, `Channels`, `AllChannelsLoaded`, `RegionNames`, `SetRegionName` and
`WriteChannel`. Because the radio only exposes one region's channels at a time,
each operation switches the radio through the regions one by one.
*/

import 'dart:async';

import 'package:flutter/material.dart';

import '../radio/radio_models.dart';
import '../services/data_broker_client.dart';
import '../utils/all_regions_file.dart';

/// Reads every region of the radio and returns them as an [AllRegionsFile], or
/// null if the user cancelled or the read failed. Every channel slot of every
/// region is captured (including empty slots) so the export is a faithful copy.
Future<AllRegionsFile?> showExportAllRegionsDialog(
  BuildContext context, {
  required int deviceId,
  required int regionCount,
  required int channelCount,
}) {
  return showDialog<AllRegionsFile>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AllRegionsTransferDialog(
      deviceId: deviceId,
      regionCount: regionCount,
      channelCount: channelCount,
      writeData: null,
    ),
  );
}

/// Programs every region described by [data] onto the radio, one region at a
/// time. Returns true when programming finished, false if cancelled.
Future<bool> showImportAllRegionsDialog(
  BuildContext context, {
  required int deviceId,
  required int regionCount,
  required int channelCount,
  required AllRegionsFile data,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AllRegionsTransferDialog(
      deviceId: deviceId,
      regionCount: regionCount,
      channelCount: channelCount,
      writeData: data,
    ),
  );
  return result ?? false;
}

class _AllRegionsTransferDialog extends StatefulWidget {
  final int deviceId;
  final int regionCount;
  final int channelCount;

  /// When null the dialog reads all regions (export). When set it programs the
  /// given regions onto the radio (import).
  final AllRegionsFile? writeData;

  const _AllRegionsTransferDialog({
    required this.deviceId,
    required this.regionCount,
    required this.channelCount,
    required this.writeData,
  });

  @override
  State<_AllRegionsTransferDialog> createState() =>
      _AllRegionsTransferDialogState();
}

class _AllRegionsTransferDialogState extends State<_AllRegionsTransferDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  bool get _isWriting => widget.writeData != null;

  int _progress = 0;
  int _progressTotal = 0;
  bool _aborted = false;

  // --- Live radio state, tracked via subscriptions. ---
  int _currRegionLive = 0;
  bool _allLoaded = false;
  List<String?> _regionNamesLive = const [];
  int _originalRegion = 0;

  // --- Region-switch synchronisation. ---
  Completer<void>? _switchCompleter;
  int? _awaitRegion;
  bool _awaitRequireLoaded = true;

  @override
  void initState() {
    super.initState();
    _progressTotal = widget.regionCount;
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
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
        (_broker.getValueDynamic(widget.deviceId, 'AllChannelsLoaded')
            as bool?) ??
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
    if (_currRegionLive == _awaitRegion &&
        (!_awaitRequireLoaded || _allLoaded)) {
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
    // The radio reports the new region (HtStatus) before it clears and reloads
    // its channels, so a stale "loaded" flag must not complete this switch.
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
    _maybeCompleteSwitch();
    await c.future;
    timer.cancel();
    _switchCompleter = null;
    _awaitRegion = null;
  }

  // --- Run -------------------------------------------------------------------

  Future<void> _run() async {
    if (_isWriting) {
      await _runWrite();
    } else {
      await _runRead();
    }
  }

  /// Reads every region and pops the assembled [AllRegionsFile].
  Future<void> _runRead() async {
    final regions = <RegionChannelData>[];
    for (int i = 0; i < widget.regionCount; i++) {
      if (_aborted || !mounted) return;
      setState(() => _progress = i);
      await _switchToRegion(i, requireLoaded: true);
      if (_aborted || !mounted) return;
      regions.add(_captureCurrentRegion(i));
    }
    // Restore the radio to the region it was on before reading.
    await _switchToRegion(_originalRegion, requireLoaded: true);
    if (!mounted) return;
    Navigator.of(context).pop(
      AllRegionsFile(
        regionCount: widget.regionCount,
        channelCount: widget.channelCount,
        regions: regions,
      ),
    );
  }

  /// Snapshots the currently loaded channels (all slots) as a region entry.
  RegionChannelData _captureCurrentRegion(int index) {
    final raw = _broker.getValueDynamic(widget.deviceId, 'Channels');
    final channels = <RadioChannelInfo>[];
    if (raw is List) {
      for (final m in raw) {
        if (m is Map) {
          channels.add(RadioChannelInfo.fromJson(m.cast<String, dynamic>()));
        }
      }
    }
    final name = index < _regionNamesLive.length
        ? (_regionNamesLive[index] ?? '')
        : '';
    return RegionChannelData(index: index, name: name, channels: channels);
  }

  /// Programs every region from [widget.writeData] onto the radio, then pops
  /// true.
  Future<void> _runWrite() async {
    final data = widget.writeData!;
    // Only program regions that exist on this radio.
    final regionsToWrite = data.regions
        .where((r) => r.index >= 0 && r.index < widget.regionCount)
        .toList();
    setState(() => _progressTotal = regionsToWrite.length);

    for (int w = 0; w < regionsToWrite.length; w++) {
      if (_aborted || !mounted) return;
      setState(() => _progress = w);
      final region = regionsToWrite[w];
      await _switchToRegion(region.index, requireLoaded: true);
      if (_aborted || !mounted) return;
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'SetRegionName',
        data: {'index': region.index, 'name': region.name},
        store: false,
      );
      await _writeRegionChannels(region);
    }

    // Restore the radio to its original region.
    await _switchToRegion(_originalRegion, requireLoaded: true);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Writes every channel slot of the current region from [region]'s data,
  /// clearing slots the file does not provide.
  Future<void> _writeRegionChannels(RegionChannelData region) async {
    final byId = <int, RadioChannelInfo>{};
    for (final c in region.channels) {
      byId[c.channelId] = c;
    }
    for (int c = 0; c < widget.channelCount; c++) {
      if (_aborted || !mounted) return;
      final ch =
          byId[c]?.copyWith(channelId: c) ?? RadioChannelInfo(channelId: c);
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'WriteChannel',
        data: ch,
        store: false,
      );
      await Future.delayed(const Duration(milliseconds: 45));
    }
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final total = _progressTotal > 0 ? _progressTotal : 1;
    final fraction = (_progress / total).clamp(0.0, 1.0);
    final title = _isWriting ? 'Importing All Regions' : 'Exporting All Regions';
    final label = _isWriting
        ? 'Programming region ${_progress + 1} of $_progressTotal...'
        : 'Reading region ${_progress + 1} of $_progressTotal...';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _aborted ? null : fraction),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _aborted
              ? null
              : () {
                  setState(() => _aborted = true);
                  Navigator.of(context).pop(_isWriting ? false : null);
                },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
