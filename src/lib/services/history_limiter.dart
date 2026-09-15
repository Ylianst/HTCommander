/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'data_broker.dart';
import 'data_broker_client.dart';
import 'db/app_database.dart';

/// Enforces user-configured history limits on persisted data (packets file,
/// SSTV images, voice-text history).
///
/// Limits are applied:
/// - Once at app startup
/// - Immediately when settings change
/// - Every 30 minutes, but only if new data has been added since the last run
///
/// Usage: call [HistoryLimiter.instance.init()] once at app startup.
class HistoryLimiter {
  HistoryLimiter._();

  /// Singleton instance.
  static final HistoryLimiter instance = HistoryLimiter._();

  /// Upper bound kept on the internet APRS history, matching the cap the old
  /// self-compacting file enforced (there is no user setting for it).
  static const int _aprsIsHardCap = 1000;

  /// Fallback cap for comms events when no user limit is set. The old
  /// voicetext.json was implicitly bounded to the in-memory history size
  /// because it rewrote the whole (trimmed) list; keep that bound so the table
  /// does not grow without limit by default.
  static const int _commsHardCap = 1000;

  final DataBrokerClient _broker = DataBrokerClient();
  Timer? _periodicTimer;
  bool _dirty = false;
  bool _initialized = false;

  /// Stops the periodic timer and unsubscribes from events.
  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _broker.dispose();
    _initialized = false;
  }

  /// Initializes the limiter: applies limits immediately, subscribes to data
  /// events, and starts the periodic 30-minute timer.
  void init() {
    if (_initialized) return;
    _initialized = true;

    // Apply limits at startup.
    apply();

    // Listen for new data additions to mark dirty.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onDataAdded,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'DecodedTextHistory',
      callback: _onDataAdded,
    );

    // Listen for settings changes (any of the limit keys).
    _broker.subscribe(
      deviceId: 0,
      name: 'MaxAprsMessages',
      callback: _onSettingsChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MaxPackets',
      callback: _onSettingsChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MaxSstvImages',
      callback: _onSettingsChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MaxCommEvents',
      callback: _onSettingsChanged,
    );

    // Start periodic timer (every 30 minutes).
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 30),
      _onPeriodicTick,
    );
  }

  void _onDataAdded(int deviceId, String name, Object? data) {
    _dirty = true;
  }

  void _onSettingsChanged(int deviceId, String name, Object? data) {
    // Settings changed — apply immediately.
    apply();
  }

  void _onPeriodicTick(Timer timer) {
    if (!_dirty) return;
    _dirty = false;
    apply();
  }

  /// Returns the current counts of persisted items.
  static Future<HistoryCounts> getCounts() async {
    if (kIsWeb) return const HistoryCounts();

    try {
      final db = AppDatabase.instance;
      int aprsCount = 0;
      int packetCount = 0;
      int commCount = 0;
      if (db != null) {
        aprsCount = await db.packets.count(aprs: true);
        packetCount = await db.packets.count(aprs: false);
        commCount = await db.comms.count();
      }

      // Count SSTV images (still stored as files on disk).
      int sstvCount = 0;
      final dir = await getApplicationSupportDirectory();
      final sstvDir = Directory('${dir.path}${Platform.pathSeparator}SSTV');
      if (await sstvDir.exists()) {
        await for (final entity in sstvDir.list()) {
          if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
            sstvCount++;
          }
        }
      }

      return HistoryCounts(
        aprsMessages: aprsCount,
        packets: packetCount,
        sstvImages: sstvCount,
        commEvents: commCount,
      );
    } catch (e) {
      debugPrint('HistoryLimiter: failed to get counts: $e');
      return const HistoryCounts();
    }
  }

  /// Reads the current limit settings from DataBroker and prunes any persisted
  /// stores that exceed their configured maximum. A limit of 0 means unlimited.
  static Future<void> apply() async {
    final maxAprs = DataBroker.getValue<int>(0, 'MaxAprsMessages', 0) ?? 0;
    final maxPackets = DataBroker.getValue<int>(0, 'MaxPackets', 0) ?? 0;
    final maxSstv = DataBroker.getValue<int>(0, 'MaxSstvImages', 0) ?? 0;
    final maxComm = DataBroker.getValue<int>(0, 'MaxCommEvents', 0) ?? 0;

    if (kIsWeb) return; // No database on the web build.

    final db = AppDatabase.instance;
    if (db != null) {
      try {
        // Indexed deletes replace the old whole-file rewrites. Packets are
        // trimmed for the APRS channel and all others independently; comms
        // events by total and by APRS encoding.
        await db.packets.enforceLimits(
          maxNonAprs: maxPackets,
          maxAprs: maxAprs,
        );
        await db.comms.enforceLimits(
          maxTotal: maxComm > 0 ? maxComm : _commsHardCap,
          maxAprs: maxAprs,
        );
        // Bound the internet APRS history the way the old file self-compacted.
        await db.aprsis.enforceLimit(_aprsIsHardCap);
      } catch (e) {
        debugPrint('HistoryLimiter: failed to enforce limits: $e');
      }
    }

    // Trim SSTV images on disk (still stored as files).
    if (maxSstv > 0) {
      final dir = await getApplicationSupportDirectory();
      await _trimSstvImages(dir, maxSstv);
    }
  }

  /// Trims SSTV image files, keeping only the most recent [max] images
  /// (sorted by filename which encodes the date).
  static Future<void> _trimSstvImages(Directory dir, int max) async {
    try {
      final sstvDir = Directory('${dir.path}${Platform.pathSeparator}SSTV');
      if (!await sstvDir.exists()) return;

      final files = await sstvDir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
          .cast<File>()
          .toList();

      if (files.length <= max) return;

      // Sort by name (filenames contain timestamps so alphabetical == chronological).
      files.sort((a, b) => a.path.compareTo(b.path));

      // Delete the oldest files.
      final toDelete = files.sublist(0, files.length - max);
      for (final file in toDelete) {
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('HistoryLimiter: failed to trim SSTV images: $e');
    }
  }
}

/// Current counts of persisted history items.
class HistoryCounts {
  final int aprsMessages;
  final int packets;
  final int sstvImages;
  final int commEvents;

  const HistoryCounts({
    this.aprsMessages = 0,
    this.packets = 0,
    this.sstvImages = 0,
    this.commEvents = 0,
  });
}
