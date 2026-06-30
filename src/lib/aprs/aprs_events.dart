/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import '../radio/ax25_packet.dart';
import '../radio/tnc_data_fragment.dart';
import 'aprs_packet.dart';

/// Event payload dispatched on the `AprsFrame` broker event.
/// Mirrors the C# `AprsFrameEventArgs`.
class AprsFrameEventArgs {
  final AprsPacket aprsPacket;
  final AX25Packet ax25Packet;
  final TncDataFragment? fragment;

  const AprsFrameEventArgs(this.aprsPacket, this.ax25Packet, this.fragment);
}

/// Data payload for the `SendAprsMessage` broker event.
/// Mirrors the C# `AprsSendMessageData`.
class AprsSendMessageData {
  final String destination;
  final String message;
  final int radioDeviceId;

  /// APRS route. Format: [RouteName, Dest, Path1, Path2, ...]
  final List<String>? route;

  const AprsSendMessageData({
    required this.destination,
    required this.message,
    required this.radioDeviceId,
    this.route,
  });
}
