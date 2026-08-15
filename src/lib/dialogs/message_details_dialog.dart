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
import '../sarsat/sarsat_1g_decoder.dart';
import '../utils/format_utils.dart';
import 'dialog_utils.dart';

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

  /// Transmit speed in words-per-minute for Morse entries (null otherwise).
  final int? wpm;

  /// Morse key type ('straight' / 'paddle') for Morse Key entries (null
  /// otherwise).
  final String? keyType;

  /// Structured decoded fields for SARSAT beacon entries (null otherwise).
  final Sarsat1gDetails? sarsat;

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
    this.wpm,
    this.keyType,
    this.sarsat,
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

  /// Optional callback that opens the message's location on a map. When
  /// non-null, a "Show Location..." button is shown at the bottom left,
  /// mirroring the [AprsDetailsDialog].
  final VoidCallback? onShowLocation;

  const MessageDetailsDialog({
    super.key,
    required this.items,
    this.onShowLocation,
  });

  /// Shows the dialog for the given [details]. When [onShowLocation] is
  /// provided, a "Show Location..." button opens the location map dialog.
  static Future<void> show(
    BuildContext context, {
    required CommsMessageDetails details,
    VoidCallback? onShowLocation,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => MessageDetailsDialog(
        items: _buildItems(l10n, details),
        onShowLocation: onShowLocation,
      ),
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
    // SARSAT beacons render a full breakdown of the structured decoded fields
    // (plus the raw frame), falling back to parsing the message text for older
    // records that predate the structured data.
    if (d.encoding == 'Sarsat') {
      final s = d.sarsat;
      if (s != null) {
        items.add(MessageDetailItem('Beacon ID', s.hexId));
        final country = s.countryName;
        if (country != null && country.isNotEmpty) {
          items.add(MessageDetailItem('Country', country));
        }
        items.add(MessageDetailItem('Country code', '${s.countryCode}'));
        items.add(MessageDetailItem('Protocol', s.protocolName));
        items.add(MessageDetailItem('Protocol code', '${s.protocolCode}'));
        if (s.identification.isNotEmpty) {
          items.add(MessageDetailItem('Identification', s.identification));
        }
        final lat = s.latitude;
        final lon = s.longitude;
        if (lat != null && lon != null) {
          items.add(
            MessageDetailItem(l10n.msgdFieldLatitude, lat.toStringAsFixed(6)),
          );
          items.add(
            MessageDetailItem(l10n.msgdFieldLongitude, lon.toStringAsFixed(6)),
          );
        }
        items.add(MessageDetailItem(
          'Format',
          s.lengthBits == 144 ? 'Long (144-bit)' : 'Short (112-bit)',
        ));
        items.add(MessageDetailItem('BCH-1', s.crc1Ok ? 'OK' : 'FAIL'));
        if (s.lengthBits == 144) {
          items.add(MessageDetailItem('BCH-2', s.crc2Ok ? 'OK' : 'FAIL'));
        }
        items.add(MessageDetailItem('Self-test', s.isTest ? 'Yes' : 'No'));
        if (s.count >= 2) {
          items.add(MessageDetailItem('Beacons received', '${s.count}'));
          final last = s.lastReceivedTime;
          if (last != null) {
            items.add(MessageDetailItem('Last received', _formatTime(last)));
          }
        }
        items.add(MessageDetailItem('Raw frame', s.rawHex));
      } else {
        for (final seg in d.text.split(', ')) {
          final i = seg.indexOf(': ');
          if (i > 0) {
            items.add(
              MessageDetailItem(seg.substring(0, i), seg.substring(i + 2)),
            );
          } else if (seg.trim().isNotEmpty) {
            items.add(MessageDetailItem(l10n.msgdFieldMessage, seg.trim()));
          }
        }
      }
      return items;
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
      items.add(MessageDetailItem(l10n.msgdFieldDuration,
          formatDurationCompact(Duration(seconds: d.duration))));
    }
    final keyType = d.keyType;
    if (keyType != null && keyType.isNotEmpty) {
      items.add(MessageDetailItem(
          'Key type', keyType == 'paddle' ? 'Paddle key' : 'Straight key'));
    }
    final wpm = d.wpm;
    if (wpm != null && wpm > 0) {
      items.add(MessageDetailItem('Speed', '$wpm WPM'));
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
      case 'Sarsat':
        return 'SARSAT Beacon';
      default:
        return encoding;
    }
  }

  static String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
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
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: scheme.surface,
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
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withValues(alpha: 0.05),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  // On narrow (mobile) layouts, show only the marker icon for
                  // the location button instead of the icon plus label.
                  final compact = constraints.maxWidth < 360;
                  return Row(
                    children: [
                      if (onShowLocation != null)
                        if (compact)
                          IconButton(
                            tooltip: l10n.apdShowLocation,
                            onPressed: onShowLocation,
                            icon: Icon(
                              Icons.location_pin,
                              color: scheme.onSurface,
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: onShowLocation,
                            icon: const Icon(Icons.location_pin, size: 18),
                            label: Text(l10n.apdShowLocation),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: scheme.surfaceContainerHighest,
                              foregroundColor: scheme.onSurface,
                            ),
                          ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _copyAll(context),
                        style: DialogStyles.secondaryButtonStyle(context),
                        child: Text(l10n.apdCopyAll),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: DialogStyles.primaryButtonStyle(context),
                        child: Text(l10n.commonClose),
                      ),
                    ],
                  );
                },
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
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapDown: (d) => onContextMenu(d.globalPosition),
      onLongPressStart: (d) => onContextMenu(d.globalPosition),
      child: Container(
        color: striped ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
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
