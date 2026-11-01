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
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  late Radio radio;
  late MockRadioTransport transport;
  late DataBrokerClient broker;

  setUp(() async {
    broker = DataBrokerClient();
    transport = MockRadioTransport();
    radio = Radio(deviceId: 9100, macAddress: 'test');
    await radio.connect(transport);
    radio.channels = List.generate(
      16,
      (id) => RadioChannelInfo(channelId: id, name: 'Channel $id'),
    );
  });

  tearDown(() async {
    radio.dispose();
    broker.dispose();
    await transport.dispose();
  });

  Future<void> receive(String hex) async {
    transport.simulateReceive(RadioUtils.hexStringToByteArray(hex)!);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'physical power button immediately updates channel and UI list',
    () async {
      final otherChannel = radio.channels![15];
      final updates = <Map<String, dynamic>>[];
      broker.subscribe(
        deviceId: radio.deviceId,
        name: 'Channel_14',
        callback: (_, _, data) => updates.add(data! as Map<String, dynamic>),
      );

      for (final sample in [
        (flags: '1E', high: false, medium: true),
        (flags: '5C', high: true, medium: false),
        (flags: '1C', high: false, medium: false),
      ]) {
        await receive(
          'FF01001A00020009050E1917F3401917F34000000000'
          '${sample.flags}00486F7573650000000000',
        );
        final channel = radio.channels![14]!;
        expect(channel.channelId, 14);
        expect(channel.name, 'House');
        expect(channel.txFreq, 421000000);
        expect(channel.rxFreq, 421000000);
        expect(channel.txAtMaxPower, sample.high);
        expect(channel.txAtMedPower, sample.medium);
        expect(channel.bandwidth, RadioBandwidthType.wide);
        expect(channel.preDeEmphBypass, isTrue);
        expect(channel.sign, isTrue);
        expect(channel.toByteArray()[13], int.parse(sample.flags, radix: 16));
        expect(radio.channels![15], same(otherChannel));
        expect(updates.last['txAtMaxPower'], sample.high);
        expect(updates.last['txAtMedPower'], sample.medium);
        final channels = broker.getValue<List>(radio.deviceId, 'Channels')!;
        expect(channels.length, 16);
        expect((channels[14] as Map)['txAtMaxPower'], sample.high);
        expect((channels[14] as Map)['txAtMedPower'], sample.medium);
        expect(
          broker.getValue<bool>(radio.deviceId, 'AllChannelsLoaded'),
          isTrue,
        );
      }
      expect(updates.length, 3);
    },
  );

  test('notification updates an incompletely loaded channel cache', () async {
    radio.channels![0] = null;
    await receive(
      'FF01001A00020009050E1917F3401917F340000000005C00486F7573650000000000',
    );
    expect(radio.channels![14]!.txAtMaxPower, isTrue);
    expect(radio.allChannelsLoaded(), isFalse);
    expect(
      broker.getValue<Map>(radio.deviceId, 'Channel_14')!['name'],
      'House',
    );
  });

  test('truncated and out-of-range events do not overwrite channels', () async {
    final before = List<RadioChannelInfo?>.from(radio.channels!);
    await receive('FF01000200020009050E');
    await receive(
      'FF01001A0002000905FF1917F3401917F340000000005C00486F7573650000000000',
    );
    expect(radio.channels, before);
  });

  test('ordinary channel read replies still update the same cache', () async {
    final channel = RadioChannelInfo(
      channelId: 14,
      name: 'Updated',
      rxFreq: 146520000,
      txFreq: 146520000,
      txAtMaxPower: false,
      txAtMedPower: true,
    );
    final payload = Uint8List.fromList([0, ...channel.toByteArray()]);
    await receive('FF01001A0002800D${RadioUtils.bytesToHex(payload)}');
    expect(radio.channels![14]!.name, 'Updated');
    expect(radio.channels![14]!.txAtMedPower, isTrue);
    expect(
      (broker.getValue<List>(radio.deviceId, 'Channels')![14] as Map)['name'],
      'Updated',
    );
  });
}
