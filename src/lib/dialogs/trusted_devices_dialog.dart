/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Shows the list of Bluetooth trusted (paired) devices stored on the radio. The
list is read from the radio one entry at a time (GET_TRUSTED_DEVICE) by the
Radio handler and published through the DataBroker as `TrustedDevices`. Each row
shows the device name above its MAC address (matching the Radio Connection
form) with a delete button to remove it from the radio.
*/

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// One trusted device entry read from the radio.
class _TrustedDevice {
  final int index;
  final String mac;
  final String name;
  _TrustedDevice({required this.index, required this.mac, required this.name});
}

/// Shows the Trusted Devices dialog for [deviceId] (the currently selected
/// radio).
Future<void> showTrustedDevicesDialog(
  BuildContext context, {
  required int deviceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _TrustedDevicesDialog(deviceId: deviceId),
  );
}

class _TrustedDevicesDialog extends StatefulWidget {
  final int deviceId;
  const _TrustedDevicesDialog({required this.deviceId});

  @override
  State<_TrustedDevicesDialog> createState() => _TrustedDevicesDialogState();
}

class _TrustedDevicesDialogState extends State<_TrustedDevicesDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  List<_TrustedDevice> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _applyTrustedDevices(
      _broker.getValueDynamic(widget.deviceId, 'TrustedDevices'),
    );
    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'TrustedDevices',
      callback: _onTrustedDevices,
    );

    // Request a fresh copy so the dialog reflects the radio's current state.
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'QueryTrustedDevices',
      data: null,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.unsubscribe(widget.deviceId, 'TrustedDevices');
    _broker.dispose();
    super.dispose();
  }

  void _onTrustedDevices(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != widget.deviceId) return;
    setState(() => _applyTrustedDevices(data));
  }

  void _applyTrustedDevices(Object? data) {
    if (data is! Map) return;
    _loading = data['loading'] == true;
    final rawList = data['devices'];
    final devices = <_TrustedDevice>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          devices.add(
            _TrustedDevice(
              index: (item['index'] as num?)?.toInt() ?? 0,
              mac: item['mac'] as String? ?? '',
              name: item['name'] as String? ?? '',
            ),
          );
        }
      }
    }
    _devices = devices;
  }

  Future<void> _onDelete(_TrustedDevice device) async {
    final l10n = AppLocalizations.of(context);
    final displayName = device.name.isEmpty ? device.mac : device.name;
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: l10n.trustedRemoveTitle,
      message: l10n.trustedRemoveMessage(displayName),
      okText: l10n.commonRemove,
    );
    if (!confirmed || !mounted) return;
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'DeleteTrustedDevice',
      data: device.mac,
      store: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return HTDialog(
      title: l10n.trustedDevicesTitle,
      maxWidth: 500,
      maxHeight: 450,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.onSurfaceVariant),
              ),
              child: Material(
                color: scheme.surface,
                child: _buildList(),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildList() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (_devices.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          l10n.trustedNoDevices,
          textAlign: TextAlign.center,
          style: DialogStyles.bodyStyle,
        ),
      );
    }

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        final displayName = device.name.isEmpty ? device.mac : device.name;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: const Icon(Icons.bluetooth, color: Colors.blue),
          title: Text(
            displayName,
            style: DialogStyles.bodyStyle,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: device.name.isEmpty
              ? null
              : Text(
                  device.mac,
                  style: DialogStyles.bodyStyle.copyWith(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.commonRemove,
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _onDelete(device),
          ),
        );
      },
    );
  }
}
