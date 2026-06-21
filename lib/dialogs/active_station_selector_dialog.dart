/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../models/station_info.dart';
import '../services/data_broker_client.dart';
import 'add_station_dialog.dart';

/// Result of the active-station selector dialog.
enum StationSelectorAction { selected, createNew, cancel }

/// The dialog result: an action plus the chosen station (when [action] is
/// [StationSelectorAction.selected] or [StationSelectorAction.createNew]).
class StationSelectorResult {
  final StationSelectorAction action;
  final StationInfo? station;

  const StationSelectorResult(this.action, [this.station]);
}

/// Shows the active-station selector, a port of the C# `ActiveStationSelectorForm`.
///
/// Lists the saved stations of [stationType] (read from `Stations` on broker
/// device 0) so the user can pick one to connect to, or create a new one. When
/// no stations of the requested type exist, the create-station dialog is shown
/// directly. Returns the selected/created [StationInfo], or `null` if cancelled.
Future<StationInfo?> showActiveStationSelector(
  BuildContext context, {
  required StationType stationType,
}) async {
  final stations = _loadStations(stationType);

  // No stations of this type yet: go straight to the add-station dialog, with
  // the type fixed (mirrors `ProceedWithConnection` when the count is zero).
  if (stations.isEmpty) {
    final created = await showStationDialog(
      context,
      existing: StationInfo(stationType: stationType),
    );
    if (created == null) return null;
    _appendStation(created);
    return created;
  }

  if (!context.mounted) return null;
  final result = await showDialog<StationSelectorResult>(
    context: context,
    barrierDismissible: true,
    builder: (context) =>
        _StationSelectorDialog(stationType: stationType, stations: stations),
  );

  if (result == null || result.action == StationSelectorAction.cancel) {
    return null;
  }

  if (result.action == StationSelectorAction.selected) {
    return result.station;
  }

  // createNew: show the add-station dialog with the type fixed.
  if (!context.mounted) return null;
  final created = await showStationDialog(
    context,
    existing: StationInfo(stationType: stationType),
  );
  if (created == null) return null;
  _appendStation(created);
  return created;
}

/// Reads the persisted stations from broker device 0 and filters by type.
List<StationInfo> _loadStations(StationType stationType) {
  final broker = DataBrokerClient();
  try {
    final raw = broker.getValueDynamic(0, 'Stations', null);
    if (raw is! List) return [];
    final all = raw
        .whereType<Map>()
        .map((e) => StationInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return all.where((s) => s.stationType == stationType).toList();
  } finally {
    broker.dispose();
  }
}

/// Appends [station] to the persisted `Stations` list on broker device 0.
void _appendStation(StationInfo station) {
  final broker = DataBrokerClient();
  try {
    final raw = broker.getValueDynamic(0, 'Stations', null);
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) list.add(Map<String, dynamic>.from(item));
      }
    }
    list.add(station.toJson());
    broker.dispatch(deviceId: 0, name: 'Stations', data: list, store: true);
  } finally {
    broker.dispose();
  }
}

class _StationSelectorDialog extends StatelessWidget {
  final StationType stationType;
  final List<StationInfo> stations;

  const _StationSelectorDialog({
    required this.stationType,
    required this.stations,
  });

  String get _title {
    switch (stationType) {
      case StationType.terminal:
        return 'Connect to Terminal Station';
      case StationType.bbs:
        return 'Connect to BBS Station';
      case StationType.winlink:
        return 'Connect to Winlink Gateway';
      default:
        return 'Connect to Station';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 380,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: stations.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final station = stations[index];
              final subtitle = station.name.isNotEmpty
                  ? station.name
                  : station.description;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.cell_tower),
                title: Text(station.callsign),
                subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                onTap: () => Navigator.of(context).pop(
                  StationSelectorResult(
                    StationSelectorAction.selected,
                    station,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const StationSelectorResult(StationSelectorAction.cancel)),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const StationSelectorResult(StationSelectorAction.createNew)),
          child: const Text('New…'),
        ),
      ],
    );
  }
}
