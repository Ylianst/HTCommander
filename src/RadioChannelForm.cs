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
using System.Drawing;
using System.Windows.Forms;
using static HTCommander.Radio;

namespace HTCommander
{
    public partial class RadioChannelForm : Form
    {
        public RadioChannelInfo channel;
        private Color normalBackColor;
        private string dialogTitle;
        private MainForm parent;
        private Radio radio;
        private int channelId = -1;
        private bool advancedMode = false;
        private bool xreadonly = false;
        public bool ReadOnly { get { return xreadonly; } set { xreadonly = value; UpdateInfo(); } }
        public int ChannelId { get { return channelId; } }

        public RadioChannelForm(MainForm parent, Radio radio, int channelId)
        {
            InitializeComponent();
            dialogTitle = this.Text;
            this.parent = parent;
            this.radio = radio;
            this.channelId = channelId;
            advGroupBox.Location = basicGroupBox.Location;
            advGroupBox.Visible = false;
            basicGroupBox.Visible = true;
            this.Height = basicGroupBox.Height + 148;
            normalBackColor = freqTextBox.BackColor;
        }

        private void RadioInfoForm_Load(object sender, EventArgs e)
        {
            UpdateChannel();
        }

        public void UpdateChannel()
        {
            RadioChannelInfo c = channel;
            if (radio != null) { c = radio.Channels[channelId]; }
            if (channelId >= 0)
            {
                this.Text = dialogTitle + " " + (channelId + 1).ToString();
            }
            else if (!string.IsNullOrEmpty(c.name_str))
            {
                this.Text = dialogTitle + " " + c.name_str;
            }
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
            if (c.tx_sub_audio == 0) {
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
            if (c.rx_sub_audio == 0) {
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
            // Create a copy of the channel and set everything
            RadioChannelInfo c = new RadioChannelInfo(radio.Channels[channelId]);
            c.name_str = advNameTextBox.Text;

            if (advancedMode)
            {
                double freq;
                if (double.TryParse(advReceiveFreqTextBox.Text, out freq) == false) return;
                c.rx_freq = (int)(freq * 1000000);
                if (double.TryParse(advTransmitFreqTextBox.Text, out freq) == false) return;
                c.tx_freq = (int)(freq * 1000000);

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
                c.rx_freq = c.tx_freq = (int)(freq * 1000000);

                if (powerComboBox.SelectedIndex == 0) { c.tx_at_max_power = true; c.tx_at_med_power = false; }
                if (powerComboBox.SelectedIndex == 1) { c.tx_at_max_power = false; c.tx_at_med_power = true; }
                if (powerComboBox.SelectedIndex == 2) { c.tx_at_max_power = false; c.tx_at_med_power = false; }

                c.tx_disable = disableTransmitCheckBox.Checked;
                c.mute = muteCheckBox.Checked;

                if (modeComboBox.SelectedIndex == 0) { c.tx_mod = c.rx_mod = RadioModulationType.FM; }
                if (modeComboBox.SelectedIndex == 1) { c.tx_mod = c.rx_mod = RadioModulationType.AM; }
            }

            if (!radio.Channels[channelId].Equals(c)) { 
                radio.SetChannel(c);
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
                return (int)(f * 100);
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
            if (parent != null) { parent.radioChannelForm = null; }
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
            this.Height = advGroupBox.Height + 148;
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
