part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothLinux() async {
  return _checkBluetoothBleAdapter();
}

Future<bool> _isBluetoothOnLinux() async {
  return _isBluetoothOnBleAdapter();
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesLinux(
  BluetoothService service, {
  required Duration timeout,
}) async {
  return _findCompatibleDevicesBle(
    service,
    timeout: timeout,
    useWebKeywordFilter: false,
    returnEarlyOnFirstMatch: false,
  );
}

Future<int?> _connectToRadioLinux(
  BluetoothService service,
  String macAddress,
  String friendlyName,
) async {
  return _connectToRadioBleImpl(
    service,
    macAddress,
    friendlyName,
    webFastMode: false,
  );
}
