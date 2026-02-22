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
            toolsPictureBox = new System.Windows.Forms.PictureBox();
            speakTextBox = new System.Windows.Forms.TextBox();
            speakButton = new System.Windows.Forms.Button();
            speakContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            chatToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            speakToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            morseToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            imageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            audioToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            voiceTopPanel = new System.Windows.Forms.Panel();
            voiceProcessingLabel = new System.Windows.Forms.Label();
            voiceMenuPictureBox = new System.Windows.Forms.PictureBox();
            voiceTitleLabel = new System.Windows.Forms.Label();
            voiceTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            recordAudioToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            speechtoTextToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            clearHistoryToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            voiceControl = new VoiceControl();
            voiceMsgContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            viewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            detailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            showLocationToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            copyMessageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            copyCallsignToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            copyImageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            saveAsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            mainImageList = new System.Windows.Forms.ImageList(components);
            mutePanel = new System.Windows.Forms.Panel();
            unMuteButton = new System.Windows.Forms.Button();
            muteLabel = new System.Windows.Forms.Label();
            voiceBottomPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)toolsPictureBox).BeginInit();
            speakContextMenuStrip.SuspendLayout();
            voiceTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)voiceMenuPictureBox).BeginInit();
            voiceTabContextMenuStrip.SuspendLayout();
            voiceMsgContextMenuStrip.SuspendLayout();
            mutePanel.SuspendLayout();
            SuspendLayout();
            // 
            // cancelVoiceButton
            // 
            cancelVoiceButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            cancelVoiceButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, 0);
            cancelVoiceButton.Location = new System.Drawing.Point(9, 10);
            cancelVoiceButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            cancelVoiceButton.Name = "cancelVoiceButton";
            cancelVoiceButton.Size = new System.Drawing.Size(484, 36);
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
            voiceBottomPanel.Controls.Add(toolsPictureBox);
            voiceBottomPanel.Controls.Add(speakTextBox);
            voiceBottomPanel.Controls.Add(speakButton);
            voiceBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            voiceBottomPanel.Location = new System.Drawing.Point(0, 427);
            voiceBottomPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            voiceBottomPanel.Name = "voiceBottomPanel";
            voiceBottomPanel.Size = new System.Drawing.Size(641, 57);
            voiceBottomPanel.TabIndex = 5;
            // 
            // toolsPictureBox
            // 
            toolsPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            toolsPictureBox.Image = Properties.Resources.MenuIcon;
            toolsPictureBox.Location = new System.Drawing.Point(609, 13);
            toolsPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            toolsPictureBox.Name = "toolsPictureBox";
            toolsPictureBox.Size = new System.Drawing.Size(27, 31);
            toolsPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            toolsPictureBox.TabIndex = 7;
            toolsPictureBox.TabStop = false;
            toolsPictureBox.MouseClick += toolsPictureBox_MouseClick;
            // 
            // speakTextBox
            // 
            speakTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            speakTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            speakTextBox.Location = new System.Drawing.Point(9, 12);
            speakTextBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            speakTextBox.MaxLength = 1000;
            speakTextBox.Name = "speakTextBox";
            speakTextBox.Size = new System.Drawing.Size(484, 30);
            speakTextBox.TabIndex = 1;
            speakTextBox.TextChanged += speakTextBox_TextChanged;
            speakTextBox.KeyPress += speakTextBox_KeyPress;
            // 
            // speakButton
            // 
            speakButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            speakButton.ContextMenuStrip = speakContextMenuStrip;
            speakButton.Enabled = false;
            speakButton.Location = new System.Drawing.Point(501, 10);
            speakButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            speakButton.Name = "speakButton";
            speakButton.Size = new System.Drawing.Size(100, 36);
            speakButton.TabIndex = 0;
            speakButton.Text = "&Chat";
            speakButton.UseVisualStyleBackColor = true;
            speakButton.Click += speakButton_Click;
            // 
            // speakContextMenuStrip
            // 
            speakContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            speakContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { chatToolStripMenuItem, speakToolStripMenuItem, morseToolStripMenuItem, toolStripMenuItem1, imageToolStripMenuItem, audioToolStripMenuItem });
            speakContextMenuStrip.Name = "speakContextMenuStrip";
            speakContextMenuStrip.Size = new System.Drawing.Size(130, 140);
            // 
            // chatToolStripMenuItem
            // 
            chatToolStripMenuItem.Checked = true;
            chatToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            chatToolStripMenuItem.Name = "chatToolStripMenuItem";
            chatToolStripMenuItem.Size = new System.Drawing.Size(129, 26);
            chatToolStripMenuItem.Text = "&Chat";
            chatToolStripMenuItem.Click += chatToolStripMenuItem_Click;
            // 
            // speakToolStripMenuItem
            // 
            speakToolStripMenuItem.Name = "speakToolStripMenuItem";
            speakToolStripMenuItem.Size = new System.Drawing.Size(129, 26);
            speakToolStripMenuItem.Text = "&Speak";
            speakToolStripMenuItem.Click += speakToolStripMenuItem_Click;
            // 
            // morseToolStripMenuItem
            // 
            morseToolStripMenuItem.Name = "morseToolStripMenuItem";
            morseToolStripMenuItem.Size = new System.Drawing.Size(129, 26);
            morseToolStripMenuItem.Text = "&Morse";
            morseToolStripMenuItem.Click += morseToolStripMenuItem_Click;
            // 
            // toolStripMenuItem1
            // 
            toolStripMenuItem1.Name = "toolStripMenuItem1";
            toolStripMenuItem1.Size = new System.Drawing.Size(126, 6);
            // 
            // imageToolStripMenuItem
            // 
            imageToolStripMenuItem.Name = "imageToolStripMenuItem";
            imageToolStripMenuItem.Size = new System.Drawing.Size(129, 26);
            imageToolStripMenuItem.Text = "&Image...";
            imageToolStripMenuItem.Click += imageToolStripMenuItem_Click;
            // 
            // audioToolStripMenuItem
            // 
            audioToolStripMenuItem.Name = "audioToolStripMenuItem";
            audioToolStripMenuItem.Size = new System.Drawing.Size(129, 26);
            audioToolStripMenuItem.Text = "&Audio...";
            audioToolStripMenuItem.Click += audioToolStripMenuItem_Click;
            // 
            // voiceTopPanel
            // 
            voiceTopPanel.BackColor = System.Drawing.Color.Silver;
            voiceTopPanel.Controls.Add(voiceProcessingLabel);
            voiceTopPanel.Controls.Add(voiceMenuPictureBox);
            voiceTopPanel.Controls.Add(voiceTitleLabel);
            voiceTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            voiceTopPanel.Location = new System.Drawing.Point(0, 0);
            voiceTopPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            voiceTopPanel.Name = "voiceTopPanel";
            voiceTopPanel.Size = new System.Drawing.Size(641, 46);
            voiceTopPanel.TabIndex = 2;
            // 
            // voiceProcessingLabel
            // 
            voiceProcessingLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            voiceProcessingLabel.AutoSize = true;
            voiceProcessingLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            voiceProcessingLabel.ForeColor = System.Drawing.Color.LightGray;
            voiceProcessingLabel.Location = new System.Drawing.Point(579, 7);
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
            voiceMenuPictureBox.Location = new System.Drawing.Point(609, 8);
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
            voiceTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { recordAudioToolStripMenuItem, speechtoTextToolStripMenuItem, clearHistoryToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            voiceTabContextMenuStrip.Name = "voiceTabContextMenuStrip";
            voiceTabContextMenuStrip.Size = new System.Drawing.Size(180, 106);
            // 
            // recordAudioToolStripMenuItem
            // 
            recordAudioToolStripMenuItem.Name = "recordAudioToolStripMenuItem";
            recordAudioToolStripMenuItem.Size = new System.Drawing.Size(179, 24);
            recordAudioToolStripMenuItem.Text = "&Record Audio";
            recordAudioToolStripMenuItem.Click += recordAudioToolStripMenuItem_Click;
            // 
            // speechtoTextToolStripMenuItem
            // 
            speechtoTextToolStripMenuItem.Name = "speechtoTextToolStripMenuItem";
            speechtoTextToolStripMenuItem.Size = new System.Drawing.Size(179, 24);
            speechtoTextToolStripMenuItem.Text = "&Speech-to-Text";
            speechtoTextToolStripMenuItem.Click += speechtoTextToolStripMenuItem_Click;
            // 
            // clearHistoryToolStripMenuItem
            // 
            clearHistoryToolStripMenuItem.Name = "clearHistoryToolStripMenuItem";
            clearHistoryToolStripMenuItem.Size = new System.Drawing.Size(179, 24);
            clearHistoryToolStripMenuItem.Text = "&Clear History";
            clearHistoryToolStripMenuItem.Click += clearHistoryToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(176, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(179, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // voiceControl
            // 
            voiceControl.AllowDrop = true;
            voiceControl.CallsignFont = new System.Drawing.Font("Arial", 8F);
            voiceControl.CallsignTextColor = System.Drawing.Color.Gray;
            voiceControl.ContextMenuStrip = voiceMsgContextMenuStrip;
            voiceControl.Dock = System.Windows.Forms.DockStyle.Fill;
            voiceControl.Images = mainImageList;
            voiceControl.Location = new System.Drawing.Point(0, 92);
            voiceControl.MessageBoxAuthColor = System.Drawing.Color.LightGreen;
            voiceControl.MessageBoxBadColor = System.Drawing.Color.Pink;
            voiceControl.MessageBoxColor = System.Drawing.Color.LightBlue;
            voiceControl.MessageFont = new System.Drawing.Font("Arial", 10F);
            voiceControl.Name = "voiceControl";
            voiceControl.Size = new System.Drawing.Size(641, 335);
            voiceControl.TabIndex = 6;
            voiceControl.TextColor = System.Drawing.Color.Black;
            voiceControl.DragDrop += voiceControl_DragDrop;
            voiceControl.DragEnter += voiceControl_DragEnter;
            voiceControl.MouseDoubleClick += voiceControl_MouseDoubleClick;
            // 
            // voiceMsgContextMenuStrip
            // 
            voiceMsgContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            voiceMsgContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { viewToolStripMenuItem, detailsToolStripMenuItem, showLocationToolStripMenuItem, copyMessageToolStripMenuItem, copyCallsignToolStripMenuItem, copyImageToolStripMenuItem, saveAsToolStripMenuItem });
            voiceMsgContextMenuStrip.Name = "voiceMsgContextMenuStrip";
            voiceMsgContextMenuStrip.Size = new System.Drawing.Size(185, 172);
            voiceMsgContextMenuStrip.Opening += voiceMsgContextMenuStrip_Opening;
            // 
            // viewToolStripMenuItem
            // 
            viewToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            viewToolStripMenuItem.Name = "viewToolStripMenuItem";
            viewToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            viewToolStripMenuItem.Text = "&View...";
            viewToolStripMenuItem.Click += voiceViewToolStripMenuItem_Click;
            // 
            // detailsToolStripMenuItem
            // 
            detailsToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            detailsToolStripMenuItem.Name = "detailsToolStripMenuItem";
            detailsToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            detailsToolStripMenuItem.Text = "&Details...";
            detailsToolStripMenuItem.Click += voiceDetailsToolStripMenuItem_Click;
            // 
            // showLocationToolStripMenuItem
            // 
            showLocationToolStripMenuItem.Name = "showLocationToolStripMenuItem";
            showLocationToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            showLocationToolStripMenuItem.Text = "Show Location...";
            showLocationToolStripMenuItem.Click += voiceShowLocationToolStripMenuItem_Click;
            // 
            // copyMessageToolStripMenuItem
            // 
            copyMessageToolStripMenuItem.Name = "copyMessageToolStripMenuItem";
            copyMessageToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            copyMessageToolStripMenuItem.Text = "Copy Message";
            copyMessageToolStripMenuItem.Click += voiceCopyMessageToolStripMenuItem_Click;
            // 
            // copyCallsignToolStripMenuItem
            // 
            copyCallsignToolStripMenuItem.Name = "copyCallsignToolStripMenuItem";
            copyCallsignToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            copyCallsignToolStripMenuItem.Text = "Copy Callsign";
            copyCallsignToolStripMenuItem.Click += voiceCopyCallsignToolStripMenuItem_Click;
            // 
            // copyImageToolStripMenuItem
            // 
            copyImageToolStripMenuItem.Name = "copyImageToolStripMenuItem";
            copyImageToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            copyImageToolStripMenuItem.Text = "Copy Image";
            copyImageToolStripMenuItem.Click += voiceCopyImageToolStripMenuItem_Click;
            // 
            // saveAsToolStripMenuItem
            // 
            saveAsToolStripMenuItem.Name = "saveAsToolStripMenuItem";
            saveAsToolStripMenuItem.Size = new System.Drawing.Size(184, 24);
            saveAsToolStripMenuItem.Text = "Save As...";
            saveAsToolStripMenuItem.Click += saveAsToolStripMenuItem_Click;
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
            // mutePanel
            // 
            mutePanel.BackColor = System.Drawing.Color.MistyRose;
            mutePanel.Controls.Add(unMuteButton);
            mutePanel.Controls.Add(muteLabel);
            mutePanel.Dock = System.Windows.Forms.DockStyle.Top;
            mutePanel.Location = new System.Drawing.Point(0, 46);
            mutePanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mutePanel.Name = "mutePanel";
            mutePanel.Size = new System.Drawing.Size(641, 46);
            mutePanel.TabIndex = 7;
            mutePanel.Visible = false;
            // 
            // unMuteButton
            // 
            unMuteButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            unMuteButton.Location = new System.Drawing.Point(537, 5);
            unMuteButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            unMuteButton.Name = "unMuteButton";
            unMuteButton.Size = new System.Drawing.Size(100, 35);
            unMuteButton.TabIndex = 8;
            unMuteButton.Text = "Un-mute";
            unMuteButton.UseVisualStyleBackColor = true;
            unMuteButton.Click += new System.EventHandler(unMuteButton_Click);
            // 
            // muteLabel
            // 
            muteLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            muteLabel.AutoSize = true;
            muteLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            muteLabel.Location = new System.Drawing.Point(7, 13);
            muteLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            muteLabel.Name = "muteLabel";
            muteLabel.Size = new System.Drawing.Size(124, 20);
            muteLabel.TabIndex = 7;
            muteLabel.Text = "Audio is muted.";
            // 
            // VoiceTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(voiceControl);
            Controls.Add(mutePanel);
            Controls.Add(voiceBottomPanel);
            Controls.Add(voiceTopPanel);
            Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            Name = "VoiceTabUserControl";
            Size = new System.Drawing.Size(641, 484);
            voiceBottomPanel.ResumeLayout(false);
            voiceBottomPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)toolsPictureBox).EndInit();
            speakContextMenuStrip.ResumeLayout(false);
            voiceTopPanel.ResumeLayout(false);
            voiceTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)voiceMenuPictureBox).EndInit();
            voiceTabContextMenuStrip.ResumeLayout(false);
            voiceMsgContextMenuStrip.ResumeLayout(false);
            mutePanel.ResumeLayout(false);
            mutePanel.PerformLayout();
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
        private System.Windows.Forms.ContextMenuStrip voiceMsgContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem detailsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem showLocationToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem copyMessageToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem copyCallsignToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem viewToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem copyImageToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem saveAsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem imageToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem audioToolStripMenuItem;
        private System.Windows.Forms.PictureBox toolsPictureBox;
        private System.Windows.Forms.ToolStripMenuItem speechtoTextToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem recordAudioToolStripMenuItem;
        private System.Windows.Forms.Panel mutePanel;
        private System.Windows.Forms.Button unMuteButton;
        private System.Windows.Forms.Label muteLabel;
    }
}
