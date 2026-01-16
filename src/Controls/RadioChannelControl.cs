/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Windows.Forms;
using HTCommander.Dialogs;
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
            
            // Set the appropriate context menu based on whether we have a parent
            if (parent == null)
            {
                channelNameLabel.ContextMenuStrip = viewOnlyContextMenuStrip;
            }
            else
            {
                channelNameLabel.ContextMenuStrip = contextMenuStrip;
            }
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
            if (parent != null)
            {
                parent.ShowChannelDialog((int)this.Tag);
            }
            else
            {
                // No parent - show in read-only mode
                RadioChannelForm f = new RadioChannelForm(channel);
                f.ShowDialog();
            }
        }

        private void channelNameLabel_DoubleClick(object sender, EventArgs e)
        {
            if (parent != null)
            {
                parent.ShowChannelDialog((int)this.Tag);
            }
            else
            {
                // No parent - show in read-only mode
                RadioChannelForm f = new RadioChannelForm(channel);
                f.ShowDialog();
            }
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

        private void contextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (parent == null) return;

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
                if (parent == null) return;

                if (MessageBox.Show(parent, string.Format("Copy \"{0}\" to channel {1}?", c.name_str, (channel.channel_id + 1)), "Channel", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) == DialogResult.OK)
                {
                    // Create a copy of the dragged channel with the target channel ID
                    RadioChannelInfo c2 = new RadioChannelInfo(c);
                    c2.channel_id = channel.channel_id;
                    
                    // Write the channel to the radio via the parent's DataBroker
                    parent.WriteChannel(c2);
                }
            }
            else if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    ImportChannelsFromFile(files[0]);
                }
            }
        }

        /// <summary>
        /// Imports channels from a CSV file and opens the ImportChannelsForm.
        /// </summary>
        /// <param name="filename">The path to the CSV file to import.</param>
        private void ImportChannelsFromFile(string filename)
        {
            RadioChannelInfo[] channels = ImportUtils.ParseChannelsFromFile(filename);
            if (channels == null || channels.Length == 0) return;

            ImportChannelsForm f = new ImportChannelsForm(null, channels);
            f.Text = f.Text + " - " + new FileInfo(filename).Name;
            f.Show();
        }

    }
}
