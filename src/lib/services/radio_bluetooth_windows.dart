part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothWindows() async {
  return BluetoothClassicMacOS.instance.isAvailable();
}

Future<bool> _isBluetoothOnWindows() async {
  return BluetoothClassicMacOS.instance.isAvailable();
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesWindows(
  BluetoothService service, {
  required Duration timeout,
}) async {
  return _findCompatibleDevicesClassic(service);
}

Future<int?> _connectToRadioWindows(
  BluetoothService service,
  String macAddress,
  String friendlyName,
) async {
  return _connectToRadioClassicImpl(service, macAddress, friendlyName);
}
