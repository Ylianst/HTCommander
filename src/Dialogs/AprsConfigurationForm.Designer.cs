namespace HTCommander
{
    partial class AprsConfigurationForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(AprsConfigurationForm));
            label4 = new System.Windows.Forms.Label();
            groupBox2 = new System.Windows.Forms.GroupBox();
            label5 = new System.Windows.Forms.Label();
            label1 = new System.Windows.Forms.Label();
            label3 = new System.Windows.Forms.Label();
            label2 = new System.Windows.Forms.Label();
            channelsComboBox = new System.Windows.Forms.ComboBox();
            freqTextBox = new System.Windows.Forms.TextBox();
            okButton = new System.Windows.Forms.Button();
            cancelButton = new System.Windows.Forms.Button();
            pictureBox2 = new System.Windows.Forms.PictureBox();
            linkLabel1 = new System.Windows.Forms.LinkLabel();
            groupBox2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).BeginInit();
            SuspendLayout();
            // 
            // label4
            // 
            label4.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label4.Location = new System.Drawing.Point(16, 14);
            label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label4.Name = "label4";
            label4.Size = new System.Drawing.Size(359, 114);
            label4.TabIndex = 16;
            label4.Text = "The APRS frequency changes depending on the region of the world. Use this site to find the right frequency to configure the APRS channel.";
            // 
            // groupBox2
            // 
            groupBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            groupBox2.Controls.Add(label5);
            groupBox2.Controls.Add(label1);
            groupBox2.Controls.Add(label3);
            groupBox2.Controls.Add(label2);
            groupBox2.Controls.Add(channelsComboBox);
            groupBox2.Controls.Add(freqTextBox);
            groupBox2.Location = new System.Drawing.Point(16, 132);
            groupBox2.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox2.Name = "groupBox2";
            groupBox2.Padding = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox2.Size = new System.Drawing.Size(459, 265);
            groupBox2.TabIndex = 15;
            groupBox2.TabStop = false;
            groupBox2.Text = "APRS Configuration";
            // 
            // label5
            // 
            label5.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label5.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            label5.Location = new System.Drawing.Point(160, 205);
            label5.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label5.Name = "label5";
            label5.Size = new System.Drawing.Size(283, 42);
            label5.TabIndex = 10;
            label5.Text = "The selected channel will be overwritten";
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new System.Drawing.Point(8, 168);
            label1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label1.Name = "label1";
            label1.Size = new System.Drawing.Size(62, 20);
            label1.TabIndex = 9;
            label1.Text = "Channel";
            // 
            // label3
            // 
            label3.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label3.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            label3.Location = new System.Drawing.Point(160, 82);
            label3.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label3.Name = "label3";
            label3.Size = new System.Drawing.Size(283, 42);
            label3.TabIndex = 8;
            label3.Text = "144.39 in North America\r\n144.80 in Europe";
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new System.Drawing.Point(8, 48);
            label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label2.Name = "label2";
            label2.Size = new System.Drawing.Size(76, 20);
            label2.TabIndex = 7;
            label2.Text = "Frequency";
            // 
            // channelsComboBox
            // 
            channelsComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            channelsComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            channelsComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            channelsComboBox.FormattingEnabled = true;
            channelsComboBox.Location = new System.Drawing.Point(164, 155);
            channelsComboBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            channelsComboBox.Name = "channelsComboBox";
            channelsComboBox.Size = new System.Drawing.Size(277, 33);
            channelsComboBox.TabIndex = 6;
            // 
            // freqTextBox
            // 
            freqTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            freqTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            freqTextBox.Location = new System.Drawing.Point(164, 29);
            freqTextBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            freqTextBox.MaxLength = 6;
            freqTextBox.Name = "freqTextBox";
            freqTextBox.Size = new System.Drawing.Size(277, 37);
            freqTextBox.TabIndex = 5;
            freqTextBox.Text = "144.39";
            freqTextBox.TextChanged += freqTextBox_TextChanged;
            freqTextBox.KeyPress += freqTextBox_KeyPress;
            // 
            // okButton
            // 
            okButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            okButton.Enabled = false;
            okButton.Location = new System.Drawing.Point(275, 406);
            okButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            okButton.Name = "okButton";
            okButton.Size = new System.Drawing.Size(100, 35);
            okButton.TabIndex = 19;
            okButton.Text = "OK";
            okButton.UseVisualStyleBackColor = true;
            okButton.Click += okButton_Click;
            // 
            // cancelButton
            // 
            cancelButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            cancelButton.Location = new System.Drawing.Point(375, 406);
            cancelButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            cancelButton.Name = "cancelButton";
            cancelButton.Size = new System.Drawing.Size(100, 35);
            cancelButton.TabIndex = 18;
            cancelButton.Text = "Cancel";
            cancelButton.UseVisualStyleBackColor = true;
            cancelButton.Click += cancelButton_Click;
            // 
            // pictureBox2
            // 
            pictureBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox2.Image = Properties.Resources.MapPoint2;
            pictureBox2.Location = new System.Drawing.Point(383, 14);
            pictureBox2.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            pictureBox2.Name = "pictureBox2";
            pictureBox2.Size = new System.Drawing.Size(92, 118);
            pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox2.TabIndex = 17;
            pictureBox2.TabStop = false;
            // 
            // linkLabel1
            // 
            linkLabel1.AutoSize = true;
            linkLabel1.Location = new System.Drawing.Point(16, 88);
            linkLabel1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            linkLabel1.Name = "linkLabel1";
            linkLabel1.Size = new System.Drawing.Size(63, 20);
            linkLabel1.TabIndex = 20;
            linkLabel1.TabStop = true;
            linkLabel1.Text = "aprs.org";
            linkLabel1.LinkClicked += linkLabel1_LinkClicked;
            // 
            // AprsConfigurationForm
            // 
            AcceptButton = okButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            CancelButton = cancelButton;
            ClientSize = new System.Drawing.Size(491, 460);
            Controls.Add(linkLabel1);
            Controls.Add(label4);
            Controls.Add(groupBox2);
            Controls.Add(okButton);
            Controls.Add(cancelButton);
            Controls.Add(pictureBox2);
            FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "AprsConfigurationForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "APRS";
            Load += AprsConfigurationForm_Load;
            groupBox2.ResumeLayout(false);
            groupBox2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).EndInit();
            ResumeLayout(false);
            PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.GroupBox groupBox2;
        private System.Windows.Forms.Button okButton;
        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.LinkLabel linkLabel1;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.ComboBox channelsComboBox;
        private System.Windows.Forms.TextBox freqTextBox;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.Label label5;
    }
}