/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using System.Collections.Generic;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class TorrentTabUserControl : UserControl
    {
        private DataBrokerClient broker;
        private bool _showDetach = false;
        private Dictionary<string, TorrentFile> fileCache = new Dictionary<string, TorrentFile>();
        private List<int> connectedRadios = new List<int>();
        private Dictionary<int, RadioLockState> lockStates = new Dictionary<int, RadioLockState>();

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

            broker = new DataBrokerClient();
            
            // Subscribe to torrent state updates
            broker.Subscribe(0, "TorrentFiles", OnTorrentFilesUpdate);
            broker.Subscribe(0, "TorrentFileUpdate", OnTorrentFileUpdate);
            broker.Subscribe(0, "TorrentStations", OnTorrentStationsUpdate);
            broker.Subscribe(0, "TorrentStationUpdate", OnTorrentStationUpdate);
            
            // Subscribe to connected radios and lock state to update activate button
            broker.Subscribe(0, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);

            // Enable double buffering for ListViews to prevent flickering
            typeof(ListView).InvokeMember("DoubleBuffered",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.SetProperty,
                null, torrentListView, new object[] { true });
            typeof(ListView).InvokeMember("DoubleBuffered",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.SetProperty,
                null, torrentDetailsListView, new object[] { true });

            // Load ShowDetails state from DataBroker
            bool showDetails = DataBroker.GetValue<bool>(0, "TorrentShowDetails", true);
            showDetailsToolStripMenuItem.Checked = showDetails;
            torrentSplitContainer.Panel2Collapsed = !showDetails;
            
            // Request initial state
            broker.Dispatch(0, "TorrentGetFiles", null, store: false);
            broker.Dispatch(0, "TorrentGetStations", null, store: false);
            
            // Set initial button state (disabled until we know radio state)
            torrentConnectButton.Text = "&Activate";
            torrentConnectButton.Enabled = false;
            
            broker.LogInfo("[TorrentTab] Torrent tab initialized");

        }

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
            
            if (data is List<int> radioList)
            {
                connectedRadios.AddRange(radioList);
            }
            else if (data is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item is int id)
                    {
                        connectedRadios.Add(id);
                    }
                    else
                    {
                        connectedRadios.Add(Convert.ToInt32(item));
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
            // Handle single radio case
            if (connectedRadios.Count == 1)
            {
                int radioId = connectedRadios[0];
                lockStates.TryGetValue(radioId, out RadioLockState lockState);
                
                if (lockState != null && lockState.IsLocked && lockState.Usage == "Torrent")
                {
                    // Radio is locked to Torrent - show Deactivate
                    torrentConnectButton.Text = "&Deactivate";
                    torrentConnectButton.Enabled = true;
                }
                else if (lockState == null || !lockState.IsLocked)
                {
                    // Radio is not locked - show Activate
                    torrentConnectButton.Text = "&Activate";
                    torrentConnectButton.Enabled = true;
                }
                else
                {
                    // Radio is locked to something else - disable
                    torrentConnectButton.Text = "&Activate";
                    torrentConnectButton.Enabled = false;
                }
            }
            // TODO: Handle multi-radio cases
            else if (connectedRadios.Count > 1)
            {
                // For now, disable the button for multi-radio
                torrentConnectButton.Text = "&Activate";
                torrentConnectButton.Enabled = false;
            }
            else
            {
                // No radios connected - disable
                torrentConnectButton.Text = "&Activate";
                torrentConnectButton.Enabled = false;
            }
        }

        private void OnTorrentFilesUpdate(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            var filesList = data as System.Collections.IEnumerable;
            if (filesList == null) return;
            
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ProcessFilesUpdate(filesList)));
            }
            else
            {
                ProcessFilesUpdate(filesList);
            }
        }

        private void ProcessFilesUpdate(System.Collections.IEnumerable filesList)
        {
            var newCache = new Dictionary<string, TorrentFile>();
            
            foreach (var item in filesList)
            {
                var fileData = CreateTorrentFileFromData(item);
                if (fileData == null) continue;
                
                string key = GetFileKey(fileData);
                newCache[key] = fileData;
                
                if (fileCache.ContainsKey(key))
                {
                    // Update existing
                    UpdateTorrent(fileData);
                }
                else
                {
                    // Add new
                    AddTorrent(fileData);
                }
            }
            
            // Remove items no longer in the list
            var keysToRemove = fileCache.Keys.Except(newCache.Keys).ToList();
            foreach (var key in keysToRemove)
            {
                RemoveTorrentFromUI(fileCache[key]);
            }
            
            fileCache = newCache;
        }

        private void OnTorrentFileUpdate(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            var fileData = CreateTorrentFileFromData(data);
            if (fileData == null) return;
            
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => UpdateTorrent(fileData)));
            }
            else
            {
                UpdateTorrent(fileData);
            }
        }

        private void OnTorrentStationsUpdate(int deviceId, string name, object data)
        {
            // Stations are tracked separately but displayed in the same UI
            // You could add a separate group or visual indicator for stations
        }

        private void OnTorrentStationUpdate(int deviceId, string name, object data)
        {
            // Handle individual station updates
        }

        private TorrentFile CreateTorrentFileFromData(object data)
        {
            if (data == null) return null;
            
            try
            {
                var dataType = data.GetType();
                
                var file = new TorrentFile();
                file.Id = dataType.GetProperty("Id")?.GetValue(data) as byte[];
                file.Callsign = dataType.GetProperty("Callsign")?.GetValue(data) as string;
                file.StationId = Convert.ToInt32(dataType.GetProperty("StationId")?.GetValue(data) ?? 0);
                file.FileName = dataType.GetProperty("FileName")?.GetValue(data) as string;
                file.Description = dataType.GetProperty("Description")?.GetValue(data) as string;
                file.Size = Convert.ToInt32(dataType.GetProperty("Size")?.GetValue(data) ?? 0);
                file.CompressedSize = Convert.ToInt32(dataType.GetProperty("CompressedSize")?.GetValue(data) ?? 0);
                
                string compressionStr = dataType.GetProperty("Compression")?.GetValue(data) as string;
                if (!string.IsNullOrEmpty(compressionStr))
                {
                    Enum.TryParse(compressionStr, out TorrentFile.TorrentCompression compression);
                    file.Compression = compression;
                }
                
                string modeStr = dataType.GetProperty("Mode")?.GetValue(data) as string;
                if (!string.IsNullOrEmpty(modeStr))
                {
                    Enum.TryParse(modeStr, out TorrentFile.TorrentModes mode);
                    file.Mode = mode;
                }
                
                file.Completed = Convert.ToBoolean(dataType.GetProperty("Completed")?.GetValue(data) ?? false);
                
                int totalBlocks = Convert.ToInt32(dataType.GetProperty("TotalBlocks")?.GetValue(data) ?? 0);
                int receivedBlocks = Convert.ToInt32(dataType.GetProperty("ReceivedBlocks")?.GetValue(data) ?? 0);
                
                if (totalBlocks > 0)
                {
                    file.Blocks = new byte[totalBlocks][];
                    // Set placeholder data for received blocks so ReceivedBlocks property works correctly
                    // For a file with all blocks, set all to non-null; otherwise set first N blocks
                    for (int i = 0; i < receivedBlocks && i < totalBlocks; i++)
                    {
                        file.Blocks[i] = new byte[0]; // Placeholder - actual data not available in UI
                    }
                }
                
                return file;
            }
            catch (Exception ex)
            {
                broker.LogError($"[TorrentTab] Error creating torrent file from data: {ex.Message}");
                return null;
            }
        }

        private string GetFileKey(TorrentFile file)
        {
            if (file.Id != null && file.Id.Length > 0)
            {
                return Utils.BytesToHex(file.Id);
            }
            return $"{file.Callsign}-{file.StationId}-{file.FileName}";
        }

        private void RemoveTorrentFromUI(TorrentFile file)
        {
            if (file.ListViewItem != null && torrentListView.Items.Contains(file.ListViewItem))
            {
                torrentListView.Items.Remove(file.ListViewItem);
                file.ListViewItem = null;
            }
        }

        public void UpdateConnectButton(bool isActive)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<bool>(UpdateConnectButton), isActive);
                return;
            }
            
            torrentConnectButton.Text = isActive ? "&Deactivate" : "&Activate";
        }

        public void SetConnectButtonEnabled(bool enabled)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<bool>(SetConnectButtonEnabled), enabled);
                return;
            }
            
            torrentConnectButton.Enabled = enabled;
        }

        public void AddTorrent(TorrentFile torrentFile)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<TorrentFile>(AddTorrent), torrentFile);
                return;
            }
            
            ListViewItem l = new ListViewItem(new string[] { 
                torrentFile.FileName ?? "", 
                torrentFile.Mode.ToString(), 
                torrentFile.Description ?? "" 
            });
            l.ImageIndex = torrentFile.Completed ? 9 : 10;

            string groupName = torrentFile.Callsign ?? "Unknown";
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
            if (this.InvokeRequired) 
            { 
                this.BeginInvoke(new Action<TorrentFile>(UpdateTorrent), file); 
                return; 
            }

            string key = GetFileKey(file);
            
            // Check if we already have this file in the cache
            if (fileCache.TryGetValue(key, out TorrentFile existingFile) && existingFile.ListViewItem != null && torrentListView.Items.Contains(existingFile.ListViewItem))
            {
                // Update existing ListViewItem
                existingFile.ListViewItem.SubItems[0].Text = file.FileName ?? "";
                existingFile.ListViewItem.SubItems[1].Text = file.Mode.ToString();
                existingFile.ListViewItem.SubItems[2].Text = file.Description ?? "";
                existingFile.ListViewItem.ImageIndex = file.Completed ? 9 : 10;
                
                // Transfer the ListViewItem reference to the new file object
                file.ListViewItem = existingFile.ListViewItem;
                file.ListViewItem.Tag = file;
                
                // Update cache with new file data
                fileCache[key] = file;
                
                if ((torrentListView.SelectedItems.Count == 1) && (torrentListView.SelectedItems[0] == file.ListViewItem))
                {
                    torrentListView_SelectedIndexChanged(null, null);
                }
            }
            else
            {
                // Add new item
                fileCache[key] = file;
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
            using (AddTorrentFileForm form = new AddTorrentFileForm(null))
            {
                if (form.ShowDialog() == DialogResult.OK)
                {
                    // Send add command to DataBroker
                    broker.Dispatch(0, "TorrentAddFile", form.torrentFile, store: false);
                    form.torrentFile.WriteTorrentFile();
                }
            }
        }

        private void torrentConnectButton_Click(object sender, EventArgs e)
        {
            // Handle single radio case
            if (connectedRadios.Count == 1)
            {
                int radioId = connectedRadios[0];
                lockStates.TryGetValue(radioId, out RadioLockState lockState);
                
                if (lockState != null && lockState.IsLocked && lockState.Usage == "Torrent")
                {
                    // Deactivate - unlock the radio
                    broker.Dispatch(radioId, "SetUnlock", null, store: false);
                }
                else if (lockState == null || !lockState.IsLocked)
                {
                    // Activate - lock the radio to Torrent usage
                    broker.Dispatch(radioId, "SetLock", "Torrent", store: false);
                }
            }
            // TODO: Handle multi-radio cases
            else if (connectedRadios.Count > 1)
            {
                MessageBox.Show(this, "Multi-radio torrent mode is not yet supported.", "Torrent", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show(this, "No radios connected. Connect a radio first.", "Torrent", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void torrentMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            torrentTabContextMenuStrip.Show(torrentMenuPictureBox, e.Location);
        }

        private void showDetailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            torrentSplitContainer.Panel2Collapsed = !showDetailsToolStripMenuItem.Checked;
            
            // Save the state to DataBroker for persistence
            broker.Dispatch(0, "TorrentShowDetails", showDetailsToolStripMenuItem.Checked, store: true);
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
                if (file.Mode != TorrentFile.TorrentModes.Error && file.Id != null)
                {
                    // Send mode change to DataBroker
                    broker.Dispatch(0, "TorrentSetFileMode", new { 
                        FileId = file.Id, 
                        Mode = TorrentFile.TorrentModes.Pause 
                    }, store: false);
                }
            }
        }

        private void torrentShareToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in torrentListView.SelectedItems)
            {
                TorrentFile file = (TorrentFile)l.Tag;
                if ((file.Mode != TorrentFile.TorrentModes.Error) && (file.Completed == true) && file.Id != null)
                {
                    // Send mode change to DataBroker
                    broker.Dispatch(0, "TorrentSetFileMode", new { 
                        FileId = file.Id, 
                        Mode = TorrentFile.TorrentModes.Sharing 
                    }, store: false);
                }
            }
        }

        private void torrentRequestToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in torrentListView.SelectedItems)
            {
                TorrentFile file = (TorrentFile)l.Tag;
                if ((file.Mode != TorrentFile.TorrentModes.Error) && (file.Completed == false) && 
                    (file.Mode != TorrentFile.TorrentModes.Sharing) && file.Id != null)
                {
                    // Send mode change to DataBroker
                    broker.Dispatch(0, "TorrentSetFileMode", new { 
                        FileId = file.Id, 
                        Mode = TorrentFile.TorrentModes.Request 
                    }, store: false);
                }
            }
        }

        private void torrentSaveAsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count != 1) return;
            TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;
            if (file.Completed == false) return;
            
            // Note: GetFileData requires actual block data which we don't have in the UI
            // This would need to be requested from the Torrent handler
            byte[] filedata = file.GetFileData();
            if (filedata == null)
            {
                MessageBox.Show(this, "File data not available. The file may not be fully downloaded.", "Torrent", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            
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
            if (MessageBox.Show(this, (torrentListView.SelectedItems.Count == 1) ? "Delete selected torrent file?" : "Delete selected torrent files?", "Torrent", MessageBoxButtons.OKCancel, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.OK)
            {
                foreach (ListViewItem l in torrentListView.SelectedItems)
                {
                    TorrentFile file = (TorrentFile)l.Tag;
                    file.DeleteTorrentFile();
                    
                    // Send remove command to DataBroker
                    broker.Dispatch(0, "TorrentRemoveFile", file, store: false);
                }
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
                    using (AddTorrentFileForm form = new AddTorrentFileForm(null))
                    {
                        if (form.Import(files[0]))
                        {
                            if (form.ShowDialog() == DialogResult.OK)
                            {
                                // Send add command to DataBroker
                                broker.Dispatch(0, "TorrentAddFile", form.torrentFile, store: false);
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
