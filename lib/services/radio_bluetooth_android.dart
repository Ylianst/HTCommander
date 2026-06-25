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
  return _findCompatibleDevicesBle(
    service,
    timeout: timeout,
    useWebKeywordFilter: false,
    returnEarlyOnFirstMatch: false,
  );
}

Future<int?> _connectToRadioAndroid(
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
