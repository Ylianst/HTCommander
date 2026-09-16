/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/radio_models.dart';
import '../utils/channel_share.dart';

/// Shows the right-click / long-press context menu for a channel tile.
///
/// Always offers **Copy** (writes the channel's share string to the clipboard)
/// and **Details…**. When [onPaste] is provided (i.e. the tile is a radio slot)
/// a **Paste** entry is added, enabled only when the clipboard currently holds
/// a valid channel-share string. When [onClear] is provided (a slot with a
/// staged/pending channel) a **Clear** entry cancels that assignment.
Future<void> showChannelContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required RadioChannelInfo channel,
  VoidCallback? onDetails,
  void Function(RadioChannelInfo channel)? onPaste,
  VoidCallback? onClear,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  // Paste is offered only for radio slots, and only when the clipboard holds a
  // valid channel-share string.
  RadioChannelInfo? pasteChannel;
  if (onPaste != null) {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    pasteChannel = ChannelShare.decode(text);
    if (pasteChannel == null && ChannelShare.contains(text)) {
      pasteChannel = ChannelShare.findAll(text).first.channel;
    }
  }
  if (!context.mounted) return;

  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      // Copying an empty (unprogrammed) channel makes no sense.
      PopupMenuItem<String>(
        value: 'copy',
        enabled: channel.isConfigured,
        child: const Text('Copy'),
      ),
      if (onPaste != null)
        PopupMenuItem<String>(
          value: 'paste',
          enabled: pasteChannel != null,
          child: const Text('Paste'),
        ),
      if (onClear != null)
        const PopupMenuItem<String>(value: 'clear', child: Text('Clear')),
      const PopupMenuItem<String>(value: 'details', child: Text('Details...')),
    ],
  );

  switch (selected) {
    case 'copy':
      await Clipboard.setData(
        ClipboardData(text: ChannelShare.encode(channel)),
      );
      messenger?.showSnackBar(
        const SnackBar(content: Text('Channel copied to clipboard')),
      );
      break;
    case 'paste':
      if (pasteChannel != null) onPaste!(pasteChannel);
      break;
    case 'clear':
      onClear?.call();
      break;
    case 'details':
      onDetails?.call();
      break;
  }
}
