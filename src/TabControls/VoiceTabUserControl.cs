/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;
using System.Drawing.Imaging;
using System.Threading.Tasks;
using System.Collections.Generic;
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
            set
            {
                _preferredRadioDeviceId = value;
                if (value >= 100)
                {
                    EnableVoiceHandler(value);
                }
                else
                {
                    DisableVoiceHandler();
                }
            }
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

            // Subscribe to SpeechToTextEnabled setting changes
            broker.Subscribe(0, "SpeechToTextEnabled", OnSpeechToTextEnabledChanged);

            // Subscribe to RecordingState changes (device 0 for registry persistence)
            broker.Subscribe(0, "RecordingState", OnRecordingStateChanged);

            // Subscribe to Settings and HtStatus changes from all radios to detect APRS/NOAA channel
            broker.Subscribe(DataBroker.AllDevices, new[] { "Settings", "HtStatus" }, OnChannelRelatedChange);

            // Create context menu for radio selection
            _radioSelectContextMenuStrip = new ContextMenuStrip();

            // Load initial state
            LoadConnectedRadios();
            LoadVoiceHandlerState();
            LoadAllowTransmitState();
            LoadSpeechToTextEnabledState();
            LoadRecordingState();
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
                var sourceProp = type.GetProperty("Source");
                var destinationProp = type.GetProperty("Destination");
                var filenameProp = type.GetProperty("Filename");
                var durationProp = type.GetProperty("Duration");
                var partialImageProp = type.GetProperty("PartialImage");

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
                    string source = sourceProp?.GetValue(data) as string;
                    string destination = destinationProp?.GetValue(data) as string;
                    string filename = filenameProp?.GetValue(data) as string;
                    int duration = 0;
                    if (durationProp != null)
                    {
                        object durValue = durationProp.GetValue(data);
                        if (durValue is int di) duration = di;
                    }
                    Image partialImage = null;
                    if (partialImageProp != null)
                    {
                        partialImage = partialImageProp.GetValue(data) as Image;
                    }

                    if (!string.IsNullOrEmpty(text) || encoding == VoiceTextEncodingType.Recording || encoding == VoiceTextEncodingType.Picture)
                    {
                        AppendVoiceHistory(text ?? "", channel, time, completed, isReceived, encoding, latitude, longitude, source, destination, filename, duration, partialImage);
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
        /// Handles Settings/HtStatus changes to update UI when the radio channel changes.
        /// </summary>
        private void OnChannelRelatedChange(int deviceId, string name, object data)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Action(() => OnChannelRelatedChange(deviceId, name, data))); return; }
            if (deviceId == _voiceHandlerTargetDeviceId)
            {
                UpdateTransmitState();
                UpdateSpeakButtonState();
            }
        }

        /// <summary>
        /// Checks if the target radio's VFO A is on the APRS or NOAA channel.
        /// </summary>
        private bool IsOnAprsOrNoaaChannel()
        {
            if (_voiceHandlerTargetDeviceId < 0) return false;

            // Check for NOAA channel via HtStatus (curr_ch_id >= 254), since channel_a in Settings may not reflect NOAA
            var htStatus = broker.GetValue<RadioHtStatus>(_voiceHandlerTargetDeviceId, "HtStatus", null);
            if (htStatus != null && htStatus.curr_ch_id >= 254) return true;

            // Check via Settings for APRS channel name
            var settings = broker.GetValue<RadioSettings>(_voiceHandlerTargetDeviceId, "Settings", null);
            if (settings == null) return false;

            var channels = broker.GetValue<RadioChannelInfo[]>(_voiceHandlerTargetDeviceId, "Channels", null);

            // Also check channel_a for NOAA in case HtStatus is not yet available
            if (channels != null && settings.channel_a >= 0 && settings.channel_a < channels.Length && channels[settings.channel_a] != null)
            {
                if (channels[settings.channel_a].channel_id >= 254) return true;
                if (string.Equals(channels[settings.channel_a].name_str, "APRS", StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        /// <summary>
        /// Updates the UI based on voice transmit state
        /// </summary>
        private void UpdateTransmitState()
        {
            bool isRestrictedChannel = IsOnAprsOrNoaaChannel();
            cancelVoiceButton.Visible = _isTransmitting;
            speakTextBox.Enabled = _voiceHandlerEnabled && !isRestrictedChannel;
            speakButton.Enabled = !_isTransmitting && speakTextBox.Enabled;
            bool canTransmit = _voiceHandlerEnabled && !_isTransmitting && !isRestrictedChannel;
            imageToolStripMenuItem.Enabled = canTransmit;
            audioToolStripMenuItem.Enabled = canTransmit;
        }

        /// <summary>
        /// Appends transcribed text to the voice history using the VoiceControl.
        /// </summary>
        private void AppendVoiceHistory(string text, string channel, DateTime time, bool completed, bool isReceived = true, VoiceTextEncodingType encoding = VoiceTextEncodingType.Voice, double latitude = 0, double longitude = 0, string source = null, string destination = null, string filename = null, int duration = 0, Image partialImage = null)
        {
            voiceControl.UpdatePartialMessage(text, channel, time, completed, isReceived, encoding, latitude, longitude, source, destination, filename, duration, partialImage);
        }

        // Properties to access internal controls
        public VoiceControl VoiceHistoryControl => voiceControl;
        public TextBox SpeakTextBox => speakTextBox;
        public Button SpeakButton => speakButton;
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
            bool isRestrictedChannel = IsOnAprsOrNoaaChannel();
            bool hasText = !string.IsNullOrWhiteSpace(speakTextBox.Text);
            speakTextBox.Enabled = _voiceHandlerEnabled && !isRestrictedChannel;
            speakButton.Enabled = hasText && _voiceHandlerEnabled && !_isTransmitting && !isRestrictedChannel;
            bool canTransmit = _voiceHandlerEnabled && !_isTransmitting && !isRestrictedChannel;
            imageToolStripMenuItem.Enabled = canTransmit;
            audioToolStripMenuItem.Enabled = canTransmit;
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
        /// Handles the SpeechToTextEnabled setting change from DataBroker.
        /// </summary>
        private void OnSpeechToTextEnabledChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action<int, string, object>(OnSpeechToTextEnabledChanged), deviceId, name, data); }
                catch (Exception) { }
                return;
            }

            bool enabled = true;
            if (data is bool boolValue) { enabled = boolValue; }
            speechtoTextToolStripMenuItem.Checked = enabled;
        }

        /// <summary>
        /// Loads the initial SpeechToTextEnabled state from the DataBroker.
        /// </summary>
        private void LoadSpeechToTextEnabledState()
        {
            bool enabled = broker.GetValue<bool>(0, "SpeechToTextEnabled", true);
            speechtoTextToolStripMenuItem.Checked = enabled;
        }

        /// <summary>
        /// Handles the Speech-to-Text menu item click to toggle the setting.
        /// </summary>
        private void speechtoTextToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool newValue = !speechtoTextToolStripMenuItem.Checked;
            speechtoTextToolStripMenuItem.Checked = newValue;
            broker?.Dispatch(0, "SpeechToTextEnabled", newValue, store: true);
        }

        /// <summary>
        /// Handles the RecordingState change from DataBroker.
        /// </summary>
        private void OnRecordingStateChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                try { this.BeginInvoke(new Action<int, string, object>(OnRecordingStateChanged), deviceId, name, data); }
                catch (Exception) { }
                return;
            }

            bool enabled = false;
            if (data is bool boolValue) { enabled = boolValue; }
            recordAudioToolStripMenuItem.Checked = enabled;
        }

        /// <summary>
        /// Loads the initial RecordingState from the DataBroker.
        /// </summary>
        private void LoadRecordingState()
        {
            bool enabled = broker.GetValue<bool>(0, "RecordingState", false);
            recordAudioToolStripMenuItem.Checked = enabled;
        }

        /// <summary>
        /// Handles the Record Audio menu item click to toggle recording.
        /// </summary>
        private void recordAudioToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool newValue = !recordAudioToolStripMenuItem.Checked;
            broker?.Dispatch(1, newValue ? "RecordingEnable" : "RecordingDisable", null, store: false);
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
                    // Skip entries with null or empty text after trimming (except Recording entries which use Filename)
                    string trimmedText = entry.Text?.Trim();
                    if (string.IsNullOrEmpty(trimmedText) && entry.Encoding != VoiceTextEncodingType.Recording) continue;

                    // Determine if message has a valid location (set ImageIndex = 3 for location icon)
                    bool hasLocation = (entry.Latitude != 0 || entry.Longitude != 0);
                    int imageIndex = hasLocation ? 3 : -1;

                    var message = new VoiceMessage(
                        FormatRoute(entry.Channel, entry.Encoding, entry.Source, entry.Destination, entry.Duration),
                        entry.Source,
                        trimmedText,
                        entry.Time,
                        !entry.IsReceived,
                        imageIndex,
                        entry.Encoding
                    );
                    message.IsCompleted = true;
                    message.Latitude = entry.Latitude;
                    message.Longitude = entry.Longitude;
                    message.Filename = entry.Filename;
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
                        FormatRoute(currentEntry.Channel, currentEntry.Encoding, currentEntry.Source, currentEntry.Destination, currentEntry.Duration),
                        currentEntry.Source,
                        trimmedText,
                        currentEntry.Time,
                        !currentEntry.IsReceived,
                        imageIndex,
                        currentEntry.Encoding
                    );
                    message.IsCompleted = false;
                    message.Latitude = currentEntry.Latitude;
                    message.Longitude = currentEntry.Longitude;
                    message.Filename = currentEntry.Filename;
                    voiceControl.Messages.Add(message);
                }
            }

            // Update and scroll to bottom
            voiceControl.UpdateMessages(true);
        }

        /// <summary>
        /// Formats the route string to include encoding type.
        /// </summary>
        private string FormatRoute(string channel, VoiceTextEncodingType encoding, string source = null, string destination = null, int duration = 0)
        {
            string encodingStr = GetEncodingTypeName(encoding);
            if (encoding == VoiceTextEncodingType.Recording && duration > 0)
            {
                encodingStr = "Recording " + FormatDuration(duration);
            }
            string callsignPart = "";
            if (!string.IsNullOrEmpty(source))
            {
                callsignPart = !string.IsNullOrEmpty(destination)
                    ? $" {source} > {destination}"
                    : $" {source}";
            }
            if (string.IsNullOrEmpty(channel))
            {
                return encodingStr + callsignPart;
            }
            return $"[{channel}] {encodingStr}{callsignPart}";
        }

        /// <summary>
        /// Formats a duration in seconds into a human-readable string.
        /// Less than 60 seconds: "34s", 60 or more: "5m 34s".
        /// </summary>
        private string FormatDuration(int totalSeconds)
        {
            if (totalSeconds < 60) return $"{totalSeconds}s";
            int minutes = totalSeconds / 60;
            int seconds = totalSeconds % 60;
            return seconds > 0 ? $"{minutes}m {seconds}s" : $"{minutes}m";
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
                case VoiceTextEncodingType.Picture: return "SSTV";
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
        /// Updates internal state tracking (formerly updated the Enable button).
        /// </summary>
        private void UpdateEnableButtonState()
        {
            // No-op: voice handler is now controlled via PreferredRadioDeviceId
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

            // Hide show location if the message has no valid position data
            bool hasPosition = (rightClickedVoiceMessage.Latitude != 0 || rightClickedVoiceMessage.Longitude != 0);
            showLocationToolStripMenuItem.Visible = hasPosition;

            // Hide copy callsign if callsign is not available
            copyCallsignToolStripMenuItem.Visible = !string.IsNullOrEmpty(rightClickedVoiceMessage.SenderCallSign);

            // Hide copy message if message text is not available
            copyMessageToolStripMenuItem.Visible = !string.IsNullOrEmpty(rightClickedVoiceMessage.Message);

            // Show "View..." for picture messages with a valid file or recording messages with a valid file
            bool hasImage = (rightClickedVoiceMessage.Encoding == VoiceTextEncodingType.Picture) && !string.IsNullOrEmpty(rightClickedVoiceMessage.Filename);
            bool hasRecording = (rightClickedVoiceMessage.Encoding == VoiceTextEncodingType.Recording) && !string.IsNullOrEmpty(rightClickedVoiceMessage.Filename);
            viewToolStripMenuItem.Visible = hasImage || hasRecording;
            copyImageToolStripMenuItem.Visible = hasImage;
            saveAsToolStripMenuItem.Visible = hasImage || hasRecording;
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

        private void voiceCopyImageToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedVoiceMessage == null || string.IsNullOrEmpty(rightClickedVoiceMessage.Filename)) return;
            try
            {
                string fullPath = VoiceControl.GetSstvImagePath(rightClickedVoiceMessage.Filename);
                if (!System.IO.File.Exists(fullPath)) return;
                using (var image = System.Drawing.Image.FromFile(fullPath))
                {
                    Clipboard.SetImage(image);
                }
            }
            catch { }
        }

        private void saveAsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedVoiceMessage == null || string.IsNullOrEmpty(rightClickedVoiceMessage.Filename)) return;

            string sourcePath;
            string filter;

            if (rightClickedVoiceMessage.Encoding == VoiceTextEncodingType.Picture)
            {
                sourcePath = VoiceControl.GetSstvImagePath(rightClickedVoiceMessage.Filename);
                filter = "PNG Image|*.png|All Files|*.*";
            }
            else if (rightClickedVoiceMessage.Encoding == VoiceTextEncodingType.Recording)
            {
                sourcePath = RecordingPlaybackForm.GetRecordingPath(rightClickedVoiceMessage.Filename);
                filter = "WAV Audio|*.wav|All Files|*.*";
            }
            else
            {
                return;
            }

            if (!System.IO.File.Exists(sourcePath))
            {
                MessageBox.Show("Source file not found.", "Save As", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            using (var dlg = new SaveFileDialog())
            {
                dlg.Title = "Save As";
                dlg.Filter = filter;
                dlg.FileName = rightClickedVoiceMessage.Filename;
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                try
                {
                    System.IO.File.Copy(sourcePath, dlg.FileName, true);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Failed to save file: " + ex.Message, "Save As", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void voiceViewToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedVoiceMessage == null || string.IsNullOrEmpty(rightClickedVoiceMessage.Filename)) return;

            if (rightClickedVoiceMessage.Encoding == VoiceTextEncodingType.Recording)
            {
                ShowRecordingPlayback(rightClickedVoiceMessage);
            }
            else
            {
                string fullPath = VoiceControl.GetSstvImagePath(rightClickedVoiceMessage.Filename);
                if (!System.IO.File.Exists(fullPath)) return;
                ImagePreviewForm form = new ImagePreviewForm(fullPath);
                form.Show(this);
            }
        }

        private void voiceControl_MouseDoubleClick(object sender, MouseEventArgs e)
        {
            VoiceMessage msg = voiceControl.GetVoiceMessageAtXY(e.X, e.Y);
            if (msg == null) return;

            if (msg.Encoding == VoiceTextEncodingType.Picture && !string.IsNullOrEmpty(msg.Filename))
            {
                // Show image preview for picture messages
                string fullPath = VoiceControl.GetSstvImagePath(msg.Filename);
                if (System.IO.File.Exists(fullPath))
                {
                    ImagePreviewForm form = new ImagePreviewForm(fullPath);
                    form.Show(this);
                }
            }
            else if (msg.Encoding == VoiceTextEncodingType.Recording && !string.IsNullOrEmpty(msg.Filename))
            {
                // Show recording playback for recording messages
                ShowRecordingPlayback(msg);
            }
            else
            {
                // Show details for all other message types
                VoiceDetailsForm form = new VoiceDetailsForm();
                form.SetMessage(msg);
                form.ShowDialog(this);
            }
        }

        /// <summary>
        /// Opens the recording playback dialog for the given voice message.
        /// </summary>
        private void ShowRecordingPlayback(VoiceMessage msg)
        {
            if (msg == null || string.IsNullOrEmpty(msg.Filename)) return;
            string fullPath = RecordingPlaybackForm.GetRecordingPath(msg.Filename);
            if (!System.IO.File.Exists(fullPath))
            {
                MessageBox.Show("Recording file not found.", "Recording", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            RecordingPlaybackForm form = new RecordingPlaybackForm(fullPath);
            form.Show(this);
        }

        #endregion

        #region Image and Audio file selection

        private void imageToolStripMenuItem_Click(object sender, EventArgs e)
        {
            using (var dlg = new OpenFileDialog())
            {
                dlg.Title = "Select Image for SSTV";
                dlg.Filter = "Image Files|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.ico;*.webp|All Files|*.*";
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                string filePath = dlg.FileName;
                if (!IsImageFile(filePath)) return;

                try
                {
                    using (var image = Image.FromFile(filePath))
                    {
                        SendSstvImage(image);
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Failed to load image: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void audioToolStripMenuItem_Click(object sender, EventArgs e)
        {
            using (var dlg = new OpenFileDialog())
            {
                dlg.Title = "Select Audio File";
                dlg.Filter = "WAV Files|*.wav|All Files|*.*";
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                string filePath = dlg.FileName;
                string fileName = System.IO.Path.GetFileName(filePath);

                if (MessageBox.Show($"Transmit audio file \"{fileName}\"?", "Transmit Audio", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;

                int targetDeviceId = _voiceHandlerTargetDeviceId;
                if (targetDeviceId < 0)
                {
                    MessageBox.Show("No radio is connected for voice transmission.", "Transmit Audio", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                Task.Run(() =>
                {
                    try
                    {
                        // Read the WAV file and convert to 32kHz 16-bit mono PCM
                        byte[] pcmData;
                        using (var reader = new NAudio.Wave.AudioFileReader(filePath))
                        {
                            // Resample to 32kHz mono
                            var targetFormat = new NAudio.Wave.WaveFormat(32000, 16, 1);
                            using (var resampler = new NAudio.Wave.MediaFoundationResampler(reader, targetFormat))
                            {
                                resampler.ResamplerQuality = 60;
                                using (var ms = new System.IO.MemoryStream())
                                {
                                    byte[] buf = new byte[8192];
                                    int bytesRead;
                                    while ((bytesRead = resampler.Read(buf, 0, buf.Length)) > 0)
                                    {
                                        ms.Write(buf, 0, bytesRead);
                                    }
                                    pcmData = ms.ToArray();
                                }
                            }
                        }

                        if (pcmData.Length == 0)
                        {
                            this.BeginInvoke((Action)(() =>
                            {
                                MessageBox.Show("The audio file is empty.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            }));
                            return;
                        }

                        broker.Dispatch(targetDeviceId, "TransmitVoicePCM", new { Data = pcmData, PlayLocally = true }, store: false);
                    }
                    catch (Exception ex)
                    {
                        this.BeginInvoke((Action)(() =>
                        {
                            MessageBox.Show("Failed to transmit audio: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }));
                    }
                });
            }
        }

        #endregion

        #region Drag and Drop for SSTV

        private void voiceControl_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files != null && files.Length == 1 && IsImageFile(files[0]))
                {
                    e.Effect = DragDropEffects.Copy;
                    return;
                }
            }
            e.Effect = DragDropEffects.None;
        }

        private void voiceControl_DragDrop(object sender, DragEventArgs e)
        {
            if (!e.Data.GetDataPresent(DataFormats.FileDrop)) return;

            string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
            if (files == null || files.Length != 1) return;

            string filePath = files[0];
            if (!IsImageFile(filePath)) return;

            try
            {
                using (var image = Image.FromFile(filePath))
                {
                    SendSstvImage(image);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Failed to load image: " + ex.Message,
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        /// <summary>
        /// Checks if a file path refers to a supported image format.
        /// </summary>
        private static bool IsImageFile(string path)
        {
            string ext = System.IO.Path.GetExtension(path);
            if (string.IsNullOrEmpty(ext)) return false;
            ext = ext.ToLowerInvariant();
            return ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".bmp" || ext == ".gif" || ext == ".tif" || ext == ".tiff" || ext == ".ico" || ext == ".webp";
        }

        /// <summary>
        /// Shows the SSTV send dialog for the given image and transmits if confirmed.
        /// </summary>
        private void SendSstvImage(Image image)
        {
            using (var form = new SstvSendForm())
            {
                form.SetImage(image);
                if (form.ShowDialog(this) != DialogResult.OK) return;

                string modeName = form.SelectedMode;
                Image scaledImage = form.ScaledImage;
                int targetDeviceId = _voiceHandlerTargetDeviceId;

                if (targetDeviceId < 0)
                {
                    MessageBox.Show("No radio is connected for voice transmission.", "SSTV", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // Save the scaled image to the SSTV application folder
                string sstvFolder = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "HTCommander", "SSTV");
                if (!System.IO.Directory.Exists(sstvFolder))
                {
                    System.IO.Directory.CreateDirectory(sstvFolder);
                }
                DateTime now = DateTime.Now;
                string safeMode = modeName.Replace(" ", "_").Replace("\u2013", "-");
                string imageFilename = $"SSTV_{now:yyyy-MM-dd}_{now:HH-mm-ss}_{safeMode}.png";
                string imageFullPath = System.IO.Path.Combine(sstvFolder, imageFilename);
                scaledImage.Save(imageFullPath, System.Drawing.Imaging.ImageFormat.Png);

                // Extract ARGB pixel data from the scaled image
                Bitmap bmp = new Bitmap(scaledImage);
                int w = bmp.Width;
                int h = bmp.Height;
                int[] pixels = new int[w * h];
                BitmapData bmpData = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                System.Runtime.InteropServices.Marshal.Copy(bmpData.Scan0, pixels, 0, pixels.Length);
                bmp.UnlockBits(bmpData);
                bmp.Dispose();

                // Notify VoiceHandler to record the picture transmission in history
                broker.Dispatch(targetDeviceId, "PictureTransmitted", new { ModeName = modeName, Filename = imageFilename }, store: false);

                // Encode and transmit on a background thread to keep the UI responsive
                Task.Run(() =>
                {
                    try
                    {
                        // Encode the image to SSTV audio at 32 kHz
                        var encoder = new SSTV.Encoder(32000);
                        float[] samples = encoder.Encode(pixels, w, h, modeName);

                        // Convert float samples to 16-bit signed PCM byte array
                        byte[] pcmData = new byte[samples.Length * 2];
                        for (int i = 0; i < samples.Length; i++)
                        {
                            float s = samples[i];
                            if (s > 1f) s = 1f;
                            else if (s < -1f) s = -1f;
                            short sample16 = (short)(s * 32767);
                            pcmData[i * 2] = (byte)(sample16 & 0xFF);
                            pcmData[i * 2 + 1] = (byte)((sample16 >> 8) & 0xFF);
                        }

                        // Send PCM data to the radio for transmission
                        broker.Dispatch(targetDeviceId, "TransmitVoicePCM", new { Data = pcmData, PlayLocally = false }, store: false);
                    }
                    catch (Exception ex)
                    {
                        this.BeginInvoke((Action)(() =>
                        {
                            MessageBox.Show("SSTV encoding failed: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        }));
                    }
                });
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

        private void toolsPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            speakContextMenuStrip.Show(toolsPictureBox, e.Location);
        }
    }
}