/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Linq;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;

namespace HTCommander.Controls
{
    public partial class TerminalTabUserControl : UserControl
    {
        private MainForm mainForm;
        public List<TerminalText> terminalTexts = new List<TerminalText>();
        public string TerminalLastDone = null;

        public class TerminalText
        {
            public bool outgoing;
            public string from;
            public string to;
            public string message;
            public bool done; // An end of line was received.

            public TerminalText(bool outgoing, string from, string to, string message, bool done)
            {
                this.outgoing = outgoing;
                this.from = from;
                this.to = to;
                this.message = message;
                this.done = done;
            }
        }

        public TerminalTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;
        }

        public void UpdateInfo()
        {
            /*
            if (mainForm == null) return;

            // Terminal
            terminalInputTextBox.Enabled = ((mainForm.radio.State == Radio.RadioState.Connected) && (mainForm.activeStationLock != null) && (mainForm.activeStationLock.StationType == StationInfoClass.StationTypes.Terminal));
            terminalSendButton.Enabled = ((mainForm.radio.State == Radio.RadioState.Connected) && (mainForm.activeStationLock != null) && (mainForm.activeStationLock.StationType == StationInfoClass.StationTypes.Terminal));
            terminalConnectButton.Enabled = (mainForm.radio.State == Radio.RadioState.Connected) && ((mainForm.activeStationLock == null) || (mainForm.activeStationLock.StationType == StationInfoClass.StationTypes.Terminal));
            terminalConnectButton.Text = ((mainForm.activeStationLock == null) || (mainForm.activeStationLock.StationType != StationInfoClass.StationTypes.Terminal)) ? "&Connect" : "&Disconnect";
            terminalConnectButton.Visible = mainForm.allowTransmit;
            terminalBottomPanel.Visible = mainForm.allowTransmit;

            // ActiveLockToStation
            if ((mainForm.activeStationLock == null) || (mainForm.activeStationLock.StationType != StationInfoClass.StationTypes.Terminal) || (string.IsNullOrEmpty(mainForm.activeStationLock.Name)))
            {
                terminalTitleLabel.Text = "Terminal";
            }
            else
            {
                terminalTitleLabel.Text = "Terminal - " + mainForm.activeStationLock.Name;
            }
            */
        }

        public bool ShowCallsign
        {
            get { return showCallsignToolStripMenuItem.Checked; }
            set { showCallsignToolStripMenuItem.Checked = value; }
        }

        public bool WordWrap
        {
            get { return wordWrapToolStripMenuItem.Checked; }
            set
            {
                wordWrapToolStripMenuItem.Checked = value;
                terminalTextBox.WordWrap = value;
            }
        }

        private void showCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm != null)
            {
                //mainForm.registry.WriteInt("TerminalShowCallsign", showCallsignToolStripMenuItem.Checked ? 1 : 0);
            }
            terminalTextBox.Clear();
            foreach (TerminalText terminalText in terminalTexts) { AppendTerminalString(terminalText); }
            terminalTextBox.SelectionStart = terminalTextBox.Text.Length;
            terminalTextBox.ScrollToCaret();
        }

        public delegate void AppendTerminalStringHandler(bool outgoing, string from, string to, string message, bool done);
        public void AppendTerminalString(bool outgoing, string from, string to, string message, bool done = true)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new AppendTerminalStringHandler(AppendTerminalString), outgoing, from, to, message, done); return; }

            TerminalText terminalText;
            if (terminalTexts.Count > 0)
            {
                terminalText = terminalTexts.Last();
                if ((terminalText.done == false) && (terminalText.from != null) && (terminalText.to != null) && (terminalText.from == from) && (terminalText.to == to))
                {
                    terminalText.message += message;
                    terminalText.done = done;
                    terminalTextBox.Rtf = TerminalLastDone;
                    AppendTerminalString(terminalText);
                    terminalTextBox.SelectionStart = terminalTextBox.Text.Length;
                    terminalTextBox.ScrollToCaret();
                    if (done) { TerminalLastDone = terminalTextBox.Rtf; }
                    return;
                }
            }

            terminalText = new TerminalText(outgoing, from, to, message, done);
            terminalTexts.Add(terminalText);
            AppendTerminalString(terminalText);
            terminalTextBox.SelectionStart = terminalTextBox.Text.Length;
            terminalTextBox.ScrollToCaret();
            if (done) { TerminalLastDone = terminalTextBox.Rtf; }
        }

        public void AppendTerminalString(TerminalText terminalText)
        {
            if (terminalTextBox.Text.Length != 0) { terminalTextBox.AppendText(Environment.NewLine); }
            if ((terminalText.to == null) || (terminalText.from == null))
            {
                AppendTerminalText(terminalText.message, Color.Yellow);
                return;
            }
            if (showCallsignToolStripMenuItem.Checked)
            {
                if (terminalText.outgoing) { AppendTerminalText(terminalText.to + " < ", Color.Green); } else { AppendTerminalText(terminalText.from + " > ", Color.Green); }
            }
            AppendTerminalText(terminalText.message, terminalText.outgoing ? Color.CornflowerBlue : Color.Gainsboro);
        }

        public void AppendTerminalText(string text, Color color)
        {
            if (InvokeRequired) { this.BeginInvoke(new Action<string, Color>(AppendTerminalText), text, color); return; }
            terminalTextBox.SelectionStart = terminalTextBox.TextLength;
            terminalTextBox.SelectionLength = 0;
            terminalTextBox.SelectionColor = color;
            terminalTextBox.AppendText(text);
            terminalTextBox.SelectionColor = terminalTextBox.ForeColor;
        }

        private void clearToolStripMenuItem_Click(object sender, EventArgs e)
        {
            terminalTexts.Clear();
            terminalTextBox.Clear();
            TerminalLastDone = null;
        }

        private void terminalClearButton_Click(object sender, EventArgs e)
        {
            terminalTexts.Clear();
            terminalTextBox.Clear();
            TerminalLastDone = null;
        }

        private void terminalInputTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == 13) { terminalSendButton_Click(this, null); e.Handled = true; return; }
        }

        private bool ParseCallsignWithId(string callsignWithId, out string xcallsign, out int xstationId)
        {
            xcallsign = null;
            xstationId = -1;
            if (callsignWithId == null) return false;
            string[] destSplit = callsignWithId.Split('-');
            if (destSplit.Length != 2) return false;
            int destStationId = -1;
            if (destSplit[0].Length < 3) return false;
            if (destSplit[0].Length > 6) return false;
            if (destSplit[1].Length < 1) return false;
            if (destSplit[1].Length > 2) return false;
            if (int.TryParse(destSplit[1], out destStationId) == false) return false;
            if ((destStationId < 0) || (destStationId > 15)) return false;
            xcallsign = destSplit[0];
            xstationId = destStationId;
            return true;
        }

        private void terminalSendButton_Click(object sender, EventArgs e)
        {
            /*
            if (mainForm == null) return;
            if (terminalInputTextBox.Text.Length == 0) return;
            //if (mainForm.activeStationLock == null) return;
            //if (mainForm.activeChannelIdLock == -1) return;
            //if (mainForm.activeStationLock.StationType != StationInfoClass.StationTypes.Terminal) return;
            if (terminalInputTextBox.Text.Length == 0) return;

            string destCallsign;
            int destStationId;
            string sendText = terminalInputTextBox.Text;
            terminalInputTextBox.Clear();

            if (mainForm.activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25)
            {
                // Raw AX.25 format
                if (ParseCallsignWithId(mainForm.activeStationLock.Callsign, out destCallsign, out destStationId) == false) return;
                AppendTerminalString(true, mainForm.callsign + "-" + mainForm.stationId, destCallsign + "-" + destStationId, sendText);
                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(AX25Address.GetAddress(destCallsign, destStationId));
                addresses.Add(AX25Address.GetAddress(mainForm.callsign, mainForm.stationId));
                AX25Packet packet = new AX25Packet(addresses, sendText, DateTime.Now);
                mainForm.radio.TransmitTncData(packet, mainForm.activeChannelIdLock);
            }
            else if (mainForm.activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25Compress)
            {
                // Raw AX.25 format + Deflate
                if (ParseCallsignWithId(mainForm.activeStationLock.Callsign, out destCallsign, out destStationId) == false) return;
                AppendTerminalString(true, mainForm.callsign + "-" + mainForm.stationId, destCallsign + "-" + destStationId, sendText);
                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(AX25Address.GetAddress(destCallsign, destStationId));
                addresses.Add(AX25Address.GetAddress(mainForm.callsign, mainForm.stationId));

                byte[] buffer1 = UTF8Encoding.Default.GetBytes(sendText);
                byte[] buffer2 = Utils.CompressBrotli(buffer1);
                byte[] buffer3 = Utils.CompressDeflate(buffer1);
                if ((buffer1.Length <= buffer2.Length) && (buffer1.Length <= buffer3.Length))
                {
                    AX25Packet packet = new AX25Packet(addresses, buffer1, DateTime.Now);
                    packet.pid = 241; // No compression, but compression is supported
                    mainForm.radio.TransmitTncData(packet, mainForm.activeChannelIdLock);
                }
                else if (buffer2.Length <= buffer3.Length) // Brotli is smaller
                {
                    AX25Packet packet = new AX25Packet(addresses, buffer2, DateTime.Now);
                    packet.pid = 242; // Compression applied
                    mainForm.radio.TransmitTncData(packet, mainForm.activeChannelIdLock);
                }
                else // Deflate is smaller
                {
                    AX25Packet packet = new AX25Packet(addresses, buffer3, DateTime.Now);
                    packet.pid = 243; // Compression applied
                    mainForm.radio.TransmitTncData(packet, mainForm.activeChannelIdLock);
                }
            }
            else if (mainForm.activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.APRS)
            {
                // APRS format
                if (ParseCallsignWithId(mainForm.activeStationLock.Callsign, out destCallsign, out destStationId) == false) return;
                string aprsAddr = ":" + mainForm.activeStationLock.Callsign;
                if (aprsAddr.EndsWith("-0")) { aprsAddr = aprsAddr.Substring(0, aprsAddr.Length - 2); }
                while (aprsAddr.Length < 10) { aprsAddr += " "; }
                aprsAddr += ":";
                AppendTerminalString(true, mainForm.callsign + "-" + mainForm.stationId, destCallsign + ((destStationId != 0) ? ("-" + destStationId) : ""), sendText);

                // Get the AX25 destination address
                AX25Address ax25dest = null;
                if (!string.IsNullOrEmpty(mainForm.activeStationLock.AX25Destination)) { ax25dest = AX25Address.GetAddress(mainForm.activeStationLock.AX25Destination); }
                if (ax25dest == null) { ax25dest = AX25Address.GetAddress(destCallsign, destStationId); }

                // Format the AX25 packet
                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(ax25dest);
                addresses.Add(AX25Address.GetAddress(mainForm.callsign, mainForm.stationId));
                int msgId = mainForm.GetNextAprsMessageId();
                AX25Packet packet = new AX25Packet(addresses, aprsAddr + sendText + "{" + msgId, DateTime.Now);
                packet.messageId = msgId;
                mainForm.aprsStack.ProcessOutgoing(packet, mainForm.activeChannelIdLock);
            }
            else if (mainForm.activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.X25Session)
            {
                // AX.25 Session
                if (mainForm.session.CurrentState == AX25Session.ConnectionState.CONNECTED)
                {
                    mainForm.session.Send(UTF8Encoding.UTF8.GetBytes(sendText + "\r"));
                    AppendTerminalString(true, mainForm.callsign + "-" + mainForm.stationId, mainForm.session.Addresses[0].ToString(), sendText);
                }
            }
            */
        }

        private void terminalMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            terminalTabContextMenuStrip.Show(terminalMenuPictureBox, e.Location);
        }

        private void wordWrapToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm != null)
            {
                //mainForm.registry.WriteInt("TerminalWordWrap", wordWrapToolStripMenuItem.Checked ? 1 : 0);
            }
            terminalTextBox.WordWrap = wordWrapToolStripMenuItem.Checked;
        }

        private void waitForConnectionToolStripMenuItem_Click(object sender, EventArgs e)
        {
            /*
            if (mainForm == null) return;
            if (mainForm.activeStationLock == null)
            {
                mainForm.activeChannelIdLock = mainForm.radio.Settings.channel_a;
                StationInfoClass station = new StationInfoClass();
                station.WaitForConnection = true;
                station.StationType = StationInfoClass.StationTypes.Terminal;
                station.TerminalProtocol = StationInfoClass.TerminalProtocols.X25Session;
                mainForm.activeStationLock = station;
                mainForm.UpdateInfo();
                //mainForm.UpdateRadioDisplay();
                terminalInputTextBox.Focus();
                AppendTerminalString(false, null, null, "Waiting for connection...");
            }
            */
        }

        private void terminalConnectButton_Click(object sender, EventArgs e)
        {
            /*
            if (mainForm == null) return;
            if (mainForm.activeStationLock == null)
            {
                int terminalStationCount = 0;
                foreach (StationInfoClass station in mainForm.stations)
                {
                    if (station.StationType == StationInfoClass.StationTypes.Terminal) { terminalStationCount++; }
                }

                if (terminalStationCount == 0)
                {
                    AddStationForm form = new AddStationForm(mainForm);
                    form.FixStationType(StationInfoClass.StationTypes.Terminal);
                    if (form.ShowDialog(mainForm) == DialogResult.OK)
                    {
                        StationInfoClass station = form.SerializeToObject();
                        mainForm.stations.Add(station);
                        mainForm.UpdateStations();
                        mainForm.ActiveLockToStation(station);
                        terminalInputTextBox.Focus();
                    }
                }
                else
                {
                    ActiveStationSelectorForm form = new ActiveStationSelectorForm(mainForm, StationInfoClass.StationTypes.Terminal);
                    DialogResult r = form.ShowDialog(mainForm);
                    if (r == DialogResult.OK)
                    {
                        if (form.selectedStation != null)
                        {
                            mainForm.ActiveLockToStation(form.selectedStation);
                            terminalInputTextBox.Focus();
                        }
                    }
                    else if (r == DialogResult.Yes)
                    {
                        AddStationForm aform = new AddStationForm(mainForm);
                        aform.FixStationType(StationInfoClass.StationTypes.Terminal);
                        if (aform.ShowDialog(mainForm) == DialogResult.OK)
                        {
                            StationInfoClass station = aform.SerializeToObject();
                            mainForm.stations.Add(station);
                            mainForm.UpdateStations();
                            mainForm.ActiveLockToStation(station);
                            terminalInputTextBox.Focus();
                        }
                    }
                }
            }
            else
            {
                if (mainForm.session.CurrentState != AX25Session.ConnectionState.DISCONNECTED)
                {
                    // Do a soft-disconnect
                    mainForm.session.Disconnect();
                }
                else
                {
                    mainForm.ActiveLockToStation(null);
                }
            }
            */
        }

        private void terminalFileTransferCancelButton_Click(object sender, EventArgs e)
        {
            //mainForm?.yappTransfer?.CancelTransfer();
        }

        public enum TerminalFileTransferStates
        {
            Idle,
            Sending,
            Receiving
        }

        public void UpdateFileTransferProgress(TerminalFileTransferStates state, string filename, int totalSize, int currentPosition)
        {
            if (InvokeRequired) { BeginInvoke(new Action<TerminalFileTransferStates, string, int, int>(UpdateFileTransferProgress), state, filename, totalSize, currentPosition); return; }
            terminalFileTransferProgressBar.Maximum = (totalSize > 0) ? totalSize : 1;
            terminalFileTransferProgressBar.Value = (Math.Min(currentPosition, terminalFileTransferProgressBar.Maximum));
            if (state == TerminalFileTransferStates.Sending)
            {
                terminalFileTransferStatusLabel.Text = "Sending: " + filename;
            }
            else if (state == TerminalFileTransferStates.Receiving)
            {
                terminalFileTransferStatusLabel.Text = "Receiving: " + filename;
            }
            else
            {
                terminalFileTransferStatusLabel.Text = "File Transfer";
            }
            if ((terminalFileTransferPanel.Visible == false) && (state != TerminalFileTransferStates.Idle)) { terminalTextBox.ScrollToCaret(); }
            terminalFileTransferPanel.Visible = (state != TerminalFileTransferStates.Idle);
        }

        public void FocusInput()
        {
            terminalInputTextBox.Focus();
        }
    }
}