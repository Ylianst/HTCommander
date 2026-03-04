/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using static HTCommander.Radio;

namespace HTCommander.radio
{
    public class RadioPosition
    {
        public Radio.RadioCommandState Status { get; private set; }
        public int LatitudeRaw { get; private set; }
        public int LongitudeRaw { get; private set; }
        public int Altitude { get; private set; }
        public int Speed { get; private set; }
        public int Heading { get; private set; }
        public int TimeRaw { get; private set; }
        public int Accuracy { get; private set; }

        public string LatitudeStr;
        public string LongitudeStr;
        public double Latitude;
        public double Longitude;
        public DateTime TimeUTC;
        public DateTime Time;
        public DateTime ReceivedTime;
        public bool Locked;

        public bool IsGpsLocked()
        {
            return Locked && (Status == RadioCommandState.SUCCESS) && (ReceivedTime.AddSeconds(10).CompareTo(DateTime.Now) > 0);
        }

        /// <summary>
        /// Creates a RadioPosition from decimal-degree coordinates (e.g. from a GPS receiver).
        /// </summary>
        public RadioPosition(double latitude, double longitude, double altitudeMetres, double speedKnots, double headingDegrees, DateTime utcTime)
        {
            Status = Radio.RadioCommandState.SUCCESS;
            ReceivedTime = DateTime.Now;
            Latitude = latitude;
            Longitude = longitude;
            LatitudeRaw = (int)Math.Round(latitude * 60.0 * 500.0);
            LongitudeRaw = (int)Math.Round(longitude * 60.0 * 500.0);
            LatitudeStr = ConvertLatitudeToDms(LatitudeRaw);
            LongitudeStr = ConvertLatitudeToDms(LongitudeRaw);
            Altitude = (int)Math.Round(altitudeMetres);
            Speed = (int)Math.Round(speedKnots);
            Heading = (int)Math.Round(headingDegrees);
            TimeRaw = (int)(new DateTimeOffset(utcTime).ToUnixTimeSeconds());
            TimeUTC = utcTime;
            Time = utcTime.ToLocalTime();
            Accuracy = 0;
            Locked = true;
        }

        public RadioPosition(byte[] msg)
        {
            Status = (Radio.RadioCommandState)msg[4];
            if (Status == Radio.RadioCommandState.SUCCESS)
            {
                ReceivedTime = DateTime.Now;
                LatitudeRaw = (msg[5] << 16) + (msg[6] << 8) + msg[7];
                LongitudeRaw = (msg[8] << 16) + (msg[9] << 8) + msg[10];
                LatitudeStr = ConvertLatitudeToDms(LatitudeRaw);
                LongitudeStr = ConvertLatitudeToDms(LongitudeRaw);
                Latitude = ConvertLatitude(LatitudeRaw);
                Longitude = ConvertLatitude(LongitudeRaw);
                if (msg.Length > 11)
                {
                    Altitude = (msg[11] << 8) + msg[12];
                    Speed = (msg[13] << 8) + msg[14];
                    Heading = (msg[15] << 8) + msg[16];
                    TimeRaw = (msg[17] << 24) + (msg[18] << 16) + (msg[19] << 8) + msg[20];
                    TimeUTC = UnixTimeStampToDateTime(TimeRaw);
                    Time = UnixTimeStampToLocalDateTime(TimeRaw);
                    Accuracy = (msg[21] << 8) + msg[22];
                }
            }
        }

        private static double ConvertLatitude(int latitudeRaw)
        {
            // Since C# `int` is 32-bit, we need to handle the 24-bit two's complement
            // correctly. If the 24th bit (0x800000) is set, it's a negative number.
            // We can achieve this by sign-extending the 24-bit value to 32 bits.
            // If the 23rd bit (0x00800000, 24th bit from 0) is set, it's negative.
            if ((latitudeRaw & 0x00800000) != 0)
            {
                // Sign-extend from 24 bits to 32 bits
                latitudeRaw |= unchecked((int)0xFF000000);
            }
            else
            {
                // Ensure no higher bits are set if positive
                latitudeRaw &= 0x00FFFFFF;
            }

            return (double)latitudeRaw / 60.0 / 500.0;
        }

        private static string ConvertLatitudeToDms(int latitudeRaw)
        {
            // Since C# `int` is 32-bit, we need to handle the 24-bit two's complement
            // correctly. If the 24th bit (0x800000) is set, it's a negative number.
            // We can achieve this by sign-extending the 24-bit value to 32 bits.
            // If the 23rd bit (0x00800000, 24th bit from 0) is set, it's negative.
            if ((latitudeRaw & 0x00800000) != 0)
            {
                // Sign-extend from 24 bits to 32 bits
                latitudeRaw |= unchecked((int)0xFF000000);
            }
            else
            {
                // Ensure no higher bits are set if positive
                latitudeRaw &= 0x00FFFFFF;
            }

            double degreesDecimal = (double)latitudeRaw / 60.0 / 500.0;

            // Determine the cardinal direction
            char direction = ' ';
            if (degreesDecimal >= 0)
            {
                direction = 'N';
            }
            else
            {
                direction = 'S';
                degreesDecimal = Math.Abs(degreesDecimal); // Work with positive value for calculation
            }

            int degrees = (int)Math.Floor(degreesDecimal);
            double minutesDecimal = (degreesDecimal - degrees) * 60;
            int minutes = (int)Math.Floor(minutesDecimal);
            double seconds = (minutesDecimal - minutes) * 60;

            // Format the seconds to two decimal places
            return $"{degrees}° {minutes}' {seconds:F2}\" {direction}";
        }

        public static DateTime UnixTimeStampToDateTime(long unixTimestamp)
        {
            // Unix epoch (January 1, 1970, 00:00:00 UTC)
            DateTimeOffset dateTimeOffset = DateTimeOffset.FromUnixTimeSeconds(unixTimestamp);

            // To get a DateTime object in UTC:
            return dateTimeOffset.UtcDateTime;
        }

        public static DateTime UnixTimeStampToLocalDateTime(long unixTimestamp)
        {
            // Unix epoch (January 1, 1970, 00:00:00 UTC)
            DateTimeOffset dateTimeOffset = DateTimeOffset.FromUnixTimeSeconds(unixTimestamp);

            // Local time, considering the machine's time zone:
            return dateTimeOffset.LocalDateTime;
        }

        /// <summary>
        /// Serializes the position into the 18-byte payload expected by the SET_POSITION command.
        /// The layout mirrors bytes [5..22] of the GET_POSITION response.
        /// </summary>
        public byte[] ToByteArray()
        {
            return new byte[]
            {
                (byte)((LatitudeRaw  >> 16) & 0xFF),
                (byte)((LatitudeRaw  >>  8) & 0xFF),
                (byte)( LatitudeRaw         & 0xFF),
                (byte)((LongitudeRaw >> 16) & 0xFF),
                (byte)((LongitudeRaw >>  8) & 0xFF),
                (byte)( LongitudeRaw        & 0xFF),
                (byte)((Altitude     >>  8) & 0xFF),
                (byte)( Altitude            & 0xFF),
                (byte)((Speed        >>  8) & 0xFF),
                (byte)( Speed               & 0xFF),
                (byte)((Heading      >>  8) & 0xFF),
                (byte)( Heading             & 0xFF),
                (byte)((TimeRaw      >> 24) & 0xFF),
                (byte)((TimeRaw      >> 16) & 0xFF),
                (byte)((TimeRaw      >>  8) & 0xFF),
                (byte)( TimeRaw             & 0xFF),
                (byte)((Accuracy     >>  8) & 0xFF),
                (byte)( Accuracy            & 0xFF)
            };
        }

    }
}
