/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/xara_settings_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/software_modem.dart';
import 'package:htcommander/radio/xara_modem.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  late DataBrokerClient observer;
  late List<(String, Object?)> commands;

  void set(String name, int value) {
    DataBroker.dispatch(deviceId: 0, name: name, data: value, store: true);
  }

  setUp(() {
    set('XaraTxKeyUpMs', XaraModemConfig.defaultTxKeyUpMs);
    set('XaraTxLatencyMs', XaraModemConfig.defaultTxLatencyMs);
    observer = DataBrokerClient();
    commands = [];
    observer.subscribeMultiple(
      deviceId: 0,
      names: ['SetXaraTxKeyUpMs', 'SetXaraTxLatencyMs'],
      callback: (_, name, data) => commands.add((name, data)),
    );
  });

  tearDown(() => observer.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showXaraSettingsDialog(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  String value(int index) =>
      (find.byType(TextFormField).at(index).evaluate().single.widget
              as TextFormField)
          .controller!
          .text;

  testWidgets('shows defaults and saving unchanged values sends no commands', (
    tester,
  ) async {
    await open(tester);
    expect(value(0), '100');
    expect(value(1), '800');
    expect(find.text('Default: 100 ms. Range: 0-5000 ms.'), findsOneWidget);
    expect(find.text('Default: 800 ms. Range: 0-5000 ms.'), findsOneWidget);
    expect(
      find.textContaining('disconnects any active XARA links'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(commands, isEmpty);
    expect(find.byType(XaraSettingsDialog), findsNothing);
  });

  testWidgets('loads saved timings and cancel discards edits', (tester) async {
    set('XaraTxKeyUpMs', 450);
    set('XaraTxLatencyMs', 1200);
    await open(tester);
    expect(value(0), '450');
    expect(value(1), '1200');
    await tester.enterText(find.byType(TextFormField).first, '600');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(commands, isEmpty);
    expect(DataBroker.getValue<int>(0, 'XaraTxKeyUpMs'), 450);
  });

  testWidgets('rejects invalid timings without applying either field', (
    tester,
  ) async {
    await open(tester);
    for (final invalid in ['', '-1', '5001', '1.5', 'abc']) {
      await tester.enterText(find.byType(TextFormField).first, invalid);
      await tester.enterText(find.byType(TextFormField).last, '900');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number from 0 to 5000.'), findsOneWidget);
      expect(find.byType(XaraSettingsDialog), findsOneWidget);
      expect(commands, isEmpty);
    }
    await tester.enterText(find.byType(TextFormField).first, '400');
    await tester.enterText(find.byType(TextFormField).last, '5001');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 0 to 5000.'), findsOneWidget);
    expect(commands, isEmpty);
  });

  testWidgets('accepts both range boundaries using live modem commands', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.enterText(find.byType(TextFormField).last, '5000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(commands, [('SetXaraTxKeyUpMs', 0), ('SetXaraTxLatencyMs', 5000)]);
  });

  testWidgets('only applies the timing that changed', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField).last, '1000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(commands, [('SetXaraTxLatencyMs', 1000)]);
  });

  testWidgets('restore defaults clears errors and waits for Save', (
    tester,
  ) async {
    set('XaraTxKeyUpMs', 600);
    set('XaraTxLatencyMs', 1600);
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'bad');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore Defaults'));
    await tester.pumpAndSettle();
    expect(value(0), '100');
    expect(value(1), '800');
    expect(find.text('Enter a whole number from 0 to 5000.'), findsNothing);
    expect(commands, isEmpty);
    expect(DataBroker.getValue<int>(0, 'XaraTxKeyUpMs'), 600);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(commands, [('SetXaraTxKeyUpMs', 100), ('SetXaraTxLatencyMs', 800)]);
  });

  testWidgets('saving persists through the SoftwareModem handler and reopens', (
    tester,
  ) async {
    final modem = SoftwareModem();
    modem.init();
    addTearDown(modem.dispose);
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, '450');
    await tester.enterText(find.byType(TextFormField).last, '1250');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(DataBroker.getValue<int>(0, 'XaraTxKeyUpMs'), 450);
    expect(DataBroker.getValue<int>(0, 'XaraTxLatencyMs'), 1250);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(value(0), '450');
    expect(value(1), '1250');
  });

  testWidgets('lays out on a narrow screen without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Restore Defaults'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
