namespace HTCommander
{
    partial class RadioChannelControl
    {
        /// <summary> 
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary> 
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Component Designer generated code

        /// <summary> 
        /// Required method for Designer support - do not modify 
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            components = new System.ComponentModel.Container();
            contextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            showToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            setChannelAToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            setChannelBToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem2 = new System.Windows.Forms.ToolStripSeparator();
            showAllChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            channelNameLabel = new System.Windows.Forms.Label();
            contextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // contextMenuStrip
            // 
            contextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            contextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { showToolStripMenuItem, toolStripMenuItem1, setChannelAToolStripMenuItem, setChannelBToolStripMenuItem, toolStripMenuItem2, showAllChannelsToolStripMenuItem });
            contextMenuStrip.Name = "contextMenuStrip";
            contextMenuStrip.Size = new System.Drawing.Size(200, 112);
            contextMenuStrip.Opening += contextMenuStrip_Opening;
            // 
            // showToolStripMenuItem
            // 
            showToolStripMenuItem.Name = "showToolStripMenuItem";
            showToolStripMenuItem.Size = new System.Drawing.Size(199, 24);
            showToolStripMenuItem.Text = "&Edit...";
            showToolStripMenuItem.Click += showToolStripMenuItem_Click;
            // 
            // toolStripMenuItem1
            // 
            toolStripMenuItem1.Name = "toolStripMenuItem1";
            toolStripMenuItem1.Size = new System.Drawing.Size(196, 6);
            // 
            // setChannelAToolStripMenuItem
            // 
            setChannelAToolStripMenuItem.Name = "setChannelAToolStripMenuItem";
            setChannelAToolStripMenuItem.Size = new System.Drawing.Size(199, 24);
            setChannelAToolStripMenuItem.Text = "Set VFO &A";
            setChannelAToolStripMenuItem.Click += setChannelAToolStripMenuItem_Click;
            // 
            // setChannelBToolStripMenuItem
            // 
            setChannelBToolStripMenuItem.Name = "setChannelBToolStripMenuItem";
            setChannelBToolStripMenuItem.Size = new System.Drawing.Size(199, 24);
            setChannelBToolStripMenuItem.Text = "Set VFO &B";
            setChannelBToolStripMenuItem.Click += setChannelBToolStripMenuItem_Click;
            // 
            // toolStripMenuItem2
            // 
            toolStripMenuItem2.Name = "toolStripMenuItem2";
            toolStripMenuItem2.Size = new System.Drawing.Size(196, 6);
            // 
            // showAllChannelsToolStripMenuItem
            // 
            showAllChannelsToolStripMenuItem.Name = "showAllChannelsToolStripMenuItem";
            showAllChannelsToolStripMenuItem.Size = new System.Drawing.Size(199, 24);
            showAllChannelsToolStripMenuItem.Text = "&Show All Channels";
            showAllChannelsToolStripMenuItem.Click += showAllChannelsToolStripMenuItem_Click;
            // 
            // channelNameLabel
            // 
            channelNameLabel.ContextMenuStrip = contextMenuStrip;
            channelNameLabel.Dock = System.Windows.Forms.DockStyle.Fill;
            channelNameLabel.Location = new System.Drawing.Point(0, 0);
            channelNameLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            channelNameLabel.Name = "channelNameLabel";
            channelNameLabel.Size = new System.Drawing.Size(121, 42);
            channelNameLabel.TabIndex = 1;
            channelNameLabel.Text = "label1";
            channelNameLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            channelNameLabel.Click += channelNameLabel_Click;
            channelNameLabel.DragDrop += RadioChannelControl_DragDrop;
            channelNameLabel.DragEnter += RadioChannelControl_DragEnter;
            channelNameLabel.DoubleClick += channelNameLabel_DoubleClick;
            channelNameLabel.MouseMove += channelNameLabel_MouseMove;
            // 
            // RadioChannelControl
            // 
            AllowDrop = true;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            BackColor = System.Drawing.Color.DarkKhaki;
            BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            Controls.Add(channelNameLabel);
            Margin = new System.Windows.Forms.Padding(0);
            Name = "RadioChannelControl";
            Size = new System.Drawing.Size(121, 42);
            DragDrop += RadioChannelControl_DragDrop;
            DragEnter += RadioChannelControl_DragEnter;
            DoubleClick += channelNameLabel_DoubleClick;
            contextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.ContextMenuStrip contextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showToolStripMenuItem;
        private System.Windows.Forms.Label channelNameLabel;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem setChannelAToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem setChannelBToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem2;
        private System.Windows.Forms.ToolStripMenuItem showAllChannelsToolStripMenuItem;
    }
}
