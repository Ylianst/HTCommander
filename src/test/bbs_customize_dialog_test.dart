/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/bbs_customize_dialog.dart';
import 'package:htcommander/handlers/bbs_files.dart';
import 'package:htcommander/handlers/bbs_settings.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';

void main() {
  setUp(DataBroker.reset);
  tearDown(DataBroker.reset);

  for (final brightness in Brightness.values) {
    testWidgets('customization tiles render and save in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showBbsCustomizeDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      Future<void> toggle(String label) async {
        final tile = find.widgetWithText(SwitchListTile, label);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> selectTab(String label) async {
        await tester.tap(find.widgetWithText(Tab, label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await toggle('Enable announcement');
      await selectTab('Files');
      await toggle('Allow stations to upload files to the BBS');
      await selectTab('Games');
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Guess the number'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await toggle('Enable games');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Guess the number'),
            )
            .onChanged,
        isNull,
      );
      await selectTab('APRS');
      await toggle('Enable APRS messages');
      await toggle('Enable APRS station lookup');
      await toggle('Enable list of heard APRS stations');
      await selectTab('Winlink');
      await toggle('Act as a Winlink gateway');
      await selectTab('Access');
      final field = find.widgetWithText(TextField, 'Callsign');
      await tester.enterText(field, 'ABC');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      expect(find.text('Enter a valid callsign'), findsOneWidget);
      await tester.enterText(field, 'n1abc-7');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'N1ABC-7'), findsOneWidget);
      await tester.tap(find.text('Only stations on the allow list'));
      await tester.pumpAndSettle();
      expect(find.text('Allow List'), findsOneWidget);
      expect(find.text('No stations'), findsOneWidget);
      await tester.enterText(field, 'W1AW');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'W1AW'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BbsCustomizeDialog), findsNothing);

      final settings = BbsSettings.load();
      expect(settings.announcementEnabled, isTrue);
      expect(settings.gamesEnabled, isFalse);
      expect(settings.disabledGames, contains('GUESS'));
      expect(settings.aprsMessagesEnabled, isFalse);
      expect(settings.aprsLookupEnabled, isTrue);
      expect(settings.aprsHeardEnabled, isTrue);
      expect(settings.winlinkGatewayEnabled, isFalse);
      expect(settings.allowListOnly, isTrue);
      expect(settings.allowedStations, ['W1AW']);
      expect(settings.deniedStations, ['N1ABC-7']);
      expect(DataBroker.getValue<int>(0, BbsFileStore.uploadsSetting), 0);
    });
  }
}
