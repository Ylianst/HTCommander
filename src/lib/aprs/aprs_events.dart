/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import '../radio/ax25_packet.dart';
import '../radio/tnc_data_fragment.dart';
import 'aprs_packet.dart';
import 'aprs_link_policy.dart';

/// Event payload dispatched on the `AprsFrame` broker event.
/// Mirrors the C# `AprsFrameEventArgs`.
class AprsFrameEventArgs {
  final AprsPacket aprsPacket;
  final AX25Packet ax25Packet;
  final TncDataFragment? fragment;
  final bool historical;

  const AprsFrameEventArgs(this.aprsPacket, this.ax25Packet, this.fragment, {this.historical = false});

  /// Serializes for cross-window transport. The underlying AX.25 frame carries
  /// everything needed to rebuild both the raw and parsed packets.
  Map<String, dynamic> toJson() {
    final json = ax25Packet.toJson();
    if (aprsPacket.fromAprsIs) json['fromAprsIs'] = true;
    if (historical) json['historical'] = true;
    return json;
  }

  /// Rebuilds an [AprsFrameEventArgs] from data produced by [toJson] so a
  /// detached window can render live APRS frames. Always returns a non-null
  /// instance; unparseable frames yield empty packets that consumers ignore.
  static AprsFrameEventArgs fromJson(Map<String, dynamic> json) {
    final ax25 = AX25Packet.fromJson(json) ?? AX25Packet(addresses: []);
    final aprs = AprsPacket.fromJson(json);
    return AprsFrameEventArgs(aprs, ax25, null, historical: json['historical'] == true);
  }
}

/// Data payload for the `SendAprsMessage` broker event.
/// Mirrors the C# `AprsSendMessageData`.
class AprsSendMessageData {
  final String destination;
  final String message;
  final int radioDeviceId;

  /// APRS route. Format: [RouteName, Dest, Path1, Path2, ...]
  final List<String>? route;
  final AprsLinkPolicy policy;

  const AprsSendMessageData({
    required this.destination,
    required this.message,
    required this.radioDeviceId,
    this.route,
    this.policy = AprsLinkPolicy.automatic,
  });

  Map<String, Object?> toJson() => {
    'destination': destination, 'message': message,
    'radioDeviceId': radioDeviceId, 'route': route, 'policy': policy.name,
  };

  factory AprsSendMessageData.fromJson(Map<String, dynamic> json) => AprsSendMessageData(
    destination: json['destination'] as String,
    message: json['message'] as String,
    radioDeviceId: json['radioDeviceId'] as int,
    route: (json['route'] as List?)?.cast<String>(),
    policy: json['policy'] == null ? AprsLinkPolicy.automatic :
      AprsLinkPolicy.values.byName(json['policy'] as String),
  );
}
