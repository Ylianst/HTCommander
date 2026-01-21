/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace HTCommander.Dialogs
{
    /// <summary>
    /// Dialog for selecting terminal connection options.
    /// </summary>
    public partial class TerminalConnectDialog : Form
    {
        private DataBrokerClient _broker;
        private List<ConnectedRadioInfo> _connectedRadios = new List<ConnectedRadioInfo>();

        /// <summary>
        /// Gets the selected radio's device ID after the dialog is closed with OK.
        /// </summary>
        public int SelectedDeviceId { get; private set; } = -1;

        /// <summary>
        /// Gets the selected radio's friendly name after the dialog is closed with OK.
        /// </summary>
        public string SelectedRadioName { get; private set; } = null;

        public TerminalConnectDialog()
        {
            InitializeComponent();
            _broker = new DataBrokerClient();

            // Subscribe to ConnectedRadios changes
            _broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
        }

        private void TerminalConnectDialog_Load(object sender, EventArgs e)
        {
            // Load connected radios from DataBroker
            LoadConnectedRadios();

            // Update UI based on available radios
            UpdateUI();
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnConnectedRadiosChanged), deviceId, name, data);
                return;
            }

            // Reload the connected radios
            LoadConnectedRadios();
            UpdateUI();
        }

        private void LoadConnectedRadios()
        {
            _connectedRadios.Clear();

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
                    }
                }
            }
        }

        private void UpdateUI()
        {
            // Update the label and connect button based on available radios
            if (_connectedRadios.Count == 0)
            {
                label1.Text = "No radios are connected.";
                connectButton.Enabled = false;
            }
            else if (_connectedRadios.Count == 1)
            {
                label1.Text = $"Connect to a remote station using {_connectedRadios[0].FriendlyName}?";
                connectButton.Enabled = true;
            }
            else
            {
                label1.Text = $"Connect to a remote station using one of {_connectedRadios.Count} available radios?";
                connectButton.Enabled = true;
            }
        }

        private void connectButton_Click(object sender, EventArgs e)
        {
            if (_connectedRadios.Count > 0)
            {
                // For now, select the first available radio
                // In the future, we could show a radio selection dropdown if multiple radios are available
                SelectedDeviceId = _connectedRadios[0].DeviceId;
                SelectedRadioName = _connectedRadios[0].FriendlyName;
            }
            this.DialogResult = DialogResult.OK;
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            this.DialogResult = DialogResult.Cancel;
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
