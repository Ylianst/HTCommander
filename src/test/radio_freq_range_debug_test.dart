import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/radio/gaia_protocol.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_transport.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  late Radio radio;
  late MockRadioTransport transport;
  late DataBrokerClient broker;
  late List<String> logs;

  Future<void> receive(List<int> command) async {
    transport.simulateReceive(GaiaProtocol.encode(Uint8List.fromList(command)));
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    broker = DataBrokerClient();
    logs = [];
    broker.dispatch(deviceId: 0, name: 'BluetoothFramesDebug', data: false);
    broker.subscribe(
      deviceId: 1,
      name: 'LogInfo',
      callback: (_, _, data) {
        if (data is String) logs.add(data);
      },
    );
    transport = MockRadioTransport();
    radio = Radio(deviceId: 9301, macAddress: 'test');
    await radio.connect(transport);
    logs.clear();
  });

  tearDown(() async {
    radio.dispose();
    broker.dispose();
    await transport.dispose();
    DataBroker.clearDevice(0);
    DataBroker.clearDevice(9301);
  });

  for (final trace in [false, true]) {
    test(
      'skips zero-width received range and publishes following band with packet tracing=$trace',
      () async {
        broker.dispatch(deviceId: 0, name: 'BluetoothFramesDebug', data: trace);
        await receive([
          0x00,
          0x02,
          0x80,
          0x27,
          0x00,
          0x80,
          0x88,
          0x00,
          0xAE,
          0x00,
          0xC8,
          0x00,
          0xC8,
          0x81,
          0x90,
          0x01,
          0xE0,
        ]);

        expect(
          logs.where((log) => log.contains('READ_FREQ_RANGE (39) reply:')),
          [
            '[Radio 9301] READ_FREQ_RANGE (39) reply: '
                '0002802700808800AE00C800C8819001E0',
          ],
        );
        expect(radio.freqRanges, [
          [136000000, 174000000],
          [400000000, 480000000],
        ]);
        expect(broker.getValueDynamic(9301, 'FreqRanges'), [
          {'lowHz': 136000000, 'highHz': 174000000, 'mod': 2},
          {'lowHz': 400000000, 'highHz': 480000000, 'mod': 2},
        ]);
        expect(
          broker.getValue<String>(9301, 'FreqRangesRaw'),
          '0002802700808800AE00C800C8819001E0',
        );
      },
    );
  }

  test(
    'uses received bands and stops at a zero-frequency terminator',
    () async {
      await receive([
        0x00,
        0x02,
        0x80,
        0x27,
        0x00,
        0x40,
        0x6C,
        0x40,
        0x89,
        0x80,
        0x88,
        0x00,
        0xAE,
        0x01,
        0x2C,
        0x02,
        0x26,
        0x81,
        0x90,
        0x02,
        0x08,
        0x40,
        0x00,
        0x00,
        0x00,
        0x80,
        0x88,
        0x00,
        0xAE,
      ]);

      expect(radio.freqRanges, [
        [108000000, 137000000],
        [136000000, 174000000],
        [300000000, 550000000],
        [400000000, 520000000],
      ]);
      expect(broker.getValueDynamic(9301, 'FreqRanges'), [
        {'lowHz': 108000000, 'highHz': 137000000, 'mod': 1},
        {'lowHz': 136000000, 'highHz': 174000000, 'mod': 2},
        {'lowHz': 300000000, 'highHz': 550000000, 'mod': 0},
        {'lowHz': 400000000, 'highHz': 520000000, 'mod': 2},
      ]);
      expect(
        broker.getValue<String>(9301, 'FreqRangesRaw'),
        '0002802700406C4089808800AE012C02268190020840000000808800AE',
      );
    },
  );

  test('logs failed and short replies before validation', () async {
    await receive([0x00, 0x02, 0x80, 0x27, 0x01]);
    await receive([0x00, 0x02, 0x80, 0x27]);

    expect(logs.where((log) => log.contains('READ_FREQ_RANGE (39) reply:')), [
      '[Radio 9301] READ_FREQ_RANGE (39) reply: 0002802701',
      '[Radio 9301] READ_FREQ_RANGE (39) reply: 00028027',
    ]);
    expect(radio.freqRanges, isEmpty);
    expect(broker.getValueDynamic(9301, 'FreqRanges'), isNull);
  });
}
