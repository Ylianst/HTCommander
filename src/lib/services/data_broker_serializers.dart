/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../handlers/bbs_handler.dart';
import '../models/aircraft.dart';
import '../radio/tnc_data_fragment.dart';
import '../winlink/winlink_client.dart';
import '../winlink/winlink_mail.dart';
import 'data_broker.dart';

/// Registers cross-window serializers with the [DataBroker].
///
/// Detached (child) windows run in a separate OS process, so any value that
/// crosses the window boundary is transported as JSON. Primitive values, and
/// `Map`/`List` structures of primitives, round-trip automatically and need no
/// registration. Values that are dispatched as *typed objects* and consumed on
/// the other side with a strict type check (e.g. `data is Aircraft` or
/// `list.whereType<Aircraft>()`, with no `Map` fallback) must be registered
/// here so the receiving window can rebuild the concrete type.
///
/// Objects that merely expose a `toJson()` and whose consumers already accept
/// the decoded `Map` form (e.g. `RadioPosition`, `GpsData` in the map tab) do
/// NOT need to be registered — the broker serializes them via `toJson()` and
/// the consumer's `Map` branch handles them.
///
/// This must be called on every process (the host/main window and each detached
/// client window) before any window is attached.
void registerBrokerSerializers() {
  // Airplanes are dispatched as `List<Aircraft>` and the map tab rebuilds them
  // with `whereType<Aircraft>()`, which would drop plain maps — so Aircraft
  // must be reconstructed as a concrete type in detached windows.
  DataBroker.registerSerializer<Aircraft>(
    'aircraft',
    (value) => value.toJson(),
    (json) => Aircraft.fromJson(json),
  );

  // The mail list is dispatched as `List<WinLinkMail>` on the 'MailList' event.
  // Detached mail windows read that list and rebuild each message, so the
  // concrete type must survive the trip.
  DataBroker.registerSerializer<WinLinkMail>(
    'winlinkMail',
    (value) => value.toJson(),
    (json) => WinLinkMail.fromJson(json),
  );

  // APRS packets and frame events are dispatched as typed objects (and lists of
  // them) that the APRS tab consumes with strict type checks. They are encoded
  // by serializing the underlying AX.25 frame and re-parsed on the other side.
  DataBroker.registerSerializer<AprsPacket>(
    'aprsPacket',
    (value) => value.toJson() ?? <String, dynamic>{},
    (json) => AprsPacket.fromJson(json),
  );
  DataBroker.registerSerializer<AprsFrameEventArgs>(
    'aprsFrame',
    (value) => value.toJson(),
    (json) => AprsFrameEventArgs.fromJson(json),
  );

  // BBS statistics are dispatched as `List<MergedStationStats>` and the BBS tab
  // rebuilds them with `whereType<MergedStationStats>()`.
  DataBroker.registerSerializer<MergedStationStats>(
    'bbsMergedStats',
    (value) => value.toJson(),
    (json) => MergedStationStats.fromJson(json),
  );

  // The mail debug dialog shows a `List<WinlinkDebugEntry>` rebuilt with
  // `whereType<WinlinkDebugEntry>()`.
  DataBroker.registerSerializer<WinlinkDebugEntry>(
    'winlinkDebugEntry',
    (value) => value.toJson(),
    (json) => WinlinkDebugEntry.fromJson(json),
  );

  // The packet capture tab reads the stored packet list (dispatched as
  // `List<TncDataFragment>` on 'PacketList') and individual packets
  // (dispatched as `TncDataFragment` on 'PacketStored'). Detached packet
  // windows rebuild each fragment from its concrete type, so it must survive
  // the cross-window trip.
  DataBroker.registerSerializer<TncDataFragment>(
    'tncFragment',
    (value) => value.toJson(),
    (json) => TncDataFragment.fromJson(json),
  );
}
