/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Windows.Forms;
using System.Collections.Generic;

namespace HTCommander
{
    public partial class EditIdentSettingsForm : Form
    {
        private DataBrokerClient _broker;
        private List<ConnectedRadioInfo> _connectedRadios = new List<ConnectedRadioInfo>();
        private int _selectedDeviceId = -1;

        public EditIdentSettingsForm()
        {
            InitializeComponent();
            _broker = new DataBrokerClient();

            // Subscribe to ConnectedRadios changes
            _broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
        }

        private void EditIdentSettingsForm_Load(object sender, EventArgs e)
        {
            // Clear the default items from the designer
            radioComboBox.Items.Clear();

            // Load connected radios from DataBroker
            LoadConnectedRadios();

            // If no radios are connected, close the dialog
            if (_connectedRadios.Count == 0)
            {
                MessageBox.Show(this, "No radios are connected.", "Ident Settings", MessageBoxButtons.OK, MessageBoxIcon.Information);
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
                MessageBox.Show(this, "All radios have been disconnected.", "Ident Settings", MessageBoxButtons.OK, MessageBoxIcon.Information);
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

            idInfoTextBox.Text = bssSettings.PttReleaseIdInfo;
            sendIdInfoCheckBox.Checked = bssSettings.PttReleaseSendIdInfo;
            sendLocationCheckBox.Checked = bssSettings.PttReleaseSendLocation;

            okButton.Enabled = (_selectedDeviceId > 0);
        }

        private void SetControlsEnabled(bool enabled)
        {
            idInfoTextBox.Enabled = enabled;
            sendIdInfoCheckBox.Enabled = enabled;
            sendLocationCheckBox.Enabled = enabled;
        }

        private void aprsCallsignTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if ((Control.ModifierKeys & Keys.Control) == Keys.Control) return;

            // Allow letters, numbers, dash (-), slash (/), and space
            if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != '/' && e.KeyChar != ' ' && e.KeyChar != (char)Keys.Back)
            {
                e.Handled = true; // Block the input
            }
        }

        private void aprsCallsignTextBox_TextChanged(object sender, EventArgs e)
        {
            okButton.Enabled = (_selectedDeviceId > 0);
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

            // Update the 4 PTT release settings from form values
            newSettings.PttReleaseIdInfo = idInfoTextBox.Text;
            newSettings.PttReleaseSendIdInfo = sendIdInfoCheckBox.Checked;
            newSettings.PttReleaseSendLocation = sendLocationCheckBox.Checked;

            // Dispatch the new settings to the radio
            _broker.Dispatch(_selectedDeviceId, "SetBssSettings", newSettings, store: false);

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
