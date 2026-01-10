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
using System.Linq;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AprsWeatherForm : Form
    {
        public string PhoneNumber { get { return locationTextBox.Text; } }

        public AprsWeatherForm()
        {
            InitializeComponent();
        }

        public string GetAprsMessage()
        {
            string time = timeComboBox.Items[timeComboBox.SelectedIndex].ToString().ToLower();
            string report = reportComboBox.Items[reportComboBox.SelectedIndex].ToString().Split(',')[0].ToLower();
            return locationTextBox.Text + " " + time + " " + report;
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://" + linkLabel1.Text);
        }

        private void UpdateInfo()
        {
            okButton.Enabled = (locationTextBox.Text.Length > 0);
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            //MainForm.g_MainForm.registry.WriteString("WxBotLocation", locationTextBox.Text);
            //MainForm.g_MainForm.registry.WriteInt("WxBotTime", timeComboBox.SelectedIndex);
            //MainForm.g_MainForm.registry.WriteInt("WxBotReport", reportComboBox.SelectedIndex);
            DialogResult = DialogResult.OK;
        }

        private void locationTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void locationTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Check if the pressed character is in the restricted list
            char[] restrictedChars = { '~', '|', '{', '}', ' ' };
            if (restrictedChars.Contains(e.KeyChar)) { e.Handled = true; return; }
        }

        private void AprsWeatherForm_Load(object sender, EventArgs e)
        {
            //locationTextBox.Text = MainForm.g_MainForm.registry.ReadString("WxBotLocation", "");
            //timeComboBox.SelectedIndex = (int)MainForm.g_MainForm.registry.ReadInt("WxBotTime", 0);
            //reportComboBox.SelectedIndex = (int)MainForm.g_MainForm.registry.ReadInt("WxBotReport", 0);
        }
    }
}
