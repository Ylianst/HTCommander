import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tab_visibility.dart';
import 'contact_avatar.dart';
import 'mail_compose_view.dart';
import 'mail_viewer_view.dart';
import '../dialogs/mail_debug_dialog.dart';
import '../dialogs/active_station_selector_dialog.dart';
import '../dialogs/add_station_dialog.dart';
import '../dialogs/dialog_utils.dart';
import '../l10n/app_localizations.dart';
import '../models/station_info.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';
import '../utils/station_channel_resolver.dart';
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

/// Payload carried while dragging one or more messages onto a mailbox.
class _MailDragData {
  final String fromMailbox;
  final List<String> ids;

  const _MailDragData(this.fromMailbox, this.ids);
}

/// Which content the Mail tab currently shows: the mailbox/list view, a
/// full-tab read-only message viewer, or the full-tab compose/edit editor.
enum _MailView { list, view, compose }

/// Mail tab - email/messaging functionality
class MailTab extends StatefulWidget {
  const MailTab({super.key});

  @override
  State<MailTab> createState() => _MailTabState();
}

class _MailTabState extends State<MailTab>
    with AutomaticKeepAliveClientMixin, TabVisibilityStateMixin {
  String _selectedMailbox = 'Inbox';
  // The focused message (shown in the preview). [_selectedIds] holds the full
  // multi-selection (Ctrl/Shift+click) by MID so it survives list reloads, and
  // [_selectionAnchor] is the row a Shift+click range extends from.
  int? _selectedMailIndex;
  final Set<String> _selectedIds = {};
  int? _selectionAnchor;
  bool _showPreview = true;
  int _sortColumnIndex = 0;
  bool _sortAscending = false; // Descending by default for time
  double _previewHeightRatio = 0.45; // Preview takes 45% of available height
  static const double _minPreviewRatio = 0.15;
  static const double _maxPreviewRatio = 0.75;

  // Which content the tab shows: the list, the full-tab viewer, or the
  // full-tab compose editor. Viewing and composing take over the whole tab
  // (with a back arrow) instead of opening a dialog.
  _MailView _view = _MailView.list;

  // Compose editor parameters, set when entering compose mode. When
  // [_composeReplaceId] is non-null the composed message replaces an existing
  // Draft/Outbox message instead of adding a new one.
  bool _composeIsEdit = false;
  String? _composeReplaceId;
  String _composeInitialTo = '';
  String _composeInitialCc = '';
  String _composeInitialSubject = '';
  String _composeInitialBody = '';
  List<ComposedAttachment> _composeInitialAttachments = const [];
  // Recreated on every compose entry so the editor starts from fresh state and
  // so a tab re-selection can ask it to save a draft before leaving.
  GlobalKey<MailComposeViewState> _composeKey =
      GlobalKey<MailComposeViewState>();

  // When the tab is narrow the mailbox tree is hidden and mailbox selection is
  // moved into the overflow menu instead.
  bool _isCompact = false;
  static const double _compactWidthThreshold = 480;

  // Mailboxes (populated from the real MailStore).
  late final Map<String, Mailbox> _mailboxes;

  // Keyboard navigation for the mailbox tree and mail list.
  final FocusNode _mailboxFocusNode = FocusNode(debugLabel: 'MailboxTree');
  final FocusNode _mailListFocusNode = FocusNode(debugLabel: 'MailList');
  final ScrollController _mailScrollController = ScrollController();
  // Right-click context menu for the mail list (a MenuAnchor so it can show a
  // cascading "Move To" submenu).
  final MenuController _mailMenuController = MenuController();
  final GlobalKey _mailListKey = GlobalKey();
  static const double _mailRowHeight = 34;

  // Raw Winlink mail keyed by MID, used for read-flag updates and lookups.
  final Map<String, WinLinkMail> _rawMails = {};

  // Contacts used to resolve an avatar for a mail's correspondent.
  List<StationInfo> _stations = const [];

  // The Winlink station a radio connection is currently being started for, so a
  // cross-region channel-resolve failure can offer to edit the right contact.
  StationInfo? _connectingStation;

  // Transient status shown in the bottom panel while mail is being processed.
  String? _transferStatus;
  // Persistent error shown in the bottom panel until the user dismisses it.
  String? _errorMessage;
  // Whether the local Winlink client is in a session (not relayed to hosted
  // web clients, which rely on [_transferStatus] instead).
  bool _winlinkBusy = false;

  /// A sync is running, so Connect is disabled until it ends or is cancelled.
  bool get _syncInProgress =>
      _winlinkBusy || (_transferStatus?.isNotEmpty ?? false);

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
    _broker.subscribe(deviceId: 0, name: 'MailList', callback: _onMailList);
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkStateMessage',
      callback: _onWinlinkStateMessage,
    );
    // Stored error state: set by a failed sync, cleared by a new sync or by
    // dismissing it here.
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkLastError',
      callback: _onWinlinkError,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkBusy',
      callback: (_, _, data) {
        if (mounted) setState(() => _winlinkBusy = data == true);
      },
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockChannelResolveFailed',
      callback: _onLockChannelResolveFailed,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'Stations',
      callback: _onStationsChanged,
    );
    // Re-tapping the Winlink/Mail tab while it is already active returns the
    // view to the mailbox list (saving a draft first when composing).
    _broker.subscribe(
      deviceId: 0,
      name: 'MailShowList',
      callback: _onShowListRequested,
    );
    _loadStations();
    // Pick up any status / error that was already set before this tab was
    // built (e.g. a sync started from the Map tab).
    final initialStatus = _broker.getValueDynamic(1, 'WinlinkStateMessage');
    if (initialStatus is String && initialStatus.isNotEmpty) {
      _transferStatus = initialStatus;
    }
    final initialError = _broker.getValueDynamic(1, 'WinlinkLastError');
    if (initialError is String && initialError.isNotEmpty) {
      _errorMessage = initialError;
    }
    _winlinkBusy = _broker.getValue<bool>(1, 'WinlinkBusy', false) ?? false;
    _loadMails();
  }

  @override
  void dispose() {
    _broker.dispose();
    _mailboxFocusNode.dispose();
    _mailListFocusNode.dispose();
    _mailScrollController.dispose();
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
    setState(
      () => _errorMessage = (data is String && data.isNotEmpty) ? data : null,
    );
  }

  void _onStationsChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(_loadStations);
  }

  /// Loads the configured contacts/stations used to resolve mail avatars.
  void _loadStations() {
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
    _stations = stations;
  }

  /// Extracts the bare, lowercased email addresses from a mail header value,
  /// handling `Name <addr>` forms, multiple addresses and the "SMTP:" prefix.
  List<String> _emailAddresses(String header) {
    final result = <String>[];
    for (final part in header.split(RegExp(r'[;,]'))) {
      var addr = part.trim();
      if (addr.isEmpty) continue;
      final lt = addr.indexOf('<');
      final gt = addr.indexOf('>');
      if (lt >= 0 && gt > lt) addr = addr.substring(lt + 1, gt).trim();
      addr = _stripSmtpPrefix(addr).trim();
      if (addr.isNotEmpty) result.add(addr.toLowerCase());
    }
    return result;
  }

  /// Returns the contact matching the mail's correspondent, or null when none
  /// matches. The correspondent is the recipient for outbound mail
  /// (Outbox/Draft/Sent) and the sender otherwise. A match occurs when the
  /// address equals a contact's ID, or when a `<callsign>@winlink.org` address
  /// matches a generic or APRS station's callsign.
  StationInfo? _matchedStationForMail(MailMessage m) {
    final header = _showRecipientColumn ? m.to : m.from;
    for (final email in _emailAddresses(header)) {
      for (final s in _stations) {
        if (s.callsign.trim().toLowerCase() == email) return s;
      }
      final at = email.indexOf('@');
      if (at > 0 && email.substring(at + 1) == 'winlink.org') {
        final callPart = email.substring(0, at);
        for (final s in _stations) {
          if (s.stationType != StationType.generic &&
              s.stationType != StationType.aprs) {
            continue;
          }
          final base = contactCallsignBase(s.callsign).trim().toLowerCase();
          if (base == callPart || s.callsign.trim().toLowerCase() == callPart) {
            return s;
          }
        }
      }
    }
    return null;
  }

  /// Opens the contact edit dialog for [station] and persists any change.
  Future<void> _editContact(StationInfo station) async {
    final result = await showStationDialog(context, existing: station);
    if (result == null || !mounted) return;
    final stations = List<StationInfo>.from(_stations);
    stations.removeWhere(
      (s) =>
          s.callsign == station.callsign &&
          s.stationType == station.stationType,
    );
    stations.add(result);
    _broker.dispatch(
      deviceId: 0,
      name: 'Stations',
      data: stations.map((s) => s.toJson()).toList(),
    );
  }

  /// The display name in the first address of a header (`Name <addr>`), or null.
  String? _displayNameFromHeader(String header) {
    final first = header
        .split(RegExp(r'[;,]'))
        .firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
    final lt = first.indexOf('<');
    if (lt > 0) {
      final name = first.substring(0, lt).trim().replaceAll('"', '');
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  /// Opens the add-contact dialog pre-filled from the mail's correspondent, then
  /// persists the new contact. A `<callsign>@winlink.org` address creates a
  /// Winlink contact; any other address creates an email contact.
  Future<void> _addContactForMail(MailMessage m) async {
    final header = _showRecipientColumn ? m.to : m.from;
    final addresses = _emailAddresses(header);
    if (addresses.isEmpty) return;
    final email = addresses.first;

    final StationInfo proposed;
    final at = email.indexOf('@');
    if (at > 0 && email.substring(at + 1) == 'winlink.org') {
      proposed = StationInfo(
        callsign: email.substring(0, at).toUpperCase(),
        stationType: StationType.winlink,
      );
    } else {
      proposed = StationInfo(callsign: email, stationType: StationType.email);
    }
    final name = _displayNameFromHeader(header);
    if (name != null) proposed.name = name;

    final result = await showStationDialog(context, existing: proposed);
    if (result == null || !mounted) return;
    final stations = List<StationInfo>.from(_stations);
    stations.removeWhere(
      (s) =>
          s.callsign == result.callsign && s.stationType == result.stationType,
    );
    stations.add(result);
    _broker.dispatch(
      deviceId: 0,
      name: 'Stations',
      data: stations.map((s) => s.toJson()).toList(),
    );
  }

  /// Whether the mail's correspondent yields an address that could be added as
  /// a contact (used to offer the add-contact affordance when unmatched).
  bool _canAddContactForMail(MailMessage m) {
    final header = _showRecipientColumn ? m.to : m.from;
    return _emailAddresses(header).isNotEmpty;
  }

  void _dismissError() {
    setState(() => _errorMessage = null);
    _broker.dispatch(deviceId: 1, name: 'WinlinkLastError', data: null);
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
    final focusedId = _selectedMail?.id;
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
      _restoreSelection(focusedId);
    });
  }

  /// Re-resolves the focused row index after the current list was rebuilt or
  /// re-sorted, and drops selected messages that are no longer in the mailbox.
  void _restoreSelection(String? focusedId) {
    final messages = _currentMessages;
    final present = messages.map((m) => m.id).toSet();
    _selectedIds.retainWhere(present.contains);
    int index = focusedId == null
        ? -1
        : messages.indexWhere((m) => m.id == focusedId);
    if (index < 0 && _selectedIds.isNotEmpty) {
      index = messages.indexWhere((m) => _selectedIds.contains(m.id));
    }
    _selectedMailIndex = index >= 0 ? index : null;
    _selectionAnchor = _selectedMailIndex;
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
      _selectedIds.clear();
      _selectionAnchor = null;
    });
  }

  /// Selects only the message at [index] (a plain click or arrow key).
  void _onMailSelected(int index) {
    setState(() {
      _selectedMailIndex = index;
      _selectionAnchor = index;
      _selectedIds
        ..clear()
        ..add(_currentMessages[index].id);
    });
  }

  /// Handles a click on a mail row: Ctrl (Cmd on macOS) toggles the row, Shift
  /// selects the range from the anchor (Ctrl+Shift adds the range), otherwise
  /// the row alone is selected.
  void _onMailClicked(int index) {
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (keyboard.isShiftPressed) {
      _selectRange(index, additive: ctrl);
    } else if (ctrl) {
      _toggleSelection(index);
    } else {
      _onMailSelected(index);
    }
  }

  void _selectRange(int index, {bool additive = false}) {
    final messages = _currentMessages;
    if (messages.isEmpty) return;
    final anchor = (_selectionAnchor ?? _selectedMailIndex ?? index).clamp(
      0,
      messages.length - 1,
    );
    final lo = anchor < index ? anchor : index;
    final hi = anchor < index ? index : anchor;
    setState(() {
      if (!additive) _selectedIds.clear();
      for (var i = lo; i <= hi; i++) {
        _selectedIds.add(messages[i].id);
      }
      _selectedMailIndex = index;
      _selectionAnchor = anchor;
    });
  }

  void _toggleSelection(int index) {
    final messages = _currentMessages;
    final id = messages[index].id;
    setState(() {
      if (_selectedIds.remove(id)) {
        if (_selectedMailIndex == index) {
          final other = messages.indexWhere((m) => _selectedIds.contains(m.id));
          _selectedMailIndex = other >= 0 ? other : null;
        }
      } else {
        _selectedIds.add(id);
        _selectedMailIndex = index;
      }
      _selectionAnchor = index;
    });
  }

  void _selectAll() {
    final messages = _currentMessages;
    if (messages.isEmpty) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(messages.map((m) => m.id));
      _selectedMailIndex ??= 0;
      _selectionAnchor = _selectedMailIndex;
    });
  }

  /// Selected messages of the current mailbox, in list order.
  List<MailMessage> get _selectedMessages =>
      _currentMessages.where((m) => _selectedIds.contains(m.id)).toList();

  bool get _hasMultiSelection => _selectedIds.length > 1;

  /// Handles arrow up/down and page up/down while the mailbox tree has focus,
  /// moving the selection between mailboxes.
  KeyEventResult _handleMailboxKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = _mailboxes.keys.toList();
    final current = keys.indexOf(_selectedMailbox);
    if (current < 0) return KeyEventResult.ignored;
    int next;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = current + 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = current - 1;
    } else if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.end) {
      next = keys.length - 1;
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.home) {
      next = 0;
    } else {
      return KeyEventResult.ignored;
    }
    next = next.clamp(0, keys.length - 1);
    if (next != current) _onMailboxSelected(keys[next]);
    return KeyEventResult.handled;
  }

  /// Handles arrow up/down and page up/down while the mail list has focus,
  /// moving the selection between messages and scrolling to keep it visible.
  KeyEventResult _handleMailListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final count = _currentMessages.length;
    if (count == 0) return KeyEventResult.ignored;

    // Enter opens the focused message full-tab (matching a double-tap).
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final m = _selectedMail;
      if (m != null) {
        _onMailSelected(_selectedMailIndex!);
        _onOpenMail(m);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyA &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      if (_selectedIds.isEmpty) return KeyEventResult.ignored;
      _deleteMails(_selectedMessages.map((m) => m.id).toList());
      return KeyEventResult.handled;
    }

    int page = 10;
    if (_mailScrollController.hasClients) {
      final viewport = _mailScrollController.position.viewportDimension;
      page = (viewport / _mailRowHeight).floor().clamp(1, count);
    }

    final current = _selectedMailIndex ?? -1;
    int next;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = current + 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = current < 0 ? count - 1 : current - 1;
    } else if (key == LogicalKeyboardKey.pageDown) {
      next = current + page;
    } else if (key == LogicalKeyboardKey.pageUp) {
      next = (current < 0 ? count - 1 : current) - page;
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = count - 1;
    } else {
      return KeyEventResult.ignored;
    }
    next = next.clamp(0, count - 1);
    if (keyboard.isShiftPressed) {
      // Shift+arrow extends the selection from the anchor.
      _selectRange(next);
      _scrollMailIntoView(next);
    } else if (next != current || _hasMultiSelection) {
      _onMailSelected(next);
      _scrollMailIntoView(next);
    }
    return KeyEventResult.handled;
  }

  /// Scrolls the mail list so the message at [index] is fully visible.
  void _scrollMailIntoView(int index) {
    if (!_mailScrollController.hasClients) return;
    final position = _mailScrollController.position;
    final itemTop = index * _mailRowHeight;
    final itemBottom = itemTop + _mailRowHeight;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (itemTop < viewTop) {
      target = itemTop;
    } else if (itemBottom > viewBottom) {
      target = itemBottom - position.viewportDimension;
    }
    if (target != null) {
      _mailScrollController.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
  }

  void _onNewMail() {
    _enterCompose();
  }

  /// Enters the full-tab compose editor with the given initial content. When
  /// [replaceId] is set the editor edits an existing Draft/Outbox message.
  void _enterCompose({
    bool isEdit = false,
    String? replaceId,
    String to = '',
    String cc = '',
    String subject = '',
    String body = '',
    List<ComposedAttachment> attachments = const [],
  }) {
    setState(() {
      _composeIsEdit = isEdit;
      _composeReplaceId = replaceId;
      _composeInitialTo = to;
      _composeInitialCc = cc;
      _composeInitialSubject = subject;
      _composeInitialBody = body;
      _composeInitialAttachments = attachments;
      _composeKey = GlobalKey<MailComposeViewState>();
      _view = _MailView.compose;
    });
  }

  /// The user pressed Send in the compose editor: queue the message in the
  /// Outbox (or update the edited message) and return to the list.
  void _onComposeSend(ComposedMail mail) {
    _addComposedMail(mail, replaceId: _composeReplaceId);
    setState(() => _view = _MailView.list);
  }

  /// The user left the compose editor via the back arrow (or a tab
  /// re-selection). A non-null [draft] is saved to the Draft mailbox.
  void _onComposeExit(ComposedMail? draft) {
    if (draft != null) _addComposedMail(draft, replaceId: _composeReplaceId);
    setState(() => _view = _MailView.list);
  }

  /// Returns the tab to the mailbox list. When composing, the editor is asked
  /// to save a draft first (mirrors the back-arrow behaviour).
  void _onShowListRequested(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (_view == _MailView.compose) {
      // Delegates to the editor so any in-progress message is kept as a draft.
      _composeKey.currentState?.exitSavingDraft();
    } else if (_view == _MailView.view) {
      setState(() => _view = _MailView.list);
    }
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

    if (c.attachments.isNotEmpty) {
      mail.attachments = c.attachments
          .map((a) => WinLinkMailAttachement(name: a.name, data: a.data))
          .toList();
    }

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
    if (station == null || !mounted) return;

    // Validate the station's region/channel up front so a missing region or
    // channel offers a quick way to fix the contact instead of failing quietly.
    final l10n = AppLocalizations.of(context);
    if (station.channel.isEmpty && station.frequencyHz <= 0) {
      await showStationConnectErrorDialog(
        context,
        station: station,
        message: l10n.stationConnectErrorNoChannel,
      );
      return;
    }
    final res = resolveStationChannel(_broker, radioId, station);
    if (res.status == StationChannelStatus.regionMissing) {
      await showStationConnectErrorDialog(
        context,
        station: station,
        message: l10n.stationConnectErrorRegion(station.channelRegion),
      );
      return;
    }
    if (res.status == StationChannelStatus.channelMissing) {
      await showStationConnectErrorDialog(
        context,
        station: station,
        message: l10n.stationConnectErrorChannel(station.channel),
      );
      return;
    }

    _connectingStation = station;
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkSync',
      data: {'RadioId': radioId, 'Station': station},
      store: false,
    );
  }

  /// A radio reported that the station's channel could not be found in the
  /// region it switched to (a cross-region channel that no longer exists).
  /// Offers to fix the contact that was being connected to.
  void _onLockChannelResolveFailed(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (data is! Map || data['usage'] != 'Winlink') return;
    final station = _connectingStation;
    _connectingStation = null;
    if (station == null) return;
    // Abort the half-established connection before prompting to edit.
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkDisconnect',
      data: true,
      store: false,
    );
    final l10n = AppLocalizations.of(context);
    showStationConnectErrorDialog(
      context,
      station: station,
      message: l10n.stationConnectErrorChannel(station.channel),
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

  void _onReply() {
    final m = _selectedMail;
    if (m == null) return;
    _enterCompose(
      to: m.from,
      subject: _replySubject(m),
      body: _quotedReplyBody(m),
    );
  }

  void _onReplyAll() {
    final m = _selectedMail;
    if (m == null) return;
    _enterCompose(
      to: m.from,
      cc: m.cc,
      subject: _replySubject(m),
      body: _quotedReplyBody(m),
    );
  }

  void _onForward() {
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
    _enterCompose(
      subject: subject,
      body: body,
      attachments: _composeAttachmentsFor(m.id),
    );
  }

  /// Builds compose attachments from a raw mail's stored attachments, used when
  /// forwarding or editing a message.
  List<ComposedAttachment> _composeAttachmentsFor(String id) {
    final raw = _rawMails[id];
    final atts = raw?.attachments;
    if (atts == null) return const [];
    return atts
        .map((a) => ComposedAttachment(name: a.name, data: a.data))
        .toList();
  }

  /// Builds read-only viewer attachments from a raw mail's stored attachments.
  List<MailViewerAttachment> _viewerAttachmentsFor(String id) {
    final raw = _rawMails[id];
    final atts = raw?.attachments;
    if (atts == null) return const [];
    return atts
        .map(
          (a) => MailViewerAttachment(
            name: a.name,
            data: a.data,
            sizeBytes: a.data.length,
          ),
        )
        .toList();
  }

  /// Prompts for a destination and writes an attachment's bytes to disk.
  Future<void> _saveAttachment(WinLinkMailAttachement attachment) async {
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

  void _onOpenMail(MailMessage m) {
    final isEditable =
        _selectedMailbox == 'Draft' || _selectedMailbox == 'Outbox';
    if (isEditable) {
      _enterCompose(
        isEdit: true,
        replaceId: m.id,
        to: m.to,
        cc: m.cc,
        subject: m.subject,
        body: m.body,
        attachments: _composeAttachmentsFor(m.id),
      );
    } else {
      _markRead(m);
      setState(() => _view = _MailView.view);
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

  /// Deletes the focused message (preview toolbar and full-tab viewer).
  void _onDelete() {
    final m = _selectedMail;
    if (m == null) return;
    _deleteMails([m.id]);
  }

  /// Moves [ids] to Trash, or permanently deletes them when already in Trash,
  /// after confirmation.
  Future<void> _deleteMails(List<String> ids) async {
    if (ids.isEmpty) return;
    final inTrash = _selectedMailbox == 'Trash';
    final l10n = AppLocalizations.of(context);
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: inTrash ? l10n.mailDeleteTitle : l10n.mailMoveToTrashTitle,
      message: inTrash
          ? l10n.mailDeletePermanentCount(ids.length)
          : l10n.mailMoveToTrashPromptCount(ids.length),
      okText: inTrash ? l10n.commonDelete : l10n.mailMove,
    );
    if (!confirmed || !mounted) return;
    if (inTrash) {
      for (final id in ids) {
        _broker.dispatch(
          deviceId: 0,
          name: 'MailDelete',
          data: id,
          store: false,
        );
      }
      _clearSelection();
    } else {
      _moveMails(ids, 'Trash');
    }
    setState(() => _view = _MailView.list);
  }

  /// Whether messages may be moved from mailbox [from] to [to]. Outbox and
  /// Draft only exchange messages with each other, so received or sent mail is
  /// never queued for transmission by accident.
  bool _isMoveAllowed(String from, String to) {
    if (from == to || !_mailboxes.containsKey(to)) return false;
    const composed = {'Outbox', 'Draft'};
    if (composed.contains(to)) return composed.contains(from);
    return true;
  }

  /// Mailboxes the current mailbox's messages may be moved to.
  List<String> get _moveTargets => _mailboxes.keys
      .where((k) => _isMoveAllowed(_selectedMailbox, k))
      .toList();

  /// Moves [ids] to the [target] mailbox via the MailStore.
  void _moveMails(List<String> ids, String target) {
    for (final id in ids) {
      if (_rawMails[id]?.mailbox == target) continue;
      _broker.dispatch(
        deviceId: 0,
        name: 'MailMove',
        data: {'MID': id, 'Mailbox': target},
        store: false,
      );
    }
    _clearSelection();
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectedMailIndex = null;
      _selectionAnchor = null;
    });
  }

  /// Opens the right-click context menu for the mail list at [globalPosition].
  /// The menu acts on the current selection (see [_buildMailContextMenuItems]).
  void _showMailContextMenu(Offset globalPosition) {
    final box = _mailListKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _mailMenuController.open(position: box.globalToLocal(globalPosition));
  }

  /// Context menu entries for the selected mail. With several messages
  /// selected only the batch actions (Move To submenu and delete) are offered.
  List<Widget> _buildMailContextMenuItems() {
    final l10n = AppLocalizations.of(context);
    final inTrash = _selectedMailbox == 'Trash';
    final error = Theme.of(context).colorScheme.error;
    List<String> selectedIds() => _selectedMessages.map((m) => m.id).toList();
    return [
      if (!_hasMultiSelection) ...[
        MenuItemButton(
          leadingIcon: const Icon(Icons.open_in_new, size: 20),
          onPressed: () {
            final m = _selectedMail;
            if (m != null) _onOpenMail(m);
          },
          child: Text(l10n.mailOpen),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.reply, size: 20),
          onPressed: _onReply,
          child: Text(l10n.mailReply),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.reply_all, size: 20),
          onPressed: _onReplyAll,
          child: Text(l10n.mailReplyAll),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.forward, size: 20),
          onPressed: _onForward,
          child: Text(l10n.mailForward),
        ),
        const Divider(height: 1),
      ],
      SubmenuButton(
        leadingIcon: const Icon(Icons.drive_file_move_outline, size: 20),
        menuChildren: [
          for (final target in _moveTargets)
            MenuItemButton(
              leadingIcon: Icon(_mailboxes[target]!.icon, size: 20),
              onPressed: () => _moveMails(selectedIds(), target),
              child: Text(_mailboxDisplayName(target)),
            ),
        ],
        child: Text(l10n.mailMoveToMenu),
      ),
      MenuItemButton(
        leadingIcon: Icon(Icons.delete_outline, size: 20, color: error),
        onPressed: () => _deleteMails(selectedIds()),
        child: Text(
          inTrash ? l10n.commonDelete : l10n.mailMoveToTrashTitle,
          style: TextStyle(color: error),
        ),
      ),
    ];
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
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).mailBackup),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'restore',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).mailRestore),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'showTraffic',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Text(AppLocalizations.of(context).mailShowTraffic),
            ],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Text(AppLocalizations.of(context).tabDetach),
              ],
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
    final focusedId = _selectedMail?.id;
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = columnIndex != 0; // Descending for time by default
      }
      _applySort(_currentMessages);
      _restoreSelection(focusedId);
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
            Expanded(child: _buildContent()),
            _buildStatusPanel(),
          ],
        );
      },
    );
  }

  /// Selects the content shown in the tab body: the mailbox list, the full-tab
  /// viewer, or the full-tab compose editor. Viewer/compose bring their own
  /// header (with a back arrow); the list keeps the toolbar header.
  Widget _buildContent() {
    switch (_view) {
      case _MailView.compose:
        return MailComposeView(
          key: _composeKey,
          isEdit: _composeIsEdit,
          initialTo: _composeInitialTo,
          initialCc: _composeInitialCc,
          initialSubject: _composeInitialSubject,
          initialBody: _composeInitialBody,
          initialAttachments: _composeInitialAttachments,
          onSend: _onComposeSend,
          onExit: _onComposeExit,
        );
      case _MailView.view:
        final mail = _selectedMail;
        if (mail != null) return _buildViewerContent(mail);
        // Selection was lost (e.g. the list reloaded); fall back to the list.
        return _buildListContent();
      case _MailView.list:
        return _buildListContent();
    }
  }

  Widget _buildListContent() {
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
      ],
    );
  }

  /// Builds the full-tab read-only viewer for [mail].
  Widget _buildViewerContent(MailMessage mail) {
    final scheme = Theme.of(context).colorScheme;
    final station = _matchedStationForMail(mail);
    // Reuse the preview pane's corner-triangle avatar (or add-contact
    // affordance), shown at the top-right of the message.
    Widget? corner;
    if (station != null) {
      corner = _buildPreviewAvatar(station, scheme);
    } else if (_canAddContactForMail(mail)) {
      corner = _buildPreviewAddContact(mail, scheme);
    }
    return MailViewerView(
      from: mail.from,
      to: mail.to,
      cc: mail.cc,
      time: mail.time,
      subject: mail.subject,
      body: mail.body,
      attachments: _viewerAttachmentsFor(mail.id),
      cornerOverlay: corner,
      onReply: _onReply,
      onReplyAll: _onReplyAll,
      onForward: _onForward,
      onDelete: _onDelete,
      onBack: () => setState(() => _view = _MailView.list),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
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
                      onPressed: _syncInProgress
                          ? null
                          : () => _onConnect(buttonContext),
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
    return Focus(
      focusNode: _mailboxFocusNode,
      onKeyEvent: _handleMailboxKey,
      child: Container(
        color: scheme.surface,
        child: ListView(
          children: _mailboxes.entries.map((entry) {
            final mailbox = entry.value;
            final isSelected = _selectedMailbox == entry.key;
            final count = mailbox.messages.length;
            // Mail rows dragged from the list can be dropped on a mailbox to
            // move them there.
            return DragTarget<_MailDragData>(
              onWillAcceptWithDetails: (details) =>
                  _isMoveAllowed(details.data.fromMailbox, entry.key),
              onAcceptWithDetails: (details) =>
                  _moveMails(details.data.ids, entry.key),
              builder: (context, candidates, rejected) {
                final isDropTarget = candidates.isNotEmpty;
                return InkWell(
                  onTap: () {
                    _mailboxFocusNode.requestFocus();
                    _onMailboxSelected(entry.key);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDropTarget
                          ? scheme.secondaryContainer
                          : (isSelected ? scheme.primaryContainer : null),
                      border: isDropTarget
                          ? Border.all(color: scheme.secondary)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          mailbox.icon,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
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
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMailList() {
    final scheme = Theme.of(context).colorScheme;
    final selectedIds = _selectedMessages.map((m) => m.id).toList();
    final list = Focus(
      key: _mailListKey,
      focusNode: _mailListFocusNode,
      onKeyEvent: _handleMailListKey,
      child: Container(
        color: scheme.surface,
        child: Column(
          children: [
            // Column headers
            _buildMailListHeaders(),
            // Mail items
            Expanded(
              child: ListView.builder(
                controller: _mailScrollController,
                itemExtent: _mailRowHeight,
                itemCount: _currentMessages.length,
                itemBuilder: (context, index) {
                  final mail = _currentMessages[index];
                  final isSelected = _selectedIds.contains(mail.id);
                  final row = InkWell(
                    onTap: () {
                      _mailListFocusNode.requestFocus();
                      _onMailClicked(index);
                    },
                    onDoubleTap: () {
                      _onMailSelected(index);
                      _onOpenMail(mail);
                    },
                    onSecondaryTapDown: (details) {
                      _mailListFocusNode.requestFocus();
                      // Right-clicking inside a multi-selection keeps it so the
                      // menu acts on all selected messages.
                      if (!isSelected) _onMailSelected(index);
                      _showMailContextMenu(details.globalPosition);
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
                  // Drag & drop to a mailbox is only available while the
                  // mailbox tree (the drop targets) is shown.
                  if (_isCompact) return row;
                  return _buildDraggableRow(
                    row: row,
                    mail: mail,
                    index: index,
                    ids: isSelected ? selectedIds : <String>[mail.id],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    return MenuAnchor(
      controller: _mailMenuController,
      menuChildren: _buildMailContextMenuItems(),
      child: list,
    );
  }

  /// Wraps a mail row so it can be dragged onto a mailbox. Dragging a selected
  /// row carries the whole selection; dragging an unselected row selects and
  /// carries just that row. Touch platforms use a long press so the list can
  /// still be scrolled.
  Widget _buildDraggableRow({
    required Widget row,
    required MailMessage mail,
    required int index,
    required List<String> ids,
  }) {
    final data = _MailDragData(_selectedMailbox, ids);
    final feedback = _buildDragFeedback(mail, ids.length);
    void onDragStarted() {
      if (!_selectedIds.contains(mail.id)) _onMailSelected(index);
    }

    final isTouch =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isTouch) {
      return LongPressDraggable<_MailDragData>(
        data: data,
        feedback: feedback,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: onDragStarted,
        child: row,
      );
    }
    return Draggable<_MailDragData>(
      data: data,
      feedback: feedback,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      child: row,
    );
  }

  /// The chip shown under the pointer while dragging messages.
  Widget _buildDragFeedback(MailMessage mail, int count) {
    final scheme = Theme.of(context).colorScheme;
    final label = count == 1
        ? (mail.subject.isEmpty ? mail.from : mail.subject)
        : AppLocalizations.of(context).mailSelectedCount(count);
    return Transform.translate(
      offset: const Offset(12, 12),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        color: scheme.primaryContainer,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                count == 1 ? Icons.mail_outline : Icons.all_inbox,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
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
          _buildColumnHeader(
            AppLocalizations.of(context).mailColTime,
            0,
            flex: 2,
          ),
          _buildColumnHeader(
            _showRecipientColumn
                ? AppLocalizations.of(context).mailColTo
                : AppLocalizations.of(context).mailColFrom,
            1,
            flex: 2,
          ),
          _buildColumnHeader(
            AppLocalizations.of(context).mailColSubject,
            2,
            flex: 3,
          ),
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

  /// Builds the clickable attachment list shown in the preview pane. Returns an
  /// empty widget when the message has no attachments. Tapping a chip prompts to
  /// save the file to disk.
  Widget _buildPreviewAttachments(String id, ColorScheme scheme) {
    final atts = _rawMails[id]?.attachments;
    if (atts == null || atts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).mailAttachmentsLabel,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in atts)
                Tooltip(
                  message: AppLocalizations.of(context).mailSaveAttachment,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _saveAttachment(a),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
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
                          Text(a.name),
                          const SizedBox(width: 6),
                          Text(
                            '(${_formatAttachmentSize(a.data.length)})',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.download, size: 16, color: scheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatAttachmentSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildPreviewArea() {
    final scheme = Theme.of(context).colorScheme;
    if (_hasMultiSelection) return _buildMultiSelectionPanel(scheme);
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
    final previewStation = _matchedStationForMail(mail);
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
            child: Stack(
              children: [
                SingleChildScrollView(
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
                        _buildPreviewAttachments(mail.id, scheme),
                        const Divider(height: 24),
                        Text(mail.body),
                      ],
                    ),
                  ),
                ),
                // Flush to the toolbar (top) and the tabs bar (right).
                if (previewStation != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _buildPreviewAvatar(previewStation, scheme),
                  )
                else if (_canAddContactForMail(mail))
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _buildPreviewAddContact(mail, scheme),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shown in place of the preview when several messages are selected, with
  /// buttons to move or delete them all at once.
  Widget _buildMultiSelectionPanel(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    final ids = _selectedMessages.map((m) => m.id).toList();
    final inTrash = _selectedMailbox == 'Trash';
    return Container(
      color: scheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.all_inbox, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(
                l10n.mailSelectedCount(ids.length),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final target in _moveTargets)
                    if (target != 'Trash')
                      OutlinedButton.icon(
                        onPressed: () => _moveMails(ids, target),
                        icon: Icon(_mailboxes[target]!.icon, size: 18),
                        label: Text(
                          l10n.mailMoveTo(_mailboxDisplayName(target)),
                        ),
                      ),
                  OutlinedButton.icon(
                    onPressed: () => _deleteMails(ids),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(
                      inTrash ? l10n.commonDelete : l10n.mailMoveToTrashTitle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The matched contact's avatar over a filled corner triangle, shown at the
  /// top-right of the (scrollable) preview header. Tapping it opens the contact
  /// edit dialog.
  Widget _buildPreviewAvatar(StationInfo station, ColorScheme scheme) {
    const double corner = 88;
    return SizedBox(
      width: corner,
      height: corner,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _MailCornerTrianglePainter(
                  scheme.surfaceContainerHigh,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Tooltip(
              message: station.name.isNotEmpty
                  ? station.name
                  : station.callsign,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _editContact(station),
                child: ContactAvatar(
                  callsign: station.callsign,
                  avatarIcon: station.avatarIcon,
                  avatarImage: station.avatarImage,
                  radius: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Add-contact affordance shown at the top-right of the preview header when
  /// the correspondent is not in the contact list. Tapping it opens the
  /// add-contact dialog pre-filled with the address.
  Widget _buildPreviewAddContact(MailMessage mail, ColorScheme scheme) {
    const double corner = 88;
    return SizedBox(
      width: corner,
      height: corner,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _MailCornerTrianglePainter(
                  scheme.surfaceContainerHigh,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Tooltip(
              message: AppLocalizations.of(context).mailAddToContacts,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _addContactForMail(mail),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.person_add_alt_1,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fills the top-right corner with a triangle so scrolling content does not
/// peek around the avatar circle.
class _MailCornerTrianglePainter extends CustomPainter {
  final Color color;
  _MailCornerTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MailCornerTrianglePainter old) => old.color != color;
}
