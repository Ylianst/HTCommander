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
// (passkey shown on the device, or 123456 on devices without a screen). On
// Windows HTCommander performs that PIN pairing itself through the native
// Bluetooth plugin; other platforms show their own system pairing prompt.
//

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'meshcore_client.dart';
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

  /// Scans for companions advertising the MeshCore name prefix or the Nordic
  /// UART service, reporting the accumulated list on each update.
  static Future<void> scan({
    required void Function(List<MeshCoreBleDevice> devices) onUpdate,
    Duration timeout = const Duration(seconds: 8),
  }) async {
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

  /// Removes the Windows bond so the next connection pairs again (needed after
  /// the companion is re-flashed or its PIN changes). No-op elsewhere.
  static Future<bool> forgetPairing(String remoteId) async {
    if (kIsWeb || !Platform.isWindows) return false;
    return await _nativeChannel.invokeMethod<bool>('bleUnpair', {
          'address': remoteId,
        }) ??
        false;
  }

  /// Pairs (Windows only), connects, and enables notifications.
  static Future<MeshCoreBleTransport> connect(
    String remoteId, {
    String pin = '',
    void Function(String message)? onStatus,
  }) async {
    if (!kIsWeb && Platform.isWindows) {
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
          throw const MeshCorePairingException(
            'Pairing failed. Check the PIN shown on the MeshCore device.',
          );
        case 'notFound':
          throw const MeshCoreException('MeshCore device not found.');
        default:
          throw MeshCoreException('Pairing failed ($status).');
      }
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
      if (!kIsWeb && Platform.isAndroid) {
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
      await _tx.setNotifyValue(true, timeout: 15);
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
