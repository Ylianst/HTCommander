/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'dialog_utils.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../radio/radio_transport.dart';

/// A device that can be displayed in the radio connection dialog
class CompatibleDevice {
  String name;
  final String mac;

  /// The original Bluetooth (discovered) name of the device, used as the
  /// default name placeholder when renaming.
  final String bluetoothName;

  CompatibleDevice({
    required this.name,
    required this.mac,
    this.bluetoothName = '',
  });
}

/// Dialog for connecting to Bluetooth radios
class RadioConnectionDialog extends StatefulWidget {
  final List<CompatibleDevice> devices;

  const RadioConnectionDialog({super.key, required this.devices});

  /// Shows the radio connection dialog
  static Future<void> show(
    BuildContext context,
    List<CompatibleDevice> devices,
  ) {
    return showDialog(
      context: context,
      builder: (context) => RadioConnectionDialog(devices: devices),
    );
  }

  /// Creates a list of CompatibleDevice from DiscoveredDevice list
  static List<CompatibleDevice> fromDiscoveredDevices(
    List<DiscoveredDevice> discovered,
  ) {
    return discovered
        .where((d) => d.isCompatibleRadio)
        .map(
          (d) =>
              CompatibleDevice(name: d.name, mac: d.id, bluetoothName: d.name),
        )
        .toList();
  }

  @override
  State<RadioConnectionDialog> createState() => _RadioConnectionDialogState();
}

class _RadioConnectionDialogState extends State<RadioConnectionDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  // Track connected radios state: MAC address -> connection state
  final Map<String, String> _connectedRadioStates = {};

  // Track deviceId -> MAC address mapping for state updates
  final Map<int, String> _deviceIdToMac = {};

  @override
  void initState() {
    super.initState();

    // Load initial connected radios state
    _loadConnectedRadiosState();

    // Subscribe to connected radios updates
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );

    // Subscribe to State changes for all devices
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'State',
      callback: _onRadioStateChanged,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _loadConnectedRadiosState() {
    _connectedRadioStates.clear();
    _deviceIdToMac.clear();

    final connectedRadios = DataBroker.getValue<List<dynamic>>(
      1,
      'ConnectedRadios',
    );
    if (connectedRadios != null) {
      for (final radio in connectedRadios) {
        if (radio is Map) {
          final deviceId = radio['DeviceId'] as int?;
          final macAddress = radio['MacAddress'] as String?;
          if (deviceId != null && macAddress != null) {
            final state =
                _broker.getValue<String>(deviceId, 'State') ??
                (radio['State'] as String?) ??
                'Disconnected';
            _connectedRadioStates[macAddress.toUpperCase()] = state;
            _deviceIdToMac[deviceId] = macAddress.toUpperCase();
          }
        }
      }
    }
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    setState(() {
      _loadConnectedRadiosState();
    });
  }

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    if (data is String) {
      final macAddress = _deviceIdToMac[deviceId];
      if (macAddress != null) {
        setState(() {
          _connectedRadioStates[macAddress] = data;
        });
      }
    }
  }

  String _getRadioStatus(String macAddress) {
    return _connectedRadioStates[macAddress.toUpperCase()] ?? 'Disconnected';
  }

  bool _isConnectable(String status) {
    return status == 'Disconnected' ||
        status == 'UnableToConnect' ||
        status == 'AccessDenied';
  }

  bool _isConnectedOrConnecting(String status) {
    return status == 'Connected' || status == 'Connecting';
  }

  String _friendlyNameForMac(String mac) {
    for (final device in widget.devices) {
      if (device.mac.toUpperCase() == mac.toUpperCase()) {
        return device.name;
      }
    }
    return '';
  }

  void _connectMac(String mac) async {
    final bluetoothService = BluetoothService();
    await bluetoothService.connectToRadio(mac, _friendlyNameForMac(mac));
  }

  void _disconnectMac(String mac) async {
    final bluetoothService = BluetoothService();
    await bluetoothService.disconnectRadioByMac(mac);
  }

  void _toggleMac(String mac) {
    final status = _getRadioStatus(mac);
    if (_isConnectedOrConnecting(status)) {
      _disconnectMac(mac);
    } else if (_isConnectable(status)) {
      _connectMac(mac);
    }
  }

  void _onRename(String mac) {
    final macKey = mac.toUpperCase();

    // Get the stored friendly names dictionary
    final friendlyNames = DataBroker.getValue<Map<String, dynamic>>(
      0,
      'DeviceFriendlyName',
    );

    // Use the original discovered Bluetooth name as the default name.
    String defaultFriendlyName = '';
    for (final device in widget.devices) {
      if (device.mac.toUpperCase() == macKey) {
        defaultFriendlyName = device.bluetoothName;
        break;
      }
    }

    // Find the current custom name (if any) from the stored dictionary
    String currentCustomName = '';
    if (friendlyNames != null && friendlyNames.containsKey(macKey)) {
      currentCustomName = friendlyNames[macKey] as String? ?? '';
    }

    // Show rename dialog
    _showRenameDialog(
      currentName: currentCustomName,
      placeholder: defaultFriendlyName,
      mac: mac,
    );
  }

  Future<void> _showRenameDialog({
    required String currentName,
    required String placeholder,
    required String mac,
  }) async {
    final controller = TextEditingController(text: currentName);
    final macKey = mac.toUpperCase();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DialogStyles.backgroundColor,
        title: const Text('Rename Radio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a custom name for this radio:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: placeholder.isEmpty ? mac : placeholder,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Leave blank to use the default name',
              style: DialogStyles.bodyStyle.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result != null) {
      final newName = result.trim();

      // Get or create the friendly names dictionary
      var friendlyNames =
          DataBroker.getValue<Map<String, dynamic>>(0, 'DeviceFriendlyName') ??
          {};
      friendlyNames = Map<String, dynamic>.from(friendlyNames);

      // Store the mapping (use uppercase MAC as key for consistency)
      if (newName.isEmpty) {
        // If blank, remove any custom name (will default to discovered name)
        friendlyNames.remove(macKey);
      } else {
        friendlyNames[macKey] = newName;
      }

      // Save to DataBroker under device id 0
      DataBroker.dispatch(
        deviceId: 0,
        name: 'DeviceFriendlyName',
        data: friendlyNames,
        store: true,
      );

      // Determine the final name to use
      final finalName = newName.isEmpty
          ? (placeholder.isNotEmpty ? placeholder : mac)
          : newName;

      // Update the device's name in memory
      for (final device in widget.devices) {
        if (device.mac.toUpperCase() == macKey) {
          device.name = finalName;
          break;
        }
      }

      // If this radio is currently connected, update its friendly name via the Radio handler
      final connectedDeviceId = _getConnectedDeviceIdByMac(mac);
      if (connectedDeviceId != null) {
        _broker.dispatch(
          deviceId: connectedDeviceId,
          name: 'UpdateFriendlyName',
          data: finalName,
          store: false,
        );
      }

      setState(() {});
    }
  }

  int? _getConnectedDeviceIdByMac(String macAddress) {
    final macUpper = macAddress.toUpperCase();
    for (final entry in _deviceIdToMac.entries) {
      if (entry.value.toUpperCase() == macUpper) {
        return entry.key;
      }
    }
    return null;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Connected':
        return Colors.green;
      case 'Connecting':
        return Colors.orange;
      case 'Disconnected':
        return Colors.grey;
      case 'UnableToConnect':
      case 'AccessDenied':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedDevices = List<CompatibleDevice>.from(widget.devices)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return HTDialog(
      title: 'Radio Connection',
      maxWidth: 500,
      maxHeight: 450,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Radio list
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: Material(
                color: Colors.white,
                child: sortedDevices.isEmpty
                    ? const Center(
                        child: Text(
                          'No compatible radios found.\nMake sure your radio is powered on and Bluetooth is enabled.',
                          textAlign: TextAlign.center,
                          style: DialogStyles.bodyStyle,
                        ),
                      )
                    : ListView.builder(
                        itemCount: sortedDevices.length,
                        itemBuilder: (context, index) {
                          final device = sortedDevices[index];
                          final status = _getRadioStatus(device.mac);
                          final connectable = _isConnectable(status);
                          final connected = _isConnectedOrConnecting(status);

                          final displayName = device.name.isEmpty
                              ? device.mac
                              : device.name;

                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: connected ? 'Disconnect' : 'Connect',
                              icon: Icon(
                                connected
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth_disabled,
                                color: _getStatusColor(status),
                              ),
                              onPressed: (connected || connectable)
                                  ? () => _toggleMac(device.mac)
                                  : null,
                            ),
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
                                      color: Colors.grey[600],
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: connected ? 'Disconnect' : 'Connect',
                                  icon: Icon(
                                    connected ? Icons.link_off : Icons.link,
                                    color: connected
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                  onPressed: connected
                                      ? () => _disconnectMac(device.mac)
                                      : (connectable
                                            ? () => _connectMac(device.mac)
                                            : null),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Rename',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _onRename(device.mac),
                                ),
                              ],
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
