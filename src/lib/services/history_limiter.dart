/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'data_broker.dart';
import 'data_broker_client.dart';

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

  /// Returns the current counts of persisted items on disk.
  static Future<HistoryCounts> getCounts() async {
    if (kIsWeb) return const HistoryCounts();

    try {
      final dir = await getApplicationSupportDirectory();

      // Count packets (APRS vs non-APRS) from the file.
      int aprsCount = 0;
      int packetCount = 0;
      final packetFile = File(
        '${dir.path}${Platform.pathSeparator}packets.ptcap',
      );
      if (await packetFile.exists()) {
        final lines = await packetFile.readAsLines();
        for (final line in lines) {
          if (line.isEmpty) continue;
          if (_isAprsPacketLine(line)) {
            aprsCount++;
          } else {
            packetCount++;
          }
        }
      }

      // Count SSTV images.
      int sstvCount = 0;
      final sstvDir = Directory(
        '${dir.path}${Platform.pathSeparator}SSTV',
      );
      if (await sstvDir.exists()) {
        await for (final entity in sstvDir.list()) {
          if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
            sstvCount++;
          }
        }
      }

      // Count communication events.
      int commCount = 0;
      final historyFile = File(
        '${dir.path}${Platform.pathSeparator}voicetext.json',
      );
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            commCount = decoded.length;
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

    if (kIsWeb) return; // No file-system access on the web build.

    final dir = await getApplicationSupportDirectory();

    // Trim packets file (APRS and non-APRS independently).
    if (maxPackets > 0 || maxAprs > 0) {
      await _trimPacketsFile(dir, maxPackets, maxAprs);
    }

    // Trim SSTV images on disk.
    if (maxSstv > 0) {
      await _trimSstvImages(dir, maxSstv);
    }

    // Trim voice-text (communication events) JSON file.
    // The same file contains entries for voice, SSTV, packets, etc.
    // When maxComm is set it limits total entries. When maxAprs is set we also
    // count APRS entries separately and remove the oldest ones that exceed the
    // limit.
    if (maxComm > 0 || maxAprs > 0) {
      await _trimVoiceTextHistory(dir, maxComm, maxAprs);
    }
  }

  /// Trims the `packets.ptcap` file, applying [maxNonAprs] to non-APRS
  /// packets and [maxAprs] to APRS packets independently. A value of 0 means
  /// unlimited for that category.
  ///
  /// Packet lines have the format:
  /// `{timestamp},{direction},TncFrag4,{channelId},{regionId},{channelName},...`
  /// APRS packets have channelName == "APRS".
  static Future<void> _trimPacketsFile(
    Directory dir,
    int maxNonAprs,
    int maxAprs,
  ) async {
    try {
      final file = File('${dir.path}${Platform.pathSeparator}packets.ptcap');
      if (!await file.exists()) return;

      final lines = await file.readAsLines();
      if (lines.isEmpty) return;

      // Separate lines into APRS and non-APRS buckets.
      final aprsLines = <String>[];
      final otherLines = <String>[];
      // Track original indices to reconstruct chronological order.
      final lineTypes = <_PacketLineType>[];

      for (final line in lines) {
        if (line.isEmpty) continue;
        if (_isAprsPacketLine(line)) {
          lineTypes.add(_PacketLineType(line: line, isAprs: true));
          aprsLines.add(line);
        } else {
          lineTypes.add(_PacketLineType(line: line, isAprs: false));
          otherLines.add(line);
        }
      }

      // Check if trimming is needed.
      final aprsNeedsTrim = maxAprs > 0 && aprsLines.length > maxAprs;
      final otherNeedsTrim = maxNonAprs > 0 && otherLines.length > maxNonAprs;
      if (!aprsNeedsTrim && !otherNeedsTrim) return;

      // Rebuild in original order, keeping only lines that pass the filter.
      // We walk through chronologically and use counters to skip the oldest
      // entries from each category.
      int aprsSkipCount = aprsNeedsTrim
          ? aprsLines.length - maxAprs
          : 0;
      int otherSkipCount = otherNeedsTrim
          ? otherLines.length - maxNonAprs
          : 0;

      final result = <String>[];
      for (final entry in lineTypes) {
        if (entry.isAprs) {
          if (aprsSkipCount > 0) {
            aprsSkipCount--;
            continue;
          }
        } else {
          if (otherSkipCount > 0) {
            otherSkipCount--;
            continue;
          }
        }
        result.add(entry.line);
      }

      await file.writeAsString('${result.join('\n')}\n');
    } catch (e) {
      debugPrint('HistoryLimiter: failed to trim packets file: $e');
    }
  }

  /// Returns true if the packet line belongs to the APRS channel.
  /// Line format: `{timestamp},{direction},TncFrag4,{channelId},{regionId},{channelName},...`
  /// The channelName is the 6th comma-separated field (index 5).
  static bool _isAprsPacketLine(String line) {
    // Find the 5th comma to locate the channelName field.
    int commaCount = 0;
    int startIdx = 0;
    for (int i = 0; i < line.length; i++) {
      if (line.codeUnitAt(i) == 0x2C) {
        // ','
        commaCount++;
        if (commaCount == 5) {
          startIdx = i + 1;
        } else if (commaCount == 6) {
          return line.substring(startIdx, i) == 'APRS';
        }
      }
    }
    return false;
  }

  /// Trims SSTV image files, keeping only the most recent [max] images
  /// (sorted by filename which encodes the date).
  static Future<void> _trimSstvImages(Directory dir, int max) async {
    try {
      final sstvDir = Directory(
        '${dir.path}${Platform.pathSeparator}SSTV',
      );
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

  /// Trims the `voicetext.json` file. [maxTotal] limits all entries;
  /// [maxAprs] limits entries with encoding == 'aprs'.
  static Future<void> _trimVoiceTextHistory(
    Directory dir,
    int maxTotal,
    int maxAprs,
  ) async {
    try {
      final file = File(
        '${dir.path}${Platform.pathSeparator}voicetext.json',
      );
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      var entries = List<Map<String, dynamic>>.from(
        decoded.whereType<Map<String, dynamic>>(),
      );

      // Trim APRS entries if a limit is set.
      if (maxAprs > 0) {
        final aprsIndices = <int>[];
        for (var i = 0; i < entries.length; i++) {
          if (entries[i]['encoding'] == 'aprs') {
            aprsIndices.add(i);
          }
        }
        if (aprsIndices.length > maxAprs) {
          final removeCount = aprsIndices.length - maxAprs;
          final toRemove = aprsIndices.sublist(0, removeCount).toSet();
          entries = [
            for (var i = 0; i < entries.length; i++)
              if (!toRemove.contains(i)) entries[i],
          ];
        }
      }

      // Trim total entries if a limit is set.
      if (maxTotal > 0 && entries.length > maxTotal) {
        entries = entries.sublist(entries.length - maxTotal);
      }

      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(entries),
      );
    } catch (e) {
      debugPrint('HistoryLimiter: failed to trim voice text history: $e');
    }
  }
}

/// Helper to track a packet line and its type during trimming.
class _PacketLineType {
  final String line;
  final bool isAprs;
  const _PacketLineType({required this.line, required this.isAprs});
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
