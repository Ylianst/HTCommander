part of 'bluetooth_service.dart';

Future<bool> _checkBluetoothWeb() async {
  return true;
}

Future<bool> _isBluetoothOnWeb() async {
  return true;
}

Future<List<DiscoveredDevice>> _findCompatibleDevicesWeb(
  BluetoothService service, {
  required Duration timeout,
}) async {
  return _findCompatibleDevicesBle(
    service,
    timeout: timeout,
    useWebKeywordFilter: true,
    returnEarlyOnFirstMatch: true,
  );
}

Future<int?> _connectToRadioWeb(
  BluetoothService service,
  String macAddress,
  String friendlyName,
) async {
  return _connectToRadioBleImpl(
    service,
    macAddress,
    friendlyName,
    webFastMode: true,
  );
}
