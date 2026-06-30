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
  // Android uses Bluetooth Classic (RFCOMM/SPP) for the radio control channel.
  // Compatible radios must be paired (bonded) in the Android Bluetooth settings;
  // they are enumerated from the bonded device list by the native plugin.
  return _findCompatibleDevicesClassic(service);
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
