import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_link_policy.dart';
import 'package:htcommander/aprs/aprs_outbox.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprs/aprs_util.dart';
import 'package:htcommander/aprs/ota.dart';
import 'package:htcommander/callsign/callsign_database.dart';
import 'package:htcommander/callsign/callsign_record.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/dialogs/aprs_location_dialog.dart';
import 'package:htcommander/dialogs/aprs_weather_dialog.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/callsign_lookup_service.dart';
import 'package:htcommander/widgets/aprs_tab.dart';
import 'package:htcommander/widgets/chat_widget.dart';
import 'package:htcommander/widgets/contact_avatar.dart';
import 'package:htcommander/widgets/ota_message_body.dart';

void main() {
  test('Maidenhead maps use the subsquare center in both hemispheres', () {
    final center = AprsUtil.gridSquareToLatLon('QF44oo');
    final bounds = AprsUtil.gridSquareBounds('QF44oo');
    expect(bounds.south, closeTo(-35.4166666667, 1e-9));
    expect(bounds.north, closeTo(-35.375, 1e-9));
    expect(bounds.west, closeTo(149.1666666667, 1e-9));
    expect(bounds.east, closeTo(149.25, 1e-9));
    final first = AprsUtil.gridSquareBounds('AA00aa');
    final last = AprsUtil.gridSquareBounds('RR99xx');
    expect(first.south, -90);
    expect(first.west, -180);
    expect(last.north, closeTo(90, 1e-9));
    expect(last.east, closeTo(180, 1e-9));
    expect(center.latitude, closeTo(-35.3958333333, 1e-9));
    expect(center.longitude, closeTo(149.2083333333, 1e-9));
    expect(
      AprsUtil.latLonToGridSquare(center.latitude, center.longitude),
      'QF44OO',
    );
    for (final grid in ['DN40fb', 'AA00aa', 'RR99xx']) {
      final point = AprsUtil.gridSquareToLatLon(grid);
      expect(
        AprsUtil.latLonToGridSquare(point.latitude, point.longitude),
        grid.toUpperCase(),
      );
    }
    for (final grid in ['ZZ44oo', 'QF44yy', 'QF44', '_']) {
      expect(() => AprsUtil.gridSquareToLatLon(grid), throwsFormatException);
    }
  });

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
    expect(decodeOtaReply('DE W1XYZ-5 DN40fb QSL please')!.grid, 'DN40fb');
    expect(decodeOtaReply('DE W1XYZ-5 _ QSL please')!.grid, isNull);
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
    expect(autoContactLogo('OTA'), isNull);
    expect(contactLogoIcon('OTA', 'star'), kContactLogos['star']);
    expect(autoContactLogo('OTA-7'), isNull);
  });

  testWidgets(
    'OTA defaults to the bundled official avatar, preserving overrides',
    (tester) async {
      final image = base64Encode(
        (await rootBundle.load(
          'assets/images/aprs_ota.png',
        )).buffer.asUint8List(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const ContactAvatar(callsign: 'OTA'),
                const ContactAvatar(callsign: ' ota-0 '),
                const ContactAvatar(callsign: 'OTA', avatarIcon: 'star'),
                ContactAvatar(callsign: 'OTA', avatarImage: image),
                const ContactAvatar(callsign: 'OTA-7'),
                const ContactAvatar(callsign: 'WXBOT'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avatars = tester
          .widgetList<CircleAvatar>(find.byType(CircleAvatar))
          .toList();
      for (final avatar in avatars.take(2)) {
        expect(avatar.backgroundImage, isA<AssetImage>());
        expect(
          (avatar.backgroundImage! as AssetImage).assetName,
          'assets/images/aprs_ota.png',
        );
      }
      expect(avatars[2].backgroundImage, isNull);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(avatars[3].backgroundImage, isA<MemoryImage>());
      expect(avatars[4].backgroundImage, isNull);
      expect(avatars[5].backgroundImage, isNull);
      expect(find.byIcon(Icons.wb_cloudy), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
      'WXBOT forecasts prepare presets and send only from the composer',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setting('CallSign', 'N0CALL');
        setting('StationId', 7);
        setting('AprsIsEnabled', 1);
        setting('WxBotLocation', '94089');
        setting('WxBotTime', 10);
        setting('WxBotReport', 4);
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
        open('WXBOT-0');
        await tester.pump();
        final menu = find.byTooltip('Request Weather Report');
        expect(menu, findsOneWidget);
        expect(find.byTooltip('OTA commands'), findsNothing);
        final bounds = tester.getRect(menu);
        expect(bounds.size, const Size(40, 40));
        expect(
          bounds.right,
          lessThan(tester.getRect(find.byType(ChatWidget)).right - 72),
        );
        final composer = tester
            .widget<TextField>(find.byType(TextField).last)
            .controller!;
        await tester.enterText(find.byType(TextField).last, 'keep my draft');
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(
          find.byType(PopupMenuItem<AprsWeatherForecast>),
          findsNWidgets(4),
        );
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expect(
          find.text('Using this command will replace your current draft.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(composer.text, 'keep my draft');
        expect(requests, isEmpty);

        for (final (label, time, report, message) in [
          ('Today', 0, 0, '94089 today brief'),
          ('Tonight', 1, 0, '94089 tonight brief'),
          ('Tomorrow', 2, 0, '94089 tomorrow brief'),
          ('Full, More complete forecast, US only', 0, 1, '94089 today full'),
        ]) {
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          final fields = tester
              .widgetList<DropdownButtonFormField<int>>(
                find.byType(DropdownButtonFormField<int>),
              )
              .toList();
          expect(fields[0].initialValue, time);
          expect(fields[1].initialValue, report);
          expect(find.text('94089'), findsOneWidget);
          await tester.tap(find.text('Use command'));
          await tester.pumpAndSettle();
          expect(composer.text, message);
          expect(requests, isEmpty);
        }
        await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.send));
        await tester.pump();
        expect(requests.single.destination, 'WXBOT');
        expect(requests.single.message, '94089 today full');
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<PopupMenuItem<AprsWeatherForecast>>(
                find.byType(PopupMenuItem<AprsWeatherForecast>),
              )
              .every((item) => !item.enabled),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'weather tools are scoped to WXBOT and respect transmit settings',
      (tester) async {
        await tester.pumpWidget(app());
        final menu = find.byTooltip('Request Weather Report');
        expect(menu, findsNothing);
        for (final peer in ['W1AW', 'OTA', 'WXBOT-7']) {
          open(peer);
          await tester.pump();
          expect(menu, findsNothing);
        }
        open('wxbot');
        await tester.pump();
        expect(menu, findsOneWidget);
        setting('AllowTransmit', 0);
        await tester.pump();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final items = tester.widgetList<PopupMenuItem<AprsWeatherForecast>>(
          find.byType(PopupMenuItem<AprsWeatherForecast>),
        );
        expect(items, hasLength(4));
        expect(items.every((item) => !item.enabled), isTrue);
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tapAt(const Offset(10, 550));
        await tester.pumpAndSettle();
        DataBroker.dispatch(
          deviceId: 1,
          name: 'AprsShowContactList',
          data: null,
          store: false,
        );
        await tester.pump();
        await tester.tap(find.text('All APRS Messages').first);
        await tester.pump();
        expect(menu, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('weather dialog without a preset preserves saved options', (
      tester,
    ) async {
      setting('WxBotLocation', '94089');
      setting('WxBotTime', 3);
      setting('WxBotReport', 2);
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showAprsWeatherDialog(context),
                child: const Text('Open weather'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open weather'));
      await tester.pumpAndSettle();
      expect(find.text('Use command'), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, '94089 tomorrow night current');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'OTA awards get celebration icons without changing text or URL links',
      (tester) async {
        setting('CallSign', 'N0CALL');
        setting('StationId', 7);
        const award = 'You earned Bronze Envoy, 2026! aprsota.org/KK7VZT';
        await tester.pumpWidget(app());
        packet('OTA', award);
        packet('OTA', 'You earned another award!');
        packet('OTA', award, addressee: 'OTHER');
        packet('OTA', 'A notice: You earned an award');
        open('OTA');
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.celebration), findsNWidgets(2));
        final messages = tester
            .widget<ChatWidget>(find.byType(ChatWidget))
            .messages;
        final message = messages.firstWhere(
          (message) => message.message == award,
        );
        expect(message.message, award);
        expect(message.bodySpans, isNotNull);
        expect(
          message.bodySpans!.whereType<TextSpan>().any(
            (span) =>
                span.text == 'aprsota.org/KK7VZT' && span.recognizer != null,
          ),
          isTrue,
        );
        open('W1AW');
        packet('W1AW', award);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.celebration), findsNothing);
        open('OTA-7');
        packet('OTA-7', award);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.celebration), findsNothing);
        DataBroker.dispatch(
          deviceId: 1,
          name: 'AprsShowContactList',
          data: null,
          store: false,
        );
        await tester.pump();
        await tester.tap(find.text('All APRS Messages').first);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.celebration), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'CQ station icons fill CHASE and INFO without sending and stay scoped',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        setting('CallSign', 'N0CALL');
        setting('StationId', 7);
        setting('AprsIsEnabled', 1);
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
        const reply =
            'CQ! 1/1 3 VK2JKB-7 QF44oo 24 9W3FAB-9 OJ51co 41 DL7PJ-9 JN39jv 48';
        await tester.pumpWidget(app());
        packet('OTA', reply);
        open('OTA-0');
        await tester.pump();
        final body = find.byType(OtaCqMessageBody);
        expect(body, findsOneWidget);
        expect(
          find.descendant(of: body, matching: find.text('CQ! 1/1')),
          findsOneWidget,
        );
        expect(find.text('CQ! 1/1 3'), findsNothing);
        for (final minutes in [24, 41, 48]) {
          expect(
            find.descendant(
              of: body,
              matching: find.text('Approximately $minutes min left'),
            ),
            findsOneWidget,
          );
        }
        for (final icon in [
          Icons.flag_outlined,
          Icons.info_outline,
          Icons.location_on_outlined,
        ]) {
          expect(
            find.descendant(
              of: body,
              matching: find.widgetWithIcon(IconButton, icon),
            ),
            findsNWidgets(3),
          );
        }
        expect(
          find.descendant(of: body, matching: find.text('QF44oo')),
          findsNothing,
        );
        double? actionLeft;
        expect(
          find.descendant(of: body, matching: find.byType(TextButton)),
          findsNothing,
        );
        for (final station in ['VK2JKB-7', '9W3FAB-9', 'DL7PJ-9']) {
          final link = find.descendant(of: body, matching: find.text(station));
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          final input = tester.widget<TextField>(find.byType(TextField).last);
          final draft = input.controller!.text;
          await tester.tap(link);
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          expect(input.controller!.text, draft);
          expect(find.byType(AlertDialog), findsNothing);
          expect(requests, isEmpty);
          for (final (tooltip, command) in [
            ('Chase: $station', 'CHASE $station'),
            ('INFO! $station', 'INFO! $station'),
          ]) {
            final action = find.descendant(
              of: body,
              matching: find.byTooltip(tooltip),
            );
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(action).right,
              lessThan(tester.getRect(link).left),
            );
            if (tooltip.startsWith('Chase:')) {
              actionLeft ??= tester.getRect(action).left;
              expect(tester.getRect(action).left, closeTo(actionLeft, 1));
            }
            await tester.tap(action);
            await tester.pump(const Duration(milliseconds: 350));
            await tester.pumpAndSettle();
            expect(input.controller!.text, command);
            expect(input.controller!.selection.baseOffset, command.length);
            expect(input.focusNode!.hasFocus, isTrue);
            expect(find.byType(AlertDialog), findsNothing);
            expect(requests, isEmpty);
          }
          final minutes = {
            'VK2JKB-7': 24,
            '9W3FAB-9': 41,
            'DL7PJ-9': 48,
          }[station]!;
          final time = find.descendant(
            of: body,
            matching: find.text('Approximately $minutes min left'),
          );
          expect(
            tester.getRect(time).left,
            closeTo(tester.getRect(link).left, 1),
          );
          expect(
            tester.getRect(time).top,
            greaterThan(tester.getRect(link).bottom),
          );
        }
        expect(
          tester
              .widget<ChatWidget>(find.byType(ChatWidget))
              .messages
              .single
              .message,
          reply,
        );
        packet('OTA', 'CQ! 1/1 1 K7ABC-6 DN40fb');
        await tester.pump();
        expect(body, findsOneWidget);
        open('W1AW');
        packet('W1AW', reply);
        await tester.pump();
        expect(body, findsNothing);
        DataBroker.dispatch(
          deviceId: 1,
          name: 'AprsShowContactList',
          data: null,
          store: false,
        );
        await tester.pump();
        await tester.tap(find.text('All APRS Messages').first);
        await tester.pump();
        expect(body, findsNothing);
        expect(
          tester.widget<ChatWidget>(find.byType(ChatWidget)).messageBodyBuilder,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'CQ unknown grids disable location and large text fits narrow rows',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox(
                  width: 220,
                  child: OtaCqMessageBody(
                    reply: decodeOtaReply('CQ! 1/1 1 K7ABC-6 _ _')!,
                  ),
                ),
              ),
            ),
          ),
        );
        final icons = tester.widgetList<IconButton>(find.byType(IconButton));
        expect(icons, hasLength(3));
        expect(icons.every((button) => button.onPressed == null), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'CQ adds installed US and Canadian records inline, ignoring SSIDs',
      (tester) async {
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('htcommander-ota-license-'),
        ))!;
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') return root.path;
          throw MissingPluginException();
        });
        final service = CallsignLookupService.instance;
        addTearDown(() async {
          for (final source in CallsignDbSource.values) {
            await service.delete(source);
          }
          messenger.setMockMethodCallHandler(channel, null);
          await root.delete(recursive: true);
        });
        await tester.runAsync(() async {
          await File(
            '${root.path}\\${CallsignDbSource.us.fileName}',
          ).writeAsBytes(
            CallsignDatabase.build(const [
              CallsignRecord(
                callsign: 'K7ABC',
                name: 'Test US Operator',
                operatorClass: 'G',
                city: 'Seattle',
                state: 'WA',
              ),
              CallsignRecord(
                callsign: 'W1AW',
                name: 'Test US Club',
                city: 'Newington',
                state: 'CT',
              ),
            ]),
          );
          await File(
            '${root.path}\\${CallsignDbSource.canada.fileName}',
          ).writeAsBytes(
            CallsignDatabase.build(const [
              CallsignRecord(
                callsign: 'VE3ABC',
                name: 'Test Canadian Operator',
                qualifications: 'D',
                city: 'Ottawa',
                state: 'ON',
              ),
            ], flags: CallsignDatabase.flagCanada),
          );
          await service.init();
        });
        Widget body(double width) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: OtaCqMessageBody(
                reply: decodeOtaReply(
                  'CQ! 1/1 4 K7ABC-6 DN40fb 22 '
                  'W1AW FN31pr 30 VE3ABC-9 FN25dj 40 VK2JKB-7 QF44oo 24',
                )!,
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.pumpWidget(body(780));
          // This read queues behind the CQ rows' asynchronous database reads.
          await service.lookup('W1AW');
        });
        await tester.pumpAndSettle();
        for (final (station, summary) in [
          ('K7ABC-6', 'Test US Operator / Seattle, WA / General'),
          ('W1AW', 'Test US Club / Newington, CT'),
          ('VE3ABC-9', 'Test Canadian Operator / Ottawa, ON / Advanced'),
        ]) {
          expect(find.text(summary), findsOneWidget);
          expect(
            tester.getRect(find.text(summary)).left,
            greaterThan(tester.getRect(find.text(station)).right),
          );
        }
        expect(find.text('VK2JKB-7'), findsOneWidget);
        expect(find.byType(TextButton), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(body(220));
        await tester.pumpAndSettle();
        expect(
          find.text('Test Canadian Operator / Ottawa, ON / Advanced'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'CQ grids and INFO coordinates open maps with distinct positions',
      (tester) async {
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('htcommander-ota-map-'),
        ))!;
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'getApplicationSupportDirectory') {
                return root.path;
              }
              throw MissingPluginException();
            });
        addTearDown(() async {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          await root.delete(recursive: true);
        });
        setting('CallSign', 'N0CALL');
        setting('StationId', 7);
        await tester.pumpWidget(app());
        packet('OTA', 'CQ! 1/1 1 VK2JKB-7 QF44oo 24');
        open('OTA');
        await tester.pump();
        Future<void> checkMap(
          Finder link,
          double latitude,
          double longitude, {
          bool gridArea = false,
        }) async {
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          final dialog = tester.widget<AprsLocationDialog>(
            find.byType(AprsLocationDialog),
          );
          expect(dialog.latitude, closeTo(latitude, 1e-9));
          expect(dialog.longitude, closeTo(longitude, 1e-9));
          if (gridArea) {
            final polygon = tester
                .widget<PolygonLayer>(find.byType(PolygonLayer))
                .polygons
                .single;
            expect(polygon.points, hasLength(4));
            for (final (index, lat, lon) in [
              (0, -35.375, 149.16666666666666),
              (1, -35.375, 149.25),
              (2, -35.416666666666664, 149.25),
              (3, -35.416666666666664, 149.16666666666666),
            ]) {
              expect(polygon.points[index].latitude, closeTo(lat, 1e-9));
              expect(polygon.points[index].longitude, closeTo(lon, 1e-9));
            }
            expect(polygon.borderStrokeWidth, greaterThan(0));
          } else {
            expect(dialog.areaBounds, isNull);
            expect(find.byType(PolygonLayer), findsNothing);
          }
          final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
          expect(map.options.initialCenter.latitude, closeTo(latitude, 1e-9));
          expect(map.options.initialCenter.longitude, closeTo(longitude, 1e-9));
          final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
          expect(
            markers.markers.single.point.latitude,
            closeTo(latitude, 1e-9),
          );
          await tester.tap(
            find.descendant(
              of: find.byType(AprsLocationDialog),
              matching: find.widgetWithIcon(IconButton, Icons.close),
            ),
          );
          await tester.pumpAndSettle();
        }

        await checkMap(
          find.descendant(
            of: find.byType(OtaCqMessageBody),
            matching: find.widgetWithIcon(
              IconButton,
              Icons.location_on_outlined,
            ),
          ),
          -35.39583333333333,
          149.20833333333334,
          gridArea: true,
        );
        const info = 'INFO! VK2JKB-7 QF44oo 12 7 0 21 -35.3848 149.1985';
        packet('OTA', info);
        await tester.pumpAndSettle();
        final body = find.byType(OtaInfoMessageBody);
        expect(body, findsOneWidget);
        for (final label in [
          'Approximately 12 min left',
          'Confirmed QSOs: 7',
          'Awaiting QSL: 0',
          'Points: 21',
          'Position that started the op (not live)',
        ]) {
          expect(
            find.descendant(of: body, matching: find.text(label)),
            findsOneWidget,
          );
        }
        final coordinates = find.descendant(
          of: body,
          matching: find.widgetWithText(
            TextButton,
            'Latitude: -35.3848\nLongitude: 149.1985',
          ),
        );
        await checkMap(coordinates, -35.3848, 149.1985);
        expect(
          tester
              .widget<ChatWidget>(find.byType(ChatWidget))
              .messages
              .last
              .message,
          info,
        );
        packet('OTA', 'DE VK2JKB-7 QF44oo QSL please');
        await tester.pumpAndSettle();
        await checkMap(
          find.descendant(
            of: find.byType(OtaActivityMessageBody),
            matching: find.widgetWithText(TextButton, 'QF44oo'),
          ),
          -35.39583333333333,
          149.20833333333334,
          gridArea: true,
        );
        open('W1AW');
        packet('W1AW', info);
        await tester.pump();
        expect(find.byType(OtaInfoMessageBody), findsNothing);
        expect(find.byType(OtaActivityMessageBody), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('INFO handles null positions, descriptions and missing ops', (
      tester,
    ) async {
      setting('CallSign', 'N0CALL');
      setting('StationId', 7);
      await tester.pumpWidget(app());
      packet('OTA', 'INFO! VK2JKB-7 _ _ 7 0 21 _ _');
      packet('OTA', 'INFO! VK2JKB-7 DESC Test op');
      packet('OTA', 'INFO! W1AW NIL');
      open('OTA');
      await tester.pump();
      expect(find.byType(OtaInfoMessageBody), findsNWidgets(3));
      expect(find.text('No position reported'), findsOneWidget);
      expect(find.text('Details: Test op'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(OtaInfoMessageBody),
          matching: find.text('W1AW has no active op'),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, '_'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Latitude:'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
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
        expect(find.byTooltip('OTA commands'), findsNothing);
        packet('OTA', 'CQ! 1/1 1 K7ABC-6 DN40fb 22');
        packet('OTA', 'CQ! 1/1 1 W1AW DN40fb 22', addressee: 'OTHER');
        open('OTA-0');
        await tester.pump();
        expect(find.byTooltip('OTA commands'), findsOneWidget);
        expect(find.text('APRS OTA'), findsNothing);
        final menuBounds = tester.getRect(find.byTooltip('OTA commands'));
        expect(menuBounds.size, const Size(40, 40));
        expect(
          menuBounds.right,
          lessThan(tester.getRect(find.byType(ChatWidget)).right - 72),
        );
        expect(
          tester
              .widget<ChatWidget>(find.byType(ChatWidget))
              .messages
              .single
              .message,
          'CQ! 1/1 1 K7ABC-6 DN40fb 22',
        );
        await tester.tap(find.byTooltip('OTA commands'));
        await tester.pumpAndSettle();
        expect(find.text('Check setup'), findsOneWidget);
        await tester.tap(find.text('Find ops'));
        await tester.pumpAndSettle();
        expect(requests, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
        final composerController = tester
            .widget<TextField>(find.byType(TextField).last)
            .controller!;
        expect(composerController.text, 'CQ!');
        await tester.tap(find.byTooltip('OTA commands'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check setup'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('PING'), findsOneWidget);
        expect(composerController.text, 'CQ!');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
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
        expect(find.byTooltip('OTA commands'), findsNothing);
        open('OTA-7');
        await tester.pump();
        expect(find.byTooltip('OTA commands'), findsNothing);
        DataBroker.dispatch(
          deviceId: 1,
          name: 'AprsShowContactList',
          data: null,
          store: false,
        );
        await tester.pump();
        await tester.tap(find.text('All APRS Messages').first);
        await tester.pump();
        expect(find.byTooltip('OTA commands'), findsNothing);
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
        expect(find.text('Confirmed QSOs: 5'), findsOneWidget);
        expect(find.text('Details: Lakeshore op'), findsOneWidget);
        expect(find.text('QSO confirmed by K7ABC-6'), findsOneWidget);
        expect(find.textContaining('waiting for host QSL'), findsOneWidget);
        expect(find.textContaining('Waiting for position'), findsOneWidget);
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
      expect(find.text('Hosting: N0CALL-7'), findsOneWidget);
      expect(find.text('CHASERS! 2/2 2'), findsOneWidget);
      expect(find.text('K7ABC-6'), findsOneWidget);
      expect(find.text('W1XYZ-5'), findsOneWidget);
      final chaser = find.descendant(
        of: find.byType(OtaActivityMessageBody),
        matching: find.widgetWithText(TextButton, 'K7ABC-6'),
      );
      await tester.ensureVisible(chaser);
      await tester.pumpAndSettle();
      await tester.tap(chaser);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'QSL K7ABC-6',
      );
      await tester.enterText(find.byType(TextField).last, '');
      await tester.tap(find.byTooltip('OTA commands'));
      await tester.pumpAndSettle();
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
      await tester.tap(find.byTooltip('OTA commands'));
      await tester.pumpAndSettle();
      expect(find.text('End op'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
