import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/add_station_dialog.dart';
import 'package:htcommander/handlers/terminal_handler.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/radio/radio.dart';
import 'package:htcommander/radio/radio_models.dart' as radio_models;
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/terminal_tab.dart';

const radioId = 301;

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

class TerminalRadio {
  final broker = DataBrokerClient();
  final commands = <String>[];
  final logs = <String>[];
  final sent = <int>[];
  SetLockData? lock;
  Map? connect;
  bool applyLock = true;
  bool answerDisconnect = true;

  TerminalRadio(StationInfo station) {
    broker.subscribeMultiple(
      deviceId: 1,
      names: const ['LogInfo', 'LogError'],
      callback: (_, _, data) => logs.add(data as String),
    );
    broker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    broker.dispatch(deviceId: 0, name: 'XaraWide', data: false);
    broker.dispatch(deviceId: 0, name: 'Stations', data: [station.toJson()]);
    broker.dispatch(
      deviceId: 1,
      name: 'ConnectedRadios',
      data: [
        {'DeviceId': radioId},
      ],
    );
    broker.dispatch(deviceId: radioId, name: 'AudioState', data: true);
    broker.dispatch(
      deviceId: radioId,
      name: 'HtStatus',
      data: {'currRegion': 0, 'currChId': 3},
    );
    broker.dispatch(
      deviceId: radioId,
      name: 'Settings',
      data: {'channelA': 3, 'scan': false, 'doubleChannel': 0},
    );
    broker.dispatch(
      deviceId: radioId,
      name: 'Channels',
      data: [
        {'name': 'BBS', 'channelId': 3},
      ],
    );
    broker.dispatch(deviceId: radioId, name: 'LockState', data: null);
    broker.subscribe(
      deviceId: radioId,
      name: 'SetLock',
      callback: (_, _, data) {
        commands.add('SetLock');
        lock = data as SetLockData;
        if (applyLock) {
          broker.dispatch(
            deviceId: radioId,
            name: 'LockState',
            data: radio_models.RadioLockState(
              isLocked: true,
              usage: lock!.usage,
              regionId: 0,
              channelId: 3,
              modem: lock!.modem,
              xaraWide: lock!.xaraWide,
            ).toJson(),
          );
        }
      },
    );
    broker.subscribe(
      deviceId: radioId,
      name: 'SetUnlock',
      callback: (_, _, _) {
        commands.add('SetUnlock');
        broker.dispatch(deviceId: radioId, name: 'LockState', data: null);
      },
    );
    broker.subscribe(
      deviceId: radioId,
      name: 'XaraConnect',
      callback: (_, _, data) {
        commands.add('XaraConnect');
        connect = data as Map;
      },
    );
    broker.subscribe(
      deviceId: radioId,
      name: 'XaraSend',
      callback: (_, _, data) => sent.addAll(data as Uint8List),
    );
    broker.subscribe(
      deviceId: radioId,
      name: 'XaraDisconnect',
      callback: (_, _, _) {
        commands.add('XaraDisconnect');
        if (answerDisconnect) event('disconnected');
      },
    );
    broker.subscribe(
      deviceId: radioId,
      name: 'XaraAbort',
      callback: (_, _, _) => commands.add('XaraAbort'),
    );
    broker.subscribe(
      deviceId: radioId,
      name: 'TransmitDataFrame',
      callback: (_, _, _) => commands.add('TransmitDataFrame'),
    );
  }

  void event(String event, {int id = radioId}) => broker.dispatch(
    deviceId: id,
    name: 'XaraEvent',
    data: {'evt': event},
    store: false,
  );

  void receive(String text, {int id = radioId}) => broker.dispatch(
    deviceId: id,
    name: 'XaraDataReceived',
    data: Uint8List.fromList(utf8.encode(text)),
    store: false,
  );

  void dispose() => broker.dispose();
}

StationInfo contact(TerminalProtocol protocol) => StationInfo(
  stationType: StationType.terminal,
  terminalProtocol: protocol,
  callsign: 'N1BBS-1',
  channel: 'BBS',
  ax25Path: 'N9DIG,N8DIG-2',
);

Future<void> connect(WidgetTester tester) async {
  await tester.pumpWidget(app(const TerminalTab()));
  await tester.tap(find.text('Connect'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('N1BBS-1'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  // The terminal engine, as main.dart registers it in the app.
  late TerminalHandler handler;
  setUp(() => handler = TerminalHandler()..init());
  // Ends a test: stop the engine (it outlives the tab) and drop the widget.
  Future<void> finish(WidgetTester tester) async {
    handler.abort();
    await tester.pumpWidget(app(const SizedBox()));
  }

  tearDown(() {
    handler.abort();
    handler.dispose();
  });

  test('radio lock preserves the per-connection XARA bandwidth', () {
    for (final wide in [null, false, true]) {
      final lock = radio_models.RadioLockState(
        isLocked: true,
        usage: 'Terminal',
        modem: 'XARA',
        xaraWide: wide,
      );
      expect(
        radio_models.RadioLockState.fromJson(lock.toJson()).xaraWide,
        wide,
      );
    }
  });
  for (final protocol in [
    TerminalProtocol.xaraNarrow,
    TerminalProtocol.xaraWide,
  ]) {
    test('$protocol persists through JSON and address-book export', () {
      final station = contact(protocol);
      expect(StationInfo.fromJson(station.toJson()).terminalProtocol, protocol);
      final restored = StationInfo.deserializeList(
        StationInfo.serializeList([station]),
      ).single;
      expect(restored.terminalProtocol, protocol);
      expect(restored.ax25Path, station.ax25Path);
      expect(restored.copyWith(name: 'BBS').terminalProtocol, protocol);
      expect(TerminalProtocol.x25Session.index, 3);
    });

    testWidgets('$protocol connects and exchanges BBS text', (tester) async {
      final radio = TerminalRadio(contact(protocol));
      addTearDown(radio.dispose);
      await connect(tester);
      expect(radio.commands, ['SetLock', 'XaraConnect']);
      expect(radio.lock!.modem, 'XARA');
      expect(radio.lock!.xaraWide, protocol == TerminalProtocol.xaraWide);
      expect(radio.connect!['Remote'], 'N1BBS-1');
      expect(radio.connect!['Vias'], ['N9DIG', 'N8DIG-2']);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      radio.event('connected', id: radioId + 1);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      radio.event('connected');
      radio.receive('Welcome to the BBS\r');
      radio.receive('Wrong radio\r', id: radioId + 1);
      await tester.pumpAndSettle();
      expect(find.textContaining('Welcome to the BBS'), findsOneWidget);
      expect(find.textContaining('Wrong radio'), findsNothing);
      await tester.enterText(find.byType(TextField), 'HELP');
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(utf8.decode(radio.sent), 'HELP\r');
      expect(radio.commands, isNot(contains('TransmitDataFrame')));

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(
        radio.commands,
        containsAllInOrder(['XaraDisconnect', 'SetUnlock']),
      );
      expect(find.text('Connect'), findsOneWidget);
      expect(radio.broker.getValue<bool>(0, 'XaraWide'), isFalse);
      await finish(tester);
    });

    testWidgets('$protocol can be edited in the address book', (tester) async {
      final broker = DataBrokerClient();
      addTearDown(broker.dispose);
      StationInfo? saved;
      final existing = contact(protocol);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showStationDialog(context, existing: existing);
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<TerminalProtocol>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('XARA Narrow'), findsWidgets);
      expect(find.text('XARA Wide'), findsWidgets);
      await tester.tap(
        find
            .text(
              protocol == TerminalProtocol.xaraWide
                  ? 'XARA Wide'
                  : 'XARA Narrow',
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Software AFSK 1200'), findsNothing);
      await tester.ensureVisible(find.text('OK'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saved!.terminalProtocol, protocol);
      expect(saved!.ax25Path, existing.ax25Path);
    });
  }

  testWidgets('create a terminal contact with XARA and validate its path', (
    tester,
  ) async {
    StationInfo? saved;
    final broker = DataBrokerClient();
    addTearDown(broker.dispose);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showStationDialog(
                context,
                fixedType: StationType.terminal,
                initialCallsign: 'N1BBS-1',
              );
            },
            child: const Text('New contact'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('New contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<TerminalProtocol>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('XARA Wide').last);
    await tester.pumpAndSettle();
    final path = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          (widget.decoration?.labelText?.startsWith('Digipeater Path') ??
              false),
    );
    await tester.ensureVisible(path);
    await tester.enterText(path, 'N9DIG,N8DIG,N7DIG');
    await tester.pump();
    final ok = find.widgetWithText(ElevatedButton, 'OK');
    expect(tester.widget<ElevatedButton>(ok).onPressed, isNull);
    expect(find.textContaining('up to two'), findsOneWidget);
    await tester.enterText(path, 'N9DIG,N8DIG');
    await tester.pump();
    await tester.ensureVisible(ok);
    await tester.tap(ok);
    await tester.pumpAndSettle();
    expect(saved!.stationType, StationType.terminal);
    expect(saved!.terminalProtocol, TerminalProtocol.xaraWide);
    expect(saved!.ax25Path, 'N9DIG,N8DIG');
  });

  testWidgets('XARA waits for cross-region tuning before connecting', (
    tester,
  ) async {
    final station = contact(TerminalProtocol.xaraWide)
      ..channelRegion = 'Remote';
    final radio = TerminalRadio(station);
    addTearDown(radio.dispose);
    radio.broker.dispatch(
      deviceId: radioId,
      name: 'RegionNames',
      data: ['Home', 'Remote'],
    );
    await connect(tester);
    expect(radio.lock!.regionId, 1);
    expect(radio.lock!.channelName, 'BBS');
    expect(radio.commands, ['SetLock']);
    radio.broker.dispatch(
      deviceId: radioId,
      name: 'HtStatus',
      data: {'currRegion': 1, 'currChId': 0},
    );
    radio.broker.dispatch(
      deviceId: radioId,
      name: 'Settings',
      data: {'channelA': 5},
    );
    radio.broker.dispatch(
      deviceId: radioId,
      name: 'Channels',
      data: [
        {'name': 'BBS', 'channelId': 5},
      ],
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(radio.commands, ['SetLock', 'XaraConnect']);
    await finish(tester);
    radio.broker.dispatch(deviceId: radioId, name: 'RegionNames', data: null);
  });

  testWidgets('XARA refuses to connect without radio audio', (tester) async {
    final radio = TerminalRadio(contact(TerminalProtocol.xaraNarrow));
    addTearDown(radio.dispose);
    radio.broker.dispatch(deviceId: radioId, name: 'AudioState', data: false);
    await connect(tester);
    expect(radio.commands, isEmpty);
    expect(find.textContaining('Enable the radio audio'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('raw AX.25 terminal contacts still use their configured modem', (
    tester,
  ) async {
    final radio = TerminalRadio(contact(TerminalProtocol.rawX25));
    addTearDown(radio.dispose);
    await connect(tester);
    expect(radio.commands, ['SetLock']);
    expect(radio.lock!.modem, 'Hardware');
    expect(radio.lock!.xaraWide, isNull);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(radio.commands, ['SetLock', 'TransmitDataFrame']);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('failed XARA link releases the terminal lock', (tester) async {
    final radio = TerminalRadio(contact(TerminalProtocol.xaraNarrow));
    addTearDown(radio.dispose);
    await connect(tester);
    radio.event('unableToConnect');
    await tester.pumpAndSettle();
    expect(find.textContaining('failed or timed out'), findsOneWidget);
    expect(radio.commands.last, 'SetUnlock');
    await finish(tester);
  });

  testWidgets('cancel while connecting aborts XARA', (tester) async {
    final radio = TerminalRadio(contact(TerminalProtocol.xaraWide));
    addTearDown(radio.dispose);
    await connect(tester);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(radio.commands, containsAllInOrder(['XaraAbort', 'SetUnlock']));
    await finish(tester);
  });

  testWidgets('lock and link timeouts abort instead of reporting success', (
    tester,
  ) async {
    final radio = TerminalRadio(contact(TerminalProtocol.xaraNarrow))
      ..applyLock = false;
    addTearDown(radio.dispose);
    await connect(tester);
    await tester.pump(const Duration(seconds: 16));
    expect(find.textContaining('Could not lock and tune'), findsOneWidget);
    expect(radio.commands, ['SetLock', 'XaraAbort']);
    await finish(tester);

    radio.applyLock = true;
    radio.commands.clear();
    await connect(tester);
    await tester.pump(const Duration(seconds: 121));
    expect(find.textContaining('failed or timed out'), findsOneWidget);
    expect(radio.commands, containsAllInOrder(['XaraAbort', 'SetUnlock']));
    await finish(tester);
  });

  for (final reason in [
    'lockNotHeld',
    'lockOwnedByOtherUsage',
    'channelMismatch',
    'statusUnavailable',
  ]) {
    testWidgets('XARA lock timeout reports $reason with radio diagnostics', (
      tester,
    ) async {
      final radio = TerminalRadio(contact(TerminalProtocol.xaraNarrow));
      addTearDown(radio.dispose);
      if (reason == 'lockNotHeld' || reason == 'lockOwnedByOtherUsage') {
        radio.applyLock = false;
      }
      if (reason == 'lockOwnedByOtherUsage') {
        radio.broker.dispatch(
          deviceId: radioId,
          name: 'LockState',
          data: {'isLocked': true, 'usage': 'Winlink'},
        );
      }
      if (reason == 'channelMismatch') {
        radio.broker.dispatch(
          deviceId: radioId,
          name: 'Settings',
          data: {'channelA': 4},
        );
      }
      if (reason == 'statusUnavailable') {
        radio.broker.dispatch(
          deviceId: radioId,
          name: 'HtStatus',
          data: null,
        );
      }
      if (reason == 'lockOwnedByOtherUsage') {
        await tester.pumpWidget(app(const TerminalTab()));
        handler.connect(radioId, contact(TerminalProtocol.xaraNarrow));
        await tester.pump(const Duration(milliseconds: 250));
      } else {
        await connect(tester);
      }
      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining('Could not lock and tune'), findsOneWidget);
      expect(find.textContaining('reason=$reason'), findsOneWidget);
      expect(find.textContaining('expectedChannel=3'), findsOneWidget);
      if (reason == 'lockOwnedByOtherUsage') {
        expect(find.textContaining('lockOwner=Winlink'), findsOneWidget);
        expect(radio.commands, isNot(contains('SetUnlock')));
      }
      if (reason == 'channelMismatch') {
        expect(find.textContaining('selectedChannel=4'), findsOneWidget);
      }
      expect(
        radio.logs.where(
          (line) =>
              line.contains('xaraLockTimeout') &&
              line.contains('radio=$radioId') &&
              line.contains('reason=$reason') &&
              line.contains('expectedRegion=0') &&
              line.contains('expectedChannel=3'),
        ),
        hasLength(1),
      );
      expect(radio.commands, isNot(contains('XaraConnect')));
      expect(radio.commands, contains('XaraAbort'));
      await finish(tester);
    });
  }

  testWidgets('XARA logs readiness changes without repeating unchanged polls', (
    tester,
  ) async {
    final radio = TerminalRadio(contact(TerminalProtocol.xaraNarrow));
    addTearDown(radio.dispose);
    radio.broker.dispatch(
      deviceId: radioId,
      name: 'Settings',
      data: {'channelA': 4},
    );
    await connect(tester);
    expect(
      radio.logs.where((line) => line.contains('XARA lock wait (15s)')),
      hasLength(1),
    );
    final logCount = radio.logs.length;
    await tester.pump(const Duration(seconds: 1));
    expect(radio.logs, hasLength(logCount));
    radio.broker.dispatch(
      deviceId: radioId,
      name: 'Settings',
      data: {'channelA': 3},
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(radio.commands, ['SetLock', 'XaraConnect']);
    expect(
      radio.logs.where(
        (line) =>
            line.contains('XARA lock wait changed') &&
            line.contains('reason=ready'),
      ),
      hasLength(1),
    );
    expect(
      radio.logs.where((line) => line.contains('XARA lock confirmed')),
      hasLength(1),
    );
    await tester.pump(const Duration(seconds: 16));
    expect(find.textContaining('Could not lock and tune'), findsNothing);
    await finish(tester);
  });

  testWidgets('disconnect timeout releases XARA; the link outlives the tab', (
    tester,
  ) async {
    final radio = TerminalRadio(contact(TerminalProtocol.xaraWide))
      ..answerDisconnect = false;
    addTearDown(radio.dispose);
    await connect(tester);
    radio.event('connected');
    await tester.pump();
    await tester.tap(find.text('Disconnect'));
    await tester.pump(const Duration(seconds: 31));
    expect(find.textContaining('disconnect timed out'), findsOneWidget);
    expect(
      radio.commands,
      containsAllInOrder(['XaraDisconnect', 'XaraAbort', 'SetUnlock']),
    );
    await finish(tester);

    // Closing the tab keeps the engine's link (a detached window or an agent
    // may be using it); reopening the tab shows it again.
    radio.commands.clear();
    await connect(tester);
    radio.event('connected');
    await tester.pump();
    await tester.pumpWidget(app(const SizedBox()));
    expect(radio.commands, isNot(contains('XaraAbort')));
    await tester.pumpWidget(app(const TerminalTab()));
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Terminal - N1BBS-1'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    // Stopping the engine releases the radio.
    await finish(tester);
    expect(radio.commands, containsAllInOrder(['XaraAbort', 'SetUnlock']));
  });

  testWidgets('losing audio or the radio lock stops XARA', (tester) async {
    final radio = TerminalRadio(contact(TerminalProtocol.xaraNarrow));
    addTearDown(radio.dispose);
    await connect(tester);
    radio.event('connected');
    radio.broker.dispatch(deviceId: radioId, name: 'AudioState', data: false);
    await tester.pumpAndSettle();
    expect(radio.commands, containsAllInOrder(['XaraAbort', 'SetUnlock']));
    await finish(tester);

    radio.broker.dispatch(deviceId: radioId, name: 'AudioState', data: true);
    radio.commands.clear();
    await connect(tester);
    radio.broker.dispatch(
      deviceId: radioId,
      name: 'LockState',
      data: {'isLocked': true, 'usage': 'Winlink'},
    );
    await tester.pump();
    expect(radio.commands.last, 'XaraAbort');
    expect(radio.commands, isNot(contains('SetUnlock')));
    await finish(tester);
  });
}
