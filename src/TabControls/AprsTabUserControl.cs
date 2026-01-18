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

        public AprsTabUserControl()
        {
            InitializeComponent();

            // Setup routes combobox
            UpdateAprsRoutesComboBox();

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
                // Get the stored packet list from the AprsStoreReady event
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

        /// <summary>
        /// Updates the visibility of transmit-related controls based on AllowTransmit setting.
        /// Controls are hidden when transmission is not allowed.
        /// </summary>
        private void UpdateBottomPanelVisibility(bool allowTransmit)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<bool>(UpdateBottomPanelVisibility), allowTransmit);
                return;
            }

            // Hide/show the bottom panel and route combo box
            aprsBottomPanel.Visible = allowTransmit;
            aprsRouteComboBox.Visible = allowTransmit && (aprsRoutes.Count > 1);

            // Hide/show menu items related to transmitting
            beaconSettingsToolStripMenuItem.Visible = allowTransmit;
            smSMessageToolStripMenuItem.Visible = allowTransmit;
            weatherReportToolStripMenuItem.Visible = allowTransmit;
            toolStripMenuItem7.Visible = allowTransmit;
        }

        /// <summary>
        /// Checks the initial connected radios state and subscribes to their channel events.
        /// </summary>
        private void CheckInitialConnectedRadios()
        {
            // Get the current list of connected radios from the broker
            var connectedRadios = _broker.GetValue<object>(1, "ConnectedRadios", null);
            if (connectedRadios != null)
            {
                OnConnectedRadiosChanged(1, "ConnectedRadios", connectedRadios);
            }
            else
            {
                // No radios connected - update the missing channel panel visibility
                UpdateMissingChannelPanelVisibility();
            }
        }

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

            // Extract device IDs from the connected radios list
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

            // Unsubscribe from radios that are no longer connected
            foreach (int oldDeviceId in _subscribedRadioDeviceIds.ToList())
            {
                if (!currentDeviceIds.Contains(oldDeviceId))
                {
                    _subscribedRadioDeviceIds.Remove(oldDeviceId);
                    // Note: DataBrokerClient doesn't have an Unsubscribe method, but the subscription
                    // will be cleaned up when the radio is removed from the DataBroker
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

            // Update the missing channel panel visibility
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

            // Update the missing channel panel visibility whenever channels change
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

            // Update the missing channel panel visibility whenever AllChannelsLoaded state changes
            UpdateMissingChannelPanelVisibility();
        }

        /// <summary>
        /// Updates the visibility of the aprsMissingChannelPanel based on connected radios and their channels.
        /// The panel is visible if: connected to one or more radios with all channels loaded AND none have a channel named "APRS".
        /// Only radios with AllChannelsLoaded = true are considered.
        /// </summary>
        private void UpdateMissingChannelPanelVisibility()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(UpdateMissingChannelPanelVisibility));
                return;
            }

            // If no radios are connected, hide the panel
            if (_subscribedRadioDeviceIds.Count == 0)
            {
                aprsMissingChannelPanel.Visible = false;
                return;
            }

            // Check if any connected radio (with all channels loaded) has a channel named "APRS"
            bool hasAprsChannel = false;
            bool hasRadioWithAllChannelsLoaded = false;

            foreach (int deviceId in _subscribedRadioDeviceIds)
            {
                // Only consider radios that have all channels loaded
                bool allChannelsLoaded = _broker.GetValue<bool>(deviceId, "AllChannelsLoaded", false);
                if (!allChannelsLoaded)
                {
                    continue; // Skip this radio - channels not fully loaded yet
                }

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

            // Show the missing channel panel only if:
            // - At least one radio has all channels loaded, AND
            // - No radio has an APRS channel
            // If no radios have all channels loaded yet, hide the panel (wait for channels to load)
            aprsMissingChannelPanel.Visible = hasRadioWithAllChannelsLoaded && !hasAprsChannel;

            // Cache the hasAprsChannel state for use in UpdateSendButtonState
            _hasAprsChannel = hasAprsChannel;

            // Enable/disable the bottom panel controls based on whether we have an APRS channel
            // Controls are enabled only when at least one radio has an APRS channel
            aprsTextBox.Enabled = hasAprsChannel;
            aprsDestinationComboBox.Enabled = hasAprsChannel;

            // Update send button state (depends on multiple conditions)
            UpdateSendButtonState();
        }

        /// <summary>
        /// Updates the enabled state of the send button based on multiple conditions:
        /// - hasAprsChannel is true
        /// - aprsDestinationComboBox contains a parsable callsign
        /// - aprsTextBox is not empty
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

        /// <summary>
        /// Gets the device ID of the preferred radio for APRS transmission.
        /// The radio must be connected and have a channel named "APRS".
        /// If multiple radios qualify, returns the one with the lowest device ID.
        /// </summary>
        /// <returns>The device ID of the preferred APRS radio, or -1 if none found.</returns>
        private int GetPreferredAprsRadioDeviceId()
        {
            int preferredDeviceId = -1;

            foreach (int deviceId in _subscribedRadioDeviceIds)
            {
                // Only consider radios that have all channels loaded
                bool allChannelsLoaded = _broker.GetValue<bool>(deviceId, "AllChannelsLoaded", false);
                if (!allChannelsLoaded)
                {
                    continue;
                }

                // Check if this radio has an APRS channel
                RadioChannelInfo[] channels = _broker.GetValue<RadioChannelInfo[]>(deviceId, "Channels", null);
                if (channels != null)
                {
                    foreach (RadioChannelInfo channel in channels)
                    {
                        if (channel != null &&
                            !string.IsNullOrEmpty(channel.name_str) &&
                            channel.name_str.Equals("APRS", StringComparison.OrdinalIgnoreCase))
                        {
                            // Found a radio with APRS channel - select lowest device ID
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

        /// <summary>
        /// Checks if the given string is a valid amateur radio callsign.
        /// A valid callsign has at least 3 characters and contains at least one letter and one digit.
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
        /// Updates the APRS destination combobox with APRS stations from the contact list.
        /// </summary>
        /// <param name="stations">The list of all stations.</param>
        private void UpdateAprsDestinationComboBox(List<StationInfoClass> stations)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<List<StationInfoClass>>(UpdateAprsDestinationComboBox), stations);
                return;
            }

            // Cache the stations list for later use (e.g., looking up preferred routes)
            _cachedStations = stations ?? new List<StationInfoClass>();

            // Remember the current text so we can restore it after updating
            string currentText = aprsDestinationComboBox.Text;

            // Clear and repopulate with APRS stations only
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

            // Restore the previous text (whether it was typed or selected)
            aprsDestinationComboBox.Text = currentText;
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
        /// Parses the APRS routes string from the DataBroker and updates the routes list.
        /// Format: "RouteName,Dest,Path1,Path2|RouteName2,Dest2,Path1,Path2"
        /// </summary>
        /// <param name="routesStr">The pipe-delimited routes string.</param>
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

        public int SelectedAprsRoute
        {
            get { return selectedAprsRoute; }
            set { selectedAprsRoute = value; }
        }

        public void SetMissingChannelVisible(bool visible)
        {
            aprsMissingChannelPanel.Visible = visible;
        }

        public void SetControlsEnabled(bool enabled)
        {
            aprsTextBox.Enabled = enabled;
            aprsSendButton.Enabled = enabled;
            aprsDestinationComboBox.Enabled = enabled;
        }

        public void AddDestinationCallsign(string callsign)
        {
            if (!aprsDestinationComboBox.Items.Contains(callsign))
            {
                aprsDestinationComboBox.Items.Add(callsign);
            }
        }

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

        public string[] GetSelectedRoute()
        {
            if (aprsRoutes.Count == 0) return null;
            if (selectedAprsRoute >= aprsRoutes.Count) selectedAprsRoute = 0;
            return aprsRoutes[selectedAprsRoute];
        }

        private void aprsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            aprsContextMenuStrip.Show(aprsMenuPictureBox, e.Location);
        }

        private void aprsSendButton_Click(object sender, EventArgs e)
        {
            string destination = aprsDestinationComboBox.Text.Trim().ToUpper();
            string message = aprsTextBox.Text;
            if (string.IsNullOrEmpty(destination) || string.IsNullOrEmpty(message)) return;

            // Get the preferred radio device ID for APRS transmission
            int radioDeviceId = GetPreferredAprsRadioDeviceId();
            if (radioDeviceId == -1) return; // No suitable radio found

            // Get the selected route (if any)
            string[] route = GetSelectedRoute();

            // Create the message data to send to AprsHandler
            var messageData = new AprsSendMessageData
            {
                Destination = destination,
                Message = message,
                RadioDeviceId = radioDeviceId,
                Route = route
            };

            // Dispatch the message to AprsHandler via DataBroker
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

            // Update send button state when destination changes
            UpdateSendButtonState();

            // Save destination to DataBroker (skip during initialization)
            if (!_initializing)
            {
                _broker.Dispatch(0, "AprsDestination", aprsDestinationComboBox.Text);
            }
        }

        private void aprsTextBox_TextChanged(object sender, EventArgs e)
        {
            // Update send button state when message text changes
            UpdateSendButtonState();
        }

        private void aprsDestinationComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            // Check if the selected station has a preferred APRS route
            string selectedCallsign = aprsDestinationComboBox.Text.Trim().ToUpper();
            if (!string.IsNullOrEmpty(selectedCallsign))
            {
                // Find the station in the cached list
                foreach (StationInfoClass station in _cachedStations)
                {
                    if (station.StationType == StationInfoClass.StationTypes.APRS &&
                        station.CallsignNoZero.Equals(selectedCallsign, StringComparison.OrdinalIgnoreCase))
                    {
                        // Check if the station has a preferred APRS route
                        if (!string.IsNullOrEmpty(station.APRSRoute))
                        {
                            // Find the route index by name
                            for (int i = 0; i < aprsRoutes.Count; i++)
                            {
                                if (aprsRoutes[i][0].Equals(station.APRSRoute, StringComparison.OrdinalIgnoreCase))
                                {
                                    // Select the preferred route
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

        private void showAllMessagesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            // Skip saving during initialization to prevent overwriting stored value
            if (_initializing) return;

            // Save setting to DataBroker
            _broker.Dispatch(0, "AprsShowTelemetry", showAllMessagesToolStripMenuItem.Checked ? 1 : 0);

            // Update visibility of all messages
            foreach (ChatMessage n in aprsChatControl.Messages)
            {
                n.Visible = showAllMessagesToolStripMenuItem.Checked || (n.MessageType == PacketDataType.Message);
            }
            aprsChatControl.UpdateMessages(true);
        }

        private void beaconSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //if (mainForm == null) return;
            //mainForm.ShowBeaconSettingsForm();
        }

        private void aprsSmsButton_Click(object sender, EventArgs e)
        {
            //if (mainForm == null) return;
            //mainForm.ShowAprsSmsForm();
        }

        private void weatherReportToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //if (mainForm == null) return;
            //mainForm.ShowAprsWeatherForm();
        }

        private void aprsSetupButton_Click(object sender, EventArgs e)
        {
            //if (mainForm == null) return;
            //mainForm.ShowAprsConfigurationForm();
        }

        private void requestPositionToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //if (mainForm == null) return;
            //string destination = aprsDestinationComboBox.Text.Trim().ToUpper();
            //if (string.IsNullOrEmpty(destination)) return;
            //mainForm.SendAprsPositionRequest(destination);
        }

        private void aprsRouteComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            selectedAprsRoute = aprsRouteComboBox.SelectedIndex;

            // Save selected route to DataBroker
            _broker.Dispatch(0, "SelectedAprsRoute", selectedAprsRoute);
        }

        private void aprsTitleLabel_DoubleClick(object sender, EventArgs e)
        {
            //if (mainForm == null) return;
            //mainForm.ShowAprsConfigurationForm();
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
            AprsPacket packet = rightClickedMessage.Tag as AprsPacket;
            showLocationToolStripMenuItem.Enabled = (packet != null && packet.Position != null);
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
            if (rightClickedMessage != null && rightClickedMessage.Tag is AprsPacket)
            {
                AprsPacket packet = (AprsPacket)rightClickedMessage.Tag;
                if (packet.Position != null)
                {
                    //mainForm.ShowLocationOnMap(packet.Position.Latitude, packet.Position.Longitude, packet.SourceCallsign);
                }
            }
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

        private void ShowAprsDetails(ChatMessage message)
        {
            AprsDetailsForm form = new AprsDetailsForm();
            form.SetMessage(message);
            form.ShowDialog(this);
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<AprsTabUserControl>("APRS");
            form.Show();
        }

        /// <summary>
        /// Handles the AprsStoreReady event - loads historical APRS packets from the event data.
        /// </summary>
        private void OnAprsStoreReady(int deviceId, string name, object data)
        {
            // The AprsStoreReady event includes the list of historical packets directly
            if (!(data is List<AprsPacket> historicalPackets)) return;

            LoadHistoricalAprsPackets(historicalPackets);
        }

        /// <summary>
        /// Loads historical APRS packets into the chat control.
        /// </summary>
        /// <param name="historicalPackets">The list of historical APRS packets.</param>
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

            // Update the display
            if (aprsChatControl.Messages.Count > 0)
            {
                aprsChatControl.UpdateMessages(true);
            }
        }

        /// <summary>
        /// Handles incoming AprsFrame events from the Data Broker.
        /// </summary>
        private void OnAprsFrame(int deviceId, string name, object data)
        {
            if (!(data is AprsFrameEventArgs args)) return;
            if (args.AX25Packet == null) return;

            // Determine if we are the sender
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

        /// <summary>
        /// Adds an APRS packet to the chat control.
        /// </summary>
        /// <param name="packet">The AX.25 packet containing APRS data.</param>
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

            //if (sender == false)
            {
                SenderAddr = packet.addresses[1];
                RoutingString = SenderAddr.ToString();
                SenderCallsign = SenderAddr.CallSignWithId;
                if ((aprsPacket.Position != null) && (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) && (aprsPacket.Position.CoordinateSet.Longitude.Value != 0)) { ImageIndex = 3; }
            }

            MessageType = aprsPacket.DataType;
            if (aprsPacket.DataType == PacketDataType.Message)
            {
                string localCallsignWithId = string.IsNullOrEmpty(_stationId) ? _callsign : _callsign + "-" + _stationId;
                bool forSelf = ((aprsPacket.MessageData.Addressee == _callsign) || (aprsPacket.MessageData.Addressee == localCallsignWithId));

                if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtAck)
                {
                    if (forSelf)
                    {
                        // Look at a message to ack
                        foreach (ChatMessage n in aprsChatControl.Messages)
                        {
                            if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId))
                            {
                                if ((n.AuthState == AX25Packet.AuthState.Unknown) || ((n.AuthState == AX25Packet.AuthState.Success) && (aprsPacket.Packet.authState == AX25Packet.AuthState.Success)) || ((n.AuthState == AX25Packet.AuthState.None) && (aprsPacket.Packet.authState == AX25Packet.AuthState.None))) { n.ImageIndex = 0; }
                            }
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
                            if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId))
                            {
                                if ((n.AuthState == AX25Packet.AuthState.Unknown) || ((n.AuthState == AX25Packet.AuthState.Success) && (aprsPacket.Packet.authState == AX25Packet.AuthState.Success)) || ((n.AuthState == AX25Packet.AuthState.None) && (aprsPacket.Packet.authState == AX25Packet.AuthState.None))) { n.ImageIndex = 1; }
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
                        // The sender and destination are the same, no need to show details.
                        RoutingString = aprsPacket.MessageData.Addressee;
                    }
                    else
                    {
                        // Show both sender and destination
                        RoutingString = SenderCallsign + " → " + aprsPacket.MessageData.Addressee;
                    }
                    if (packet.authState == AX25Packet.AuthState.Success) { RoutingString += " ✓"; }
                    if (packet.authState == AX25Packet.AuthState.Failed) { RoutingString += " ❌"; }
                }
                MessageId = aprsPacket.MessageData.SeqId;
                MessageText = aprsPacket.MessageData.MsgText;

                // If this is a SMS message, do more processing to make it look good
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

                // Check if we already got this exact message before
                if (MessageId != null)
                {
                    foreach (ChatMessage n in aprsChatControl.Messages)
                    {
                        // If this is a duplicate, don't display it.
                        if ((n.MessageId == MessageId) && (n.Route == RoutingString) && (n.Message == MessageText)) return;
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

            if ((packet.addresses != null) && (packet.addresses.Count == 1))
            {
                AX25Address addr = packet.addresses[0];
                SenderCallsign = RoutingString = addr.ToString();
                MessageText = packet.dataStr;
            }

            if ((MessageText != null) && (MessageText.Trim().Length > 0))
            {
                ChatMessage c = new ChatMessage(RoutingString, SenderCallsign, MessageText.Trim(), packet.time, sender, -1);
                c.Tag = packet;
                c.MessageId = MessageId;
                c.MessageType = MessageType;
                c.Visible = showAllMessagesToolStripMenuItem.Checked || (c.MessageType == PacketDataType.Message);
                c.ImageIndex = ImageIndex;
                c.AuthState = packet.authState;

                // Check if we already got this message in the last 5 minutes
                // When starting up HTCommander, this packet may already be loaded, so we still process if the packet is the same content and the same time.
                foreach (ChatMessage chatMessage2 in aprsChatControl.Messages)
                {
                    AX25Packet packet2 = (AX25Packet)chatMessage2.Tag;
                    if ((c.Message == chatMessage2.Message) && (packet2.time.AddMinutes(5).CompareTo(packet.time) > 0) && (c.Time != packet2.time)) { return; }
                }

                // Add the message
                aprsChatControl.Messages.Add(c);
                if (c.Visible) { aprsChatControl.UpdateMessages(true); }

                // Add or move the map marker
                if ((c.ImageIndex == 3) && (aprsPacket != null))
                {
                    c.Latitude = aprsPacket.Position.CoordinateSet.Latitude.Value;
                    c.Longitude = aprsPacket.Position.CoordinateSet.Longitude.Value;
                    // TODO: Add map marker support via Data Broker
                    // AddMapMarker(packet.addresses[1].CallSignWithId, aprsPacket.Position.CoordinateSet.Latitude.Value, aprsPacket.Position.CoordinateSet.Longitude.Value, packet.time);
                }
            }
        }

    }
}
