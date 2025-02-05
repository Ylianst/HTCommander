using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class ImportChannelsForm : Form
    {
        private MainForm parent;
        private RadioChannelInfo[] Channels = null;
        private RadioChannelControl[] channelControls = null;

        public ImportChannelsForm(MainForm parent, RadioChannelInfo[] channels)
        {
            InitializeComponent();
            Channels = channels;
        }

        public void UpdateChannelsPanel()
        {
            channelsFlowLayoutPanel.SuspendLayout();
            int visibleChannels = 0;
            int channelHeight = 0;
            if ((Channels != null) && (Channels.Length > 0))
            {
                if (channelControls == null) { channelControls = new RadioChannelControl[Channels.Length]; }
                for (int i = 0; i < channelControls.Length; i++)
                {
                    if (Channels[i] != null)
                    {
                        if (channelControls[i] == null)
                        {
                            channelControls[i] = new RadioChannelControl(parent);
                            channelsFlowLayoutPanel.Controls.Add(channelControls[i]);
                        }
                        channelControls[i].Channel = Channels[i];
                        channelControls[i].Tag = i;
                        bool visible = (Channels[i].name_str.Length > 0) || (Channels[i].rx_freq != 0);
                        channelControls[i].Visible = visible;
                        if (visible) { visibleChannels++; }
                        channelHeight = channelControls[i].Height;
                    }
                }
                int hBlockCount = ((visibleChannels / 3) + (((visibleChannels % 3) != 0) ? 1 : 0));
                int xHeight = 130 + (hBlockCount * channelControls[0].Height);
                if (xHeight < Height)
                {
                    Height = xHeight;
                    channelsFlowLayoutPanel.AutoScroll = false;
                }
                else
                {
                    Width += 24;
                    channelsFlowLayoutPanel.AutoScroll = true;
                }

            }
            channelsFlowLayoutPanel.Visible = (visibleChannels > 0);
            channelsFlowLayoutPanel.ResumeLayout();
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void ImportChannelsForm_Load(object sender, EventArgs e)
        {
            UpdateChannelsPanel();
        }
    }

}
