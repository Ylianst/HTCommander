import 'aprs_conversation.dart';
import 'aprs_outbox.dart';

bool isOtaPeer(String? peer) => peer != null && aprsPeerKey(peer) == 'OTA';

String otaCommandFamily(String text) {
  final tokens = text.trim().toUpperCase().split(RegExp(r'\s+'));
  final word = tokens.first.replaceAll('!', '');
  if (word.startsWith('@')) {
    return tokens.length > 1 && tokens[1] == 'QSL' ? 'QSL' : 'CHASE';
  }
  return switch (word) {
    'QRV' => 'HOST',
    'QRT' => 'DONE',
    'QRT?' => 'TIME',
    'QST' => 'BLAST',
    _ => word,
  };
}

bool otaCommandRequiresRf(String text) =>
    const {'HOST', 'QSL'}.contains(otaCommandFamily(text));

void validateOtaCommand(String text, {bool authenticated = false}) {
  final parts = splitAprsMessage(text, 'OTA', authenticated: authenticated);
  if (parts.length != 1) {
    throw const AprsComposeException(AprsComposeError.tooLong);
  }
}

/// Local estimates only: the bot also counts traffic from other clients/SSIDs.
Duration otaCommandCooldown(
  String text,
  Iterable<AprsOutgoingMessage> outbox,
  String localCallsign,
  DateTime now,
) {
  final family = otaCommandFamily(text);
  final limits = switch (family) {
    'PING' => [(2, 60), (5, 600)],
    'HOST' => [(2, 60), (3, 600)],
    'CHASE' => [(4, 60), (8, 600)],
    'BLAST' => [(4, 600), (8, 3600)],
    'CQ' || 'INFO' || 'TIME' || 'CHASERS' || 'STAY' => [(1, 180), (3, 900)],
    _ => <(int, int)>[],
  };
  final times =
      outbox
          .where(
            (m) =>
                isOtaPeer(m.destination) &&
                m.source.split('-').first ==
                    localCallsign.toUpperCase().split('-').first &&
                otaCommandFamily(m.text) == family &&
                !m.created.isAfter(now),
          )
          .map((m) => m.created)
          .toList()
        ..sort((a, b) => b.compareTo(a));
  var seconds = 0;
  for (final (count, window) in limits) {
    if (times.length < count) continue;
    final remaining = window - now.difference(times[count - 1]).inSeconds;
    if (remaining > seconds) seconds = remaining;
  }
  return Duration(seconds: seconds);
}

enum OtaReplyKind {
  ops,
  info,
  description,
  missing,
  time,
  chasers,
  pong,
  beaconHost,
  beaconChase,
  hosting,
  chasing,
  pendingQsl,
  confirmed,
  complete,
  blast,
  notice,
}

class OtaOp {
  final String station;
  final String? grid;
  final int? minutes;
  final int? qsos;
  final int? waiting;
  final int? points;
  final double? latitude;
  final double? longitude;

  const OtaOp(
    this.station,
    this.grid,
    this.minutes, {
    this.qsos,
    this.waiting,
    this.points,
    this.latitude,
    this.longitude,
  });
}

class OtaReply {
  final OtaReplyKind kind;
  final String raw;
  final String? station;
  final String? text;
  final List<OtaOp> ops;
  final List<String> stations;
  final int page;
  final int pages;
  final int total;
  final int? minutes;
  final int? cap;
  final Uri? link;

  const OtaReply(
    this.kind,
    this.raw, {
    this.station,
    this.text,
    this.ops = const [],
    this.stations = const [],
    this.page = 1,
    this.pages = 1,
    this.total = 0,
    this.minutes,
    this.cap,
    this.link,
  });
}

final _stationPattern = RegExp(r'^[A-Z0-9]{1,6}(?:-(?:[0-9]|1[0-5]))?$');
final _gridPattern = RegExp(r'^[A-Ra-r]{2}[0-9]{2}[A-Xa-x]{2}$');

bool _station(String text) =>
    _stationPattern.hasMatch(text) && RegExp(r'[A-Z]').hasMatch(text);
bool _grid(String text) => text == '_' || _gridPattern.hasMatch(text);
int? _number(String text) =>
    RegExp(r'^\d{1,6}$').hasMatch(text) ? int.tryParse(text) : null;
bool _minutes(String text) =>
    text == '_' || (_number(text) != null && _number(text)! <= 120);

Uri? _link(String text) {
  final match = RegExp(
    r'(?:https://)?aprsota\.org/[A-Za-z0-9/_-]+',
  ).firstMatch(text);
  if (match == null) return null;
  final value = match.group(0)!;
  return Uri.parse(value.startsWith('https://') ? value : 'https://$value');
}

/// Unknown/malformed text is left in the normal chat, never coerced into state.
OtaReply? decodeOtaReply(String raw) {
  final text = raw.trim();
  final t = text.split(RegExp(r'\s+'));
  if (t.first == 'CQ!' || t.first == 'CHASERS!') {
    if (t.length < 3) return null;
    final pagination = RegExp(r'^([1-3])/([1-3])$').firstMatch(t[1]);
    final total = _number(t[2]);
    if (pagination == null || total == null) return null;
    final page = int.parse(pagination[1]!);
    final pages = int.parse(pagination[2]!);
    if (page > pages) return null;
    final ops = <OtaOp>[];
    final stations = <String>[];
    if (t.first == 'CQ!') {
      for (var i = 3; i < t.length; i += 3) {
        // An appended numeric/null field is not another station record.
        if (_number(t[i]) != null || t[i] == '_') break;
        if (i + 2 >= t.length ||
            !_station(t[i]) ||
            !_grid(t[i + 1]) ||
            !_minutes(t[i + 2])) {
          return null;
        }
        ops.add(
          OtaOp(t[i], t[i + 1] == '_' ? null : t[i + 1], _number(t[i + 2])),
        );
      }
    } else {
      for (final s in t.skip(3)) {
        if (_number(s) != null || s == '_') break;
        if (!_station(s)) return null;
        stations.add(s);
      }
    }
    final count = ops.length + stations.length;
    if (count > total ||
        (total > 0 && count == 0) ||
        (total == 0 && (pages != 1 || count != 0))) {
      return null;
    }
    return OtaReply(
      t.first == 'CQ!' ? OtaReplyKind.ops : OtaReplyKind.chasers,
      raw,
      ops: ops,
      stations: stations,
      page: page,
      pages: pages,
      total: total,
    );
  }
  if (t.first == 'INFO!') {
    if (t.length < 3 || !_station(t[1])) return null;
    if (t[2] == 'NIL') {
      return OtaReply(OtaReplyKind.missing, raw, station: t[1]);
    }
    if (t[2] == 'DESC') {
      final description = RegExp(
        r'^INFO!\s+\S+\s+DESC(?:\s+(.*))?$',
      ).firstMatch(text);
      return OtaReply(
        OtaReplyKind.description,
        raw,
        station: t[1],
        text: description?.group(1) ?? '',
      );
    }
    if (t.length < 9 ||
        !_grid(t[2]) ||
        !_minutes(t[3]) ||
        t.sublist(4, 7).any((s) => _number(s) == null)) {
      return null;
    }
    return _decodeInfo(raw, t);
  }
  if (t.first == 'TIME!') {
    if (t.length < 3 || _number(t[1]) == null || _number(t[2]) == null) {
      return null;
    }
    final minutes = _number(t[1])!;
    final cap = _number(t[2])!;
    if (minutes > cap || cap > 120) return null;
    return OtaReply(OtaReplyKind.time, raw, minutes: minutes, cap: cap);
  }
  if (text.startsWith('PONG heard on RF') ||
      text.startsWith('PONG heard on APRS-IS')) {
    return OtaReply(OtaReplyKind.pong, raw, text: text);
  }
  if (text == 'Send a position report within 5 mins to go on the air') {
    return OtaReply(OtaReplyKind.beaconHost, raw);
  }
  var m = RegExp(
    r'^Send a position report within 5 mins to chase (\S+)$',
  ).firstMatch(text);
  if (m != null && _station(m[1]!)) {
    return OtaReply(OtaReplyKind.beaconChase, raw, station: m[1]);
  }
  m = RegExp(r'^DE (\S+) QSL(?: (.*))?$').firstMatch(text);
  if (m != null && _station(m[1]!)) {
    return OtaReply(OtaReplyKind.confirmed, raw, station: m[1], text: m[2]);
  }
  m = RegExp(
    r'^DE (\S+) ([A-Ra-r]{2}[0-9]{2}[A-Xa-x]{2}|_)(?: (.*))?$',
  ).firstMatch(text);
  if (m != null && _station(m[1]!)) {
    return OtaReply(OtaReplyKind.pendingQsl, raw, station: m[1], text: m[3]);
  }
  m = RegExp(r'^Now chasing (\S+)(?: .*)?$').firstMatch(text);
  if (m != null && _station(m[1]!)) {
    return OtaReply(
      OtaReplyKind.chasing,
      raw,
      station: m[1],
      link: _link(text),
    );
  }
  m = RegExp(r'^(\S+) is on the air(?: .*)?$').firstMatch(text);
  if (m != null && _station(m[1]!)) {
    return OtaReply(
      OtaReplyKind.hosting,
      raw,
      station: m[1],
      link: _link(text),
    );
  }
  if (RegExp(r'^Op complete: \d+ QSOs?, \d+ pts?\b').hasMatch(text)) {
    return OtaReply(OtaReplyKind.complete, raw, text: text, link: _link(text));
  }
  if (text.startsWith('BLAST ')) {
    return OtaReply(OtaReplyKind.blast, raw, text: text);
  }
  if (text == 'No ops on the air. Send HOST to start one.') {
    return OtaReply(OtaReplyKind.ops, raw);
  }
  if (text == 'No one is waiting on your QSL.') {
    return OtaReply(OtaReplyKind.chasers, raw);
  }
  if (const [
    'No beacon received.',
    'Beacon arrived on APRS-IS, not RF.',
    'Beacons arrived on APRS-IS, not RF.',
    'Beacons had no usable position.',
    'Beacon has no usable position.',
    'Must transmit via RF to host.',
    'Your QSL for ',
    'Your op is run by ',
    'Chase limit reached.',
    'Already chasing ',
    'Going quiet for maintenance.',
    'No position report from your client.',
    'At the 2 hour max.',
    'Staying on the air.',
    'No more blasts from ',
  ].any(text.startsWith)) {
    return OtaReply(OtaReplyKind.notice, raw, text: text);
  }
  return null;
}

OtaReply? _decodeInfo(String raw, List<String> t) {
  double? latitude;
  double? longitude;
  if (t[7] == '_' && t[8] == '_') {
    // Unplaced op.
  } else {
    latitude = double.tryParse(t[7]);
    longitude = double.tryParse(t[8]);
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
  }
  return OtaReply(
    OtaReplyKind.info,
    raw,
    station: t[1],
    ops: [
      OtaOp(
        t[1],
        t[2] == '_' ? null : t[2],
        _number(t[3]),
        qsos: _number(t[4]),
        waiting: _number(t[5]),
        points: _number(t[6]),
        latitude: latitude,
        longitude: longitude,
      ),
    ],
  );
}

class OtaReceived {
  final OtaReply reply;
  final DateTime time;
  const OtaReceived(this.reply, this.time);
}

/// Assembles only a bounded, consistent response; there is no OTA snapshot ID.
class OtaPages {
  final Map<int, OtaReceived> _pages = {};
  bool ambiguous = false;

  void add(OtaReceived received) {
    final r = received.reply;
    if (_pages.isNotEmpty) {
      final first = _pages.values.first;
      if (received.time.difference(first.time).abs() >
          const Duration(minutes: 2)) {
        _pages.clear();
        ambiguous = false;
      } else if (r.pages != first.reply.pages || r.total != first.reply.total) {
        ambiguous = true;
        return;
      }
    }
    final old = _pages[r.page];
    if (old != null && old.reply.raw != r.raw) {
      ambiguous = true;
      return;
    }
    _pages[r.page] = received;
    final names = _pages.values
        .expand(
          (p) => [...p.reply.ops.map((op) => op.station), ...p.reply.stations],
        )
        .toList();
    if (names.length > r.total || names.toSet().length != names.length) {
      ambiguous = true;
    }
  }

  List<OtaReceived> get received {
    final entries = _pages.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => e.value).toList();
  }
}
