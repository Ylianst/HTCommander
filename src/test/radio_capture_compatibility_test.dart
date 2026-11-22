import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/gaia_protocol.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_transport.dart';
import 'package:htcommander/radio/utils.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

Uint8List _bytes(String hex) => RadioUtils.hexStringToByteArray(hex)!;

class _RecordingTransport extends MockRadioTransport {
  final sent = <Uint8List>[];

  @override
  TransportState get state => TransportState.connected;

  @override
  Future<bool> send(Uint8List data) async {
    sent.add(Uint8List.fromList(data));
    return true;
  }
}

void main() {
  // Control payloads from the supplied AP-2 and D9000-APP btsnoop captures.
  const captures = [
    (
      model: 'Benshi AP-2',
      bluetoothName: 'AP-2',
      devInfo: '0000100202008c84101034',
      settings: '002f22280698003e81f800000000000078000000000000',
      status: '0188010000',
      channelA: 2,
      channelB: 15,
      channelChange: 'ChannelChangeVfoB',
      newChannel: 14,
      settingsWrite: '2e22280698003e81f800000000000078000000000000',
    ),
    (
      model: 'Zastone D9000-APP',
      bluetoothName: 'ZASTONE',
      devInfo: '00040302010054c4c01000',
      settings: '00fe12360c20003e80e0000000',
      status: '0184000000',
      channelA: 15,
      channelB: 14,
      channelChange: 'ChannelChangeVfoA',
      newChannel: 5,
      settingsWrite: '5e12360c20003e80e0000000',
    ),
  ];

  for (final capture in captures) {
    test(
      '${capture.model} is discoverable by vendor UUID and fallback name',
      () {
        final device = DiscoveredDevice(
          id: 'test',
          name: capture.bluetoothName.toLowerCase(),
          type: BluetoothType.classic,
          serviceUuids: ['39144315-32fa-40db-85ed-fbfeba2d86e6'],
        );
        expect(device.isCompatibleRadio, isTrue);
        expect(device.hasRadioName, isTrue);
        expect(
          DiscoveredDevice(
            id: 'test',
            name: capture.bluetoothName,
            type: BluetoothType.ble,
          ).isCompatibleRadio,
          isFalse,
        );
      },
    );
  }

  group('captured control replies', () {
    const deviceId = 9500;
    late Radio radio;
    late _RecordingTransport transport;
    late DataBrokerClient broker;

    Future<void> receive(String command) async {
      transport.simulateReceive(GaiaProtocol.encode(_bytes(command)));
      await Future<void>.delayed(Duration.zero);
    }

    setUp(() async {
      DataBroker.clearDevice(deviceId);
      broker = DataBrokerClient();
      transport = _RecordingTransport();
      radio = Radio(deviceId: deviceId, macAddress: 'test');
      await radio.connect(transport);
    });

    tearDown(() async {
      radio.dispose();
      broker.dispose();
      await transport.dispose();
      DataBroker.clearDevice(deviceId);
    });

    for (final capture in captures) {
      test(
        '${capture.model} initializes and writes its native settings size',
        () async {
          await receive('00028004${capture.devInfo}');

          expect(
            transport.sent,
            contains(orderedEquals(GaiaProtocol.encode(_bytes('00020027')))),
          );
          expect(radio.info!.name, capture.model);
          expect(
            broker.getValue<String>(deviceId, 'FriendlyName'),
            capture.model,
          );
          expect(radio.channels, hasLength(16));
          expect(
            transport.sent,
            contains(orderedEquals(GaiaProtocol.encode(_bytes('0002000d00')))),
          );

          await receive('0002802700808800ae00c800c8819001e0');
          expect(broker.getValueDynamic(deviceId, 'FreqRanges'), [
            {'lowHz': 136000000, 'highHz': 174000000, 'mod': 2},
            {'lowHz': 400000000, 'highHz': 480000000, 'mod': 2},
          ]);

          await receive('0002800a${capture.settings}');
          expect(radio.settings!.channelA, capture.channelA);
          expect(radio.settings!.channelB, capture.channelB);
          expect(
            radio.settings!.toByteArrayWith(),
            _bytes(capture.settings.substring(2)),
          );

          await receive('00020009${capture.status}');
          expect(radio.htStatus!.isPowerOn, isTrue);
          expect(radio.htStatus!.isAocConnected, isFalse);

          transport.sent.clear();
          broker.dispatch(
            deviceId: deviceId,
            name: capture.channelChange,
            data: capture.newChannel,
            store: false,
          );
          await Future<void>.delayed(Duration.zero);
          expect(transport.sent, [
            GaiaProtocol.encode(_bytes('0002000b${capture.settingsWrite}')),
          ]);
          expect(
            radio.settings!.rawData,
            _bytes('0002800a${capture.settings}'),
          );

          transport.sent.clear();
          await receive('0002800b00');
          expect(transport.sent, [GaiaProtocol.encode(_bytes('0002000a'))]);
          await receive('0002800a00${capture.settingsWrite}');
          expect(
            capture.channelChange == 'ChannelChangeVfoA'
                ? radio.settings!.channelA
                : radio.settings!.channelB,
            capture.newChannel,
          );
        },
      );
    }

    test('unknown radios can return bands despite advertising zero', () async {
      await receive('000280040007123401000180001000');
      expect(radio.info!.freqRangeCount, 0);
      expect(
        transport.sent,
        contains(orderedEquals(GaiaProtocol.encode(_bytes('00020027')))),
      );
      await receive('0002802700808800ae00c800c8819001e0');
      expect(broker.getValueDynamic(deviceId, 'FreqRanges'), [
        {'lowHz': 136000000, 'highHz': 174000000, 'mod': 2},
        {'lowHz': 400000000, 'highHz': 480000000, 'mod': 2},
      ]);
    });

    test(
      'unsupported band discovery leaves other initialization working',
      () async {
        await receive('000280040007123401000180001000');
        transport.sent.clear();
        await receive('0002802701');
        expect(radio.freqRanges, isEmpty);
        expect(broker.getValueDynamic(deviceId, 'FreqRanges'), isNull);
        expect(transport.sent, isEmpty);

        await receive('0002800a${captures.last.settings}');
        expect(radio.settings!.channelA, captures.last.channelA);
        expect(
          broker.getValue<Map<String, dynamic>>(deviceId, 'Settings'),
          isNotNull,
        );
      },
    );
  });
}
