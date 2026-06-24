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
import '../radio/radio_audio_stub.dart'
    if (dart.library.io) '../radio/radio_audio.dart';
import '../radio/radio_transport.dart';
import 'bluetooth_classic_macos.dart';
import 'data_broker.dart';
import 'data_broker_client.dart';

/// BLE GATT service UUIDs the radio control channel may expose.
///
/// On the web (Web Bluetooth API) the set of GATT services an application is
/// allowed to access must be declared up-front: after the user picks a device
/// in the browser's chooser, `discoverServices()` only returns services listed
/// here. These are passed as `webOptionalServices` on every scan so the BLE
/// control channel works in the browser. Ignored on native platforms.
final List<Guid> kRadioBleOptionalServices = [
  // Benshi / UV-PRO style radio control service (and its write/indicate
  // characteristics). This is the service the HT actually exposes; it must be
  // whitelisted here or Web Bluetooth rejects GATT access with
  // "NetworkError: Unsupported device.".
  Guid('00001100-d102-11e1-9b23-00025b00a5a5'), // Radio control service
  Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e'), // Nordic UART Service
  Guid('00001101-0000-1000-8000-00805f9b34fb'), // SPP-like service
];

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

  // Radio audio instances (macOS Bluetooth Classic only): deviceId -> RadioAudio
  final Map<int, RadioAudio> _radioAudioInstances = {};

  // For macOS Bluetooth Classic connections
  final Map<int, String> _classicConnections = {}; // deviceId -> macAddress

  // Starting device ID for radios
  static const int _startingDeviceId = 100;

  // Track if Bluetooth has been initialized
  static bool _bluetoothInitialized = false;

  /// Check if we should use Bluetooth Classic (macOS/Windows) or BLE
  static bool get _useBluetoothClassic =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows) && BluetoothClassicMacOS.isSupported;

  /// Check if Bluetooth is available on this platform
  /// On first call, waits for adapter to initialize
  static Future<bool> checkBluetooth() async {
    if (kIsWeb) {
      // Web Bluetooth API availability
      return true; // We'll handle errors when scanning
    }

    // On macOS, use native Bluetooth Classic
    if (_useBluetoothClassic) {
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

        // Small delay to let the adapter initialize
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      // Check adapter state, retry a few times if we get transient states
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final state = await FlutterBluePlus.adapterState.first.timeout(
            const Duration(seconds: 2),
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
        return finalState == BluetoothAdapterState.on;
      } catch (e) {
        return false;
      }
    } catch (e) {
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
    } catch (e) {
      // Ignore errors finding Classic devices
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
        withKeywords: kIsWeb ? const ['UV-PRO'] : const [],
        webOptionalServices: kRadioBleOptionalServices,
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
            if (kIsWeb) {
              // Web scan uses a browser chooser; once we have one compatible
              // device, return immediately to avoid waiting for scan timeout.
              return devices;
            }
          }
        }
      }
    } catch (e) {
      // Ignore BLE scan errors
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
          type: BluetoothType.ble,
          rssi: 0,
        );

        if (discovered.isCompatibleRadio) {
          seen.add(deviceId);
          devices.add(discovered);
        }
      }
    } catch (e) {
      // Ignore errors getting bonded devices
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
      final success = await transport.connect(device);

      if (success) {
        // Store the transport
        _connectedRadios[deviceId] = transport;

        // Create a Radio instance
        final radio = Radio(deviceId: deviceId, macAddress: macAddress);
        radio.updateFriendlyName(friendlyName);
        _radioInstances[deviceId] = radio;

        // Connect the radio to the transport (will start communication)
        await radio.connect(transport);

        // Create the audio handler for this radio. Audio is DISABLED by default
        // and is only started when a 'SetAudio' true command is dispatched
        // through the DataBroker (mirrors the C# behavior). RadioAudio itself
        // subscribes to 'SetAudio' and manages start/stop.
        final radioAudio = RadioAudio(
          radio: radio,
          deviceId: deviceId,
          macAddress: macAddress,
        );
        _radioAudioInstances[deviceId] = radioAudio;

        // If the user previously enabled audio, automatically enable the audio
        // channel for this newly connected radio (preference stored on device 0).
        final audioEnabledPref =
            _broker.getValue<bool>(0, 'AudioEnabled', false) ?? false;
        if (audioEnabledPref) {
          _broker.dispatch(
            deviceId: deviceId,
            name: 'SetAudio',
            data: true,
            store: false,
          );
        }

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
        // Create a Radio instance and attach the BLE transport so GAIA
        // initialization commands start immediately after link-up.
        final radio = Radio(deviceId: deviceId, macAddress: macAddress);
        radio.updateFriendlyName(friendlyName);
        _radioInstances[deviceId] = radio;
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
      return null;
    }
  }

  /// Disconnect a radio by device ID
  Future<void> disconnectRadio(int deviceId) async {
    // Dispose of the audio instance if it exists (macOS Classic only)
    final radioAudio = _radioAudioInstances.remove(deviceId);
    if (radioAudio != null) {
      await radioAudio.dispose();
    }

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

  /// Get the list of connected radio device IDs.
  ///
  /// A Bluetooth Classic radio is tracked in both [_connectedRadios] and
  /// [_classicConnections] under the same device ID, so the keys are merged
  /// into a set to avoid reporting the same radio twice.
  List<int> get connectedRadioIds =>
      <int>{..._connectedRadios.keys, ..._classicConnections.keys}.toList();

  /// Get a transport by device ID (BLE only)
  RadioTransport? getTransport(int deviceId) => _connectedRadios[deviceId];

  /// Publish the connected radios list to the DataBroker.
  ///
  /// Builds exactly one entry per device ID. A Bluetooth Classic radio that has
  /// finished connecting lives in both [_connectedRadios] (its transport) and
  /// [_classicConnections] (its MAC address) under the same device ID; the two
  /// maps are merged here so the radio is published only once. The
  /// [_classicConnections] map is otherwise only needed for radios that are
  /// still connecting and not yet present in [_connectedRadios].
  void _publishConnectedRadios() {
    final byDeviceId = <int, Map<String, dynamic>>{};

    // Add radios that have an active transport (BLE, or a connected Classic
    // radio). The transport carries the most up-to-date MAC / name / state.
    for (final entry in _connectedRadios.entries) {
      final transport = entry.value;
      final device = transport.connectedDevice;
      final classicMac = _classicConnections[entry.key];
      byDeviceId[entry.key] = {
        'DeviceId': entry.key,
        'MacAddress': device?.id ?? classicMac ?? '',
        'FriendlyName':
            device?.name ??
            DataBroker.getValue<String>(entry.key, 'FriendlyName', '') ??
            '',
        'State': transport.state.name,
      };
    }

    // Add Classic connections that do not yet have a transport (i.e. still
    // connecting). Anything already represented above is skipped so a radio is
    // never listed twice.
    for (final entry in _classicConnections.entries) {
      final deviceId = entry.key;
      if (byDeviceId.containsKey(deviceId)) continue;
      final macAddress = entry.value;
      final state =
          DataBroker.getValue<String>(deviceId, 'State', 'Disconnected') ??
          'Disconnected';
      final friendlyName =
          DataBroker.getValue<String>(deviceId, 'FriendlyName', macAddress) ??
          macAddress;
      byDeviceId[deviceId] = {
        'DeviceId': deviceId,
        'MacAddress': macAddress,
        'FriendlyName': friendlyName,
        'State': state,
      };
    }

    DataBroker.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: byDeviceId.values.toList(),
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

  /// Broker used to surface connection diagnostics in the Debug tab in addition
  /// to the console.
  final DataBrokerClient _broker = DataBrokerClient();

  TransportState _state = TransportState.disconnected;
  DiscoveredDevice? _connectedDevice;
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _altTxCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _rxPollTimer;
  Timer? _notifyRetryTimer;
  bool _rxPollInFlight = false;
  bool _webNotifyFallbackMode = false;
  final Map<String, List<int>> _lastPolledByChar = {};
  int _rxTraceCount = 0;
  int _txTraceCount = 0;
  bool _usingReferenceWebProfile = false;

  // Nordic UART Service UUIDs (commonly used by radio devices)
  static const String _nordicUartServiceUuid =
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _nordicUartTxCharUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _nordicUartRxCharUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  // Alternative SPP-like UUIDs that some radios use
  static const String _sppServiceUuid = '00001101-0000-1000-8000-00805f9b34fb';

  // Benshi / UV-PRO style radio control service. The HT exposes a "write"
  // characteristic (commands TO the radio = our TX) and an "indicate"
  // characteristic (notifications FROM the radio = our RX).
  static const String _btRadioServiceUuid =
      '00001100-d102-11e1-9b23-00025b00a5a5';
  static const String _btRadioWriteCharUuid =
      '00001101-d102-11e1-9b23-00025b00a5a5';
  static const String _btRadioAltWriteCharUuid =
      '00001103-d102-11e1-9b23-00025b00a5a5';
  static const String _btRadioIndicateCharUuid =
      '00001102-d102-11e1-9b23-00025b00a5a5';

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
      await FlutterBluePlus.startScan(
        timeout: timeout,
        withKeywords: kIsWeb ? const ['UV-PRO'] : const [],
        webOptionalServices: kRadioBleOptionalServices,
      );

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

  /// Logs an informational diagnostic both to the console and the Debug tab.
  void _logInfo(String msg) {
    debugPrint('BleRadioTransport: $msg');
    _broker.logInfo('[BLE] $msg');
  }

  /// Logs an error diagnostic both to the console and the Debug tab.
  void _logError(String msg) {
    debugPrint('BleRadioTransport: $msg');
    _broker.logError('[BLE] $msg');
  }

  void _emitRxData(List<int> data) {
    if (data.isEmpty) return;
    _dataController.add(Uint8List.fromList(data));
  }

  Future<void> _tryRearmWebNotify() async {
    final rx = _rxCharacteristic;
    if (!kIsWeb || rx == null || _state != TransportState.connected) return;
    try {
      await rx.setNotifyValue(true, timeout: 3);
      _webNotifyFallbackMode = false;
      _notifyRetryTimer?.cancel();
      _logInfo('Web notify recovery succeeded; using notifications/indications.');
    } catch (_) {
      // Keep retry timer running while connected.
    }
  }

  Future<void> _readAssistAfterTx() async {
    if (!kIsWeb || !_webNotifyFallbackMode || _state != TransportState.connected) {
      return;
    }

    final rx = _rxCharacteristic;
    if (rx == null || !rx.properties.read || _rxPollInFlight) return;
    _rxPollInFlight = true;
    try {
      final data = await rx.read();
      if (data.isEmpty) return;
      final key = rx.uuid.toString().toLowerCase();
      final last = _lastPolledByChar[key];
      if (last != null && _listEquals(last, data)) return;
      _lastPolledByChar[key] = List<int>.from(data);
      _emitRxData(data);
    } catch (_) {
      // Ignore; periodic polling continues.
    } finally {
      _rxPollInFlight = false;
    }
  }

  void _startRxPolling() {
    final candidates = <BluetoothCharacteristic>[];
    if (_rxCharacteristic != null && _rxCharacteristic!.properties.read) {
      candidates.add(_rxCharacteristic!);
    }
    if (_txCharacteristic != null && _txCharacteristic!.properties.read) {
      final txUuid = _txCharacteristic!.uuid.toString().toLowerCase();
      final exists = candidates.any(
        (c) => c.uuid.toString().toLowerCase() == txUuid,
      );
      if (!exists && !_usingReferenceWebProfile) {
        candidates.add(_txCharacteristic!);
      }
    }
    if (_altTxCharacteristic != null && _altTxCharacteristic!.properties.read) {
      final altUuid = _altTxCharacteristic!.uuid.toString().toLowerCase();
      final exists = candidates.any(
        (c) => c.uuid.toString().toLowerCase() == altUuid,
      );
      if (!exists && !_usingReferenceWebProfile) {
        candidates.add(_altTxCharacteristic!);
      }
    }

    if (candidates.isEmpty) {
      _logInfo(
        'No readable characteristic available; polling fallback unavailable.',
      );
      return;
    }

    final pollIntervalMs = kIsWeb
      ? (_usingReferenceWebProfile ? 80 : 120)
      : 200;
    _rxPollTimer?.cancel();
    _rxPollTimer = Timer.periodic(Duration(milliseconds: pollIntervalMs), (_) async {
      if (_rxPollInFlight || _state != TransportState.connected) return;
      _rxPollInFlight = true;
      try {
        for (final characteristic in candidates) {
          final data = await characteristic.read();
          if (data.isEmpty) continue;

          final key = characteristic.uuid.toString().toLowerCase();
          // Avoid dispatching duplicates when polling the same last value from
          // a given characteristic.
          final last = _lastPolledByChar[key];
          if (last != null && _listEquals(last, data)) continue;
          _lastPolledByChar[key] = List<int>.from(data);
          if (_rxTraceCount < 12) {
            _rxTraceCount++;
            _logInfo(
              'RX poll[$_rxTraceCount] from $key: ${data.length} byte(s): '
              '${_hexPreview(data)}',
            );
          }
          _emitRxData(data);
        }
      } catch (_) {
        // Ignore transient read failures while the connection stabilizes.
      } finally {
        _rxPollInFlight = false;
      }
    });
    final uuids = candidates
        .map((c) => c.uuid.toString().toLowerCase())
        .join(', ');
    _logInfo(
      'Started RX polling fallback at ${pollIntervalMs}ms interval on: $uuids',
    );
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _hexPreview(List<int> data, {int max = 24}) {
    if (data.isEmpty) return '';
    final take = data.length < max ? data.length : max;
    final sb = StringBuffer();
    for (int i = 0; i < take; i++) {
      if (i > 0) sb.write(' ');
      sb.write(data[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    if (data.length > max) sb.write(' ...');
    return sb.toString();
  }

  @override
  Future<bool> connect(DiscoveredDevice device) async {
    if (_state == TransportState.connected ||
        _state == TransportState.connecting) {
      return false;
    }

    _state = TransportState.connecting;
    _stateController.add(_state);

    _logInfo(
      'Connecting to "${device.name}" (id=${device.id}, type=${device.type.name})...',
    );

    try {
      _bleDevice = BluetoothDevice.fromId(device.id);

      // Listen for connection state changes
      _connectionSubscription = _bleDevice!.connectionState.listen((state) {
        _logInfo('Connection state: ${state.name}');
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      // Connect to the device
      _logInfo('Opening GATT connection (timeout 15s)...');
      await _bleDevice!.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
      _logInfo('GATT connected, discovering services...');

      // Discover services
      final services = await _bleDevice!.discoverServices();
      _logInfo('Discovered ${services.length} service(s).');

      // Find the UART service and characteristics
      bool foundService = false;
      bool foundBtRadioService = false;
      for (final service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();
        _logInfo(
          'Service $serviceUuid with ${service.characteristics.length} '
          'characteristic(s).',
        );

        if (serviceUuid == _nordicUartServiceUuid.toLowerCase() ||
            serviceUuid == _sppServiceUuid.toLowerCase() ||
            serviceUuid == _btRadioServiceUuid.toLowerCase()) {
          foundBtRadioService =
              serviceUuid == _btRadioServiceUuid.toLowerCase();
          for (final char in service.characteristics) {
            final charUuid = char.uuid.toString().toLowerCase();
            _logInfo(
              '  char $charUuid '
              '(write=${char.properties.write}, '
              'writeNoResp=${char.properties.writeWithoutResponse}, '
              'read=${char.properties.read}, '
              'notify=${char.properties.notify}, '
              'indicate=${char.properties.indicate})',
            );

            if (charUuid == _nordicUartTxCharUuid.toLowerCase() ||
                charUuid == _btRadioWriteCharUuid.toLowerCase()) {
              _txCharacteristic = char;
            } else if (charUuid == _btRadioAltWriteCharUuid.toLowerCase()) {
              _altTxCharacteristic = char;
            } else if (charUuid == _nordicUartRxCharUuid.toLowerCase() ||
                charUuid == _btRadioIndicateCharUuid.toLowerCase()) {
              _rxCharacteristic = char;
            } else if (char.properties.write ||
                char.properties.writeWithoutResponse) {
              // Fallback: use any writable characteristic for TX
              if (_txCharacteristic == null) {
                _txCharacteristic = char;
              } else {
                _altTxCharacteristic ??= char;
              }
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
        _logInfo(
          'No Nordic UART / SPP service found; scanning all services for '
          'usable characteristics...',
        );
        for (final service in services) {
          for (final char in service.characteristics) {
            if (_txCharacteristic == null &&
                (char.properties.write ||
                    char.properties.writeWithoutResponse)) {
              if (_txCharacteristic == null) {
                _txCharacteristic = char;
              } else {
                _altTxCharacteristic ??= char;
              }
            }
            if (_rxCharacteristic == null &&
                (char.properties.notify || char.properties.indicate)) {
              _rxCharacteristic = char;
            }
          }
        }
      }

      if (_txCharacteristic == null) {
        _logError(
          'No writable characteristic found; cannot use this device as a '
          'radio transport.',
        );
        await disconnect();
        return false;
      }
      _logInfo(
        'Using TX ${_txCharacteristic!.uuid.toString().toLowerCase()}'
        '${_altTxCharacteristic != null ? ', ALT-TX ${_altTxCharacteristic!.uuid.toString().toLowerCase()}' : ''}'
        '${_rxCharacteristic != null ? ', RX ${_rxCharacteristic!.uuid.toString().toLowerCase()}' : ' (no RX/notify characteristic)'}.',
      );

      _usingReferenceWebProfile =
          kIsWeb &&
          foundBtRadioService &&
          _txCharacteristic!.uuid.toString().toLowerCase() ==
              _btRadioWriteCharUuid.toLowerCase() &&
          _rxCharacteristic != null &&
          _rxCharacteristic!.uuid.toString().toLowerCase() ==
              _btRadioIndicateCharUuid.toLowerCase();
      if (_usingReferenceWebProfile) {
        _logInfo(
          'Web reference profile active: TX=$_btRadioWriteCharUuid '
          'RX=$_btRadioIndicateCharUuid',
        );
      }

      // Set up notifications for RX characteristic
      if (_rxCharacteristic != null) {
        // Subscribe first so values are not missed if they arrive immediately
        // after the CCCD change.
        _notifySubscription = _rxCharacteristic!.onValueReceived.listen((data) {
          _emitRxData(data);
        });

        try {
          await _rxCharacteristic!.setNotifyValue(
            true,
            timeout: kIsWeb ? 3 : 15,
          );
          _webNotifyFallbackMode = false;
          _logInfo('RX notifications/indications enabled.');
        } catch (e) {
          if (kIsWeb) {
            // Web Bluetooth can time out on setNotifyValue for some
            // indicate-only radios even though the link is otherwise usable.
            // Keep the connection up and fall back to periodic reads.
            _logInfo(
              'RX notify setup timed out on web; continuing with '
              'read-poll fallback. Error: $e',
            );
            _webNotifyFallbackMode = true;
            _startRxPolling();
            _notifyRetryTimer?.cancel();
            _notifyRetryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
              _tryRearmWebNotify();
            });
          } else {
            rethrow;
          }
        }
      }

      _connectedDevice = device;
      _state = TransportState.connected;
      _stateController.add(_state);

      _logInfo('Connected to ${device.name}');
      return true;
    } catch (e, stack) {
      // Surface the error type as well as the message: on the web, GATT
      // failures such as "NetworkError: Unsupported device" come back as
      // opaque strings, so the runtime type helps narrow down the cause.
      _logError(
        'Error connecting to "${device.name}" (id=${device.id}): '
        '$e (type: ${e.runtimeType})',
      );
      debugPrint('BleRadioTransport: connect stack trace:\n$stack');
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
    _altTxCharacteristic = null;
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

    _rxPollTimer?.cancel();
    _rxPollTimer = null;
    _notifyRetryTimer?.cancel();
    _notifyRetryTimer = null;
    _lastPolledByChar.clear();
    _rxTraceCount = 0;
    _txTraceCount = 0;
    _usingReferenceWebProfile = false;
    _webNotifyFallbackMode = false;

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
    _altTxCharacteristic = null;
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
      final primary = _txCharacteristic!;
      if (kIsWeb && _txTraceCount < 20) {
        _txTraceCount++;
        _logInfo(
          'TX[$_txTraceCount] -> ${primary.uuid.toString().toLowerCase()} '
          '${data.length} byte(s): ${_hexPreview(data)}',
        );
      }
      await primary.write(
        data.toList(),
        withoutResponse: primary.properties.writeWithoutResponse,
      );
      await _readAssistAfterTx();

      // Web BLE radios may expose two writable characteristics where only one
      // actually processes control commands. Mirror writes to improve
      // compatibility while probing the active endpoint.
      if (kIsWeb && !_usingReferenceWebProfile && _altTxCharacteristic != null) {
        final alt = _altTxCharacteristic!;
        try {
          if (_txTraceCount < 20) {
            _txTraceCount++;
            _logInfo(
              'TX[$_txTraceCount] mirror -> ${alt.uuid.toString().toLowerCase()} '
              '${data.length} byte(s): ${_hexPreview(data)}',
            );
          }
          await alt.write(
            data.toList(),
            withoutResponse: alt.properties.writeWithoutResponse,
          );
        } catch (_) {
          // Ignore bootstrap mirror failures; primary write already succeeded.
        }
      }
      return true;
    } catch (e1) {
      final fallback = _altTxCharacteristic;
      if (fallback != null) {
        try {
          _logInfo(
            'Primary TX write failed (${_txCharacteristic!.uuid.toString().toLowerCase()}); '
            'retrying on ALT-TX ${fallback.uuid.toString().toLowerCase()}.',
          );
          await fallback.write(
            data.toList(),
            withoutResponse: fallback.properties.writeWithoutResponse,
          );
          await _readAssistAfterTx();
          final oldPrimary = _txCharacteristic;
          _txCharacteristic = fallback;
          _altTxCharacteristic = oldPrimary;
          return true;
        } catch (e2) {
          debugPrint(
            'BleRadioTransport: Error sending data (primary: $e1, alt: $e2)',
          );
          return false;
        }
      }
      debugPrint('BleRadioTransport: Error sending data: $e1');
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
