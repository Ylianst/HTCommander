/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    public class GpsLocation
    {
        public double Latitude { get; }
        public double Longitude { get; }

        public GpsLocation(double latitude, double longitude)
        {
            Latitude = latitude;
            Longitude = longitude;
        }
        
        public byte[] EncodeToGpsBytes()
        {
            byte[] data = new byte[6];
            int latRaw = (int)(Latitude * 30000.0);
            int lonRaw = (int)(Longitude * 30000.0);

            data[0] = (byte)((latRaw >> 16) & 0xFF);
            data[1] = (byte)((latRaw >> 8) & 0xFF);
            data[2] = (byte)(latRaw & 0xFF);

            data[3] = (byte)((lonRaw >> 16) & 0xFF);
            data[4] = (byte)((lonRaw >> 8) & 0xFF);
            data[5] = (byte)(lonRaw & 0xFF);

            return data;
        }

        public override string ToString() => $"{Latitude:F6}, {Longitude:F6}";

        public static GpsLocation DecodeGpsBytes(byte[] data)
        {
            if (data == null || data.Length < 6)
                throw new ArgumentException("Byte array must contain at least 6 bytes.");

            // Pack first 3 bytes into Latitude
            int latRaw = (data[0] << 16) | (data[1] << 8) | data[2];

            // Pack next 3 bytes into Longitude
            int lonRaw = (data[3] << 16) | (data[4] << 8) | data[5];

            return new GpsLocation(
                Apply24BitScaling(latRaw),
                Apply24BitScaling(lonRaw)
            );
        }

        private static double Apply24BitScaling(int val)
        {
            // Sign-extend 24-bit to 32-bit if the 24th bit is set
            if ((val & 0x800000) != 0)
            {
                val |= unchecked((int)0xFF000000);
            }

            // Protocol scaling factor
            return (double)val / 30000.0;
        }
    }    
}
