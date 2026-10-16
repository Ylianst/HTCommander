/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// meshcore_ble_transport.dart - MeshCore companion link over BLE (Nordic UART
// service). Each GATT write and each notification carries exactly one frame.
//
// The companion only exposes its characteristics over an authenticated bond
// (passkey shown on the device, or 123456 on devices without a screen). How
// the PIN reaches the OS differs per platform:
//   Windows  - HTCommander pairs through the native Bluetooth plugin.
//   Android  - flutter_blue_plus createBond() with the PIN (the system pairing
//              dialog appears when no PIN is given).
//   Linux    - HTCommander registers a temporary BlueZ agent with the PIN.
//   macOS/iOS/web - the operating system or browser shows its own PIN prompt
//              the first time an encrypted characteristic is used.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'meshcore_client.dart';
import 'meshcore_linux_pairing_stub.dart'
    if (dart.library.io) 'meshcore_linux_pairing.dart';
import 'meshcore_protocol.dart';

/// A MeshCore companion found while scanning.
class MeshCoreBleDevice {
  final String id;
  final String name;
  final int rssi;

  const MeshCoreBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'rssi': rssi};
}

class MeshCoreBleTransport implements MeshCoreTransport {
  MeshCoreBleTransport._(this._device, this._rx, this._tx);

  static final Guid _serviceGuid = Guid(MeshCoreConst.bleServiceUuid);

  static const MethodChannel _nativeChannel = MethodChannel(
    'com.htcommander/bluetooth_classic',
  );

  final BluetoothDevice _device;
  final BluetoothCharacteristic _rx;
  final BluetoothCharacteristic _tx;
  final _frames = StreamController<Uint8List>.broadcast();
  final _disconnected = StreamController<void>.broadcast();
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  bool _closed = false;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  static bool get isSupported =>
      kIsWeb ||
      Platform.isWindows ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get _isLinux => !kIsWeb && Platform.isLinux;
  static bool get _isWindows => !kIsWeb && Platform.isWindows;

  /// Whether HTCommander can hand the PIN to the OS itself. Elsewhere the
  /// system or browser asks for it.
  static bool get supportsPinEntry => _isWindows || _isAndroid || _isLinux;

  /// Whether [forgetPairing] can remove a bond on this platform.
  static bool get supportsForgetPairing => _isWindows || _isAndroid || _isLinux;

  /// Whether a remembered device can be reconnected without user action.
  /// Web Bluetooth needs a fresh device-chooser gesture.
  static bool get supportsAutoConnect => !kIsWeb;

  /// Android 12+ needs the runtime Bluetooth permissions before scanning or
  /// connecting.
  static Future<void> _ensureAndroidPermissions() async {
    if (!_isAndroid) return;
    try {
      await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    } catch (_) {
      // flutter_blue_plus requests them as a fallback.
    }
  }

  /// Scans for companions advertising the MeshCore name prefix or the Nordic
  /// UART service, reporting the accumulated list on each update.
  static Future<void> scan({
    required void Function(List<MeshCoreBleDevice> devices) onUpdate,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await _ensureAndroidPermissions();
    final found = <String, MeshCoreBleDevice>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      var changed = false;
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        final hasService = r.advertisementData.serviceUuids.contains(
          _serviceGuid,
        );
        if (!hasService && !name.startsWith(MeshCoreConst.bleNamePrefix)) {
          continue;
        }
        final id = r.device.remoteId.str;
        found[id] = MeshCoreBleDevice(
          id: id,
          name: name.isNotEmpty ? name : id,
          rssi: r.rssi,
        );
        changed = true;
      }
      if (changed) onUpdate(found.values.toList());
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: kIsWeb ? [_serviceGuid] : const [],
        webOptionalServices: [_serviceGuid],
      );
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } finally {
      await sub.cancel();
    }
  }

  static Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// Removes the bond so the next connection pairs again (needed after the
  /// companion is re-flashed or its PIN changes).
  static Future<bool> forgetPairing(String remoteId) async {
    if (_isWindows) {
      return await _nativeChannel.invokeMethod<bool>('bleUnpair', {
            'address': remoteId,
          }) ??
          false;
    }
    if (_isAndroid) {
      try {
        await BluetoothDevice.fromId(remoteId).removeBond();
        return true;
      } catch (_) {
        return false;
      }
    }
    if (_isLinux) return meshCoreLinuxForget(remoteId);
    return false;
  }

  static const _pinRejected = MeshCorePairingException(
    'Pairing failed. Check the PIN shown on the MeshCore device.',
  );

  /// Pairs where the platform allows HTCommander to supply the PIN, connects,
  /// and enables notifications.
  static Future<MeshCoreBleTransport> connect(
    String remoteId, {
    String pin = '',
    void Function(String message)? onStatus,
  }) async {
    await _ensureAndroidPermissions();
    if (_isWindows) {
      onStatus?.call('pairing');
      final status =
          await _nativeChannel.invokeMethod<String>('blePair', {
            'address': remoteId,
            'pin': pin,
          }) ??
          'error';
      switch (status) {
        case 'paired':
        case 'alreadyPaired':
        case 'cannotPair':
          break;
        case 'authFailed':
          throw _pinRejected;
        case 'notFound':
          throw const MeshCoreException('MeshCore device not found.');
        default:
          throw MeshCoreException('Pairing failed ($status).');
      }
    } else if (_isLinux) {
      onStatus?.call('pairing');
      await meshCoreLinuxPair(remoteId, pin);
    }

    onStatus?.call('connecting');
    final device = BluetoothDevice.fromId(remoteId);
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
      autoConnect: false,
    );
    MeshCoreBleTransport? transport;
    try {
      if (_isAndroid) {
        // Bond before touching the encrypted characteristics. Already bonded
        // devices return immediately; otherwise Android uses the PIN or shows
        // its pairing dialog.
        onStatus?.call('pairing');
        try {
          await device.createBond(
            timeout: 60,
            pin: pin.isEmpty ? null : Uint8List.fromList(utf8.encode(pin)),
          );
        } on FlutterBluePlusException {
          throw _pinRejected;
        }
        onStatus?.call('connecting');
        try {
          await device.requestMtu(185);
        } catch (_) {
          // The default MTU still carries the smaller frames.
        }
      }
      final services = await device.discoverServices();
      BluetoothCharacteristic? rx;
      BluetoothCharacteristic? tx;
      for (final s in services) {
        if (s.uuid != _serviceGuid) continue;
        for (final c in s.characteristics) {
          if (c.uuid == Guid(MeshCoreConst.bleRxCharUuid)) rx = c;
          if (c.uuid == Guid(MeshCoreConst.bleTxCharUuid)) tx = c;
        }
      }
      if (rx == null || tx == null) {
        throw const MeshCoreException(
          'This device does not expose the MeshCore companion service.',
        );
      }
      transport = MeshCoreBleTransport._(device, rx, tx);
      await transport._start();
      return transport;
    } catch (_) {
      if (transport != null) {
        // Also cancels the notification listener and closes the streams.
        await transport.close();
      } else {
        try {
          await device.disconnect();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _start() async {
    _notifySub = _tx.onValueReceived.listen((value) {
      if (value.isNotEmpty) _frames.add(Uint8List.fromList(value));
    });
    try {
      // Where the OS or browser asks for the PIN itself, this first access to
      // an encrypted characteristic waits while the user types it.
      await _tx.setNotifyValue(true, timeout: supportsPinEntry ? 15 : 90);
    } catch (e) {
      throw MeshCoreException(
        'Unable to subscribe to the MeshCore device ($e). If it was '
        're-flashed or its PIN changed, forget the pairing and try again.',
      );
    }
    _stateSub = _device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && !_closed) {
        _closed = true;
        _disconnected.add(null);
      }
    });
  }

  @override
  Future<void> sendFrame(Uint8List frame) =>
      _rx.write(frame, withoutResponse: false, timeout: 10);

  @override
  Future<void> close() async {
    _closed = true;
    await _notifySub?.cancel();
    await _stateSub?.cancel();
    try {
      await _device.disconnect();
    } catch (_) {}
    await _frames.close();
    await _disconnected.close();
  }
}
