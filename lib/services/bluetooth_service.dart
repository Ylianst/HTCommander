/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../radio/bluetooth_classic_transport.dart';
import '../radio/radio.dart';
import '../radio/radio_transport.dart';
import 'bluetooth_classic_macos.dart';
import 'data_broker.dart';
import 'data_broker_client.dart';

/// Service for managing Bluetooth radio connections
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  final DataBrokerClient _broker = DataBrokerClient();

  // Connected radios: deviceId -> RadioTransport (BLE or Classic)
  final Map<int, RadioTransport> _connectedRadios = {};

  // Radio instances: deviceId -> Radio
  final Map<int, Radio> _radioInstances = {};

  // For macOS Bluetooth Classic connections
  final Map<int, String> _classicConnections = {}; // deviceId -> macAddress

  // Starting device ID for radios
  static const int _startingDeviceId = 100;

  // Track if Bluetooth has been initialized
  static bool _bluetoothInitialized = false;

  /// Check if we should use Bluetooth Classic (macOS) or BLE
  static bool get _useBluetoothClassic =>
      !kIsWeb && Platform.isMacOS && BluetoothClassicMacOS.isSupported;

  /// Check if Bluetooth is available on this platform
  /// On first call, waits for adapter to initialize
  static Future<bool> checkBluetooth() async {
    if (kIsWeb) {
      // Web Bluetooth API availability
      return true; // We'll handle errors when scanning
    }

    // On macOS, use native Bluetooth Classic
    if (_useBluetoothClassic) {
      debugPrint('BluetoothService: Using Bluetooth Classic on macOS');
      return await BluetoothClassicMacOS.instance.isAvailable();
    }

    // On other platforms, use BLE via flutter_blue_plus
    try {
      // Check if Bluetooth adapter is available
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;

      // On first call, give the adapter time to initialize
      // The CBCentralManager reports transient states before settling
      if (!_bluetoothInitialized) {
        _bluetoothInitialized = true;
        debugPrint(
          'BluetoothService: First Bluetooth check, initializing adapter...',
        );

        // Small delay to let the adapter initialize
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      // Check adapter state, retry a few times if we get transient states
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final state = await FlutterBluePlus.adapterState.first.timeout(
            const Duration(seconds: 2),
          );
          debugPrint(
            'BluetoothService: Adapter state (attempt ${attempt + 1}): $state',
          );

          if (state == BluetoothAdapterState.on) {
            return true;
          } else if (state == BluetoothAdapterState.off ||
              state == BluetoothAdapterState.unauthorized) {
            // Definitive states - Bluetooth exists but is off or not permitted
            return false;
          }

          // Unknown/unavailable/turningOn/turningOff - wait and retry
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          debugPrint(
            'BluetoothService: State check timeout (attempt ${attempt + 1})',
          );
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
        }
      }

      // After retries, do a final check
      try {
        final finalState = await FlutterBluePlus.adapterState.first.timeout(
          const Duration(seconds: 1),
        );
        debugPrint('BluetoothService: Final adapter state: $finalState');
        return finalState == BluetoothAdapterState.on;
      } catch (e) {
        return false;
      }
    } catch (e) {
      debugPrint('BluetoothService: Error checking Bluetooth: $e');
      return false;
    }
  }

  /// Check if Bluetooth adapter is turned on
  static Future<bool> isBluetoothOn() async {
    if (_useBluetoothClassic) {
      return await BluetoothClassicMacOS.instance.isAvailable();
    }

    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(milliseconds: 500),
      );
      return state == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }

  /// Find compatible radio devices
  /// Returns a list of discovered devices that match known radio patterns
  Future<List<DiscoveredDevice>> findCompatibleDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // On macOS, use Bluetooth Classic to find paired radio devices
    if (_useBluetoothClassic) {
      return await _findCompatibleDevicesMacOS();
    }

    // On other platforms, use BLE scanning
    return await _findCompatibleDevicesBLE(timeout: timeout);
  }

  /// Find compatible devices using Bluetooth Classic (macOS)
  Future<List<DiscoveredDevice>> _findCompatibleDevicesMacOS() async {
    final devices = <DiscoveredDevice>[];

    try {
      final classicDevices = await BluetoothClassicMacOS.instance
          .findCompatibleDevices();

      for (final device in classicDevices) {
        devices.add(
          DiscoveredDevice(
            id: device.address,
            name: device.name,
            type: BluetoothType.classic,
            rssi: 0,
          ),
        );
      }

      debugPrint(
        'BluetoothService: Found ${devices.length} compatible devices via Bluetooth Classic',
      );
    } catch (e) {
      debugPrint('BluetoothService: Error finding Classic devices: $e');
    }

    return devices;
  }

  /// Find compatible devices using BLE scanning
  Future<List<DiscoveredDevice>> _findCompatibleDevicesBLE({
    required Duration timeout,
  }) async {
    final devices = <DiscoveredDevice>[];
    final seen = <String>{};

    try {
      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      // Listen for results during the scan
      await for (final results in FlutterBluePlus.scanResults.timeout(
        timeout,
        onTimeout: (sink) => sink.close(),
      )) {
        for (final result in results) {
          final deviceId = result.device.remoteId.str;
          if (seen.contains(deviceId)) continue;

          final name = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : result.advertisementData.advName;

          if (name.isEmpty) continue;

          // Check if this is a compatible device
          final device = DiscoveredDevice(
            id: deviceId,
            name: name,
            type: BluetoothType.ble,
            rssi: result.rssi,
          );

          if (device.isCompatibleRadio) {
            seen.add(deviceId);
            devices.add(device);
          }
        }
      }
    } catch (e) {
      debugPrint('BluetoothService: Error during BLE scan: $e');
    } finally {
      await FlutterBluePlus.stopScan();
    }

    // Also check bonded/paired devices
    try {
      final bonded = await FlutterBluePlus.bondedDevices;
      for (final device in bonded) {
        final deviceId = device.remoteId.str;
        if (seen.contains(deviceId)) continue;

        final name = device.platformName;
        if (name.isEmpty) continue;

        final discovered = DiscoveredDevice(
          id: deviceId,
          name: name,
          type: BluetoothType.classic,
          rssi: 0,
        );

        if (discovered.isCompatibleRadio) {
          seen.add(deviceId);
          devices.add(discovered);
        }
      }
    } catch (e) {
      debugPrint('BluetoothService: Error getting bonded devices: $e');
    }

    return devices;
  }

  /// Get the next available device ID for a new radio
  int _getNextDeviceId() {
    int deviceId = _startingDeviceId;
    while (_connectedRadios.containsKey(deviceId) ||
        _classicConnections.containsKey(deviceId)) {
      deviceId++;
    }
    return deviceId;
  }

  /// Connect to a radio by MAC address
  /// Returns the device ID if successful, or null if failed
  Future<int?> connectToRadio(String macAddress, String friendlyName) async {
    // On macOS, use Bluetooth Classic
    if (_useBluetoothClassic) {
      return await _connectToRadioClassic(macAddress, friendlyName);
    }

    // On other platforms, use BLE
    return await _connectToRadioBLE(macAddress, friendlyName);
  }

  /// Connect using Bluetooth Classic (macOS)
  Future<int?> _connectToRadioClassic(
    String macAddress,
    String friendlyName,
  ) async {
    final macUpper = macAddress.toUpperCase();

    // Check if already connected
    for (final entry in _classicConnections.entries) {
      if (entry.value.toUpperCase() == macUpper) {
        return entry.key;
      }
    }

    try {
      final deviceId = _getNextDeviceId();

      // Dispatch state change
      _broker.dispatch(
        deviceId: deviceId,
        name: 'State',
        data: 'Connecting',
        store: true,
      );

      // Dispatch FriendlyName early so it's available during connection
      _broker.dispatch(
        deviceId: deviceId,
        name: 'FriendlyName',
        data: friendlyName,
        store: true,
      );

      // Store the connection info (before connecting for UI feedback)
      _classicConnections[deviceId] = macAddress;
      _publishConnectedRadios();

      // Create a BluetoothClassicTransport
      final transport = BluetoothClassicTransport();
      final device = DiscoveredDevice(
        id: macAddress,
        name: friendlyName.isNotEmpty ? friendlyName : macAddress,
        type: BluetoothType.classic,
      );

      // Connect using the transport
      debugPrint(
        'BluetoothService: Connecting via Bluetooth Classic to $macAddress',
      );
      final success = await transport.connect(device);

      if (success) {
        debugPrint('BluetoothService: Bluetooth Classic connection successful');

        // Store the transport
        _connectedRadios[deviceId] = transport;

        // Create a Radio instance
        final radio = Radio(deviceId: deviceId, macAddress: macAddress);
        radio.updateFriendlyName(friendlyName);
        _radioInstances[deviceId] = radio;

        // Connect the radio to the transport (will start communication)
        await radio.connect(transport);

        _broker.dispatch(
          deviceId: deviceId,
          name: 'MacAddress',
          data: macAddress,
          store: true,
        );
        _broker.dispatch(
          deviceId: deviceId,
          name: 'FriendlyName',
          data: friendlyName,
          store: true,
        );
        _publishConnectedRadios();
        return deviceId;
      } else {
        debugPrint('BluetoothService: Bluetooth Classic connection failed');
        _classicConnections.remove(deviceId);
        await transport.dispose();
        _broker.dispatch(
          deviceId: deviceId,
          name: 'State',
          data: 'UnableToConnect',
          store: true,
        );
        _publishConnectedRadios();
        return null;
      }
    } catch (e) {
      debugPrint('BluetoothService: Error connecting via Classic: $e');
      return null;
    }
  }

  /// Connect using BLE
  Future<int?> _connectToRadioBLE(
    String macAddress,
    String friendlyName,
  ) async {
    // Check if already connected
    for (final entry in _connectedRadios.entries) {
      if (entry.value.connectedDevice?.id.toUpperCase() ==
          macAddress.toUpperCase()) {
        return entry.key;
      }
    }

    try {
      final deviceId = _getNextDeviceId();
      final transport = BleRadioTransport();

      // Create a DiscoveredDevice for the transport
      final discovered = DiscoveredDevice(
        id: macAddress,
        name: friendlyName.isNotEmpty ? friendlyName : macAddress,
        type: BluetoothType.ble,
      );

      // Store the transport
      _connectedRadios[deviceId] = transport;

      // Dispatch FriendlyName early so it's available during connection
      _broker.dispatch(
        deviceId: deviceId,
        name: 'FriendlyName',
        data: friendlyName,
        store: true,
      );

      // Update the connected radios list
      _publishConnectedRadios();

      // Dispatch state change
      _broker.dispatch(
        deviceId: deviceId,
        name: 'State',
        data: 'Connecting',
        store: true,
      );

      // Connect
      final success = await transport.connect(discovered);

      if (success) {
        _broker.dispatch(
          deviceId: deviceId,
          name: 'State',
          data: 'Connected',
          store: true,
        );
        _publishConnectedRadios();
        return deviceId;
      } else {
        // Connection failed
        _connectedRadios.remove(deviceId);
        _broker.dispatch(
          deviceId: deviceId,
          name: 'State',
          data: 'UnableToConnect',
          store: true,
        );
        _publishConnectedRadios();
        await transport.dispose();
        return null;
      }
    } catch (e) {
      debugPrint('BluetoothService: Error connecting via BLE: $e');
      return null;
    }
  }

  /// Disconnect a radio by device ID
  Future<void> disconnectRadio(int deviceId) async {
    // Dispose of the Radio instance if it exists
    final radio = _radioInstances.remove(deviceId);
    radio?.dispose();

    // Check for Classic connection (macOS)
    if (_classicConnections.containsKey(deviceId)) {
      _classicConnections.remove(deviceId);
      // Transport handles the actual disconnection
      final transport = _connectedRadios.remove(deviceId);
      if (transport != null) {
        await transport.disconnect();
        await transport.dispose();
      }
      _broker.dispatch(
        deviceId: deviceId,
        name: 'State',
        data: 'Disconnected',
        store: true,
      );
      _publishConnectedRadios();
      return;
    }

    // Check for BLE connection
    final transport = _connectedRadios.remove(deviceId);
    if (transport != null) {
      await transport.disconnect();
      await transport.dispose();
      _broker.dispatch(
        deviceId: deviceId,
        name: 'State',
        data: 'Disconnected',
        store: true,
      );
      _publishConnectedRadios();
    }
  }

  /// Disconnect a radio by MAC address
  Future<void> disconnectRadioByMac(String macAddress) async {
    final macUpper = macAddress.toUpperCase();
    int? deviceIdToRemove;

    // Check Classic connections (macOS)
    for (final entry in _classicConnections.entries) {
      if (entry.value.toUpperCase() == macUpper) {
        deviceIdToRemove = entry.key;
        break;
      }
    }

    // Check BLE connections
    if (deviceIdToRemove == null) {
      for (final entry in _connectedRadios.entries) {
        if (entry.value.connectedDevice?.id.toUpperCase() == macUpper) {
          deviceIdToRemove = entry.key;
          break;
        }
      }
    }

    if (deviceIdToRemove != null) {
      await disconnectRadio(deviceIdToRemove);
    }
  }

  /// Get the list of connected radio device IDs
  List<int> get connectedRadioIds => [
    ..._connectedRadios.keys,
    ..._classicConnections.keys,
  ];

  /// Get a transport by device ID (BLE only)
  RadioTransport? getTransport(int deviceId) => _connectedRadios[deviceId];

  /// Publish the connected radios list to the DataBroker
  void _publishConnectedRadios() {
    final radioList = <Map<String, dynamic>>[];

    // Add BLE connections
    for (final entry in _connectedRadios.entries) {
      final transport = entry.value;
      final device = transport.connectedDevice;
      radioList.add({
        'DeviceId': entry.key,
        'MacAddress': device?.id ?? '',
        'FriendlyName': device?.name ?? '',
        'State': transport.state.name,
      });
    }

    // Add Classic connections (macOS)
    for (final entry in _classicConnections.entries) {
      final deviceId = entry.key;
      final macAddress = entry.value;
      final state =
          DataBroker.getValue<String>(deviceId, 'State', 'Disconnected') ??
          'Disconnected';
      final friendlyName =
          DataBroker.getValue<String>(deviceId, 'FriendlyName', macAddress) ??
          macAddress;
      radioList.add({
        'DeviceId': deviceId,
        'MacAddress': macAddress,
        'FriendlyName': friendlyName,
        'State': state,
      });
    }

    DataBroker.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: radioList,
      store: true,
    );
  }

  /// Dispose all resources
  Future<void> dispose() async {
    // Dispose Radio instances
    for (final radio in _radioInstances.values) {
      radio.dispose();
    }
    _radioInstances.clear();

    // Dispose BLE transports
    for (final transport in _connectedRadios.values) {
      await transport.disconnect();
      await transport.dispose();
    }
    _connectedRadios.clear();

    // Clear Classic connections (transports already disposed above)
    _classicConnections.clear();

    _broker.dispose();
  }
}

/// BLE implementation of RadioTransport using flutter_blue_plus
class BleRadioTransport implements RadioTransport {
  final _stateController = StreamController<TransportState>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _scanController = StreamController<DiscoveredDevice>.broadcast();

  TransportState _state = TransportState.disconnected;
  DiscoveredDevice? _connectedDevice;
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  // Nordic UART Service UUIDs (commonly used by radio devices)
  static const String _nordicUartServiceUuid =
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _nordicUartTxCharUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _nordicUartRxCharUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  // Alternative SPP-like UUIDs that some radios use
  static const String _sppServiceUuid = '00001101-0000-1000-8000-00805f9b34fb';

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateStream => _stateController.stream;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<DiscoveredDevice> get scanStream => _scanController.stream;

  @override
  DiscoveredDevice? get connectedDevice => _connectedDevice;

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await FlutterBluePlus.startScan(timeout: timeout);

      FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final name = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : result.advertisementData.advName;

          if (name.isEmpty) continue;

          final device = DiscoveredDevice(
            id: result.device.remoteId.str,
            name: name,
            type: BluetoothType.ble,
            rssi: result.rssi,
          );

          _scanController.add(device);
        }
      });
    } catch (e) {
      debugPrint('BleRadioTransport: Error starting scan: $e');
    }
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<bool> connect(DiscoveredDevice device) async {
    if (_state == TransportState.connected ||
        _state == TransportState.connecting) {
      return false;
    }

    _state = TransportState.connecting;
    _stateController.add(_state);

    try {
      _bleDevice = BluetoothDevice.fromId(device.id);

      // Listen for connection state changes
      _connectionSubscription = _bleDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      // Connect to the device
      await _bleDevice!.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      // Discover services
      final services = await _bleDevice!.discoverServices();

      // Find the UART service and characteristics
      bool foundService = false;
      for (final service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();

        if (serviceUuid == _nordicUartServiceUuid.toLowerCase() ||
            serviceUuid == _sppServiceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            final charUuid = char.uuid.toString().toLowerCase();

            if (charUuid == _nordicUartTxCharUuid.toLowerCase()) {
              _txCharacteristic = char;
            } else if (charUuid == _nordicUartRxCharUuid.toLowerCase()) {
              _rxCharacteristic = char;
            } else if (char.properties.write ||
                char.properties.writeWithoutResponse) {
              // Fallback: use any writable characteristic for TX
              _txCharacteristic ??= char;
            } else if (char.properties.notify || char.properties.indicate) {
              // Fallback: use any notifiable characteristic for RX
              _rxCharacteristic ??= char;
            }
          }
          foundService = true;
          break;
        }
      }

      // If no UART service found, try to find any suitable characteristics
      if (!foundService) {
        for (final service in services) {
          for (final char in service.characteristics) {
            if (_txCharacteristic == null &&
                (char.properties.write ||
                    char.properties.writeWithoutResponse)) {
              _txCharacteristic = char;
            }
            if (_rxCharacteristic == null &&
                (char.properties.notify || char.properties.indicate)) {
              _rxCharacteristic = char;
            }
          }
        }
      }

      if (_txCharacteristic == null) {
        debugPrint('BleRadioTransport: No writable characteristic found');
        await disconnect();
        return false;
      }

      // Set up notifications for RX characteristic
      if (_rxCharacteristic != null) {
        await _rxCharacteristic!.setNotifyValue(true);
        _notifySubscription = _rxCharacteristic!.onValueReceived.listen((data) {
          _dataController.add(Uint8List.fromList(data));
        });
      }

      _connectedDevice = device;
      _state = TransportState.connected;
      _stateController.add(_state);

      debugPrint('BleRadioTransport: Connected to ${device.name}');
      return true;
    } catch (e) {
      debugPrint('BleRadioTransport: Error connecting: $e');
      _state = TransportState.disconnected;
      _stateController.add(_state);
      return false;
    }
  }

  void _handleDisconnect() {
    if (_state == TransportState.disconnected) return;

    _state = TransportState.disconnected;
    _connectedDevice = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
    _stateController.add(_state);
  }

  @override
  Future<void> disconnect() async {
    if (_state == TransportState.disconnected) return;

    _state = TransportState.disconnecting;
    _stateController.add(_state);

    await _notifySubscription?.cancel();
    _notifySubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    try {
      await _bleDevice?.disconnect();
    } catch (e) {
      debugPrint('BleRadioTransport: Error disconnecting: $e');
    }

    _bleDevice = null;
    _connectedDevice = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;

    _state = TransportState.disconnected;
    _stateController.add(_state);
  }

  @override
  Future<bool> send(Uint8List data) async {
    if (_state != TransportState.connected || _txCharacteristic == null) {
      return false;
    }

    try {
      await _txCharacteristic!.write(
        data.toList(),
        withoutResponse: _txCharacteristic!.properties.writeWithoutResponse,
      );
      return true;
    } catch (e) {
      debugPrint('BleRadioTransport: Error sending data: $e');
      return false;
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    if (_bleDevice == null) return 20;

    try {
      return await _bleDevice!.requestMtu(mtu);
    } catch (e) {
      debugPrint('BleRadioTransport: Error requesting MTU: $e');
      return 20;
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _dataController.close();
    await _scanController.close();
  }
}
