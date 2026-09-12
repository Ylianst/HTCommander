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
import 'package:htcommander/utils/channel_import.dart';

const _chirpHeader =
    'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,'
    'DtcsPolarity,RxDtcsCode,CrossMode,Mode,TStep,Skip,Power,Comment,URCALL,'
    'RPT1CALL,RPT2CALL,DVCODE';

void main() {
  group('ChannelImport CHIRP CSV', () {
    test('imports a simplex FM channel', () {
      final csv =
          '$_chirpHeader\n'
          '1,Simplex,146.520000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final channels = ChannelImport.parseChannelsFromCsv(csv);
      expect(channels, hasLength(1));
      final c = channels.single;
      expect(c.name, 'Simplex');
      expect(c.rxFreq, 146520000);
      expect(c.txFreq, 146520000);
      expect(c.rxMod, RadioModulationType.fm);
      expect(c.bandwidth, RadioBandwidthType.wide);
      expect(c.txDisable, isFalse);
    });

    test('applies positive offset and CTCSS tone on a repeater', () {
      final csv =
          '$_chirpHeader\n'
          '2,W1AW,147.380000,+,0.600000,Tone,100.0,100.0,023,NN,023,Tone->Tone,NFM,5.00,,5W,,,,,';
      final c = ChannelImport.parseChannelsFromCsv(csv).single;
      expect(c.rxFreq, 147380000);
      expect(c.txFreq, 147980000);
      expect(c.txSubAudio, 10000); // 100.0 Hz * 100
      expect(c.rxSubAudio, 0); // Tone (encode only)
      expect(c.bandwidth, RadioBandwidthType.narrow);
    });

    test('still parses when the file starts with a UTF-8 BOM', () {
      final csv =
          '\uFEFF$_chirpHeader\n'
          '1,BOMtest,146.520000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final channels = ChannelImport.parseChannelsFromCsv(csv);
      expect(channels, hasLength(1));
      expect(channels.single.name, 'BOMtest');
    });

    test('handles a quoted field that contains a comma', () {
      final csv =
          '$_chirpHeader\n'
          '1,"Simp, x",146.520000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final c = ChannelImport.parseChannelsFromCsv(csv).single;
      expect(c.name, 'Simp, x');
      expect(c.rxFreq, 146520000);
    });

    test('skips channels with unsupported digital/broadcast modes', () {
      final csv =
          '$_chirpHeader\n'
          '1,DStar,145.000000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,DV,5.00,,5W,,,,,\n'
          '2,Fusion,145.010000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,DN,5.00,,5W,,,,,\n'
          '3,Broadcast,100.100000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,WFM,5.00,,5W,,,,,\n'
          '4,DMRch,440.000000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,DMR,5.00,,5W,,,,,\n'
          '5,GoodFM,146.520000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final channels = ChannelImport.parseChannelsFromCsv(csv);
      expect(channels, hasLength(1));
      expect(channels.single.name, 'GoodFM');
    });

    test('skips DMR channels', () {
      final csv =
          '$_chirpHeader\n'
          '1,DMRch,440.000000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,DMR,5.00,,5W,,,,,';
      expect(ChannelImport.parseChannelsFromCsv(csv), isEmpty);
    });

    test('skips rows with a missing or invalid frequency', () {
      final csv =
          '$_chirpHeader\n'
          '1,Empty,,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,\n'
          '2,Good,146.520000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final channels = ChannelImport.parseChannelsFromCsv(csv);
      expect(channels, hasLength(1));
      expect(channels.single.name, 'Good');
    });

    test('disables transmit when Duplex is off', () {
      final csv =
          '$_chirpHeader\n'
          '1,RxOnly,162.400000,off,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final c = ChannelImport.parseChannelsFromCsv(csv).single;
      expect(c.txDisable, isTrue);
      expect(c.txFreq, c.rxFreq);
    });

    test('reads a split-duplex transmit frequency from the Offset column', () {
      final csv =
          '$_chirpHeader\n'
          '1,Split,145.800000,split,437.800000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final c = ChannelImport.parseChannelsFromCsv(csv).single;
      expect(c.rxFreq, 145800000);
      expect(c.txFreq, 437800000);
    });

    test('parses a semicolon-delimited export with decimal commas', () {
      final header = _chirpHeader.replaceAll(',', ';');
      final csv =
          '$header\n'
          '1;Euro;146,520000;;0,000000;;88.5;88.5;023;NN;023;Tone->Tone;FM;5.00;;5W;;;;;';
      final c = ChannelImport.parseChannelsFromCsv(csv).single;
      expect(c.name, 'Euro');
      expect(c.rxFreq, 146520000);
    });

    test('clamps names longer than 10 characters', () {
      final csv =
          '$_chirpHeader\n'
          '1,ThisNameIsWayTooLong,146.520000,,0.000000,,88.5,88.5,023,NN,023,Tone->Tone,FM,5.00,,5W,,,,,';
      final c = ChannelImport.parseChannelsFromCsv(csv).single;
      expect(c.name, 'ThisNameIs');
    });

    test('returns an empty list for an unrecognised header', () {
      final channels = ChannelImport.parseChannelsFromCsv(
        'foo,bar,baz\n1,2,3',
      );
      expect(channels, isEmpty);
    });
  });
}
