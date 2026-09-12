/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/radio_connection_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';

void main() {
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
