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

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/terminal_handler.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

const int radioId = 701;

void main() {
  late TerminalHandler handler;
  late DataBrokerClient bus;
  final texts = <Map>[];
  final notices = <Map>[];
  final sent = <AX25Packet>[];
  final commands = <String>[];

  Map state() => DataBroker.getValueDynamic(1, 'TerminalState')! as Map;

  void command(String name, [Object? data]) =>
      bus.dispatch(deviceId: 1, name: name, data: data, store: false);

  setUp(() {
    texts.clear();
    notices.clear();
    sent.clear();
    commands.clear();
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
          data: {'isLocked': true, 'usage': 'Terminal'},
        );
      },
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

  test('APRS messages are addressed to the padded callsign', () {
    command('TerminalConnect', {
      'RadioId': radioId,
      'Station': station(TerminalProtocol.aprs).toJson(),
    });
    command('TerminalSend', {'Text': 'test'});
    expect(sent.single.dataStr, ':N1ABC-1  :test');
    expect(sent.single.pid, 240);
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
    expect(state()['status'], 'idle');
  });
}
