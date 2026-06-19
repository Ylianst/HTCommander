import 'package:flutter/material.dart';
import '../services/window_service.dart';

/// Email message data
class MailMessage {
  final String id;
  final DateTime time;
  final String from;
  final String to;
  final String subject;
  final String body;
  final bool isRead;

  const MailMessage({
    required this.id,
    required this.time,
    required this.from,
    required this.to,
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

  // Mailboxes with sample data
  late final Map<String, Mailbox> _mailboxes;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeMailboxes();
  }

  void _initializeMailboxes() {
    _mailboxes = {
      'Inbox': Mailbox(
        name: 'Inbox',
        icon: Icons.inbox,
        messages: [
          MailMessage(
            id: '1',
            time: DateTime.now().subtract(const Duration(hours: 2)),
            from: 'KK7VZT',
            to: 'KC3SLD',
            subject: 'Welcome to Winlink!',
            body:
                'Hello and welcome to the Winlink network!\n\nThis is a test message to demonstrate the mail functionality.\n\n73,\nKK7VZT',
          ),
          MailMessage(
            id: '2',
            time: DateTime.now().subtract(const Duration(days: 1)),
            from: 'WL2K-1',
            to: 'KC3SLD',
            subject: 'System Notification',
            body:
                'Your message has been successfully delivered.\n\nWinlink Gateway',
            isRead: true,
          ),
          MailMessage(
            id: '3',
            time: DateTime.now().subtract(const Duration(days: 3)),
            from: 'N0CALL',
            to: 'KC3SLD',
            subject: 'Re: Field Day Planning',
            body:
                'Sounds good! I will bring the antenna.\n\nSee you there!\n\n73,\nN0CALL',
            isRead: true,
          ),
        ],
      ),
      'Outbox': Mailbox(name: 'Outbox', icon: Icons.outbox),
      'Draft': Mailbox(
        name: 'Draft',
        icon: Icons.drafts,
        messages: [
          MailMessage(
            id: '4',
            time: DateTime.now().subtract(const Duration(hours: 5)),
            from: 'KC3SLD',
            to: 'KK7VZT',
            subject: 'Draft message',
            body: 'This is a draft message that has not been sent yet...',
          ),
        ],
      ),
      'Sent': Mailbox(
        name: 'Sent',
        icon: Icons.send,
        messages: [
          MailMessage(
            id: '5',
            time: DateTime.now().subtract(const Duration(days: 2)),
            from: 'KC3SLD',
            to: 'KK7VZT',
            subject: 'Hello!',
            body: 'Hi there!\n\nJust testing the mail system.\n\n73,\nKC3SLD',
            isRead: true,
          ),
        ],
      ),
      'Archive': Mailbox(name: 'Archive', icon: Icons.archive),
      'Trash': Mailbox(name: 'Trash', icon: Icons.delete),
    };
  }

  List<MailMessage> get _currentMessages =>
      _mailboxes[_selectedMailbox]?.messages ?? [];

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

  void _onNewMail() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New mail dialog not implemented yet')),
    );
  }

  void _onConnect() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connect to Winlink not implemented yet')),
    );
  }

  void _onReply() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Reply not implemented yet')));
  }

  void _onForward() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Forward not implemented yet')),
    );
  }

  void _onDelete() {
    if (_selectedMailIndex == null) return;
    setState(() {
      _currentMessages.removeAt(_selectedMailIndex!);
      _selectedMailIndex = null;
    });
  }

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    showMenu<String>(
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
              const Text('Show Preview'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'backup',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Backup Mail...')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'restore',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Restore Mail...')],
          ),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: const Row(
              children: [SizedBox(width: 20), Text('Detach...')],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'showPreview':
          setState(() => _showPreview = !_showPreview);
          break;
        case 'detach':
          windowService.createWindow('mail');
          break;
      }
    });
  }

  void _sort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = columnIndex != 0; // Descending for time by default
      }
      _currentMessages.sort((a, b) {
        int result;
        switch (columnIndex) {
          case 0:
            result = a.time.compareTo(b.time);
            break;
          case 1:
            result = a.from.compareTo(b.from);
            break;
          case 2:
            result = a.subject.compareTo(b.subject);
            break;
          default:
            result = 0;
        }
        return _sortAscending ? result : -result;
      });
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

  Widget _buildSplitter(double totalHeight) {
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
          color: const Color(0xFFC0C0C0),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButtons = constraints.maxWidth > 280;
          return Row(
            children: [
              const Text(
                'Mail',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
                    child: const Text('New Mail'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _onConnect,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Connect'),
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
        // Mailbox tree
        SizedBox(width: 150, child: _buildMailboxTree()),
        const VerticalDivider(width: 1),
        // Mail list
        Expanded(child: _buildMailList()),
      ],
    );
  }

  Widget _buildMailboxTree() {
    return Container(
      color: Colors.white,
      child: ListView(
        children: _mailboxes.entries.map((entry) {
          final mailbox = entry.value;
          final isSelected = _selectedMailbox == entry.key;
          final count = mailbox.messages.length;
          return InkWell(
            onTap: () => _onMailboxSelected(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: isSelected ? Colors.blue.shade100 : null,
              child: Row(
                children: [
                  Icon(mailbox.icon, size: 20, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      count > 0 ? '${mailbox.name} ($count)' : mailbox.name,
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
    return Container(
      color: Colors.white,
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
                    // TODO: Open mail viewer
                  },
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade100 : null,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
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
                              mail.from,
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
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: [
          _buildColumnHeader('Time', 0, flex: 2),
          _buildColumnHeader('From', 1, flex: 2),
          _buildColumnHeader('Subject', 2, flex: 3),
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
          final showIcon = constraints.maxWidth > 30 && _sortColumnIndex == index;
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
    if (_selectedMail == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'Select a message to preview',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final mail = _selectedMail!;
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toolbar
          Container(
            height: 36,
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.reply, size: 20),
                  onPressed: _onReply,
                  tooltip: 'Reply',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: const Icon(Icons.reply_all, size: 20),
                  onPressed: _onReply,
                  tooltip: 'Reply All',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: const Icon(Icons.forward, size: 20),
                  onPressed: _onForward,
                  tooltip: 'Forward',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: _onDelete,
                  tooltip: 'Delete',
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
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  Text(
                    'To: ${mail.to}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  Text(
                    'Date: ${mail.time}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const Divider(height: 24),
                  Text(mail.body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
