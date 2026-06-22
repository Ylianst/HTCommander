/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:typed_data';

import '../services/bluetooth_classic_macos.dart';
import 'radio_transport.dart';

/// RadioTransport implementation using Bluetooth Classic (RFCOMM)
/// Uses BluetoothClassicMacOS for native macOS Bluetooth connections
class BluetoothClassicTransport implements RadioTransport {
  final _stateController = StreamController<TransportState>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _scanController = StreamController<DiscoveredDevice>.broadcast();

  TransportState _state = TransportState.disconnected;
  DiscoveredDevice? _connectedDevice;
  StreamSubscription<Uint8List>? _dataSubscription;
  StreamSubscription<BluetoothClassicEvent>? _connectionSubscription;

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

  BluetoothClassicTransport() {
    // Listen for connection events from native layer
    _connectionSubscription = BluetoothClassicMacOS.instance.connectionEvents
        .listen((event) {
          final eventAddress = event.address.toUpperCase().replaceAll('-', ':');
          final connectedAddress = _connectedDevice?.id
              .toUpperCase()
              .replaceAll('-', ':');

          if (connectedAddress == eventAddress) {
            if (event.type == BluetoothClassicEventType.disconnected) {
              _updateState(TransportState.disconnected);
              _connectedDevice = null;
              _dataSubscription?.cancel();
              _dataSubscription = null;
            }
          }
        });
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // For Bluetooth Classic, we return paired/bonded devices
    // No actual scanning is needed
    try {
      final devices = await BluetoothClassicMacOS.instance
          .findCompatibleDevices();
      for (final device in devices) {
        _scanController.add(
          DiscoveredDevice(
            id: device.address,
            name: device.name,
            type: BluetoothType.classic,
            rssi: 0,
          ),
        );
      }
    } catch (e) {
      // Ignore errors enumerating paired devices.
    }
  }

  @override
  Future<void> stopScan() async {
    // No-op for Bluetooth Classic - we don't do active scanning
  }

  @override
  Future<bool> connect(DiscoveredDevice device) async {
    if (_state == TransportState.connected ||
        _state == TransportState.connecting) {
      return false;
    }

    _updateState(TransportState.connecting);

    try {
      final success = await BluetoothClassicMacOS.instance.connect(device.id);

      if (success) {
        _connectedDevice = device;
        _updateState(TransportState.connected);

        // Start listening for data
        _dataSubscription = BluetoothClassicMacOS.instance
            .getDataStream(device.id)
            .listen((data) {
              _dataController.add(data);
            }, onError: (error) {});

        return true;
      } else {
        _updateState(TransportState.disconnected);
        return false;
      }
    } catch (e) {
      _updateState(TransportState.disconnected);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    _updateState(TransportState.disconnecting);

    try {
      await BluetoothClassicMacOS.instance.disconnect(_connectedDevice!.id);
    } catch (e) {
      // Ignore disconnect errors.
    }

    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connectedDevice = null;
    _updateState(TransportState.disconnected);
  }

  @override
  Future<bool> send(Uint8List data) async {
    if (_state != TransportState.connected || _connectedDevice == null) {
      return false;
    }

    try {
      final result = await BluetoothClassicMacOS.instance.send(
        _connectedDevice!.id,
        data,
      );
      return result;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    // Bluetooth Classic RFCOMM doesn't have MTU negotiation like BLE
    // Return a reasonable default for serial communication
    return 512;
  }

  void _updateState(TransportState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _connectionSubscription?.cancel();
    await _stateController.close();
    await _dataController.close();
    await _scanController.close();
  }
}
