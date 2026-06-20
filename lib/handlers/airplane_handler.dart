/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.Airplanes.AirplaneHandler` class.
*/

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/aircraft.dart';
import '../services/data_broker_client.dart';

/// Data Broker handler that polls a Dump1090 endpoint for airplane data.
///
/// Reads the `AirplaneServer` setting from device 0 and, when present and
/// `ShowAirplanesOnMap` is enabled, periodically fetches the `aircraft.json`
/// endpoint. Each successful poll dispatches an `Airplanes` event on device 0
/// with the parsed `List<Aircraft>` (broadcast only, not stored).
class AirplaneHandler {
  /// Device id that owns persisted application settings.
  static const int _settingsDeviceId = 0;

  final DataBrokerClient _broker = DataBrokerClient();

  http.Client? _httpClient;
  String? _currentUrl;
  bool _showOnMap = false;
  bool _polling = false;
  bool _disposed = false;

  /// Initializes the handler: subscribes to broker events and applies the
  /// current settings. Safe to call once at startup.
  void init() {
    // Server URL changes on device 0.
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'AirplaneServer',
      callback: _onAirplaneServerChanged,
    );

    // Show/hide toggle starts or stops polling.
    _broker.subscribe(
      deviceId: _settingsDeviceId,
      name: 'ShowAirplanesOnMap',
      callback: _onShowAirplanesOnMapChanged,
    );

    // Load initial state.
    _showOnMap =
        (_broker.getValue<int>(_settingsDeviceId, 'ShowAirplanesOnMap', 0) ??
            0) ==
        1;
    final server =
        _broker.getValue<String>(_settingsDeviceId, 'AirplaneServer', '') ?? '';
    _applyServerSetting(server);
  }

  void _onAirplaneServerChanged(int deviceId, String name, Object? data) {
    _applyServerSetting(data as String? ?? '');
  }

  void _onShowAirplanesOnMapChanged(int deviceId, String name, Object? data) {
    _showOnMap = (data as int?) == 1;
    final server =
        _broker.getValue<String>(_settingsDeviceId, 'AirplaneServer', '') ?? '';
    _applyServerSetting(server);
  }

  /// Applies a new server setting: stops any existing poll loop and, if the
  /// value is non-empty and [_showOnMap] is true, starts a new one.
  void _applyServerSetting(String server) {
    final url = _showOnMap ? _resolveUrl(server) : null;

    // If the resolved URL hasn't changed, nothing to do.
    if (url == _currentUrl) return;

    _stopPolling();
    _currentUrl = url;

    if (url != null && url.isNotEmpty) {
      _startPolling(url);
    }
  }

  /// Resolves the server setting to a full URL. If it already starts with
  /// `http://`/`https://` it is used as-is; otherwise the default Dump1090 URL
  /// is built.
  static String? _resolveUrl(String server) {
    final trimmed = server.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed/data/aircraft.json';
  }

  void _startPolling(String url) {
    debugPrint('AirplaneHandler: starting polling for $url');
    _httpClient = http.Client();
    _polling = true;
    // Fire and forget; the loop exits when the URL changes or on dispose.
    unawaited(_pollLoop(url));
  }

  /// Continuously polls the endpoint, waiting one second after each completed
  /// request before issuing the next one.
  Future<void> _pollLoop(String url) async {
    final uri = Uri.parse(url);

    while (_polling && !_disposed && _currentUrl == url) {
      final client = _httpClient;
      if (client == null) break;

      try {
        final response = await client
            .get(uri)
            .timeout(const Duration(seconds: 10));

        // Bail out if the settings changed while the request was in flight.
        if (!_polling || _disposed || _currentUrl != url) break;

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['aircraft'] is List) {
            final aircraft = (decoded['aircraft'] as List)
                .whereType<Map>()
                .map((e) => Aircraft.fromJson(Map<String, dynamic>.from(e)))
                .toList();
            final withPosition = aircraft
                .where((a) => a.hasPosition)
                .length;
            debugPrint(
              'AirplaneHandler: fetched ${aircraft.length} aircraft '
              '($withPosition with position)',
            );
            _broker.dispatch(
              deviceId: _settingsDeviceId,
              name: 'Airplanes',
              data: aircraft,
              store: false,
            );
          } else {
            debugPrint(
              'AirplaneHandler: response had no "aircraft" list '
              '(root type: ${decoded.runtimeType})',
            );
          }
        } else {
          debugPrint('AirplaneHandler: HTTP ${response.statusCode} from $url');
        }
      } catch (e) {
        // Log and retry after the delay so failures are visible.
        debugPrint('AirplaneHandler: poll error for $url: $e');
      }

      if (!_polling || _disposed || _currentUrl != url) break;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _stopPolling() {
    _polling = false;
    _httpClient?.close();
    _httpClient = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopPolling();
    _broker.dispose();
  }
}
