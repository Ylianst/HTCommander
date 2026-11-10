/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';

import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// Sysop customization of the BBS menu, stored as JSON on device 0. Uploads
/// are switched on and off by `BbsFileStore.uploadsSetting`.
class BbsSettings {
  static const String brokerKey = 'BbsSettings';
  static const String defaultWelcomeMessage = 'Welcome to our BBS';
  static const int defaultMaxUploadBytes = 25 * 1024;
  static const int maxUploadBytesLimit = 1024 * 1024;

  String welcomeMessage;
  bool announcementEnabled;
  String announcementText;
  bool callsignLookupEnabled;
  int maxUploadBytes;
  bool gamesEnabled;

  /// Keys of individual games turned off by the sysop.
  Set<String> disabledGames;

  /// The A / AM commands listing APRS messages heard.
  bool aprsMessagesEnabled;

  /// The AP command showing an APRS station's last position and weather.
  bool aprsLookupEnabled;

  /// The AH command listing recently heard APRS stations.
  bool aprsHeardEnabled;

  /// Relays Winlink clients to the Winlink CMS over the Internet. When off,
  /// mail is exchanged with the local mailbox only.
  bool winlinkGatewayEnabled;

  /// Only stations on [allowedStations] may connect; otherwise every station
  /// except those on [deniedStations] may.
  bool allowListOnly;

  /// Callsigns, upper case; without an SSID an entry matches every SSID.
  List<String> allowedStations;
  List<String> deniedStations;

  BbsSettings({
    this.welcomeMessage = defaultWelcomeMessage,
    this.announcementEnabled = false,
    this.announcementText = '',
    this.callsignLookupEnabled = true,
    this.maxUploadBytes = defaultMaxUploadBytes,
    this.gamesEnabled = true,
    Set<String>? disabledGames,
    this.aprsMessagesEnabled = true,
    this.aprsLookupEnabled = false,
    this.aprsHeardEnabled = false,
    this.winlinkGatewayEnabled = true,
    this.allowListOnly = false,
    List<String>? allowedStations,
    List<String>? deniedStations,
  }) : disabledGames = disabledGames ?? {},
       allowedStations = allowedStations ?? [],
       deniedStations = deniedStations ?? [];

  bool isGameEnabled(String key) =>
      gamesEnabled && !disabledGames.contains(key);

  /// Upper-cases [callsign] and drops a `-0` SSID, which AX.25 treats as none.
  static String normalizeStation(String callsign) {
    final call = callsign.trim().toUpperCase();
    return call.endsWith('-0') ? call.substring(0, call.length - 2) : call;
  }

  static bool _listMatches(List<String> list, String callsign) {
    final call = normalizeStation(callsign);
    final dash = call.indexOf('-');
    final base = dash < 0 ? call : call.substring(0, dash);
    for (final entry in list) {
      final e = normalizeStation(entry);
      if (e == call || (!e.contains('-') && e == base)) return true;
    }
    return false;
  }

  /// Whether [callsign] may use the BBS under the access list.
  bool isStationAllowed(String callsign) => allowListOnly
      ? _listMatches(allowedStations, callsign)
      : !_listMatches(deniedStations, callsign);

  Map<String, dynamic> toJson() => {
    'welcomeMessage': welcomeMessage,
    'announcementEnabled': announcementEnabled,
    'announcementText': announcementText,
    'callsignLookupEnabled': callsignLookupEnabled,
    'maxUploadBytes': maxUploadBytes,
    'gamesEnabled': gamesEnabled,
    'disabledGames': disabledGames.toList(),
    'aprsMessagesEnabled': aprsMessagesEnabled,
    'aprsLookupEnabled': aprsLookupEnabled,
    'aprsHeardEnabled': aprsHeardEnabled,
    'winlinkGatewayEnabled': winlinkGatewayEnabled,
    'allowListOnly': allowListOnly,
    'allowedStations': allowedStations,
    'deniedStations': deniedStations,
  };

  static List<String> _stations(Object? list) => [
    for (final s in list is List ? list : const [])
      if (s is String && s.trim().isNotEmpty) normalizeStation(s),
  ];

  static BbsSettings fromJson(Map<String, dynamic> json) {
    final d = BbsSettings();
    return BbsSettings(
      welcomeMessage: json['welcomeMessage'] as String? ?? d.welcomeMessage,
      announcementEnabled:
          json['announcementEnabled'] as bool? ?? d.announcementEnabled,
      announcementText: json['announcementText'] as String? ?? '',
      callsignLookupEnabled:
          json['callsignLookupEnabled'] as bool? ?? d.callsignLookupEnabled,
      maxUploadBytes:
          ((json['maxUploadBytes'] as num?)?.toInt() ?? d.maxUploadBytes).clamp(
            1,
            maxUploadBytesLimit,
          ),
      gamesEnabled: json['gamesEnabled'] as bool? ?? d.gamesEnabled,
      disabledGames: {
        for (final g in json['disabledGames'] as List? ?? const [])
          if (g is String) g,
      },
      aprsMessagesEnabled:
          json['aprsMessagesEnabled'] as bool? ?? d.aprsMessagesEnabled,
      aprsLookupEnabled:
          json['aprsLookupEnabled'] as bool? ?? d.aprsLookupEnabled,
      aprsHeardEnabled: json['aprsHeardEnabled'] as bool? ?? d.aprsHeardEnabled,
      winlinkGatewayEnabled:
          json['winlinkGatewayEnabled'] as bool? ?? d.winlinkGatewayEnabled,
      allowListOnly: json['allowListOnly'] as bool? ?? d.allowListOnly,
      allowedStations: _stations(json['allowedStations']),
      deniedStations: _stations(json['deniedStations']),
    );
  }

  /// The current settings, or defaults when unset or unreadable.
  static BbsSettings load() {
    final raw = DataBroker.getValue<String>(0, brokerKey, '') ?? '';
    if (raw.isEmpty) return BbsSettings();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return fromJson(json);
    } catch (_) {}
    return BbsSettings();
  }

  void save(DataBrokerClient broker) {
    broker.dispatch(
      deviceId: 0,
      name: brokerKey,
      data: jsonEncode(toJson()),
      store: true,
    );
  }
}
