/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/settings_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';

/// Regression coverage for issue #59: opening the settings dialog on desktop
/// (Windows) must build and lay out every tab without throwing or overflowing.
void main() {
  testWidgets('local mail servers default off and save validated ports', (
    tester,
  ) async {
    DataBroker.reset();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'N0CALL');
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const SettingsDialog(initialTabName: 'Servers'),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final smtpPort = find.widgetWithText(TextField, '8025');
      final popPort = find.widgetWithText(TextField, '8110');
      expect(tester.widget<TextField>(smtpPort).enabled, isFalse);
      expect(tester.widget<TextField>(popPort).enabled, isFalse);
      await tester.tap(find.text('Enable local SMTP server'));
      await tester.pumpAndSettle();
      final password = find.widgetWithText(TextField, 'Mail bridge password');
      expect(
        tester.widget<TextField>(password).controller!.text.length,
        greaterThanOrEqualTo(12),
      );
      await tester.enterText(smtpPort, '0');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(find.textContaining('ports between 1 and 65535'), findsOneWidget);
      expect(DataBroker.hasValue(0, 'smtpServerEnabled'), isFalse);
      await tester.enterText(find.widgetWithText(TextField, '0'), '18025');
      await tester.tap(find.text('Enable local POP3 server'));
      await tester.pumpAndSettle();
      await tester.enterText(popPort, '18110');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
      expect(DataBroker.getValue<int>(0, 'smtpServerEnabled', 0), 1);
      expect(DataBroker.getValue<int>(0, 'pop3ServerEnabled', 0), 1);
      expect(DataBroker.getValue<int>(0, 'smtpServerPort', 0), 18025);
      expect(DataBroker.getValue<int>(0, 'pop3ServerPort', 0), 18110);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      DataBroker.reset();
    }
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('named settings links select Application on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SettingsDialog(initialTabName: 'Application'),
            ),
          ),
        );
        await tester.pump();
        final tabBar = tester.widget<TabBar>(find.byType(TabBar));
        expect(
          (tabBar.tabs[tabBar.controller!.index] as Tab).text,
          'Application',
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('settings dialog builds every tab on Windows without overflow', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // A valid 1x1 transparent PNG, base64-encoded, as a stored avatar image.
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

    void set(String name, Object? data) =>
        DataBroker.dispatch(deviceId: 0, name: name, data: data, store: true);

    set('CallSign', 'KK7ABC');
    set('StationId', 7);
    set('AvatarImage', png);
    set('AprsIsEnabled', 1);
    set('AprsIsServer', 'my.custom.server.example.com');
    set('AprsIsPort', 12345);
    set('AprsIsPasscode', '12345');
    set('GpsSerialPort', 'COM5');
    set('EchoLinkProxyEnabled', 1);
    set('EchoLinkProxyAuto', 0);
    set('ManualLocationEnabled', 1);
    set('ManualLatitude', 47.6062);
    set('ManualLongitude', -122.3321);

    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsDialog()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'initial build');

      final callsign = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'KK7ABC',
      );
      await tester.enterText(callsign, 'KK7VZT7');
      await tester.pump();
      expect(find.text('KK7VZT-7'), findsOneWidget);
      final stationId = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<int> &&
            widget.key == const ValueKey(7),
      );
      expect(stationId, findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'KK7VZT-7'),
        'KK7VZT15',
      );
      await tester.pump();
      expect(find.text('KK7VZT-15'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<int> &&
              widget.key == const ValueKey(15),
        ),
        findsOneWidget,
      );

      final tabs = find.byType(Tab);
      final count = tabs.evaluate().length;
      for (var i = 0; i < count; i++) {
        await tester.tap(tabs.at(i), warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'tab index $i');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
