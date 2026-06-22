import 'package:flutter/material.dart';

import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// The result returned by [showMailComposeDialog] when the user sends or saves
/// a message. [isDraft] is true when the message should be saved to the Draft
/// mailbox, false when it should be queued in the Outbox for sending.
class ComposedMail {
  const ComposedMail({
    required this.from,
    required this.to,
    required this.cc,
    required this.subject,
    required this.body,
    required this.isDraft,
  });

  final String from;
  final String to;
  final String cc;
  final String subject;
  final String body;
  final bool isDraft;
}

/// Shows the mail compose / edit dialog (ports `MailComposeForm`).
///
/// When [isEdit] is true the dialog title reflects editing an existing message.
/// The [initial*] parameters pre-fill the fields for reply / forward / edit.
Future<ComposedMail?> showMailComposeDialog(
  BuildContext context, {
  bool isEdit = false,
  String initialTo = '',
  String initialCc = '',
  String initialSubject = '',
  String initialBody = '',
}) {
  return showDialog<ComposedMail>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MailComposeDialog(
      isEdit: isEdit,
      initialTo: initialTo,
      initialCc: initialCc,
      initialSubject: initialSubject,
      initialBody: initialBody,
    ),
  );
}

class _MailComposeDialog extends StatefulWidget {
  const _MailComposeDialog({
    required this.isEdit,
    required this.initialTo,
    required this.initialCc,
    required this.initialSubject,
    required this.initialBody,
  });

  final bool isEdit;
  final String initialTo;
  final String initialCc;
  final String initialSubject;
  final String initialBody;

  @override
  State<_MailComposeDialog> createState() => _MailComposeDialogState();
}

class _MailComposeDialogState extends State<_MailComposeDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  // Bisque highlight for invalid address lines (matches the C# Color.Bisque).
  static const Color _invalidColor = Color(0xFFFFE4C4);

  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;

  bool _messageChanged = false;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(text: widget.initialTo);
    _ccController = TextEditingController(text: widget.initialCc);
    _subjectController = TextEditingController(text: widget.initialSubject);
    _bodyController = TextEditingController(text: widget.initialBody);

    for (final c in [
      _toController,
      _ccController,
      _subjectController,
      _bodyController,
    ]) {
      c.addListener(() => setState(() {}));
    }
    _subjectController.addListener(() => _messageChanged = true);
    _bodyController.addListener(() => _messageChanged = true);
    _toController.addListener(() => _messageChanged = true);
  }

  @override
  void dispose() {
    _broker.dispose();
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  bool get _toValid => _validateAddressLine(_toController.text);
  bool get _ccValid => _validateAddressLine(_ccController.text);

  bool get _canSend =>
      _toValid &&
      _ccValid &&
      _toController.text.isNotEmpty &&
      _subjectController.text.isNotEmpty &&
      _bodyController.text.isNotEmpty;

  /// Validates a recipient line which may contain multiple callsigns / emails
  /// separated by spaces or semicolons (ports `validateToLine`).
  bool _validateAddressLine(String text) {
    final items = text.replaceAll(' ', ';').split(';');
    for (final item in items) {
      if (!_validateAddressItem(item)) return false;
    }
    return true;
  }

  /// Validates a single recipient: a callsign (optionally with SSID) or an
  /// email address (ports `validateToItem`).
  bool _validateAddressItem(String value) {
    if (value.isEmpty) return true;
    final t = value.trim();
    final atIndex = t.indexOf('@');
    if (atIndex == -1) {
      // Callsign, e.g. "kk7vzt" or "kk7vzt-6".
      if (t.length > 10) return false;
      return RegExp(r'^[a-zA-Z0-9]+(-[0-9]{1,2})?$').hasMatch(t);
    }
    // Email address.
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(t);
  }

  /// Trims items and re-joins them with semicolons (ports `CleanString`).
  String _cleanString(String text) {
    final items = text.replaceAll(' ', ';').split(';');
    final cleaned = items.map((s) => s.trim()).where((s) => s.isNotEmpty);
    return cleaned.join(';');
  }

  String _resolveFromCallsign() {
    var fromCallsign = _broker.getValue<String>(0, 'Callsign', '') ?? '';
    final useStationId =
        (_broker.getValue<int>(0, 'WinlinkUseStationId', 0) ?? 0) == 1;
    if (useStationId) {
      final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
      if (stationId > 0) fromCallsign += '-$stationId';
    }
    return fromCallsign;
  }

  void _submit({required bool isDraft}) {
    Navigator.of(context).pop(
      ComposedMail(
        from: _resolveFromCallsign(),
        to: _cleanString(_toController.text),
        cc: _cleanString(_ccController.text),
        subject: _subjectController.text,
        body: _bodyController.text,
        isDraft: isDraft,
      ),
    );
  }

  Future<void> _onCancel() async {
    final to = _toController.text;
    final subject = _subjectController.text;
    final body = _bodyController.text;

    final isEmpty = to.isEmpty && subject.isEmpty && body.isEmpty;
    if (isEmpty || !_messageChanged) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final discard = await DialogHelper.showConfirmDialog(
      context,
      title: 'Mail',
      message: widget.isEdit
          ? 'Discard changes to this message?'
          : 'Discard this message?',
      okText: 'Discard',
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return HTDialog(
      title: widget.isEdit ? 'Edit Message' : 'New Message',
      maxWidth: 600,
      maxHeight: 620,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _toController,
            onEditingComplete: () {
              _toController.text = _cleanString(_toController.text);
            },
            decoration: InputDecoration(
              labelText: 'To',
              border: const OutlineInputBorder(),
              isDense: true,
              filled: !_toValid,
              fillColor: _invalidColor,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ccController,
            onEditingComplete: () {
              _ccController.text = _cleanString(_ccController.text);
            },
            decoration: InputDecoration(
              labelText: 'Cc',
              border: const OutlineInputBorder(),
              isDense: true,
              filled: !_ccValid,
              fillColor: _invalidColor,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subjectController,
            decoration: const InputDecoration(
              labelText: 'Subject',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: _bodyController,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _onCancel,
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _submit(isDraft: true),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Save Draft'),
        ),
        ElevatedButton(
          onPressed: _canSend ? () => _submit(isDraft: false) : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
