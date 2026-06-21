import 'package:flutter/material.dart';

import 'dialog_utils.dart';

/// A read-only attachment shown in the mail viewer.
class MailViewerAttachment {
  const MailViewerAttachment({required this.name, this.sizeBytes});

  final String name;
  final int? sizeBytes;
}

/// Shows the read-only mail viewer dialog (ports `MailViewerForm`).
Future<void> showMailViewerDialog(
  BuildContext context, {
  required String from,
  required String to,
  String cc = '',
  required DateTime time,
  required String subject,
  required String body,
  List<MailViewerAttachment> attachments = const [],
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
  });

  final String from;
  final String to;
  final String cc;
  final DateTime time;
  final String subject;
  final String body;
  final List<MailViewerAttachment> attachments;

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
              Text(
                subject.isNotEmpty ? 'Mail - $subject' : 'Mail',
                style: DialogStyles.titleStyle,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _sectionDecoration(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (from.isNotEmpty) _headerLine('From: ', from),
                      if (to.isNotEmpty) _headerLine('To: ', to),
                      if (cc.isNotEmpty) _headerLine('Cc: ', cc),
                      _headerLine('Time: ', time.toLocal().toString()),
                      if (subject.isNotEmpty)
                        _headerLine('Subject: ', subject),
                      if (attachments.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildAttachments(),
                      ],
                      const Divider(height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            body,
                            style: DialogStyles.bodyStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.primaryButtonStyle(context),
                    child: const Text('Close'),
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

  Widget _headerLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
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
