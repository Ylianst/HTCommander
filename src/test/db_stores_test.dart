/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/comms_handler.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/services/db/legacy_import.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.openInMemory();
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  group('CommsDao', () {
    test(
      'insert then recent round-trips fields in chronological order',
      () async {
        final base = DateTime.fromMillisecondsSinceEpoch(1000000);
        await db.comms.insert(
          DecodedTextEntry(
            text: 'first',
            channel: 'Voice 1',
            time: base,
            encoding: VoiceTextEncodingType.voice,
          ),
        );
        await db.comms.insert(
          DecodedTextEntry(
            text: 'ping',
            channel: 'APRS',
            time: base.add(const Duration(seconds: 1)),
            isReceived: false,
            encoding: VoiceTextEncodingType.aprs,
            source: 'N0CALL',
            destination: 'APDR16',
            latitude: 45.5,
            longitude: -73.6,
          ),
        );

        final rows = await db.comms.recent(10);
        expect(rows.map((e) => e.text), ['first', 'ping']);
        final aprs = rows[1];
        expect(aprs.encoding, VoiceTextEncodingType.aprs);
        expect(aprs.channel, 'APRS');
        expect(aprs.isReceived, isFalse);
        expect(aprs.source, 'N0CALL');
        expect(aprs.latitude, 45.5);
        expect(aprs.longitude, -73.6);
      },
    );

    test('recent returns only the newest entries', () async {
      for (var i = 0; i < 5; i++) {
        await db.comms.insert(
          DecodedTextEntry(
            text: 'm$i',
            time: DateTime.fromMillisecondsSinceEpoch(1000 + i),
          ),
        );
      }
      final rows = await db.comms.recent(2);
      expect(rows.map((e) => e.text), ['m3', 'm4']);
    });

    test('enforceLimits trims total and APRS independently', () async {
      for (var i = 0; i < 6; i++) {
        await db.comms.insert(
          DecodedTextEntry(
            text: 'v$i',
            time: DateTime.fromMillisecondsSinceEpoch(1000 + i),
            encoding: VoiceTextEncodingType.voice,
          ),
        );
      }
      for (var i = 0; i < 4; i++) {
        await db.comms.insert(
          DecodedTextEntry(
            text: 'a$i',
            time: DateTime.fromMillisecondsSinceEpoch(2000 + i),
            encoding: VoiceTextEncodingType.aprs,
          ),
        );
      }

      await db.comms.enforceLimits(maxTotal: 0, maxAprs: 2);
      expect(
        await _count(
          db,
          "SELECT COUNT(*) FROM comms_events WHERE encoding='APRS'",
        ),
        2,
      );

      await db.comms.enforceLimits(maxTotal: 3, maxAprs: 0);
      expect(await db.comms.count(), 3);
    });
  });

  group('PacketsDao', () {
    TncDataFragment frame({
      required String channel,
      required int micros,
      List<int> data = const [1, 2, 3],
    }) {
      return TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: Uint8List.fromList(data),
        channelId: 3,
        regionId: 1,
        channelName: channel,
        incoming: true,
        time: DateTime.fromMicrosecondsSinceEpoch(micros),
        encoding: FragmentEncodingType.softwareDart,
        frameType: FragmentFrameType.ax25,
        corrections: 2,
        radioMac: 'AA:BB',
      );
    }

    test('insert then recent preserves bytes and fields', () async {
      await db.packets.insert(
        frame(channel: '1', micros: 10, data: const [9, 8, 7, 0, 255]),
      );
      final rows = await db.packets.recent(10);
      expect(rows, hasLength(1));
      final f = rows.single;
      expect(f.channelName, '1');
      expect(f.data, Uint8List.fromList(const [9, 8, 7, 0, 255]));
      expect(f.encoding, FragmentEncodingType.softwareDart);
      expect(f.frameType, FragmentFrameType.ax25);
      expect(f.corrections, 2);
      expect(f.radioMac, 'AA:BB');
      expect(f.incoming, isTrue);
    });

    test('enforceLimits caps APRS and non-APRS separately', () async {
      for (var i = 0; i < 5; i++) {
        await db.packets.insert(frame(channel: 'APRS', micros: 100 + i));
      }
      for (var i = 0; i < 5; i++) {
        await db.packets.insert(frame(channel: '1', micros: 200 + i));
      }
      await db.packets.enforceLimits(maxNonAprs: 2, maxAprs: 3);
      expect(await db.packets.count(aprs: true), 3);
      expect(await db.packets.count(aprs: false), 2);
    });
  });

  group('AprsisDao', () {
    test('insert, recent and enforceLimit', () async {
      for (var i = 0; i < 5; i++) {
        await db.aprsis.insert(
          DateTime.fromMicrosecondsSinceEpoch(1000 + i),
          'N0CALL>APRS:hello $i',
        );
      }
      final recent = await db.aprsis.recent(3);
      expect(recent.map((r) => r.tnc2Line), [
        'N0CALL>APRS:hello 2',
        'N0CALL>APRS:hello 3',
        'N0CALL>APRS:hello 4',
      ]);

      await db.aprsis.enforceLimit(2);
      final left = await db.aprsis.recent(100);
      expect(left, hasLength(2));
    });

    test('insert collapses tabs and newlines', () async {
      await db.aprsis.insert(
        DateTime.fromMicrosecondsSinceEpoch(5),
        'line1\r\n\twith\tbreaks',
      );
      final rows = await db.aprsis.recent(1);
      expect(rows.single.tnc2Line, 'line1   with breaks');
    });
  });

  group('LegacyImport', () {
    test('imports legacy files then renames them', () async {
      final dir = await Directory.systemTemp.createTemp('htc_legacy');
      addTearDown(() => dir.delete(recursive: true));

      final voiceText = File('${dir.path}/voicetext.json');
      await voiceText.writeAsString(
        jsonEncode([
          DecodedTextEntry(
            text: 'hello',
            time: DateTime.fromMillisecondsSinceEpoch(1000),
            encoding: VoiceTextEncodingType.voice,
          ).toJson(),
          DecodedTextEntry(
            text: 'ping',
            time: DateTime.fromMillisecondsSinceEpoch(2000),
            encoding: VoiceTextEncodingType.aprs,
            channel: 'APRS',
          ).toJson(),
        ]),
      );

      final frame = TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: Uint8List.fromList(const [1, 2, 3]),
        channelId: 0,
        regionId: 1,
        channelName: 'APRS',
        incoming: true,
        time: DateTime.fromMicrosecondsSinceEpoch(500),
        encoding: FragmentEncodingType.hardwareAfsk1200,
        frameType: FragmentFrameType.ax25,
        corrections: 0,
      );
      final packets = File('${dir.path}/packets.ptcap');
      await packets.writeAsString(
        '${frame.time.microsecondsSinceEpoch},'
        '${frame.incoming ? 1 : 0},${frame.toString()}\n',
      );

      final aprsIs = File('${dir.path}/aprsis_history.txt');
      await aprsIs.writeAsString('42\tN0CALL>APRS:hi\n');

      await LegacyImport.run(db, dir.path);

      expect(await db.comms.count(), 2);
      expect(await db.packets.count(aprs: true), 1);
      final aprsRows = await db.aprsis.recent(10);
      expect(aprsRows.single.tnc2Line, 'N0CALL>APRS:hi');

      expect(await voiceText.exists(), isFalse);
      expect(await File('${voiceText.path}.imported').exists(), isTrue);
      expect(await File('${packets.path}.imported').exists(), isTrue);
      expect(await File('${aprsIs.path}.imported').exists(), isTrue);

      // Idempotent: a second run finds nothing to import and adds no rows.
      await LegacyImport.run(db, dir.path);
      expect(await db.comms.count(), 2);
    });
  });
}

Future<int> _count(AppDatabase db, String sql) async {
  final rows = await db.db.rawQuery(sql);
  return (rows.first.values.first as int?) ?? 0;
}
