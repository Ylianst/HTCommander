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
            System.Windows.Forms.ListViewGroup listViewGroup1 = new System.Windows.Forms.ListViewGroup("Generic Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup2 = new System.Windows.Forms.ListViewGroup("APRS Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup3 = new System.Windows.Forms.ListViewGroup("Terminal Stations", System.Windows.Forms.HorizontalAlignment.Left);
            this.bbsSplitContainer = new System.Windows.Forms.SplitContainer();
            this.bbsListView = new System.Windows.Forms.ListView();
            this.columnHeader10 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader11 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader12 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.bbsTextBox = new System.Windows.Forms.RichTextBox();
            this.bbsTopPanel = new System.Windows.Forms.Panel();
            this.bbsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.bbsConnectButton = new System.Windows.Forms.Button();
            this.bbsTitleLabel = new System.Windows.Forms.Label();
            this.bbsTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.viewTrafficToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem11 = new System.Windows.Forms.ToolStripSeparator();
            this.clearStatsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            ((System.ComponentModel.ISupportInitialize)(this.bbsSplitContainer)).BeginInit();
            this.bbsSplitContainer.Panel1.SuspendLayout();
            this.bbsSplitContainer.Panel2.SuspendLayout();
            this.bbsSplitContainer.SuspendLayout();
            this.bbsTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.bbsMenuPictureBox)).BeginInit();
            this.bbsTabContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // bbsSplitContainer
            // 
            this.bbsSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.bbsSplitContainer.Location = new System.Drawing.Point(0, 37);
            this.bbsSplitContainer.Margin = new System.Windows.Forms.Padding(4);
            this.bbsSplitContainer.Name = "bbsSplitContainer";
            this.bbsSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // bbsSplitContainer.Panel1
            // 
            this.bbsSplitContainer.Panel1.Controls.Add(this.bbsListView);
            // 
            // bbsSplitContainer.Panel2
            // 
            this.bbsSplitContainer.Panel2.Controls.Add(this.bbsTextBox);
            this.bbsSplitContainer.Size = new System.Drawing.Size(669, 586);
            this.bbsSplitContainer.SplitterDistance = 105;
            this.bbsSplitContainer.SplitterWidth = 5;
            this.bbsSplitContainer.TabIndex = 7;
            // 
            // bbsListView
            // 
            this.bbsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader10,
            this.columnHeader11,
            this.columnHeader12});
            this.bbsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.bbsListView.FullRowSelect = true;
            this.bbsListView.GridLines = true;
            listViewGroup1.Header = "Generic Stations";
            listViewGroup1.Name = "Generic Stations";
            listViewGroup2.Header = "APRS Stations";
            listViewGroup2.Name = "APRS Stations";
            listViewGroup3.Header = "Terminal Stations";
            listViewGroup3.Name = "Terminal Stations";
            this.bbsListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] {
            listViewGroup1,
            listViewGroup2,
            listViewGroup3});
            this.bbsListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            this.bbsListView.HideSelection = false;
            this.bbsListView.Location = new System.Drawing.Point(0, 0);
            this.bbsListView.Margin = new System.Windows.Forms.Padding(4);
            this.bbsListView.Name = "bbsListView";
            this.bbsListView.Size = new System.Drawing.Size(669, 105);
            this.bbsListView.SmallImageList = this.mainImageList;
            this.bbsListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            this.bbsListView.TabIndex = 6;
            this.bbsListView.UseCompatibleStateImageBehavior = false;
            this.bbsListView.View = System.Windows.Forms.View.Details;
            this.bbsListView.Resize += new System.EventHandler(this.bbsListView_Resize);
            // 
            // columnHeader10
            // 
            this.columnHeader10.Text = "Call Sign";
            this.columnHeader10.Width = 100;
            // 
            // columnHeader11
            // 
            this.columnHeader11.Text = "Last Seen";
            this.columnHeader11.Width = 133;
            // 
            // columnHeader12
            // 
            this.columnHeader12.Text = "Stats";
            this.columnHeader12.Width = 251;
            // 
            // bbsTextBox
            // 
            this.bbsTextBox.BackColor = System.Drawing.Color.Black;
            this.bbsTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.bbsTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.bbsTextBox.Font = new System.Drawing.Font("Courier New", 12F, System.Drawing.FontStyle.Bold);
            this.bbsTextBox.ForeColor = System.Drawing.Color.Gainsboro;
            this.bbsTextBox.Location = new System.Drawing.Point(0, 0);
            this.bbsTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.bbsTextBox.Name = "bbsTextBox";
            this.bbsTextBox.ReadOnly = true;
            this.bbsTextBox.Size = new System.Drawing.Size(669, 476);
            this.bbsTextBox.TabIndex = 5;
            this.bbsTextBox.Text = "";
            // 
            // bbsTopPanel
            // 
            this.bbsTopPanel.BackColor = System.Drawing.Color.Silver;
            this.bbsTopPanel.Controls.Add(this.bbsMenuPictureBox);
            this.bbsTopPanel.Controls.Add(this.bbsConnectButton);
            this.bbsTopPanel.Controls.Add(this.bbsTitleLabel);
            this.bbsTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.bbsTopPanel.Location = new System.Drawing.Point(0, 0);
            this.bbsTopPanel.Margin = new System.Windows.Forms.Padding(4);
            this.bbsTopPanel.Name = "bbsTopPanel";
            this.bbsTopPanel.Size = new System.Drawing.Size(669, 37);
            this.bbsTopPanel.TabIndex = 5;
            // 
            // bbsMenuPictureBox
            // 
            this.bbsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.bbsMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.bbsMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.bbsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.bbsMenuPictureBox.Name = "bbsMenuPictureBox";
            this.bbsMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.bbsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.bbsMenuPictureBox.TabIndex = 4;
            this.bbsMenuPictureBox.TabStop = false;
            this.bbsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.bbsMenuPictureBox_MouseClick);
            // 
            // bbsConnectButton
            // 
            this.bbsConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.bbsConnectButton.Location = new System.Drawing.Point(527, 4);
            this.bbsConnectButton.Margin = new System.Windows.Forms.Padding(4);
            this.bbsConnectButton.Name = "bbsConnectButton";
            this.bbsConnectButton.Size = new System.Drawing.Size(100, 28);
            this.bbsConnectButton.TabIndex = 2;
            this.bbsConnectButton.Text = "&Activate";
            this.bbsConnectButton.UseVisualStyleBackColor = true;
            this.bbsConnectButton.Click += new System.EventHandler(this.bbsConnectButton_Click);
            // 
            // bbsTitleLabel
            // 
            this.bbsTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.bbsTitleLabel.AutoSize = true;
            this.bbsTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.bbsTitleLabel.Location = new System.Drawing.Point(7, 6);
            this.bbsTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.bbsTitleLabel.Name = "bbsTitleLabel";
            this.bbsTitleLabel.Size = new System.Drawing.Size(52, 25);
            this.bbsTitleLabel.TabIndex = 0;
            this.bbsTitleLabel.Text = "BBS";
            // 
            // bbsTabContextMenuStrip
            // 
            this.bbsTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.bbsTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.viewTrafficToolStripMenuItem,
            this.toolStripMenuItem11,
            this.clearStatsToolStripMenuItem});
            this.bbsTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.bbsTabContextMenuStrip.Size = new System.Drawing.Size(156, 62);
            // 
            // viewTrafficToolStripMenuItem
            // 
            this.viewTrafficToolStripMenuItem.Checked = true;
            this.viewTrafficToolStripMenuItem.CheckOnClick = true;
            this.viewTrafficToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.viewTrafficToolStripMenuItem.Name = "viewTrafficToolStripMenuItem";
            this.viewTrafficToolStripMenuItem.Size = new System.Drawing.Size(155, 26);
            this.viewTrafficToolStripMenuItem.Text = "&View Traffic";
            this.viewTrafficToolStripMenuItem.Click += new System.EventHandler(this.viewTrafficToolStripMenuItem_Click);
            // 
            // toolStripMenuItem11
            // 
            this.toolStripMenuItem11.Name = "toolStripMenuItem11";
            this.toolStripMenuItem11.Size = new System.Drawing.Size(152, 6);
            // 
            // clearStatsToolStripMenuItem
            // 
            this.clearStatsToolStripMenuItem.Name = "clearStatsToolStripMenuItem";
            this.clearStatsToolStripMenuItem.Size = new System.Drawing.Size(155, 26);
            this.clearStatsToolStripMenuItem.Text = "&Clear Stats";
            this.clearStatsToolStripMenuItem.Click += new System.EventHandler(this.clearStatsToolStripMenuItem_Click);
            // 
            // mainImageList
            // 
            this.mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit;
            this.mainImageList.ImageSize = new System.Drawing.Size(16, 16);
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            // 
            // BbsTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.bbsSplitContainer);
            this.Controls.Add(this.bbsTopPanel);
            this.Name = "BbsTabUserControl";
            this.Size = new System.Drawing.Size(669, 623);
            this.bbsSplitContainer.Panel1.ResumeLayout(false);
            this.bbsSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.bbsSplitContainer)).EndInit();
            this.bbsSplitContainer.ResumeLayout(false);
            this.bbsTopPanel.ResumeLayout(false);
            this.bbsTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.bbsMenuPictureBox)).EndInit();
            this.bbsTabContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

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
        private System.Windows.Forms.ImageList mainImageList;
    }
}