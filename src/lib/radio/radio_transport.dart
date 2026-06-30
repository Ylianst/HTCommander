/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:typed_data';

/// Radio transport state
enum TransportState { disconnected, connecting, connected, disconnecting }

/// Bluetooth transport type
enum BluetoothType { classic, ble }

/// Discovered device
class DiscoveredDevice {
  final String id;
  final String name;
  final BluetoothType type;
  final int rssi;
  final DateTime discoveredAt;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.type,
    this.rssi = 0,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  /// Check if this is a compatible radio device
  bool get isCompatibleRadio {
    return targetDeviceNames.any(
      (target) => name.toLowerCase().contains(target.toLowerCase()),
    );
  }

  /// List of known compatible radio device name patterns
  static const List<String> targetDeviceNames = [
    'UV-PRO',
    'WP-C1',
    'HT-CH1',
    'QUANSHENG',
    'VR-N7500',
    'VR-N',
    'SA-888S',
    'HG-UV98',
    'UV-98',
    'HAM-AIO',
    'VR-6600PRO',
    'TH-UV88',
    '3B01B', // Generic firmware device
    'E1WPR',
    'PNI-HP98WP',
  ];

  @override
  String toString() => 'DiscoveredDevice($name, $id, $type)';
}

/// Abstract transport interface for radio communication
/// Implementations provide either Bluetooth Classic or BLE connectivity
abstract class RadioTransport {
  /// Current connection state
  TransportState get state;

  /// Stream of connection state changes
  Stream<TransportState> get stateStream;

  /// Stream of received data
  Stream<Uint8List> get dataStream;

  /// The currently connected device (null if not connected)
  DiscoveredDevice? get connectedDevice;

  /// Start scanning for devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)});

  /// Stop scanning
  Future<void> stopScan();

  /// Stream of discovered devices during scanning
  Stream<DiscoveredDevice> get scanStream;

  /// Connect to a device
  Future<bool> connect(DiscoveredDevice device);

  /// Disconnect from the current device
  Future<void> disconnect();

  /// Send data to the connected device
  Future<bool> send(Uint8List data);

  /// Request MTU size (BLE only, returns actual MTU)
  Future<int> requestMtu(int mtu) async => 512;

  /// Dispose of resources
  Future<void> dispose();
}

/// Mock/stub implementation for testing
class MockRadioTransport implements RadioTransport {
  final _stateController = StreamController<TransportState>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _scanController = StreamController<DiscoveredDevice>.broadcast();

  TransportState _state = TransportState.disconnected;
  DiscoveredDevice? _connectedDevice;

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
    // Mock: emit some fake devices
    _scanController.add(
      DiscoveredDevice(
        id: 'mock-device-1',
        name: 'VR-N7500 (Mock)',
        type: BluetoothType.classic,
        rssi: -50,
      ),
    );
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> connect(DiscoveredDevice device) async {
    _state = TransportState.connecting;
    _stateController.add(_state);

    await Future<void>.delayed(const Duration(milliseconds: 500));

    _state = TransportState.connected;
    _connectedDevice = device;
    _stateController.add(_state);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _state = TransportState.disconnecting;
    _stateController.add(_state);

    await Future<void>.delayed(const Duration(milliseconds: 200));

    _state = TransportState.disconnected;
    _connectedDevice = null;
    _stateController.add(_state);
  }

  @override
  Future<bool> send(Uint8List data) async {
    if (_state != TransportState.connected) return false;
    return true;
  }

  @override
  Future<int> requestMtu(int mtu) async => 512;

  /// Simulate receiving data (for testing)
  void simulateReceive(Uint8List data) {
    _dataController.add(data);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _dataController.close();
    await _scanController.close();
  }
}

/// Factory for creating platform-appropriate transport
class RadioTransportFactory {
  /// Create a transport instance appropriate for the current platform
  /// On web, returns BLE transport; otherwise returns Classic transport
  static RadioTransport create({bool preferBle = false}) {
    // For now, return mock implementation
    // Real implementations will be platform-specific:
    // - Android/iOS/macOS/Windows: Bluetooth Classic preferred, BLE fallback
    // - Web: BLE only
    return MockRadioTransport();
  }
}
