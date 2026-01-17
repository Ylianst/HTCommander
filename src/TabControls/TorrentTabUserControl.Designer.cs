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
            this.components = new System.ComponentModel.Container();
            this.torrentSplitContainer = new System.Windows.Forms.SplitContainer();
            this.torrentListView = new System.Windows.Forms.ListView();
            this.columnHeader14 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader16 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader15 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.torrentContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.torrentPauseToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentShareToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentRequestToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem19 = new System.Windows.Forms.ToolStripSeparator();
            this.torrentSaveAsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem20 = new System.Windows.Forms.ToolStripSeparator();
            this.torrentDeleteToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentTabControl = new System.Windows.Forms.TabControl();
            this.tabPage1 = new System.Windows.Forms.TabPage();
            this.torrentDetailsListView = new System.Windows.Forms.ListView();
            this.columnHeader13 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader17 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.tabPage2 = new System.Windows.Forms.TabPage();
            this.torrentBlocksUserControl = new HTCommander.TorrentBlocksUserControl();
            this.torrentControlsPanel = new System.Windows.Forms.Panel();
            this.torrentAddFileButton = new System.Windows.Forms.Button();
            this.torrentMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.torrentTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showDetailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentConnectButton = new System.Windows.Forms.Button();
            this.torrentTitleLabel = new System.Windows.Forms.Label();
            this.torrentSaveFileDialog = new System.Windows.Forms.SaveFileDialog();
            ((System.ComponentModel.ISupportInitialize)(this.torrentSplitContainer)).BeginInit();
            this.torrentSplitContainer.Panel1.SuspendLayout();
            this.torrentSplitContainer.Panel2.SuspendLayout();
            this.torrentSplitContainer.SuspendLayout();
            this.torrentContextMenuStrip.SuspendLayout();
            this.torrentTabControl.SuspendLayout();
            this.tabPage1.SuspendLayout();
            this.tabPage2.SuspendLayout();
            this.torrentControlsPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.torrentMenuPictureBox)).BeginInit();
            this.torrentTabContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // torrentSplitContainer
            // 
            this.torrentSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentSplitContainer.Location = new System.Drawing.Point(0, 37);
            this.torrentSplitContainer.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.torrentSplitContainer.Name = "torrentSplitContainer";
            this.torrentSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // torrentSplitContainer.Panel1
            // 
            this.torrentSplitContainer.Panel1.Controls.Add(this.torrentListView);
            // 
            // torrentSplitContainer.Panel2
            // 
            this.torrentSplitContainer.Panel2.Controls.Add(this.torrentTabControl);
            this.torrentSplitContainer.Size = new System.Drawing.Size(669, 586);
            this.torrentSplitContainer.SplitterDistance = 247;
            this.torrentSplitContainer.TabIndex = 7;
            // 
            // torrentListView
            // 
            this.torrentListView.AllowDrop = true;
            this.torrentListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader14,
            this.columnHeader16,
            this.columnHeader15});
            this.torrentListView.ContextMenuStrip = this.torrentContextMenuStrip;
            this.torrentListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentListView.FullRowSelect = true;
            this.torrentListView.HideSelection = false;
            this.torrentListView.Location = new System.Drawing.Point(0, 0);
            this.torrentListView.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.torrentListView.Name = "torrentListView";
            this.torrentListView.Size = new System.Drawing.Size(669, 247);
            this.torrentListView.TabIndex = 0;
            this.torrentListView.UseCompatibleStateImageBehavior = false;
            this.torrentListView.View = System.Windows.Forms.View.Details;
            this.torrentListView.SelectedIndexChanged += new System.EventHandler(this.torrentListView_SelectedIndexChanged);
            this.torrentListView.DragDrop += new System.Windows.Forms.DragEventHandler(this.torrentListView_DragDrop);
            this.torrentListView.DragEnter += new System.Windows.Forms.DragEventHandler(this.torrentListView_DragEnter);
            this.torrentListView.KeyDown += new System.Windows.Forms.KeyEventHandler(this.torrentListView_KeyDown);
            this.torrentListView.Resize += new System.EventHandler(this.torrentListView_Resize);
            // 
            // columnHeader14
            // 
            this.columnHeader14.Text = "File";
            this.columnHeader14.Width = 200;
            // 
            // columnHeader16
            // 
            this.columnHeader16.Text = "Mode";
            this.columnHeader16.Width = 80;
            // 
            // columnHeader15
            // 
            this.columnHeader15.Text = "Description";
            this.columnHeader15.Width = 300;
            // 
            // torrentContextMenuStrip
            // 
            this.torrentContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.torrentContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.torrentPauseToolStripMenuItem,
            this.torrentShareToolStripMenuItem,
            this.torrentRequestToolStripMenuItem,
            this.toolStripMenuItem19,
            this.torrentSaveAsToolStripMenuItem,
            this.toolStripMenuItem20,
            this.torrentDeleteToolStripMenuItem});
            this.torrentContextMenuStrip.Name = "mailContextMenuStrip";
            this.torrentContextMenuStrip.Size = new System.Drawing.Size(139, 136);
            this.torrentContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.torrentContextMenuStrip_Opening);
            // 
            // torrentPauseToolStripMenuItem
            // 
            this.torrentPauseToolStripMenuItem.Name = "torrentPauseToolStripMenuItem";
            this.torrentPauseToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            this.torrentPauseToolStripMenuItem.Text = "Pause";
            this.torrentPauseToolStripMenuItem.Click += new System.EventHandler(this.torrentPauseToolStripMenuItem_Click);
            // 
            // torrentShareToolStripMenuItem
            // 
            this.torrentShareToolStripMenuItem.Name = "torrentShareToolStripMenuItem";
            this.torrentShareToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            this.torrentShareToolStripMenuItem.Text = "Share";
            this.torrentShareToolStripMenuItem.Click += new System.EventHandler(this.torrentShareToolStripMenuItem_Click);
            // 
            // torrentRequestToolStripMenuItem
            // 
            this.torrentRequestToolStripMenuItem.Name = "torrentRequestToolStripMenuItem";
            this.torrentRequestToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            this.torrentRequestToolStripMenuItem.Text = "Request";
            this.torrentRequestToolStripMenuItem.Click += new System.EventHandler(this.torrentRequestToolStripMenuItem_Click);
            // 
            // toolStripMenuItem19
            // 
            this.toolStripMenuItem19.Name = "toolStripMenuItem19";
            this.toolStripMenuItem19.Size = new System.Drawing.Size(135, 6);
            // 
            // torrentSaveAsToolStripMenuItem
            // 
            this.torrentSaveAsToolStripMenuItem.Name = "torrentSaveAsToolStripMenuItem";
            this.torrentSaveAsToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            this.torrentSaveAsToolStripMenuItem.Text = "Save As...";
            this.torrentSaveAsToolStripMenuItem.Click += new System.EventHandler(this.torrentSaveAsToolStripMenuItem_Click);
            // 
            // toolStripMenuItem20
            // 
            this.toolStripMenuItem20.Name = "toolStripMenuItem20";
            this.toolStripMenuItem20.Size = new System.Drawing.Size(135, 6);
            // 
            // torrentDeleteToolStripMenuItem
            // 
            this.torrentDeleteToolStripMenuItem.Name = "torrentDeleteToolStripMenuItem";
            this.torrentDeleteToolStripMenuItem.Size = new System.Drawing.Size(138, 24);
            this.torrentDeleteToolStripMenuItem.Text = "&Delete";
            this.torrentDeleteToolStripMenuItem.Click += new System.EventHandler(this.torrentDeleteToolStripMenuItem_Click);
            // 
            // torrentTabControl
            // 
            this.torrentTabControl.Controls.Add(this.tabPage1);
            this.torrentTabControl.Controls.Add(this.tabPage2);
            this.torrentTabControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentTabControl.Location = new System.Drawing.Point(0, 0);
            this.torrentTabControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.torrentTabControl.Name = "torrentTabControl";
            this.torrentTabControl.SelectedIndex = 0;
            this.torrentTabControl.Size = new System.Drawing.Size(669, 335);
            this.torrentTabControl.TabIndex = 0;
            // 
            // tabPage1
            // 
            this.tabPage1.Controls.Add(this.torrentDetailsListView);
            this.tabPage1.Location = new System.Drawing.Point(4, 25);
            this.tabPage1.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.tabPage1.Name = "tabPage1";
            this.tabPage1.Padding = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.tabPage1.Size = new System.Drawing.Size(661, 306);
            this.tabPage1.TabIndex = 0;
            this.tabPage1.Text = "Details";
            this.tabPage1.UseVisualStyleBackColor = true;
            // 
            // torrentDetailsListView
            // 
            this.torrentDetailsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader13,
            this.columnHeader17});
            this.torrentDetailsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentDetailsListView.FullRowSelect = true;
            this.torrentDetailsListView.HideSelection = false;
            this.torrentDetailsListView.Location = new System.Drawing.Point(3, 1);
            this.torrentDetailsListView.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.torrentDetailsListView.Name = "torrentDetailsListView";
            this.torrentDetailsListView.Size = new System.Drawing.Size(655, 304);
            this.torrentDetailsListView.TabIndex = 0;
            this.torrentDetailsListView.UseCompatibleStateImageBehavior = false;
            this.torrentDetailsListView.View = System.Windows.Forms.View.Details;
            this.torrentDetailsListView.Resize += new System.EventHandler(this.torrentDetailsListView_Resize);
            // 
            // columnHeader13
            // 
            this.columnHeader13.Text = "Property";
            this.columnHeader13.Width = 120;
            // 
            // columnHeader17
            // 
            this.columnHeader17.Text = "Value";
            this.columnHeader17.Width = 400;
            // 
            // tabPage2
            // 
            this.tabPage2.Controls.Add(this.torrentBlocksUserControl);
            this.tabPage2.Location = new System.Drawing.Point(4, 25);
            this.tabPage2.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.tabPage2.Name = "tabPage2";
            this.tabPage2.Padding = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.tabPage2.Size = new System.Drawing.Size(661, 306);
            this.tabPage2.TabIndex = 1;
            this.tabPage2.Text = "Blocks";
            this.tabPage2.UseVisualStyleBackColor = true;
            // 
            // torrentBlocksUserControl
            // 
            this.torrentBlocksUserControl.AutoScroll = true;
            this.torrentBlocksUserControl.Blocks = null;
            this.torrentBlocksUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentBlocksUserControl.Location = new System.Drawing.Point(3, 1);
            this.torrentBlocksUserControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.torrentBlocksUserControl.Name = "torrentBlocksUserControl";
            this.torrentBlocksUserControl.Size = new System.Drawing.Size(655, 304);
            this.torrentBlocksUserControl.TabIndex = 0;
            // 
            // torrentControlsPanel
            // 
            this.torrentControlsPanel.BackColor = System.Drawing.Color.Silver;
            this.torrentControlsPanel.Controls.Add(this.torrentAddFileButton);
            this.torrentControlsPanel.Controls.Add(this.torrentMenuPictureBox);
            this.torrentControlsPanel.Controls.Add(this.torrentConnectButton);
            this.torrentControlsPanel.Controls.Add(this.torrentTitleLabel);
            this.torrentControlsPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.torrentControlsPanel.Location = new System.Drawing.Point(0, 0);
            this.torrentControlsPanel.Margin = new System.Windows.Forms.Padding(4);
            this.torrentControlsPanel.Name = "torrentControlsPanel";
            this.torrentControlsPanel.Size = new System.Drawing.Size(669, 37);
            this.torrentControlsPanel.TabIndex = 6;
            // 
            // torrentAddFileButton
            // 
            this.torrentAddFileButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.torrentAddFileButton.Location = new System.Drawing.Point(421, 4);
            this.torrentAddFileButton.Margin = new System.Windows.Forms.Padding(4);
            this.torrentAddFileButton.Name = "torrentAddFileButton";
            this.torrentAddFileButton.Size = new System.Drawing.Size(100, 28);
            this.torrentAddFileButton.TabIndex = 5;
            this.torrentAddFileButton.Text = "Add &File...";
            this.torrentAddFileButton.UseVisualStyleBackColor = true;
            this.torrentAddFileButton.Click += new System.EventHandler(this.torrentAddFileButton_Click);
            // 
            // torrentMenuPictureBox
            // 
            this.torrentMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.torrentMenuPictureBox.ContextMenuStrip = this.torrentTabContextMenuStrip;
            this.torrentMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.torrentMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.torrentMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.torrentMenuPictureBox.Name = "torrentMenuPictureBox";
            this.torrentMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.torrentMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.torrentMenuPictureBox.TabIndex = 4;
            this.torrentMenuPictureBox.TabStop = false;
            this.torrentMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.torrentMenuPictureBox_MouseClick);
            // 
            // torrentTabContextMenuStrip
            // 
            this.torrentTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.torrentTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showDetailsToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.torrentTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.torrentTabContextMenuStrip.Size = new System.Drawing.Size(165, 58);
            this.torrentTabContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.torrentTabContextMenuStrip_Opening);
            // 
            // showDetailsToolStripMenuItem
            // 
            this.showDetailsToolStripMenuItem.CheckOnClick = true;
            this.showDetailsToolStripMenuItem.Name = "showDetailsToolStripMenuItem";
            this.showDetailsToolStripMenuItem.Size = new System.Drawing.Size(164, 24);
            this.showDetailsToolStripMenuItem.Text = "Show &Details";
            this.showDetailsToolStripMenuItem.Click += new System.EventHandler(this.showDetailsToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(161, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(164, 24);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // torrentConnectButton
            // 
            this.torrentConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.torrentConnectButton.Location = new System.Drawing.Point(527, 4);
            this.torrentConnectButton.Margin = new System.Windows.Forms.Padding(4);
            this.torrentConnectButton.Name = "torrentConnectButton";
            this.torrentConnectButton.Size = new System.Drawing.Size(100, 28);
            this.torrentConnectButton.TabIndex = 2;
            this.torrentConnectButton.Text = "&Activate";
            this.torrentConnectButton.UseVisualStyleBackColor = true;
            this.torrentConnectButton.Click += new System.EventHandler(this.torrentConnectButton_Click);
            // 
            // torrentTitleLabel
            // 
            this.torrentTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.torrentTitleLabel.AutoSize = true;
            this.torrentTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.torrentTitleLabel.Location = new System.Drawing.Point(4, 6);
            this.torrentTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.torrentTitleLabel.Name = "torrentTitleLabel";
            this.torrentTitleLabel.Size = new System.Drawing.Size(68, 25);
            this.torrentTitleLabel.TabIndex = 1;
            this.torrentTitleLabel.Text = "Torrent";
            // 
            // torrentSaveFileDialog
            // 
            this.torrentSaveFileDialog.Title = "Save Torrent File";
            // 
            // TorrentTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.torrentSplitContainer);
            this.Controls.Add(this.torrentControlsPanel);
            this.Name = "TorrentTabUserControl";
            this.Size = new System.Drawing.Size(669, 623);
            this.torrentSplitContainer.Panel1.ResumeLayout(false);
            this.torrentSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.torrentSplitContainer)).EndInit();
            this.torrentSplitContainer.ResumeLayout(false);
            this.torrentContextMenuStrip.ResumeLayout(false);
            this.torrentTabControl.ResumeLayout(false);
            this.tabPage1.ResumeLayout(false);
            this.tabPage2.ResumeLayout(false);
            this.torrentControlsPanel.ResumeLayout(false);
            this.torrentControlsPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.torrentMenuPictureBox)).EndInit();
            this.torrentTabContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

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
    }
}
