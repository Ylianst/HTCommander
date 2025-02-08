using System;
using System.Text;
using System.Windows.Forms;
using System.Collections.Generic;
using aprsparser;

namespace HTCommander
{
    public class BBS
    {
        private MainForm parent;
        public Dictionary<string, StationStats> stats = new Dictionary<string, StationStats>();

        public class StationStats
        {
            public string callsign;
            public DateTime lastseen;
            public string protocol;
            public int packetsIn = 0;
            public int packetsOut = 0;
            public int bytesIn = 0;
            public int bytesOut = 0;
            public ListViewItem listViewItem = null;
        }

        public BBS(MainForm parent)
        {
            this.parent = parent;
        }

        private void UpdateStats(string callsign, string protocol, int packetIn, int packetOut, int bytesIn, int bytesOut)
        {
            StationStats s;
            if (stats.ContainsKey(callsign)) { s = stats[callsign]; } else { s = new StationStats(); }
            s.callsign = callsign;
            s.lastseen = DateTime.Now;
            s.protocol = protocol;
            s.packetsIn += packetIn;
            s.packetsOut += packetOut;
            s.bytesIn += bytesIn;
            s.bytesOut += bytesOut;
            stats[callsign] = s;
            parent.UpdateBbsStats(s);
        }

        public void ClearStats()
        {
            stats.Clear();
        }

        public void ProcessFrame(TncDataFragment frame)
        {
            AX25Packet p = AX25Packet.DecodeAX25Packet(frame.data, frame.time);
            if (p == null) { return; }

            // TODO: Add support for the weird packet format
            // TODO: Add support for ignoring stations
            if (p.addresses[0].CallSignWithId != parent.callsign + "-" + parent.stationId) return;

            parent.addBbsTraffic(p.addresses[1].ToString(), false, p.dataStr);
            AdventurerDOS.GameRunner runner = new AdventurerDOS.GameRunner();
            string output = runner.RunTurn("adv01.dat", p.addresses[1].CallSignWithId + ".sav", p.dataStr).Replace("\r\n\r\n", "\r\n").Trim();
            if ((output != null) && (output.Length > 0))
            {
                parent.addBbsTraffic(p.addresses[1].ToString(), true, output);
                //if (output.Length > 310) { output = output.Substring(0, 310); }
                List<string> stringList = new List<string>();
                StringBuilder sb = new StringBuilder();
                string[] outputSplit = output.Replace("\r\n", "\n").Replace("\n\n", "\n").Split('\n');
                foreach (string s in outputSplit)
                {
                    if ((sb.Length + s.Length) < 310)
                    {
                        if (sb.Length > 0) { sb.Append("\n"); }
                        sb.Append(s);
                    }
                    else
                    {
                        stringList.Add(sb.ToString());
                        sb.Clear();
                        sb.Append(s);
                    }
                }
                if (sb.Length > 0) { stringList.Add(sb.ToString()); }

                // Raw AX.25 format
                //terminalTextBox.AppendText(destCallsign + "-" + destStationId + "< " + sendText + Environment.NewLine);
                //AppendTerminalString(true, callsign + "-" + stationId, destCallsign + "-" + destStationId, sendText);
                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(p.addresses[1]);
                addresses.Add(AX25Address.GetAddress(parent.callsign, parent.stationId));

                int bytesOut = 0;
                int packetsOut = 0;
                for (int i = 0; i < stringList.Count; i++)
                {
                    AX25Packet packet = new AX25Packet(addresses, stringList[i], DateTime.Now);
                    bytesOut += parent.radio.TransmitTncData(packet, parent.activeChannelIdLock);
                    packetsOut++;
                }

                UpdateStats(p.addresses[1].ToString(), "AX.25 RAW", 1, packetsOut, frame.data.Length, bytesOut);
            }
        }
    }
}
