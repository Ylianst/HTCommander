/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Windows.Forms;
using System.Collections.Generic;
using aprsparser;

namespace HTCommander
{
    /// <summary>
    /// BBS (Bulletin Board System) handler for a specific radio device.
    /// Each BBS instance handles at most one AX25 session for its associated radio.
    /// Listens for UniqueDataFrame events with "BBS" usage matching the radio device ID.
    /// </summary>
    public class BBS : IDisposable
    {
        private readonly DataBrokerClient broker;
        private readonly string adventureAppDataPath;
        private readonly int deviceId;
        private AX25Session session;
        private bool disposed = false;

        /// <summary>
        /// Gets or sets whether this BBS handler is enabled. When disabled, incoming packets are ignored.
        /// </summary>
        public bool Enabled { get; set; } = false;

        /// <summary>
        /// Gets the radio device ID this BBS instance is servicing.
        /// </summary>
        public int DeviceId => deviceId;

        /// <summary>
        /// Gets the current AX25 session, if any.
        /// </summary>
        public AX25Session Session => session;

        /// <summary>
        /// Statistics for stations that have connected to this BBS.
        /// </summary>
        public Dictionary<string, StationStats> stats = new Dictionary<string, StationStats>();

        /// <summary>
        /// Statistics for a station that has connected to the BBS.
        /// </summary>
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

        /// <summary>
        /// Creates a new BBS handler for the specified radio device.
        /// </summary>
        /// <param name="deviceId">The radio device ID this BBS will service.</param>
        public BBS(int deviceId)
        {
            this.deviceId = deviceId;
            broker = new DataBrokerClient();

            // Get application data path for adventure game saves
            adventureAppDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", "Adventure");
            if (!Directory.Exists(adventureAppDataPath)) { try { Directory.CreateDirectory(adventureAppDataPath); } catch (Exception) { } }

            // Create the AX25 session for this device
            session = new AX25Session(deviceId);
            session.StateChanged += OnSessionStateChanged;
            session.DataReceivedEvent += OnSessionDataReceived;
            session.UiDataReceivedEvent += OnSessionUiDataReceived;
            session.ErrorEvent += OnSessionError;

            // Subscribe to UniqueDataFrame events to handle incoming BBS packets
            broker.Subscribe(DataBroker.AllDevices, "UniqueDataFrame", OnUniqueDataFrame);

            broker.LogInfo($"[BBS/{deviceId}] BBS handler created for device {deviceId}");
        }

        /// <summary>
        /// Handles UniqueDataFrame events, filtering for BBS usage and matching device ID.
        /// </summary>
        private void OnUniqueDataFrame(int sourceDeviceId, string name, object data)
        {
            if (!Enabled) return;
            if (disposed) return;
            if (!(data is TncDataFragment frame)) return;

            // Only process frames for our device with BBS usage
            if (frame.RadioDeviceId != deviceId) return;
            if (string.IsNullOrEmpty(frame.usage) || !frame.usage.Equals("BBS", StringComparison.OrdinalIgnoreCase)) return;

            broker.LogInfo($"[BBS/{deviceId}] Received BBS frame from device {frame.RadioDeviceId}");

            // Parse the AX.25 packet
            AX25Packet packet = AX25Packet.DecodeAX25Packet(frame);
            if (packet == null) return;

            // Process the frame
            ProcessFrame(frame, packet);
        }

        /// <summary>
        /// Handles session state changes.
        /// </summary>
        private void OnSessionStateChanged(AX25Session sender, AX25Session.ConnectionState state)
        {
            if (!Enabled) return;
            ProcessStreamState(sender, state);
        }

        /// <summary>
        /// Handles data received from the session (I-frames).
        /// </summary>
        private void OnSessionDataReceived(AX25Session sender, byte[] data)
        {
            if (!Enabled) return;
            ProcessStream(sender, data);
        }

        /// <summary>
        /// Handles UI data received from the session (connectionless).
        /// </summary>
        private void OnSessionUiDataReceived(AX25Session sender, byte[] data)
        {
            if (!Enabled) return;
            // UI frames can be handled here if needed
            broker.LogInfo($"[BBS/{deviceId}] Received UI data: {data?.Length ?? 0} bytes");
        }

        /// <summary>
        /// Handles session errors.
        /// </summary>
        private void OnSessionError(AX25Session sender, string error)
        {
            broker.LogError($"[BBS/{deviceId}] Session error: {error}");
            broker.Dispatch(0, "BbsError", new { DeviceId = deviceId, Error = error });
        }

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!disposed)
            {
                if (disposing)
                {
                    broker?.LogInfo($"[BBS/{deviceId}] BBS handler disposing");

                    // Dispose the session
                    if (session != null)
                    {
                        session.StateChanged -= OnSessionStateChanged;
                        session.DataReceivedEvent -= OnSessionDataReceived;
                        session.UiDataReceivedEvent -= OnSessionUiDataReceived;
                        session.ErrorEvent -= OnSessionError;
                        session.Dispose();
                        session = null;
                    }

                    broker?.Dispose();
                }
                disposed = true;
            }
        }

        private void UpdateStats(string callsign, string protocol, int packetIn, int packetOut, int bytesIn, int bytesOut)
        {
            if (!Enabled) return;

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

            // Dispatch stats update via broker
            broker.Dispatch(0, "BbsStatsUpdated", new { DeviceId = deviceId, Stats = s });
        }

        public void ClearStats()
        {
            stats.Clear();
            broker.Dispatch(0, "BbsStatsCleared", new { DeviceId = deviceId });
        }

        private void SessionSend(AX25Session session, string output)
        {
            if (!Enabled) return;
            if (session == null) return;
            if (!string.IsNullOrEmpty(output))
            {
                string[] dataStrs = output.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                for (int i = 0; i < dataStrs.Length; i++)
                {
                    if ((dataStrs[i].Trim().Length == 0) && (i == (dataStrs.Length - 1))) continue;
                    broker.Dispatch(0, "BbsTraffic", new { DeviceId = deviceId, Callsign = session.Addresses[0].ToString(), Outgoing = true, Message = dataStrs[i].Trim() });
                }
                UpdateStats(session.Addresses[0].ToString(), "Stream", 0, 1, 0, output.Length);
                session.Send(output);
            }
        }

        private string GetVersion()
        {
            string exePath = Application.ExecutablePath;
            FileVersionInfo versionInfo = FileVersionInfo.GetVersionInfo(exePath);
            string[] vers = versionInfo.FileVersion.Split('.');
            return vers[0] + "." + vers[1];
        }

        public void ProcessStreamState(AX25Session session, AX25Session.ConnectionState state)
        {
            if (!Enabled) return;

            switch (state)
            {
                case AX25Session.ConnectionState.CONNECTED:
                    broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Connected to " + session.Addresses[0].ToString() });
                    session.sessionState["wlChallenge"] = WinlinkSecurity.GenerateChallenge();

                    StringBuilder sb = new StringBuilder();
                    sb.Append("Handy-Talky Commander BBS\r[M] for menu\r");
                    sb.Append("[WL2K-5.0-B2FWIHJM$]\r");

                    string winlinkPassword = broker.GetValue<string>(0, "WinlinkPassword", "");
                    if (!string.IsNullOrEmpty(winlinkPassword)) { sb.Append(";PQ: " + session.sessionState["wlChallenge"] + "\r"); }
                    sb.Append(">\r");
                    SessionSend(session, sb.ToString());
                    break;
                case AX25Session.ConnectionState.DISCONNECTED:
                    broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Disconnected" });
                    break;
                case AX25Session.ConnectionState.CONNECTING:
                    broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Connecting..." });
                    break;
                case AX25Session.ConnectionState.DISCONNECTING:
                    broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Disconnecting..." });
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
            if (proposalSplit.Length < 4) return true; // Invalid proposal format
            string MID = proposalSplit[1];
            int mFullLen, mCompLen;
            int.TryParse(proposalSplit[2], out mFullLen);
            int.TryParse(proposalSplit[3], out mCompLen);

            // See what we got
            bool fail;
            int dataConsumed = 0;
            WinLinkMail mail = WinLinkMail.DecodeBlocksToEmail(blocks.ToArray(), out fail, out dataConsumed);
            if (fail)
            {
                broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Failed to decode mail." });
                broker.LogError($"[BBS/{deviceId}] Failed to decode mail {MID}");
                return true;
            }
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
            string callsign = broker.GetValue<string>(0, "CallSign", "");
            bool others = false;
            bool isForUs = WinLinkMail.IsMailForStation(callsign, mail.To, mail.Cc, out others);
            
            // Set mailbox based on whether mail is for us
            if (isForUs)
            {
                mail.Mailbox = "Inbox";
            }
            else
            {
                mail.Mailbox = "Outbox"; // Keep for forwarding to others
            }

            // TODO: If others is true, we may need to keep a copy for others to get.

            // Add the received mail to the store via broker
            broker.Dispatch(0, "MailAdd", mail, store: false);
            broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Got mail for " + mail.To + "." });
            broker.LogInfo($"[BBS/{deviceId}] Received mail {mail.MID} for {mail.To}");

            return (proposals.Count == 0);
        }
        private bool WeHaveEmail(string mid)
        {
            // Check if mail exists using MailStore via DataBroker handler
            MailStore mailStore = DataBroker.GetDataHandler<MailStore>("MailStore");
            return mailStore?.MailExists(mid) ?? false;
        }

        public void ProcessStream(AX25Session session, byte[] data)
        {
            if (!Enabled) return;
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
            if (!Enabled) return;

            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            StringBuilder sb = new StringBuilder();
            for (int lineIndex = 0; lineIndex < dataStrs.Length; lineIndex++)
            {
                string str = dataStrs[lineIndex];
                if (str.Length == 0) continue;
                broker.Dispatch(0, "BbsTraffic", new { DeviceId = deviceId, Callsign = session.Addresses[0].ToString(), Outgoing = false, Message = str.Trim() });

                // Switch to Winlink mail mode
                if ((!session.sessionState.ContainsKey("mode")) && (str.Length > 6) && (str.IndexOf("-") > 0) && str.StartsWith("[") && str.EndsWith("$]"))
                {
                    session.sessionState["mode"] = "mail";
                    // Process remaining lines in this packet as mail stream
                    if (lineIndex + 1 < dataStrs.Length)
                    {
                        // Build remaining data from unprocessed lines
                        StringBuilder remainingData = new StringBuilder();
                        for (int j = lineIndex + 1; j < dataStrs.Length; j++)
                        {
                            if (remainingData.Length > 0) remainingData.Append("\r");
                            remainingData.Append(dataStrs[j]);
                        }
                        if (remainingData.Length > 0)
                        {
                            ProcessMailStream(session, UTF8Encoding.UTF8.GetBytes(remainingData.ToString()));
                        }
                    }
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
        /// Process traffic from a user playing the adventure game.
        /// </summary>
        public void ProcessAdventureStream(AX25Session session, byte[] data, bool start = false)
        {
            if (!Enabled) return;

            string dataStr = null;
            if (data != null) { dataStr = UTF8Encoding.UTF8.GetString(data).Replace("\r\n", "\r").Replace("\n", "\r").Split('\r')[0]; }
            if (start) { dataStr = "help"; }

            Adventurer.GameRunner runner = new Adventurer.GameRunner();

            string output = runner.RunTurn("adv01.dat", Path.Combine(adventureAppDataPath, session.Addresses[0].CallSignWithId + ".sav"), dataStr).Replace("\r\n\r\n", "\r\n").Trim();
            if ((output != null) && (output.Length > 0))
            {
                if (start) { output = "Welcome to the Adventure Game\r\"quit\" to go back to BBS.\r" + output; }
                if (string.Compare(dataStr.Trim(), "quit", true) == 0)
                {
                    session.sessionState["mode"] = "bbs";
                    output += "\rBack to BBS, [M] for menu.";
                }
                SessionSend(session, output + "\r");
            }
        }

        /// <summary>
        /// Process traffic from a Winlink client.
        /// </summary>
        public void ProcessMailStream(AX25Session session, byte[] data)
        {
            if (!Enabled) return;

            // This is embedded mail sent in compressed format
            if (session.sessionState.ContainsKey("wlMailBinary"))
            {
                MemoryStream blocks = (MemoryStream)session.sessionState["wlMailBinary"];
                blocks.Write(data, 0, data.Length);
                broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Receiving mail, " + blocks.Length + ((blocks.Length < 2) ? " byte" : " bytes") });
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
                broker.Dispatch(0, "BbsTraffic", new { DeviceId = deviceId, Callsign = session.Addresses[0].ToString(), Outgoing = false, Message = str.Trim() });
                string key = str.ToUpper(), value = "";
                int i = str.IndexOf(' ');
                if (i > 0) { key = str.Substring(0, i).ToUpper(); value = str.Substring(i + 1); }

                string winlinkPassword = broker.GetValue<string>(0, "WinlinkPassword", "");

                if ((key == ";PR:") && (!string.IsNullOrEmpty(winlinkPassword)))
                {   // Winlink Authentication Response
                    if (WinlinkSecurity.SecureLoginResponse((string)(session.sessionState["wlChallenge"]), winlinkPassword) == value)
                    {
                        session.sessionState["wlAuth"] = "OK";
                        broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Authentication Success" });
                        broker.LogInfo($"[BBS/{deviceId}] Winlink Auth Success");
                    }
                    else
                    {
                        broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Authentication Failed" });
                        broker.LogInfo($"[BBS/{deviceId}] Winlink Auth Failed");
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
                                broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Checksum Failed" });
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
                            if (sentMails == 1) { broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Sending mail, " + totalSize + " bytes..." }); }
                            else if (sentMails > 1) { broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Sending " + sentMails + " mails, " + totalSize + " bytes..." }); }
                            else
                            {
                                // Winlink Session Close
                                UpdateEmails(session);
                                broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "No emails to transfer." });
                                SessionSend(session, "FQ");
                            }
                        }
                        else
                        {
                            // Winlink Session Close
                            broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Incorrect proposal response." });
                            SessionSend(session, "FQ");
                        }
                    }
                    else
                    {
                        // Winlink Session Close
                        broker.Dispatch(0, "BbsControlMessage", new { DeviceId = deviceId, Message = "Unexpected proposal response." });
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
            if (!Enabled) return;

            StringBuilder sb = new StringBuilder();
            List<WinLinkMail> proposedMails = new List<WinLinkMail>();
            List<List<Byte[]>> proposedMailsBinary = new List<List<Byte[]>>();
            int checksum = 0, mailSendCount = 0;

            // TODO: Implement mail proposal sending via broker when enabled

            if (mailSendCount > 0)
            {
                checksum = (-checksum) & 0xFF;
                sb.Append("F> " + checksum.ToString("X2") + "\r");
                session.sessionState["OutMails"] = proposedMails;
                session.sessionState["OutMailBlocks"] = proposedMailsBinary;
            }
            else
            {
                if (lastExchange) { sb.Append("FQ\r"); } else { sb.Append("FF\r"); }
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

        /// <summary>
        /// Process an incoming frame. The session will handle the AX.25 protocol,
        /// but this method can be used for additional frame-level processing.
        /// </summary>
        public void ProcessFrame(TncDataFragment frame, AX25Packet p)
        {
            if (!Enabled) return;

            // The AX25Session will handle the packet through its subscription to UniqueDataFrame.
            // This method is for any additional BBS-specific frame processing.
            broker.LogInfo($"[BBS/{deviceId}] Processing frame from {p.addresses[1]?.ToString() ?? "unknown"}");
        }

        private void UpdateEmails(AX25Session session)
        {
            if (!Enabled) return;

            if (session.sessionState.ContainsKey("OutMails") && session.sessionState.ContainsKey("OutMailBlocks") && session.sessionState.ContainsKey("MailProposals"))
            {
                List<WinLinkMail> proposedMails = (List<WinLinkMail>)session.sessionState["OutMails"];
                List<List<Byte[]>> proposedMailsBinary = (List<List<Byte[]>>)session.sessionState["OutMailBlocks"];
                string[] proposalResponses = ParseProposalResponses((string)session.sessionState["MailProposals"]);

                int mailsChanges = 0;
                if (proposalResponses.Length == proposedMails.Count)
                {
                    for (int j = 0; j < proposalResponses.Length; j++)
                    {
                        if ((proposalResponses[j] == "Y") || (proposalResponses[j] == "N"))
                        {
                            proposedMails[j].Mailbox = "Sent";
                            // TODO: Update mail via broker when implemented
                            mailsChanges++;
                        }
                    }
                }

                if (mailsChanges > 0)
                {
                    broker.Dispatch(0, "BbsMailUpdated", new { DeviceId = deviceId, MailChanges = mailsChanges });
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
                if ((r1.Length <= r2.Length) && (r1.Length <= r3.Length)) { outpid = 241; return r1; }
                if (r2.Length <= r3.Length) { outpid = 242; return r2; }
                outpid = 243;
                return r3;
            }
            outpid = 240;
            return r1;
        }

        private void ProcessRawFrame(AX25Packet p, int frameLength)
        {
            if (!Enabled) return;

            string dataStr = p.dataStr;
            if (p.pid == 242) { try { dataStr = UTF8Encoding.Default.GetString(Utils.DecompressBrotli(p.data)); } catch (Exception) { } }
            if (p.pid == 243) { try { dataStr = UTF8Encoding.Default.GetString(Utils.CompressDeflate(p.data)); } catch (Exception) { } }

            broker.Dispatch(0, "BbsTraffic", new { DeviceId = deviceId, Callsign = p.addresses[1].ToString(), Outgoing = false, Message = dataStr });

            Adventurer.GameRunner runner = new Adventurer.GameRunner();

            string output = runner.RunTurn("adv01.dat", Path.Combine(adventureAppDataPath, p.addresses[1].CallSignWithId + ".sav"), p.dataStr).Replace("\r\n\r\n", "\r\n").Trim();
            if ((output != null) && (output.Length > 0))
            {
                broker.Dispatch(0, "BbsTraffic", new { DeviceId = deviceId, Callsign = p.addresses[1].ToString(), Outgoing = true, Message = output });

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

                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(p.addresses[1]);

                int bytesOut = 0;
                int packetsOut = 0;
                byte outPid = 0;
                for (int i = 0; i < stringList.Count; i++)
                {
                    AX25Packet packet = new AX25Packet(addresses, GetCompressed(p.pid, stringList[i], out outPid), DateTime.Now);
                    packet.pid = outPid;
                    packet.channel_id = p.channel_id;
                    packet.channel_name = p.channel_name;

                    // Request packet transmission via broker
                    broker.Dispatch(deviceId, "BbsTransmitPacket", new { Packet = packet, ChannelId = packet.channel_id });
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
            if (!Enabled) return;
            // TODO: Implement APRS packet processing when BBS is fully enabled
        }
    }
}
