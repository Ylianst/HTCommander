/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/vfo_frequency_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

const _deviceId = 9160;

void main() {
  late DataBrokerClient broker;
  late List<Object?> commands;

  setUp(() {
    broker = DataBrokerClient();
    commands = [];
    broker.dispatch(
      deviceId: _deviceId,
      name: 'FreqRanges',
      data: [
        {'lowHz': 108000000, 'highHz': 136000000, 'mod': 1},
        {'lowHz': 136000000, 'highHz': 174000000, 'mod': 2},
        {'lowHz': 400000000, 'highHz': 520000000, 'mod': 2},
      ],
    );
    broker.dispatch(
      deviceId: _deviceId,
      name: 'Settings',
      data: {'channelA': 252, 'channelB': 1},
    );
    broker.dispatch(
      deviceId: _deviceId,
      name: 'Channels',
      data: [
        for (var i = 0; i < 32; i++) {'channelId': i, 'name': 'Ch $i'},
      ],
    );
    broker.dispatch(
      deviceId: _deviceId,
      name: 'VfoChannels',
      data: [
        {'channelId': 252, 'rxFreq': 146520000, 'txFreq': 146520000},
      ],
    );
    broker.subscribeMultiple(
      deviceId: _deviceId,
      names: ['VfoTune', 'VfoExit'],
      callback: (_, name, data) =>
          commands.add(name == 'VfoExit' ? 'exit' : data),
    );
  });

  tearDown(() {
    broker.dispose();
    DataBroker.clearDevice(_deviceId);
    DataBroker.clearDevice(0);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Ahem's wide glyphs overflow dialog labels at normal scale.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showVfoFrequencyDialog(context, deviceId: _deviceId),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  ElevatedButton tuneButton(WidgetTester tester) => tester.widget(
    find.ancestor(of: find.text('Tune'), matching: find.byType(ElevatedButton)),
  );

  testWidgets('shows the current VFO frequency and tunes in range', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Frequency Mode'), findsOneWidget);
    expect(find.text('146.520'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '147.0');
    await tester.pump();
    await tester.tap(find.text('Tune'));
    expect(commands.single, {'freqHz': 147000000, 'am': false, 'wide': false});
  });

  testWidgets('blocks frequencies outside the radio bands', (tester) async {
    await open(tester);
    for (final text in ['200', '300.5', '600', '120']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      expect(tuneButton(tester).onPressed, isNull, reason: text);
      expect(
        find.text("Outside the radio's allowed range"),
        findsOneWidget,
        reason: text,
      );
    }
    expect(commands, isEmpty);

    // 120 MHz is valid once AM is selected (108-136 MHz is AM RX).
    await tester.tap(find.text('FM'));
    await tester.pump();
    expect(tuneButton(tester).onPressed, isNotNull);
  });

  testWidgets('step buttons tune and stop at the band edge', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '173.9875');
    await tester.pump();
    await tester.tap(find.byTooltip('Step up'));
    await tester.pump();
    expect(commands.single, {'freqHz': 174000000, 'am': false, 'wide': false});
    final stepUp = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(stepUp.onPressed, isNull);
  });

  testWidgets('titles channel mode and cycles the step size', (tester) async {
    broker.dispatch(
      deviceId: _deviceId,
      name: 'Settings',
      data: {'channelA': 3, 'channelB': 1},
    );
    await open(tester);
    expect(find.text('Channel Mode'), findsOneWidget);
    expect(find.text('Frequency Mode'), findsNothing);

    await tester.tap(find.text('12.5 kHz'));
    await tester.pump();
    expect(find.text('25 kHz'), findsOneWidget);
  });

  testWidgets('exit leaves frequency mode and closes the dialog', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Exit Frequency Mode'));
    await tester.pumpAndSettle();
    expect(commands.single, 'exit');
    expect(find.text('Frequency Mode'), findsNothing);
  });

  testWidgets('saves, tunes, renames and deletes saved frequencies', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('No saved frequencies'), findsOneWidget);

    // Save 120 MHz AM wide under a custom name.
    await tester.enterText(find.byType(TextField), '120');
    await tester.tap(find.text('FM'));
    await tester.tap(find.text('Narrow'));
    await tester.pump();
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('Wide'), findsOneWidget);
    await tester.tap(find.byTooltip('Save current frequency'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Tower');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Tower'), findsOneWidget);
    expect(commands, isEmpty);
    final stored = broker.getValue<String>(0, 'VfoFrequencies')!;
    expect(stored, contains('"freqHz":120000000'));

    // Change the editor, then tap the saved entry to restore and tune it.
    await tester.enterText(find.byType(TextField), '146.52');
    await tester.tap(find.text('AM'));
    await tester.pump();
    await tester.tap(find.text('Tower'));
    await tester.pump();
    expect(commands.single, {'freqHz': 120000000, 'am': true, 'wide': true});
    expect(find.text('120.000'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Airport');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Airport'), findsOneWidget);
    expect(find.text('Tower'), findsNothing);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Airport'), findsNothing);
    expect(find.text('No saved frequencies'), findsOneWidget);
    expect(broker.getValue<String>(0, 'VfoFrequencies'), '[]');
  });
}
