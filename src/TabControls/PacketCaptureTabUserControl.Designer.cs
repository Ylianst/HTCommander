namespace HTCommander.Controls
{
    partial class PacketCaptureTabUserControl
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
            System.Windows.Forms.ListViewGroup listViewGroup1 = new System.Windows.Forms.ListViewGroup("Encoding", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup2 = new System.Windows.Forms.ListViewGroup("Radio", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup3 = new System.Windows.Forms.ListViewGroup("AX.25 Decoding", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup4 = new System.Windows.Forms.ListViewGroup("AX.25 Data", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup5 = new System.Windows.Forms.ListViewGroup("APRS Decoding", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup6 = new System.Windows.Forms.ListViewGroup("APRS Position", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup7 = new System.Windows.Forms.ListViewGroup("Decompressed Data", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup8 = new System.Windows.Forms.ListViewGroup("Short Binary Protocol", System.Windows.Forms.HorizontalAlignment.Left);
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(PacketCaptureTabUserControl));
            this.packetsSplitContainer = new System.Windows.Forms.SplitContainer();
            this.packetsListView = new System.Windows.Forms.ListView();
            this.columnHeader7 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader8 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader9 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetsListContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.copyHEXValuesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.saveToFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.packetDecodeListView = new System.Windows.Forms.ListView();
            this.packetDecodeColumnHeader1 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetDecodeColumnHeader2 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetDataContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.copyToClipboardToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.panel3 = new System.Windows.Forms.Panel();
            this.packetsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.label5 = new System.Windows.Forms.Label();
            this.packetsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showPacketDecodeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem18 = new System.Windows.Forms.ToolStripSeparator();
            this.saveToFileToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.openFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem17 = new System.Windows.Forms.ToolStripSeparator();
            this.clearPacketsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.savePacketsFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.openPacketsFileDialog = new System.Windows.Forms.OpenFileDialog();
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            ((System.ComponentModel.ISupportInitialize)(this.packetsSplitContainer)).BeginInit();
            this.packetsSplitContainer.Panel1.SuspendLayout();
            this.packetsSplitContainer.Panel2.SuspendLayout();
            this.packetsSplitContainer.SuspendLayout();
            this.packetsListContextMenuStrip.SuspendLayout();
            this.packetDataContextMenuStrip.SuspendLayout();
            this.panel3.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.packetsMenuPictureBox)).BeginInit();
            this.packetsContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // packetsSplitContainer
            // 
            this.packetsSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetsSplitContainer.Location = new System.Drawing.Point(0, 37);
            this.packetsSplitContainer.Margin = new System.Windows.Forms.Padding(4);
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
            this.packetsSplitContainer.Size = new System.Drawing.Size(669, 586);
            this.packetsSplitContainer.SplitterDistance = 241;
            this.packetsSplitContainer.SplitterWidth = 5;
            this.packetsSplitContainer.TabIndex = 6;
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
            this.packetsListView.Margin = new System.Windows.Forms.Padding(4);
            this.packetsListView.Name = "packetsListView";
            this.packetsListView.Size = new System.Drawing.Size(669, 241);
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
            this.columnHeader9.Width = 505;
            // 
            // packetsListContextMenuStrip
            // 
            this.packetsListContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.packetsListContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.copyHEXValuesToolStripMenuItem,
            this.saveToFileToolStripMenuItem});
            this.packetsListContextMenuStrip.Name = "packetsListContextMenuStrip";
            this.packetsListContextMenuStrip.Size = new System.Drawing.Size(191, 52);
            this.packetsListContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.packetsListContextMenuStrip_Opening);
            // 
            // copyHEXValuesToolStripMenuItem
            // 
            this.copyHEXValuesToolStripMenuItem.Name = "copyHEXValuesToolStripMenuItem";
            this.copyHEXValuesToolStripMenuItem.Size = new System.Drawing.Size(190, 24);
            this.copyHEXValuesToolStripMenuItem.Text = "Copy &HEX Values";
            this.copyHEXValuesToolStripMenuItem.Click += new System.EventHandler(this.copyHEXValuesToolStripMenuItem_Click);
            // 
            // saveToFileToolStripMenuItem
            // 
            this.saveToFileToolStripMenuItem.Name = "saveToFileToolStripMenuItem";
            this.saveToFileToolStripMenuItem.Size = new System.Drawing.Size(190, 24);
            this.saveToFileToolStripMenuItem.Text = "&Save to File...";
            this.saveToFileToolStripMenuItem.Click += new System.EventHandler(this.saveToFileToolStripMenuItem_Click);
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
            listViewGroup1.Header = "Encoding";
            listViewGroup1.Name = "encodingListViewGroup";
            listViewGroup2.Header = "Radio";
            listViewGroup2.Name = "radioListViewGroup";
            listViewGroup3.Header = "AX.25 Decoding";
            listViewGroup3.Name = "decodingListViewGroup";
            listViewGroup4.Header = "AX.25 Data";
            listViewGroup4.Name = "dataListViewGroup";
            listViewGroup5.Header = "APRS Decoding";
            listViewGroup5.Name = "aprsDecodingListViewGroup";
            listViewGroup6.Header = "APRS Position";
            listViewGroup6.Name = "aprsPositionListViewGroup";
            listViewGroup7.Header = "Decompressed Data";
            listViewGroup7.Name = "decompressedListViewGroup";
            listViewGroup8.Header = "Short Binary Protocol";
            listViewGroup8.Name = "shortBinaryListViewGroup";
            this.packetDecodeListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] {
            listViewGroup1,
            listViewGroup2,
            listViewGroup3,
            listViewGroup4,
            listViewGroup5,
            listViewGroup6,
            listViewGroup7,
            listViewGroup8});
            this.packetDecodeListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            this.packetDecodeListView.HideSelection = false;
            this.packetDecodeListView.Location = new System.Drawing.Point(0, 0);
            this.packetDecodeListView.Margin = new System.Windows.Forms.Padding(4);
            this.packetDecodeListView.Name = "packetDecodeListView";
            this.packetDecodeListView.Size = new System.Drawing.Size(669, 340);
            this.packetDecodeListView.TabIndex = 1;
            this.packetDecodeListView.UseCompatibleStateImageBehavior = false;
            this.packetDecodeListView.View = System.Windows.Forms.View.Details;
            // 
            // packetDecodeColumnHeader1
            // 
            this.packetDecodeColumnHeader1.Text = "Name";
            this.packetDecodeColumnHeader1.Width = 120;
            // 
            // packetDecodeColumnHeader2
            // 
            this.packetDecodeColumnHeader2.Text = "Value";
            this.packetDecodeColumnHeader2.Width = 545;
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
            // panel3
            // 
            this.panel3.BackColor = System.Drawing.Color.Silver;
            this.panel3.Controls.Add(this.packetsMenuPictureBox);
            this.panel3.Controls.Add(this.label5);
            this.panel3.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel3.Location = new System.Drawing.Point(0, 0);
            this.panel3.Margin = new System.Windows.Forms.Padding(4);
            this.panel3.Name = "panel3";
            this.panel3.Size = new System.Drawing.Size(669, 37);
            this.panel3.TabIndex = 3;
            // 
            // packetsMenuPictureBox
            // 
            this.packetsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.packetsMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.packetsMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.packetsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.packetsMenuPictureBox.Name = "packetsMenuPictureBox";
            this.packetsMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.packetsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.packetsMenuPictureBox.TabIndex = 2;
            this.packetsMenuPictureBox.TabStop = false;
            this.packetsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.packetsMenuPictureBox_MouseClick);
            // 
            // label5
            // 
            this.label5.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label5.AutoSize = true;
            this.label5.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label5.Location = new System.Drawing.Point(7, 6);
            this.label5.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(147, 25);
            this.label5.TabIndex = 0;
            this.label5.Text = "Packet Capture";
            // 
            // packetsContextMenuStrip
            // 
            this.packetsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.packetsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showPacketDecodeToolStripMenuItem,
            this.toolStripMenuItem18,
            this.saveToFileToolStripMenuItem1,
            this.openFileToolStripMenuItem,
            this.toolStripMenuItem17,
            this.clearPacketsToolStripMenuItem});
            this.packetsContextMenuStrip.Name = "packetsContextMenuStrip";
            this.packetsContextMenuStrip.Size = new System.Drawing.Size(217, 112);
            this.packetsContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.packetsContextMenuStrip_Opening);
            // 
            // showPacketDecodeToolStripMenuItem
            // 
            this.showPacketDecodeToolStripMenuItem.CheckOnClick = true;
            this.showPacketDecodeToolStripMenuItem.Name = "showPacketDecodeToolStripMenuItem";
            this.showPacketDecodeToolStripMenuItem.Size = new System.Drawing.Size(216, 24);
            this.showPacketDecodeToolStripMenuItem.Text = "Show Packet &Decode";
            this.showPacketDecodeToolStripMenuItem.CheckStateChanged += new System.EventHandler(this.showPacketDecodeToolStripMenuItem_CheckStateChanged);
            // 
            // toolStripMenuItem18
            // 
            this.toolStripMenuItem18.Name = "toolStripMenuItem18";
            this.toolStripMenuItem18.Size = new System.Drawing.Size(213, 6);
            // 
            // saveToFileToolStripMenuItem1
            // 
            this.saveToFileToolStripMenuItem1.Name = "saveToFileToolStripMenuItem1";
            this.saveToFileToolStripMenuItem1.Size = new System.Drawing.Size(216, 24);
            this.saveToFileToolStripMenuItem1.Text = "Save to &File...";
            this.saveToFileToolStripMenuItem1.Click += new System.EventHandler(this.saveToFileToolStripMenuItem1_Click);
            // 
            // openFileToolStripMenuItem
            // 
            this.openFileToolStripMenuItem.Name = "openFileToolStripMenuItem";
            this.openFileToolStripMenuItem.Size = new System.Drawing.Size(216, 24);
            this.openFileToolStripMenuItem.Text = "&Open File...";
            this.openFileToolStripMenuItem.Click += new System.EventHandler(this.openFileToolStripMenuItem_Click);
            // 
            // toolStripMenuItem17
            // 
            this.toolStripMenuItem17.Name = "toolStripMenuItem17";
            this.toolStripMenuItem17.Size = new System.Drawing.Size(213, 6);
            // 
            // clearPacketsToolStripMenuItem
            // 
            this.clearPacketsToolStripMenuItem.Name = "clearPacketsToolStripMenuItem";
            this.clearPacketsToolStripMenuItem.Size = new System.Drawing.Size(216, 24);
            this.clearPacketsToolStripMenuItem.Text = "&Clear Packets";
            this.clearPacketsToolStripMenuItem.Click += new System.EventHandler(this.clearPacketsToolStripMenuItem_Click);
            // 
            // savePacketsFileDialog
            // 
            this.savePacketsFileDialog.DefaultExt = "ptcap";
            this.savePacketsFileDialog.Filter = "Packet Capture|*.ptcap|All files|*.*";
            this.savePacketsFileDialog.Title = "Save Packet Capture";
            // 
            // openPacketsFileDialog
            // 
            this.openPacketsFileDialog.FileName = "packets.ptcap";
            this.openPacketsFileDialog.Filter = "Packet Capture|*.ptcap|All files|*.*";
            this.openPacketsFileDialog.Title = "Open Packet Capture File";
            // 
            // mainImageList
            // 
            this.mainImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("mainImageList.ImageStream")));
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.mainImageList.Images.SetKeyName(0, "GreenCheck-20.png");
            this.mainImageList.Images.SetKeyName(1, "");
            this.mainImageList.Images.SetKeyName(2, "");
            this.mainImageList.Images.SetKeyName(3, "");
            this.mainImageList.Images.SetKeyName(4, "");
            this.mainImageList.Images.SetKeyName(5, "");
            this.mainImageList.Images.SetKeyName(6, "");
            this.mainImageList.Images.SetKeyName(7, "");
            this.mainImageList.Images.SetKeyName(8, "mail-20.png");
            this.mainImageList.Images.SetKeyName(9, "file-20.png");
            this.mainImageList.Images.SetKeyName(10, "file-empty-20.png");
            // 
            // PacketCaptureTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.packetsSplitContainer);
            this.Controls.Add(this.panel3);
            this.Name = "PacketCaptureTabUserControl";
            this.Size = new System.Drawing.Size(669, 623);
            this.packetsSplitContainer.Panel1.ResumeLayout(false);
            this.packetsSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.packetsSplitContainer)).EndInit();
            this.packetsSplitContainer.ResumeLayout(false);
            this.packetsListContextMenuStrip.ResumeLayout(false);
            this.packetDataContextMenuStrip.ResumeLayout(false);
            this.panel3.ResumeLayout(false);
            this.panel3.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.packetsMenuPictureBox)).EndInit();
            this.packetsContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.SplitContainer packetsSplitContainer;
        private System.Windows.Forms.ListView packetsListView;
        private System.Windows.Forms.ColumnHeader columnHeader7;
        private System.Windows.Forms.ColumnHeader columnHeader8;
        private System.Windows.Forms.ColumnHeader columnHeader9;
        private System.Windows.Forms.ContextMenuStrip packetsListContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem copyHEXValuesToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem saveToFileToolStripMenuItem;
        private System.Windows.Forms.ListView packetDecodeListView;
        private System.Windows.Forms.ColumnHeader packetDecodeColumnHeader1;
        private System.Windows.Forms.ColumnHeader packetDecodeColumnHeader2;
        private System.Windows.Forms.ContextMenuStrip packetDataContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem copyToClipboardToolStripMenuItem;
        private System.Windows.Forms.Panel panel3;
        private System.Windows.Forms.PictureBox packetsMenuPictureBox;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.ContextMenuStrip packetsContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showPacketDecodeToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem18;
        private System.Windows.Forms.ToolStripMenuItem saveToFileToolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem openFileToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem17;
        private System.Windows.Forms.ToolStripMenuItem clearPacketsToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog savePacketsFileDialog;
        private System.Windows.Forms.OpenFileDialog openPacketsFileDialog;
        private System.Windows.Forms.ImageList mainImageList;
    }
}