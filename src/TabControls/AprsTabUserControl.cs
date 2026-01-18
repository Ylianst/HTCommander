/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Linq;
using System.Windows.Forms;
using System.Collections.Generic;
using aprsparser;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class AprsTabUserControl : UserControl
    {
        #region Fields

        private ChatMessage rightClickedMessage = null;
        private ChatMessage selectedAprsMessage = null;
        private AprsDetailsForm aprsDetailsForm = null;
        private List<string[]> aprsRoutes = new List<string[]>();
        private int selectedAprsRoute = 0;
        private bool _showDetach = false;
        private DataBrokerClient _broker;
        private string _callsign = "";
        private string _stationId = "";
        private bool _initializing = true;
        private HashSet<int> _subscribedRadioDeviceIds = new HashSet<int>();
        private List<StationInfoClass> _cachedStations = new List<StationInfoClass>();
        private bool _hasAprsChannel = false;

        #endregion

        #region Constructor

        public AprsTabUserControl()
        {
            InitializeComponent();

            // Setup routes combobox
            UpdateAprsRoutesComboBox();

            // Disable transmit menu items by default (enabled when APRS channel is detected)
            smSMessageToolStripMenuItem.Enabled = false;
            weatherReportToolStripMenuItem.Enabled = false;

            // Initialize the Data Broker client and subscribe to APRS events
            _broker = new DataBrokerClient();
            _broker.Subscribe(1, "AprsFrame", OnAprsFrame);
            _broker.Subscribe(1, "AprsStoreReady", OnAprsStoreReady);

            // Subscribe to settings changes from device 0
            _broker.Subscribe(0, new[] { "CallSign", "StationId", "AprsRoutes", "AllowTransmit" }, OnSettingsChanged);

            // Subscribe to Stations changes to populate APRS destination combobox
            _broker.Subscribe(0, "Stations", OnStationsChanged);

            // Load initial values from DataBroker
            _callsign = _broker.GetValue<string>(0, "CallSign", "");
            int stationIdInt = _broker.GetValue<int>(0, "StationId", 0);
            _stationId = stationIdInt > 0 ? stationIdInt.ToString() : "";

            // Load APRS routes from DataBroker
            string aprsRoutesStr = _broker.GetValue<string>(0, "AprsRoutes", "");
            ParseAndSetAprsRoutes(aprsRoutesStr);

            // Load selected APRS route from DataBroker
            selectedAprsRoute = _broker.GetValue<int>(0, "SelectedAprsRoute", 0);
            if (selectedAprsRoute >= aprsRoutes.Count) { selectedAprsRoute = 0; }
            if (aprsRouteComboBox.Items.Count > 0)
            {
                aprsRouteComboBox.SelectedIndex = selectedAprsRoute;
            }

            // Load AprsShowTelemetry setting from DataBroker
            bool showTelemetry = _broker.GetValue<int>(0, "AprsShowTelemetry", 0) == 1;
            showAllMessagesToolStripMenuItem.Checked = showTelemetry;

            // Load initial APRS stations for destination combobox
            List<StationInfoClass> stations = _broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());
            UpdateAprsDestinationComboBox(stations);

            // Load saved APRS destination from DataBroker
            string savedDestination = _broker.GetValue<string>(0, "AprsDestination", "");
            if (!string.IsNullOrEmpty(savedDestination))
            {
                aprsDestinationComboBox.Text = savedDestination;
            }

            // Check if the store is already ready (in case we subscribed after it was dispatched)
            if (_broker.HasValue(1, "AprsStoreReady"))
            {
                List<AprsPacket> historicalPackets = _broker.GetValue<List<AprsPacket>>(1, "AprsStoreReady", null);
                if (historicalPackets != null)
                {
                    LoadHistoricalAprsPackets(historicalPackets);
                }
            }

            // Subscribe to ConnectedRadios changes to track radio connections and check for APRS channel
            _broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Check initial connected radios state
            CheckInitialConnectedRadios();

            // Load initial AllowTransmit value and update bottom panel visibility
            int allowTransmitInt = _broker.GetValue<int>(0, "AllowTransmit", 0);
            UpdateBottomPanelVisibility(allowTransmitInt == 1);

            // Initialization complete - allow event handlers to save settings
            _initializing = false;
        }

        #endregion

        #region Properties

        /// <summary>
        /// Gets or sets the local callsign (without station ID).
        /// </summary>
        public string Callsign
        {
            get { return _callsign; }
            set { _callsign = value ?? ""; }
        }

        /// <summary>
        /// Gets or sets the station ID.
        /// </summary>
        public string StationId
        {
            get { return _stationId; }
            set { _stationId = value ?? ""; }
        }

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

        /// <summary>
        /// Gets or sets the index of the currently selected APRS route.
        /// </summary>
        public int SelectedAprsRoute
        {
            get { return selectedAprsRoute; }
            set { selectedAprsRoute = value; }
        }

        #endregion

        #region Public Methods

        /// <summary>
        /// Sets the visibility of the missing channel panel.
        /// </summary>
        public void SetMissingChannelVisible(bool visible)
        {
            aprsMissingChannelPanel.Visible = visible;
        }

        /// <summary>
        /// Enables or disables the APRS input controls.
        /// </summary>
        public void SetControlsEnabled(bool enabled)
        {
            aprsTextBox.Enabled = enabled;
            aprsSendButton.Enabled = enabled;
            aprsDestinationComboBox.Enabled = enabled;
        }

        /// <summary>
        /// Adds a callsign to the destination combobox if not already present.
        /// </summary>
        public void AddDestinationCallsign(string callsign)
        {
            if (!aprsDestinationComboBox.Items.Contains(callsign))
            {
                aprsDestinationComboBox.Items.Add(callsign);
            }
        }

        /// <summary>
        /// Updates the APRS routes combobox with the current routes list.
        /// </summary>
        public void UpdateAprsRoutesComboBox()
        {
            aprsRouteComboBox.Items.Clear();
            if (aprsRoutes.Count > 0)
            {
                foreach (string[] route in aprsRoutes)
                {
                    aprsRouteComboBox.Items.Add(route[0]);
                }
                if (selectedAprsRoute >= aprsRoutes.Count) { selectedAprsRoute = 0; }
                aprsRouteComboBox.SelectedIndex = selectedAprsRoute;
                aprsRouteComboBox.Visible = (aprsRoutes.Count > 1);
            }
            else
            {
                aprsRouteComboBox.Visible = false;
            }
        }

        /// <summary>
        /// Gets the currently selected APRS route.
        /// </summary>
        /// <returns>The route array, or null if no routes are configured.</returns>
        public string[] GetSelectedRoute()
        {
            if (aprsRoutes.Count == 0) return null;
            if (selectedAprsRoute >= aprsRoutes.Count) selectedAprsRoute = 0;
            return aprsRoutes[selectedAprsRoute];
        }

        /// <summary>
        /// Adds an APRS packet to the chat control.
        /// </summary>
        /// <param name="aprsPacket">The APRS packet to add.</param>
        /// <param name="sender">True if we are the sender of this packet.</param>
        public void AddAprsPacket(AprsPacket aprsPacket, bool sender)
        {
            string MessageId = null;
            string MessageText = null;
            PacketDataType MessageType = PacketDataType.Message;
            string RoutingString = null;
            string SenderCallsign = null;
            AX25Address SenderAddr = null;
            int ImageIndex = -1;
            AX25Packet packet = aprsPacket.Packet;

            // Extract sender information
            SenderAddr = packet.addresses[1];
            RoutingString = SenderAddr.ToString();
            SenderCallsign = SenderAddr.CallSignWithId;
            if ((aprsPacket.Position != null) && (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) && (aprsPacket.Position.CoordinateSet.Longitude.Value != 0))
            {
                ImageIndex = 3;
            }

            MessageType = aprsPacket.DataType;
            if (aprsPacket.DataType == PacketDataType.Message)
            {
                string localCallsignWithId = string.IsNullOrEmpty(_stationId) ? _callsign : _callsign + "-" + _stationId;
                bool forSelf = ((aprsPacket.MessageData.Addressee == _callsign) || (aprsPacket.MessageData.Addressee == localCallsignWithId));

                // Handle ACK messages
                if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtAck)
                {
                    if (forSelf)
                    {
                        foreach (ChatMessage n in aprsChatControl.Messages)
                        {
                            if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId))
                            {
                                if ((n.AuthState == AX25Packet.AuthState.Unknown) ||
                                    ((n.AuthState == AX25Packet.AuthState.Success) && (aprsPacket.Packet.authState == AX25Packet.AuthState.Success)) ||
                                    ((n.AuthState == AX25Packet.AuthState.None) && (aprsPacket.Packet.authState == AX25Packet.AuthState.None)))
                                {
                                    n.ImageIndex = 0;
                                }
                            }
                        }
                    }
                    return;
                }
                // Handle REJ messages
                else if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtRej)
                {
                    if (forSelf)
                    {
                        foreach (ChatMessage n in aprsChatControl.Messages)
                        {
                            if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId))
                            {
                                if ((n.AuthState == AX25Packet.AuthState.Unknown) ||
                                    ((n.AuthState == AX25Packet.AuthState.Success) && (aprsPacket.Packet.authState == AX25Packet.AuthState.Success)) ||
                                    ((n.AuthState == AX25Packet.AuthState.None) && (aprsPacket.Packet.authState == AX25Packet.AuthState.None)))
                                {
                                    n.ImageIndex = 1;
                                }
                            }
                        }
                    }
                    return;
                }

                // Normal message processing
                if (sender)
                {
                    RoutingString = "→ " + aprsPacket.MessageData.Addressee;
                    if (packet.authState == AX25Packet.AuthState.Success) { RoutingString += " ✓"; }
                    if (packet.authState == AX25Packet.AuthState.Failed) { RoutingString += " ❌"; }
                }
                else
                {
                    if ((SenderAddr.address == aprsPacket.MessageData.Addressee) || (SenderAddr.CallSignWithId == aprsPacket.MessageData.Addressee))
                    {
                        RoutingString = aprsPacket.MessageData.Addressee;
                    }
                    else
                    {
                        RoutingString = SenderCallsign + " → " + aprsPacket.MessageData.Addressee;
                    }
                    if (packet.authState == AX25Packet.AuthState.Success) { RoutingString += " ✓"; }
                    if (packet.authState == AX25Packet.AuthState.Failed) { RoutingString += " ❌"; }
                }
                MessageId = aprsPacket.MessageData.SeqId;
                MessageText = aprsPacket.MessageData.MsgText;

                // Handle SMS messages with special formatting
                if ((aprsPacket.MessageData.Addressee == "SMS") && (aprsPacket.MessageData.MsgText.Length > 12) && (aprsPacket.MessageData.MsgText[0] == '@'))
                {
                    int i = aprsPacket.MessageData.MsgText.IndexOf(" ");
                    if (i >= 0)
                    {
                        RoutingString = "→ SMS: " + aprsPacket.MessageData.MsgText.Substring(1, i);
                        MessageId = aprsPacket.MessageData.SeqId;
                        MessageText = aprsPacket.MessageData.MsgText.Substring(i + 1);
                    }
                }

                // Check for duplicate messages
                if (MessageId != null)
                {
                    foreach (ChatMessage n in aprsChatControl.Messages)
                    {
                        if ((n.MessageId == MessageId) && (n.Route == RoutingString) && (n.Message == MessageText)) return;
                    }
                }
            }
            else
            {
                // Non-message packets (telemetry, status, etc.)
                if ((aprsPacket.Comment != null) && ((aprsPacket.DataType != PacketDataType.MicE) && (aprsPacket.DataType != PacketDataType.MicECurrent) && (aprsPacket.DataType != PacketDataType.MicEOld)))
                {
                    MessageText = aprsPacket.Comment;
                }
            }

            // Handle single-address packets
            if ((packet.addresses != null) && (packet.addresses.Count == 1))
            {
                AX25Address addr = packet.addresses[0];
                SenderCallsign = RoutingString = addr.ToString();
                MessageText = packet.dataStr;
            }

            // Add the message to the chat control if there's text
            if ((MessageText != null) && (MessageText.Trim().Length > 0))
            {
                ChatMessage c = new ChatMessage(RoutingString, SenderCallsign, MessageText.Trim(), packet.time, sender, -1);
                c.Tag = packet;
                c.MessageId = MessageId;
                c.MessageType = MessageType;
                c.Visible = showAllMessagesToolStripMenuItem.Checked || (c.MessageType == PacketDataType.Message);
                c.ImageIndex = ImageIndex;
                c.AuthState = packet.authState;

                // Check for duplicate messages within the last 5 minutes
                foreach (ChatMessage chatMessage2 in aprsChatControl.Messages)
                {
                    AX25Packet packet2 = (AX25Packet)chatMessage2.Tag;
                    if ((c.Message == chatMessage2.Message) && (packet2.time.AddMinutes(5).CompareTo(packet.time) > 0) && (c.Time != packet2.time))
                    {
                        return;
                    }
                }

                // Add the message
                aprsChatControl.Messages.Add(c);
                if (c.Visible) { aprsChatControl.UpdateMessages(true); }

                // Store position data if available
                if ((c.ImageIndex == 3) && (aprsPacket != null))
                {
                    c.Latitude = aprsPacket.Position.CoordinateSet.Latitude.Value;
                    c.Longitude = aprsPacket.Position.CoordinateSet.Longitude.Value;
                }
            }
        }

        #endregion

        #region UI State Management

        /// <summary>
        /// Updates the visibility of transmit-related controls based on AllowTransmit setting.
        /// </summary>
        private void UpdateBottomPanelVisibility(bool allowTransmit)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<bool>(UpdateBottomPanelVisibility), allowTransmit);
                return;
            }

            aprsBottomPanel.Visible = allowTransmit;
            aprsRouteComboBox.Visible = allowTransmit && (aprsRoutes.Count > 1);

            beaconSettingsToolStripMenuItem.Visible = allowTransmit;
            smSMessageToolStripMenuItem.Visible = allowTransmit;
            weatherReportToolStripMenuItem.Visible = allowTransmit;
            toolStripMenuItem7.Visible = allowTransmit;
        }

        /// <summary>
        /// Updates the visibility of the missing channel panel based on connected radios and their channels.
        /// </summary>
        private void UpdateMissingChannelPanelVisibility()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(UpdateMissingChannelPanelVisibility));
                return;
            }

            if (_subscribedRadioDeviceIds.Count == 0)
            {
                aprsMissingChannelPanel.Visible = false;
                _hasAprsChannel = false;
                smSMessageToolStripMenuItem.Enabled = false;
                weatherReportToolStripMenuItem.Enabled = false;
                return;
            }

            bool hasAprsChannel = false;
            bool hasRadioWithAllChannelsLoaded = false;

            foreach (int deviceId in _subscribedRadioDeviceIds)
            {
                bool allChannelsLoaded = _broker.GetValue<bool>(deviceId, "AllChannelsLoaded", false);
                if (!allChannelsLoaded) continue;

                hasRadioWithAllChannelsLoaded = true;

                RadioChannelInfo[] channels = _broker.GetValue<RadioChannelInfo[]>(deviceId, "Channels", null);
                if (channels != null)
                {
                    foreach (RadioChannelInfo channel in channels)
                    {
                        if (channel != null &&
                            !string.IsNullOrEmpty(channel.name_str) &&
                            channel.name_str.Equals("APRS", StringComparison.OrdinalIgnoreCase))
                        {
                            hasAprsChannel = true;
                            break;
                        }
                    }
                }
                if (hasAprsChannel) break;
            }

            aprsMissingChannelPanel.Visible = hasRadioWithAllChannelsLoaded && !hasAprsChannel;
            _hasAprsChannel = hasAprsChannel;

            aprsTextBox.Enabled = hasAprsChannel;
            aprsDestinationComboBox.Enabled = hasAprsChannel;

            // Enable/disable transmit menu items based on APRS channel availability
            smSMessageToolStripMenuItem.Enabled = hasAprsChannel;
            weatherReportToolStripMenuItem.Enabled = hasAprsChannel;

            UpdateSendButtonState();
        }

        /// <summary>
        /// Updates the enabled state of the send button.
        /// </summary>
        private void UpdateSendButtonState()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(UpdateSendButtonState));
                return;
            }

            bool canSend = _hasAprsChannel &&
                           IsValidCallsign(aprsDestinationComboBox.Text) &&
                           !string.IsNullOrWhiteSpace(aprsTextBox.Text);

            aprsSendButton.Enabled = canSend;
        }

        #endregion

        #region Radio and Channel Management

        /// <summary>
        /// Checks the initial connected radios state and subscribes to their channel events.
        /// </summary>
        private void CheckInitialConnectedRadios()
        {
            var connectedRadios = _broker.GetValue<object>(1, "ConnectedRadios", null);
            if (connectedRadios != null)
            {
                OnConnectedRadiosChanged(1, "ConnectedRadios", connectedRadios);
            }
            else
            {
                UpdateMissingChannelPanelVisibility();
            }
        }

        /// <summary>
        /// Gets the device ID of the preferred radio for APRS transmission.
        /// </summary>
        /// <returns>The device ID of the preferred APRS radio, or -1 if none found.</returns>
        private int GetPreferredAprsRadioDeviceId()
        {
            int preferredDeviceId = -1;

            foreach (int deviceId in _subscribedRadioDeviceIds)
            {
                bool allChannelsLoaded = _broker.GetValue<bool>(deviceId, "AllChannelsLoaded", false);
                if (!allChannelsLoaded) continue;

                RadioChannelInfo[] channels = _broker.GetValue<RadioChannelInfo[]>(deviceId, "Channels", null);
                if (channels != null)
                {
                    foreach (RadioChannelInfo channel in channels)
                    {
                        if (channel != null &&
                            !string.IsNullOrEmpty(channel.name_str) &&
                            channel.name_str.Equals("APRS", StringComparison.OrdinalIgnoreCase))
                        {
                            if (preferredDeviceId == -1 || deviceId < preferredDeviceId)
                            {
                                preferredDeviceId = deviceId;
                            }
                            break;
                        }
                    }
                }
            }

            return preferredDeviceId;
        }

        #endregion

        #region Validation Helpers

        /// <summary>
        /// Checks if the given string is a valid amateur radio callsign.
        /// </summary>
        private bool IsValidCallsign(string callsign)
        {
            if (string.IsNullOrWhiteSpace(callsign)) return false;

            string trimmed = callsign.Trim();
            if (trimmed.Length < 3) return false;

            bool hasLetter = false;
            bool hasDigit = false;

            foreach (char c in trimmed)
            {
                if (char.IsLetter(c)) hasLetter = true;
                if (char.IsDigit(c)) hasDigit = true;
            }

            return hasLetter && hasDigit;
        }

        #endregion

        #region DataBroker Event Handlers

        /// <summary>
        /// Handles ConnectedRadios changes from the DataBroker.
        /// </summary>
        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnConnectedRadiosChanged), deviceId, name, data);
                return;
            }

            HashSet<int> currentDeviceIds = new HashSet<int>();

            if (data is System.Collections.IEnumerable radioList)
            {
                foreach (var radio in radioList)
                {
                    var radioType = radio.GetType();
                    var deviceIdProp = radioType.GetProperty("DeviceId");
                    if (deviceIdProp != null)
                    {
                        int radioDeviceId = (int)deviceIdProp.GetValue(radio);
                        currentDeviceIds.Add(radioDeviceId);
                    }
                }
            }

            // Unsubscribe from disconnected radios
            foreach (int oldDeviceId in _subscribedRadioDeviceIds.ToList())
            {
                if (!currentDeviceIds.Contains(oldDeviceId))
                {
                    _subscribedRadioDeviceIds.Remove(oldDeviceId);
                }
            }

            // Subscribe to new radios
            foreach (int newDeviceId in currentDeviceIds)
            {
                if (!_subscribedRadioDeviceIds.Contains(newDeviceId))
                {
                    _subscribedRadioDeviceIds.Add(newDeviceId);
                    _broker.Subscribe(newDeviceId, "Channels", OnRadioChannelsChanged);
                    _broker.Subscribe(newDeviceId, "AllChannelsLoaded", OnAllChannelsLoadedChanged);
                }
            }

            UpdateMissingChannelPanelVisibility();
        }

        /// <summary>
        /// Handles Channels changes from a radio device.
        /// </summary>
        private void OnRadioChannelsChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnRadioChannelsChanged), deviceId, name, data);
                return;
            }

            UpdateMissingChannelPanelVisibility();
        }

        /// <summary>
        /// Handles AllChannelsLoaded changes from a radio device.
        /// </summary>
        private void OnAllChannelsLoadedChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnAllChannelsLoadedChanged), deviceId, name, data);
                return;
            }

            UpdateMissingChannelPanelVisibility();
        }

        /// <summary>
        /// Handles Stations changes from the DataBroker to update APRS destination combobox.
        /// </summary>
        private void OnStationsChanged(int deviceId, string name, object data)
        {
            if (data is List<StationInfoClass> stations)
            {
                UpdateAprsDestinationComboBox(stations);
            }
        }

        /// <summary>
        /// Handles settings changes from the DataBroker.
        /// </summary>
        private void OnSettingsChanged(int deviceId, string name, object data)
        {
            if (name == "CallSign")
            {
                _callsign = data as string ?? "";
            }
            else if (name == "StationId")
            {
                if (data is int stationIdInt)
                {
                    _stationId = stationIdInt > 0 ? stationIdInt.ToString() : "";
                }
            }
            else if (name == "AprsRoutes")
            {
                ParseAndSetAprsRoutes(data as string ?? "");
            }
            else if (name == "AllowTransmit")
            {
                if (data is int allowTransmitInt)
                {
                    UpdateBottomPanelVisibility(allowTransmitInt == 1);
                }
            }
        }

        /// <summary>
        /// Handles the AprsStoreReady event - loads historical APRS packets.
        /// </summary>
        private void OnAprsStoreReady(int deviceId, string name, object data)
        {
            if (!(data is List<AprsPacket> historicalPackets)) return;
            LoadHistoricalAprsPackets(historicalPackets);
        }

        /// <summary>
        /// Handles incoming AprsFrame events from the Data Broker.
        /// </summary>
        private void OnAprsFrame(int deviceId, string name, object data)
        {
            if (!(data is AprsFrameEventArgs args)) return;
            if (args.AX25Packet == null) return;

            bool isSender = false;
            if (args.AX25Packet.addresses != null && args.AX25Packet.addresses.Count >= 2)
            {
                string srcCallsign = args.AX25Packet.addresses[1].CallSignWithId;
                string localCallsignWithId = string.IsNullOrEmpty(_stationId) ? _callsign : _callsign + "-" + _stationId;
                if (!string.IsNullOrEmpty(localCallsignWithId) &&
                    srcCallsign.Equals(localCallsignWithId, StringComparison.OrdinalIgnoreCase))
                {
                    isSender = true;
                }
            }

            AddAprsPacket(args.AprsPacket, isSender);
        }

        #endregion

        #region Helper Methods

        /// <summary>
        /// Updates the APRS destination combobox with APRS stations from the contact list.
        /// </summary>
        private void UpdateAprsDestinationComboBox(List<StationInfoClass> stations)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<List<StationInfoClass>>(UpdateAprsDestinationComboBox), stations);
                return;
            }

            _cachedStations = stations ?? new List<StationInfoClass>();
            string currentText = aprsDestinationComboBox.Text;

            aprsDestinationComboBox.Items.Clear();
            foreach (StationInfoClass station in stations)
            {
                if (station.StationType == StationInfoClass.StationTypes.APRS)
                {
                    string callsign = station.CallsignNoZero;
                    if (!aprsDestinationComboBox.Items.Contains(callsign))
                    {
                        aprsDestinationComboBox.Items.Add(callsign);
                    }
                }
            }

            aprsDestinationComboBox.Text = currentText;
        }

        /// <summary>
        /// Parses the APRS routes string from the DataBroker and updates the routes list.
        /// </summary>
        private void ParseAndSetAprsRoutes(string routesStr)
        {
            aprsRoutes.Clear();

            if (string.IsNullOrEmpty(routesStr))
            {
                UpdateAprsRoutesComboBox();
                return;
            }

            string[] routes = routesStr.Split('|');
            foreach (string route in routes)
            {
                if (!string.IsNullOrEmpty(route))
                {
                    string[] routeParts = route.Split(',');
                    if (routeParts.Length >= 2)
                    {
                        aprsRoutes.Add(routeParts);
                    }
                }
            }

            UpdateAprsRoutesComboBox();
        }

        /// <summary>
        /// Loads historical APRS packets into the chat control.
        /// </summary>
        private void LoadHistoricalAprsPackets(List<AprsPacket> historicalPackets)
        {
            if (historicalPackets == null) return;

            foreach (AprsPacket aprsPacket in historicalPackets)
            {
                if (aprsPacket?.Packet != null)
                {
                    AddAprsPacket(aprsPacket, !aprsPacket.Packet.incoming);
                }
            }

            if (aprsChatControl.Messages.Count > 0)
            {
                aprsChatControl.UpdateMessages(true);
            }
        }

        /// <summary>
        /// Shows the APRS details dialog for a message.
        /// </summary>
        private void ShowAprsDetails(ChatMessage message)
        {
            AprsDetailsForm form = new AprsDetailsForm();
            form.SetMessage(message);
            form.ShowDialog(this);
        }

        #endregion

        #region UI Event Handlers

        private void aprsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            aprsContextMenuStrip.Show(aprsMenuPictureBox, e.Location);
        }

        private void aprsSendButton_Click(object sender, EventArgs e)
        {
            string destination = aprsDestinationComboBox.Text.Trim().ToUpper();
            string message = aprsTextBox.Text;
            if (string.IsNullOrEmpty(destination) || string.IsNullOrEmpty(message)) return;

            int radioDeviceId = GetPreferredAprsRadioDeviceId();
            if (radioDeviceId == -1) return;

            string[] route = GetSelectedRoute();

            var messageData = new AprsSendMessageData
            {
                Destination = destination,
                Message = message,
                RadioDeviceId = radioDeviceId,
                Route = route
            };

            _broker.Dispatch(1, "SendAprsMessage", messageData, store: false);
            aprsTextBox.Text = "";
        }

        private void aprsTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                aprsSendButton_Click(this, null);
            }
        }

        private void aprsTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateSendButtonState();
        }

        private void aprsDestinationComboBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                aprsTextBox.Focus();
            }
            else if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != (char)Keys.Back)
            {
                e.Handled = true;
            }
        }

        private void aprsDestinationComboBox_TextChanged(object sender, EventArgs e)
        {
            int selectionStart = aprsDestinationComboBox.SelectionStart;
            aprsDestinationComboBox.Text = aprsDestinationComboBox.Text.ToUpper();
            aprsDestinationComboBox.SelectionStart = selectionStart;

            UpdateSendButtonState();

            if (!_initializing)
            {
                _broker.Dispatch(0, "AprsDestination", aprsDestinationComboBox.Text);
            }
        }

        private void aprsDestinationComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            string selectedCallsign = aprsDestinationComboBox.Text.Trim().ToUpper();
            if (!string.IsNullOrEmpty(selectedCallsign))
            {
                foreach (StationInfoClass station in _cachedStations)
                {
                    if (station.StationType == StationInfoClass.StationTypes.APRS &&
                        station.CallsignNoZero.Equals(selectedCallsign, StringComparison.OrdinalIgnoreCase))
                    {
                        if (!string.IsNullOrEmpty(station.APRSRoute))
                        {
                            for (int i = 0; i < aprsRoutes.Count; i++)
                            {
                                if (aprsRoutes[i][0].Equals(station.APRSRoute, StringComparison.OrdinalIgnoreCase))
                                {
                                    selectedAprsRoute = i;
                                    aprsRouteComboBox.SelectedIndex = i;
                                    _broker.Dispatch(0, "SelectedAprsRoute", selectedAprsRoute);
                                    break;
                                }
                            }
                        }
                        break;
                    }
                }
            }

            aprsTextBox.Focus();
        }

        private void aprsRouteComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            selectedAprsRoute = aprsRouteComboBox.SelectedIndex;
            _broker.Dispatch(0, "SelectedAprsRoute", selectedAprsRoute);
        }

        private void showAllMessagesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            if (_initializing) return;

            _broker.Dispatch(0, "AprsShowTelemetry", showAllMessagesToolStripMenuItem.Checked ? 1 : 0);

            foreach (ChatMessage n in aprsChatControl.Messages)
            {
                n.Visible = showAllMessagesToolStripMenuItem.Checked || (n.MessageType == PacketDataType.Message);
            }
            aprsChatControl.UpdateMessages(true);
        }

        private void beaconSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            using (EditBeaconSettingsForm beaconSettingsForm = new EditBeaconSettingsForm())
            {
                beaconSettingsForm.ShowDialog(this);
            }
        }

        private void aprsSmsButton_Click(object sender, EventArgs e)
        {
            using (AprsSmsForm aprsSmsForm = new AprsSmsForm())
            {
                if (aprsSmsForm.ShowDialog(this) == DialogResult.OK)
                {
                    int radioDeviceId = GetPreferredAprsRadioDeviceId();
                    if (radioDeviceId == -1) return;

                    string[] route = GetSelectedRoute();

                    var messageData = new AprsSendMessageData
                    {
                        Destination = "SMS",
                        Message = "@" + aprsSmsForm.PhoneNumber + " " + aprsSmsForm.Message,
                        RadioDeviceId = radioDeviceId,
                        Route = route
                    };

                    _broker.Dispatch(1, "SendAprsMessage", messageData, store: false);
                }
            }
        }

        private void weatherReportToolStripMenuItem_Click(object sender, EventArgs e)
        {
            using (AprsWeatherForm aprsWeatherForm = new AprsWeatherForm())
            {
                if (aprsWeatherForm.ShowDialog(this) == DialogResult.OK)
                {
                    int radioDeviceId = GetPreferredAprsRadioDeviceId();
                    if (radioDeviceId == -1) return;

                    string[] route = GetSelectedRoute();

                    var messageData = new AprsSendMessageData
                    {
                        Destination = "WXBOT",
                        Message = aprsWeatherForm.GetAprsMessage(),
                        RadioDeviceId = radioDeviceId,
                        Route = route
                    };

                    _broker.Dispatch(1, "SendAprsMessage", messageData, store: false);
                }
            }
        }

        private void aprsSetupButton_Click(object sender, EventArgs e)
        {
            // Find a connected radio with all channels loaded
            int radioDeviceId = -1;
            RadioChannelInfo[] channels = null;

            foreach (int deviceId in _subscribedRadioDeviceIds)
            {
                bool allChannelsLoaded = _broker.GetValue<bool>(deviceId, "AllChannelsLoaded", false);
                if (allChannelsLoaded)
                {
                    channels = _broker.GetValue<RadioChannelInfo[]>(deviceId, "Channels", null);
                    if (channels != null && channels.Length > 0)
                    {
                        radioDeviceId = deviceId;
                        break;
                    }
                }
            }

            if (radioDeviceId == -1 || channels == null)
            {
                MessageBox.Show("No radio with loaded channels is available.", "APRS Setup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Show the APRS configuration form
            using (AprsConfigurationForm form = new AprsConfigurationForm())
            {
                form.Channels = channels;
                if (form.ShowDialog(this) == DialogResult.OK)
                {
                    int selectedChannelId = form.SelectedChannelId;
                    float frequencyMhz = form.Frequency;

                    if (selectedChannelId >= 0 && selectedChannelId < channels.Length && channels[selectedChannelId] != null)
                    {
                        // Create a new channel based on the selected one with APRS settings
                        RadioChannelInfo aprsChannel = new RadioChannelInfo(channels[selectedChannelId]);
                        aprsChannel.name_str = "APRS";
                        aprsChannel.rx_freq = (int)(frequencyMhz * 1000000);
                        aprsChannel.tx_freq = (int)(frequencyMhz * 1000000);
                        aprsChannel.rx_mod = Radio.RadioModulationType.FM;
                        aprsChannel.tx_mod = Radio.RadioModulationType.FM;
                        aprsChannel.bandwidth = Radio.RadioBandwidthType.WIDE;
                        aprsChannel.mute = true;
                        aprsChannel.pre_de_emph_bypass = true;
                        aprsChannel.scan = false;
                        aprsChannel.talk_around = false;
                        aprsChannel.tx_at_max_power = true;
                        aprsChannel.tx_at_med_power = false;
                        aprsChannel.tx_sub_audio = 0;
                        aprsChannel.rx_sub_audio = 0;
                        aprsChannel.tx_disable = false;

                        // Dispatch the channel write event to the radio
                        _broker.Dispatch(radioDeviceId, "WriteChannel", aprsChannel, store: false);
                    }
                }
            }
        }

        private void requestPositionToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // TODO: Implement position request via DataBroker
        }

        private void aprsTitleLabel_DoubleClick(object sender, EventArgs e)
        {
            // Dispatch message to open Settings form at APRS tab (tab index 1)
            _broker.Dispatch(0, "ShowSettingsTab", 1, store: false);
        }

        private void aprsChatControl_MouseClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                rightClickedMessage = aprsChatControl.GetChatMessageAtXY(e.X, e.Y);
                if (rightClickedMessage != null)
                {
                    aprsMsgContextMenuStrip.Show(aprsChatControl, e.Location);
                }
            }
        }

        private void aprsChatControl_MouseDoubleClick(object sender, MouseEventArgs e)
        {
            selectedAprsMessage = aprsChatControl.GetChatMessageAtXY(e.X, e.Y);
            if (selectedAprsMessage != null)
            {
                if (aprsDetailsForm == null || aprsDetailsForm.IsDisposed)
                {
                    aprsDetailsForm = new AprsDetailsForm();
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

        private void aprsMsgContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (rightClickedMessage == null)
            {
                e.Cancel = true;
                return;
            }
            // Enable show location if the message has valid position data
            bool hasPosition = (rightClickedMessage.Latitude != 0 || rightClickedMessage.Longitude != 0);
            showLocationToolStripMenuItem.Enabled = hasPosition;
        }

        private void detailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedMessage != null)
            {
                ShowAprsDetails(rightClickedMessage);
            }
        }

        private void showLocationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedMessage == null) return;

            AX25Packet ax25Packet = rightClickedMessage.Tag as AX25Packet;
            if (ax25Packet == null) return;

            // Get callsign from the message
            string callsign = rightClickedMessage.SenderCallSign;
            if (string.IsNullOrEmpty(callsign)) return;

            // Get position from the ChatMessage (stored when packet was added)
            double latitude = rightClickedMessage.Latitude;
            double longitude = rightClickedMessage.Longitude;

            if (latitude == 0 && longitude == 0) return;

            // Show the map location form with the callsign and position
            MapLocationForm mapForm = new MapLocationForm(callsign, latitude, longitude);
            mapForm.Show();
        }

        private void copyMessageToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedMessage != null)
            {
                Clipboard.SetText(rightClickedMessage.Message);
            }
        }

        private void copyCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((rightClickedMessage != null) && (rightClickedMessage.SenderCallSign != null))
            {
                Clipboard.SetText(rightClickedMessage.SenderCallSign);
            }
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<AprsTabUserControl>("APRS");
            form.Show();
        }

        #endregion
    }
}
