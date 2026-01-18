namespace HTCommander.Controls
{
    partial class AprsTabUserControl
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
                _broker?.Dispose();
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(AprsTabUserControl));
            aprsChatControl = new ChatControl();
            mainImageList = new System.Windows.Forms.ImageList(components);
            aprsMissingChannelPanel = new System.Windows.Forms.Panel();
            aprsSetupButton = new System.Windows.Forms.Button();
            missingAprsChannelLabel = new System.Windows.Forms.Label();
            aprsBottomPanel = new System.Windows.Forms.Panel();
            aprsDestinationComboBox = new System.Windows.Forms.ComboBox();
            aprsTextBox = new System.Windows.Forms.TextBox();
            aprsSendButton = new System.Windows.Forms.Button();
            aprsSendContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            requestPositionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            aprsTopPanel = new System.Windows.Forms.Panel();
            aprsRouteComboBox = new System.Windows.Forms.ComboBox();
            aprsMenuPictureBox = new System.Windows.Forms.PictureBox();
            aprsTitleLabel = new System.Windows.Forms.Label();
            aprsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            showAllMessagesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem7 = new System.Windows.Forms.ToolStripSeparator();
            beaconSettingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            smSMessageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            weatherReportToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            aprsMsgContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            detailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            showLocationToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            copyMessageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            copyCallsignToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            aprsMissingChannelPanel.SuspendLayout();
            aprsBottomPanel.SuspendLayout();
            aprsSendContextMenuStrip.SuspendLayout();
            aprsTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)aprsMenuPictureBox).BeginInit();
            aprsContextMenuStrip.SuspendLayout();
            aprsMsgContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // aprsChatControl
            // 
            aprsChatControl.CallsignFont = new System.Drawing.Font("Arial", 8F);
            aprsChatControl.CallsignTextColor = System.Drawing.Color.Gray;
            aprsChatControl.CornerRadius = 4;
            aprsChatControl.Dock = System.Windows.Forms.DockStyle.Fill;
            aprsChatControl.Images = mainImageList;
            aprsChatControl.InterMessageMargin = 12;
            aprsChatControl.Location = new System.Drawing.Point(0, 92);
            aprsChatControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            aprsChatControl.MaxWidth = 300;
            aprsChatControl.MessageBoxAuthColor = System.Drawing.Color.LightGreen;
            aprsChatControl.MessageBoxBadColor = System.Drawing.Color.Wheat;
            aprsChatControl.MessageBoxColor = System.Drawing.Color.LightBlue;
            aprsChatControl.MessageBoxMargin = 10;
            aprsChatControl.MessageFont = new System.Drawing.Font("Arial", 10F);
            aprsChatControl.MinWidth = 100;
            aprsChatControl.Name = "aprsChatControl";
            aprsChatControl.ShadowOffset = 2;
            aprsChatControl.SideMargins = 12;
            aprsChatControl.Size = new System.Drawing.Size(669, 368);
            aprsChatControl.TabIndex = 5;
            aprsChatControl.TextColor = System.Drawing.Color.Black;
            aprsChatControl.MouseClick += aprsChatControl_MouseClick;
            aprsChatControl.MouseDoubleClick += aprsChatControl_MouseDoubleClick;
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
            mainImageList.Images.SetKeyName(6, "terminal-1.png");
            mainImageList.Images.SetKeyName(7, "talking.ico");
            mainImageList.Images.SetKeyName(8, "mail-20.png");
            mainImageList.Images.SetKeyName(9, "file-20.png");
            mainImageList.Images.SetKeyName(10, "file-empty-20.png");
            // 
            // aprsMissingChannelPanel
            // 
            aprsMissingChannelPanel.BackColor = System.Drawing.Color.MistyRose;
            aprsMissingChannelPanel.Controls.Add(aprsSetupButton);
            aprsMissingChannelPanel.Controls.Add(missingAprsChannelLabel);
            aprsMissingChannelPanel.Dock = System.Windows.Forms.DockStyle.Top;
            aprsMissingChannelPanel.Location = new System.Drawing.Point(0, 46);
            aprsMissingChannelPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsMissingChannelPanel.Name = "aprsMissingChannelPanel";
            aprsMissingChannelPanel.Size = new System.Drawing.Size(669, 46);
            aprsMissingChannelPanel.TabIndex = 6;
            aprsMissingChannelPanel.Visible = false;
            // 
            // aprsSetupButton
            // 
            aprsSetupButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            aprsSetupButton.Location = new System.Drawing.Point(565, 6);
            aprsSetupButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsSetupButton.Name = "aprsSetupButton";
            aprsSetupButton.Size = new System.Drawing.Size(100, 35);
            aprsSetupButton.TabIndex = 8;
            aprsSetupButton.Text = "Setup";
            aprsSetupButton.UseVisualStyleBackColor = true;
            aprsSetupButton.Click += aprsSetupButton_Click;
            // 
            // missingAprsChannelLabel
            // 
            missingAprsChannelLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            missingAprsChannelLabel.AutoSize = true;
            missingAprsChannelLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            missingAprsChannelLabel.Location = new System.Drawing.Point(7, 11);
            missingAprsChannelLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            missingAprsChannelLabel.Name = "missingAprsChannelLabel";
            missingAprsChannelLabel.Size = new System.Drawing.Size(422, 20);
            missingAprsChannelLabel.TabIndex = 7;
            missingAprsChannelLabel.Text = "Configure a channel labeled \"APRS\" to use this feature.";
            // 
            // aprsBottomPanel
            // 
            aprsBottomPanel.BackColor = System.Drawing.Color.Silver;
            aprsBottomPanel.Controls.Add(aprsDestinationComboBox);
            aprsBottomPanel.Controls.Add(aprsTextBox);
            aprsBottomPanel.Controls.Add(aprsSendButton);
            aprsBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            aprsBottomPanel.Location = new System.Drawing.Point(0, 460);
            aprsBottomPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsBottomPanel.Name = "aprsBottomPanel";
            aprsBottomPanel.Size = new System.Drawing.Size(669, 59);
            aprsBottomPanel.TabIndex = 4;
            // 
            // aprsDestinationComboBox
            // 
            aprsDestinationComboBox.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left;
            aprsDestinationComboBox.Enabled = false;
            aprsDestinationComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            aprsDestinationComboBox.FormattingEnabled = true;
            aprsDestinationComboBox.Items.AddRange(new object[] { "ALL", "QST", "CQ" });
            aprsDestinationComboBox.Location = new System.Drawing.Point(7, 9);
            aprsDestinationComboBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsDestinationComboBox.MaxLength = 9;
            aprsDestinationComboBox.Name = "aprsDestinationComboBox";
            aprsDestinationComboBox.Size = new System.Drawing.Size(147, 33);
            aprsDestinationComboBox.TabIndex = 7;
            aprsDestinationComboBox.SelectionChangeCommitted += aprsDestinationComboBox_SelectionChangeCommitted;
            aprsDestinationComboBox.TextChanged += aprsDestinationComboBox_TextChanged;
            aprsDestinationComboBox.KeyPress += aprsDestinationComboBox_KeyPress;
            // 
            // aprsTextBox
            // 
            aprsTextBox.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            aprsTextBox.Enabled = false;
            aprsTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            aprsTextBox.Location = new System.Drawing.Point(163, 11);
            aprsTextBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsTextBox.MaxLength = 67;
            aprsTextBox.Name = "aprsTextBox";
            aprsTextBox.Size = new System.Drawing.Size(393, 30);
            aprsTextBox.TabIndex = 1;
            aprsTextBox.TextChanged += aprsTextBox_TextChanged;
            aprsTextBox.KeyPress += aprsTextBox_KeyPress;
            // 
            // aprsSendButton
            // 
            aprsSendButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            aprsSendButton.ContextMenuStrip = aprsSendContextMenuStrip;
            aprsSendButton.Enabled = false;
            aprsSendButton.Location = new System.Drawing.Point(565, 9);
            aprsSendButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsSendButton.Name = "aprsSendButton";
            aprsSendButton.Size = new System.Drawing.Size(100, 38);
            aprsSendButton.TabIndex = 0;
            aprsSendButton.Text = "&Send";
            aprsSendButton.UseVisualStyleBackColor = true;
            aprsSendButton.Click += aprsSendButton_Click;
            // 
            // aprsSendContextMenuStrip
            // 
            aprsSendContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            aprsSendContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { requestPositionToolStripMenuItem });
            aprsSendContextMenuStrip.Name = "aprsSendContextMenuStrip";
            aprsSendContextMenuStrip.Size = new System.Drawing.Size(188, 28);
            // 
            // requestPositionToolStripMenuItem
            // 
            requestPositionToolStripMenuItem.Name = "requestPositionToolStripMenuItem";
            requestPositionToolStripMenuItem.Size = new System.Drawing.Size(187, 24);
            requestPositionToolStripMenuItem.Text = "Request &Position";
            requestPositionToolStripMenuItem.Click += requestPositionToolStripMenuItem_Click;
            // 
            // aprsTopPanel
            // 
            aprsTopPanel.BackColor = System.Drawing.Color.Silver;
            aprsTopPanel.Controls.Add(aprsRouteComboBox);
            aprsTopPanel.Controls.Add(aprsMenuPictureBox);
            aprsTopPanel.Controls.Add(aprsTitleLabel);
            aprsTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            aprsTopPanel.Location = new System.Drawing.Point(0, 0);
            aprsTopPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsTopPanel.Name = "aprsTopPanel";
            aprsTopPanel.Size = new System.Drawing.Size(669, 46);
            aprsTopPanel.TabIndex = 2;
            // 
            // aprsRouteComboBox
            // 
            aprsRouteComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            aprsRouteComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            aprsRouteComboBox.FormattingEnabled = true;
            aprsRouteComboBox.Location = new System.Drawing.Point(504, 8);
            aprsRouteComboBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsRouteComboBox.Name = "aprsRouteComboBox";
            aprsRouteComboBox.Size = new System.Drawing.Size(124, 28);
            aprsRouteComboBox.TabIndex = 3;
            aprsRouteComboBox.Visible = false;
            aprsRouteComboBox.SelectionChangeCommitted += aprsRouteComboBox_SelectionChangeCommitted;
            // 
            // aprsMenuPictureBox
            // 
            aprsMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            aprsMenuPictureBox.Image = Properties.Resources.MenuIcon;
            aprsMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            aprsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsMenuPictureBox.Name = "aprsMenuPictureBox";
            aprsMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            aprsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            aprsMenuPictureBox.TabIndex = 2;
            aprsMenuPictureBox.TabStop = false;
            aprsMenuPictureBox.MouseClick += aprsMenuPictureBox_MouseClick;
            // 
            // aprsTitleLabel
            // 
            aprsTitleLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            aprsTitleLabel.AutoSize = true;
            aprsTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            aprsTitleLabel.Location = new System.Drawing.Point(7, 8);
            aprsTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            aprsTitleLabel.Name = "aprsTitleLabel";
            aprsTitleLabel.Size = new System.Drawing.Size(66, 25);
            aprsTitleLabel.TabIndex = 0;
            aprsTitleLabel.Text = "APRS";
            aprsTitleLabel.DoubleClick += aprsTitleLabel_DoubleClick;
            // 
            // aprsContextMenuStrip
            // 
            aprsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            aprsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { showAllMessagesToolStripMenuItem, toolStripMenuItem7, beaconSettingsToolStripMenuItem, smSMessageToolStripMenuItem, weatherReportToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            aprsContextMenuStrip.Name = "aprsContextMenuStrip";
            aprsContextMenuStrip.Size = new System.Drawing.Size(194, 136);
            // 
            // showAllMessagesToolStripMenuItem
            // 
            showAllMessagesToolStripMenuItem.CheckOnClick = true;
            showAllMessagesToolStripMenuItem.Name = "showAllMessagesToolStripMenuItem";
            showAllMessagesToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            showAllMessagesToolStripMenuItem.Text = "Show &Telemetry";
            showAllMessagesToolStripMenuItem.CheckStateChanged += showAllMessagesToolStripMenuItem_CheckStateChanged;
            // 
            // toolStripMenuItem7
            // 
            toolStripMenuItem7.Name = "toolStripMenuItem7";
            toolStripMenuItem7.Size = new System.Drawing.Size(190, 6);
            // 
            // beaconSettingsToolStripMenuItem
            // 
            beaconSettingsToolStripMenuItem.Name = "beaconSettingsToolStripMenuItem";
            beaconSettingsToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            beaconSettingsToolStripMenuItem.Text = "&Beacon Settings...";
            beaconSettingsToolStripMenuItem.Click += beaconSettingsToolStripMenuItem_Click;
            // 
            // smSMessageToolStripMenuItem
            // 
            smSMessageToolStripMenuItem.Name = "smSMessageToolStripMenuItem";
            smSMessageToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            smSMessageToolStripMenuItem.Text = "&SMS Message...";
            smSMessageToolStripMenuItem.Click += aprsSmsButton_Click;
            // 
            // weatherReportToolStripMenuItem
            // 
            weatherReportToolStripMenuItem.Name = "weatherReportToolStripMenuItem";
            weatherReportToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            weatherReportToolStripMenuItem.Text = "&Weather Report...";
            weatherReportToolStripMenuItem.Click += weatherReportToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(190, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // aprsMsgContextMenuStrip
            // 
            aprsMsgContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            aprsMsgContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { detailsToolStripMenuItem, showLocationToolStripMenuItem, copyMessageToolStripMenuItem, copyCallsignToolStripMenuItem });
            aprsMsgContextMenuStrip.Name = "aprsMsgContextMenuStrip";
            aprsMsgContextMenuStrip.Size = new System.Drawing.Size(185, 100);
            aprsMsgContextMenuStrip.Opening += aprsMsgContextMenuStrip_Opening;
            // 
            // detailsToolStripMenuItem
            // 
            detailsToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, 0);
            detailsToolStripMenuItem.Name = "detailsToolStripMenuItem";
            detailsToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            detailsToolStripMenuItem.Text = "&Details...";
            detailsToolStripMenuItem.Click += detailsToolStripMenuItem_Click;
            // 
            // showLocationToolStripMenuItem
            // 
            showLocationToolStripMenuItem.Name = "showLocationToolStripMenuItem";
            showLocationToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            showLocationToolStripMenuItem.Text = "Show Location...";
            showLocationToolStripMenuItem.Click += showLocationToolStripMenuItem_Click;
            // 
            // copyMessageToolStripMenuItem
            // 
            copyMessageToolStripMenuItem.Name = "copyMessageToolStripMenuItem";
            copyMessageToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            copyMessageToolStripMenuItem.Text = "Copy Message";
            copyMessageToolStripMenuItem.Click += copyMessageToolStripMenuItem_Click;
            // 
            // copyCallsignToolStripMenuItem
            // 
            copyCallsignToolStripMenuItem.Name = "copyCallsignToolStripMenuItem";
            copyCallsignToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            copyCallsignToolStripMenuItem.Text = "Copy Callsign";
            copyCallsignToolStripMenuItem.Click += copyCallsignToolStripMenuItem_Click;
            // 
            // AprsTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(aprsChatControl);
            Controls.Add(aprsMissingChannelPanel);
            Controls.Add(aprsBottomPanel);
            Controls.Add(aprsTopPanel);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            Name = "AprsTabUserControl";
            Size = new System.Drawing.Size(669, 519);
            aprsMissingChannelPanel.ResumeLayout(false);
            aprsMissingChannelPanel.PerformLayout();
            aprsBottomPanel.ResumeLayout(false);
            aprsBottomPanel.PerformLayout();
            aprsSendContextMenuStrip.ResumeLayout(false);
            aprsTopPanel.ResumeLayout(false);
            aprsTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)aprsMenuPictureBox).EndInit();
            aprsContextMenuStrip.ResumeLayout(false);
            aprsMsgContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

        }

        #endregion

        private ChatControl aprsChatControl;
        private System.Windows.Forms.ImageList mainImageList;
        private System.Windows.Forms.Panel aprsMissingChannelPanel;
        private System.Windows.Forms.Button aprsSetupButton;
        private System.Windows.Forms.Label missingAprsChannelLabel;
        private System.Windows.Forms.Panel aprsBottomPanel;
        private System.Windows.Forms.ComboBox aprsDestinationComboBox;
        private System.Windows.Forms.TextBox aprsTextBox;
        private System.Windows.Forms.Button aprsSendButton;
        private System.Windows.Forms.ContextMenuStrip aprsSendContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem requestPositionToolStripMenuItem;
        private System.Windows.Forms.Panel aprsTopPanel;
        private System.Windows.Forms.ComboBox aprsRouteComboBox;
        private System.Windows.Forms.PictureBox aprsMenuPictureBox;
        private System.Windows.Forms.Label aprsTitleLabel;
        private System.Windows.Forms.ContextMenuStrip aprsContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showAllMessagesToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem7;
        private System.Windows.Forms.ToolStripMenuItem beaconSettingsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem smSMessageToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem weatherReportToolStripMenuItem;
        private System.Windows.Forms.ContextMenuStrip aprsMsgContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem detailsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem showLocationToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem copyMessageToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem copyCallsignToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
    }
}
