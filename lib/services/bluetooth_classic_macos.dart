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
  static const EventChannel _audioEventChannel = EventChannel(
    'com.htcommander/bluetooth_classic_audio',
  );

  static BluetoothClassicMacOS? _instance;
  static BluetoothClassicMacOS get instance {
    _instance ??= BluetoothClassicMacOS._();
    return _instance!;
  }

  BluetoothClassicMacOS._() {
    _setupEventChannel();
    _setupAudioEventChannel();
  }

  // Stream controllers for connection events and data
  final _connectionController =
      StreamController<BluetoothClassicEvent>.broadcast();
  final _dataControllers = <String, StreamController<Uint8List>>{};

  // Stream controllers for the audio (BS AOC vendor) RFCOMM channel
  final _audioConnectionController =
      StreamController<BluetoothClassicEvent>.broadcast();
  final _audioDataControllers = <String, StreamController<Uint8List>>{};

  /// Stream of connection events (connected, disconnected)
  Stream<BluetoothClassicEvent> get connectionEvents =>
      _connectionController.stream;

  /// Stream of audio channel connection events (connected, disconnected)
  Stream<BluetoothClassicEvent> get audioConnectionEvents =>
      _audioConnectionController.stream;

  /// Check if this platform supports Bluetooth Classic via native code
  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  void _setupEventChannel() {
    _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final eventType = event['event'] as String?;
          final rawAddress = event['address'] as String?;

          if (eventType == null || rawAddress == null) return;

          // Normalize address to uppercase with colons
          final address = _normalizeAddress(rawAddress);
          debugPrint(
            'BluetoothClassicMacOS: Event: $eventType, address: $address',
          );

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
                debugPrint(
                  'BluetoothClassicMacOS: Received ${data.length} bytes from $address',
                );
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

  void _setupAudioEventChannel() {
    _audioEventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final eventType = event['event'] as String?;
          final rawAddress = event['address'] as String?;

          if (eventType == null || rawAddress == null) return;

          final address = _normalizeAddress(rawAddress);

          switch (eventType) {
            case 'connected':
              _audioConnectionController.add(
                BluetoothClassicEvent(
                  type: BluetoothClassicEventType.connected,
                  address: address,
                ),
              );
              break;
            case 'disconnected':
              _audioConnectionController.add(
                BluetoothClassicEvent(
                  type: BluetoothClassicEventType.disconnected,
                  address: address,
                ),
              );
              _audioDataControllers[address]?.close();
              _audioDataControllers.remove(address);
              break;
            case 'data':
              final data = event['data'];
              if (data is Uint8List) {
                _getOrCreateAudioDataController(address).add(data);
              }
              break;
          }
        }
      },
      onError: (error) {
        debugPrint('BluetoothClassicMacOS: Audio event stream error: $error');
      },
    );
  }

  /// Normalize address to uppercase with colons
  static String _normalizeAddress(String address) {
    return address.toUpperCase().replaceAll('-', ':');
  }

  StreamController<Uint8List> _getOrCreateDataController(String address) {
    final normalizedAddress = _normalizeAddress(address);
    return _dataControllers.putIfAbsent(
      normalizedAddress,
      () => StreamController<Uint8List>.broadcast(),
    );
  }

  StreamController<Uint8List> _getOrCreateAudioDataController(String address) {
    final normalizedAddress = _normalizeAddress(address);
    return _audioDataControllers.putIfAbsent(
      normalizedAddress,
      () => StreamController<Uint8List>.broadcast(),
    );
  }

  /// Get data stream for a specific device
  Stream<Uint8List> getDataStream(String address) {
    final normalizedAddress = _normalizeAddress(address);
    debugPrint('BluetoothClassicMacOS: getDataStream for $normalizedAddress');
    return _getOrCreateDataController(normalizedAddress).stream;
  }

  /// Get the audio (BS AOC vendor RFCOMM) data stream for a specific device
  Stream<Uint8List> getAudioDataStream(String address) {
    final normalizedAddress = _normalizeAddress(address);
    return _getOrCreateAudioDataController(normalizedAddress).stream;
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

  /// Connect to the audio RFCOMM channel of a device. Audio is carried by the
  /// vendor "BS AOC" service (resolved natively by UUID), NOT Generic Audio
  /// (0x1203). This is a second, independent channel alongside the SPP data
  /// channel. See docs/radio-bluetooth.md.
  Future<bool> connectAudio(String address) async {
    try {
      final result = await _channel.invokeMethod<bool>('connectAudio', {
        'address': address,
      });
      return result ?? false;
    } catch (e) {
      debugPrint(
        'BluetoothClassicMacOS: Error connecting audio to $address: $e',
      );
      return false;
    }
  }

  /// Disconnect the audio RFCOMM channel of a device.
  Future<void> disconnectAudio(String address) async {
    try {
      await _channel.invokeMethod<bool>('disconnectAudio', {
        'address': address,
      });
    } catch (e) {
      debugPrint(
        'BluetoothClassicMacOS: Error disconnecting audio from $address: $e',
      );
    }
  }

  /// Send data on the audio RFCOMM channel of a device.
  Future<bool> sendAudio(String address, Uint8List data) async {
    try {
      final result = await _channel.invokeMethod<bool>('sendAudio', {
        'address': address,
        'data': data,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('BluetoothClassicMacOS: Error sending audio data: $e');
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
    _audioConnectionController.close();
    for (final controller in _audioDataControllers.values) {
      controller.close();
    }
    _audioDataControllers.clear();
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
