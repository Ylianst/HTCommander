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
            this.panel2 = new System.Windows.Forms.Panel();
            this.mailPictureBox = new System.Windows.Forms.PictureBox();
            this.toComboBox = new System.Windows.Forms.ComboBox();
            this.label2 = new System.Windows.Forms.Label();
            this.label1 = new System.Windows.Forms.Label();
            this.subjectTextBox = new System.Windows.Forms.TextBox();
            this.mainTextBox = new System.Windows.Forms.TextBox();
            this.panel1 = new System.Windows.Forms.Panel();
            this.draftButton = new System.Windows.Forms.Button();
            this.sendButton = new System.Windows.Forms.Button();
            this.cancelButton = new System.Windows.Forms.Button();
            this.panel2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailPictureBox)).BeginInit();
            this.panel1.SuspendLayout();
            this.SuspendLayout();
            // 
            // panel2
            // 
            this.panel2.BackColor = System.Drawing.Color.Silver;
            this.panel2.Controls.Add(this.mailPictureBox);
            this.panel2.Controls.Add(this.toComboBox);
            this.panel2.Controls.Add(this.label2);
            this.panel2.Controls.Add(this.label1);
            this.panel2.Controls.Add(this.subjectTextBox);
            this.panel2.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel2.Location = new System.Drawing.Point(0, 0);
            this.panel2.Margin = new System.Windows.Forms.Padding(4);
            this.panel2.Name = "panel2";
            this.panel2.Size = new System.Drawing.Size(536, 67);
            this.panel2.TabIndex = 3;
            // 
            // mailPictureBox
            // 
            this.mailPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.mailPictureBox.Image = global::HTCommander.Properties.Resources.Mail;
            this.mailPictureBox.Location = new System.Drawing.Point(472, 3);
            this.mailPictureBox.Name = "mailPictureBox";
            this.mailPictureBox.Size = new System.Drawing.Size(60, 60);
            this.mailPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.mailPictureBox.TabIndex = 8;
            this.mailPictureBox.TabStop = false;
            // 
            // toComboBox
            // 
            this.toComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.toComboBox.FormattingEnabled = true;
            this.toComboBox.Location = new System.Drawing.Point(95, 9);
            this.toComboBox.MaxLength = 80;
            this.toComboBox.Name = "toComboBox";
            this.toComboBox.Size = new System.Drawing.Size(370, 24);
            this.toComboBox.TabIndex = 10;
            this.toComboBox.TextChanged += new System.EventHandler(this.toComboBox_TextChanged);
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(12, 40);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(52, 16);
            this.label2.TabIndex = 9;
            this.label2.Text = "Subject";
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(12, 12);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(24, 16);
            this.label1.TabIndex = 7;
            this.label1.Text = "To";
            // 
            // subjectTextBox
            // 
            this.subjectTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.subjectTextBox.Location = new System.Drawing.Point(95, 37);
            this.subjectTextBox.Name = "subjectTextBox";
            this.subjectTextBox.Size = new System.Drawing.Size(370, 22);
            this.subjectTextBox.TabIndex = 11;
            this.subjectTextBox.TextChanged += new System.EventHandler(this.subjectTextBox_TextChanged);
            // 
            // mainTextBox
            // 
            this.mainTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mainTextBox.Location = new System.Drawing.Point(0, 67);
            this.mainTextBox.Multiline = true;
            this.mainTextBox.Name = "mainTextBox";
            this.mainTextBox.Size = new System.Drawing.Size(536, 367);
            this.mainTextBox.TabIndex = 12;
            this.mainTextBox.TextChanged += new System.EventHandler(this.mainTextBox_TextChanged);
            // 
            // panel1
            // 
            this.panel1.BackColor = System.Drawing.Color.Silver;
            this.panel1.Controls.Add(this.draftButton);
            this.panel1.Controls.Add(this.sendButton);
            this.panel1.Controls.Add(this.cancelButton);
            this.panel1.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.panel1.Location = new System.Drawing.Point(0, 397);
            this.panel1.Margin = new System.Windows.Forms.Padding(4);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(536, 37);
            this.panel1.TabIndex = 7;
            // 
            // draftButton
            // 
            this.draftButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.draftButton.Enabled = false;
            this.draftButton.Location = new System.Drawing.Point(207, 5);
            this.draftButton.Margin = new System.Windows.Forms.Padding(4);
            this.draftButton.Name = "draftButton";
            this.draftButton.Size = new System.Drawing.Size(100, 28);
            this.draftButton.TabIndex = 20;
            this.draftButton.Text = "&Draft";
            this.draftButton.UseVisualStyleBackColor = true;
            this.draftButton.Click += new System.EventHandler(this.draftButton_Click);
            // 
            // sendButton
            // 
            this.sendButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.sendButton.Enabled = false;
            this.sendButton.Location = new System.Drawing.Point(315, 5);
            this.sendButton.Margin = new System.Windows.Forms.Padding(4);
            this.sendButton.Name = "sendButton";
            this.sendButton.Size = new System.Drawing.Size(100, 28);
            this.sendButton.TabIndex = 21;
            this.sendButton.Text = "&Send";
            this.sendButton.UseVisualStyleBackColor = true;
            this.sendButton.Click += new System.EventHandler(this.okButton_Click);
            // 
            // cancelButton
            // 
            this.cancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelButton.Location = new System.Drawing.Point(423, 5);
            this.cancelButton.Margin = new System.Windows.Forms.Padding(4);
            this.cancelButton.Name = "cancelButton";
            this.cancelButton.Size = new System.Drawing.Size(100, 28);
            this.cancelButton.TabIndex = 22;
            this.cancelButton.Text = "&Cancel";
            this.cancelButton.UseVisualStyleBackColor = true;
            this.cancelButton.Click += new System.EventHandler(this.cancelButton_Click);
            // 
            // MailComposeForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(536, 434);
            this.Controls.Add(this.panel1);
            this.Controls.Add(this.mainTextBox);
            this.Controls.Add(this.panel2);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Name = "MailComposeForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "New Mail";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.MailComposeForm_FormClosing);
            this.Load += new System.EventHandler(this.MailComposeForm_Load);
            this.Shown += new System.EventHandler(this.MailComposeForm_Shown);
            this.panel2.ResumeLayout(false);
            this.panel2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailPictureBox)).EndInit();
            this.panel1.ResumeLayout(false);
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Panel panel2;
        private System.Windows.Forms.ComboBox toComboBox;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.TextBox subjectTextBox;
        private System.Windows.Forms.TextBox mainTextBox;
        private System.Windows.Forms.Panel panel1;
        private System.Windows.Forms.Button sendButton;
        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.PictureBox mailPictureBox;
        private System.Windows.Forms.Button draftButton;
    }
}