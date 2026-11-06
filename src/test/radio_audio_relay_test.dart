/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/radio_transport.dart';
import 'package:htcommander/radio/utils.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/models/radio_models.dart' as ui;

const _on = '5D43E7471A1E1C80A1010C2000000078000000000000';
const _off = '5D43A7471A1E1C80A1010C2000000078000000000000';

Uint8List _bytes(String hex) => RadioUtils.hexStringToByteArray(hex)!;

class _RecordingTransport extends MockRadioTransport {
  final BluetoothType type;
  final sent = <Uint8List>[];

  _RecordingTransport(this.type);

  @override
  DiscoveredDevice get connectedDevice =>
      DiscoveredDevice(id: 'test', name: 'UV-Pro', type: type);

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> send(Uint8List data) async {
    sent.add(Uint8List.fromList(data));
    return true;
  }
}

void main() {
  test('captured settings decode Audio Relay and survive JSON conversion', () {
    for (final enabled in [false, true]) {
      final payload = enabled ? _on : _off;
      final settings = RadioSettings.fromBytes(_bytes('0002800A00$payload'));
      expect(settings.autoRelayEn, enabled);
      expect(ui.RadioSettings.fromJson(settings.toJson()).autoRelayEn, enabled);
      expect(settings.toByteArrayWith(), _bytes(payload));
      expect(
        settings.toByteArrayWith(autoRelayEn: !enabled),
        _bytes(enabled ? _off : _on),
      );
      expect(settings.rawData, _bytes('0002800A00$payload'));
    }
  });

  test('Audio Relay overlay preserves every other bit and trailing byte', () {
    for (var flags = 0; flags < 256; flags++) {
      final raw = _bytes('0002800A00${_off}12345678');
      raw[7] = flags;
      final settings = RadioSettings.fromBytes(raw);
      for (final enabled in [false, true]) {
        final expected = Uint8List.fromList(raw.sublist(5));
        expected[2] = (flags & 0xBF) | (enabled ? 0x40 : 0);
        expect(settings.toByteArrayWith(autoRelayEn: enabled), expected);
        expect(raw[7], flags);
      }
    }
  });

  test('incomplete settings cannot be used to change Audio Relay', () {
    expect(
      () => RadioSettings.fromBytes(
        Uint8List(7),
      ).toByteArrayWith(autoRelayEn: true),
      throwsStateError,
    );
  });

  for (final type in BluetoothType.values) {
    group('${type.name} Audio Relay', () {
      const deviceId = 9400;
      late Radio radio;
      late _RecordingTransport transport;
      late DataBrokerClient broker;

      setUp(() async {
        DataBroker.clearDevice(deviceId);
        broker = DataBrokerClient();
        transport = _RecordingTransport(type);
        radio = Radio(deviceId: deviceId, macAddress: 'test');
        await radio.connect(transport);
        transport.sent.clear();
      });

      tearDown(() async {
        radio.dispose();
        broker.dispose();
        await transport.dispose();
        DataBroker.clearDevice(deviceId);
      });

      Future<void> receive(String frame) async {
        // BLE replies share the direct command envelope without GAIA framing.
        transport.simulateReceive(
          _bytes(type == BluetoothType.ble ? frame.substring(8) : frame),
        );
        await Future<void>.delayed(Duration.zero);
      }

      test(
        'five broker toggle pairs match capture and confirmed state',
        () async {
          await receive('FF0100170002800A00$_off');
          for (var pair = 0; pair < 5; pair++) {
            for (final enabled in [true, false]) {
              transport.sent.clear();
              broker.dispatch(
                deviceId: deviceId,
                name: 'SetAudioRelay',
                data: enabled,
                store: false,
              );
              final payload = enabled ? _on : _off;
              final prefix = type == BluetoothType.ble
                  ? '0002000B'
                  : 'FF0100160002000B';
              expect(transport.sent.single, _bytes('$prefix$payload'));
              expect(radio.settings!.autoRelayEn, !enabled);
              await receive('FF0100010002800B00');
              expect(
                transport.sent.last,
                _bytes(
                  type == BluetoothType.ble ? '0002000A00' : 'FF0100000002000A',
                ),
              );
              await receive('FF0100170002000906$payload');
              expect(radio.settings!.autoRelayEn, enabled);
              expect(
                broker.getValue<Map<String, dynamic>>(
                  deviceId,
                  'Settings',
                )!['autoRelayEn'],
                enabled,
              );
            }
          }
        },
      );

      test('direct API preserves unrelated settings', () {
        radio.settings = RadioSettings.fromBytes(_bytes('0002800A00$_off'));
        radio.setAudioRelay(true);
        expect(
          transport.sent.single.sublist(type == BluetoothType.ble ? 4 : 8),
          _bytes(_on),
        );
      });

      test('missing, truncated, invalid and locked requests send nothing', () {
        radio.setAudioRelay(true);
        radio.settings = RadioSettings.fromBytes(Uint8List(7));
        radio.setAudioRelay(true);
        radio.settings = RadioSettings.fromBytes(_bytes('0002800A00$_off'));
        broker.dispatch(
          deviceId: deviceId,
          name: 'SetAudioRelay',
          data: 'true',
        );
        broker.dispatch(
          deviceId: deviceId + 1,
          name: 'SetAudioRelay',
          data: true,
        );
        expect(transport.sent, isEmpty);
        radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
        broker.dispatch(
          deviceId: deviceId,
          name: 'SetLock',
          data: SetLockData(usage: 'Satellite'),
        );
        transport.sent.clear();
        radio.setAudioRelay(true);
        broker.dispatch(deviceId: deviceId, name: 'SetAudioRelay', data: false);
        expect(transport.sent, isEmpty);
      });

      test('reported Audio Relay holds the lock until turned off', () async {
        radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
        await receive('FF0100170002800A00$_on');
        expect(radio.lockUsage, kAudioRelayLockUsage);
        expect(
          broker.getValue<Map<String, dynamic>>(deviceId, 'LockState')!['usage'],
          kAudioRelayLockUsage,
        );

        transport.sent.clear();
        broker.dispatch(
          deviceId: deviceId,
          name: 'SetLock',
          data: SetLockData(usage: 'Terminal'),
        );
        broker.dispatch(
          deviceId: deviceId,
          name: 'SetUnlock',
          data: SetUnlockData(usage: kAudioRelayLockUsage),
        );
        broker.dispatch(
          deviceId: deviceId,
          name: 'ChannelChangeVfoA',
          data: 3,
        );
        broker.dispatch(deviceId: deviceId, name: 'SetAudioRelay', data: true);
        expect(transport.sent, isEmpty);
        expect(radio.lockUsage, kAudioRelayLockUsage);

        broker.dispatch(deviceId: deviceId, name: 'SetAudioRelay', data: false);
        expect(transport.sent, hasLength(1));
        // The lock is released only once the radio confirms the change.
        expect(radio.lockUsage, kAudioRelayLockUsage);
        await receive('FF0100170002000906$_off');
        expect(radio.lockUsage, isNull);
        expect(
          broker.getValue<Map<String, dynamic>>(
            deviceId,
            'LockState',
          )!['isLocked'],
          false,
        );
      });

      test('Audio Relay lock cannot be requested via SetLock', () async {
        radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
        await receive('FF0100170002800A00$_off');
        transport.sent.clear();
        broker.dispatch(
          deviceId: deviceId,
          name: 'SetLock',
          data: SetLockData(usage: kAudioRelayLockUsage),
        );
        expect(radio.lockUsage, isNull);
        expect(transport.sent, isEmpty);
      });

      test('relay enabled during another lock takes over on unlock', () async {
        radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
        await receive('FF0100170002800A00$_off');
        broker.dispatch(
          deviceId: deviceId,
          name: 'SetLock',
          data: SetLockData(usage: 'Satellite'),
        );
        await receive('FF0100170002000906$_on');
        expect(radio.lockUsage, 'Satellite');

        broker.dispatch(
          deviceId: deviceId,
          name: 'SetUnlock',
          data: SetUnlockData(usage: 'Satellite'),
        );
        expect(radio.lockUsage, kAudioRelayLockUsage);
      });

      test('relay can be turned off while another usage holds the lock',
          () async {
        radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
        await receive('FF0100170002800A00$_off');
        broker.dispatch(
          deviceId: deviceId,
          name: 'SetLock',
          data: SetLockData(usage: 'Satellite'),
        );
        await receive('FF0100170002000906$_on');
        transport.sent.clear();
        broker.dispatch(deviceId: deviceId, name: 'SetAudioRelay', data: false);
        expect(
          transport.sent.single.sublist(type == BluetoothType.ble ? 4 : 8),
          _bytes(_off),
        );
        await receive('FF0100170002000906$_off');
        expect(radio.lockUsage, 'Satellite');
      });
    });
  }
}
