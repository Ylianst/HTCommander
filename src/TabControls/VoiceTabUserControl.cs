/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using HTCommander.Dialogs;

// DecodedTextEntry is defined in the HTCommander namespace (VoiceHandler.cs)

namespace HTCommander.Controls
{
    /// <summary>
    /// Enum representing the available voice transmission modes.
    /// </summary>
    public enum VoiceTransmitMode
    {
        Chat,
        Speak,
        Morse
    }

    public partial class VoiceTabUserControl : UserControl, IRadioDeviceSelector
    {
        private int _preferredRadioDeviceId = -1;
        private DataBrokerClient broker;

        /// <summary>
        /// Gets or sets the preferred radio device ID for this control.
        /// </summary>
        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public int PreferredRadioDeviceId
        {
            get { return _preferredRadioDeviceId; }
            set { _preferredRadioDeviceId = value; }
        }
        private bool _showDetach = false;
        private bool _isListening = false;
        private bool _isProcessing = false;
        private bool _isTransmitting = false;

        // Current voice transmit mode
        private VoiceTransmitMode _currentMode = VoiceTransmitMode.Chat;

        // Voice handler state tracking
        private List<ConnectedRadioInfo> _connectedRadios = new List<ConnectedRadioInfo>();
        private bool _voiceHandlerEnabled = false;
        private int _voiceHandlerTargetDeviceId = -1;

        // Context menu for radio selection when multiple radios are connected
        private ContextMenuStrip _radioSelectContextMenuStrip;

        // Track right-clicked voice message for context menu
        private VoiceMessage rightClickedVoiceMessage = null;

        // Track the AllowTransmit setting
        private bool _allowTransmit = false;

        /// <summary>
        /// Simple class to hold connected radio information.
        /// </summary>
        private class ConnectedRadioInfo
        {
            public int DeviceId { get; set; }
            public string FriendlyName { get; set; }
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

        public VoiceTabUserControl()
        {
            InitializeComponent();

            // Create the DataBrokerClient and subscribe to radio events from all radios
            broker = new DataBrokerClient();

            // Subscribe to ProcessingVoice, TextReady, and VoiceTransmitStateChanged from all radios
            broker.Subscribe(DataBroker.AllDevices, new string[] { "ProcessingVoice", "TextReady", "VoiceTransmitStateChanged" }, OnBrokerEvent);

            // Subscribe to ConnectedRadios changes to track radio connections
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Subscribe to VoiceHandlerState changes to track voice handler state
            broker.Subscribe(1, "VoiceHandlerState", OnVoiceHandlerStateChanged);

            // Subscribe to VoiceTextCleared to clear the voice control
            broker.Subscribe(1, "VoiceTextCleared", OnVoiceTextCleared);

            // Subscribe to VoiceTextHistoryLoaded to load history when VoiceHandler finishes loading
            broker.Subscribe(1, "VoiceTextHistoryLoaded", OnVoiceTextHistoryLoaded);

            // Subscribe to AllowTransmit changes to show/hide the bottom panel
            broker.Subscribe(0, "AllowTransmit", OnAllowTransmitChanged);

            // Create context menu for radio selection
            _radioSelectContextMenuStrip = new ContextMenuStrip();

            // Load initial state
            LoadConnectedRadios();
            LoadVoiceHandlerState();
            LoadAllowTransmitState();
            UpdateEnableButtonState();
            UpdateSpeakButtonState();

            // Load existing decoded text history from the Data Broker
            LoadDecodedTextHistory();
        }

        /// <summary>
        /// Handles events from the DataBroker
        /// </summary>
        private void OnBrokerEvent(int deviceId, string name, object data)
        {
            // Marshal to UI thread if needed
            if (this.InvokeRequired)
            {
                try
                {
                    this.BeginInvoke(new Action(() => OnBrokerEvent(deviceId, name, data)));
                }
                catch (Exception) { }
                return;
            }

            switch (name)
            {
                case "ProcessingVoice":
                    HandleProcessingVoice(deviceId, data);
                    break;
                case "TextReady":
                    HandleTextReady(deviceId, data);
                    break;
                case "VoiceTransmitStateChanged":
                    HandleVoiceTransmitStateChanged(deviceId, data);
                    break;
            }
        }

        /// <summary>
        /// Handles the ProcessingVoice event - updates the processing indicator
        /// </summary>
        private void HandleProcessingVoice(int deviceId, object data)
        {
            if (data == null) return;

            try
            {
                // Extract Listening and Processing from the anonymous type
                var type = data.GetType();
                var listeningProp = type.GetProperty("Listening");
                var processingProp = type.GetProperty("Processing");

                if (listeningProp != null && processingProp != null)
                {
                    _isListening = (bool)listeningProp.GetValue(data);
                    _isProcessing = (bool)processingProp.GetValue(data);
                    UpdateProcessingIndicator();
                }
            }
            catch (Exception)
            {
                // Ignore errors parsing the event data
            }
        }

        /// <summary>
        /// Handles the TextReady event - adds transcribed text to the history
        /// </summary>
        private void HandleTextReady(int deviceId, object data)
        {
            if (data == null) return;

            try
            {
                // Extract Text, Channel, Time, Completed, IsReceived, Encoding, Latitude, and Longitude from the anonymous type
                var type = data.GetType();
                var textProp = type.GetProperty("Text");
                var channelProp = type.GetProperty("Channel");
                var timeProp = type.GetProperty("Time");
                var completedProp = type.GetProperty("Completed");
                var isReceivedProp = type.GetProperty("IsReceived");
                var encodingProp = type.GetProperty("Encoding");
                var latitudeProp = type.GetProperty("Latitude");
                var longitudeProp = type.GetProperty("Longitude");

                if (textProp != null)
                {
                    string text = textProp.GetValue(data) as string;
                    string channel = channelProp?.GetValue(data) as string ?? "";
                    DateTime time = timeProp != null ? (DateTime)timeProp.GetValue(data) : DateTime.Now;
                    bool completed = completedProp != null && (bool)completedProp.GetValue(data);
                    bool isReceived = isReceivedProp != null ? (bool)isReceivedProp.GetValue(data) : true;
                    VoiceTextEncodingType encoding = VoiceTextEncodingType.Voice;
                    if (encodingProp != null)
                    {
                        object encodingValue = encodingProp.GetValue(data);
                        if (encodingValue is VoiceTextEncodingType e)
                        {
                            encoding = e;
                        }
                        else if (encodingValue is int ei)
                        {
                            encoding = (VoiceTextEncodingType)ei;
                        }
                    }
                    double latitude = 0;
                    double longitude = 0;
                    if (latitudeProp != null)
                    {
                        object latValue = latitudeProp.GetValue(data);
                        if (latValue is double d) latitude = d;
                    }
                    if (longitudeProp != null)
                    {
                        object lonValue = longitudeProp.GetValue(data);
                        if (lonValue is double d) longitude = d;
                    }

                    if (!string.IsNullOrEmpty(text))
                    {
                        AppendVoiceHistory(text, channel, time, completed, isReceived, encoding, latitude, longitude);
                    }
                }
            }
            catch (Exception)
            {
                // Ignore errors parsing the event data
            }
        }

        /// <summary>
        /// Handles the VoiceTransmitStateChanged event - updates UI for transmit state
        /// </summary>
        private void HandleVoiceTransmitStateChanged(int deviceId, object data)
        {
            if (data == null) return;

            try
            {
                _isTransmitting = (bool)data;
                UpdateTransmitState();
            }
            catch (Exception)
            {
                // Ignore errors parsing the event data
            }
        }

        /// <summary>
        /// Updates the processing indicator (● label) based on listening/processing state
        /// </summary>
        private void UpdateProcessingIndicator()
        {
            if (_isProcessing)
            {
                // Processing - show yellow/orange indicator
                voiceProcessingLabel.ForeColor = Color.Red;
                voiceProcessingLabel.Visible = true;
            }
            else if (_isListening)
            {
                // Listening - show green indicator
                voiceProcessingLabel.ForeColor = Color.DarkGreen;
                voiceProcessingLabel.Visible = true;
            }
            else
            {
                // Not active - hide indicator
                voiceProcessingLabel.Visible = false;
            }
        }

        /// <summary>
        /// Updates the UI based on voice transmit state
        /// </summary>
        private void UpdateTransmitState()
        {
            cancelVoiceButton.Visible = _isTransmitting;
            speakButton.Enabled = !_isTransmitting && speakTextBox.Enabled;
        }

        /// <summary>
        /// Appends transcribed text to the voice history using the VoiceControl.
        /// </summary>
        private void AppendVoiceHistory(string text, string channel, DateTime time, bool completed, bool isReceived = true, VoiceTextEncodingType encoding = VoiceTextEncodingType.Voice, double latitude = 0, double longitude = 0)
        {
            voiceControl.UpdatePartialMessage(text, channel, time, completed, isReceived, encoding, latitude, longitude);
        }

        // Properties to access internal controls
        public VoiceControl VoiceHistoryControl => voiceControl;
        public TextBox SpeakTextBox => speakTextBox;
        public Button SpeakButton => speakButton;
        public Button VoiceEnableButton => voiceEnableButton;
        public Button CancelVoiceButton => cancelVoiceButton;
        public Label VoiceProcessingLabel => voiceProcessingLabel;
        public Panel VoiceBottomPanel => voiceBottomPanel;

        /// <summary>
        /// Gets the current voice transmit mode.
        /// </summary>
        public VoiceTransmitMode CurrentMode => _currentMode;

        /// <summary>
        /// Sets the current voice transmit mode and updates UI accordingly.
        /// </summary>
        public void SetMode(VoiceTransmitMode mode)
        {
            _currentMode = mode;

            // Update menu item checked states
            chatToolStripMenuItem.Checked = (mode == VoiceTransmitMode.Chat);
            speakToolStripMenuItem.Checked = (mode == VoiceTransmitMode.Speak);
            morseToolStripMenuItem.Checked = (mode == VoiceTransmitMode.Morse);

            // Update button text to reflect current mode
            speakButton.Text = "&" + mode.ToString();
        }

        private void voiceEnableButton_Click(object sender, EventArgs e)
        {
            if (_voiceHandlerEnabled)
            {
                // Voice handler is active - disable it
                DisableVoiceHandler();
            }
            else if (_connectedRadios.Count == 1)
            {
                // Only one radio connected - enable for that radio directly
                EnableVoiceHandler(_connectedRadios[0].DeviceId);
            }
            else if (_connectedRadios.Count > 1)
            {
                // Multiple radios connected - check if PreferredRadioDeviceId is set (>= 100) and connected
                if (_preferredRadioDeviceId >= 100 && _connectedRadios.Any(r => r.DeviceId == _preferredRadioDeviceId))
                {
                    // Use the preferred radio directly
                    EnableVoiceHandler(_preferredRadioDeviceId);
                }
                else
                {
                    // Show dropdown menu to select
                    PopulateRadioSelectMenu();
                    _radioSelectContextMenuStrip.Show(voiceEnableButton, new Point(0, voiceEnableButton.Height));
                }
            }
            // If no radios connected, button should be disabled so this case shouldn't happen
        }

        private void speakButton_Click(object sender, EventArgs e)
        {
            // Send request based on current mode
            if (string.IsNullOrWhiteSpace(speakTextBox.Text)) return;
            if (!_voiceHandlerEnabled) return; // Voice must be enabled (button should already be disabled)

            string text = speakTextBox.Text.Trim();

            switch (_currentMode)
            {
                case VoiceTransmitMode.Chat:
                    // Chat mode - dispatch Chat command to device 1
                    broker?.Dispatch(1, "Chat", text, store: false);
                    break;

                case VoiceTransmitMode.Speak:
                    // Speak mode - dispatch Speak command to device 1 (VoiceHandler routes to voice-enabled radio)
                    broker?.Dispatch(1, "Speak", text, store: false);
                    break;

                case VoiceTransmitMode.Morse:
                    // Morse mode - dispatch Morse command to device 1 (uses voice-enabled radio)
                    broker?.Dispatch(1, "Morse", text, store: false);
                    break;
            }

            speakTextBox.Clear();
        }

        private void speakTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateSpeakButtonState();
        }

        /// <summary>
        /// Updates the speak button enabled state based on text box content, voice enabled state, and transmit state.
        /// </summary>
        private void UpdateSpeakButtonState()
        {
            bool hasText = !string.IsNullOrWhiteSpace(speakTextBox.Text);
            speakButton.Enabled = hasText && _voiceHandlerEnabled && !_isTransmitting;
        }

        private void speakTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                speakButton_Click(sender, e);
            }
        }

        private void chatToolStripMenuItem_Click(object sender, EventArgs e)
        {
            SetMode(VoiceTransmitMode.Chat);
        }

        private void speakToolStripMenuItem_Click(object sender, EventArgs e)
        {
            SetMode(VoiceTransmitMode.Speak);
        }

        private void morseToolStripMenuItem_Click(object sender, EventArgs e)
        {
            SetMode(VoiceTransmitMode.Morse);
        }

        private void cancelVoiceButton_Click(object sender, EventArgs e)
        {
            // Cancel voice transmission - dispatch to the target device
            int targetDeviceId = -1;
            if (_voiceHandlerTargetDeviceId > 0)
            {
                targetDeviceId = _voiceHandlerTargetDeviceId;
            }
            else if (_connectedRadios.Count > 0)
            {
                targetDeviceId = _connectedRadios[0].DeviceId;
            }

            if (targetDeviceId > 0)
            {
                broker?.Dispatch(targetDeviceId, "CancelVoiceTransmit", null, store: false);
            }
        }

        private void clearHistoryToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Ask for confirmation before clearing
            DialogResult result = MessageBox.Show(
                "Are you sure you want to clear the voice history?",
                "Clear History",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);

            if (result != DialogResult.Yes) return;

            // Clear the voice control
            voiceControl.Clear();

            // Also clear the history in the VoiceHandler via Data Broker
            broker?.Dispatch(1, "ClearVoiceText", null, store: false);
        }

        /// <summary>
        /// Loads the existing decoded text history from the Data Broker.
        /// </summary>
        private void LoadDecodedTextHistory()
        {
            var history = broker.GetValue<List<HTCommander.DecodedTextEntry>>(1, "DecodedTextHistory", null);

            // Populate the voice control with existing entries
            if (history != null && history.Count > 0)
            {
                foreach (var entry in history)
                {
                    // Skip entries with null or empty text after trimming
                    string trimmedText = entry.Text?.Trim();
                    if (string.IsNullOrEmpty(trimmedText)) continue;

                    // Determine if message has a valid location (set ImageIndex = 3 for location icon)
                    bool hasLocation = (entry.Latitude != 0 || entry.Longitude != 0);
                    int imageIndex = hasLocation ? 3 : -1;

                    var message = new VoiceMessage(
                        FormatRoute(entry.Channel, entry.Encoding),
                        null,
                        trimmedText,
                        entry.Time,
                        !entry.IsReceived,
                        imageIndex,
                        entry.Encoding
                    );
                    message.IsCompleted = true;
                    message.Latitude = entry.Latitude;
                    message.Longitude = entry.Longitude;
                    voiceControl.Messages.Add(message);
                }
            }

            // Also load any current (in-progress) entry
            var currentEntry = broker.GetValue<HTCommander.DecodedTextEntry>(1, "CurrentDecodedTextEntry", null);
            if (currentEntry != null)
            {
                // Skip entries with null or empty text after trimming
                string trimmedText = currentEntry.Text?.Trim();
                if (!string.IsNullOrEmpty(trimmedText))
                {
                    // Determine if message has a valid location (set ImageIndex = 3 for location icon)
                    bool hasLocation = (currentEntry.Latitude != 0 || currentEntry.Longitude != 0);
                    int imageIndex = hasLocation ? 3 : -1;

                    var message = new VoiceMessage(
                        FormatRoute(currentEntry.Channel, currentEntry.Encoding),
                        null,
                        trimmedText,
                        currentEntry.Time,
                        !currentEntry.IsReceived,
                        imageIndex,
                        currentEntry.Encoding
                    );
                    message.IsCompleted = false;
                    message.Latitude = currentEntry.Latitude;
                    message.Longitude = currentEntry.Longitude;
                    voiceControl.Messages.Add(message);
                }
            }

            // Update and scroll to bottom
            voiceControl.UpdateMessages(true);
        }

        /// <summary>
        /// Formats the route string to include encoding type.
        /// </summary>
        private string FormatRoute(string channel, VoiceTextEncodingType encoding)
        {
            string encodingStr = GetEncodingTypeName(encoding);
            if (string.IsNullOrEmpty(channel))
            {
                return encodingStr;
            }
            return $"[{channel}] {encodingStr}";
        }

        /// <summary>
        /// Gets the display name for a VoiceTextEncodingType.
        /// </summary>
        private string GetEncodingTypeName(VoiceTextEncodingType encoding)
        {
            switch (encoding)
            {
                case VoiceTextEncodingType.Voice: return "Voice";
                case VoiceTextEncodingType.Morse: return "Morse";
                case VoiceTextEncodingType.VoiceClip: return "Clip";
                case VoiceTextEncodingType.AX25: return "AX.25";
                case VoiceTextEncodingType.BSS: return "Chat";
                default: return encoding.ToString();
            }
        }

        private void voiceMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            voiceTabContextMenuStrip.Show(voiceMenuPictureBox, e.Location);
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<VoiceTabUserControl>("Communication");
            form.Show();
        }

        #region Voice Handler State Management

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

            LoadConnectedRadios();
            UpdateEnableButtonState();
        }

        /// <summary>
        /// Handles VoiceHandlerState changes from the DataBroker.
        /// </summary>
        private void OnVoiceHandlerStateChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                try
                {
                    this.BeginInvoke(new Action(() =>
                    {
                        ProcessVoiceHandlerState(data);
                        UpdateEnableButtonState();
                    }));
                }
                catch (Exception) { }
                return;
            }

            ProcessVoiceHandlerState(data);
            UpdateEnableButtonState();
        }

        /// <summary>
        /// Handles VoiceTextCleared event from the DataBroker - clears the voice control.
        /// </summary>
        private void OnVoiceTextCleared(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnVoiceTextCleared), deviceId, name, data);
                return;
            }

            // Clear the voice control
            voiceControl.Clear();
        }

        /// <summary>
        /// Handles VoiceTextHistoryLoaded event from the DataBroker - loads history when VoiceHandler finishes loading.
        /// This handles the race condition where VoiceHandler may load history after this control is initialized.
        /// </summary>
        private void OnVoiceTextHistoryLoaded(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnVoiceTextHistoryLoaded), deviceId, name, data);
                return;
            }

            // Only load if we don't already have content (avoid duplicates)
            if (voiceControl.Messages.Count == 0)
            {
                LoadDecodedTextHistory();
            }
        }

        /// <summary>
        /// Loads the list of connected radios from the DataBroker.
        /// </summary>
        private void LoadConnectedRadios()
        {
            _connectedRadios.Clear();

            var connectedRadios = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (connectedRadios == null) return;

            if (connectedRadios is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var itemType = item.GetType();
                    int? radioDeviceId = (int?)itemType.GetProperty("DeviceId")?.GetValue(item);
                    string friendlyName = (string)itemType.GetProperty("FriendlyName")?.GetValue(item);

                    if (radioDeviceId.HasValue)
                    {
                        var radioInfo = new ConnectedRadioInfo
                        {
                            DeviceId = radioDeviceId.Value,
                            FriendlyName = friendlyName ?? $"Radio {radioDeviceId.Value}"
                        };
                        _connectedRadios.Add(radioInfo);
                    }
                }
            }
        }

        /// <summary>
        /// Loads the current VoiceHandlerState from the DataBroker.
        /// </summary>
        private void LoadVoiceHandlerState()
        {
            var state = broker.GetValue<object>(1, "VoiceHandlerState", null);
            ProcessVoiceHandlerState(state);
        }

        /// <summary>
        /// Processes the VoiceHandlerState data object.
        /// </summary>
        private void ProcessVoiceHandlerState(object data)
        {
            bool enabled = false;
            int targetDeviceId = -1;

            if (data != null)
            {
                try
                {
                    var type = data.GetType();
                    var enabledProp = type.GetProperty("Enabled");
                    var targetDeviceIdProp = type.GetProperty("TargetDeviceId");

                    if (enabledProp != null)
                    {
                        object enabledValue = enabledProp.GetValue(data);
                        if (enabledValue is bool b)
                        {
                            enabled = b;
                        }
                    }

                    if (targetDeviceIdProp != null)
                    {
                        object targetValue = targetDeviceIdProp.GetValue(data);
                        if (targetValue is int i)
                        {
                            targetDeviceId = i;
                        }
                    }
                }
                catch (Exception)
                {
                    // Ignore parsing errors
                }
            }

            _voiceHandlerEnabled = enabled;
            _voiceHandlerTargetDeviceId = targetDeviceId;

            // Enable/disable speakTextBox and speakButton based on voice enabled state
            speakTextBox.Enabled = _voiceHandlerEnabled;
            UpdateSpeakButtonState();
        }

        /// <summary>
        /// Updates the Enable button state based on connected radios and voice handler state.
        /// </summary>
        private void UpdateEnableButtonState()
        {
            if (_voiceHandlerEnabled)
            {
                // Voice handler is active - show "Disable" button
                voiceEnableButton.Text = "&Disable";
                voiceEnableButton.Enabled = true;
            }
            else if (_connectedRadios.Count == 0)
            {
                // No radios connected - show "Enable" but disabled
                voiceEnableButton.Text = "&Enable";
                voiceEnableButton.Enabled = false;
            }
            else
            {
                // Radios connected, voice handler not active - show "Enable" and enabled
                voiceEnableButton.Text = "&Enable";
                voiceEnableButton.Enabled = true;
            }
        }

        /// <summary>
        /// Enables the voice handler for the specified radio device.
        /// </summary>
        private void EnableVoiceHandler(int deviceId)
        {
            // Get voice settings from DataBroker
            string language = broker.GetValue<string>(0, "VoiceLanguage", "en");
            string model = broker.GetValue<string>(0, "VoiceModel", "");

            // Dispatch VoiceHandlerEnable command
            broker.Dispatch(1, "VoiceHandlerEnable", new
            {
                DeviceId = deviceId,
                Language = language,
                Model = model
            }, store: false);
        }

        /// <summary>
        /// Disables the voice handler.
        /// </summary>
        private void DisableVoiceHandler()
        {
            broker.Dispatch(1, "VoiceHandlerDisable", null, store: false);
        }

        /// <summary>
        /// Populates the radio selection context menu with connected radios.
        /// </summary>
        private void PopulateRadioSelectMenu()
        {
            _radioSelectContextMenuStrip.Items.Clear();

            foreach (var radio in _connectedRadios)
            {
                var menuItem = new ToolStripMenuItem(radio.FriendlyName)
                {
                    Tag = radio.DeviceId
                };
                menuItem.Click += RadioSelectMenuItem_Click;
                _radioSelectContextMenuStrip.Items.Add(menuItem);
            }
        }

        /// <summary>
        /// Handles click on a radio selection menu item.
        /// </summary>
        private void RadioSelectMenuItem_Click(object sender, EventArgs e)
        {
            if (sender is ToolStripMenuItem menuItem && menuItem.Tag is int deviceId)
            {
                EnableVoiceHandler(deviceId);
            }
        }

        #endregion

        #region Voice Message Context Menu Handlers

        private void voiceMsgContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            // Determine which message was right-clicked using cursor position
            System.Drawing.Point pt = voiceControl.PointToClient(Cursor.Position);
            rightClickedVoiceMessage = voiceControl.GetVoiceMessageAtXY(pt.X, pt.Y);

            if (rightClickedVoiceMessage == null)
            {
                e.Cancel = true;
                return;
            }

            // Enable show location if the message has valid position data
            bool hasPosition = (rightClickedVoiceMessage.Latitude != 0 || rightClickedVoiceMessage.Longitude != 0);
            showLocationToolStripMenuItem.Enabled = hasPosition;

            // Enable copy callsign only if callsign is available
            copyCallsignToolStripMenuItem.Enabled = !string.IsNullOrEmpty(rightClickedVoiceMessage.SenderCallSign);
        }

        private void voiceDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedVoiceMessage == null) return;

            VoiceDetailsForm form = new VoiceDetailsForm();
            form.SetMessage(rightClickedVoiceMessage);
            form.ShowDialog(this);
        }

        private void voiceShowLocationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedVoiceMessage == null) return;

            double latitude = rightClickedVoiceMessage.Latitude;
            double longitude = rightClickedVoiceMessage.Longitude;
            if (latitude == 0 && longitude == 0) return;

            // Use the route or callsign as the label
            string label = rightClickedVoiceMessage.SenderCallSign;
            if (string.IsNullOrEmpty(label)) label = rightClickedVoiceMessage.Route ?? "Unknown";

            MapLocationForm mapForm = new MapLocationForm(label, latitude, longitude);
            mapForm.Show();
        }

        private void voiceCopyMessageToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedVoiceMessage != null && !string.IsNullOrEmpty(rightClickedVoiceMessage.Message))
            {
                Clipboard.SetText(rightClickedVoiceMessage.Message);
            }
        }

        private void voiceCopyCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedVoiceMessage != null && !string.IsNullOrEmpty(rightClickedVoiceMessage.SenderCallSign))
            {
                Clipboard.SetText(rightClickedVoiceMessage.SenderCallSign);
            }
        }

        #endregion

        #region AllowTransmit State Management

        /// <summary>
        /// Handles AllowTransmit changes from the DataBroker.
        /// </summary>
        private void OnAllowTransmitChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnAllowTransmitChanged), deviceId, name, data);
                return;
            }

            if (data is int allowTransmitValue)
            {
                _allowTransmit = allowTransmitValue == 1;
            }
            else
            {
                _allowTransmit = false;
            }

            UpdateBottomPanelVisibility();
        }

        /// <summary>
        /// Loads the initial AllowTransmit state from the DataBroker.
        /// </summary>
        private void LoadAllowTransmitState()
        {
            _allowTransmit = broker.GetValue<int>(0, "AllowTransmit", 0) == 1;
            UpdateBottomPanelVisibility();
        }

        /// <summary>
        /// Updates the visibility of the voiceBottomPanel based on AllowTransmit setting.
        /// </summary>
        private void UpdateBottomPanelVisibility()
        {
            voiceBottomPanel.Visible = _allowTransmit;
        }

        #endregion

    }
}