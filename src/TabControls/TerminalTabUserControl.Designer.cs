namespace HTCommander.Controls
{
    partial class TerminalTabUserControl
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Component Designer generated code

        private void InitializeComponent()
        {
            components = new System.ComponentModel.Container();
            terminalTextBox = new System.Windows.Forms.RichTextBox();
            terminalFileTransferPanel = new System.Windows.Forms.Panel();
            terminalFileTransferProgressBar = new System.Windows.Forms.ProgressBar();
            terminalFileTransferStatusLabel = new System.Windows.Forms.Label();
            terminalFileTransferCancelButton = new System.Windows.Forms.Button();
            terminalBottomPanel = new System.Windows.Forms.Panel();
            terminalInputTextBox = new System.Windows.Forms.TextBox();
            terminalSendButton = new System.Windows.Forms.Button();
            terminalTopPanel = new System.Windows.Forms.Panel();
            terminalConnectButton = new System.Windows.Forms.Button();
            terminalMenuPictureBox = new System.Windows.Forms.PictureBox();
            terminalTitleLabel = new System.Windows.Forms.Label();
            terminalTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            showCallsignToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            wordWrapToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            waitForConnectionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripSeparator1 = new System.Windows.Forms.ToolStripSeparator();
            clearToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            terminalFileTransferPanel.SuspendLayout();
            terminalBottomPanel.SuspendLayout();
            terminalTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)terminalMenuPictureBox).BeginInit();
            terminalTabContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // terminalTextBox
            // 
            terminalTextBox.BackColor = System.Drawing.Color.Black;
            terminalTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            terminalTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            terminalTextBox.Font = new System.Drawing.Font("Courier New", 12F, System.Drawing.FontStyle.Bold);
            terminalTextBox.ForeColor = System.Drawing.Color.Gainsboro;
            terminalTextBox.Location = new System.Drawing.Point(0, 111);
            terminalTextBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalTextBox.Name = "terminalTextBox";
            terminalTextBox.ReadOnly = true;
            terminalTextBox.Size = new System.Drawing.Size(669, 331);
            terminalTextBox.TabIndex = 4;
            terminalTextBox.Text = "";
            terminalTextBox.WordWrap = false;
            // 
            // terminalFileTransferPanel
            // 
            terminalFileTransferPanel.BackColor = System.Drawing.Color.Silver;
            terminalFileTransferPanel.Controls.Add(terminalFileTransferProgressBar);
            terminalFileTransferPanel.Controls.Add(terminalFileTransferStatusLabel);
            terminalFileTransferPanel.Controls.Add(terminalFileTransferCancelButton);
            terminalFileTransferPanel.Dock = System.Windows.Forms.DockStyle.Top;
            terminalFileTransferPanel.Location = new System.Drawing.Point(0, 46);
            terminalFileTransferPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalFileTransferPanel.Name = "terminalFileTransferPanel";
            terminalFileTransferPanel.Size = new System.Drawing.Size(669, 65);
            terminalFileTransferPanel.TabIndex = 5;
            terminalFileTransferPanel.Visible = false;
            // 
            // terminalFileTransferProgressBar
            // 
            terminalFileTransferProgressBar.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            terminalFileTransferProgressBar.Location = new System.Drawing.Point(9, 45);
            terminalFileTransferProgressBar.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            terminalFileTransferProgressBar.Name = "terminalFileTransferProgressBar";
            terminalFileTransferProgressBar.Size = new System.Drawing.Size(649, 12);
            terminalFileTransferProgressBar.TabIndex = 6;
            terminalFileTransferProgressBar.Value = 65;
            // 
            // terminalFileTransferStatusLabel
            // 
            terminalFileTransferStatusLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            terminalFileTransferStatusLabel.Location = new System.Drawing.Point(7, 12);
            terminalFileTransferStatusLabel.Name = "terminalFileTransferStatusLabel";
            terminalFileTransferStatusLabel.Size = new System.Drawing.Size(545, 21);
            terminalFileTransferStatusLabel.TabIndex = 5;
            terminalFileTransferStatusLabel.Text = "Downloading";
            // 
            // terminalFileTransferCancelButton
            // 
            terminalFileTransferCancelButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            terminalFileTransferCancelButton.Enabled = false;
            terminalFileTransferCancelButton.Location = new System.Drawing.Point(558, 5);
            terminalFileTransferCancelButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalFileTransferCancelButton.Name = "terminalFileTransferCancelButton";
            terminalFileTransferCancelButton.Size = new System.Drawing.Size(100, 35);
            terminalFileTransferCancelButton.TabIndex = 4;
            terminalFileTransferCancelButton.Text = "C&ancel";
            terminalFileTransferCancelButton.UseVisualStyleBackColor = true;
            terminalFileTransferCancelButton.Click += terminalFileTransferCancelButton_Click;
            // 
            // terminalBottomPanel
            // 
            terminalBottomPanel.BackColor = System.Drawing.Color.Silver;
            terminalBottomPanel.Controls.Add(terminalInputTextBox);
            terminalBottomPanel.Controls.Add(terminalSendButton);
            terminalBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            terminalBottomPanel.Location = new System.Drawing.Point(0, 442);
            terminalBottomPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalBottomPanel.Name = "terminalBottomPanel";
            terminalBottomPanel.Size = new System.Drawing.Size(669, 59);
            terminalBottomPanel.TabIndex = 3;
            // 
            // terminalInputTextBox
            // 
            terminalInputTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            terminalInputTextBox.Enabled = false;
            terminalInputTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            terminalInputTextBox.Location = new System.Drawing.Point(9, 9);
            terminalInputTextBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalInputTextBox.Name = "terminalInputTextBox";
            terminalInputTextBox.Size = new System.Drawing.Size(545, 30);
            terminalInputTextBox.TabIndex = 1;
            terminalInputTextBox.KeyPress += terminalInputTextBox_KeyPress;
            // 
            // terminalSendButton
            // 
            terminalSendButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            terminalSendButton.Enabled = false;
            terminalSendButton.Location = new System.Drawing.Point(565, 6);
            terminalSendButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalSendButton.Name = "terminalSendButton";
            terminalSendButton.Size = new System.Drawing.Size(100, 41);
            terminalSendButton.TabIndex = 0;
            terminalSendButton.Text = "&Send";
            terminalSendButton.UseVisualStyleBackColor = true;
            terminalSendButton.Click += terminalSendButton_Click;
            // 
            // terminalTopPanel
            // 
            terminalTopPanel.BackColor = System.Drawing.Color.Silver;
            terminalTopPanel.Controls.Add(terminalConnectButton);
            terminalTopPanel.Controls.Add(terminalMenuPictureBox);
            terminalTopPanel.Controls.Add(terminalTitleLabel);
            terminalTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            terminalTopPanel.Location = new System.Drawing.Point(0, 0);
            terminalTopPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalTopPanel.Name = "terminalTopPanel";
            terminalTopPanel.Size = new System.Drawing.Size(669, 46);
            terminalTopPanel.TabIndex = 1;
            // 
            // terminalConnectButton
            // 
            terminalConnectButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            terminalConnectButton.Enabled = false;
            terminalConnectButton.Location = new System.Drawing.Point(526, 5);
            terminalConnectButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalConnectButton.Name = "terminalConnectButton";
            terminalConnectButton.Size = new System.Drawing.Size(100, 35);
            terminalConnectButton.TabIndex = 4;
            terminalConnectButton.Text = "&Connect";
            terminalConnectButton.UseVisualStyleBackColor = true;
            terminalConnectButton.Click += terminalConnectButton_Click;
            // 
            // terminalMenuPictureBox
            // 
            terminalMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            terminalMenuPictureBox.Image = Properties.Resources.MenuIcon;
            terminalMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            terminalMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalMenuPictureBox.Name = "terminalMenuPictureBox";
            terminalMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            terminalMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            terminalMenuPictureBox.TabIndex = 3;
            terminalMenuPictureBox.TabStop = false;
            terminalMenuPictureBox.MouseClick += terminalMenuPictureBox_MouseClick;
            // 
            // terminalTitleLabel
            // 
            terminalTitleLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            terminalTitleLabel.AutoSize = true;
            terminalTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            terminalTitleLabel.Location = new System.Drawing.Point(4, 8);
            terminalTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            terminalTitleLabel.Name = "terminalTitleLabel";
            terminalTitleLabel.Size = new System.Drawing.Size(88, 25);
            terminalTitleLabel.TabIndex = 1;
            terminalTitleLabel.Text = "Terminal";
            // 
            // terminalTabContextMenuStrip
            // 
            terminalTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            terminalTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { showCallsignToolStripMenuItem, wordWrapToolStripMenuItem, waitForConnectionToolStripMenuItem, toolStripSeparator1, clearToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            terminalTabContextMenuStrip.Name = "terminalTabContextMenuStrip";
            terminalTabContextMenuStrip.Size = new System.Drawing.Size(211, 136);
            // 
            // showCallsignToolStripMenuItem
            // 
            showCallsignToolStripMenuItem.CheckOnClick = true;
            showCallsignToolStripMenuItem.Name = "showCallsignToolStripMenuItem";
            showCallsignToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            showCallsignToolStripMenuItem.Text = "&Show Callsign";
            showCallsignToolStripMenuItem.Click += showCallsignToolStripMenuItem_Click;
            // 
            // wordWrapToolStripMenuItem
            // 
            wordWrapToolStripMenuItem.CheckOnClick = true;
            wordWrapToolStripMenuItem.Name = "wordWrapToolStripMenuItem";
            wordWrapToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            wordWrapToolStripMenuItem.Text = "W&ord Wrap";
            wordWrapToolStripMenuItem.Click += wordWrapToolStripMenuItem_Click;
            // 
            // waitForConnectionToolStripMenuItem
            // 
            waitForConnectionToolStripMenuItem.Name = "waitForConnectionToolStripMenuItem";
            waitForConnectionToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            waitForConnectionToolStripMenuItem.Text = "&Wait for Connection";
            waitForConnectionToolStripMenuItem.Click += waitForConnectionToolStripMenuItem_Click;
            // 
            // toolStripSeparator1
            // 
            toolStripSeparator1.Name = "toolStripSeparator1";
            toolStripSeparator1.Size = new System.Drawing.Size(207, 6);
            // 
            // clearToolStripMenuItem
            // 
            clearToolStripMenuItem.Name = "clearToolStripMenuItem";
            clearToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            clearToolStripMenuItem.Text = "&Clear";
            clearToolStripMenuItem.Click += clearToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(207, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // TerminalTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(terminalTextBox);
            Controls.Add(terminalFileTransferPanel);
            Controls.Add(terminalBottomPanel);
            Controls.Add(terminalTopPanel);
            Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            Name = "TerminalTabUserControl";
            Size = new System.Drawing.Size(669, 501);
            terminalFileTransferPanel.ResumeLayout(false);
            terminalBottomPanel.ResumeLayout(false);
            terminalBottomPanel.PerformLayout();
            terminalTopPanel.ResumeLayout(false);
            terminalTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)terminalMenuPictureBox).EndInit();
            terminalTabContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.RichTextBox terminalTextBox;
        private System.Windows.Forms.Panel terminalFileTransferPanel;
        private System.Windows.Forms.ProgressBar terminalFileTransferProgressBar;
        private System.Windows.Forms.Label terminalFileTransferStatusLabel;
        private System.Windows.Forms.Button terminalFileTransferCancelButton;
        private System.Windows.Forms.Panel terminalBottomPanel;
        private System.Windows.Forms.TextBox terminalInputTextBox;
        private System.Windows.Forms.Button terminalSendButton;
        private System.Windows.Forms.Panel terminalTopPanel;
        private System.Windows.Forms.Button terminalConnectButton;
        private System.Windows.Forms.PictureBox terminalMenuPictureBox;
        private System.Windows.Forms.Label terminalTitleLabel;
        private System.Windows.Forms.ContextMenuStrip terminalTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showCallsignToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem wordWrapToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem waitForConnectionToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripSeparator1;
        private System.Windows.Forms.ToolStripMenuItem clearToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
    }
}
