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
  testWidgets('recipient fields format callsigns without changing emails', (
    tester,
  ) async {
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

    final to = find.byType(TextField).first;
    await tester.enterText(to, 'KK7VZT7');
    expect(tester.widget<TextField>(to).controller!.text, 'KK7VZT-7');
    await tester.enterText(to, 'KK7VZT-7@example.com');
    expect(
      tester.widget<TextField>(to).controller!.text,
      'KK7VZT7@example.com',
    );
    await tester.enterText(to, 'Mixed.Case@example.com;N1ABC15');
    expect(
      tester.widget<TextField>(to).controller!.text,
      'Mixed.Case@example.com;N1ABC-15',
    );

    await tester.tap(
      find.widgetWithText(
        TextButton,
        AppLocalizations.of(tester.element(to)).mailAddCc,
      ),
    );
    await tester.pumpAndSettle();
    final cc = find.byType(TextField).at(1);
    await tester.enterText(cc, 'KK7VZT7');
    expect(tester.widget<TextField>(cc).controller!.text, 'KK7VZT-7');
    expect(tester.takeException(), isNull);
  });

  testWidgets('message field fills available desktop height and resizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
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
    final formScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final initialHeight = tester.getSize(bodyField).height;
    expect(formScrollable.position.maxScrollExtent, 0);
    expect(initialHeight, greaterThan(400));
    expect(find.text('Add Attachment').hitTestable(), findsOneWidget);
    expect(
      tester.getBottomLeft(bodyField).dy,
      closeTo(
        tester
                .getTopLeft(
                  find
                      .ancestor(
                        of: find.text('Attachments'),
                        matching: find.byType(Row),
                      )
                      .first,
                )
                .dy -
            8,
        1,
      ),
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1200, 1100);
    await tester.pumpAndSettle();

    expect(tester.getSize(bodyField).height, closeTo(initialHeight + 200, 1));
    expect(formScrollable.position.maxScrollExtent, 0);
    expect(find.text('Add Attachment').hitTestable(), findsOneWidget);

    await tester.enterText(
      bodyField,
      List.generate(100, (index) => 'Message line $index').join('\n'),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(bodyField).height, closeTo(initialHeight + 200, 1));
    expect(formScrollable.position.maxScrollExtent, 0);
    expect(find.text('Add Attachment').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
      find.byType(CustomScrollView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Attachment').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
