/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Shared state of the BBS menu: the message board and the log of stations that
connected. Used by every radio BBS and the HTTP BBS alike, so a message posted
over the web can be read over the air and vice versa.

Reads are served from memory (the BBS conversation is synchronous); changes are
persisted to the SQLite database in the background, in order. On the web build
(no database) the store simply lives in memory.
*/

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/db/app_database.dart';

/// A message posted on the BBS message board.
class BbsBoardMessage {
  const BbsBoardMessage({
    required this.id,
    required this.time,
    required this.callsign,
    required this.text,
  });

  /// Message number shown to users; never reused once deleted.
  final int id;
  final DateTime time;

  /// Callsign of the poster, with SSID as connected.
  final String callsign;
  final String text;
}

/// When a station last connected to the BBS.
class BbsVisit {
  const BbsVisit({
    required this.callsign,
    required this.firstSeen,
    required this.lastSeen,
    required this.protocol,
    required this.count,
  });

  /// Callsign with SSID, upper case.
  final String callsign;
  final DateTime firstSeen;
  final DateTime lastSeen;

  /// How the station connected the last time ("AX.25", "XARA", "Web"...).
  final String protocol;

  /// Number of connections seen from this station.
  final int count;
}

/// The BBS message board and visitor log.
class BbsStore {
  BbsStore({this.maxMessages = 500, this.maxVisits = 500});

  /// The store shared by all BBS instances. Replaceable in tests.
  static BbsStore instance = BbsStore();

  /// Longest board message accepted, in characters.
  static const int maxMessageLength = 200;

  /// Oldest messages are dropped beyond this many.
  final int maxMessages;

  /// Least recently seen stations are forgotten beyond this many.
  final int maxVisits;

  final List<BbsBoardMessage> _messages = [];

  /// Stations in visit order, oldest first (re-inserted on every visit).
  final Map<String, BbsVisit> _visits = {};
  int _lastId = 0;

  // Typed dynamically: the DAO type is not imported, keeping sqflite out of the
  // web bundle (where AppDatabase.instance is always null).
  dynamic _dao;
  Future<void> _writes = Future<void>.value();

  /// Loads the persisted board and visitor log. Safe to skip (memory only).
  Future<void> init() async {
    final dao = AppDatabase.instance?.bbs;
    if (dao == null) return;
    try {
      final rows = (await dao.boardMessages()) as List;
      final lastId = (await dao.lastBoardId()) as int;
      final visits = (await dao.visits()) as List;
      _messages
        ..clear()
        ..addAll([
          for (final r in rows.cast<Map>())
            BbsBoardMessage(
              id: (r['id'] as num).toInt(),
              time: DateTime.fromMillisecondsSinceEpoch(
                (r['time_ms'] as num).toInt(),
              ),
              callsign: r['callsign'] as String,
              text: r['text'] as String,
            ),
        ]);
      _lastId = lastId;
      for (final m in _messages) {
        if (m.id > _lastId) _lastId = m.id;
      }
      // Kept in visit order (oldest first); the database lists newest first.
      _visits.clear();
      for (final r in visits.reversed.cast<Map>()) {
        final v = BbsVisit(
          callsign: r['callsign'] as String,
          firstSeen: DateTime.fromMillisecondsSinceEpoch(
            (r['first_ms'] as num).toInt(),
          ),
          lastSeen: DateTime.fromMillisecondsSinceEpoch(
            (r['last_ms'] as num).toInt(),
          ),
          protocol: r['protocol'] as String,
          count: (r['count'] as num).toInt(),
        );
        _visits[v.callsign] = v;
      }
      _dao = dao;
    } catch (e) {
      debugPrint('BbsStore: load failed: $e');
    }
  }

  /// Waits for pending database writes (tests).
  @visibleForTesting
  Future<void> flush() => _writes;

  void _persist(Future<void> Function(dynamic dao) write) {
    final dao = _dao;
    if (dao == null) return;
    _writes = _writes.then((_) => write(dao)).catchError((Object e) {
      debugPrint('BbsStore: write failed: $e');
    });
  }

  // ---- message board --------------------------------------------------------

  /// All board messages, oldest first.
  List<BbsBoardMessage> get messages => List.unmodifiable(_messages);

  /// The message numbered [id], or null.
  BbsBoardMessage? message(int id) {
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Posts [text] (already validated) from [callsign].
  BbsBoardMessage post(String callsign, String text, {DateTime? time}) {
    final message = BbsBoardMessage(
      id: ++_lastId,
      time: time ?? DateTime.now(),
      callsign: callsign.toUpperCase(),
      text: text,
    );
    _messages.add(message);
    _persist(
      (dao) => dao.insertBoardMessage(
        message.id,
        message.time.millisecondsSinceEpoch,
        message.callsign,
        message.text,
      ),
    );
    while (_messages.length > maxMessages) {
      final old = _messages.removeAt(0);
      _persist((dao) => dao.deleteBoardMessage(old.id));
    }
    return message;
  }

  /// Deletes the message numbered [id]; false when there is no such message.
  bool delete(int id) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0) return false;
    _messages.removeAt(index);
    _persist((dao) => dao.deleteBoardMessage(id));
    return true;
  }

  // ---- visitor log ----------------------------------------------------------

  /// The visit record of [callsign] (with SSID), or null if never seen.
  BbsVisit? visit(String callsign) => _visits[callsign.toUpperCase()];

  /// Records that [callsign] connected over [protocol]. Returns the station's
  /// previous visit, or null on its first visit.
  BbsVisit? recordVisit(String callsign, String protocol, {DateTime? time}) {
    final key = callsign.trim().toUpperCase();
    if (key.isEmpty) return null;
    final now = time ?? DateTime.now();
    final previous = _visits.remove(key);
    final visit = BbsVisit(
      callsign: key,
      firstSeen: previous?.firstSeen ?? now,
      lastSeen: now,
      protocol: protocol,
      count: (previous?.count ?? 0) + 1,
    );
    _visits[key] = visit;
    _persist(
      (dao) => dao.upsertVisit(
        visit.callsign,
        visit.firstSeen.millisecondsSinceEpoch,
        visit.lastSeen.millisecondsSinceEpoch,
        visit.protocol,
        visit.count,
      ),
    );
    if (_visits.length > maxVisits) {
      final oldest = _visits.keys.first;
      _visits.remove(oldest);
      _persist((dao) => dao.deleteVisit(oldest));
    }
    return previous;
  }

  /// The [count] most recently seen stations, most recent first.
  List<BbsVisit> recentVisits(int count) =>
      _visits.values.toList().reversed.take(count).toList();

  /// Number of stations in the visitor log.
  int get visitCount => _visits.length;
}
