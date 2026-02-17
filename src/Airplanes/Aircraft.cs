/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System.Text.Json.Serialization;

namespace HTCommander.Airplanes
{

    /// <summary>
    /// Represents a single aircraft as reported by Dump1090.
    /// </summary>
    public class Aircraft
    {
        /// <summary>ICAO 24-bit hex identifier.</summary>
        [JsonPropertyName("hex")]
        public string? Hex { get; set; }

        /// <summary>Callsign / flight number.</summary>
        [JsonPropertyName("flight")]
        public string? Flight { get; set; }

        /// <summary>Latitude in degrees.</summary>
        [JsonPropertyName("lat")]
        public double? Latitude { get; set; }

        /// <summary>Longitude in degrees.</summary>
        [JsonPropertyName("lon")]
        public double? Longitude { get; set; }

        /// <summary>Altitude in feet (barometric).</summary>
        [JsonPropertyName("altitude")]
        public object? Altitude { get; set; }

        /// <summary>Altitude (geometric / GNSS) in feet.</summary>
        [JsonPropertyName("alt_geom")]
        public int? AltitudeGeometric { get; set; }

        /// <summary>Barometric altitude in feet (alt_baro field used by some builds).</summary>
        [JsonPropertyName("alt_baro")]
        public object? AltitudeBaro { get; set; }

        /// <summary>Ground speed in knots.</summary>
        [JsonPropertyName("speed")]
        public double? Speed { get; set; }

        /// <summary>Ground speed in knots (gs field used by some builds).</summary>
        [JsonPropertyName("gs")]
        public double? GroundSpeed { get; set; }

        /// <summary>Track angle in degrees (0 = north).</summary>
        [JsonPropertyName("track")]
        public double? Track { get; set; }

        /// <summary>Squawk transponder code.</summary>
        [JsonPropertyName("squawk")]
        public string? Squawk { get; set; }

        /// <summary>Vertical rate in feet/minute.</summary>
        [JsonPropertyName("vert_rate")]
        public int? VerticalRate { get; set; }

        /// <summary>Barometric vertical rate in feet/minute.</summary>
        [JsonPropertyName("baro_rate")]
        public int? BaroRate { get; set; }

        /// <summary>Number of messages received for this aircraft.</summary>
        [JsonPropertyName("messages")]
        public int? Messages { get; set; }

        /// <summary>Seconds since last message was received.</summary>
        [JsonPropertyName("seen")]
        public double? Seen { get; set; }

        /// <summary>Seconds since last position update.</summary>
        [JsonPropertyName("seen_pos")]
        public double? SeenPos { get; set; }

        /// <summary>Received signal strength in dBFS.</summary>
        [JsonPropertyName("rssi")]
        public double? Rssi { get; set; }

        /// <summary>Aircraft category (A0-D7).</summary>
        [JsonPropertyName("category")]
        public string? Category { get; set; }

        /// <summary>Navigation integrity category.</summary>
        [JsonPropertyName("nic")]
        public int? Nic { get; set; }

        /// <summary>Navigation accuracy for position.</summary>
        [JsonPropertyName("nac_p")]
        public int? NacP { get; set; }

        /// <summary>Navigation accuracy for velocity.</summary>
        [JsonPropertyName("nac_v")]
        public int? NacV { get; set; }

        /// <summary>Source integrity level.</summary>
        [JsonPropertyName("sil")]
        public int? Sil { get; set; }

        /// <summary>Emergency/priority status.</summary>
        [JsonPropertyName("emergency")]
        public string? Emergency { get; set; }

        // ── Convenience helpers ──────────────────────────────────────

        /// <summary>Returns the best available altitude value.</summary>
        public string GetAltitudeDisplay()
        {
            if (AltitudeBaro is not null)
                return AltitudeBaro.ToString()!;
            if (Altitude is not null)
                return Altitude.ToString()!;
            if (AltitudeGeometric is not null)
                return AltitudeGeometric.Value.ToString();
            return "—";
        }

        /// <summary>Returns the best available speed value.</summary>
        public double? GetSpeed() => GroundSpeed ?? Speed;

        /// <summary>Returns the best available vertical rate.</summary>
        public int? GetVerticalRate() => BaroRate ?? VerticalRate;
    }

}