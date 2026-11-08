import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/widgets/contacts_tab.dart';

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

  Future<void> pumpTab(WidgetTester tester) async {
    DataBroker.dispatch(
      deviceId: 0,
      name: 'Stations',
      data: [
        for (final callsign in ['K1AAA', 'K2BBB', 'K3CCC'])
          StationInfo(callsign: callsign).toJson(),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ContactsTab()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String callsign) async {
    await tester.tap(find.text(callsign));
    await tester.pump(const Duration(milliseconds: 400));
  }

  List<String> storedCallsigns() =>
      (DataBroker.getValueDynamic(0, 'Stations') as List)
          .map((station) => (station as Map)['Callsign'] as String)
          .toList();

  tearDown(() {
    DataBroker.clearDevice(0);
  });

  testWidgets(
    'Delete uses the Remove confirmation and cancel preserves contacts',
    (tester) async {
      await pumpTab(tester);
      await select(tester, 'K1AAA');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
      await tester.pumpAndSettle();
      final buttonPrompt = tester.widget<AlertDialog>(find.byType(AlertDialog));
      final promptText = (buttonPrompt.content! as Text).data;
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await select(tester, 'K1AAA');
      await select(tester, 'K1AAA');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(promptText!), findsOneWidget);
      expect(storedCallsigns(), ['K1AAA', 'K2BBB', 'K3CCC']);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(storedCallsigns(), ['K1AAA', 'K2BBB', 'K3CCC']);
    },
    variant: desktop,
  );

  testWidgets('Delete removes all selected contacts only after confirmation', (
    tester,
  ) async {
    await pumpTab(tester);
    await select(tester, 'K1AAA');
    await select(tester, 'K2BBB');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(storedCallsigns(), ['K1AAA', 'K2BBB', 'K3CCC']);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(storedCallsigns(), ['K3CCC']);
    expect(find.text('K1AAA'), findsNothing);
    expect(find.text('K2BBB'), findsNothing);
    expect(find.text('K3CCC'), findsOneWidget);
  }, variant: desktop);

  testWidgets('Delete does nothing without a selection', (tester) async {
    await pumpTab(tester);
    await select(tester, 'K1AAA');
    await select(tester, 'K1AAA');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(storedCallsigns(), ['K1AAA', 'K2BBB', 'K3CCC']);
  }, variant: desktop);

  testWidgets('Holding Delete does not reopen confirmation after cancel', (
    tester,
  ) async {
    await pumpTab(tester);
    await select(tester, 'K1AAA');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    expect(storedCallsigns(), ['K1AAA', 'K2BBB', 'K3CCC']);
  }, variant: desktop);
}
