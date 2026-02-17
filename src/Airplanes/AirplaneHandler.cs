/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Threading;
using System.Threading.Tasks;

namespace HTCommander.Airplanes
{
    /// <summary>
    /// Data Broker handler that polls a Dump1090 endpoint for airplane data.
    /// Reads the "AirplaneServer" setting from device 0 and, when present,
    /// uses <see cref="Dump1090HttpClient"/> to periodically fetch aircraft.
    /// Each successful poll dispatches an "Airplanes" event with the aircraft list.
    /// </summary>
    public class AirplaneHandler : IDisposable
    {
        private readonly DataBrokerClient broker;
        private Dump1090HttpClient _client;
        private CancellationTokenSource _cts;
        private string _currentUrl;
        private bool _showOnMap;
        private bool _disposed;

        public AirplaneHandler()
        {
            broker = new DataBrokerClient();

            // Subscribe to AirplaneServer setting changes on device 0
            broker.Subscribe(0, "AirplaneServer", OnAirplaneServerChanged);

            // Subscribe to ShowAirplanesOnMap to start/stop polling
            broker.Subscribe(0, "ShowAirplanesOnMap", OnShowAirplanesOnMapChanged);

            // Subscribe to test requests on device 1
            broker.Subscribe(1, "TestAirplaneServer", OnTestAirplaneServer);

            // Load initial state
            _showOnMap = broker.GetValue<int>(0, "ShowAirplanesOnMap", 0) == 1;
            string server = broker.GetValue<string>(0, "AirplaneServer", "");
            if (!string.IsNullOrEmpty(server))
            {
                ApplyServerSetting(server);
            }
        }

        /// <summary>
        /// Called when the "AirplaneServer" setting changes on device 0.
        /// </summary>
        private void OnAirplaneServerChanged(int deviceId, string name, object data)
        {
            string server = data as string ?? "";
            ApplyServerSetting(server);
        }

        /// <summary>
        /// Called when the "ShowAirplanesOnMap" setting changes on device 0.
        /// </summary>
        private void OnShowAirplanesOnMapChanged(int deviceId, string name, object data)
        {
            _showOnMap = (data is int val) && val == 1;
            // Re-evaluate polling with the current server setting
            string server = broker.GetValue<string>(0, "AirplaneServer", "");
            ApplyServerSetting(server);
        }

        /// <summary>
        /// Applies a new server setting: stops any existing poll loop and, if
        /// the value is non-empty and ShowAirplanesOnMap is true, starts a new one.
        /// </summary>
        private void ApplyServerSetting(string server)
        {
            string url = _showOnMap ? ResolveUrl(server) : null;

            // If the resolved URL hasn't changed, nothing to do
            if (url == _currentUrl) return;

            // Stop any existing poll
            StopPolling();

            _currentUrl = url;

            if (!string.IsNullOrEmpty(url))
            {
                StartPolling(url);
            }
        }

        /// <summary>
        /// Resolves the server setting to a full URL.
        /// If it starts with "http://", use as-is; otherwise build the default Dump1090 URL.
        /// </summary>
        private static string ResolveUrl(string server)
        {
            if (string.IsNullOrWhiteSpace(server)) return null;

            server = server.Trim();
            if (server.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                server.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return server;
            }

            return $"http://{server}/data/aircraft.json";
        }

        /// <summary>
        /// Starts the background polling loop against the given URL.
        /// </summary>
        private void StartPolling(string url)
        {
            _cts = new CancellationTokenSource();
            _client = new Dump1090HttpClient(url);
            var token = _cts.Token;

            Task.Run(async () =>
            {
                await _client.PollAsync(async response =>
                {
                    broker.Dispatch(0, "Airplanes", response.Aircraft, store: false);
                    await Task.CompletedTask;
                }, token);
            }, token);
        }

        /// <summary>
        /// Stops the current polling loop and disposes the HTTP client.
        /// </summary>
        private void StopPolling()
        {
            if (_cts != null)
            {
                _cts.Cancel();
                _cts.Dispose();
                _cts = null;
            }

            if (_client != null)
            {
                _client.Dispose();
                _client = null;
            }
        }

        /// <summary>
        /// Handles a test request from SettingsForm. Tries a single fetch against the
        /// provided server value and dispatches the result on device 1.
        /// </summary>
        private async void OnTestAirplaneServer(int deviceId, string name, object data)
        {
            string server = data as string ?? "";
            string url = ResolveUrl(server);
            if (string.IsNullOrEmpty(url))
            {
                broker.Dispatch(1, "TestAirplaneServerResult", "Failed: empty server address", store: false);
                return;
            }

            try
            {
                using (var client = new Dump1090HttpClient(url))
                {
                    var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                    var response = await client.GetAircraftAsync(cts.Token);
                    int count = response.Aircraft != null ? response.Aircraft.Length : 0;
                    broker.Dispatch(1, "TestAirplaneServerResult", $"Success, {count} aircraft found.", store: false);
                }
            }
            catch (Exception ex)
            {
                broker.Dispatch(1, "TestAirplaneServerResult", $"Failed: {ex.Message}", store: false);
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            StopPolling();
            broker?.Dispose();
        }
    }
}
