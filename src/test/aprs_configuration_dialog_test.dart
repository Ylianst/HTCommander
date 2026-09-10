/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/aprs_configuration_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/radio/radio_models.dart';

void main() {
  testWidgets('accepts a three-decimal APRS frequency', (tester) async {
    AprsConfigurationResult? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAprsConfigurationDialog(
                context,
                channels: [RadioChannelInfo(channelId: 3, name: 'Test')],
              );
            },
            child: const Text('Configure'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '145.175');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result?.channelId, 3);
    expect(result?.frequencyMhz, 145.175);
  });
}
