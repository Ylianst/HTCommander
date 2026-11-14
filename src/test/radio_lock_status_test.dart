/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Radio;
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/models/radio_models.dart' as ui;
import 'package:htcommander/models/torrent_file.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart' as wire;
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/radio/utils.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/torrent/torrent_handler.dart';
import 'package:htcommander/widgets/radio_panel.dart';

Radio _radio(int id) => Radio(deviceId: id, macAddress: 'test')
  ..settings = wire.RadioSettings.fromBytes(
    RadioUtils.hexStringToByteArray(
      '0002800A005D43A7471A1E1C80A1010C2000000078000000000000',
    )!,
  )
  ..htStatus = wire.RadioHtStatus.fromBytes(Uint8List(9));

void main() {
  const first = 9600;
  const second = 9601;
  late DataBrokerClient broker;

  int lock(int id, [String usage = 'BBS']) {
    broker.dispatch(
      deviceId: id,
      name: 'SetLock',
      data: SetLockData(usage: usage),
      store: false,
    );
    return broker.getValue<Map<String, dynamic>>(id, 'LockState')!['lockId']
        as int;
  }

  void status(int id, int lockId, String text, [String usage = 'BBS']) {
    broker.dispatch(
      deviceId: id,
      name: 'SetLockStatus',
      data: SetLockStatusData(usage: usage, lockId: lockId, text: text),
      store: false,
    );
  }

  void unlock(int id, [String usage = 'BBS']) => broker.dispatch(
    deviceId: id,
    name: 'SetUnlock',
    data: SetUnlockData(usage: usage),
    store: false,
  );

  setUp(() {
    DataBroker.clearDevice(first);
    DataBroker.clearDevice(second);
    broker = DataBrokerClient();
  });

  tearDown(() {
    broker.dispose();
    DataBroker.clearDevice(first);
    DataBroker.clearDevice(second);
  });

  test('status is radio-local, owner-checked and reset for every lock', () {
    final a = _radio(first);
    final b = _radio(second);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final aLock = lock(first);
    final bLock = lock(second, 'Winlink');
    expect(broker.getValue<String>(first, 'LockStatus'), '');

    status(first, aLock, 'N1ABC: Connected');
    status(second, bLock, 'Sending mail...', 'Winlink');
    status(first, aLock, 'Wrong owner', 'Winlink');
    expect(broker.getValue<String>(first, 'LockStatus'), 'N1ABC: Connected');
    expect(broker.getValue<String>(second, 'LockStatus'), 'Sending mail...');

    var updates = 0;
    broker.subscribe(
      deviceId: first,
      name: 'LockStatus',
      callback: (_, _, _) => updates++,
    );
    status(first, aLock, 'N1ABC: Connected');
    expect(updates, 0);
    status(first, aLock, '');
    expect(broker.getValue<String>(first, 'LockStatus'), '');
    status(first, aLock, 'Old session');
    unlock(first);
    expect(broker.getValue<String>(first, 'LockStatus'), '');
    status(first, aLock, 'After unlock');
    expect(broker.getValue<String>(first, 'LockStatus'), '');

    final newLock = lock(first);
    expect(newLock, isNot(aLock));
    status(first, newLock, 'New session');
    status(first, aLock, 'Late callback');
    expect(broker.getValue<String>(first, 'LockStatus'), 'New session');
    expect(broker.getValue<String>(second, 'LockStatus'), 'Sending mail...');
    a.disconnect();
    expect(broker.getValue<String>(first, 'LockStatus'), '');
    expect(broker.getValue<String>(second, 'LockStatus'), 'Sending mail...');
  });

  test('a lock subscriber can publish the initial status synchronously', () {
    final radio = _radio(first);
    addTearDown(radio.dispose);
    broker.subscribe(
      deviceId: first,
      name: 'LockState',
      callback: (_, _, data) {
        if (data is Map<String, dynamic> && data['isLocked'] == true) {
          status(first, data['lockId'] as int, 'Connecting...');
        }
      },
    );
    lock(first);
    expect(broker.getValue<String>(first, 'LockStatus'), 'Connecting...');
  });

  void seedDisplay(int id) {
    broker.dispatch(deviceId: id, name: 'State', data: 'Connected');
    broker.dispatch(
      deviceId: id,
      name: 'Settings',
      data: ui.RadioSettings(
        channelA: 0,
        channelB: 1,
        doubleChannel: 1,
      ).toJson(),
    );
    broker.dispatch(
      deviceId: id,
      name: 'HtStatus',
      data: ui.RadioHtStatus(isPowerOn: true).toJson(),
    );
    broker.dispatch(
      deviceId: id,
      name: 'Channels',
      data: [
        for (var ch = 0; ch < 2; ch++)
          wire.RadioChannelInfo(
            channelId: ch,
            name: ch == 0 ? 'Main' : 'Secondary',
            rxFreq: 146520000,
            txFreq: 146520000,
          ).toJson(),
      ],
    );
    broker.dispatch(deviceId: id, name: 'GpsEnabled', data: true);
  }

  Widget panel(int id) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: RadioPanelControl(deviceId: id)),
  );

  for (final width in [360.0, 500.0]) {
    testWidgets('locked status keeps VFO B color and geometry at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.reset();
      });
      seedDisplay(first);
      await tester.pumpWidget(panel(first));
      final secondary = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Secondary' &&
            widget.style?.fontSize == 22,
      );
      final normalColor = tester.widget<Text>(secondary).style!.color;
      final gpsY = tester.getTopLeft(find.text('No GPS Lock')).dy;
      var switches = 0;
      broker.subscribe(
        deviceId: first,
        name: 'SwitchVfo',
        callback: (_, _, _) => switches++,
      );
      broker.dispatch(
        deviceId: first,
        name: 'LockState',
        data: {'isLocked': true, 'usage': 'BBS'},
      );
      await tester.pump();
      final area = find.byKey(const ValueKey('radioLockStatus'));
      expect(tester.getSize(area).height, 46);
      expect(secondary, findsNothing);
      final empty = find.descendant(of: area, matching: find.byType(Text));
      expect(tester.widget<Text>(empty).data, '');
      expect(tester.getTopLeft(find.text('No GPS Lock')).dy, closeTo(gpsY, 1));
      const longMessage =
          'N1ABC: Receiving a file with a very long name and additional '
          'details that need to wrap over several lines without moving GPS.';
      broker.dispatch(deviceId: first, name: 'LockStatus', data: longMessage);
      await tester.pump();
      final text = tester.widget<Text>(find.text(longMessage));
      expect(text.style!.color, normalColor);
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.getSize(area).height, 46);
      expect(tester.takeException(), isNull);
      await tester.tap(area);
      expect(switches, 0);
      broker.dispatch(deviceId: first, name: 'LockStatus', data: '');
      await tester.pump();
      expect(find.text(longMessage), findsNothing);
      broker.dispatch(
        deviceId: first,
        name: 'LockState',
        data: {'isLocked': false},
      );
      await tester.pump();
      expect(area, findsNothing);
      expect(secondary, findsOneWidget);
    });
  }

  testWidgets('selection and panel recreation recover only that radio status', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    for (final id in [first, second]) {
      seedDisplay(id);
      broker.dispatch(
        deviceId: id,
        name: 'LockState',
        data: {'isLocked': true, 'usage': 'BBS'},
      );
    }
    broker.dispatch(deviceId: first, name: 'LockStatus', data: 'N1ABC: Connected');
    broker.dispatch(deviceId: second, name: 'LockStatus', data: 'N2XYZ: Connected');
    await tester.pumpWidget(panel(first));
    expect(find.text('N1ABC: Connected'), findsOneWidget);
    await tester.pumpWidget(panel(second));
    expect(find.text('N2XYZ: Connected'), findsOneWidget);
    expect(find.text('N1ABC: Connected'), findsNothing);
    broker.dispatch(deviceId: first, name: 'LockStatus', data: 'N1ABC: Sending');
    await tester.pump();
    expect(find.text('N2XYZ: Connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(panel(first));
    expect(find.text('N1ABC: Sending'), findsOneWidget);
  });

  test('Torrent receive progress follows the receiving radio only', () {
    final a = _radio(first);
    final b = _radio(second);
    final torrent = TorrentHandler()..init();
    addTearDown(() {
      torrent.dispose();
      a.dispose();
      b.dispose();
    });
    lock(first, 'Torrent');
    lock(second, 'Torrent');
    final source = TorrentFile.fromFileBytes(
      fileName: 'test.txt',
      fileBytes: Uint8List.fromList(
        List.generate(1000, (i) => (i * 71 + i ~/ 7) & 255),
      ),
    )..callsign = 'N1ABC';
    expect(source.totalBlocks, greaterThan(1));
    final download = TorrentFile()
      ..id = source.id
      ..callsign = source.callsign
      ..fileName = source.fileName
      ..mode = TorrentMode.request
      ..blocks = List<Uint8List?>.filled(source.totalBlocks, null);
    torrent.files.add(download);

    void receive(int id, int block) {
      final payload = Uint8List.fromList([
        ...source.shortId,
        block >> 8,
        block & 255,
        ...source.blocks![block]!,
      ]);
      if (block == source.totalBlocks - 1) payload[5] |= 1;
      final packet = AX25Packet(
        addresses: [AX25Address.parse('N1ABC')!],
        data: payload,
      )..pid = 163;
      broker.dispatch(
        deviceId: id,
        name: 'UniqueDataFrame',
        data: TncDataFragment(
          finalFragment: true,
          fragmentId: 0,
          data: packet.toByteArray(),
          channelId: 0,
          regionId: 0,
          incoming: true,
          radioDeviceId: id,
          usage: 'Torrent',
        ),
        store: false,
      );
    }

    receive(first, 0);
    final aStatus = broker.getValue<String>(first, 'LockStatus');
    expect(aStatus, startsWith('Receiving test.txt: '));
    expect(broker.getValue<String>(second, 'LockStatus'), '');
    receive(second, 1);
    expect(broker.getValue<String>(second, 'LockStatus'), startsWith('Receiving'));
    expect(broker.getValue<String>(first, 'LockStatus'), aStatus);
    for (var i = 2; i < source.totalBlocks; i++) {
      receive(second, i);
    }
    expect(download.completed, true);
    expect(broker.getValue<String>(second, 'LockStatus'), 'Received test.txt');
    expect(broker.getValue<String>(first, 'LockStatus'), aStatus);

    final advertisement = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: (AX25Packet(
        addresses: [AX25Address.parse('N1ABC')!],
        data: Uint8List.fromList([1, 1, 3]),
      )..pid = 162).toByteArray(),
      channelId: 0,
      regionId: 0,
      radioDeviceId: first,
      usage: 'Torrent',
    );
    broker.dispatch(
      deviceId: first,
      name: 'UniqueDataFrame',
      data: advertisement,
      store: false,
    );
    expect(broker.getValue<String>(first, 'LockStatus'), aStatus);
    advertisement.incoming = true;
    broker.dispatch(
      deviceId: first,
      name: 'UniqueDataFrame',
      data: advertisement,
      store: false,
    );
    expect(broker.getValue<String>(first, 'LockStatus'), 'Heard N1ABC-0');
    expect(broker.getValue<String>(second, 'LockStatus'), 'Received test.txt');
  });
}
