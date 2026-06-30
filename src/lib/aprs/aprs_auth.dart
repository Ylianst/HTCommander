/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the APRS authentication methods in the C# `AprsHandler` class.
See docs/Aprs-Auth-Specification.md for the protocol details.
*/

import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../radio/ax25_packet.dart';

/// Minimal station record used to look up APRS authentication passwords.
class AprsStationInfo {
  final String callsign;
  final bool isAprs;
  final String authPassword;

  const AprsStationInfo({
    required this.callsign,
    required this.isAprs,
    required this.authPassword,
  });

  /// Builds a station record from a DataBroker JSON map. Recognises a few
  /// common key spellings so it works with whatever station publisher exists.
  static AprsStationInfo? fromJson(Map<String, dynamic> json) {
    final callsign = (json['Callsign'] ?? json['callsign'] ?? json['CallSign'])
        ?.toString();
    if (callsign == null || callsign.isEmpty) return null;
    final typeRaw = (json['StationType'] ?? json['stationType'] ?? json['type'])
        ?.toString()
        .toLowerCase();
    final isAprs = typeRaw == 'aprs' || typeRaw == '1';
    final pwd =
        (json['AuthPassword'] ?? json['authPassword'] ?? json['password'])
            ?.toString() ??
        '';
    return AprsStationInfo(
      callsign: callsign,
      isAprs: isAprs,
      authPassword: pwd,
    );
  }
}

/// Result of applying authentication to an outbound APRS message.
class AprsAuthResult {
  final String content;
  final bool applied;
  const AprsAuthResult(this.content, this.applied);
}

/// Implements APRS shared-secret message authentication (HMAC-SHA256).
class AprsAuth {
  /// Stations used to look up auth passwords. Updated by the handler from the
  /// DataBroker `Stations` value.
  List<AprsStationInfo> stations = const [];

  static List<int> _sha256(List<int> data) => sha256.convert(data).bytes;

  static List<int> _hmacSha256(List<int> key, List<int> data) =>
      Hmac(sha256, key).convert(data).bytes;

  static int _minutesSinceEpoch(DateTime time) =>
      time.toUtc().millisecondsSinceEpoch ~/ 60000;

  /// Finds an APRS auth password for [callsign] (case-insensitive), or null.
  String? _findAuthPassword(String callsign) {
    for (final station in stations) {
      if (station.isAprs &&
          station.callsign.toLowerCase() == callsign.toLowerCase() &&
          station.authPassword.isNotEmpty) {
        return station.authPassword;
      }
    }
    return null;
  }

  static String _padAddr(String destAddress) {
    var aprsAddr = destAddress;
    while (aprsAddr.length < 9) {
      aprsAddr += ' ';
    }
    return aprsAddr;
  }

  static String _authCodeFor(String authPassword, String hashInput) {
    final authKey = _sha256(utf8.encode(authPassword));
    final authCode = _hmacSha256(authKey, utf8.encode(hashInput));
    return base64.encode(authCode).substring(0, 6);
  }

  /// Builds an APRS message body with optional authentication and a message ID.
  AprsAuthResult addAprsAuth(
    String srcAddress,
    String destAddress,
    String aprsMessage,
    int msgId,
    DateTime time,
  ) {
    final aprsAddr = _padAddr(destAddress);
    final authPassword = _findAuthPassword(destAddress);
    if (authPassword == null || authPassword.isEmpty) {
      return AprsAuthResult(':$aprsAddr:$aprsMessage{$msgId', false);
    }
    final minutes = _minutesSinceEpoch(time);
    final hashInput =
        '$minutes:$srcAddress:${aprsAddr.trim()}:$aprsMessage{$msgId';
    final authCodeBase64 = _authCodeFor(authPassword, hashInput);
    return AprsAuthResult(
      ':$aprsAddr:$aprsMessage}$authCodeBase64{$msgId',
      true,
    );
  }

  /// Builds an APRS message body with optional authentication (no message ID).
  AprsAuthResult addAprsAuthNoMsgId(
    String srcAddress,
    String destAddress,
    String aprsMessage,
    DateTime time,
  ) {
    final aprsAddr = _padAddr(destAddress);
    final authPassword = _findAuthPassword(destAddress);
    if (authPassword == null || authPassword.isEmpty) {
      return AprsAuthResult(':$aprsAddr$aprsMessage', false);
    }
    final minutes = _minutesSinceEpoch(time);
    final hashInput = '$minutes:$srcAddress:${aprsAddr.trim()}$aprsMessage';
    final authCodeBase64 = _authCodeFor(authPassword, hashInput);
    return AprsAuthResult(':$aprsAddr$aprsMessage}$authCodeBase64', true);
  }

  /// Builds an APRS ACK message body with optional authentication.
  AprsAuthResult addAprsAckAuth(
    String srcAddress,
    String destAddress,
    String ackMessage,
    DateTime time,
  ) {
    final aprsAddr = _padAddr(destAddress);
    final authPassword = _findAuthPassword(destAddress);
    if (authPassword == null || authPassword.isEmpty) {
      return AprsAuthResult(':$aprsAddr:$ackMessage', false);
    }
    final minutes = _minutesSinceEpoch(time);
    final hashInput = '$minutes:$srcAddress:${aprsAddr.trim()}:$ackMessage';
    final authCodeBase64 = _authCodeFor(authPassword, hashInput);
    return AprsAuthResult(':$aprsAddr:$ackMessage}$authCodeBase64', true);
  }

  /// Verifies the authentication of an incoming (or echoed) APRS message.
  AuthState checkAprsAuth(
    bool sender,
    String srcAddress,
    String? aprsMessage,
    DateTime time,
  ) {
    if (aprsMessage == null || aprsMessage.length < 11) return AuthState.none;

    final aprsAddr = aprsMessage.substring(1, 10);
    final keyAddr = sender ? aprsAddr.trim() : srcAddress;

    final authPassword = _findAuthPassword(keyAddr);
    if (authPassword == null || authPassword.isEmpty) return AuthState.none;

    String? msgId;
    var messageContent = aprsMessage.substring(10);

    // Check for message ID (format: message{msgId).
    final msplit1 = messageContent.split('{');
    if (msplit1.length == 2) {
      msgId = msplit1[1];
      messageContent = msplit1[0];
    }

    // Check for auth code (format: message}authCode).
    final msplit2 = messageContent.split('}');
    if (msplit2.length != 2) return AuthState.none;

    final authCodeBase64Check = msplit2[1];
    final cleanMessage = msplit2[0];

    final minutesSinceEpoch = _minutesSinceEpoch(time) - 2;
    final authKey = _sha256(utf8.encode(authPassword));

    var hashMsg = ':$srcAddress:${aprsAddr.trim()}$cleanMessage';
    if (msgId != null) {
      hashMsg += '{$msgId';
    }

    // Try a window of 5 minutes to account for time drift.
    for (int x = minutesSinceEpoch; x < minutesSinceEpoch + 5; x++) {
      final computedAuth = _hmacSha256(authKey, utf8.encode('$x$hashMsg'));
      final authCodeBase64 = base64.encode(computedAuth).substring(0, 6);
      if (authCodeBase64Check == authCodeBase64) {
        return AuthState.success;
      }
    }

    return AuthState.failed;
  }
}
