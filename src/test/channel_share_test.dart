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
import 'package:htcommander/utils/channel_share.dart';

void main() {
  group('ChannelShare.encode', () {
    test('encodes a wide FM simplex calling channel', () {
      final ch = RadioChannelInfo(
        channelId: 3,
        name: 'Calling',
        rxFreq: 146520000,
        txFreq: 146520000,
        bandwidth: RadioBandwidthType.wide,
        txAtMaxPower: true,
      );
      expect(ChannelShare.encode(ch), 'HTC:1:Calling:146.52:0:::G1*4A');
    });

    test('encodes a narrow FM repeater with negative offset and TSQL', () {
      final ch = RadioChannelInfo(
        channelId: 0,
        name: 'W1AW',
        rxFreq: 449925000,
        txFreq: 444925000,
        txSubAudio: 10000, // 100.0 Hz
        rxSubAudio: 10000,
        bandwidth: RadioBandwidthType.narrow,
        txAtMaxPower: true,
      );
      expect(ChannelShare.encode(ch), 'HTC:1:W1AW:449.925:-5:100:100:G0*62');
    });

    test('percent-encodes spaces in the name (AM receive-only)', () {
      final ch = RadioChannelInfo(
        channelId: 0,
        name: 'Air Guard',
        rxFreq: 121500000,
        txFreq: 121500000,
        rxMod: RadioModulationType.am,
        txMod: RadioModulationType.am,
        txDisable: true,
        txAtMaxPower: false,
      );
      expect(ChannelShare.encode(ch), 'HTC:1:Air%20Guard:121.5:0:::16*72');
    });

    test('encodes mute + de-emphasis-bypass data channel', () {
      final ch = RadioChannelInfo(
        channelId: 0,
        name: 'Packet',
        rxFreq: 144390000,
        txFreq: 144390000,
        bandwidth: RadioBandwidthType.wide,
        mute: true,
        preDeEmphBypass: true,
        txAtMaxPower: true,
      );
      expect(ChannelShare.encode(ch), 'HTC:1:Packet:144.39:0:::GS*4D');
    });

    test('encodes a positive offset with CTCSS decimal', () {
      final ch = RadioChannelInfo(
        channelId: 0,
        name: 'GMRS-19',
        rxFreq: 462650000,
        txFreq: 467650000,
        txSubAudio: 14130, // 141.3 Hz
        rxSubAudio: 14130,
        txAtMaxPower: true,
      );
      expect(
        ChannelShare.encode(ch),
        'HTC:1:GMRS-19:462.65:+5:141.3:141.3:G0*0E',
      );
    });
  });

  group('ChannelShare.decode', () {
    test('rejects a token with a bad checksum', () {
      expect(ChannelShare.decode('HTC:1:Calling:146.52:0:::G1*00'), isNull);
    });

    test('rejects an unsupported version', () {
      // Re-checksum a version-9 token so only the version check can fail.
      const body = 'HTC:9:Calling:146.52:0:::G1';
      int x = 0;
      for (final u in body.codeUnits) {
        x ^= u;
      }
      final cs = (x & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0');
      expect(ChannelShare.decode('$body*$cs'), isNull);
    });

    test('decodes DCS tones and fractional Hz frequency', () {
      final ch = RadioChannelInfo(
        channelId: 0,
        name: 'Repeat',
        rxFreq: 444006250,
        txFreq: 449006250,
        txSubAudio: 23, // DCS-023
        rxSubAudio: 23,
        bandwidth: RadioBandwidthType.narrow,
        txAtMaxPower: true,
      );
      final decoded = ChannelShare.decode(ChannelShare.encode(ch));
      expect(decoded, isNotNull);
      expect(decoded!.rxFreq, 444006250);
      expect(decoded.txFreq, 449006250);
      expect(decoded.txSubAudio, 23);
      expect(decoded.rxSubAudio, 23);
    });
  });

  group('round-trip', () {
    void expectRoundTrip(RadioChannelInfo ch) {
      final decoded = ChannelShare.decode(ChannelShare.encode(ch));
      expect(decoded, isNotNull);
      expect(decoded!.name, ch.name);
      expect(decoded.rxFreq, ch.rxFreq);
      expect(decoded.txFreq, ch.txFreq);
      expect(decoded.txSubAudio, ch.txSubAudio);
      expect(decoded.rxSubAudio, ch.rxSubAudio);
      expect(decoded.bandwidth, ch.bandwidth);
      expect(decoded.rxMod, ch.rxMod);
      expect(decoded.txMod, ch.txMod);
      expect(decoded.mute, ch.mute);
      expect(decoded.preDeEmphBypass, ch.preDeEmphBypass);
      expect(decoded.txDisable, ch.txDisable);
      expect(decoded.scan, ch.scan);
      expect(decoded.talkAround, ch.talkAround);
      expect(decoded.txAtMedPower, ch.txAtMedPower);
      expect(decoded.txAtMaxPower, ch.txAtMaxPower);
    }

    test('preserves every shared field', () {
      expectRoundTrip(
        RadioChannelInfo(
          channelId: 5,
          name: 'Field Day!',
          rxFreq: 147315000,
          txFreq: 147915000,
          txSubAudio: 8850,
          rxSubAudio: 23,
          bandwidth: RadioBandwidthType.wide,
          rxMod: RadioModulationType.fm,
          txMod: RadioModulationType.am,
          mute: true,
          preDeEmphBypass: true,
          txDisable: false,
          scan: true,
          talkAround: true,
          txAtMedPower: true,
          txAtMaxPower: false,
        ),
      );
    });

    test('preserves a plain simplex channel', () {
      expectRoundTrip(
        RadioChannelInfo(
          channelId: 0,
          name: 'Simplex',
          rxFreq: 146520000,
          txFreq: 146520000,
          bandwidth: RadioBandwidthType.wide,
          txAtMaxPower: true,
        ),
      );
    });
  });

  group('ChannelShare.findAll', () {
    test('extracts a token surrounded by prose', () {
      const text = 'try this one HTC:1:Calling:146.52:0:::G1*4A works great';
      final matches = ChannelShare.findAll(text);
      expect(matches, hasLength(1));
      expect(matches.first.channel.name, 'Calling');
      expect(matches.first.raw, 'HTC:1:Calling:146.52:0:::G1*4A');
    });

    test('extracts a token glued directly to surrounding text', () {
      const text = 'ch:HTC:1:Calling:146.52:0:::G1*4Ahere';
      final matches = ChannelShare.findAll(text);
      expect(matches, hasLength(1));
      expect(matches.first.channel.rxFreq, 146520000);
    });

    test('extracts two tokens from one line', () {
      const text =
          'HTC:1:Calling:146.52:0:::G1*4A HTC:1:W1AW:449.925:-5:100:100:G0*62';
      final matches = ChannelShare.findAll(text);
      expect(matches, hasLength(2));
      expect(matches[0].channel.name, 'Calling');
      expect(matches[1].channel.name, 'W1AW');
      expect(matches[1].channel.txFreq, 444925000);
    });

    test('skips a token whose checksum does not validate', () {
      const text = 'bad HTC:1:Calling:146.52:0:::G1*FF and good '
          'HTC:1:Calling:146.52:0:::G1*4A';
      final matches = ChannelShare.findAll(text);
      expect(matches, hasLength(1));
    });
  });
}
