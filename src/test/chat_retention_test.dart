import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_events.dart';
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/widgets/aprs_tab.dart';
import 'package:htcommander/widgets/chat_widget.dart';
import 'package:htcommander/widgets/comms_tab.dart';
import 'package:htcommander/dialogs/stored_history_dialog.dart';
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  setUp(DataBroker.reset);
  tearDown(DataBroker.reset);

  Widget app(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  void packet(int n, {required bool internet, DateTime? time}) {
    final ax = Tnc2Codec.decode('N0CALL>APRS:>status $n')!;
    ax.time = time ?? DateTime(2026, 1, 1).add(Duration(seconds: n));
    final aprs = AprsPacket.parse(ax)!..fromAprsIs = internet;
    DataBroker.dispatch(
      deviceId: 1,
      name: 'AprsFrame',
      data: AprsFrameEventArgs(aprs, ax, null),
      store: false,
    );
  }

  List<ChatMessage> messages(WidgetTester tester) =>
      tester.widget<ChatWidget>(find.byType(ChatWidget).first).messages;

  testWidgets('APRS eviction retains existing message objects and stable IDs', (
    tester,
  ) async {
    DataBroker.dispatch(deviceId: 0, name: 'AprsShowTelemetry', data: 1);
    await tester.pumpWidget(app(const AprsTab()));
    await tester.tap(find.text('All APRS Messages').first);
    await tester.pump();
    for (var i = 0; i < 1000; i++) {
      packet(i, internet: true);
    }
    await tester.pump();
    final retained = messages(tester)[1];
    packet(1000, internet: true);
    await tester.pump();
    expect(messages(tester), hasLength(1000));
    expect(identical(messages(tester).first, retained), isTrue);
    expect(messages(tester).last.message, contains('status 1000'));
    packet(1001, internet: false);
    await tester.pump();
    expect(messages(tester), hasLength(1001));
    expect(identical(messages(tester).first, retained), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RF live history is bounded independently of internet history', (
    tester,
  ) async {
    DataBroker.dispatch(deviceId: 0, name: 'AprsShowTelemetry', data: 1);
    await tester.pumpWidget(app(const AprsTab()));
    await tester.tap(find.text('All APRS Messages').first);
    await tester.pump();
    packet(0, internet: true);
    for (var i = 1; i <= 1002; i++) {
      packet(i, internet: false);
    }
    await tester.pump();
    expect(messages(tester), hasLength(1001));
    expect(messages(tester).first.message, contains('status 0'));
    expect(messages(tester)[1].message, contains('status 3'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Comms live presentation obeys the stored history window', (
    tester,
  ) async {
    await tester.pumpWidget(app(const CommsTab()));
    for (var i = 0; i < 1002; i++) {
      DataBroker.dispatch(
        deviceId: 2,
        name: 'TextReady',
        store: false,
        data: {
          'text': 'message $i',
          'completed': true,
          'encoding': 'Voice',
          'time': DateTime(2026, 1, 1).millisecondsSinceEpoch + i,
        },
      );
    }
    await tester.pump();
    expect(messages(tester), hasLength(1000));
    expect(messages(tester).first.message, 'message 2');
    expect(messages(tester).map((m) => m.id).toSet(), hasLength(1000));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Comms prepends archive pages inline without boundary duplicates',
    (tester) async {
      final host = DataBrokerClient();
      addTearDown(host.dispose);
      final time = DateTime(2026).millisecondsSinceEpoch;
      Map<String, Object?> entry(String text, int timestamp) => {
        'text': text,
        'time': timestamp,
        'encoding': 'Voice',
        'completed': true,
      };
      DataBroker.dispatch(
        deviceId: 1,
        name: 'StoredChatHistoryAvailable',
        data: true,
      );
      DataBroker.dispatch(
        deviceId: 1,
        name: 'DecodedTextHistory',
        data: [entry('same', time), entry('same', time)],
      );
      final requests = <Map>[];
      host.subscribe(
        deviceId: 1,
        name: 'RequestStoredChatHistory',
        callback: (_, _, data) {
          final request = data as Map;
          requests.add(request);
          final firstPage = requests.length == 1;
          host.dispatch(
            deviceId: 1,
            name: 'StoredChatHistoryPage',
            store: false,
            data: {
              'requestId': request['requestId'],
              'before': firstPage ? [time, 2] : [time - 1, 0],
              'hasMore': firstPage,
              'entries': firstPage
                  ? [
                      {'id': 2, 'data': entry('same', time)},
                      {'id': 3, 'data': entry('same', time)},
                    ]
                  : [
                      {'id': 0, 'data': entry('older', time - 1)},
                      {'id': 1, 'data': entry('same', time)},
                    ],
            },
          );
        },
      );
      await tester.pumpWidget(app(const CommsTab()));
      expect(find.byTooltip('Stored History'), findsNothing);
      final retained = messages(tester).last;
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.first['before'], [time + 1, 0]);
      expect(requests.last['before'], [time, 2]);
      expect(messages(tester).map((m) => m.message), [
        'older',
        'same',
        'same',
        'same',
      ]);
      expect(messages(tester).map((m) => m.id).toSet(), hasLength(4));
      expect(identical(messages(tester).last, retained), isTrue);
      expect(find.byType(StoredHistoryDialog), findsNothing);
      expect(find.text('Show more'), findsNothing);
      host.dispatch(
        deviceId: 2,
        name: 'TextReady',
        store: false,
        data: entry('live', time + 1),
      );
      await tester.pump();
      expect(messages(tester).last.message, 'live');
      expect(messages(tester).first.message, 'older');
      for (var i = 0; i < 1000; i++) {
        host.dispatch(
          deviceId: 2,
          name: 'TextReady',
          store: false,
          data: entry('live $i', time + 2 + i),
        );
      }
      await tester.pump();
      expect(messages(tester), hasLength(1005));
      expect(messages(tester).first.message, 'older');
      expect(messages(tester).last.message, 'live 999');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Comms history retries timeouts and ignores stale or cleared pages',
    (tester) async {
      final host = DataBrokerClient();
      addTearDown(host.dispose);
      final requests = <Map>[];
      host.subscribe(
        deviceId: 1,
        name: 'RequestStoredChatHistory',
        callback: (_, _, data) => requests.add(data as Map),
      );
      host.dispatch(
        deviceId: 1,
        name: 'StoredChatHistoryAvailable',
        data: true,
      );
      await tester.pumpWidget(app(const CommsTab()));
      await tester.tap(find.text('Show more'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
      await tester.pump(const Duration(seconds: 15));
      expect(
        find.textContaining('Stored history request timed out'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(requests, hasLength(2));
      void respond(Map request, {String? error}) => host.dispatch(
        deviceId: 1,
        name: 'StoredChatHistoryPage',
        store: false,
        data: {
          'requestId': request['requestId'],
          'error': error,
          'hasMore': false,
          'entries': [
            {
              'id': 1,
              'data': {
                'text': 'older',
                'time': DateTime(2026).millisecondsSinceEpoch,
                'encoding': 'Voice',
              },
            },
          ],
        },
      );
      respond(requests.first);
      await tester.pump();
      expect(messages(tester), isEmpty);
      respond(requests.last, error: 'Archive unavailable');
      await tester.pump();
      expect(find.textContaining('Archive unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      host.dispatch(
        deviceId: 1,
        name: 'VoiceTextCleared',
        data: null,
        store: false,
      );
      respond(requests.last);
      await tester.pump();
      expect(messages(tester), isEmpty);
      expect(find.text('Show more'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('prepending history preserves the chat scroll position', (
    tester,
  ) async {
    final history = [
      for (var i = 20; i < 60; i++)
        ChatMessage(
          id: '$i',
          route: '',
          senderCallsign: '',
          message: 'message $i',
          time: DateTime(2026).add(Duration(minutes: i)),
          isSender: false,
        ),
    ];
    Widget chat() => app(
      ChatWidget(messages: history, historyHeader: const Text('Show more')),
    );
    await tester.pumpWidget(chat());
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // Even near the live end, a history prepend must not trigger auto-scroll.
    position.jumpTo(40);
    await tester.pumpAndSettle();
    history.insert(
      0,
      ChatMessage(
        id: 'older',
        route: '',
        senderCallsign: '',
        message: 'older',
        time: DateTime(2026),
        isSender: false,
      ),
    );
    await tester.pumpWidget(chat());
    await tester.pumpAndSettle();
    expect(position.pixels, 40);

    await tester.scrollUntilVisible(
      find.text('Show more'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('Show more').hitTestable(), findsOneWidget);
    final anchor = tester.getTopLeft(find.text('older'));
    final offset = position.pixels;
    history.insert(
      0,
      ChatMessage(
        id: 'oldest',
        route: '',
        senderCallsign: '',
        message: 'oldest',
        time: DateTime(2025),
        isSender: false,
      ),
    );
    await tester.pumpWidget(chat());
    await tester.pumpAndSettle();
    expect(position.pixels, offset);
    expect(tester.getTopLeft(find.text('older')), anchor);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('archive navigation replaces pages and ignores stale responses', (
    tester,
  ) async {
    final host = DataBrokerClient();
    addTearDown(host.dispose);
    String? lastId;
    var pageIndex = 0;
    host.subscribe(
      deviceId: 1,
      name: 'RequestStoredChatHistory',
      callback: (_, _, data) {
        final request = data as Map;
        lastId = request['requestId'] as String;
        host.dispatch(
          deviceId: 1,
          name: 'StoredChatHistoryPage',
          store: false,
          data: {
            'requestId': lastId,
            'before': [1, pageIndex],
            'hasMore': true,
            'entries': [
              for (var i = 0; i < 200; i++)
                {
                  'id': i,
                  'data': {'text': 'page ${pageIndex}_$i'},
                },
            ],
          },
        );
        pageIndex++;
      },
    );
    await tester.pumpWidget(
      app(
        StoredHistoryDialog(
          sources: const {'comms': 'Comms'},
          messageBuilder: (data, id) => ChatMessage(
            id: '$id',
            route: '',
            senderCallsign: '',
            message: data['text'] as String,
            time: DateTime(2026),
            isSender: false,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(messages(tester), hasLength(200));
    final first = messages(tester).first;
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pump();
    expect(messages(tester), hasLength(200));
    expect(messages(tester).first.message, 'page 1_0');
    expect(messages(tester).contains(first), isFalse);
    host.dispatch(
      deviceId: 1,
      name: 'StoredChatHistoryPage',
      store: false,
      data: {'requestId': 'stale', 'entries': []},
    );
    await tester.pump();
    expect(messages(tester), hasLength(200));
    await tester.pumpWidget(const SizedBox());
  });
}
