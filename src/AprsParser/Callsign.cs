namespace aprsparser
{
    public class Callsign
    {
        public string StationCallsign; //callsign plus ssid
        public string BaseCallsign;
        public byte Ssid;

        public Callsign(string callsign)
        {
            StationCallsign = callsign.ToUpper().Trim();
            if (StationCallsign.Contains("-"))
            {
                var parts = StationCallsign.Split('-');
                BaseCallsign = parts[0].ToUpper();
                if (!byte.TryParse(parts[1], out Ssid))
                {
                    //not a valid ssid - must be something else
                    BaseCallsign = StationCallsign;
                    Ssid = 0;
                }
            }
            else
            {
                BaseCallsign = StationCallsign;
            }
        }

        public static Callsign ParseCallsign(string callsign)
        {
            return new Callsign(callsign);
        }

    }


}
