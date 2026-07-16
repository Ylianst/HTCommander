/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AprsDetailsForm` dialog.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'aprs_location_dialog.dart';
import 'dialog_utils.dart';

/// A single name/value row shown in the [AprsDetailsDialog].
class AprsDetailItem {
  final String name;
  final String value;
  const AprsDetailItem(this.name, this.value);
}

/// Dialog that shows the detailed contents of a parsed APRS packet.
///
/// Mirrors the C# `AprsDetailsForm`: a two-column (name/value) list with
/// per-row "copy value" and a "copy all" action. Styled to match the
/// application's settings dialog.
class AprsDetailsDialog extends StatelessWidget {
  final List<AprsDetailItem> items;

  /// Optional sender location. When both [latitude] and [longitude] are
  /// provided (and not both zero), a "Show Location..." button is shown on the
  /// bottom left that opens the APRS location map dialog.
  final double? latitude;
  final double? longitude;

  /// Optional title shown in the location map dialog (e.g. the sender call).
  final String? locationTitle;

  const AprsDetailsDialog({
    super.key,
    required this.items,
    this.latitude,
    this.longitude,
    this.locationTitle,
  });

  /// Shows the dialog. [items] are the name/value pairs to display.
  static Future<void> show(
    BuildContext context, {
    required List<AprsDetailItem> items,
    double? latitude,
    double? longitude,
    String? locationTitle,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AprsDetailsDialog(
        items: items,
        latitude: latitude,
        longitude: longitude,
        locationTitle: locationTitle,
      ),
    );
  }

  bool get _hasLocation =>
      latitude != null &&
      longitude != null &&
      (latitude != 0 || longitude != 0);

  void _copyValue(BuildContext context, AprsDetailItem item) {
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
    AprsDetailItem item,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                      l10n.apdTitle,
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
                      if (_hasLocation)
                        if (compact)
                          IconButton(
                            tooltip: l10n.apdShowLocation,
                            onPressed: () => showAprsLocationDialog(
                              context,
                              latitude: latitude!,
                              longitude: longitude!,
                              title: locationTitle,
                            ),
                            icon: Icon(
                              Icons.location_pin,
                              color: scheme.onSurface,
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () => showAprsLocationDialog(
                              context,
                              latitude: latitude!,
                              longitude: longitude!,
                              title: locationTitle,
                            ),
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
  final AprsDetailItem item;
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
        color: striped
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
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
