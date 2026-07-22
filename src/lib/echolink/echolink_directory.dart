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
// echolink_directory.dart - EchoLink directory server protocol (TCP 5200).
//
// Port of the wire protocol in reference/svxlink/src/echolib/
// EchoLinkDirectory.cpp (login commands + call-list parsing). This module only
// builds/parses bytes; the TCP transport and reconnect logic are wired
// separately.
//
// Login command (sent right after connecting):
//   "l" callsign 0xAC 0xAC password 0x0D <statusline> 0x0D description 0x0D
// where <statusline> is one of:
//   ONLINE : "ONLINE3.38(HH:MM)"
//   BUSY   : "BUSY3.40(HH:MM)"
//   OFFLINE: "OFF-V3.40"
// The call-list request is the single byte "s".
//

import 'dart:convert';
import 'dart:typed_data';

import 'echolink_station.dart';

/// TCP port of an EchoLink directory server.
const int directoryServerPort = 5200;

/// Field separator used in the login command (octal \254).
const int _sep = 0xAC;

/// Carriage return record separator used by the directory protocol.
const int _cr = 0x0d;

/// Default directory server hostname (round-robin DNS).
const List<String> defaultDirectoryServers = <String>['servers.echolink.org'];

/// The presence status advertised to the directory server on login.
enum DirectoryStatus { online, busy, offline }

/// Builds the login command for the given status. [timeHHmm] (local "HH:MM")
/// is required for online/busy; it is ignored for offline.
Uint8List buildLoginCommand({
  required String callsign,
  required String password,
  String description = '',
  DirectoryStatus status = DirectoryStatus.online,
  String timeHHmm = '',
}) {
  String statusLine;
  switch (status) {
    case DirectoryStatus.online:
      statusLine = 'ONLINE3.38($timeHHmm)';
      break;
    case DirectoryStatus.busy:
      statusLine = 'BUSY3.40($timeHHmm)';
      break;
    case DirectoryStatus.offline:
      statusLine = 'OFF-V3.40';
      break;
  }

  final BytesBuilder b = BytesBuilder();
  b.addByte(0x6c); // 'l'
  b.add(latin1.encode(callsign));
  b.addByte(_sep);
  b.addByte(_sep);
  b.add(latin1.encode(password));
  b.addByte(_cr);
  b.add(latin1.encode(statusLine));
  b.addByte(_cr);
  b.add(latin1.encode(description));
  b.addByte(_cr);
  return b.toBytes();
}

/// Builds the call-list request command (the single byte "s").
Uint8List buildListRequest() => Uint8List.fromList(<int>[0x73]); // 's'

/// A parsed directory listing, split by station category.
class DirectoryListing {
  final List<StationData> stations;
  final List<StationData> links;
  final List<StationData> repeaters;
  final List<StationData> conferences;

  /// Free-text server message lines (entries whose callsign was a single space).
  final String message;

  const DirectoryListing({
    required this.stations,
    required this.links,
    required this.repeaters,
    required this.conferences,
    required this.message,
  });

  /// All entries in one list (stations + links + repeaters + conferences).
  List<StationData> get all =>
      <StationData>[...stations, ...links, ...repeaters, ...conferences];
}

/// Thrown when a directory call-list response is malformed.
class DirectoryFormatException implements Exception {
  final String message;
  const DirectoryFormatException(this.message);
  @override
  String toString() => 'DirectoryFormatException: $message';
}

int _atoi(String s) {
  final Match? m = RegExp(r'^\s*(-?\d+)').firstMatch(s);
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// Parses a complete call-list response ("@@@\n" <count> entries "+++").
/// Mirrors Directory::handleCallList. Throws [DirectoryFormatException] on a
/// malformed stream.
DirectoryListing parseStationList(Uint8List response) {
  final List<String> lines = const LineSplitter().convert(latin1.decode(response));

  int i = 0;
  if (i >= lines.length || lines[i] != '@@@') {
    throw const DirectoryFormatException('missing @@@ start marker');
  }
  i++;

  if (i >= lines.length) {
    throw const DirectoryFormatException('missing count');
  }
  int count = _atoi(lines[i]);
  i++;

  final List<StationData> entries = <StationData>[];
  final StringBuffer message = StringBuffer();

  while (count > 0) {
    if (i + 4 > lines.length) {
      throw const DirectoryFormatException('truncated station entry');
    }
    final String callsign = lines[i];
    final String data = lines[i + 1];
    final int id = _atoi(lines[i + 2]);
    final String ip = lines[i + 3];
    i += 4;

    if (callsign == '.') {
      // Separator entry: consumed but does not count towards the total.
      continue;
    }

    final StationData station = StationData.fromDirectory(
        callsign: callsign, data: data, id: id, ip: ip);

    if (callsign == ' ') {
      message.writeln(station.description);
    } else {
      entries.add(station);
    }
    count--;
  }

  if (i >= lines.length || !lines[i].startsWith('+++')) {
    throw const DirectoryFormatException('missing +++ end marker');
  }

  final List<StationData> stations = <StationData>[];
  final List<StationData> links = <StationData>[];
  final List<StationData> repeaters = <StationData>[];
  final List<StationData> conferences = <StationData>[];

  for (final StationData s in entries) {
    if (s.isLink) {
      links.add(s);
    } else if (s.isRepeater) {
      repeaters.add(s);
    } else if (s.isConference) {
      conferences.add(s);
    } else {
      stations.add(s);
    }
  }

  return DirectoryListing(
    stations: stations,
    links: links,
    repeaters: repeaters,
    conferences: conferences,
    message: message.toString(),
  );
}
