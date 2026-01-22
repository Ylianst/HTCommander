/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// A data handler that manages BBS (Bulletin Board System) instances for radios.
    /// It listens for BBS control commands on Device ID 1 and creates/removes BBS instances
    /// for specific radio devices, locking the radio to a dedicated channel when a BBS is active.
    /// Also aggregates station statistics from all BBS instances into a merged table.
    /// </summary>
    public class BbsHandler : IDisposable
    {
        private readonly DataBrokerClient _broker;
        private readonly Dictionary<int, BBS> _bbsInstances;
        private readonly Dictionary<string, MergedStationStats> _mergedStats;
        private readonly object _lock = new object();
        private bool _disposed = false;

        /// <summary>
        /// Gets whether the handler is disposed.
        /// </summary>
        public bool IsDisposed => _disposed;

        /// <summary>
        /// Gets the number of active BBS instances.
        /// </summary>
        public int ActiveBbsCount
        {
            get
            {
                lock (_lock)
                {
                    return _bbsInstances.Count;
                }
            }
        }

        /// <summary>
        /// Creates a new BbsHandler that listens for BBS control commands on Device ID 1.
        /// </summary>
        public BbsHandler()
        {
            _broker = new DataBrokerClient();
            _bbsInstances = new Dictionary<int, BBS>();
            _mergedStats = new Dictionary<string, MergedStationStats>(StringComparer.OrdinalIgnoreCase);

            // Subscribe to BBS control commands on Device ID 1
            _broker.Subscribe(1, "CreateBbs", OnCreateBbs);
            _broker.Subscribe(1, "RemoveBbs", OnRemoveBbs);
            _broker.Subscribe(1, "GetBbsStatus", OnGetBbsStatus);

            // Subscribe to radio disconnection events to clean up BBS instances
            _broker.Subscribe(DataBroker.AllDevices, "State", OnRadioStateChanged);

            // Subscribe to BBS stats updates from individual BBS instances
            _broker.Subscribe(0, "BbsStatsUpdated", OnBbsStatsUpdated);
            _broker.Subscribe(0, "BbsStatsCleared", OnBbsStatsCleared);
            _broker.Subscribe(1, "BbsClearAllStats", OnBbsClearAllStats);

            _broker.LogInfo("[BbsHandler] BBS Handler initialized");
        }

        /// <summary>
        /// Handles the CreateBbs command to create a new BBS instance for a radio.
        /// </summary>
        private void OnCreateBbs(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is CreateBbsData createData)) return;

            int radioDeviceId = createData.RadioDeviceId;
            int channelId = createData.ChannelId;
            int regionId = createData.RegionId;

            lock (_lock)
            {
                // Check if a BBS instance already exists for this radio
                if (_bbsInstances.ContainsKey(radioDeviceId))
                {
                    _broker.LogError($"[BbsHandler] BBS instance already exists for radio {radioDeviceId}");
                    _broker.Dispatch(1, "BbsCreateFailed", new BbsErrorData
                    {
                        RadioDeviceId = radioDeviceId,
                        Error = "BBS instance already exists for this radio"
                    }, store: false);
                    return;
                }

                // Lock the radio for BBS usage
                var lockData = new SetLockData
                {
                    Usage = "BBS",
                    RegionId = regionId,
                    ChannelId = channelId
                };
                _broker.Dispatch(radioDeviceId, "SetLock", lockData, store: false);

                // Create the BBS instance
                BBS bbsInstance = new BBS(radioDeviceId);
                bbsInstance.Enabled = true;
                _bbsInstances[radioDeviceId] = bbsInstance;

                _broker.LogInfo($"[BbsHandler] Created BBS instance for radio {radioDeviceId} on channel {channelId}, region {regionId}");
            }

            // Dispatch success event
            _broker.Dispatch(1, "BbsCreated", new BbsStatusData
            {
                RadioDeviceId = radioDeviceId,
                ChannelId = channelId,
                RegionId = regionId,
                Enabled = true
            }, store: false);

            // Dispatch updated BBS list
            DispatchBbsList();
        }

        /// <summary>
        /// Handles the RemoveBbs command to remove and dispose a BBS instance for a radio.
        /// </summary>
        private void OnRemoveBbs(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is RemoveBbsData removeData)) return;

            int radioDeviceId = removeData.RadioDeviceId;

            lock (_lock)
            {
                // Check if a BBS instance exists for this radio
                if (!_bbsInstances.TryGetValue(radioDeviceId, out BBS bbsInstance))
                {
                    _broker.LogError($"[BbsHandler] No BBS instance exists for radio {radioDeviceId}");
                    _broker.Dispatch(1, "BbsRemoveFailed", new BbsErrorData
                    {
                        RadioDeviceId = radioDeviceId,
                        Error = "No BBS instance exists for this radio"
                    }, store: false);
                    return;
                }

                // Disable and dispose the BBS instance
                bbsInstance.Enabled = false;
                bbsInstance.Dispose();
                _bbsInstances.Remove(radioDeviceId);

                _broker.LogInfo($"[BbsHandler] Removed BBS instance for radio {radioDeviceId}");
            }

            // Unlock the radio
            var unlockData = new SetUnlockData
            {
                Usage = "BBS"
            };
            _broker.Dispatch(radioDeviceId, "SetUnlock", unlockData, store: false);

            // Dispatch success event
            _broker.Dispatch(1, "BbsRemoved", new BbsRemovedData
            {
                RadioDeviceId = radioDeviceId
            }, store: false);

            // Dispatch updated BBS list
            DispatchBbsList();
        }

        /// <summary>
        /// Handles the GetBbsStatus command to return the current BBS instances.
        /// </summary>
        private void OnGetBbsStatus(int deviceId, string name, object data)
        {
            if (_disposed) return;
            DispatchBbsList();
        }

        /// <summary>
        /// Handles BBS stats updates from individual BBS instances and merges them into the aggregate table.
        /// </summary>
        private void OnBbsStatsUpdated(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (data == null) return;

            // Extract stats from the anonymous type
            var dataType = data.GetType();
            var statsProp = dataType.GetProperty("Stats");
            var deviceIdProp = dataType.GetProperty("DeviceId");
            if (statsProp == null) return;

            var stats = statsProp.GetValue(data) as BBS.StationStats;
            int sourceDeviceId = deviceIdProp != null ? (int)deviceIdProp.GetValue(data) : 0;

            if (stats == null || string.IsNullOrEmpty(stats.callsign)) return;

            lock (_lock)
            {
                string key = stats.callsign.ToUpperInvariant();

                if (_mergedStats.TryGetValue(key, out MergedStationStats mergedStats))
                {
                    // Update existing entry - merge stats
                    mergedStats.LastSeen = stats.lastseen > mergedStats.LastSeen ? stats.lastseen : mergedStats.LastSeen;
                    mergedStats.Protocol = stats.protocol;
                    
                    // Update device-specific stats
                    if (!mergedStats.DeviceStats.ContainsKey(sourceDeviceId))
                    {
                        mergedStats.DeviceStats[sourceDeviceId] = new DeviceStationStats();
                    }
                    var deviceStats = mergedStats.DeviceStats[sourceDeviceId];
                    deviceStats.PacketsIn = stats.packetsIn;
                    deviceStats.PacketsOut = stats.packetsOut;
                    deviceStats.BytesIn = stats.bytesIn;
                    deviceStats.BytesOut = stats.bytesOut;

                    // Recalculate totals from all devices
                    RecalculateTotals(mergedStats);
                }
                else
                {
                    // Create new entry
                    mergedStats = new MergedStationStats
                    {
                        Callsign = stats.callsign,
                        LastSeen = stats.lastseen,
                        Protocol = stats.protocol,
                        DeviceStats = new Dictionary<int, DeviceStationStats>
                        {
                            [sourceDeviceId] = new DeviceStationStats
                            {
                                PacketsIn = stats.packetsIn,
                                PacketsOut = stats.packetsOut,
                                BytesIn = stats.bytesIn,
                                BytesOut = stats.bytesOut
                            }
                        }
                    };
                    RecalculateTotals(mergedStats);
                    _mergedStats[key] = mergedStats;
                }
            }

            // Dispatch the updated merged stats table
            DispatchMergedStats();
        }

        /// <summary>
        /// Recalculates the total stats from all device-specific stats.
        /// </summary>
        private void RecalculateTotals(MergedStationStats mergedStats)
        {
            mergedStats.TotalPacketsIn = 0;
            mergedStats.TotalPacketsOut = 0;
            mergedStats.TotalBytesIn = 0;
            mergedStats.TotalBytesOut = 0;

            foreach (var deviceStats in mergedStats.DeviceStats.Values)
            {
                mergedStats.TotalPacketsIn += deviceStats.PacketsIn;
                mergedStats.TotalPacketsOut += deviceStats.PacketsOut;
                mergedStats.TotalBytesIn += deviceStats.BytesIn;
                mergedStats.TotalBytesOut += deviceStats.BytesOut;
            }
        }

        /// <summary>
        /// Handles BBS stats cleared events from individual BBS instances.
        /// </summary>
        private void OnBbsStatsCleared(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (data == null) return;

            // Extract device ID from the event
            var dataType = data.GetType();
            var deviceIdProp = dataType.GetProperty("DeviceId");
            if (deviceIdProp == null) return;

            int sourceDeviceId = (int)deviceIdProp.GetValue(data);

            lock (_lock)
            {
                // Remove stats for this device from all merged entries
                List<string> keysToRemove = new List<string>();

                foreach (var kvp in _mergedStats)
                {
                    if (kvp.Value.DeviceStats.ContainsKey(sourceDeviceId))
                    {
                        kvp.Value.DeviceStats.Remove(sourceDeviceId);
                        
                        // If no more device stats, mark for removal
                        if (kvp.Value.DeviceStats.Count == 0)
                        {
                            keysToRemove.Add(kvp.Key);
                        }
                        else
                        {
                            // Recalculate totals
                            RecalculateTotals(kvp.Value);
                        }
                    }
                }

                // Remove entries with no device stats
                foreach (var key in keysToRemove)
                {
                    _mergedStats.Remove(key);
                }
            }

            // Dispatch the updated merged stats table
            DispatchMergedStats();
        }

        /// <summary>
        /// Handles request to clear all BBS stats.
        /// </summary>
        private void OnBbsClearAllStats(int deviceId, string name, object data)
        {
            if (_disposed) return;

            lock (_lock)
            {
                _mergedStats.Clear();

                // Also clear stats in all BBS instances
                foreach (var bbs in _bbsInstances.Values)
                {
                    bbs.ClearStats();
                }
            }

            // Dispatch the cleared stats table
            DispatchMergedStats();
        }

        /// <summary>
        /// Dispatches the current merged stats table to subscribers.
        /// </summary>
        private void DispatchMergedStats()
        {
            List<MergedStationStats> statsList;

            lock (_lock)
            {
                statsList = new List<MergedStationStats>(_mergedStats.Values);
            }

            _broker.Dispatch(1, "BbsMergedStats", statsList, store: true);
        }

        /// <summary>
        /// Handles radio state changes to clean up BBS instances when a radio disconnects.
        /// </summary>
        private void OnRadioStateChanged(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is string stateStr)) return;

            // Only handle disconnections
            if (stateStr != "Disconnected") return;

            lock (_lock)
            {
                // Check if there's a BBS instance for this radio
                if (_bbsInstances.TryGetValue(deviceId, out BBS bbsInstance))
                {
                    _broker.LogInfo($"[BbsHandler] Radio {deviceId} disconnected, removing BBS instance");

                    // Disable and dispose the BBS instance
                    bbsInstance.Enabled = false;
                    bbsInstance.Dispose();
                    _bbsInstances.Remove(deviceId);

                    // Dispatch removal event
                    _broker.Dispatch(1, "BbsRemoved", new BbsRemovedData
                    {
                        RadioDeviceId = deviceId
                    }, store: false);

                    // Dispatch updated BBS list
                    DispatchBbsList();
                }
            }
        }

        /// <summary>
        /// Dispatches the current list of active BBS instances.
        /// </summary>
        private void DispatchBbsList()
        {
            List<BbsStatusData> bbsList = new List<BbsStatusData>();

            lock (_lock)
            {
                foreach (var kvp in _bbsInstances)
                {
                    // Get lock state from the radio to get channel/region info
                    var lockState = _broker.GetValue<RadioLockState>(kvp.Key, "LockState", null);

                    bbsList.Add(new BbsStatusData
                    {
                        RadioDeviceId = kvp.Key,
                        ChannelId = lockState?.ChannelId ?? -1,
                        RegionId = lockState?.RegionId ?? -1,
                        Enabled = kvp.Value.Enabled
                    });
                }
            }

            _broker.Dispatch(1, "BbsList", bbsList, store: true);
        }

        /// <summary>
        /// Gets a BBS instance by radio device ID.
        /// </summary>
        /// <param name="radioDeviceId">The radio device ID.</param>
        /// <returns>The BBS instance, or null if not found.</returns>
        public BBS GetBbsInstance(int radioDeviceId)
        {
            lock (_lock)
            {
                _bbsInstances.TryGetValue(radioDeviceId, out BBS bbsInstance);
                return bbsInstance;
            }
        }

        /// <summary>
        /// Gets a list of all active radio device IDs with BBS instances.
        /// </summary>
        /// <returns>A list of radio device IDs.</returns>
        public List<int> GetActiveBbsRadioIds()
        {
            lock (_lock)
            {
                return new List<int>(_bbsInstances.Keys);
            }
        }

        /// <summary>
        /// Disposes the handler, cleaning up all BBS instances.
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
                    _broker?.LogInfo("[BbsHandler] BBS Handler disposing");

                    // Dispose all BBS instances
                    lock (_lock)
                    {
                        foreach (var kvp in _bbsInstances)
                        {
                            kvp.Value.Enabled = false;
                            kvp.Value.Dispose();

                            // Unlock the radio
                            var unlockData = new SetUnlockData
                            {
                                Usage = "BBS"
                            };
                            _broker.Dispatch(kvp.Key, "SetUnlock", unlockData, store: false);
                        }
                        _bbsInstances.Clear();
                    }

                    _broker?.Dispose();
                }
                _disposed = true;
            }
        }

        /// <summary>
        /// Finalizer to ensure cleanup if Dispose is not called.
        /// </summary>
        ~BbsHandler()
        {
            Dispose(false);
        }
    }

    /// <summary>
    /// Merged station statistics aggregated from all BBS instances.
    /// </summary>
    public class MergedStationStats
    {
        /// <summary>
        /// The station callsign.
        /// </summary>
        public string Callsign { get; set; }

        /// <summary>
        /// The last time this station was seen (across all radios).
        /// </summary>
        public DateTime LastSeen { get; set; }

        /// <summary>
        /// The protocol used by this station.
        /// </summary>
        public string Protocol { get; set; }

        /// <summary>
        /// Total packets received from this station (across all radios).
        /// </summary>
        public int TotalPacketsIn { get; set; }

        /// <summary>
        /// Total packets sent to this station (across all radios).
        /// </summary>
        public int TotalPacketsOut { get; set; }

        /// <summary>
        /// Total bytes received from this station (across all radios).
        /// </summary>
        public int TotalBytesIn { get; set; }

        /// <summary>
        /// Total bytes sent to this station (across all radios).
        /// </summary>
        public int TotalBytesOut { get; set; }

        /// <summary>
        /// Per-device statistics for this station.
        /// </summary>
        public Dictionary<int, DeviceStationStats> DeviceStats { get; set; } = new Dictionary<int, DeviceStationStats>();
    }

    /// <summary>
    /// Station statistics for a specific device/radio.
    /// </summary>
    public class DeviceStationStats
    {
        public int PacketsIn { get; set; }
        public int PacketsOut { get; set; }
        public int BytesIn { get; set; }
        public int BytesOut { get; set; }
    }

    /// <summary>
    /// Data class for creating a BBS instance.
    /// </summary>
    public class CreateBbsData
    {
        /// <summary>
        /// The radio device ID to create the BBS for.
        /// </summary>
        public int RadioDeviceId { get; set; }

        /// <summary>
        /// The channel ID to lock the radio to for BBS operations.
        /// </summary>
        public int ChannelId { get; set; }

        /// <summary>
        /// The region ID for the radio.
        /// </summary>
        public int RegionId { get; set; }
    }

    /// <summary>
    /// Data class for removing a BBS instance.
    /// </summary>
    public class RemoveBbsData
    {
        /// <summary>
        /// The radio device ID to remove the BBS from.
        /// </summary>
        public int RadioDeviceId { get; set; }
    }

    /// <summary>
    /// Data class for BBS status information.
    /// </summary>
    public class BbsStatusData
    {
        /// <summary>
        /// The radio device ID.
        /// </summary>
        public int RadioDeviceId { get; set; }

        /// <summary>
        /// The channel ID the BBS is operating on.
        /// </summary>
        public int ChannelId { get; set; }

        /// <summary>
        /// The region ID.
        /// </summary>
        public int RegionId { get; set; }

        /// <summary>
        /// Whether the BBS is enabled.
        /// </summary>
        public bool Enabled { get; set; }
    }

    /// <summary>
    /// Data class for BBS removal events.
    /// </summary>
    public class BbsRemovedData
    {
        /// <summary>
        /// The radio device ID that was removed.
        /// </summary>
        public int RadioDeviceId { get; set; }
    }

    /// <summary>
    /// Data class for BBS error events.
    /// </summary>
    public class BbsErrorData
    {
        /// <summary>
        /// The radio device ID related to the error.
        /// </summary>
        public int RadioDeviceId { get; set; }

        /// <summary>
        /// The error message.
        /// </summary>
        public string Error { get; set; }
    }
}
