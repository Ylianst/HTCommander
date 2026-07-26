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
    // iOS: these radios do NOT advertise their 128-bit control service; they
    // only advertise unrelated UUIDs (e.g. `88a1`), and CoreBluetooth hides
    // any 128-bit overflow UUIDs from an unfiltered scan. So scan unfiltered
    // and identify compatible radios by their advertised product name.
    useServiceScanFilter: false,
    matchByName: true,
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
