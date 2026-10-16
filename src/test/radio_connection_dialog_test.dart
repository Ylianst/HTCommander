/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/radio_connection_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';

Widget _launcher(List<CompatibleDevice> devices, {RadioScanner? scanner}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            RadioConnectionDialog.show(context, devices, scanner: scanner),
        child: const Text('Open'),
      ),
    ),
  );
}

void main() {
  testWidgets('dialog opens immediately and lists radios as they are found', (
    tester,
  ) async {
    final scanDone = Completer<RadioScanOutcome>();
    late void Function(CompatibleDevice) report;

    await tester.pumpWidget(
      _launcher(
        [CompatibleDevice(name: 'AllStarLink', mac: '', isAllStar: true)],
        scanner: (onFound) {
          report = onFound;
          return scanDone.future;
        },
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Radio Connection'), findsOneWidget);
    expect(find.text('AllStarLink'), findsOneWidget);
    expect(find.text('Scanning for radios...'), findsOneWidget);

    report(CompatibleDevice(name: 'UV-PRO', mac: 'AA:BB:CC:DD:EE:01'));
    await tester.pump();
    expect(find.text('UV-PRO'), findsOneWidget);
    expect(find.text('Scanning for radios...'), findsOneWidget);

    // Duplicate reports are ignored.
    report(CompatibleDevice(name: 'UV-PRO', mac: 'aa:bb:cc:dd:ee:01'));
    await tester.pump();
    expect(find.text('UV-PRO'), findsOneWidget);

    scanDone.complete(RadioScanOutcome.completed);
    await tester.pump();
    await tester.pump();
    expect(find.text('Scanning for radios...'), findsNothing);
    expect(find.text('UV-PRO'), findsOneWidget);
  });

  testWidgets('internet entries stay on top; radios keep discovery order', (
    tester,
  ) async {
    final scanDone = Completer<RadioScanOutcome>();
    late void Function(CompatibleDevice) report;

    await tester.pumpWidget(
      _launcher(
        [
          CompatibleDevice(name: 'EchoLink', mac: '', isEchoLink: true),
          CompatibleDevice(name: 'AllStarLink', mac: '', isAllStar: true),
        ],
        scanner: (onFound) {
          report = onFound;
          return scanDone.future;
        },
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    // Discovered out of alphabetical order on purpose.
    report(CompatibleDevice(name: 'Zulu', mac: 'AA:BB:CC:DD:EE:01'));
    await tester.pump();
    report(CompatibleDevice(name: 'Alpha', mac: 'AA:BB:CC:DD:EE:02'));
    await tester.pump();
    scanDone.complete(RadioScanOutcome.completed);
    await tester.pump();

    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('EchoLink'), lessThan(y('AllStarLink')));
    expect(y('AllStarLink'), lessThan(y('Zulu')));
    expect(y('Zulu'), lessThan(y('Alpha')));
  });

  testWidgets('dialog reports Bluetooth unavailable after the scan', (
    tester,
  ) async {
    await tester.pumpWidget(
      _launcher([
        CompatibleDevice(name: 'EchoLink', mac: '', isEchoLink: true),
      ], scanner: (_) async => RadioScanOutcome.bluetoothUnavailable),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.text('EchoLink'), findsOneWidget);
    expect(find.text('Bluetooth not available'), findsOneWidget);
  });

  testWidgets('dialog shows no radios found when the scan finds none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _launcher(const [], scanner: (_) async => RadioScanOutcome.completed),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('No compatible radios found.'), findsOneWidget);
  });

  testWidgets('cannot-connect dialog shows troubleshooting guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => RadioConnectionDialog.showCannotConnect(context),
            child: const Text('Connect'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot Connect to Radio'), findsOneWidget);
    expect(find.textContaining('Move the radio closer'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/images/CantConnect.png')),
      findsOneWidget,
    );
  });
}
