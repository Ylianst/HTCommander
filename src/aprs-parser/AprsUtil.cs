using System;
using System.Globalization;
using System.Text.RegularExpressions;
using Microsoft.VisualBasic;

namespace aprsparser
{
    public static class AprsUtil
    {
        public static string AprsValidationCode(string callsign)
        {
            int hash = 0x73e2; //magic number
            string cs = callsign.ToUpper().Trim();
            //get just the callsign no ssid
            var parts = cs.Split('-');
            cs = parts[0];
            int len = cs.Length;
            // in case callsign is odd length add null
            cs += "\0";
            //perform the hash
            int i = 0;
            while ((i < len))
            {
                hash = (cs[i] << 8) ^ hash;
                i += 1;
                hash = (cs[i]) ^ hash;
                i += 1;
            }
            return (hash & 0x7fff).ToString(CultureInfo.InvariantCulture);
        }

        //build string to send to an aprs server for login
        public static string GetServerLogonString(string callsign, string product, string version)
        {
            return "user " + callsign + " pass " + AprsValidationCode(callsign) +
                " vers " + product + " " + version;
        }

        public static string LatLonToGridSquare(double lat, double lon)
        {
            var locator = string.Empty;

            lat += 90;
            lon += 180;
            var v = (int)(lon / 20);
            lon -= v * 20;
            locator += (char)('A' + v);
            v = (int)(lat / 10);
            lat -= v * 10;
            locator += (char)('A' + v);
            locator += ((int)(lon / 2)).ToString(CultureInfo.InvariantCulture);
            locator += ((int)lat).ToString(CultureInfo.InvariantCulture);
            lon -= (int)(lon / 2) * 2;
            lat -= (int)lat;
            locator += (char)('A' + lon * 12);
            locator += (char)('A' + lat * 24);
            return locator;
        }

        public static string LatLonToGridSquare(CoordinateSet coordinateSet)
        {
            return LatLonToGridSquare(coordinateSet.Latitude.Value, coordinateSet.Longitude.Value);
        }

        public static CoordinateSet GridSquareToLatLon(string locator)
        {
            var coordinates = new CoordinateSet();
            locator = locator.ToUpper();
            if (locator.Length == 4)
                locator += "IL"; //somewhere near the center of the grid  
            if (!Regex.IsMatch(locator, "^[A-R]{2}[0-9]{2}[A-X]{2}$"))
                return null;
            coordinates.Longitude.Value = (locator[0] - 'A') * 20 + (locator[2] - '0') * 2 + (locator[4] - 'A' + 0.5) / 12 - 180;
            coordinates.Latitude.Value = (locator[1] - 'A') * 10 + (locator[3] - '0') + (locator[5] - 'A' + 0.5) / 24 - 90;
            return coordinates;
        }

        /// <summary>
        /// Convert to format: DDMM.MMN/S or DDDMM.MME/W
        /// </summary>
        /// <param name="d"></param>
        /// <param name="direction"></param>
        /// <param name="isLat"></param>
        /// <returns></returns>
        private static string ConvertToNmea(double d, string direction, bool isLat)
        {
            //break into degrees and minutes
            double l = Math.Abs(d);
            var degrees = (int)Math.Floor(l);
            double minutes = (l - degrees) * 60;

            //format degrees
            string sD = degrees.ToString(isLat ? "00" : "000");

            //format minutes
            string sM = minutes.ToString("00.00");

            //replace whatever is being used as the decimal seperator with a period
            var ni = new NumberFormatInfo();
            sM = sM.Replace(ni.NumberDecimalSeparator, ".");

            //put it back together - NMEA format
            return sD + sM + direction;
        }

        public static string ConvertLatToNmea(double lat)
        {
            var cd = lat < 0 ? "S" : "N";
            return ConvertToNmea(lat, cd, true);
        }

        public static string ConvertLonToNmea(double lon)
        {
            var cd = lon < 0 ? "W" : "E";
            return ConvertToNmea(lon, cd, false);
        }

        public static Coordinate ConvertNmea(string nmea)
        {
            var c = new Coordinate();
            if (string.IsNullOrEmpty(nmea))
            {
                c.Clear();
            }
            else
            {
                c.Nmea = nmea;
                c.Value = ConvertNmeaToFloat(nmea);
            }
            return c;
        }

        public static double ConvertNmeaToFloat(string nmea)
        {
            try
            {
                if (string.IsNullOrEmpty(nmea)) return 0;
                double d;

                //replace whatever is being used as the decimal separator with a period
                var ni = new NumberFormatInfo();
                nmea = nmea.Replace(ni.NumberDecimalSeparator, ".");

                //lat
                if (nmea.Length == 8) 
                {
                    d = double.Parse(nmea.Substring(0, 2)); //hours
                    d += double.Parse(nmea.Substring(2, 5)) / 60; //decimal minutes

                    //last digit is compass direction
                    if (nmea.EndsWith("S", true, CultureInfo.InvariantCulture))
                        d = -d;
                    return d;
                }

                //lon
                if (nmea.Length == 9) 
                {
                    d = double.Parse(nmea.Substring(0, 3)); //hours
                    d += double.Parse(nmea.Substring(3, 5)) / 60; //decimal minutes

                    //last digit is compass direction
                    if (nmea.EndsWith("W", true, CultureInfo.InvariantCulture))
                        d = -d;
                    return d;
                }

                //error
                return 0;
            }
            catch (Exception)
            {
                return 0;
            }
        }

    }
}
