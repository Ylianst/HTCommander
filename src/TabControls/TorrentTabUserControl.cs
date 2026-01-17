/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Windows.Forms;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class TorrentTabUserControl : UserControl
    {
        private MainForm mainForm;
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

        public TorrentTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;

            // Enable double buffering for torrentListView to prevent flickering
            typeof(ListView).InvokeMember("DoubleBuffered",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.SetProperty,
                null, torrentListView, new object[] { true });

            // Load settings from registry
            //showDetailsToolStripMenuItem.Checked = (mainForm.registry.ReadInt("ViewTorrentDetails", 1) == 1);
            torrentSplitContainer.Panel2Collapsed = !showDetailsToolStripMenuItem.Checked;
        }

        public ListView TorrentListView { get { return torrentListView; } }
        public TorrentBlocksUserControl TorrentBlocksControl { get { return torrentBlocksUserControl; } }

        public void UpdateConnectButton(bool isActive)
        {
            torrentConnectButton.Text = isActive ? "&Deactivate" : "&Activate";
        }

        public void SetConnectButtonEnabled(bool enabled)
        {
            torrentConnectButton.Enabled = enabled;
        }

        public void AddTorrent(TorrentFile torrentFile)
        {
            ListViewItem l = new ListViewItem(new string[] { torrentFile.FileName, torrentFile.Mode.ToString(), torrentFile.Description });
            l.ImageIndex = torrentFile.Completed ? 9 : 10;

            string groupName = torrentFile.Callsign;
            if (torrentFile.StationId > 0) groupName += "-" + torrentFile.StationId;
            ListViewGroup group = null;
            foreach (ListViewGroup g in torrentListView.Groups)
            {
                if (g.Header == groupName) { group = g; break; }
            }
            if (group == null)
            {
                group = new ListViewGroup(groupName);
                torrentListView.Groups.Add(group);
            }
            l.Group = group;
            l.Tag = torrentFile;
            torrentFile.ListViewItem = l;
            torrentListView.Items.Add(l);
        }

        public void UpdateTorrent(TorrentFile file)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Action<TorrentFile>(UpdateTorrent), file); return; }

            if (file.ListViewItem != null)
            {
                file.ListViewItem.SubItems[0].Text = (file.FileName == null) ? "" : file.FileName;
                file.ListViewItem.SubItems[1].Text = file.Mode.ToString();
                file.ListViewItem.SubItems[2].Text = (file.Description == null) ? "" : file.Description;
                file.ListViewItem.ImageIndex = file.Completed ? 9 : 10;
                if ((torrentListView.SelectedItems.Count == 1) && (torrentListView.SelectedItems[0] == file.ListViewItem))
                {
                    torrentListView_SelectedIndexChanged(null, null);
                }
            }
            else
            {
                AddTorrent(file);
            }
        }

        private void addTorrentDetailProperty(string name, string value)
        {
            ListViewItem l = new ListViewItem(new string[] { name, value });
            torrentDetailsListView.Items.Add(l);
        }

        private void torrentListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count > 0)
            {
                TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;

                bool hasPaused = false, hasShared = false, hasRequest = false, hasNotError = false, hasCompleted = false, hasNotCompleted = false;
                foreach (ListViewItem l in torrentListView.SelectedItems)
                {
                    TorrentFile xfile = (TorrentFile)l.Tag;
                    if (xfile.Mode == TorrentFile.TorrentModes.Pause) { hasPaused = true; hasNotError = true; }
                    if (xfile.Mode == TorrentFile.TorrentModes.Sharing) { hasShared = true; hasNotError = true; }
                    if (xfile.Mode == TorrentFile.TorrentModes.Request) { hasRequest = true; hasNotError = true; }
                    if (xfile.Completed == true) { hasCompleted = true; }
                    if (xfile.Completed == false) { hasNotCompleted = true; }
                }

                torrentPauseToolStripMenuItem.Visible = true;
                torrentPauseToolStripMenuItem.Checked = hasPaused;
                torrentPauseToolStripMenuItem.Enabled = hasNotError;
                torrentShareToolStripMenuItem.Visible = true;
                torrentShareToolStripMenuItem.Checked = hasShared;
                torrentShareToolStripMenuItem.Enabled = hasCompleted && hasNotError;
                torrentRequestToolStripMenuItem.Visible = true;
                torrentRequestToolStripMenuItem.Checked = hasRequest;
                torrentRequestToolStripMenuItem.Enabled = hasNotCompleted && hasNotError;
                toolStripMenuItem19.Visible = true;
                torrentSaveAsToolStripMenuItem.Visible = true;
                torrentSaveAsToolStripMenuItem.Enabled = hasCompleted && hasNotError && (torrentListView.SelectedItems.Count == 1);
                toolStripMenuItem20.Visible = true;
                torrentDeleteToolStripMenuItem.Visible = true;

                torrentDetailsListView.Items.Clear();
                if (!string.IsNullOrEmpty(file.FileName)) { addTorrentDetailProperty("File name", file.FileName); }
                if (!string.IsNullOrEmpty(file.Description)) { addTorrentDetailProperty("Description", file.Description); }
                if (!string.IsNullOrEmpty(file.Callsign)) { string cs = file.Callsign; if (file.StationId > 0) cs += "-" + file.StationId; addTorrentDetailProperty("Source", cs); }
                if (file.Size != 0) { addTorrentDetailProperty("File Size", file.Size.ToString() + " bytes"); }
                if (file.Compression != TorrentFile.TorrentCompression.Unknown)
                {
                    string comp = file.Compression.ToString();
                    if (file.CompressedSize != 0) { comp += ", " + file.CompressedSize.ToString() + " bytes"; }
                    addTorrentDetailProperty("Compression", comp);
                }
                if (file.TotalBlocks != 0) { addTorrentDetailProperty("Blocks", file.ReceivedBlocks.ToString() + " / " + file.TotalBlocks.ToString()); }
                torrentBlocksUserControl.Blocks = file.Blocks;
            }
            else
            {
                torrentPauseToolStripMenuItem.Visible = false;
                torrentShareToolStripMenuItem.Visible = false;
                torrentRequestToolStripMenuItem.Visible = false;
                toolStripMenuItem19.Visible = false;
                torrentSaveAsToolStripMenuItem.Visible = false;
                toolStripMenuItem20.Visible = false;
                torrentDeleteToolStripMenuItem.Visible = false;
                torrentDetailsListView.Items.Clear();
                torrentBlocksUserControl.Blocks = null;
            }
        }

        private void torrentAddFileButton_Click(object sender, EventArgs e)
        {
            using (AddTorrentFileForm form = new AddTorrentFileForm(mainForm))
            {
                if (form.ShowDialog() == DialogResult.OK)
                {
                    AddTorrent(form.torrentFile);
                    //mainForm.torrent.Add(form.torrentFile);
                    form.torrentFile.WriteTorrentFile();
                }
            }
        }

        private void torrentConnectButton_Click(object sender, EventArgs e)
        {
            /*
            if (mainForm.activeStationLock != null)
            {
                if (mainForm.activeStationLock.StationType == StationInfoClass.StationTypes.Torrent)
                {
                    mainForm.ActiveLockToStation(null);
                }
            }
            else
            {
                StationInfoClass station = new StationInfoClass();
                station.StationType = StationInfoClass.StationTypes.Torrent;
                mainForm.ActiveLockToStation(station, mainForm.radio.Settings.channel_a);
            }
            */
        }

        private void torrentMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            torrentTabContextMenuStrip.Show(torrentMenuPictureBox, e.Location);
        }

        private void showDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            torrentSplitContainer.Panel2Collapsed = !showDetailsToolStripMenuItem.Checked;
            //mainForm.registry.WriteInt("ViewTorrentDetails", showDetailsToolStripMenuItem.Checked ? 1 : 0);
        }

        private void torrentTabContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            showDetailsToolStripMenuItem.Checked = !torrentSplitContainer.Panel2Collapsed;
        }

        private void torrentContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            torrentListView_SelectedIndexChanged(sender, null);
        }

        private void torrentPauseToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in torrentListView.SelectedItems)
            {
                TorrentFile file = (TorrentFile)l.Tag;
                if (file.Mode != TorrentFile.TorrentModes.Error)
                {
                    file.Mode = TorrentFile.TorrentModes.Pause;
                    l.SubItems[1].Text = file.Mode.ToString();
                }
            }
        }

        private void torrentShareToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in torrentListView.SelectedItems)
            {
                TorrentFile file = (TorrentFile)l.Tag;
                if ((file.Mode != TorrentFile.TorrentModes.Error) && (file.Completed == true))
                {
                    file.Mode = TorrentFile.TorrentModes.Sharing;
                    l.SubItems[1].Text = file.Mode.ToString();
                }
            }
        }

        private void torrentRequestToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool sendRequest = false;
            foreach (ListViewItem l in torrentListView.SelectedItems)
            {
                TorrentFile file = (TorrentFile)l.Tag;
                if ((file.Mode != TorrentFile.TorrentModes.Error) && (file.Completed == false) && (file.Mode != TorrentFile.TorrentModes.Sharing))
                {
                    file.Mode = TorrentFile.TorrentModes.Request;
                    l.SubItems[1].Text = file.Mode.ToString();
                    sendRequest = true;
                }
            }
            //if (sendRequest) mainForm.torrent.SendRequest(); // Cause a request frame to be sent
        }

        private void torrentSaveAsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count != 1) return;
            TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;
            if (file.Completed == false) return;
            byte[] filedata = file.GetFileData();
            torrentSaveFileDialog.FileName = file.FileName;
            if (torrentSaveFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                try
                {
                    File.WriteAllBytes(torrentSaveFileDialog.FileName, filedata);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, "Error saving file: " + ex.Message, "Torrent", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void torrentDeleteToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count == 0) return;
            if (MessageBox.Show(this, (torrentListView.SelectedItems.Count == 1) ? "Deleted selected torrent file?" : "Deleted selected torrent files?", "Torrent", MessageBoxButtons.OKCancel, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.OK)
            {
                foreach (ListViewItem l in torrentListView.SelectedItems)
                {
                    TorrentFile file = (TorrentFile)l.Tag;
                    file.DeleteTorrentFile();
                    //mainForm.torrent.Remove(file);
                    torrentListView.Items.Remove(torrentListView.SelectedItems[0]);
                }
                //mainForm.torrent.UpdateAllStations();
            }
        }

        private void torrentListView_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files.Length == 1)
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else
                {
                    e.Effect = DragDropEffects.None;
                }
            }
            else
            {
                e.Effect = DragDropEffects.None;
            }
        }

        private void torrentListView_DragDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files.Length == 1)
                {
                    using (AddTorrentFileForm form = new AddTorrentFileForm(mainForm))
                    {
                        if (form.Import(files[0]))
                        {
                            if (form.ShowDialog() == DialogResult.OK)
                            {
                                AddTorrent(form.torrentFile);
                                //mainForm.torrent.Add(form.torrentFile);
                                form.torrentFile.WriteTorrentFile();
                            }
                        }
                    }
                }
            }
        }

        private void torrentListView_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Delete)
            {
                torrentDeleteToolStripMenuItem_Click(this, null);
                e.Handled = true;
                return;
            }
            e.Handled = false;
        }

        private void torrentListView_Resize(object sender, EventArgs e)
        {
            torrentListView.Columns[2].Width = torrentListView.Width - torrentListView.Columns[1].Width - torrentListView.Columns[0].Width - 28;
        }

        private void torrentDetailsListView_Resize(object sender, EventArgs e)
        {
            torrentDetailsListView.Columns[1].Width = torrentDetailsListView.Width - torrentDetailsListView.Columns[0].Width - 28;
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<TorrentTabUserControl>("Torrent");
            form.Show();
        }
    }
}
