/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';

import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'digipeater_config.dart';

/// A data handler that acts as an APRS digipeater.
///
/// When [DigipeaterConfig.enabled] is set, it listens to incoming APRS frames
/// on the "APRS" channel, decides whether a frame should be repeated using the
/// WIDEn-N "New Paradigm" (plus optional custom aliases and a fill-in only
/// mode), rewrites the AX.25 digipeater path (decrementing the hop count,
/// marking the has-been-repeated bit and optionally inserting its own
/// callsign), and re-transmits the frame. Recently seen frames are suppressed
/// to avoid loops.
///
/// While enabled the radio is locked to the APRS channel with the usage
/// `Digipeater`, mirroring the BBS/Terminal/Torrent handlers.
class DigipeaterConstants {
  /// Callsign base used for WIDEn-N flooding.
  static const String wide = 'WIDE';

  /// Maximum number of addresses (dest + src + 8 digipeaters) in an AX.25
  /// frame.
  static const int maxAddresses = 10;

  /// AX.25 lock usage identifier.
  static const String lockUsage = 'Digipeater';
}

class DigipeaterHandler {
  final DataBrokerClient _broker = DataBrokerClient();

  DigipeaterConfig _config = const DigipeaterConfig();
  bool _disposed = false;

  /// Recently repeated frames: dedup key -> time last repeated.
  final Map<String, DateTime> _recent = {};

  DigipeaterConfig get config => _config;

  /// Initializes the handler: subscribes to broker events and loads persisted
  /// configuration. Safe to call once at startup.
  void init() {
    // Incoming frames from all radios.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );

    // Configuration changes from the UI (device 0).
    _broker.subscribe(
      deviceId: 0,
      name: 'DigipeaterConfig',
      callback: _onConfigChanged,
    );

    // Load any persisted configuration.
    _loadConfig(_broker.getValueDynamic(0, 'DigipeaterConfig', null));
    if (_config.enabled) _applyLock(_config, lock: true);
  }

  void _onConfigChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final previous = _config;
    _loadConfig(data);
    _reconcileLock(previous, _config);
  }

  void _loadConfig(Object? data) {
    if (data is DigipeaterConfig) {
      _config = data;
      return;
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          _config = DigipeaterConfig.fromJson(decoded);
          return;
        }
      } catch (_) {
        // Ignore malformed configuration.
      }
    }
    if (data is Map<String, dynamic>) {
      _config = DigipeaterConfig.fromJson(data);
    }
  }

  /// Locks or unlocks the radio when the enabled state or target radio changes.
  void _reconcileLock(DigipeaterConfig previous, DigipeaterConfig current) {
    final wasActive = previous.enabled && previous.radioDeviceId > 0;

    // Unlock the previously locked radio if we are stopping or switching radios.
    if (wasActive &&
        (!current.enabled || previous.radioDeviceId != current.radioDeviceId)) {
      _applyUnlock(previous);
    }

    // Whenever the digipeater is active, (re)apply the lock. SetLock is a safe
    // no-op when the radio is already locked, so re-issuing it here recovers
    // from cases where an earlier lock attempt was dropped because the radio
    // was not ready yet (e.g. right after startup).
    if (current.enabled && current.radioDeviceId > 0) {
      _applyLock(current, lock: true);
    }
  }

  void _applyLock(DigipeaterConfig config, {required bool lock}) {
    if (config.radioDeviceId <= 0) return;
    final channelId = _getAprsChannelId(config.radioDeviceId);
    if (channelId < 0) {
      _broker.logError(
        'Digipeater: No APRS channel found on radio ${config.radioDeviceId}',
      );
      return;
    }
    _broker.dispatch(
      deviceId: config.radioDeviceId,
      name: 'SetLock',
      data: SetLockData(
        usage: DigipeaterConstants.lockUsage,
        regionId: -1,
        channelId: channelId,
      ),
      store: false,
    );
  }

  void _applyUnlock(DigipeaterConfig config) {
    if (config.radioDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: config.radioDeviceId,
      name: 'SetUnlock',
      data: SetUnlockData(usage: DigipeaterConstants.lockUsage),
      store: false,
    );
  }

  /// Returns the channel id of the "APRS" channel for [radioDeviceId], or -1.
  int _getAprsChannelId(int radioDeviceId) {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      radioDeviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return -1;
    for (final channel in channels) {
      if (channel.name == 'APRS') return channel.channelId;
    }
    return -1;
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (_disposed || !_config.enabled) return;
    if (data is! TncDataFragment) return;
    final frame = data;
    if (frame.channelName != 'APRS') return;

    final radioDeviceId = frame.radioDeviceId ?? deviceId;
    if (_config.radioDeviceId > 0 && radioDeviceId != _config.radioDeviceId) {
      return;
    }

    final ax25Packet = AX25Packet.decode(frame);
    if (ax25Packet == null) return;
    if (ax25Packet.type != FrameType.uFrameUi &&
        ax25Packet.type != FrameType.uFrame) {
      return;
    }
    // Never repeat frames we transmitted ourselves.
    if (ax25Packet.sent || !frame.incoming) return;

    final ownCall = _ownAddress();
    if (ownCall == null) return;

    // Duplicate/loop suppression.
    final dedupKey = _dedupKey(ax25Packet);
    if (_isDuplicate(dedupKey)) return;

    final repeated = _computeRepeat(ax25Packet, ownCall);
    if (repeated == null) return;

    _recordSeen(dedupKey);

    final aprsChannelId = _getAprsChannelId(radioDeviceId);
    if (aprsChannelId < 0) return;

    repeated.pid = ax25Packet.pid == 0 ? 240 : ax25Packet.pid;
    repeated.type = FrameType.uFrameUi;
    repeated.command = true;
    repeated.incoming = false;
    repeated.sent = false;
    repeated.channelId = aprsChannelId;
    repeated.channelName = 'APRS';

    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        packet: repeated,
        channelId: aprsChannelId,
        regionId: -1,
      ),
      store: false,
    );
  }

  /// The digipeater's own AX.25 address (global callsign + station id from the
  /// settings dialog).
  AX25Address? _ownAddress() {
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    if (callsign.isEmpty) return null;
    final stationId = (_broker.getValue<int>(0, 'StationId', 0) ?? 0).clamp(
      0,
      15,
    );
    return AX25Address.getAddress(callsign, stationId);
  }

  /// Builds a deduplication key from the source callsign and payload.
  String _dedupKey(AX25Packet packet) {
    final src = packet.source?.callSignWithId ?? '';
    final dest = packet.destination?.callSignWithId ?? '';
    final payload = packet.dataStr ?? '';
    return '$src>$dest|$payload';
  }

  bool _isDuplicate(String key) {
    if (_config.dedupSeconds <= 0) return false;
    _pruneRecent();
    return _recent.containsKey(key);
  }

  void _recordSeen(String key) {
    if (_config.dedupSeconds <= 0) return;
    _recent[key] = DateTime.now();
  }

  void _pruneRecent() {
    if (_recent.isEmpty) return;
    final cutoff = DateTime.now().subtract(
      Duration(seconds: _config.dedupSeconds),
    );
    _recent.removeWhere((_, when) => when.isBefore(cutoff));
  }

  /// Determines whether [packet] should be repeated and, if so, returns a new
  /// packet with the rewritten digipeater path. Returns null if the packet is
  /// not eligible for digipeating.
  AX25Packet? _computeRepeat(AX25Packet packet, AX25Address ownCall) {
    // Path entries are addresses after dest + src.
    final path = packet.addresses.length > 2
        ? packet.addresses.sublist(2)
        : const <AX25Address>[];
    if (path.isEmpty) return null;

    // Find the first unused (not yet repeated) path entry.
    int nextIndex = -1;
    for (int i = 0; i < path.length; i++) {
      if (!_hasBeenRepeated(path[i])) {
        nextIndex = i;
        break;
      }
    }
    if (nextIndex < 0) return null;

    final entry = path[nextIndex];

    // Don't repeat if we already appear (repeated) in the path (loop guard).
    for (int i = 0; i < nextIndex; i++) {
      if (path[i].isSame(ownCall)) return null;
    }

    // Build the rewritten packet as a deep-ish copy of the addresses.
    final newAddresses = <AX25Address>[
      for (final a in packet.addresses) _cloneAddress(a),
    ];
    // Index within the full address list for the entry we act on.
    final entryAddrIndex = nextIndex + 2;

    final base = entry.address.toUpperCase();

    // Exact match against our own identity or a configured alias.
    if (entry.isSame(ownCall) || _matchesAlias(entry)) {
      _setRepeated(newAddresses[entryAddrIndex]);
      // Substitute our real callsign for a generic alias match.
      newAddresses[entryAddrIndex].address = ownCall.address;
      newAddresses[entryAddrIndex].ssid = ownCall.ssid;
      return _rebuild(packet, newAddresses);
    }

    // WIDEn-N handling.
    if (base == DigipeaterConstants.wide) {
      final n = entry.ssid;
      // Fill-in mode only services WIDE1-1.
      if (_config.fillInOnly) {
        if (!(n == 1)) return null;
      } else if (!_config.handleWideN) {
        return null;
      }
      if (n <= 0) return null;

      final cappedInsert = _config.substituteOwnCall && n > 0;
      final newN = (n - 1).clamp(0, _config.maxHops);

      if (newN == 0) {
        // Last hop: mark the WIDE entry repeated.
        _setRepeated(newAddresses[entryAddrIndex]);
        if (cappedInsert) {
          _insertOwnCall(newAddresses, entryAddrIndex, ownCall);
        }
      } else {
        // Decrement the hop count.
        newAddresses[entryAddrIndex].ssid = newN;
        if (cappedInsert) {
          _insertOwnCall(newAddresses, entryAddrIndex, ownCall);
        }
      }
      return _rebuild(packet, newAddresses);
    }

    return null;
  }

  /// Inserts our own (already-repeated) callsign immediately before the address
  /// at [entryAddrIndex], respecting the maximum address count.
  void _insertOwnCall(
    List<AX25Address> addresses,
    int entryAddrIndex,
    AX25Address ownCall,
  ) {
    if (addresses.length >= DigipeaterConstants.maxAddresses) return;
    final own = _cloneAddress(ownCall);
    _setRepeated(own);
    addresses.insert(entryAddrIndex, own);
  }

  AX25Packet _rebuild(AX25Packet source, List<AX25Address> addresses) {
    final packet = AX25Packet(
      addresses: addresses,
      dataStr: source.dataStr,
      data: source.data,
      type: FrameType.uFrameUi,
      command: true,
      time: DateTime.now(),
    );
    packet.pid = source.pid;
    return packet;
  }

  bool _matchesAlias(AX25Address entry) {
    for (final alias in _config.aliases) {
      final parsed = AX25Address.parse(alias);
      if (parsed != null && parsed.isSame(entry)) return true;
    }
    return false;
  }

  /// The has-been-repeated (H) bit for a digipeater path address is carried in
  /// bit 7 of the SSID octet, decoded into [AX25Address.crBit1].
  bool _hasBeenRepeated(AX25Address address) => address.crBit1;

  void _setRepeated(AX25Address address) => address.crBit1 = true;

  AX25Address _cloneAddress(AX25Address a) {
    final copy = AX25Address.getAddress(a.address, a.ssid)!;
    copy.crBit1 = a.crBit1;
    copy.crBit2 = a.crBit2;
    copy.crBit3 = a.crBit3;
    return copy;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_config.enabled && _config.radioDeviceId > 0) {
      _applyUnlock(_config);
    }
    _recent.clear();
    _broker.dispose();
  }
}
