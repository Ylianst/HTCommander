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
            this.components = new System.ComponentModel.Container();
            this.terminalTextBox = new System.Windows.Forms.RichTextBox();
            this.terminalFileTransferPanel = new System.Windows.Forms.Panel();
            this.terminalFileTransferProgressBar = new System.Windows.Forms.ProgressBar();
            this.terminalFileTransferStatusLabel = new System.Windows.Forms.Label();
            this.terminalFileTransferCancelButton = new System.Windows.Forms.Button();
            this.terminalBottomPanel = new System.Windows.Forms.Panel();
            this.terminalInputTextBox = new System.Windows.Forms.TextBox();
            this.terminalSendButton = new System.Windows.Forms.Button();
            this.terminalTopPanel = new System.Windows.Forms.Panel();
            this.terminalConnectButton = new System.Windows.Forms.Button();
            this.terminalMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.terminalTitleLabel = new System.Windows.Forms.Label();
            this.terminalTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showCallsignToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.wordWrapToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.waitForConnectionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripSeparator1 = new System.Windows.Forms.ToolStripSeparator();
            this.clearToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.terminalFileTransferPanel.SuspendLayout();
            this.terminalBottomPanel.SuspendLayout();
            this.terminalTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.terminalMenuPictureBox)).BeginInit();
            this.terminalTabContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // terminalTextBox
            // 
            this.terminalTextBox.BackColor = System.Drawing.Color.Black;
            this.terminalTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.terminalTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.terminalTextBox.Font = new System.Drawing.Font("Courier New", 12F, System.Drawing.FontStyle.Bold);
            this.terminalTextBox.ForeColor = System.Drawing.Color.Gainsboro;
            this.terminalTextBox.Location = new System.Drawing.Point(0, 89);
            this.terminalTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.terminalTextBox.Name = "terminalTextBox";
            this.terminalTextBox.ReadOnly = true;
            this.terminalTextBox.Size = new System.Drawing.Size(669, 522);
            this.terminalTextBox.TabIndex = 4;
            this.terminalTextBox.Text = "";
            this.terminalTextBox.WordWrap = false;
            // 
            // terminalFileTransferPanel
            // 
            this.terminalFileTransferPanel.BackColor = System.Drawing.Color.Silver;
            this.terminalFileTransferPanel.Controls.Add(this.terminalFileTransferProgressBar);
            this.terminalFileTransferPanel.Controls.Add(this.terminalFileTransferStatusLabel);
            this.terminalFileTransferPanel.Controls.Add(this.terminalFileTransferCancelButton);
            this.terminalFileTransferPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.terminalFileTransferPanel.Location = new System.Drawing.Point(0, 37);
            this.terminalFileTransferPanel.Margin = new System.Windows.Forms.Padding(4);
            this.terminalFileTransferPanel.Name = "terminalFileTransferPanel";
            this.terminalFileTransferPanel.Size = new System.Drawing.Size(669, 52);
            this.terminalFileTransferPanel.TabIndex = 5;
            this.terminalFileTransferPanel.Visible = false;
            // 
            // terminalFileTransferProgressBar
            // 
            this.terminalFileTransferProgressBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalFileTransferProgressBar.Location = new System.Drawing.Point(9, 36);
            this.terminalFileTransferProgressBar.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.terminalFileTransferProgressBar.Name = "terminalFileTransferProgressBar";
            this.terminalFileTransferProgressBar.Size = new System.Drawing.Size(649, 10);
            this.terminalFileTransferProgressBar.TabIndex = 6;
            this.terminalFileTransferProgressBar.Value = 65;
            // 
            // terminalFileTransferStatusLabel
            // 
            this.terminalFileTransferStatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalFileTransferStatusLabel.Location = new System.Drawing.Point(7, 10);
            this.terminalFileTransferStatusLabel.Name = "terminalFileTransferStatusLabel";
            this.terminalFileTransferStatusLabel.Size = new System.Drawing.Size(545, 17);
            this.terminalFileTransferStatusLabel.TabIndex = 5;
            this.terminalFileTransferStatusLabel.Text = "Downloading";
            // 
            // terminalFileTransferCancelButton
            // 
            this.terminalFileTransferCancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalFileTransferCancelButton.Enabled = false;
            this.terminalFileTransferCancelButton.Location = new System.Drawing.Point(558, 4);
            this.terminalFileTransferCancelButton.Margin = new System.Windows.Forms.Padding(4);
            this.terminalFileTransferCancelButton.Name = "terminalFileTransferCancelButton";
            this.terminalFileTransferCancelButton.Size = new System.Drawing.Size(100, 28);
            this.terminalFileTransferCancelButton.TabIndex = 4;
            this.terminalFileTransferCancelButton.Text = "C&ancel";
            this.terminalFileTransferCancelButton.UseVisualStyleBackColor = true;
            this.terminalFileTransferCancelButton.Click += new System.EventHandler(this.terminalFileTransferCancelButton_Click);
            // 
            // terminalBottomPanel
            // 
            this.terminalBottomPanel.BackColor = System.Drawing.Color.Silver;
            this.terminalBottomPanel.Controls.Add(this.terminalInputTextBox);
            this.terminalBottomPanel.Controls.Add(this.terminalSendButton);
            this.terminalBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.terminalBottomPanel.Location = new System.Drawing.Point(0, 611);
            this.terminalBottomPanel.Margin = new System.Windows.Forms.Padding(4);
            this.terminalBottomPanel.Name = "terminalBottomPanel";
            this.terminalBottomPanel.Size = new System.Drawing.Size(669, 47);
            this.terminalBottomPanel.TabIndex = 3;
            // 
            // terminalInputTextBox
            // 
            this.terminalInputTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalInputTextBox.Enabled = false;
            this.terminalInputTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.terminalInputTextBox.Location = new System.Drawing.Point(9, 7);
            this.terminalInputTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.terminalInputTextBox.Name = "terminalInputTextBox";
            this.terminalInputTextBox.Size = new System.Drawing.Size(545, 30);
            this.terminalInputTextBox.TabIndex = 1;
            this.terminalInputTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.terminalInputTextBox_KeyPress);
            // 
            // terminalSendButton
            // 
            this.terminalSendButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalSendButton.Enabled = false;
            this.terminalSendButton.Location = new System.Drawing.Point(565, 5);
            this.terminalSendButton.Margin = new System.Windows.Forms.Padding(4);
            this.terminalSendButton.Name = "terminalSendButton";
            this.terminalSendButton.Size = new System.Drawing.Size(100, 33);
            this.terminalSendButton.TabIndex = 0;
            this.terminalSendButton.Text = "&Send";
            this.terminalSendButton.UseVisualStyleBackColor = true;
            this.terminalSendButton.Click += new System.EventHandler(this.terminalSendButton_Click);
            // 
            // terminalTopPanel
            // 
            this.terminalTopPanel.BackColor = System.Drawing.Color.Silver;
            this.terminalTopPanel.Controls.Add(this.terminalConnectButton);
            this.terminalTopPanel.Controls.Add(this.terminalMenuPictureBox);
            this.terminalTopPanel.Controls.Add(this.terminalTitleLabel);
            this.terminalTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.terminalTopPanel.Location = new System.Drawing.Point(0, 0);
            this.terminalTopPanel.Margin = new System.Windows.Forms.Padding(4);
            this.terminalTopPanel.Name = "terminalTopPanel";
            this.terminalTopPanel.Size = new System.Drawing.Size(669, 37);
            this.terminalTopPanel.TabIndex = 1;
            // 
            // terminalConnectButton
            // 
            this.terminalConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalConnectButton.Enabled = false;
            this.terminalConnectButton.Location = new System.Drawing.Point(526, 4);
            this.terminalConnectButton.Margin = new System.Windows.Forms.Padding(4);
            this.terminalConnectButton.Name = "terminalConnectButton";
            this.terminalConnectButton.Size = new System.Drawing.Size(100, 28);
            this.terminalConnectButton.TabIndex = 4;
            this.terminalConnectButton.Text = "&Connect";
            this.terminalConnectButton.UseVisualStyleBackColor = true;
            this.terminalConnectButton.Click += new System.EventHandler(this.terminalConnectButton_Click);
            // 
            // terminalMenuPictureBox
            // 
            this.terminalMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.terminalMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.terminalMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.terminalMenuPictureBox.Name = "terminalMenuPictureBox";
            this.terminalMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.terminalMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.terminalMenuPictureBox.TabIndex = 3;
            this.terminalMenuPictureBox.TabStop = false;
            this.terminalMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.terminalMenuPictureBox_MouseClick);
            // 
            // terminalTitleLabel
            // 
            this.terminalTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalTitleLabel.AutoSize = true;
            this.terminalTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.terminalTitleLabel.Location = new System.Drawing.Point(4, 6);
            this.terminalTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.terminalTitleLabel.Name = "terminalTitleLabel";
            this.terminalTitleLabel.Size = new System.Drawing.Size(88, 25);
            this.terminalTitleLabel.TabIndex = 1;
            this.terminalTitleLabel.Text = "Terminal";
            // 
            // terminalTabContextMenuStrip
            // 
            this.terminalTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.terminalTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showCallsignToolStripMenuItem,
            this.wordWrapToolStripMenuItem,
            this.waitForConnectionToolStripMenuItem,
            this.toolStripSeparator1,
            this.clearToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.terminalTabContextMenuStrip.Name = "terminalTabContextMenuStrip";
            this.terminalTabContextMenuStrip.Size = new System.Drawing.Size(211, 136);
            // 
            // showCallsignToolStripMenuItem
            // 
            this.showCallsignToolStripMenuItem.CheckOnClick = true;
            this.showCallsignToolStripMenuItem.Name = "showCallsignToolStripMenuItem";
            this.showCallsignToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.showCallsignToolStripMenuItem.Text = "&Show Callsign";
            this.showCallsignToolStripMenuItem.Click += new System.EventHandler(this.showCallsignToolStripMenuItem_Click);
            // 
            // wordWrapToolStripMenuItem
            // 
            this.wordWrapToolStripMenuItem.CheckOnClick = true;
            this.wordWrapToolStripMenuItem.Name = "wordWrapToolStripMenuItem";
            this.wordWrapToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.wordWrapToolStripMenuItem.Text = "W&ord Wrap";
            this.wordWrapToolStripMenuItem.Click += new System.EventHandler(this.wordWrapToolStripMenuItem_Click);
            // 
            // waitForConnectionToolStripMenuItem
            // 
            this.waitForConnectionToolStripMenuItem.Name = "waitForConnectionToolStripMenuItem";
            this.waitForConnectionToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.waitForConnectionToolStripMenuItem.Text = "&Wait for Connection";
            this.waitForConnectionToolStripMenuItem.Click += new System.EventHandler(this.waitForConnectionToolStripMenuItem_Click);
            // 
            // toolStripSeparator1
            // 
            this.toolStripSeparator1.Name = "toolStripSeparator1";
            this.toolStripSeparator1.Size = new System.Drawing.Size(207, 6);
            // 
            // clearToolStripMenuItem
            // 
            this.clearToolStripMenuItem.Name = "clearToolStripMenuItem";
            this.clearToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.clearToolStripMenuItem.Text = "&Clear";
            this.clearToolStripMenuItem.Click += new System.EventHandler(this.clearToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(207, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // TerminalTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.terminalTextBox);
            this.Controls.Add(this.terminalFileTransferPanel);
            this.Controls.Add(this.terminalBottomPanel);
            this.Controls.Add(this.terminalTopPanel);
            this.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.Name = "TerminalTabUserControl";
            this.Size = new System.Drawing.Size(669, 658);
            this.terminalFileTransferPanel.ResumeLayout(false);
            this.terminalBottomPanel.ResumeLayout(false);
            this.terminalBottomPanel.PerformLayout();
            this.terminalTopPanel.ResumeLayout(false);
            this.terminalTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.terminalMenuPictureBox)).EndInit();
            this.terminalTabContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

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
