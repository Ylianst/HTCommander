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
using System.Windows.Forms;
using HTCommander.RadioControls;

namespace HTCommander
{
    public partial class RadioChannelControl : UserControl
    {
        private RadioChannelInfo channel;
        private RadioPanelControl parent;

        public RadioChannelControl(RadioPanelControl parent)
        {
            InitializeComponent();
            this.parent = parent;
        }

        public RadioChannelInfo Channel
        {
            get
            {
                return channel;
            }
            set
            {
                channel = value;
                if (channel.name_str.Length > 0)
                {
                    channelNameLabel.Text = channel.name_str;
                }
                else if (channel.rx_freq != 0)
                {
                    channelNameLabel.Text = ((double)channel.rx_freq / 1000000).ToString() + " Mhz";
                }
                else
                {
                    channelNameLabel.Text = (channel.channel_id + 1).ToString();
                }
            }
        }

        private void showToolStripMenuItem_Click(object sender, EventArgs e)
        {
            /*
            if (parent != null) { parent.ShowChannelDialog((int)this.Tag); }
            else
            {
                RadioChannelForm f = new RadioChannelForm(null, null, -1);
                f.channel = channel;
                f.ReadOnly = true;
                f.ShowDialog();
            }
            */
        }

        private void channelNameLabel_DoubleClick(object sender, EventArgs e)
        {
            /*
            if (parent != null) { parent.ShowChannelDialog((int)this.Tag); } else
            {
                RadioChannelForm f = new RadioChannelForm(null, null, -1);
                f.channel = channel;
                f.ReadOnly = true;
                f.ShowDialog();
            }
            */
        }

        private void channelNameLabel_Click(object sender, EventArgs e)
        {
            if (parent != null) { parent.ChangeChannelA((int)this.Tag); }
        }

        private void setChannelAToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (parent != null) { parent.ChangeChannelA((int)this.Tag); }
        }

        private void setChannelBToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (parent != null) { parent.ChangeChannelB((int)this.Tag); }
        }

        private void showAllChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (parent != null)
            {
                parent.ShowAllChannels = !parent.ShowAllChannels;
            }
        }

        public void UpdateChannelsPanel()
        {
            /*
            channelsFlowLayoutPanel.SuspendLayout();
            int visibleChannels = 0;
            int channelHeight = 0;
            if ((channelControls != null) && (radio.Channels != null))
            {
                for (int i = 0; i < channelControls.Length; i++)
                {
                    if (radio.Channels[i] != null)
                    {
                        if (channelControls[i] == null)
                        {
                            channelControls[i] = new RadioChannelControl(this);
                            //channelsFlowLayoutPanel.Controls.Add(channelControls[i]);
                        }
                        channelControls[i].Channel = radio.Channels[i];
                        channelControls[i].Tag = i;
                        bool visible = showAllChannels || (radio.Channels[i].name_str.Length > 0) || (radio.Channels[i].rx_freq != 0);
                        channelControls[i].Visible = visible;
                        if (visible) { visibleChannels++; }
                        channelHeight = channelControls[i].Height;
                    }
                }
                int hBlockCount = ((visibleChannels / 3) + (((visibleChannels % 3) != 0) ? 1 : 0));
                int blockHeight = 0;
                if (hBlockCount > 0)
                {
                    blockHeight = (radioPanel.Height - 310) / hBlockCount;
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

        private void contextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (parent != null)
            {
                int channelId = (int)this.Tag;
                int? currentChannelA = parent.GetCurrentChannelA();
                int? currentChannelB = parent.GetCurrentChannelB();
                
                // Disable "Set VFO A" if this channel is already VFO A
                setChannelAToolStripMenuItem.Enabled = (currentChannelA == null || currentChannelA != channelId);
                
                // Disable "Set VFO B" if this channel is already VFO B
                setChannelBToolStripMenuItem.Enabled = (currentChannelB == null || currentChannelB != channelId);
                
                // Set the "Show All Channels" checkbox state
                showAllChannelsToolStripMenuItem.Checked = parent.ShowAllChannels;
            }
        }

        private void channelNameLabel_MouseMove(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                DoDragDrop((object)channel, DragDropEffects.Copy | DragDropEffects.Move);
            }
        }

        private void RadioChannelControl_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(typeof(RadioChannelInfo)))
            {
                RadioChannelInfo c = (RadioChannelInfo)e.Data.GetData(typeof(RadioChannelInfo));
                if (c.channel_id == channel.channel_id)
                {
                    e.Effect = DragDropEffects.None;
                }
                else
                {
                    e.Effect = DragDropEffects.Copy;
                }
            }
            else if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
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

        private void RadioChannelControl_DragDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(typeof(RadioChannelInfo)))
            {
                RadioChannelInfo c = (RadioChannelInfo)e.Data.GetData(typeof(RadioChannelInfo));
                if (c.channel_id == channel.channel_id) return;
                if (MessageBox.Show(parent, string.Format("Copy \"{0}\" to channel {1}?", c.name_str, (channel.channel_id + 1)), "Channel", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) == DialogResult.OK)
                {
                    RadioChannelInfo c2 = new RadioChannelInfo(c);
                    c2.channel_id = channel.channel_id;
                    //parent.radio.SetChannel(c2);
                }
            }
            else if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    //parent.importChannels(files[0]);
                }
            }
        }

    }
}
