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

using System;
using System.Drawing;
using System.Windows.Forms;
using HTCommander.radio;
using NAudio.Wave;

namespace HTCommander.RadioControls
{
    public partial class RadioPanelControl : UserControl
    {
        private MainForm parent;
        private RadioChannelControl[] channelControls = null;
        private int vfo2LastChannelId = -1;

        public RadioPanelControl()
        {
            InitializeComponent();
        }

        public RadioPanelControl(MainForm mainForm) : this()
        {
            Initialize(mainForm);
        }

        public void Initialize(MainForm mainForm)
        {
            this.parent = mainForm;
            //this.CheckBluetoothRequested += (s, e) => mainForm?.CheckBluetooth();
        }

        public RadioChannelControl[] ChannelControls
        {
            get { return channelControls; }
            set { channelControls = value; }
        }

        public int Vfo2LastChannelId
        {
            get { return vfo2LastChannelId; }
            set { vfo2LastChannelId = value; }
        }

        public bool ConnectButtonVisible
        {
            get { return connectButton.Visible; }
            set { connectButton.Visible = value; }
        }

        public bool CheckBluetoothButtonVisible
        {
            get { return checkBluetoothButton.Visible; }
            set { checkBluetoothButton.Visible = value; }
        }

        public string RadioStateText
        {
            get { return radioStateLabel.Text; }
            set { radioStateLabel.Text = value; }
        }

        public bool RadioStateLabelVisible
        {
            get { return radioStateLabel.Visible; }
            set { radioStateLabel.Visible = value; }
        }

        public bool ConnectedPanelVisible
        {
            get { return connectedPanel.Visible; }
            set { connectedPanel.Visible = value; }
        }

        public bool TransmitBarVisible
        {
            get { return transmitBarPanel.Visible; }
            set { transmitBarPanel.Visible = value; }
        }

        public bool RssiProgressBarVisible
        {
            get { return rssiProgressBar.Visible; }
            set { rssiProgressBar.Visible = value; }
        }

        public int RssiValue
        {
            get { return rssiProgressBar.Value; }
            set { rssiProgressBar.Value = value; }
        }

        public bool VoiceProcessingVisible
        {
            get { return voiceProcessingLabel.Visible; }
            set { voiceProcessingLabel.Visible = value; }
        }

        public string GpsStatusText
        {
            get { return gpsStatusLabel.Text; }
            set { gpsStatusLabel.Text = value; }
        }

        public void SetRadioImage(int radioType)
        {
            radioPictureBox.Visible = (radioType == 0);
            radio2PictureBox.Visible = (radioType == 1);
        }

        public void ClearChannels()
        {
            channelsFlowLayoutPanel.Controls.Clear();
        }

        public void UpdateChannelsPanel()
        {
            /*
            if (parent == null || parent.radio == null) return;
            
            channelsFlowLayoutPanel.SuspendLayout();
            int visibleChannels = 0;
            int channelHeight = 0;
            if ((channelControls != null) && (parent.radio.Channels != null))
            {
                for (int i = 0; i < channelControls.Length; i++)
                {
                    if (parent.radio.Channels[i] != null)
                    {
                        if (channelControls[i] == null)
                        {
                            channelControls[i] = new RadioChannelControl(parent);
                            channelsFlowLayoutPanel.Controls.Add(channelControls[i]);
                        }
                        channelControls[i].Channel = parent.radio.Channels[i];
                        channelControls[i].Tag = i;
                        bool visible = parent.showAllChannels || (parent.radio.Channels[i].name_str.Length > 0) || (parent.radio.Channels[i].rx_freq != 0);
                        channelControls[i].Visible = visible;
                        if (visible) { visibleChannels++; }
                        channelHeight = channelControls[i].Height;
                    }
                }
                int hBlockCount = ((visibleChannels / 3) + (((visibleChannels % 3) != 0) ? 1 : 0));
                int blockHeight = 0;
                if (hBlockCount > 0)
                {
                    blockHeight = (this.Height - 310) / hBlockCount;
                    if (blockHeight > 50) { blockHeight = 50; }
                    for (int i = 0; i < channelControls.Length; i++)
                    {
                        if (channelControls[i] != null) { channelControls[i].Height = blockHeight; }
                    }
                }
                channelsFlowLayoutPanel.Height = blockHeight * hBlockCount;
            }
            channelsFlowLayoutPanel.Visible = (visibleChannels > 0);
            channelsFlowLayoutPanel.ResumeLayout();
            */
        }

        public void UpdateRadioDisplay()
        {
            /*
            if (parent == null || parent.radio == null) return;
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.BeginInvoke(new Action(UpdateRadioDisplay)); return; }
            
            if (parent.radio.Settings == null) return;

            if (parent.radio.Channels != null)
            {
                RadioChannelInfo channelA = null;
                RadioChannelInfo channelB = null;

                if ((parent.radio.Settings.channel_a >= 0) && (parent.radio.Settings.channel_a < parent.radio.Channels.Length))
                {
                    channelA = parent.radio.Channels[parent.radio.Settings.channel_a];
                }
                if ((parent.radio.Settings.channel_b >= 0) && (parent.radio.Settings.channel_b < parent.radio.Channels.Length))
                {
                    channelB = parent.radio.Channels[parent.radio.Settings.channel_b];
                }

                if (channelControls != null)
                {
                    foreach (RadioChannelControl c in channelControls)
                    {
                        if (c == null) continue;
                        if ((channelA != null) && (((int)c.Tag) == channelA.channel_id))
                        {
                            c.BackColor = Color.PaleGoldenrod;
                        }
                        else if ((channelB != null) && (parent.radio.Settings.double_channel == 1) && (((int)c.Tag) == channelB.channel_id))
                        {
                            c.BackColor = Color.PaleGoldenrod;
                        }
                        else
                        {
                            c.BackColor = Color.DarkKhaki;
                        }
                    }
                }

                if (channelA != null)
                {
                    if (channelA.name_str.Length > 0)
                    {
                        vfo1Label.Text = channelA.name_str;
                        vfo1FreqLabel.Text = (((float)channelA.rx_freq) / 1000000).ToString("F3") + " MHz";
                    }
                    else if (channelA.rx_freq > 0)
                    {
                        vfo1Label.Text = ((double)channelA.rx_freq / 1000000).ToString("F3");
                        vfo1FreqLabel.Text = " MHz";
                    }
                    else
                    {
                        vfo1Label.Text = "Empty";
                        vfo1FreqLabel.Text = "";
                    }
                    if (parent.activeStationLock == null)
                    {
                        vfo1StatusLabel.Text = "";
                    }
                    else
                    {
                        if (parent.activeStationLock.StationType == StationInfoClass.StationTypes.Terminal) { vfo1StatusLabel.Text = "Terminal"; }
                        else if (parent.activeStationLock.StationType == StationInfoClass.StationTypes.Winlink) { vfo1StatusLabel.Text = "WinLink"; }
                        else if (parent.activeStationLock.StationType == StationInfoClass.StationTypes.BBS) { vfo1StatusLabel.Text = "BBS"; }
                        else if (parent.activeStationLock.StationType == StationInfoClass.StationTypes.Torrent) { vfo1StatusLabel.Text = "Torrent"; }
                        else if (parent.activeStationLock.StationType == StationInfoClass.StationTypes.AGWPE) { vfo1StatusLabel.Text = "AGWPE"; }
                    }
                }
                else
                {
                    vfo1Label.Text = "";
                    vfo1FreqLabel.Text = "";
                    vfo1StatusLabel.Text = "";
                }
                if (parent.radio.Settings.scan == true)
                {
                    if ((parent.radio.HtStatus != null) && (parent.radio.Channels != null) && (parent.radio.Channels.Length > parent.radio.HtStatus.curr_ch_id) && (parent.radio.Channels[parent.radio.HtStatus.curr_ch_id] != null))
                    {
                        if (parent.radio.Channels[parent.radio.HtStatus.curr_ch_id] == channelA)
                        {
                            if (vfo2LastChannelId >= 0)
                            {
                                channelB = parent.radio.Channels[vfo2LastChannelId];
                                vfo2Label.Text = channelB.name_str;
                                vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                                vfo2StatusLabel.Text = "Scanning...";
                            }
                            else
                            {
                                vfo2Label.Text = "Scanning...";
                                vfo2FreqLabel.Text = "";
                                vfo2StatusLabel.Text = "";
                            }
                        }
                        else
                        {
                            channelB = parent.radio.Channels[parent.radio.HtStatus.curr_ch_id];
                            vfo2Label.Text = channelB.name_str;
                            vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                            vfo2StatusLabel.Text = "Scanning...";
                            vfo2LastChannelId = parent.radio.HtStatus.curr_ch_id;
                        }
                    }
                    else
                    {
                        vfo2Label.Text = "Scanning...";
                        vfo2FreqLabel.Text = "";
                        vfo2StatusLabel.Text = "";
                    }
                }
                else if ((parent.radio.Settings.double_channel == 1) && (channelB != null))
                {
                    if (channelB.name_str.Length > 0)
                    {
                        vfo2Label.Text = channelB.name_str;
                        vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                    }
                    else if (channelB.rx_freq != 0)
                    {
                        vfo2Label.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3");
                        vfo2FreqLabel.Text = " MHz";
                    }
                    else
                    {
                        vfo2Label.Text = "Empty";
                        vfo2FreqLabel.Text = "";
                    }
                    vfo2StatusLabel.Text = "";
                }
                else
                {
                    vfo2Label.Text = "";
                    vfo2FreqLabel.Text = "";
                    vfo2StatusLabel.Text = "";
                }
                connectedPanel.Visible = true;

                // Update the colors
                if ((channelB != null) && (parent.radio.State == Radio.RadioState.Connected) && (parent.radio.HtStatus != null) && (parent.radio.HtStatus.double_channel == Radio.RadioChannelType.A))
                {
                    if ((parent.radio.HtStatus.is_in_rx || parent.radio.HtStatus.is_in_tx) && (parent.radio.HtStatus.curr_ch_id == channelB.channel_id))
                    {
                        vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                        vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.FromArgb(221, 211, 0);
                    }
                    else
                    {
                        vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.FromArgb(221, 211, 0);
                        vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
                    }
                }
                else
                {
                    vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                    vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
                }
            }
            else
            {
                vfo1Label.Text = "";
                vfo1FreqLabel.Text = "";
                vfo1StatusLabel.Text = "";
                vfo2Label.Text = "";
                vfo2FreqLabel.Text = "";
                vfo2StatusLabel.Text = "";
                vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
            }
            AdjustVfoLabel(vfo1Label);
            AdjustVfoLabel(vfo2Label);
            */
        }

        private void AdjustVfoLabel(Label label)
        {
            // Initial font size.
            float fontSize = 20;
            label.Font = new Font(label.Font.FontFamily, fontSize);

            // Create a Graphics object to measure the text.
            using (Graphics g = label.CreateGraphics())
            {
                // Measure the text width.
                SizeF textSize = g.MeasureString(label.Text, new Font(label.Font.FontFamily, fontSize));

                // While the text width exceeds the label width, reduce the font size.
                while (textSize.Width > label.ClientSize.Width && fontSize > 1)
                {
                    fontSize -= 1;
                    label.Font = new Font(label.Font.FontFamily, fontSize);
                    textSize = g.MeasureString(label.Text, label.Font);
                }
            }
        }

        private void connectButton_Click(object sender, EventArgs e)
        {
            //if (parent != null) { parent.connectToolStripMenuItem_Click(sender, e); }
        }

        private void checkBluetoothButton_Click(object sender, EventArgs e)
        {
            // Trigger bluetooth check in parent
            if (parent != null)
            {
                // Parent will handle this
            }
        }

        private void radioPictureBox_Click(object sender, EventArgs e)
        {
            //if (parent != null) { parent.volumeToolStripMenuItem_Click(sender, e); }
        }

        private void radioPictureBox_DragEnter(object sender, DragEventArgs e)
        {
            /*
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else if ((files.Length == 1) && (files[0].ToLower().EndsWith(".wav") && parent != null && parent.allowTransmit && (parent.radio.State == Radio.RadioState.Connected)))
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else
                {
                    e.Effect = DragDropEffects.None;
                }
            }
            */
        }

        private void radioPictureBox_DragDrop(object sender, DragEventArgs e)
        {
            if (parent == null) return;
            
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    //parent.importChannels(files[0]);
                }
                else if ((files.Length == 1) && (files[0].ToLower().EndsWith(".wav")))
                {
                    // Transmit the wav file
                    using (var reader = new WaveFileReader(files[0]))
                    {
                        var buffer = new byte[reader.Length];
                        int bytesRead = reader.Read(buffer, 0, buffer.Length);
                        //parent.radio.TransmitVoice(buffer, 0, bytesRead, true);
                    }
                }
            }
        }

        private void radioPanel_SizeChanged(object sender, EventArgs e)
        {
            UpdateChannelsPanel();
        }

        private void gpsStatusLabel_DoubleClick(object sender, EventArgs e)
        {
            //if (parent != null) { parent.radioPositionToolStripMenuItem_Click(sender, e); }
        }

        // Event that parent can subscribe to for bluetooth check
        public event EventHandler CheckBluetoothRequested;

        protected virtual void OnCheckBluetoothRequested()
        {
            CheckBluetoothRequested?.Invoke(this, EventArgs.Empty);
        }

        private void checkBluetoothButton_ClickInternal(object sender, EventArgs e)
        {
            OnCheckBluetoothRequested();
        }


        private void UpdateGpsStatusDisplay()
        {
            /*
            string status = "";

            // GPS Status
            if ((radio.State == RadioState.Connected) && gPSEnabledToolStripMenuItem.Checked)
            {
                if (radio.Position == null)
                {
                    status = "No GPS Lock";
                }
                else
                {
                    if (radio.Position.IsGpsLocked()) { status = "GPS Lock"; } else { status = "No GPS Lock"; }
                }
            }
            else
            {
                status = "";
            }

            if (radio.AudioState == true)
            {
                // Software modem status
                if (radio.SoftwareModemMode != RadioAudio.SoftwareModemModeType.Disabled)
                {
                    if (status.Length > 0) { status += " / "; }
                    if (radio.SoftwareModemMode == RadioAudio.SoftwareModemModeType.Afsk1200) { status += "AFK1200"; }
                    else if (radio.SoftwareModemMode == RadioAudio.SoftwareModemModeType.Psk2400) { status += "PSK2400"; }
                    else if (radio.SoftwareModemMode == RadioAudio.SoftwareModemModeType.Psk4800) { status += "PSK4800"; }
                    else if (radio.SoftwareModemMode == RadioAudio.SoftwareModemModeType.G3RUH9600) { status += "G9600"; }
                    else status += radio.SoftwareModemMode.ToString();
                }
            }
            */

            //gpsStatusLabel.Text = status;
        }
    }
}
