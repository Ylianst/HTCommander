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

using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class MainForm : Form
    {
        private DataBrokerClient broker;
        private List<Radio> connectedRadios = new List<Radio>();
        private const int StartingDeviceId = 100;
        private SettingsForm settingsForm = null;
        private RadioConnectionForm radioSelectorForm = null;

        private string LastUpdateCheck => DataBroker.GetValue<string>(0, "LastUpdateCheck", null);
        private bool CheckForUpdates => DataBroker.GetValue<bool>(0, "CheckForUpdates", false);

        public MainForm(string[] args)
        {
            bool multiInstance = false;
            foreach (string arg in args)
            {
                if (string.Compare(arg, "-multiinstance", true) == 0) { multiInstance = true; }
            }
            if (multiInstance == false) { StartPipeServer(); }

            InitializeComponent();

            // Set UI context for broker callbacks and create main form broker client
            DataBroker.SetUIContext(this);
            broker = new DataBrokerClient();

            // Subscribe to CallSign and StationId changes for title bar updates
            broker.Subscribe(0, new[] { "CallSign", "StationId" }, OnCallSignOrStationIdChanged);

            // Subscribe to RadioConnect event from device 1 (e.g., from RadioPanelControl)
            broker.Subscribe(1, "RadioConnect", OnRadioConnectRequested);

            // Subscribe to RadioConnectRequest and RadioDisconnectRequest from RadioSelectorForm
            broker.Subscribe(1, "RadioConnectRequest", OnRadioConnectRequest);
            broker.Subscribe(1, "RadioDisconnectRequest", OnRadioDisconnectRequest);

            // Set initial title bar based on stored values
            UpdateTitleBar();

            // Publish initial empty connected radios list
            PublishConnectedRadios();

            aprsTabUserControl.Initialize(this);
            mapTabUserControl.Initialize(this);
            voiceTabUserControl.Initialize(this);
            mailTabUserControl.Initialize(this);
            terminalTabUserControl.Initialize(this);
            contactsTabUserControl.Initialize(this);
            bbsTabUserControl.Initialize(this);
            torrentTabUserControl.Initialize(this);
            packetCaptureTabUserControl.Initialize(this);
        }
        private void StartPipeServer()
        {
            Task.Run(() =>
            {
                while (true)
                {
                    using (var server = new NamedPipeServerStream(Program.PipeName))
                    using (var reader = new StreamReader(server))
                    {
                        server.WaitForConnection();
                        var message = reader.ReadLine();
                        //if (message == "show") { showToolStripMenuItem_Click(this, null); }
                    }
                }
            });
        }

        private void MainForm_Load(object sender, EventArgs e)
        {
            // Check for updates
            checkForUpdatesToolStripMenuItem.Checked = CheckForUpdates;
            if (File.Exists("NoUpdateCheck.txt"))
            {
                checkForUpdatesToolStripMenuItem.Visible = false;
                checkForUpdatesToolStripMenuItem.Checked = false;
            }
            else if (checkForUpdatesToolStripMenuItem.Checked)
            {
                if (string.IsNullOrEmpty(LastUpdateCheck) || (DateTime.Now - DateTime.Parse(LastUpdateCheck)).TotalDays > 1)
                {
                    SelfUpdateForm.CheckForUpdate(this);
                }
            }
        }

        private void checkForUpdatesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Check for updates
            DataBroker.Dispatch(0, "CheckForUpdates", checkForUpdatesToolStripMenuItem.Checked);
            if (checkForUpdatesToolStripMenuItem.Checked) { SelfUpdateForm.CheckForUpdate(this); }
        }

        private delegate void UpdateAvailableHandler(float currentVersion, float onlineVersion, string url);
        public void UpdateAvailable(float currentVersion, float onlineVersion, string url)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new UpdateAvailableHandler(UpdateAvailable), currentVersion, onlineVersion, url); return; }

            // Display update dialog
            SelfUpdateForm updateForm = new SelfUpdateForm();
            updateForm.currentVersionText = currentVersion.ToString();
            updateForm.onlineVersionText = onlineVersion.ToString();
            updateForm.updateUrl = url;
            updateForm.ShowDialog(this);
        }

        private void fileToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            // Enable Connect if there might be radios to connect to
            // (We can't know for sure without scanning, so we leave it enabled)
            connectToolStripMenuItem.Enabled = true;

            // Enable Disconnect only if we have connected radios
            disconnectToolStripMenuItem.Enabled = (connectedRadios.Count > 0);
        }

        private void aboutToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            // Enable the first 5 radio-related menu items only if we have connected radios
            bool hasRadio = (connectedRadios.Count > 0);
            radioInformationToolStripMenuItem.Enabled = hasRadio;
        }

        private void radioInformationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            new RadioInfoForm().Show(this);
        }

        private void aboutToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            broker.LogInfo("Opening About dialog");
            new AboutForm().ShowDialog(this);
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Application.Exit();
        }

        private async void connectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Check if Bluetooth is available
            if (!RadioBluetoothWin.CheckBluetooth())
            {
                MessageBox.Show(this, "Bluetooth is not available on this system.", "Bluetooth Not Available", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Find compatible devices
            Radio.CompatibleDevice[] allDevices;
            try
            {
                allDevices = await RadioBluetoothWin.FindCompatibleDevices();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Error searching for compatible radios: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (allDevices == null || allDevices.Length == 0)
            {
                MessageBox.Show(this, "No compatible radios found. Make sure your radio is powered on and paired with this computer.", "No Radios Found", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // Apply stored friendly names
            ApplyStoredFriendlyNames(allDevices);

            // Filter out already connected radios
            var connectedMacs = connectedRadios.Select(r => r.MacAddress.ToUpperInvariant()).ToHashSet();
            var availableDevices = allDevices.Where(d => !connectedMacs.Contains(d.mac.ToUpperInvariant())).ToArray();

            if (availableDevices.Length == 0)
            {
                MessageBox.Show(this, "All compatible radios are already connected.", "No Available Radios", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // If only one compatible radio and it's not connected, connect directly
            if (availableDevices.Length == 1 && allDevices.Length == 1)
            {
                ConnectToRadio(availableDevices[0].mac, availableDevices[0].name);
                return;
            }

            // Show selector dialog for all devices - user can connect/disconnect from there
            if (radioSelectorForm != null && !radioSelectorForm.IsDisposed)
            {
                radioSelectorForm.Focus();
                return;
            }

            radioSelectorForm = new RadioConnectionForm(allDevices);
            radioSelectorForm.FormClosed += (s, args) => { radioSelectorForm = null; };
            radioSelectorForm.Show(this);
        }

        private int GetNextAvailableDeviceId()
        {
            int deviceId = StartingDeviceId;
            var usedIds = connectedRadios.Select(r => r.DeviceId).ToHashSet();
            while (usedIds.Contains(deviceId)) { deviceId++; }
            return deviceId;
        }

        private void ConnectToRadio(string macAddress, string friendlyName)
        {
            // Check if already connected to this MAC address
            if (connectedRadios.Any(r => r.MacAddress.Equals(macAddress, StringComparison.OrdinalIgnoreCase)))
            {
                return;
            }

            // Get the next available device ID
            int deviceId = GetNextAvailableDeviceId();

            // Create the radio instance
            Radio radio = new Radio(deviceId, macAddress);
            radio.UpdateFriendlyName(friendlyName);

            // Add the radio as a data handler in the DataBroker
            string handlerName = "Radio_" + deviceId;
            DataBroker.AddDataHandler(handlerName, radio);

            // Track the connected radio
            connectedRadios.Add(radio);

            // Publish updated connected radios list
            PublishConnectedRadios();

            // Start the Bluetooth connection
            radio.Connect();
        }

        private async void disconnectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // If only one radio is connected, disconnect it directly
            if (connectedRadios.Count == 1)
            {
                DisconnectRadio(connectedRadios[0]);
                return;
            }

            // Otherwise, show selector dialog with all radios
            // Check if Bluetooth is available
            if (!RadioBluetoothWin.CheckBluetooth())
            {
                MessageBox.Show(this, "Bluetooth is not available on this system.", "Bluetooth Not Available", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Find compatible devices
            Radio.CompatibleDevice[] allDevices;
            try
            {
                allDevices = await RadioBluetoothWin.FindCompatibleDevices();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Error searching for compatible radios: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (allDevices == null || allDevices.Length == 0)
            {
                MessageBox.Show(this, "No compatible radios found.", "No Radios Found", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // Apply stored friendly names
            ApplyStoredFriendlyNames(allDevices);

            // Show selector dialog for all devices - user can connect/disconnect from there
            if (radioSelectorForm != null && !radioSelectorForm.IsDisposed)
            {
                radioSelectorForm.Focus();
                return;
            }

            radioSelectorForm = new RadioConnectionForm(allDevices);
            radioSelectorForm.FormClosed += (s, args) => { radioSelectorForm = null; };
            radioSelectorForm.Show(this);
        }

        private void DisconnectRadio(Radio radio)
        {
            // Remove from DataBroker
            string handlerName = "Radio_" + radio.DeviceId;
            DataBroker.RemoveDataHandler(handlerName);

            // Disconnect and dispose
            radio.Dispose();

            // Remove from tracking list
            connectedRadios.Remove(radio);

            // Publish updated connected radios list
            PublishConnectedRadios();
        }

        private void radioToolStripMenuItem_CheckedChanged(object sender, EventArgs e)
        {
            radioPanel.Visible = radioToolStripMenuItem.Checked;
        }

        private void settingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // If settings form is already open, just focus it
            if (settingsForm != null && !settingsForm.IsDisposed)
            {
                settingsForm.Focus();
                return;
            }

            // Create and show the settings form as non-modal
            settingsForm = new SettingsForm();
            settingsForm.FormClosed += (s, args) => { settingsForm = null; };
            settingsForm.Show(this);
        }

        private void PublishConnectedRadios()
        {
            var radioList = connectedRadios.Select(r => new
            {
                DeviceId = r.DeviceId,
                MacAddress = r.MacAddress,
                FriendlyName = r.FriendlyName,
                State = r.State.ToString()
            }).ToList();
            broker.Dispatch(1, "ConnectedRadios", radioList);
        }

        private void OnCallSignOrStationIdChanged(int deviceId, string name, object data)
        {
            UpdateTitleBar();
        }

        private void OnRadioConnectRequested(int deviceId, string name, object data)
        {
            // Trigger the radio connection process when RadioConnect event is received
            connectToolStripMenuItem_Click(this, EventArgs.Empty);
        }

        private void OnRadioConnectRequest(int deviceId, string name, object data)
        {
            // Handle connection request from RadioSelectorForm
            if (data == null) return;
            var dataType = data.GetType();
            string macAddress = (string)dataType.GetProperty("MacAddress")?.GetValue(data);
            string friendlyName = (string)dataType.GetProperty("FriendlyName")?.GetValue(data);
            if (!string.IsNullOrEmpty(macAddress))
            {
                ConnectToRadio(macAddress, friendlyName ?? "");
            }
        }

        private void OnRadioDisconnectRequest(int deviceId, string name, object data)
        {
            // Handle disconnection request from RadioSelectorForm
            if (data == null) return;
            var dataType = data.GetType();
            string macAddress = (string)dataType.GetProperty("MacAddress")?.GetValue(data);
            if (!string.IsNullOrEmpty(macAddress))
            {
                Radio radio = connectedRadios.FirstOrDefault(r => r.MacAddress.Equals(macAddress, StringComparison.OrdinalIgnoreCase));
                if (radio != null)
                {
                    DisconnectRadio(radio);
                }
            }
        }

        private void UpdateTitleBar()
        {
            string callSign = DataBroker.GetValue<string>(0, "CallSign", "");
            int stationId = DataBroker.GetValue<int>(0, "StationId", 0);

            string baseTitle = "HTCommander";

            if (string.IsNullOrEmpty(callSign))
            {
                // No callsign, just show base title
                this.Text = baseTitle;
            }
            else if (stationId == 0)
            {
                // Has callsign but station ID is 0, show only callsign
                this.Text = baseTitle + " - " + callSign;
            }
            else
            {
                // Has callsign and non-zero station ID
                this.Text = baseTitle + " - " + callSign + "-" + stationId;
            }
        }

        private void ApplyStoredFriendlyNames(Radio.CompatibleDevice[] devices)
        {
            // Get stored friendly names and Bluetooth names from DataBroker
            var friendlyNames = DataBroker.GetValue<Dictionary<string, string>>(0, "DeviceFriendlyName", null);
            var bluetoothNames = DataBroker.GetValue<Dictionary<string, string>>(0, "DeviceBluetoothName", null);
            
            // Create or update the Bluetooth names dictionary with newly discovered names
            if (bluetoothNames == null)
            {
                bluetoothNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            }

            bool bluetoothNamesUpdated = false;
            foreach (var device in devices)
            {
                string macKey = device.mac.ToUpperInvariant();
                
                // Store the original Bluetooth-discovered name (from FindCompatibleDevices)
                // Only update if we don't have it yet or if the device has a non-empty name
                if (!string.IsNullOrEmpty(device.name) && 
                    (!bluetoothNames.ContainsKey(macKey) || string.IsNullOrEmpty(bluetoothNames[macKey])))
                {
                    bluetoothNames[macKey] = device.name;
                    bluetoothNamesUpdated = true;
                }

                // Apply the stored friendly name if available
                if (friendlyNames != null && friendlyNames.TryGetValue(macKey, out string storedName))
                {
                    device.name = storedName;
                }
                // If no stored name, keep the name from FindCompatibleDevices (default friendly name)
            }

            // Save updated Bluetooth names if changed
            if (bluetoothNamesUpdated)
            {
                DataBroker.Dispatch(0, "DeviceBluetoothName", bluetoothNames, store: true);
            }
        }

    }
}
