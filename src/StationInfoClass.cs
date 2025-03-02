/*
Copyright 2025 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using System;
using System.Collections.Generic;
using System.Text;

namespace HTCommander
{
    public class StationInfoClass
    {
        public enum StationTypes : int
        {
            Generic = 0,
            APRS = 1,
            Terminal = 2,
            BBS = 3,
            Winlink = 4
        }

        public enum TerminalProtocols : int
        {
            RawX25 = 0,
            APRS = 1,
            RawX25Compress = 2,
            X25Session = 3
        }

        public string Callsign { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public StationTypes StationType { get; set; }
        public string APRSRoute { get; set; }
        public TerminalProtocols TerminalProtocol { get; set; }
        public string Channel { get; set; }
        public string AX25Destination { get; set; }
        public bool WaitForConnection { get; set; }

        public string CallsignNoZero
        {
            get
            {
                if (Callsign.EndsWith("-0")) { return Callsign.Substring(0, Callsign.Length - 2); }
                return Callsign;
            }
        }

        // Serialize a list of stations to a plain text format
        public static string Serialize(List<StationInfoClass> stations)
        {
            StringBuilder sb = new StringBuilder();
            foreach (var station in stations)
            {
                sb.AppendLine("Station:");
                sb.AppendLine($"Callsign={station.Callsign}");
                sb.AppendLine($"Name={station.Name}");
                sb.AppendLine($"Description={station.Description}");
                sb.AppendLine($"StationType={(int)station.StationType}");
                sb.AppendLine($"APRSRoute={station.APRSRoute}");
                sb.AppendLine($"TerminalProtocol={(int)station.TerminalProtocol}");
                sb.AppendLine($"Channel={station.Channel}");
                sb.AppendLine($"AX25Destination={station.AX25Destination}");
                sb.AppendLine(); // Separate entries with a blank line
            }
            return sb.ToString();
        }

        // Deserialize a plain text format into a list of StationInfoClass objects
        public static List<StationInfoClass> Deserialize(string data)
        {
            List<StationInfoClass> stations = new List<StationInfoClass>();
            StationInfoClass currentStation = null;

            string[] lines = data.Split(new[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string line in lines)
            {
                string trimmedLine = line.Trim();
                if (trimmedLine == "Station:")
                {
                    if (currentStation != null) { stations.Add(currentStation); }
                    currentStation = new StationInfoClass();
                }
                else if (currentStation != null)
                {
                    string[] parts = trimmedLine.Split('=');
                    if (parts.Length == 2)
                    {
                        string key = parts[0].Trim();
                        string value = parts[1].Trim();

                        switch (key)
                        {
                            case "Callsign": currentStation.Callsign = value; break;
                            case "Name": currentStation.Name = value; break;
                            case "Description": currentStation.Description = value; break;
                            case "StationType": currentStation.StationType = (StationTypes)int.Parse(value); break;
                            case "APRSRoute": currentStation.APRSRoute = value; break;
                            case "TerminalProtocol": currentStation.TerminalProtocol = (TerminalProtocols)int.Parse(value); break;
                            case "Channel": currentStation.Channel = value; break;
                            case "AX25Destination": currentStation.AX25Destination = value; break;
                        }
                    }
                }
            }

            if (currentStation != null) { stations.Add(currentStation); }

            return stations;
        }
    }
}
