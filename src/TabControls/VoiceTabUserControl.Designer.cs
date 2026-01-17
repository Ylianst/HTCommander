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
            this.cancelVoiceButton = new System.Windows.Forms.Button();
            this.voiceHistoryTextBox = new System.Windows.Forms.RichTextBox();
            this.voiceBottomPanel = new System.Windows.Forms.Panel();
            this.speakTextBox = new System.Windows.Forms.TextBox();
            this.speakButton = new System.Windows.Forms.Button();
            this.speakContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.speakToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.morseToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.voiceTopPanel = new System.Windows.Forms.Panel();
            this.voiceProcessingLabel = new System.Windows.Forms.Label();
            this.voiceEnableButton = new System.Windows.Forms.Button();
            this.voiceMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.voiceTitleLabel = new System.Windows.Forms.Label();
            this.voiceTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.clearHistoryToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.voiceBottomPanel.SuspendLayout();
            this.speakContextMenuStrip.SuspendLayout();
            this.voiceTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.voiceMenuPictureBox)).BeginInit();
            this.voiceTabContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // cancelVoiceButton
            // 
            this.cancelVoiceButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelVoiceButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.cancelVoiceButton.Location = new System.Drawing.Point(507, 486);
            this.cancelVoiceButton.Margin = new System.Windows.Forms.Padding(4);
            this.cancelVoiceButton.Name = "cancelVoiceButton";
            this.cancelVoiceButton.Size = new System.Drawing.Size(121, 64);
            this.cancelVoiceButton.TabIndex = 6;
            this.cancelVoiceButton.Text = "Cancel";
            this.cancelVoiceButton.UseVisualStyleBackColor = true;
            this.cancelVoiceButton.Visible = false;
            this.cancelVoiceButton.Click += new System.EventHandler(this.cancelVoiceButton_Click);
            // 
            // voiceHistoryTextBox
            // 
            this.voiceHistoryTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.voiceHistoryTextBox.Location = new System.Drawing.Point(0, 37);
            this.voiceHistoryTextBox.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.voiceHistoryTextBox.Name = "voiceHistoryTextBox";
            this.voiceHistoryTextBox.ReadOnly = true;
            this.voiceHistoryTextBox.ScrollBars = System.Windows.Forms.RichTextBoxScrollBars.ForcedVertical;
            this.voiceHistoryTextBox.Size = new System.Drawing.Size(669, 574);
            this.voiceHistoryTextBox.TabIndex = 0;
            this.voiceHistoryTextBox.Text = "";
            // 
            // voiceBottomPanel
            // 
            this.voiceBottomPanel.BackColor = System.Drawing.Color.Silver;
            this.voiceBottomPanel.Controls.Add(this.speakTextBox);
            this.voiceBottomPanel.Controls.Add(this.speakButton);
            this.voiceBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.voiceBottomPanel.Location = new System.Drawing.Point(0, 611);
            this.voiceBottomPanel.Margin = new System.Windows.Forms.Padding(4);
            this.voiceBottomPanel.Name = "voiceBottomPanel";
            this.voiceBottomPanel.Size = new System.Drawing.Size(669, 47);
            this.voiceBottomPanel.TabIndex = 5;
            // 
            // speakTextBox
            // 
            this.speakTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.speakTextBox.Enabled = false;
            this.speakTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.speakTextBox.Location = new System.Drawing.Point(9, 9);
            this.speakTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.speakTextBox.MaxLength = 1000;
            this.speakTextBox.Name = "speakTextBox";
            this.speakTextBox.Size = new System.Drawing.Size(545, 30);
            this.speakTextBox.TabIndex = 1;
            this.speakTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.speakTextBox_KeyPress);
            // 
            // speakButton
            // 
            this.speakButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.speakButton.ContextMenuStrip = this.speakContextMenuStrip;
            this.speakButton.Enabled = false;
            this.speakButton.Location = new System.Drawing.Point(565, 6);
            this.speakButton.Margin = new System.Windows.Forms.Padding(4);
            this.speakButton.Name = "speakButton";
            this.speakButton.Size = new System.Drawing.Size(100, 33);
            this.speakButton.TabIndex = 0;
            this.speakButton.Text = "&Speak";
            this.speakButton.UseVisualStyleBackColor = true;
            this.speakButton.Click += new System.EventHandler(this.speakButton_Click);
            // 
            // speakContextMenuStrip
            // 
            this.speakContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.speakContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.speakToolStripMenuItem,
            this.morseToolStripMenuItem});
            this.speakContextMenuStrip.Name = "speakContextMenuStrip";
            this.speakContextMenuStrip.Size = new System.Drawing.Size(120, 56);
            // 
            // speakToolStripMenuItem
            // 
            this.speakToolStripMenuItem.Checked = true;
            this.speakToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.speakToolStripMenuItem.Name = "speakToolStripMenuItem";
            this.speakToolStripMenuItem.Size = new System.Drawing.Size(119, 26);
            this.speakToolStripMenuItem.Text = "&Speak";
            this.speakToolStripMenuItem.Click += new System.EventHandler(this.speakToolStripMenuItem_Click);
            // 
            // morseToolStripMenuItem
            // 
            this.morseToolStripMenuItem.Name = "morseToolStripMenuItem";
            this.morseToolStripMenuItem.Size = new System.Drawing.Size(119, 26);
            this.morseToolStripMenuItem.Text = "&Morse";
            this.morseToolStripMenuItem.Click += new System.EventHandler(this.morseToolStripMenuItem_Click);
            // 
            // voiceTopPanel
            // 
            this.voiceTopPanel.BackColor = System.Drawing.Color.Silver;
            this.voiceTopPanel.Controls.Add(this.voiceProcessingLabel);
            this.voiceTopPanel.Controls.Add(this.voiceEnableButton);
            this.voiceTopPanel.Controls.Add(this.voiceMenuPictureBox);
            this.voiceTopPanel.Controls.Add(this.voiceTitleLabel);
            this.voiceTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.voiceTopPanel.Location = new System.Drawing.Point(0, 0);
            this.voiceTopPanel.Margin = new System.Windows.Forms.Padding(4);
            this.voiceTopPanel.Name = "voiceTopPanel";
            this.voiceTopPanel.Size = new System.Drawing.Size(669, 37);
            this.voiceTopPanel.TabIndex = 2;
            // 
            // voiceProcessingLabel
            // 
            this.voiceProcessingLabel.AutoSize = true;
            this.voiceProcessingLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.voiceProcessingLabel.ForeColor = System.Drawing.Color.LightGray;
            this.voiceProcessingLabel.Location = new System.Drawing.Point(72, 6);
            this.voiceProcessingLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.voiceProcessingLabel.Name = "voiceProcessingLabel";
            this.voiceProcessingLabel.Size = new System.Drawing.Size(24, 25);
            this.voiceProcessingLabel.TabIndex = 7;
            this.voiceProcessingLabel.Text = "●";
            this.voiceProcessingLabel.Visible = false;
            // 
            // voiceEnableButton
            // 
            this.voiceEnableButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.voiceEnableButton.Enabled = false;
            this.voiceEnableButton.Location = new System.Drawing.Point(529, 4);
            this.voiceEnableButton.Margin = new System.Windows.Forms.Padding(4);
            this.voiceEnableButton.Name = "voiceEnableButton";
            this.voiceEnableButton.Size = new System.Drawing.Size(100, 28);
            this.voiceEnableButton.TabIndex = 6;
            this.voiceEnableButton.Text = "&Enable";
            this.voiceEnableButton.UseVisualStyleBackColor = true;
            this.voiceEnableButton.Click += new System.EventHandler(this.voiceEnableButton_Click);
            // 
            // voiceMenuPictureBox
            // 
            this.voiceMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.voiceMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.voiceMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.voiceMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.voiceMenuPictureBox.Name = "voiceMenuPictureBox";
            this.voiceMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.voiceMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.voiceMenuPictureBox.TabIndex = 3;
            this.voiceMenuPictureBox.TabStop = false;
            this.voiceMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.voiceMenuPictureBox_MouseClick);
            // 
            // voiceTitleLabel
            // 
            this.voiceTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.voiceTitleLabel.AutoSize = true;
            this.voiceTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.voiceTitleLabel.Location = new System.Drawing.Point(4, 6);
            this.voiceTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.voiceTitleLabel.Name = "voiceTitleLabel";
            this.voiceTitleLabel.Size = new System.Drawing.Size(62, 25);
            this.voiceTitleLabel.TabIndex = 1;
            this.voiceTitleLabel.Text = "Voice";
            // 
            // voiceTabContextMenuStrip
            // 
            this.voiceTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.voiceTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.clearHistoryToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.voiceTabContextMenuStrip.Name = "voiceTabContextMenuStrip";
            this.voiceTabContextMenuStrip.Size = new System.Drawing.Size(164, 58);
            // 
            // clearHistoryToolStripMenuItem
            // 
            this.clearHistoryToolStripMenuItem.Name = "clearHistoryToolStripMenuItem";
            this.clearHistoryToolStripMenuItem.Size = new System.Drawing.Size(163, 24);
            this.clearHistoryToolStripMenuItem.Text = "&Clear History";
            this.clearHistoryToolStripMenuItem.Click += new System.EventHandler(this.clearHistoryToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(160, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(163, 24);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // VoiceTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.cancelVoiceButton);
            this.Controls.Add(this.voiceHistoryTextBox);
            this.Controls.Add(this.voiceBottomPanel);
            this.Controls.Add(this.voiceTopPanel);
            this.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.Name = "VoiceTabUserControl";
            this.Size = new System.Drawing.Size(669, 658);
            this.voiceBottomPanel.ResumeLayout(false);
            this.voiceBottomPanel.PerformLayout();
            this.speakContextMenuStrip.ResumeLayout(false);
            this.voiceTopPanel.ResumeLayout(false);
            this.voiceTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.voiceMenuPictureBox)).EndInit();
            this.voiceTabContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Button cancelVoiceButton;
        private System.Windows.Forms.RichTextBox voiceHistoryTextBox;
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
    }
}
