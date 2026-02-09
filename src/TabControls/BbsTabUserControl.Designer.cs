namespace HTCommander.Controls
{
    partial class BbsTabUserControl
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
            if (disposing)
            {
                broker?.Dispose();
                if (components != null)
                {
                    components.Dispose();
                }
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
            System.Windows.Forms.ListViewGroup listViewGroup1 = new System.Windows.Forms.ListViewGroup("Generic Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup2 = new System.Windows.Forms.ListViewGroup("APRS Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup3 = new System.Windows.Forms.ListViewGroup("Terminal Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(BbsTabUserControl));
            bbsSplitContainer = new System.Windows.Forms.SplitContainer();
            bbsListView = new System.Windows.Forms.ListView();
            columnHeader10 = new System.Windows.Forms.ColumnHeader();
            columnHeader11 = new System.Windows.Forms.ColumnHeader();
            columnHeader12 = new System.Windows.Forms.ColumnHeader();
            mainImageList = new System.Windows.Forms.ImageList(components);
            bbsTextBox = new System.Windows.Forms.RichTextBox();
            bbsTopPanel = new System.Windows.Forms.Panel();
            bbsMenuPictureBox = new System.Windows.Forms.PictureBox();
            bbsConnectButton = new System.Windows.Forms.Button();
            bbsTitleLabel = new System.Windows.Forms.Label();
            bbsTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            viewTrafficToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem11 = new System.Windows.Forms.ToolStripSeparator();
            clearStatsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)bbsSplitContainer).BeginInit();
            bbsSplitContainer.Panel1.SuspendLayout();
            bbsSplitContainer.Panel2.SuspendLayout();
            bbsSplitContainer.SuspendLayout();
            bbsTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)bbsMenuPictureBox).BeginInit();
            bbsTabContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // bbsSplitContainer
            // 
            bbsSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            bbsSplitContainer.Location = new System.Drawing.Point(0, 34);
            bbsSplitContainer.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            bbsSplitContainer.Name = "bbsSplitContainer";
            bbsSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // bbsSplitContainer.Panel1
            // 
            bbsSplitContainer.Panel1.Controls.Add(bbsListView);
            // 
            // bbsSplitContainer.Panel2
            // 
            bbsSplitContainer.Panel2.Controls.Add(bbsTextBox);
            bbsSplitContainer.Size = new System.Drawing.Size(585, 335);
            bbsSplitContainer.SplitterDistance = 59;
            bbsSplitContainer.TabIndex = 7;
            // 
            // bbsListView
            // 
            bbsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader10, columnHeader11, columnHeader12 });
            bbsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            bbsListView.FullRowSelect = true;
            bbsListView.GridLines = true;
            listViewGroup1.Header = "Generic Stations";
            listViewGroup1.Name = "Generic Stations";
            listViewGroup2.Header = "APRS Stations";
            listViewGroup2.Name = "APRS Stations";
            listViewGroup3.Header = "Terminal Stations";
            listViewGroup3.Name = "Terminal Stations";
            bbsListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] { listViewGroup1, listViewGroup2, listViewGroup3 });
            bbsListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            bbsListView.Location = new System.Drawing.Point(0, 0);
            bbsListView.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            bbsListView.Name = "bbsListView";
            bbsListView.Size = new System.Drawing.Size(585, 59);
            bbsListView.SmallImageList = mainImageList;
            bbsListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            bbsListView.TabIndex = 6;
            bbsListView.UseCompatibleStateImageBehavior = false;
            bbsListView.View = System.Windows.Forms.View.Details;
            bbsListView.Resize += bbsListView_Resize;
            // 
            // columnHeader10
            // 
            columnHeader10.Text = "Call Sign";
            columnHeader10.Width = 100;
            // 
            // columnHeader11
            // 
            columnHeader11.Text = "Last Seen";
            columnHeader11.Width = 133;
            // 
            // columnHeader12
            // 
            columnHeader12.Text = "Stats";
            columnHeader12.Width = 251;
            // 
            // mainImageList
            // 
            mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit;
            mainImageList.ImageStream = (System.Windows.Forms.ImageListStreamer)resources.GetObject("mainImageList.ImageStream");
            mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            mainImageList.Images.SetKeyName(0, "talking.ico");
            // 
            // bbsTextBox
            // 
            bbsTextBox.BackColor = System.Drawing.Color.Black;
            bbsTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            bbsTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            bbsTextBox.Font = new System.Drawing.Font("Courier New", 12F, System.Drawing.FontStyle.Bold);
            bbsTextBox.ForeColor = System.Drawing.Color.Gainsboro;
            bbsTextBox.Location = new System.Drawing.Point(0, 0);
            bbsTextBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            bbsTextBox.Name = "bbsTextBox";
            bbsTextBox.ReadOnly = true;
            bbsTextBox.Size = new System.Drawing.Size(585, 272);
            bbsTextBox.TabIndex = 5;
            bbsTextBox.Text = "";
            // 
            // bbsTopPanel
            // 
            bbsTopPanel.BackColor = System.Drawing.Color.Silver;
            bbsTopPanel.Controls.Add(bbsMenuPictureBox);
            bbsTopPanel.Controls.Add(bbsConnectButton);
            bbsTopPanel.Controls.Add(bbsTitleLabel);
            bbsTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            bbsTopPanel.Location = new System.Drawing.Point(0, 0);
            bbsTopPanel.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            bbsTopPanel.Name = "bbsTopPanel";
            bbsTopPanel.Size = new System.Drawing.Size(585, 34);
            bbsTopPanel.TabIndex = 5;
            // 
            // bbsMenuPictureBox
            // 
            bbsMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            bbsMenuPictureBox.Image = Properties.Resources.MenuIcon;
            bbsMenuPictureBox.Location = new System.Drawing.Point(557, 6);
            bbsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            bbsMenuPictureBox.Name = "bbsMenuPictureBox";
            bbsMenuPictureBox.Size = new System.Drawing.Size(24, 23);
            bbsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            bbsMenuPictureBox.TabIndex = 4;
            bbsMenuPictureBox.TabStop = false;
            bbsMenuPictureBox.MouseClick += bbsMenuPictureBox_MouseClick;
            // 
            // bbsConnectButton
            // 
            bbsConnectButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            bbsConnectButton.Location = new System.Drawing.Point(461, 4);
            bbsConnectButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            bbsConnectButton.Name = "bbsConnectButton";
            bbsConnectButton.Size = new System.Drawing.Size(88, 26);
            bbsConnectButton.TabIndex = 2;
            bbsConnectButton.Text = "&Activate";
            bbsConnectButton.UseVisualStyleBackColor = true;
            bbsConnectButton.Click += bbsConnectButton_Click;
            // 
            // bbsTitleLabel
            // 
            bbsTitleLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            bbsTitleLabel.AutoSize = true;
            bbsTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            bbsTitleLabel.Location = new System.Drawing.Point(6, 6);
            bbsTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            bbsTitleLabel.Name = "bbsTitleLabel";
            bbsTitleLabel.Size = new System.Drawing.Size(42, 20);
            bbsTitleLabel.TabIndex = 0;
            bbsTitleLabel.Text = "BBS";
            // 
            // bbsTabContextMenuStrip
            // 
            bbsTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            bbsTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { viewTrafficToolStripMenuItem, toolStripMenuItem11, clearStatsToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            bbsTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            bbsTabContextMenuStrip.Size = new System.Drawing.Size(136, 82);
            // 
            // viewTrafficToolStripMenuItem
            // 
            viewTrafficToolStripMenuItem.Checked = true;
            viewTrafficToolStripMenuItem.CheckOnClick = true;
            viewTrafficToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            viewTrafficToolStripMenuItem.Name = "viewTrafficToolStripMenuItem";
            viewTrafficToolStripMenuItem.Size = new System.Drawing.Size(135, 22);
            viewTrafficToolStripMenuItem.Text = "&View Traffic";
            viewTrafficToolStripMenuItem.Click += viewTrafficToolStripMenuItem_Click;
            // 
            // toolStripMenuItem11
            // 
            toolStripMenuItem11.Name = "toolStripMenuItem11";
            toolStripMenuItem11.Size = new System.Drawing.Size(132, 6);
            // 
            // clearStatsToolStripMenuItem
            // 
            clearStatsToolStripMenuItem.Name = "clearStatsToolStripMenuItem";
            clearStatsToolStripMenuItem.Size = new System.Drawing.Size(135, 22);
            clearStatsToolStripMenuItem.Text = "&Clear Stats";
            clearStatsToolStripMenuItem.Click += clearStatsToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(132, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(135, 22);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // BbsTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(bbsSplitContainer);
            Controls.Add(bbsTopPanel);
            Name = "BbsTabUserControl";
            Size = new System.Drawing.Size(585, 369);
            bbsSplitContainer.Panel1.ResumeLayout(false);
            bbsSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)bbsSplitContainer).EndInit();
            bbsSplitContainer.ResumeLayout(false);
            bbsTopPanel.ResumeLayout(false);
            bbsTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)bbsMenuPictureBox).EndInit();
            bbsTabContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.SplitContainer bbsSplitContainer;
        private System.Windows.Forms.ListView bbsListView;
        private System.Windows.Forms.ColumnHeader columnHeader10;
        private System.Windows.Forms.ColumnHeader columnHeader11;
        private System.Windows.Forms.ColumnHeader columnHeader12;
        private System.Windows.Forms.RichTextBox bbsTextBox;
        private System.Windows.Forms.Panel bbsTopPanel;
        private System.Windows.Forms.PictureBox bbsMenuPictureBox;
        private System.Windows.Forms.Button bbsConnectButton;
        private System.Windows.Forms.Label bbsTitleLabel;
        private System.Windows.Forms.ContextMenuStrip bbsTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem viewTrafficToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem11;
        private System.Windows.Forms.ToolStripMenuItem clearStatsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
        private System.Windows.Forms.ImageList mainImageList;
    }
}
