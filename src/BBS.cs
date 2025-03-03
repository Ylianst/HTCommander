using System;
using System.Text;
using System.Windows.Forms;
using System.Collections.Generic;
using aprsparser;
using System.Security.Cryptography;
using static System.Net.Mime.MediaTypeNames;
using HTCommander.radio;
using static System.Collections.Specialized.BitVector32;

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

        private void SessionSend(AX25Session session, string output)
        {
            if (!string.IsNullOrEmpty(output))
            {
                parent.AddBbsTraffic(session.Addresses[0].ToString(), true, output);
                session.Send(output);
            }
        }

        public void ProcessStreamState(AX25Session session, AX25Session.ConnectionState state)
        {
            if (state == AX25Session.ConnectionState.CONNECTED)
            {
                session.sessionState["wlChallenge"] = WinlinkSecurity.GenerateChallenge();
                SessionSend(session, "Welcome to the Handy-Talky Commander BBS by " + parent.callsign + ".");
                SessionSend(session, "[WL2K-5.0-B2FWIHJM$]");
                if (!string.IsNullOrEmpty(parent.winlinkPassword)) { SessionSend(session, ";PQ: " + session.sessionState["wlChallenge"]); }
                SessionSend(session, "CMS via " + parent.callsign + " >");

                /*
                Adventurer.GameRunner runner = new Adventurer.GameRunner();
                string output = runner.RunTurn("adv01.dat", session.Addresses[0].CallSignWithId + ".sav", "").Replace("\r\n\r\n", "\r\n").Trim();
                SessionSend(session, output);
                */
            }
        }

        public void ProcessStream(AX25Session session, byte[] data)
        {
            string dataStr = UTF8Encoding.UTF8.GetString(data);
            parent.AddBbsTraffic(session.Addresses[0].ToString(), false, dataStr);

            int i = dataStr.IndexOf(' ');
            if (i > 0)
            {
                string key = dataStr.Substring(0, i).ToUpper();
                string value = dataStr.Substring(i + 1);
                if ((key == ";PR:") && (!string.IsNullOrEmpty(parent.winlinkPassword)))
                {
                    if (WinlinkSecurity.SecureLoginResponse(session.sessionState["wlChallenge"], parent.winlinkPassword) == value)
                    {
                        session.sessionState["wlAuth"] = "OK";
                        parent.DebugTrace("Winlink Auth Success");
                    }
                    else
                    {
                        parent.DebugTrace("Winlink Auth Failed");
                    }
                }
            }


            /*
            string dataStr = UTF8Encoding.UTF8.GetString(data);
            parent.AddBbsTraffic(session.Addresses[0].ToString(), false, dataStr);
            Adventurer.GameRunner runner = new Adventurer.GameRunner();
            string output = runner.RunTurn("adv01.dat", session.Addresses[0].CallSignWithId + ".sav", dataStr).Replace("\r\n\r\n", "\r\n").Trim();
            if ((output != null) && (output.Length > 0))
            {
                parent.AddBbsTraffic(session.Addresses[0].ToString(), true, output);
                byte[] bytesOut = UTF8Encoding.UTF8.GetBytes(output);
                session.Send(bytesOut);
                UpdateStats(session.Addresses[0].ToString(), "Stream", 1, 1, data.Length, bytesOut.Length);
            }
            */
        }

        public void ProcessFrame(TncDataFragment frame, AX25Packet p)
        {
            // TODO: Add support for the weird packet format
            // TODO: Add support for ignoring stations

            // If the packet is directly addressed to us in the AX.25 frame, process it as a raw frame.
            if ((frame.channel_name != "APRS") && (p.addresses[0].CallSignWithId == parent.callsign + "-" + parent.stationId)) { ProcessRawFrame(p, frame.data.Length); return; }

            // If the packet can be processed as a APRS message directed to use, process as APRS
            AprsPacket aprsPacket = AprsPacket.Parse(p);
            if ((aprsPacket == null) || (parent.aprsStack.ProcessIncoming(aprsPacket) == false)) return;
            if ((aprsPacket.MessageData.Addressee == parent.callsign + "-" + parent.stationId) || (aprsPacket.MessageData.Addressee == parent.callsign)) // Check if this packet is for us
            {
                if (aprsPacket.DataType == PacketDataType.Message) { ProcessAprsPacket(p, aprsPacket, frame.data.Length, frame.channel_name == "APRS"); return; }
            }
        }

        private int GetCompressedLength(byte pid, string s)
        {
            byte[] r1 = UTF8Encoding.UTF8.GetBytes(s);
            if ((pid == 241) || (pid == 242) || (pid == 243))
            {
                byte[] r2 = Utils.CompressBrotli(r1);
                byte[] r3 = Utils.CompressDeflate(r1);
                return Math.Min(r1.Length, Math.Min(r2.Length, r3.Length));
            }
            return r1.Length;
        }

        private byte[] GetCompressed(byte pid, string s, out byte outpid)
        {
            byte[] r1 = UTF8Encoding.UTF8.GetBytes(s);
            if ((pid == 241) || (pid == 242) || (pid == 243))
            {
                byte[] r2 = Utils.CompressBrotli(r1);
                byte[] r3 = Utils.CompressDeflate(r1);
                if ((r1.Length <= r2.Length) && (r1.Length <= r3.Length)) { outpid = 241; return r1; } // No compression
                if (r2.Length <= r3.Length) { outpid = 242; return r2; } // Brotli compression
                outpid = 243; // Deflate compression
                return r3;
            }
            outpid = 240; // Compression not supported
            return r1;
        }

        private void ProcessRawFrame(AX25Packet p, int frameLength)
        {
            string dataStr = p.dataStr;
            if (p.pid == 242) { try { dataStr = UTF8Encoding.Default.GetString(Utils.DecompressBrotli(p.data)); } catch (Exception) { } }
            if (p.pid == 243) { try { dataStr = UTF8Encoding.Default.GetString(Utils.CompressDeflate(p.data)); } catch (Exception) { } }
            parent.AddBbsTraffic(p.addresses[1].ToString(), false, dataStr);
            Adventurer.GameRunner runner = new Adventurer.GameRunner();
            string output = runner.RunTurn("adv01.dat", p.addresses[1].CallSignWithId + ".sav", p.dataStr).Replace("\r\n\r\n", "\r\n").Trim();
            if ((output != null) && (output.Length > 0))
            {
                parent.AddBbsTraffic(p.addresses[1].ToString(), true, output);
                //if (output.Length > 310) { output = output.Substring(0, 310); }
                List<string> stringList = new List<string>();
                StringBuilder sb = new StringBuilder();
                string[] outputSplit = output.Replace("\r\n", "\n").Replace("\n\n", "\n").Split('\n');
                foreach (string s in outputSplit)
                {
                    if (GetCompressedLength(p.pid, sb + s) < 310)
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
                byte outPid = 0;
                for (int i = 0; i < stringList.Count; i++)
                {
                    AX25Packet packet = new AX25Packet(addresses, GetCompressed(p.pid, stringList[i], out outPid), DateTime.Now);
                    packet.pid = outPid;
                    packet.channel_id = p.channel_id;
                    packet.channel_name = p.channel_name;
                    bytesOut += parent.radio.TransmitTncData(packet, packet.channel_id);
                    packetsOut++;
                }

                if ((p.pid == 241) || (p.pid == 242) || (p.pid == 243))
                {
                    UpdateStats(p.addresses[1].ToString(), "AX.25 Compress", 1, packetsOut, frameLength, bytesOut);
                }
                else
                {
                    UpdateStats(p.addresses[1].ToString(), "AX.25 RAW", 1, packetsOut, frameLength, bytesOut);
                }
            }
        }

        private void ProcessAprsPacket(AX25Packet p, AprsPacket aprsPacket, int frameLength, bool aprsChannel)
        {
            if (aprsPacket.DataType != PacketDataType.Message) return;
            if (aprsPacket.MessageData.MsgType != MessageType.mtGeneral) return;

            parent.AddBbsTraffic(p.addresses[1].ToString(), false, aprsPacket.MessageData.MsgText);
            Adventurer.GameRunner runner = new Adventurer.GameRunner();
            string output = runner.RunTurn("adv01.dat", p.addresses[1].CallSignWithId + ".sav", aprsPacket.MessageData.MsgText).Replace("\r\n\r\n", "\r\n").Trim();
            if ((output != null) && (output.Length > 0))
            {
                // Replace characters that are not allowed in APRS messages
                output = output.Replace("\r\n", "\n").Replace("\n\n", "\n").Replace("~", "-").Replace("|", "!").Replace("{", "[").Replace("}", "]");
                parent.AddBbsTraffic(p.addresses[1].ToString(), true, output);

                //if (output.Length > 310) { output = output.Substring(0, 310); }
                List<string> stringList = new List<string>();
                StringBuilder sb = new StringBuilder();
                string[] outputSplit = output.Split('\n');

                foreach (string s in outputSplit)
                {
                    if ((sb.Length + s.Length) < 200)
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

                // APRS format
                //terminalTextBox.AppendText(destCallsign + "-" + destStationId + "< " + sendText + Environment.NewLine);
                //AppendTerminalString(true, callsign + "-" + stationId, destCallsign + "-" + destStationId, sendText);
                List<AX25Address> addresses = new List<AX25Address>(2);
                addresses.Add(p.addresses[0]);
                addresses.Add(AX25Address.GetAddress(parent.callsign, parent.stationId));

                int bytesOut = 0;
                int packetsOut = 0;
                for (int i = 0; i < stringList.Count; i++)
                {
                    // APRS format
                    string aprsAddr = ":" + p.addresses[1].address;
                    if (p.addresses[1].SSID > 0) { aprsAddr += "-" + p.addresses[1].SSID; }
                    while (aprsAddr.Length < 10) { aprsAddr += " "; }
                    aprsAddr += ":";

                    int msgId = parent.GetNextAprsMessageId();
                    AX25Packet packet = new AX25Packet(addresses, aprsAddr + stringList[i] + "{" + msgId, DateTime.Now);
                    packet.messageId = msgId;
                    packet.channel_id = p.channel_id;
                    packet.channel_name = p.channel_name;
                    bytesOut += parent.aprsStack.ProcessOutgoing(packet);
                    packetsOut++;

                    // If the BBS channel is the APRS channel, add the packet to the APRS tab
                    if (aprsChannel) { parent.AddAprsPacket(packet, true); }
                }

                UpdateStats(p.addresses[1].ToString(), "APRS", 1, packetsOut, frameLength, bytesOut);
            }
        }
    }
}
