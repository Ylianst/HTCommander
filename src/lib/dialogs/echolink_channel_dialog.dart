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
import '../services/data_broker_client.dart';

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
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _searchController = TextEditingController();

  List<StationData> _stations = const [];
  String _state = 'Disconnected';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _state = _broker.getValue<String>(echoLinkDeviceId, 'State') ?? 'Disconnected';
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

  List<StationData> get _filtered {
    if (_query.isEmpty) return _stations;
    final q = _query.toUpperCase();
    return _stations
        .where((s) =>
            s.callsign.toUpperCase().contains(q) ||
            s.description.toUpperCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Add EchoLink Channel'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search callsign or location',
                      border: OutlineInputBorder(),
                    ),
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
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(scheme)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
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
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _broker.dispatch(
                deviceId: echoLinkDeviceId,
                name: 'EchoLinkGoOnline',
                data: null,
                store: false,
              ),
              icon: const Icon(Icons.login),
              label: const Text('Go Online'),
            ),
          ],
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _stations.isEmpty
              ? 'Loading directory...'
              : 'No stations match your search.',
          style: TextStyle(color: scheme.outline),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final station = items[index];
        final bool online = station.status == StationStatus.online;
        final bool busy = station.status == StationStatus.busy;
        final bool already =
            widget.existingCallsigns.contains(station.callsign.toUpperCase());
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.circle,
            size: 12,
            color: busy
                ? Colors.orange
                : online
                    ? Colors.green
                    : scheme.outline,
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
}
