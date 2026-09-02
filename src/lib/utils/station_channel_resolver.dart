/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import '../models/station_info.dart';
import '../services/data_broker_client.dart';

/// Outcome of resolving a station's stored channel/region against a radio.
enum StationChannelStatus {
  /// The channel/region were resolved (or the station has no channel and the
  /// current channel is used).
  ok,

  /// The station's stored region name no longer exists on the radio.
  regionMissing,

  /// The channel is expected in the radio's current region but was not found.
  channelMissing,

  /// The channel lives in another region, so it can't be resolved until the
  /// radio switches region; the radio resolves it after the switch.
  crossRegionPending,
}

/// The result of [resolveStationChannel].
class StationChannelResolution {
  final StationChannelStatus status;

  /// Target region index to lock onto (falls back to the current region).
  final int regionId;

  /// Resolved channel id, or -1 when it can't be resolved up front (empty
  /// channel or cross-region deferral).
  final int channelId;

  /// Channel name to pass to the lock for cross-region deferred resolution.
  final String? channelName;

  const StationChannelResolution(
    this.status, {
    this.regionId = -1,
    this.channelId = -1,
    this.channelName,
  });

  bool get isError =>
      status == StationChannelStatus.regionMissing ||
      status == StationChannelStatus.channelMissing;
}

/// Resolves [station]'s stored region/channel against radio [radioId] using the
/// broker's live `HtStatus`, `RegionNames` and `Channels` values.
///
/// Region existence and same-region channel existence are checked up front. A
/// channel in a different region can't be validated here (that region's channel
/// list isn't loaded); it is reported as [StationChannelStatus.crossRegionPending]
/// and the radio validates it after switching region.
StationChannelResolution resolveStationChannel(
  DataBrokerClient broker,
  int radioId,
  StationInfo station,
) {
  final htStatus = broker.getValueDynamic(radioId, 'HtStatus');
  final currRegion =
      (htStatus is Map ? htStatus['currRegion'] as int? : null) ?? 0;

  // Resolve the region the station's channel lives in.
  int targetRegion = currRegion;
  if (station.channelRegion.isNotEmpty) {
    final regionNames = broker.getValueDynamic(radioId, 'RegionNames');
    if (regionNames is List) {
      final idx = regionNames.indexOf(station.channelRegion);
      if (idx < 0) {
        return StationChannelResolution(
          StationChannelStatus.regionMissing,
          regionId: currRegion,
        );
      }
      targetRegion = idx;
    }
    // When RegionNames isn't available yet the region can't be validated; fall
    // back to the current region rather than blocking the connection.
  }

  // No channel configured: lock to the target region's current channel.
  if (station.channel.isEmpty) {
    return StationChannelResolution(
      StationChannelStatus.ok,
      regionId: targetRegion,
      channelId: -1,
    );
  }

  // Same region: the channel list is loaded, so resolve the id now.
  if (targetRegion == currRegion) {
    final channels = broker.getValueDynamic(radioId, 'Channels');
    if (channels is List) {
      for (int i = 0; i < channels.length; i++) {
        final channel = channels[i];
        if (channel is Map && channel['name'] == station.channel) {
          return StationChannelResolution(
            StationChannelStatus.ok,
            regionId: targetRegion,
            channelId: (channel['channelId'] as int?) ?? i,
          );
        }
      }
    }
    return StationChannelResolution(
      StationChannelStatus.channelMissing,
      regionId: targetRegion,
    );
  }

  // Different region: defer channel resolution to the radio post-switch.
  return StationChannelResolution(
    StationChannelStatus.crossRegionPending,
    regionId: targetRegion,
    channelName: station.channel,
  );
}
