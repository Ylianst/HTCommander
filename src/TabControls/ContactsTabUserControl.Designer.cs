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
            if (disposing)
            {
                broker?.Dispose();
                components?.Dispose();
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
            System.Windows.Forms.ListViewGroup listViewGroup4 = new System.Windows.Forms.ListViewGroup("Winlink Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup5 = new System.Windows.Forms.ListViewGroup("BBS Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup6 = new System.Windows.Forms.ListViewGroup("Torrent Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(ContactsTabUserControl));
            stationsTopPanel = new System.Windows.Forms.Panel();
            stationsMenuPictureBox = new System.Windows.Forms.PictureBox();
            stationsTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            setToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            editToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            removeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem10 = new System.Windows.Forms.ToolStripSeparator();
            exportStationsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            importStationsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            stationsTitleLabel = new System.Windows.Forms.Label();
            mainAddressBookListView = new System.Windows.Forms.ListView();
            columnHeader7 = new System.Windows.Forms.ColumnHeader();
            columnHeader8 = new System.Windows.Forms.ColumnHeader();
            columnHeader9 = new System.Windows.Forms.ColumnHeader();
            mainImageList = new System.Windows.Forms.ImageList(components);
            stationsBottomPanel = new System.Windows.Forms.Panel();
            removeStationButton = new System.Windows.Forms.Button();
            addStationButton = new System.Windows.Forms.Button();
            saveStationsFileDialog = new System.Windows.Forms.SaveFileDialog();
            openStationsFileDialog = new System.Windows.Forms.OpenFileDialog();
            stationsTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)stationsMenuPictureBox).BeginInit();
            stationsTabContextMenuStrip.SuspendLayout();
            stationsBottomPanel.SuspendLayout();
            SuspendLayout();
            // 
            // stationsTopPanel
            // 
            stationsTopPanel.BackColor = System.Drawing.Color.Silver;
            stationsTopPanel.Controls.Add(stationsMenuPictureBox);
            stationsTopPanel.Controls.Add(stationsTitleLabel);
            stationsTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            stationsTopPanel.Location = new System.Drawing.Point(0, 0);
            stationsTopPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            stationsTopPanel.Name = "stationsTopPanel";
            stationsTopPanel.Size = new System.Drawing.Size(669, 46);
            stationsTopPanel.TabIndex = 0;
            // 
            // stationsMenuPictureBox
            // 
            stationsMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            stationsMenuPictureBox.ContextMenuStrip = stationsTabContextMenuStrip;
            stationsMenuPictureBox.Image = Properties.Resources.MenuIcon;
            stationsMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            stationsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            stationsMenuPictureBox.Name = "stationsMenuPictureBox";
            stationsMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            stationsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            stationsMenuPictureBox.TabIndex = 4;
            stationsMenuPictureBox.TabStop = false;
            stationsMenuPictureBox.MouseClick += stationsMenuPictureBox_MouseClick;
            // 
            // stationsTabContextMenuStrip
            // 
            stationsTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            stationsTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { setToolStripMenuItem, editToolStripMenuItem, removeToolStripMenuItem, toolStripMenuItem10, exportStationsToolStripMenuItem, importStationsToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            stationsTabContextMenuStrip.Name = "stationsTabContextMenuStrip";
            stationsTabContextMenuStrip.Size = new System.Drawing.Size(135, 160);
            // 
            // setToolStripMenuItem
            // 
            setToolStripMenuItem.Name = "setToolStripMenuItem";
            setToolStripMenuItem.Size = new System.Drawing.Size(134, 24);
            setToolStripMenuItem.Text = "&Set";
            setToolStripMenuItem.Click += setToolStripMenuItem_Click;
            // 
            // editToolStripMenuItem
            // 
            editToolStripMenuItem.Name = "editToolStripMenuItem";
            editToolStripMenuItem.Size = new System.Drawing.Size(134, 24);
            editToolStripMenuItem.Text = "&Edit";
            editToolStripMenuItem.Click += mainAddressBookListView_DoubleClick;
            // 
            // removeToolStripMenuItem
            // 
            removeToolStripMenuItem.Name = "removeToolStripMenuItem";
            removeToolStripMenuItem.Size = new System.Drawing.Size(134, 24);
            removeToolStripMenuItem.Text = "&Remove";
            removeToolStripMenuItem.Click += removeToolStripMenuItem_Click;
            // 
            // toolStripMenuItem10
            // 
            toolStripMenuItem10.Name = "toolStripMenuItem10";
            toolStripMenuItem10.Size = new System.Drawing.Size(131, 6);
            // 
            // exportStationsToolStripMenuItem
            // 
            exportStationsToolStripMenuItem.Name = "exportStationsToolStripMenuItem";
            exportStationsToolStripMenuItem.Size = new System.Drawing.Size(134, 24);
            exportStationsToolStripMenuItem.Text = "E&xport...";
            exportStationsToolStripMenuItem.Click += exportStationsToolStripMenuItem_Click;
            // 
            // importStationsToolStripMenuItem
            // 
            importStationsToolStripMenuItem.Name = "importStationsToolStripMenuItem";
            importStationsToolStripMenuItem.Size = new System.Drawing.Size(134, 24);
            importStationsToolStripMenuItem.Text = "&Import...";
            importStationsToolStripMenuItem.Click += importStationsToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(131, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(134, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // stationsTitleLabel
            // 
            stationsTitleLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            stationsTitleLabel.AutoSize = true;
            stationsTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            stationsTitleLabel.Location = new System.Drawing.Point(7, 8);
            stationsTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            stationsTitleLabel.Name = "stationsTitleLabel";
            stationsTitleLabel.Size = new System.Drawing.Size(90, 25);
            stationsTitleLabel.TabIndex = 0;
            stationsTitleLabel.Text = "Contacts";
            // 
            // mainAddressBookListView
            // 
            mainAddressBookListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader7, columnHeader8, columnHeader9 });
            mainAddressBookListView.Dock = System.Windows.Forms.DockStyle.Fill;
            mainAddressBookListView.FullRowSelect = true;
            mainAddressBookListView.GridLines = true;
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
            mainAddressBookListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] { listViewGroup1, listViewGroup2, listViewGroup3, listViewGroup4, listViewGroup5, listViewGroup6 });
            mainAddressBookListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            mainAddressBookListView.Location = new System.Drawing.Point(0, 46);
            mainAddressBookListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mainAddressBookListView.Name = "mainAddressBookListView";
            mainAddressBookListView.Size = new System.Drawing.Size(669, 449);
            mainAddressBookListView.SmallImageList = mainImageList;
            mainAddressBookListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            mainAddressBookListView.TabIndex = 1;
            mainAddressBookListView.UseCompatibleStateImageBehavior = false;
            mainAddressBookListView.View = System.Windows.Forms.View.Details;
            mainAddressBookListView.SelectedIndexChanged += mainAddressBookListView_SelectedIndexChanged;
            mainAddressBookListView.DoubleClick += mainAddressBookListView_DoubleClick;
            mainAddressBookListView.Resize += mainAddressBookListView_Resize;
            // 
            // columnHeader7
            // 
            columnHeader7.Text = "Callsign";
            columnHeader7.Width = 100;
            // 
            // columnHeader8
            // 
            columnHeader8.Text = "Name";
            columnHeader8.Width = 150;
            // 
            // columnHeader9
            // 
            columnHeader9.Text = "Description";
            columnHeader9.Width = 200;
            // 
            // mainImageList
            // 
            mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth16Bit;
            mainImageList.ImageStream = (System.Windows.Forms.ImageListStreamer)resources.GetObject("mainImageList.ImageStream");
            mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            mainImageList.Images.SetKeyName(0, "GreenCheck.png");
            mainImageList.Images.SetKeyName(1, "RedCheck.png");
            mainImageList.Images.SetKeyName(2, "info.ico");
            mainImageList.Images.SetKeyName(3, "LocationPin2.png");
            mainImageList.Images.SetKeyName(4, "left-arrow.png");
            mainImageList.Images.SetKeyName(5, "right-arrow.png");
            mainImageList.Images.SetKeyName(6, "terminal-32.png");
            mainImageList.Images.SetKeyName(7, "talking.ico");
            mainImageList.Images.SetKeyName(8, "mail-20.png");
            // 
            // stationsBottomPanel
            // 
            stationsBottomPanel.BackColor = System.Drawing.Color.Silver;
            stationsBottomPanel.Controls.Add(removeStationButton);
            stationsBottomPanel.Controls.Add(addStationButton);
            stationsBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            stationsBottomPanel.Location = new System.Drawing.Point(0, 495);
            stationsBottomPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            stationsBottomPanel.Name = "stationsBottomPanel";
            stationsBottomPanel.Size = new System.Drawing.Size(669, 54);
            stationsBottomPanel.TabIndex = 2;
            // 
            // removeStationButton
            // 
            removeStationButton.Enabled = false;
            removeStationButton.Location = new System.Drawing.Point(119, 9);
            removeStationButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            removeStationButton.Name = "removeStationButton";
            removeStationButton.Size = new System.Drawing.Size(100, 35);
            removeStationButton.TabIndex = 1;
            removeStationButton.Text = "&Remove";
            removeStationButton.UseVisualStyleBackColor = true;
            removeStationButton.Click += removeStationButton_Click;
            // 
            // addStationButton
            // 
            addStationButton.Location = new System.Drawing.Point(11, 9);
            addStationButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            addStationButton.Name = "addStationButton";
            addStationButton.Size = new System.Drawing.Size(100, 35);
            addStationButton.TabIndex = 0;
            addStationButton.Text = "&Add";
            addStationButton.UseVisualStyleBackColor = true;
            addStationButton.Click += addStationButton_Click;
            // 
            // saveStationsFileDialog
            // 
            saveStationsFileDialog.DefaultExt = "json";
            saveStationsFileDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*";
            saveStationsFileDialog.Title = "Export Stations";
            // 
            // openStationsFileDialog
            // 
            openStationsFileDialog.DefaultExt = "json";
            openStationsFileDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*";
            openStationsFileDialog.Title = "Import Stations";
            // 
            // ContactsTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(mainAddressBookListView);
            Controls.Add(stationsBottomPanel);
            Controls.Add(stationsTopPanel);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            Name = "ContactsTabUserControl";
            Size = new System.Drawing.Size(669, 549);
            stationsTopPanel.ResumeLayout(false);
            stationsTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)stationsMenuPictureBox).EndInit();
            stationsTabContextMenuStrip.ResumeLayout(false);
            stationsBottomPanel.ResumeLayout(false);
            ResumeLayout(false);

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
