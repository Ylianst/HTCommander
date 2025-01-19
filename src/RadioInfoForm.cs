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
    public partial class RadioInfoForm : Form
    {
        private Radio radio;

        public RadioInfoForm(Radio radio)
        {
            InitializeComponent();
            this.radio = radio;
        }

        private void RadioInfoForm_Load(object sender, EventArgs e)
        {
            addItem("Device Name", radio.SelectedDevice);
            addItem("Product ID", radio.Info.product_id.ToString());
            addItem("Vendor ID", radio.Info.vendor_id.ToString());
            addItem("DMR Support", radio.Info.support_dmr ? "Present" : "Not-Present");
            addItem("GMRS Support", radio.Info.gmrs ? "Present" : "Not-Present");
            addItem("Hardware Speaker", radio.Info.have_hm_speaker ? "Present" : "Not-Present");
            addItem("Hardware Version", radio.Info.hw_ver.ToString());
            addItem("Software Version", radio.Info.soft_ver.ToString());
            addItem("Region Count", radio.Info.region_count.ToString());
            addItem("Medium Power", radio.Info.support_medium_power ? "Supported" : "Not-Supported");
            addItem("Channel Count", radio.Info.channel_count.ToString());
            addItem("NOAA", radio.Info.support_noaa ? "Supported" : "Not-Supported");
            addItem("Radio", radio.Info.support_radio ? "Supported" : "Not-Supported");
            addItem("VFO", radio.Info.support_vfo ? "Supported" : "Not-Supported");
            addItem("Freq Range Count", radio.Info.freq_range_count.ToString());
        }

        private void addItem(string name, string value)
        {
            mainListView.Items.Add(new ListViewItem(new string[2] { name, value }));
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.OK;
        }
    }
}
