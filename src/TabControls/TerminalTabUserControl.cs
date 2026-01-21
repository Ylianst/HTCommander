/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Linq;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
using System.Collections.Generic;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class TerminalTabUserControl : UserControl
    {
        private DataBrokerClient broker;
        private bool _showDetach = false;
        private List<int> connectedRadios = new List<int>();
        private Dictionary<int, RadioLockState> lockStates = new Dictionary<int, RadioLockState>();
        private StationInfoClass connectedStation = null;
        private int connectedRadioId = -1;
        private int nextAprsMessageId = 1;

        /// <summary>
        /// Gets or sets whether the "Detach..." menu item is visible.
        /// </summary>
        [System.ComponentModel.Category("Behavior")]
        [System.ComponentModel.Description("Gets or sets whether the Detach menu item is visible.")]
        [System.ComponentModel.DefaultValue(false)]
        public bool ShowDetach
        {
            get { return _showDetach; }
            set
            {
                _showDetach = value;
                if (detachToolStripMenuItem != null)
                {
                    detachToolStripMenuItem.Visible = value;
                    toolStripMenuItemDetachSeparator.Visible = value;
                }
            }
        }
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

            broker = new DataBrokerClient();

            // Subscribe to connected radios and lock state to update connect button
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);

            // Subscribe to UniqueDataFrame to receive incoming packets with "Terminal" usage
            broker.Subscribe(1, "UniqueDataFrame", OnUniqueDataFrame);

            // Set initial button state (disabled until we know radio state)
            terminalConnectButton.Text = "&Connect";
            terminalConnectButton.Enabled = false;

            // Load saved settings from DataBroker
            LoadSavedSettings();

            broker.LogInfo("[TerminalTab] Terminal tab initialized");
        }

        private void LoadSavedSettings()
        {
            // Load Show Callsign setting (default: false)
            bool showCallsign = broker.GetValue<bool>(0, "TerminalShowCallsign", false);
            showCallsignToolStripMenuItem.Checked = showCallsign;

            // Load Word Wrap setting (default: false)
            bool wordWrap = broker.GetValue<bool>(0, "TerminalWordWrap", false);
            wordWrapToolStripMenuItem.Checked = wordWrap;
            terminalTextBox.WordWrap = wordWrap;
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (data == null) return;

            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ProcessConnectedRadiosChanged(data)));
            }
            else
            {
                ProcessConnectedRadiosChanged(data);
            }
        }

        private void ProcessConnectedRadiosChanged(object data)
        {
            connectedRadios.Clear();

            if (data is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var itemType = item.GetType();
                    int? deviceId = (int?)itemType.GetProperty("DeviceId")?.GetValue(item);
                    if (deviceId.HasValue)
                    {
                        connectedRadios.Add(deviceId.Value);
                    }
                }
            }

            UpdateConnectButtonState();
        }

        private void OnLockStateChanged(int deviceId, string name, object data)
        {
            if (!(data is RadioLockState lockState)) return;

            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ProcessLockStateChanged(deviceId, lockState)));
            }
            else
            {
                ProcessLockStateChanged(deviceId, lockState);
            }
        }

        private void ProcessLockStateChanged(int deviceId, RadioLockState lockState)
        {
            lockStates[deviceId] = lockState;
            UpdateConnectButtonState();
        }

        private void UpdateConnectButtonState()
        {
            // Handle single radio case
            if (connectedRadios.Count == 1)
            {
                int radioId = connectedRadios[0];
                lockStates.TryGetValue(radioId, out RadioLockState lockState);

                if (lockState != null && lockState.IsLocked && lockState.Usage == "Terminal")
                {
                    // Radio is locked to Terminal - show Disconnect
                    terminalConnectButton.Text = "&Disconnect";
                    terminalConnectButton.Enabled = true;
                    terminalInputTextBox.Enabled = true;
                    terminalSendButton.Enabled = true;
                    terminalTitleLabel.Text = "Terminal - Connected";
                }
                else if (lockState == null || !lockState.IsLocked)
                {
                    // Radio is not locked - show Connect
                    terminalConnectButton.Text = "&Connect";
                    terminalConnectButton.Enabled = true;
                    terminalInputTextBox.Enabled = false;
                    terminalSendButton.Enabled = false;
                    terminalTitleLabel.Text = "Terminal";
                }
                else
                {
                    // Radio is locked to something else - disable
                    terminalConnectButton.Text = "&Connect";
                    terminalConnectButton.Enabled = false;
                    terminalInputTextBox.Enabled = false;
                    terminalSendButton.Enabled = false;
                    terminalTitleLabel.Text = "Terminal";
                }
            }
            // Handle multi-radio cases (for now, just disable)
            else if (connectedRadios.Count > 1)
            {
                // Check if any radio is locked to Terminal
                bool hasTerminalLock = false;
                int terminalRadioId = -1;
                foreach (var radioId in connectedRadios)
                {
                    if (lockStates.TryGetValue(radioId, out RadioLockState lockState) && lockState.IsLocked && lockState.Usage == "Terminal")
                    {
                        hasTerminalLock = true;
                        terminalRadioId = radioId;
                        break;
                    }
                }

                if (hasTerminalLock)
                {
                    terminalConnectButton.Text = "&Disconnect";
                    terminalConnectButton.Enabled = true;
                    terminalInputTextBox.Enabled = true;
                    terminalSendButton.Enabled = true;
                    terminalTitleLabel.Text = "Terminal - Connected";
                }
                else
                {
                    // Check if any radio is available (not locked)
                    bool hasAvailableRadio = false;
                    foreach (var radioId in connectedRadios)
                    {
                        if (!lockStates.TryGetValue(radioId, out RadioLockState lockState) || !lockState.IsLocked)
                        {
                            hasAvailableRadio = true;
                            break;
                        }
                    }

                    terminalConnectButton.Text = "&Connect";
                    terminalConnectButton.Enabled = hasAvailableRadio;
                    terminalInputTextBox.Enabled = false;
                    terminalSendButton.Enabled = false;
                    terminalTitleLabel.Text = "Terminal";
                }
            }
            else
            {
                // No radios connected - disable
                terminalConnectButton.Text = "&Connect";
                terminalConnectButton.Enabled = false;
                terminalInputTextBox.Enabled = false;
                terminalSendButton.Enabled = false;
                terminalTitleLabel.Text = "Terminal";
            }
        }

        private void showCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Save setting with store: true for persistence across application restarts
            broker.Dispatch(0, "TerminalShowCallsign", showCallsignToolStripMenuItem.Checked, store: true);
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

        private void terminalInputTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == 13) { terminalSendButton_Click(this, null); e.Handled = true; return; }
        }

        private void terminalSendButton_Click(object sender, EventArgs e)
        {
            if (terminalInputTextBox.Text.Length == 0) return;
            if (connectedStation == null || connectedRadioId <= 0) return;

            string sendText = terminalInputTextBox.Text;
            terminalInputTextBox.Clear();

            // Send based on terminal protocol
            if (connectedStation.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25)
            {
                SendRawX25Packet(sendText);
            }
            else if (connectedStation.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25Compress)
            {
                SendRawX25CompressPacket(sendText);
            }
            else if (connectedStation.TerminalProtocol == StationInfoClass.TerminalProtocols.APRS)
            {
                SendAprsPacket(sendText);
            }
            else
            {
                // For other protocols, just dispatch to the radio for now
                broker.Dispatch(connectedRadioId, "TerminalSend", sendText, store: false);
            }
        }

        /// <summary>
        /// Sends a RawX25 packet with the given text as UTF-8 encoded data.
        /// </summary>
        private void SendRawX25Packet(string text)
        {
            if (connectedStation == null || connectedRadioId <= 0) return;

            // Get our callsign from settings (should be in format "CALLSIGN-ID")
            string myCallsignWithId = broker.GetValue<string>(0, "Callsign", "N0CALL-0");

            // Parse our callsign to get callsign and station ID
            string myCallsign;
            int myStationId;
            if (!Utils.ParseCallsignWithId(myCallsignWithId, out myCallsign, out myStationId))
            {
                // If parsing fails, use the whole string as callsign with ID 0
                myCallsign = myCallsignWithId;
                myStationId = 0;
            }

            // Parse the destination callsign to get callsign and station ID
            string destCallsign;
            int destStationId;
            if (!Utils.ParseCallsignWithId(connectedStation.Callsign, out destCallsign, out destStationId))
            {
                // If parsing fails, use the whole string as callsign with ID 0
                destCallsign = connectedStation.Callsign;
                destStationId = 0;
            }

            // Create addresses: destination (remote station) and source (our callsign)
            List<AX25Address> addresses = new List<AX25Address>();
            addresses.Add(AX25Address.GetAddress(destCallsign, destStationId)); // Destination
            addresses.Add(AX25Address.GetAddress(myCallsign, myStationId)); // Source

            // Encode text as UTF-8
            byte[] data = Encoding.UTF8.GetBytes(text);

            // Create U_FRAME_UI packet
            AX25Packet packet = new AX25Packet(addresses, data, DateTime.Now);
            packet.type = AX25Packet.FrameType.U_FRAME_UI;
            packet.pid = 240; // No layer 3 protocol

            // Get the channel ID from the lock state
            int channelId = -1;
            int regionId = -1;
            if (lockStates.TryGetValue(connectedRadioId, out RadioLockState lockState))
            {
                channelId = lockState.ChannelId;
                regionId = lockState.RegionId;
            }

            // Send the packet via TransmitDataFrame
            var txData = new TransmitDataFrameData
            {
                Packet = packet,
                ChannelId = channelId,
                RegionId = regionId
            };
            broker.Dispatch(connectedRadioId, "TransmitDataFrame", txData, store: false);

            // Display the sent message in the terminal
            AppendTerminalString(true, myCallsignWithId, connectedStation.Callsign, text);

            broker.LogInfo("[TerminalTab] Sent RawX25 packet to " + connectedStation.Callsign);
        }

        /// <summary>
        /// Sends a RawX25Compress packet with the given text as UTF-8 encoded data with optional compression.
        /// Uses pid 241 for no compression, 242 for Brotli compression, 243 for Deflate compression.
        /// </summary>
        private void SendRawX25CompressPacket(string text)
        {
            if (connectedStation == null || connectedRadioId <= 0) return;

            // Get our callsign from settings (should be in format "CALLSIGN-ID")
            string myCallsignWithId = broker.GetValue<string>(0, "Callsign", "N0CALL-0");

            // Parse our callsign to get callsign and station ID
            string myCallsign;
            int myStationId;
            if (!Utils.ParseCallsignWithId(myCallsignWithId, out myCallsign, out myStationId))
            {
                myCallsign = myCallsignWithId;
                myStationId = 0;
            }

            // Parse the destination callsign to get callsign and station ID
            string destCallsign;
            int destStationId;
            if (!Utils.ParseCallsignWithId(connectedStation.Callsign, out destCallsign, out destStationId))
            {
                return; // RawX25Compress requires valid callsign format
            }

            // Create addresses: destination (remote station) and source (our callsign)
            List<AX25Address> addresses = new List<AX25Address>();
            addresses.Add(AX25Address.GetAddress(destCallsign, destStationId)); // Destination
            addresses.Add(AX25Address.GetAddress(myCallsign, myStationId)); // Source

            // Encode text as UTF-8
            byte[] buffer1 = Encoding.UTF8.GetBytes(text);
            byte[] buffer2 = Utils.CompressBrotli(buffer1);
            byte[] buffer3 = Utils.CompressDeflate(buffer1);

            // Get the channel ID from the lock state
            int channelId = -1;
            int regionId = -1;
            if (lockStates.TryGetValue(connectedRadioId, out RadioLockState lockState))
            {
                channelId = lockState.ChannelId;
                regionId = lockState.RegionId;
            }

            AX25Packet packet;
            if ((buffer1.Length <= buffer2.Length) && (buffer1.Length <= buffer3.Length))
            {
                // No compression is smallest
                packet = new AX25Packet(addresses, buffer1, DateTime.Now);
                packet.type = AX25Packet.FrameType.U_FRAME_UI;
                packet.pid = 241; // No compression, but compression is supported
            }
            else if (buffer2.Length <= buffer3.Length)
            {
                // Brotli is smallest
                packet = new AX25Packet(addresses, buffer2, DateTime.Now);
                packet.type = AX25Packet.FrameType.U_FRAME_UI;
                packet.pid = 242; // Brotli compression applied
            }
            else
            {
                // Deflate is smallest
                packet = new AX25Packet(addresses, buffer3, DateTime.Now);
                packet.type = AX25Packet.FrameType.U_FRAME_UI;
                packet.pid = 243; // Deflate compression applied
            }

            // Send the packet via TransmitDataFrame
            var txData = new TransmitDataFrameData
            {
                Packet = packet,
                ChannelId = channelId,
                RegionId = regionId
            };
            broker.Dispatch(connectedRadioId, "TransmitDataFrame", txData, store: false);

            // Display the sent message in the terminal
            AppendTerminalString(true, myCallsignWithId, connectedStation.Callsign, text);

            broker.LogInfo("[TerminalTab] Sent RawX25Compress packet (pid=" + packet.pid + ") to " + connectedStation.Callsign);
        }

        /// <summary>
        /// Gets the next APRS message ID, cycling from 1 to 999.
        /// </summary>
        private int GetNextAprsMessageId()
        {
            int msgId = nextAprsMessageId++;
            if (nextAprsMessageId > 999) { nextAprsMessageId = 1; }
            return msgId;
        }

        /// <summary>
        /// Sends an APRS message packet with the given text.
        /// APRS message format: :CALLSIGN  :message{msgId
        /// </summary>
        private void SendAprsPacket(string text)
        {
            if (connectedStation == null || connectedRadioId <= 0) return;

            // Get our callsign from settings (should be in format "CALLSIGN-ID")
            string myCallsignWithId = broker.GetValue<string>(0, "Callsign", "N0CALL-0");

            // Parse our callsign to get callsign and station ID
            string myCallsign;
            int myStationId;
            if (!Utils.ParseCallsignWithId(myCallsignWithId, out myCallsign, out myStationId))
            {
                myCallsign = myCallsignWithId;
                myStationId = 0;
            }

            // Parse the destination callsign to get callsign and station ID
            string destCallsign;
            int destStationId;
            if (!Utils.ParseCallsignWithId(connectedStation.Callsign, out destCallsign, out destStationId))
            {
                return; // APRS requires valid callsign format
            }

            // Build APRS address: pad to 9 characters then add ":"
            string aprsAddr = ":" + connectedStation.Callsign;
            if (aprsAddr.EndsWith("-0")) { aprsAddr = aprsAddr.Substring(0, aprsAddr.Length - 2); }
            while (aprsAddr.Length < 10) { aprsAddr += " "; }
            aprsAddr += ":";

            // Display in terminal (format callsign without -0 suffix)
            string displayDestCallsign = destCallsign + ((destStationId != 0) ? ("-" + destStationId) : "");
            AppendTerminalString(true, myCallsign + "-" + myStationId, displayDestCallsign, text);

            // Get the AX25 destination address from station settings, or use the destination callsign
            AX25Address ax25dest = null;
            if (!string.IsNullOrEmpty(connectedStation.AX25Destination))
            {
                ax25dest = AX25Address.GetAddress(connectedStation.AX25Destination);
            }
            if (ax25dest == null)
            {
                ax25dest = AX25Address.GetAddress(destCallsign, destStationId);
            }

            // Create addresses: destination and source
            List<AX25Address> addresses = new List<AX25Address>();
            addresses.Add(ax25dest); // Destination
            addresses.Add(AX25Address.GetAddress(myCallsign, myStationId)); // Source

            // Get the next message ID and create the APRS message
            int msgId = GetNextAprsMessageId();
            string aprsMessage = aprsAddr + text + "{" + msgId;

            // Create U_FRAME_UI packet
            AX25Packet packet = new AX25Packet(addresses, aprsMessage, DateTime.Now);
            packet.type = AX25Packet.FrameType.U_FRAME_UI;
            packet.pid = 240; // No layer 3 protocol
            packet.messageId = msgId;

            // Get the channel ID from the lock state
            int channelId = -1;
            int regionId = -1;
            if (lockStates.TryGetValue(connectedRadioId, out RadioLockState lockState))
            {
                channelId = lockState.ChannelId;
                regionId = lockState.RegionId;
            }

            // Send the packet via TransmitDataFrame
            var txData = new TransmitDataFrameData
            {
                Packet = packet,
                ChannelId = channelId,
                RegionId = regionId
            };
            broker.Dispatch(connectedRadioId, "TransmitDataFrame", txData, store: false);

            broker.LogInfo("[TerminalTab] Sent APRS packet (msgId=" + msgId + ") to " + connectedStation.Callsign);
        }

        /// <summary>
        /// Handles incoming UniqueDataFrame events and processes packets for Terminal usage.
        /// </summary>
        private void OnUniqueDataFrame(int deviceId, string name, object data)
        {
            if (!(data is TncDataFragment frame)) return;

            // Only process frames with "Terminal" usage
            if (frame.usage != "Terminal") return;

            // Only process incoming frames
            if (!frame.incoming) return;

            // Decode the AX.25 packet
            AX25Packet packet = AX25Packet.DecodeAX25Packet(frame);
            if (packet == null) return;

            // Process based on terminal protocol
            if (connectedStation != null)
            {
                if (connectedStation.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25)
                {
                    ProcessRawX25Packet(packet);
                }
                else if (connectedStation.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25Compress)
                {
                    ProcessRawX25CompressPacket(packet);
                }
                else if (connectedStation.TerminalProtocol == StationInfoClass.TerminalProtocols.APRS)
                {
                    ProcessAprsPacket(packet);
                }
            }
        }

        /// <summary>
        /// Processes an incoming RawX25 packet and displays the data in the terminal.
        /// </summary>
        private void ProcessRawX25Packet(AX25Packet packet)
        {
            if (packet == null) return;

            // Get the source callsign
            string fromCallsign = "UNKNOWN";
            if (packet.addresses != null && packet.addresses.Count >= 2)
            {
                fromCallsign = packet.addresses[1].ToString(); // Source is second address
            }

            // Get our callsign
            string myCallsign = broker.GetValue<string>(0, "Callsign", "N0CALL");

            // Decode the data as UTF-8 text
            string text = "";
            if (packet.data != null && packet.data.Length > 0)
            {
                text = Encoding.UTF8.GetString(packet.data);
            }
            else if (!string.IsNullOrEmpty(packet.dataStr))
            {
                text = packet.dataStr;
            }

            if (!string.IsNullOrEmpty(text))
            {
                // Display the received message in the terminal
                AppendTerminalString(false, fromCallsign, myCallsign, text);
            }
        }

        /// <summary>
        /// Processes an incoming RawX25Compress packet and displays the data in the terminal.
        /// Handles decompression based on pid: 241 = no compression, 242 = Brotli, 243 = Deflate.
        /// </summary>
        private void ProcessRawX25CompressPacket(AX25Packet packet)
        {
            if (packet == null) return;

            // Get the source callsign
            string fromCallsign = "UNKNOWN";
            if (packet.addresses != null && packet.addresses.Count >= 2)
            {
                fromCallsign = packet.addresses[1].ToString(); // Source is second address
            }

            // Get our callsign
            string myCallsign = broker.GetValue<string>(0, "Callsign", "N0CALL");

            // Decode the data based on compression type (pid)
            string text = "";
            if (packet.data != null && packet.data.Length > 0)
            {
                try
                {
                    byte[] decompressedData;
                    switch (packet.pid)
                    {
                        case 241:
                            // No compression
                            decompressedData = packet.data;
                            break;
                        case 242:
                            // Brotli compression
                            decompressedData = Utils.DecompressBrotli(packet.data);
                            break;
                        case 243:
                            // Deflate compression
                            decompressedData = Utils.DecompressDeflate(packet.data);
                            break;
                        default:
                            // Unknown pid, try to interpret as plain text
                            decompressedData = packet.data;
                            break;
                    }
                    text = Encoding.UTF8.GetString(decompressedData);
                }
                catch (Exception)
                {
                    // Decompression failed, try to interpret raw data as text
                    text = Encoding.UTF8.GetString(packet.data);
                }
            }
            else if (!string.IsNullOrEmpty(packet.dataStr))
            {
                text = packet.dataStr;
            }

            if (!string.IsNullOrEmpty(text))
            {
                // Display the received message in the terminal
                AppendTerminalString(false, fromCallsign, myCallsign, text);
            }
        }

        /// <summary>
        /// Processes an incoming APRS packet and displays the message in the terminal.
        /// APRS message format: :CALLSIGN  :message{msgId
        /// </summary>
        private void ProcessAprsPacket(AX25Packet packet)
        {
            if (packet == null) return;

            // Get the source callsign from AX.25 addresses
            string fromCallsign = "UNKNOWN";
            if (packet.addresses != null && packet.addresses.Count >= 2)
            {
                fromCallsign = packet.addresses[1].CallSignWithId; // Source is second address
            }

            // Get our callsign
            string myCallsign = broker.GetValue<string>(0, "Callsign", "N0CALL");

            // Get the APRS message data
            string aprsData = packet.dataStr;
            if (string.IsNullOrEmpty(aprsData) && packet.data != null && packet.data.Length > 0)
            {
                aprsData = Encoding.UTF8.GetString(packet.data);
            }

            if (string.IsNullOrEmpty(aprsData)) return;

            // Parse APRS message format: :CALLSIGN  :message{msgId
            // The message starts with ":" followed by 9-character padded callsign, then ":"
            if (aprsData.Length < 11 || aprsData[0] != ':') return;

            // Extract the destination callsign (first 9 characters after ":")
            string destCallsign = aprsData.Substring(1, 9).Trim();

            // Skip the ":" separator after the callsign
            if (aprsData[10] != ':') return;

            // Extract the message content (after the 10th character)
            string messageContent = aprsData.Substring(11);

            // Strip off the message ID suffix if present (format: message{msgId)
            int msgIdIndex = messageContent.LastIndexOf('{');
            if (msgIdIndex >= 0)
            {
                messageContent = messageContent.Substring(0, msgIdIndex);
            }

            // Also handle auth code if present (format: message}authCode)
            int authIndex = messageContent.LastIndexOf('}');
            if (authIndex >= 0)
            {
                messageContent = messageContent.Substring(0, authIndex);
            }

            if (!string.IsNullOrEmpty(messageContent))
            {
                // Display the received message in the terminal
                AppendTerminalString(false, fromCallsign, myCallsign, messageContent);
            }
        }

        /// <summary>
        /// Gets the radio ID that is currently locked to Terminal usage.
        /// </summary>
        private int GetActiveTerminalRadioId()
        {
            foreach (var radioId in connectedRadios)
            {
                if (lockStates.TryGetValue(radioId, out RadioLockState lockState) && lockState.IsLocked && lockState.Usage == "Terminal")
                {
                    return radioId;
                }
            }
            return -1;
        }

        /// <summary>
        /// Gets the first available (unlocked) radio ID.
        /// </summary>
        private int GetAvailableRadioId()
        {
            foreach (var radioId in connectedRadios)
            {
                if (!lockStates.TryGetValue(radioId, out RadioLockState lockState) || !lockState.IsLocked)
                {
                    return radioId;
                }
            }
            return -1;
        }

        private void terminalMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            terminalTabContextMenuStrip.Show(terminalMenuPictureBox, e.Location);
        }

        private void wordWrapToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Save setting with store: true for persistence across application restarts
            broker.Dispatch(0, "TerminalWordWrap", wordWrapToolStripMenuItem.Checked, store: true);
            terminalTextBox.WordWrap = wordWrapToolStripMenuItem.Checked;
        }

        private void waitForConnectionToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // TODO: Implement wait for connection functionality through DataBroker
            int radioId = GetAvailableRadioId();
            if (radioId > 0)
            {
                // Get the current region from HtStatus
                RadioHtStatus htStatus = broker.GetValue<RadioHtStatus>(radioId, "HtStatus", null);
                int regionId = htStatus?.curr_region ?? 0;

                // Get the current channel from Settings
                RadioSettings settings = broker.GetValue<RadioSettings>(radioId, "Settings", null);
                int channelId = settings?.channel_a ?? 0;

                // Lock the radio to Terminal usage with the current region and channel
                var lockData = new SetLockData
                {
                    Usage = "Terminal",
                    RegionId = regionId,
                    ChannelId = channelId
                };
                broker.Dispatch(radioId, "SetLock", lockData, store: false);
                AppendTerminalString(false, null, null, "Waiting for connection...");
            }
        }

        private void terminalConnectButton_Click(object sender, EventArgs e)
        {
            int activeRadioId = GetActiveTerminalRadioId();

            if (activeRadioId > 0)
            {
                // We have an active Terminal connection - disconnect (unlock the radio)
                var unlockData = new SetUnlockData { Usage = "Terminal" };
                broker.Dispatch(activeRadioId, "SetUnlock", unlockData, store: false);
                broker.LogInfo("[TerminalTab] Disconnecting from radio " + activeRadioId);

                // Clear the connected station and radio references
                connectedStation = null;
                connectedRadioId = -1;
            }
            else
            {
                // No active connection - check for available radios first
                int availableRadioId = GetAvailableRadioId();
                if (availableRadioId <= 0)
                {
                    MessageBox.Show(this, "No available radio to connect.", "Terminal", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // Get stations from DataBroker and count terminal stations
                List<StationInfoClass> stations = broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());
                int terminalStationCount = 0;
                foreach (StationInfoClass station in stations)
                {
                    if (station.StationType == StationInfoClass.StationTypes.Terminal) { terminalStationCount++; }
                }

                if (terminalStationCount == 0)
                {
                    // No terminal stations - show AddStationForm to create one
                    AddStationForm form = new AddStationForm();
                    form.FixStationType(StationInfoClass.StationTypes.Terminal);
                    if (form.ShowDialog(this) == DialogResult.OK)
                    {
                        StationInfoClass station = form.SerializeToObject();
                        stations.Add(station);
                        broker.Dispatch(0, "Stations", stations, store: true);
                        ActiveLockToStation(availableRadioId, station);
                        terminalInputTextBox.Focus();
                    }
                }
                else
                {
                    // Has terminal stations - show ActiveStationSelectorForm to select one
                    ActiveStationSelectorForm form = new ActiveStationSelectorForm(StationInfoClass.StationTypes.Terminal);
                    DialogResult r = form.ShowDialog(this);
                    if (r == DialogResult.OK)
                    {
                        if (form.selectedStation != null)
                        {
                            ActiveLockToStation(availableRadioId, form.selectedStation);
                            terminalInputTextBox.Focus();
                        }
                    }
                    else if (r == DialogResult.Yes)
                    {
                        // User clicked "New" button - show AddStationForm
                        AddStationForm aform = new AddStationForm();
                        aform.FixStationType(StationInfoClass.StationTypes.Terminal);
                        if (aform.ShowDialog(this) == DialogResult.OK)
                        {
                            StationInfoClass station = aform.SerializeToObject();
                            stations.Add(station);
                            broker.Dispatch(0, "Stations", stations, store: true);
                            ActiveLockToStation(availableRadioId, station);
                            terminalInputTextBox.Focus();
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Locks the radio to Terminal usage and sets up connection to the specified station.
        /// </summary>
        private void ActiveLockToStation(int radioId, StationInfoClass station)
        {
            if (station == null || radioId <= 0) return;

            // Store the connected station and radio references
            connectedStation = station;
            connectedRadioId = radioId;

            // Get the current region from HtStatus
            RadioHtStatus htStatus = broker.GetValue<RadioHtStatus>(radioId, "HtStatus", null);
            int regionId = htStatus?.curr_region ?? 0;

            // Look up the channel ID from the channel name
            int channelId = -1;
            if (!string.IsNullOrEmpty(station.Channel))
            {
                RadioChannelInfo[] channels = broker.GetValue<RadioChannelInfo[]>(radioId, "Channels", null);
                if (channels != null)
                {
                    for (int i = 0; i < channels.Length; i++)
                    {
                        if (channels[i] != null && channels[i].name_str == station.Channel)
                        {
                            channelId = i;
                            break;
                        }
                    }
                }
            }

            // If no channel found, use the current channel
            if (channelId < 0)
            {
                RadioSettings settings = broker.GetValue<RadioSettings>(radioId, "Settings", null);
                channelId = settings?.channel_a ?? 0;
            }

            // Lock the radio to Terminal usage with the specific region and channel
            var lockData = new SetLockData
            {
                Usage = "Terminal",
                RegionId = regionId,
                ChannelId = channelId
            };
            broker.Dispatch(radioId, "SetLock", lockData, store: false);

            // Dispatch station info to the radio for connection
            broker.Dispatch(radioId, "TerminalStation", station, store: false);

            broker.LogInfo("[TerminalTab] Connecting to station " + station.Callsign + " on radio " + radioId + " (Region: " + regionId + ", Channel: " + channelId + ")");
        }

        private void terminalFileTransferCancelButton_Click(object sender, EventArgs e)
        {
            int radioId = GetActiveTerminalRadioId();
            if (radioId > 0)
            {
                broker.Dispatch(radioId, "TerminalCancelTransfer", null, store: false);
            }
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

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<TerminalTabUserControl>("Terminal");
            form.Show();
        }
    }
}
