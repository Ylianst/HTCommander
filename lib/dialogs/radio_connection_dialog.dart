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

  CompatibleDevice({required this.name, required this.mac});
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
        .map((d) => CompatibleDevice(name: d.name, mac: d.id))
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

  // Selected MAC addresses
  final Set<String> _selectedMacs = {};

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

  bool get _hasDisconnectedSelected {
    for (final mac in _selectedMacs) {
      final status = _getRadioStatus(mac);
      if (status == 'Disconnected' ||
          status == 'UnableToConnect' ||
          status == 'AccessDenied') {
        return true;
      }
    }
    return false;
  }

  bool get _hasConnectedSelected {
    for (final mac in _selectedMacs) {
      final status = _getRadioStatus(mac);
      if (status == 'Connected' || status == 'Connecting') {
        return true;
      }
    }
    return false;
  }

  void _onConnect() async {
    final bluetoothService = BluetoothService();

    for (final mac in _selectedMacs) {
      final status = _getRadioStatus(mac);
      if (status == 'Disconnected' ||
          status == 'UnableToConnect' ||
          status == 'AccessDenied') {
        // Find the friendly name from the devices list
        String friendlyName = '';
        for (final device in widget.devices) {
          if (device.mac.toUpperCase() == mac.toUpperCase()) {
            friendlyName = device.name;
            break;
          }
        }

        // Connect using BluetoothService
        await bluetoothService.connectToRadio(mac, friendlyName);
      }
    }
  }

  void _onDisconnect() async {
    final bluetoothService = BluetoothService();

    for (final mac in _selectedMacs) {
      final status = _getRadioStatus(mac);
      if (status == 'Connected' || status == 'Connecting') {
        // Disconnect using BluetoothService
        await bluetoothService.disconnectRadioByMac(mac);
      }
    }
  }

  void _onRename() {
    if (_selectedMacs.length != 1) return;

    final mac = _selectedMacs.first;
    final macKey = mac.toUpperCase();

    // Get the stored friendly names dictionary
    final friendlyNames = DataBroker.getValue<Map<String, dynamic>>(
      0,
      'DeviceFriendlyName',
    );

    // Get the original Bluetooth name from the stored DeviceBluetoothName dictionary
    final bluetoothNames = DataBroker.getValue<Map<String, dynamic>>(
      0,
      'DeviceBluetoothName',
    );
    String defaultFriendlyName = '';
    if (bluetoothNames != null && bluetoothNames.containsKey(macKey)) {
      defaultFriendlyName = bluetoothNames[macKey] as String? ?? '';
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

  void _onDoubleTap(String mac) {
    final status = _getRadioStatus(mac);
    if (status == 'Disconnected' ||
        status == 'UnableToConnect' ||
        status == 'AccessDenied') {
      _selectedMacs
        ..clear()
        ..add(mac);
      _onConnect();
    } else if (status == 'Connected' || status == 'Connecting') {
      _selectedMacs
        ..clear()
        ..add(mac);
      _onDisconnect();
    }
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
                child: widget.devices.isEmpty
                    ? const Center(
                        child: Text(
                          'No compatible radios found.\nMake sure your radio is powered on and Bluetooth is enabled.',
                          textAlign: TextAlign.center,
                          style: DialogStyles.bodyStyle,
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.devices.length,
                        itemBuilder: (context, index) {
                          final device = widget.devices[index];
                          final status = _getRadioStatus(device.mac);
                          final isSelected = _selectedMacs.contains(
                            device.mac.toUpperCase(),
                          );

                          final displayName = device.name.isEmpty
                              ? device.mac
                              : '${device.name} (${device.mac})';

                          return InkWell(
                            onDoubleTap: () => _onDoubleTap(device.mac),
                            onTap: () {
                              setState(() {
                                final macUpper = device.mac.toUpperCase();
                                if (isSelected) {
                                  _selectedMacs.remove(macUpper);
                                } else {
                                  _selectedMacs.add(macUpper);
                                }
                              });
                            },
                            child: ListTile(
                              selected: isSelected,
                              selectedTileColor: Colors.blue.withAlpha(50),
                              title: Text(
                                displayName,
                                style: DialogStyles.bodyStyle,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _getStatusColor(status),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      status,
                                      style: DialogStyles.bodyStyle,
                                    ),
                                  ),
                                ],
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
              ElevatedButton(
                onPressed: _hasDisconnectedSelected ? _onConnect : null,
                child: const Text('Connect'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _hasConnectedSelected ? _onDisconnect : null,
                child: const Text('Disconnect'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectedMacs.length == 1 ? _onRename : null,
                child: const Text('Rename'),
              ),
              const SizedBox(width: 16),
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
