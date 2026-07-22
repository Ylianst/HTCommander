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
import 'package:htcommander/callsign/callsign_country.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final lookup = CallsignCountryLookup.instance;

  setUpAll(() async {
    await lookup.init();
  });

  group('CallsignCountryLookup', () {
    test('loads the bundled table', () {
      expect(lookup.isLoaded, isTrue);
    });

    test('resolves common callsigns to their country', () {
      expect(lookup.lookup('DH1TW')?.country, contains('Germany'));
      expect(lookup.lookup('K7VZT')?.country, contains('United States'));
      expect(lookup.lookup('G0RDI')?.country, contains('England'));
      expect(lookup.lookup('VK2ABC')?.country, contains('Australia'));
      expect(lookup.lookup('JA1XYZ')?.country, contains('Japan'));
    });

    test('reports the continent', () {
      expect(lookup.lookup('DH1TW')?.continent, 'EU');
      expect(lookup.lookup('K7VZT')?.continentName, 'North America');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(lookup.lookup('  dh1tw  ')?.country, contains('Germany'));
    });

    test('strips SSID appendix', () {
      expect(lookup.lookup('K7VZT-9')?.country, contains('United States'));
    });

    test('handles a portable operating prefix', () {
      // Operating from Ecuador while licensed in Germany.
      expect(lookup.lookup('HC2/DH1TW')?.country, contains('Ecuador'));
      // Home call with a country appendix.
      expect(lookup.lookup('DH1TW/HC2')?.country, contains('Ecuador'));
    });

    test('handles single-letter and call-area appendices', () {
      expect(lookup.lookup('DH1TW/P')?.country, contains('Germany'));
      expect(lookup.lookup('W1AW/4')?.country, contains('United States'));
    });

    test('maritime and aircraft mobile are not tied to a country', () {
      expect(lookup.lookup('DH1TW/MM')?.country, 'Maritime Mobile');
      expect(lookup.lookup('DH1TW/AM')?.country, 'Aircraft Mobile');
    });

    test('returns null for an unresolvable callsign', () {
      expect(lookup.lookup(''), isNull);
      expect(lookup.lookup('12345'), isNull);
    });
  });
}
