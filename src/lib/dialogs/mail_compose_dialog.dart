import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// A file attached to a composed message, carrying the file name and its raw
/// bytes so it can be turned into a `WinLinkMailAttachement` on send.
class ComposedAttachment {
  const ComposedAttachment({required this.name, required this.data});

  final String name;
  final Uint8List data;
}

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
    this.attachments = const [],
  });

  final String from;
  final String to;
  final String cc;
  final String subject;
  final String body;
  final bool isDraft;
  final List<ComposedAttachment> attachments;
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
  List<ComposedAttachment> initialAttachments = const [],
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
      initialAttachments: initialAttachments,
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
    required this.initialAttachments,
  });

  final bool isEdit;
  final String initialTo;
  final String initialCc;
  final String initialSubject;
  final String initialBody;
  final List<ComposedAttachment> initialAttachments;

  @override
  State<_MailComposeDialog> createState() => _MailComposeDialogState();
}

class _MailComposeDialogState extends State<_MailComposeDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;

  bool _messageChanged = false;

  // The Cc line is hidden behind a toggle to save vertical space; it is shown
  // automatically when the message is pre-filled with a Cc (reply / forward).
  bool _showCc = false;

  // Attachments added to the message (from the file picker or drag & drop).
  final List<ComposedAttachment> _attachments = [];

  // True while a file is being dragged over the dialog, used to show the drop
  // overlay hint.
  bool _dragging = false;

  // Total attachment size above which a soft "large attachment" warning is
  // shown (Winlink over radio is very low-bandwidth). Sending is still allowed.
  static const int _largeAttachmentThreshold = 120 * 1024;

  int get _totalAttachmentBytes =>
      _attachments.fold(0, (sum, a) => sum + a.data.length);

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(text: widget.initialTo);
    _ccController = TextEditingController(text: widget.initialCc);
    _showCc = widget.initialCc.trim().isNotEmpty;
    _subjectController = TextEditingController(text: widget.initialSubject);
    _bodyController = TextEditingController(text: widget.initialBody);
    _attachments.addAll(widget.initialAttachments);

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
        attachments: List.unmodifiable(_attachments),
      ),
    );
  }

  /// Opens the file picker and appends the selected files as attachments.
  Future<void> _onAddAttachment() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(allowMultiple: true, withData: true);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorOpeningFileDialog(e.toString()))),
      );
      return;
    }
    if (result == null) return;

    for (final file in result.files) {
      Uint8List? bytes = file.bytes;
      if (bytes == null && !kIsWeb && file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {
          bytes = null;
        }
      }
      if (bytes == null) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.mailAttachmentReadFailed(file.name))),
          );
        }
        continue;
      }
      _addAttachment(file.name, bytes);
    }
  }

  /// Reads dropped files and appends them as attachments (desktop / web).
  Future<void> _onDropFiles(DropDoneDetails detail) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    for (final file in detail.files) {
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.mailAttachmentReadFailed(file.name))),
          );
        }
        continue;
      }
      _addAttachment(file.name, bytes);
    }
  }

  void _addAttachment(String name, Uint8List data) {
    if (!mounted) return;
    setState(() {
      _attachments.add(ComposedAttachment(name: name, data: data));
      _messageChanged = true;
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
      _messageChanged = true;
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildAttachmentsSection() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                l10n.mailAttachmentsLabel,
                style: DialogStyles.labelStyle,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _onAddAttachment,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(l10n.mailAddAttachment),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (_attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l10n.mailAttachmentDropHint,
                style: DialogStyles.bodyStyle.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < _attachments.length; i++)
                      _buildAttachmentChip(i, scheme),
                  ],
                ),
              ),
            ),
            if (_totalAttachmentBytes > _largeAttachmentThreshold) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.mailAttachmentLargeWarning(
                        _formatSize(_totalAttachmentBytes),
                      ),
                      style: DialogStyles.bodyStyle.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentChip(int index, ColorScheme scheme) {
    final a = _attachments[index];
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
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
          Flexible(
            child: Text(
              a.name,
              overflow: TextOverflow.ellipsis,
              style: DialogStyles.bodyStyle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${_formatSize(a.data.length)})',
            style: DialogStyles.bodyStyle.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => _removeAttachment(index),
            tooltip: AppLocalizations.of(context).mailRemoveAttachment,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.only(left: 4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildDropOverlay() {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_upload, size: 48, color: scheme.primary),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).mailAttachmentDropHint,
                  style: DialogStyles.titleStyle.copyWith(color: scheme.primary),
                ),
              ],
            ),
          ),
        ),
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

    final l10n = AppLocalizations.of(context);
    final discard = await DialogHelper.showConfirmDialog(
      context,
      title: l10n.tabMail,
      message: widget.isEdit
          ? l10n.mailDiscardChanges
          : l10n.mailDiscardMessage,
      okText: l10n.mailDiscard,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  // Helper for consistent input decoration (matches settings_dialog).
  InputDecoration _inputDecoration({Color? fillColor}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: fillColor ?? scheme.surfaceContainerHighest,
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
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    );
  }

  // Helper for section card styling (matches settings_dialog).
  BoxDecoration _sectionDecoration() {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardOpen = viewInsets.bottom > 100;
    // Available height for the dialog after accounting for keyboard and padding.
    final availableHeight = screenHeight - viewInsets.bottom - 48;
    // On tall screens without keyboard, cap at 620; otherwise use available.
    final dialogMaxHeight = availableHeight.clamp(200.0, 620.0);

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Add the keyboard inset so the dialog floats above the on-screen
      // keyboard on mobile and its scrollable body stays usable.
      insetPadding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: keyboardOpen ? 8 : 24,
        bottom: 24 + viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: dialogMaxHeight),
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) {
            setState(() => _dragging = false);
            _onDropFiles(detail);
          },
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.all(keyboardOpen ? 12 : 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    Text(
                      widget.isEdit
                          ? AppLocalizations.of(context).mailComposeEditTitle
                          : AppLocalizations.of(context).mailComposeNewTitle,
                      style: DialogStyles.titleStyle,
                    ),
                    SizedBox(height: keyboardOpen ? 8 : 16),
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
                        padding: EdgeInsets.all(keyboardOpen ? 12 : 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  AppLocalizations.of(context).mailColTo,
                                  style: DialogStyles.labelStyle,
                                ),
                                const Spacer(),
                                if (!_showCc)
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _showCc = true),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: Text(AppLocalizations.of(context).mailAddCc),
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
                                fillColor: _toValid
                                    ? null
                                    : Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_showCc) ...[
                              Row(
                                children: [
                                  Text(
                                    AppLocalizations.of(context).mailCc,
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
                                    tooltip: AppLocalizations.of(context).mailRemoveCc,
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
                                  fillColor: _ccValid
                                      ? null
                                      : Theme.of(context)
                                            .colorScheme
                                            .errorContainer,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              AppLocalizations.of(context).mailColSubject,
                              style: DialogStyles.labelStyle,
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _subjectController,
                              decoration: _inputDecoration(),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppLocalizations.of(context).mailMessageLabel,
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
              _buildAttachmentsSection(),
              SizedBox(height: keyboardOpen ? 8 : 16),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _onCancel,
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonCancel),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _submit(isDraft: true),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).mailSaveDraft),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSend ? () => _submit(isDraft: false) : null,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonSend),
                  ),
                ],
              ),
            ],
          ),
        ),
              if (_dragging) _buildDropOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}
