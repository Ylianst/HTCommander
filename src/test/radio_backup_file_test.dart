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
import 'package:htcommander/radio/radio_models.dart';
import 'package:htcommander/utils/all_regions_file.dart';
import 'package:htcommander/utils/radio_backup_file.dart';

void main() {
  group('RadioBackupFile', () {
    test('round-trips regions and radio settings', () {
      final file = RadioBackupFile(
        regionCount: 1,
        channelCount: 2,
        regions: [
          RegionChannelData(
            index: 0,
            name: 'Home',
            channels: [
              RadioChannelInfo(
                channelId: 0,
                name: 'Calling',
                rxFreq: 146520000,
                txFreq: 146520000,
              ),
              RadioChannelInfo(channelId: 1),
            ],
          ),
        ],
        settingsRaw: 'AQIDBAUGBwgJ',
        bssSettings: {'aprsCallsign': 'N0CALL', 'aprsSsid': 7},
        aprsPath: 'WIDE1-1,WIDE2-1',
        pfTable: [
          {'buttonId': 1, 'actionValue': 0, 'effectValue': 5},
          {'buttonId': 1, 'actionValue': 1, 'effectValue': 9},
        ],
      );

      final parsed = RadioBackupFile.tryParse(file.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.regionCount, 1);
      expect(parsed.channelCount, 2);
      expect(parsed.regions.single.name, 'Home');
      expect(parsed.regions.single.channels.length, 2);
      expect(parsed.regions.single.channels[0].rxFreq, 146520000);
      expect(parsed.settingsRaw, 'AQIDBAUGBwgJ');
      expect(parsed.bssSettings?['aprsCallsign'], 'N0CALL');
      expect(parsed.aprsPath, 'WIDE1-1,WIDE2-1');
      expect(parsed.pfTable?.length, 2);
      expect(parsed.pfTable?[1]['effectValue'], 9);

      // The regions can be handed to the shared all-regions writer.
      final asRegions = parsed.toAllRegionsFile();
      expect(asRegions, isA<AllRegionsFile>());
      expect(asRegions.regions.single.name, 'Home');
    });

    test('omits absent settings fields from JSON', () {
      final file = RadioBackupFile(
        regionCount: 0,
        channelCount: 0,
        regions: const [],
      );
      final json = file.toJsonString();
      expect(json.contains('settingsRaw'), isFalse);
      expect(json.contains('bssSettings'), isFalse);
      expect(json.contains('aprsPath'), isFalse);
      expect(json.contains('pfTable'), isFalse);

      final parsed = RadioBackupFile.tryParse(json);
      expect(parsed, isNotNull);
      expect(parsed!.settingsRaw, isNull);
      expect(parsed.bssSettings, isNull);
      expect(parsed.aprsPath, isNull);
      expect(parsed.pfTable, isNull);
    });

    test('a backup is not mistaken for a plain all-regions file', () {
      // The backup carries a distinct format marker, so the all-regions parser
      // must reject it (import checks the backup format first).
      final file = RadioBackupFile(
        regionCount: 0,
        channelCount: 0,
        regions: const [],
      );
      expect(AllRegionsFile.tryParse(file.toJsonString()), isNull);
    });

    test('returns null for non-backup content', () {
      expect(RadioBackupFile.tryParse('{"format":"htcommander-regions"}'),
          isNull);
      expect(RadioBackupFile.tryParse('not json'), isNull);
    });
  });
}
