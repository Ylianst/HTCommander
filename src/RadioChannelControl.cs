/*
Copyright 2025 Ylian Saint-Hilaire

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

using Microsoft.Win32;
using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class RadioChannelControl : UserControl
    {
        private MainForm parent;

        public RadioChannelControl(MainForm parent)
        {
            InitializeComponent();
            this.parent = parent;
        }

        public string ChannelName
        {
            get { return channelNameLabel.Text; }
            set { channelNameLabel.Text = value; }
        }

        private void showToolStripMenuItem_Click(object sender, EventArgs e)
        {
            parent.ShowChannelDialog((int)this.Tag);
        }

        private void channelNameLabel_DoubleClick(object sender, EventArgs e)
        {
            parent.ShowChannelDialog((int)this.Tag);
        }

        private void channelNameLabel_Click(object sender, EventArgs e)
        {
            parent.ChangeChannelA((int)this.Tag);
        }

        private void setChannelAToolStripMenuItem_Click(object sender, EventArgs e)
        {
            parent.ChangeChannelA((int)this.Tag);
        }

        private void setChannelBToolStripMenuItem_Click(object sender, EventArgs e)
        {
            parent.ChangeChannelB((int)this.Tag);
        }

        private void showAllChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            parent.showAllChannels = !showAllChannelsToolStripMenuItem.Checked;
            parent.registry.WriteInt("ShowAllChannels", parent.showAllChannels ? 1 : 0);
            parent.UpdateChannelsPanel();
        }

        private void contextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            showAllChannelsToolStripMenuItem.Checked = parent.showAllChannels;
        }
    }
}
