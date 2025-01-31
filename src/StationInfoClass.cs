using System.Collections.Generic;
using System.Text.Json;

namespace HTCommander
{
    public class StationInfoClass
    {
        public enum StationTypes : int
        {
            Generic = 0,
            APRS = 1,
            Terminal = 2
        }

        public enum TerminalProtocols : int
        {
            RawX25 = 0,
            APRS = 1
        }

        public string Callsign { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public StationTypes StationType { get; set; }
        public string APRSRoute { get; set; }
        public TerminalProtocols TerminalProtocol { get; set; }
        public string Channel { get; set; }
        public string AX25Destination { get; set; }

        public string CallsignNoZero {
            get
            {
                if (Callsign.EndsWith("-0")) { return Callsign.Substring(0, Callsign.Length - 2); }
                return Callsign;
            }
        }

        // Serialize the list to JSON
        public static string Serialize(List<StationInfoClass> stations)
        {
            var options = new JsonSerializerOptions
            {
                WriteIndented = true // For pretty printing
            };
            return JsonSerializer.Serialize(stations, options);
        }

        // Deserialize JSON to a list
        public static List<StationInfoClass> Deserialize(string json)
        {
            try
            {
                return JsonSerializer.Deserialize<List<StationInfoClass>>(json);
            }
            catch { }
            return null;
        }
    }
}
