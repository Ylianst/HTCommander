/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

The BBS text menu, shared by radio clients (AX.25, XARA...) and the HTTP BBS.

Besides the software information, it offers a message board, the stations
that recently connected, the APRS messages this station received (all, or only
the ones addressed to the caller), a file area (see bbs_files.dart) and, when an
offline callsign database is installed, callsign lookups. Clients that keep a
session state map also get a few text games (see bbs_games.dart).
*/

import 'dart:async';
import 'dart:math' as math;

import '../aprs/aprs_packet.dart';
import '../aprs/message_data.dart';
import '../aprs/packet_data_type.dart';
import '../aprsis/aprsis_manager.dart';
import '../callsign/callsign_record.dart';
import '../services/callsign_lookup_service.dart';
import '../services/data_broker.dart';
import 'aprs_handler.dart';
import 'bbs_files.dart';
import 'bbs_games.dart';
import 'bbs_settings.dart';
import 'bbs_store.dart';

/// Reply to a single BBS menu command.
class BbsMenuReply {
  /// Text to send back (lines terminated by `\r`).
  final String text;

  /// The client asked to end the session.
  final bool disconnect;

  /// A file the transport should send to the client after [text]. For YAPP
  /// the prompt is left to the transport, to send once the transfer ends.
  final BbsFile? download;

  const BbsMenuReply(this.text, {this.disconnect = false, this.download});
}

/// How a client can exchange files with the BBS.
enum BbsFileTransfer {
  /// No file transfer (e.g. XARA links): files can only be listed.
  none,

  /// YAPP over an AX.25 connected session.
  yapp,

  /// HTTP downloads and uploads from the web BBS page.
  web,
}

/// An APRS message received by this station, as listed by the BBS.
class BbsAprsMessage {
  const BbsAprsMessage({
    required this.time,
    required this.source,
    required this.addressee,
    required this.text,
  });

  final DateTime time;
  final String source;
  final String addressee;
  final String text;
}

/// Looks up a callsign (no SSID) in the offline callsign database.
typedef BbsCallsignLookup = Future<CallsignRecord?> Function(String callsign);

/// The BBS menu. Each command is a line starting with a command word, optionally
/// followed by an argument (e.g. `B 20`, `P Hello all`, `C W1AW`).
class BbsMenu {
  BbsMenu({
    BbsStore? store,
    BbsFileStore? files,
    List<AprsPacket> Function()? aprsPackets,
    bool Function()? callsignLookupAvailable,
    BbsCallsignLookup? callsignLookup,
    String Function()? stationCallsign,
    DateTime Function()? clock,
    math.Random? random,
  }) : _games = BbsGames(random ?? math.Random()),
       _storeOverride = store,
       _filesOverride = files,
       _aprsPackets = aprsPackets ?? _defaultAprsPackets,
       _lookupAvailable =
           callsignLookupAvailable ??
           (() => CallsignLookupService.instance.isAvailable),
       _lookup = callsignLookup ?? _defaultLookup,
       _stationCallsign = stationCallsign ?? _defaultStationCallsign,
       _clock = clock ?? DateTime.now;

  static const String banner = 'Handy-Talky Commander BBS\r[M] for menu\r';

  /// Sent to stations the access list keeps out, before disconnecting.
  static const String accessDenied =
      'Handy-Talky Commander BBS\rAccess denied, goodbye.\r';

  /// Prompt sent after every reply.
  static const String prompt = '>\r';

  /// Number of entries listed when no count is given.
  static const int defaultCount = 10;

  /// Most entries listed at once, to keep replies short on slow radio links.
  static const int maxCount = 50;

  final BbsStore? _storeOverride;
  final BbsFileStore? _filesOverride;
  final List<AprsPacket> Function() _aprsPackets;
  final bool Function() _lookupAvailable;
  final BbsCallsignLookup _lookup;
  final String Function() _stationCallsign;
  final DateTime Function() _clock;
  final BbsGames _games;

  BbsStore get store => _storeOverride ?? BbsStore.instance;

  BbsFileStore get files => _filesOverride ?? BbsFileStore.instance;

  bool get _hasCallsignLookup {
    if (!BbsSettings.load().callsignLookupEnabled) return false;
    try {
      return _lookupAvailable();
    } catch (_) {
      return false;
    }
  }

  static List<AprsPacket> _defaultAprsPackets() => [
    ...?DataBroker.getDataHandler<AprsHandler>('AprsHandler')?.getAprsFrames(),
    ...?DataBroker.getDataHandler<AprsIsManager>(
      'AprsIsManager',
    )?.historyPackets,
  ];

  static Future<CallsignRecord?> _defaultLookup(String callsign) async =>
      (await CallsignLookupService.instance.lookup(callsign))?.record;

  static String _defaultStationCallsign() =>
      DataBroker.getValue<String>(0, 'CallSign', '') ?? '';

  // ---- session start --------------------------------------------------------

  /// Records that [callsign] connected over [protocol] and returns a short
  /// greeting to send after the [banner], summarizing what is new since the
  /// station's last visit.
  String welcome(String callsign, String protocol) {
    final call = callsign.trim().toUpperCase();
    if (call.isEmpty) return '';
    final previous = store.recordVisit(call, protocol, time: _clock());
    final settings = BbsSettings.load();
    final news = _hasAnnouncement(settings)
        ? 'There is an announcement, [N] to read it.\r'
        : '';
    final sb = StringBuffer();
    if (previous == null) {
      sb.write('Welcome $call!\r');
      final count = store.messages.length;
      if (count > 0) {
        sb.write('${_plural(count, 'message')} on the board, [B] to list.\r');
      }
      sb.write(news);
      return sb.toString();
    }

    sb.write('Welcome back $call, last visit ${_date(previous.lastSeen)}.\r');
    final base = _baseCall(call);
    final newPosts = store.messages
        .where(
          (m) =>
              m.time.isAfter(previous.lastSeen) &&
              _baseCall(m.callsign) != base,
        )
        .length;
    if (newPosts > 0) {
      sb.write('${_plural(newPosts, 'new board message')}, [B] to list.\r');
    }
    final newAprs = !settings.aprsMessagesEnabled
        ? 0
        : aprsMessages()
              .where(
                (m) =>
                    m.time.isAfter(previous.lastSeen) &&
                    _baseCall(m.addressee) == base,
              )
              .length;
    if (newAprs > 0) {
      sb.write(
        '${_plural(newAprs, 'new APRS message')} for you, [AM] to list.\r',
      );
    }
    sb.write(news);
    return sb.toString();
  }

  // ---- commands -------------------------------------------------------------

  /// Handles a [line] typed by [callsign]. Returns the reply right away, or a
  /// future for commands that need to wait (callsign lookup). Replies other
  /// than a disconnect end with the [prompt], except YAPP downloads (the
  /// transport sends the prompt when the transfer ends). [transfer] says how
  /// this client can exchange files. [session] is the client's session state,
  /// needed to play games; while a game runs, lines go to the game.
  FutureOr<BbsMenuReply> handleLine(
    String callsign,
    String line, {
    BbsFileTransfer transfer = BbsFileTransfer.none,
    Map<String, Object?>? session,
  }) {
    if (session != null && BbsGames.isPlaying(session)) {
      return _withPrompt(BbsMenuReply(_games.play(session, line)));
    }
    final trimmed = line.trim();
    final space = trimmed.indexOf(RegExp(r'\s'));
    final key = (space > 0 ? trimmed.substring(0, space) : trimmed)
        .toUpperCase();
    final arg = space > 0 ? trimmed.substring(space + 1).trim() : '';
    final caller = callsign.trim().toUpperCase();

    switch (key) {
      case 'D' || 'DISC' || 'DISCONNECT' || 'BYE' || 'QUIT':
        return const BbsMenuReply('', disconnect: true);
      case 'C' || 'CALL' || 'LOOKUP':
        if (_hasCallsignLookup) {
          return _callsignLookup(caller, arg).then(_withPrompt);
        }
        return _withPrompt(
          const BbsMenuReply('Callsign lookup is not available on this BBS.\r'),
        );
      case 'DL' || 'GET' || 'DOWNLOAD':
        final reply = _download(arg, transfer);
        return reply.download != null && transfer == BbsFileTransfer.yapp
            ? reply
            : _withPrompt(reply);
    }

    final settings = BbsSettings.load();
    const aprsOff = 'APRS features are not available on this BBS.\r';
    final String text = switch (key) {
      'M' ||
      'MENU' ||
      'H' ||
      'HELP' ||
      '?' => _menuText(caller, transfer, settings, games: session != null),
      'S' || 'SOFTWARE' => _softwareText,
      'N' || 'NEWS' => _announcement(settings),
      'B' || 'BOARD' => _board(arg),
      'R' || 'READ' => _read(arg),
      'P' || 'POST' => _post(caller, arg),
      'K' || 'KILL' || 'DEL' || 'DELETE' => _delete(caller, arg),
      'A' || 'APRS' =>
        settings.aprsMessagesEnabled
            ? _aprs(caller, arg, toCaller: false)
            : aprsOff,
      'AM' =>
        settings.aprsMessagesEnabled
            ? _aprs(caller, arg, toCaller: true)
            : aprsOff,
      'AP' => settings.aprsLookupEnabled ? _aprsStation(arg) : aprsOff,
      'AH' => settings.aprsHeardEnabled ? _aprsHeard(arg) : aprsOff,
      'L' || 'LAST' => _lastVisitors(arg),
      'F' || 'FILES' || 'DIR' || 'LS' => _listFiles(arg, transfer),
      'UL' || 'PUT' || 'UPLOAD' => _upload(transfer),
      'FK' || 'FKILL' || 'FDEL' => _deleteFile(caller, arg),
      'G' || 'GAME' || 'GAMES' =>
        session == null
            ? 'Games are not available on this connection.\r'
            : _games.command(session, arg),
      _ => 'Unknown command, [M] for menu\r',
    };
    return _withPrompt(BbsMenuReply(text));
  }

  static BbsMenuReply _withPrompt(BbsMenuReply reply) => reply.disconnect
      ? reply
      : BbsMenuReply('${reply.text}$prompt', download: reply.download);

  /// The main menu. Listing commands show how many entries they have, e.g.
  /// `List board messages (3)`.
  String _menuText(
    String caller,
    BbsFileTransfer transfer,
    BbsSettings settings, {
    required bool games,
  }) {
    final sb = StringBuffer();
    final welcome = settings.welcomeMessage.trim();
    if (welcome.isNotEmpty) sb.write('${_toBbsText(welcome)}\r');
    sb
      ..write('---\r')
      ..write('[M]ain menu\r');
    if (_hasAnnouncement(settings)) {
      sb.write('[N]ews          Read the announcement\r');
    }
    sb
      ..write(
        '[B]oard [n]     List board messages (${store.messages.length})\r',
      )
      ..write('[R]ead <#>      Read a board message\r')
      ..write('[P]ost <text>   Post on the board\r')
      ..write('[K]ill <#>      Delete your board message\r');
    if (settings.aprsMessagesEnabled) {
      final aprs = aprsMessages();
      final base = _baseCall(caller);
      final aprsForCaller = aprs
          .where((m) => _baseCall(m.addressee) == base)
          .length;
      sb
        ..write('[A]PRS [n]      APRS messages heard (${aprs.length})\r')
        ..write('[AM] [n]        APRS messages for you ($aprsForCaller)\r');
    }
    if (settings.aprsLookupEnabled) {
      sb.write('[AP] <call>     APRS station position and weather\r');
    }
    if (settings.aprsHeardEnabled) {
      sb.write('[AH] [n]        APRS stations heard\r');
    }
    sb.write('[L]ast [n]      Stations that connected (${store.visitCount})\r');
    if (files.isAvailable) {
      sb.write('[F]iles [n]     List files (${files.list().length})\r');
      if (transfer != BbsFileTransfer.none) {
        sb.write('[DL] <#>        Download a file\r');
        if (files.uploadsEnabled) {
          sb.write('[UL]            Upload a file\r');
        }
      }
      sb.write('[FK] <#>        Delete your file\r');
    }
    if (_hasCallsignLookup) {
      sb.write('[C]all <call>   Callsign lookup\r');
    }
    if (games && BbsGames.anyEnabled) {
      sb.write('[G]ames [#]     Play a text game\r');
    }
    sb
      ..write('[S]oftware information\r')
      ..write('[D]isconnect\r')
      ..write('---\r');
    return sb.toString();
  }

  static const String _softwareText =
      'This BBS is run by Handy-Talky Commander, an open source software '
      'available at https://github.com/Ylianst/HTCommander. This BBS can '
      'also handle Winlink messages in a limited way.\r';

  /// Multi-line sysop text with `\r` line endings and no control characters.
  static String _toBbsText(String text) => text
      .replaceAll('\r\n', '\r')
      .replaceAll('\n', '\r')
      .replaceAll(RegExp(r'[\x00-\x0C\x0E-\x1F\x7F]'), ' ');

  static bool _hasAnnouncement(BbsSettings settings) =>
      settings.announcementEnabled &&
      settings.announcementText.trim().isNotEmpty;

  static String _announcement(BbsSettings settings) =>
      _hasAnnouncement(settings)
      ? '${_toBbsText(settings.announcementText.trim())}\r'
      : 'There is no announcement.\r';

  /// Parses an optional entry count; null when [arg] is not a valid count.
  static int? _count(String arg) {
    if (arg.isEmpty) return defaultCount;
    final n = int.tryParse(arg);
    if (n == null || n < 1) return null;
    return math.min(n, maxCount);
  }

  /// Parses a message number, accepting an optional leading `#`.
  static int? _number(String arg) {
    final s = arg.startsWith('#') ? arg.substring(1) : arg;
    final n = int.tryParse(s.trim());
    return n == null || n < 1 ? null : n;
  }

  // ---- message board --------------------------------------------------------

  String _board(String arg) {
    final count = _count(arg);
    if (count == null) return 'Usage: B [count], up to $maxCount\r';
    final all = store.messages;
    if (all.isEmpty) {
      return 'The board is empty. Use P <text> to post the first message.\r';
    }
    final shown = all.sublist(math.max(0, all.length - count));
    final sb = StringBuffer(
      shown.length == all.length
          ? 'Message board, ${_plural(all.length, 'message')}:\r'
          : 'Message board, last ${shown.length} of ${all.length} messages:\r',
    );
    for (final m in shown) {
      sb.write(_messageText(m));
    }
    return sb.toString();
  }

  static String _messageText(BbsBoardMessage m) =>
      '#${m.id} ${m.callsign} ${_date(m.time)}\r  ${m.text}\r';

  String _read(String arg) {
    final id = _number(arg);
    if (id == null) return 'Usage: R <message number>\r';
    final m = store.message(id);
    if (m == null) return 'Message #$id not found.\r';
    return _messageText(m);
  }

  String _post(String caller, String arg) {
    // Control characters could garble other users' terminals.
    final text = arg
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const max = BbsStore.maxMessageLength;
    if (text.isEmpty) return 'Usage: P <message>, up to $max characters\r';
    if (text.length > max) {
      return 'Message too long (${text.length} characters, max $max).\r';
    }
    final m = store.post(caller, text, time: _clock());
    return 'Message #${m.id} posted.\r';
  }

  String _delete(String caller, String arg) {
    final id = _number(arg);
    if (id == null) return 'Usage: K <message number>\r';
    final m = store.message(id);
    if (m == null) return 'Message #$id not found.\r';
    final base = _baseCall(caller);
    final sysop = _baseCall(_stationCallsign());
    if (_baseCall(m.callsign) != base && (sysop.isEmpty || base != sysop)) {
      return 'Message #$id was posted by ${m.callsign}, '
          'you can only delete your own messages.\r';
    }
    store.delete(id);
    return 'Message #$id deleted.\r';
  }

  // ---- visitors -------------------------------------------------------------

  String _lastVisitors(String arg) {
    final count = _count(arg);
    if (count == null) return 'Usage: L [count], up to $maxCount\r';
    final visits = store.recentVisits(count);
    if (visits.isEmpty) return 'No stations have connected yet.\r';
    final now = _clock();
    final sb = StringBuffer(
      visits.length == 1
          ? 'Last station to connect:\r'
          : 'Last ${visits.length} stations to connect:\r',
    );
    for (final v in visits) {
      sb.write(
        '${v.callsign.padRight(10)} ${_date(v.lastSeen)} '
        '${_ago(now, v.lastSeen).padRight(8)} ${v.protocol.padRight(6)} '
        '${_plural(v.count, 'visit')}\r',
      );
    }
    return sb.toString();
  }

  // ---- APRS -----------------------------------------------------------------

  /// APRS messages received by this station (over the air or from APRS-IS),
  /// oldest first. Acks, rejects, bulletins and our own messages are excluded,
  /// as are repeats of the same message.
  List<BbsAprsMessage> aprsMessages() {
    List<AprsPacket> packets;
    try {
      packets = _aprsPackets();
    } catch (_) {
      return const [];
    }
    final seen = <String>{};
    final out = <BbsAprsMessage>[];
    for (final p in packets) {
      final ax25 = p.packet;
      if (ax25 == null || !ax25.incoming) continue;
      if (p.dataType != PacketDataType.message) continue;
      final data = p.messageData;
      if (data.msgType != MessageType.mtGeneral) continue;
      final text = data.msgText.trim();
      if (text.isEmpty) continue;
      final source = _displayCall(p.sourceCallsignWithId);
      final addressee = _displayCall(data.addressee);
      // Bulletins, announcements and weather alerts are not user messages.
      if (RegExp(r'^(BLN|NWS)').hasMatch(addressee)) continue;
      // Senders repeat a message until acknowledged, and it may also be heard
      // both over the air and from APRS-IS.
      if (!seen.add('$source|$addressee|${data.seqId}|$text')) continue;
      out.add(
        BbsAprsMessage(
          time: ax25.time,
          source: source,
          addressee: addressee,
          text: text.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' '),
        ),
      );
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  String _aprs(String caller, String arg, {required bool toCaller}) {
    final count = _count(arg);
    if (count == null) {
      return 'Usage: ${toCaller ? 'AM' : 'A'} [count], up to $maxCount\r';
    }
    final base = _baseCall(caller);
    var messages = aprsMessages();
    if (toCaller) {
      messages = messages.where((m) => _baseCall(m.addressee) == base).toList();
    }
    if (messages.isEmpty) {
      return toCaller
          ? 'No APRS messages for $base have been received.\r'
          : 'No APRS messages have been received.\r';
    }
    final shown = messages.sublist(math.max(0, messages.length - count));
    final suffix = toCaller ? ' for $base' : ' heard';
    final sb = StringBuffer(
      shown.length == messages.length
          ? '${_plural(shown.length, 'APRS message')}$suffix:\r'
          : 'Last ${shown.length} of ${messages.length} '
                'APRS messages$suffix:\r',
    );
    for (final m in shown) {
      sb.write('${_date(m.time)} ${m.source} > ${m.addressee}: ${m.text}\r');
    }
    return sb.toString();
  }

  /// Incoming APRS packets with a source station.
  List<AprsPacket> _heardPackets() {
    try {
      return _aprsPackets()
          .where(
            (p) =>
                p.packet?.incoming == true && p.sourceCallsignWithId.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The last position, comment and weather heard from a station.
  String _aprsStation(String arg) {
    final call = _displayCall(arg.split(RegExp(r'\s')).first);
    if (!RegExp(r'^[A-Z0-9/\-]{3,12}$').hasMatch(call)) {
      return 'Usage: AP <callsign>\r';
    }
    final matches = _heardPackets().where((p) {
      final source = _displayCall(p.sourceCallsignWithId);
      return source == call ||
          (!call.contains('-') && _baseCall(source) == call);
    }).toList()..sort((a, b) => a.packet!.time.compareTo(b.packet!.time));
    if (matches.isEmpty) return 'No APRS station $call has been heard.\r';

    final now = _clock();
    final last = matches.last;
    final station = _displayCall(last.sourceCallsignWithId);
    final fromStation = matches
        .where((p) => _displayCall(p.sourceCallsignWithId) == station)
        .toList();
    final sb = StringBuffer(
      '$station last heard ${_date(last.packet!.time)} '
      '(${_ago(now, last.packet!.time)})\r',
    );
    final positioned = fromStation
        .where((p) => p.position.isValid())
        .lastOrNull;
    if (positioned != null) {
      final c = positioned.position.coordinateSet;
      final grid = positioned.position.gridsquare;
      sb.write(
        'Position: ${c.latitude.value.toStringAsFixed(4)}, '
        '${c.longitude.value.toStringAsFixed(4)}'
        '${grid.isEmpty ? '' : ' ($grid)'}, '
        '${_ago(now, positioned.packet!.time)}\r',
      );
      final comment = positioned.comment
          .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
          .trim();
      if (comment.isNotEmpty) sb.write('Comment: $comment\r');
    }
    final weather = fromStation
        .where((p) => p.weather?.hasData == true)
        .lastOrNull;
    if (weather != null) {
      sb.write(
        'Weather: ${weather.weather!.toReadableString()}, '
        '${_ago(now, weather.packet!.time)}\r',
      );
    }
    return sb.toString();
  }

  /// The stations heard most recently, newest first.
  String _aprsHeard(String arg) {
    final count = _count(arg);
    if (count == null) return 'Usage: AH [count], up to $maxCount\r';
    final latest = <String, AprsPacket>{};
    for (final p in _heardPackets()) {
      final call = _displayCall(p.sourceCallsignWithId);
      final prev = latest[call];
      if (prev == null || !p.packet!.time.isBefore(prev.packet!.time)) {
        latest[call] = p;
      }
    }
    if (latest.isEmpty) return 'No APRS stations have been heard.\r';
    final stations = latest.entries.toList()
      ..sort((a, b) => b.value.packet!.time.compareTo(a.value.packet!.time));
    final shown = stations.take(count).toList();
    final now = _clock();
    final sb = StringBuffer(
      shown.length == stations.length
          ? '${_plural(shown.length, 'APRS station')} heard:\r'
          : 'Last ${shown.length} of ${stations.length} APRS stations heard:\r',
    );
    for (final e in shown) {
      final p = e.value;
      final grid = p.position.isValid() ? ' ${p.position.gridsquare}' : '';
      sb.write(
        '${e.key.padRight(10)} ${_ago(now, p.packet!.time).padRight(8)}$grid\r',
      );
    }
    return sb.toString();
  }

  // ---- files ----------------------------------------------------------------

  static const String _noFileArea = 'There is no file area on this BBS.\r';

  String _listFiles(String arg, BbsFileTransfer transfer) {
    if (!files.isAvailable) return _noFileArea;
    final count = _count(arg);
    if (count == null) return 'Usage: F [count], up to $maxCount\r';
    final all = files.list();
    final canUpload = transfer != BbsFileTransfer.none && files.uploadsEnabled;
    if (all.isEmpty) {
      return canUpload
          ? 'There are no files yet. Use UL to upload the first one.\r'
          : 'There are no files yet.\r';
    }
    final shown = all.sublist(math.max(0, all.length - count));
    final sb = StringBuffer(
      shown.length == all.length
          ? 'Files, ${all.length}:\r'
          : 'Files, last ${shown.length} of ${all.length}:\r',
    );
    final width = math.min(
      24,
      shown.fold<int>(0, (w, f) => math.max(w, f.name.length)),
    );
    for (final f in shown) {
      final uploader = f.uploader.isEmpty ? '' : ' ${f.uploader}';
      sb.write(
        '#${f.id} ${f.name.padRight(width)} ${_size(f.size).padLeft(8)} '
        '${_date(f.time)}$uploader\r',
      );
    }
    sb.write(switch (transfer) {
      BbsFileTransfer.none =>
        'Downloads need an AX.25 connection or the web BBS.\r',
      _ =>
        canUpload
            ? 'DL <#> to download, UL to upload.\r'
            : 'DL <#> to download.\r',
    });
    return sb.toString();
  }

  BbsMenuReply _download(String arg, BbsFileTransfer transfer) {
    if (!files.isAvailable) return const BbsMenuReply(_noFileArea);
    if (arg.isEmpty) {
      return const BbsMenuReply('Usage: DL <file number or name>\r');
    }
    final file = files.find(arg);
    if (file == null) {
      return BbsMenuReply('File $arg not found, F to list files.\r');
    }
    final what = '${file.name} (${_size(file.size)})';
    return switch (transfer) {
      BbsFileTransfer.none => const BbsMenuReply(
        'Downloads need an AX.25 connection or the web BBS.\r',
      ),
      BbsFileTransfer.yapp => BbsMenuReply(
        'Sending $what with YAPP...\r',
        download: file,
      ),
      BbsFileTransfer.web => BbsMenuReply(
        'Downloading $what...\r',
        download: file,
      ),
    };
  }

  String _upload(BbsFileTransfer transfer) {
    if (!files.isAvailable) return _noFileArea;
    if (!files.uploadsEnabled) return 'Uploads are disabled on this BBS.\r';
    final max = _size(BbsFileStore.maxUploadBytes);
    return switch (transfer) {
      BbsFileTransfer.none =>
        'Uploads need an AX.25 connection or the web BBS.\r',
      BbsFileTransfer.yapp =>
        'Ready to receive. Send your file with YAPP now, up to $max.\r',
      BbsFileTransfer.web =>
        'Use the Upload button at the top of the page, up to $max.\r',
    };
  }

  String _deleteFile(String caller, String arg) {
    if (!files.isAvailable) return _noFileArea;
    if (arg.isEmpty) return 'Usage: FK <file number or name>\r';
    final file = files.find(arg);
    if (file == null) return 'File $arg not found.\r';
    final base = _baseCall(caller);
    final sysop = _baseCall(_stationCallsign());
    final isSysop = sysop.isNotEmpty && base == sysop;
    if (!isSysop && _baseCall(file.uploader) != base) {
      return file.uploader.isEmpty
          ? 'File #${file.id} was added by the sysop, '
                'you can only delete your own files.\r'
          : 'File #${file.id} was uploaded by ${file.uploader}, '
                'you can only delete your own files.\r';
    }
    if (!files.delete(file.id)) {
      return 'File #${file.id} could not be deleted.\r';
    }
    return 'File #${file.id} ${file.name} deleted.\r';
  }

  /// A file size for display, e.g. `512 bytes`, `12.3 KB`, `1.5 MB`.
  static String _size(int bytes) {
    if (bytes < 1024) return bytes == 1 ? '1 byte' : '$bytes bytes';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ---- callsign lookup ------------------------------------------------------

  Future<BbsMenuReply> _callsignLookup(String caller, String arg) async {
    var call = (arg.isEmpty ? caller : arg.split(RegExp(r'\s')).first)
        .toUpperCase();
    final dash = call.indexOf('-');
    if (dash > 0) call = call.substring(0, dash);
    if (!RegExp(r'^[A-Z0-9]{3,8}$').hasMatch(call) ||
        !call.contains(RegExp(r'[0-9]'))) {
      return const BbsMenuReply('Usage: C <callsign>\r');
    }
    CallsignRecord? record;
    try {
      record = await _lookup(call);
    } catch (_) {
      return BbsMenuReply('Lookup of $call failed.\r');
    }
    if (record == null) {
      return BbsMenuReply('$call was not found in the callsign database.\r');
    }
    final sb = StringBuffer(
      record.name.isEmpty
          ? '${record.callsign}\r'
          : '${record.callsign}: ${record.name}\r',
    );
    final license = [
      record.operatorClassName,
      record.statusName,
    ].where((s) => s.isNotEmpty).join(', ');
    if (license.isNotEmpty) sb.write('License: $license\r');
    if (record.qualificationsName.isNotEmpty) {
      sb.write('Qualifications: ${record.qualificationsName}\r');
    }
    if (record.location.isNotEmpty) sb.write('Location: ${record.location}\r');
    if (record.expireDateFormatted.isNotEmpty) {
      sb.write('Expires: ${record.expireDateFormatted}\r');
    }
    return BbsMenuReply(sb.toString());
  }

  // ---- formatting -----------------------------------------------------------

  /// Callsign without SSID, upper case.
  static String _baseCall(String call) {
    final c = call.trim().toUpperCase();
    final dash = c.indexOf('-');
    return dash > 0 ? c.substring(0, dash) : c;
  }

  /// Upper-case callsign, without the implicit `-0` SSID.
  static String _displayCall(String call) {
    final c = call.trim().toUpperCase();
    return c.endsWith('-0') ? c.substring(0, c.length - 2) : c;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Local date and time as `YYYY-MM-DD HH:MM`.
  static String _date(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${_two(l.month)}-${_two(l.day)} '
        '${_two(l.hour)}:${_two(l.minute)}';
  }

  static String _ago(DateTime now, DateTime t) {
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  static String _plural(int n, String noun) =>
      n == 1 ? '1 $noun' : '$n ${noun}s';
}
