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

            /*
            // This is embedded mail sent in compressed format
            if (session.sessionState.ContainsKey("wlMailBinary"))
            {
                parent.AddBbsControlMessage("Receiving binary traffic.");
                List<byte[]> blocks;
                if (session.sessionState.ContainsKey("wlMailBlocks")) { blocks = (List<byte[]>)session.sessionState["wlMailBlocks"]; } else { blocks = new List<byte[]>(); }
                blocks.Add(data);
                session.sessionState["wlMailBlocks"] = blocks;
                if (ExtractMail(session) == true)
                {
                    // We are done with the mail reception
                    session.sessionState.Remove("wlMailBinary");
                    session.sessionState.Remove("wlMailBlocks");
                    session.sessionState.Remove("wlMailProp");
                    SessionSend(session, "FF\r");
                }
                return;
            }
            */

            string dataStr = UTF8Encoding.UTF8.GetString(data);
            string[] dataStrs = dataStr.Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
            foreach (string str in dataStrs)
            {
                if (str.Length == 0) continue;
                parent.mailClientDebugForm.AddBbsTraffic(session.Addresses[0].ToString(), false, str);

                if (str.EndsWith(">"))
                {
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

                        int uncompressedSize;
                        int compressedSize;
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
                        // No mail proposals sent, close.
                        sb.Append("FQ");
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
                                    SessionSend(session, "FQ");
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
                }
            }
        }

        // Process un-numbered frames
        public void ProcessFrame(TncDataFragment frame, AX25Packet p)
        {
            // Do nothing
        }

    }
}
