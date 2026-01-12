using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using HTCommander.RadioControls;

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
            var radioList = broker.GetValue<List<object>>(1, "ConnectedRadios", null);
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
