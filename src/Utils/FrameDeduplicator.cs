/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Linq;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// A data handler that deduplicates DataFrame events received from multiple radios.
    /// When multiple radios receive the same data frame, this handler ensures only one
    /// UniqueDataFrame event is dispatched for frames not seen in the last 3 seconds.
    /// </summary>
    public class FrameDeduplicator : IDisposable
    {
        private readonly DataBrokerClient _broker;
        private readonly object _lock = new object();
        private bool _disposed = false;

        /// <summary>
        /// How long to keep frames in the deduplication cache (in seconds).
        /// </summary>
        private const double DeduplicationWindowSeconds = 3.0;

        /// <summary>
        /// Cache of recently seen frames with their timestamps.
        /// Key is the hex string of the frame data, value is the timestamp when it was first seen.
        /// </summary>
        private readonly Dictionary<string, DateTime> _recentFrames = new Dictionary<string, DateTime>();

        /// <summary>
        /// Creates a new FrameDeduplicator that listens for DataFrame events and dispatches UniqueDataFrame events.
        /// </summary>
        public FrameDeduplicator()
        {
            _broker = new DataBrokerClient();

            // Subscribe to DataFrame events from all devices (-1 = AllDevices)
            _broker.Subscribe(DataBroker.AllDevices, "DataFrame", OnDataFrame);
        }

        /// <summary>
        /// Gets whether the handler is disposed.
        /// </summary>
        public bool IsDisposed => _disposed;

        /// <summary>
        /// Handles incoming DataFrame events and dispatches UniqueDataFrame if the frame is unique.
        /// </summary>
        private void OnDataFrame(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is TncDataFragment frame)) return;

            // Create a unique key for this frame based on its data content
            string frameKey = frame.ToHex();
            if (string.IsNullOrEmpty(frameKey)) return;

            bool isUnique = false;
            DateTime now = DateTime.Now;

            lock (_lock)
            {
                // Clean up old frames first
                CleanupOldFrames(now);

                // Check if we've seen this frame recently
                if (!_recentFrames.ContainsKey(frameKey))
                {
                    // This is a unique frame - add it to the cache
                    _recentFrames[frameKey] = now;
                    isUnique = true;
                }
            }

            // Dispatch UniqueDataFrame on the same device we received it from
            if (isUnique)
            {
                _broker.Dispatch(deviceId, "UniqueDataFrame", frame, store: false);
            }
        }

        /// <summary>
        /// Removes frames older than the deduplication window from the cache.
        /// Must be called while holding the lock.
        /// </summary>
        private void CleanupOldFrames(DateTime now)
        {
            var cutoffTime = now.AddSeconds(-DeduplicationWindowSeconds);
            var keysToRemove = _recentFrames.Where(kvp => kvp.Value < cutoffTime).Select(kvp => kvp.Key).ToList();

            foreach (var key in keysToRemove)
            {
                _recentFrames.Remove(key);
            }
        }

        /// <summary>
        /// Gets the number of frames currently in the deduplication cache.
        /// </summary>
        public int CacheCount
        {
            get
            {
                lock (_lock)
                {
                    return _recentFrames.Count;
                }
            }
        }

        /// <summary>
        /// Clears all frames from the deduplication cache.
        /// </summary>
        public void ClearCache()
        {
            lock (_lock)
            {
                _recentFrames.Clear();
            }
        }

        /// <summary>
        /// Disposes the handler, unsubscribing from the broker.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Disposes the handler.
        /// </summary>
        /// <param name="disposing">True if called from Dispose(), false if called from finalizer.</param>
        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    // Dispose the broker client (unsubscribes)
                    _broker?.Dispose();

                    // Clear the cache
                    lock (_lock)
                    {
                        _recentFrames.Clear();
                    }
                }
                _disposed = true;
            }
        }

        /// <summary>
        /// Finalizer to ensure cleanup if Dispose is not called.
        /// </summary>
        ~FrameDeduplicator()
        {
            Dispose(false);
        }
    }
}
