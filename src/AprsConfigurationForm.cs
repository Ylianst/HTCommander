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

namespace HTCommander
{
    public partial class AprsConfigurationForm : Form
    {
        private MainForm parent;

        private class DropDownOptionClass
        {
            public string text;
            public int chid;


            public DropDownOptionClass(string text, int chid)
            {
                this.text = text;
                this.chid = chid;
            }

            public override string ToString()
            {
                return text;
            }
        }

        public AprsConfigurationForm(MainForm parent)
        {
            this.parent = parent;
            InitializeComponent();
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://" + linkLabel1.Text);
        }

        private void AprsConfigurationForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            parent.aprsConfigurationForm = null;
        }

        private void AprsConfigurationForm_Load(object sender, EventArgs e)
        {
            foreach (RadioChannelInfo channel in this.parent.radio.Channels)
            {
                string option = (channel.channel_id + 1).ToString();
                if (channel.name_str.Length > 0) { option += " - " + channel.name_str; }
                channelsComboBox.Items.Add(new DropDownOptionClass(option, channel.channel_id));
            }
            channelsComboBox.SelectedIndex = channelsComboBox.Items.Count - 1;
            Utils.SetPlaceholderText(freqTextBox, "144.39");
            UpdateInfo();
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            float freq;
            if (float.TryParse(freqTextBox.Text, out freq))
            {
                if ((freq >= 144) && (freq <= 146)) {
                    // Dulicate the existing channel
                    int channelId = ((DropDownOptionClass)channelsComboBox.SelectedItem).chid;
                    RadioChannelInfo channel = new RadioChannelInfo(parent.radio.Channels[channelId]);
                    channel.bandwidth = Radio.RadioBandwidthType.WIDE;
                    channel.mute = true;
                    channel.name_str = "APRS";
                    channel.rx_freq = 144390000;
                    channel.tx_freq = 144390000;
                    channel.pre_de_emph_bypass = true;
                    channel.rx_mod = Radio.RadioModulationType.FM;
                    channel.scan = false;
                    channel.talk_around = false;
                    channel.tx_at_max_power = true;
                    channel.tx_at_med_power = false;
                    channel.tx_sub_audio = 0;
                    channel.rx_sub_audio = 0;
                    channel.tx_disable = false;
                    parent.radio.SetChannel(channel);
                    Close();
                }
            }
        }

        private void freqTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void UpdateInfo()
        {
            bool ok = true;
            float freq;
            if (float.TryParse(freqTextBox.Text, out freq))
            {
                if ((freq < 144) || (freq > 146)) {
                    freqTextBox.BackColor = Color.Salmon;
                    ok = false;
                }
            }
            else
            {
                freqTextBox.BackColor = Color.Salmon;
                ok = false;
            }
            freqTextBox.BackColor = channelsComboBox.BackColor;
            okButton.Enabled = ok;
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
    }
}
