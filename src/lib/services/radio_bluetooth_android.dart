part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothAndroid() async {
  return _checkBluetoothBleAdapter();
}

Future<bool> _isBluetoothOnAndroid() async {
  return _isBluetoothOnBleAdapter();
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesAndroid(
  BluetoothService service, {
  required Duration timeout,
}) async {
  // Android 12+ (API 31+) requires the BLUETOOTH_CONNECT (and BLUETOOTH_SCAN)
  // runtime permissions before paired devices can be enumerated. On first run
  // these are not yet granted, so request them up-front and await the user's
  // response. Without this the native plugin returns an empty list on the same
  // call that triggers the permission dialog, and the user sees "No compatible
  // radios found" with no chance to retry.
  await _ensureAndroidBluetoothPermissions();

  // Android uses Bluetooth Classic (RFCOMM/SPP) for the radio control channel.
  // Compatible radios must be paired (bonded) in the Android Bluetooth settings;
  // they are enumerated from the bonded device list by the native plugin.
  return _findCompatibleDevicesClassic(service);
}

/// Requests the runtime Bluetooth permissions needed to enumerate and connect
/// to paired Classic devices on Android 12+, waiting for the user's response.
///
/// Failures are swallowed: if the plugin is unavailable or throws, the native
/// side still requests permissions as a fallback and the caller handles the
/// resulting (possibly empty) device list.
Future<void> _ensureAndroidBluetoothPermissions() async {
  try {
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
  } catch (_) {
    // Ignore; the native plugin requests permissions as a fallback.
  }
}

Future<int?> _connectToRadioAndroid(
  BluetoothService service,
  String macAddress,
  String friendlyName,
) async {
  // Android connects over Bluetooth Classic (RFCOMM/SPP) via the native plugin,
  // reusing the shared Classic connect flow (control channel).
  return _connectToRadioClassicImpl(service, macAddress, friendlyName);
}
