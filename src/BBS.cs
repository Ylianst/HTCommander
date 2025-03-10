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
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Windows.Forms;
using System.Collections.Generic;
using aprsparser;
using HTCommander.radio;

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
                string[] dataStrs = output.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                foreach (string str in dataStrs)
                {
                    if (str.Length == 0) continue;
                    parent.AddBbsTraffic(session.Addresses[0].ToString(), true, str.Trim());
                }
                UpdateStats(session.Addresses[0].ToString(), "Stream", 0, 1, 0, output.Length);
                session.Send(output);
            }
        }

        private string GetVersion()
        {
            // Get the path of the currently running executable
            string exePath = System.Windows.Forms.Application.ExecutablePath;

            // Get the FileVersionInfo for the executable
            FileVersionInfo versionInfo = FileVersionInfo.GetVersionInfo(exePath);

            // Return the FileVersion as a string
            string[] vers = versionInfo.FileVersion.Split('.');
            return vers[0] + "." + vers[1];
        }

        public void ProcessStreamState(AX25Session session, AX25Session.ConnectionState state)
        {
            switch (state)
            {
                case AX25Session.ConnectionState.CONNECTED:
                    parent.AddBbsControlMessage("Connected to " + session.Addresses[0].ToString());
                    session.sessionState["wlChallenge"] = WinlinkSecurity.GenerateChallenge();

                    StringBuilder sb = new StringBuilder();
                    sb.Append("Handy-Talky Commander BBS\r");
                    sb.Append("[HTCmd-" + GetVersion() + "-B2FWIHJM$]\r");
                    if (!string.IsNullOrEmpty(parent.winlinkPassword)) { sb.Append(";PQ: " + session.sessionState["wlChallenge"] + "\r"); }
                    //sb.Append("CMS via " + parent.callsign + " >\r");
                    sb.Append(">\r");
                    SessionSend(session, sb.ToString());
                    break;
                case AX25Session.ConnectionState.DISCONNECTED:
                    parent.AddBbsControlMessage("Disconnected");
                    break;
                case AX25Session.ConnectionState.CONNECTING:
                    parent.AddBbsControlMessage("Connecting...");
                    break;
                case AX25Session.ConnectionState.DISCONNECTING:
                    parent.AddBbsControlMessage("Disconnecting...");
                    break;
            }

            /*
            Adventurer.GameRunner runner = new Adventurer.GameRunner();
            string output = runner.RunTurn("adv01.dat", session.Addresses[0].CallSignWithId + ".sav", "").Replace("\r\n\r\n", "\r\n").Trim();
            SessionSend(session, output);
            */
        }

        private bool ExtractMail(AX25Session session, MemoryStream blocks)
        {
            if (session.sessionState.ContainsKey("wlMailProp") == false) return false;
            List<string> proposals = (List<string>)session.sessionState["wlMailProp"];
            if ((proposals == null) || (blocks == null)) return false;
            if ((proposals.Count == 0) || (blocks.Length == 0)) return true;

            // Decode the proposal
            string[] proposalSplit = proposals[0].Split(' ');
            string MID = proposalSplit[1];
            int mFullLen, mCompLen;
            int.TryParse(proposalSplit[2], out mFullLen);
            int.TryParse(proposalSplit[3], out mCompLen);

            // See what we got
            bool fail;
            int dataConsumed = 0;
            WinLinkMail mail = WinLinkMail.DecodeBlocksToEmail(blocks.ToArray(), out fail, out dataConsumed);
            if (fail) { parent.AddBbsControlMessage("Failed to decode mail."); return true; }
            if (mail == null) return false;
            if (dataConsumed > 0)
            {
                if (dataConsumed >= blocks.Length)
                {
                    blocks.SetLength(0);
                }
                else
                {
                    byte[] newBlocks = new byte[blocks.Length - dataConsumed];
                    Array.Copy(blocks.ToArray(), dataConsumed, newBlocks, 0, newBlocks.Length);
                    blocks.SetLength(0);
                    blocks.Write(newBlocks, 0, newBlocks.Length);
                }
            }
            proposals.RemoveAt(0);

            // Process the mail
            parent.Mails.Add(mail);
            parent.SaveMails();
            parent.UpdateMail();
            parent.AddBbsControlMessage("Got mail for " + mail.To + ".");

            return (proposals.Count == 0);
        }
        private bool WeHaveEmail(string mid)
        {
            foreach (WinLinkMail mail in parent.Mails) { if (mail.MID == mid) return true; }
            return false;
        }

        public void ProcessStream(AX25Session session, byte[] data)
        {
            if ((data == null) || (data.Length == 0)) return;
            UpdateStats(session.Addresses[0].ToString(), "Stream", 1, 0, data.Length, 0);

            // This is embedded mail sent in compressed format
            if (session.sessionState.ContainsKey("wlMailBinary"))
            {
                parent.AddBbsControlMessage("Received binary traffic, " + data.Length + ((data.Length < 2) ? " byte" : " bytes"), 1);
                MemoryStream blocks = (MemoryStream)session.sessionState["wlMailBinary"];
                blocks.Write(data, 0, data.Length);
                //List<byte[]> blocks;
                //if (session.sessionState.ContainsKey("wlMailBlocks")) { blocks = (List<byte[]>)session.sessionState["wlMailBlocks"]; } else { blocks = new List<byte[]>(); }
                //blocks.Add(data);
                //session.sessionState["wlMailBlocks"] = blocks;
                if (ExtractMail(session, blocks) == true)
                {
                    // We are done with the mail reception
                    session.sessionState.Remove("wlMailBinary");
                    session.sessionState.Remove("wlMailBlocks");
                    session.sessionState.Remove("wlMailProp");
                    SessionSend(session, "FF\r");
                }
                return;
            }

            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            foreach (string str in dataStrs)
            {
                if (str.Length == 0) continue;
                parent.AddBbsTraffic(session.Addresses[0].ToString(), false, str.Trim());
                string key = str, value = "";
                int i = str.IndexOf(' ');
                if (i > 0) { key = str.Substring(0, i).ToUpper(); value = str.Substring(i + 1); }

                if ((key == ";PR:") && (!string.IsNullOrEmpty(parent.winlinkPassword)))
                {   // Winlink Authentication Response
                    if (WinlinkSecurity.SecureLoginResponse((string)(session.sessionState["wlChallenge"]), parent.winlinkPassword) == value)
                    {
                        session.sessionState["wlAuth"] = "OK";
                        parent.AddBbsControlMessage("Authentication Success");
                        parent.DebugTrace("Winlink Auth Success");
                    }
                    else
                    {
                        parent.AddBbsControlMessage("Authentication Failed");
                        parent.DebugTrace("Winlink Auth Failed");
                    }
                }
                else if (key == "FC")
                {   // Winlink Mail Proposal
                    List<string> proposals;
                    if (session.sessionState.ContainsKey("wlMailProp")) { proposals = (List<string>)session.sessionState["wlMailProp"]; } else { proposals = new List<string>(); }
                    proposals.Add(value);
                    session.sessionState["wlMailProp"] = proposals;
                }
                else if (key == "F>")
                {
                    // Winlink Mail Proposals completed, we need to respond
                    if ((session.sessionState.ContainsKey("wlMailProp")) && (!session.sessionState.ContainsKey("wlMailBinary")))
                    {
                        List<string> proposals = (List<string>)session.sessionState["wlMailProp"];
                        List<string> proposals2 = new List<string>();
                        if ((proposals != null) && (proposals.Count > 0))
                        {
                            // Compute the proposal checksum
                            int checksum = 0;
                            foreach (string proposal in proposals)
                            {
                                byte[] proposalBin = ASCIIEncoding.ASCII.GetBytes("FC " + proposal + "\r");
                                for (int j = 0; j < proposalBin.Length; j++) { checksum += proposalBin[j]; }
                            }
                            checksum = (-checksum) & 0xFF;
                            if (checksum.ToString("X2") == value)
                            {
                                // Build a response
                                string response = "";
                                int acceptedProposalCount = 0;
                                foreach (string proposal in proposals)
                                {
                                    string[] proposalSplit = proposal.Split(' ');
                                    if ((proposalSplit.Length >= 5) && (proposalSplit[0] == "EM") && (proposalSplit[1].Length == 12))
                                    {
                                        int mFullLen, mCompLen, mUnknown;
                                        if (
                                            int.TryParse(proposalSplit[2], out mFullLen) &&
                                            int.TryParse(proposalSplit[3], out mCompLen) &&
                                            int.TryParse(proposalSplit[4], out mUnknown)
                                        )
                                        {
                                            // Check if we already have this email
                                            if (WeHaveEmail(proposalSplit[1]))
                                            {
                                                response += "N";
                                            }
                                            else
                                            {
                                                response += "Y";
                                                proposals2.Add(proposal);
                                                acceptedProposalCount++;
                                            }
                                        }
                                        else { response += "H"; }
                                    }
                                    else { response += "H"; }
                                }
                                SessionSend(session, "FS " + response + "\r");
                                if (acceptedProposalCount > 0)
                                {
                                    session.sessionState["wlMailBinary"] = new MemoryStream();
                                    session.sessionState["wlMailProp"] = proposals2;
                                }
                            }
                            else
                            {
                                // Checksum failed
                                parent.AddBbsControlMessage("Checksum Failed");
                                session.Disconnect();
                            }
                        }
                    }
                }
                else if (key == "FQ")
                {   // Winlink Session Close
                    session.Disconnect();
                }
                else if (key == "ECHO")
                {   // Test Echo command
                    SessionSend(session, value + "\r");
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
