/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// The BBS tab's traffic panel follows every BBS session live and can switch
// between them (radio, local terminal and web sessions alike).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/bbs_handler.dart';
import 'package:htcommander/handlers/bbs_monitor.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/widgets/bbs_tab.dart';

void main() {
  late BbsMonitor monitor;

  void say(int deviceId, String call, String message, {bool out = false}) {
    DataBroker.dispatch(
      deviceId: 0,
      name: 'BbsTraffic',
      data: BbsTrafficData(
        deviceId: deviceId,
        callsign: call,
        outgoing: out,
        message: message,
      ),
      store: false,
    );
  }

  setUp(() {
    DataBroker.reset();
    monitor = BbsMonitor()..init();
    BbsMonitor.instance = monitor;
  });

  tearDown(() {
    monitor.dispose();
    BbsMonitor.instance = BbsMonitor();
    DataBroker.reset();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: BbsTab()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String trafficText(WidgetTester tester) => tester
      .widget<SelectableText>(find.byType(SelectableText))
      .textSpan!
      .toPlainText();

  Future<void> pick(WidgetTester tester, String item) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('switches between live sessions', (tester) async {
    // Traffic from before the tab opened comes from the history.
    monitor.sessionStarted(430, 'N1ABC', 'AX.25');
    say(430, 'N1ABC', 'M');
    await pumpTab(tester);
    expect(find.text('All sessions (1 active)'), findsOneWidget);
    expect(trafficText(tester), contains('N1ABC > M'));

    monitor.sessionStarted(0, 'W1AW', 'Web');
    monitor.sessionStarted(205, 'N0CALL', 'Local');
    say(0, 'W1AW', 'F');
    say(205, 'N0CALL', 'B');
    await tester.pump();
    expect(find.text('All sessions (3 active)'), findsOneWidget);
    expect(
      trafficText(tester),
      allOf(contains('W1AW > F'), contains('N0CALL > B')),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('N1ABC'), findsOneWidget);
    expect(find.textContaining('AX.25 ·'), findsOneWidget);
    expect(find.textContaining('Web ·'), findsOneWidget);
    expect(find.textContaining('Local ·'), findsOneWidget);
    await tester.tap(find.text('W1AW'));
    await tester.pumpAndSettle();

    expect(find.text('W1AW · Web'), findsOneWidget);
    var text = trafficText(tester);
    expect(text, contains('W1AW > F'));
    expect(text, isNot(contains('N1ABC')));
    expect(text, isNot(contains('N0CALL')));

    // New lines for the shown session appear; others mark it unread.
    say(0, 'W1AW', 'Files, 2:', out: true);
    say(430, 'N1ABC', 'L');
    await tester.pump();
    text = trafficText(tester);
    expect(text, contains('W1AW < Files, 2:'));
    expect(text, isNot(contains('N1ABC > L')));

    await pick(tester, 'N1ABC');
    expect(trafficText(tester), contains('N1ABC > L'));

    // An ended session stays readable until another one is picked.
    monitor.sessionEnded(430, 'N1ABC');
    await tester.pump();
    expect(find.text('N1ABC · AX.25 (ended)'), findsOneWidget);
    expect(trafficText(tester), contains('N1ABC > L'));

    await pick(tester, 'All Sessions');
    expect(find.text('All sessions (2 active)'), findsOneWidget);
    expect(trafficText(tester), contains('N0CALL > B'));
  });
}
