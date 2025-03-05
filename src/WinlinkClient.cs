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

using HTCommander.radio;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

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
                    StringBuilder sb = new StringBuilder();
                    sb.Append("[HTCmd-" + GetVersion() + "-B2FHM$]\r");
                    if (session.sessionState.ContainsKey("WinlinkAUth"))
                    {
                        string authResponse = WinlinkSecurity.SecureLoginResponse((string)session.sessionState["WinlinkAUth"], parent.winlinkPassword);
                        if (!string.IsNullOrEmpty(parent.winlinkPassword)) { sb.Append(";PR: " + authResponse + "\r"); }
                        StateMessage("Authenticating...");
                    }
                    SessionSend(session, sb.ToString());
                }
                else
                {
                    int i = str.IndexOf(' ');
                    if (i > 0)
                    {
                        string key = str.Substring(0, i).ToUpper();
                        string value = str.Substring(i + 1);

                        if ((key == ";PQ:") && (!string.IsNullOrEmpty(parent.winlinkPassword)))
                        {   // Winlink Authentication Request
                            session.sessionState["WinlinkAUth"] = value;
                        }
                        else if (key == "FS") // "FS YY"
                        {   // Winlink Mail Transfer Approvals

                        }
                        else if (key == "FF")
                        {   // Winlink Session Close
                            SessionSend(session, "FQ");
                        }
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
