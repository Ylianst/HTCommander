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
    public partial class RadioHtStatusForm : Form
    {
        private MainForm parent;
        private Radio radio;

        public RadioHtStatusForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
        }

        public void UpdateInfo()
        {
            if (radio.HtStatus == null) return;
            addItem("Power on", radio.HtStatus.is_power_on.ToString());
            addItem("In TX", radio.HtStatus.is_in_tx.ToString());
            addItem("is_sq", radio.HtStatus.is_sq.ToString());
            addItem("In RX", radio.HtStatus.is_in_rx.ToString());
            addItem("Double Channel", radio.HtStatus.double_channel.ToString());
            addItem("Scanning", radio.HtStatus.is_scan.ToString());
            addItem("Radio", radio.HtStatus.is_radio.ToString());
            addItem("Current Channel ID", (radio.HtStatus.curr_ch_id + 1).ToString());
            addItem("GPS Locker", radio.HtStatus.is_gps_locked.ToString());
            addItem("HFP Connected", radio.HtStatus.is_hfp_connected.ToString());
            addItem("AOC Connected", radio.HtStatus.is_aoc_connected.ToString());
            addItem("RSSI", radio.HtStatus.rssi.ToString());
            addItem("Current Region", radio.HtStatus.curr_region.ToString());
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

        private void RadioHtStatusForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            parent.radioHtStatusForm = null;
        }
    }
}
