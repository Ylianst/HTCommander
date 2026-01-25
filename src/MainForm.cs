/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.IO.Pipes;
using System.Threading;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.Collections.Generic;
using HTCommander.Dialogs;

namespace HTCommander
{
    public partial class MainForm : Form
    {
        private DataBrokerClient broker;
        private List<Radio> connectedRadios = new List<Radio>();
        private const int StartingDeviceId = 100;
        private SettingsForm settingsForm = null;
        private RadioConnectionForm radioSelectorForm = null;
        private CancellationTokenSource pipeServerCts = null;

        private string LastUpdateCheck => DataBroker.GetValue<string>(0, "LastUpdateCheck", null);
        private bool CheckForUpdates => DataBroker.GetValue<bool>(0, "CheckForUpdates", false);
        private int SelectedTabIndex => DataBroker.GetValue<int>(0, "SelectedTabIndex", 0);

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

            // Add the data handlers
            DataBroker.AddDataHandler("FrameDeduplicator", new FrameDeduplicator());
            DataBroker.AddDataHandler("PacketStore", new PacketStore());
            DataBroker.AddDataHandler("VoiceHandler", new VoiceHandler());
            DataBroker.AddDataHandler("LogStore", new LogStore());
            DataBroker.AddDataHandler("AprsHandler", new AprsHandler());
            DataBroker.AddDataHandler("Torrent", new Torrent());
            DataBroker.AddDataHandler("BbsHandler", new BbsHandler());

            // Subscribe to CallSign and StationId changes for title bar updates
            broker.Subscribe(0, new[] { "CallSign", "StationId" }, OnCallSignOrStationIdChanged);

            // Subscribe to AudioState changes from all radio devices
            broker.Subscribe(DataBroker.AllDevices, "AudioState", OnAudioStateChanged);

            // Subscribe to RadioConnect event from device 1 (e.g., from RadioPanelControl)
            broker.Subscribe(1, "RadioConnect", OnRadioConnectRequested);

            // Subscribe to RadioConnectRequest and RadioDisconnectRequest from RadioSelectorForm
            broker.Subscribe(1, "RadioConnectRequest", OnRadioConnectRequest);
            broker.Subscribe(1, "RadioDisconnectRequest", OnRadioDisconnectRequest);

            // Subscribe to ShowSettingsTab to open settings form at a specific tab
            broker.Subscribe(0, "ShowSettingsTab", OnShowSettingsTab);

            // Set initial title bar based on stored values
            UpdateTitleBar();

            // Publish initial empty connected radios list
            PublishConnectedRadios();
        }
        private void StartPipeServer()
        {
            pipeServerCts = new CancellationTokenSource();
            var token = pipeServerCts.Token;

            Task.Run(() =>
            {
                while (!token.IsCancellationRequested)
                {
                    NamedPipeServerStream server = null;
                    try
                    {
                        server = new NamedPipeServerStream(Program.PipeName);
                        // Use async wait with cancellation support
                        var waitTask = server.WaitForConnectionAsync(token);
                        waitTask.Wait(token);

                        if (token.IsCancellationRequested)
                        {
                            server.Dispose();
                            break;
                        }

                        using (var reader = new StreamReader(server))
                        {
                            var message = reader.ReadLine();
                            //if (message == "show") { showToolStripMenuItem_Click(this, null); }
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        // Cancellation requested, exit gracefully
                        server?.Dispose();
                        break;
                    }
                    catch (Exception)
                    {
                        // Handle other exceptions (e.g., pipe broken)
                        server?.Dispose();
                        if (token.IsCancellationRequested) break;
                    }
                }
            }, token);
        }

        private void StopPipeServer()
        {
            if (pipeServerCts != null)
            {
                pipeServerCts.Cancel();
                pipeServerCts.Dispose();
                pipeServerCts = null;
            }
        }

        private void MainForm_Load(object sender, EventArgs e)
        {
            // Restore selected tab
            int savedTabIndex = SelectedTabIndex;
            if (savedTabIndex >= 0 && savedTabIndex < mainTabControl.TabCount)
            {
                mainTabControl.SelectedIndex = savedTabIndex;
            }

            // Subscribe to tab selection changes to save the selected tab
            mainTabControl.SelectedIndexChanged += MainTabControl_SelectedIndexChanged;

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

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            StopPipeServer();
            base.OnFormClosing(e);
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

            // If the radioPanelControl is not monitoring an existing connected radio, set it to this new radio
            if (radioPanelControl.DeviceId <= 0 || !connectedRadios.Any(r => r.DeviceId == radioPanelControl.DeviceId))
            {
                radioPanelControl.DeviceId = deviceId;
            }

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
            int disconnectedDeviceId = radio.DeviceId;

            // Remove from DataBroker
            string handlerName = "Radio_" + radio.DeviceId;
            DataBroker.RemoveDataHandler(handlerName);

            // Disconnect and dispose
            radio.Dispose();

            // Remove from tracking list
            connectedRadios.Remove(radio);

            // If the radioPanelControl was displaying this radio, switch to another connected radio if available
            if (radioPanelControl.DeviceId == disconnectedDeviceId)
            {
                if (connectedRadios.Count > 0)
                {
                    // Switch to the first available connected radio
                    radioPanelControl.DeviceId = connectedRadios[0].DeviceId;
                }
                else
                {
                    // No radios left, reset to disconnected state
                    radioPanelControl.DeviceId = -1;
                }
            }

            // Publish updated connected radios list
            PublishConnectedRadios();
        }

        private void radioToolStripMenuItem_CheckedChanged(object sender, EventArgs e)
        {
            radioPanel.Visible = radioToolStripMenuItem.Checked;
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
                foreach (Radio radio in connectedRadios)
                {
                    ToolStripMenuItem radioMenuItem = new ToolStripMenuItem();
                    radioMenuItem.Text = string.IsNullOrEmpty(radio.FriendlyName) ? $"Radio {radio.DeviceId}" : radio.FriendlyName;
                    radioMenuItem.Tag = "DynamicRadioItem";
                    radioMenuItem.Checked = (radio.DeviceId == radioPanelControl.DeviceId);
                    radioMenuItem.Click += (s, args) =>
                    {
                        // Switch the radioPanelControl to display this radio
                        radioPanelControl.DeviceId = radio.DeviceId;
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

        private void allChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Toggle the ShowAllChannels state in RadioPanelControl
            radioPanelControl.ShowAllChannels = !radioPanelControl.ShowAllChannels;
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

        private void OnShowSettingsTab(int deviceId, string name, object data)
        {
            // Show the settings form at the specified tab index
            int tabIndex = 0;
            if (data is int tabIndexValue) { tabIndex = tabIndexValue; }

            // If settings form is already open, just focus it and move to the tab
            if (settingsForm != null && !settingsForm.IsDisposed)
            {
                settingsForm.MoveToTab(tabIndex);
                settingsForm.Focus();
                return;
            }

            // Create and show the settings form as non-modal
            settingsForm = new SettingsForm();
            settingsForm.FormClosed += (s, args) => { settingsForm = null; };
            settingsForm.Show(this);
            settingsForm.MoveToTab(tabIndex);
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

        private void radioWindowToolStripMenuItem_Click(object sender, EventArgs e)
        {
            RadioForm radioForm = new RadioForm();
            radioForm.DeviceId = radioPanelControl.DeviceId;
            radioForm.Show(this);
        }

        private void settingsMenuToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
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
                ImportChannelsFromFile(importChannelsFileDialog.FileName);
            }
        }

        /// <summary>
        /// Imports channels from a CSV file and opens the ImportChannelsForm.
        /// </summary>
        /// <param name="filename">The path to the CSV file to import.</param>
        public void ImportChannelsFromFile(string filename)
        {
            RadioChannelInfo[] channels = ImportUtils.ParseChannelsFromFile(filename);
            if (channels == null || channels.Length == 0) return;

            ImportChannelsForm f = new ImportChannelsForm(null, channels);
            f.Text = f.Text + " - " + new FileInfo(filename).Name;
            f.Show(this);
        }

        private void MainTabControl_SelectedIndexChanged(object sender, EventArgs e)
        {
            // Save the currently selected tab index to the DataBroker
            DataBroker.Dispatch(0, "SelectedTabIndex", mainTabControl.SelectedIndex, store: true);
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

        private void OnAudioStateChanged(int deviceId, string name, object data)
        {
            // Update the audio enabled menu item checkbox when the audio state changes
            // for the radio that radioPanelControl is currently viewing
            if (deviceId == radioPanelControl.DeviceId)
            {
                bool audioEnabled = (data is bool b) && b;
                audioEnabledToolStripMenuItem.Checked = audioEnabled;
            }
        }

        private void audioToolStripMenuItem1_DropDownOpening(object sender, EventArgs e)
        {
            int deviceId = radioPanelControl.DeviceId;
            bool hasRadio = (deviceId > 0) && connectedRadios.Any(r => r.DeviceId == deviceId);

            // Enable/disable audio menu items based on radio connection
            audioEnabledToolStripMenuItem.Enabled = hasRadio;

            if (!hasRadio)
            {
                audioEnabledToolStripMenuItem.Checked = false;
                return;
            }

            // Get the current audio state from the broker
            bool audioEnabled = DataBroker.GetValue<bool>(deviceId, "AudioState", false);
            audioEnabledToolStripMenuItem.Checked = audioEnabled;
        }

        private void audioEnabledToolStripMenuItem_Click(object sender, EventArgs e)
        {
            int deviceId = radioPanelControl.DeviceId;
            if (deviceId <= 0) return;

            // Toggle audio state - get current state and toggle it
            bool currentlyEnabled = DataBroker.GetValue<bool>(deviceId, "AudioState", false);
            DataBroker.Dispatch(deviceId, "SetAudio", !currentlyEnabled, store: false);
        }

    }
}
