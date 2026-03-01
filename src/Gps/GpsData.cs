/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander.Gps
{
    /// <summary>
    /// Represents a decoded GPS position fix, combining data from NMEA sentences
    /// (RMC and GGA). Dispatched on the Data Broker as device 1, key "GpsData".
    /// </summary>
    public class GpsData
    {
        /// <summary>Latitude in decimal degrees. Negative values indicate South.</summary>
        public double Latitude { get; set; }

        /// <summary>Longitude in decimal degrees. Negative values indicate West.</summary>
        public double Longitude { get; set; }

        /// <summary>Altitude above mean sea level in metres (from GGA).</summary>
        public double Altitude { get; set; }

        /// <summary>Speed over ground in knots (from RMC).</summary>
        public double Speed { get; set; }

        /// <summary>Track angle / heading in degrees true (from RMC).</summary>
        public double Heading { get; set; }

        /// <summary>
        /// GPS fix quality indicator from GGA sentence.
        /// 0 = invalid, 1 = GPS fix, 2 = DGPS fix.
        /// </summary>
        public int FixQuality { get; set; }

        /// <summary>Number of satellites in use (from GGA).</summary>
        public int Satellites { get; set; }

        /// <summary>
        /// True when the RMC sentence status field is 'A' (active / valid fix).
        /// </summary>
        public bool IsFixed { get; set; }

        /// <summary>UTC date and time of the fix (from RMC).</summary>
        public System.DateTime GpsTime { get; set; }
    }
}