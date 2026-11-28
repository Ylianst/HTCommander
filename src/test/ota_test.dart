import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_link_policy.dart';
import 'package:htcommander/aprs/aprs_outbox.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprs/ota.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/widgets/aprs_tab.dart';
import 'package:htcommander/widgets/chat_widget.dart';
import 'package:htcommander/widgets/contact_avatar.dart';
import 'package:htcommander/widgets/ota_conversation_panel.dart';

void main() {
  test(
    'machine replies preserve nulls, records, descriptions and extensions',
    () {
      final cq = decodeOtaReply('CQ! 2/2 3 K7ABC-6 _ 22')!;
      expect(cq.page, 2);
      expect(cq.ops.single.grid, isNull);
      expect(cq.ops.single.minutes, 22);
      final info = decodeOtaReply(
        'INFO! K7ABC-6 DN40fb 22 5 3 5 40.0542 -111.5250 future',
      )!;
      expect(info.ops.single.qsos, 5);
      expect(info.ops.single.waiting, 3);
      expect(info.ops.single.longitude, -111.5250);
      expect(
        decodeOtaReply('INFO! K7ABC-6 _ _ 5 3 5 _ _')!.ops.single.minutes,
        isNull,
      );
      expect(decodeOtaReply('INFO! K7ABC NIL')!.kind, OtaReplyKind.missing);
      expect(
        decodeOtaReply('INFO! K7ABC-6 DESC QSL from the trail')!.text,
        'QSL from the trail',
      );
      expect(decodeOtaReply('TIME! 22 82 extra')!.cap, 82);
      expect(decodeOtaReply('CHASERS! 1/1 2 W1XYZ-5 N0CALL-7')!.stations, [
        'W1XYZ-5',
        'N0CALL-7',
      ]);
      expect(decodeOtaReply('CQ! 1/1 0')!.ops, isEmpty);
      expect(
        decodeOtaReply('CQ! 1/1 1 K7ABC-6 DN40fb 22 99 100 101')!.ops,
        hasLength(1),
      );
      for (final invalid in [
        'CQ! 2/1 1 K7ABC-6 DN40fb 22',
        'CQ! 1/1 1 K7ABC-6 DN40fb',
        'CQ! 1/1 1 K7ABC-16 DN40fb 22',
        'CQ! 1/1 1 K7ABC-6 ZZ40fb 22',
        'INFO! K7ABC-6 DN40fb 22 5 3 5 91 -111',
        'INFO! K7ABC-6 DN40fb 22 5 3 5 _ 1',
        'TIME! 82 22',
        'CHASERS! 1/1 1 W1XYZ-5 N0CALL-7',
        'here is DE K7ABC-6 QSL hi',
      ]) {
        expect(decodeOtaReply(invalid), isNull, reason: invalid);
      }
    },
  );

  test('chase relays and confirmations cannot be confused by free text', () {
    expect(
      decodeOtaReply('DE W1XYZ-5 DN40fb QSL please')!.kind,
      OtaReplyKind.pendingQsl,
    );
    expect(
      decodeOtaReply('DE K7ABC-6 QSL thanks')!.kind,
      OtaReplyKind.confirmed,
    );
    expect(
      decodeOtaReply(
        'Send a position report within 5 mins to chase K7ABC-6',
      )!.kind,
      OtaReplyKind.beaconChase,
    );
    expect(
      decodeOtaReply(
        'Now chasing K7ABC-6 DN40fb. aprsota.org/K7ABC/ops/3',
      )!.link,
      Uri.parse('https://aprsota.org/K7ABC/ops/3'),
    );
  });

  test('paging handles reordering, duplicates, conflicts and new windows', () {
    final pages = OtaPages();
    final time = DateTime(2026);
    void add(String reply, int seconds) => pages.add(
      OtaReceived(decodeOtaReply(reply)!, time.add(Duration(seconds: seconds))),
    );
    add('CQ! 2/2 2 W1XYZ-5 DN40fb 22', 0);
    add('CQ! 1/2 2 K7ABC-6 DN40fb 12', 1);
    add('CQ! 1/2 2 K7ABC-6 DN40fb 12', 2);
    expect(pages.received.map((r) => r.reply.page), [1, 2]);
    expect(pages.ambiguous, isFalse);
    add('CQ! 1/2 2 N0CALL-7 DN40fb 12', 3);
    expect(pages.ambiguous, isTrue);
    add('CQ! 1/1 0', 181);
    expect(pages.ambiguous, isFalse);
    expect(pages.received, hasLength(1));
  });

  test('OTA commands stay single-part at actual byte boundaries', () {
    validateOtaCommand('PING ${'a' * 62}');
    validateOtaCommand('PING ${'a' * 55}', authenticated: true);
    for (final (text, auth) in [
      ('PING ${'a' * 63}', false),
      ('PING ${'a' * 56}', true),
    ]) {
      expect(
        () => validateOtaCommand(text, authenticated: auth),
        throwsA(
          isA<AprsComposeException>().having(
            (e) => e.reason,
            'reason',
            AprsComposeError.tooLong,
          ),
        ),
      );
    }
    expect(otaCommandRequiresRf('QRV trail'), isTrue);
    expect(otaCommandRequiresRf('@W1XYZ-5 QSL 73'), isTrue);
    expect(otaCommandRequiresRf('CHASE K7ABC'), isFalse);
    expect(isOtaPeer(' ota-0 '), isTrue);
    expect(isOtaPeer('OTA-7'), isFalse);
    expect(autoContactLogo('OTA'), 'radio');
    expect(contactLogoIcon('OTA', 'star'), kContactLogos['star']);
    expect(autoContactLogo('OTA-7'), isNull);
  });

  test('human and machine commands share an operator-wide local cooldown', () {
    final now = DateTime(2026);
    final sent = AprsOutgoingMessage(
      id: 'query',
      source: 'N0CALL-9',
      destination: 'OTA',
      text: 'CQ',
      created: now.subtract(const Duration(seconds: 30)),
      radioDeviceId: -1,
      linkPolicy: AprsLinkPolicy.internetOnly,
      authenticated: false,
      parts: const [],
    );
    expect(
      otaCommandCooldown('CQ!', [sent], 'N0CALL-7', now),
      const Duration(seconds: 150),
    );
    expect(otaCommandCooldown('INFO!', [sent], 'N0CALL', now), Duration.zero);
  });

  group('OTA conversation', () {
    setUp(DataBroker.reset);
    tearDown(DataBroker.reset);

    Widget app() => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: AprsTab()),
    );

    void setting(String name, Object data, {int device = 0}) =>
        DataBroker.dispatch(deviceId: device, name: name, data: data);

    void packet(String sender, String text, {String addressee = 'N0CALL-7'}) {
      final ax = Tnc2Codec.decode(
        '$sender>APRS::${addressee.padRight(9)}:$text',
      )!;
      ax.time = DateTime.now();
      final aprs = AprsPacket.parse(ax)!;
      DataBroker.dispatch(
        deviceId: 1,
        name: 'AprsFrame',
        data: AprsFrameEventArgs(aprs, ax, null),
        store: false,
      );
    }

    void open(String peer) => DataBroker.dispatch(
      deviceId: 1,
      name: 'AprsOpenConversation',
      data: peer,
      store: false,
    );

    testWidgets(
      'tools exist only in OTA, keep raw chat and prepare without sending',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setting('CallSign', 'N0CALL');
        setting('StationId', 7);
        setting('AprsIsEnabled', 1);
        final requests = <AprsSendMessageData>[];
        final bus = DataBrokerClient();
        addTearDown(bus.dispose);
        bus.subscribe(
          deviceId: 1,
          name: 'SendAprsMessage',
          callback: (_, _, data) {
            if (data is AprsSendMessageData) requests.add(data);
          },
        );
        await tester.pumpWidget(app());
        expect(find.byType(OtaConversationPanel), findsNothing);
        packet('OTA', 'CQ! 1/1 1 K7ABC-6 DN40fb 22');
        packet('OTA', 'CQ! 1/1 1 W1AW DN40fb 22', addressee: 'OTHER');
        open('OTA-0');
        await tester.pump();
        expect(find.byType(OtaConversationPanel), findsOneWidget);
        expect(
          tester
              .widget<ChatWidget>(find.byType(ChatWidget))
              .messages
              .single
              .message,
          'CQ! 1/1 1 K7ABC-6 DN40fb 22',
        );
        await tester.tap(find.text('Find ops'));
        await tester.pumpAndSettle();
        expect(requests, isEmpty);
        await tester.tap(find.text('Use command'));
        await tester.pumpAndSettle();
        final composer = find.byType(TextField).last;
        expect(tester.widget<TextField>(composer).controller!.text, 'CQ!');
        await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.send));
        await tester.pump();
        expect(requests.single.destination, 'OTA');
        expect(requests.single.message, 'CQ!');
        DataBroker.dispatch(
          deviceId: 1,
          name: 'AprsMessageQueued',
          data: requests.single.toJson(),
          store: false,
        );
        open('W1AW');
        await tester.pump();
        expect(find.byType(OtaConversationPanel), findsNothing);
        open('OTA-7');
        await tester.pump();
        expect(find.byType(OtaConversationPanel), findsNothing);
        DataBroker.dispatch(
          deviceId: 1,
          name: 'AprsShowContactList',
          data: null,
          store: false,
        );
        await tester.pump();
        await tester.tap(find.text('All APRS Messages').first);
        await tester.pump();
        expect(find.byType(OtaConversationPanel), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'HOST never falls back to internet and long commands keep their draft',
      (tester) async {
        setting('CallSign', 'N0CALL');
        setting('StationId', 7);
        setting('AprsIsEnabled', 1);
        await tester.pumpWidget(app());
        open('OTA');
        await tester.pump();
        final input = find.byType(TextField).last;
        await tester.enterText(input, 'HOST from the trail');
        await tester.pump();
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithIcon(ElevatedButton, Icons.send),
              )
              .onPressed,
          isNull,
        );
        expect(find.byTooltip('RF only'), findsOneWidget);
        await tester.enterText(input, 'PING ${'a' * 63}');
        await tester.pump();
        await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.send));
        await tester.pump();
        expect(find.textContaining('OTA commands must fit'), findsOneWidget);
        expect(tester.widget<TextField>(input).controller!.text.length, 68);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('HOST and QSL use the existing outbox with RF-only requests', (
      tester,
    ) async {
      setting('CallSign', 'N0CALL');
      setting('StationId', 7);
      setting('AprsIsEnabled', 1);
      setting('ConnectedRadios', [
        {'DeviceId': 42},
      ], device: 1);
      setting('AllChannelsLoaded', true, device: 42);
      setting('State', 'Connected', device: 42);
      setting('Channels', [
        {'channelId': 7, 'name': 'APRS'},
      ], device: 42);
      final bus = DataBrokerClient();
      addTearDown(bus.dispose);
      final requests = <AprsSendMessageData>[];
      bus.subscribe(
        deviceId: 1,
        name: 'SendAprsMessage',
        callback: (_, _, data) {
          if (data is AprsSendMessageData) requests.add(data);
        },
      );
      await tester.pumpWidget(app());
      open('OTA');
      await tester.pump();
      final input = find.byType(TextField).last;
      for (final command in ['HOST trail', '@W1XYZ-5 QSL thanks']) {
        await tester.enterText(input, command);
        await tester.pump();
        await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.send));
        await tester.pump();
        expect(requests.last.destination, 'OTA');
        expect(requests.last.policy, AprsLinkPolicy.rfOnly);
        expect(requests.last.radioDeviceId, 42);
        expect(requests.last.message, command);
        bus.dispatch(
          deviceId: 1,
          name: 'AprsMessageQueued',
          data: requests.last.toJson(),
          store: false,
        );
        await tester.pump();
      }
      expect(requests, hasLength(2));
      open('W1AW');
      await tester.pump();
      expect(find.byTooltip('Automatic'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'decoded details and progress do not replace the raw messages',
      (tester) async {
        setting('CallSign', 'N0CALL');
        setting('StationId', 7);
        await tester.pumpWidget(app());
        packet('OTA', 'INFO! K7ABC-6 DESC Lakeshore op');
        packet('OTA', 'INFO! K7ABC-6 DN40fb 22 5 3 5 40.0542 -111.5250');
        packet('OTA', 'Send a position report within 5 mins to chase K7ABC-6');
        packet('OTA', 'Now chasing K7ABC-6 DN40fb. aprsota.org/K7ABC/ops/3');
        packet('OTA', 'DE K7ABC-6 QSL thanks');
        open('OTA');
        await tester.pump();
        expect(find.text('5 QSOs, 3 awaiting QSL, 5 points'), findsOneWidget);
        expect(find.text('Lakeshore op'), findsOneWidget);
        expect(find.text('QSO confirmed by K7ABC-6'), findsOneWidget);
        expect(find.textContaining('waiting for host QSL'), findsNothing);
        expect(find.textContaining('Waiting for position'), findsNothing);
        expect(
          tester.widget<ChatWidget>(find.byType(ChatWidget)).messages,
          hasLength(5),
        );
        setting('CallSign', 'W1AW');
        await tester.pump();
        expect(find.text('QSO confirmed by K7ABC-6'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a confirmed host gets a manual QSL queue and a DONE warning', (
      tester,
    ) async {
      setting('CallSign', 'N0CALL');
      setting('StationId', 7);
      await tester.pumpWidget(app());
      packet('OTA', 'N0CALL-7 is on the air from DN40fb. aprsota.org/N0CALL');
      packet('OTA', 'CHASERS! 2/2 2 W1XYZ-5');
      packet('OTA', 'CHASERS! 1/2 2 K7ABC-6');
      packet('OTA', 'CHASERS! 1/2 2 K7ABC-6');
      open('OTA');
      await tester.pump();
      expect(find.text('Hosting: N0CALL-7'), findsNWidgets(2));
      expect(
        find.text('2/2 pages received; showing 2/2 stations'),
        findsOneWidget,
      );
      expect(find.text('K7ABC-6'), findsOneWidget);
      expect(find.text('W1XYZ-5'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'QSL'), findsNWidgets(2));
      final end = find.text('End op');
      await tester.ensureVisible(end);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('every DONE ends your own op'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      packet('OTA', 'Op complete: 2 QSOs, 3 pts. aprsota.org/N0CALL');
      await tester.pump();
      expect(find.text('End op'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
