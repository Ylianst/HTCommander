/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/models/station_info.dart';
import 'package:htcommander/winlink/winlink_gateway.dart';
import 'package:htcommander/winlink/winlink_gateway_options.dart';

WinlinkGateway _gateway(List<(int, int)> channels) => WinlinkGateway(
  callsign: 'KG4MRA-10',
  latitude: 35,
  longitude: -80,
  channels: [
    for (final (hz, modes) in channels)
      WinlinkGatewayChannel(frequencyHz: hz, modes: modes),
  ],
);

const _both =
    WinlinkGatewayChannel.packetMode | WinlinkGatewayChannel.varaFmMode;

void main() {
  test('lists one option per frequency and supported protocol', () {
    final gw = _gateway([
      (145050000, _both),
      (441000000, WinlinkGatewayChannel.varaFmMode),
    ]);

    final options = winlinkGatewayOptions(gw, xaraAvailable: true);

    expect(options.map((o) => o.label), [
      '2m · 145.050 MHz · Packet',
      '2m · 145.050 MHz · XARA',
      '70cm · 441.000 MHz · XARA',
    ]);
    expect(
      winlinkGatewayOptions(gw, xaraAvailable: false).map((o) => o.label),
      ['2m · 145.050 MHz · Packet'],
    );
  });

  test('builds a frequency-only Winlink station for the chosen option', () {
    const packet = WinlinkGatewayOption(
      145050000,
      WinlinkGatewayProtocol.packet,
    );
    const xara = WinlinkGatewayOption(441000000, WinlinkGatewayProtocol.xara);

    final p = packet.toStation('KG4MRA-10');
    expect(p.stationType, StationType.winlink);
    expect(p.terminalProtocol, TerminalProtocol.x25Session);
    expect(p.frequencyHz, 145050000);
    expect(p.channel, isEmpty);

    expect(
      xara.toStation('KG4MRA-10').terminalProtocol,
      TerminalProtocol.xaraNarrow,
    );
    expect(
      xara.toStation('KG4MRA-10', xaraWide: true).terminalProtocol,
      TerminalProtocol.xaraWide,
    );
  });

  test('drops XARA from gateways where XARA is unavailable', () {
    final mixed = _gateway([
      (145050000, _both),
      (441000000, WinlinkGatewayChannel.varaFmMode),
    ]);
    final xaraOnly = _gateway([(441000000, WinlinkGatewayChannel.varaFmMode)]);

    expect(usableWinlinkGateway(mixed, xaraAvailable: true), same(mixed));
    expect(usableWinlinkGateway(xaraOnly, xaraAvailable: false), isNull);

    final stripped = usableWinlinkGateway(mixed, xaraAvailable: false)!;
    expect(stripped.frequenciesHz, [145050000]);
    expect(stripped.channels.single.supportsVaraFm, isFalse);
    expect(stripped.channels.single.supportsPacket, isTrue);
  });
}
