import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../dialogs/dialog_utils.dart';
import '../l10n/app_localizations.dart';

/// A read-only attachment shown in the mail viewer.
class MailViewerAttachment {
  const MailViewerAttachment({
    required this.name,
    required this.data,
    this.sizeBytes,
  });

  final String name;
  final Uint8List data;
  final int? sizeBytes;
}

/// Full-tab read-only mail viewer (replaces the former viewer dialog so a
/// message uses the entire tab area). A back arrow in the header returns to the
/// mail list; the optional action callbacks drive the toolbar buttons.
class MailViewerView extends StatelessWidget {
  const MailViewerView({
    super.key,
    required this.from,
    required this.to,
    required this.cc,
    required this.time,
    required this.subject,
    required this.body,
    required this.onBack,
    this.attachments = const [],
    this.cornerOverlay,
    this.onReply,
    this.onReplyAll,
    this.onForward,
    this.onDelete,
  });

  final String from;
  final String to;
  final String cc;
  final DateTime time;
  final String subject;
  final String body;
  final List<MailViewerAttachment> attachments;
  final VoidCallback onBack;
  // Corner-triangle avatar (or add-contact affordance) shown at the top-right,
  // built by the parent so it can reuse the preview pane's exact widget.
  final Widget? cornerOverlay;
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, scheme),
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (from.isNotEmpty)
                          _headerLine('From: ', from, scheme),
                        if (to.isNotEmpty) _headerLine('To: ', to, scheme),
                        if (cc.isNotEmpty) _headerLine('Cc: ', cc, scheme),
                        _headerLine('Time: ', _formatTime(time), scheme),
                        if (subject.isNotEmpty)
                          _headerLine('Subject: ', subject, scheme),
                        if (attachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildAttachments(context, scheme),
                        ],
                        const Divider(height: 24),
                        Text(body, style: DialogStyles.bodyStyle),
                      ],
                    ),
                  ),
                ),
                // Flush to the title bar (top) and the tabs bar (right).
                if (cornerOverlay != null)
                  Positioned(top: 0, right: 0, child: cornerOverlay!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // The back arrow and title share one wide hit box so the whole left
          // side of the title bar returns to the mail list.
          Expanded(
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.arrow_back, size: 20),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        subject.isNotEmpty
                            ? '${l10n.tabMail} - $subject'
                            : l10n.tabMail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onReply != null)
            IconButton(
              icon: const Icon(Icons.reply, size: 20),
              onPressed: onReply,
              tooltip: l10n.mailReply,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          if (onReplyAll != null)
            IconButton(
              icon: const Icon(Icons.reply_all, size: 20),
              onPressed: onReplyAll,
              tooltip: l10n.mailReplyAll,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          if (onForward != null)
            IconButton(
              icon: const Icon(Icons.forward, size: 20),
              onPressed: onForward,
              tooltip: l10n.mailForward,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: onDelete,
              tooltip: l10n.commonDelete,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  /// Formats a received time for display as "YYYY-MM-DD HH:MM" (no seconds or
  /// milliseconds), in local time.
  static String _formatTime(DateTime time) {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  Widget _headerLine(String label, String value, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          style: DialogStyles.bodyStyle.copyWith(color: scheme.onSurface),
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachments(BuildContext context, ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((a) {
        return Tooltip(
          message: AppLocalizations.of(context).mailSaveAttachment,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _saveAttachment(context, a),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.attach_file, size: 16),
                  const SizedBox(width: 4),
                  Text(a.name, style: DialogStyles.bodyStyle),
                  if (a.sizeBytes != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      _formatSize(a.sizeBytes!),
                      style: DialogStyles.bodyStyle.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Icon(Icons.download, size: 16, color: scheme.primary),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Prompts for a destination and writes the attachment bytes to disk.
  Future<void> _saveAttachment(
    BuildContext context,
    MailViewerAttachment attachment,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Web and mobile require the bytes up front; desktop returns a path that
    // we write to ourselves.
    final needsBytes = kIsWeb || Platform.isAndroid || Platform.isIOS;

    String? outputPath;
    try {
      outputPath = await FilePicker.saveFile(
        dialogTitle: l10n.mailSaveAttachment,
        fileName: attachment.name,
        bytes: needsBytes ? attachment.data : null,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorOpeningFileDialog(e.toString()))),
      );
      return;
    }

    if (outputPath == null) return;

    if (!needsBytes) {
      try {
        await File(outputPath).writeAsBytes(attachment.data);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.errorSavingFile(e.toString()))),
        );
        return;
      }
    }

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.mailAttachmentSaved(attachment.name))),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '($bytes B)';
    if (bytes < 1024 * 1024) return '(${(bytes / 1024).toStringAsFixed(1)} KB)';
    return '(${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)';
  }
}
