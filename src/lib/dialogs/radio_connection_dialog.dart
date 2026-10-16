/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dialog_utils.dart';
import '../l10n/app_localizations.dart';
import '../echolink/echolink_client.dart' show echoLinkDeviceId;
import '../allstar/allstar_client.dart' show allStarDeviceId;
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

  /// True for the internet-only EchoLink pseudo-radio (device 200). It connects
  /// by going online with the EchoLink directory rather than over Bluetooth.
  final bool isEchoLink;

  /// True for the internet-only AllStarLink pseudo-radio (device 202). It
  /// connects by going online (opening its IAX2 transport) rather than over
  /// Bluetooth.
  final bool isAllStar;

  CompatibleDevice({
    required this.name,
    required this.mac,
    this.bluetoothName = '',
    this.isEchoLink = false,
    this.isAllStar = false,
  });
}

/// Outcome of a background radio scan run by [RadioConnectionDialog].
enum RadioScanOutcome { completed, bluetoothUnavailable }

/// Scans for radios while the connection dialog is open. Must call [onFound]
/// once per radio as it is discovered and complete when the scan is over.
/// Throws if the scan fails.
typedef RadioScanner =
    Future<RadioScanOutcome> Function(
      void Function(CompatibleDevice device) onFound,
    );

enum _ScanState { idle, scanning, done, bluetoothUnavailable, error }

/// Dialog for connecting to Bluetooth radios
class RadioConnectionDialog extends StatefulWidget {
  /// Devices listed as soon as the dialog opens (e.g. EchoLink / AllStarLink).
  final List<CompatibleDevice> devices;

  /// Optional background scan; radios it finds are added to the list live.
  final RadioScanner? scanner;

  const RadioConnectionDialog({super.key, required this.devices, this.scanner});

  /// Shows the radio connection dialog. When [scanner] is given the dialog
  /// opens immediately and radios are added as the scan discovers them.
  static Future<void> show(
    BuildContext context,
    List<CompatibleDevice> devices, {
    RadioScanner? scanner,
  }) {
    return showDialog(
      context: context,
      builder: (context) =>
          RadioConnectionDialog(devices: devices, scanner: scanner),
    );
  }

  /// Shows guidance after all attempts to connect to a paired radio fail.
  static Future<void> showCannotConnect(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => HTDialog(
        title: l10n.radioCannotConnectTitle,
        maxWidth: 600,
        maxHeight: 620,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.radioCannotConnectBody, style: DialogStyles.bodyStyle),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/CantConnect.png',
                  fit: BoxFit.contain,
                  semanticLabel: l10n.radioCannotConnectImageDescription,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: DialogStyles.primaryButtonStyle(context),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
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

  // Current device-200 (EchoLink) state, used when an EchoLink row is shown.
  String _echoLinkState = 'Disconnected';

  // Current device-202 (AllStarLink) state, used when an AllStar row is shown.
  String _allStarState = 'Disconnected';

  // Devices listed in the dialog; grows as the background scan finds radios.
  late final List<CompatibleDevice> _devices = List<CompatibleDevice>.of(
    widget.devices,
  );

  _ScanState _scanState = _ScanState.idle;
  String _scanError = '';

  @override
  void initState() {
    super.initState();

    if (widget.scanner != null) {
      _scanState = _ScanState.scanning;
      _runScan(widget.scanner!);
    }
    // Load initial connected radios state
    _loadConnectedRadiosState();

    // Load initial EchoLink state (device 200).
    _echoLinkState =
        _broker.getValue<String>(echoLinkDeviceId, 'State') ?? 'Disconnected';
    // Load initial AllStarLink state (device 202).
    _allStarState =
        _broker.getValue<String>(allStarDeviceId, 'State') ?? 'Disconnected';

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

  Future<void> _runScan(RadioScanner scanner) async {
    _ScanState result;
    try {
      final outcome = await scanner(_onDeviceFound);
      result = outcome == RadioScanOutcome.bluetoothUnavailable
          ? _ScanState.bluetoothUnavailable
          : _ScanState.done;
    } catch (e) {
      _scanError = e.toString();
      result = _ScanState.error;
    }
    if (!mounted) return;
    setState(() => _scanState = result);
  }

  void _onDeviceFound(CompatibleDevice device) {
    if (!mounted) return;
    final mac = device.mac.toUpperCase();
    if (_devices.any((d) => d.mac.toUpperCase() == mac)) return;
    setState(() => _devices.add(device));
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
      if (deviceId == echoLinkDeviceId) {
        setState(() {
          _echoLinkState = data;
        });
        return;
      }
      if (deviceId == allStarDeviceId) {
        setState(() {
          _allStarState = data;
        });
        return;
      }
      final macAddress = _deviceIdToMac[deviceId];
      if (macAddress != null) {
        setState(() {
          _connectedRadioStates[macAddress] = data;
        });
      }
    }
  }

  /// Maps the EchoLink device-200 `State` onto the connection-dialog status
  /// vocabulary. EchoLink connects by "going online" with the directory, so any
  /// online/QSO state is shown as connected.
  String _echoLinkStatus() {
    switch (_echoLinkState) {
      case 'Online':
      case 'Connecting':
      case 'Connected':
        return 'Connected';
      default:
        return 'Disconnected';
    }
  }

  String _getRadioStatus(String macAddress) {
    return _connectedRadioStates[macAddress.toUpperCase()] ?? 'Disconnected';
  }

  /// Status for any dialog row, handling the EchoLink pseudo-radio specially.
  String _statusForDevice(CompatibleDevice device) {
    if (device.isEchoLink) return _echoLinkStatus();
    if (device.isAllStar) return _allStarStatus();
    return _getRadioStatus(device.mac);
  }

  /// Maps the AllStarLink device-202 `State` onto the dialog status vocabulary.
  String _allStarStatus() {
    switch (_allStarState) {
      case 'Online':
      case 'Connecting':
      case 'Connected':
        return 'Connected';
      default:
        return 'Disconnected';
    }
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
    for (final device in _devices) {
      if (device.mac.toUpperCase() == mac.toUpperCase()) {
        return device.name;
      }
    }
    return '';
  }

  Future<void> _connectMac(String mac) async {
    final bluetoothService = BluetoothService();
    final deviceId = await bluetoothService.connectToRadio(
      mac,
      _friendlyNameForMac(mac),
    );
    if (deviceId == null &&
        mounted &&
        defaultTargetPlatform == TargetPlatform.macOS) {
      await RadioConnectionDialog.showCannotConnect(context);
    }
  }

  void _disconnectMac(String mac) async {
    final bluetoothService = BluetoothService();
    await bluetoothService.disconnectRadioByMac(mac);
  }

  /// Connect EchoLink by going online with the directory server (device 200).
  void _connectEchoLink() {
    _broker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkGoOnline',
      data: null,
      store: false,
    );
  }

  /// Disconnect EchoLink by going offline (device 200).
  void _disconnectEchoLink() {
    _broker.dispatch(
      deviceId: echoLinkDeviceId,
      name: 'EchoLinkGoOffline',
      data: null,
      store: false,
    );
  }

  /// Connect AllStarLink by going online (opening its transport, device 202).
  void _connectAllStar() {
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'AllStarGoOnline',
      data: null,
      store: false,
    );
  }

  /// Disconnect AllStarLink by going offline (device 202).
  void _disconnectAllStar() {
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'AllStarGoOffline',
      data: null,
      store: false,
    );
  }

  void _toggleDevice(CompatibleDevice device) {
    final status = _statusForDevice(device);
    if (device.isEchoLink) {
      if (_isConnectedOrConnecting(status)) {
        _disconnectEchoLink();
      } else if (_isConnectable(status)) {
        _connectEchoLink();
      }
      return;
    }
    if (device.isAllStar) {
      if (_isConnectedOrConnecting(status)) {
        _disconnectAllStar();
      } else if (_isConnectable(status)) {
        _connectAllStar();
      }
      return;
    }
    if (_isConnectedOrConnecting(status)) {
      _disconnectMac(device.mac);
    } else if (_isConnectable(status)) {
      _connectMac(device.mac);
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
    for (final device in _devices) {
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
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(l10n.radioRenameTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.radioRenamePrompt),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: placeholder.isEmpty ? mac : placeholder,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.radioRenameHint,
                style: DialogStyles.bodyStyle.copyWith(
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(l10n.commonOk),
            ),
          ],
        );
      },
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
      for (final device in _devices) {
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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Internet pseudo-radios stay at the top and radios follow in discovery
    // order, so newly found radios are only ever appended at the bottom and
    // never shift an entry the user is about to click.
    final sortedDevices = <CompatibleDevice>[
      ..._devices.where((d) => d.isEchoLink || d.isAllStar),
      ..._devices.where((d) => !d.isEchoLink && !d.isAllStar),
    ];

    return HTDialog(
      title: l10n.radioConnectionTitle,
      maxWidth: 500,
      maxHeight: 450,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Radio list
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
              ),
              child: Material(
                color: scheme.surface,
                child: sortedDevices.isEmpty
                    ? Center(
                        child: _scanState == _ScanState.scanning
                            ? _buildScanningIndicator(l10n)
                            : Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  _emptyListMessage(l10n),
                                  textAlign: TextAlign.center,
                                  style: DialogStyles.bodyStyle,
                                ),
                              ),
                      )
                    : ListView.builder(
                        itemCount: sortedDevices.length,
                        itemBuilder: (context, index) {
                          final device = sortedDevices[index];
                          final status = _statusForDevice(device);
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
                              tooltip: connected
                                  ? l10n.commonDisconnect
                                  : l10n.commonConnect,
                              icon: Icon(
                                device.isEchoLink
                                    ? (connected
                                          ? Icons.public
                                          : Icons.public_off)
                                    : device.isAllStar
                                    ? Icons.cell_tower
                                    : (connected
                                          ? Icons.bluetooth_connected
                                          : Icons.bluetooth_disabled),
                                color: _getStatusColor(status),
                              ),
                              onPressed: (connected || connectable)
                                  ? () => _toggleDevice(device)
                                  : null,
                            ),
                            title: Text(
                              displayName,
                              style: DialogStyles.bodyStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: (device.isEchoLink || device.isAllStar)
                                ? Text(
                                    l10n.radioConnectionInternet,
                                    style: DialogStyles.bodyStyle.copyWith(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : device.name.isEmpty
                                ? null
                                : Text(
                                    device.mac,
                                    style: DialogStyles.bodyStyle.copyWith(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!device.isEchoLink && !device.isAllStar)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: l10n.commonRename,
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _onRename(device.mac),
                                  ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: connected
                                      ? l10n.commonDisconnect
                                      : l10n.commonConnect,
                                  icon: Icon(
                                    connected ? Icons.link_off : Icons.link,
                                    color: connected
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                  onPressed: (connected || connectable)
                                      ? () => _toggleDevice(device)
                                      : null,
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
          // Scan status and buttons
          Row(
            children: [
              Expanded(
                child: sortedDevices.isEmpty
                    ? const SizedBox.shrink()
                    : _buildScanStatus(l10n, scheme),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: DialogStyles.primaryButtonStyle(context),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Message shown in place of the list when no devices are available.
  String _emptyListMessage(AppLocalizations l10n) {
    switch (_scanState) {
      case _ScanState.bluetoothUnavailable:
        return l10n.connectBluetoothOffBody;
      case _ScanState.error:
        return l10n.connectScanError(_scanError);
      default:
        return l10n.radioConnectionEmpty;
    }
  }

  Widget _buildScanningIndicator(AppLocalizations l10n) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            l10n.statusScanningForRadios,
            style: DialogStyles.bodyStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Scan progress / result shown next to the Close button while the list
  /// already has entries.
  Widget _buildScanStatus(AppLocalizations l10n, ColorScheme scheme) {
    switch (_scanState) {
      case _ScanState.scanning:
        return Align(
          alignment: Alignment.centerLeft,
          child: _buildScanningIndicator(l10n),
        );
      case _ScanState.bluetoothUnavailable:
        return _buildScanMessage(
          Icons.bluetooth_disabled,
          l10n.statusBluetoothNotAvailable,
          scheme.error,
        );
      case _ScanState.error:
        return Tooltip(
          message: l10n.connectScanError(_scanError),
          child: _buildScanMessage(
            Icons.error_outline,
            l10n.statusErrorScanning,
            scheme.error,
          ),
        );
      case _ScanState.done:
        if (_devices.any((d) => !d.isEchoLink && !d.isAllStar)) {
          return const SizedBox.shrink();
        }
        return _buildScanMessage(
          Icons.info_outline,
          l10n.statusNoCompatibleRadios,
          scheme.onSurfaceVariant,
        );
      case _ScanState.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildScanMessage(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: DialogStyles.bodyStyle.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
