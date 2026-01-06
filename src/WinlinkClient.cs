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
using System.Text;
using System.Diagnostics;
using System.Windows.Forms;
using System.Collections.Generic;
using HTCommander.radio;
using System.IO;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

namespace HTCommander
{
    public class WinlinkClient
    {
        public enum TransportType { X25, TCP }
        public enum ConnectionState { DISCONNECTED, CONNECTED, CONNECTING, DISCONNECTING }

        private MainForm parent;
        private TransportType transportType;
        private Dictionary<string, object> sessionState = new Dictionary<string, object>();
        
        // TCP specific fields
        private TcpClient tcpClient;
        private Stream tcpStream; // Changed to Stream to support both NetworkStream and SslStream
        private bool tcpRunning = false;
        private string remoteAddress = "";
        private ConnectionState currentState = ConnectionState.DISCONNECTED;
        private bool useTls = false;

        public WinlinkClient(MainForm parent, TransportType transportType)
        {
            this.parent = parent;
            this.transportType = transportType;
        }

        private void TransportSend(string output)
        {
            if (!string.IsNullOrEmpty(output))
            {
                string[] dataStrs = output.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                foreach (string str in dataStrs)
                {
                    if (str.Length == 0) continue;
                    parent.mailClientDebugForm.AddBbsTraffic(remoteAddress, true, str.Trim());
                }

                if (transportType == TransportType.TCP)
                {
                    SendTcp(output);
                }
            }
        }

        private void TransportSend(byte[] data)
        {
            if ((data != null) && (data.Length > 0))
            {
                if (transportType == TransportType.TCP)
                {
                    SendTcp(data);
                }
            }
        }

        private void StateMessage(string msg)
        {
            parent.MailStateMessage(msg);
            parent.mailClientDebugForm.AddBbsControlMessage(msg);
        }

        private void SetConnectionState(ConnectionState state)
        {
            if (state != currentState)
            {
                currentState = state;
                ProcessTransportStateChange(state);
                
                if (state == ConnectionState.DISCONNECTED)
                {
                    sessionState.Clear();
                    remoteAddress = "";
                }
            }
        }

        // TCP Connection Methods
        public async Task<bool> ConnectTcp(string server, int port, bool useTls = false)
        {
            if (transportType != TransportType.TCP)
            {
                StateMessage("Error: Cannot use TCP connection with X25 transport type.");
                return false;
            }

            if (currentState != ConnectionState.DISCONNECTED)
            {
                StateMessage("Error: Already connected or connecting.");
                return false;
            }

            try
            {
                SetConnectionState(ConnectionState.CONNECTING);
                remoteAddress = server + ":" + port;
                this.useTls = useTls;
                parent.mailClientDebugForm.Clear();
                
                tcpClient = new TcpClient();
                await tcpClient.ConnectAsync(server, port);
                
                if (useTls)
                {
                    // Wrap the network stream with SSL/TLS
                    NetworkStream networkStream = tcpClient.GetStream();
                    SslStream sslStream = new SslStream(
                        networkStream,
                        false,
                        new RemoteCertificateValidationCallback(ValidateServerCertificate),
                        null
                    );
                    
                    try
                    {
                        await sslStream.AuthenticateAsClientAsync(server);
                        tcpStream = sslStream;
                        StateMessage("TLS/SSL connection established.");
                    }
                    catch (Exception ex)
                    {
                        StateMessage("TLS/SSL authentication failed: " + ex.Message);
                        sslStream.Close();
                        throw;
                    }
                }
                else
                {
                    tcpStream = tcpClient.GetStream();
                }
                
                SetConnectionState(ConnectionState.CONNECTED);
                
                // Start receiving data
                tcpRunning = true;
                _ = Task.Run(() => TcpReceiveLoop());
                
                return true;
            }
            catch (Exception ex)
            {
                StateMessage("TCP Connection failed: " + ex.Message);
                SetConnectionState(ConnectionState.DISCONNECTED);
                CleanupTcp();
                return false;
            }
        }

        // Certificate validation callback for SSL/TLS
        private bool ValidateServerCertificate(
            object sender,
            X509Certificate certificate,
            X509Chain chain,
            SslPolicyErrors sslPolicyErrors)
        {
            if (sslPolicyErrors == SslPolicyErrors.None)
            {
                return true;
            }

            StateMessage("Certificate validation error: " + sslPolicyErrors.ToString());
            
            // Log certificate details for debugging
            if (certificate != null)
            {
                StateMessage("Certificate Subject: " + certificate.Subject);
                StateMessage("Certificate Issuer: " + certificate.Issuer);
            }
            
            // For production, you should return false here to reject invalid certificates
            // For now, we'll be strict and reject invalid certificates
            return false;
        }

        public void DisconnectTcp()
        {
            if (transportType != TransportType.TCP) return;
            
            SetConnectionState(ConnectionState.DISCONNECTING);
            tcpRunning = false;
            CleanupTcp();
            SetConnectionState(ConnectionState.DISCONNECTED);
        }

        private void CleanupTcp()
        {
            try
            {
                if (tcpStream != null)
                {
                    tcpStream.Close();
                    tcpStream.Dispose();
                    tcpStream = null;
                }
                if (tcpClient != null)
                {
                    tcpClient.Close();
                    tcpClient.Dispose();
                    tcpClient = null;
                }
            }
            catch { }
        }

        private void SendTcp(string data)
        {
            if (tcpStream != null && tcpStream.CanWrite)
            {
                try
                {
                    byte[] buffer = UTF8Encoding.UTF8.GetBytes(data);
                    tcpStream.Write(buffer, 0, buffer.Length);
                    tcpStream.Flush();
                }
                catch (Exception ex)
                {
                    StateMessage("TCP Send error: " + ex.Message);
                    DisconnectTcp();
                }
            }
        }

        private void SendTcp(byte[] data)
        {
            if (tcpStream != null && tcpStream.CanWrite)
            {
                try
                {
                    tcpStream.Write(data, 0, data.Length);
                    tcpStream.Flush();
                }
                catch (Exception ex)
                {
                    StateMessage("TCP Send error: " + ex.Message);
                    DisconnectTcp();
                }
            }
        }

        private async Task TcpReceiveLoop()
        {
            byte[] buffer = new byte[8192];
            
            while (tcpRunning && tcpClient != null && tcpClient.Connected)
            {
                try
                {
                    int bytesRead = await tcpStream.ReadAsync(buffer, 0, buffer.Length);
                    
                    if (bytesRead > 0)
                    {
                        byte[] data = new byte[bytesRead];
                        Array.Copy(buffer, 0, data, 0, bytesRead);
                        
                        // Process received data on UI thread
                        parent.Invoke(new Action(() => {
                            ProcessStream(data);
                        }));
                    }
                    else
                    {
                        // Connection closed by remote
                        break;
                    }
                }
                catch (Exception ex)
                {
                    if (tcpRunning)
                    {
                        parent.Invoke(new Action(() => {
                            StateMessage("TCP Receive error: " + ex.Message);
                        }));
                    }
                    break;
                }
            }

            // Connection closed
            if (tcpRunning)
            {
                parent.Invoke(new Action(() => {
                    DisconnectTcp();
                }));
            }
        }

        // X25 Support Methods (called from external code for X25 transport)
        public void ProcessStreamState(AX25Session session, AX25Session.ConnectionState state)
        {
            if (transportType != TransportType.X25) return;

            remoteAddress = session.Addresses[0].ToString();
            
            ConnectionState newState;
            switch (state)
            {
                case AX25Session.ConnectionState.CONNECTED:
                    newState = ConnectionState.CONNECTED;
                    break;
                case AX25Session.ConnectionState.DISCONNECTED:
                    newState = ConnectionState.DISCONNECTED;
                    break;
                case AX25Session.ConnectionState.CONNECTING:
                    newState = ConnectionState.CONNECTING;
                    parent.mailClientDebugForm.Clear();
                    break;
                case AX25Session.ConnectionState.DISCONNECTING:
                    newState = ConnectionState.DISCONNECTING;
                    break;
                default:
                    return;
            }
            
            SetConnectionState(newState);
        }

        public void ProcessStream(AX25Session session, byte[] data)
        {
            if (transportType != TransportType.X25) return;
            
            // Copy session state from AX25Session
            sessionState = session.sessionState;
            remoteAddress = session.Addresses[0].ToString();
            
            ProcessStream(data);
        }

        private void ProcessTransportStateChange(ConnectionState state)
        {
            switch (state)
            {
                case ConnectionState.CONNECTED:
                    StateMessage("Connected to " + remoteAddress);
                    break;
                case ConnectionState.DISCONNECTED:
                    StateMessage("Disconnected");
                    StateMessage(null);
                    break;
                case ConnectionState.CONNECTING:
                    StateMessage("Connecting...");
                    break;
                case ConnectionState.DISCONNECTING:
                    StateMessage("Disconnecting...");
                    break;
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

        private void UpdateEmails()
        {
            // All good, save the new state of the mails
            if (sessionState.ContainsKey("OutMails") && sessionState.ContainsKey("OutMailBlocks") && sessionState.ContainsKey("MailProposals"))
            {
                List<WinLinkMail> proposedMails = (List<WinLinkMail>)sessionState["OutMails"];
                List<List<Byte[]>> proposedMailsBinary = (List<List<Byte[]>>)sessionState["OutMailBlocks"];
                string[] proposalResponses = ParseProposalResponses((string)sessionState["MailProposals"]);

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

        // Process stream data (unified for both TCP and X25)
        private void ProcessStream(byte[] data)
        {
            if ((data == null) || (data.Length == 0)) return;

            // This is embedded mail sent in compressed format
            if (sessionState.ContainsKey("wlMailBinary"))
            {
                MemoryStream blocks = (MemoryStream)sessionState["wlMailBinary"];
                blocks.Write(data, 0, data.Length);
                StateMessage("Receiving mail, " + blocks.Length + ((blocks.Length < 2) ? " byte" : " bytes"));
                if (ExtractMail(blocks) == true)
                {
                    // We are done with the mail reception
                    sessionState.Remove("wlMailBinary");
                    sessionState.Remove("wlMailBlocks");
                    sessionState.Remove("wlMailProp");
                    TransportSend("FF");
                    
                    // Close TCP session after sending FF
                    if (transportType == TransportType.TCP)
                    {
                        DisconnectTcp();
                    }
                }
                return;
            }

            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            foreach (string str in dataStrs)
            {
                if (str.Length == 0) continue;
                parent.mailClientDebugForm.AddBbsTraffic(remoteAddress, false, str);

                // Handle TCP callsign prompt
                if ((transportType == TransportType.TCP) && str.Trim().Equals("Callsign :", StringComparison.OrdinalIgnoreCase))
                {
                    // Send our callsign with station ID
                    string callsignResponse = parent.callsign;
                    /*
                    if (parent.stationId > 0) { callsignResponse += "-" + parent.stationId; }
                    */
                    callsignResponse += "\r";
                    TransportSend(callsignResponse);
                    StateMessage("Sent callsign: " + callsignResponse.Trim());
                    continue;
                }

                // Handle TCP password prompt
                if ((transportType == TransportType.TCP) && str.Trim().Equals("Password :", StringComparison.OrdinalIgnoreCase))
                {
                    // Send "CMSTelnet" as the password
                    TransportSend("CMSTelnet\r");
                    continue;
                }

                if (str.EndsWith(">") && !sessionState.ContainsKey("SessionStart"))
                {
                    // Only do this once at the start of the session
                    sessionState["SessionStart"] = 1;

                    // Build the big response (Info + Auth + Proposals)
                    StringBuilder sb = new StringBuilder();

                    // Send Information
                    sb.Append("[RMS Express-1.7.28.0-B2FHM$]\r");

                    // Send Authentication
                    if (sessionState.ContainsKey("WinlinkAuth"))
                    {
                        string authResponse = WinlinkSecurity.SecureLoginResponse((string)sessionState["WinlinkAuth"], parent.winlinkPassword);
                        if (!string.IsNullOrEmpty(parent.winlinkPassword)) { sb.Append(";PR: " + authResponse + "\r"); }
                        StateMessage("Authenticating...");
                    }

                    // Send proposals with checksum
                    List<WinLinkMail> proposedMails = new List<WinLinkMail>();
                    List<List<Byte[]>> proposedMailsBinary = new List<List<Byte[]>>();
                    int checksum = 0, mailSendCount = 0;
                    foreach (WinLinkMail mail in parent.Mails)
                    {
                        if ((mail.Mailbox != "Outbox") || string.IsNullOrEmpty(mail.MID) || (mail.MID.Length != 12)) continue;

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
                        sb.Append("F> " + checksum.ToString("X2") + "\r");
                        TransportSend(sb.ToString());
                        sessionState["OutMails"] = proposedMails;
                        sessionState["OutMailBlocks"] = proposedMailsBinary;
                    }
                    else
                    {
                        // No mail proposals sent, give a change to the server to send us mails.
                        sb.Append("FF\r");
                        TransportSend(sb.ToString());
                    }
                }
                else
                {
                    string key = str, value = "";
                    int i = str.IndexOf(' ');
                    if (i > 0) { key = str.Substring(0, i).ToUpper(); value = str.Substring(i + 1); }

                    if ((key == ";PQ:") && (!string.IsNullOrEmpty(parent.winlinkPassword)))
                    {   // Winlink Authentication Request
                        sessionState["WinlinkAuth"] = value;
                    }
                    else if (key == "FS") // "FS YY"
                    {   // Winlink Mail Transfer Approvals
                        if (sessionState.ContainsKey("OutMails") && sessionState.ContainsKey("OutMailBlocks"))
                        {
                            List<WinLinkMail> proposedMails = (List<WinLinkMail>)sessionState["OutMails"];
                            List<List<Byte[]>> proposedMailsBinary = (List<List<Byte[]>>)sessionState["OutMailBlocks"];
                            sessionState["MailProposals"] = value;

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
                                        foreach (byte[] block in proposedMailsBinary[j]) { TransportSend(block); totalSize += block.Length; }
                                    }
                                }
                                if (sentMails == 1) { StateMessage("Sending mail, " + totalSize + " bytes..."); }
                                else if (sentMails > 1) { StateMessage("Sending " + sentMails + " mails, " + totalSize + " bytes..."); }
                                else
                                {
                                    // Winlink Session Close
                                    UpdateEmails();
                                    StateMessage("No emails to transfer.");
                                    TransportSend("FF\r");
                                }
                            }
                            else
                            {
                                // Winlink Session Close
                                StateMessage("Incorrect proposal response.");
                                TransportSend("FQ\r");
                            }
                        }
                        else
                        {
                            // Winlink Session Close
                            StateMessage("Unexpected proposal response.");
                            TransportSend("FQ\r");
                        }
                    }
                    else if (key == "FF")
                    {
                        // Winlink Session Close
                        UpdateEmails();
                        TransportSend("FQ\r");
                    }
                    else if (key == "FC")
                    {
                        // Winlink Mail Proposal
                        List<string> proposals;
                        if (sessionState.ContainsKey("wlMailProp")) { proposals = (List<string>)sessionState["wlMailProp"]; } else { proposals = new List<string>(); }
                        proposals.Add(value);
                        sessionState["wlMailProp"] = proposals;
                    }
                    else if (key == "F>")
                    {
                        // Winlink Mail Proposals completed, we need to respond
                        if ((sessionState.ContainsKey("wlMailProp")) && (!sessionState.ContainsKey("wlMailBinary")))
                        {
                            List<string> proposals = (List<string>)sessionState["wlMailProp"];
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
                                    TransportSend("FS " + response + "\r");
                                    if (acceptedProposalCount > 0)
                                    {
                                        sessionState["wlMailBinary"] = new MemoryStream();
                                        sessionState["wlMailProp"] = proposals2;
                                    }
                                }
                                else
                                {
                                    // Checksum failed
                                    StateMessage("Checksum Failed");
                                    if (transportType == TransportType.TCP)
                                    {
                                        DisconnectTcp();
                                    }
                                }
                            }
                        }
                    }
                    else if (key == "FQ")
                    {   // Winlink Session Close
                        UpdateEmails();
                        if (transportType == TransportType.TCP)
                        {
                            DisconnectTcp();
                        }
                    }
                }
            }
        }

        private bool ExtractMail(MemoryStream blocks)
        {
            if (sessionState.ContainsKey("wlMailProp") == false) return false;
            List<string> proposals = (List<string>)sessionState["wlMailProp"];
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
            if (fail) { StateMessage("Failed to decode mail."); return true; }
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
            parent.mailStore.AddMail(mail);
            parent.UpdateMail();
            StateMessage("Got mail for " + mail.To + ".");

            return (proposals.Count == 0);
        }

        private bool WeHaveEmail(string mid)
        {
            foreach (WinLinkMail mail in parent.Mails) { if (mail.MID == mid) return true; }
            return false;
        }
    }
}
