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
        readonly private MainForm parent;
        readonly private string adventureAppDataPath;
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

            // Get application data path
            adventureAppDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", "Adventure");
            // Create the application data path if it does not exist
            if (!Directory.Exists(adventureAppDataPath)) { try { Directory.CreateDirectory(adventureAppDataPath); } catch (Exception) { } }
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
                for (int i = 0; i < dataStrs.Length; i++)
                {
                    if ((dataStrs[i].Trim().Length == 0) && (i == (dataStrs.Length - 1))) continue;
                    parent.AddBbsTraffic(session.Addresses[0].ToString(), true, dataStrs[i].Trim());
                }
                UpdateStats(session.Addresses[0].ToString(), "Stream", 0, 1, 0, output.Length);
                session.Send(output);
            }
        }

        private string GetVersion()
        {
            // Get the path of the currently running executable
            string exePath = Application.ExecutablePath;

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
                    sb.Append("Handy-Talky Commander BBS\r[M] for menu\r");
                    //sb.Append("[HTCmd-" + GetVersion() + "-B2FWIHJM$]\r");
                    sb.Append("[WL2K-5.0-B2FWIHJM$]\r");
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

            // Check if the mail is for us
            bool others = false;
            bool response = WinLinkMail.IsMailForStation(parent.callsign, mail.To, mail.Cc, out others);
            if (response == false) { mail.Mailbox = "Outbox"; }

            // TODO: If others is true, we need to keep the email on the outbox for others to get.
            // So, we need to duplicate the email.

            // Process the mail
            parent.mailStore.AddMail(mail);
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

            string mode = null;
            if (session.sessionState.ContainsKey("mode")) { mode = (string)session.sessionState["mode"]; } 
            if (mode == "mail") { ProcessMailStream(session, data); return; }
            if (mode == "adventure") { ProcessAdventureStream(session, data); return; }
            ProcessBbsStream(session, data);
        }

        public void ProcessBbsStream(AX25Session session, byte[] data)
        {
            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            StringBuilder sb = new StringBuilder();
            foreach (string str in dataStrs)
            {
                if (str.Length == 0) continue;
                parent.AddBbsTraffic(session.Addresses[0].ToString(), false, str.Trim());

                // Switch to Winlink mail mode
                if ((!session.sessionState.ContainsKey("mode")) && (str.Length > 6) && (str.IndexOf("-") > 0) && str.StartsWith("[") && str.EndsWith("$]"))
                {
                    session.sessionState["mode"] = "mail";
                    ProcessMailStream(session, data);
                    return;
                }

                // Decode command and arguments
                string key = str.ToUpper(), value = "";
                int i = str.IndexOf(' ');
                if (i > 0) { key = str.Substring(0, i).ToUpper(); value = str.Substring(i + 1); }

                // Process commands
                if ((key == "M") || (key == "MENU"))
                {
                    sb.Append("Welcome to our BBS\r");
                    sb.Append("---\r");
                    sb.Append("[M]ain menu\r");
                    sb.Append("[A]dventure game\r");
                    sb.Append("[D]isconnect\r");
                    sb.Append("[S]oftware information\r");
                    sb.Append("---\r");
                }
                else if ((key == "S") || (key == "SOFTWARE"))
                {
                    sb.Append("This BBS is run by Handy-Talky Commander, an open source software available at https://github.com/Ylianst/HTCommander. This BBS can also handle Winlink messages in a limited way.\r");
                }
                else if ((key == "A") || (key == "ADVENTURE"))
                {
                    session.sessionState["mode"] = "adventure";
                    ProcessAdventureStream(session, null, true);
                }
                else if ((key == "D") || (key == "DISC") || (key == "DISCONNECT"))
                {
                    session.Disconnect();
                    return;
                }

                SessionSend(session, sb.ToString());
            }
        }

        /// <summary>
        /// Process traffic from a user playing the adventure game
        /// </summary>
        /// <param name="session"></param>
        /// <param name="data"></param>
        public void ProcessAdventureStream(AX25Session session, byte[] data, bool start = false)
        {
            string dataStr = null;
            if (data != null) { dataStr = UTF8Encoding.UTF8.GetString(data).Replace("\r\n", "\r").Replace("\n", "\r").Split('\r')[0]; }
            if (!string.IsNullOrEmpty(dataStr)) { parent.AddBbsTraffic(session.Addresses[0].ToString(), false, dataStr); }
            if (start) { dataStr = "help"; }

            Adventurer.GameRunner runner = new Adventurer.GameRunner();

            string output = runner.RunTurn("adv01.dat", Path.Combine(adventureAppDataPath, session.Addresses[0].CallSignWithId + ".sav"), dataStr).Replace("\r\n\r\n", "\r\n").Trim();
            if ((output != null) && (output.Length > 0))
            {
                if (start) { output = "Welcome to the Adventure Game\r\"quit\" to go back to BBS.\r" + output; }
                if (string.Compare(dataStr.Trim(), "quit", true) == 0) {
                    session.sessionState["mode"] = "bbs";
                    output += "\rBack to BBS, [M] for menu.";
                }
                SessionSend(session, output + "\r");
            }
        }

        /// <summary>
        /// Process traffic from a Winlink client
        /// </summary>
        /// <param name="session"></param>
        /// <param name="data"></param>
        public void ProcessMailStream(AX25Session session, byte[] data)
        {
            // This is embedded mail sent in compressed format
            if (session.sessionState.ContainsKey("wlMailBinary"))
            {
                MemoryStream blocks = (MemoryStream)session.sessionState["wlMailBinary"];
                blocks.Write(data, 0, data.Length);
                parent.AddBbsControlMessage("Receiving mail, " + blocks.Length + ((blocks.Length < 2) ? " byte" : " bytes"));
                if (ExtractMail(session, blocks) == true)
                {
                    // We are done with the mail reception
                    session.sessionState.Remove("wlMailBinary");
                    session.sessionState.Remove("wlMailBlocks");
                    session.sessionState.Remove("wlMailProp");
                    SendProposals(session, false);
                }
                return;
            }

            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            foreach (string str in dataStrs)
            {
                if (str.Length == 0) continue;
                parent.AddBbsTraffic(session.Addresses[0].ToString(), false, str.Trim());
                string key = str.ToUpper(), value = "";
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
                else if (key == "FF")
                {   // Winlink send messages back to connected station
                    UpdateEmails(session);
                    SendProposals(session, true);
                }
                else if (key == "FQ")
                {   // Winlink Session Close
                    session.Disconnect();
                }
                else if (key == "FS")
                {   // Winlink Send Mails
                    if (session.sessionState.ContainsKey("OutMails") && session.sessionState.ContainsKey("OutMailBlocks"))
                    {
                        List<WinLinkMail> proposedMails = (List<WinLinkMail>)session.sessionState["OutMails"];
                        List<List<Byte[]>> proposedMailsBinary = (List<List<Byte[]>>)session.sessionState["OutMailBlocks"];
                        session.sessionState["MailProposals"] = value;

                        // Look at proposal responses
                        int sentMails = 0;
                        string[] proposalResponses = ParseProposalResponses(value);
                        if (proposalResponses.Length == proposedMails.Count)
                        {
                            int totalSize = 0;
                            for (int j = 0; j < proposalResponses.Length; j++)
                            {
                                if (proposalResponses[j] == "Y")
                                {
                                    sentMails++;
                                    foreach (byte[] block in proposedMailsBinary[j]) { session.Send(block); totalSize += block.Length; }
                                }
                            }
                            if (sentMails == 1) { parent.AddBbsControlMessage("Sending mail, " + totalSize + " bytes..."); }
                            else if (sentMails > 1) { parent.AddBbsControlMessage("Sending " + sentMails + " mails, " + totalSize + " bytes..."); }
                            else
                            {
                                // Winlink Session Close
                                UpdateEmails(session);
                                parent.AddBbsControlMessage("No emails to transfer.");
                                SessionSend(session, "FQ");
                            }
                        }
                        else
                        {
                            // Winlink Session Close
                            parent.AddBbsControlMessage("Incorrect proposal response.");
                            SessionSend(session, "FQ");
                        }
                    }
                    else
                    {
                        // Winlink Session Close
                        parent.AddBbsControlMessage("Unexpected proposal response.");
                        SessionSend(session, "FQ");
                    }
                }
                else if (key == "ECHO")
                {   // Test Echo command
                    SessionSend(session, value + "\r");
                }
            }
        }

        private void SendProposals(AX25Session session, bool lastExchange)
        {
            // Send proposals with checksum
            StringBuilder sb = new StringBuilder();
            List<WinLinkMail> proposedMails = new List<WinLinkMail>();
            List<List<Byte[]>> proposedMailsBinary = new List<List<Byte[]>>();
            int checksum = 0, mailSendCount = 0;
            foreach (WinLinkMail mail in parent.Mails)
            {
                if ((mail.Mailbox != "Outbox") || string.IsNullOrEmpty(mail.MID) || (mail.MID.Length != 12)) continue;

                // See if the mail in the outbox is for the connected station
                bool others = false;
                bool response = WinLinkMail.IsMailForStation(session.Addresses[1].address, mail.To, mail.Cc, out others);
                if (response == false) continue;

                int uncompressedSize, compressedSize;
                List<Byte[]> blocks = WinLinkMail.EncodeMailToBlocks(mail, out uncompressedSize, out compressedSize);
                if (blocks != null)
                {
                    proposedMails.Add(mail);
                    proposedMailsBinary.Add(blocks);
                    string proposal = "FC EM " + mail.MID + " " + uncompressedSize + " " + compressedSize + " 0\r";
                    sb.Append(proposal);
                    byte[] proposalBin = ASCIIEncoding.ASCII.GetBytes(proposal);
                    for (int i = 0; i < proposalBin.Length; i++) { checksum += proposalBin[i]; }
                    mailSendCount++;
                }
            }
            if (mailSendCount > 0)
            {
                // Send proposal checksum
                checksum = (-checksum) & 0xFF;
                sb.Append("F> " + checksum.ToString("X2"));
                session.sessionState["OutMails"] = proposedMails;
                session.sessionState["OutMailBlocks"] = proposedMailsBinary;
            }
            else
            {
                // No mail proposals sent, close.
                if (lastExchange) { sb.Append("FQ"); } else { sb.Append("FF"); }
            }
            SessionSend(session, sb.ToString());
        }

        private string[] ParseProposalResponses(string value)
        {
            value = value.ToUpper().Replace("+", "Y").Replace("R", "N").Replace("-", "N").Replace("=", "L").Replace("H", "L").Replace("!", "A");
            List<string> responses = new List<string>();
            string r = "";
            for (int i = 0; i < value.Length; i++)
            {
                if ((value[i] >= '0') && (value[i] <= '9'))
                {
                    if (!string.IsNullOrEmpty(r)) { r += value[i]; }
                }
                else
                {
                    if (!string.IsNullOrEmpty(r)) { responses.Add(r); r = ""; }
                    r += value[i];
                }
            }
            if (!string.IsNullOrEmpty(r)) { responses.Add(r); }
            return responses.ToArray();
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

        private void UpdateEmails(AX25Session session)
        {
            // All good, save the new state of the mails
            if (session.sessionState.ContainsKey("OutMails") && session.sessionState.ContainsKey("OutMailBlocks") && session.sessionState.ContainsKey("MailProposals"))
            {
                List<WinLinkMail> proposedMails = (List<WinLinkMail>)session.sessionState["OutMails"];
                List<List<Byte[]>> proposedMailsBinary = (List<List<Byte[]>>)session.sessionState["OutMailBlocks"];
                string[] proposalResponses = ParseProposalResponses((string)session.sessionState["MailProposals"]);

                // Look at proposal responses
                int mailsChanges = 0;
                if (proposalResponses.Length == proposedMails.Count)
                {
                    for (int j = 0; j < proposalResponses.Length; j++)
                    {
                        if ((proposalResponses[j] == "Y") || (proposalResponses[j] == "N"))
                        {
                            proposedMails[j].Mailbox = "Sent";
                            parent.mailStore.UpdateMail(proposedMails[j]);
                            mailsChanges++;
                        }
                    }
                }

                if (mailsChanges > 0)
                {
                    parent.UpdateMail();
                }
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

            string output = runner.RunTurn("adv01.dat", Path.Combine(adventureAppDataPath, p.addresses[1].CallSignWithId + ".sav"), p.dataStr).Replace("\r\n\r\n", "\r\n").Trim();
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

            string output = runner.RunTurn("adv01.dat", Path.Combine(adventureAppDataPath, p.addresses[1].CallSignWithId + ".sav"), aprsPacket.MessageData.MsgText).Replace("\r\n\r\n", "\r\n").Trim();
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
