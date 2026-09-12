/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/widgets/mail_compose_view.dart';

void main() {
  testWidgets('compose content scrolls in a keyboard-sized viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MailComposeView(isEdit: false, onSend: (_) {}, onExit: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(TextField).at(2);
    expect(tester.getSize(bodyField).height, greaterThanOrEqualTo(120));
    expect(find.text('Add Attachment').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Attachment').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
