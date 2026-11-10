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

  test('the VFO caption shows the offset and tones', () async {
    final channel = RadioChannelInfo(
      channelId: 252,
      rxFreq: 442100000,
      txFreq: 447100000,
      txSubAudio: 8850,
      rxSubAudio: 8850,
    );
    final payload = Uint8List.fromList([0, ...channel.toByteArray()]);
    await receive('FF01001A0002800D${RadioUtils.bytesToHex(payload)}');
    final published = ui.parseVfoChannels(
      broker.getValueDynamic(radio.deviceId, 'VfoChannels'),
    );
    expect(
      published[252]!.vfoCaption('VFO'),
      'VFO · FM · Narrow · +5 · TSQL 88.5',
    );
    expect(
      ui.offsetToneSummary(offsetHz: -600000, rxSubAudio: 23, txSubAudio: 6700),
      '-0.6 · T 67.0 · R D023',
    );
  });

  group('tuning keypad VFO mode', () {
    // READ_FREQ_RANGE reply: 108-136 AM RX, 136-174 FM TX/RX, 300-550 FM RX,
    // 400-520 FM TX/RX.
    const bands =
        'FF010015000280270040'
        '6C4088808800AE012C0226819002084000000000';
    final writeSettings = RegExp('^FF01[0-9A-F]{4}0002000B');
    final writeChannel = RegExp('^FF01[0-9A-F]{4}0002000E');

    List<String> sentMatching(RegExp re) =>
        transport.sent.where(re.hasMatch).toList();

    Future<void> ready() async {
      await receive(bands);
      expect(radio.freqBands, hasLength(4));
      await receive(_exitVfoSettings);
      transport.sent.clear();
    }

    test('enters the mode by writing slot 252 then selecting it', () async {
      await ready();
      expect(
        radio.tuneKeypadVfo(
          freqHz: 146520000,
          mod: RadioModulationType.fm,
          bandwidth: RadioBandwidthType.wide,
        ),
        isTrue,
      );
      final ch = sentMatching(writeChannel).single;
      final payload = RadioUtils.hexStringToByteArray(ch)!.sublist(8);
      final written = RadioChannelInfo.fromBytes(
        Uint8List.fromList([0, 0, 0, 0, 0, ...payload]),
      );
      expect(written.channelId, 252);
      expect(written.rxFreq, 146520000);
      expect(written.txFreq, 146520000);
      expect(written.bandwidth, RadioBandwidthType.wide);

      final settingsFrame = RadioUtils.hexStringToByteArray(
        sentMatching(writeSettings).single,
      )!;
      final written2 = RadioSettings.fromBytes(
        Uint8List.fromList([0, 0, 0, 0, 0, ...settingsFrame.sublist(8)]),
      );
      expect(written2.channelA, 252);
      expect(written2.channelB, radio.settings!.channelB);
    });

    test(
      'station lock tunes a simplex tone-free VFO and restores channel',
      () async {
        await ready();
        radio.htStatus = RadioHtStatus.fromBytes(Uint8List(9));
        radio.vfoChannels[252] = RadioChannelInfo(
          channelId: 252,
          rxFreq: 145000000,
          txFreq: 145600000,
          rxSubAudio: 885,
          txSubAudio: 885,
        );
        broker.dispatch(
          deviceId: radio.deviceId,
          name: 'SetLock',
          data: SetLockData(usage: 'Terminal', frequencyHz: 145050000),
          store: false,
        );
        final channelFrame = RadioUtils.hexStringToByteArray(
          sentMatching(writeChannel).single,
        )!;
        final written = RadioChannelInfo.fromBytes(
          Uint8List.fromList([0, 0, 0, 0, 0, ...channelFrame.sublist(8)]),
        );
        expect(written.channelId, 252);
        expect(written.rxFreq, 145050000);
        expect(written.txFreq, 145050000);
        expect(written.rxSubAudio, 0);
        expect(written.txSubAudio, 0);
        final settingsFrame = RadioUtils.hexStringToByteArray(
          sentMatching(writeSettings).single,
        )!;
        final selected = RadioSettings.fromBytes(
          Uint8List.fromList([0, 0, 0, 0, 0, ...settingsFrame.sublist(8)]),
        );
        expect(selected.channelA, 252);
        expect(selected.doubleChannel, 0);
        expect(selected.scan, isFalse);
        expect(radio.lockUsage, 'Terminal');
        expect(radio.channels![4]!.name, 'Channel 4');

        transport.sent.clear();
        broker.dispatch(
          deviceId: radio.deviceId,
          name: 'SetUnlock',
          data: SetUnlockData(usage: 'Terminal'),
          store: false,
        );
        final restoredFrame = RadioUtils.hexStringToByteArray(
          sentMatching(writeSettings).single,
        )!;
        final restored = RadioSettings.fromBytes(
          Uint8List.fromList([0, 0, 0, 0, 0, ...restoredFrame.sublist(8)]),
        );
        expect(restored.channelA, 4);
        expect(radio.lockUsage, isNull);
      },
    );

    test('retuning while in the mode only rewrites the slot', () async {
      await ready();
      await receive(_enterVfoSettings);
      transport.sent.clear();
      expect(
        radio.tuneKeypadVfo(
          freqHz: 446000000,
          mod: RadioModulationType.fm,
          bandwidth: RadioBandwidthType.narrow,
        ),
        isTrue,
      );
      expect(sentMatching(writeChannel), hasLength(1));
      expect(sentMatching(writeSettings), isEmpty);
    });

    test('rejects frequencies outside the radio bands', () async {
      await ready();
      for (final (hz, mod) in [
        (200000000, RadioModulationType.fm),
        (600000000, RadioModulationType.fm),
        (146520000, RadioModulationType.am),
        (120000000, RadioModulationType.fm),
      ]) {
        expect(
          radio.tuneKeypadVfo(
            freqHz: hz,
            mod: mod,
            bandwidth: RadioBandwidthType.narrow,
          ),
          isFalse,
        );
      }
      expect(
        radio.tuneKeypadVfo(
          freqHz: 120000000,
          mod: RadioModulationType.am,
          bandwidth: RadioBandwidthType.wide,
        ),
        isTrue,
      );
      expect(sentMatching(writeChannel), hasLength(1));
    });

    test('exit restores the last regular channel A', () async {
      await ready();
      expect(radio.exitKeypadVfo(), isFalse);
      await receive(_enterVfoSettings);
      transport.sent.clear();
      expect(radio.exitKeypadVfo(), isTrue);
      final frame = RadioUtils.hexStringToByteArray(
        sentMatching(writeSettings).single,
      )!;
      final written = RadioSettings.fromBytes(
        Uint8List.fromList([0, 0, 0, 0, 0, ...frame.sublist(8)]),
      );
      expect(written.channelA, 4);
    });

    test('writes a repeater offset and tones into the slot', () async {
      await ready();
      expect(
        radio.tuneKeypadVfo(
          freqHz: 146940000,
          mod: RadioModulationType.fm,
          bandwidth: RadioBandwidthType.wide,
          txFreqHz: 146340000,
          rxSubAudio: 23,
          txSubAudio: 10000,
        ),
        isTrue,
      );
      final payload = RadioUtils.hexStringToByteArray(
        sentMatching(writeChannel).single,
      )!.sublist(8);
      final written = RadioChannelInfo.fromBytes(
        Uint8List.fromList([0, 0, 0, 0, 0, ...payload]),
      );
      expect(written.rxFreq, 146940000);
      expect(written.txFreq, 146340000);
      expect(written.rxSubAudio, 23);
      expect(written.txSubAudio, 10000);
    });

    test('rejects offsets outside the TX bands or in AM', () async {
      await ready();
      for (final (rx, tx, mod) in [
        (173900000, 174900000, RadioModulationType.fm),
        (146520000, 300000000, RadioModulationType.fm),
        (120000000, 121000000, RadioModulationType.am),
      ]) {
        expect(
          radio.tuneKeypadVfo(
            freqHz: rx,
            mod: mod,
            bandwidth: RadioBandwidthType.narrow,
            txFreqHz: tx,
          ),
          isFalse,
          reason: '$rx -> $tx',
        );
      }
      expect(sentMatching(writeChannel), isEmpty);
    });

    test('broker VfoTune and VfoExit drive the radio', () async {
      await ready();
      broker.dispatch(
        deviceId: radio.deviceId,
        name: 'VfoTune',
        data: {'freqHz': 145500000, 'am': false, 'wide': false},
        store: false,
      );
      expect(sentMatching(writeChannel), hasLength(1));
      expect(sentMatching(writeSettings), hasLength(1));
    });
  });
}
