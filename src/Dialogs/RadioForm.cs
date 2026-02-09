/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using System.Collections.Generic;

namespace HTCommander.Dialogs
{
    public partial class RadioForm : Form
    {
        private DataBrokerClient broker;
        private List<ConnectedRadioInfo> connectedRadios = new List<ConnectedRadioInfo>();

        public RadioForm()
        {
            InitializeComponent();

            // Set up DataBrokerClient for subscribing to broker events
            broker = new DataBrokerClient();

            // Subscribe to ConnectedRadios updates
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Subscribe to FriendlyName updates for all device IDs
            broker.Subscribe(DataBroker.AllDevices, "FriendlyName", OnFriendlyNameChanged);

            // Load initial connected radios list
            LoadConnectedRadios();
        }

        /// <summary>
        /// Gets or sets the device ID that this form's RadioPanelControl monitors.
        /// </summary>
        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public int DeviceId
        {
            get { return radioPanelControl.DeviceId; }
            set
            {
                radioPanelControl.DeviceId = value;
                UpdateFormTitle();
            }
        }

        private void LoadConnectedRadios()
        {
            var radioList = DataBroker.GetValue(1, "ConnectedRadios") as System.Collections.IList;
            UpdateConnectedRadiosList(radioList);
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => OnConnectedRadiosChanged(deviceId, name, data)));
                return;
            }

            UpdateConnectedRadiosList(data);

            // Check if the current radioPanelControl's DeviceId is still a connected radio
            int currentDeviceId = radioPanelControl.DeviceId;
            bool isCurrentRadioConnected = connectedRadios.Any(r => r.DeviceId == currentDeviceId);

            if (!isCurrentRadioConnected && connectedRadios.Count > 0)
            {
                // Current radio is no longer connected, switch to the first available radio
                radioPanelControl.DeviceId = connectedRadios[0].DeviceId;
            }
            else if (connectedRadios.Count == 0)
            {
                // No radios connected, reset to disconnected state
                radioPanelControl.DeviceId = -1;
            }

            // Update the form title in case the friendly name changed
            UpdateFormTitle();
        }

        private void OnFriendlyNameChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => OnFriendlyNameChanged(deviceId, name, data)));
                return;
            }

            // Only update if this is for the radio we're currently displaying
            if (deviceId == radioPanelControl.DeviceId)
            {
                UpdateFormTitle();
            }
        }

        private void UpdateFormTitle()
        {
            int currentDeviceId = radioPanelControl.DeviceId;

            if (currentDeviceId <= 0)
            {
                this.Text = "Radio";
                return;
            }

            // Try to get the friendly name from the connected radios list first
            var radio = connectedRadios.FirstOrDefault(r => r.DeviceId == currentDeviceId);
            if (radio != null && !string.IsNullOrEmpty(radio.FriendlyName))
            {
                this.Text = "Radio - " + radio.FriendlyName;
                return;
            }

            // Try to get the friendly name from the broker
            string friendlyName = broker.GetValue<string>(currentDeviceId, "FriendlyName", null);
            if (!string.IsNullOrEmpty(friendlyName))
            {
                this.Text = "Radio - " + friendlyName;
            }
            else
            {
                this.Text = "Radio";
            }
        }

        private void UpdateConnectedRadiosList(object data)
        {
            connectedRadios.Clear();

            if (data == null) return;

            // The data is a list of anonymous objects with DeviceId, MacAddress, FriendlyName, State properties
            if (data is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var itemType = item.GetType();
                    int? deviceIdProp = (int?)itemType.GetProperty("DeviceId")?.GetValue(item);
                    string friendlyName = (string)itemType.GetProperty("FriendlyName")?.GetValue(item);

                    if (deviceIdProp.HasValue)
                    {
                        connectedRadios.Add(new ConnectedRadioInfo
                        {
                            DeviceId = deviceIdProp.Value,
                            FriendlyName = friendlyName ?? ""
                        });
                    }
                }
            }
        }

        private void allChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Toggle the ShowAllChannels state in RadioPanelControl
            radioPanelControl.ShowAllChannels = !radioPanelControl.ShowAllChannels;
        }

        private void viewToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            // Set the "All Channels" checkbox state based on RadioPanelControl's ShowAllChannels
            allChannelsToolStripMenuItem.Checked = radioPanelControl.ShowAllChannels;

            // Remove any previously added dynamic radio menu items and separator
            RemoveDynamicRadioMenuItems();

            // If there are 2 or more radios connected, add a separator and menu items for each radio
            if (connectedRadios.Count >= 2)
            {
                // Add separator
                ToolStripSeparator separator = new ToolStripSeparator();
                separator.Tag = "DynamicRadioItem";
                viewToolStripMenuItem.DropDownItems.Add(separator);

                // Add menu item for each connected radio
                foreach (var radio in connectedRadios)
                {
                    ToolStripMenuItem radioMenuItem = new ToolStripMenuItem();
                    radioMenuItem.Text = string.IsNullOrEmpty(radio.FriendlyName) ? $"Radio {radio.DeviceId}" : radio.FriendlyName;
                    radioMenuItem.Tag = "DynamicRadioItem";
                    radioMenuItem.Checked = (radio.DeviceId == radioPanelControl.DeviceId);
                    int radioDeviceId = radio.DeviceId; // Capture for lambda
                    radioMenuItem.Click += (s, args) =>
                    {
                        // Switch the radioPanelControl to display this radio and update title
                        radioPanelControl.DeviceId = radioDeviceId;
                        UpdateFormTitle();
                    };
                    viewToolStripMenuItem.DropDownItems.Add(radioMenuItem);
                }
            }
        }

        private void RemoveDynamicRadioMenuItems()
        {
            // Remove all items tagged as dynamic radio items
            for (int i = viewToolStripMenuItem.DropDownItems.Count - 1; i >= 0; i--)
            {
                ToolStripItem item = viewToolStripMenuItem.DropDownItems[i];
                if (item.Tag != null && item.Tag.ToString() == "DynamicRadioItem")
                {
                    viewToolStripMenuItem.DropDownItems.RemoveAt(i);
                }
            }
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void settingsToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            int deviceId = radioPanelControl.DeviceId;
            bool hasRadio = (deviceId > 0) && connectedRadios.Any(r => r.DeviceId == deviceId);

            // Enable/disable menu items based on radio connection
            dualWatchToolStripMenuItem.Enabled = hasRadio;
            scanToolStripMenuItem.Enabled = hasRadio;
            regionToolStripMenuItem.Enabled = hasRadio;
            gPSEnabledToolStripMenuItem.Enabled = hasRadio;
            exportChannelsToolStripMenuItem.Enabled = hasRadio;

            if (!hasRadio)
            {
                // Clear checked states when no radio
                dualWatchToolStripMenuItem.Checked = false;
                scanToolStripMenuItem.Checked = false;
                gPSEnabledToolStripMenuItem.Checked = false;
                regionToolStripMenuItem.DropDownItems.Clear();
                return;
            }

            // Get the current radio's settings and status from the broker
            RadioSettings settings = DataBroker.GetValue<RadioSettings>(deviceId, "Settings", null);
            RadioHtStatus htStatus = DataBroker.GetValue<RadioHtStatus>(deviceId, "HtStatus", null);
            RadioDevInfo devInfo = DataBroker.GetValue<RadioDevInfo>(deviceId, "Info", null);

            // Set Dual-Watch state (double_channel: 0 = off, 1 = on)
            if (settings != null)
            {
                dualWatchToolStripMenuItem.Checked = (settings.double_channel == 1);
                scanToolStripMenuItem.Checked = settings.scan;
            }
            else
            {
                dualWatchToolStripMenuItem.Checked = false;
                scanToolStripMenuItem.Checked = false;
            }

            // Set GPS Enabled state from the broker
            bool gpsEnabled = DataBroker.GetValue<bool>(deviceId, "GpsEnabled", false);
            gPSEnabledToolStripMenuItem.Checked = gpsEnabled;

            // Build Regions sub-menu
            regionToolStripMenuItem.DropDownItems.Clear();
            if (devInfo != null && htStatus != null && devInfo.region_count > 0)
            {
                for (int i = 0; i < devInfo.region_count; i++)
                {
                    ToolStripMenuItem regionItem = new ToolStripMenuItem();
                    regionItem.Text = $"Region {i + 1}";
                    regionItem.Tag = i;
                    regionItem.Checked = (i == htStatus.curr_region);
                    int regionIndex = i; // Capture for closure
                    int currentDeviceId = deviceId; // Capture for closure
                    regionItem.Click += (s, args) =>
                    {
                        // Send Region event via broker
                        DataBroker.Dispatch(currentDeviceId, "Region", regionIndex, store: false);
                    };
                    regionToolStripMenuItem.DropDownItems.Add(regionItem);
                }
            }
        }

        private void dualWatchToolStripMenuItem_Click(object sender, EventArgs e)
        {
            int deviceId = radioPanelControl.DeviceId;
            RadioSettings settings = DataBroker.GetValue<RadioSettings>(deviceId, "Settings", null);
            if (settings == null) return;

            // Toggle dual-watch (double_channel: 0 = off, 1 = on) and send via broker
            bool newDualWatch = (settings.double_channel != 1);
            DataBroker.Dispatch(deviceId, "DualWatch", newDualWatch, store: false);
        }

        private void scanToolStripMenuItem_Click(object sender, EventArgs e)
        {
            int deviceId = radioPanelControl.DeviceId;
            RadioSettings settings = DataBroker.GetValue<RadioSettings>(deviceId, "Settings", null);
            if (settings == null) return;

            // Toggle scan and send via broker
            bool newScan = !settings.scan;
            DataBroker.Dispatch(deviceId, "Scan", newScan, store: false);
        }

        private void gPSEnabledToolStripMenuItem_Click(object sender, EventArgs e)
        {
            int deviceId = radioPanelControl.DeviceId;
            if (deviceId <= 0) return;

            // Toggle GPS - check current state and toggle, send via broker
            bool currentlyEnabled = gPSEnabledToolStripMenuItem.Checked;
            DataBroker.Dispatch(deviceId, "SetGPS", !currentlyEnabled, store: false);
        }

        private void importChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (importChannelsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                RadioChannelInfo[] channels = ImportUtils.ParseChannelsFromFile(importChannelsFileDialog.FileName);
                if (channels == null || channels.Length == 0) return;

                ImportChannelsForm f = new ImportChannelsForm(null, channels);
                f.Text = f.Text + " - " + new FileInfo(importChannelsFileDialog.FileName).Name;
                f.Show(this);
            }
        }

        private void exportChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Get the displayed channels from the radio panel control
            RadioChannelInfo[] channels = radioPanelControl.GetDisplayedChannels();
            if (channels == null || channels.Length == 0)
            {
                MessageBox.Show(this, "No channels available to export.", "Export Channels", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (exportChannelsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                string content;
                if (exportChannelsFileDialog.FilterIndex == 1)
                {
                    content = ImportUtils.ExportToNativeFormat(channels);
                }
                else
                {
                    content = ImportUtils.ExportToChirpFormat(channels);
                }
                File.WriteAllText(exportChannelsFileDialog.FileName, content);
            }
        }

        /// <summary>
        /// Simple class to hold connected radio information.
        /// </summary>
        private class ConnectedRadioInfo
        {
            public int DeviceId { get; set; }
            public string FriendlyName { get; set; }
        }
    }
}
