/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Captures application log messages from application startup so the Debug tab does
not need to be opened first for messages to be recorded.
*/

import 'dart:collection';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// Keeps a bounded log on the host. Views receive append events and request
/// a snapshot when opened, instead of mirroring the full log on every line.
class DebugLogHandler {
  static const int maxEntries = 2000;
  final DataBrokerClient _broker = DataBrokerClient();
  final Queue<Map<String, dynamic>> _entries = Queue();
  bool _initialized = false;

  List<Map<String, dynamic>> get entries => List.of(_entries, growable: false);

  String get _platformLabel {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  void init() {
    if (_initialized) return;
    _initialized = true;

    // Restore any entries already stored in the broker (e.g. from a sub-window).
    final stored = DataBroker.getValue<List<dynamic>>(1, 'DebugLogEntries');
    if (stored != null) {
      _entries.addAll(stored.whereType<Map<String, dynamic>>());
      while (_entries.length > maxEntries) {
        _entries.removeFirst();
      }
    }

    // Start capturing log messages right away.
    _broker.subscribeMultiple(
      deviceId: 1,
      names: const ['LogInfo', 'LogError'],
      callback: _onLogMessage,
    );

    // Allow the Debug tab (or anything else) to clear the captured log.
    _broker.subscribe(
      deviceId: 1,
      name: 'ClearDebugLog',
      callback: _onClearDebugLog,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'RequestDebugLog',
      callback: (_, _, _) => _dispatchEntries(),
    );

    // Emit the startup banner only on a fresh start.
    if (_entries.isEmpty) {
      PackageInfo.fromPlatform().then((info) {
        _broker.logInfo(
          'HTCommander ${info.version} started on $_platformLabel',
        );
      });
    }
  }

  void _onLogMessage(int deviceId, String name, Object? data) {
    if (data is! String) return;
    final entry = <String, dynamic>{
      'time': DateTime.now().toIso8601String(),
      'message': data,
      'isError': name == 'LogError',
    };
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeFirst();
    _broker.dispatch(
      deviceId: 1,
      name: 'DebugLogEntry',
      data: entry,
      store: false,
    );
  }

  void _onClearDebugLog(int deviceId, String name, Object? data) {
    _entries.clear();
    _dispatchEntries();
  }

  void _dispatchEntries() {
    _broker.dispatch(
      deviceId: 1,
      name: 'DebugLogEntries',
      data: entries,
      store: false,
    );
  }

  void dispose() => _broker.dispose();
}
