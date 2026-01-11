/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using HTCommander.radio;
using NAudio.Wave;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class RadioAudioClipsForm : Form
    {
        private AudioClipManager clipManager;
        private WaveInEvent waveIn;
        private WaveOutEvent waveOut;
        private WaveFileWriter waveWriter;
        private MemoryStream recordingStream;
        private bool isRecording = false;
        private bool isPlaying = false;
        private Stopwatch recordingTimer;
        private Timer uiTimer;
        private AudioClip currentRecordingClip;
        private List<byte> recordedBytes;
        private Radio radio;
        private RegistryHelper registry;
        private Stopwatch playbackTimer;
        private string currentPlayingClipName;
        private int sortColumn = -1;
        private SortOrder sortOrder = SortOrder.None;

        public RadioAudioClipsForm(Radio radio)
        {
            /*
            InitializeComponent();
            this.radio = radio;
            this.registry = MainForm.g_MainForm.registry;
            clipManager = new AudioClipManager();
            recordingTimer = new Stopwatch();
            playbackTimer = new Stopwatch();
            
            // Enable double buffering for the ListView to reduce flicker
            typeof(Control).GetProperty("DoubleBuffered", 
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)
                .SetValue(clipsListView, true, null);
            
            // UI update timer
            uiTimer = new Timer();
            uiTimer.Interval = 100;
            uiTimer.Tick += UiTimer_Tick;
            */
        }

        private void RadioAudioClipsForm_Load(object sender, EventArgs e)
        {
            // Load existing clips
            clipManager.LoadClips();
            RefreshClipsList();
            UpdateUI();
            
            // Load form position from registry
            LoadFormPosition();
            
            // Resize name column to fill remaining space
            ResizeNameColumn();
        }

        private void ResizeNameColumn()
        {
            // Set name column width to ListView width minus duration column width minus scrollbar width
            int totalWidth = clipsListView.ClientSize.Width;
            int durationWidth = durationColumn.Width;
            nameColumn.Width = totalWidth - durationWidth - 4; // 4 pixels for padding
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            ResizeNameColumn();
        }

        private void RefreshClipsList()
        {
            clipsListView.Items.Clear();
            
            foreach (var clip in clipManager.Clips)
            {
                ListViewItem item = new ListViewItem(clip.Name);
                item.SubItems.Add(clip.GetDurationString());
                item.SubItems.Add(clip.GetFileSizeString());
                item.SubItems.Add(clip.RecordedDate.ToString("MM/dd/yyyy HH:mm"));
                item.Tag = clip;
                clip.ListViewItem = item;
                clipsListView.Items.Add(item);
            }
            
            UpdateStatusLabel();
        }

        private void UpdateStatusLabel()
        {
            if (!isRecording && !isPlaying)
            {
                int count = clipsListView.Items.Count;
                mainToolStripStatusLabel.Text = count == 1 ? "1 clip" : $"{count} clips";
            }
        }

        public void UpdateUI()
        {
            /*
            bool hasSelection = clipsListView.SelectedItems.Count > 0;
            bool canOperate = !isRecording && !isPlaying;
            bool canTransmit = canOperate && hasSelection && radio != null && (radio.State == Radio.RadioState.Connected) && MainForm.g_MainForm.AudioEnabled;
            
            // Update buttons
            recordButton.Enabled = canOperate;
            stopButton.Enabled = isRecording || isPlaying;
            playButton.Enabled = canOperate && hasSelection;
            playRadioButton.Enabled = canTransmit;
            renameButton.Enabled = canOperate && hasSelection;
            deleteButton.Enabled = canOperate && hasSelection;
            
            // Update menu items to match button states
            recordToolStripMenuItem.Enabled = canOperate;
            stopToolStripMenuItem.Enabled = isRecording || isPlaying;
            playToolStripMenuItem.Enabled = canOperate && hasSelection;
            transmitToolStripMenuItem.Enabled = canTransmit;
            duplicateToolStripMenuItem.Enabled = canOperate && hasSelection;
            boostVolumeToolStripMenuItem.Enabled = canOperate && hasSelection;
            renameToolStripMenuItem.Enabled = canOperate && hasSelection;
            deleteToolStripMenuItem.Enabled = canOperate && hasSelection;
            
            if (isRecording)
            {
                recordButton.ForeColor = Color.Red;
                recordButton.Font = new Font(recordButton.Font, FontStyle.Bold);
            }
            else
            {
                recordButton.ForeColor = SystemColors.ControlText;
                recordButton.Font = new Font(recordButton.Font, FontStyle.Bold);
            }
            */
        }

        private void recordButton_Click(object sender, EventArgs e)
        {
            StartRecording();
        }

        private void StartRecording()
        {
            try
            {
                // Create new clip with default name
                string fileName = clipManager.GenerateFileName();
                string clipName = clipManager.GenerateDefaultName();
                
                currentRecordingClip = new AudioClip(clipName, fileName);
                recordedBytes = new List<byte>();
                
                // Initialize audio input (32kHz, 16-bit, Mono)
                waveIn = new WaveInEvent();
                waveIn.DeviceNumber = SettingsForm.GetDefaultInputDeviceNumber();
                waveIn.WaveFormat = new WaveFormat(32000, 16, 1);
                waveIn.DataAvailable += WaveIn_DataAvailable;
                waveIn.RecordingStopped += WaveIn_RecordingStopped;
                
                // Create temp file for recording
                recordingStream = new MemoryStream();
                waveWriter = new WaveFileWriter(recordingStream, waveIn.WaveFormat);
                
                // Start recording
                waveIn.StartRecording();
                isRecording = true;
                recordingTimer.Restart();
                uiTimer.Start();

                mainToolStripStatusLabel.Text = "Recording";
                UpdateUI();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"Failed to start recording: {ex.Message}", "Recording Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                StopRecording();
            }
        }

        private void WaveIn_DataAvailable(object sender, WaveInEventArgs e)
        {
            if (waveWriter != null)
            {
                waveWriter.Write(e.Buffer, 0, e.BytesRecorded);
                
                // Store bytes for waveform generation
                for (int i = 0; i < e.BytesRecorded; i++)
                {
                    recordedBytes.Add(e.Buffer[i]);
                }
            }
        }

        private void WaveIn_RecordingStopped(object sender, StoppedEventArgs e)
        {
            if (e.Exception != null)
            {
                MessageBox.Show(this, $"Recording error: {e.Exception.Message}", "Recording Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void stopButton_Click(object sender, EventArgs e)
        {
            if (isRecording)
            {
                StopRecording();
            }
            else if (isPlaying)
            {
                StopPlayback();
            }
        }

        private void StopRecording()
        {
            try
            {
                uiTimer.Stop();
                recordingTimer.Stop();
                
                if (waveIn != null)
                {
                    waveIn.StopRecording();
                    waveIn.DataAvailable -= WaveIn_DataAvailable;
                    waveIn.RecordingStopped -= WaveIn_RecordingStopped;
                    waveIn.Dispose();
                    waveIn = null;
                }
                
                // Save the recording to file
                if (currentRecordingClip != null && recordingStream != null && waveWriter != null)
                {
                    // Flush the writer but don't dispose yet
                    waveWriter.Flush();
                    
                    // Check if we have valid audio data (more than just WAV header)
                    if (recordingStream.Length > 44)
                    {
                        string filePath = currentRecordingClip.GetFullPath();
                        byte[] audioData = recordingStream.ToArray();
                        File.WriteAllBytes(filePath, audioData);
                    
                        // Update clip metadata
                        FileInfo fileInfo = new FileInfo(filePath);
                        currentRecordingClip.FileSize = fileInfo.Length;
                        currentRecordingClip.Duration = TimeSpan.FromSeconds(recordingTimer.Elapsed.TotalSeconds);
                        
                        // Generate waveform
                        if (recordedBytes.Count > 0)
                        {
                            currentRecordingClip.WaveformData = WaveformGenerator.GenerateWaveformFromRecording(
                                recordedBytes.ToArray(), 
                                new WaveFormat(32000, 16, 1));
                        }
                        
                        // Add to manager
                        clipManager.AddClip(currentRecordingClip);
                        RefreshClipsList();
                        
                        // Select the new clip
                        foreach (ListViewItem item in clipsListView.Items)
                        {
                            if (item.Tag == currentRecordingClip)
                            {
                                item.Selected = true;
                                item.EnsureVisible();
                                break;
                            }
                        }
                    }
                }
                
                // Now dispose the writer and stream
                if (waveWriter != null)
                {
                    waveWriter.Dispose();
                    waveWriter = null;
                }
                
                if (recordingStream != null)
                {
                    recordingStream.Dispose();
                    recordingStream = null;
                }
                
                recordedBytes = null;
                currentRecordingClip = null;
                isRecording = false;
                UpdateStatusLabel();
                UpdateUI();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"Error stopping recording: {ex.Message}", "Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void UiTimer_Tick(object sender, EventArgs e)
        {
            if (isRecording && recordingTimer.IsRunning)
            {
                mainToolStripStatusLabel.Text = "Recording " + recordingTimer.Elapsed.ToString(@"mm\:ss");
            }
            else if (isPlaying && playbackTimer.IsRunning)
            {
                mainToolStripStatusLabel.Text = "Playing " + playbackTimer.Elapsed.ToString(@"mm\:ss");
            }
        }

        private void playButton_Click(object sender, EventArgs e)
        {
            if (clipsListView.SelectedItems.Count > 0)
            {
                AudioClip clip = (AudioClip)clipsListView.SelectedItems[0].Tag;
                PlayClipLocally(clip);
            }
        }

        private void PlayClipLocally(AudioClip clip)
        {
            try
            {
                if (!clip.FileExists())
                {
                    MessageBox.Show(this, "Audio file not found.", "Error", 
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                
                waveOut = new WaveOutEvent();
                waveOut.DeviceNumber = SettingsForm.GetDefaultOutputDeviceNumber();
                
                var reader = new WaveFileReader(clip.GetFullPath());
                waveOut.Init(reader);
                waveOut.PlaybackStopped += (s, ev) =>
                {
                    reader.Dispose();
                    if (waveOut != null) {
                        waveOut.Dispose();
                        waveOut = null;
                    }
                    isPlaying = false;
                    playbackTimer.Stop();
                    uiTimer.Stop();
                    
                    if (InvokeRequired)
                    {
                        Invoke(new Action(() =>
                        {
                            UpdateStatusLabel();
                            UpdateUI();
                        }));
                    }
                    else
                    {
                        UpdateStatusLabel();
                        UpdateUI();
                    }
                };
                
                waveOut.Play();
                isPlaying = true;
                currentPlayingClipName = clip.Name;
                playbackTimer.Restart();
                uiTimer.Start();
                mainToolStripStatusLabel.Text = "Playing 00:00";
                UpdateUI();
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"Playback error: {ex.Message}", "Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                StopPlayback();
            }
        }

        private void StopPlayback()
        {
            if (waveOut != null)
            {
                waveOut.Stop();
                waveOut.Dispose();
                waveOut = null;
            }
            
            isPlaying = false;
            playbackTimer.Stop();
            uiTimer.Stop();
            UpdateStatusLabel();
            UpdateUI();
        }

        private void playRadioButton_Click(object sender, EventArgs e)
        {
            if (clipsListView.SelectedItems.Count > 0)
            {
                AudioClip clip = (AudioClip)clipsListView.SelectedItems[0].Tag;
                PlayClipOverRadio(clip);
            }
        }

        private void PlayClipOverRadio(AudioClip clip)
        {
            if (radio == null || !(radio.State == Radio.RadioState.Connected))
            {
                MessageBox.Show(this, "Not connected to radio.", "Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            
            if (!clip.FileExists())
            {
                MessageBox.Show(this, "Audio file not found.", "Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            
            // Check if confirmation is enabled
            bool shouldConfirm = confirmTransmitToolStripMenuItem.Checked;
            DialogResult result = DialogResult.Yes;
            
            if (shouldConfirm)
            {
                result = MessageBox.Show(this, 
                    $"Transmit '{clip.Name}' over the radio?\n\nDuration: {clip.GetDurationString()}", 
                    "Confirm Transmission", 
                    MessageBoxButtons.YesNo, 
                    MessageBoxIcon.Question);
            }
            
            if (result == DialogResult.Yes)
            {
                try
                {
                    // Start timer for transmission display
                    Stopwatch transmitTimer = new Stopwatch();
                    transmitTimer.Start();
                    Timer transmitUiTimer = new Timer();
                    transmitUiTimer.Interval = 100;
                    transmitUiTimer.Tick += (s, ev) =>
                    {
                        mainToolStripStatusLabel.Text = "Transmitting " + transmitTimer.Elapsed.ToString(@"mm\:ss");
                    };
                    transmitUiTimer.Start();
                    mainToolStripStatusLabel.Text = "Transmitting 00:00";
                    UpdateUI();
                    
                    // Read WAV file and transmit using radio's TransmitVoice method
                    using (var reader = new WaveFileReader(clip.GetFullPath()))
                    {
                        var buffer = new byte[reader.Length];
                        int bytesRead = reader.Read(buffer, 0, buffer.Length);
                        radio.RadioAudio.TransmitVoice(buffer, 0, bytesRead, true);
                    }

                    transmitUiTimer.Stop();
                    transmitUiTimer.Dispose();
                    transmitTimer.Stop();
                    UpdateStatusLabel();
                    UpdateUI();
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, $"Transmission error: {ex.Message}", "Error", 
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    UpdateStatusLabel();
                    UpdateUI();
                }
            }
        }

        private void renameButton_Click(object sender, EventArgs e)
        {
            if (clipsListView.SelectedItems.Count > 0)
            {
                AudioClip clip = (AudioClip)clipsListView.SelectedItems[0].Tag;
                RenameClip(clip);
            }
        }

        private void RenameClip(AudioClip clip)
        {
            using (var dialog = new AudioClipRenameDialog(clip.Name))
            {
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    string newName = dialog.ClipName;
                    
                    if (newName == clip.Name)
                    {
                        return;
                    }
                    
                    if (!clipManager.IsValidClipName(newName, clip))
                    {
                        MessageBox.Show(this, "This name is already in use or contains invalid characters.", "Invalid Name", 
                            MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    
                    if (clipManager.RenameClip(clip, newName))
                    {
                        RefreshClipsList();
                        
                        // Re-select the renamed clip
                        foreach (ListViewItem item in clipsListView.Items)
                        {
                            if (item.Tag == clip)
                            {
                                item.Selected = true;
                                item.EnsureVisible();
                                break;
                            }
                        }
                    }
                }
            }
        }

        private void deleteButton_Click(object sender, EventArgs e)
        {
            if (clipsListView.SelectedItems.Count > 0)
            {
                var selectedClips = new List<AudioClip>();
                foreach (ListViewItem item in clipsListView.SelectedItems)
                {
                    selectedClips.Add((AudioClip)item.Tag);
                }
                
                DeleteClips(selectedClips);
            }
        }

        private void DeleteClips(List<AudioClip> clips)
        {
            string message;
            if (clips.Count == 1)
            {
                message = $"Delete clip '{clips[0].Name}'?";
            }
            else
            {
                message = $"Delete {clips.Count} selected clips?";
            }
            
            DialogResult result = MessageBox.Show(this, message, "Confirm Delete", 
                MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            
            if (result == DialogResult.Yes)
            {
                foreach (var clip in clips)
                {
                    clipManager.RemoveClip(clip, true);
                }
                
                RefreshClipsList();
                UpdateStatusLabel();
                UpdateUI();
            }
        }

        private void clipsListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateUI();
            if (!isRecording && !isPlaying)
            {
                UpdateStatusLabel();
            }
        }

        private void clipsListView_DoubleClick(object sender, EventArgs e)
        {
            if (clipsListView.SelectedItems.Count > 0 && !isRecording && !isPlaying)
            {
                AudioClip clip = (AudioClip)clipsListView.SelectedItems[0].Tag;
                
                // Check if double-click should transmit instead of play
                if (doubleClickTransmitToolStripMenuItem.Checked)
                {
                    PlayClipOverRadio(clip);
                }
                else
                {
                    PlayClipLocally(clip);
                }
            }
        }

        private void clipsListView_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Delete && clipsListView.SelectedItems.Count > 0 && !isRecording && !isPlaying)
            {
                var selectedClips = new List<AudioClip>();
                foreach (ListViewItem item in clipsListView.SelectedItems)
                {
                    selectedClips.Add((AudioClip)item.Tag);
                }
                
                DeleteClips(selectedClips);
                e.Handled = true;
            }
        }

        private void clipsContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            /*
            // Update menu item states to match button states
            bool hasSelection = clipsListView.SelectedItems.Count > 0;
            bool canOperate = !isRecording && !isPlaying;
            bool canTransmit = canOperate && hasSelection && radio != null && (radio.State == Radio.RadioState.Connected) && MainForm.g_MainForm.AudioEnabled;
            
            //recordMenuItem.Enabled = canOperate;
            //stopMenuItem.Enabled = isRecording || isPlaying;
            playMenuItem.Enabled = canOperate && hasSelection;
            playRadioMenuItem.Enabled = canTransmit;
            duplicateMenuItem.Enabled = canOperate && hasSelection;
            boostVolumeMenuItem.Enabled = canOperate && hasSelection;
            renameMenuItem.Enabled = canOperate && hasSelection;
            deleteMenuItem.Enabled = canOperate && hasSelection;
            */
        }

        private void RadioAudioClipsForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            // Stop any ongoing operations
            if (isRecording)
            {
                StopRecording();
            }
            
            if (isPlaying)
            {
                StopPlayback();
            }
            
            // Save form position
            SaveFormPosition();
        }


        #region Registry Settings

        private void LoadFormPosition()
        {
            try
            {
                int? x = registry.ReadInt("AudioClipsFormX", -1);
                int? y = registry.ReadInt("AudioClipsFormY", -1);
                int? width = registry.ReadInt("AudioClipsFormWidth", 784);
                int? height = registry.ReadInt("AudioClipsFormHeight", 561);
                
                if (x >= 0 && y >= 0)
                {
                    this.StartPosition = FormStartPosition.Manual;
                    this.Location = new Point(x.Value, y.Value);
                }
                
                this.Size = new Size(width.Value, height.Value);
            }
            catch { }
        }

        private void SaveFormPosition()
        {
            try
            {
                if (this.WindowState == FormWindowState.Normal)
                {
                    registry.WriteInt("AudioClipsFormX", this.Location.X);
                    registry.WriteInt("AudioClipsFormY", this.Location.Y);
                    registry.WriteInt("AudioClipsFormWidth", this.Size.Width);
                    registry.WriteInt("AudioClipsFormHeight", this.Size.Height);
                }
            }
            catch { }
        }

        #endregion

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void openClipsFolderToolStripMenuItem_Click(object sender, EventArgs e)
        {
            try
            {
                string clipsFolderPath = clipManager.GetClipsFolder();
                
                // Ensure the folder exists before trying to open it
                if (!Directory.Exists(clipsFolderPath))
                {
                    Directory.CreateDirectory(clipsFolderPath);
                }
                
                // Open the folder in Windows Explorer
                Process.Start("explorer.exe", clipsFolderPath);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"Failed to open clips folder: {ex.Message}", "Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void clipsListView_ColumnClick(object sender, ColumnClickEventArgs e)
        {
            // Determine if the clicked column is already the sort column
            if (e.Column == sortColumn)
            {
                // Reverse the current sort direction for this column
                if (sortOrder == SortOrder.Ascending)
                {
                    sortOrder = SortOrder.Descending;
                }
                else
                {
                    sortOrder = SortOrder.Ascending;
                }
            }
            else
            {
                // Set the column number that is to be sorted; default to ascending
                sortColumn = e.Column;
                sortOrder = SortOrder.Ascending;
            }

            // Set the ListViewItemSorter property to a new AudioClipComparer
            clipsListView.ListViewItemSorter = new AudioClipComparer(sortColumn, sortOrder);
            
            // Sort the list
            clipsListView.Sort();
        }

        private void duplicateMenuItem_Click(object sender, EventArgs e)
        {
            if (clipsListView.SelectedItems.Count > 0)
            {
                AudioClip originalClip = (AudioClip)clipsListView.SelectedItems[0].Tag;
                DuplicateClip(originalClip);
            }
        }

        private void DuplicateClip(AudioClip originalClip)
        {
            try
            {
                if (!originalClip.FileExists())
                {
                    MessageBox.Show(this, "Original clip file not found.", "Error", 
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }

                // Generate new file name
                string newFileName = clipManager.GenerateFileName();
                string newClipName = "Copy of " + originalClip.Name;

                // Create new clip object
                AudioClip newClip = new AudioClip(newClipName, newFileName);
                newClip.Duration = originalClip.Duration;
                newClip.RecordedDate = DateTime.Now;
                newClip.WaveformData = originalClip.WaveformData != null ? (float[])originalClip.WaveformData.Clone() : new float[0];

                // Copy the WAV file
                string sourcePath = originalClip.GetFullPath();
                string destPath = newClip.GetFullPath();
                File.Copy(sourcePath, destPath);

                // Update file size
                FileInfo fileInfo = new FileInfo(destPath);
                newClip.FileSize = fileInfo.Length;

                // Add to manager
                clipManager.AddClip(newClip);
                RefreshClipsList();

                // Select the new clip
                foreach (ListViewItem item in clipsListView.Items)
                {
                    if (item.Tag == newClip)
                    {
                        item.Selected = true;
                        item.EnsureVisible();
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"Failed to duplicate clip: {ex.Message}", "Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void boostVolumeMenuItem_Click(object sender, EventArgs e)
        {
            if (clipsListView.SelectedItems.Count > 0)
            {
                AudioClip clip = (AudioClip)clipsListView.SelectedItems[0].Tag;
                BoostClipVolume(clip);
            }
        }

        private void BoostClipVolume(AudioClip clip)
        {
            DialogResult result = MessageBox.Show(this, 
                $"Boost volume of '{clip.Name}' to 90% of maximum?\n\nThis will modify the audio file.", 
                "Confirm Volume Boost", 
                MessageBoxButtons.YesNo, 
                MessageBoxIcon.Question);

            if (result != DialogResult.Yes)
                return;

            try
            {
                if (!clip.FileExists())
                {
                    MessageBox.Show(this, "Audio file not found.", "Error", 
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }

                string filePath = clip.GetFullPath();
                
                // Read the entire WAV file into memory
                byte[] buffer = File.ReadAllBytes(filePath);

                // Find the maximum amplitude (assuming 16-bit PCM)
                int headerSize = 44; // Standard WAV header size
                short maxAmplitude = 0;

                for (int i = headerSize; i < buffer.Length - 1; i += 2)
                {
                    short sample = BitConverter.ToInt16(buffer, i);
                    if (Math.Abs(sample) > Math.Abs(maxAmplitude))
                    {
                        maxAmplitude = sample;
                    }
                }

                if (maxAmplitude == 0)
                {
                    MessageBox.Show(this, "Clip appears to be silent.", "Error", 
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // Calculate boost factor to reach 90% of maximum (32767 for 16-bit)
                double targetAmplitude = 32767 * 0.9;
                double boostFactor = targetAmplitude / Math.Abs(maxAmplitude);

                // Apply boost to all samples
                for (int i = headerSize; i < buffer.Length - 1; i += 2)
                {
                    short sample = BitConverter.ToInt16(buffer, i);
                    int boostedSample = (int)(sample * boostFactor);
                    
                    // Clamp to prevent clipping
                    if (boostedSample > 32767) boostedSample = 32767;
                    if (boostedSample < -32768) boostedSample = -32768;
                    
                    byte[] sampleBytes = BitConverter.GetBytes((short)boostedSample);
                    buffer[i] = sampleBytes[0];
                    buffer[i + 1] = sampleBytes[1];
                }

                // Write the modified buffer back to the file (file is not open anymore)
                File.WriteAllBytes(filePath, buffer);

                // Regenerate waveform data by reading the file we just wrote
                using (var reader = new WaveFileReader(filePath))
                {
                    byte[] audioData = new byte[reader.Length];
                    reader.Read(audioData, 0, audioData.Length);
                    clip.WaveformData = WaveformGenerator.GenerateWaveformFromRecording(
                        audioData, 
                        reader.WaveFormat);
                }

                clipManager.SaveClips();
                RefreshClipsList();

                // Reselect the clip
                foreach (ListViewItem item in clipsListView.Items)
                {
                    if (item.Tag == clip)
                    {
                        item.Selected = true;
                        item.EnsureVisible();
                        break;
                    }
                }

                MessageBox.Show(this, "Volume boost applied successfully.", "Success", 
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, $"Failed to boost volume: {ex.Message}", "Error", 
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    /// <summary>
    /// Custom comparer for sorting ListView items by AudioClip properties
    /// </summary>
    public class AudioClipComparer : System.Collections.IComparer
    {
        private int columnIndex;
        private SortOrder sortOrder;

        public AudioClipComparer(int column, SortOrder order)
        {
            columnIndex = column;
            sortOrder = order;
        }

        public int Compare(object x, object y)
        {
            ListViewItem itemX = x as ListViewItem;
            ListViewItem itemY = y as ListViewItem;

            if (itemX == null || itemY == null)
                return 0;

            AudioClip clipX = itemX.Tag as AudioClip;
            AudioClip clipY = itemY.Tag as AudioClip;

            if (clipX == null || clipY == null)
                return 0;

            int result = 0;

            switch (columnIndex)
            {
                case 0: // Name column
                    result = string.Compare(clipX.Name, clipY.Name, StringComparison.OrdinalIgnoreCase);
                    break;
                case 1: // Duration column
                    result = clipX.Duration.CompareTo(clipY.Duration);
                    break;
                default:
                    result = 0;
                    break;
            }

            // Apply sort order
            if (sortOrder == SortOrder.Descending)
                result = -result;

            return result;
        }
    }
}
