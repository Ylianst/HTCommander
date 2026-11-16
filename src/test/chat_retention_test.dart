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
