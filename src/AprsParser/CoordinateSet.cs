namespace aprsparser
{
    public class Coordinate
    {
        public double Value;
        public string Nmea;

        public Coordinate()
        {
            Clear();
        }

        public Coordinate(double value, bool isLat)
        {
            Value = value;
            Nmea = isLat ? AprsUtil.ConvertLatToNmea(value) : AprsUtil.ConvertLonToNmea(value);
        }

        public Coordinate(string nmea)
        {
            if (string.IsNullOrEmpty(nmea))
            {
                Clear();
            }
            else
            {
                Nmea = nmea.Trim();
                Value = AprsUtil.ConvertNmeaToFloat(nmea);
            }
        }

        public void Clear()
        {
            Value = 0;
            Nmea = string.Empty;
        }
    }

    public class CoordinateSet
    {
        public Coordinate Latitude;
        public Coordinate Longitude;

        public CoordinateSet()
        {
            Latitude = new Coordinate();
            Longitude = new Coordinate();
        }

        public CoordinateSet(double lat, double lon)
        {
            Latitude = new Coordinate(lat, true);
            Longitude = new Coordinate(lon, false);
        }

        public void Clear()
        {
            Latitude.Clear();
            Longitude.Clear();
        }

        //0 0 indicates an invalid position
        public bool IsValid()
        {
            bool valid;
            // ReSharper disable CompareOfFloatsByEqualityOperator
            if (0 == Latitude.Value && 0 == Longitude.Value)
                valid = false;
            else
                valid = true;
            // ReSharper restore CompareOfFloatsByEqualityOperator
            return valid;
        }
    }
}
