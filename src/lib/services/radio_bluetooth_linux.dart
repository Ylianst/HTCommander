part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothLinux() async {
  return BluetoothClassicMacOS.instance.isAvailable();
}

Future<bool> _isBluetoothOnLinux() async {
  return BluetoothClassicMacOS.instance.isAvailable();
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesLinux(
  BluetoothService service, {
  required Duration timeout,
}) async {
  return _findCompatibleDevicesClassic(service);
}

Future<int?> _connectToRadioLinux(
  BluetoothService service,
  String macAddress,
  String friendlyName,
) async {
  return _connectToRadioClassicImpl(service, macAddress, friendlyName);
}
