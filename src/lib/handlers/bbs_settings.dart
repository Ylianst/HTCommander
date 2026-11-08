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
  }) : disabledGames = disabledGames ?? {};

  bool isGameEnabled(String key) =>
      gamesEnabled && !disabledGames.contains(key);

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
  };

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
          ((json['maxUploadBytes'] as num?)?.toInt() ?? d.maxUploadBytes)
              .clamp(1, maxUploadBytesLimit),
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
