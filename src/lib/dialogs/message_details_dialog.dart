/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Shows the detailed contents of a Comms tab message (type, time, channel,
source/destination, duration, location, etc.).
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// All the metadata known about a single Comms tab message. Attached as the
/// [ChatMessage.tag] so the details dialog can display the full record.
class CommsMessageDetails {
  final String encoding;
  final DateTime time;
  final String channel;
  final bool isReceived;
  final String? source;
  final String? destination;
  final int duration;
  final double? latitude;
  final double? longitude;
  final String text;
  final String? filename;
  final String? imagePath;

  const CommsMessageDetails({
    required this.encoding,
    required this.time,
    required this.channel,
    required this.isReceived,
    this.source,
    this.destination,
    this.duration = 0,
    this.latitude,
    this.longitude,
    this.text = '',
    this.filename,
    this.imagePath,
  });
}

/// A single name/value row shown in the [MessageDetailsDialog].
class MessageDetailItem {
  final String name;
  final String value;
  const MessageDetailItem(this.name, this.value);
}

/// Dialog that shows the detailed contents of a Comms tab message.
///
/// Styled to match the [AprsDetailsDialog]: a two-column (name/value) list
/// with per-row "copy value" and a "copy all" action.
class MessageDetailsDialog extends StatelessWidget {
  final List<MessageDetailItem> items;

  const MessageDetailsDialog({super.key, required this.items});

  /// Shows the dialog for the given [details].
  static Future<void> show(
    BuildContext context, {
    required CommsMessageDetails details,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) =>
          MessageDetailsDialog(items: _buildItems(l10n, details)),
    );
  }

  /// Builds the displayed name/value rows from a [CommsMessageDetails],
  /// skipping fields that have no meaningful value.
  static List<MessageDetailItem> _buildItems(
    AppLocalizations l10n,
    CommsMessageDetails d,
  ) {
    final items = <MessageDetailItem>[];
    items.add(MessageDetailItem(l10n.msgdFieldType, _typeLabel(l10n, d.encoding)));
    items.add(
      MessageDetailItem(l10n.msgdFieldDirection,
          d.isReceived ? l10n.msgdDirReceived : l10n.msgdDirSent),
    );
    items.add(MessageDetailItem(l10n.msgdFieldTime, _formatTime(d.time)));
    if (d.channel.isNotEmpty) {
      items.add(MessageDetailItem(l10n.packetsColChannel, d.channel));
    }
    final source = d.source;
    if (source != null && source.isNotEmpty) {
      items.add(MessageDetailItem(l10n.msgdFieldSource, source));
    }
    final destination = d.destination;
    if (destination != null && destination.isNotEmpty) {
      items.add(MessageDetailItem(l10n.msgdFieldReceiver, destination));
    }
    if (d.duration > 0) {
      items.add(MessageDetailItem(
          l10n.msgdFieldDuration, _formatDuration(d.duration)));
    }
    final lat = d.latitude;
    final lon = d.longitude;
    if (lat != null && lon != null && (lat != 0 || lon != 0)) {
      items.add(MessageDetailItem(l10n.msgdFieldLatitude, lat.toStringAsFixed(6)));
      items.add(
          MessageDetailItem(l10n.msgdFieldLongitude, lon.toStringAsFixed(6)));
    }
    if (d.text.trim().isNotEmpty) {
      items.add(MessageDetailItem(l10n.msgdFieldMessage, d.text.trim()));
    }
    final filename = d.filename;
    if (filename != null && filename.isNotEmpty) {
      items.add(MessageDetailItem(l10n.msgdFieldFile, filename));
    }
    return items;
  }

  static String _typeLabel(AppLocalizations l10n, String encoding) {
    switch (encoding) {
      case 'Voice':
        return l10n.msgdTypeVoice;
      case 'VoiceClip':
        return l10n.msgdTypeVoiceClip;
      case 'Recording':
        return l10n.msgdTypeRecording;
      case 'Picture':
        return l10n.msgdTypeSstvPicture;
      case 'Ident':
        return l10n.msgdTypeIdentification;
      case 'BSS':
        return l10n.msgdTypeChatMessage;
      case 'AX25':
        return l10n.msgdTypeAx25Packet;
      case 'APRS':
        return 'APRS';
      default:
        return encoding;
    }
  }

  static String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  static String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) return '${totalSeconds}s';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  }

  void _copyValue(BuildContext context, MessageDetailItem item) {
    Clipboard.setData(ClipboardData(text: item.value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).apdValueCopied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _copyAll(BuildContext context) {
    final sb = StringBuffer();
    for (final item in items) {
      sb.write(item.name);
      sb.write('\t');
      sb.write(item.value);
      sb.write('\r\n');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).apdAllValuesCopied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _showRowMenu(
    BuildContext context,
    Offset position,
    MessageDetailItem item,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final l10n = AppLocalizations.of(context);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(value: 'copyValue', child: Text(l10n.apdCopyValue)),
        PopupMenuItem<String>(value: 'copyAll', child: Text(l10n.apdCopyAll)),
      ],
    );
    if (!context.mounted) return;
    if (value == 'copyValue') {
      _copyValue(context, item);
    } else if (value == 'copyAll') {
      _copyAll(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title row with a "copy all" action.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.msgdTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.apdCopyAll,
                    icon: const Icon(Icons.copy_all, size: 20),
                    onPressed: () => _copyAll(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Detail list.
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l10n.apdNoDetails,
                            style: const TextStyle(fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, thickness: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _DetailRow(
                              item: item,
                              striped: index.isOdd,
                              onContextMenu: (pos) =>
                                  _showRowMenu(context, pos, item),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // Buttons.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _copyAll(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                    ),
                    child: Text(l10n.apdCopyAll),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single name/value row. Right-click (or long-press) opens a copy menu.
class _DetailRow extends StatelessWidget {
  final MessageDetailItem item;
  final bool striped;
  final ValueChanged<Offset> onContextMenu;

  const _DetailRow({
    required this.item,
    required this.striped,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
      onLongPressStart: (d) => onContextMenu(d.globalPosition),
      child: Container(
        color: striped ? const Color(0xFFF7F9FB) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                item.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                item.value,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
