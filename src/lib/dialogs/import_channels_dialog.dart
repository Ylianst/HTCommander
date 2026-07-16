/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';
import '../radio/radio_models.dart';
import '../services/data_broker_client.dart';
import '../utils/channel_colors.dart';
import 'channel_details_dialog.dart';

/// Opens the channel import dialog.
///
/// Mirrors the C# `ImportChannelsForm`: imported channels are shown on the
/// left, the radio's existing channels on the right. The user moves channels
/// from left to right — either by dragging a tile onto a destination slot or by
/// selecting a channel and a slot and pressing the move button. Nothing is
/// written to the radio until OK is pressed.
Future<void> showImportChannelsDialog(
  BuildContext context, {
  required int deviceId,
  String? radioName,
  required List<RadioChannelInfo> importedChannels,
  required List<RadioChannelInfo> radioChannels,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ImportChannelsDialog(
      deviceId: deviceId,
      radioName: radioName,
      importedChannels: importedChannels,
      radioChannels: radioChannels,
    ),
  );
}

class ImportChannelsDialog extends StatefulWidget {
  final int deviceId;
  final String? radioName;
  final List<RadioChannelInfo> importedChannels;
  final List<RadioChannelInfo> radioChannels;

  const ImportChannelsDialog({
    super.key,
    required this.deviceId,
    this.radioName,
    required this.importedChannels,
    required this.radioChannels,
  });

  @override
  State<ImportChannelsDialog> createState() => _ImportChannelsDialogState();
}

class _ImportChannelsDialogState extends State<ImportChannelsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  static const double _tileWidth = 156;
  static const double _tileHeight = 50;

  /// Radio slots sorted by channel id (the right column).
  late final List<RadioChannelInfo> _slots;

  /// Pending assignments: slot channel id -> imported channel to write.
  final Map<int, RadioChannelInfo> _staged = <int, RadioChannelInfo>{};

  int? _selectedImportedIndex;
  int? _selectedSlotId;

  @override
  void initState() {
    super.initState();
    _slots = List<RadioChannelInfo>.from(widget.radioChannels)
      ..sort((a, b) => a.channelId.compareTo(b.channelId));
  }

  // --- Actions ---------------------------------------------------------------

  void _assign(RadioChannelInfo imported, int slotId) {
    setState(() {
      _staged[slotId] = imported;
      _selectedSlotId = slotId;
    });
  }

  void _moveSelected() {
    final idx = _selectedImportedIndex;
    final slotId = _selectedSlotId;
    if (idx == null || slotId == null) return;
    if (idx < 0 || idx >= widget.importedChannels.length) return;
    _assign(widget.importedChannels[idx], slotId);
  }

  bool get _canCopyAllOneToOne =>
      widget.importedChannels.length > 1 &&
      widget.importedChannels.length <= _slots.length;

  void _copyAllOneToOne() {
    if (!_canCopyAllOneToOne) return;

    setState(() {
      _staged.clear();
      for (int i = 0; i < widget.importedChannels.length; i++) {
        _staged[_slots[i].channelId] = widget.importedChannels[i];
      }
      _selectedImportedIndex = null;
      _selectedSlotId = null;
    });
  }

  void _clearStaged(int slotId) {
    setState(() {
      _staged.remove(slotId);
    });
  }

  void _onOk() {
    // Write every staged channel to the radio, re-targeted to its slot id.
    for (final entry in _staged.entries) {
      final channel = entry.value.copyWith(channelId: entry.key);
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'WriteChannel',
        data: channel,
        store: false,
      );
    }
    Navigator.of(context).pop();
  }

  String _slotLabel(RadioChannelInfo slot) {
    final staged = _staged[slot.channelId];
    final channel = staged ?? slot;
    if (channel.name.isNotEmpty) return channel.name;
    return AppLocalizations.of(context).importChannelShort(slot.channelId + 1);
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final radio = widget.radioName;
    final title = (radio != null && radio.isNotEmpty)
        ? l10n.importChannelsTitleWith(radio)
        : l10n.importChannelsTitle;

    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.importIntro,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildImportedColumn()),
                  _buildMoveButtons(),
                  Expanded(child: _buildRadioColumn()),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _staged.isEmpty ? null : _onOk,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.importOkCount(_staged.length)),
        ),
      ],
    );
  }

  Widget _buildImportedColumn() {
    return _buildColumnFrame(
      header: AppLocalizations.of(
        context,
      ).importImportedHeader(widget.importedChannels.length),
      child: widget.importedChannels.isEmpty
          ? Center(child: Text(AppLocalizations.of(context).importNoChannels))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < widget.importedChannels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _buildImportedTile(i, widget.importedChannels[i]),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildRadioColumn() {
    return _buildColumnFrame(
      header: AppLocalizations.of(context).importRadioChannelsHeader(_slots.length),
      child: _slots.isEmpty
          ? Center(child: Text(AppLocalizations.of(context).importNoRadioChannels))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final slot in _slots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _buildSlotTile(slot),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildColumnFrame({required String header, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
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

  Widget _buildMoveButtons() {
    final canMove = _selectedImportedIndex != null && _selectedSlotId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context).importMoveTooltip,
            icon: const Icon(Icons.arrow_forward),
            onPressed: canMove ? _moveSelected : null,
            style: IconButton.styleFrom(
              backgroundColor: canMove
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
          ),
          if (_canCopyAllOneToOne)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Tooltip(
                message: AppLocalizations.of(context).importCopyAllTooltip,
                child: OutlinedButton(
                  onPressed: _copyAllOneToOne,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('1:1'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImportedTile(int index, RadioChannelInfo channel) {
    final selected = _selectedImportedIndex == index;
    final palette = ChannelPalette.of(context);
    final tile = _channelTile(
      label: channel.name.isNotEmpty ? channel.name : 'Ch ${index + 1}',
      freqHz: channel.rxFreq,
      background: selected ? palette.selected : palette.base,
      highlight: selected,
      onTap: () => setState(() => _selectedImportedIndex = index),
      onInfo: () => showChannelDetailsDialog(context, channel: channel),
    );

    return Draggable<RadioChannelInfo>(
      data: channel,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: _channelTile(
            label: channel.name.isNotEmpty ? channel.name : 'Ch ${index + 1}',
            freqHz: channel.rxFreq,
            background: palette.selected,
            highlight: true,
            width: _tileWidth,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Widget _buildSlotTile(RadioChannelInfo slot) {
    final staged = _staged[slot.channelId];
    final isStaged = staged != null;
    final selected = _selectedSlotId == slot.channelId;
    final channel = staged ?? slot;

    return DragTarget<RadioChannelInfo>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _assign(details.data, slot.channelId),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        final palette = ChannelPalette.of(context);
        return _channelTile(
          label: _slotLabel(slot),
          freqHz: channel.rxFreq,
          slotNumber: slot.channelId + 1,
          background: isStaged
              ? palette.pending
              : (selected || hovering ? palette.selected : palette.base),
          highlight: selected || hovering || isStaged,
          onTap: () => setState(() => _selectedSlotId = slot.channelId),
          onInfo: () => showChannelDetailsDialog(
            context,
            channel: isStaged
                ? channel.copyWith(channelId: slot.channelId)
                : slot,
            title: isStaged ? 'Pending: ${_slotLabel(slot)}' : null,
          ),
          onClear: isStaged ? () => _clearStaged(slot.channelId) : null,
        );
      },
    );
  }

  Widget _channelTile({
    required String label,
    required int freqHz,
    required Color background,
    bool highlight = false,
    int? slotNumber,
    double? width,
    VoidCallback? onTap,
    VoidCallback? onInfo,
    VoidCallback? onClear,
  }) {
    final freq = freqHz > 0
        ? '${(freqHz / 1000000).toStringAsFixed(3)} MHz'
        : null;
    final palette = ChannelPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: _tileHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: highlight ? palette.borderHighlight : palette.border,
            width: highlight ? 1.5 : 0.5,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: palette.onChannel,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (slotNumber != null)
                    Text(
                      'Slot $slotNumber',
                      style: TextStyle(
                        fontSize: 8,
                        color: palette.onChannelSecondary,
                      ),
                    ),
                  if (freq != null)
                    Text(
                      freq,
                      style: TextStyle(
                        fontSize: 9,
                        color: palette.onChannelSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (onClear != null)
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                  tooltip: AppLocalizations.of(context).importClearTooltip,
                  icon: Icon(Icons.cancel, color: palette.onChannel),
                  onPressed: onClear,
                ),
              )
            else if (onInfo != null)
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                  tooltip: AppLocalizations.of(context).importChannelDetails,
                  icon: Icon(Icons.info_outline, color: palette.onChannel),
                  onPressed: onInfo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
