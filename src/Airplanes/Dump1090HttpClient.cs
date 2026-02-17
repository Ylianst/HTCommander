/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json;
using System.Net.Http.Json;
using System.Net.Http;

namespace HTCommander.Airplanes
{

    /// <summary>
    /// HTTP client that polls a Dump1090 aircraft.json endpoint.
    /// </summary>
    public sealed class Dump1090HttpClient : IDisposable
    {
        private readonly HttpClient _http;
        private readonly Uri _uri;

        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNameCaseInsensitive = true
        };

        public Dump1090HttpClient(string url)
        {
            _uri = new Uri(url);
            _http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        }

        /// <summary>
        /// Fetches the current aircraft list from the Dump1090 endpoint.
        /// Returns the full <see cref="AircraftResponse"/> including the aircraft array.
        /// </summary>
        public async Task<AircraftResponse> GetAircraftAsync(CancellationToken ct = default)
        {
            var response = await _http.GetAsync(_uri, ct);
            response.EnsureSuccessStatusCode();

            var result = await response.Content.ReadFromJsonAsync<AircraftResponse>(JsonOptions, ct);
            return result ?? new AircraftResponse();
        }

        /// <summary>
        /// Continuously polls the endpoint. Waits one second after each completed
        /// request before issuing the next one. Invokes <paramref name="onData"/>
        /// with every successful response.
        /// </summary>
        public async Task PollAsync(
            Func<AircraftResponse, Task> onData,
            CancellationToken ct = default)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    var data = await GetAircraftAsync(ct);
                    await onData(data);
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested)
                {
                    break;
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"[ERROR] {ex.Message}");
                }

                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(1), ct);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
            }
        }

        public void Dispose() => _http.Dispose();
    }

}