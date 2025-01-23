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
using System.Linq;
using System.Text;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using GMap.NET.MapProviders;
using GMap.NET.WindowsForms;
using GMap.NET.WindowsForms.Markers;
using GMap.NET;
using aprsparser;
using static HTCommander.Radio;

namespace HTCommander
{
    public partial class MainForm : Form
    {
        static public MainForm g_MainForm = null;
        public Radio radio = new Radio();
        public RadioChannelControl[] channelControls = null;
        public RadioHtStatusForm radioHtStatusForm = null;
        public RadioSettingsForm radioSettingsForm = null;
        public RadioChannelForm radioChannelForm = null;
        public RadioVolumeForm radioVolumeForm = null;
        public AprsDetailsForm aprsDetailsForm = null;
        public BTActivateForm bluetoothActivateForm = null;
        public AprsConfigurationForm aprsConfigurationForm = null;
        public int vfo2LastChannelId = -1;
        public int nextAprsMessageId = 1;
        public RegistryHelper registry = new RegistryHelper("HTCommander");
        public FileStream debugFile = null;
        public FileStream AprsFile = null;
        public string callsign;
        public int stationId;
        public bool allowTransmit;
        public string appTitle;
        public Dictionary<string, List<AX25Address>> aprsRoutes;
        public string aprsSelectedRoute;
        public ChatMessage selectedAprsMessage;
        public GMapOverlay mapMarkersOverlay = new GMapOverlay("AprsMarkers");
        public bool previewMode = false;
        public CompatibleDevice[] devices = null;
        public List<MapLocationForm> mapLocationForms = new List<MapLocationForm>();
        public bool bluetoothEnabled = false;
        public int aprsChannel = -1;
        public bool showAllChannels = false;

        public static Image GetImage(int i) { return g_MainForm.mainImageList.Images[i]; }

        public MainForm(string[] args)
        {
            foreach (string arg in args) { if (string.Compare(arg, "-preview", true) == 0) { previewMode = true; } }

            g_MainForm = this;
            InitializeComponent();
        }

        private void MainForm_Load(object sender, EventArgs e)
        {
            Program.BlockBoxEvent("MainForm_Load");

            appTitle = this.Text;
            this.SuspendLayout();
            radio.DebugMessage += Radio_DebugMessage;
            radio.OnInfoUpdate += Radio_InfoUpdate;
            radio.OnDataFrame += Radio_OnDataFrame;
            mainTabControl.SelectedTab = aprsTabPage;
            mapControl.MapProvider = GMapProviders.OpenStreetMap;
            mapControl.ShowCenter = false;
            mapControl.MinZoom = 3;
            mapControl.MaxZoom = 20;
            mapControl.CanDragMap = true;
            mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            mapControl.IgnoreMarkerOnMouseWheel = true; // Optional, depending on marker usage
            mapControl.DragButton = MouseButtons.Left; // Set the mouse button for dragging

            if (double.TryParse(registry.ReadString("MapZoom", "3"), out double d1) == false) { d1 = 3; }
            mapControl.Zoom = d1;

            if (double.TryParse(registry.ReadString("MapLatitude", "0"), out d1) == false) { d1 = 0; }
            if (double.TryParse(registry.ReadString("MapLongetude", "0"), out double d2) == false) { d2 = 0; }
            mapControl.Position = new GMap.NET.PointLatLng(d1,d2);

            // Add the overlay to the map
            mapControl.Overlays.Add(mapMarkersOverlay);
            mapControl.Update();
            mapControl.Refresh();

            // Read registry values
            callsign = registry.ReadString("CallSign", null);
            stationId = (int)registry.ReadInt("StationId", 0);
            if ((callsign != null) && ((callsign.Length > 6) || (callsign.Length < 3))) { callsign = null; }
            if ((stationId < 0) || (stationId > 15)) { stationId = 0; }
            aprsRoutes = Utils.DecodeAprsRoutes(registry.ReadString("AprsRoutes", "Standard,APN000,WIDE1-1,WIDE2-2"));
            aprsSelectedRoute = registry.ReadString("SelectedAprsRoute", "Standard");
            nextAprsMessageId = (int)registry.ReadInt("NextAprsMessageId", new Random().Next(1, 1000));
            radioPanel.Visible = radioToolStripMenuItem.Checked = registry.ReadInt("ViewRadio", 1) == 1;
            showBluetoothFramesToolStripMenuItem.Checked = (registry.ReadInt("PacketTrace", 0) == 1);
            showAllChannels = (registry.ReadInt("ShowAllChannels", 0) == 1);
            allowTransmit = (registry.ReadInt("AllowTransmit", 0) == 1);
            aprsDestinationComboBox.Text = registry.ReadString("AprsDestination", "ALL");
            terminalDestinationComboBox.Text = registry.ReadString("TerminalDestination", "ALL");
            mapToolStripMenuItem.Checked = (registry.ReadInt("ViewMap", 0) == 1);
            if (previewMode)
            {
                terminalToolStripMenuItem.Checked = (registry.ReadInt("ViewTerminal", 1) == 1);
                mailToolStripMenuItem.Checked = (registry.ReadInt("ViewMail", 0) == 1);
                contactsToolStripMenuItem.Checked = (registry.ReadInt("ViewContacts", 0) == 1);
            }
            else
            {
                terminalToolStripMenuItem.Checked = terminalToolStripMenuItem.Visible = false;
                mailToolStripMenuItem.Checked = mailToolStripMenuItem.Visible = false;
                contactsToolStripMenuItem.Checked = contactsToolStripMenuItem.Visible = false;
            }

            packetsToolStripMenuItem.Checked = (registry.ReadInt("ViewPackets", 0) == 1);
            debugToolStripMenuItem.Checked = (registry.ReadInt("ViewDebug", 0) == 1);
            showAllMessagesToolStripMenuItem.Checked = (registry.ReadInt("aprsViewAll", 1) == 1);
            showPacketDecodeToolStripMenuItem.Checked = (registry.ReadInt("showPacketDecode", 0) == 1);
            packetsSplitContainer.Panel2Collapsed = !showPacketDecodeToolStripMenuItem.Checked;
            UpdateTabs();

            string debugFileName = registry.ReadString("DebugFile", null);
            try {
                saveTraceFileDialog.FileName = debugFileName;
                debugFile = File.OpenWrite(debugFileName);
                debugSaveToFileToolStripMenuItem.Checked = true;
                DebugTrace("-- Application Started --");
            }
            catch (Exception) { }

            // Read the packets file
            string[] lines = null;
            try { lines = File.ReadAllLines("packets.txt"); } catch (Exception) { }
            if (lines != null)
            {
                // If the packet file is big, load only the first 200 packets
                int i = 0;
                if (lines.Length > 200) { i = lines.Length - 200; }
                for (; i < lines.Length; i++)
                {
                    // Reac the packets
                    string[] s = lines[i].Split(',');
                    DateTime t = new DateTime(long.Parse(s[0]));
                    bool incoming = (s[1] == "1");
                    if (s[2] != "TncFrag") continue;
                    int cid = int.Parse(s[3]);
                    byte[] f = Utils.HexStringToByteArray(s[4]);

                    // Process the packets
                    TncDataFragment fragment = new TncDataFragment(true, 0, f, cid);
                    fragment.time = t;
                    fragment.incoming = incoming;
                    Radio_OnDataFrame(radio, fragment);
                    if (incoming == false)
                    {
                        AX25Packet packet = AX25Packet.DecodeAX25Packet(f, t);
                        if (packet != null) { AddAprsPacket(packet, true); }
                    }
                }
            }

            // Open the packet write file
            AprsFile = File.Open("packets.txt", FileMode.Append, FileAccess.Write);
            UpdateInfo();
            this.ResumeLayout();
            aprsChatControl.UpdateMessages(true);

            CheckBluetooth();
        }

        private async void CheckBluetooth()
        {
            DebugTrace("Looking for compatible radios...");
            bluetoothEnabled = await Radio.CheckBluetooth();
            if (bluetoothEnabled == false)
            {
                checkBluetoothButton.Visible = true;
                DebugTrace("Bluetooth LE not found on this computer.");
                if (bluetoothActivateForm == null)
                {
                    bluetoothActivateForm = new BTActivateForm(this);
                    bluetoothActivateForm.StartPosition = FormStartPosition.Manual;

                    // Calculate the center position relative to the parent
                    int x = this.Left + (this.Width - bluetoothActivateForm.Width) / 2;
                    int y = this.Top + (this.Height - bluetoothActivateForm.Height) / 2;

                    // Set the dialog's location
                    bluetoothActivateForm.Location = new Point(x, y);
                    bluetoothActivateForm.Show(this);
                }
                else
                {
                    bluetoothActivateForm.Focus();
                }
            }
            else
            {
                if (bluetoothActivateForm != null) {
                    bluetoothActivateForm.Close();
                    bluetoothActivateForm = null;
                }

                // Search for compatible devices
                checkBluetoothButton.Visible = false;
                devices = await Radio.FindCompatibleDevices();
                if (devices.Length == 0)
                {
                    MessageBox.Show("No compatible radios found. Please pair the radio using Bluetooth and restart this application.", "Bluetooth Radio", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    DebugTrace("No compatible radios found.");
                }
                else
                {
                    foreach (CompatibleDevice radio in devices) { DebugTrace("Found " + radio.name + " - " + radio.mac); }
                }
                UpdateInfo();
            }
        }

        private void Radio_OnDataFrame(Radio sender, TncDataFragment frame)
        {
            if (this.InvokeRequired) { this.Invoke(new Action(() => { Radio_OnDataFrame(sender, frame); })); return; }

            // Add to the packet capture tab
            ListViewItem l = new ListViewItem(new string[] { frame.time.ToShortTimeString(), (frame.channel_id >= 0)?(frame.channel_id + 1).ToString():"", Utils.BytesToHex(frame.data) });
            l.ImageIndex = frame.incoming ? 5 : 4;
            l.Tag = frame;
            packetsListView.Items.Add(l);

            // Write frame data to file
            if (AprsFile != null)
            {
                byte[] bytes = UTF8Encoding.Default.GetBytes(frame.time.Ticks + "," + (frame.incoming ? "1":"0") + "," + frame.ToString() + "\r\n");
                AprsFile.Write(bytes, 0, bytes.Length);
            }

            if (frame.incoming == false) return;

            //DebugTrace("Packet: " + frame.ToHex());

            AX25Packet p = AX25Packet.DecodeAX25Packet(frame.data, frame.time);
            if (p == null)
            {
                DebugTrace("Unable to parse AX25 packet: " + frame.ToHex());
                return;
            }
            p.time = frame.time;
            if (p != null)
            {
                AddAprsPacket(p, false);
                aprsChatControl.UpdateMessages(false);
                DebugTrace(frame.time.ToShortTimeString() + " CHANNEL: " + (frame.channel_id + 1) + " X25: " + p.ToString());
            }
            else
            {
                DebugTrace("APRS decode failed: " + frame.ToHex());
            }
        }

        private void Radio_InfoUpdate(Radio sender, Radio.RadioUpdateNotification msg)
        {
            if (this.InvokeRequired) { this.Invoke(new Action(() => { Radio_InfoUpdate(sender, msg); })); return; }
            switch (msg)
            {
                case Radio.RadioUpdateNotification.State:
                    switch (radio.State)
                    {
                        case Radio.RadioState.Connected:
                            connectToolStripMenuItem.Enabled = false;
                            disconnectToolStripMenuItem.Enabled = true;
                            radio.UpdateChannels();
                            radioStateLabel.Text = "Connected";
                            channelControls = new RadioChannelControl[radio.Info.channel_count];
                            vfo2LastChannelId = -1;
                            break;
                        case Radio.RadioState.Disconnected:
                            connectToolStripMenuItem.Enabled = true;
                            disconnectToolStripMenuItem.Enabled = false;
                            radioStateLabel.Text = "Disconnected";
                            channelsFlowLayoutPanel.Controls.Clear();
                            rssiProgressBar.Visible = false;
                            if (channelControls != null)
                            {
                                for (int i = 0; i < channelControls.Length; i++) { if (channelControls[i] != null) { channelControls[i].Dispose(); } }
                            }
                            if (radioHtStatusForm != null) { radioHtStatusForm.Close(); radioHtStatusForm = null; }
                            if (radioSettingsForm != null) { radioSettingsForm.Close(); radioSettingsForm = null; }
                            if (radioChannelForm != null) { radioChannelForm.Close(); radioChannelForm = null; }
                            if (radioVolumeForm != null) { radioVolumeForm.Close(); radioVolumeForm = null; }
                            if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
                            break;
                        case Radio.RadioState.Connecting:
                            radioStateLabel.Text = "Connecting";
                            break;
                        case Radio.RadioState.MultiRadioSelect:
                            radioStateLabel.Text = "Multiple Radios";
                            break;
                        case Radio.RadioState.UnableToConnect:
                            radioStateLabel.Text = "Can't connect";
                            break;
                        case Radio.RadioState.AccessDenied:
                            radioStateLabel.Text = "Access Denied";
                            new BTAccessDeniedForm().ShowDialog(this);
                            break;
                        case Radio.RadioState.BluetoothNotAvailable:
                            radioStateLabel.Text = "No Bluetooth";
                            break;
                        case Radio.RadioState.NotRadioFound:
                            radioStateLabel.Text = "No Radio Found";
                            break;
                    }

                    UpdateInfo();
                    break;
                case Radio.RadioUpdateNotification.ChannelInfo:
                    if (radio.Channels != null)
                    {
                        UpdateChannelsPanel();
                        CheckAprsChannel();
                        UpdateRadioDisplay();
                        UpdateInfo();
                    }
                    break;
                case Radio.RadioUpdateNotification.BatteryAsPercentage:
                    batteryToolStripStatusLabel.Text = "Battery " + radio.BatteryAsPercentage + "%";
                    batteryToolStripStatusLabel.Visible = true;
                    break;
                case Radio.RadioUpdateNotification.HtStatus:
                    rssiProgressBar.Visible = (radio.HtStatus.rssi > 0);
                    rssiProgressBar.Value = radio.HtStatus.rssi;
                    if (radioHtStatusForm != null) { radioHtStatusForm.UpdateInfo(); }
                    radioStatusToolStripMenuItem.Enabled = true;
                    UpdateRadioDisplay();
                    setupRegionMenu();
                    break;
                case Radio.RadioUpdateNotification.Settings:
                    if (radioSettingsForm != null) { radioSettingsForm.UpdateInfo(); }
                    radioSettingsToolStripMenuItem.Enabled = true;
                    dualWatchToolStripMenuItem.Checked = (radio.Settings.double_channel == 1);
                    scanToolStripMenuItem.Checked = radio.Settings.scan;
                    UpdateRadioDisplay();
                    setupRegionMenu();
                    break;
                case Radio.RadioUpdateNotification.Volume:
                    if (radioVolumeForm != null) {
                        radioVolumeForm.Volume = radio.Volume;
                    } else {
                        radioVolumeForm = new RadioVolumeForm(this, radio);
                        radioVolumeForm.Volume = radio.Volume;
                        radioVolumeForm.Show(this);
                    }
                    break;
                case Radio.RadioUpdateNotification.RegionChange:
                    break;
            }
        }

        private void UpdateRadioDisplay()
        {
            if (radio.Settings == null) return;
            if (radio.Channels != null)
            {
                RadioChannelInfo channelA = radio.Channels[radio.Settings.channel_a];
                RadioChannelInfo channelB = radio.Channels[radio.Settings.channel_b];

                foreach (RadioChannelControl c in channelControls)
                {
                    if (c == null) continue;
                    if ((channelA != null) && (((int)c.Tag) == channelA.channel_id))
                    {
                        c.BackColor = Color.PaleGoldenrod;
                    }
                    else if ((channelB != null) && (radio.Settings.double_channel == 1) && (((int)c.Tag) == channelB.channel_id))
                    {
                        c.BackColor = Color.PaleGoldenrod;
                    }
                    else
                    {
                        c.BackColor = Color.DarkKhaki;
                    }
                }

                if (channelA != null)
                {
                    vfo1Label.Text = channelA.name_str;
                    vfo1FreqLabel.Text = (((float)channelA.rx_freq)/1000000).ToString() + " MHz";
                    vfo1StatusLabel.Text = "";
                }
                else
                {
                    vfo1Label.Text = "";
                    vfo1FreqLabel.Text = "";
                    vfo1StatusLabel.Text = "";
                }
                if (radio.Settings.scan == true)
                {
                    if ((radio.HtStatus != null) && (radio.Channels[radio.HtStatus.curr_ch_id] != null))
                    {
                        if (radio.Channels[radio.HtStatus.curr_ch_id] == channelA)
                        {
                            if (vfo2LastChannelId >= 0)
                            {
                                channelB = radio.Channels[vfo2LastChannelId];
                                vfo2Label.Text = channelB.name_str;
                                vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString() + " MHz";
                                vfo2StatusLabel.Text = "Scanning...";
                            }
                            else
                            {
                                vfo2Label.Text = "Scanning...";
                                vfo2FreqLabel.Text = "";
                                vfo2StatusLabel.Text = "";
                            }
                        }
                        else
                        {
                            channelB = radio.Channels[radio.HtStatus.curr_ch_id];
                            vfo2Label.Text = channelB.name_str;
                            vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString() + " MHz";
                            vfo2StatusLabel.Text = "Scanning...";
                            vfo2LastChannelId = radio.HtStatus.curr_ch_id;
                        }
                    }
                    else
                    {
                        vfo2Label.Text = "Scanning...";
                        vfo2FreqLabel.Text = "";
                        vfo2StatusLabel.Text = "";
                    }
                }
                else if ((radio.Settings.double_channel == 1) && (channelB != null))
                {
                    vfo2Label.Text = channelB.name_str;
                    vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString() + " MHz";
                    vfo2StatusLabel.Text = "";
                }
                else
                {
                    vfo2Label.Text = "";
                    vfo2FreqLabel.Text = "";
                    vfo2StatusLabel.Text = "";
                }
                connectedPanel.Visible = true;
            }
            else
            {
                vfo1Label.Text = "";
                vfo1FreqLabel.Text = "";
                vfo1StatusLabel.Text = "";
                vfo2Label.Text = "";
                vfo2FreqLabel.Text = "";
                vfo2StatusLabel.Text = "";
            }
        }

        private void DebugTrace(string msg)
        {
            Program.BlockBoxEvent(msg);
            debugTextBox.AppendText(msg + Environment.NewLine);
            if (debugFile != null)
            {
                byte[] buf = UTF8Encoding.UTF8.GetBytes(DateTime.Now.ToString() + ": " + msg + Environment.NewLine);
                try { debugFile.Write(buf, 0, buf.Length); } catch (Exception) { }
            }
        }

        private void Radio_DebugMessage(Radio sender, string msg)
        {
            if (this.InvokeRequired) { this.Invoke(new Action(() => { Radio_DebugMessage(sender, msg); })); return; }
            DebugTrace(msg);
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Application.Exit();
        }

        private void connectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (devices == null || devices.Length == 0) return;
            if (devices.Length == 1)
            {
                // Connect to the only device found
                radio.Connect(devices[0].mac);
            }
            else
            {
                // Have the user select a device to connect to
                RadioSelectorForm selectorForm = new RadioSelectorForm(this);
                if (selectorForm.ShowDialog(this) == DialogResult.OK)
                {
                    radio.Connect(selectorForm.SelectedMac);
                }
            }
        }

        private void disconnectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radio.Disconnect();
        }

        private void radioInformationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            RadioInfoForm radioInfoForm = new RadioInfoForm(radio);
            radioInfoForm.ShowDialog();
        }

        private void batteryTimer_Tick(object sender, EventArgs e)
        {
            if (radio.State == Radio.RadioState.Connected) { radio.GetBatteryLevelAtPercentage(); }
        }

        private void radioStatusToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioHtStatusForm != null)
            {
                radioHtStatusForm.Focus();
            }
            else
            {
                radioHtStatusForm = new RadioHtStatusForm(this, radio);
                radioHtStatusForm.Show(this);
            }
        }

        public void ShowChannelDialog(int channelId)
        {
            if (radioChannelForm != null)
            {
                radioChannelForm.UpdateChannel(channelId);
                radioChannelForm.Focus();
            }
            else
            {
                radioChannelForm = new RadioChannelForm(this, radio, channelId);
                radioChannelForm.Show(this);
            }
        }

        private void radioSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioSettingsForm != null)
            {
                radioSettingsForm.UpdateInfo();
                radioSettingsForm.Focus();
            }
            else
            {
                radioSettingsForm = new RadioSettingsForm(this, radio);
                radioSettingsForm.Show(this);
            }
        }

        private void terminalClearButton_Click(object sender, EventArgs e)
        {
            terminalTextBox.Clear();
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
            string[] destSplit = terminalDestinationComboBox.Text.Split('-');
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

        private async void terminalSendButton_Click(object sender, EventArgs e)
        {
            if (terminalInputTextBox.Text.Length == 0) return;

            string destCallsign;
            int destStationId;
            if (ParseCallsignWithId(terminalDestinationComboBox.Text, out destCallsign, out destStationId) == false) return;
            terminalTextBox.AppendText(destCallsign + "-" + destStationId + "> " + terminalInputTextBox.Text + Environment.NewLine);
            terminalInputTextBox.Clear();

            List<AX25Address> addresses = new List<AX25Address>(1);
            addresses.Add(AX25Address.GetAddress(destCallsign, destStationId));
            addresses.Add(AX25Address.GetAddress(callsign, stationId));
            AX25Packet packet = new AX25Packet(addresses, terminalInputTextBox.Text, DateTime.Now);
            packet.time = DateTime.Now;
            await radio.TransmitTncData(packet);
            terminalInputTextBox.Text = "";
        }

        private void radioToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radioPanel.Visible = radioToolStripMenuItem.Checked;
            registry.WriteInt("ViewRadio", radioPanel.Visible ? 1 : 0);
        }

        private List<AX25Address> GetTransmitAprsRoute()
        {
            List<AX25Address> addresses = new List<AX25Address>(1);
            if (aprsRoutes.Count == 0) {
                addresses.Add(AX25Address.GetAddress("APN000", 0));
                addresses.Add(AX25Address.GetAddress(callsign, stationId));
                addresses.Add(AX25Address.GetAddress("WIDE1", 1));
                addresses.Add(AX25Address.GetAddress("WIDE2", 2));
                return addresses;
            }

            string routeKey = null;
            routeKey = (string)aprsRouteComboBox.SelectedItem;
            if ((routeKey == null) || (aprsRoutes[routeKey] == null)) { routeKey = null; }
            if (routeKey == null) { routeKey = aprsRoutes.Keys.ElementAt(0); }
            List<AX25Address> route = aprsRoutes[routeKey];

            addresses.Add(route[0]);
            addresses.Add(AX25Address.GetAddress(callsign, stationId));
            if (route.Count > 1) { addresses.Add(route[1]); }
            if (route.Count > 2) { addresses.Add(route[2]); }
            if (route.Count > 3) { addresses.Add(route[3]); }
            return addresses;
        }

        private async void aprsSendButton_Click(object sender, EventArgs e)
        {
            if (aprsTextBox.Text.Length == 0) return;
            if (UTF8Encoding.Default.GetByteCount(aprsTextBox.Text) > 67) return;
            if (aprsChannel < 0) return;

            // APRS format
            string aprsAddr = ":" + aprsDestinationComboBox.Text;
            while (aprsAddr.Length < 10) { aprsAddr += " "; }
            aprsAddr += ":";
            int msgId = nextAprsMessageId++;
            if (nextAprsMessageId > 999) { nextAprsMessageId = 1; }
            registry.WriteInt("NextAprsMessageId", nextAprsMessageId);

            AX25Packet packet = new AX25Packet(GetTransmitAprsRoute(), aprsAddr + aprsTextBox.Text + "{" + msgId, DateTime.Now);
            packet.messageId = msgId;
            packet.time = DateTime.Now;

            // Simplified Format, not APRS
            //addresses.Add(AX25Address.GetAddress(callsign, 0, false, true));
            //AX25Packet packet = new AX25Packet(1, addresses, 0, aprsTextBox.Text);
            //packet.time = DateTime.Now;

            await radio.TransmitTncData(packet, aprsChannel);
            AddAprsPacket(packet, true);
            aprsTextBox.Text = "";
        }


        public void AddAprsPacket(AX25Packet packet, bool sender)
        {
            string MessageId = null;
            string MessageText = null;
            PacketDataType MessageType = PacketDataType.Message;
            String xcallsign = null;
            int ImageIndex = -1;
            AprsPacket aprsPacket = null;
            if ((packet.addresses != null) && (packet.addresses.Count >= 2))
            {
                aprsPacket = new AprsPacket();
                if (aprsPacket.Parse(packet.payload, packet.addresses[0].CallSignWithId) == false) return;
                if (sender == false)
                {
                    AX25Address addr = packet.addresses[1];
                    xcallsign = addr.address + ((addr.SSID == 0) ? "" : ("-" + addr.SSID));
                }
                MessageType = aprsPacket.DataType;

                if (sender == false)
                {
                    if ((aprsPacket.Position != null) && (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) && (aprsPacket.Position.CoordinateSet.Longitude.Value != 0))
                    {
                        ImageIndex = 3;
                    }
                }

                if (aprsPacket.DataType == PacketDataType.Message)
                {
                    bool forSelf = ((aprsPacket.MessageData.Addressee == callsign) || (aprsPacket.MessageData.Addressee == callsign + "-" + stationId));

                    if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtAck)
                    {
                        if (forSelf)
                        {
                            // Look at a message to ack
                            foreach (ChatMessage n in aprsChatControl.Messages)
                            {
                                if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId)) { n.ImageIndex = 0; }
                            }
                        }
                        return;
                    }
                    else if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtRej)
                    {
                        if (forSelf)
                        {
                            // Look at a message to reject
                            foreach (ChatMessage n in aprsChatControl.Messages)
                            {
                                if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId)) { n.ImageIndex = 1; }
                            }
                        }
                        return;
                    }

                    // Normal message processing
                    xcallsign = (sender ? "→ " : "") + aprsPacket.MessageData.Addressee;
                    MessageId = aprsPacket.MessageData.SeqId;
                    MessageText = aprsPacket.MessageData.MsgText;

                    // If this is a SMS message, do more processing to make it look good
                    if ((aprsPacket.MessageData.Addressee == "SMS") && (aprsPacket.MessageData.MsgText.Length > 12) && (aprsPacket.MessageData.MsgText[0] == '@'))
                    {
                        int i = aprsPacket.MessageData.MsgText.IndexOf(" ");
                        if (i >= 0)
                        {
                            xcallsign = "→ SMS: " + aprsPacket.MessageData.MsgText.Substring(1, i);
                            MessageId = aprsPacket.MessageData.SeqId;
                            MessageText = aprsPacket.MessageData.MsgText.Substring(i + 1);
                        }
                    }

                    // Check if we already got this exact message before
                    if (MessageId != null)
                    {
                        foreach (ChatMessage n in aprsChatControl.Messages)
                        {
                            // If this is a duplicate, don't display it.
                            if ((n.MessageId == MessageId) && (n.CallSign == xcallsign) && (n.Message == MessageText)) return;
                        }
                    }
                }
                else
                {
                    if ((aprsPacket.Comment != null) && ((aprsPacket.DataType != PacketDataType.MicE) && (aprsPacket.DataType != PacketDataType.MicECurrent) && (aprsPacket.DataType != PacketDataType.MicEOld)))
                    {
                        // This is not a message
                        MessageText = aprsPacket.Comment;
                    }
                }
            }
            if ((packet.addresses != null) && (packet.addresses.Count == 1))
            {
                AX25Address addr = packet.addresses[0];
                xcallsign = addr.address + ((addr.SSID == 0) ? "" : ("-" + addr.SSID));
                MessageText = packet.payload;
            }

            if ((MessageText != null) && (MessageText.Length > 0))
            {
                ChatMessage c = new ChatMessage(xcallsign, MessageText, packet.time, sender, -1);
                c.Tag = packet;
                c.MessageId = MessageId;
                c.MessageType = MessageType;
                c.Visible = showAllMessagesToolStripMenuItem.Checked || (c.MessageType == PacketDataType.Message);
                c.ImageIndex = ImageIndex;
                aprsChatControl.Messages.Add(c);
                if (c.Visible) { aprsChatControl.UpdateMessages(true); }

                if ((c.ImageIndex == 3) && (aprsPacket != null))
                {
                    c.Latitude = aprsPacket.Position.CoordinateSet.Latitude.Value;
                    c.Longitude = aprsPacket.Position.CoordinateSet.Longitude.Value;
                    AddMapMarker(packet.addresses[1].CallSignWithId, aprsPacket.Position.CoordinateSet.Latitude.Value, aprsPacket.Position.CoordinateSet.Longitude.Value);
                }
            }
        }

        private void aprsTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == 13) { aprsSendButton_Click(this, null); e.Handled = true; return; }

            // Check if the pressed character is in the restricted list
            char[] restrictedChars = { '~', '|', '}' };
            if (restrictedChars.Contains(e.KeyChar)) { e.Handled = true; return; }
        }

        private void aboutToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            new AboutForm().ShowDialog(this);
        }

        private void mainMenuStrip_ItemClicked(object sender, ToolStripItemClickedEventArgs e)
        {

        }

        private void showPacketTraceToolStripMenuItem_Click(object sender, EventArgs e)
        {
        }

        private void saveToFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (debugFile != null)
            {
                debugFile.Close();
                debugFile = null;
                debugSaveToFileToolStripMenuItem.Checked = false;
                registry.DeleteValue("DebugFile");
            }
            else
            {
                if (saveTraceFileDialog.ShowDialog(this) == DialogResult.OK)
                {
                    debugFile = File.OpenWrite(saveTraceFileDialog.FileName);
                    debugSaveToFileToolStripMenuItem.Checked = true;
                    registry.WriteString("DebugFile", saveTraceFileDialog.FileName);
                }
            }
        }

        private async void aprsSmsButton_Click(object sender, EventArgs e)
        {
            using (AprsSmsForm aprsSmsForm = new AprsSmsForm())
            {
                if (aprsSmsForm.ShowDialog(this) == DialogResult.OK)
                {
                    // APRS format
                    if (aprsChannel < 0) return;
                    int msgId = nextAprsMessageId++;
                    if (nextAprsMessageId > 999) { nextAprsMessageId = 1; }
                    registry.WriteInt("NextAprsMessageId", nextAprsMessageId);
                    AX25Packet packet = new AX25Packet(GetTransmitAprsRoute(), ":SMS      :@" + aprsSmsForm.PhoneNumber + " " + aprsSmsForm.Message + "{" + msgId, DateTime.Now);
                    packet.messageId = msgId;
                    packet.time = DateTime.Now;
                    
                    await radio.TransmitTncData(packet, aprsChannel);
                    AddAprsPacket(packet, true);
                    aprsTextBox.Text = "";
                }
            }
        }

        public void UpdateInfo()
        {
            radioStateLabel.Visible = (radio.State != Radio.RadioState.Connected);
            if (radio.State != Radio.RadioState.Connected)
            {
                channelsFlowLayoutPanel.Visible = false;
                batteryToolStripStatusLabel.Visible = false;
            }
            smSMessageToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            volumeToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            dualWatchToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            scanToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            aprsDestinationComboBox.Enabled = (radio.State == Radio.RadioState.Connected);
            terminalDestinationComboBox.Enabled = (radio.State == Radio.RadioState.Connected);
            aprsTextBox.Enabled = (radio.State == Radio.RadioState.Connected);
            aprsSendButton.Enabled = (radio.State == Radio.RadioState.Connected);
            batteryTimer.Enabled = (radio.State == Radio.RadioState.Connected);
            terminalInputTextBox.Enabled = (radio.State == Radio.RadioState.Connected);
            terminalSendButton.Enabled = (radio.State == Radio.RadioState.Connected);
            connectToolStripMenuItem.Enabled = connectButton.Visible = (radio.State != Radio.RadioState.Connected && radio.State != Radio.RadioState.Connecting && devices != null && devices.Length > 0);
            radioInformationToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            radioStatusToolStripMenuItem.Enabled = ((radio.State == Radio.RadioState.Connected) && (radio.HtStatus != null));
            if (radio.State != Radio.RadioState.Connected) { connectedPanel.Visible = false; }

            toolStripMenuItem7.Visible = smSMessageToolStripMenuItem.Visible = (allowTransmit && (aprsChannel != -1));
            aprsBottomPanel.Visible = allowTransmit && (aprsChannel != -1);
            terminalBottomPanel.Visible = allowTransmit;

            // APRS Routes
            string selectedAprsRoute = aprsSelectedRoute;
            if ((aprsSelectedRoute == null) && (aprsRouteComboBox.SelectedItem != null)) { selectedAprsRoute = (string)aprsRouteComboBox.SelectedItem; }
            aprsRouteComboBox.Visible = ((aprsRoutes != null) && (aprsRoutes.Count > 1));
            aprsRouteComboBox.Items.Clear();
            aprsRouteComboBox.Items.AddRange(aprsRoutes.Keys.ToArray());
            aprsRouteComboBox.SelectedItem = selectedAprsRoute;
            if (aprsRouteComboBox.SelectedIndex == -1) { aprsRouteComboBox.SelectedIndex = 0; }
            aprsSelectedRoute = null;


            if ((callsign != null) && (callsign.Length >= 3))
            {
                this.Text = appTitle + " - " + callsign + ((stationId != 0) ? ("-" + stationId) : "");
            }
            else
            {
                this.Text = appTitle;
            }
        }

        public void UpdateChannelsPanel()
        {
            channelsFlowLayoutPanel.SuspendLayout();
            int visibleChannels = 0;
            int channelHeight = 0;
            if (channelControls != null)
            {
                for (int i = 0; i < channelControls.Length; i++)
                {
                    if (radio.Channels[i] != null)
                    {
                        if (channelControls[i] == null)
                        {
                            channelControls[i] = new RadioChannelControl(this);
                            channelsFlowLayoutPanel.Controls.Add(channelControls[i]);
                        }
                        channelControls[i].ChannelName = (radio.Channels[i].name_str.Length > 0) ? radio.Channels[i].name_str : (i + 1).ToString();
                        channelControls[i].Tag = i;
                        bool visible = showAllChannels || (radio.Channels[i].name_str.Length > 0); ;
                        channelControls[i].Visible = visible;
                        if (visible) { visibleChannels++; }
                        channelHeight = channelControls[i].Height;
                    }
                }
                int hBlockCount = ((visibleChannels / 3) + (((visibleChannels % 3) != 0) ? 1 : 0));
                int blockHeight = 0;
                if (hBlockCount > 0)
                {
                    blockHeight = (radioPanel.Height - 310) / hBlockCount;
                    if (blockHeight > 50) { blockHeight = 50; }
                    for (int i = 0; i < channelControls.Length; i++)
                    {
                        if (channelControls[i] != null) { channelControls[i].Height = blockHeight; }
                    }
                }
                channelsFlowLayoutPanel.Height = blockHeight * hBlockCount;
            }
            channelsFlowLayoutPanel.Visible = (visibleChannels > 0);
            channelsFlowLayoutPanel.ResumeLayout();
        }

        private void settingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            using (SettingsForm settingsForm = new SettingsForm())
            {
                if ((callsign != null) && (callsign.Length <= 6)) { settingsForm.CallSign = callsign; }
                if ((stationId >= 0) && (stationId <= 15)) { settingsForm.StationId = stationId; }
                settingsForm.AllowTransmit = allowTransmit;
                settingsForm.AprsRoutes = Utils.EncodeAprsRoutes(aprsRoutes);
                if (settingsForm.ShowDialog(this) == DialogResult.OK)
                {
                    // License Settings
                    callsign = settingsForm.CallSign;
                    stationId = settingsForm.StationId;
                    allowTransmit = settingsForm.AllowTransmit;
                    registry.WriteString("CallSign", callsign);
                    registry.WriteInt("StationId", stationId);
                    registry.WriteInt("AllowTransmit", allowTransmit ? 1 : 0);

                    // APRS Settings
                    string aprsRoutesStr = settingsForm.AprsRoutes;
                    registry.WriteString("AprsRoutes", aprsRoutesStr);
                    aprsRoutes = Utils.DecodeAprsRoutes(aprsRoutesStr);

                    CheckAprsChannel();
                    UpdateInfo();
                }
            }
        }

        private void aprsDestinationComboBox_TextChanged(object sender, EventArgs e)
        {
            // Uppercase the callsign
            int selectionStart = aprsDestinationComboBox.SelectionStart;
            aprsDestinationComboBox.Text = aprsDestinationComboBox.Text.ToUpper();
            aprsDestinationComboBox.SelectionStart = selectionStart;

            AX25Address addr = AX25Address.GetAddress(aprsDestinationComboBox.Text);
            aprsDestinationComboBox.BackColor = (addr == null) ? Color.Salmon : SystemColors.Window;
            registry.WriteString("AprsDestination", aprsDestinationComboBox.Text);
        }

        private void terminalDestinationComboBox_TextChanged(object sender, EventArgs e)
        {
            // Uppercase the callsign
            int selectionStart = terminalDestinationComboBox.SelectionStart;
            terminalDestinationComboBox.Text = terminalDestinationComboBox.Text.ToUpper();
            terminalDestinationComboBox.SelectionStart = selectionStart;

            string destCallsign;
            int destStationId;
            bool destParsed = ParseCallsignWithId(terminalDestinationComboBox.Text, out destCallsign, out destStationId);
            terminalDestinationComboBox.BackColor = (destParsed == false) ? Color.Salmon : SystemColors.Window;
            if (destParsed == true) { registry.WriteString("TerminalDestination", terminalDestinationComboBox.Text); }
        }

        private void volumeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioVolumeForm != null)
            {
                radioVolumeForm.Focus();
            }
            else
            {
                radio.GetVolumeLevel();
            }
        }

        public void ChangeChannelA(int channelId)
        {
            radio.WriteSettings(radio.Settings.ToByteArray(channelId, radio.Settings.channel_b, radio.Settings.double_channel, radio.Settings.scan, radio.Settings.squelch_level));
        }

        public void ChangeChannelB(int channelId)
        {
            radio.WriteSettings(radio.Settings.ToByteArray(radio.Settings.channel_a, channelId, radio.Settings.double_channel, radio.Settings.scan, radio.Settings.squelch_level));
        }

        private void dualWatchToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radio.WriteSettings(radio.Settings.ToByteArray(radio.Settings.channel_a, radio.Settings.channel_b, (radio.Settings.double_channel == 1) ? 0 : 1, radio.Settings.scan, radio.Settings.squelch_level));
        }

        private void scanToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radio.WriteSettings(radio.Settings.ToByteArray(radio.Settings.channel_a, radio.Settings.channel_b, radio.Settings.double_channel, !radio.Settings.scan, radio.Settings.squelch_level));
        }

        private void mapToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void terminalToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void mailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void contactsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void packetsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }
        private void debugToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void UpdateTabs()
        {
            mainTabControl.TabPages.Clear();
            mainTabControl.TabPages.Add(aprsTabPage);
            if (mapToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(mapTabPage); }
            if (terminalToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(terminalTabPage); }
            if (mailToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(mailTabPage); }
            if (contactsToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(addressesTabPage); }
            if (packetsToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(packetsTabPage); }
            if (debugToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(debugTabPage); }
            registry.WriteInt("ViewMap", mapToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewTerminal", terminalToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewMail", mailToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewContacts", contactsToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewDebug", debugToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewPackets", packetsToolStripMenuItem.Checked ? 1 : 0);
        }

        private void aprsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            aprsContextMenuStrip.Show(aprsMenuPictureBox, e.Location);
        }

        private void showAllMessagesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            registry.WriteInt("aprsViewAll", showAllMessagesToolStripMenuItem.Checked ? 1 : 0);
            foreach (ChatMessage n in aprsChatControl.Messages)
            {
                n.Visible = showAllMessagesToolStripMenuItem.Checked || (n.MessageType == PacketDataType.Message);
            }
            aprsChatControl.UpdateMessages(true);
        }

        private void aprsChatControl_MouseClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                selectedAprsMessage = aprsChatControl.GetChatMessageAtXY(e.X, e.Y);
                if (selectedAprsMessage != null) { aprsMsgContextMenuStrip.Show(aprsChatControl, e.Location); }
            }
        }

        private void copyMessageToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((selectedAprsMessage != null) && (string.IsNullOrEmpty(selectedAprsMessage.Message) == false))
            {
                Clipboard.SetText(selectedAprsMessage.Message);
            }
        }

        private void copyCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((selectedAprsMessage != null) && (string.IsNullOrEmpty(selectedAprsMessage.CallSign) == false))
            {
                Clipboard.SetText(selectedAprsMessage.CallSign);
            }
        }

        private void detailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (selectedAprsMessage == null) return;
            if (aprsDetailsForm == null)
            {
                aprsDetailsForm = new AprsDetailsForm(this);
                aprsDetailsForm.SetMessage(selectedAprsMessage);
                aprsDetailsForm.Show(this);
            }
            else
            {
                aprsDetailsForm.SetMessage(selectedAprsMessage);
                aprsDetailsForm.Focus();
            }
        }

        private void aprsChatControl_MouseDoubleClick(object sender, MouseEventArgs e)
        {
            selectedAprsMessage = aprsChatControl.GetChatMessageAtXY(e.X, e.Y);
            if (selectedAprsMessage != null) {
                if (aprsDetailsForm == null)
                {
                    aprsDetailsForm = new AprsDetailsForm(this);
                    aprsDetailsForm.SetMessage(selectedAprsMessage);
                    aprsDetailsForm.Show(this);
                }
                else
                {
                    aprsDetailsForm.SetMessage(selectedAprsMessage);
                    aprsDetailsForm.Focus();
                }
            }
        }

        private void mapZoomInbutton_Click(object sender, EventArgs e)
        {
            mapControl.Zoom = mapControl.Zoom * 1.2;
            mapControl.Update();
            mapControl.Refresh();
        }

        private void mapZoomOutButton_Click(object sender, EventArgs e)
        {
            mapControl.Zoom = mapControl.Zoom * 0.8;
            mapControl.Update();
            mapControl.Refresh();
        }

        private void mapControl_OnMapZoomChanged()
        {
            registry.WriteString("MapZoom", mapControl.Zoom.ToString());
        }

        private void mapControl_OnPositionChanged(GMap.NET.PointLatLng point)
        {
            registry.WriteString("MapLatitude", mapControl.Position.Lat.ToString());
            registry.WriteString("MapLongetude", mapControl.Position.Lng.ToString());
        }

        private void AddMapMarker(string callsign, double lat, double lng)
        {
            foreach (GMarkerGoogle m in mapMarkersOverlay.Markers)
            {
                if (m.ToolTipText == callsign) { m.Position = new PointLatLng(lat, lng); return; }
            }
            GMarkerGoogle marker = new GMarkerGoogle(new PointLatLng(lat, lng), GMarkerGoogleType.red_dot);
            marker.ToolTipText = callsign;
            marker.ToolTipMode = MarkerTooltipMode.OnMouseOver;
            mapMarkersOverlay.Markers.Add(marker);
        }

        private void RemoveMapMarker(string callsign)
        {
            GMarkerGoogle marker = null;
            foreach (GMarkerGoogle m in mapMarkersOverlay.Markers)
            {
                if (m.ToolTipText == callsign) { marker = m; break; }
            }
            mapMarkersOverlay.Markers.Remove(marker);
        }

        private void packetsListView_Resize(object sender, EventArgs e)
        {
            packetsListView.Columns[2].Width = packetsListView.Width - packetsListView.Columns[1].Width - packetsListView.Columns[0].Width - 28;
        }

        private void packetsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            packetsContextMenuStrip.Show(packetsMenuPictureBox, e.Location);
        }

        private void showPacketDecodeToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            registry.WriteInt("showPacketDecode", showPacketDecodeToolStripMenuItem.Checked ? 1 : 0);
            packetsSplitContainer.Panel2Collapsed = !showPacketDecodeToolStripMenuItem.Checked;
        }

        private void packetsListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            packetDecodeTextBox.Clear();
            if (packetsListView.SelectedItems.Count == 0) return;
            ListViewItem l = packetsListView.SelectedItems[0];
            if (l.Tag == null) return;
            TncDataFragment fragment = (TncDataFragment)l.Tag;
            StringBuilder sb = new StringBuilder();
            sb.Append("Packet " + (fragment.incoming ? "received" : "sent"));
            sb.Append(" on " + fragment.time.ToString());
            if (fragment.channel_id >= 0) { sb.Append(" on channel " + (fragment.channel_id + 1)); }
            sb.AppendLine(", " + fragment.data.Length + " byte" + (fragment.data.Length > 1 ? "s" : ""));


            AX25Packet packet = AX25Packet.DecodeAX25Packet(fragment.data, fragment.time);
            if (packet == null)
            {
                sb.AppendLine("AX25 Decoder failed to decode packet.");
            }
            else
            {
                sb.AppendLine("AX25 Addresses");
                for (int i = 0; i < packet.addresses.Count; i++)
                {
                    AX25Address addr = packet.addresses[i];
                    sb.Append("  " + addr.CallSignWithId + " [");
                    sb.Append((addr.CRBit1) ? "X" : "-");
                    sb.Append((addr.CRBit2) ? "X" : "-");
                    sb.Append((addr.CRBit3) ? "X" : "-");
                    sb.AppendLine("]");
                }
                sb.Append("Frame: " + packet.type.ToString());
                if (packet.modulo128) { sb.Append(", Modulo128"); }
                if (packet.pollFinal) { sb.Append(", PollFinal"); }
                if (packet.ns > 0) { sb.Append(", NS:" + packet.ns); }
                if (packet.nr > 0) { sb.Append(", NR:" + packet.nr); }
                if (packet.pid > 0) { sb.Append(", PID:" + packet.pid); }
                sb.AppendLine();
            }

            packetDecodeTextBox.Text = sb.ToString();
        }

        private void packetsListContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (packetsListView.SelectedItems.Count == 0) { e.Cancel = true; return; }
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetsListView.SelectedItems) { sb.AppendLine(l.SubItems[2].Text); }
            Clipboard.SetText(sb.ToString());
        }

        private void clearToolStripMenuItem_Click(object sender, EventArgs e)
        {
            debugTextBox.Clear();
        }

        private void showBluetoothFramesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            radio.PacketTrace = showBluetoothFramesToolStripMenuItem.Checked;
            registry.WriteInt("PacketTrace", showBluetoothFramesToolStripMenuItem.Checked ? 1 : 0);
        }

        private void debugMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            debugTabContextMenuStrip.Show(aprsMenuPictureBox, e.Location);
        }

        private async void queryDeviceNamesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string[] deviceNames = await Radio.GetDeviceNames();
            DebugTrace("List of devices:");
            foreach (string deviceName in deviceNames)
            {
                DebugTrace("  " + deviceName);
            }
        }

        private void aprsRouteComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            registry.WriteString("SelectedAprsRoute", (string)aprsRouteComboBox.SelectedItem);
        }

        private void showLocationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((selectedAprsMessage == null) || ((selectedAprsMessage.Latitude == 0) && (selectedAprsMessage.Longitude == 0))) return;
            foreach (MapLocationForm form in mapLocationForms)
            {
                if (form.Callsign == selectedAprsMessage.CallSign) { form.Focus(); return; }
            }
            MapLocationForm mapForm = new MapLocationForm(this, selectedAprsMessage.CallSign);
            mapForm.SetPosition(selectedAprsMessage.Latitude, selectedAprsMessage.Longitude);
            List<GMarkerGoogle> markers = new List<GMarkerGoogle>();
            foreach (GMarkerGoogle marker in mapMarkersOverlay.Markers) { markers.Add(marker); }
            mapForm.SetMarkers(markers.ToArray());
            mapLocationForms.Add(mapForm);
            mapForm.Show();
        }

        private void aprsMsgContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (selectedAprsMessage == null) return;
            showLocationToolStripMenuItem.Visible = ((selectedAprsMessage.Latitude != 0) && (selectedAprsMessage.Longitude != 0));
        }

        private void checkBluetoothButton_Click(object sender, EventArgs e)
        {
            CheckBluetooth();
        }

        private void CheckAprsChannel()
        {
            if ((allowTransmit == false) || (radio.State != RadioState.Connected) || (radio.Channels == null) || (radio.AllChannelsLoaded() == false))
            {
                aprsMissingChannelPanel.Visible = false;
                aprsChannel = -1;
                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
                return;
            }

            // Check if we have a APRS channel
            RadioChannelInfo channel = radio.GetChannelByName("APRS");
            if (channel != null)
            {
                aprsMissingChannelPanel.Visible = false;
                aprsChannel = channel.channel_id;
                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
            }
            else
            {
                aprsMissingChannelPanel.Visible = true;
                aprsChannel = -1;
            }
        }

        private void aprsSetupButton_Click(object sender, EventArgs e)
        {
            if (aprsConfigurationForm != null)
            {
                aprsConfigurationForm.Focus();
            }
            else
            {
                aprsConfigurationForm = new AprsConfigurationForm(this);
                aprsConfigurationForm.Show(this);
            }
        }

        private void channelsContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            showAllChannelsToolStripMenuItem.Checked = showAllChannels;
        }

        private void channelsContextMenuStrip_Click(object sender, EventArgs e)
        {
            showAllChannels = !showAllChannelsToolStripMenuItem.Checked;
            registry.WriteInt("ShowAllChannels", showAllChannels ? 1 : 0);
            UpdateChannelsPanel();
        }

        private void allChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            showAllChannels = !allChannelsToolStripMenuItem.Checked;
            registry.WriteInt("ShowAllChannels", showAllChannels ? 1 : 0);
            UpdateChannelsPanel();
        }

        private void viewToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            allChannelsToolStripMenuItem.Checked = showAllChannels;
        }

        private void radioPanel_SizeChanged(object sender, EventArgs e)
        {
            UpdateChannelsPanel();
        }

        private void setupRegionMenu()
        {
            if ((radio.State != RadioState.Connected) || (radio.Settings == null) || (radio.HtStatus == null))
            {
                regionToolStripMenuItem.Enabled = false;
                regionToolStripMenuItem.DropDownItems.Clear();
            }
            else
            {
                if (regionToolStripMenuItem.DropDownItems.Count == 0)
                {
                    for (int i = 0; i < radio.Info.region_count; i++)
                    {
                        ToolStripMenuItem item = new ToolStripMenuItem("Region " + (i + 1).ToString());
                        item.Tag = i;
                        item.Click += regionSelectToolStripMenuItem_Click;
                        regionToolStripMenuItem.DropDownItems.Add(item);
                    }
                }
                foreach (ToolStripMenuItem item in regionToolStripMenuItem.DropDownItems)
                {
                    item.Checked = ((int)item.Tag == radio.HtStatus.curr_region);
                }
                regionToolStripMenuItem.Enabled = true;
            }
        }

        private void regionSelectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radio.HtStatus == null) return;
            ToolStripMenuItem item = (ToolStripMenuItem)sender;
            int region = (int)item.Tag;
            if (region == radio.HtStatus.curr_region) return;
            radio.SetRegion(region);
        }

    }
}
