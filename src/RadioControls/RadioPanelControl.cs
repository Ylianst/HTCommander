/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;
using HTCommander.radio;

namespace HTCommander.RadioControls
{
    public partial class RadioPanelControl : UserControl
    {
        private RadioChannelControl[] channelControls = null;
        private int vfo2LastChannelId = -1;
        private DataBrokerClient broker;

        // Device ID that this control is monitoring
        private int _deviceId = -1;

        // Cached state from broker
        private string currentState = null;
        private RadioHtStatus currentHtStatus = null;
        private RadioSettings currentSettings = null;
        private RadioChannelInfo[] currentChannels = null;
        private string _friendlyName = null;
        private bool _gpsEnabled = false;
        private RadioPosition _position = null;

        // UI state
        private bool _showAllChannels = false;

        public RadioPanelControl()
        {
            InitializeComponent();

            // Enable double buffering to prevent flickering when drawing
            this.DoubleBuffered = true;

            // Subscribe to PictureBox Paint event to draw text on top of the image
            radioPictureBox.Paint += RadioPictureBox_Paint;

            // Set up DataBrokerClient for subscribing to broker events
            broker = new DataBrokerClient();
        }

        /// <summary>
        /// Gets or sets the device ID that this control monitors.
        /// Setting this property will subscribe to broker events for that device.
        /// Set to -1 to disconnect from any device.
        /// </summary>
        public int DeviceId
        {
            get { return _deviceId; }
            set
            {
                if (_deviceId == value) return;

                // Unsubscribe from previous device
                if (_deviceId > 0 && broker != null)
                {
                    broker.Unsubscribe(_deviceId, "State");
                    broker.Unsubscribe(_deviceId, "HtStatus");
                    broker.Unsubscribe(_deviceId, "Settings");
                    broker.Unsubscribe(_deviceId, "Channels");
                }

                // Clear cached state
                currentState = null;
                currentHtStatus = null;
                currentSettings = null;
                currentChannels = null;

                _deviceId = value;

                if (_deviceId > 0 && broker != null)
                {
                    // Subscribe to the new device's events
                    broker.Subscribe(_deviceId, new[] { "State", "HtStatus", "Settings", "Channels", "FriendlyName", "GpsEnabled", "Position" }, OnBrokerEvent);

                    // Load initial state from broker
                    LoadInitialState();
                }

                // Update the display
                UpdateDisplayForCurrentState();
            }
        }

        /// <summary>
        /// Loads the initial state from the broker for the current device.
        /// </summary>
        private void LoadInitialState()
        {
            if (_deviceId <= 0 || broker == null) return;

            // Load cached values from broker
            currentState = broker.GetValue<string>(_deviceId, "State", null);
            currentHtStatus = broker.GetValue<RadioHtStatus>(_deviceId, "HtStatus", null);
            currentSettings = broker.GetValue<RadioSettings>(_deviceId, "Settings", null);
            currentChannels = broker.GetValue<RadioChannelInfo[]>(_deviceId, "Channels", null);
            _gpsEnabled = broker.GetValue<bool>(_deviceId, "GpsEnabled", false);
            _position = broker.GetValue<RadioPosition>(_deviceId, "Position", null);

            // Get FriendlyName from ConnectedRadios list on device id 1
            _friendlyName = GetFriendlyNameFromConnectedRadios(_deviceId);

            // Force redraw of the PictureBox to show the FriendlyName
            radioPictureBox.Invalidate();

            // Update GPS status display
            UpdateGpsStatusDisplay();
        }

        /// <summary>
        /// Gets the FriendlyName for a device from the ConnectedRadios list.
        /// </summary>
        /// <param name="deviceId">The device ID to look up.</param>
        /// <returns>The FriendlyName if found, otherwise null.</returns>
        private string GetFriendlyNameFromConnectedRadios(int deviceId)
        {
            var connectedRadios = DataBroker.GetValue(1, "ConnectedRadios") as System.Collections.IList;
            if (connectedRadios == null) return null;

            foreach (var item in connectedRadios)
            {
                if (item == null) continue;
                var itemType = item.GetType();
                int? itemDeviceId = (int?)itemType.GetProperty("DeviceId")?.GetValue(item);
                if (itemDeviceId.HasValue && itemDeviceId.Value == deviceId)
                {
                    return (string)itemType.GetProperty("FriendlyName")?.GetValue(item);
                }
            }
            return null;
        }

        /// <summary>
        /// Handles broker events for the subscribed device.
        /// </summary>
        private void OnBrokerEvent(int deviceId, string name, object data)
        {
            if (deviceId != _deviceId) return;

            switch (name)
            {
                case "State":
                    currentState = data as string;
                    UpdateDisplayForCurrentState();
                    break;
                case "HtStatus":
                    currentHtStatus = data as RadioHtStatus;
                    UpdateRadioDisplay();
                    break;
                case "Settings":
                    currentSettings = data as RadioSettings;
                    UpdateRadioDisplay();
                    break;
                case "Channels":
                    currentChannels = data as RadioChannelInfo[];
                    UpdateChannelsPanel();
                    UpdateRadioDisplay();
                    break;
                case "FriendlyName":
                    _friendlyName = data as string;
                    radioPictureBox.Invalidate(); // Trigger repaint to update the displayed name
                    break;
                case "GpsEnabled":
                    if (data is bool gpsEnabled)
                    {
                        _gpsEnabled = gpsEnabled;
                        UpdateGpsStatusDisplay();
                    }
                    break;
                case "Position":
                    _position = data as RadioPosition;
                    UpdateGpsStatusDisplay();
                    break;
            }
        }

        /// <summary>
        /// Updates the display based on the current connection state.
        /// Shows "Disconnected" if no device or disconnected, "Connecting..." if connecting,
        /// and the full radio display if connected.
        /// </summary>
        private void UpdateDisplayForCurrentState()
        {
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.BeginInvoke(new Action(UpdateDisplayForCurrentState)); return; }

            if (_deviceId <= 0 || currentState == null)
            {
                // No device assigned - show disconnected state
                ShowDisconnectedState("Disconnected");
                return;
            }

            switch (currentState)
            {
                case "Disconnected":
                case "NotRadioFound":
                case "BluetoothNotAvailable":
                    ShowDisconnectedState("Disconnected");
                    break;
                case "Connecting":
                    ShowConnectingState();
                    break;
                case "Connected":
                    ShowConnectedState();
                    break;
                case "UnableToConnect":
                    ShowDisconnectedState("Unable to Connect");
                    break;
                case "AccessDenied":
                    ShowDisconnectedState("Access Denied");
                    break;
                case "MultiRadioSelect":
                    ShowDisconnectedState("Select Radio");
                    break;
                default:
                    ShowDisconnectedState(currentState);
                    break;
            }
        }

        /// <summary>
        /// Paint event handler for the PictureBox to draw the FriendlyName on top of the image.
        /// </summary>
        private void RadioPictureBox_Paint(object sender, PaintEventArgs e)
        {
            // Draw the FriendlyName if available
            if (!string.IsNullOrEmpty(_friendlyName))
            {
                using (Font font = new Font("Microsoft Sans Serif", 14, FontStyle.Regular, GraphicsUnit.Pixel))
                using (Brush brush = new SolidBrush(Color.Gray))
                {
                    // Measure the string to center it horizontally within the PictureBox
                    SizeF textSize = e.Graphics.MeasureString(_friendlyName, font);
                    float x = ((radioPictureBox.ClientSize.Width - textSize.Width) / 2) + 4;
                    float y = 106;

                    // Draw the text on top of the image
                    e.Graphics.DrawString(_friendlyName, font, brush, x, y);
                }
            }
        }

        /// <summary>
        /// Shows the disconnected state with the specified message.
        /// </summary>
        private void ShowDisconnectedState(string message)
        {
            radioStateLabel.Text = message;
            radioStateLabel.Visible = true;
            connectedPanel.Visible = false;
            connectButton.Visible = true;
            rssiProgressBar.Visible = false;
            transmitBarPanel.Visible = false;
            voiceProcessingLabel.Visible = false;
        }

        /// <summary>
        /// Shows the connecting state.
        /// </summary>
        private void ShowConnectingState()
        {
            radioStateLabel.Text = "Connecting...";
            radioStateLabel.Visible = true;
            connectedPanel.Visible = false;
            connectButton.Visible = false;
            rssiProgressBar.Visible = false;
            transmitBarPanel.Visible = false;
            voiceProcessingLabel.Visible = false;
        }

        /// <summary>
        /// Shows the connected state with full radio display.
        /// </summary>
        private void ShowConnectedState()
        {
            radioStateLabel.Visible = false;
            connectedPanel.Visible = true;
            connectButton.Visible = false;
            rssiProgressBar.Visible = false;

            // Update the full display
            UpdateRadioDisplay();
            UpdateChannelsPanel();
            UpdateGpsStatusDisplay();
        }

        public void UpdateChannelsPanel()
        {
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.BeginInvoke(new Action(UpdateChannelsPanel)); return; }

            if (currentChannels == null || currentChannels.Length == 0)
            {
                channelsFlowLayoutPanel.Visible = false;
                return;
            }

            channelsFlowLayoutPanel.SuspendLayout();
            int visibleChannels = 0;
            int channelHeight = 0;

            // Initialize channel controls array if needed
            if (channelControls == null || channelControls.Length != currentChannels.Length)
            {
                channelControls = new RadioChannelControl[currentChannels.Length];
            }

            for (int i = 0; i < currentChannels.Length; i++)
            {
                if (currentChannels[i] != null)
                {
                    if (channelControls[i] == null)
                    {
                        channelControls[i] = new RadioChannelControl(this);
                        channelsFlowLayoutPanel.Controls.Add(channelControls[i]);
                    }
                    channelControls[i].Channel = currentChannels[i];
                    channelControls[i].Tag = i;

                    // Show channels that have a name or frequency, or if ShowAllChannels is enabled
                    bool visible = _showAllChannels || (currentChannels[i].name_str.Length > 0) || (currentChannels[i].rx_freq != 0);
                    channelControls[i].Visible = visible;
                    if (visible) { visibleChannels++; }
                    channelHeight = channelControls[i].Height;
                }
            }

            int hBlockCount = ((visibleChannels / 3) + (((visibleChannels % 3) != 0) ? 1 : 0));
            int blockHeight = 0;
            if (hBlockCount > 0)
            {
                blockHeight = (this.Height - 340) / hBlockCount;
                if (blockHeight > 50) { blockHeight = 50; }
                for (int i = 0; i < channelControls.Length; i++)
                {
                    if (channelControls[i] != null) { channelControls[i].Height = blockHeight; }
                }
            }
            channelsFlowLayoutPanel.Height = blockHeight * hBlockCount;
            channelsFlowLayoutPanel.Visible = (visibleChannels > 0);
            channelsFlowLayoutPanel.ResumeLayout();
        }

        public void UpdateRadioDisplay()
        {
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.BeginInvoke(new Action(UpdateRadioDisplay)); return; }

            if (currentSettings == null) return;

            if (currentChannels != null)
            {
                RadioChannelInfo channelA = null;
                RadioChannelInfo channelB = null;

                // Get channel A from settings
                if ((currentSettings.channel_a >= 0) && (currentSettings.channel_a < currentChannels.Length))
                {
                    channelA = currentChannels[currentSettings.channel_a];
                }
                // Get channel B from settings
                if ((currentSettings.channel_b >= 0) && (currentSettings.channel_b < currentChannels.Length))
                {
                    channelB = currentChannels[currentSettings.channel_b];
                }

                // Update channel control highlighting
                if (channelControls != null)
                {
                    foreach (RadioChannelControl c in channelControls)
                    {
                        if (c == null) continue;
                        if ((channelA != null) && (((int)c.Tag) == channelA.channel_id))
                        {
                            c.BackColor = Color.PaleGoldenrod;
                        }
                        else if ((channelB != null) && (currentSettings.double_channel == 1) && (((int)c.Tag) == channelB.channel_id))
                        {
                            c.BackColor = Color.PaleGoldenrod;
                        }
                        else
                        {
                            c.BackColor = Color.DarkKhaki;
                        }
                    }
                }

                // Update VFO1 display (Channel A)
                if (channelA != null)
                {
                    if (channelA.name_str.Length > 0)
                    {
                        vfo1Label.Text = channelA.name_str;
                        vfo1FreqLabel.Text = (((float)channelA.rx_freq) / 1000000).ToString("F3") + " MHz";
                    }
                    else if (channelA.rx_freq > 0)
                    {
                        vfo1Label.Text = ((double)channelA.rx_freq / 1000000).ToString("F3");
                        vfo1FreqLabel.Text = " MHz";
                    }
                    else
                    {
                        vfo1Label.Text = "Empty";
                        vfo1FreqLabel.Text = "";
                    }
                    vfo1StatusLabel.Text = "";
                }
                else
                {
                    vfo1Label.Text = "";
                    vfo1FreqLabel.Text = "";
                    vfo1StatusLabel.Text = "";
                }

                // Update VFO2 display (Channel B or scanning)
                if (currentSettings.scan == true)
                {
                    // Scanning mode
                    if ((currentHtStatus != null) && (currentChannels != null) && (currentChannels.Length > currentHtStatus.curr_ch_id) && (currentChannels[currentHtStatus.curr_ch_id] != null))
                    {
                        if (currentChannels[currentHtStatus.curr_ch_id] == channelA)
                        {
                            if (vfo2LastChannelId >= 0 && vfo2LastChannelId < currentChannels.Length && currentChannels[vfo2LastChannelId] != null)
                            {
                                channelB = currentChannels[vfo2LastChannelId];
                                vfo2Label.Text = channelB.name_str;
                                vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
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
                            channelB = currentChannels[currentHtStatus.curr_ch_id];
                            vfo2Label.Text = channelB.name_str;
                            vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                            vfo2StatusLabel.Text = "Scanning...";
                            vfo2LastChannelId = currentHtStatus.curr_ch_id;
                        }
                    }
                    else
                    {
                        vfo2Label.Text = "Scanning...";
                        vfo2FreqLabel.Text = "";
                        vfo2StatusLabel.Text = "";
                    }
                }
                else if ((currentSettings.double_channel == 1) && (channelB != null))
                {
                    // Dual channel mode
                    if (channelB.name_str.Length > 0)
                    {
                        vfo2Label.Text = channelB.name_str;
                        vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                    }
                    else if (channelB.rx_freq != 0)
                    {
                        vfo2Label.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3");
                        vfo2FreqLabel.Text = " MHz";
                    }
                    else
                    {
                        vfo2Label.Text = "Empty";
                        vfo2FreqLabel.Text = "";
                    }
                    vfo2StatusLabel.Text = "";
                }
                else
                {
                    // Single channel mode - clear VFO2
                    vfo2Label.Text = "";
                    vfo2FreqLabel.Text = "";
                    vfo2StatusLabel.Text = "";
                }

                // Update RSSI if HtStatus is available
                if (currentHtStatus != null)
                {
                    // RSSI is 0-16. rssiProgressBar maximum is set to 16
                    rssiProgressBar.Value = currentHtStatus.rssi;
                    rssiProgressBar.Visible = (currentHtStatus.rssi > 0);
                }

                // Update the VFO colors based on RX/TX state
                if ((channelB != null) && (currentState == "Connected") && (currentHtStatus != null) && (currentHtStatus.double_channel == Radio.RadioChannelType.A))
                {
                    if ((currentHtStatus.is_in_rx || currentHtStatus.is_in_tx) && (currentHtStatus.curr_ch_id == channelB.channel_id))
                    {
                        vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                        vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.FromArgb(221, 211, 0);
                    }
                    else
                    {
                        vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.FromArgb(221, 211, 0);
                        vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
                    }
                }
                else
                {
                    vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                    vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
                }
            }
            else
            {
                // No channels available - clear display
                vfo1Label.Text = "";
                vfo1FreqLabel.Text = "";
                vfo1StatusLabel.Text = "";
                vfo2Label.Text = "";
                vfo2FreqLabel.Text = "";
                vfo2StatusLabel.Text = "";
                vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
            }

            AdjustVfoLabel(vfo1Label);
            AdjustVfoLabel(vfo2Label);
        }

        private void AdjustVfoLabel(Label label)
        {
            // Initial font size.
            float fontSize = 20;
            label.Font = new Font(label.Font.FontFamily, fontSize);

            // Create a Graphics object to measure the text.
            using (Graphics g = label.CreateGraphics())
            {
                // Measure the text width.
                SizeF textSize = g.MeasureString(label.Text, new Font(label.Font.FontFamily, fontSize));

                // While the text width exceeds the label width, reduce the font size.
                while (textSize.Width > label.ClientSize.Width && fontSize > 1)
                {
                    fontSize -= 1;
                    label.Font = new Font(label.Font.FontFamily, fontSize);
                    textSize = g.MeasureString(label.Text, label.Font);
                }
            }
        }

        private void connectButton_Click(object sender, EventArgs e)
        {
            // This is a message to the mainform.cs to connect a radio
            DataBroker.Dispatch(1, "RadioConnect", true, store: false);
        }

        private void radioPictureBox_Click(object sender, EventArgs e)
        {
            //if (parent != null) { parent.volumeToolStripMenuItem_Click(sender, e); }
        }

        private void radioPictureBox_DragEnter(object sender, DragEventArgs e)
        {
            /*
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else if ((files.Length == 1) && (files[0].ToLower().EndsWith(".wav") && parent != null && parent.allowTransmit && (parent.radio.State == Radio.RadioState.Connected)))
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else
                {
                    e.Effect = DragDropEffects.None;
                }
            }
            */
        }

        private void radioPictureBox_DragDrop(object sender, DragEventArgs e)
        {
            /*
            if (parent == null) return;
            
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    //parent.importChannels(files[0]);
                }
                else if ((files.Length == 1) && (files[0].ToLower().EndsWith(".wav")))
                {
                    // Transmit the wav file
                    using (var reader = new WaveFileReader(files[0]))
                    {
                        var buffer = new byte[reader.Length];
                        int bytesRead = reader.Read(buffer, 0, buffer.Length);
                        //parent.radio.TransmitVoice(buffer, 0, bytesRead, true);
                    }
                }
            }
            */
        }

        private void radioPanel_SizeChanged(object sender, EventArgs e)
        {
            UpdateChannelsPanel();
        }

        private void gpsStatusLabel_DoubleClick(object sender, EventArgs e)
        {
            //if (parent != null) { parent.radioPositionToolStripMenuItem_Click(sender, e); }
        }

        // Event that parent can subscribe to for bluetooth check
        public event EventHandler CheckBluetoothRequested;

        protected virtual void OnCheckBluetoothRequested()
        {
            CheckBluetoothRequested?.Invoke(this, EventArgs.Empty);
        }

        private void checkBluetoothButton_ClickInternal(object sender, EventArgs e)
        {
            OnCheckBluetoothRequested();
        }


        private void UpdateGpsStatusDisplay()
        {
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.BeginInvoke(new Action(UpdateGpsStatusDisplay)); return; }

            // If GPS is not enabled, display nothing
            if (!_gpsEnabled)
            {
                gpsStatusLabel.Text = "";
                return;
            }

            // GPS is enabled - check if we have a position
            if (_position == null)
            {
                gpsStatusLabel.Text = "No GPS Lock";
            }
            else
            {
                // Check if position has a valid GPS lock
                if (_position.Locked)
                {
                    gpsStatusLabel.Text = "GPS Lock";
                }
                else
                {
                    gpsStatusLabel.Text = "No GPS Lock";
                }
            }
        }

        /// <summary>
        /// Gets the current VFO A channel ID from the cached settings.
        /// </summary>
        /// <returns>The channel ID for VFO A, or null if settings are not available.</returns>
        public int? GetCurrentChannelA()
        {
            if (currentSettings == null) return null;
            return currentSettings.channel_a;
        }

        /// <summary>
        /// Gets the current VFO B channel ID from the cached settings.
        /// </summary>
        /// <returns>The channel ID for VFO B, or null if settings are not available.</returns>
        public int? GetCurrentChannelB()
        {
            if (currentSettings == null) return null;
            return currentSettings.channel_b;
        }

        /// <summary>
        /// Changes the VFO A channel to the specified channel ID.
        /// Dispatches a ChannelChangeVfoA event to the broker.
        /// </summary>
        /// <param name="channelId">The channel ID to switch VFO A to.</param>
        public void ChangeChannelA(int channelId)
        {
            if (_deviceId <= 0) return;
            broker.Dispatch(_deviceId, "ChannelChangeVfoA", channelId, store: false);
        }

        /// <summary>
        /// Changes the VFO B channel to the specified channel ID.
        /// Dispatches a ChannelChangeVfoB event to the broker.
        /// </summary>
        /// <param name="channelId">The channel ID to switch VFO B to.</param>
        public void ChangeChannelB(int channelId)
        {
            if (_deviceId <= 0) return;
            broker.Dispatch(_deviceId, "ChannelChangeVfoB", channelId, store: false);
        }

        /// <summary>
        /// Gets or sets whether all channels should be shown, including empty ones.
        /// </summary>
        public bool ShowAllChannels
        {
            get { return _showAllChannels; }
            set
            {
                if (_showAllChannels == value) return;
                _showAllChannels = value;
                UpdateChannelsPanel();
            }
        }
    }
}
