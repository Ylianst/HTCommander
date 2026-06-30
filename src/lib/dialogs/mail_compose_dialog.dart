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

  // The Cc line is hidden behind a toggle to save vertical space; it is shown
  // automatically when the message is pre-filled with a Cc (reply / forward).
  bool _showCc = false;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(text: widget.initialTo);
    _ccController = TextEditingController(text: widget.initialCc);
    _showCc = widget.initialCc.trim().isNotEmpty;
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
    var fromCallsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
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

  // Helper for consistent input decoration (matches settings_dialog).
  InputDecoration _inputDecoration({Color? fillColor}) {
    return InputDecoration(
      filled: true,
      fillColor: fillColor ?? Colors.grey.shade100,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    );
  }

  // Helper for section card styling (matches settings_dialog).
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

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Add the keyboard inset so the dialog floats above the on-screen
      // keyboard on mobile and its scrollable body stays usable.
      insetPadding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                widget.isEdit ? 'Edit Message' : 'New Message',
                style: DialogStyles.titleStyle,
              ),
              const SizedBox(height: 16),
              // Fields section card. The contents scroll so the dialog stays
              // usable on short displays (e.g. mobile with the keyboard up).
              Expanded(
                child: Container(
                  decoration: _sectionDecoration(),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Size the message box to fill the leftover space, but
                      // keep a sensible minimum so the whole form scrolls when
                      // vertical space is tight.
                      final reserved = _showCc ? 300.0 : 200.0;
                      final messageHeight = (constraints.maxHeight - reserved)
                          .clamp(120.0, double.infinity);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'To',
                                  style: DialogStyles.labelStyle,
                                ),
                                const Spacer(),
                                if (!_showCc)
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _showCc = true),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add Cc'),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _toController,
                              onEditingComplete: () {
                                _toController.text = _cleanString(
                                  _toController.text,
                                );
                              },
                              decoration: _inputDecoration(
                                fillColor: _toValid ? null : _invalidColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_showCc) ...[
                              Row(
                                children: [
                                  const Text(
                                    'Cc',
                                    style: DialogStyles.labelStyle,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _showCc = false;
                                        _ccController.clear();
                                      });
                                    },
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: 'Remove Cc',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _ccController,
                                onEditingComplete: () {
                                  _ccController.text = _cleanString(
                                    _ccController.text,
                                  );
                                },
                                decoration: _inputDecoration(
                                  fillColor: _ccValid ? null : _invalidColor,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const Text(
                              'Subject',
                              style: DialogStyles.labelStyle,
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _subjectController,
                              decoration: _inputDecoration(),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Message',
                              style: DialogStyles.labelStyle,
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: messageHeight,
                              child: TextField(
                                controller: _bodyController,
                                expands: true,
                                maxLines: null,
                                minLines: null,
                                textAlignVertical: TextAlignVertical.top,
                                keyboardType: TextInputType.multiline,
                                decoration: _inputDecoration(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _onCancel,
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _submit(isDraft: true),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: const Text('Save Draft'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSend ? () => _submit(isDraft: false) : null,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: const Text('Send'),
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
