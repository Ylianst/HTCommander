namespace HTCommander.Controls
{
    partial class VoiceTabUserControl
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
                // Dispose the DataBrokerClient to unsubscribe from all events
                broker?.Dispose();
                broker = null;

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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(VoiceTabUserControl));
            cancelVoiceButton = new System.Windows.Forms.Button();
            voiceBottomPanel = new System.Windows.Forms.Panel();
            speakTextBox = new System.Windows.Forms.TextBox();
            speakButton = new System.Windows.Forms.Button();
            speakContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            chatToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            speakToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            morseToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            voiceTopPanel = new System.Windows.Forms.Panel();
            voiceEnableButton = new System.Windows.Forms.Button();
            voiceProcessingLabel = new System.Windows.Forms.Label();
            voiceMenuPictureBox = new System.Windows.Forms.PictureBox();
            voiceTitleLabel = new System.Windows.Forms.Label();
            voiceTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            clearHistoryToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            voiceControl = new VoiceControl();
            mainImageList = new System.Windows.Forms.ImageList(components);
            voiceBottomPanel.SuspendLayout();
            speakContextMenuStrip.SuspendLayout();
            voiceTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)voiceMenuPictureBox).BeginInit();
            voiceTabContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // cancelVoiceButton
            // 
            cancelVoiceButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            cancelVoiceButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, 0);
            cancelVoiceButton.Location = new System.Drawing.Point(9, 8);
            cancelVoiceButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            cancelVoiceButton.Name = "cancelVoiceButton";
            cancelVoiceButton.Size = new System.Drawing.Size(544, 41);
            cancelVoiceButton.TabIndex = 6;
            cancelVoiceButton.Text = "Cancel";
            cancelVoiceButton.UseVisualStyleBackColor = true;
            cancelVoiceButton.Visible = false;
            cancelVoiceButton.Click += cancelVoiceButton_Click;
            // 
            // voiceBottomPanel
            // 
            voiceBottomPanel.BackColor = System.Drawing.Color.Silver;
            voiceBottomPanel.Controls.Add(cancelVoiceButton);
            voiceBottomPanel.Controls.Add(speakTextBox);
            voiceBottomPanel.Controls.Add(speakButton);
            voiceBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            voiceBottomPanel.Location = new System.Drawing.Point(0, 449);
            voiceBottomPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            voiceBottomPanel.Name = "voiceBottomPanel";
            voiceBottomPanel.Size = new System.Drawing.Size(669, 59);
            voiceBottomPanel.TabIndex = 5;
            // 
            // speakTextBox
            // 
            speakTextBox.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            speakTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            speakTextBox.Location = new System.Drawing.Point(9, 11);
            speakTextBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            speakTextBox.MaxLength = 1000;
            speakTextBox.Name = "speakTextBox";
            speakTextBox.Size = new System.Drawing.Size(544, 30);
            speakTextBox.TabIndex = 1;
            speakTextBox.TextChanged += speakTextBox_TextChanged;
            speakTextBox.KeyPress += speakTextBox_KeyPress;
            // 
            // speakButton
            // 
            speakButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            speakButton.ContextMenuStrip = speakContextMenuStrip;
            speakButton.Enabled = false;
            speakButton.Location = new System.Drawing.Point(561, 8);
            speakButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            speakButton.Name = "speakButton";
            speakButton.Size = new System.Drawing.Size(100, 41);
            speakButton.TabIndex = 0;
            speakButton.Text = "&Chat";
            speakButton.UseVisualStyleBackColor = true;
            speakButton.Click += speakButton_Click;
            // 
            // speakContextMenuStrip
            // 
            speakContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            speakContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { chatToolStripMenuItem, speakToolStripMenuItem, morseToolStripMenuItem });
            speakContextMenuStrip.Name = "speakContextMenuStrip";
            speakContextMenuStrip.Size = new System.Drawing.Size(120, 82);
            // 
            // chatToolStripMenuItem
            // 
            chatToolStripMenuItem.Checked = true;
            chatToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            chatToolStripMenuItem.Name = "chatToolStripMenuItem";
            chatToolStripMenuItem.Size = new System.Drawing.Size(119, 26);
            chatToolStripMenuItem.Text = "&Chat";
            chatToolStripMenuItem.Click += chatToolStripMenuItem_Click;
            // 
            // speakToolStripMenuItem
            // 
            speakToolStripMenuItem.Name = "speakToolStripMenuItem";
            speakToolStripMenuItem.Size = new System.Drawing.Size(119, 26);
            speakToolStripMenuItem.Text = "&Speak";
            speakToolStripMenuItem.Click += speakToolStripMenuItem_Click;
            // 
            // morseToolStripMenuItem
            // 
            morseToolStripMenuItem.Name = "morseToolStripMenuItem";
            morseToolStripMenuItem.Size = new System.Drawing.Size(119, 26);
            morseToolStripMenuItem.Text = "&Morse";
            morseToolStripMenuItem.Click += morseToolStripMenuItem_Click;
            // 
            // voiceTopPanel
            // 
            voiceTopPanel.BackColor = System.Drawing.Color.Silver;
            voiceTopPanel.Controls.Add(voiceEnableButton);
            voiceTopPanel.Controls.Add(voiceProcessingLabel);
            voiceTopPanel.Controls.Add(voiceMenuPictureBox);
            voiceTopPanel.Controls.Add(voiceTitleLabel);
            voiceTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            voiceTopPanel.Location = new System.Drawing.Point(0, 0);
            voiceTopPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            voiceTopPanel.Name = "voiceTopPanel";
            voiceTopPanel.Size = new System.Drawing.Size(669, 46);
            voiceTopPanel.TabIndex = 2;
            // 
            // voiceEnableButton
            // 
            voiceEnableButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            voiceEnableButton.Enabled = false;
            voiceEnableButton.Location = new System.Drawing.Point(529, 5);
            voiceEnableButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            voiceEnableButton.Name = "voiceEnableButton";
            voiceEnableButton.Size = new System.Drawing.Size(100, 35);
            voiceEnableButton.TabIndex = 6;
            voiceEnableButton.Text = "&Enable";
            voiceEnableButton.UseVisualStyleBackColor = true;
            voiceEnableButton.Click += voiceEnableButton_Click;
            // 
            // voiceProcessingLabel
            // 
            voiceProcessingLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            voiceProcessingLabel.AutoSize = true;
            voiceProcessingLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            voiceProcessingLabel.ForeColor = System.Drawing.Color.LightGray;
            voiceProcessingLabel.Location = new System.Drawing.Point(506, 8);
            voiceProcessingLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            voiceProcessingLabel.Name = "voiceProcessingLabel";
            voiceProcessingLabel.Size = new System.Drawing.Size(24, 25);
            voiceProcessingLabel.TabIndex = 7;
            voiceProcessingLabel.Text = "●";
            voiceProcessingLabel.Visible = false;
            // 
            // voiceMenuPictureBox
            // 
            voiceMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            voiceMenuPictureBox.Image = Properties.Resources.MenuIcon;
            voiceMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            voiceMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            voiceMenuPictureBox.Name = "voiceMenuPictureBox";
            voiceMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            voiceMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            voiceMenuPictureBox.TabIndex = 3;
            voiceMenuPictureBox.TabStop = false;
            voiceMenuPictureBox.MouseClick += voiceMenuPictureBox_MouseClick;
            // 
            // voiceTitleLabel
            // 
            voiceTitleLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            voiceTitleLabel.AutoSize = true;
            voiceTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            voiceTitleLabel.Location = new System.Drawing.Point(4, 8);
            voiceTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            voiceTitleLabel.Name = "voiceTitleLabel";
            voiceTitleLabel.Size = new System.Drawing.Size(148, 25);
            voiceTitleLabel.TabIndex = 1;
            voiceTitleLabel.Text = "Communication";
            // 
            // voiceTabContextMenuStrip
            // 
            voiceTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            voiceTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { clearHistoryToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            voiceTabContextMenuStrip.Name = "voiceTabContextMenuStrip";
            voiceTabContextMenuStrip.Size = new System.Drawing.Size(164, 58);
            // 
            // clearHistoryToolStripMenuItem
            // 
            clearHistoryToolStripMenuItem.Name = "clearHistoryToolStripMenuItem";
            clearHistoryToolStripMenuItem.Size = new System.Drawing.Size(163, 24);
            clearHistoryToolStripMenuItem.Text = "&Clear History";
            clearHistoryToolStripMenuItem.Click += clearHistoryToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(160, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(163, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // voiceControl
            // 
            voiceControl.CallsignFont = new System.Drawing.Font("Arial", 8F);
            voiceControl.CallsignTextColor = System.Drawing.Color.Gray;
            voiceControl.Dock = System.Windows.Forms.DockStyle.Fill;
            voiceControl.Images = mainImageList;
            voiceControl.Location = new System.Drawing.Point(0, 46);
            voiceControl.MessageBoxAuthColor = System.Drawing.Color.LightGreen;
            voiceControl.MessageBoxBadColor = System.Drawing.Color.Pink;
            voiceControl.MessageBoxColor = System.Drawing.Color.LightBlue;
            voiceControl.MessageFont = new System.Drawing.Font("Arial", 10F);
            voiceControl.Name = "voiceControl";
            voiceControl.Size = new System.Drawing.Size(669, 403);
            voiceControl.TabIndex = 6;
            voiceControl.TextColor = System.Drawing.Color.Black;
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
            // 
            // VoiceTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(voiceControl);
            Controls.Add(voiceBottomPanel);
            Controls.Add(voiceTopPanel);
            Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            Name = "VoiceTabUserControl";
            Size = new System.Drawing.Size(669, 508);
            voiceBottomPanel.ResumeLayout(false);
            voiceBottomPanel.PerformLayout();
            speakContextMenuStrip.ResumeLayout(false);
            voiceTopPanel.ResumeLayout(false);
            voiceTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)voiceMenuPictureBox).EndInit();
            voiceTabContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Button cancelVoiceButton;
        private System.Windows.Forms.Panel voiceBottomPanel;
        private System.Windows.Forms.TextBox speakTextBox;
        private System.Windows.Forms.Button speakButton;
        private System.Windows.Forms.ContextMenuStrip speakContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem speakToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem morseToolStripMenuItem;
        private System.Windows.Forms.Panel voiceTopPanel;
        private System.Windows.Forms.Button voiceEnableButton;
        private System.Windows.Forms.PictureBox voiceMenuPictureBox;
        private System.Windows.Forms.Label voiceTitleLabel;
        private System.Windows.Forms.Label voiceProcessingLabel;
        private System.Windows.Forms.ContextMenuStrip voiceTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem clearHistoryToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem chatToolStripMenuItem;
        private VoiceControl voiceControl;
        private System.Windows.Forms.ImageList mainImageList;
    }
}
