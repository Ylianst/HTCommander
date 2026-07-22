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

//
// echolink_directory_test.dart - EchoLink directory protocol (login commands +
// call-list parsing). Uses real captured directory responses (from
// reference/svxlink/src/echolib/messages.txt) plus synthetic station lists.
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/echolink/echolink_directory.dart';
import 'package:htcommander/echolink/echolink_station.dart';

Uint8List _resp(List<String> lines) =>
    Uint8List.fromList(latin1.encode(lines.join('\n')));

void main() {
  group('directory login commands', () {
    test('online command byte layout', () {
      final Uint8List cmd = buildLoginCommand(
        callsign: 'N0CALL',
        password: 'secret',
        description: 'HTCommander',
        status: DirectoryStatus.online,
        timeHHmm: '08:30',
      );
      final List<int> expected = <int>[
        0x6c, // 'l'
        ...latin1.encode('N0CALL'),
        0xAC, 0xAC,
        ...latin1.encode('secret'),
        0x0d,
        ...latin1.encode('ONLINE3.38(08:30)'),
        0x0d,
        ...latin1.encode('HTCommander'),
        0x0d,
      ];
      expect(cmd, orderedEquals(expected));
    });

    test('offline command has no time and OFF-V3.40', () {
      final Uint8List cmd = buildLoginCommand(
        callsign: 'N0CALL',
        password: 'pw',
        description: 'desc',
        status: DirectoryStatus.offline,
      );
      expect(latin1.decode(cmd), 'lN0CALL\xAC\xACpw\rOFF-V3.40\rdesc\r');
    });

    test('busy command uses BUSY3.40(HH:MM)', () {
      final Uint8List cmd = buildLoginCommand(
        callsign: 'W1AW',
        password: 'x',
        description: '',
        status: DirectoryStatus.busy,
        timeHHmm: '12:34',
      );
      expect(latin1.decode(cmd), 'lW1AW\xAC\xACx\rBUSY3.40(12:34)\r\r');
    });

    test('list request is a single "s"', () {
      expect(buildListRequest(), orderedEquals(<int>[0x73]));
    });
  });

  group('call-list parsing (real capture)', () {
    test('parses the "incorrect password" server-message block', () {
      // From reference/svxlink/src/echolib/messages.txt (count = 6).
      final Uint8List resp = _resp(<String>[
        '@@@',
        '6',
        '.', 'Incorrect password         [     ]', '0000', '127.0.0.1',
        '.', 'See View => Server Message [     ]', '0000', '127.0.0.1',
        ' ', 'INCORRECT PASSWORD                   ', '    ', '127.0.0.1',
        ' ', '                                     ', '    ', '127.0.0.1',
        ' ', 'Please check the password            ', '    ', '127.0.0.1',
        ' ', 'and try again. If you have           ', '    ', '127.0.0.1',
        ' ', 'forgotten it, see the Support        ', '    ', '127.0.0.1',
        ' ', 'section at www.echolink.org.         ', '    ', '127.0.0.1',
        '+++',
      ]);

      final DirectoryListing listing = parseStationList(resp);
      expect(listing.all, isEmpty);
      expect(
        listing.message,
        'INCORRECT PASSWORD\n\nPlease check the password\n'
        'and try again. If you have\nforgotten it, see the Support\n'
        'section at www.echolink.org.\n',
      );
    });
  });

  group('call-list parsing (stations)', () {
    test('categorizes and parses station fields', () {
      // Real-shaped lines from messages.txt.
      final Uint8List resp = _resp(<String>[
        '@@@',
        '4',
        '*ECSEA*', 'Panama City, Fl. [0/8]     [ON 16:08]', '172277', '24.214.38.68',
        'IW2LXR', 'Vittorio Milano            [ON 23:07]', '29136', '219.113.182.123',
        'K6IRF-R', 'Claremont, CA              [ON 13:49]', '13887', '216.117.200.62',
        'KC5LOS-L', 'Beeville, TX               [BUSY 15:08]', '62280', '67.67.253.16',
        '+++',
      ]);

      final DirectoryListing d = parseStationList(resp);
      expect(d.conferences.length, 1);
      expect(d.stations.length, 1);
      expect(d.repeaters.length, 1);
      expect(d.links.length, 1);

      final StationData conf = d.conferences.single;
      expect(conf.callsign, '*ECSEA*');
      expect(conf.status, StationStatus.online);
      expect(conf.time, '16:08');
      expect(conf.description, 'Panama City, Fl. [0/8]');
      expect(conf.id, 172277);
      expect(conf.ip, '24.214.38.68');

      final StationData stn = d.stations.single;
      expect(stn.callsign, 'IW2LXR');
      expect(stn.description, 'Vittorio Milano');
      expect(stn.ip, '219.113.182.123');

      final StationData link = d.links.single;
      expect(link.callsign, 'KC5LOS-L');
      expect(link.status, StationStatus.busy);
      expect(link.time, '15:08');
    });

    test('handles a zero-count listing', () {
      final DirectoryListing d = parseStationList(_resp(<String>['@@@', '0', '+++']));
      expect(d.all, isEmpty);
      expect(d.message, isEmpty);
    });
  });

  group('malformed responses', () {
    test('missing start marker throws', () {
      expect(() => parseStationList(_resp(<String>['???', '0', '+++'])),
          throwsA(isA<DirectoryFormatException>()));
    });

    test('missing end marker throws', () {
      expect(
          () => parseStationList(_resp(<String>[
                '@@@',
                '1',
                'N0CALL', 'desc [ON 00:00]', '1', '1.2.3.4',
              ])),
          throwsA(isA<DirectoryFormatException>()));
    });

    test('truncated entry throws', () {
      expect(
          () => parseStationList(_resp(<String>['@@@', '1', 'N0CALL', 'desc'])),
          throwsA(isA<DirectoryFormatException>()));
    });
  });

  group('StationData.fromDirectory', () {
    test('parses status/time/description with a bracket', () {
      final StationData s = StationData.fromDirectory(
          callsign: 'AB1CD', data: 'Somewhere        [ON 09:15]', id: 42, ip: '10.0.0.1');
      expect(s.status, StationStatus.online);
      expect(s.time, '09:15');
      expect(s.description, 'Somewhere');
    });

    test('no bracket means unknown status and full description', () {
      final StationData s = StationData.fromDirectory(
          callsign: 'AB1CD', data: 'Just a note    ', id: 0, ip: '');
      expect(s.status, StationStatus.unknown);
      expect(s.time, '');
      expect(s.description, 'Just a note');
    });
  });
}
