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
            components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(PacketCaptureTabUserControl));
            System.Windows.Forms.ListViewGroup listViewGroup9 = new System.Windows.Forms.ListViewGroup("Encoding", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup10 = new System.Windows.Forms.ListViewGroup("Radio", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup11 = new System.Windows.Forms.ListViewGroup("AX.25 Decoding", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup12 = new System.Windows.Forms.ListViewGroup("AX.25 Data", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup13 = new System.Windows.Forms.ListViewGroup("APRS Decoding", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup14 = new System.Windows.Forms.ListViewGroup("APRS Position", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup15 = new System.Windows.Forms.ListViewGroup("Decompressed Data", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup16 = new System.Windows.Forms.ListViewGroup("BSS Protocol", System.Windows.Forms.HorizontalAlignment.Left);
            packetsSplitContainer = new System.Windows.Forms.SplitContainer();
            packetsListView = new System.Windows.Forms.ListView();
            columnHeader7 = new System.Windows.Forms.ColumnHeader();
            columnHeader8 = new System.Windows.Forms.ColumnHeader();
            columnHeader9 = new System.Windows.Forms.ColumnHeader();
            packetsListContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            copyHEXValuesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            saveToFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            mainImageList = new System.Windows.Forms.ImageList(components);
            packetDecodeListView = new System.Windows.Forms.ListView();
            packetDecodeColumnHeader1 = new System.Windows.Forms.ColumnHeader();
            packetDecodeColumnHeader2 = new System.Windows.Forms.ColumnHeader();
            packetDataContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            copyToClipboardToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            titlePanel = new System.Windows.Forms.Panel();
            packetsMenuPictureBox = new System.Windows.Forms.PictureBox();
            label5 = new System.Windows.Forms.Label();
            packetsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            showPacketDecodeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem18 = new System.Windows.Forms.ToolStripSeparator();
            saveToFileToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            openFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem17 = new System.Windows.Forms.ToolStripSeparator();
            clearPacketsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            savePacketsFileDialog = new System.Windows.Forms.SaveFileDialog();
            openPacketsFileDialog = new System.Windows.Forms.OpenFileDialog();
            ((System.ComponentModel.ISupportInitialize)packetsSplitContainer).BeginInit();
            packetsSplitContainer.Panel1.SuspendLayout();
            packetsSplitContainer.Panel2.SuspendLayout();
            packetsSplitContainer.SuspendLayout();
            packetsListContextMenuStrip.SuspendLayout();
            packetDataContextMenuStrip.SuspendLayout();
            titlePanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)packetsMenuPictureBox).BeginInit();
            packetsContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // packetsSplitContainer
            // 
            packetsSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            packetsSplitContainer.Location = new System.Drawing.Point(0, 46);
            packetsSplitContainer.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            packetsSplitContainer.Name = "packetsSplitContainer";
            packetsSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // packetsSplitContainer.Panel1
            // 
            packetsSplitContainer.Panel1.Controls.Add(packetsListView);
            // 
            // packetsSplitContainer.Panel2
            // 
            packetsSplitContainer.Panel2.Controls.Add(packetDecodeListView);
            packetsSplitContainer.Size = new System.Drawing.Size(669, 733);
            packetsSplitContainer.SplitterDistance = 301;
            packetsSplitContainer.SplitterWidth = 6;
            packetsSplitContainer.TabIndex = 6;
            // 
            // packetsListView
            // 
            packetsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader7, columnHeader8, columnHeader9 });
            packetsListView.ContextMenuStrip = packetsListContextMenuStrip;
            packetsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            packetsListView.FullRowSelect = true;
            packetsListView.GridLines = true;
            packetsListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            packetsListView.Location = new System.Drawing.Point(0, 0);
            packetsListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            packetsListView.Name = "packetsListView";
            packetsListView.Size = new System.Drawing.Size(669, 301);
            packetsListView.SmallImageList = mainImageList;
            packetsListView.TabIndex = 5;
            packetsListView.UseCompatibleStateImageBehavior = false;
            packetsListView.View = System.Windows.Forms.View.Details;
            packetsListView.SelectedIndexChanged += packetsListView_SelectedIndexChanged;
            packetsListView.Resize += packetsListView_Resize;
            // 
            // columnHeader7
            // 
            columnHeader7.Text = "Time";
            columnHeader7.Width = 90;
            // 
            // columnHeader8
            // 
            columnHeader8.Text = "Channel";
            columnHeader8.Width = 70;
            // 
            // columnHeader9
            // 
            columnHeader9.Text = "Data";
            columnHeader9.Width = 505;
            // 
            // packetsListContextMenuStrip
            // 
            packetsListContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            packetsListContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { copyHEXValuesToolStripMenuItem, saveToFileToolStripMenuItem });
            packetsListContextMenuStrip.Name = "packetsListContextMenuStrip";
            packetsListContextMenuStrip.Size = new System.Drawing.Size(191, 52);
            packetsListContextMenuStrip.Opening += packetsListContextMenuStrip_Opening;
            // 
            // copyHEXValuesToolStripMenuItem
            // 
            copyHEXValuesToolStripMenuItem.Name = "copyHEXValuesToolStripMenuItem";
            copyHEXValuesToolStripMenuItem.Size = new System.Drawing.Size(190, 24);
            copyHEXValuesToolStripMenuItem.Text = "Copy &HEX Values";
            copyHEXValuesToolStripMenuItem.Click += copyHEXValuesToolStripMenuItem_Click;
            // 
            // saveToFileToolStripMenuItem
            // 
            saveToFileToolStripMenuItem.Name = "saveToFileToolStripMenuItem";
            saveToFileToolStripMenuItem.Size = new System.Drawing.Size(190, 24);
            saveToFileToolStripMenuItem.Text = "&Save to File...";
            saveToFileToolStripMenuItem.Click += saveToFileToolStripMenuItem_Click;
            // 
            // mainImageList
            // 
            mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth24Bit;
            mainImageList.ImageStream = (System.Windows.Forms.ImageListStreamer)resources.GetObject("mainImageList.ImageStream");
            mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            mainImageList.Images.SetKeyName(0, "GreenCheck-20.png");
            mainImageList.Images.SetKeyName(1, "");
            mainImageList.Images.SetKeyName(2, "");
            mainImageList.Images.SetKeyName(3, "");
            mainImageList.Images.SetKeyName(4, "");
            mainImageList.Images.SetKeyName(5, "");
            mainImageList.Images.SetKeyName(6, "");
            mainImageList.Images.SetKeyName(7, "");
            mainImageList.Images.SetKeyName(8, "mail-20.png");
            mainImageList.Images.SetKeyName(9, "file-20.png");
            mainImageList.Images.SetKeyName(10, "file-empty-20.png");
            // 
            // packetDecodeListView
            // 
            packetDecodeListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { packetDecodeColumnHeader1, packetDecodeColumnHeader2 });
            packetDecodeListView.ContextMenuStrip = packetDataContextMenuStrip;
            packetDecodeListView.Dock = System.Windows.Forms.DockStyle.Fill;
            packetDecodeListView.FullRowSelect = true;
            packetDecodeListView.GridLines = true;
            listViewGroup9.Header = "Encoding";
            listViewGroup9.Name = "encodingListViewGroup";
            listViewGroup10.Header = "Radio";
            listViewGroup10.Name = "radioListViewGroup";
            listViewGroup11.Header = "AX.25 Decoding";
            listViewGroup11.Name = "decodingListViewGroup";
            listViewGroup12.Header = "AX.25 Data";
            listViewGroup12.Name = "dataListViewGroup";
            listViewGroup13.Header = "APRS Decoding";
            listViewGroup13.Name = "aprsDecodingListViewGroup";
            listViewGroup14.Header = "APRS Position";
            listViewGroup14.Name = "aprsPositionListViewGroup";
            listViewGroup15.Header = "Decompressed Data";
            listViewGroup15.Name = "decompressedListViewGroup";
            listViewGroup16.Header = "Short Binary Protocol";
            listViewGroup16.Name = "shortBinaryListViewGroup";
            packetDecodeListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] { listViewGroup9, listViewGroup10, listViewGroup11, listViewGroup12, listViewGroup13, listViewGroup14, listViewGroup15, listViewGroup16 });
            packetDecodeListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            packetDecodeListView.Location = new System.Drawing.Point(0, 0);
            packetDecodeListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            packetDecodeListView.Name = "packetDecodeListView";
            packetDecodeListView.Size = new System.Drawing.Size(669, 426);
            packetDecodeListView.TabIndex = 1;
            packetDecodeListView.UseCompatibleStateImageBehavior = false;
            packetDecodeListView.View = System.Windows.Forms.View.Details;
            // 
            // packetDecodeColumnHeader1
            // 
            packetDecodeColumnHeader1.Text = "Name";
            packetDecodeColumnHeader1.Width = 120;
            // 
            // packetDecodeColumnHeader2
            // 
            packetDecodeColumnHeader2.Text = "Value";
            packetDecodeColumnHeader2.Width = 545;
            // 
            // packetDataContextMenuStrip
            // 
            packetDataContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            packetDataContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { copyToClipboardToolStripMenuItem });
            packetDataContextMenuStrip.Name = "packetDataContextMenuStrip";
            packetDataContextMenuStrip.Size = new System.Drawing.Size(201, 28);
            packetDataContextMenuStrip.Opening += packetDataContextMenuStrip_Opening;
            // 
            // copyToClipboardToolStripMenuItem
            // 
            copyToClipboardToolStripMenuItem.Name = "copyToClipboardToolStripMenuItem";
            copyToClipboardToolStripMenuItem.Size = new System.Drawing.Size(200, 24);
            copyToClipboardToolStripMenuItem.Text = "Copy to Clipboard";
            copyToClipboardToolStripMenuItem.Click += copyToClipboardToolStripMenuItem_Click;
            // 
            // titlePanel
            // 
            titlePanel.BackColor = System.Drawing.Color.Silver;
            titlePanel.Controls.Add(packetsMenuPictureBox);
            titlePanel.Controls.Add(label5);
            titlePanel.Dock = System.Windows.Forms.DockStyle.Top;
            titlePanel.Location = new System.Drawing.Point(0, 0);
            titlePanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            titlePanel.Name = "titlePanel";
            titlePanel.Size = new System.Drawing.Size(669, 46);
            titlePanel.TabIndex = 3;
            // 
            // packetsMenuPictureBox
            // 
            packetsMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            packetsMenuPictureBox.Image = Properties.Resources.MenuIcon;
            packetsMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            packetsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            packetsMenuPictureBox.Name = "packetsMenuPictureBox";
            packetsMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            packetsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            packetsMenuPictureBox.TabIndex = 2;
            packetsMenuPictureBox.TabStop = false;
            packetsMenuPictureBox.MouseClick += packetsMenuPictureBox_MouseClick;
            // 
            // label5
            // 
            label5.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label5.AutoSize = true;
            label5.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            label5.Location = new System.Drawing.Point(7, 8);
            label5.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label5.Name = "label5";
            label5.Size = new System.Drawing.Size(147, 25);
            label5.TabIndex = 0;
            label5.Text = "Packet Capture";
            // 
            // packetsContextMenuStrip
            // 
            packetsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            packetsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { showPacketDecodeToolStripMenuItem, toolStripMenuItem18, saveToFileToolStripMenuItem1, openFileToolStripMenuItem, toolStripMenuItem17, clearPacketsToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            packetsContextMenuStrip.Name = "packetsContextMenuStrip";
            packetsContextMenuStrip.Size = new System.Drawing.Size(217, 142);
            packetsContextMenuStrip.Opening += packetsContextMenuStrip_Opening;
            // 
            // showPacketDecodeToolStripMenuItem
            // 
            showPacketDecodeToolStripMenuItem.CheckOnClick = true;
            showPacketDecodeToolStripMenuItem.Name = "showPacketDecodeToolStripMenuItem";
            showPacketDecodeToolStripMenuItem.Size = new System.Drawing.Size(216, 24);
            showPacketDecodeToolStripMenuItem.Text = "Show Packet &Decode";
            showPacketDecodeToolStripMenuItem.CheckStateChanged += showPacketDecodeToolStripMenuItem_CheckStateChanged;
            // 
            // toolStripMenuItem18
            // 
            toolStripMenuItem18.Name = "toolStripMenuItem18";
            toolStripMenuItem18.Size = new System.Drawing.Size(213, 6);
            // 
            // saveToFileToolStripMenuItem1
            // 
            saveToFileToolStripMenuItem1.Name = "saveToFileToolStripMenuItem1";
            saveToFileToolStripMenuItem1.Size = new System.Drawing.Size(216, 24);
            saveToFileToolStripMenuItem1.Text = "Save to &File...";
            saveToFileToolStripMenuItem1.Click += saveToFileToolStripMenuItem1_Click;
            // 
            // openFileToolStripMenuItem
            // 
            openFileToolStripMenuItem.Name = "openFileToolStripMenuItem";
            openFileToolStripMenuItem.Size = new System.Drawing.Size(216, 24);
            openFileToolStripMenuItem.Text = "&Open File...";
            openFileToolStripMenuItem.Click += openFileToolStripMenuItem_Click;
            // 
            // toolStripMenuItem17
            // 
            toolStripMenuItem17.Name = "toolStripMenuItem17";
            toolStripMenuItem17.Size = new System.Drawing.Size(213, 6);
            // 
            // clearPacketsToolStripMenuItem
            // 
            clearPacketsToolStripMenuItem.Name = "clearPacketsToolStripMenuItem";
            clearPacketsToolStripMenuItem.Size = new System.Drawing.Size(216, 24);
            clearPacketsToolStripMenuItem.Text = "&Clear Packets";
            clearPacketsToolStripMenuItem.Click += clearPacketsToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(213, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(216, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // savePacketsFileDialog
            // 
            savePacketsFileDialog.DefaultExt = "ptcap";
            savePacketsFileDialog.Filter = "Packet Capture|*.ptcap|All files|*.*";
            savePacketsFileDialog.Title = "Save Packet Capture";
            // 
            // openPacketsFileDialog
            // 
            openPacketsFileDialog.FileName = "packets.ptcap";
            openPacketsFileDialog.Filter = "Packet Capture|*.ptcap|All files|*.*";
            openPacketsFileDialog.Title = "Open Packet Capture File";
            // 
            // PacketCaptureTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(packetsSplitContainer);
            Controls.Add(titlePanel);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            Name = "PacketCaptureTabUserControl";
            Size = new System.Drawing.Size(669, 779);
            packetsSplitContainer.Panel1.ResumeLayout(false);
            packetsSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)packetsSplitContainer).EndInit();
            packetsSplitContainer.ResumeLayout(false);
            packetsListContextMenuStrip.ResumeLayout(false);
            packetDataContextMenuStrip.ResumeLayout(false);
            titlePanel.ResumeLayout(false);
            titlePanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)packetsMenuPictureBox).EndInit();
            packetsContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

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
        private System.Windows.Forms.Panel titlePanel;
        private System.Windows.Forms.PictureBox packetsMenuPictureBox;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.ContextMenuStrip packetsContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showPacketDecodeToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem18;
        private System.Windows.Forms.ToolStripMenuItem saveToFileToolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem openFileToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem17;
        private System.Windows.Forms.ToolStripMenuItem clearPacketsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog savePacketsFileDialog;
        private System.Windows.Forms.OpenFileDialog openPacketsFileDialog;
        private System.Windows.Forms.ImageList mainImageList;
    }
}
