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
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.Collections.Generic;

namespace HTCommander
{
    public partial class MainForm : Form
    {
        private DataBrokerClient broker;
        private List<Radio> connectedRadios = new List<Radio>();
        private const int StartingDeviceId = 100;

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
            radioStatusToolStripMenuItem.Enabled = hasRadio;
            radioSettingsToolStripMenuItem.Enabled = hasRadio;
            radioBSSSettingsToolStripMenuItem.Enabled = hasRadio;
            radioPositionToolStripMenuItem.Enabled = hasRadio;
        }

        private void radioInformationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (connectedRadios.Count == 0) return;
            new RadioInfoForm(connectedRadios[0].DeviceId).Show(this);
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

            // Filter out already connected radios
            var connectedMacs = connectedRadios.Select(r => r.MacAddress.ToUpperInvariant()).ToHashSet();
            var availableDevices = allDevices.Where(d => !connectedMacs.Contains(d.mac.ToUpperInvariant())).ToArray();

            if (availableDevices.Length == 0)
            {
                MessageBox.Show(this, "All compatible radios are already connected.", "No Available Radios", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (availableDevices.Length == 1)
            {
                // Single device found - connect directly
                ConnectToRadio(availableDevices[0].mac);
            }
            else
            {
                // Multiple devices found - show selector dialog
                using (RadioSelectorForm selectorForm = new RadioSelectorForm(this, availableDevices))
                {
                    if (selectorForm.ShowDialog(this) == DialogResult.OK)
                    {
                        string selectedMac = selectorForm.SelectedMac;
                        if (!string.IsNullOrEmpty(selectedMac))
                        {
                            ConnectToRadio(selectedMac);
                        }
                    }
                }
            }
        }

        private int GetNextAvailableDeviceId()
        {
            int deviceId = StartingDeviceId;
            var usedIds = connectedRadios.Select(r => r.DeviceId).ToHashSet();
            while (usedIds.Contains(deviceId))
            {
                deviceId++;
            }
            return deviceId;
        }

        private void ConnectToRadio(string macAddress)
        {
            // Check if already connected to this MAC address
            if (connectedRadios.Any(r => r.MacAddress.Equals(macAddress, StringComparison.OrdinalIgnoreCase)))
            {
                MessageBox.Show(this, "This radio is already connected.", "Already Connected", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            // Get the next available device ID
            int deviceId = GetNextAvailableDeviceId();

            // Create the radio instance
            Radio radio = new Radio(deviceId, macAddress);

            // Add the radio as a data handler in the DataBroker
            string handlerName = "Radio_" + deviceId;
            DataBroker.AddDataHandler(handlerName, radio);

            // Track the connected radio
            connectedRadios.Add(radio);

            // Start the Bluetooth connection
            radio.Connect();
        }

        private void disconnectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (connectedRadios.Count == 0)
            {
                MessageBox.Show(this, "No radios are currently connected.", "No Connected Radios", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (connectedRadios.Count == 1)
            {
                // Single radio connected - disconnect directly
                DisconnectRadio(connectedRadios[0]);
            }
            else
            {
                // Multiple radios connected - show selector dialog
                var devices = connectedRadios.Select(r => new Radio.CompatibleDevice("Radio " + r.DeviceId, r.MacAddress)).ToArray();
                using (RadioSelectorForm selectorForm = new RadioSelectorForm(this, devices))
                {
                    if (selectorForm.ShowDialog(this) == DialogResult.OK)
                    {
                        string selectedMac = selectorForm.SelectedMac;
                        if (!string.IsNullOrEmpty(selectedMac))
                        {
                            Radio radio = connectedRadios.FirstOrDefault(r => r.MacAddress.Equals(selectedMac, StringComparison.OrdinalIgnoreCase));
                            if (radio != null)
                            {
                                DisconnectRadio(radio);
                            }
                        }
                    }
                }
            }
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
        }

        private void radioToolStripMenuItem_CheckedChanged(object sender, EventArgs e)
        {
            radioPanel.Visible = radioToolStripMenuItem.Checked;
        }
    }
}
