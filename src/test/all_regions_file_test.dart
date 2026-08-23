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

void main() {
  group('AllRegionsFile', () {
    test('round-trips regions, names and every channel slot', () {
      final file = AllRegionsFile(
        regionCount: 2,
        channelCount: 3,
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
                bandwidth: RadioBandwidthType.wide,
                txAtMaxPower: true,
              ),
              // An empty (unset) slot is preserved with its channel number.
              RadioChannelInfo(channelId: 1),
              RadioChannelInfo(
                channelId: 2,
                name: 'Repeater',
                rxFreq: 146940000,
                txFreq: 146340000,
              ),
            ],
          ),
          RegionChannelData(index: 1, name: 'Travel', channels: []),
        ],
      );

      final parsed = AllRegionsFile.tryParse(file.toJsonString());
      expect(parsed, isNotNull);
      expect(parsed!.regionCount, 2);
      expect(parsed.channelCount, 3);
      expect(parsed.regions.length, 2);

      final region0 = parsed.regions[0];
      expect(region0.index, 0);
      expect(region0.name, 'Home');
      expect(region0.channels.length, 3);
      expect(region0.channels[0].name, 'Calling');
      expect(region0.channels[0].rxFreq, 146520000);
      expect(region0.channels[0].bandwidth, RadioBandwidthType.wide);
      // Unset slot keeps its channel id and zero frequency.
      expect(region0.channels[1].channelId, 1);
      expect(region0.channels[1].rxFreq, 0);
      expect(region0.channels[2].txFreq, 146340000);

      expect(parsed.regions[1].name, 'Travel');
      expect(parsed.regions[1].channels, isEmpty);
    });

    test('returns null for non-JSON content', () {
      expect(AllRegionsFile.tryParse('title,tx_freq,rx_freq\nA,1,2'), isNull);
    });

    test('returns null for JSON without the format marker', () {
      expect(AllRegionsFile.tryParse('{"foo": "bar"}'), isNull);
    });
  });
}
