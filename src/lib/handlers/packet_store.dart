/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/db/app_database.dart';

/// A data handler that stores packets to a file and maintains a running list of
/// the last [_maxPacketsInMemory] packets in memory.
///
/// Listens for `UniqueDataFrame` events (from the [FrameDeduplicator]) and
/// appends them to "packets.ptcap" in the application support directory. On
/// startup it loads the most recent packets back from that file so they can be
/// "played back" in the packet capture tab. Other modules can request the
/// packet list via the Data Broker by dispatching `RequestPacketList` on
/// device 1.
class PacketStore {
  /// Maximum number of packets to keep in memory.
  static const int _maxPacketsInMemory = 2000;

  /// The device id used for PacketStore broker messages.
  static const int _storeDeviceId = 1;

  final DataBrokerClient _broker = DataBrokerClient();

  /// Recent packets, kept in chronological order (newest at the end).
  final List<TncDataFragment> _packets = [];

  bool _disposed = false;

  /// Whether the handler has been disposed.
  bool get isDisposed => _disposed;

  /// Number of packets currently stored in memory.
  int get packetCount => _packets.length;

  /// Returns a copy of the current packet list.
  List<TncDataFragment> getPackets() => List<TncDataFragment>.from(_packets);

  /// Initializes the store: resolves the data file, loads existing packets,
  /// subscribes to broker events, and announces readiness. Must be awaited
  /// before registering the handler.
  Future<void> init() async {
    // The web build has no database (no dart:io), so packet persistence is
    // skipped there and packets are kept in memory only.
    await _loadPackets();

    // Subscribe to unique data frames from all radios.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );

    // Subscribe to requests for the packet list.
    _broker.subscribe(
      deviceId: _storeDeviceId,
      name: 'RequestPacketList',
      callback: _onRequestPacketList,
    );

    // Subscribe to clear requests.
    _broker.subscribe(
      deviceId: _storeDeviceId,
      name: 'ClearPackets',
      callback: _onClearPackets,
    );

    // Notify subscribers that PacketStore is ready (stored so late subscribers
    // can check the flag directly).
    _broker.dispatch(
      deviceId: _storeDeviceId,
      name: 'PacketStoreReady',
      data: true,
      store: true,
    );
  }

  /// Loads the last [_maxPacketsInMemory] packets from the database.
  Future<void> _loadPackets() async {
    final dao = AppDatabase.instance?.packets;
    if (dao == null) return; // web / no database: packets kept in memory only
    try {
      _packets.addAll(await dao.recent(_maxPacketsInMemory));
    } catch (e) {
      debugPrint('PacketStore: failed to load packets: $e');
    }
  }

  /// Parses a stored packet line into a [TncDataFragment], or null if invalid.
  ///
  /// Line format: `{microsecondsSinceEpoch},{incoming?1:0},{fragment.toString()}`
  static TncDataFragment? parsePacketLine(String line) {
    if (line.isEmpty) return null;

    // Split off the timestamp and direction prefix; the remainder is the
    // fragment string (which itself contains commas).
    final firstComma = line.indexOf(',');
    if (firstComma < 0) return null;
    final secondComma = line.indexOf(',', firstComma + 1);
    if (secondComma < 0) return null;

    final micros = int.tryParse(line.substring(0, firstComma));
    if (micros == null) return null;
    final incoming = line.substring(firstComma + 1, secondComma) == '1';
    final fragmentStr = line.substring(secondComma + 1);

    final fragment = TncDataFragment.fromString(fragmentStr);
    if (fragment == null) return null;

    fragment.time = DateTime.fromMicrosecondsSinceEpoch(micros);
    fragment.incoming = incoming;
    return fragment;
  }

  /// Handles incoming UniqueDataFrame events and stores the packet.
  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! TncDataFragment) return;

    // Persist to the database.
    _persistPacket(data);

    // Add to memory list, trimming to the maximum size.
    _packets.add(data);
    while (_packets.length > _maxPacketsInMemory) {
      _packets.removeAt(0);
    }

    // Notify that a new packet was stored.
    _broker.dispatch(
      deviceId: _storeDeviceId,
      name: 'PacketStored',
      data: data,
      store: false,
    );
  }

  /// Handles requests for the packet list by dispatching the current list.
  void _onRequestPacketList(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _broker.dispatch(
      deviceId: _storeDeviceId,
      name: 'PacketList',
      data: getPackets(),
      store: false,
    );
  }

  /// Clears all packets from memory and the database.
  void _onClearPackets(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _packets.clear();
    _clearPackets();
    _broker.dispatch(
      deviceId: _storeDeviceId,
      name: 'PacketList',
      data: getPackets(),
      store: false,
    );
  }

  /// Persists a packet to the database. Each insert is a small WAL append, so
  /// individual packets are durably committed as they arrive without the
  /// whole-file rewrites the previous flat file required.
  void _persistPacket(TncDataFragment frame) {
    final dao = AppDatabase.instance?.packets;
    if (dao == null) return;
    unawaited(
      dao
          .insert(frame)
          .catchError(
            (Object e) => debugPrint('PacketStore: failed to write packet: $e'),
          ),
    );
  }

  /// Deletes all persisted packets.
  void _clearPackets() {
    final dao = AppDatabase.instance?.packets;
    if (dao == null) return;
    unawaited(
      dao.clear().catchError(
        (Object e) => debugPrint('PacketStore: failed to clear packets: $e'),
      ),
    );
  }

  /// Disposes the handler, unsubscribing from the broker and closing the file.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _broker.dispose();
    _packets.clear();
  }
}
