import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_util.dart';
import 'package:htcommander/dialogs/tips_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/winlink/mail_store.dart';
import 'package:htcommander/winlink/winlink_mail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(DataBroker.reset);
  tearDown(DataBroker.reset);

  void set(String name, Object? value) =>
      DataBroker.dispatch(deviceId: 0, name: name, data: value);

  Future<void> open(
    WidgetTester tester, {
    Future<void> Function(String)? onOpenSettings,
    void Function(String)? onOpenTab,
    Locale? locale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => TipsDialog(
                  onOpenSettings: onOpenSettings ?? (_) async {},
                  onOpenTab: onOpenTab ?? (_) {},
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  final done = find.text('Done');

  testWidgets('first tip links to License and reflects saved configuration', (
    tester,
  ) async {
    String? openedTab;
    await open(
      tester,
      onOpenSettings: (tab) async {
        openedTab = tab;
        set('CallSign', 'KK7ABC');
        set('StationId', 15);
        set('AllowTransmit', 1);
      },
    );
    expect(find.text("Unlock HTCommander's transmit features"), findsOneWidget);
    expect(done, findsNothing);
    expect(TipsDialog.showOnStart, isTrue);
    await tap(tester, 'Open Settings / License');
    expect(openedTab, 'License');
    expect(done, findsOneWidget);
    expect(find.text('Tip #1'), findsOneWidget);
    expect(find.text('Tip 1 of 14'), findsNothing);
    expect(
      tester.getCenter(done).dy,
      closeTo(tester.getCenter(find.text('Tip #1')).dy, 1),
    );
    expect(
      tester.getCenter(done).dx,
      greaterThan(tester.getCenter(find.text('Tip #1')).dx),
    );
    expect(
      tester.getCenter(find.text('Show on start')).dy,
      closeTo(tester.getCenter(find.text('Next')).dy, 1),
    );
    expect(
      tester.getCenter(find.text('Show on start')).dx,
      lessThan(tester.getCenter(find.text('Previous')).dx),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_box)).color,
      Colors.green,
    );
    set('StationId', 16);
    await tester.pump();
    expect(done, findsNothing);
    set('StationId', 0);
    set('AllowTransmit', 0);
    await tester.pump();
    expect(done, findsNothing);
  });

  testWidgets('navigation wraps and subsequent openings advance', (
    tester,
  ) async {
    await open(tester);
    expect(DataBroker.getValue<String>(0, 'TipsNextId'), 'winlink');
    await tap(tester, 'Previous');
    expect(DataBroker.getValue<String>(0, 'TipsNextId'), 'license');
    expect(find.text('See what is happening on the air'), findsOneWidget);
    await tap(tester, 'Next');
    expect(find.text("Unlock HTCommander's transmit features"), findsOneWidget);
    await tap(tester, 'Close');
    expect(DataBroker.getValue<String>(0, 'TipsNextId'), 'winlink');
    await tap(tester, 'Open');
    expect(find.text('Set up Winlink email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup preference and manual completion survive reopening', (
    tester,
  ) async {
    set('TipsNextId', 'weather');
    await open(tester);
    final completion = find.byKey(const ValueKey('tipCompletion'));
    expect(tester.widget<Checkbox>(completion).value, isFalse);
    expect(
      tester.getCenter(find.text('Todo')).dy,
      closeTo(tester.getCenter(find.text('Tip #10')).dy, 1),
    );
    expect(
      tester.getCenter(completion).dx,
      greaterThan(tester.getCenter(find.text('Tip #10')).dx),
    );
    await tap(tester, 'Show on start');
    expect(TipsDialog.showOnStart, isFalse);
    await tap(tester, 'Todo');
    expect(done, findsOneWidget);
    expect(find.text('Todo'), findsNothing);
    expect(tester.widget<Checkbox>(completion).value, isTrue);
    await tap(tester, 'Close');
    await tap(tester, 'Open');
    await tap(tester, 'Previous');
    expect(find.text('Get a weather report using APRS'), findsOneWidget);
    expect(done, findsOneWidget);
    expect(TipsDialog.showOnStart, isFalse);
    await tester.tap(completion);
    await tester.pumpAndSettle();
    expect(done, findsNothing);
    expect(find.text('Todo'), findsOneWidget);
    expect(tester.widget<Checkbox>(completion).value, isFalse);
    await tap(tester, 'Close');
    expect(tester.takeException(), isNull);
  });

  testWidgets('APRS completion requires a correct passcode', (tester) async {
    set('TipsNextId', 'aprsIs');
    set('CallSign', 'KK7ABC');
    set('AprsIsEnabled', 1);
    set('AprsIsPasscode', '-1');
    await open(tester);
    expect(done, findsNothing);
    set('AprsIsPasscode', AprsUtil.aprsValidationCode('KK7ABC'));
    await tester.pump();
    expect(done, findsOneWidget);
    await tap(tester, 'Next');
    expect(done, findsNothing);
    set('AprsCloudNotifications', 1);
    await tester.pump();
    expect(done, findsOneWidget);
    set('AprsIsEnabled', 0);
    await tester.pump();
    expect(done, findsNothing);
  });

  testWidgets('Winlink completion and mail shortcut require transmit setup', (
    tester,
  ) async {
    set('TipsNextId', 'winlink');
    set('WinlinkPassword', 'test-password');
    await open(tester);
    expect(done, findsNothing);
    set('CallSign', 'KK7ABC');
    set('AllowTransmit', 1);
    await tester.pump();
    expect(done, findsOneWidget);
    await tap(tester, 'Close');
    set('TipsNextId', 'firstMail');
    await tap(tester, 'Open');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Open Mail'))
          .onPressed,
      isNotNull,
    );
    set('AllowTransmit', 0);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Open Mail'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('first email tip follows messages in the Sent mailbox', (
    tester,
  ) async {
    final store = MailStore();
    expect(DataBroker.addDataHandler('MailStore', store), isTrue);
    addTearDown(store.dispose);
    final mail = WinLinkMail()
      ..mid = 'first-email'
      ..mailbox = 'Sent';
    store.addMail(mail);
    set('TipsNextId', 'firstMail');
    set('TipDone.firstMail', true);
    await open(tester);
    expect(done, findsOneWidget);
    expect(find.byKey(const ValueKey('tipCompletion')), findsNothing);

    void notify() => DataBroker.dispatch(
      deviceId: 0,
      name: 'MailsChanged',
      data: null,
      store: false,
    );

    store.deleteMail(mail.mid!);
    notify();
    await tester.pump();
    expect(done, findsNothing);

    mail.mailbox = 'Outbox';
    store.addMail(mail);
    store.addMail(WinLinkMail()..mid = 'received-email');
    notify();
    await tester.pump();
    expect(done, findsNothing);

    mail.mailbox = 'Sent';
    store.updateMail(mail);
    notify();
    await tester.pump();
    expect(done, findsOneWidget);
  });

  testWidgets('all tips fit a small screen and unknown saved IDs reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    set('TipsNextId', 'removed-tip');
    await open(tester);
    expect(find.text("Unlock HTCommander's transmit features"), findsOneWidget);
    for (var i = 0; i < 14; i++) {
      await tap(tester, 'Next');
      expect(tester.takeException(), isNull, reason: 'tip $i');
    }
    await tap(tester, 'Close');
    expect(tester.takeException(), isNull);
  });

  testWidgets('speech completion follows recognizer readiness and preference', (
    tester,
  ) async {
    set('TipsNextId', 'speech');
    await open(tester);
    expect(done, findsNothing);
    DataBroker.dispatch(
      deviceId: 1,
      name: 'CommsHandlerState',
      data: {'engineReady': true},
    );
    await tester.pump();
    expect(done, findsOneWidget);
    set('SpeechToTextEnabled', false);
    await tester.pump();
    expect(done, findsNothing);
  });

  testWidgets('feature shortcut selects its tab and closes Tips', (
    tester,
  ) async {
    set('TipsNextId', 'contacts');
    String? selectedTab;
    await open(tester, onOpenTab: (tab) => selectedTab = tab);
    await tap(tester, 'Open Contacts');
    expect(selectedTab, 'Contacts');
    expect(find.byType(TipsDialog), findsNothing);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    if (locale.languageCode == 'en') continue;
    testWidgets('compact Tips layout supports ${locale.languageCode}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = await AppLocalizations.delegate.load(locale);
      set('TipsNextId', 'weather');
      await open(tester, locale: locale);
      expect(find.text(l10n.tipsPosition(10)), findsOneWidget);
      expect(find.text(l10n.tipsTodo), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, l10n.tipsTodo);
      expect(find.text(l10n.tipsDone), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, l10n.tipsPrevious);
      expect(find.text(l10n.tipsPosition(9)), findsOneWidget);
      expect(find.byKey(const ValueKey('tipCompletion')), findsNothing);
      expect(tester.takeException(), isNull);
      await tap(tester, l10n.commonClose);
    });
  }

  testWidgets('startup, next tip and completion are persisted to preferences', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await DataBroker.initialize();
    set('TipsNextId', 'weather');
    await open(tester);
    await tap(tester, 'Show on start');
    await tap(tester, 'Todo');
    await tap(tester, 'Close');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('databroker_TipsShowOnStart'), isFalse);
    expect(prefs.getBool('databroker_TipDone.weather'), isTrue);
    expect(prefs.getString('databroker_TipsNextId'), 'sms');
    DataBroker.reset();
    expect(TipsDialog.showOnStart, isFalse);
    expect(DataBroker.getValue<bool>(0, 'TipDone.weather'), isTrue);
    expect(DataBroker.getValue<String>(0, 'TipsNextId'), 'sms');
  });
}
