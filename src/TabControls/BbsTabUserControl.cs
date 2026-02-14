/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;
using System.Collections.Generic;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class BbsTabUserControl : UserControl, IRadioDeviceSelector
    {
        private int _preferredRadioDeviceId = -1;
        private DataBrokerClient broker;
        private bool _showDetach = false;
        private List<int> connectedRadios = new List<int>();
        private Dictionary<int, RadioLockState> lockStates = new Dictionary<int, RadioLockState>();

        /// <summary>
        /// Gets or sets the preferred radio device ID for this control.
        /// </summary>
        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public int PreferredRadioDeviceId
        {
            get { return _preferredRadioDeviceId; }
            set { _preferredRadioDeviceId = value; }
        }

        /// <summary>
        /// Gets or sets whether the "Detach..." menu item is visible.
        /// </summary>
        [System.ComponentModel.Category("Behavior")]
        [System.ComponentModel.Description("Gets or sets whether the Detach menu item is visible.")]
        [System.ComponentModel.DefaultValue(false)]
        public bool ShowDetach
        {
            get { return _showDetach; }
            set
            {
                _showDetach = value;
                if (detachToolStripMenuItem != null)
                {
                    detachToolStripMenuItem.Visible = value;
                    toolStripMenuItemDetachSeparator.Visible = value;
                }
            }
        }

        public BbsTabUserControl()
        {
            InitializeComponent();

            broker = new DataBrokerClient();

            // Subscribe to connected radios and lock state to update activate button
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);

            // Subscribe to BBS events from the broker (device 0 for global BBS events)
            broker.Subscribe(DataBroker.AllDevices, new[] { "BbsTraffic", "BbsControlMessage", "BbsError" }, OnBbsEvent);

            // Subscribe to merged stats from BbsHandler (device ID 1)
            broker.Subscribe(1, "BbsMergedStats", OnBbsMergedStats);

            // Load settings from broker (device 0 for app settings)
            bool viewTraffic = broker.GetValue<int>(0, "ViewBbsTraffic", 1) == 1;
            viewTrafficToolStripMenuItem.Checked = viewTraffic;
            bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;

            // Set initial button state (disabled until we know radio state)
            bbsConnectButton.Text = "&Activate";
            bbsConnectButton.Enabled = false;

            // Enable double buffering on the ListView to prevent flickering
            EnableDoubleBuffering(bbsListView);
        }

        /// <summary>
        /// Enables double buffering on a ListView control to prevent flickering during updates.
        /// </summary>
        private void EnableDoubleBuffering(ListView listView)
        {
            // Use reflection to set the protected DoubleBuffered property
            PropertyInfo prop = typeof(ListView).GetProperty("DoubleBuffered", BindingFlags.Instance | BindingFlags.NonPublic);
            prop?.SetValue(listView, true, null);
        }

        #region Radio State Management

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (data == null) return;

            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ProcessConnectedRadiosChanged(data)));
            }
            else
            {
                ProcessConnectedRadiosChanged(data);
            }
        }

        private void ProcessConnectedRadiosChanged(object data)
        {
            connectedRadios.Clear();

            if (data is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var itemType = item.GetType();
                    int? radioDeviceId = (int?)itemType.GetProperty("DeviceId")?.GetValue(item);
                    if (radioDeviceId.HasValue)
                    {
                        connectedRadios.Add(radioDeviceId.Value);
                    }
                }
            }

            UpdateActivateButtonState();
        }

        private void OnLockStateChanged(int deviceId, string name, object data)
        {
            if (!(data is RadioLockState lockState)) return;

            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ProcessLockStateChanged(deviceId, lockState)));
            }
            else
            {
                ProcessLockStateChanged(deviceId, lockState);
            }
        }

        private void ProcessLockStateChanged(int deviceId, RadioLockState lockState)
        {
            lockStates[deviceId] = lockState;
            UpdateActivateButtonState();
        }

        private void UpdateActivateButtonState()
        {
            // Check if any radio is locked to BBS
            int bbsRadioId = GetActiveBbsRadioId();
            
            if (bbsRadioId > 0)
            {
                // Radio is locked to BBS - show Deactivate
                bbsConnectButton.Text = "&Deactivate";
                bbsConnectButton.Enabled = true;
                bbsTitleLabel.Text = "BBS - Active";
            }
            else
            {
                // No radio locked to BBS - check for available radios
                var availableRadios = GetAvailableRadiosWithNames();
                
                if (availableRadios.Count > 0)
                {
                    // At least one radio available - show Activate
                    bbsConnectButton.Text = "&Activate";
                    bbsConnectButton.Enabled = true;
                    bbsTitleLabel.Text = "BBS";
                }
                else if (connectedRadios.Count > 0)
                {
                    // Radios connected but all locked to other uses - disable
                    bbsConnectButton.Text = "&Activate";
                    bbsConnectButton.Enabled = false;
                    bbsTitleLabel.Text = "BBS";
                }
                else
                {
                    // No radios connected - disable
                    bbsConnectButton.Text = "&Activate";
                    bbsConnectButton.Enabled = false;
                    bbsTitleLabel.Text = "BBS";
                }
            }
        }

        /// <summary>
        /// Gets the radio ID that is currently locked to BBS usage.
        /// </summary>
        private int GetActiveBbsRadioId()
        {
            foreach (var radioId in connectedRadios)
            {
                if (lockStates.TryGetValue(radioId, out RadioLockState lockState) && lockState.IsLocked && lockState.Usage == "BBS")
                {
                    return radioId;
                }
            }
            return -1;
        }

        /// <summary>
        /// Gets the first available (unlocked) radio ID.
        /// </summary>
        private int GetAvailableRadioId()
        {
            foreach (var radioId in connectedRadios)
            {
                if (!lockStates.TryGetValue(radioId, out RadioLockState lockState) || !lockState.IsLocked)
                {
                    return radioId;
                }
            }
            return -1;
        }

        /// <summary>
        /// Gets all available (unlocked) radios with their friendly names.
        /// </summary>
        private List<(int DeviceId, string FriendlyName)> GetAvailableRadiosWithNames()
        {
            var availableRadios = new List<(int DeviceId, string FriendlyName)>();

            foreach (var radioId in connectedRadios)
            {
                if (!lockStates.TryGetValue(radioId, out RadioLockState lockState) || !lockState.IsLocked)
                {
                    // Get the friendly name from the DataBroker
                    string friendlyName = broker.GetValue<string>(radioId, "FriendlyName", $"Radio {radioId}");
                    availableRadios.Add((radioId, friendlyName));
                }
            }

            return availableRadios;
        }

        #endregion

        /// <summary>
        /// Handles BBS events from the DataBroker.
        /// </summary>
        private void OnBbsEvent(int deviceId, string name, object data)
        {
            switch (name)
            {
                case "BbsTraffic":
                    HandleTraffic(data);
                    break;
                case "BbsControlMessage":
                    HandleControlMessage(data);
                    break;
                case "BbsError":
                    HandleError(data);
                    break;
            }
        }

        /// <summary>
        /// Handles merged stats updates from BbsHandler.
        /// </summary>
        private void OnBbsMergedStats(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnBbsMergedStats), deviceId, name, data);
                return;
            }

            if (!(data is List<MergedStationStats> statsList))
            {
                // Try to handle as IEnumerable for compatibility
                if (data is System.Collections.IEnumerable enumerable)
                {
                    UpdateMergedStatsFromEnumerable(enumerable);
                }
                return;
            }

            UpdateMergedStats(statsList);
        }

        /// <summary>
        /// Updates the ListView with the merged stats list.
        /// </summary>
        private void UpdateMergedStats(List<MergedStationStats> statsList)
        {
            // Suspend drawing to prevent flickering during batch updates
            bbsListView.BeginUpdate();
            try
            {
                // Build a dictionary of existing items by callsign for efficient lookup
                Dictionary<string, ListViewItem> existingItems = new Dictionary<string, ListViewItem>(StringComparer.OrdinalIgnoreCase);
                foreach (ListViewItem item in bbsListView.Items)
                {
                    if (item.Tag is string callsign)
                    {
                        existingItems[callsign] = item;
                    }
                }

                // Track which callsigns are still present
                HashSet<string> presentCallsigns = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

                foreach (var stats in statsList)
                {
                    presentCallsigns.Add(stats.Callsign);

                    if (existingItems.TryGetValue(stats.Callsign, out ListViewItem existingItem))
                    {
                        // Update existing item
                        existingItem.SubItems[1].Text = stats.LastSeen.ToString();
                        existingItem.SubItems[2].Text = FormatStatsDetails(stats);
                    }
                    else
                    {
                        // Create new item
                        ListViewItem newItem = new ListViewItem(new string[] { stats.Callsign, stats.LastSeen.ToString(), FormatStatsDetails(stats) });
                        newItem.ImageIndex = 0;
                        newItem.Tag = stats.Callsign;
                        bbsListView.Items.Add(newItem);
                    }
                }

                // Remove items that are no longer in the stats list
                for (int i = bbsListView.Items.Count - 1; i >= 0; i--)
                {
                    ListViewItem item = bbsListView.Items[i];
                    if (item.Tag is string callsign && !presentCallsigns.Contains(callsign))
                    {
                        bbsListView.Items.RemoveAt(i);
                    }
                }
            }
            finally
            {
                // Resume drawing
                bbsListView.EndUpdate();
            }
        }

        /// <summary>
        /// Updates merged stats from an IEnumerable (for compatibility with different data types).
        /// </summary>
        private void UpdateMergedStatsFromEnumerable(System.Collections.IEnumerable enumerable)
        {
            List<MergedStationStats> statsList = new List<MergedStationStats>();

            foreach (var item in enumerable)
            {
                if (item is MergedStationStats stats)
                {
                    statsList.Add(stats);
                }
            }

            if (statsList.Count > 0)
            {
                UpdateMergedStats(statsList);
            }
        }

        /// <summary>
        /// Formats the stats details for display in the ListView.
        /// </summary>
        private string FormatStatsDetails(MergedStationStats stats)
        {
            return $"{stats.Protocol}, {stats.TotalPacketsIn} in / {stats.TotalPacketsOut} out, {stats.TotalBytesIn} in / {stats.TotalBytesOut} out";
        }

        /// <summary>
        /// Handles BbsTraffic events.
        /// </summary>
        private void HandleTraffic(object data)
        {
            if (data == null) return;
            var dataType = data.GetType();
            var callsignProp = dataType.GetProperty("Callsign");
            var outgoingProp = dataType.GetProperty("Outgoing");
            var messageProp = dataType.GetProperty("Message");
            if (callsignProp == null || outgoingProp == null || messageProp == null) return;

            string callsign = callsignProp.GetValue(data) as string;
            bool outgoing = (bool)outgoingProp.GetValue(data);
            string message = messageProp.GetValue(data) as string;

            if (callsign != null && message != null)
            {
                AddBbsTraffic(callsign, outgoing, message);
            }
        }

        /// <summary>
        /// Handles BbsControlMessage events.
        /// </summary>
        private void HandleControlMessage(object data)
        {
            if (data == null) return;
            var dataType = data.GetType();
            var messageProp = dataType.GetProperty("Message");
            if (messageProp == null) return;

            string message = messageProp.GetValue(data) as string;
            if (message != null)
            {
                AddBbsControlMessage(message);
            }
        }

        /// <summary>
        /// Handles BbsError events.
        /// </summary>
        private void HandleError(object data)
        {
            if (data == null) return;
            var dataType = data.GetType();
            var errorProp = dataType.GetProperty("Error");
            if (errorProp == null) return;

            string error = errorProp.GetValue(data) as string;
            if (error != null)
            {
                AddBbsControlMessage("Error: " + error);
            }
        }


        public void AddBbsTraffic(string callsign, bool outgoing, string text)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, bool, string>(AddBbsTraffic), callsign, outgoing, text);
                return;
            }

            if (bbsTextBox.Text.Length != 0) { bbsTextBox.AppendText(Environment.NewLine); }
            if (outgoing) { AppendBbsText(callsign + " < ", Color.Green); } else { AppendBbsText(callsign + " > ", Color.Green); }
            AppendBbsText(text, outgoing ? Color.CornflowerBlue : Color.Gainsboro);
            bbsTextBox.SelectionStart = bbsTextBox.Text.Length;
            bbsTextBox.ScrollToCaret();
        }

        public void AddBbsControlMessage(string text)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(AddBbsControlMessage), text);
                return;
            }

            if (bbsTextBox.Text.Length != 0) { bbsTextBox.AppendText(Environment.NewLine); }
            AppendBbsText(text, Color.Yellow);
            bbsTextBox.SelectionStart = bbsTextBox.Text.Length;
            bbsTextBox.ScrollToCaret();
        }

        private void AppendBbsText(string text, Color color)
        {
            bbsTextBox.SelectionStart = bbsTextBox.TextLength;
            bbsTextBox.SelectionLength = 0;
            bbsTextBox.SelectionColor = color;
            bbsTextBox.AppendText(text);
            bbsTextBox.SelectionColor = bbsTextBox.ForeColor;
        }

        public void ClearStats()
        {
            bbsListView.Items.Clear();
            // Request stats clear via broker (device ID 1 for BbsHandler)
            broker?.Dispatch(1, "BbsClearAllStats", null, store: false);
        }

        private void bbsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            bbsTabContextMenuStrip.Show(bbsMenuPictureBox, e.Location);
        }

        private void bbsConnectButton_Click(object sender, EventArgs e)
        {
            int activeBbsRadioId = GetActiveBbsRadioId();

            if (activeBbsRadioId > 0)
            {
                // We have an active BBS - deactivate it
                var removeData = new RemoveBbsData
                {
                    RadioDeviceId = activeBbsRadioId
                };
                broker.Dispatch(1, "RemoveBbs", removeData, store: false);
                broker.LogInfo("[BbsTab] Deactivating BBS on radio " + activeBbsRadioId);
            }
            else
            {
                // No active BBS - check for available radios
                var availableRadios = GetAvailableRadiosWithNames();
                if (availableRadios.Count == 0)
                {
                    MessageBox.Show(this, "No available radio to activate BBS.", "BBS", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // If multiple radios are available, show a context menu to select one
                if (availableRadios.Count > 1)
                {
                    ShowRadioSelectionMenu(availableRadios);
                    return;
                }

                // Single radio available - proceed with activation
                int availableRadioId = availableRadios[0].DeviceId;
                ActivateBbsOnRadio(availableRadioId);
            }
        }

        /// <summary>
        /// Shows a context menu for selecting a radio when multiple radios are available.
        /// </summary>
        private void ShowRadioSelectionMenu(List<(int DeviceId, string FriendlyName)> availableRadios)
        {
            ContextMenuStrip radioMenu = new ContextMenuStrip();

            foreach (var radio in availableRadios)
            {
                ToolStripMenuItem menuItem = new ToolStripMenuItem(radio.FriendlyName);
                menuItem.Tag = radio.DeviceId;
                menuItem.Click += RadioSelectionMenuItem_Click;
                radioMenu.Items.Add(menuItem);
            }

            // Show the menu below the Activate button
            Point menuLocation = bbsConnectButton.PointToScreen(new Point(0, bbsConnectButton.Height));
            radioMenu.Show(menuLocation);
        }

        /// <summary>
        /// Handles the click event when a radio is selected from the context menu.
        /// </summary>
        private void RadioSelectionMenuItem_Click(object sender, EventArgs e)
        {
            if (sender is ToolStripMenuItem menuItem && menuItem.Tag is int radioId)
            {
                ActivateBbsOnRadio(radioId);
            }
        }

        /// <summary>
        /// Activates BBS on the specified radio using the current channel and region.
        /// </summary>
        private void ActivateBbsOnRadio(int radioId)
        {
            if (radioId <= 0) return;

            // Get the current region from HtStatus
            RadioHtStatus htStatus = broker.GetValue<RadioHtStatus>(radioId, "HtStatus", null);
            int regionId = htStatus?.curr_region ?? 0;

            // Get the current channel from Settings
            RadioSettings settings = broker.GetValue<RadioSettings>(radioId, "Settings", null);
            int channelId = settings?.channel_a ?? 0;

            // Create the BBS instance via BbsHandler
            var createData = new CreateBbsData
            {
                RadioDeviceId = radioId,
                ChannelId = channelId,
                RegionId = regionId
            };
            broker.Dispatch(1, "CreateBbs", createData, store: false);
            broker.LogInfo($"[BbsTab] Activating BBS on radio {radioId} (Region: {regionId}, Channel: {channelId})");
        }

        private void viewTrafficToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;
            // Save setting via broker (device 0 persists to registry)
            broker?.Dispatch(0, "ViewBbsTraffic", viewTrafficToolStripMenuItem.Checked ? 1 : 0);
        }

        private void clearStatsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            ClearStats();
        }

        private void bbsListView_Resize(object sender, EventArgs e)
        {
            if (bbsListView.Columns.Count >= 3)
            {
                bbsListView.Columns[2].Width = bbsListView.Width - bbsListView.Columns[1].Width - bbsListView.Columns[0].Width - 28;
            }
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<BbsTabUserControl>("BBS");
            form.Show();
        }
    }
}
