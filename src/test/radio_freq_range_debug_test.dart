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
      'logs full frequency range reply with packet tracing=$trace',
      () async {
        broker.dispatch(deviceId: 0, name: 'BluetoothFramesDebug', data: trace);
        await receive([
          0x00,
          0x02,
          0x80,
          0x27,
          0x00,
          0x40,
          0x6C,
          0x40,
          0x88,
          0x80,
          0x88,
          0x00,
          0xAE,
          0x00,
          0x00,
          0x00,
          0x00,
        ]);

        expect(
          logs.where((log) => log.contains('READ_FREQ_RANGE (39) reply:')),
          [
            '[Radio 9301] READ_FREQ_RANGE (39) reply: '
                '0002802700406C4088808800AE00000000',
          ],
        );
        expect(radio.freqRanges, [
          [108000000, 136000000],
          [136000000, 174000000],
        ]);
        expect(broker.getValueDynamic(9301, 'FreqRanges'), [
          {'lowHz': 108000000, 'highHz': 136000000, 'mod': 1},
          {'lowHz': 136000000, 'highHz': 174000000, 'mod': 2},
        ]);
        expect(
          broker.getValue<String>(9301, 'FreqRangesRaw'),
          '0002802700406C4088808800AE00000000',
        );
      },
    );
  }

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
