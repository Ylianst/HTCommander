import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../dialogs/dialog_utils.dart';
import '../l10n/app_localizations.dart';
import '../models/station_info.dart';
import '../services/data_broker_client.dart';
import 'contact_avatar.dart';

/// A file attached to a composed message, carrying the file name and its raw
/// bytes so it can be turned into a `WinLinkMailAttachement` on send.
class ComposedAttachment {
  const ComposedAttachment({required this.name, required this.data});

  final String name;
  final Uint8List data;
}

/// The message the compose view produces when the user sends or saves a draft.
/// [isDraft] is true when the message should be saved to the Draft mailbox,
/// false when it should be queued in the Outbox for sending.
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

/// Full-tab mail compose / edit view (replaces the former compose dialog so the
/// editor uses the entire tab area, which also keeps it usable when the on-screen
/// keyboard is open on mobile).
///
/// The [onSend] callback fires when the user sends the message. The [onExit]
/// callback fires when the user leaves the editor via the back arrow (or a
/// tab re-selection): its argument is a draft [ComposedMail] to save when the
/// message has unsaved content, or null when there is nothing worth keeping.
class MailComposeView extends StatefulWidget {
  const MailComposeView({
    super.key,
    required this.isEdit,
    required this.onSend,
    required this.onExit,
    this.initialTo = '',
    this.initialCc = '',
    this.initialSubject = '',
    this.initialBody = '',
    this.initialAttachments = const [],
  });

  final bool isEdit;
  final String initialTo;
  final String initialCc;
  final String initialSubject;
  final String initialBody;
  final List<ComposedAttachment> initialAttachments;

  final void Function(ComposedMail mail) onSend;
  final void Function(ComposedMail? draft) onExit;

  @override
  State<MailComposeView> createState() => MailComposeViewState();
}

class MailComposeViewState extends State<MailComposeView> {
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

  // True while a file is being dragged over the view, used to show the drop
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

  /// Contacts that can be addressed from a Winlink message: email contacts,
  /// Winlink callsign contacts, or any contact whose id is an email address.
  List<StationInfo> _loadMailContacts() {
    final stations = <StationInfo>[];
    final raw = _broker.getValueDynamic(0, 'Stations', null);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          stations.add(StationInfo.fromJson(item));
        } else if (item is Map) {
          stations.add(StationInfo.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    bool isMailContact(StationInfo s) =>
        s.stationType == StationType.email ||
        s.stationType == StationType.winlink ||
        s.callsign.contains('@');
    final result = stations.where(isMailContact).toList();
    String key(StationInfo s) =>
        (s.name.isNotEmpty ? s.name : s.callsign).toLowerCase();
    result.sort((a, b) => key(a).compareTo(key(b)));
    return result;
  }

  /// Appends [id] to a recipient field, avoiding duplicates.
  void _addRecipient(TextEditingController controller, String id) {
    final existing = _cleanString(
      controller.text,
    ).split(';').where((s) => s.isNotEmpty).toList();
    if (existing.any((e) => e.toLowerCase() == id.toLowerCase())) return;
    existing.add(id);
    controller.text = existing.join(';');
  }

  /// Opens a contact picker and appends the chosen contact to [target].
  Future<void> _pickContact(TextEditingController target) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final contacts = _loadMailContacts();
    if (contacts.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mailNoContacts)));
      return;
    }
    final selected = await showDialog<StationInfo>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(l10n.mailContactsTitle),
          content: SizedBox(
            width: 360,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: contacts.length,
                itemBuilder: (context, i) {
                  final c = contacts[i];
                  final title = c.name.isNotEmpty ? c.name : c.callsign;
                  return ListTile(
                    leading: ContactAvatar(
                      callsign: c.callsign,
                      avatarIcon: c.avatarIcon,
                      avatarImage: c.avatarImage,
                    ),
                    title: Text(title),
                    subtitle: c.name.isNotEmpty
                        ? Text(
                            c.callsign,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _addRecipient(target, selected.callsign);
      _messageChanged = true;
    });
  }

  /// A small button next to a recipient label that opens the contact picker.
  Widget _buildAddContactButton(TextEditingController target) {
    return IconButton(
      onPressed: () => _pickContact(target),
      icon: const Icon(Icons.person_add_alt_1, size: 18),
      tooltip: AppLocalizations.of(context).mailAddContact,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
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

  ComposedMail _buildComposedMail({required bool isDraft}) {
    return ComposedMail(
      from: _resolveFromCallsign(),
      to: _cleanString(_toController.text),
      cc: _cleanString(_ccController.text),
      subject: _subjectController.text,
      body: _bodyController.text,
      isDraft: isDraft,
      attachments: List.unmodifiable(_attachments),
    );
  }

  void _onSend() {
    widget.onSend(_buildComposedMail(isDraft: false));
  }

  /// Leaves the editor. When the message has unsaved content it is handed back
  /// as a draft to be stored in the Draft mailbox; otherwise nothing is saved.
  /// Also used when the user re-selects the Winlink tab while composing.
  void exitSavingDraft() {
    final hasContent =
        _cleanString(_toController.text).isNotEmpty ||
        _subjectController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty ||
        _attachments.isNotEmpty;
    if (hasContent && _messageChanged) {
      widget.onExit(_buildComposedMail(isDraft: true));
    } else {
      widget.onExit(null);
    }
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

  // Helper for consistent input decoration (matches settings_dialog).
  InputDecoration _inputDecoration({Color? fillColor}) {
    return DialogStyles.inputDecoration(context, fillColor: fillColor);
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // The back arrow and title share one wide hit box so the whole left
          // side of the title bar leaves the editor (saving a draft).
          Expanded(
            child: InkWell(
              onTap: exitSavingDraft,
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
                        widget.isEdit
                            ? l10n.mailComposeEditTitle
                            : l10n.mailComposeNewTitle,
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
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: _canSend ? _onSend : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(l10n.commonSend),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFields() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(l10n.mailColTo, style: DialogStyles.labelStyle),
            const Spacer(),
            _buildAddContactButton(_toController),
            if (!_showCc)
              TextButton.icon(
                onPressed: () => setState(() => _showCc = true),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.mailAddCc),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _toController,
          onEditingComplete: () {
            _toController.text = _cleanString(_toController.text);
          },
          decoration: _inputDecoration(
            fillColor: _toValid
                ? null
                : Theme.of(context).colorScheme.errorContainer,
          ),
        ),
        const SizedBox(height: 12),
        if (_showCc) ...[
          Row(
            children: [
              Text(l10n.mailCc, style: DialogStyles.labelStyle),
              const Spacer(),
              _buildAddContactButton(_ccController),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showCc = false;
                    _ccController.clear();
                  });
                },
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.mailRemoveCc,
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
              _ccController.text = _cleanString(_ccController.text);
            },
            decoration: _inputDecoration(
              fillColor: _ccValid
                  ? null
                  : Theme.of(context).colorScheme.errorContainer,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(l10n.mailColSubject, style: DialogStyles.labelStyle),
        const SizedBox(height: 4),
        TextField(
          controller: _subjectController,
          decoration: _inputDecoration(),
        ),
      ],
    );
  }

  Widget _buildMessageField() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.mailMessageLabel, style: DialogStyles.labelStyle),
        const SizedBox(height: 4),
        TextField(
          controller: _bodyController,
          minLines: 6,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          decoration: _inputDecoration().copyWith(
            fillColor: scheme.surfaceContainerLowest,
            filled: true,
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentsSection() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(l10n.mailAttachmentsLabel, style: DialogStyles.labelStyle),
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
                    style: DialogStyles.bodyStyle.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
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
                  style: DialogStyles.titleStyle.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (detail) {
                setState(() => _dragging = false);
                _onDropFiles(detail);
              },
              child: Stack(
                children: [
                  SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFields(),
                        const SizedBox(height: 12),
                        _buildMessageField(),
                        const SizedBox(height: 8),
                        _buildAttachmentsSection(),
                      ],
                    ),
                  ),
                  if (_dragging) _buildDropOverlay(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
