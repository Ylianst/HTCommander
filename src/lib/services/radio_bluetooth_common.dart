part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothBleAdapter() async {
  try {
    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) return false;

    if (!BluetoothService._bluetoothInitialized) {
      BluetoothService._bluetoothInitialized = true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final state = await FlutterBluePlus.adapterState.first.timeout(
          const Duration(seconds: 2),
        );

        if (state == BluetoothAdapterState.on) {
          return true;
        } else if (state == BluetoothAdapterState.off ||
            state == BluetoothAdapterState.unauthorized) {
          return false;
        }

        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    try {
      final finalState = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 1),
      );
      return finalState == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  } catch (_) {
    return false;
  }
}

Future<bool> _isBluetoothOnBleAdapter() async {
  try {
    final state = await FlutterBluePlus.adapterState.first.timeout(
      const Duration(milliseconds: 500),
    );
    return state == BluetoothAdapterState.on;
  } catch (_) {
    return false;
  }
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesClassic(
  BluetoothService service,
) async {
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
  } catch (_) {
    // Ignore errors finding Classic devices.
  }

  return devices;
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesBle(
  BluetoothService service, {
  required Duration timeout,
  required bool useWebKeywordFilter,
  required bool returnEarlyOnFirstMatch,
}) async {
  final devices = <DiscoveredDevice>[];
  final seen = <String>{};

  try {
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
      withKeywords: useWebKeywordFilter ? const ['UV-PRO'] : const [],
      webOptionalServices: kRadioBleOptionalServices,
    );

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

        final device = DiscoveredDevice(
          id: deviceId,
          name: name,
          type: BluetoothType.ble,
          rssi: result.rssi,
        );

        if (device.isCompatibleRadio) {
          seen.add(deviceId);
          devices.add(device);
          if (returnEarlyOnFirstMatch) {
            return devices;
          }
        }
      }
    }
  } catch (_) {
    // Ignore BLE scan errors.
  } finally {
    await FlutterBluePlus.stopScan();
  }

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
  } catch (_) {
    // Ignore errors getting bonded devices.
  }

  return devices;
}

Future<int?> _connectToRadioClassicImpl(
  BluetoothService service,
  String macAddress,
  String friendlyName,
) async {
  final macUpper = macAddress.toUpperCase();

  for (final entry in service._classicConnections.entries) {
    if (entry.value.toUpperCase() == macUpper) {
      return entry.key;
    }
  }

  try {
    final deviceId = service._getNextDeviceId();

    service._broker.dispatch(
      deviceId: deviceId,
      name: 'State',
      data: 'Connecting',
      store: true,
    );

    service._broker.dispatch(
      deviceId: deviceId,
      name: 'FriendlyName',
      data: friendlyName,
      store: true,
    );

    service._classicConnections[deviceId] = macAddress;
    service._publishConnectedRadios();

    final transport = BluetoothClassicTransport();
    final device = DiscoveredDevice(
      id: macAddress,
      name: friendlyName.isNotEmpty ? friendlyName : macAddress,
      type: BluetoothType.classic,
    );

    final success = await transport.connect(device);

    if (!success) {
      service._classicConnections.remove(deviceId);
      await transport.dispose();
      service._broker.dispatch(
        deviceId: deviceId,
        name: 'State',
        data: 'UnableToConnect',
        store: true,
      );
      service._publishConnectedRadios();
      return null;
    }

    service._connectedRadios[deviceId] = transport;

    final radio = Radio(deviceId: deviceId, macAddress: macAddress);
    radio.updateFriendlyName(friendlyName);
    service._radioInstances[deviceId] = radio;
    await radio.connect(transport);

    final radioAudio = RadioAudio(
      radio: radio,
      deviceId: deviceId,
      macAddress: macAddress,
    );
    service._radioAudioInstances[deviceId] = radioAudio;

    final audioEnabledPref =
        service._broker.getValue<bool>(0, 'AudioEnabled', false) ?? false;
    if (audioEnabledPref) {
      service._broker.dispatch(
        deviceId: deviceId,
        name: 'SetAudio',
        data: true,
        store: false,
      );
    }

    // Restore the user's GPS-enabled preference (device 0). Radios without
    // GPS support silently ignore the enable command.
    final gpsEnabledPref =
        service._broker.getValue<bool>(0, 'GpsEnabled', false) ?? false;
    if (gpsEnabledPref) {
      service._broker.dispatch(
        deviceId: deviceId,
        name: 'SetGPS',
        data: true,
        store: false,
      );
    }

    service._broker.dispatch(
      deviceId: deviceId,
      name: 'MacAddress',
      data: macAddress,
      store: true,
    );
    service._broker.dispatch(
      deviceId: deviceId,
      name: 'FriendlyName',
      data: friendlyName,
      store: true,
    );
    service._broker.dispatch(
      deviceId: deviceId,
      name: 'State',
      data: 'Connected',
      store: true,
    );
    service._publishConnectedRadios();
    return deviceId;
  } catch (e) {
    service._broker.logError(
      '[BT-Classic] Classic connect flow threw for $macAddress: $e',
    );
    return null;
  }
}

Future<int?> _connectToRadioBleImpl(
  BluetoothService service,
  String macAddress,
  String friendlyName, {
  required bool webFastMode,
}) async {
  for (final entry in service._connectedRadios.entries) {
    if (entry.value.connectedDevice?.id.toUpperCase() ==
        macAddress.toUpperCase()) {
      return entry.key;
    }
  }

  try {
    final deviceId = service._getNextDeviceId();
    final transport = BleRadioTransport(webFastMode: webFastMode);

    final discovered = DiscoveredDevice(
      id: macAddress,
      name: friendlyName.isNotEmpty ? friendlyName : macAddress,
      type: BluetoothType.ble,
    );

    service._connectedRadios[deviceId] = transport;

    service._broker.dispatch(
      deviceId: deviceId,
      name: 'FriendlyName',
      data: friendlyName,
      store: true,
    );

    service._publishConnectedRadios();

    service._broker.dispatch(
      deviceId: deviceId,
      name: 'State',
      data: 'Connecting',
      store: true,
    );

    final success = await transport.connect(discovered);

    if (!success) {
      service._connectedRadios.remove(deviceId);
      service._broker.dispatch(
        deviceId: deviceId,
        name: 'State',
        data: 'UnableToConnect',
        store: true,
      );
      service._publishConnectedRadios();
      await transport.dispose();
      return null;
    }

    final radio = Radio(deviceId: deviceId, macAddress: macAddress);
    radio.updateFriendlyName(friendlyName);
    service._radioInstances[deviceId] = radio;
    await radio.connect(transport);

    // Restore the user's GPS-enabled preference (device 0). Radios without
    // GPS support silently ignore the enable command.
    final gpsEnabledPref =
        service._broker.getValue<bool>(0, 'GpsEnabled', false) ?? false;
    if (gpsEnabledPref) {
      service._broker.dispatch(
        deviceId: deviceId,
        name: 'SetGPS',
        data: true,
        store: false,
      );
    }

    service._broker.dispatch(
      deviceId: deviceId,
      name: 'MacAddress',
      data: macAddress,
      store: true,
    );
    service._broker.dispatch(
      deviceId: deviceId,
      name: 'FriendlyName',
      data: friendlyName,
      store: true,
    );
    service._broker.dispatch(
      deviceId: deviceId,
      name: 'State',
      data: 'Connected',
      store: true,
    );
    service._publishConnectedRadios();
    return deviceId;
  } catch (_) {
    return null;
  }
}
