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
// echolink_station.dart - Directory station entry model.
//
// Port of reference/svxlink/src/echolib/EchoLinkStationData.{h,cpp}. Parses the
// per-station "data" field (e.g. "Denver, CO      [On 08:30]") into a status,
// a time and a description.
//

/// Directory presence status of a station.
enum StationStatus { unknown, offline, online, busy }

class StationData {
  final String callsign;
  final StationStatus status;
  final String time;
  final String description;
  final int id;
  final String ip;

  const StationData({
    required this.callsign,
    this.status = StationStatus.unknown,
    this.time = '',
    this.description = '',
    this.id = 0,
    this.ip = '',
  });

  /// True if the callsign is a link node (suffix "-L").
  bool get isLink => callsign.endsWith('-L');

  /// True if the callsign is a repeater node (suffix "-R").
  bool get isRepeater => callsign.endsWith('-R');

  /// True if the callsign is a conference (prefix "*").
  bool get isConference => callsign.startsWith('*');

  /// Builds a station from the four directory-list fields, parsing [data] the
  /// same way as StationData::setData.
  factory StationData.fromDirectory({
    required String callsign,
    required String data,
    required int id,
    required String ip,
  }) {
    StationStatus status = StationStatus.unknown;
    String time = '';
    String description;

    final int lastBracket = data.lastIndexOf('[');
    if (lastBracket >= 0) {
      final String after = data.substring(lastBracket + 1);
      if (after.contains('ON')) {
        status = StationStatus.online;
      } else if (after.contains('BUSY')) {
        status = StationStatus.busy;
      } else {
        status = StationStatus.unknown;
      }

      final int sp = data.indexOf(' ', lastBracket);
      if (sp >= 0) {
        final int end = (sp + 6) <= data.length ? sp + 6 : data.length;
        time = data.substring(sp + 1, end);
      }

      description = _removeTrailingSpaces(data.substring(0, lastBracket));
    } else {
      description = _removeTrailingSpaces(data);
    }

    return StationData(
      callsign: callsign,
      status: status,
      time: time,
      description: description,
      id: id,
      ip: ip,
    );
  }

  static String _removeTrailingSpaces(String s) =>
      s.replaceFirst(RegExp(r' +$'), '');

  @override
  String toString() =>
      'StationData($callsign, $status, "$description", id=$id, ip=$ip)';
}
