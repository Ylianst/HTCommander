/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class VoiceTabUserControl : UserControl
    {
        private DataBrokerClient broker;
        private bool _showDetach = false;
        private bool _isListening = false;
        private bool _isProcessing = false;
        private bool _isTransmitting = false;

        // Voice handler state tracking
        private List<ConnectedRadioInfo> _connectedRadios = new List<ConnectedRadioInfo>();
        private bool _voiceHandlerEnabled = false;
        private int _voiceHandlerTargetDeviceId = -1;

        // Context menu for radio selection when multiple radios are connected
        private ContextMenuStrip _radioSelectContextMenuStrip;

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
            broker.Subscribe(0, "VoiceHandlerState", OnVoiceHandlerStateChanged);

            // Create context menu for radio selection
            _radioSelectContextMenuStrip = new ContextMenuStrip();

            // Load initial state
            LoadConnectedRadios();
            LoadVoiceHandlerState();
            UpdateEnableButtonState();
        }

        /// <summary>
        /// Handles events from the DataBroker
        /// </summary>
        private void OnBrokerEvent(int deviceId, string name, object data)
        {
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
                // Extract Text, Channel, Time, and Completed from the anonymous type
                var type = data.GetType();
                var textProp = type.GetProperty("Text");
                var channelProp = type.GetProperty("Channel");
                var timeProp = type.GetProperty("Time");
                var completedProp = type.GetProperty("Completed");

                if (textProp != null)
                {
                    string text = textProp.GetValue(data) as string;
                    string channel = channelProp?.GetValue(data) as string ?? "";
                    DateTime time = timeProp != null ? (DateTime)timeProp.GetValue(data) : DateTime.Now;
                    bool completed = completedProp != null && (bool)completedProp.GetValue(data);

                    if (!string.IsNullOrEmpty(text))
                    {
                        AppendVoiceHistory(text, channel, time, completed);
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
                voiceProcessingLabel.ForeColor = Color.Orange;
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
        /// Appends transcribed text to the voice history
        /// </summary>
        private void AppendVoiceHistory(string text, string channel, DateTime time, bool completed)
        {
            string timeStr = time.ToString("HH:mm:ss");
            string prefix = string.IsNullOrEmpty(channel) ? "" : $"[{channel}] ";
            string line = $"{timeStr} {prefix}{text}";

            if (completed)
            {
                voiceHistoryTextBox.AppendText(line + Environment.NewLine);
            }
            else
            {
                // For partial results, update the last line if it exists
                // or append a new line
                if (voiceHistoryTextBox.Lines.Length > 0)
                {
                    // Find the last line and check if it's a partial result
                    int lastLineStart = voiceHistoryTextBox.GetFirstCharIndexFromLine(voiceHistoryTextBox.Lines.Length - 1);
                    int lastLineLength = voiceHistoryTextBox.TextLength - lastLineStart;
                    
                    // Replace the last line with the updated partial result
                    voiceHistoryTextBox.Select(lastLineStart, lastLineLength);
                    voiceHistoryTextBox.SelectedText = line;
                }
                else
                {
                    voiceHistoryTextBox.AppendText(line);
                }
            }

            // Scroll to the end
            voiceHistoryTextBox.SelectionStart = voiceHistoryTextBox.TextLength;
            voiceHistoryTextBox.ScrollToCaret();
        }

        // Properties to access internal controls
        public RichTextBox VoiceHistoryTextBox => voiceHistoryTextBox;
        public TextBox SpeakTextBox => speakTextBox;
        public Button SpeakButton => speakButton;
        public Button VoiceEnableButton => voiceEnableButton;
        public Button CancelVoiceButton => cancelVoiceButton;
        public Label VoiceProcessingLabel => voiceProcessingLabel;
        public Panel VoiceBottomPanel => voiceBottomPanel;

        public bool IsSpeakMode => speakToolStripMenuItem.Checked;

        public void SetSpeakMode(bool speakMode)
        {
            speakToolStripMenuItem.Checked = speakMode;
            morseToolStripMenuItem.Checked = !speakMode;
            speakButton.Text = speakMode ? "&Speak" : "&Morse";
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
                // Multiple radios connected - show dropdown menu to select
                PopulateRadioSelectMenu();
                _radioSelectContextMenuStrip.Show(voiceEnableButton, new Point(0, voiceEnableButton.Height));
            }
            // If no radios connected, button should be disabled so this case shouldn't happen
        }

        private void speakButton_Click(object sender, EventArgs e)
        {
            // Send speak request to the broker
            if (string.IsNullOrWhiteSpace(speakTextBox.Text)) return;

            string text = speakTextBox.Text.Trim();
            bool isMorseMode = !IsSpeakMode;

            broker?.Dispatch(DataBroker.AllDevices, "SpeakRequest", new { Text = text, MorseMode = isMorseMode }, store: false);
            speakTextBox.Clear();
        }

        private void speakTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                speakButton_Click(sender, e);
            }
        }

        private void speakToolStripMenuItem_Click(object sender, EventArgs e)
        {
            SetSpeakMode(true);
        }

        private void morseToolStripMenuItem_Click(object sender, EventArgs e)
        {
            SetSpeakMode(false);
        }

        private void cancelVoiceButton_Click(object sender, EventArgs e)
        {
            // Cancel voice transmission - dispatch event to the broker
            broker?.Dispatch(DataBroker.AllDevices, "CancelVoiceTransmit", null, store: false);
        }

        private void clearHistoryToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Clear the voice history text box
            voiceHistoryTextBox.Clear();
        }

        private void voiceMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            voiceTabContextMenuStrip.Show(voiceMenuPictureBox, e.Location);
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<VoiceTabUserControl>("Voice");
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
                this.BeginInvoke(new Action<int, string, object>(OnVoiceHandlerStateChanged), deviceId, name, data);
                return;
            }

            ProcessVoiceHandlerState(data);
            UpdateEnableButtonState();
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
            var state = broker.GetValue<object>(0, "VoiceHandlerState", null);
            ProcessVoiceHandlerState(state);
        }

        /// <summary>
        /// Processes the VoiceHandlerState data object.
        /// </summary>
        private void ProcessVoiceHandlerState(object data)
        {
            if (data == null)
            {
                _voiceHandlerEnabled = false;
                _voiceHandlerTargetDeviceId = -1;
                return;
            }

            try
            {
                var type = data.GetType();
                var enabledProp = type.GetProperty("Enabled");
                var targetDeviceIdProp = type.GetProperty("TargetDeviceId");

                if (enabledProp != null)
                {
                    _voiceHandlerEnabled = (bool)enabledProp.GetValue(data);
                }

                if (targetDeviceIdProp != null)
                {
                    _voiceHandlerTargetDeviceId = (int)targetDeviceIdProp.GetValue(data);
                }
            }
            catch (Exception)
            {
                _voiceHandlerEnabled = false;
                _voiceHandlerTargetDeviceId = -1;
            }
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
            broker.Dispatch(0, "VoiceHandlerEnable", new
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
            broker.Dispatch(0, "VoiceHandlerDisable", null, store: false);
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
    }
}
