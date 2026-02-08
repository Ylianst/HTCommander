namespace HTCommander
{
    partial class MailComposeForm
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

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(MailComposeForm));
            panel2 = new System.Windows.Forms.Panel();
            sendButton = new System.Windows.Forms.Button();
            ccTextBox = new System.Windows.Forms.TextBox();
            toTextBox = new System.Windows.Forms.TextBox();
            label3 = new System.Windows.Forms.Label();
            mailPictureBox = new System.Windows.Forms.PictureBox();
            label2 = new System.Windows.Forms.Label();
            label1 = new System.Windows.Forms.Label();
            subjectTextBox = new System.Windows.Forms.TextBox();
            mainTextBox = new System.Windows.Forms.TextBox();
            mainMenuStrip = new System.Windows.Forms.MenuStrip();
            fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            draftToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            cancelToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            sendToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            attachmentsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            addToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            attachmentsFlowLayoutPanel = new System.Windows.Forms.FlowLayoutPanel();
            addAttachementPpenFileDialog = new System.Windows.Forms.OpenFileDialog();
            panel2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)mailPictureBox).BeginInit();
            mainMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // panel2
            // 
            panel2.BackColor = System.Drawing.Color.Silver;
            panel2.Controls.Add(sendButton);
            panel2.Controls.Add(ccTextBox);
            panel2.Controls.Add(toTextBox);
            panel2.Controls.Add(label3);
            panel2.Controls.Add(mailPictureBox);
            panel2.Controls.Add(label2);
            panel2.Controls.Add(label1);
            panel2.Controls.Add(subjectTextBox);
            panel2.Dock = System.Windows.Forms.DockStyle.Top;
            panel2.Location = new System.Drawing.Point(0, 24);
            panel2.Margin = new System.Windows.Forms.Padding(4);
            panel2.Name = "panel2";
            panel2.Size = new System.Drawing.Size(511, 94);
            panel2.TabIndex = 3;
            panel2.Paint += panel2_Paint;
            // 
            // sendButton
            // 
            sendButton.Location = new System.Drawing.Point(447, 64);
            sendButton.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            sendButton.Name = "sendButton";
            sendButton.Size = new System.Drawing.Size(57, 25);
            sendButton.TabIndex = 14;
            sendButton.Text = "Send";
            sendButton.UseVisualStyleBackColor = true;
            sendButton.Click += sendButton_Click;
            // 
            // ccTextBox
            // 
            ccTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            ccTextBox.Location = new System.Drawing.Point(83, 37);
            ccTextBox.Name = "ccTextBox";
            ccTextBox.Size = new System.Drawing.Size(360, 23);
            ccTextBox.TabIndex = 11;
            ccTextBox.TextChanged += ccTextBox_TextChanged;
            ccTextBox.Leave += ccTextBox_Leave;
            // 
            // toTextBox
            // 
            toTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            toTextBox.Location = new System.Drawing.Point(83, 8);
            toTextBox.Name = "toTextBox";
            toTextBox.Size = new System.Drawing.Size(360, 23);
            toTextBox.TabIndex = 10;
            toTextBox.TextChanged += toTextBox_TextChanged;
            toTextBox.Leave += toTextBox_Leave;
            // 
            // label3
            // 
            label3.AutoSize = true;
            label3.Location = new System.Drawing.Point(11, 39);
            label3.Name = "label3";
            label3.Size = new System.Drawing.Size(23, 15);
            label3.TabIndex = 12;
            label3.Text = "CC";
            // 
            // mailPictureBox
            // 
            mailPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            mailPictureBox.Image = Properties.Resources.Letter;
            mailPictureBox.Location = new System.Drawing.Point(447, 8);
            mailPictureBox.Name = "mailPictureBox";
            mailPictureBox.Size = new System.Drawing.Size(57, 52);
            mailPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            mailPictureBox.TabIndex = 8;
            mailPictureBox.TabStop = false;
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new System.Drawing.Point(11, 68);
            label2.Name = "label2";
            label2.Size = new System.Drawing.Size(46, 15);
            label2.TabIndex = 9;
            label2.Text = "Subject";
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new System.Drawing.Point(10, 11);
            label1.Name = "label1";
            label1.Size = new System.Drawing.Size(20, 15);
            label1.TabIndex = 7;
            label1.Text = "To";
            // 
            // subjectTextBox
            // 
            subjectTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            subjectTextBox.Location = new System.Drawing.Point(83, 66);
            subjectTextBox.Name = "subjectTextBox";
            subjectTextBox.Size = new System.Drawing.Size(360, 23);
            subjectTextBox.TabIndex = 12;
            subjectTextBox.TextChanged += subjectTextBox_TextChanged;
            // 
            // mainTextBox
            // 
            mainTextBox.AllowDrop = true;
            mainTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            mainTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 10.2F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            mainTextBox.Location = new System.Drawing.Point(0, 118);
            mainTextBox.Multiline = true;
            mainTextBox.Name = "mainTextBox";
            mainTextBox.Size = new System.Drawing.Size(511, 394);
            mainTextBox.TabIndex = 13;
            mainTextBox.TextChanged += mainTextBox_TextChanged;
            mainTextBox.DragDrop += mainTextBox_DragDrop;
            mainTextBox.DragEnter += mainTextBox_DragEnter;
            // 
            // mainMenuStrip
            // 
            mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { fileToolStripMenuItem, attachmentsToolStripMenuItem });
            mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            mainMenuStrip.Name = "mainMenuStrip";
            mainMenuStrip.Padding = new System.Windows.Forms.Padding(5, 2, 0, 2);
            mainMenuStrip.Size = new System.Drawing.Size(511, 24);
            mainMenuStrip.TabIndex = 20;
            mainMenuStrip.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { draftToolStripMenuItem, cancelToolStripMenuItem, toolStripMenuItem1, sendToolStripMenuItem });
            fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            fileToolStripMenuItem.Size = new System.Drawing.Size(37, 20);
            fileToolStripMenuItem.Text = "&File";
            // 
            // draftToolStripMenuItem
            // 
            draftToolStripMenuItem.Name = "draftToolStripMenuItem";
            draftToolStripMenuItem.Size = new System.Drawing.Size(180, 22);
            draftToolStripMenuItem.Text = "&Drafts";
            draftToolStripMenuItem.Click += draftButton_Click;
            // 
            // cancelToolStripMenuItem
            // 
            cancelToolStripMenuItem.Name = "cancelToolStripMenuItem";
            cancelToolStripMenuItem.Size = new System.Drawing.Size(180, 22);
            cancelToolStripMenuItem.Text = "&Cancel";
            cancelToolStripMenuItem.Click += cancelButton_Click;
            // 
            // toolStripMenuItem1
            // 
            toolStripMenuItem1.Name = "toolStripMenuItem1";
            toolStripMenuItem1.Size = new System.Drawing.Size(177, 6);
            // 
            // sendToolStripMenuItem
            // 
            sendToolStripMenuItem.Name = "sendToolStripMenuItem";
            sendToolStripMenuItem.Size = new System.Drawing.Size(180, 22);
            sendToolStripMenuItem.Text = "&Send";
            sendToolStripMenuItem.Click += sendButton_Click;
            // 
            // attachmentsToolStripMenuItem
            // 
            attachmentsToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { addToolStripMenuItem });
            attachmentsToolStripMenuItem.Name = "attachmentsToolStripMenuItem";
            attachmentsToolStripMenuItem.Size = new System.Drawing.Size(87, 20);
            attachmentsToolStripMenuItem.Text = "&Attachments";
            // 
            // addToolStripMenuItem
            // 
            addToolStripMenuItem.Name = "addToolStripMenuItem";
            addToolStripMenuItem.Size = new System.Drawing.Size(105, 22);
            addToolStripMenuItem.Text = "&Add...";
            addToolStripMenuItem.Click += addToolStripMenuItem_Click;
            // 
            // attachmentsFlowLayoutPanel
            // 
            attachmentsFlowLayoutPanel.AllowDrop = true;
            attachmentsFlowLayoutPanel.AutoSize = true;
            attachmentsFlowLayoutPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            attachmentsFlowLayoutPanel.Location = new System.Drawing.Point(0, 512);
            attachmentsFlowLayoutPanel.Name = "attachmentsFlowLayoutPanel";
            attachmentsFlowLayoutPanel.Padding = new System.Windows.Forms.Padding(3);
            attachmentsFlowLayoutPanel.Size = new System.Drawing.Size(511, 6);
            attachmentsFlowLayoutPanel.TabIndex = 21;
            attachmentsFlowLayoutPanel.DragDrop += mainTextBox_DragDrop;
            attachmentsFlowLayoutPanel.DragEnter += mainTextBox_DragEnter;
            // 
            // addAttachementPpenFileDialog
            // 
            addAttachementPpenFileDialog.Filter = "All files|*.*";
            addAttachementPpenFileDialog.Title = "Add Attachement";
            // 
            // MailComposeForm
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(511, 518);
            Controls.Add(mainTextBox);
            Controls.Add(attachmentsFlowLayoutPanel);
            Controls.Add(panel2);
            Controls.Add(mainMenuStrip);
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            MinimumSize = new System.Drawing.Size(527, 376);
            Name = "MailComposeForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "New Mail";
            FormClosing += MailComposeForm_FormClosing;
            Load += MailComposeForm_Load;
            Shown += MailComposeForm_Shown;
            panel2.ResumeLayout(false);
            panel2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)mailPictureBox).EndInit();
            mainMenuStrip.ResumeLayout(false);
            mainMenuStrip.PerformLayout();
            ResumeLayout(false);
            PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Panel panel2;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.TextBox subjectTextBox;
        private System.Windows.Forms.TextBox mainTextBox;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.MenuStrip mainMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem draftToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem cancelToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem sendToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem attachmentsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem addToolStripMenuItem;
        private System.Windows.Forms.FlowLayoutPanel attachmentsFlowLayoutPanel;
        private System.Windows.Forms.TextBox ccTextBox;
        private System.Windows.Forms.TextBox toTextBox;
        private System.Windows.Forms.OpenFileDialog addAttachementPpenFileDialog;
        private System.Windows.Forms.Button sendButton;
        private System.Windows.Forms.PictureBox mailPictureBox;
    }
}