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
import 'package:htcommander/services/callsign_lookup_service.dart';

void main() {
  group('CallsignDbManifest overlay parsing', () {
    test('parses a v2 manifest with an overlay object', () {
      final m = CallsignDbManifest.fromJson({
        'schemaVersion': 2,
        'version': '2026.07.12',
        'sourceDate': 20260712,
        'url': 'http://x/fcc_amateur.cdb.xz',
        'compressed': true,
        'sizeBytes': 22400780,
        'md5': 'ABC123',
        'recordCount': 1588146,
        'overlay': {
          'version': '2026.07.19',
          'sourceDate': 20260719,
          'url': 'http://x/fcc_amateur_overlay.cdb.xz',
          'compressed': true,
          'sizeBytes': 512345,
          'md5': 'DEF456',
          'recordCount': 20345,
        },
      });
      expect(m.sourceDate, 20260712);
      expect(m.md5, 'abc123'); // lower-cased
      expect(m.overlay, isNotNull);
      expect(m.overlay!.sourceDate, 20260719);
      expect(m.overlay!.recordCount, 20345);
      expect(m.overlay!.md5, 'def456');
      expect(m.overlay!.url, 'http://x/fcc_amateur_overlay.cdb.xz');
    });

    test('legacy v1 manifest has a null overlay', () {
      final m = CallsignDbManifest.fromJson({
        'schemaVersion': 1,
        'version': '2026.07.12',
        'sourceDate': 20260712,
        'url': 'http://x/fcc_amateur.cdb.xz',
        'compressed': true,
        'sizeBytes': 22400780,
        'md5': 'abc123',
        'recordCount': 1588146,
      });
      expect(m.overlay, isNull);
    });
  });

  group('overlay-before-baseline lookup order', () {
    late CallsignDatabase baseline;
    late CallsignDatabase overlay;

    setUp(() {
      // Baseline: W1AW, K7VZT (old city), AB1CDE.
      baseline = CallsignDatabase.openBytes(
        CallsignDatabase.build(const [
          CallsignRecord(
            callsign: 'W1AW',
            name: 'ARRL HQ',
            city: 'Newington',
            state: 'CT',
          ),
          CallsignRecord(
            callsign: 'K7VZT',
            name: 'DOE JOHN',
            city: 'Seattle',
            state: 'WA',
          ),
          CallsignRecord(
            callsign: 'AB1CDE',
            name: 'SMITH JANE',
            city: 'Boston',
            state: 'MA',
          ),
        ], sourceDate: 20260101),
      );
      // Overlay: K7VZT changed city, plus a brand-new W9NEW.
      overlay = CallsignDatabase.openBytes(
        CallsignDatabase.build(const [
          CallsignRecord(
            callsign: 'K7VZT',
            name: 'DOE JOHN',
            city: 'Tacoma',
            state: 'WA',
          ),
          CallsignRecord(
            callsign: 'W9NEW',
            name: 'NEW HAM',
            city: 'Chicago',
            state: 'IL',
          ),
        ], sourceDate: 20260108),
      );
    });

    test('overlay record supersedes the baseline', () async {
      final r = await CallsignLookupService.lookupInOrder(
        [overlay, baseline],
        'K7VZT',
      );
      expect(r, isNotNull);
      expect(r!.city, 'Tacoma'); // the overlay's fresher value, not Seattle
    });

    test('a key only in the overlay is found', () async {
      final r = await CallsignLookupService.lookupInOrder(
        [overlay, baseline],
        'W9NEW',
      );
      expect(r, isNotNull);
      expect(r!.name, 'NEW HAM');
    });

    test('a key only in the baseline falls through', () async {
      final r = await CallsignLookupService.lookupInOrder(
        [overlay, baseline],
        'W1AW',
      );
      expect(r, isNotNull);
      expect(r!.city, 'Newington');
    });

    test('an unknown key returns null', () async {
      final r = await CallsignLookupService.lookupInOrder(
        [overlay, baseline],
        'ZZ9ZZ',
      );
      expect(r, isNull);
    });

    test('null slots are skipped (overlay not installed)', () async {
      final r = await CallsignLookupService.lookupInOrder(
        [null, baseline],
        'K7VZT',
      );
      expect(r, isNotNull);
      expect(r!.city, 'Seattle'); // baseline value when no overlay present
    });
  });
}
