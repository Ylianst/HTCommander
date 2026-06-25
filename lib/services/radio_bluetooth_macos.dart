part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothMacos() async {
  return BluetoothClassicMacOS.instance.isAvailable();
}

Future<bool> _isBluetoothOnMacos() async {
  return BluetoothClassicMacOS.instance.isAvailable();
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesMacos(
  BluetoothService service, {
  required Duration timeout,
}) async {
  return _findCompatibleDevicesClassic(service);
}

Future<int?> _connectToRadioMacos(
  BluetoothService service,
  String macAddress,
  String friendlyName,
) async {
  return _connectToRadioClassicImpl(service, macAddress, friendlyName);
}
