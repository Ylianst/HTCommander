part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothIos() async {
  return _checkBluetoothBleAdapter();
}

Future<bool> _isBluetoothOnIos() async {
  return _isBluetoothOnBleAdapter();
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesIos(
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

Future<int?> _connectToRadioIos(
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
