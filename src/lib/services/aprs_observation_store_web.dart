/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../aprs/aprs_observation.dart';

/// Only standalone browsers use this store; hosted browsers mirror the owner.
class AprsObservationStore {
  static const _key = 'aprs_observations';
  List<AprsObservation> _saved = [];

  Future<List<AprsObservation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _saved = saved == null ? [] : (jsonDecode(saved) as List)
      .map((json) => AprsObservation.fromJson(Map<String, dynamic>.from(json as Map))
        .withStatus(live: false, persisted: true)).toList();
    if (_saved.length > AprsObservation.capacity) {
      _saved = _saved.sublist(_saved.length - AprsObservation.capacity);
    }
    return List.of(_saved);
  }

  Future<void> save(AprsObservation observation) async {
    final next = [..._saved, observation];
    if (next.length > AprsObservation.capacity) next.removeAt(0);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(next.map((o) => o.toJson()).toList()))) {
      throw StateError('Unable to persist APRS observations');
    }
    _saved = next;
  }
}
