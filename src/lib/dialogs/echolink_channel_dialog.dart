/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// echolink_channel_dialog.dart - Picker for adding an EchoLink station to the
// favorites shown below the EchoLink radio.
//
// The EchoLink directory is very long, so this dialog offers a searchable list
// of the live directory (device 200 'StationList'). Picking a station returns
// it so the caller can store it as a favorite "channel".
//

import 'package:flutter/material.dart';

import '../echolink/echolink_client.dart' show echoLinkDeviceId;
import '../echolink/echolink_station.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// EchoLink station categories, derived from the callsign suffix/prefix.
enum _EchoLinkStationKind { user, link, repeater, conference }

/// Shows the EchoLink station picker and returns the chosen station, or null if
/// the user cancelled. [existingCallsigns] (upper-case) are already-favorited
/// stations, shown disabled so they can't be added twice.
Future<StationData?> showEchoLinkChannelDialog(
  BuildContext context, {
  Set<String> existingCallsigns = const {},
}) {
  return showDialog<StationData>(
    context: context,
    builder: (context) =>
        _EchoLinkChannelDialog(existingCallsigns: existingCallsigns),
  );
}

class _EchoLinkChannelDialog extends StatefulWidget {
  final Set<String> existingCallsigns;

  const _EchoLinkChannelDialog({required this.existingCallsigns});

  @override
  State<_EchoLinkChannelDialog> createState() => _EchoLinkChannelDialogState();
}

class _EchoLinkChannelDialogState extends State<_EchoLinkChannelDialog> {
  /// Only the first [_maxResults] matching stations are rendered so the very
  /// long directory does not make the dialog sluggish.
  static const int _maxResults = 100;

  /// Data Broker key (device 0) used to persist the station-type filter
  /// across dialog openings.
  static const String _filterStoreKey = 'EchoLinkChannelFilter';

  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _searchController = TextEditingController();

  List<StationData> _stations = const [];
  String _state = 'Disconnected';
  String _query = '';
  // Active station-type filter; null means "All".
  _EchoLinkStationKind? _filterKind;

  @override
  void initState() {
    super.initState();
    _state = _broker.getValue<String>(echoLinkDeviceId, 'State') ?? 'Disconnected';
    _filterKind = _restoreFilter();
    _stations = _parseStations(
      _broker.getValueDynamic(echoLinkDeviceId, 'StationList'),
    );
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'State',
      callback: _onState,
    );
    _broker.subscribe(
      deviceId: echoLinkDeviceId,
      name: 'StationList',
      callback: _onStationList,
    );
  }

  /// Reads the persisted station-type filter from Data Broker device 0.
  _EchoLinkStationKind? _restoreFilter() {
    final stored = _broker.getValue<String>(0, _filterStoreKey);
    if (stored == null) return null;
    for (final kind in _EchoLinkStationKind.values) {
      if (kind.name == stored) return kind;
    }
    return null;
  }

  /// Stores the active station-type filter in Data Broker device 0.
  void _setFilter(_EchoLinkStationKind? kind) {
    setState(() => _filterKind = kind);
    _broker.dispatch(
      deviceId: 0,
      name: _filterStoreKey,
      data: kind?.name,
      store: true,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onState(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() => _state = data as String? ?? _state);
  }

  void _onStationList(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() => _stations = _parseStations(data));
  }

  static List<StationData> _parseStations(Object? data) {
    if (data is! List) return const [];
    final out = <StationData>[];
    for (final item in data) {
      if (item is! Map) continue;
      final callsign = (item['Callsign'] ?? item['callsign'] ?? '') as String;
      if (callsign.isEmpty) continue;
      StationStatus status = StationStatus.unknown;
      final s = item['Status'] ?? item['status'];
      if (s is String) {
        status = StationStatus.values.firstWhere(
          (v) => v.name == s,
          orElse: () => StationStatus.unknown,
        );
      }
      out.add(StationData(
        callsign: callsign,
        description: (item['Description'] ?? item['description'] ?? '') as String,
        status: status,
        time: (item['Time'] ?? item['time'] ?? '') as String,
        id: (item['Id'] ?? item['id'] ?? 0) as int,
        ip: (item['Ip'] ?? item['ip'] ?? '') as String,
      ));
    }
    return out;
  }

  bool get _online =>
      _state == 'Online' || _state == 'Connecting' || _state == 'Connected';

  /// All stations matching the current search + type filter (unbounded), used
  /// for the count.
  List<StationData> get _matches {
    Iterable<StationData> list = _stations;
    if (_filterKind != null) {
      list = list.where((s) => _kindOf(s) == _filterKind);
    }
    if (_query.isNotEmpty) {
      final q = _query.toUpperCase();
      list = list.where((s) =>
          s.callsign.toUpperCase().contains(q) ||
          s.description.toUpperCase().contains(q));
    }
    return list.toList();
  }

  static _EchoLinkStationKind _kindOf(StationData s) {
    if (s.isConference) return _EchoLinkStationKind.conference;
    if (s.isRepeater) return _EchoLinkStationKind.repeater;
    if (s.isLink) return _EchoLinkStationKind.link;
    return _EchoLinkStationKind.user;
  }

  static IconData _kindIcon(_EchoLinkStationKind kind) {
    switch (kind) {
      case _EchoLinkStationKind.user:
        return Icons.person;
      case _EchoLinkStationKind.link:
        return Icons.link;
      case _EchoLinkStationKind.repeater:
        return Icons.cell_tower;
      case _EchoLinkStationKind.conference:
        return Icons.groups;
    }
  }

  static String _kindLabel(_EchoLinkStationKind kind) {
    switch (kind) {
      case _EchoLinkStationKind.user:
        return 'Users';
      case _EchoLinkStationKind.link:
        return 'Links';
      case _EchoLinkStationKind.repeater:
        return 'Repeaters';
      case _EchoLinkStationKind.conference:
        return 'Conferences';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add EchoLink Channel',
                style: DialogStyles.titleStyle.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: _inputDecoration(
                        hintText: 'Search callsign or location',
                      ).copyWith(prefixIcon: const Icon(Icons.search)),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _online
                        ? () => _broker.dispatch(
                              deviceId: echoLinkDeviceId,
                              name: 'EchoLinkRefreshStations',
                              data: null,
                              store: false,
                            )
                        : null,
                    icon: const Icon(Icons.refresh),
                  ),
                  _buildFilterMenu(scheme),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: _sectionDecoration(),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _buildBody(scheme),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (!_online) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'EchoLink is offline.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _broker.dispatch(
                deviceId: echoLinkDeviceId,
                name: 'EchoLinkGoOnline',
                data: null,
                store: false,
              ),
              style: DialogStyles.primaryButtonStyle(context),
              icon: const Icon(Icons.login),
              label: const Text('Go Online'),
            ),
          ],
        ),
      );
    }

    final matches = _matches;
    if (matches.isEmpty) {
      return Center(
        child: Text(
          _stations.isEmpty
              ? 'Loading directory...'
              : 'No stations match your search.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final bool truncated = matches.length > _maxResults;
    final items =
        truncated ? matches.sublist(0, _maxResults) : matches;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length + (truncated ? 1 : 0),
      itemBuilder: (context, index) {
        if (truncated && index == items.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Showing first $_maxResults of ${matches.length} matches. '
                'Refine your search to narrow it down.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        final station = items[index];
        final bool online = station.status == StationStatus.online;
        final bool busy = station.status == StationStatus.busy;
        final bool already = widget.existingCallsigns
            .contains(station.callsign.toUpperCase());
        final kind = _kindOf(station);
        final Color statusColor = busy
            ? Colors.orange
            : online
                ? Colors.green
                : scheme.outline;
        return ListTile(
          dense: true,
          leading: Tooltip(
            message: _kindLabel(kind),
            child: Icon(_kindIcon(kind), size: 20, color: statusColor),
          ),
          title: Text(station.callsign),
          subtitle: station.description.isEmpty
              ? null
              : Text(
                  station.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: already
              ? const Icon(Icons.check, size: 18)
              : const Icon(Icons.add, size: 18),
          enabled: !already,
          onTap: already ? null : () => Navigator.of(context).pop(station),
        );
      },
    );
  }

  // --- Styling helpers mirroring the settings dialog -----------------------

  /// A filter icon whose popup menu selects the station-type filter.
  Widget _buildFilterMenu(ColorScheme scheme) {
    // PopupMenuButton treats a null value as "cancel", so "All" is encoded as
    // -1 and each kind as its enum index.
    PopupMenuItem<int> item(
      String label,
      _EchoLinkStationKind? kind,
      IconData? icon,
    ) {
      final bool selected = _filterKind == kind;
      return PopupMenuItem<int>(
        value: kind?.index ?? -1,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: selected
                  ? Icon(Icons.check, size: 18, color: scheme.primary)
                  : null,
            ),
            Icon(
              icon ?? Icons.list,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );
    }

    return PopupMenuButton<int>(
      tooltip: 'Filter',
      icon: Icon(
        _filterKind == null ? Icons.filter_list : Icons.filter_list_alt,
        color: _filterKind == null ? null : scheme.primary,
      ),
      onSelected: (value) => _setFilter(
        value < 0 ? null : _EchoLinkStationKind.values[value],
      ),
      itemBuilder: (context) => [
        item('All', null, Icons.list),
        for (final kind in _EchoLinkStationKind.values)
          item(_kindLabel(kind), kind, _kindIcon(kind)),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hintText}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      hintText: hintText,
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
}
