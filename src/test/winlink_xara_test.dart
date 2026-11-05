/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// Winlink over XARA: the WinlinkClient drives the XARA software modem
// through its per-radio broker API. A fake radio applies the lock and plays a
// CMS gateway over 'XaraEvent' / 'XaraDataReceived'.
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/radio/radio.dart' show SetLockData;
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/winlink/winlink_client.dart';

Future<bool> waitFor(
  bool Function() done, {
  Duration limit = const Duration(seconds: 5),
}) async {
  final DateTime end = DateTime.now().add(limit);
  while (!done()) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return true;
}

class FakeXaraRadio {
  final int id;
  final DataBrokerClient b = DataBrokerClient();
  final List<String> commands = <String>[];
  final List<int> sent = <int>[];
  Map<Object?, Object?>? connect;
  SetLockData? lock;
  bool answer = true;

  FakeXaraRadio(this.id) {
    b.dispatch(deviceId: id, name: 'AudioState', data: true, store: true);
    b.dispatch(
      deviceId: id,
      name: 'HtStatus',
      data: <String, Object?>{'currRegion': 0},
      store: true,
    );
    b.dispatch(
      deviceId: id,
      name: 'Channels',
      data: <Map<String, Object?>>[
        <String, Object?>{'name': 'WINLINK', 'channelId': 3},
      ],
      store: true,
    );
    b.dispatch(
      deviceId: id,
      name: 'LockState',
      data: <String, Object?>{'isLocked': false},
      store: true,
    );
    b.subscribe(
      deviceId: id,
      name: 'SetLock',
      callback: (_, _, data) {
        commands.add('SetLock');
        lock = data as SetLockData;
        b.dispatch(
          deviceId: id,
          name: 'LockState',
          data: <String, Object?>{
            'isLocked': true,
            'usage': 'Winlink',
            'channelId': 3,
          },
          store: true,
        );
      },
    );
    b.subscribe(
      deviceId: id,
      name: 'SetUnlock',
      callback: (_, _, _) => commands.add('SetUnlock'),
    );
    b.subscribe(
      deviceId: id,
      name: 'XaraConnect',
      callback: (_, _, d) {
        commands.add('XaraConnect');
        connect = d! as Map;
        event(answer ? 'connected' : 'timedOut');
      },
    );
    b.subscribe(
      deviceId: id,
      name: 'XaraSend',
      callback: (_, _, d) => sent.addAll(d! as Uint8List),
    );
    b.subscribe(
      deviceId: id,
      name: 'XaraDisconnect',
      callback: (_, _, _) {
        commands.add('XaraDisconnect');
        event('disconnected');
      },
    );
    b.subscribe(
      deviceId: id,
      name: 'XaraAbort',
      callback: (_, _, _) => commands.add('XaraAbort'),
    );
  }

  void event(String evt) => b.dispatch(
    deviceId: id,
    name: 'XaraEvent',
    data: <String, Object?>{'evt': evt},
    store: false,
  );

  void receive(String s) => b.dispatch(
    deviceId: id,
    name: 'XaraDataReceived',
    data: Uint8List.fromList(utf8.encode(s)),
    store: false,
  );

  String get transcript => utf8.decode(sent, allowMalformed: true);

  void dispose() => b.dispose();
}

StationInfo gateway() => StationInfo(
  callsign: 'N1RMS-10',
  stationType: StationType.winlink,
  channel: 'WINLINK',
  ax25Path: 'N9DIG',
  modem: 'XARA',
);

void main() {
  final DataBrokerClient ui = DataBrokerClient();
  final List<String> states = <String>[];
  final List<String> errors = <String>[];
  ui.subscribe(
    deviceId: 1,
    name: 'WinlinkConnectionState',
    callback: (_, _, d) => states.add(d! as String),
  );
  ui.subscribe(
    deviceId: 1,
    name: 'WinlinkError',
    callback: (_, _, d) => errors.add(d! as String),
  );
  ui.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL', store: true);

  setUp(() {
    states.clear();
    errors.clear();
  });

  test('a legacy XARA Winlink session runs B2F over the XARA link', () async {
    final FakeXaraRadio radio = FakeXaraRadio(201);
    final WinlinkClient client = WinlinkClient();
    try {
      ui.dispatch(
        deviceId: 1,
        name: 'WinlinkSync',
        data: <String, Object?>{'RadioId': 201, 'Station': gateway()},
      );
      expect(
        await waitFor(() => states.contains('CONNECTED')),
        isTrue,
        reason: '$states $errors',
      );
      expect(radio.commands.take(2), <String>['SetLock', 'XaraConnect']);
      expect(radio.connect?['Remote'], 'N1RMS-10');
      expect(radio.connect?['Vias'], <String>['N9DIG']);
      expect(radio.lock!.modem, 'XARA');
      expect(radio.lock!.xaraWide, isNull);

      radio.receive('[WL2K-5.0-B2FWIHJM\$]\rCMS>\r');
      expect(
        await waitFor(() => radio.transcript.contains('FF\r')),
        isTrue,
        reason: radio.transcript,
      );
      expect(radio.transcript, startsWith('[RMS Express-'));

      radio.receive('FQ\r');
      expect(
        await waitFor(() => states.contains('DISCONNECTED')),
        isTrue,
        reason: '$states',
      );
      expect(
        radio.commands,
        containsAllInOrder(<String>['XaraDisconnect', 'SetUnlock']),
      );
      expect(errors, isEmpty);
    } finally {
      client.dispose();
      radio.dispose();
    }
  });

  test('no answer over XARA ends the attempt with an error', () async {
    final FakeXaraRadio radio = FakeXaraRadio(202)..answer = false;
    final WinlinkClient client = WinlinkClient();
    try {
      ui.dispatch(
        deviceId: 1,
        name: 'WinlinkSync',
        data: <String, Object?>{'RadioId': 202, 'Station': gateway()},
      );
      expect(
        await waitFor(() => states.contains('DISCONNECTED')),
        isTrue,
        reason: '$states',
      );
      expect(errors.single, contains('No answer from N1RMS-10'));
      expect(radio.commands.last, 'SetUnlock');
    } finally {
      client.dispose();
      radio.dispose();
    }
  });

  test('user cancel while connecting disconnects the XARA link', () async {
    final FakeXaraRadio radio = FakeXaraRadio(203);
    radio.b.unsubscribe(203, 'XaraConnect');
    radio.b.subscribe(
      deviceId: 203,
      name: 'XaraConnect',
      callback: (_, _, _) => radio.commands.add('XaraConnect'),
    );
    final WinlinkClient client = WinlinkClient();
    try {
      ui.dispatch(
        deviceId: 1,
        name: 'WinlinkSync',
        data: <String, Object?>{'RadioId': 203, 'Station': gateway()},
      );
      expect(
        await waitFor(() => radio.commands.contains('XaraConnect')),
        isTrue,
      );
      ui.dispatch(deviceId: 1, name: 'WinlinkDisconnect', data: null);
      expect(
        await waitFor(() => states.contains('DISCONNECTED')),
        isTrue,
        reason: '$states',
      );
      expect(
        radio.commands,
        containsAllInOrder(<String>['XaraDisconnect', 'SetUnlock']),
      );
      expect(errors, isEmpty);
    } finally {
      client.dispose();
      radio.dispose();
    }
  });

  test('XARA needs the radio audio channel', () async {
    final FakeXaraRadio radio = FakeXaraRadio(204);
    radio.b.dispatch(
      deviceId: 204,
      name: 'AudioState',
      data: false,
      store: true,
    );
    final WinlinkClient client = WinlinkClient();
    try {
      ui.dispatch(
        deviceId: 1,
        name: 'WinlinkSync',
        data: <String, Object?>{'RadioId': 204, 'Station': gateway()},
      );
      expect(await waitFor(() => errors.isNotEmpty), isTrue);
      expect(errors.single, contains('Enable the radio audio'));
      expect(radio.commands, <String>['SetLock', 'SetUnlock']);
      expect(radio.commands, isNot(contains('XaraConnect')));
    } finally {
      client.dispose();
      radio.dispose();
    }
  });

  for (final protocol in [
    TerminalProtocol.xaraNarrow,
    TerminalProtocol.xaraWide,
  ]) {
    test('Winlink $protocol overrides the modem and bandwidth', () async {
      final radio = FakeXaraRadio(205);
      final client = WinlinkClient();
      final station = StationInfo.fromJson(
        gateway()
            .copyWith(terminalProtocol: protocol, modem: 'Hardware')
            .toJson(),
      );
      ui.dispatch(
        deviceId: 0,
        name: 'XaraWide',
        data: !(protocol == TerminalProtocol.xaraWide),
      );
      try {
        ui.dispatch(
          deviceId: 1,
          name: 'WinlinkSync',
          data: {'RadioId': radio.id, 'Station': station},
        );
        expect(await waitFor(() => states.contains('CONNECTED')), isTrue);
        expect(radio.lock!.modem, 'XARA');
        expect(radio.lock!.xaraWide, protocol == TerminalProtocol.xaraWide);
        expect(
          ui.getValue<bool>(0, 'XaraWide'),
          protocol != TerminalProtocol.xaraWide,
        );
        radio.receive('FQ\r');
        expect(await waitFor(() => states.contains('DISCONNECTED')), isTrue);
        expect(radio.commands.last, 'SetUnlock');
        expect(errors, isEmpty);
      } finally {
        client.dispose();
        radio.dispose();
        ui.dispatch(deviceId: 0, name: 'XaraWide', data: false);
      }
    });
  }

  for (final path in ['N9DIG,N8DIG,N7DIG', 'INVALID!']) {
    test(
      'Winlink XARA rejects invalid path $path rather than truncating',
      () async {
        final radio = FakeXaraRadio(206);
        final client = WinlinkClient();
        try {
          ui.dispatch(
            deviceId: 1,
            name: 'WinlinkSync',
            data: {
              'RadioId': radio.id,
              'Station': gateway().copyWith(
                terminalProtocol: TerminalProtocol.xaraNarrow,
                ax25Path: path,
              ),
            },
          );
          expect(await waitFor(() => errors.isNotEmpty), isTrue);
          expect(errors.single, contains('up to two digipeaters'));
          expect(radio.commands, ['SetLock', 'SetUnlock']);
        } finally {
          client.dispose();
          radio.dispose();
        }
      },
    );
  }
}
