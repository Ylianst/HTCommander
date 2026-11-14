/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../models/station_info.dart';
import 'winlink_gateway.dart';

/// Whether this platform can run the XARA software modem. It needs the radio
/// audio channel, which is unavailable on web and iOS.
bool get winlinkXaraSupported =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

/// Protocol used to reach a Winlink gateway on one of its frequencies.
enum WinlinkGatewayProtocol { packet, xara }

/// One way to connect to a Winlink gateway: a frequency plus a protocol.
class WinlinkGatewayOption {
  final int frequencyHz;
  final WinlinkGatewayProtocol protocol;

  const WinlinkGatewayOption(this.frequencyHz, this.protocol);

  /// Amateur band name for [frequencyHz] (e.g. `2m`), empty when unknown.
  String get bandLabel {
    final mhz = frequencyHz / 1e6;
    if (mhz >= 50 && mhz <= 54) return '6m';
    if (mhz >= 144 && mhz <= 148) return '2m';
    if (mhz >= 219 && mhz <= 225) return '1.25m';
    if (mhz >= 420 && mhz <= 450) return '70cm';
    if (mhz >= 902 && mhz <= 928) return '33cm';
    return '';
  }

  String get protocolLabel =>
      protocol == WinlinkGatewayProtocol.xara ? 'XARA' : 'Packet';

  /// E.g. `2m · 145.050 MHz · Packet`.
  String get label => [
    if (bandLabel.isNotEmpty) bandLabel,
    '${(frequencyHz / 1e6).toStringAsFixed(3)} MHz',
    protocolLabel,
  ].join(' · ');

  /// A Winlink station for [callsign] on this frequency and protocol. XARA
  /// uses the narrow or wide variant per [xaraWide] (the global setting).
  StationInfo toStation(String callsign, {bool xaraWide = false}) {
    final xara = protocol == WinlinkGatewayProtocol.xara;
    return StationInfo(
      callsign: callsign,
      stationType: StationType.winlink,
      terminalProtocol: xara
          ? (xaraWide ? TerminalProtocol.xaraWide : TerminalProtocol.xaraNarrow)
          : TerminalProtocol.x25Session,
      frequencyHz: frequencyHz,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WinlinkGatewayOption &&
      other.frequencyHz == frequencyHz &&
      other.protocol == protocol;

  @override
  int get hashCode => Object.hash(frequencyHz, protocol);
}

/// Every frequency/protocol combination [gw] offers, in directory order with
/// Packet before XARA on a shared frequency. XARA is left out unless
/// [xaraAvailable].
List<WinlinkGatewayOption> winlinkGatewayOptions(
  WinlinkGateway gw, {
  required bool xaraAvailable,
}) => [
  for (final c in gw.channels) ...[
    if (c.supportsPacket)
      WinlinkGatewayOption(c.frequencyHz, WinlinkGatewayProtocol.packet),
    if (xaraAvailable && c.supportsVaraFm)
      WinlinkGatewayOption(c.frequencyHz, WinlinkGatewayProtocol.xara),
  ],
];

/// [gw] as it should be shown on this platform: without XARA when
/// [xaraAvailable] is false, or null when nothing usable is left.
WinlinkGateway? usableWinlinkGateway(
  WinlinkGateway gw, {
  required bool xaraAvailable,
}) {
  if (xaraAvailable) return gw.channels.isEmpty ? null : gw;
  if (gw.channels.every((c) => !c.supportsVaraFm)) {
    return gw.channels.isEmpty ? null : gw;
  }
  final channels = [
    for (final c in gw.channels)
      if (c.supportsPacket)
        WinlinkGatewayChannel(
          frequencyHz: c.frequencyHz,
          modes: WinlinkGatewayChannel.packetMode,
        ),
  ];
  if (channels.isEmpty) return null;
  return WinlinkGateway(
    callsign: gw.callsign,
    latitude: gw.latitude,
    longitude: gw.longitude,
    channels: channels,
  );
}
