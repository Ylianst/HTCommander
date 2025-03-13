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

namespace HTCommander
{
    public class WinlinkClient
    {
        private MainForm parent;

        public WinlinkClient(MainForm parent)
        {
            this.parent = parent;
        }

        private void SessionSend(AX25Session session, string output)
        {
            if (!string.IsNullOrEmpty(output))
            {
                string[] dataStrs = output.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                foreach (string str in dataStrs)
                {
                    if (str.Length == 0) continue;
                    parent.mailClientDebugForm.AddBbsTraffic(session.Addresses[0].ToString(), true, str.Trim());
                }
                session.Send(output);
            }
        }

        private void StateMessage(string msg) {
            parent.MailStateMessage(msg);
            parent.mailClientDebugForm.AddBbsControlMessage(msg);
        }

        // Process connection state change
        public void ProcessStreamState(AX25Session session, AX25Session.ConnectionState state)
        {
            switch (state)
            {
                case AX25Session.ConnectionState.CONNECTED:
                    StateMessage("Connected to " + session.Addresses[0].ToString());
                    break;
                case AX25Session.ConnectionState.DISCONNECTED:
                    StateMessage("Disconnected");
                    StateMessage(null);
                    break;
                case AX25Session.ConnectionState.CONNECTING:
                    parent.mailClientDebugForm.Clear();
                    StateMessage("Connecting...");
                    break;
                case AX25Session.ConnectionState.DISCONNECTING:
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
                            proposedMails[j].Mailbox = 3; // Sent
                            mailsChanges++;
                        }
                    }
                }

                if (mailsChanges > 0)
                {
                    parent.SaveMails();
                    parent.UpdateMail();
                }
            }
        }

        // Process stream data
        public void ProcessStream(AX25Session session, byte[] data)
        {
            if ((data == null) || (data.Length == 0)) return;

            // This is embedded mail sent in compressed format
            if (session.sessionState.ContainsKey("wlMailBinary"))
            {
                MemoryStream blocks = (MemoryStream)session.sessionState["wlMailBinary"];
                blocks.Write(data, 0, data.Length);
                StateMessage("Receiving mail, " + blocks.Length + ((blocks.Length < 2) ? " byte" : " bytes"));
                if (ExtractMail(session, blocks) == true)
                {
                    // We are done with the mail reception
                    session.sessionState.Remove("wlMailBinary");
                    session.sessionState.Remove("wlMailBlocks");
                    session.sessionState.Remove("wlMailProp");
                    SessionSend(session, "FF");
                }
                return;
            }

            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            foreach (string str in dataStrs)
            {
                if (str.Length == 0) continue;
                parent.mailClientDebugForm.AddBbsTraffic(session.Addresses[0].ToString(), false, str);

                if (str.EndsWith(">") && !session.sessionState.ContainsKey("SessionStart"))
                {
                    // Only do this once at the start of the session
                    session.sessionState["SessionStart"] = 1;

                    // Build the big response (Info + Auth + Proposals)
                    StringBuilder sb = new StringBuilder();

                    // Send Information
                    sb.Append("[HTCmd-" + GetVersion() + "-B2FHM$]\r");

                    // Send Authentication
                    if (session.sessionState.ContainsKey("WinlinkAUth"))
                    {
                        string authResponse = WinlinkSecurity.SecureLoginResponse((string)session.sessionState["WinlinkAUth"], parent.winlinkPassword);
                        if (!string.IsNullOrEmpty(parent.winlinkPassword)) { sb.Append(";PR: " + authResponse + "\r"); }
                        StateMessage("Authenticating...");
                    }

                    // Send proposals with checksum
                    List<WinLinkMail> proposedMails = new List<WinLinkMail>();
                    List<List<Byte[]>> proposedMailsBinary = new List<List<Byte[]>>();
                    int checksum = 0, mailSendCount = 0;
                    foreach (WinLinkMail mail in parent.Mails)
                    {
                        if ((mail.Mailbox != 1) || string.IsNullOrEmpty(mail.MID) || (mail.MID.Length != 12)) continue;

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
                        SessionSend(session, sb.ToString());
                        session.sessionState["OutMails"] = proposedMails;
                        session.sessionState["OutMailBlocks"] = proposedMailsBinary;
                    }
                    else
                    {
                        // No mail proposals sent, give a change to the server to send us mails.
                        sb.Append("FF");
                        SessionSend(session, sb.ToString());
                    }
                }
                else
                {
                    string key = str, value = "";
                    int i = str.IndexOf(' ');
                    if (i > 0) { key = str.Substring(0, i).ToUpper(); value = str.Substring(i + 1); }

                    if ((key == ";PQ:") && (!string.IsNullOrEmpty(parent.winlinkPassword)))
                    {   // Winlink Authentication Request
                        session.sessionState["WinlinkAUth"] = value;
                    }
                    else if (key == "FS") // "FS YY"
                    {   // Winlink Mail Transfer Approvals
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
                                if (sentMails == 1) { StateMessage("Sending mail, " + totalSize + " bytes..."); }
                                else if (sentMails > 1) { StateMessage("Sending " + sentMails + " mails, " + totalSize + " bytes..."); }
                                else
                                {
                                    // Winlink Session Close
                                    UpdateEmails(session);
                                    StateMessage("No emails to transfer.");
                                    SessionSend(session, "FF");
                                }
                            }
                            else
                            {
                                // Winlink Session Close
                                StateMessage("Incorrect proposal response.");
                                SessionSend(session, "FQ");
                            }
                        }
                        else
                        {
                            // Winlink Session Close
                            StateMessage("Unexpected proposal response.");
                            SessionSend(session, "FQ");
                        }
                    }
                    else if (key == "FF")
                    {
                        // Winlink Session Close
                        UpdateEmails(session);
                        SessionSend(session, "FQ");
                    }
                    else if (key == "FC")
                    {
                        // Winlink Mail Proposal
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
                                    StateMessage("Checksum Failed");
                                    session.Disconnect();
                                }
                            }
                        }
                    }
                    else if (key == "FQ")
                    {   // Winlink Session Close
                        UpdateEmails(session);
                        session.Disconnect();
                    }
                }
            }
        }

        // Process un-numbered frames
        public void ProcessFrame(TncDataFragment frame, AX25Packet p)
        {
            // Do nothing
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
            parent.Mails.Add(mail);
            parent.SaveMails();
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
