import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/comms_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/services/stored_chat_history.dart';
import 'package:htcommander/aprsis/tnc2_codec.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';

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

  for (final source in ['rf', 'internet']) {
    test(
      '$source pages count only messages belonging to the requested peer',
      () async {
        DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'K7VZT');
        final time = DateTime(2026);
        final lines = <String>[
          for (var i = 0; i < 201; i++) ...[
            'W1AW>APRS::K7VZT    :message $i',
            'N0CALL>APRS::K7VZT    :unrelated $i',
            'W1AW>APRS:>telemetry $i',
            'W1AW>APRS::K7VZT    :ack$i',
          ],
        ];
        if (source == 'internet') {
          for (final line in lines) {
            await db.aprsis.insert(time, line);
          }
        } else {
          await db.packets.importAll([
            for (final line in lines)
              TncDataFragment(
                finalFragment: true,
                fragmentId: 0,
                data: Tnc2Codec.decode(line)!.toByteArray(),
                channelId: 0,
                regionId: 0,
                channelName: 'APRS',
                incoming: true,
                time: time,
              ),
          ]);
        }
        final first = await service.page({
          'requestId': 'first',
          'source': source,
          'peer': 'w1aw-0',
        });
        expect(first['error'], isNull);
        expect(first['entries'], hasLength(200));
        expect(first['hasMore'], isTrue);
        final last = await service.page({
          'requestId': 'last',
          'source': source,
          'peer': 'W1AW',
          'before': first['before'],
        });
        expect(last['entries'], hasLength(1));
        expect(last['hasMore'], isFalse);
        final empty = await service.page({
          'requestId': 'empty',
          'source': source,
          'peer': 'MISSING',
        });
        expect(empty['entries'], isEmpty);
        expect(empty['hasMore'], isFalse);
      },
    );
  }

  test(
    'internet thread filters include outgoing messages and SMS replies',
    () async {
      DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: 'K7VZT');
      DataBroker.dispatch(deviceId: 0, name: 'StationId', data: 5);
      for (final line in [
        'K7VZT-5>APRS::W1AW-9   :outgoing',
        'W1AW-9>APRS::K7VZT-5  :incoming',
        'K7VZT-5>APRS::SMS      :@5551234 outgoing SMS',
        'SMSGTE>APRS::K7VZT-5  :@5551234 incoming SMS',
        'N0CALL>APRS::W1AW-9   :not our conversation',
      ]) {
        await db.aprsis.insert(DateTime(2026), line);
      }
      for (final peer in ['W1AW-9', '5551234']) {
        final page = await service.page({
          'requestId': peer,
          'source': 'internet',
          'peer': peer,
        });
        expect(page['error'], isNull);
        expect(page['entries'], hasLength(2));
        expect(page['hasMore'], isFalse);
      }
    },
  );
}
