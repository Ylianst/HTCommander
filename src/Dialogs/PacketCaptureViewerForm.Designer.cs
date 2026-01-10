namespace HTCommander
{
    partial class PacketCaptureViewerForm
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

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(PacketCaptureViewerForm));
            System.Windows.Forms.ListViewGroup listViewGroup1 = new System.Windows.Forms.ListViewGroup("Metadata", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup2 = new System.Windows.Forms.ListViewGroup("AX.25 Header", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup3 = new System.Windows.Forms.ListViewGroup("AX.25 Data", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup4 = new System.Windows.Forms.ListViewGroup("APRS", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup5 = new System.Windows.Forms.ListViewGroup("Position", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup6 = new System.Windows.Forms.ListViewGroup("Decompression", System.Windows.Forms.HorizontalAlignment.Left);
            this.packetsSplitContainer = new System.Windows.Forms.SplitContainer();
            this.packetsListView = new System.Windows.Forms.ListView();
            this.columnHeader7 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader8 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader9 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetsListContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.copyHEXValuesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            this.packetDecodeListView = new System.Windows.Forms.ListView();
            this.packetDecodeColumnHeader1 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetDecodeColumnHeader2 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetDataContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.copyToClipboardToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mainMenuStrip = new System.Windows.Forms.MenuStrip();
            this.fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.closeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)(this.packetsSplitContainer)).BeginInit();
            this.packetsSplitContainer.Panel1.SuspendLayout();
            this.packetsSplitContainer.Panel2.SuspendLayout();
            this.packetsSplitContainer.SuspendLayout();
            this.packetsListContextMenuStrip.SuspendLayout();
            this.packetDataContextMenuStrip.SuspendLayout();
            this.mainMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // packetsSplitContainer
            // 
            this.packetsSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetsSplitContainer.Location = new System.Drawing.Point(0, 28);
            this.packetsSplitContainer.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.packetsSplitContainer.Name = "packetsSplitContainer";
            this.packetsSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // packetsSplitContainer.Panel1
            // 
            this.packetsSplitContainer.Panel1.Controls.Add(this.packetsListView);
            // 
            // packetsSplitContainer.Panel2
            // 
            this.packetsSplitContainer.Panel2.Controls.Add(this.packetDecodeListView);
            this.packetsSplitContainer.Size = new System.Drawing.Size(817, 483);
            this.packetsSplitContainer.SplitterDistance = 238;
            this.packetsSplitContainer.SplitterWidth = 5;
            this.packetsSplitContainer.TabIndex = 7;
            // 
            // packetsListView
            // 
            this.packetsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader7,
            this.columnHeader8,
            this.columnHeader9});
            this.packetsListView.ContextMenuStrip = this.packetsListContextMenuStrip;
            this.packetsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetsListView.FullRowSelect = true;
            this.packetsListView.GridLines = true;
            this.packetsListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            this.packetsListView.HideSelection = false;
            this.packetsListView.Location = new System.Drawing.Point(0, 0);
            this.packetsListView.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.packetsListView.Name = "packetsListView";
            this.packetsListView.Size = new System.Drawing.Size(817, 238);
            this.packetsListView.SmallImageList = this.mainImageList;
            this.packetsListView.TabIndex = 5;
            this.packetsListView.UseCompatibleStateImageBehavior = false;
            this.packetsListView.View = System.Windows.Forms.View.Details;
            this.packetsListView.SelectedIndexChanged += new System.EventHandler(this.packetsListView_SelectedIndexChanged);
            this.packetsListView.Resize += new System.EventHandler(this.packetsListView_Resize);
            // 
            // columnHeader7
            // 
            this.columnHeader7.Text = "Time";
            this.columnHeader7.Width = 90;
            // 
            // columnHeader8
            // 
            this.columnHeader8.Text = "Channel";
            this.columnHeader8.Width = 70;
            // 
            // columnHeader9
            // 
            this.columnHeader9.Text = "Data";
            this.columnHeader9.Width = 326;
            // 
            // packetsListContextMenuStrip
            // 
            this.packetsListContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.packetsListContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.copyHEXValuesToolStripMenuItem});
            this.packetsListContextMenuStrip.Name = "packetsListContextMenuStrip";
            this.packetsListContextMenuStrip.Size = new System.Drawing.Size(191, 28);
            this.packetsListContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.packetsListContextMenuStrip_Opening);
            // 
            // copyHEXValuesToolStripMenuItem
            // 
            this.copyHEXValuesToolStripMenuItem.Name = "copyHEXValuesToolStripMenuItem";
            this.copyHEXValuesToolStripMenuItem.Size = new System.Drawing.Size(190, 24);
            this.copyHEXValuesToolStripMenuItem.Text = "Copy &HEX Values";
            this.copyHEXValuesToolStripMenuItem.Click += new System.EventHandler(this.copyHEXValuesToolStripMenuItem_Click);
            // 
            // mainImageList
            // 
            this.mainImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("mainImageList.ImageStream")));
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.mainImageList.Images.SetKeyName(0, "GreenCheck.png");
            this.mainImageList.Images.SetKeyName(1, "RedCheck.png");
            this.mainImageList.Images.SetKeyName(2, "info.ico");
            this.mainImageList.Images.SetKeyName(3, "LocationPin2.png");
            this.mainImageList.Images.SetKeyName(4, "left-arrow.png");
            this.mainImageList.Images.SetKeyName(5, "right-arrow.png");
            // 
            // packetDecodeListView
            // 
            this.packetDecodeListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.packetDecodeColumnHeader1,
            this.packetDecodeColumnHeader2});
            this.packetDecodeListView.ContextMenuStrip = this.packetDataContextMenuStrip;
            this.packetDecodeListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetDecodeListView.FullRowSelect = true;
            this.packetDecodeListView.GridLines = true;
            listViewGroup1.Header = "Metadata";
            listViewGroup1.Name = "packetDecodeMetadataListViewGroup";
            listViewGroup2.Header = "AX.25 Header";
            listViewGroup2.Name = "packetDecodeHeaderListViewGroup";
            listViewGroup3.Header = "AX.25 Data";
            listViewGroup3.Name = "packetDecodeDataListViewGroup";
            listViewGroup4.Header = "APRS";
            listViewGroup4.Name = "packetDecodeAprsListViewGroup";
            listViewGroup5.Header = "Position";
            listViewGroup5.Name = "packetDecodePositionListViewGroup";
            listViewGroup6.Header = "Decompression";
            listViewGroup6.Name = "packetDecodeDecompressionListViewGroup";
            this.packetDecodeListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] {
            listViewGroup1,
            listViewGroup2,
            listViewGroup3,
            listViewGroup4,
            listViewGroup5,
            listViewGroup6});
            this.packetDecodeListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            this.packetDecodeListView.HideSelection = false;
            this.packetDecodeListView.Location = new System.Drawing.Point(0, 0);
            this.packetDecodeListView.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.packetDecodeListView.Name = "packetDecodeListView";
            this.packetDecodeListView.Size = new System.Drawing.Size(817, 240);
            this.packetDecodeListView.TabIndex = 1;
            this.packetDecodeListView.UseCompatibleStateImageBehavior = false;
            this.packetDecodeListView.View = System.Windows.Forms.View.Details;
            this.packetDecodeListView.Resize += new System.EventHandler(this.packetDecodeListView_Resize);
            // 
            // packetDecodeColumnHeader1
            // 
            this.packetDecodeColumnHeader1.Width = 100;
            // 
            // packetDecodeColumnHeader2
            // 
            this.packetDecodeColumnHeader2.Width = 300;
            // 
            // packetDataContextMenuStrip
            // 
            this.packetDataContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.packetDataContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.copyToClipboardToolStripMenuItem});
            this.packetDataContextMenuStrip.Name = "packetDataContextMenuStrip";
            this.packetDataContextMenuStrip.Size = new System.Drawing.Size(201, 28);
            this.packetDataContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.packetDataContextMenuStrip_Opening);
            // 
            // copyToClipboardToolStripMenuItem
            // 
            this.copyToClipboardToolStripMenuItem.Name = "copyToClipboardToolStripMenuItem";
            this.copyToClipboardToolStripMenuItem.Size = new System.Drawing.Size(200, 24);
            this.copyToClipboardToolStripMenuItem.Text = "Copy to Clipboard";
            this.copyToClipboardToolStripMenuItem.Click += new System.EventHandler(this.copyToClipboardToolStripMenuItem_Click);
            // 
            // mainMenuStrip
            // 
            this.mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.fileToolStripMenuItem});
            this.mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            this.mainMenuStrip.Name = "mainMenuStrip";
            this.mainMenuStrip.Size = new System.Drawing.Size(817, 28);
            this.mainMenuStrip.TabIndex = 8;
            this.mainMenuStrip.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            this.fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.closeToolStripMenuItem});
            this.fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            this.fileToolStripMenuItem.Size = new System.Drawing.Size(46, 24);
            this.fileToolStripMenuItem.Text = "&File";
            // 
            // closeToolStripMenuItem
            // 
            this.closeToolStripMenuItem.Name = "closeToolStripMenuItem";
            this.closeToolStripMenuItem.Size = new System.Drawing.Size(128, 26);
            this.closeToolStripMenuItem.Text = "&Close";
            this.closeToolStripMenuItem.Click += new System.EventHandler(this.closeToolStripMenuItem_Click);
            // 
            // PacketCaptureViewerForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(817, 511);
            this.Controls.Add(this.packetsSplitContainer);
            this.Controls.Add(this.mainMenuStrip);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MainMenuStrip = this.mainMenuStrip;
            this.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.Name = "PacketCaptureViewerForm";
            this.Text = "Packet Viewer";
            this.Load += new System.EventHandler(this.PacketCaptureViewerForm_Load);
            this.packetsSplitContainer.Panel1.ResumeLayout(false);
            this.packetsSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.packetsSplitContainer)).EndInit();
            this.packetsSplitContainer.ResumeLayout(false);
            this.packetsListContextMenuStrip.ResumeLayout(false);
            this.packetDataContextMenuStrip.ResumeLayout(false);
            this.mainMenuStrip.ResumeLayout(false);
            this.mainMenuStrip.PerformLayout();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.SplitContainer packetsSplitContainer;
        private System.Windows.Forms.ListView packetsListView;
        private System.Windows.Forms.ColumnHeader columnHeader7;
        private System.Windows.Forms.ColumnHeader columnHeader8;
        private System.Windows.Forms.ColumnHeader columnHeader9;
        private System.Windows.Forms.ListView packetDecodeListView;
        private System.Windows.Forms.ColumnHeader packetDecodeColumnHeader1;
        private System.Windows.Forms.ColumnHeader packetDecodeColumnHeader2;
        private System.Windows.Forms.MenuStrip mainMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem closeToolStripMenuItem;
        private System.Windows.Forms.ImageList mainImageList;
        private System.Windows.Forms.ContextMenuStrip packetsListContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem copyHEXValuesToolStripMenuItem;
        private System.Windows.Forms.ContextMenuStrip packetDataContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem copyToClipboardToolStripMenuItem;
    }
}