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
using System.Reflection;
using System.Collections;
using System.Windows.Forms;
using System.Collections.Generic;
using static HTCommander.Radio;
using HTCommander.Dialogs;

namespace HTCommander
{
    public partial class RadioConnectionForm : Form
    {
        private CompatibleDevice[] devices;
        private DataBrokerClient broker;

        // Track connected radios state: MAC address -> connection state
        private Dictionary<string, string> connectedRadioStates = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        // Track deviceId -> MAC address mapping for state updates
        private Dictionary<int, string> deviceIdToMac = new Dictionary<int, string>();

        public RadioConnectionForm(CompatibleDevice[] devices)
        {
            this.devices = devices;
            InitializeComponent();
            EnableDoubleBuffering(radiosListView);

            // Create the broker for subscribing to events
            broker = new DataBrokerClient();

            // Subscribe to connected radios updates
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Subscribe to State changes for all devices
            broker.Subscribe(DataBroker.AllDevices, "State", OnRadioStateChanged);

            // Wire up button click handlers
            connectButton.Click += connectButton_Click;
            disconnectButton.Click += disconnectButton_Click;
            renameButton.Click += renameButton_Click;

            this.FormClosed += (s, e) => broker?.Dispose();
        }

        private void EnableDoubleBuffering(ListView listView)
        {
            listView.GetType()
                .GetProperty("DoubleBuffered", BindingFlags.Instance | BindingFlags.NonPublic)
                ?.SetValue(listView, true, null);
        }

        private void LoadConnectedRadiosState()
        {
            connectedRadioStates.Clear();
            deviceIdToMac.Clear();
            var connectedRadios = DataBroker.GetValue(1, "ConnectedRadios") as IList;
            if (connectedRadios != null)
            {
                foreach (var radio in connectedRadios)
                {
                    var radioType = radio.GetType();
                    int deviceId = (int)radioType.GetProperty("DeviceId").GetValue(radio);
                    string macAddress = (string)radioType.GetProperty("MacAddress").GetValue(radio);
                    string state = broker.GetValue(deviceId, "State", (string)radioType.GetProperty("State").GetValue(radio));
                    connectedRadioStates[macAddress] = state;
                    deviceIdToMac[deviceId] = macAddress;
                }
            }
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            LoadConnectedRadiosState();
            UpdateListView();
            UpdateButtonStates();
        }

        private void OnRadioStateChanged(int deviceId, string name, object data)
        {
            // When a radio's state changes, update our tracking
            if (data is string state && deviceIdToMac.TryGetValue(deviceId, out string macAddress))
            {
                connectedRadioStates[macAddress] = state;
                UpdateListView();
                UpdateButtonStates();
            }
        }

        private void RadioSelectorForm_Load(object sender, EventArgs e)
        {
            // Load connected radios state right before populating the list
            LoadConnectedRadiosState();

            PopulateListView();

            // Set up column widths
            ResizeListViewColumns();
            radiosListView.Resize += (s, ev) => ResizeListViewColumns();

            // Initial button state update
            UpdateButtonStates();
        }

        private void ResizeListViewColumns()
        {
            // Second column fixed at 170px, first column fills remaining space
            int fixedColumnWidth = 170;
            radiosListView.Columns[1].Width = fixedColumnWidth;
            radiosListView.Columns[0].Width = radiosListView.ClientSize.Width - fixedColumnWidth;
        }

        private void PopulateListView()
        {
            // Store currently selected MAC addresses before clearing
            HashSet<string> selectedMacs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (ListViewItem selectedItem in radiosListView.SelectedItems)
            {
                string mac = selectedItem.Tag as string;
                if (mac != null)
                {
                    selectedMacs.Add(mac);
                }
            }

            radiosListView.Items.Clear();
            foreach (CompatibleDevice radio in devices)
            {
                string displayName = string.IsNullOrEmpty(radio.name)
                    ? radio.mac
                    : $"{radio.name} ({radio.mac})";
                string status = GetRadioStatus(radio.mac);

                ListViewItem item = new ListViewItem(new string[] { displayName, status });
                item.Tag = radio.mac; // Store MAC address in Tag for later retrieval
                radiosListView.Items.Add(item);

                // Re-select items that were previously selected
                if (selectedMacs.Contains(radio.mac))
                {
                    item.Selected = true;
                }
            }

            // Update button states to reflect current selection
            UpdateButtonStates();
        }

        private void UpdateListView()
        {
            foreach (ListViewItem item in radiosListView.Items)
            {
                string mac = item.Tag as string;
                if (mac != null)
                {
                    item.SubItems[1].Text = GetRadioStatus(mac);
                }
            }
        }

        private string GetRadioStatus(string macAddress)
        {
            if (connectedRadioStates.TryGetValue(macAddress, out string state))
            {
                return state;
            }
            return "Disconnected";
        }

        private void radiosListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateButtonStates();
        }

        private void UpdateButtonStates()
        {
            bool hasDisconnectedSelected = false;
            bool hasConnectedSelected = false;

            foreach (ListViewItem item in radiosListView.SelectedItems)
            {
                string mac = item.Tag as string;
                if (mac != null)
                {
                    string status = GetRadioStatus(mac);
                    if (status == "Disconnected" || status == "UnableToConnect" || status == "AccessDenied")
                    {
                        hasDisconnectedSelected = true;
                    }
                    else if (status == "Connected" || status == "Connecting")
                    {
                        hasConnectedSelected = true;
                    }
                }
            }

            connectButton.Enabled = hasDisconnectedSelected;
            disconnectButton.Enabled = hasConnectedSelected;

            // Rename button enabled only when exactly one radio is selected
            renameButton.Enabled = (radiosListView.SelectedItems.Count == 1);
        }

        private void connectButton_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem item in radiosListView.SelectedItems)
            {
                string mac = item.Tag as string;
                if (mac != null)
                {
                    string status = GetRadioStatus(mac);
                    if (status == "Disconnected" || status == "UnableToConnect" || status == "AccessDenied")
                    {
                        // Find the friendly name from the devices array
                        string friendlyName = "";
                        foreach (var device in devices)
                        {
                            if (device.mac.Equals(mac, StringComparison.OrdinalIgnoreCase))
                            {
                                friendlyName = device.name;
                                break;
                            }
                        }

                        // Request connection through DataBroker
                        broker.Dispatch(1, "RadioConnectRequest", new { MacAddress = mac, FriendlyName = friendlyName }, store: false);
                    }
                }
            }
        }

        private void disconnectButton_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem item in radiosListView.SelectedItems)
            {
                string mac = item.Tag as string;
                if (mac != null)
                {
                    string status = GetRadioStatus(mac);
                    if (status == "Connected" || status == "Connecting")
                    {
                        // Request disconnection through DataBroker
                        broker.Dispatch(1, "RadioDisconnectRequest", new { MacAddress = mac }, store: false);
                    }
                }
            }
        }

        private void radiosListView_MouseDoubleClick(object sender, MouseEventArgs e)
        {
            // Double-click toggles connection state
            if (radiosListView.SelectedItems.Count == 1)
            {
                ListViewItem item = radiosListView.SelectedItems[0];
                string mac = item.Tag as string;
                if (mac != null)
                {
                    string status = GetRadioStatus(mac);
                    if (status == "Disconnected" || status == "UnableToConnect" || status == "AccessDenied")
                    {
                        connectButton_Click(sender, e);
                    }
                    else if (status == "Connected" || status == "Connecting")
                    {
                        disconnectButton_Click(sender, e);
                    }
                }
            }
        }

        private void renameButton_Click(object sender, EventArgs e)
        {
            if (radiosListView.SelectedItems.Count != 1) return;

            ListViewItem item = radiosListView.SelectedItems[0];
            string mac = item.Tag as string;
            if (mac == null) return;

            string macKey = mac.ToUpperInvariant();

            // Get the stored friendly names dictionary
            var friendlyNames = DataBroker.GetValue<Dictionary<string, string>>(0, "DeviceFriendlyName", null);

            // Get the original Bluetooth name from the stored DeviceBluetoothName dictionary
            var bluetoothNames = DataBroker.GetValue<Dictionary<string, string>>(0, "DeviceBluetoothName", null);
            string defaultFriendlyName = "";
            if (bluetoothNames != null && bluetoothNames.TryGetValue(macKey, out string originalName))
            {
                defaultFriendlyName = originalName;
            }

            // Find the current custom name (if any) from the stored dictionary
            string currentCustomName = "";
            if (friendlyNames != null && friendlyNames.TryGetValue(macKey, out string storedName))
            {
                currentCustomName = storedName;
            }

            // Show the rename dialog
            using (var renameForm = new RadioRenameForm())
            {
                // Set placeholder to the default Bluetooth name
                renameForm.PlaceholderText = defaultFriendlyName;
                
                // Set current name - if there's a custom name use it, otherwise show placeholder
                renameForm.RadioName = currentCustomName;
                
                if (renameForm.ShowDialog(this) == DialogResult.OK)
                {
                    string newName = renameForm.RadioName.Trim();

                    // Get or create the friendly names dictionary
                    if (friendlyNames == null)
                    {
                        friendlyNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    }

                    // Store the mapping (use uppercase MAC as key for consistency)
                    if (string.IsNullOrEmpty(newName))
                    {
                        // If blank, remove any custom name (will default to discovered name)
                        friendlyNames.Remove(macKey);
                    }
                    else
                    {
                        friendlyNames[macKey] = newName;
                    }

                    // Save to DataBroker under device id 0
                    DataBroker.Dispatch(0, "DeviceFriendlyName", friendlyNames, store: true);

                    // Determine the final name to use
                    string finalName = string.IsNullOrEmpty(newName) 
                        ? (!string.IsNullOrEmpty(defaultFriendlyName) ? defaultFriendlyName : mac)
                        : newName;

                    // Update the device's name in memory
                    foreach (var device in devices)
                    {
                        if (device.mac.Equals(mac, StringComparison.OrdinalIgnoreCase))
                        {
                            device.name = finalName;
                            break;
                        }
                    }

                    // If this radio is currently connected, update its friendly name via the Radio handler
                    int? connectedDeviceId = GetConnectedDeviceIdByMac(mac);
                    if (connectedDeviceId.HasValue)
                    {
                        // Get the Radio instance from DataBroker and update its friendly name
                        var radio = DataBroker.GetDataHandler<Radio>("Radio_" + connectedDeviceId.Value);
                        if (radio != null)
                        {
                            radio.UpdateFriendlyName(finalName);
                        }
                    }

                    // Refresh the list view
                    PopulateListView();
                }
            }
        }

        private int? GetConnectedDeviceIdByMac(string macAddress)
        {
            foreach (var kvp in deviceIdToMac)
            {
                if (kvp.Value.Equals(macAddress, StringComparison.OrdinalIgnoreCase))
                {
                    return kvp.Key;
                }
            }
            return null;
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }
    }
}
