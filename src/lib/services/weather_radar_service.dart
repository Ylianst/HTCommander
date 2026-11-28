/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherRadarFrame {
  const WeatherRadarFrame({required this.layerName, required this.observedAt});

  final String layerName;
  final DateTime observedAt;

  String get urlTemplate =>
      'https://mesonet.agron.iastate.edu/c/tile.py/1.0.0/'
      '$layerName/{z}/{x}/{y}.png';

  bool isStale(DateTime now) =>
      now.toUtc().difference(observedAt) >= const Duration(minutes: 15);

  static WeatherRadarFrame parse(String body, {required DateTime now}) {
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic> || data['services'] is! List) {
      throw const FormatException('Invalid radar metadata.');
    }
    for (final entry in data['services'] as List) {
      if (entry is! Map<String, dynamic> || entry['id'] != 'ridge_uscomp_n0q') {
        continue;
      }
      final layer = entry['layername'];
      final time = entry['utc_valid'];
      if (layer is! String ||
          !RegExp(r'^ridge::USCOMP-N0Q-\d{12}$').hasMatch(layer) ||
          time is! String) {
        throw const FormatException('Invalid NEXRAD frame.');
      }
      final observed = DateTime.tryParse(time);
      if (observed == null || !observed.isUtc) {
        throw const FormatException('Invalid radar observation time.');
      }
      final stamp = observed
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(RegExp('[-:T]'), '');
      if (!layer.endsWith(stamp) ||
          observed.difference(now.toUtc()) > const Duration(minutes: 10)) {
        throw const FormatException('Inconsistent radar observation time.');
      }
      return WeatherRadarFrame(layerName: layer, observedAt: observed);
    }
    throw const FormatException('NEXRAD radar metadata is unavailable.');
  }
}

class WeatherRadarHttpException implements Exception {
  const WeatherRadarHttpException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'Radar metadata HTTP $statusCode';
}

Future<WeatherRadarFrame> fetchWeatherRadarFrame(
  http.Client client, {
  required DateTime now,
}) async {
  final response = await client
      .get(Uri.parse('https://mesonet.agron.iastate.edu/json/tms.json'))
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) {
    throw WeatherRadarHttpException(response.statusCode);
  }
  return WeatherRadarFrame.parse(response.body, now: now);
}
