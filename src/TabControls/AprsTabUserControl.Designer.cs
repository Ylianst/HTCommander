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
            this.aprsChatControl = new HTCommander.ChatControl();
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            this.aprsMissingChannelPanel = new System.Windows.Forms.Panel();
            this.aprsSetupButton = new System.Windows.Forms.Button();
            this.missingAprsChannelLabel = new System.Windows.Forms.Label();
            this.aprsBottomPanel = new System.Windows.Forms.Panel();
            this.aprsDestinationComboBox = new System.Windows.Forms.ComboBox();
            this.aprsTextBox = new System.Windows.Forms.TextBox();
            this.aprsSendButton = new System.Windows.Forms.Button();
            this.aprsSendContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.requestPositionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.aprsTopPanel = new System.Windows.Forms.Panel();
            this.aprsRouteComboBox = new System.Windows.Forms.ComboBox();
            this.aprsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.aprsTitleLabel = new System.Windows.Forms.Label();
            this.aprsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showAllMessagesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem7 = new System.Windows.Forms.ToolStripSeparator();
            this.beaconSettingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.smSMessageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.weatherReportToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.aprsMsgContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.detailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.showLocationToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.copyMessageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.copyCallsignToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.aprsMissingChannelPanel.SuspendLayout();
            this.aprsBottomPanel.SuspendLayout();
            this.aprsSendContextMenuStrip.SuspendLayout();
            this.aprsTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.aprsMenuPictureBox)).BeginInit();
            this.aprsContextMenuStrip.SuspendLayout();
            this.aprsMsgContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // aprsChatControl
            // 
            this.aprsChatControl.CallsignFont = new System.Drawing.Font("Arial", 8F);
            this.aprsChatControl.CallsignTextColor = System.Drawing.Color.Gray;
            this.aprsChatControl.CornerRadius = 4;
            this.aprsChatControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.aprsChatControl.Images = this.mainImageList;
            this.aprsChatControl.InterMessageMargin = 12;
            this.aprsChatControl.Location = new System.Drawing.Point(0, 74);
            this.aprsChatControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.aprsChatControl.MaxWidth = 300;
            this.aprsChatControl.MessageBoxAuthColor = System.Drawing.Color.LightGreen;
            this.aprsChatControl.MessageBoxBadColor = System.Drawing.Color.Wheat;
            this.aprsChatControl.MessageBoxColor = System.Drawing.Color.LightBlue;
            this.aprsChatControl.MessageBoxMargin = 10;
            this.aprsChatControl.MessageFont = new System.Drawing.Font("Arial", 10F);
            this.aprsChatControl.MinWidth = 100;
            this.aprsChatControl.Name = "aprsChatControl";
            this.aprsChatControl.ShadowOffset = 2;
            this.aprsChatControl.SideMargins = 12;
            this.aprsChatControl.Size = new System.Drawing.Size(669, 537);
            this.aprsChatControl.TabIndex = 5;
            this.aprsChatControl.TextColor = System.Drawing.Color.Black;
            this.aprsChatControl.MouseClick += new System.Windows.Forms.MouseEventHandler(this.aprsChatControl_MouseClick);
            this.aprsChatControl.MouseDoubleClick += new System.Windows.Forms.MouseEventHandler(this.aprsChatControl_MouseDoubleClick);
            // 
            // mainImageList
            // 
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            // 
            // aprsMissingChannelPanel
            // 
            this.aprsMissingChannelPanel.BackColor = System.Drawing.Color.MistyRose;
            this.aprsMissingChannelPanel.Controls.Add(this.aprsSetupButton);
            this.aprsMissingChannelPanel.Controls.Add(this.missingAprsChannelLabel);
            this.aprsMissingChannelPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.aprsMissingChannelPanel.Location = new System.Drawing.Point(0, 37);
            this.aprsMissingChannelPanel.Margin = new System.Windows.Forms.Padding(4);
            this.aprsMissingChannelPanel.Name = "aprsMissingChannelPanel";
            this.aprsMissingChannelPanel.Size = new System.Drawing.Size(669, 37);
            this.aprsMissingChannelPanel.TabIndex = 6;
            this.aprsMissingChannelPanel.Visible = false;
            // 
            // aprsSetupButton
            // 
            this.aprsSetupButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsSetupButton.Location = new System.Drawing.Point(565, 5);
            this.aprsSetupButton.Margin = new System.Windows.Forms.Padding(4);
            this.aprsSetupButton.Name = "aprsSetupButton";
            this.aprsSetupButton.Size = new System.Drawing.Size(100, 28);
            this.aprsSetupButton.TabIndex = 8;
            this.aprsSetupButton.Text = "Setup";
            this.aprsSetupButton.UseVisualStyleBackColor = true;
            this.aprsSetupButton.Click += new System.EventHandler(this.aprsSetupButton_Click);
            // 
            // missingAprsChannelLabel
            // 
            this.missingAprsChannelLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.missingAprsChannelLabel.AutoSize = true;
            this.missingAprsChannelLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.missingAprsChannelLabel.Location = new System.Drawing.Point(7, 9);
            this.missingAprsChannelLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.missingAprsChannelLabel.Name = "missingAprsChannelLabel";
            this.missingAprsChannelLabel.Size = new System.Drawing.Size(422, 20);
            this.missingAprsChannelLabel.TabIndex = 7;
            this.missingAprsChannelLabel.Text = "Configure a channel labeled \"APRS\" to use this feature.";
            // 
            // aprsBottomPanel
            // 
            this.aprsBottomPanel.BackColor = System.Drawing.Color.Silver;
            this.aprsBottomPanel.Controls.Add(this.aprsDestinationComboBox);
            this.aprsBottomPanel.Controls.Add(this.aprsTextBox);
            this.aprsBottomPanel.Controls.Add(this.aprsSendButton);
            this.aprsBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.aprsBottomPanel.Location = new System.Drawing.Point(0, 611);
            this.aprsBottomPanel.Margin = new System.Windows.Forms.Padding(4);
            this.aprsBottomPanel.Name = "aprsBottomPanel";
            this.aprsBottomPanel.Size = new System.Drawing.Size(669, 47);
            this.aprsBottomPanel.TabIndex = 4;
            // 
            // aprsDestinationComboBox
            // 
            this.aprsDestinationComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.aprsDestinationComboBox.Enabled = false;
            this.aprsDestinationComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.aprsDestinationComboBox.FormattingEnabled = true;
            this.aprsDestinationComboBox.Items.AddRange(new object[] {
            "ALL",
            "QST",
            "CQ"});
            this.aprsDestinationComboBox.Location = new System.Drawing.Point(7, 7);
            this.aprsDestinationComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.aprsDestinationComboBox.MaxLength = 9;
            this.aprsDestinationComboBox.Name = "aprsDestinationComboBox";
            this.aprsDestinationComboBox.Size = new System.Drawing.Size(147, 33);
            this.aprsDestinationComboBox.TabIndex = 7;
            this.aprsDestinationComboBox.SelectionChangeCommitted += new System.EventHandler(this.aprsDestinationComboBox_SelectionChangeCommitted);
            this.aprsDestinationComboBox.TextChanged += new System.EventHandler(this.aprsDestinationComboBox_TextChanged);
            this.aprsDestinationComboBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.aprsDestinationComboBox_KeyPress);
            // 
            // aprsTextBox
            // 
            this.aprsTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsTextBox.Enabled = false;
            this.aprsTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.aprsTextBox.Location = new System.Drawing.Point(163, 9);
            this.aprsTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.aprsTextBox.MaxLength = 67;
            this.aprsTextBox.Name = "aprsTextBox";
            this.aprsTextBox.Size = new System.Drawing.Size(393, 30);
            this.aprsTextBox.TabIndex = 1;
            this.aprsTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.aprsTextBox_KeyPress);
            // 
            // aprsSendButton
            // 
            this.aprsSendButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsSendButton.ContextMenuStrip = this.aprsSendContextMenuStrip;
            this.aprsSendButton.Enabled = false;
            this.aprsSendButton.Location = new System.Drawing.Point(565, 6);
            this.aprsSendButton.Margin = new System.Windows.Forms.Padding(4);
            this.aprsSendButton.Name = "aprsSendButton";
            this.aprsSendButton.Size = new System.Drawing.Size(100, 33);
            this.aprsSendButton.TabIndex = 0;
            this.aprsSendButton.Text = "&Send";
            this.aprsSendButton.UseVisualStyleBackColor = true;
            this.aprsSendButton.Click += new System.EventHandler(this.aprsSendButton_Click);
            // 
            // aprsSendContextMenuStrip
            // 
            this.aprsSendContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.aprsSendContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.requestPositionToolStripMenuItem});
            this.aprsSendContextMenuStrip.Name = "aprsSendContextMenuStrip";
            this.aprsSendContextMenuStrip.Size = new System.Drawing.Size(188, 28);
            // 
            // requestPositionToolStripMenuItem
            // 
            this.requestPositionToolStripMenuItem.Name = "requestPositionToolStripMenuItem";
            this.requestPositionToolStripMenuItem.Size = new System.Drawing.Size(187, 24);
            this.requestPositionToolStripMenuItem.Text = "Request &Position";
            this.requestPositionToolStripMenuItem.Click += new System.EventHandler(this.requestPositionToolStripMenuItem_Click);
            // 
            // aprsTopPanel
            // 
            this.aprsTopPanel.BackColor = System.Drawing.Color.Silver;
            this.aprsTopPanel.Controls.Add(this.aprsRouteComboBox);
            this.aprsTopPanel.Controls.Add(this.aprsMenuPictureBox);
            this.aprsTopPanel.Controls.Add(this.aprsTitleLabel);
            this.aprsTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.aprsTopPanel.Location = new System.Drawing.Point(0, 0);
            this.aprsTopPanel.Margin = new System.Windows.Forms.Padding(4);
            this.aprsTopPanel.Name = "aprsTopPanel";
            this.aprsTopPanel.Size = new System.Drawing.Size(669, 37);
            this.aprsTopPanel.TabIndex = 2;
            // 
            // aprsRouteComboBox
            // 
            this.aprsRouteComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsRouteComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.aprsRouteComboBox.FormattingEnabled = true;
            this.aprsRouteComboBox.Location = new System.Drawing.Point(504, 6);
            this.aprsRouteComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.aprsRouteComboBox.Name = "aprsRouteComboBox";
            this.aprsRouteComboBox.Size = new System.Drawing.Size(124, 24);
            this.aprsRouteComboBox.TabIndex = 3;
            this.aprsRouteComboBox.Visible = false;
            this.aprsRouteComboBox.SelectionChangeCommitted += new System.EventHandler(this.aprsRouteComboBox_SelectionChangeCommitted);
            // 
            // aprsMenuPictureBox
            // 
            this.aprsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.aprsMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.aprsMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.aprsMenuPictureBox.Name = "aprsMenuPictureBox";
            this.aprsMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.aprsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.aprsMenuPictureBox.TabIndex = 2;
            this.aprsMenuPictureBox.TabStop = false;
            this.aprsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.aprsMenuPictureBox_MouseClick);
            // 
            // aprsTitleLabel
            // 
            this.aprsTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsTitleLabel.AutoSize = true;
            this.aprsTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.aprsTitleLabel.Location = new System.Drawing.Point(7, 6);
            this.aprsTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.aprsTitleLabel.Name = "aprsTitleLabel";
            this.aprsTitleLabel.Size = new System.Drawing.Size(66, 25);
            this.aprsTitleLabel.TabIndex = 0;
            this.aprsTitleLabel.Text = "APRS";
            this.aprsTitleLabel.DoubleClick += new System.EventHandler(this.aprsTitleLabel_DoubleClick);
            // 
            // aprsContextMenuStrip
            // 
            this.aprsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.aprsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showAllMessagesToolStripMenuItem,
            this.toolStripMenuItem7,
            this.beaconSettingsToolStripMenuItem,
            this.smSMessageToolStripMenuItem,
            this.weatherReportToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.aprsContextMenuStrip.Name = "aprsContextMenuStrip";
            this.aprsContextMenuStrip.Size = new System.Drawing.Size(194, 136);
            // 
            // showAllMessagesToolStripMenuItem
            // 
            this.showAllMessagesToolStripMenuItem.CheckOnClick = true;
            this.showAllMessagesToolStripMenuItem.Name = "showAllMessagesToolStripMenuItem";
            this.showAllMessagesToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            this.showAllMessagesToolStripMenuItem.Text = "Show &Telemetry";
            this.showAllMessagesToolStripMenuItem.CheckStateChanged += new System.EventHandler(this.showAllMessagesToolStripMenuItem_CheckStateChanged);
            // 
            // toolStripMenuItem7
            // 
            this.toolStripMenuItem7.Name = "toolStripMenuItem7";
            this.toolStripMenuItem7.Size = new System.Drawing.Size(190, 6);
            // 
            // beaconSettingsToolStripMenuItem
            // 
            this.beaconSettingsToolStripMenuItem.Name = "beaconSettingsToolStripMenuItem";
            this.beaconSettingsToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            this.beaconSettingsToolStripMenuItem.Text = "&Beacon Settings...";
            this.beaconSettingsToolStripMenuItem.Click += new System.EventHandler(this.beaconSettingsToolStripMenuItem_Click);
            // 
            // smSMessageToolStripMenuItem
            // 
            this.smSMessageToolStripMenuItem.Name = "smSMessageToolStripMenuItem";
            this.smSMessageToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            this.smSMessageToolStripMenuItem.Text = "&SMS Message...";
            this.smSMessageToolStripMenuItem.Click += new System.EventHandler(this.aprsSmsButton_Click);
            // 
            // weatherReportToolStripMenuItem
            // 
            this.weatherReportToolStripMenuItem.Name = "weatherReportToolStripMenuItem";
            this.weatherReportToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            this.weatherReportToolStripMenuItem.Text = "&Weather Report...";
            this.weatherReportToolStripMenuItem.Click += new System.EventHandler(this.weatherReportToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(190, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(193, 24);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // aprsMsgContextMenuStrip
            // 
            this.aprsMsgContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.aprsMsgContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.detailsToolStripMenuItem,
            this.showLocationToolStripMenuItem,
            this.copyMessageToolStripMenuItem,
            this.copyCallsignToolStripMenuItem});
            this.aprsMsgContextMenuStrip.Name = "aprsMsgContextMenuStrip";
            this.aprsMsgContextMenuStrip.Size = new System.Drawing.Size(185, 100);
            this.aprsMsgContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.aprsMsgContextMenuStrip_Opening);
            // 
            // detailsToolStripMenuItem
            // 
            this.detailsToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.detailsToolStripMenuItem.Name = "detailsToolStripMenuItem";
            this.detailsToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            this.detailsToolStripMenuItem.Text = "&Details...";
            this.detailsToolStripMenuItem.Click += new System.EventHandler(this.detailsToolStripMenuItem_Click);
            // 
            // showLocationToolStripMenuItem
            // 
            this.showLocationToolStripMenuItem.Name = "showLocationToolStripMenuItem";
            this.showLocationToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            this.showLocationToolStripMenuItem.Text = "Show Location...";
            this.showLocationToolStripMenuItem.Click += new System.EventHandler(this.showLocationToolStripMenuItem_Click);
            // 
            // copyMessageToolStripMenuItem
            // 
            this.copyMessageToolStripMenuItem.Name = "copyMessageToolStripMenuItem";
            this.copyMessageToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            this.copyMessageToolStripMenuItem.Text = "Copy Message";
            this.copyMessageToolStripMenuItem.Click += new System.EventHandler(this.copyMessageToolStripMenuItem_Click);
            // 
            // copyCallsignToolStripMenuItem
            // 
            this.copyCallsignToolStripMenuItem.Name = "copyCallsignToolStripMenuItem";
            this.copyCallsignToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            this.copyCallsignToolStripMenuItem.Text = "Copy Callsign";
            this.copyCallsignToolStripMenuItem.Click += new System.EventHandler(this.copyCallsignToolStripMenuItem_Click);
            // 
            // AprsTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.aprsChatControl);
            this.Controls.Add(this.aprsMissingChannelPanel);
            this.Controls.Add(this.aprsBottomPanel);
            this.Controls.Add(this.aprsTopPanel);
            this.Name = "AprsTabUserControl";
            this.Size = new System.Drawing.Size(669, 658);
            this.aprsMissingChannelPanel.ResumeLayout(false);
            this.aprsMissingChannelPanel.PerformLayout();
            this.aprsBottomPanel.ResumeLayout(false);
            this.aprsBottomPanel.PerformLayout();
            this.aprsSendContextMenuStrip.ResumeLayout(false);
            this.aprsTopPanel.ResumeLayout(false);
            this.aprsTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.aprsMenuPictureBox)).EndInit();
            this.aprsContextMenuStrip.ResumeLayout(false);
            this.aprsMsgContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

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
