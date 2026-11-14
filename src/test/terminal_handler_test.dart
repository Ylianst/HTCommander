/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// The headless terminal engine (TerminalHandler), driven through its broker
// commands the way the Terminal tab, detached windows and agents drive it.
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/terminal_handler.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/utils/station_channel_resolver.dart';

const int radioId = 701;

void main() {
  late TerminalHandler handler;
  late DataBrokerClient bus;
  final texts = <Map>[];
  final notices = <Map>[];
  final sent = <AX25Packet>[];
  final commands = <String>[];
  final statuses = <int, SetLockStatusData>{};
  var lockId = 0;

  Map state() => DataBroker.getValueDynamic(1, 'TerminalState')! as Map;

  void command(String name, [Object? data]) =>
      bus.dispatch(deviceId: 1, name: name, data: data, store: false);

  setUp(() {
    texts.clear();
    notices.clear();
    sent.clear();
    commands.clear();
    statuses.clear();
    lockId = 0;
    bus = DataBrokerClient();
    bus.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    bus.dispatch(deviceId: 0, name: 'StationId', data: 0);
    bus.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: [
        {'DeviceId': radioId},
      ],
    );
    bus.dispatch(
      deviceId: radioId,
      name: 'LockState',
      data: {'isLocked': false},
    );
    bus.dispatch(
      deviceId: radioId,
      name: 'HtStatus',
      data: {'currRegion': 0, 'currChId': 2},
    );
    bus.dispatch(
      deviceId: radioId,
      name: 'Channels',
      data: [
        {'name': 'PKT', 'channelId': 2},
      ],
    );
    bus.subscribe(
      deviceId: radioId,
      name: 'SetLock',
      callback: (_, _, d) {
        commands.add('SetLock:${(d! as SetLockData).modem}');
        bus.dispatch(
          deviceId: radioId,
          name: 'LockState',
          data: {'isLocked': true, 'usage': 'Terminal', 'lockId': ++lockId},
        );
      },
    );
    bus.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'SetLockStatus',
      callback: (id, _, data) => statuses[id] = data! as SetLockStatusData,
    );
    bus.subscribe(
      deviceId: radioId,
      name: 'SetUnlock',
      callback: (_, _, _) {
        commands.add('SetUnlock');
        bus.dispatch(
          deviceId: radioId,
          name: 'LockState',
          data: {'isLocked': false},
        );
      },
    );
    bus.subscribe(
      deviceId: radioId,
      name: 'TransmitDataFrame',
      callback: (_, _, d) => sent.add((d! as TransmitDataFrameData).packet!),
    );
    bus.subscribe(
      deviceId: 1,
      name: 'TerminalText',
      callback: (_, _, d) => texts.add(d! as Map),
    );
    bus.subscribe(
      deviceId: 1,
      name: 'TerminalNotice',
      callback: (_, _, d) => notices.add(d! as Map),
    );
    handler = TerminalHandler()..init();
  });

  tearDown(() {
    handler.abort();
    handler.dispose();
    bus.dispose();
  });

  StationInfo station(TerminalProtocol p) => StationInfo(
    callsign: 'N1ABC-1',
    stationType: StationType.terminal,
    terminalProtocol: p,
    channel: 'PKT',
  );

  test('starts idle and reports busy for a second connection', () {
    expect(state()['status'], 'idle');
    expect(state()['canSend'], isFalse);
    command('TerminalConnect', {
      'RadioId': radioId,
      'Station': station(TerminalProtocol.rawX25).toJson(),
    });
    expect(state()['status'], 'connected');
    expect(state()['remote'], 'N1ABC-1');
    expect(state()['canSend'], isTrue);
    expect(notices.last, {'kind': 'connectedTo', 'callsign': 'N1ABC-1'});
    command('TerminalWait', {'RadioId': radioId});
    expect(notices.last['kind'], 'busy');
  });

  test('station frequency prefers an exact simplex channel without tones', () {
    final contact = station(
      TerminalProtocol.rawX25,
    ).copyWith(frequencyHz: 145050000, channelRegion: 'Old region');
    bus.dispatch(
      deviceId: radioId,
      name: 'Channels',
      data: [
        {'channelId': 0, 'rxFreq': 145050001, 'txFreq': 145050001},
        {'channelId': 1, 'rxFreq': 145050000, 'txFreq': 145650000},
        {
          'channelId': 2,
          'rxFreq': 145050000,
          'txFreq': 145050000,
          'rxSubAudio': 885,
        },
        {
          'channelId': 3,
          'rxFreq': 145050000,
          'txFreq': 145050000,
          'txSubAudio': 885,
        },
        {'channelId': 4, 'rxFreq': 145050000, 'txFreq': 145050000},
      ],
    );
    final resolution = resolveStationChannel(bus, radioId, contact);
    expect(resolution.status, StationChannelStatus.ok);
    expect(resolution.regionId, 0);
    expect(resolution.channelId, 4);
    expect(resolution.frequencyHz, 0);
    SetLockData? lock;
    bus.subscribe(
      deviceId: radioId,
      name: 'SetLock',
      callback: (_, _, data) => lock = data as SetLockData,
    );
    handler.connect(radioId, contact);
    expect(lock!.channelId, 4);
    expect(lock!.frequencyHz, 0);
  });

  test('station frequency without a matching channel requests VFO tuning', () {
    var channelWrites = 0;
    bus.subscribe(
      deviceId: radioId,
      name: 'WriteChannel',
      callback: (_, _, _) => channelWrites++,
    );
    final contact = station(
      TerminalProtocol.rawX25,
    ).copyWith(frequencyHz: 145050000, channel: '');
    final resolution = resolveStationChannel(bus, radioId, contact);
    expect(resolution.status, StationChannelStatus.ok);
    expect(resolution.channelId, -1);
    expect(resolution.frequencyHz, 145050000);
    SetLockData? lock;
    bus.subscribe(
      deviceId: radioId,
      name: 'SetLock',
      callback: (_, _, data) => lock = data as SetLockData,
    );
    handler.connect(radioId, contact);
    expect(lock!.frequencyHz, 145050000);
    expect(lock!.channelId, -1);
    expect(channelWrites, 0);
    expect(state()['status'], 'connected');
  });

  test('raw AX.25 sends UI frames and shows received text', () {
    command('TerminalConnect', {
      'RadioId': radioId,
      'Station': station(TerminalProtocol.rawX25).toJson(),
    });
    expect(commands, ['SetLock:Hardware']);
    command('TerminalSend', {'Text': 'hello'});
    expect(sent.single.pid, 241);
    expect(utf8.decode(sent.single.data!), 'hello');
    expect(texts.last, {
      'outgoing': true,
      'from': 'N0CALL',
      'to': 'N1ABC-1',
      'text': 'hello\n',
    });

    final reply = AX25Packet(
      addresses: [AX25Address.parse('N0CALL')!, AX25Address.parse('N1ABC-1')!],
      data: utf8.encode('hi there'),
      type: FrameType.uFrameUi,
      command: true,
      time: DateTime.now(),
    );
    final frame = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: reply.toByteArray(),
      channelId: 2,
      regionId: 0,
      incoming: true,
      radioDeviceId: radioId,
    );
    bus.dispatch(
      deviceId: radioId,
      name: 'UniqueDataFrame',
      data: frame,
      store: false,
    );
    expect(texts.last['outgoing'], isFalse);
    expect(texts.last['from'], 'N1ABC-1');
    expect(texts.last['text'], 'hi there');

    command('TerminalDisconnect');
    expect(commands.last, 'SetUnlock');
    expect(state()['status'], 'idle');
    expect(notices.last['kind'], 'disconnected');
  });

  test('radio status counts peer payload bytes and resets on reconnect', () {
    final contact = station(TerminalProtocol.rawX25);
    handler.connect(radioId, contact);
    expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 0 B  Out: 0 B');
    final text = 'caf${String.fromCharCode(0xe9)}';
    handler.send(text);
    expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 0 B  Out: 5 B');

    const otherId = radioId + 1;
    bus.dispatch(
      deviceId: otherId,
      name: 'LockState',
      data: {'isLocked': true, 'usage': 'Terminal', 'lockId': 50},
    );
    bus.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: [
        {'DeviceId': otherId},
        {'DeviceId': radioId},
      ],
    );
    expect(handler.activeRadioId, radioId);
    void receive(int id, String peer) {
      final reply = AX25Packet(
        addresses: [AX25Address.parse('N0CALL')!, AX25Address.parse(peer)!],
        data: utf8.encode('reply'),
      )..pid = 241;
      bus.dispatch(
        deviceId: id,
        name: 'UniqueDataFrame',
        data: TncDataFragment(
          finalFragment: true,
          fragmentId: 0,
          data: reply.toByteArray(),
          channelId: 2,
          regionId: 0,
          incoming: true,
          radioDeviceId: id,
        ),
        store: false,
      );
    }

    receive(otherId, 'N1ABC-1');
    receive(radioId, 'N2XYZ');
    expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 0 B  Out: 5 B');
    receive(radioId, 'N1ABC-1');
    expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 5 B  Out: 5 B');
    expect(statuses.containsKey(otherId), false);

    bus.dispatch(deviceId: otherId, name: 'LockState', data: null);
    bus.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: [
        {'DeviceId': radioId},
      ],
    );
    handler.disconnect();
    final previousLock = statuses[radioId]!.lockId;
    handler.connect(radioId, contact);
    expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 0 B  Out: 0 B');
    expect(statuses[radioId]!.lockId, isNot(previousLock));
    addTearDown(() => DataBroker.clearDevice(otherId));
  });

  test(
    'incoming sessions count text and YAPP bytes without duplicate RX',
    () async {
      handler.waitForConnection(radioId);
      expect(
        statuses[radioId]!.text,
        'Waiting for connection...',
      );
      void receive(int type, {Uint8List? data, int nr = 0}) {
        final packet = AX25Packet(
          addresses: [
            AX25Address.parse('N0CALL')!,
            AX25Address.parse('N1ABC-1')!,
          ],
          type: type,
          command: true,
          pollFinal: type == FrameType.uFrameSabm,
          data: data,
          nr: nr,
        );
        bus.dispatch(
          deviceId: radioId,
          name: 'UniqueDataFrame',
          data: TncDataFragment(
            finalFragment: true,
            fragmentId: 0,
            data: packet.toByteArray(),
            channelId: 2,
            regionId: 0,
            incoming: true,
            radioDeviceId: radioId,
          ),
          store: false,
        );
      }

      receive(FrameType.uFrameSabm);
      expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 0 B  Out: 0 B');
      handler.send('x');
      expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 0 B  Out: 2 B');
      await Future<void>.delayed(Duration.zero);
      receive(
        FrameType.iFrame,
        data: Uint8List.fromList(utf8.encode('ok\r')),
        nr: 1,
      );
      expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 3 B  Out: 2 B');
      receive(
        FrameType.iFrame,
        data: Uint8List.fromList(utf8.encode('ok\r')),
        nr: 1,
      );
      expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 3 B  Out: 2 B');
      handler.sendFile('tiny.bin', Uint8List.fromList([1, 2, 3]));
      expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 3 B  Out: 4 B');
      handler.disconnect();
      expect(statuses[radioId]!.text, 'Disconnecting from N1ABC-1...');
    },
  );

  test('APRS messages are addressed to the padded callsign', () {
    command('TerminalConnect', {
      'RadioId': radioId,
      'Station': station(TerminalProtocol.aprs).toJson(),
    });
    command('TerminalSend', {'Text': 'test'});
    expect(sent.single.dataStr, ':N1ABC-1  :test');
    expect(sent.single.pid, 240);
    expect(statuses[radioId]!.text, 'N1ABC-1\nIn: 0 B  Out: 15 B');
  });

  test('compressed Terminal traffic counts the compressed payload size', () {
    handler.connect(radioId, station(TerminalProtocol.rawX25Compress));
    final text = List.filled(200, 'A').join();
    handler.send(text);
    final payload = sent.single.data!;
    expect(sent.single.pid, 243);
    expect(payload.length, lessThan(utf8.encode(text).length));
    expect(
      statuses[radioId]!.text,
      'N1ABC-1\nIn: 0 B  Out: ${payload.length} B',
    );
    final reply = AX25Packet(
      addresses: [AX25Address.parse('N0CALL')!, AX25Address.parse('N1ABC-1')!],
      data: payload,
    )..pid = 243;
    bus.dispatch(
      deviceId: radioId,
      name: 'UniqueDataFrame',
      data: TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: reply.toByteArray(),
        channelId: 2,
        regionId: 0,
        incoming: true,
        radioDeviceId: radioId,
      ),
      store: false,
    );
    expect(texts.last['text'], text);
    expect(
      statuses[radioId]!.text,
      'N1ABC-1\nIn: ${payload.length} B  Out: ${payload.length} B',
    );
  });

  test('an AX.25 session refuses text until connected', () {
    command('TerminalConnect', {
      'RadioId': radioId,
      'Station': station(TerminalProtocol.x25Session).toJson(),
    });
    expect(notices.last, {'kind': 'connecting', 'callsign': 'N1ABC-1'});
    expect(state()['status'], 'connecting');
    expect(state()['canSendFile'], isFalse);
    // Text is refused until the session is up.
    command('TerminalSend', {'Text': 'x'});
    expect(notices.last['kind'], 'notConnected');
    expect(statuses[radioId]!.text, 'Connecting to N1ABC-1...');
    command('TerminalDisconnect');
    expect(state()['status'], 'idle');
    expect(commands.last, 'SetUnlock');
  });

  test('wait for connection locks the radio and listens', () {
    command('TerminalWait', {'RadioId': radioId});
    expect(commands, ['SetLock:null']);
    expect(state()['status'], 'waiting');
    expect(notices.last['kind'], 'waiting');
    command('TerminalAbort');
    expect(state()['status'], 'idle');
  });

  test('contact problems are reported with the station', () {
    final s = station(TerminalProtocol.rawX25)..channel = 'NOPE';
    command('TerminalConnect', {'RadioId': radioId, 'Station': s.toJson()});
    expect(notices.last['kind'], 'channelMissing');
    expect((notices.last['station'] as Map)['Channel'], 'NOPE');
    expect(commands, isEmpty);
    expect(statuses, isEmpty);
    expect(state()['status'], 'idle');
  });

  group('local BBS', () {
    String incoming() =>
        texts.where((t) => t['outgoing'] == false).map((t) => t['text']).join();

    test('connects without a radio and serves the BBS menu', () {
      command('TerminalConnectLocalBbs');
      expect(commands, isEmpty);
      expect(statuses, isEmpty);
      expect(state()['status'], 'connected');
      expect(state()['remote'], 'N0CALL');
      expect(state()['protocol'], localBbsProtocol);
      expect(state()['canSend'], isTrue);
      expect(state()['canSendFile'], isFalse);
      expect(notices.last, {'kind': 'connectedTo', 'callsign': 'N0CALL'});
      expect(incoming(), contains('Handy-Talky Commander BBS'));

      command('TerminalSend', {'Text': 'M'});
      expect(texts.where((t) => t['outgoing'] == true).last['text'], 'M\n');
      expect(incoming(), contains('[S]oftware information'));

      command('TerminalWait', {'RadioId': radioId});
      expect(notices.last['kind'], 'busy');

      command('TerminalDisconnect');
      expect(state()['status'], 'idle');
      expect(state()['protocol'], isNull);
      expect(notices.last['kind'], 'disconnected');
      expect(commands, isEmpty);
    });

    test('the BBS D command ends the session', () async {
      command('TerminalConnectLocalBbs');
      command('TerminalSend', {'Text': 'D'});
      await Future<void>.delayed(Duration.zero);
      expect(state()['status'], 'idle');
      expect(notices.last['kind'], 'disconnected');
      // A fresh connection works afterwards.
      command('TerminalConnectLocalBbs');
      expect(state()['status'], 'connected');
    });
  });
}
