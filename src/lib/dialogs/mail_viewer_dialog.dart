import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import 'dialog_utils.dart';

/// A read-only attachment shown in the mail viewer.
class MailViewerAttachment {
  const MailViewerAttachment({required this.name, this.sizeBytes});

  final String name;
  final int? sizeBytes;
}

/// Shows the read-only mail viewer dialog (ports `MailViewerForm`).
///
/// The optional [onReply], [onReplyAll], [onForward] and [onDelete] callbacks
/// enable the matching toolbar actions. When provided, the corresponding icon
/// is shown; pressing it closes the viewer and then invokes the callback.
Future<void> showMailViewerDialog(
  BuildContext context, {
  required String from,
  required String to,
  String cc = '',
  required DateTime time,
  required String subject,
  required String body,
  List<MailViewerAttachment> attachments = const [],
  VoidCallback? onReply,
  VoidCallback? onReplyAll,
  VoidCallback? onForward,
  VoidCallback? onDelete,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MailViewerDialog(
      from: from,
      to: to,
      cc: cc,
      time: time,
      subject: subject,
      body: body,
      attachments: attachments,
      onReply: onReply,
      onReplyAll: onReplyAll,
      onForward: onForward,
      onDelete: onDelete,
    ),
  );
}

class _MailViewerDialog extends StatelessWidget {
  const _MailViewerDialog({
    required this.from,
    required this.to,
    required this.cc,
    required this.time,
    required this.subject,
    required this.body,
    required this.attachments,
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
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  subject.isNotEmpty ? 'Mail - $subject' : 'Mail',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _sectionDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (from.isNotEmpty) _headerLine('From: ', from),
                          if (to.isNotEmpty) _headerLine('To: ', to),
                          if (cc.isNotEmpty) _headerLine('Cc: ', cc),
                          _headerLine('Time: ', _formatTime(time)),
                          if (subject.isNotEmpty)
                            _headerLine('Subject: ', subject),
                          if (attachments.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildAttachments(),
                          ],
                          const Divider(height: 24),
                          Text(body, style: DialogStyles.bodyStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (onReply != null)
                    IconButton(
                      icon: const Icon(Icons.reply, size: 20),
                      onPressed: () => _runAction(context, onReply!),
                      tooltip: AppLocalizations.of(context).mailReply,
                    ),
                  if (onReplyAll != null)
                    IconButton(
                      icon: const Icon(Icons.reply_all, size: 20),
                      onPressed: () => _runAction(context, onReplyAll!),
                      tooltip: AppLocalizations.of(context).mailReplyAll,
                    ),
                  if (onForward != null)
                    IconButton(
                      icon: const Icon(Icons.forward, size: 20),
                      onPressed: () => _runAction(context, onForward!),
                      tooltip: AppLocalizations.of(context).mailForward,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () => _runAction(context, onDelete!),
                      tooltip: AppLocalizations.of(context).commonDelete,
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _sectionDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Closes the viewer dialog and then runs [action]. Used by the toolbar
  /// buttons so a follow-up compose/confirm dialog opens cleanly.
  void _runAction(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  /// Formats a received time for display as "YYYY-MM-DD HH:MM" (no seconds or
  /// milliseconds), in local time.
  static String _formatTime(DateTime time) {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  Widget _headerLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          style: DialogStyles.bodyStyle.copyWith(color: Colors.black),
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

  Widget _buildAttachments() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((a) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400),
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
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '($bytes B)';
    if (bytes < 1024 * 1024) return '(${(bytes / 1024).toStringAsFixed(1)} KB)';
    return '(${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)';
  }
}
