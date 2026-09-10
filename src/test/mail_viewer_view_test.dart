/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/widgets/mail_viewer_view.dart';

void main() {
  testWidgets('long message body scrolls to the end', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final body = List.generate(
      40,
      (index) => 'Message line ${index + 1}',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MailViewerView(
            from: 'N0CALL',
            to: 'W1AW',
            cc: '',
            time: DateTime(2026, 9, 10, 12),
            subject: 'Long message',
            body: body,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(SingleChildScrollView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scrollable, matching: find.byType(Scrollable)),
        )
        .position;
    final bodyText = find.text(body);
    final viewportBottom = tester.getBottomRight(scrollable).dy;

    expect(position.maxScrollExtent, greaterThan(0));
    expect(tester.getBottomRight(bodyText).dy, greaterThan(viewportBottom));
    expect(tester.takeException(), isNull);

    await tester.drag(scrollable, const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(position.pixels, position.maxScrollExtent);
    expect(
      tester.getBottomRight(bodyText).dy,
      lessThanOrEqualTo(viewportBottom),
    );
    expect(tester.takeException(), isNull);
  });
}
