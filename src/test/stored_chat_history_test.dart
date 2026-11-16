import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/comms_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/services/stored_chat_history.dart';

void main() {
  late AppDatabase db;
  late StoredChatHistory service;
  late DataBrokerClient client;

  setUp(() async {
    DataBroker.reset();
    db = await AppDatabase.openInMemory();
    service = StoredChatHistory()..init();
    client = DataBrokerClient();
  });

  tearDown(() async {
    service.dispose();
    client.dispose();
    DataBroker.reset();
    await AppDatabase.close();
  });

  Future<Map> request(String id, {Object? before}) async {
    final response = Completer<Map>();
    client.subscribe(
      deviceId: 1,
      name: 'StoredChatHistoryPage',
      callback: (_, _, data) {
        if (data is Map && data['requestId'] == id) response.complete(data);
      },
    );
    client.dispatch(
      deviceId: 1,
      name: 'RequestStoredChatHistory',
      store: false,
      data: {'requestId': id, 'source': 'comms', 'before': before},
    );
    return response.future.timeout(const Duration(seconds: 5));
  }

  test('pages equal timestamps without gaps or accumulating rows', () async {
    await db.comms.importAll([
      for (var i = 0; i < 405; i++)
        DecodedTextEntry(
          text: '$i',
          time: DateTime(2026),
          isReceived: true,
          encoding: VoiceTextEncodingType.voice,
        ),
    ]);
    final seen = <String>{};
    Object? cursor;
    for (var pageIndex = 0; pageIndex < 3; pageIndex++) {
      final page = await request('$pageIndex', before: cursor);
      final entries = page['entries'] as List;
      expect(entries.length, pageIndex < 2 ? 200 : 5);
      expect(page['hasMore'], pageIndex < 2);
      for (final raw in entries.cast<Map>()) {
        expect(seen.add((raw['data'] as Map)['text'] as String), isTrue);
      }
      cursor = page['before'];
    }
    expect(seen, hasLength(405));
    expect(await db.comms.count(), 405);
  });

  test(
    'bad cursors return explicit errors rather than an empty success',
    () async {
      final page = await request('invalid', before: ['invalid']);
      expect(page['error'], contains('Invalid history cursor'));
      expect(page.containsKey('entries'), isFalse);
    },
  );

  test('RF archive respects cleared APRS packets', () async {
    await db.db.insert('packets', {
      'time_us': 1,
      'incoming': 1,
      'channel_id': 0,
      'region_id': 0,
      'channel_name': 'APRS',
      'data': Uint8List(0),
      'encoding': 0,
      'frame_type': 0,
      'corrections': 0,
      'aprs_hidden': 1,
    });
    final page = await db.packets.page();
    expect(page['entries'], isEmpty);
  });
}
