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
            this.components = new System.ComponentModel.Container();
            this.contextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            this.setChannelAToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.setChannelBToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem2 = new System.Windows.Forms.ToolStripSeparator();
            this.showAllChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.channelNameLabel = new System.Windows.Forms.Label();
            this.contextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // contextMenuStrip
            // 
            this.contextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.contextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showToolStripMenuItem,
            this.toolStripMenuItem1,
            this.setChannelAToolStripMenuItem,
            this.setChannelBToolStripMenuItem,
            this.toolStripMenuItem2,
            this.showAllChannelsToolStripMenuItem});
            this.contextMenuStrip.Name = "contextMenuStrip";
            this.contextMenuStrip.Size = new System.Drawing.Size(200, 112);
            this.contextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.contextMenuStrip_Opening);
            // 
            // showToolStripMenuItem
            // 
            this.showToolStripMenuItem.Name = "showToolStripMenuItem";
            this.showToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.showToolStripMenuItem.Text = "&Edit...";
            this.showToolStripMenuItem.Click += new System.EventHandler(this.showToolStripMenuItem_Click);
            // 
            // toolStripMenuItem1
            // 
            this.toolStripMenuItem1.Name = "toolStripMenuItem1";
            this.toolStripMenuItem1.Size = new System.Drawing.Size(207, 6);
            // 
            // setChannelAToolStripMenuItem
            // 
            this.setChannelAToolStripMenuItem.Name = "setChannelAToolStripMenuItem";
            this.setChannelAToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.setChannelAToolStripMenuItem.Text = "Set VFO &A";
            this.setChannelAToolStripMenuItem.Click += new System.EventHandler(this.setChannelAToolStripMenuItem_Click);
            // 
            // setChannelBToolStripMenuItem
            // 
            this.setChannelBToolStripMenuItem.Name = "setChannelBToolStripMenuItem";
            this.setChannelBToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.setChannelBToolStripMenuItem.Text = "Set VFO &B";
            this.setChannelBToolStripMenuItem.Click += new System.EventHandler(this.setChannelBToolStripMenuItem_Click);
            // 
            // toolStripMenuItem2
            // 
            this.toolStripMenuItem2.Name = "toolStripMenuItem2";
            this.toolStripMenuItem2.Size = new System.Drawing.Size(207, 6);
            // 
            // showAllChannelsToolStripMenuItem
            // 
            this.showAllChannelsToolStripMenuItem.Name = "showAllChannelsToolStripMenuItem";
            this.showAllChannelsToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.showAllChannelsToolStripMenuItem.Text = "&Show All Channels";
            this.showAllChannelsToolStripMenuItem.Click += new System.EventHandler(this.showAllChannelsToolStripMenuItem_Click);
            // 
            // channelNameLabel
            // 
            this.channelNameLabel.ContextMenuStrip = this.contextMenuStrip;
            this.channelNameLabel.Dock = System.Windows.Forms.DockStyle.Fill;
            this.channelNameLabel.Location = new System.Drawing.Point(0, 0);
            this.channelNameLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.channelNameLabel.Name = "channelNameLabel";
            this.channelNameLabel.Size = new System.Drawing.Size(122, 34);
            this.channelNameLabel.TabIndex = 1;
            this.channelNameLabel.Text = "label1";
            this.channelNameLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            this.channelNameLabel.Click += new System.EventHandler(this.channelNameLabel_Click);
            this.channelNameLabel.DragDrop += new System.Windows.Forms.DragEventHandler(this.RadioChannelControl_DragDrop);
            this.channelNameLabel.DragEnter += new System.Windows.Forms.DragEventHandler(this.RadioChannelControl_DragEnter);
            this.channelNameLabel.DoubleClick += new System.EventHandler(this.channelNameLabel_DoubleClick);
            this.channelNameLabel.MouseMove += new System.Windows.Forms.MouseEventHandler(this.channelNameLabel_MouseMove);
            // 
            // RadioChannelControl
            // 
            this.AllowDrop = true;
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.BackColor = System.Drawing.Color.DarkKhaki;
            this.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.Controls.Add(this.channelNameLabel);
            this.Margin = new System.Windows.Forms.Padding(0);
            this.Name = "RadioChannelControl";
            this.Size = new System.Drawing.Size(122, 34);
            this.DragDrop += new System.Windows.Forms.DragEventHandler(this.RadioChannelControl_DragDrop);
            this.DragEnter += new System.Windows.Forms.DragEventHandler(this.RadioChannelControl_DragEnter);
            this.DoubleClick += new System.EventHandler(this.channelNameLabel_DoubleClick);
            this.contextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

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
