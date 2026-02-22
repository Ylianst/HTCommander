/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;

namespace HTCommander
{
    public partial class EditBeaconSettingsForm : Form
    {
        private DataBrokerClient _broker;
        private List<ConnectedRadioInfo> _connectedRadios = new List<ConnectedRadioInfo>();
        private List<int> _channelValues = new List<int>();
        private int _selectedDeviceId = -1;

        public EditBeaconSettingsForm()
        {
            InitializeComponent();
            _broker = new DataBrokerClient();

            // Subscribe to ConnectedRadios changes
            _broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
        }

        private void EditBeaconSettingsForm_Load(object sender, EventArgs e)
        {
            // Clear the default items from the designer
            radioComboBox.Items.Clear();
            channelComboBox.Items.Clear();

            // Load connected radios from DataBroker
            LoadConnectedRadios();

            // If no radios are connected, close the dialog
            if (_connectedRadios.Count == 0)
            {
                MessageBox.Show(this, "No radios are connected.", "Beacon Settings", MessageBoxButtons.OK, MessageBoxIcon.Information);
                DialogResult = DialogResult.Cancel;
                Close();
                return;
            }

            // Select the first radio
            if (radioComboBox.Items.Count > 0)
            {
                radioComboBox.SelectedIndex = 0;
            }
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnConnectedRadiosChanged), deviceId, name, data);
                return;
            }

            // Remember currently selected device ID
            int previousSelectedDeviceId = _selectedDeviceId;

            // Reload the connected radios
            LoadConnectedRadios();

            // If no radios are connected, close the dialog
            if (_connectedRadios.Count == 0)
            {
                MessageBox.Show(this, "All radios have been disconnected.", "Beacon Settings", MessageBoxButtons.OK, MessageBoxIcon.Information);
                DialogResult = DialogResult.Cancel;
                Close();
                return;
            }

            // Try to reselect the previously selected radio
            int newSelectedIndex = -1;
            for (int i = 0; i < _connectedRadios.Count; i++)
            {
                if (_connectedRadios[i].DeviceId == previousSelectedDeviceId)
                {
                    newSelectedIndex = i;
                    break;
                }
            }

            // If the previously selected radio is no longer available, select the first one
            if (newSelectedIndex >= 0)
            {
                radioComboBox.SelectedIndex = newSelectedIndex;
            }
            else if (radioComboBox.Items.Count > 0)
            {
                radioComboBox.SelectedIndex = 0;
            }
        }

        private void LoadConnectedRadios()
        {
            _connectedRadios.Clear();
            radioComboBox.Items.Clear();

            var connectedRadios = _broker.GetValue<object>(1, "ConnectedRadios", null);
            if (connectedRadios == null) return;

            if (connectedRadios is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var itemType = item.GetType();
                    int? deviceId = (int?)itemType.GetProperty("DeviceId")?.GetValue(item);
                    string friendlyName = (string)itemType.GetProperty("FriendlyName")?.GetValue(item);

                    if (deviceId.HasValue)
                    {
                        var radioInfo = new ConnectedRadioInfo
                        {
                            DeviceId = deviceId.Value,
                            FriendlyName = friendlyName ?? $"Radio {deviceId.Value}"
                        };
                        _connectedRadios.Add(radioInfo);
                        radioComboBox.Items.Add(radioInfo.FriendlyName);
                    }
                }
            }
        }

        private void radioComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            int selectedIndex = radioComboBox.SelectedIndex;
            if (selectedIndex < 0 || selectedIndex >= _connectedRadios.Count)
            {
                _selectedDeviceId = -1;
                SetControlsEnabled(false);
                return;
            }

            _selectedDeviceId = _connectedRadios[selectedIndex].DeviceId;
            LoadBssSettings(_selectedDeviceId);
        }

        private void LoadBssSettings(int deviceId)
        {
            RadioBssSettings bssSettings = _broker.GetValue<RadioBssSettings>(deviceId, "BssSettings", null);
            if (bssSettings == null)
            {
                SetControlsEnabled(false);
                okButton.Enabled = false;
                return;
            }

            SetControlsEnabled(true);
            LoadChannelComboBox(deviceId);

            packetFormatComboBox.SelectedIndex = bssSettings.PacketFormat;
            aprsCallsignTextBox.Text = bssSettings.AprsCallsign + "-" + bssSettings.AprsSsid.ToString();
            aprsMessageTextBox.Text = bssSettings.BeaconMessage;
            shareLocationCheckBox.Checked = bssSettings.ShouldShareLocation;
            sendVoltageCheckBox.Checked = bssSettings.SendPwrVoltage;
            allowPositionCheckBox.Checked = bssSettings.AllowPositionCheck;

            // Set interval combobox based on LocationShareInterval
            intervalComboBox.SelectedIndex = 0; // Off
            if (bssSettings.LocationShareInterval >= 10) { intervalComboBox.SelectedIndex = 1; }
            if (bssSettings.LocationShareInterval >= 20) { intervalComboBox.SelectedIndex = 2; }
            if (bssSettings.LocationShareInterval >= 30) { intervalComboBox.SelectedIndex = 3; }
            if (bssSettings.LocationShareInterval >= 40) { intervalComboBox.SelectedIndex = 4; }
            if (bssSettings.LocationShareInterval >= 50) { intervalComboBox.SelectedIndex = 5; }
            if (bssSettings.LocationShareInterval >= (1 * 60)) { intervalComboBox.SelectedIndex = 6; }
            if (bssSettings.LocationShareInterval >= (2 * 60)) { intervalComboBox.SelectedIndex = 7; }
            if (bssSettings.LocationShareInterval >= (3 * 60)) { intervalComboBox.SelectedIndex = 8; }
            if (bssSettings.LocationShareInterval >= (4 * 60)) { intervalComboBox.SelectedIndex = 9; }
            if (bssSettings.LocationShareInterval >= (5 * 60)) { intervalComboBox.SelectedIndex = 10; }
            if (bssSettings.LocationShareInterval >= (6 * 60)) { intervalComboBox.SelectedIndex = 11; }
            if (bssSettings.LocationShareInterval >= (7 * 60)) { intervalComboBox.SelectedIndex = 12; }
            if (bssSettings.LocationShareInterval >= (8 * 60)) { intervalComboBox.SelectedIndex = 13; }
            if (bssSettings.LocationShareInterval >= (9 * 60)) { intervalComboBox.SelectedIndex = 14; }
            if (bssSettings.LocationShareInterval >= (10 * 60)) { intervalComboBox.SelectedIndex = 15; }
            if (bssSettings.LocationShareInterval >= (15 * 60)) { intervalComboBox.SelectedIndex = 16; }
            if (bssSettings.LocationShareInterval >= (20 * 60)) { intervalComboBox.SelectedIndex = 17; }
            if (bssSettings.LocationShareInterval >= (25 * 60)) { intervalComboBox.SelectedIndex = 18; }
            if (bssSettings.LocationShareInterval >= (30 * 60)) { intervalComboBox.SelectedIndex = 19; }

            UpdateInfo();
        }

        private void LoadChannelComboBox(int deviceId)
        {
            channelComboBox.Items.Clear();
            _channelValues.Clear();

            // Add "Current (Not Recommended)" as the first option with value 0
            channelComboBox.Items.Add("Current (Not Recommended)");
            _channelValues.Add(0);

            // Load named channels from the radio
            RadioChannelInfo[] channels = _broker.GetValue<RadioChannelInfo[]>(deviceId, "Channels", null);
            if (channels != null)
            {
                for (int i = 0; i < channels.Length; i++)
                {
                    if (channels[i] != null && !string.IsNullOrEmpty(channels[i].name_str))
                    {
                        channelComboBox.Items.Add(channels[i].name_str);
                        _channelValues.Add(channels[i].channel_id + 1);
                    }
                }
            }

            // Select the current value from RadioSettings.auto_share_loc_ch
            RadioSettings settings = _broker.GetValue<RadioSettings>(deviceId, "Settings", null);
            int currentValue = settings?.auto_share_loc_ch ?? 0;
            int selectedIndex = 0;
            for (int i = 0; i < _channelValues.Count; i++)
            {
                if (_channelValues[i] == currentValue)
                {
                    selectedIndex = i;
                    break;
                }
            }
            channelComboBox.SelectedIndex = selectedIndex;
        }

        private void SetControlsEnabled(bool enabled)
        {
            channelComboBox.Enabled = enabled;
            packetFormatComboBox.Enabled = enabled;
            intervalComboBox.Enabled = enabled;
            aprsCallsignTextBox.Enabled = enabled;
            aprsMessageTextBox.Enabled = enabled;
            shareLocationCheckBox.Enabled = enabled;
            sendVoltageCheckBox.Enabled = enabled;
            allowPositionCheckBox.Enabled = enabled;
        }

        private void UpdateInfo()
        {
            bool ok = true;

            if (packetFormatComboBox.SelectedIndex == 0)
            {
                aprsCallsignTextBox.BackColor = SystemColors.Window;
                aprsCallsignTextBox.Enabled = false;
                aprsMessageTextBox.Enabled = false;
            }
            else
            {
                // Check callsign
                AX25Address addr = AX25Address.GetAddress(aprsCallsignTextBox.Text);
                aprsCallsignTextBox.BackColor = (addr == null) ? Color.MistyRose : SystemColors.Window;
                if (addr == null) { ok = false; }
                aprsCallsignTextBox.Enabled = true;
                aprsMessageTextBox.Enabled = true;
            }

            okButton.Enabled = ok && (_selectedDeviceId > 0);
        }

        private void aprsCallsignTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if ((Control.ModifierKeys & Keys.Control) == Keys.Control) return;

            // Allow letters, numbers, and the dash (-)
            if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != (char)Keys.Back)
            {
                e.Handled = true; // Block the input
            }
        }

        private void aprsCallsignTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void packetFormatComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            if (_selectedDeviceId <= 0) return;

            // Get the current BssSettings to preserve unchanged values
            RadioBssSettings currentSettings = _broker.GetValue<RadioBssSettings>(_selectedDeviceId, "BssSettings", null);
            if (currentSettings == null) return;

            // Create a copy of the current settings
            byte[] x1 = currentSettings.ToByteArray();
            byte[] x2 = new byte[x1.Length + 5];
            Array.Copy(x1, 0, x2, 5, x1.Length);
            RadioBssSettings newSettings = new RadioBssSettings(x2);

            // Update the settings from form values
            AX25Address addr = AX25Address.GetAddress(aprsCallsignTextBox.Text);
            if (addr != null)
            {
                newSettings.AprsCallsign = addr.address;
                newSettings.AprsSsid = addr.SSID;
            }
            newSettings.PacketFormat = packetFormatComboBox.SelectedIndex;
            newSettings.BeaconMessage = aprsMessageTextBox.Text;
            newSettings.ShouldShareLocation = shareLocationCheckBox.Checked;
            newSettings.SendPwrVoltage = sendVoltageCheckBox.Checked;
            newSettings.AllowPositionCheck = allowPositionCheckBox.Checked;

            // Convert interval combobox selection to seconds
            int[] intervalValues = { 0, 10, 20, 30, 40, 50, 60, 120, 180, 240, 300, 360, 420, 480, 540, 600, 900, 1200, 1500, 1800 };
            if (intervalComboBox.SelectedIndex >= 0 && intervalComboBox.SelectedIndex < intervalValues.Length)
            {
                newSettings.LocationShareInterval = intervalValues[intervalComboBox.SelectedIndex];
            }

            // Dispatch the new settings to the radio
            _broker.Dispatch(_selectedDeviceId, "SetBssSettings", newSettings, store: false);

            // Save auto_share_loc_ch to RadioSettings
            RadioSettings radioSettings = _broker.GetValue<RadioSettings>(_selectedDeviceId, "Settings", null);
            if (radioSettings != null)
            {
                int channelValue = 0;
                if (channelComboBox.SelectedIndex >= 0 && channelComboBox.SelectedIndex < _channelValues.Count)
                {
                    channelValue = _channelValues[channelComboBox.SelectedIndex];
                }
                byte[] settingsData = radioSettings.ToByteArray(radioSettings.channel_a, radioSettings.channel_b, radioSettings.double_channel, radioSettings.scan, radioSettings.squelch_level);
                settingsData[5] = (byte)((settingsData[5] & 0xE0) | (channelValue & 0x1F));
                _broker.Dispatch(_selectedDeviceId, "WriteSettings", settingsData, store: false);
            }

            DialogResult = DialogResult.OK;
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
