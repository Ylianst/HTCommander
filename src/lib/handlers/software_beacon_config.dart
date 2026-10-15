/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import '../utils/num_parsing.dart';

/// Configuration for the app's own periodic APRS beacon
/// ([SoftwareBeaconHandler]).
///
/// Persisted as a JSON string in the [DataBroker] at device 0 under the key
/// `SoftwareBeaconConfig`. Unlike the radio's built-in beacon, the software
/// beacon always uses the global station callsign + SSID, always transmits on
/// the "APRS" channel in APRS format, and is always gated to the Internet
/// (APRS-IS) in addition to any selected radio.
class SoftwareBeaconConfig {
  /// Beacon interval in seconds. 0 disables the periodic beacon.
  final int intervalSeconds;

  /// APRS symbol table identifier (single character, '/' or '\').
  final String symbolTable;

  /// APRS symbol code (single character).
  final String symbolCode;

  /// Free-text comment/status appended to the beacon.
  final String message;

  /// When true, the current GPS/manual location is included as a position
  /// report; otherwise a status-only beacon is sent.
  final bool includeLocation;

  /// Preferred radio device id used for the RF transmission. -1 = none (the
  /// beacon is only gated to the Internet, or the first connected radio with an
  /// APRS channel is used as a fallback).
  final int radioDeviceId;

  /// When true (and [includeLocation] is set), the beacon also fires early
  /// between interval ticks when the station moves significantly — faster when
  /// moving quickly and on sharp turns. The configured [intervalSeconds] acts
  /// as the maximum (slowest) interval.
  final bool smartBeacon;

  /// Manual mode: no periodic beacon, but the user may send a one-time beacon
  /// on demand. Only meaningful when [intervalSeconds] is 0.
  final bool manual;

  const SoftwareBeaconConfig({
    this.intervalSeconds = 0,
    this.manual = false,
    this.symbolTable = '/',
    this.symbolCode = '-',
    this.message = '',
    this.includeLocation = true,
    this.radioDeviceId = -1,
    this.smartBeacon = false,
  });

  /// True when the periodic beacon is running.
  bool get enabled => intervalSeconds > 0;

  /// True when the beacon is not off: periodic or manual.
  bool get isActive => enabled || manual;

  SoftwareBeaconConfig copyWith({
    int? intervalSeconds,
    bool? manual,
    String? symbolTable,
    String? symbolCode,
    String? message,
    bool? includeLocation,
    int? radioDeviceId,
    bool? smartBeacon,
  }) {
    return SoftwareBeaconConfig(
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      manual: manual ?? this.manual,
      symbolTable: symbolTable ?? this.symbolTable,
      symbolCode: symbolCode ?? this.symbolCode,
      message: message ?? this.message,
      includeLocation: includeLocation ?? this.includeLocation,
      radioDeviceId: radioDeviceId ?? this.radioDeviceId,
      smartBeacon: smartBeacon ?? this.smartBeacon,
    );
  }

  Map<String, dynamic> toJson() => {
    'intervalSeconds': intervalSeconds,
    'manual': manual,
    'symbolTable': symbolTable,
    'symbolCode': symbolCode,
    'message': message,
    'includeLocation': includeLocation,
    'radioDeviceId': radioDeviceId,
    'smartBeacon': smartBeacon,
  };

  static SoftwareBeaconConfig fromJson(Map<String, dynamic> json) {
    bool asBool(Object? v, bool fallback) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      return fallback;
    }

    String asChar(Object? v, String fallback) {
      if (v is String && v.isNotEmpty) return v.substring(0, 1);
      return fallback;
    }

    final intervalSeconds = asInt(json['intervalSeconds'], 0).clamp(0, 86400);
    return SoftwareBeaconConfig(
      intervalSeconds: intervalSeconds,
      manual: intervalSeconds == 0 && asBool(json['manual'], false),
      symbolTable: asChar(json['symbolTable'], '/'),
      symbolCode: asChar(json['symbolCode'], '-'),
      message: (json['message'] as String?) ?? '',
      includeLocation: asBool(json['includeLocation'], true),
      radioDeviceId: asInt(json['radioDeviceId'], -1),
      smartBeacon: asBool(json['smartBeacon'], false),
    );
  }
}
