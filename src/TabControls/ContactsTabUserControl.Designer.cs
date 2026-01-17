namespace HTCommander.Controls
{
    partial class ContactsTabUserControl
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
            System.Windows.Forms.ListViewGroup listViewGroup4 = new System.Windows.Forms.ListViewGroup("Winlink Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup5 = new System.Windows.Forms.ListViewGroup("BBS Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup6 = new System.Windows.Forms.ListViewGroup("Torrent Stations", System.Windows.Forms.HorizontalAlignment.Left);
            this.stationsTopPanel = new System.Windows.Forms.Panel();
            this.stationsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.stationsTitleLabel = new System.Windows.Forms.Label();
            this.mainAddressBookListView = new System.Windows.Forms.ListView();
            this.columnHeader7 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader8 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader9 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.stationsBottomPanel = new System.Windows.Forms.Panel();
            this.removeStationButton = new System.Windows.Forms.Button();
            this.addStationButton = new System.Windows.Forms.Button();
            this.stationsTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.setToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.editToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.removeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem10 = new System.Windows.Forms.ToolStripSeparator();
            this.exportStationsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.importStationsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            this.saveStationsFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.openStationsFileDialog = new System.Windows.Forms.OpenFileDialog();
            this.stationsTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.stationsMenuPictureBox)).BeginInit();
            this.stationsBottomPanel.SuspendLayout();
            this.stationsTabContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // stationsTopPanel
            // 
            this.stationsTopPanel.BackColor = System.Drawing.Color.Silver;
            this.stationsTopPanel.Controls.Add(this.stationsMenuPictureBox);
            this.stationsTopPanel.Controls.Add(this.stationsTitleLabel);
            this.stationsTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.stationsTopPanel.Location = new System.Drawing.Point(0, 0);
            this.stationsTopPanel.Margin = new System.Windows.Forms.Padding(4);
            this.stationsTopPanel.Name = "stationsTopPanel";
            this.stationsTopPanel.Size = new System.Drawing.Size(669, 37);
            this.stationsTopPanel.TabIndex = 0;
            // 
            // stationsMenuPictureBox
            // 
            this.stationsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.stationsMenuPictureBox.ContextMenuStrip = this.stationsTabContextMenuStrip;
            this.stationsMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.stationsMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.stationsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.stationsMenuPictureBox.Name = "stationsMenuPictureBox";
            this.stationsMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.stationsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.stationsMenuPictureBox.TabIndex = 4;
            this.stationsMenuPictureBox.TabStop = false;
            this.stationsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.stationsMenuPictureBox_MouseClick);
            // 
            // stationsTitleLabel
            // 
            this.stationsTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.stationsTitleLabel.AutoSize = true;
            this.stationsTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.stationsTitleLabel.Location = new System.Drawing.Point(7, 6);
            this.stationsTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.stationsTitleLabel.Name = "stationsTitleLabel";
            this.stationsTitleLabel.Size = new System.Drawing.Size(84, 25);
            this.stationsTitleLabel.TabIndex = 0;
            this.stationsTitleLabel.Text = "Contacts";
            // 
            // mainAddressBookListView
            // 
            this.mainAddressBookListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader7,
            this.columnHeader8,
            this.columnHeader9});
            this.mainAddressBookListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mainAddressBookListView.FullRowSelect = true;
            this.mainAddressBookListView.GridLines = true;
            listViewGroup1.Header = "Generic Stations";
            listViewGroup1.Name = "Generic Stations";
            listViewGroup2.Header = "APRS Stations";
            listViewGroup2.Name = "APRS Stations";
            listViewGroup3.Header = "Terminal Stations";
            listViewGroup3.Name = "Terminal Stations";
            listViewGroup4.Header = "Winlink Stations";
            listViewGroup4.Name = "Winlink Stations";
            listViewGroup5.Header = "BBS Stations";
            listViewGroup5.Name = "BBS Stations";
            listViewGroup6.Header = "Torrent Stations";
            listViewGroup6.Name = "Torrent Stations";
            this.mainAddressBookListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] {
            listViewGroup1,
            listViewGroup2,
            listViewGroup3,
            listViewGroup4,
            listViewGroup5,
            listViewGroup6});
            this.mainAddressBookListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            this.mainAddressBookListView.HideSelection = false;
            this.mainAddressBookListView.Location = new System.Drawing.Point(0, 37);
            this.mainAddressBookListView.Margin = new System.Windows.Forms.Padding(4);
            this.mainAddressBookListView.Name = "mainAddressBookListView";
            this.mainAddressBookListView.Size = new System.Drawing.Size(669, 543);
            this.mainAddressBookListView.SmallImageList = this.mainImageList;
            this.mainAddressBookListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            this.mainAddressBookListView.TabIndex = 1;
            this.mainAddressBookListView.UseCompatibleStateImageBehavior = false;
            this.mainAddressBookListView.View = System.Windows.Forms.View.Details;
            this.mainAddressBookListView.SelectedIndexChanged += new System.EventHandler(this.mainAddressBookListView_SelectedIndexChanged);
            this.mainAddressBookListView.DoubleClick += new System.EventHandler(this.mainAddressBookListView_DoubleClick);
            this.mainAddressBookListView.Resize += new System.EventHandler(this.mainAddressBookListView_Resize);
            // 
            // columnHeader7
            // 
            this.columnHeader7.Text = "Callsign";
            this.columnHeader7.Width = 100;
            // 
            // columnHeader8
            // 
            this.columnHeader8.Text = "Name";
            this.columnHeader8.Width = 150;
            // 
            // columnHeader9
            // 
            this.columnHeader9.Text = "Description";
            this.columnHeader9.Width = 200;
            // 
            // stationsBottomPanel
            // 
            this.stationsBottomPanel.BackColor = System.Drawing.Color.Silver;
            this.stationsBottomPanel.Controls.Add(this.removeStationButton);
            this.stationsBottomPanel.Controls.Add(this.addStationButton);
            this.stationsBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.stationsBottomPanel.Location = new System.Drawing.Point(0, 580);
            this.stationsBottomPanel.Margin = new System.Windows.Forms.Padding(4);
            this.stationsBottomPanel.Name = "stationsBottomPanel";
            this.stationsBottomPanel.Size = new System.Drawing.Size(669, 43);
            this.stationsBottomPanel.TabIndex = 2;
            // 
            // removeStationButton
            // 
            this.removeStationButton.Enabled = false;
            this.removeStationButton.Location = new System.Drawing.Point(119, 7);
            this.removeStationButton.Margin = new System.Windows.Forms.Padding(4);
            this.removeStationButton.Name = "removeStationButton";
            this.removeStationButton.Size = new System.Drawing.Size(100, 28);
            this.removeStationButton.TabIndex = 1;
            this.removeStationButton.Text = "&Remove";
            this.removeStationButton.UseVisualStyleBackColor = true;
            this.removeStationButton.Click += new System.EventHandler(this.removeStationButton_Click);
            // 
            // addStationButton
            // 
            this.addStationButton.Location = new System.Drawing.Point(11, 7);
            this.addStationButton.Margin = new System.Windows.Forms.Padding(4);
            this.addStationButton.Name = "addStationButton";
            this.addStationButton.Size = new System.Drawing.Size(100, 28);
            this.addStationButton.TabIndex = 0;
            this.addStationButton.Text = "&Add";
            this.addStationButton.UseVisualStyleBackColor = true;
            this.addStationButton.Click += new System.EventHandler(this.addStationButton_Click);
            // 
            // stationsTabContextMenuStrip
            // 
            this.stationsTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.stationsTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.setToolStripMenuItem,
            this.editToolStripMenuItem,
            this.removeToolStripMenuItem,
            this.toolStripMenuItem10,
            this.exportStationsToolStripMenuItem,
            this.importStationsToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.stationsTabContextMenuStrip.Name = "stationsTabContextMenuStrip";
            this.stationsTabContextMenuStrip.Size = new System.Drawing.Size(181, 172);
            // 
            // setToolStripMenuItem
            // 
            this.setToolStripMenuItem.Name = "setToolStripMenuItem";
            this.setToolStripMenuItem.Size = new System.Drawing.Size(180, 26);
            this.setToolStripMenuItem.Text = "&Set";
            this.setToolStripMenuItem.Click += new System.EventHandler(this.setToolStripMenuItem_Click);
            // 
            // editToolStripMenuItem
            // 
            this.editToolStripMenuItem.Name = "editToolStripMenuItem";
            this.editToolStripMenuItem.Size = new System.Drawing.Size(180, 26);
            this.editToolStripMenuItem.Text = "&Edit";
            this.editToolStripMenuItem.Click += new System.EventHandler(this.mainAddressBookListView_DoubleClick);
            // 
            // removeToolStripMenuItem
            // 
            this.removeToolStripMenuItem.Name = "removeToolStripMenuItem";
            this.removeToolStripMenuItem.Size = new System.Drawing.Size(180, 26);
            this.removeToolStripMenuItem.Text = "&Remove";
            this.removeToolStripMenuItem.Click += new System.EventHandler(this.removeToolStripMenuItem_Click);
            // 
            // toolStripMenuItem10
            // 
            this.toolStripMenuItem10.Name = "toolStripMenuItem10";
            this.toolStripMenuItem10.Size = new System.Drawing.Size(177, 6);
            // 
            // exportStationsToolStripMenuItem
            // 
            this.exportStationsToolStripMenuItem.Name = "exportStationsToolStripMenuItem";
            this.exportStationsToolStripMenuItem.Size = new System.Drawing.Size(180, 26);
            this.exportStationsToolStripMenuItem.Text = "E&xport...";
            this.exportStationsToolStripMenuItem.Click += new System.EventHandler(this.exportStationsToolStripMenuItem_Click);
            // 
            // importStationsToolStripMenuItem
            // 
            this.importStationsToolStripMenuItem.Name = "importStationsToolStripMenuItem";
            this.importStationsToolStripMenuItem.Size = new System.Drawing.Size(180, 26);
            this.importStationsToolStripMenuItem.Text = "&Import...";
            this.importStationsToolStripMenuItem.Click += new System.EventHandler(this.importStationsToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(177, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(180, 26);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // mainImageList
            // 
            this.mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit;
            this.mainImageList.ImageSize = new System.Drawing.Size(16, 16);
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            // 
            // saveStationsFileDialog
            // 
            this.saveStationsFileDialog.DefaultExt = "json";
            this.saveStationsFileDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*";
            this.saveStationsFileDialog.Title = "Export Stations";
            // 
            // openStationsFileDialog
            // 
            this.openStationsFileDialog.DefaultExt = "json";
            this.openStationsFileDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*";
            this.openStationsFileDialog.Title = "Import Stations";
            // 
            // ContactsTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.mainAddressBookListView);
            this.Controls.Add(this.stationsBottomPanel);
            this.Controls.Add(this.stationsTopPanel);
            this.Name = "ContactsTabUserControl";
            this.Size = new System.Drawing.Size(669, 623);
            this.stationsTopPanel.ResumeLayout(false);
            this.stationsTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.stationsMenuPictureBox)).EndInit();
            this.stationsBottomPanel.ResumeLayout(false);
            this.stationsTabContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Panel stationsTopPanel;
        private System.Windows.Forms.PictureBox stationsMenuPictureBox;
        private System.Windows.Forms.Label stationsTitleLabel;
        private System.Windows.Forms.ListView mainAddressBookListView;
        private System.Windows.Forms.ColumnHeader columnHeader7;
        private System.Windows.Forms.ColumnHeader columnHeader8;
        private System.Windows.Forms.ColumnHeader columnHeader9;
        private System.Windows.Forms.Panel stationsBottomPanel;
        private System.Windows.Forms.Button removeStationButton;
        private System.Windows.Forms.Button addStationButton;
        private System.Windows.Forms.ContextMenuStrip stationsTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem setToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem editToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem removeToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem10;
        private System.Windows.Forms.ToolStripMenuItem exportStationsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem importStationsToolStripMenuItem;
        private System.Windows.Forms.ImageList mainImageList;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog saveStationsFileDialog;
        private System.Windows.Forms.OpenFileDialog openStationsFileDialog;
    }
}
