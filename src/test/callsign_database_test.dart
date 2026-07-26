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

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/callsign/callsign_database.dart';
import 'package:htcommander/callsign/callsign_record.dart';

void main() {
  group('CallsignRecord formatting', () {
    test('operator class and status names', () {
      const r = CallsignRecord(
        callsign: 'K7VZT',
        operatorClass: 'E',
        status: 'A',
      );
      expect(r.operatorClassName, 'Amateur Extra');
      expect(r.statusName, 'Active');
    });

    test('expire date formatting', () {
      const r = CallsignRecord(callsign: 'W1AW', expireDate: 20301231);
      expect(r.expireDateFormatted, '2030-12-31');
    });

    test('invalid expire date yields empty', () {
      const r = CallsignRecord(callsign: 'W1AW', expireDate: 0);
      expect(r.expireDateFormatted, '');
    });

    test('location joins city, state and zip', () {
      const r = CallsignRecord(
        callsign: 'W1AW',
        city: 'Newington',
        state: 'CT',
        zip: '06111',
      );
      expect(r.location, 'Newington, CT 06111');
    });
  });

  group('CallsignDatabase round-trip', () {
    final records = <CallsignRecord>[
      const CallsignRecord(
        callsign: 'W1AW',
        name: 'ARRL HQ OPERATORS CLUB',
        operatorClass: 'E',
        status: 'A',
        city: 'Newington',
        state: 'CT',
        zip: '06111',
        expireDate: 20301231,
      ),
      const CallsignRecord(
        callsign: 'K7VZT',
        name: 'DOE JOHN',
        operatorClass: 'G',
        status: 'A',
        city: 'Seattle',
        state: 'WA',
        zip: '98101',
        expireDate: 20281115,
      ),
      const CallsignRecord(
        callsign: 'AB1CDE',
        name: 'SMITH JANE',
        operatorClass: 'T',
        status: 'A',
        city: 'Boston',
        state: 'MA',
        zip: '02108',
      ),
      const CallsignRecord(
        callsign: 'N0CALL',
        name: 'TEST STATION',
        operatorClass: 'N',
        status: 'E',
      ),
    ];

    late CallsignDatabase db;

    setUp(() {
      final bytes = CallsignDatabase.build(records, sourceDate: 20260715);
      db = CallsignDatabase.openBytes(bytes);
    });

    test('reports header metadata', () {
      expect(db.recordCount, records.length);
      expect(db.sourceDate, 20260715);
      expect(db.epochDate, CallsignDatabase.defaultEpochDate);
    });

    test('exact lookup returns the full record', () async {
      final r = await db.lookup('W1AW');
      expect(r, isNotNull);
      expect(r!.callsign, 'W1AW');
      expect(r.name, 'ARRL HQ OPERATORS CLUB');
      expect(r.operatorClass, 'E');
      expect(r.status, 'A');
      expect(r.city, 'Newington');
      expect(r.state, 'CT');
      expect(r.zip, '06111');
      expect(r.expireDate, 20301231);
    });

    test('lookup ignores SSID', () async {
      final r = await db.lookup('K7VZT-5');
      expect(r, isNotNull);
      expect(r!.callsign, 'K7VZT');
      expect(r.city, 'Seattle');
    });

    test('lookup is case-insensitive', () async {
      final r = await db.lookup('ab1cde');
      expect(r, isNotNull);
      expect(r!.callsign, 'AB1CDE');
    });

    test('missing callsign returns null', () async {
      expect(await db.lookup('ZZ9ZZ'), isNull);
    });

    test('empty / invalid callsign returns null', () async {
      expect(await db.lookup(''), isNull);
      expect(await db.lookup('-3'), isNull);
    });

    test('every inserted callsign is retrievable', () async {
      for (final rec in records) {
        final r = await db.lookup(rec.callsign);
        expect(r, isNotNull, reason: 'expected to find ${rec.callsign}');
        expect(r!.callsign, rec.callsign);
      }
    });
  });

  group('CallsignDatabase Canadian (ISED) round-trip', () {
    final records = <CallsignRecord>[
      const CallsignRecord(
        callsign: 'VA1AA',
        name: 'Bill McFadden',
        qualifications: 'ACD',
        city: 'MIDDLE SACKVILLE',
        state: 'NS',
        zip: 'B4E 2X8',
      ),
      const CallsignRecord(
        callsign: 'VE3XYZ',
        name: 'Jane Smith',
        qualifications: 'AD',
        city: 'Toronto',
        state: 'ON',
        zip: 'M5V 2T6',
      ),
      const CallsignRecord(
        callsign: 'VA2AAC',
        name: 'André Charron',
        qualifications: 'A',
        city: 'MONT-LAURIER',
        state: 'QC',
        zip: 'J9L1X1',
      ),
      const CallsignRecord(
        callsign: 'VE9NOPO',
        name: 'NO POSTAL CLUB',
        qualifications: '',
        city: 'Fredericton',
        state: 'NB',
      ),
    ];

    late CallsignDatabase db;

    setUp(() {
      final bytes = CallsignDatabase.build(
        records,
        sourceDate: 20260725,
        flags: CallsignDatabase.flagCanada,
      );
      db = CallsignDatabase.openBytes(bytes);
    });

    test('reports the Canadian flag', () {
      expect(db.flags & CallsignDatabase.flagCanada, isNot(0));
    });

    test('decodes qualifications and alphanumeric postal code', () async {
      final r = await db.lookup('VA1AA');
      expect(r, isNotNull);
      expect(r!.name, 'Bill McFadden');
      expect(r.qualifications, 'ACD');
      expect(r.qualificationsName, 'Basic, 12 wpm, Advanced');
      expect(r.operatorClass, '');
      expect(r.status, '');
      expect(r.state, 'NS');
      expect(r.zip, 'B4E 2X8');
      expect(r.location, 'MIDDLE SACKVILLE, NS B4E 2X8');
    });

    test('normalizes postal codes with or without a space', () async {
      final r = await db.lookup('VA2AAC');
      expect(r, isNotNull);
      expect(r!.zip, 'J9L 1X1');
      expect(r.name, 'André Charron');
    });

    test('missing postal code and qualifications decode to empty', () async {
      final r = await db.lookup('VE9NOPO');
      expect(r, isNotNull);
      expect(r!.zip, '');
      expect(r.qualifications, '');
      expect(r.qualificationsName, '');
    });

    test('every inserted callsign is retrievable', () async {
      for (final rec in records) {
        final r = await db.lookup(rec.callsign);
        expect(r, isNotNull, reason: 'expected to find ${rec.callsign}');
        expect(r!.callsign, rec.callsign);
      }
    });
  });
}

