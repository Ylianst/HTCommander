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
    public partial class RadioBssSettingsForm : Form
    {
        private MainForm parent;
        private Radio radio;

        public RadioBssSettingsForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
        }

        public void UpdateInfo()
        {
            if (radio.BssSettings == null) return;
            addItem("Allow Position Check", radio.BssSettings.AllowPositionCheck.ToString());
            addItem("APRS Callsign", radio.BssSettings.AprsCallsign + "-" + radio.BssSettings.AprsSsid.ToString());
            addItem("APRS Symbol", radio.BssSettings.AprsSymbol);
            addItem("Beacon Message", radio.BssSettings.BeaconMessage);
            addItem("BSS User Id Lower", radio.BssSettings.BssUserIdLower.ToString());
            addItem("Location Share Interval", radio.BssSettings.LocationShareInterval.ToString() + " second(s)");
            addItem("Max Fwd Times", radio.BssSettings.MaxFwdTimes.ToString());
            addItem("Packet Format", radio.BssSettings.PacketFormat.ToString());
            addItem("PTT Release ID Info", radio.BssSettings.PttReleaseIdInfo.ToString());
            addItem("PTT Release Send BSS User Id", radio.BssSettings.PttReleaseSendBssUserId.ToString());
            addItem("PTT Release Send Id Info", radio.BssSettings.PttReleaseSendIdInfo.ToString());
            addItem("PTT Release Send Location", radio.BssSettings.PttReleaseSendLocation.ToString());
            addItem("Send Pwr Voltage", radio.BssSettings.SendPwrVoltage.ToString());
            addItem("Should Share Location", radio.BssSettings.ShouldShareLocation.ToString());
            addItem("Time To Live", radio.BssSettings.TimeToLive.ToString());
        }

        private void RadioInfoForm_Load(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void addItem(string name, string value)
        {
            foreach (ListViewItem l in mainListView.Items)
            {
                if (l.SubItems[0].Text == name) { l.SubItems[1].Text = value; return; }
            }
            mainListView.Items.Add(new ListViewItem(new string[2] { name, value }));
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void RadioSettingsForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            parent.radioBssSettingsForm = null;
        }
    }
}
