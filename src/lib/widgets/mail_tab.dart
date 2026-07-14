import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../dialogs/mail_compose_dialog.dart';
import '../dialogs/mail_viewer_dialog.dart';
import '../dialogs/mail_debug_dialog.dart';
import '../dialogs/active_station_selector_dialog.dart';
import '../dialogs/dialog_utils.dart';
import '../l10n/app_localizations.dart';
import '../models/station_info.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';
import '../winlink/winlink_mail.dart';

/// Email message data
class MailMessage {
  final String id;
  final DateTime time;
  final String from;
  final String to;
  final String cc;
  final String subject;
  final String body;
  final bool isRead;

  const MailMessage({
    required this.id,
    required this.time,
    required this.from,
    required this.to,
    this.cc = '',
    required this.subject,
    required this.body,
    this.isRead = false,
  });
}

/// Mailbox definition
class Mailbox {
  final String name;
  final IconData icon;
  final List<MailMessage> messages;

  Mailbox({required this.name, required this.icon, List<MailMessage>? messages})
    : messages = messages ?? [];

  int get unreadCount => messages.where((m) => !m.isRead).length;
}

/// Mail tab - email/messaging functionality
class MailTab extends StatefulWidget {
  const MailTab({super.key});

  @override
  State<MailTab> createState() => _MailTabState();
}

class _MailTabState extends State<MailTab> with AutomaticKeepAliveClientMixin {
  String _selectedMailbox = 'Inbox';
  int? _selectedMailIndex;
  bool _showPreview = true;
  int _sortColumnIndex = 0;
  bool _sortAscending = false; // Descending by default for time
  double _previewHeightRatio = 0.45; // Preview takes 45% of available height
  static const double _minPreviewRatio = 0.15;
  static const double _maxPreviewRatio = 0.75;

  // When the tab is narrow the mailbox tree is hidden and mailbox selection is
  // moved into the overflow menu instead.
  bool _isCompact = false;
  static const double _compactWidthThreshold = 480;

  // Mailboxes (populated from the real MailStore).
  late final Map<String, Mailbox> _mailboxes;

  // Raw Winlink mail keyed by MID, used for read-flag updates and lookups.
  final Map<String, WinLinkMail> _rawMails = {};

  // Transient status shown in the bottom panel while mail is being processed.
  String? _transferStatus;
  // Persistent error shown in the bottom panel until the user dismisses it.
  String? _errorMessage;

  final DataBrokerClient _broker = DataBrokerClient();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeMailboxes();
    _broker.subscribe(
      deviceId: 0,
      name: 'MailsChanged',
      callback: _onMailsChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MailStoreReady',
      callback: _onMailsChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MailList',
      callback: _onMailList,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkStateMessage',
      callback: _onWinlinkStateMessage,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkError',
      callback: _onWinlinkError,
    );
    // Pick up any status that was already set before this tab was built.
    final initialStatus = _broker.getValueDynamic(1, 'WinlinkStateMessage');
    if (initialStatus is String && initialStatus.isNotEmpty) {
      _transferStatus = initialStatus;
    }
    _loadMails();
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _initializeMailboxes() {
    _mailboxes = {
      'Inbox': Mailbox(name: 'Inbox', icon: Icons.inbox),
      'Outbox': Mailbox(name: 'Outbox', icon: Icons.outbox),
      'Draft': Mailbox(name: 'Draft', icon: Icons.drafts),
      'Sent': Mailbox(name: 'Sent', icon: Icons.send),
      'Archive': Mailbox(name: 'Archive', icon: Icons.archive),
      'Trash': Mailbox(name: 'Trash', icon: Icons.delete),
    };
  }

  /// Localized display name for an internal mailbox key (the key itself is used
  /// as an identifier throughout, so only the shown text is translated).
  String _mailboxDisplayName(String key) {
    final l10n = AppLocalizations.of(context);
    switch (key) {
      case 'Inbox':
        return l10n.mailInbox;
      case 'Outbox':
        return l10n.mailOutbox;
      case 'Draft':
        return l10n.mailDraft;
      case 'Sent':
        return l10n.mailSent;
      case 'Archive':
        return l10n.mailArchive;
      case 'Trash':
        return l10n.mailTrash;
    }
    return key;
  }

  void _onMailsChanged(int deviceId, String name, Object? data) {
    if (mounted) _loadMails();
  }

  void _onWinlinkStateMessage(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final status = (data is String && data.isNotEmpty) ? data : null;
    setState(() => _transferStatus = status);
  }

  void _onWinlinkError(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (data is String && data.isNotEmpty) {
      setState(() => _errorMessage = data);
    }
  }

  void _dismissError() {
    setState(() => _errorMessage = null);
  }

  /// Removes a leading, case-insensitive "SMTP:" prefix that Winlink adds to
  /// internet email senders, so only the bare address is displayed.
  static String _stripSmtpPrefix(String address) {
    if (address.length >= 5 &&
        address.substring(0, 5).toUpperCase() == 'SMTP:') {
      return address.substring(5);
    }
    return address;
  }

  /// Formats a received time for display as "YYYY-MM-DD HH:MM" (no seconds or
  /// milliseconds), in local time.
  static String _formatMailTime(DateTime time) {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  /// Requests the current mail list from the MailStore over the data broker.
  /// The store responds with a 'MailList' event, handled by [_onMailList]. This
  /// path works in both the main window and detached (client) windows.
  void _loadMails() {
    _broker.dispatch(deviceId: 0, name: 'MailGetAll', data: null, store: false);
  }

  /// Populates the mailboxes from a 'MailList' broker event. The payload is a
  /// list of [WinLinkMail] (rebuilt from JSON in detached windows).
  void _onMailList(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (data is! List) return;
    final mails = data.whereType<WinLinkMail>().toList();
    setState(() {
      _rawMails.clear();
      for (final box in _mailboxes.values) {
        box.messages.clear();
      }
      for (final mail in mails) {
        final mid = mail.mid;
        if (mid == null) continue;
        _rawMails[mid] = mail;
        final box = _mailboxes[mail.mailbox] ?? _mailboxes['Inbox']!;
        box.messages.add(
          MailMessage(
            id: mid,
            time: mail.dateTime,
            from: _stripSmtpPrefix(mail.from ?? ''),
            to: mail.to ?? '',
            cc: mail.cc ?? '',
            subject: mail.subject ?? '',
            body: mail.body ?? '',
            isRead: (mail.flags & MailFlags.unread.value) == 0,
          ),
        );
      }
      // Keep each mailbox sorted by the active sort settings.
      for (final box in _mailboxes.values) {
        _applySort(box.messages);
      }
      if (_selectedMailIndex != null &&
          _selectedMailIndex! >= _currentMessages.length) {
        _selectedMailIndex = null;
      }
    });
  }

  List<MailMessage> get _currentMessages =>
      _mailboxes[_selectedMailbox]?.messages ?? [];

  /// In the Outbox, Draft and Sent mailboxes we care about the recipient, so
  /// the address column shows "To" instead of "From".
  bool get _showRecipientColumn =>
      _selectedMailbox == 'Outbox' ||
      _selectedMailbox == 'Draft' ||
      _selectedMailbox == 'Sent';

  MailMessage? get _selectedMail {
    if (_selectedMailIndex == null ||
        _selectedMailIndex! >= _currentMessages.length) {
      return null;
    }
    return _currentMessages[_selectedMailIndex!];
  }

  void _onMailboxSelected(String mailbox) {
    setState(() {
      _selectedMailbox = mailbox;
      _selectedMailIndex = null;
    });
  }

  void _onMailSelected(int index) {
    setState(() {
      _selectedMailIndex = index;
    });
  }

  void _onNewMail() async {
    final result = await showMailComposeDialog(context);
    if (result != null) _addComposedMail(result);
  }

  /// Adds (or updates) a composed message in the MailStore. Messages go to the
  /// Outbox (queued for sending) or the Draft mailbox.
  void _addComposedMail(ComposedMail c, {String? replaceId}) {
    final target = c.isDraft ? 'Draft' : 'Outbox';

    final mail = WinLinkMail()
      ..mid = replaceId ?? WinLinkMail.generateMID()
      ..dateTime = DateTime.now()
      ..from = c.from
      ..to = c.to
      ..cc = c.cc
      ..subject = c.subject
      ..body = c.body
      ..mailbox = target;

    if (replaceId != null && _rawMails.containsKey(replaceId)) {
      _broker.dispatch(
        deviceId: 0,
        name: 'MailUpdate',
        data: mail,
        store: false,
      );
    } else {
      _broker.dispatch(deviceId: 0, name: 'MailAdd', data: mail, store: false);
    }
    // The store will emit MailsChanged, which triggers _loadMails().
  }

  void _onConnect(BuildContext buttonContext) {
    final RenderBox box = buttonContext.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);

    final items = <PopupMenuEntry<Object>>[
      PopupMenuItem<Object>(
        value: '__internet__',
        child: Text(AppLocalizations.of(context).mailInternet),
      ),
    ];

    final radios = _broker.getValueDynamic(1, 'ConnectedRadios');
    if (radios is List && radios.isNotEmpty) {
      items.add(const PopupMenuDivider());
      for (final r in radios) {
        if (r is Map) {
          final id = r['DeviceId'];
          final name =
              (r['FriendlyName'] as String?) ??
              AppLocalizations.of(context).tabRadio;
          if (id is int) {
            items.add(PopupMenuItem<Object>(value: id, child: Text(name)));
          }
        }
      }
    }

    showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + box.size.height,
        offset.dx + box.size.width,
        offset.dy,
      ),
      items: items,
    ).then((value) {
      if (value == null) return;
      if (value == '__internet__') {
        _connectInternet();
      } else if (value is int) {
        _connectRadio(value);
      }
    });
  }

  void _connectInternet() {
    _dismissError();
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkSync',
      data: {'Server': 'server.winlink.org', 'Port': 8773, 'UseTls': true},
      store: false,
    );
  }

  void _connectRadio(int radioId) async {
    _dismissError();
    final station = await showActiveStationSelector(
      context,
      stationType: StationType.winlink,
    );
    if (station == null) return;
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkSync',
      data: {'RadioId': radioId, 'Station': station},
      store: false,
    );
  }

  String _quotedReplyBody(MailMessage m) {
    return '\n\n--- Original Message ---\n'
        'From: ${m.from}\n'
        'Date: ${m.time.toLocal()}\n\n'
        '${m.body}';
  }

  String _replySubject(MailMessage m) =>
      m.subject.startsWith('Re: ') ? m.subject : 'Re: ${m.subject}';

  void _onReply() async {
    final m = _selectedMail;
    if (m == null) return;
    final result = await showMailComposeDialog(
      context,
      initialTo: m.from,
      initialSubject: _replySubject(m),
      initialBody: _quotedReplyBody(m),
    );
    if (result != null) _addComposedMail(result);
  }

  void _onReplyAll() async {
    final m = _selectedMail;
    if (m == null) return;
    final result = await showMailComposeDialog(
      context,
      initialTo: m.from,
      initialCc: m.cc,
      initialSubject: _replySubject(m),
      initialBody: _quotedReplyBody(m),
    );
    if (result != null) _addComposedMail(result);
  }

  void _onForward() async {
    final m = _selectedMail;
    if (m == null) return;
    final subject = m.subject.startsWith('Fwd: ')
        ? m.subject
        : 'Fwd: ${m.subject}';
    final body =
        '\n\n--- Forwarded Message ---\n'
        'From: ${m.from}\n'
        'To: ${m.to}\n'
        'Date: ${m.time.toLocal()}\n'
        'Subject: ${m.subject}\n\n'
        '${m.body}';
    final result = await showMailComposeDialog(
      context,
      initialSubject: subject,
      initialBody: body,
    );
    if (result != null) _addComposedMail(result);
  }

  void _onOpenMail(MailMessage m) async {
    final isEditable =
        _selectedMailbox == 'Draft' || _selectedMailbox == 'Outbox';
    if (isEditable) {
      final result = await showMailComposeDialog(
        context,
        isEdit: true,
        initialTo: m.to,
        initialCc: m.cc,
        initialSubject: m.subject,
        initialBody: m.body,
      );
      if (result != null) _addComposedMail(result, replaceId: m.id);
    } else {
      _markRead(m);
      await showMailViewerDialog(
        context,
        from: m.from,
        to: m.to,
        cc: m.cc,
        time: m.time,
        subject: m.subject,
        body: m.body,
        onReply: _onReply,
        onReplyAll: _onReplyAll,
        onForward: _onForward,
        onDelete: _onDelete,
      );
    }
  }

  /// Clears the unread flag on a message and persists it via the MailStore.
  void _markRead(MailMessage m) {
    final raw = _rawMails[m.id];
    if (raw == null) return;
    if ((raw.flags & MailFlags.unread.value) == 0) return;
    raw.flags &= ~MailFlags.unread.value;
    _broker.dispatch(deviceId: 0, name: 'MailUpdate', data: raw, store: false);
  }

  void _onDelete() async {
    final m = _selectedMail;
    if (m == null) return;
    final inTrash = _selectedMailbox == 'Trash';
    final l10n = AppLocalizations.of(context);
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: inTrash ? l10n.mailDeleteTitle : l10n.mailMoveToTrashTitle,
      message: inTrash
          ? l10n.mailDeletePermanent
          : l10n.mailMoveToTrashPrompt,
      okText: inTrash ? l10n.commonDelete : l10n.mailMove,
    );
    if (!confirmed) return;
    if (inTrash) {
      _broker.dispatch(
        deviceId: 0,
        name: 'MailDelete',
        data: m.id,
        store: false,
      );
    } else {
      _broker.dispatch(
        deviceId: 0,
        name: 'MailMove',
        data: {'MID': m.id, 'Mailbox': 'Trash'},
        store: false,
      );
    }
    setState(() => _selectedMailIndex = null);
  }

  /// Shows a right-click context menu for a mail row with common actions.
  void _showMailContextMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final inTrash = _selectedMailbox == 'Trash';

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(48, 48),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'open',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.open_in_new),
            title: Text(AppLocalizations.of(context).mailOpen),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'reply',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.reply),
            title: Text(AppLocalizations.of(context).mailReply),
          ),
        ),
        PopupMenuItem<String>(
          value: 'replyAll',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.reply_all),
            title: Text(AppLocalizations.of(context).mailReplyAll),
          ),
        ),
        PopupMenuItem<String>(
          value: 'forward',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.forward),
            title: Text(AppLocalizations.of(context).mailForward),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              inTrash
                  ? AppLocalizations.of(context).commonDelete
                  : AppLocalizations.of(context).mailMoveToTrashTitle,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    );

    if (!mounted) return;
    switch (value) {
      case 'open':
        final m = _selectedMail;
        if (m != null) _onOpenMail(m);
        break;
      case 'reply':
        _onReply();
        break;
      case 'replyAll':
        _onReplyAll();
        break;
      case 'forward':
        _onForward();
        break;
      case 'delete':
        _onDelete();
        break;
    }
  }

  /// Shows a mailbox-selection menu anchored to the compact-mode title. Lists
  /// every mailbox with a check mark next to the currently viewed one.
  void _showMailboxMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        for (final entry in _mailboxes.entries)
          PopupMenuItem<String>(
            value: entry.key,
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: _selectedMailbox == entry.key
                      ? const Text('✓', style: TextStyle(fontSize: 14))
                      : null,
                ),
                Text(
                  entry.value.messages.isNotEmpty
                      ? '${_mailboxDisplayName(entry.key)} (${entry.value.messages.length})'
                      : _mailboxDisplayName(entry.key),
                  style: TextStyle(
                    fontWeight: entry.value.unreadCount > 0
                        ? FontWeight.bold
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (value == null || !mounted) return;
    _onMailboxSelected(value);
  }

  void _showMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'showPreview',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showPreview
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(AppLocalizations.of(context).mailShowPreview),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        if (_isCompact) ...[
          for (final entry in _mailboxes.entries)
            PopupMenuItem<String>(
              value: 'mailbox:${entry.key}',
              height: menuItemHeight,
              padding: menuItemPadding,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: _selectedMailbox == entry.key
                        ? const Text('✓', style: TextStyle(fontSize: 14))
                        : null,
                  ),
                  Text(
                    entry.value.messages.isNotEmpty
                        ? '${_mailboxDisplayName(entry.key)} (${entry.value.messages.length})'
                        : _mailboxDisplayName(entry.key),
                    style: TextStyle(
                      fontWeight: entry.value.unreadCount > 0
                          ? FontWeight.bold
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuDivider(height: 8),
        ],
        PopupMenuItem<String>(
          value: 'backup',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text(AppLocalizations.of(context).mailBackup)],
          ),
        ),
        PopupMenuItem<String>(
          value: 'restore',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text(AppLocalizations.of(context).mailRestore)],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'showTraffic',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text(AppLocalizations.of(context).mailShowTraffic)],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [const SizedBox(width: 20), Text(AppLocalizations.of(context).tabDetach)],
            ),
          ),
        ],
      ],
    );
    if (value == null || !context.mounted) return;
    if (value.startsWith('mailbox:')) {
      _onMailboxSelected(value.substring('mailbox:'.length));
      return;
    }
    switch (value) {
      case 'showPreview':
        setState(() => _showPreview = !_showPreview);
        break;
      case 'showTraffic':
        showMailDebugDialog(context);
        break;
      case 'backup':
        _onBackupMail();
        break;
      case 'restore':
        _onRestoreMail();
        break;
      case 'detach':
        windowService.createWindow('mail');
        break;
    }
  }

  /// Backs up all mail to a gzip-compressed JSON file (ports
  /// `backupMailToolStripMenuItem_Click`). The format is compatible with the
  /// C# application's backup files.
  Future<void> _onBackupMail() async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    final l10n = mounted ? AppLocalizations.of(context) : null;

    final mails = _rawMails.values.toList();

    final Uint8List data;
    try {
      final json = const JsonEncoder.withIndent(
        '  ',
      ).convert(mails.map((m) => m.toJson()).toList());
      final encoded = GZipEncoder().encode(utf8.encode(json));
      data = Uint8List.fromList(encoded);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n?.mailBackupFailed(e.toString()) ?? '')),
      );
      return;
    }

    // Web and mobile require the bytes up front; desktop returns a path that
    // we write to ourselves.
    final needsBytes = kIsWeb || Platform.isAndroid || Platform.isIOS;

    String? outputPath;
    try {
      outputPath = await FilePicker.saveFile(
        dialogTitle: l10n?.mailBackupTitle ?? 'Backup Mail',
        fileName: 'mail-backup',
        type: FileType.custom,
        allowedExtensions: const ['dat'],
        bytes: needsBytes ? data : null,
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(l10n?.errorOpeningFileDialog(e.toString()) ?? ''),
        ),
      );
      return;
    }

    if (outputPath == null) return;

    if (!needsBytes) {
      try {
        await File(outputPath).writeAsBytes(data);
      } catch (e) {
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n?.mailBackupFailed(e.toString()) ?? '')),
        );
        return;
      }
    }

    messenger?.showSnackBar(
      SnackBar(content: Text(l10n?.mailBackupSuccess ?? '')),
    );
  }

  /// Restores mail from a gzip-compressed JSON backup file, adding any messages
  /// whose MID is not already present (ports `restoreMailToolStripMenuItem_Click`).
  Future<void> _onRestoreMail() async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;
    final l10n = mounted ? AppLocalizations.of(context) : null;

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: l10n?.mailRestoreTitle ?? 'Restore Mail',
        type: FileType.custom,
        allowedExtensions: const ['dat'],
        withData: true,
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(l10n?.errorOpeningFileDialog(e.toString()) ?? ''),
        ),
      );
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    Uint8List? bytes;
    try {
      if (file.bytes != null) {
        bytes = file.bytes;
      } else if (!kIsWeb && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
    } catch (_) {
      bytes = null;
    }

    if (bytes == null) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n?.mailRestoreUnableOpen ?? '')),
      );
      return;
    }

    final List<WinLinkMail> restoredMails;
    try {
      final decoded = GZipDecoder().decodeBytes(bytes);
      final json = utf8.decode(decoded);
      final list = jsonDecode(json) as List;
      restoredMails = list
          .whereType<Map>()
          .map((m) => WinLinkMail.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n?.mailRestoreFailed(e.toString()) ?? '')),
      );
      return;
    }

    // Existing MIDs are skipped; the MailStore also dedupes on MailAdd.
    final existingMids = _rawMails.keys.toSet();
    var added = 0;
    for (final mail in restoredMails) {
      final mid = mail.mid;
      if (mid == null || mid.isEmpty || existingMids.contains(mid)) continue;
      existingMids.add(mid);
      _broker.dispatch(deviceId: 0, name: 'MailAdd', data: mail, store: false);
      added++;
    }

    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'Restore completed successfully ($added message'
          '${added == 1 ? '' : 's'} added).',
        ),
      ),
    );
  }

  void _sort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = columnIndex != 0; // Descending for time by default
      }
      _applySort(_currentMessages);
    });
  }

  /// Sorts a message list in place using the active sort column/direction.
  void _applySort(List<MailMessage> messages) {
    messages.sort((a, b) {
      int result;
      switch (_sortColumnIndex) {
        case 0:
          result = a.time.compareTo(b.time);
          break;
        case 1:
          result = _showRecipientColumn
              ? a.to.compareTo(b.to)
              : a.from.compareTo(b.from);
          break;
        case 2:
          result = a.subject.compareTo(b.subject);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.month}/${time.day}/${time.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _isCompact = constraints.maxWidth < _compactWidthThreshold;
        return Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _showPreview
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final totalHeight = constraints.maxHeight;
                        final previewHeight = totalHeight * _previewHeightRatio;
                        final listHeight =
                            totalHeight - previewHeight - 8; // 8 for splitter
                        return Column(
                          children: [
                            SizedBox(
                              height: listHeight,
                              child: _buildMailListArea(),
                            ),
                            _buildSplitter(totalHeight),
                            SizedBox(
                              height: previewHeight,
                              child: _buildPreviewArea(),
                            ),
                          ],
                        );
                      },
                    )
                  : _buildMailListArea(),
            ),
            _buildStatusPanel(),
          ],
        );
      },
    );
  }

  /// Bottom panel showing either a persistent error (with a dismiss button) or
  /// a transient transfer status while mail is being processed. Mirrors the C#
  /// mailTransferStatusPanel behaviour, with an added error display.
  Widget _buildStatusPanel() {
    final scheme = Theme.of(context).colorScheme;
    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          border: Border(top: BorderSide(color: scheme.error)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: ElevatedButton(
                onPressed: _dismissError,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(AppLocalizations.of(context).commonOk),
              ),
            ),
          ],
        ),
      );
    }

    final status = _transferStatus;
    if (status != null && status.isNotEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: OutlinedButton(
                onPressed: _cancelWinlink,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(AppLocalizations.of(context).commonCancel),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Cancels an ongoing Winlink connection or disconnects an existing one.
  void _cancelWinlink() {
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkDisconnect',
      data: true,
      store: false,
    );
  }

  Widget _buildSplitter(double totalHeight) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          setState(() {
            // Moving down increases preview height (decreases ratio because preview is at bottom)
            final delta = details.delta.dy;
            final newRatio = _previewHeightRatio - (delta / totalHeight);
            _previewHeightRatio = newRatio.clamp(
              _minPreviewRatio,
              _maxPreviewRatio,
            );
          });
        },
        child: Container(
          height: 8,
          color: scheme.surfaceContainerHigh,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButtons = constraints.maxWidth > 280;
          return Row(
            children: [
              if (_isCompact)
                Builder(
                  builder: (titleContext) => InkWell(
                    onTap: () => _showMailboxMenu(titleContext),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${AppLocalizations.of(context).tabMail} ${_mailboxDisplayName(_selectedMailbox)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Text(
                  AppLocalizations.of(context).tabMail,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              const Spacer(),
              if (showButtons) ...[
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _onNewMail,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(
                      _isCompact
                          ? AppLocalizations.of(context).mailNew
                          : AppLocalizations.of(context).mailNewMail,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: Builder(
                    builder: (buttonContext) => ElevatedButton(
                      onPressed: () => _onConnect(buttonContext),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(AppLocalizations.of(context).commonConnect),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Builder(
                builder: (context) => InkWell(
                  onTap: () => _showMenu(context),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/MenuIcon.png',
                      width: 24,
                      height: 24,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.menu, size: 24);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMailListArea() {
    return Row(
      children: [
        // Mailbox tree (hidden in compact mode; selection moves to the menu)
        if (!_isCompact) ...[
          SizedBox(width: 150, child: _buildMailboxTree()),
          const VerticalDivider(width: 1),
        ],
        // Mail list
        Expanded(child: _buildMailList()),
      ],
    );
  }

  Widget _buildMailboxTree() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: ListView(
        children: _mailboxes.entries.map((entry) {
          final mailbox = entry.value;
          final isSelected = _selectedMailbox == entry.key;
          final count = mailbox.messages.length;
          return InkWell(
            onTap: () => _onMailboxSelected(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: isSelected ? scheme.primaryContainer : null,
              child: Row(
                children: [
                  Icon(mailbox.icon, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      count > 0
                          ? '${_mailboxDisplayName(entry.key)} ($count)'
                          : _mailboxDisplayName(entry.key),
                      style: TextStyle(
                        fontWeight: mailbox.unreadCount > 0
                            ? FontWeight.bold
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMailList() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: Column(
        children: [
          // Column headers
          _buildMailListHeaders(),
          // Mail items
          Expanded(
            child: ListView.builder(
              itemCount: _currentMessages.length,
              itemBuilder: (context, index) {
                final mail = _currentMessages[index];
                final isSelected = _selectedMailIndex == index;
                return InkWell(
                  onTap: () => _onMailSelected(index),
                  onDoubleTap: () {
                    _onMailSelected(index);
                    _onOpenMail(mail);
                  },
                  onSecondaryTapDown: (details) {
                    _onMailSelected(index);
                    _showMailContextMenu(context, details.globalPosition);
                  },
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: isSelected ? scheme.primaryContainer : null,
                      border: Border(
                        bottom: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              _formatTime(mail.time),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: mail.isRead
                                    ? null
                                    : FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              _showRecipientColumn ? mail.to : mail.from,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: mail.isRead
                                    ? null
                                    : FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              mail.subject,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: mail.isRead
                                    ? null
                                    : FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMailListHeaders() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: scheme.outline)),
      ),
      child: Row(
        children: [
          _buildColumnHeader(AppLocalizations.of(context).mailColTime, 0, flex: 2),
          _buildColumnHeader(
            _showRecipientColumn
                ? AppLocalizations.of(context).mailColTo
                : AppLocalizations.of(context).mailColFrom,
            1,
            flex: 2,
          ),
          _buildColumnHeader(AppLocalizations.of(context).mailColSubject, 2, flex: 3),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(
    String title,
    int index, {
    double? width,
    int? flex,
  }) {
    final content = InkWell(
      onTap: () => _sort(index),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showIcon =
              constraints.maxWidth > 30 && _sortColumnIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showIcon)
                  Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                  ),
              ],
            ),
          );
        },
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return Expanded(flex: flex ?? 1, child: content);
  }

  Widget _buildPreviewArea() {
    final scheme = Theme.of(context).colorScheme;
    if (_selectedMail == null) {
      return Container(
        color: scheme.surface,
        child: Center(
          child: Text(
            AppLocalizations.of(context).mailSelectPreview,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final mail = _selectedMail!;
    return Container(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toolbar
          Container(
            height: 36,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.reply, size: 20),
                  onPressed: _onReply,
                  tooltip: AppLocalizations.of(context).mailReply,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: const Icon(Icons.reply_all, size: 20),
                  onPressed: _onReplyAll,
                  tooltip: AppLocalizations.of(context).mailReplyAll,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: const Icon(Icons.forward, size: 20),
                  onPressed: _onForward,
                  tooltip: AppLocalizations.of(context).mailForward,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: _onDelete,
                  tooltip: AppLocalizations.of(context).commonDelete,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Preview content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mail.subject,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'From: ${mail.from}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      'To: ${mail.to}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      'Date: ${_formatMailTime(mail.time)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const Divider(height: 24),
                    Text(mail.body),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
