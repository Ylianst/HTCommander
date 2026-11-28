/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../aprs/aprs_outbox.dart';

/// Standalone browsers persist their own outbox. Hosted browsers never use it.
class AprsOutboxStore {
  static const _key = 'aprs_outbox';
  final Map<String, AprsOutgoingMessage> _messages = {};

  Future<List<AprsOutgoingMessage>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      for (final json in jsonDecode(saved) as List) {
        final message = AprsOutgoingMessage.fromJson(Map<String, dynamic>.from(json as Map));
        _messages[message.id] = message;
      }
    }
    return _messages.values.toList();
  }

  Future<void> _write(Map<String, AprsOutgoingMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(messages.values.map((m) => m.toJson()).toList()))) {
      throw StateError('Unable to persist APRS outbox');
    }
    _messages..clear()..addAll(messages);
  }

  Future<void> save(AprsOutgoingMessage message) => _write({..._messages, message.id: message});
  Future<void> delete(List<String> ids) => _write({
    for (final entry in _messages.entries)
      if (!ids.contains(entry.key)) entry.key: entry.value,
  });
}
