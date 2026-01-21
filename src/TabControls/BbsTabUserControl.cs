/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text;
using System.Drawing;
using System.Windows.Forms;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class BbsTabUserControl : UserControl
    {
        private DataBrokerClient broker;
        private bool _showDetach = false;

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

            // Subscribe to BBS events from the broker
            broker.Subscribe(0, new[] { "BbsStatsUpdated", "BbsStatsCleared", "BbsTraffic", "BbsControlMessage", "BbsError" }, OnBbsEvent);

            // Load settings from broker (device 0 for app settings)
            bool viewTraffic = broker.GetValue<int>(0, "ViewBbsTraffic", 1) == 1;
            viewTrafficToolStripMenuItem.Checked = viewTraffic;
            bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;
        }

        /// <summary>
        /// Handles BBS events from the DataBroker.
        /// </summary>
        private void OnBbsEvent(int deviceId, string name, object data)
        {
            switch (name)
            {
                case "BbsStatsUpdated":
                    HandleStatsUpdated(data);
                    break;
                case "BbsStatsCleared":
                    HandleStatsCleared(data);
                    break;
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
        /// Handles BbsStatsUpdated events.
        /// </summary>
        private void HandleStatsUpdated(object data)
        {
            // Extract stats from the anonymous type
            if (data == null) return;
            var dataType = data.GetType();
            var statsProp = dataType.GetProperty("Stats");
            if (statsProp == null) return;
            var stats = statsProp.GetValue(data) as BBS.StationStats;
            if (stats != null)
            {
                UpdateBbsStats(stats);
            }
        }

        /// <summary>
        /// Handles BbsStatsCleared events.
        /// </summary>
        private void HandleStatsCleared(object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<object>(HandleStatsCleared), data);
                return;
            }
            bbsListView.Items.Clear();
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

        public void UpdateBbsStats(BBS.StationStats stats)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<BBS.StationStats>(UpdateBbsStats), stats);
                return;
            }

            ListViewItem l;
            if (stats.listViewItem == null)
            {
                l = new ListViewItem(new string[] { stats.callsign, "", "" });
                l.ImageIndex = 7;
                bbsListView.Items.Add(l);
                stats.listViewItem = l;
            }
            else
            {
                l = stats.listViewItem;
            }
            l.SubItems[1].Text = stats.lastseen.ToString();
            StringBuilder sb = new StringBuilder();
            sb.Append($"{stats.protocol}, {stats.packetsIn} in / {stats.packetsOut} out, {stats.bytesIn} in / {stats.bytesOut} out");
            l.SubItems[2].Text = sb.ToString();
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
            // Request stats clear via broker
            broker?.Dispatch(0, "BbsClearStatsRequest", null, store: false);
        }

        private void bbsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            bbsTabContextMenuStrip.Show(bbsMenuPictureBox, e.Location);
        }

        private void bbsConnectButton_Click(object sender, EventArgs e)
        {
            // TODO: Implement BBS connection via broker
            // Request to lock to BBS station type
            broker?.Dispatch(0, "BbsConnectRequest", null, store: false);
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
