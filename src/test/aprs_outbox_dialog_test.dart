import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_link_policy.dart';
import 'package:htcommander/aprs/aprs_outbox.dart';
import 'package:htcommander/dialogs/aprs_outbox_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

AprsOutgoingMessage message(AprsDelivery state) => AprsOutgoingMessage(
  id: 'message-1',
  source: 'N0CALL-7',
  destination: 'W1AW',
  text: 'Test outgoing message',
  created: DateTime(2026, 11, 28),
  radioDeviceId: 100,
  linkPolicy: AprsLinkPolicy.rfOnly,
  authenticated: false,
  parts: [
    AprsOutboxPart(
      wireId: 1,
      text: 'Test outgoing message',
      state: state,
      attempts: 2,
      error: state == AprsDelivery.failed ? 'Transmit failed' : null,
    ),
  ],
);

void publish(AprsDelivery state) => DataBroker.dispatch(
  deviceId: 1,
  name: 'AprsOutbox',
  data: [message(state).toJson()],
);

Future<void> openDialog(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        ),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAprsOutboxDialog(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(DataBroker.reset);
  tearDown(DataBroker.reset);

  for (final brightness in Brightness.values) {
    testWidgets('delivery icons and labels update live in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      publish(AprsDelivery.queued);
      await openDialog(tester, brightness: brightness);
      final context = tester.element(find.byType(Dialog));
      final l10n = AppLocalizations.of(context);
      final colors = <AprsDelivery, Color>{};
      for (final state in AprsDelivery.values) {
        publish(state);
        await tester.pumpAndSettle();
        final status = aprsDeliveryLabel(l10n, state);
        final tooltip = find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == status,
        );
        expect(tooltip, findsOneWidget);
        final iconFinder = find.descendant(
          of: tooltip,
          matching: find.byType(Icon),
        );
        final icon = tester.widget<Icon>(iconFinder);
        expect(icon.color, isNotNull);
        colors[state] = icon.color!;
        expect(
          tester.getTopLeft(iconFinder).dx,
          lessThan(tester.getTopLeft(find.text('N0CALL-7 > W1AW')).dx),
        );
        expect(find.text(status), findsOneWidget);
        expect(find.text('Test outgoing message'), findsOneWidget);
        expect(
          find.text(
            '1/1: $status (2/6)'
            '${state == AprsDelivery.failed ? ' - Transmit failed' : ''}',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      expect(
        colors[AprsDelivery.queued],
        isNot(colors[AprsDelivery.delivered]),
      );
      expect(
        colors[AprsDelivery.failed],
        isNot(colors[AprsDelivery.delivered]),
      );
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  }

  testWidgets(
    'retry, stop and filled retry settings preserve broker commands',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      publish(AprsDelivery.failed);
      final bus = DataBrokerClient();
      addTearDown(bus.dispose);
      final commands = <String>[];
      for (final name in ['RetryAprsMessage', 'StopAprsMessage']) {
        bus.subscribe(
          deviceId: 1,
          name: name,
          callback: (_, name, data) {
            commands.add('$name:$data');
          },
        );
      }
      await openDialog(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(Dialog)));
      await tester.tap(find.text(l10n.aprsRetryResume));
      expect(commands, ['RetryAprsMessage:message-1']);
      expect(find.text(l10n.aprsStopRetries), findsNothing);
      publish(AprsDelivery.sent);
      await tester.pumpAndSettle();
      expect(find.text(l10n.aprsRetryResume), findsNothing);
      await tester.tap(find.text(l10n.aprsStopRetries));
      expect(commands.last, 'StopAprsMessage:message-1');

      final fields = find.byType(DropdownButtonFormField<int>);
      await tester.tap(fields.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();
      expect(DataBroker.getValue<int>(0, 'AprsRetryAttempts'), 4);
      await tester.tap(fields.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('60').last);
      await tester.pumpAndSettle();
      expect(DataBroker.getValue<int>(0, 'AprsRetrySeconds'), 60);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short narrow dialog scrolls settings and messages at large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DataBroker.dispatch(deviceId: 0, name: 'AprsRetrySeconds', data: 45);
      await openDialog(tester, textScale: 1.5);
      final l10n = AppLocalizations.of(tester.element(find.byType(Dialog)));
      await tester.scrollUntilVisible(
        find.text(l10n.aprsOutboxEmpty),
        150,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      publish(AprsDelivery.failed);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(l10n.aprsRetryResume),
        150,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.aprsRetryResume).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );
}
