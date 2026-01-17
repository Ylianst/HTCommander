/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander.Controls
{
    public partial class BbsTabUserControl : UserControl
    {
        private MainForm mainForm;

        public BbsTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;

            // Load settings from registry
            //viewTrafficToolStripMenuItem.Checked = (mainForm.registry.ReadInt("ViewBbsTraffic", 1) == 1);
            bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;
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
            /*
            if (mainForm != null && mainForm.bbs != null)
            {
                mainForm.bbs.ClearStats();
            }
            */
        }

        private void bbsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            bbsTabContextMenuStrip.Show(bbsMenuPictureBox, e.Location);
        }

        private void bbsConnectButton_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            /*
            if (mainForm.activeStationLock != null)
            {
                if (mainForm.activeStationLock.StationType == StationInfoClass.StationTypes.BBS)
                {
                    mainForm.ActiveLockToStation(null);
                }
            }
            else
            {
                StationInfoClass station = new StationInfoClass();
                station.StationType = StationInfoClass.StationTypes.BBS;
                mainForm.ActiveLockToStation(station, mainForm.radio.Settings.channel_a);
            }
            */
        }

        private void viewTrafficToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;
            if (mainForm != null)
            {
                //mainForm.registry.WriteInt("ViewBbsTraffic", viewTrafficToolStripMenuItem.Checked ? 1 : 0);
            }
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
    }
}
