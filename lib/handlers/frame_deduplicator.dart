/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// A data handler that deduplicates DataFrame events received from multiple
/// radios. When multiple radios receive the same data frame, this handler
/// ensures only one UniqueDataFrame event is dispatched for frames not seen in
/// the last [_deduplicationWindow].
class FrameDeduplicator {
  final DataBrokerClient _broker = DataBrokerClient();
  bool _disposed = false;

  /// How long to keep frames in the deduplication cache.
  static const Duration _deduplicationWindow = Duration(seconds: 3);

  /// Cache of recently seen frames with their timestamps. Key is the hex string
  /// of the frame data, value is the time when it was first seen.
  final Map<String, DateTime> _recentFrames = {};

  /// Creates a new FrameDeduplicator that listens for DataFrame events and
  /// dispatches UniqueDataFrame events.
  FrameDeduplicator() {
    // Subscribe to DataFrame events from all devices.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'DataFrame',
      callback: _onDataFrame,
    );
  }

  /// Whether the handler has been disposed.
  bool get isDisposed => _disposed;

  /// Number of frames currently in the deduplication cache.
  int get cacheCount => _recentFrames.length;

  /// Handles incoming DataFrame events and dispatches UniqueDataFrame if the
  /// frame is unique.
  void _onDataFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! TncDataFragment) return;

    // Create a unique key for this frame based on its data content.
    final frameKey = data.toHex();
    if (frameKey.isEmpty) return;

    final now = DateTime.now();
    _cleanupOldFrames(now);

    // Check if we've seen this frame recently.
    if (_recentFrames.containsKey(frameKey)) return;

    // This is a unique frame - add it to the cache and dispatch.
    _recentFrames[frameKey] = now;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'UniqueDataFrame',
      data: data,
      store: false,
    );
  }

  /// Removes frames older than the deduplication window from the cache.
  void _cleanupOldFrames(DateTime now) {
    final cutoff = now.subtract(_deduplicationWindow);
    _recentFrames.removeWhere((key, time) => time.isBefore(cutoff));
  }

  /// Clears all frames from the deduplication cache.
  void clearCache() => _recentFrames.clear();

  /// Disposes the handler, unsubscribing from the broker.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _broker.dispose();
    _recentFrames.clear();
  }
}
