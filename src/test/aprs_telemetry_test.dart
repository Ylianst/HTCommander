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
import 'package:htcommander/aprs/aprs_packet.dart';
import 'package:htcommander/aprs/telemetry_data.dart';
import 'package:htcommander/radio/ax25_address.dart';
import 'package:htcommander/radio/ax25_packet.dart';

void main() {
  group('TelemetryData.parse', () {
    test('decodes sequence and a single channel (|ss11|)', () {
      final t = TelemetryData.parse('ss11')!;
      expect(t.sequence, 7544);
      expect(t.analog, [1472]);
      expect(t.binaryBits, isNull);
      expect(t.binary, isEmpty);
    });

    test('decodes sequence and three channels (|ss112233|)', () {
      final t = TelemetryData.parse('ss112233')!;
      expect(t.sequence, 7544);
      expect(t.analog, [1472, 1564, 1656]);
      expect(t.binaryBits, isNull);
    });

    test('decodes five channels plus binary values (|ss1122334455!"|)', () {
      final t = TelemetryData.parse('ss1122334455!"')!;
      expect(t.sequence, 7544);
      expect(t.analog, [1472, 1564, 1656, 1748, 1840]);
      // '!"' decodes to 1: B1 set, B2..B8 clear.
      expect(t.binaryBits, 1);
      expect(t.binary, [
        true, false, false, false,
        false, false, false, false,
      ]);
    });

    test('decodes the minimal all-zero sequence (|!!!!|)', () {
      final t = TelemetryData.parse('!!!!')!;
      expect(t.sequence, 0);
      expect(t.analog, [0]);
    });

    test('rejects invalid payloads', () {
      expect(TelemetryData.parse(''), isNull);
      expect(TelemetryData.parse('ss'), isNull); // sequence only, no channel
      expect(TelemetryData.parse('ss1'), isNull); // odd length
      expect(TelemetryData.parse('ss1122334455!"66'), isNull); // too long
      expect(TelemetryData.parse('ss|1'), isNull); // non-base91 char
    });
  });

  group('AprsPacket Base91 comment telemetry', () {
    AprsPacket parseInfo(String info) {
      final packet = AX25Packet.ui([
        AX25Address.getAddress('APRS')!,
        AX25Address.getAddress('N0CALL')!,
      ], info);
      final aprs = AprsPacket.parse(packet);
      expect(aprs, isNotNull);
      return aprs!;
    }

    test('extracts telemetry from a compressed position comment', () {
      // Spec example 3.11.2: compressed position, comment text and 3 channels.
      final aprs = parseInfo("!/0%3RTh<6>dS_http://aprs.fi/|\"p%T'.ag|");
      expect(aprs.telemetry, isNotNull);
      expect(aprs.telemetry!.analog.length, 3);
      // Telemetry block is removed, free-form comment remains.
      expect(aprs.comment, 'http://aprs.fi/');
    });

    test('leaves comment untouched when no telemetry is present', () {
      final aprs = parseInfo('!/0%3RTh<6>dS_http://aprs.fi/');
      expect(aprs.telemetry, isNull);
      expect(aprs.comment, 'http://aprs.fi/');
    });

    test('strips telemetry even when the comment contains a stray pipe', () {
      // Free-form comment holds a lone '|' before the real telemetry block.
      final aprs = parseInfo("!/0%3RTh<6>dS_a|b|ss11|");
      expect(aprs.telemetry, isNotNull);
      expect(aprs.telemetry!.analog, [1472]);
      expect(aprs.comment, 'a|b');
    });
  });
}
