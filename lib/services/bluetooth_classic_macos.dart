/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

/// Dart wrapper for native Bluetooth Classic (RFCOMM) on macOS
/// Uses IOBluetooth framework for Serial Port Profile connections
class BluetoothClassicMacOS {
  static const MethodChannel _channel = MethodChannel(
    'com.htcommander/bluetooth_classic',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.htcommander/bluetooth_classic_data',
  );

  static BluetoothClassicMacOS? _instance;
  static BluetoothClassicMacOS get instance {
    _instance ??= BluetoothClassicMacOS._();
    return _instance!;
  }

  BluetoothClassicMacOS._() {
    _setupEventChannel();
  }

  // Stream controllers for connection events and data
  final _connectionController =
      StreamController<BluetoothClassicEvent>.broadcast();
  final _dataControllers = <String, StreamController<Uint8List>>{};

  /// Stream of connection events (connected, disconnected)
  Stream<BluetoothClassicEvent> get connectionEvents =>
      _connectionController.stream;

  /// Check if this platform supports Bluetooth Classic via native code
  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  void _setupEventChannel() {
    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final eventType = event['event'] as String?;
          final address = event['address'] as String?;

          if (eventType == null || address == null) return;

          switch (eventType) {
            case 'connected':
              _connectionController.add(
                BluetoothClassicEvent(
                  type: BluetoothClassicEventType.connected,
                  address: address,
                ),
              );
              break;
            case 'disconnected':
              _connectionController.add(
                BluetoothClassicEvent(
                  type: BluetoothClassicEventType.disconnected,
                  address: address,
                ),
              );
              // Clean up data controller
              _dataControllers[address]?.close();
              _dataControllers.remove(address);
              break;
            case 'data':
              final data = event['data'];
              if (data is Uint8List) {
                _getOrCreateDataController(address).add(data);
              }
              break;
          }
        }
      },
      onError: (error) {
        debugPrint('BluetoothClassicMacOS: Event stream error: $error');
      },
    );
  }

  StreamController<Uint8List> _getOrCreateDataController(String address) {
    return _dataControllers.putIfAbsent(
      address,
      () => StreamController<Uint8List>.broadcast(),
    );
  }

  /// Get data stream for a specific device
  Stream<Uint8List> getDataStream(String address) {
    return _getOrCreateDataController(address).stream;
  }

  /// Check if Bluetooth is available
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      debugPrint('BluetoothClassicMacOS: Error checking availability: $e');
      return false;
    }
  }

  /// Get all paired Bluetooth devices
  Future<List<BluetoothClassicDevice>> getPairedDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('getPairedDevices');
      if (result == null) return [];

      return result.map((device) {
        final map = Map<String, dynamic>.from(device as Map);
        return BluetoothClassicDevice(
          name: map['name'] as String? ?? '',
          address: map['address'] as String? ?? '',
          isPaired: map['isPaired'] as bool? ?? false,
          isConnected: map['isConnected'] as bool? ?? false,
        );
      }).toList();
    } catch (e) {
      debugPrint('BluetoothClassicMacOS: Error getting paired devices: $e');
      return [];
    }
  }

  /// Find compatible radio devices from paired devices
  Future<List<BluetoothClassicDevice>> findCompatibleDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('findCompatibleDevices');
      if (result == null) return [];

      return result.map((device) {
        final map = Map<String, dynamic>.from(device as Map);
        return BluetoothClassicDevice(
          name: map['name'] as String? ?? '',
          address: map['address'] as String? ?? '',
          isPaired: map['isPaired'] as bool? ?? false,
          isConnected: map['isConnected'] as bool? ?? false,
        );
      }).toList();
    } catch (e) {
      debugPrint('BluetoothClassicMacOS: Error finding compatible devices: $e');
      return [];
    }
  }

  /// Get names of all paired devices
  Future<List<String>> getDeviceNames() async {
    try {
      final result = await _channel.invokeMethod<List>('getDeviceNames');
      return result?.cast<String>() ?? [];
    } catch (e) {
      debugPrint('BluetoothClassicMacOS: Error getting device names: $e');
      return [];
    }
  }

  /// Connect to a device by address
  Future<bool> connect(String address) async {
    try {
      final result = await _channel.invokeMethod<bool>('connect', {
        'address': address,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('BluetoothClassicMacOS: Error connecting to $address: $e');
      return false;
    }
  }

  /// Disconnect from a device
  Future<void> disconnect(String address) async {
    try {
      await _channel.invokeMethod<bool>('disconnect', {'address': address});
    } catch (e) {
      debugPrint(
        'BluetoothClassicMacOS: Error disconnecting from $address: $e',
      );
    }
  }

  /// Send data to a connected device
  Future<bool> send(String address, Uint8List data) async {
    try {
      final result = await _channel.invokeMethod<bool>('send', {
        'address': address,
        'data': data,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('BluetoothClassicMacOS: Error sending data: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _connectionController.close();
    for (final controller in _dataControllers.values) {
      controller.close();
    }
    _dataControllers.clear();
  }
}

/// Bluetooth Classic device info
class BluetoothClassicDevice {
  final String name;
  final String address;
  final bool isPaired;
  final bool isConnected;

  BluetoothClassicDevice({
    required this.name,
    required this.address,
    this.isPaired = false,
    this.isConnected = false,
  });

  @override
  String toString() =>
      'BluetoothClassicDevice($name, $address, paired: $isPaired, connected: $isConnected)';
}

/// Bluetooth Classic connection event types
enum BluetoothClassicEventType { connected, disconnected }

/// Bluetooth Classic connection event
class BluetoothClassicEvent {
  final BluetoothClassicEventType type;
  final String address;

  BluetoothClassicEvent({required this.type, required this.address});
}
