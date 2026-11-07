/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/models/radio_models.dart' as ui;
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/radio/radio_transport.dart';
import 'package:htcommander/radio/utils.dart';
import 'package:htcommander/services/data_broker_client.dart';

class _RecordingTransport extends MockRadioTransport {
  final sent = <String>[];

  @override
  TransportState get state => TransportState.connected;

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> send(Uint8List data) async {
    sent.add(RadioUtils.bytesToHex(data));
    return true;
  }
}

// Frames captured from a radio entering the keypad "any frequency" mode
// (hold *), typing 144.000 MHz and leaving the mode again.
const _enterVfoSettings =
    'FF0100170002000906CD43A7471A1E1C80A1F10C2000000078000000000000';
const _vfoChannelChanged =
    'FF01001A0002000905FC089544000895440000000000040000000000000000000000';
const _exitVfoSettings =
    'FF01001700020009064D43A7471A1E1C80A1010C2000000078000000000000';
const _readVfoSlot = '0002000DFC';

void main() {
  late Radio radio;
  late _RecordingTransport transport;
  late DataBrokerClient broker;

  setUp(() async {
    broker = DataBrokerClient();
    transport = _RecordingTransport();
    radio = Radio(deviceId: 9150, macAddress: 'test');
    await radio.connect(transport);
    radio.channels = List.generate(
      32,
      (id) => RadioChannelInfo(channelId: id, name: 'Channel $id'),
    );
    transport.sent.clear();
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

  int vfoReads() =>
      transport.sent.where((f) => f.contains(_readVfoSlot)).length;

  test('slot ids between the channel table and 254 are VFO slots', () {
    expect(isVfoChannelId(252, 32), isTrue);
    expect(isVfoChannelId(253, 32), isTrue);
    expect(isVfoChannelId(31, 32), isFalse);
    expect(isVfoChannelId(254, 32), isFalse);
    expect(isVfoChannelId(252, 0), isFalse);
  });

  test('entering keypad VFO mode reads the selected VFO slot', () async {
    await receive(_exitVfoSettings);
    expect(radio.settings!.channelA, 4);
    expect(vfoReads(), 0);

    await receive(_enterVfoSettings);
    expect(radio.settings!.channelA, 252);
    expect(vfoReads(), 1);
  });

  test('VFO slot channel change is tracked instead of rejected', () async {
    await receive(_enterVfoSettings);
    await receive(_vfoChannelChanged);

    final slot = radio.vfoChannels[252]!;
    expect(slot.rxFreq, 144000000);
    expect(slot.txFreq, 144000000);
    expect(slot.rxMod, RadioModulationType.fm);
    expect(radio.channels!.length, 32);
    expect(radio.channelById(252), same(slot));

    final published = ui.parseVfoChannels(
      broker.getValueDynamic(radio.deviceId, 'VfoChannels'),
    );
    expect(published[252]!.rxFreq, 144000000);
    expect(published[252]!.frequencyDisplay, '144.000');

    // The htChChanged-triggered settings re-read must not re-read the slot.
    final reads = vfoReads();
    expect(reads, 1);
    await receive(_enterVfoSettings);
    expect(vfoReads(), reads);
  });

  test('a READ_RF_CH reply for the VFO slot is stored', () async {
    final channel = RadioChannelInfo(
      channelId: 252,
      rxFreq: 446000000,
      txFreq: 446000000,
      rxMod: RadioModulationType.am,
      txMod: RadioModulationType.am,
      bandwidth: RadioBandwidthType.wide,
    );
    final payload = Uint8List.fromList([0, ...channel.toByteArray()]);
    await receive('FF01001A0002800D${RadioUtils.bytesToHex(payload)}');

    final slot = radio.vfoChannels[252]!;
    expect(slot.rxFreq, 446000000);
    expect(slot.rxMod, RadioModulationType.am);
    expect(slot.bandwidth, RadioBandwidthType.wide);
    final published = ui.parseVfoChannels(
      broker.getValueDynamic(radio.deviceId, 'VfoChannels'),
    );
    expect(published[252]!.vfoCaption('VFO'), 'VFO · AM · Wide');
  });
}
