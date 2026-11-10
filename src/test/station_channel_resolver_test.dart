/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/utils/station_channel_resolver.dart';

const int radioId = 190;

Map<String, Object?> ch(
  int id,
  String name,
  int rx, {
  int? tx,
  int rxTone = 0,
  int txTone = 0,
  int mod = 0,
}) => {
  'channelId': id,
  'name': name,
  'rxFreq': rx,
  'txFreq': tx ?? rx,
  'rxSubAudio': rxTone,
  'txSubAudio': txTone,
  'rxMod': mod,
  'txMod': mod,
  'bandwidth': 0,
};

void main() {
  late DataBrokerClient broker;

  setUp(() {
    broker = DataBrokerClient();
    broker.dispatch(
      deviceId: radioId,
      name: 'HtStatus',
      data: {'currRegion': 1},
    );
    broker.dispatch(
      deviceId: radioId,
      name: 'RegionNames',
      data: ['Home', 'Away'],
    );
  });

  tearDown(() {
    broker.dispatch(deviceId: radioId, name: 'Channels', data: null);
    broker.dispatch(deviceId: radioId, name: 'HtStatus', data: null);
    broker.dispatch(deviceId: radioId, name: 'RegionNames', data: null);
    broker.dispose();
  });

  void channels(List<Map<String, Object?>> list) =>
      broker.dispatch(deviceId: radioId, name: 'Channels', data: list);

  group('resolveStationChannel with a frequency', () {
    test('matches a tone-less simplex channel and ignores the region', () {
      channels([
        ch(0, 'RPT', 145050000, tx: 145650000),
        ch(1, 'TONE', 145050000, rxTone: 10000, txTone: 10000),
        ch(2, 'AM', 145050000, mod: 1),
        ch(3, 'PKT', 145050000),
      ]);
      final station = StationInfo(
        frequency: 145050000,
        channel: 'Gone',
        channelRegion: 'Missing region',
      );
      final res = resolveStationChannel(broker, radioId, station);
      expect(res.status, StationChannelStatus.ok);
      expect(res.channelId, 3);
      expect(res.regionId, 1);
    });

    test('prefers the stored channel name among several matches', () {
      channels([ch(4, 'FIRST', 145050000), ch(7, 'MINE', 145050000)]);
      final res = resolveStationChannel(
        broker,
        radioId,
        StationInfo(frequency: 145050000, channel: 'MINE'),
      );
      expect(res.channelId, 7);
      final other = resolveStationChannel(
        broker,
        radioId,
        StationInfo(frequency: 145050000, channel: 'NOPE'),
      );
      expect(other.channelId, 4);
    });

    test('tunes directly when no channel matches', () {
      channels([
        ch(0, 'PKT', 144390000),
        ch(1, 'TONE', 145050000, txTone: 8850),
      ]);
      final res = resolveStationChannel(
        broker,
        radioId,
        StationInfo(frequency: 145050000, channel: 'TONE'),
      );
      expect(res.status, StationChannelStatus.ok);
      expect(res.isError, isFalse);
      expect(res.channelId, -1);
      expect(res.frequencyHz, 145050000);
    });
  });

  test('stations without a frequency keep resolving by name', () {
    channels([ch(2, 'PKT', 145050000)]);
    final res = resolveStationChannel(
      broker,
      radioId,
      StationInfo(channel: 'PKT', channelRegion: 'Away'),
    );
    expect(res.status, StationChannelStatus.ok);
    expect(res.channelId, 2);
    final missing = resolveStationChannel(
      broker,
      radioId,
      StationInfo(channel: 'PKT', channelRegion: 'Gone'),
    );
    expect(missing.status, StationChannelStatus.regionMissing);
  });

  test('StationInfo round-trips the frequency', () {
    final s = StationInfo(callsign: 'W1AW', frequency: 145050000);
    expect(StationInfo.fromJson(s.toJson()).frequency, 145050000);
    expect(StationInfo.fromJson({'Callsign': 'OLD'}).frequency, 0);
    final list = StationInfo.deserializeList(StationInfo.serializeList([s]));
    expect(list.single.frequency, 145050000);
    expect(s.copyWith(frequency: 1).frequency, 1);
  });

  test('legacy and GitHub frequency fields share one value', () {
    final station = StationInfo(frequencyHz: 145050000);
    expect(station.frequency, 145050000);
    station.frequency = 144390000;
    expect(station.frequencyHz, 144390000);
    expect(
      StationInfo.fromJson({'Frequency': 145050000}).frequencyHz,
      145050000,
    );
    expect(
      StationInfo.fromJson({
        'FrequencyHz': 145050000,
        'Frequency': 144390000,
      }).frequency,
      145050000,
    );
    expect(station.copyWith(frequencyHz: 146520000).frequency, 146520000);
  });
}
