/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../models/station_info.dart';
import '../services/data_broker_client.dart';
import '../l10n/app_localizations.dart';
import 'add_station_dialog.dart';
import 'dialog_utils.dart';

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
      fixedType: stationType,
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
    fixedType: stationType,
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

  String _title(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (stationType) {
      case StationType.terminal:
        return l10n.assConnectTerminal;
      case StationType.bbs:
        return l10n.assConnectBbs;
      case StationType.winlink:
        return l10n.assConnectWinlink;
      default:
        return l10n.assConnectStation;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(_title(context), style: DialogStyles.titleStyle),
              const SizedBox(height: 16),
              // Station list section card
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: stations.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final station = stations[index];
                        final subtitle = station.name.isNotEmpty
                            ? station.name
                            : station.description;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.cell_tower,
                            color: Colors.blue.shade700,
                          ),
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
              ),
              const SizedBox(height: 16),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      const StationSelectorResult(StationSelectorAction.cancel),
                    ),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(
                      const StationSelectorResult(
                        StationSelectorAction.createNew,
                      ),
                    ),
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).assNew),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
