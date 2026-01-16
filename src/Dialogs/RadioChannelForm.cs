/*
Copyright 2026 Ylian Saint-Hilaire

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
using System.Drawing;
using System.Windows.Forms;
using static HTCommander.Radio;

namespace HTCommander
{
    public partial class RadioChannelForm : Form
    {
        private DataBrokerClient broker;
        private RadioChannelInfo channel;
        private Color normalBackColor;
        private int deviceId = -1;
        private int channelId = -1;
        private bool advancedMode = false;
        private bool xreadonly = false;
        private string friendlyName = null;

        /// <summary>
        /// Constructor for editing a channel on a connected radio.
        /// </summary>
        /// <param name="deviceId">The device ID of the connected radio.</param>
        /// <param name="channelId">The channel ID to view/edit.</param>
        public RadioChannelForm(int deviceId, int channelId)
        {
            InitializeComponent();
            this.deviceId = deviceId;
            this.channelId = channelId;
            this.xreadonly = false;

            // Set up DataBrokerClient
            broker = new DataBrokerClient();

            // Subscribe to channel updates and friendly name changes
            broker.Subscribe(deviceId, new[] { "Channels", "FriendlyName" }, OnBrokerEvent);

            // Load the initial friendly name
            friendlyName = GetFriendlyNameFromConnectedRadios(deviceId);
            UpdateFormTitle();

            advGroupBox.Location = basicGroupBox.Location;
            advGroupBox.Visible = false;
            basicGroupBox.Visible = true;
            this.Height = basicGroupBox.Height + 158;
            clearButton.Top = cancelButton.Top = okButton.Top = (this.Height - 74);
            normalBackColor = freqTextBox.BackColor;
            this.PerformLayout();
        }

        /// <summary>
        /// Constructor for viewing an imported/external channel (read-only mode).
        /// </summary>
        /// <param name="channelInfo">The RadioChannelInfo to display.</param>
        public RadioChannelForm(RadioChannelInfo channelInfo)
        {
            InitializeComponent();
            this.deviceId = -1;
            this.channelId = channelInfo.channel_id;
            this.channel = channelInfo;
            this.xreadonly = true;

            // No broker needed for read-only imported channels
            broker = null;

            // Set title for imported channel
            UpdateFormTitle();

            advGroupBox.Location = basicGroupBox.Location;
            advGroupBox.Visible = false;
            basicGroupBox.Visible = true;
            this.Height = basicGroupBox.Height + 158;
            clearButton.Top = cancelButton.Top = okButton.Top = (this.Height - 74);
            normalBackColor = freqTextBox.BackColor;
            this.PerformLayout();
        }

        /// <summary>
        /// Gets the FriendlyName for a device from the ConnectedRadios list.
        /// </summary>
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
        /// Updates the form title based on the radio friendly name and channel ID.
        /// </summary>
        private void UpdateFormTitle()
        {
            if (deviceId > 0)
            {
                // Connected radio - show "FriendlyName Channel X" or "Channel X" if no friendly name
                if (!string.IsNullOrEmpty(friendlyName))
                {
                    this.Text = friendlyName + " Channel " + (channelId + 1).ToString();
                }
                else
                {
                    this.Text = "Channel " + (channelId + 1).ToString();
                }
            }
            else if (channel != null && !string.IsNullOrEmpty(channel.name_str))
            {
                // Imported channel - show channel name
                this.Text = "Channel - " + channel.name_str;
            }
            else if (channelId >= 0)
            {
                // Fallback - show channel number
                this.Text = "Channel " + (channelId + 1).ToString();
            }
            else
            {
                this.Text = "Channel";
            }
        }

        private void RadioInfoForm_Load(object sender, EventArgs e)
        {
            UpdateChannel();
        }

        /// <summary>
        /// Handles broker events for channels and friendly name changes.
        /// </summary>
        private void OnBrokerEvent(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => OnBrokerEvent(deviceId, name, data)));
                return;
            }

            switch (name)
            {
                case "Channels":
                    // Refresh the channel display when channels are updated
                    UpdateChannel();
                    break;
                case "FriendlyName":
                    // Update the friendly name and refresh the form title
                    friendlyName = data as string;
                    UpdateFormTitle();
                    break;
            }
        }

        public void UpdateChannel()
        {
            RadioChannelInfo c = channel;

            // If we have a deviceId, get the channel from the broker
            if (deviceId > 0)
            {
                RadioChannelInfo[] channels = DataBroker.GetValue<RadioChannelInfo[]>(deviceId, "Channels", null);
                if (channels != null && channelId >= 0 && channelId < channels.Length && channels[channelId] != null)
                {
                    c = channels[channelId];
                }
            }

            if (c == null) return;

            nameTextBox.Text = c.name_str;
            advNameTextBox.Text = c.name_str;
            if (c.tx_freq == 0) { c.tx_freq = c.rx_freq; }
            if (c.rx_freq == 0) { c.rx_freq = c.tx_freq; }
            advTransmitFreqTextBox.Text = freqTextBox.Text = (((float)c.tx_freq) / 1000000).ToString();
            advReceiveFreqTextBox.Text = (((float)c.rx_freq) / 1000000).ToString();

            disableTransmitCheckBox.Checked = advDisableTransmitCheckBox.Checked = c.tx_disable;
            muteCheckBox.Checked = advMuteCheckBox.Checked = c.mute;
            advScanCheckBox.Checked = c.scan;
            advTalkAroundCheckBox.Checked = c.talk_around;
            deemphasisCheckBox.Checked = !c.pre_de_emph_bypass;

            advModeComboBox.SelectedIndex = modeComboBox.SelectedIndex = 0;
            if ((c.tx_mod == RadioModulationType.AM) || (c.rx_mod == RadioModulationType.AM)) { advModeComboBox.SelectedIndex = modeComboBox.SelectedIndex = 1; }
            if (c.bandwidth == RadioBandwidthType.WIDE) { advBandwidthComboBox.SelectedIndex = 0; }
            if (c.bandwidth == RadioBandwidthType.NARROW) { advBandwidthComboBox.SelectedIndex = 1; }

            if (c.tx_at_max_power) { powerComboBox.SelectedIndex = advPowerComboBox.SelectedIndex = 0; }
            else if (c.tx_at_med_power) { powerComboBox.SelectedIndex = advPowerComboBox.SelectedIndex = 1; }
            else { powerComboBox.SelectedIndex = advPowerComboBox.SelectedIndex = 2; }
            if (c.tx_sub_audio == 0)
            {
                transmitCtcssComboBox.SelectedIndex = 0;
            }
            else
            {
                string x = (((float)c.tx_sub_audio) / 100).ToString("F1") + " Hz";
                if (c.tx_sub_audio < 1000) { x = "DCS-" + ((int)(c.tx_sub_audio)).ToString("D3") + "N"; }
                for (int i = 1; i < transmitCtcssComboBox.Items.Count; i++)
                {
                    if (transmitCtcssComboBox.Items[i].ToString().StartsWith(x)) { transmitCtcssComboBox.SelectedIndex = i; }
                }
            }
            if (c.rx_sub_audio == 0)
            {
                receiveCtcssComboBox.SelectedIndex = 0;
            }
            else
            {
                string x = (((float)c.rx_sub_audio) / 100).ToString("F1") + " Hz";
                if (c.rx_sub_audio < 1000) { x = "DCS-" + ((int)(c.rx_sub_audio)).ToString("D3") + "N"; }
                for (int i = 1; i < receiveCtcssComboBox.Items.Count; i++)
                {
                    if (receiveCtcssComboBox.Items[i].ToString().StartsWith(x)) { receiveCtcssComboBox.SelectedIndex = i; }
                }
            }

            if ((advTransmitFreqTextBox.Text != advReceiveFreqTextBox.Text) || (c.tx_sub_audio != 0) || (c.rx_sub_audio != 0) || (c.talk_around) || (c.scan) || (c.bandwidth == RadioBandwidthType.NARROW)) { MoveToAdvancedMode(); }
        }

        public void UpdateChannel(int channelId)
        {
            this.channelId = channelId;
            UpdateChannel();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            // Can only save if we have a valid deviceId (connected radio)
            if (deviceId <= 0) return;

            // Get the current channel from the broker
            RadioChannelInfo[] channels = DataBroker.GetValue<RadioChannelInfo[]>(deviceId, "Channels", null);
            if (channels == null || channelId < 0 || channelId >= channels.Length || channels[channelId] == null) return;

            // Create a copy of the channel and set everything
            RadioChannelInfo c = new RadioChannelInfo(channels[channelId]);
            c.name_str = advNameTextBox.Text;

            if (advancedMode)
            {
                double freq;
                if (double.TryParse(advReceiveFreqTextBox.Text, out freq) == false) return;
                c.rx_freq = (int)Math.Round(freq * 1000000);
                if (double.TryParse(advTransmitFreqTextBox.Text, out freq) == false) return;
                c.tx_freq = (int)Math.Round(freq * 1000000);

                if (advPowerComboBox.SelectedIndex == 0) { c.tx_at_max_power = true; c.tx_at_med_power = false; }
                if (advPowerComboBox.SelectedIndex == 1) { c.tx_at_max_power = false; c.tx_at_med_power = true; }
                if (advPowerComboBox.SelectedIndex == 2) { c.tx_at_max_power = false; c.tx_at_med_power = false; }

                c.tx_disable = advDisableTransmitCheckBox.Checked;
                c.mute = advMuteCheckBox.Checked;
                c.scan = advScanCheckBox.Checked;
                c.talk_around = advTalkAroundCheckBox.Checked;
                c.pre_de_emph_bypass = !deemphasisCheckBox.Checked;

                if (advModeComboBox.SelectedIndex == 0) { c.tx_mod = c.rx_mod = RadioModulationType.FM; }
                if (advModeComboBox.SelectedIndex == 1) { c.tx_mod = c.rx_mod = RadioModulationType.AM; }
                if (advBandwidthComboBox.SelectedIndex == 0) { c.bandwidth = RadioBandwidthType.WIDE; }
                if (advBandwidthComboBox.SelectedIndex == 1) { c.bandwidth = RadioBandwidthType.NARROW; }

                c.rx_sub_audio = ToneStringToValue(receiveCtcssComboBox.Text);
                c.tx_sub_audio = ToneStringToValue(transmitCtcssComboBox.Text);
                if ((c.rx_sub_audio == -1) || (c.tx_sub_audio == -1)) return;
            }
            else
            {
                float freq;
                if (float.TryParse(freqTextBox.Text, out freq) == false) return;
                c.rx_freq = c.tx_freq = (int)Math.Round(freq * 1000000);

                if (powerComboBox.SelectedIndex == 0) { c.tx_at_max_power = true; c.tx_at_med_power = false; }
                if (powerComboBox.SelectedIndex == 1) { c.tx_at_max_power = false; c.tx_at_med_power = true; }
                if (powerComboBox.SelectedIndex == 2) { c.tx_at_max_power = false; c.tx_at_med_power = false; }

                c.tx_disable = disableTransmitCheckBox.Checked;
                c.mute = muteCheckBox.Checked;

                if (modeComboBox.SelectedIndex == 0) { c.tx_mod = c.rx_mod = RadioModulationType.FM; }
                if (modeComboBox.SelectedIndex == 1) { c.tx_mod = c.rx_mod = RadioModulationType.AM; }
            }

            // Check if the channel has changed
            if (!channels[channelId].Equals(c))
            {
                // Dispatch the updated channel to the broker
                DataBroker.Dispatch(deviceId, "WriteChannel", c, store: false);
            }

            Close();
        }

        private int ToneStringToValue(string tone)
        {
            if ((tone == null) || (tone.Length == 0)) return 0;
            if (tone == "None") { return 0; }

            if (tone.EndsWith(" Hz"))
            {
                float f;
                if (float.TryParse(tone.Split(' ')[0], out f) == false) return -1;
                return (int)Math.Round(f * 100);
            }

            if (tone.StartsWith("DCS-"))
            {
                int f;
                if (int.TryParse(tone.Substring(4, 3), out f) == false) return -1;
                return f;
            }

            return -1;
        }

        private void RadioChannelForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            // Dispose the broker if it exists
            broker?.Dispose();
        }

        private void repeaterBookLinkLabel_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start(repeaterBookLinkLabel.Text);
        }

        private void moreSettingsButton_Click(object sender, EventArgs e)
        {
            MoveToAdvancedMode();
        }

        private void MoveToAdvancedMode()
        {
            advancedMode = true;
            advGroupBox.Visible = true;
            basicGroupBox.Visible = false;
            this.Height = advGroupBox.Height + 158;
            clearButton.Top = cancelButton.Top = okButton.Top = (this.Height - 74);
            this.PerformLayout();
            this.Refresh();
        }

        private void disableTransmitCheckBox_CheckedChanged(object sender, EventArgs e)
        {
            advDisableTransmitCheckBox.Checked = disableTransmitCheckBox.Checked;
        }

        private void muteCheckBox_CheckedChanged(object sender, EventArgs e)
        {
            advMuteCheckBox.Checked = muteCheckBox.Checked;
        }

        private void nameTextBox_TextChanged(object sender, EventArgs e)
        {
            advNameTextBox.Text = nameTextBox.Text;
        }

        private void freqTextBox_TextChanged(object sender, EventArgs e)
        {
            advReceiveFreqTextBox.Text = advTransmitFreqTextBox.Text = freqTextBox.Text;
            UpdateInfo();
        }

        private void UpdateInfo()
        {
            if (xreadonly)
            {
                okButton.Visible = false;
                cancelButton.Text = "Close";
                clearButton.Visible = false;
                nameTextBox.Enabled = freqTextBox.Enabled = modeComboBox.Enabled = false;
                powerComboBox.Enabled = false;
                disableTransmitCheckBox.Enabled = false;
                muteCheckBox.Enabled = false;
                moreSettingsButton.Visible = false;
                advNameTextBox.Enabled = advReceiveFreqTextBox.Enabled = false;
                advModeComboBox.Enabled = advTransmitFreqTextBox.Enabled = false;
                transmitCtcssComboBox.Enabled = receiveCtcssComboBox.Enabled = false;
                advBandwidthComboBox.Enabled = advPowerComboBox.Enabled = false;
                advDisableTransmitCheckBox.Enabled = advMuteCheckBox.Enabled = false;
                advScanCheckBox.Enabled = advTalkAroundCheckBox.Enabled = deemphasisCheckBox.Enabled = false;
                freqTextBox.BackColor = normalBackColor;
                advReceiveFreqTextBox.BackColor = normalBackColor;
                advTransmitFreqTextBox.BackColor = normalBackColor;
            }

            bool f1 = CheckFreqRange(freqTextBox.Text, advancedMode ? advModeComboBox.SelectedIndex : modeComboBox.SelectedIndex);
            bool f2 = CheckFreqRange(advReceiveFreqTextBox.Text, advancedMode ? advModeComboBox.SelectedIndex : modeComboBox.SelectedIndex);
            bool f3 = CheckFreqRange(advTransmitFreqTextBox.Text, advancedMode ? advModeComboBox.SelectedIndex : modeComboBox.SelectedIndex);

            freqTextBox.BackColor = f1 ? normalBackColor : Color.LightSalmon;
            advReceiveFreqTextBox.BackColor = f2 ? normalBackColor : Color.LightSalmon;
            advTransmitFreqTextBox.BackColor = f3 ? normalBackColor : Color.LightSalmon;

            if (advancedMode)
            {
                if (advModeComboBox.SelectedIndex == 0) { possibleFreqLabel1.Text = possibleFreqLabel2.Text = "136 MHz - 174 MHz, 300 MHz - 550 MHz"; }
                if (advModeComboBox.SelectedIndex == 1) { possibleFreqLabel1.Text = possibleFreqLabel2.Text = "108 MHz - 136 MHz"; }
                okButton.Enabled = f2 & f3;
            }
            else
            {
                if (modeComboBox.SelectedIndex == 0) { possibleFreqLabel1.Text = possibleFreqLabel2.Text = "136 MHz - 174 MHz, 300 MHz - 550 MHz"; }
                if (modeComboBox.SelectedIndex == 1) { possibleFreqLabel1.Text = possibleFreqLabel2.Text = "108 MHz - 136 MHz"; }
                okButton.Enabled = f1;
            }
        }

        private bool CheckFreqRange(string freqStr, int mode)
        {
            if (freqStr == null) return false;
            float freq;
            if (float.TryParse(freqStr, out freq) == false) return false;
            if (mode == 0)
            {
                if (freq < 136) return false;
                if (freq > 550) return false;
                if ((freq > 174) && (freq < 300)) return false;
            }
            if (mode == 1)
            {
                if (freq < 108) return false;
                if (freq > 136) return false;
            }
            return true;
        }

        private void advReceiveFreqTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void advTransmitFreqTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void powerComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            advPowerComboBox.SelectedIndex = (int)powerComboBox.SelectedIndex;
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void freqTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Allow control keys like backspace
            if (char.IsControl(e.KeyChar)) return;

            // Allow numeric digits
            if (char.IsDigit(e.KeyChar)) return;

            // Allow a single dot, ensuring only one is present
            if (e.KeyChar == '.' && !freqTextBox.Text.Contains(".")) return;

            // Disallow all other characters
            e.Handled = true;
        }

        private void advReceiveFreqTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Allow control keys like backspace
            if (char.IsControl(e.KeyChar)) return;

            // Allow numeric digits
            if (char.IsDigit(e.KeyChar)) return;

            // Allow a single dot, ensuring only one is present
            if (e.KeyChar == '.' && !advReceiveFreqTextBox.Text.Contains(".")) return;

            // Disallow all other characters
            e.Handled = true;
        }

        private void advTransmitFreqTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Allow control keys like backspace
            if (char.IsControl(e.KeyChar)) return;

            // Allow numeric digits
            if (char.IsDigit(e.KeyChar)) return;

            // Allow a single dot, ensuring only one is present
            if (e.KeyChar == '.' && !advTransmitFreqTextBox.Text.Contains(".")) return;

            // Disallow all other characters
            e.Handled = true;
        }

        private void clearButton_Click(object sender, EventArgs e)
        {
            nameTextBox.Text = "";
            freqTextBox.Text = "0";
            advReceiveFreqTextBox.Text = "0";
            advTransmitFreqTextBox.Text = "0";
            muteCheckBox.Checked = disableTransmitCheckBox.Checked = false;
            advDisableTransmitCheckBox.Checked = advMuteCheckBox.Checked = false;
            advScanCheckBox.Checked = advTalkAroundCheckBox.Checked = deemphasisCheckBox.Enabled = false;
            transmitCtcssComboBox.SelectedIndex = receiveCtcssComboBox.SelectedIndex = 0;
            modeComboBox.SelectedIndex = advModeComboBox.SelectedIndex = 0;
            advBandwidthComboBox.SelectedIndex = 0;
            advPowerComboBox.SelectedIndex = 0;
            advModeComboBox.SelectedIndex = 0;
            okButton_Click(this, null);
        }

        private void modeComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void advModeComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }
    }
}
