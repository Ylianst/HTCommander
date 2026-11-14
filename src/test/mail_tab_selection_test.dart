import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/mail_tab.dart';
import 'package:htcommander/winlink/winlink_mail.dart';

void main() {
  late DataBrokerClient probe;
  late List<Map> moves;
  late List<String> deletes;
  final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

  WinLinkMail mail(int n, String mailbox) => WinLinkMail()
    ..mid = 'MID$n'
    ..dateTime = DateTime(2026, 1, 1, 12, n)
    ..from = 'N0CALL$n@winlink.org'
    ..to = 'ME@winlink.org'
    ..subject = 'Subject $n'
    ..body = 'Body $n'
    ..mailbox = mailbox;

  Future<void> pumpTab(WidgetTester tester, List<WinLinkMail> mails) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: MailTab()),
      ),
    );
    probe.dispatch(deviceId: 0, name: 'MailList', data: mails, store: false);
    await tester.pump();
  }

  // The list row (the preview pane may show the same subject further down).
  Finder row(String subject) => find.text(subject).first;

  // Clicks a row and lets the double-tap window lapse so onTap fires.
  Future<void> click(WidgetTester tester, String subject) async {
    await tester.tap(row(subject), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> dragRowTo(
    WidgetTester tester,
    String subject,
    Finder target,
  ) async {
    final gesture = await tester.startGesture(
      tester.getCenter(row(subject)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  }

  setUp(() {
    moves = [];
    deletes = [];
    probe = DataBrokerClient();
    probe.subscribe(
      deviceId: 0,
      name: 'MailMove',
      callback: (_, _, data) => moves.add(data as Map),
    );
    probe.subscribe(
      deviceId: 0,
      name: 'MailDelete',
      callback: (_, _, data) => deletes.add(data as String),
    );
  });

  tearDown(() {
    probe.dispose();
    DataBroker.clearDevice(0);
    DataBroker.clearDevice(1);
  });

  testWidgets('Ctrl and Shift click select several mails', (tester) async {
    await pumpTab(tester, [for (var i = 1; i <= 5; i++) mail(i, 'Inbox')]);

    // Sorted newest first: Subject 5 .. Subject 1.
    await click(tester, 'Subject 5');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await click(tester, 'Subject 3');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.text('3 messages selected'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await click(tester, 'Subject 1');
    await click(tester, 'Subject 4');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(find.text('3 messages selected'), findsOneWidget);

    await tester.tap(find.text('Move to Archive'));
    await tester.pump();
    expect(moves.map((m) => m['MID']).toSet(), {'MID5', 'MID3', 'MID1'});
    expect(moves.every((m) => m['Mailbox'] == 'Archive'), isTrue);

    // A plain click collapses back to a single selection.
    await click(tester, 'Subject 2');
    expect(find.textContaining('messages selected'), findsNothing);
  }, variant: desktop);

  testWidgets('dragging a selection onto a mailbox moves it', (tester) async {
    await pumpTab(tester, [for (var i = 1; i <= 3; i++) mail(i, 'Inbox')]);

    await click(tester, 'Subject 3');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await click(tester, 'Subject 2');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await dragRowTo(tester, 'Subject 2', find.text('Trash'));
    expect(moves.map((m) => m['MID']).toSet(), {'MID3', 'MID2'});
    expect(moves.every((m) => m['Mailbox'] == 'Trash'), isTrue);
  }, variant: desktop);

  testWidgets('dragging an unselected row moves only that row', (tester) async {
    await pumpTab(tester, [for (var i = 1; i <= 3; i++) mail(i, 'Inbox')]);

    await click(tester, 'Subject 3');
    await dragRowTo(tester, 'Subject 1', find.text('Archive'));
    expect(moves, [
      {'MID': 'MID1', 'Mailbox': 'Archive'},
    ]);
  }, variant: desktop);

  testWidgets('context menu Move To submenu moves the selection', (
    tester,
  ) async {
    await pumpTab(tester, [for (var i = 1; i <= 3; i++) mail(i, 'Inbox')]);

    await click(tester, 'Subject 3');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await click(tester, 'Subject 1');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    await tester.tap(
      row('Subject 1'),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    // Multi-selection: single-mail actions are hidden.
    expect(find.text('Reply'), findsNothing);

    await tester.tap(find.widgetWithText(SubmenuButton, 'Move To'));
    await tester.pumpAndSettle();
    final submenu = find.byType(MenuItemButton);
    // Received mail can't go to Outbox/Draft, nor to its own mailbox.
    expect(find.widgetWithText(MenuItemButton, 'Outbox'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, 'Inbox'), findsNothing);
    expect(submenu, findsWidgets);

    await tester.tap(find.widgetWithText(MenuItemButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(moves.map((m) => m['MID']).toSet(), {'MID3', 'MID1'});
    expect(moves.every((m) => m['Mailbox'] == 'Archive'), isTrue);
  }, variant: desktop);

  testWidgets('received mail cannot be dropped into the Outbox', (
    tester,
  ) async {
    await pumpTab(tester, [mail(1, 'Inbox')]);
    await click(tester, 'Subject 1');
    await dragRowTo(tester, 'Subject 1', find.text('Outbox'));
    expect(moves, isEmpty);
  }, variant: desktop);

  testWidgets('a sync started before the tab was built shows its status', (
    tester,
  ) async {
    probe.dispatch(deviceId: 1, name: 'WinlinkBusy', data: true);
    probe.dispatch(
      deviceId: 1,
      name: 'WinlinkStateMessage',
      data: 'Connecting to KG4MRA-10 via radio...',
    );
    await pumpTab(tester, [mail(1, 'Inbox')]);

    expect(find.text('Connecting to KG4MRA-10 via radio...'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    final connect = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Connect'),
    );
    expect(connect.onPressed, isNull);

    probe.dispatch(deviceId: 1, name: 'WinlinkBusy', data: false);
    probe.dispatch(deviceId: 1, name: 'WinlinkStateMessage', data: null);
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Connect'),
          )
          .onPressed,
      isNotNull,
    );
  }, variant: desktop);

  testWidgets('Ctrl+A then Delete in Trash permanently deletes all', (
    tester,
  ) async {
    await pumpTab(tester, [mail(1, 'Trash'), mail(2, 'Trash')]);
    await tester.tap(find.text('Trash (2)'));
    await tester.pump();
    await click(tester, 'Subject 2');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('2 messages selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Permanently delete the 2 selected messages? This cannot be undone.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deletes.toSet(), {'MID1', 'MID2'});
  }, variant: desktop);
}
