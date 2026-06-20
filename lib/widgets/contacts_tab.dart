import 'package:flutter/material.dart';
import '../services/window_service.dart';
import '../services/data_broker_client.dart';
import '../models/station_info.dart';
import '../dialogs/add_station_dialog.dart';

/// Contacts tab - contact management
class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab>
    with AutomaticKeepAliveClientMixin {
  /// Device id that owns persisted application settings (the station list).
  static const int _settingsDeviceId = 0;

  final DataBrokerClient _broker = DataBrokerClient();
  final Set<int> _selectedIndices = {};
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  /// The current station list, loaded from and saved to the DataBroker.
  List<StationInfo> _contacts = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStations();
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'Stations',
      callback: _onStationsChanged,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _onStationsChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _loadStations();
      _selectedIndices.clear();
    });
  }

  /// Reads the current station list from the broker as a fresh, mutable list.
  ///
  /// The broker is the single source of truth (mirrors the C# `GetStations()`):
  /// handlers fetch the list with this, mutate it, then call [_saveStations].
  /// The UI is only rebuilt from the `Stations` subscription in
  /// [_onStationsChanged], so any instances sharing a broker stay in sync.
  List<StationInfo> _getStations() {
    final raw = _broker.getValueDynamic(_settingsDeviceId, 'Stations', null);
    final list = <StationInfo>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          list.add(StationInfo.fromJson(item));
        } else if (item is Map) {
          list.add(StationInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return list;
  }

  void _loadStations() {
    _contacts = _getStations();
    _applySort();
  }

  void _saveStations(List<StationInfo> stations) {
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'Stations',
      data: stations.map((s) => s.toJson()).toList(),
    );
  }

  String _getStationTypeName(StationType type) {
    switch (type) {
      case StationType.generic:
        return 'Generic Stations';
      case StationType.aprs:
        return 'APRS Stations';
      case StationType.terminal:
        return 'Terminal Stations';
      case StationType.bbs:
        return 'BBS Stations';
      case StationType.winlink:
        return 'Winlink Stations';
      case StationType.torrent:
        return 'Torrent Stations';
      case StationType.agwpe:
        return 'AGWPE Stations';
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
      case StationType.bbs:
        return Icons.forum;
      case StationType.winlink:
        return Icons.mail;
      case StationType.torrent:
        return Icons.swap_horiz;
      case StationType.agwpe:
        return Icons.lan;
    }
  }

  Future<void> _onAdd() async {
    final station = await showStationDialog(context);
    if (station == null || !mounted) return;
    final stations = _getStations();
    final exists = stations.any(
      (s) =>
          s.callsign == station.callsign &&
          s.stationType == station.stationType,
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A station with this callsign and type already exists'),
        ),
      );
      return;
    }
    stations.add(station);
    // The UI updates via the 'Stations' subscription in _onStationsChanged.
    _saveStations(stations);
  }

  void _onRemove() {
    if (_selectedIndices.isEmpty) return;

    // Capture the selected stations from the currently displayed list so we can
    // match them against the broker's authoritative list when removing.
    final selectedStations = _selectedIndices
        .where((i) => i >= 0 && i < _contacts.length)
        .map((i) => _contacts[i])
        .toList();
    if (selectedStations.isEmpty) return;

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
      if (confirmed != true) return;
      final stations = _getStations();
      for (final station in selectedStations) {
        stations.removeWhere(
          (s) =>
              s.callsign == station.callsign &&
              s.stationType == station.stationType,
        );
      }
      // The UI updates via the 'Stations' subscription in _onStationsChanged.
      _saveStations(stations);
    });
  }

  Future<void> _onEdit() async {
    if (_selectedIndices.length != 1) return;
    final index = _selectedIndices.first;
    if (index < 0 || index >= _contacts.length) return;
    final existing = _contacts[index];

    final updated = await showStationDialog(context, existing: existing);
    if (updated == null || !mounted) return;

    final stations = _getStations();
    // Remove the old entry and add the updated one (mirrors the C# edit flow).
    stations.removeWhere(
      (s) =>
          s.callsign == existing.callsign &&
          s.stationType == existing.stationType,
    );
    stations.add(updated);
    // The UI updates via the 'Stations' subscription in _onStationsChanged.
    _saveStations(stations);
    // Notify listeners (e.g. active station lock) of the update.
    _broker.dispatch(
      deviceId: _settingsDeviceId,
      name: 'StationUpdated',
      data: updated.toJson(),
      store: false,
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
      _applySort();
    });
  }

  void _applySort() {
    _contacts.sort((a, b) {
      String aValue, bValue;
      switch (_sortColumnIndex) {
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
    final groupedContacts = <StationType, List<MapEntry<int, StationInfo>>>{};
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

  Widget _buildContactRow(int index, StationInfo contact) {
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
                        contact.callsignNoZero,
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
