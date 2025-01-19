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
using System.Windows.Forms;

namespace HTCommander
{
    public partial class SettingsForm : Form
    {
        public bool AllowTransmit { get { return allowTransmitCheckBox.Checked; } set { allowTransmitCheckBox.Checked = value; } }
        public string CallSign { get { return callsignTextBox.Text; } set { callsignTextBox.Text = value; } }
        public int StationId { get { return stationIdComboBox.SelectedIndex; } set { stationIdComboBox.SelectedIndex = value; } }

        public SettingsForm()
        {
            InitializeComponent();
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start(linkLabel1.Text);
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.OK;
        }

        private void UpdateInfo()
        {
            allowTransmitCheckBox.Enabled = (callsignTextBox.Text.Length >= 3);
            if (allowTransmitCheckBox.Enabled == false) { allowTransmitCheckBox.Checked = false; }
        }

        private void callsignTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }
    }
}
