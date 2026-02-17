/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System.Text.Json.Serialization;

namespace HTCommander.Airplanes
{

    /// <summary>
    /// Root JSON object returned by Dump1090's aircraft.json endpoint.
    /// </summary>
    public class AircraftResponse
    {
        /// <summary>Timestamp of the data (seconds since epoch).</summary>
        [JsonPropertyName("now")]
        public double Now { get; set; }

        /// <summary>Number of aircraft with positions.</summary>
        [JsonPropertyName("messages")]
        public long Messages { get; set; }

        /// <summary>Array of tracked aircraft.</summary>
        [JsonPropertyName("aircraft")]
        public Aircraft[] Aircraft { get; set; } = [];
    }

}