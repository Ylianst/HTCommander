/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class RadioInfoForm : Form
    {
        private int deviceId;
        private RadioDevInfo Info;
        private DataBrokerClient broker;

        public RadioInfoForm(int deviceId)
        {
            InitializeComponent();
            this.deviceId = deviceId;
            Info = (RadioDevInfo)DataBroker.GetValue(deviceId, "DeviceInfo");

            // Subscribe to DeviceInfo updates for this device
            broker = new DataBrokerClient();
            broker.Subscribe(deviceId, "DeviceInfo", OnDeviceInfoChanged);

            this.FormClosed += (s, e) => broker?.Dispose();
        }

        private void OnDeviceInfoChanged(int deviceId, string name, object data)
        {
            Info = data as RadioDevInfo;
            UpdateListView();
        }

        private void RadioInfoForm_Load(object sender, EventArgs e)
        {
            UpdateListView();
            mainListView.Columns[mainListView.Columns.Count - 1].Width = -2; // Auto-fill remaining width
        }

        private void UpdateListView()
        {
            mainListView.BeginUpdate();
            mainListView.Items.Clear();
            if (Info != null)
            {
                mainListView.Items.AddRange(new ListViewItem[]
                {
                    new ListViewItem(new[] { "Product ID", Info.product_id.ToString() }),
                    new ListViewItem(new[] { "Vendor ID", Info.vendor_id.ToString() }),
                    new ListViewItem(new[] { "DMR Support", Info.support_dmr ? "Present" : "Not-Present" }),
                    new ListViewItem(new[] { "GMRS Support", Info.gmrs ? "Present" : "Not-Present" }),
                    new ListViewItem(new[] { "Hardware Speaker", Info.have_hm_speaker ? "Present" : "Not-Present" }),
                    new ListViewItem(new[] { "Hardware Version", Info.hw_ver.ToString() }),
                    new ListViewItem(new[] { "Software Version", $"{(Info.soft_ver >> 8) & 0xF}.{(Info.soft_ver >> 4) & 0xF}.{Info.soft_ver & 0xF}" }),
                    new ListViewItem(new[] { "Region Count", Info.region_count.ToString() }),
                    new ListViewItem(new[] { "Medium Power", Info.support_medium_power ? "Supported" : "Not-Supported" }),
                    new ListViewItem(new[] { "Channel Count", Info.channel_count.ToString() }),
                    new ListViewItem(new[] { "NOAA", Info.support_noaa ? "Supported" : "Not-Supported" }),
                    new ListViewItem(new[] { "Radio", Info.support_radio ? "Supported" : "Not-Supported" }),
                    new ListViewItem(new[] { "VFO", Info.support_vfo ? "Supported" : "Not-Supported" }),
                    new ListViewItem(new[] { "Freq Range Count", Info.freq_range_count.ToString() })
                });
            }
            mainListView.EndUpdate();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            Close();
        }
    }
}
