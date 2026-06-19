import 'package:flutter/material.dart';
import '../services/window_service.dart';

/// Station type enum matching C# StationTypes
enum StationType { generic, aprs, terminal, winlink, bbs, torrent }

/// Contact/Station information
class ContactInfo {
  final String callsign;
  final String name;
  final String description;
  final StationType stationType;

  const ContactInfo({
    required this.callsign,
    required this.name,
    this.description = '',
    this.stationType = StationType.generic,
  });
}

/// Contacts tab - contact management
class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab>
    with AutomaticKeepAliveClientMixin {
  final Set<int> _selectedIndices = {};
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  // Sample contacts data
  final List<ContactInfo> _contacts = [
    const ContactInfo(
      callsign: 'KK7VZT',
      name: 'Ylian Saint-Hilaire',
      description: 'HTCommander Author',
      stationType: StationType.generic,
    ),
    const ContactInfo(
      callsign: 'KC3SLD',
      name: 'Kyle Husmann',
      description: 'BenLink Author',
      stationType: StationType.generic,
    ),
    const ContactInfo(
      callsign: 'APRS-1',
      name: 'Local Digipeater',
      description: 'Regional APRS digipeater',
      stationType: StationType.aprs,
    ),
    const ContactInfo(
      callsign: 'WL2K-1',
      name: 'Winlink Gateway',
      description: 'Regional Winlink RMS',
      stationType: StationType.winlink,
    ),
    const ContactInfo(
      callsign: 'BBS-1',
      name: 'Local BBS',
      description: 'Community bulletin board',
      stationType: StationType.bbs,
    ),
    const ContactInfo(
      callsign: 'TERM-1',
      name: 'Terminal Server',
      description: 'Packet terminal server',
      stationType: StationType.terminal,
    ),
  ];

  @override
  bool get wantKeepAlive => true;

  String _getStationTypeName(StationType type) {
    switch (type) {
      case StationType.generic:
        return 'Generic Stations';
      case StationType.aprs:
        return 'APRS Stations';
      case StationType.terminal:
        return 'Terminal Stations';
      case StationType.winlink:
        return 'Winlink Stations';
      case StationType.bbs:
        return 'BBS Stations';
      case StationType.torrent:
        return 'Torrent Stations';
    }
  }

  IconData _getStationIcon(StationType type) {
    switch (type) {
      case StationType.generic:
        return Icons.person;
      case StationType.aprs:
        return Icons.location_on;
      case StationType.terminal:
        return Icons.terminal;
      case StationType.winlink:
        return Icons.mail;
      case StationType.bbs:
        return Icons.forum;
      case StationType.torrent:
        return Icons.swap_horiz;
    }
  }

  void _onAdd() {
    // TODO: Show add contact dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add contact dialog not implemented yet')),
    );
  }

  void _onRemove() {
    if (_selectedIndices.isEmpty) return;

    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contacts'),
        content: const Text('Remove selected station?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          final indicesToRemove = _selectedIndices.toList()
            ..sort((a, b) => b.compareTo(a));
          for (final index in indicesToRemove) {
            _contacts.removeAt(index);
          }
          _selectedIndices.clear();
        });
      }
    });
  }

  void _onEdit() {
    if (_selectedIndices.length != 1) return;
    // TODO: Show edit contact dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit contact dialog not implemented yet')),
    );
  }

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;
    final hasSelection = _selectedIndices.isNotEmpty;
    final hasSingleSelection = _selectedIndices.length == 1;

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
          value: 'edit',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: hasSingleSelection,
          child: const Row(children: [SizedBox(width: 20), Text('Edit')]),
        ),
        PopupMenuItem<String>(
          value: 'remove',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: hasSelection,
          child: const Row(children: [SizedBox(width: 20), Text('Remove')]),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'export',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(children: [SizedBox(width: 20), Text('Export...')]),
        ),
        PopupMenuItem<String>(
          value: 'import',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(children: [SizedBox(width: 20), Text('Import...')]),
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
        case 'edit':
          _onEdit();
          break;
        case 'remove':
          _onRemove();
          break;
        case 'export':
          // TODO: Implement export
          break;
        case 'import':
          // TODO: Implement import
          break;
        case 'detach':
          windowService.createWindow('contacts');
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
        _sortAscending = true;
      }
      _contacts.sort((a, b) {
        String aValue, bValue;
        switch (columnIndex) {
          case 0:
            aValue = a.callsign;
            bValue = b.callsign;
            break;
          case 1:
            aValue = a.name;
            bValue = b.name;
            break;
          case 2:
            aValue = a.description;
            bValue = b.description;
            break;
          default:
            aValue = a.callsign;
            bValue = b.callsign;
        }
        return _sortAscending
            ? aValue.compareTo(bValue)
            : bValue.compareTo(aValue);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Column(
      children: [
        // Header bar
        _buildHeader(),
        // Contact list
        Expanded(child: _buildContactList()),
        // Bottom button panel
        _buildBottomPanel(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      color: const Color(0xFFC0C0C0), // Silver color
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Contacts label
          const Text(
            'Contacts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          // Menu icon
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
      ),
    );
  }

  Widget _buildContactList() {
    // Group contacts by station type
    final groupedContacts = <StationType, List<MapEntry<int, ContactInfo>>>{};
    for (var i = 0; i < _contacts.length; i++) {
      final contact = _contacts[i];
      groupedContacts
          .putIfAbsent(contact.stationType, () => [])
          .add(MapEntry(i, contact));
    }

    return Container(
      color: Colors.white,
      child: ListView(
        children: [
          // Column headers
          _buildColumnHeaders(),
          // Grouped contacts
          for (final type in StationType.values)
            if (groupedContacts.containsKey(type)) ...[
              _buildGroupHeader(type),
              for (final entry in groupedContacts[type]!)
                _buildContactRow(entry.key, entry.value),
            ],
        ],
      ),
    );
  }

  Widget _buildColumnHeaders() {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: [
          _buildColumnHeader('Callsign', 0, flex: 2),
          _buildColumnHeader('Name', 1, flex: 3),
          _buildColumnHeader('Description', 2, flex: 4),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(String title, int index, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: InkWell(
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
                      _sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 14,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGroupHeader(StationType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        border: Border(
          top: BorderSide(color: Colors.grey.shade400),
          bottom: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      child: Text(
        _getStationTypeName(type),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildContactRow(int index, ContactInfo contact) {
    final isSelected = _selectedIndices.contains(index);
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIndices.remove(index);
          } else {
            _selectedIndices.add(index);
          }
        });
      },
      onDoubleTap: () {
        setState(() {
          _selectedIndices.clear();
          _selectedIndices.add(index);
        });
        _onEdit();
      },
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade100 : null,
          border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _getStationIcon(contact.stationType),
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        contact.callsign,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(contact.name, overflow: TextOverflow.ellipsis),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  contact.description,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    final hasSelection = _selectedIndices.isNotEmpty;
    final hasSingleSelection = _selectedIndices.length == 1;

    return Container(
      height: 50,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showAllButtons = constraints.maxWidth > 280;
          final showEditButton = constraints.maxWidth > 180;
          return Row(
            children: [
              // Add button
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: _onAdd,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Add'),
                ),
              ),
              if (showAllButtons) ...[
                const SizedBox(width: 8),
                // Remove button
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: hasSelection ? _onRemove : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Remove'),
                  ),
                ),
              ],
              if (showEditButton) ...[
                const SizedBox(width: 8),
                // Edit button
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    onPressed: hasSingleSelection ? _onEdit : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Edit...'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
