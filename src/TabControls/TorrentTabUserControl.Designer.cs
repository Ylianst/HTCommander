namespace HTCommander.Controls
{
    partial class TorrentTabUserControl
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(TorrentTabUserControl));
            torrentSplitContainer = new System.Windows.Forms.SplitContainer();
            torrentListView = new System.Windows.Forms.ListView();
            columnHeader14 = new System.Windows.Forms.ColumnHeader();
            columnHeader16 = new System.Windows.Forms.ColumnHeader();
            columnHeader15 = new System.Windows.Forms.ColumnHeader();
            torrentContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            torrentPauseToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            torrentShareToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            torrentRequestToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem19 = new System.Windows.Forms.ToolStripSeparator();
            torrentSaveAsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem20 = new System.Windows.Forms.ToolStripSeparator();
            torrentDeleteToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            imageList = new System.Windows.Forms.ImageList(components);
            torrentTabControl = new System.Windows.Forms.TabControl();
            tabPage1 = new System.Windows.Forms.TabPage();
            torrentDetailsListView = new System.Windows.Forms.ListView();
            columnHeader13 = new System.Windows.Forms.ColumnHeader();
            columnHeader17 = new System.Windows.Forms.ColumnHeader();
            tabPage2 = new System.Windows.Forms.TabPage();
            torrentBlocksUserControl = new TorrentBlocksUserControl();
            torrentControlsPanel = new System.Windows.Forms.Panel();
            torrentAddFileButton = new System.Windows.Forms.Button();
            torrentMenuPictureBox = new System.Windows.Forms.PictureBox();
            torrentTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            showDetailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            torrentConnectButton = new System.Windows.Forms.Button();
            torrentTitleLabel = new System.Windows.Forms.Label();
            torrentSaveFileDialog = new System.Windows.Forms.SaveFileDialog();
            ((System.ComponentModel.ISupportInitialize)torrentSplitContainer).BeginInit();
            torrentSplitContainer.Panel1.SuspendLayout();
            torrentSplitContainer.Panel2.SuspendLayout();
            torrentSplitContainer.SuspendLayout();
            torrentContextMenuStrip.SuspendLayout();
            torrentTabControl.SuspendLayout();
            tabPage1.SuspendLayout();
            tabPage2.SuspendLayout();
            torrentControlsPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)torrentMenuPictureBox).BeginInit();
            torrentTabContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // torrentSplitContainer
            // 
            torrentSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            torrentSplitContainer.Location = new System.Drawing.Point(0, 46);
            torrentSplitContainer.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            torrentSplitContainer.Name = "torrentSplitContainer";
            torrentSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // torrentSplitContainer.Panel1
            // 
            torrentSplitContainer.Panel1.Controls.Add(torrentListView);
            // 
            // torrentSplitContainer.Panel2
            // 
            torrentSplitContainer.Panel2.Controls.Add(torrentTabControl);
            torrentSplitContainer.Size = new System.Drawing.Size(669, 444);
            torrentSplitContainer.SplitterDistance = 186;
            torrentSplitContainer.SplitterWidth = 5;
            torrentSplitContainer.TabIndex = 7;
            // 
            // torrentListView
            // 
            torrentListView.AllowDrop = true;
            torrentListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader14, columnHeader16, columnHeader15 });
            torrentListView.ContextMenuStrip = torrentContextMenuStrip;
            torrentListView.Dock = System.Windows.Forms.DockStyle.Fill;
            torrentListView.FullRowSelect = true;
            torrentListView.Location = new System.Drawing.Point(0, 0);
            torrentListView.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            torrentListView.Name = "torrentListView";
            torrentListView.Size = new System.Drawing.Size(669, 186);
            torrentListView.SmallImageList = imageList;
            torrentListView.TabIndex = 0;
            torrentListView.UseCompatibleStateImageBehavior = false;
            torrentListView.View = System.Windows.Forms.View.Details;
            torrentListView.ColumnClick += torrentListView_ColumnClick;
            torrentListView.SelectedIndexChanged += torrentListView_SelectedIndexChanged;
            torrentListView.DragDrop += torrentListView_DragDrop;
            torrentListView.DragEnter += torrentListView_DragEnter;
            torrentListView.KeyDown += torrentListView_KeyDown;
            torrentListView.Resize += torrentListView_Resize;
            // 
            // columnHeader14
            // 
            columnHeader14.Text = "File";
            columnHeader14.Width = 200;
            // 
            // columnHeader16
            // 
            columnHeader16.Text = "Mode";
            columnHeader16.Width = 80;
            // 
            // columnHeader15
            // 
            columnHeader15.Text = "Description";
            columnHeader15.Width = 300;
            // 
            // torrentContextMenuStrip
            // 
            torrentContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            torrentContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { torrentPauseToolStripMenuItem, torrentShareToolStripMenuItem, torrentRequestToolStripMenuItem, toolStripMenuItem19, torrentSaveAsToolStripMenuItem, toolStripMenuItem20, torrentDeleteToolStripMenuItem });
            torrentContextMenuStrip.Name = "mailContextMenuStrip";
            torrentContextMenuStrip.Size = new System.Drawing.Size(139, 136);
            torrentContextMenuStrip.Opening += torrentContextMenuStrip_Opening;
            // 
            // torrentPauseToolStripMenuItem
            // 
            torrentPauseToolStripMenuItem.Name = "torrentPauseToolStripMenuItem";
            torrentPauseToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            torrentPauseToolStripMenuItem.Text = "Pause";
            torrentPauseToolStripMenuItem.Click += torrentPauseToolStripMenuItem_Click;
            // 
            // torrentShareToolStripMenuItem
            // 
            torrentShareToolStripMenuItem.Name = "torrentShareToolStripMenuItem";
            torrentShareToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            torrentShareToolStripMenuItem.Text = "Share";
            torrentShareToolStripMenuItem.Click += torrentShareToolStripMenuItem_Click;
            // 
            // torrentRequestToolStripMenuItem
            // 
            torrentRequestToolStripMenuItem.Name = "torrentRequestToolStripMenuItem";
            torrentRequestToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            torrentRequestToolStripMenuItem.Text = "Request";
            torrentRequestToolStripMenuItem.Click += torrentRequestToolStripMenuItem_Click;
            // 
            // toolStripMenuItem19
            // 
            toolStripMenuItem19.Name = "toolStripMenuItem19";
            toolStripMenuItem19.Size = new System.Drawing.Size(135, 6);
            // 
            // torrentSaveAsToolStripMenuItem
            // 
            torrentSaveAsToolStripMenuItem.Name = "torrentSaveAsToolStripMenuItem";
            torrentSaveAsToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            torrentSaveAsToolStripMenuItem.Text = "Save As...";
            torrentSaveAsToolStripMenuItem.Click += torrentSaveAsToolStripMenuItem_Click;
            // 
            // toolStripMenuItem20
            // 
            toolStripMenuItem20.Name = "toolStripMenuItem20";
            toolStripMenuItem20.Size = new System.Drawing.Size(135, 6);
            // 
            // torrentDeleteToolStripMenuItem
            // 
            torrentDeleteToolStripMenuItem.Name = "torrentDeleteToolStripMenuItem";
            torrentDeleteToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            torrentDeleteToolStripMenuItem.Text = "&Delete";
            torrentDeleteToolStripMenuItem.Click += torrentDeleteToolStripMenuItem_Click;
            // 
            // imageList
            // 
            imageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth16Bit;
            imageList.ImageStream = (System.Windows.Forms.ImageListStreamer)resources.GetObject("imageList.ImageStream");
            imageList.TransparentColor = System.Drawing.Color.Transparent;
            imageList.Images.SetKeyName(0, "GreenCheck.png");
            imageList.Images.SetKeyName(1, "RedCheck.png");
            imageList.Images.SetKeyName(2, "info.ico");
            imageList.Images.SetKeyName(3, "LocationPin2.png");
            imageList.Images.SetKeyName(4, "left-arrow.png");
            imageList.Images.SetKeyName(5, "right-arrow.png");
            imageList.Images.SetKeyName(6, "terminal-32.png");
            imageList.Images.SetKeyName(7, "talking.ico");
            imageList.Images.SetKeyName(8, "mail-200.png");
            imageList.Images.SetKeyName(9, "file-20.png");
            imageList.Images.SetKeyName(10, "file-empty-20.png");
            // 
            // torrentTabControl
            // 
            torrentTabControl.Controls.Add(tabPage1);
            torrentTabControl.Controls.Add(tabPage2);
            torrentTabControl.Dock = System.Windows.Forms.DockStyle.Fill;
            torrentTabControl.Location = new System.Drawing.Point(0, 0);
            torrentTabControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            torrentTabControl.Name = "torrentTabControl";
            torrentTabControl.SelectedIndex = 0;
            torrentTabControl.Size = new System.Drawing.Size(669, 253);
            torrentTabControl.TabIndex = 0;
            // 
            // tabPage1
            // 
            tabPage1.Controls.Add(torrentDetailsListView);
            tabPage1.Location = new System.Drawing.Point(4, 29);
            tabPage1.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            tabPage1.Name = "tabPage1";
            tabPage1.Padding = new System.Windows.Forms.Padding(3, 1, 3, 1);
            tabPage1.Size = new System.Drawing.Size(661, 220);
            tabPage1.TabIndex = 0;
            tabPage1.Text = "Details";
            tabPage1.UseVisualStyleBackColor = true;
            // 
            // torrentDetailsListView
            // 
            torrentDetailsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader13, columnHeader17 });
            torrentDetailsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            torrentDetailsListView.FullRowSelect = true;
            torrentDetailsListView.Location = new System.Drawing.Point(3, 1);
            torrentDetailsListView.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            torrentDetailsListView.Name = "torrentDetailsListView";
            torrentDetailsListView.Size = new System.Drawing.Size(655, 218);
            torrentDetailsListView.TabIndex = 0;
            torrentDetailsListView.UseCompatibleStateImageBehavior = false;
            torrentDetailsListView.View = System.Windows.Forms.View.Details;
            torrentDetailsListView.Resize += torrentDetailsListView_Resize;
            // 
            // columnHeader13
            // 
            columnHeader13.Text = "Property";
            columnHeader13.Width = 120;
            // 
            // columnHeader17
            // 
            columnHeader17.Text = "Value";
            columnHeader17.Width = 400;
            // 
            // tabPage2
            // 
            tabPage2.Controls.Add(torrentBlocksUserControl);
            tabPage2.Location = new System.Drawing.Point(4, 29);
            tabPage2.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            tabPage2.Name = "tabPage2";
            tabPage2.Padding = new System.Windows.Forms.Padding(3, 1, 3, 1);
            tabPage2.Size = new System.Drawing.Size(661, 387);
            tabPage2.TabIndex = 1;
            tabPage2.Text = "Blocks";
            tabPage2.UseVisualStyleBackColor = true;
            // 
            // torrentBlocksUserControl
            // 
            torrentBlocksUserControl.AutoScroll = true;
            torrentBlocksUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            torrentBlocksUserControl.Location = new System.Drawing.Point(3, 1);
            torrentBlocksUserControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            torrentBlocksUserControl.Name = "torrentBlocksUserControl";
            torrentBlocksUserControl.Size = new System.Drawing.Size(655, 385);
            torrentBlocksUserControl.TabIndex = 0;
            // 
            // torrentControlsPanel
            // 
            torrentControlsPanel.BackColor = System.Drawing.Color.Silver;
            torrentControlsPanel.Controls.Add(torrentAddFileButton);
            torrentControlsPanel.Controls.Add(torrentMenuPictureBox);
            torrentControlsPanel.Controls.Add(torrentConnectButton);
            torrentControlsPanel.Controls.Add(torrentTitleLabel);
            torrentControlsPanel.Dock = System.Windows.Forms.DockStyle.Top;
            torrentControlsPanel.Location = new System.Drawing.Point(0, 0);
            torrentControlsPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            torrentControlsPanel.Name = "torrentControlsPanel";
            torrentControlsPanel.Size = new System.Drawing.Size(669, 46);
            torrentControlsPanel.TabIndex = 6;
            // 
            // torrentAddFileButton
            // 
            torrentAddFileButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            torrentAddFileButton.Location = new System.Drawing.Point(421, 5);
            torrentAddFileButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            torrentAddFileButton.Name = "torrentAddFileButton";
            torrentAddFileButton.Size = new System.Drawing.Size(100, 35);
            torrentAddFileButton.TabIndex = 5;
            torrentAddFileButton.Text = "Add &File...";
            torrentAddFileButton.UseVisualStyleBackColor = true;
            torrentAddFileButton.Click += torrentAddFileButton_Click;
            // 
            // torrentMenuPictureBox
            // 
            torrentMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            torrentMenuPictureBox.ContextMenuStrip = torrentTabContextMenuStrip;
            torrentMenuPictureBox.Image = Properties.Resources.MenuIcon;
            torrentMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            torrentMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            torrentMenuPictureBox.Name = "torrentMenuPictureBox";
            torrentMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            torrentMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            torrentMenuPictureBox.TabIndex = 4;
            torrentMenuPictureBox.TabStop = false;
            torrentMenuPictureBox.MouseClick += torrentMenuPictureBox_MouseClick;
            // 
            // torrentTabContextMenuStrip
            // 
            torrentTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            torrentTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { showDetailsToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            torrentTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            torrentTabContextMenuStrip.Size = new System.Drawing.Size(165, 58);
            torrentTabContextMenuStrip.Opening += torrentTabContextMenuStrip_Opening;
            // 
            // showDetailsToolStripMenuItem
            // 
            showDetailsToolStripMenuItem.CheckOnClick = true;
            showDetailsToolStripMenuItem.Name = "showDetailsToolStripMenuItem";
            showDetailsToolStripMenuItem.Size = new System.Drawing.Size(164, 24);
            showDetailsToolStripMenuItem.Text = "Show &Details";
            showDetailsToolStripMenuItem.Click += showDetailsToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(161, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(164, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // torrentConnectButton
            // 
            torrentConnectButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            torrentConnectButton.Location = new System.Drawing.Point(527, 5);
            torrentConnectButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            torrentConnectButton.Name = "torrentConnectButton";
            torrentConnectButton.Size = new System.Drawing.Size(100, 35);
            torrentConnectButton.TabIndex = 2;
            torrentConnectButton.Text = "&Activate";
            torrentConnectButton.UseVisualStyleBackColor = true;
            torrentConnectButton.Click += torrentConnectButton_Click;
            // 
            // torrentTitleLabel
            // 
            torrentTitleLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            torrentTitleLabel.AutoSize = true;
            torrentTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            torrentTitleLabel.Location = new System.Drawing.Point(4, 8);
            torrentTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            torrentTitleLabel.Name = "torrentTitleLabel";
            torrentTitleLabel.Size = new System.Drawing.Size(75, 25);
            torrentTitleLabel.TabIndex = 1;
            torrentTitleLabel.Text = "Torrent";
            // 
            // torrentSaveFileDialog
            // 
            torrentSaveFileDialog.Title = "Save Torrent File";
            // 
            // TorrentTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(torrentSplitContainer);
            Controls.Add(torrentControlsPanel);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            Name = "TorrentTabUserControl";
            Size = new System.Drawing.Size(669, 490);
            torrentSplitContainer.Panel1.ResumeLayout(false);
            torrentSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)torrentSplitContainer).EndInit();
            torrentSplitContainer.ResumeLayout(false);
            torrentContextMenuStrip.ResumeLayout(false);
            torrentTabControl.ResumeLayout(false);
            tabPage1.ResumeLayout(false);
            tabPage2.ResumeLayout(false);
            torrentControlsPanel.ResumeLayout(false);
            torrentControlsPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)torrentMenuPictureBox).EndInit();
            torrentTabContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.SplitContainer torrentSplitContainer;
        private System.Windows.Forms.ListView torrentListView;
        private System.Windows.Forms.ColumnHeader columnHeader14;
        private System.Windows.Forms.ColumnHeader columnHeader16;
        private System.Windows.Forms.ColumnHeader columnHeader15;
        private System.Windows.Forms.ContextMenuStrip torrentContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem torrentPauseToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem torrentShareToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem torrentRequestToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem19;
        private System.Windows.Forms.ToolStripMenuItem torrentSaveAsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem20;
        private System.Windows.Forms.ToolStripMenuItem torrentDeleteToolStripMenuItem;
        private System.Windows.Forms.TabControl torrentTabControl;
        private System.Windows.Forms.TabPage tabPage1;
        private System.Windows.Forms.ListView torrentDetailsListView;
        private System.Windows.Forms.ColumnHeader columnHeader13;
        private System.Windows.Forms.ColumnHeader columnHeader17;
        private System.Windows.Forms.TabPage tabPage2;
        private TorrentBlocksUserControl torrentBlocksUserControl;
        private System.Windows.Forms.Panel torrentControlsPanel;
        private System.Windows.Forms.Button torrentAddFileButton;
        private System.Windows.Forms.PictureBox torrentMenuPictureBox;
        private System.Windows.Forms.ContextMenuStrip torrentTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showDetailsToolStripMenuItem;
        private System.Windows.Forms.Button torrentConnectButton;
        private System.Windows.Forms.Label torrentTitleLabel;
        private System.Windows.Forms.SaveFileDialog torrentSaveFileDialog;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
        private System.Windows.Forms.ImageList imageList;
    }
}
