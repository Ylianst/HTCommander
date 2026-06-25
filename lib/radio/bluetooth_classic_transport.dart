/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:typed_data';

import '../services/bluetooth_classic_macos.dart';
import '../services/data_broker_client.dart';
import 'radio_transport.dart';

/// RadioTransport implementation using Bluetooth Classic (RFCOMM)
/// Uses BluetoothClassicMacOS for native macOS Bluetooth connections
class BluetoothClassicTransport implements RadioTransport {
  final _stateController = StreamController<TransportState>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();
  final _scanController = StreamController<DiscoveredDevice>.broadcast();
  final DataBrokerClient _broker = DataBrokerClient();

  TransportState _state = TransportState.disconnected;
  DiscoveredDevice? _connectedDevice;
  StreamSubscription<Uint8List>? _dataSubscription;
  StreamSubscription<BluetoothClassicEvent>? _connectionSubscription;
  int _rxLogCount = 0;
  int _txLogCount = 0;

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

  void _logInfo(String msg) {
    _broker.logInfo('[BT-Classic] $msg');
  }

  void _logError(String msg) {
    _broker.logError('[BT-Classic] $msg');
  }

  String _hexPreview(Uint8List data, {int max = 24}) {
    if (data.isEmpty) return '';
    final take = data.length < max ? data.length : max;
    final parts = <String>[];
    for (int i = 0; i < take; i++) {
      parts.add(data[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return data.length > max ? '${parts.join(' ')} ...' : parts.join(' ');
  }

  BluetoothClassicTransport() {
    _logInfo('Transport created; listening for native Classic connection events');
    // Listen for connection events from native layer
    _connectionSubscription = BluetoothClassicMacOS.instance.connectionEvents
        .listen((event) {
          final eventAddress = event.address.toUpperCase().replaceAll('-', ':');
          final connectedAddress = _connectedDevice?.id
              .toUpperCase()
              .replaceAll('-', ':');

          _logInfo(
            'Native event ${event.type.name} for $eventAddress '
            '(transport device: ${connectedAddress ?? 'none'})',
          );

          if (connectedAddress == eventAddress) {
            if (event.type == BluetoothClassicEventType.disconnected) {
              _logInfo('Native disconnect matched active transport $eventAddress');
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
      _logInfo('Connect ignored for ${device.id}; state=${_state.name}');
      return false;
    }

    _logInfo(
      'Connecting to ${device.name} (${device.id}) over Bluetooth Classic',
    );
    _updateState(TransportState.connecting);

    try {
      final success = await BluetoothClassicMacOS.instance.connect(device.id);
      _logInfo('Native connect returned $success for ${device.id}');

      if (success) {
        _connectedDevice = device;
        _rxLogCount = 0;
        _txLogCount = 0;
        _updateState(TransportState.connected);
        _logInfo('Connected transport for ${device.id}; subscribing to RFCOMM RX stream');

        // Start listening for data
        _dataSubscription = BluetoothClassicMacOS.instance
            .getDataStream(device.id)
            .listen((data) {
              if (_rxLogCount < 60) {
                _rxLogCount++;
                _logInfo(
                  'RX chunk[$_rxLogCount] ${data.length} byte(s) from ${device.id}: '
                  '${_hexPreview(data)}',
                );
              }
              _dataController.add(data);
            }, onError: (error) {
              _logError('RX stream error for ${device.id}: $error');
            });

        return true;
      } else {
        _logError('Native Classic connect failed for ${device.id}');
        _updateState(TransportState.disconnected);
        return false;
      }
    } catch (e) {
      _logError('Classic connect threw for ${device.id}: $e');
      _updateState(TransportState.disconnected);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    _logInfo('Disconnecting ${_connectedDevice!.id}');

    _updateState(TransportState.disconnecting);

    try {
      await BluetoothClassicMacOS.instance.disconnect(_connectedDevice!.id);
    } catch (e) {
      _logError('Disconnect error for ${_connectedDevice!.id}: $e');
    }

    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connectedDevice = null;
    _updateState(TransportState.disconnected);
  }

  @override
  Future<bool> send(Uint8List data) async {
    if (_state != TransportState.connected || _connectedDevice == null) {
      _logError(
        'Send rejected: state=${_state.name}, device=${_connectedDevice?.id ?? 'none'}, '
        'len=${data.length}',
      );
      return false;
    }

    try {
      if (_txLogCount < 60) {
        _txLogCount++;
        _logInfo(
          'TX chunk[$_txLogCount] ${data.length} byte(s) to ${_connectedDevice!.id}: '
          '${_hexPreview(data)}',
        );
      }
      final result = await BluetoothClassicMacOS.instance.send(
        _connectedDevice!.id,
        data,
      );
      _logInfo('Native send result for ${_connectedDevice!.id}: $result');
      return result;
    } catch (e) {
      _logError('Send threw for ${_connectedDevice!.id}: $e');
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
      _logInfo('Transport state ${_state.name} -> ${newState.name}');
      _state = newState;
      _stateController.add(newState);
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _connectionSubscription?.cancel();
    _broker.dispose();
    await _stateController.close();
    await _dataController.close();
    await _scanController.close();
  }
}
