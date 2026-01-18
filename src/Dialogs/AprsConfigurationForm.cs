/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Diagnostics;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AprsConfigurationForm : Form
    {
        private RadioChannelInfo[] _channels;

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

        /// <summary>
        /// Gets the channel ID selected by the user.
        /// </summary>
        public int SelectedChannelId
        {
            get
            {
                if (channelsComboBox.SelectedItem is DropDownOptionClass option)
                {
                    return option.chid;
                }
                return -1;
            }
        }

        /// <summary>
        /// Gets the frequency entered by the user (in MHz).
        /// </summary>
        public float Frequency
        {
            get
            {
                if (float.TryParse(freqTextBox.Text, out float freq))
                {
                    return freq;
                }
                return 0;
            }
        }

        /// <summary>
        /// Sets the channels to populate the dropdown.
        /// </summary>
        public RadioChannelInfo[] Channels
        {
            set { _channels = value; }
        }

        public AprsConfigurationForm()
        {
            InitializeComponent();
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            Process.Start(new ProcessStartInfo("https://" + linkLabel1.Text) { UseShellExecute = true });
        }

        private void AprsConfigurationForm_Load(object sender, EventArgs e)
        {
            if (_channels != null)
            {
                foreach (RadioChannelInfo channel in _channels)
                {
                    if (channel == null) continue;
                    string option = (channel.channel_id + 1).ToString();
                    if (!string.IsNullOrEmpty(channel.name_str)) { option += " - " + channel.name_str; }
                    channelsComboBox.Items.Add(new DropDownOptionClass(option, channel.channel_id));
                }
                if (channelsComboBox.Items.Count > 0)
                {
                    channelsComboBox.SelectedIndex = channelsComboBox.Items.Count - 1;
                }
            }
            UpdateInfo();
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.OK;
            Close();
        }

        private void freqTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void UpdateInfo()
        {
            bool ok = true;
            if (float.TryParse(freqTextBox.Text, out float freq))
            {
                if ((freq < 144) || (freq > 148))
                {
                    freqTextBox.BackColor = Color.Salmon;
                    ok = false;
                }
                else
                {
                    freqTextBox.BackColor = SystemColors.Window;
                }
            }
            else
            {
                freqTextBox.BackColor = Color.Salmon;
                ok = false;
            }

            // Also check that a channel is selected
            if (channelsComboBox.SelectedItem == null)
            {
                ok = false;
            }

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
