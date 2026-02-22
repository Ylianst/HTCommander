namespace HTCommander
{
    partial class EditBeaconSettingsForm
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
                components?.Dispose();
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(EditBeaconSettingsForm));
            okButton = new System.Windows.Forms.Button();
            cancelButton = new System.Windows.Forms.Button();
            groupBox1 = new System.Windows.Forms.GroupBox();
            label8 = new System.Windows.Forms.Label();
            channelComboBox = new System.Windows.Forms.ComboBox();
            label6 = new System.Windows.Forms.Label();
            radioComboBox = new System.Windows.Forms.ComboBox();
            label7 = new System.Windows.Forms.Label();
            shareLocationCheckBox = new System.Windows.Forms.CheckBox();
            sendVoltageCheckBox = new System.Windows.Forms.CheckBox();
            allowPositionCheckBox = new System.Windows.Forms.CheckBox();
            label3 = new System.Windows.Forms.Label();
            aprsMessageTextBox = new System.Windows.Forms.TextBox();
            label2 = new System.Windows.Forms.Label();
            intervalComboBox = new System.Windows.Forms.ComboBox();
            label1 = new System.Windows.Forms.Label();
            aprsCallsignTextBox = new System.Windows.Forms.TextBox();
            label5 = new System.Windows.Forms.Label();
            packetFormatComboBox = new System.Windows.Forms.ComboBox();
            pictureBox2 = new System.Windows.Forms.PictureBox();
            label4 = new System.Windows.Forms.Label();
            groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).BeginInit();
            SuspendLayout();
            // 
            // okButton
            // 
            okButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            okButton.Location = new System.Drawing.Point(269, 496);
            okButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            okButton.Name = "okButton";
            okButton.Size = new System.Drawing.Size(100, 35);
            okButton.TabIndex = 18;
            okButton.Text = "OK";
            okButton.UseVisualStyleBackColor = true;
            okButton.Click += okButton_Click;
            // 
            // cancelButton
            // 
            cancelButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            cancelButton.Location = new System.Drawing.Point(377, 496);
            cancelButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            cancelButton.Name = "cancelButton";
            cancelButton.Size = new System.Drawing.Size(100, 35);
            cancelButton.TabIndex = 17;
            cancelButton.Text = "Cancel";
            cancelButton.UseVisualStyleBackColor = true;
            // 
            // groupBox1
            // 
            groupBox1.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            groupBox1.Controls.Add(label8);
            groupBox1.Controls.Add(channelComboBox);
            groupBox1.Controls.Add(label6);
            groupBox1.Controls.Add(radioComboBox);
            groupBox1.Controls.Add(label7);
            groupBox1.Controls.Add(shareLocationCheckBox);
            groupBox1.Controls.Add(sendVoltageCheckBox);
            groupBox1.Controls.Add(allowPositionCheckBox);
            groupBox1.Controls.Add(label3);
            groupBox1.Controls.Add(aprsMessageTextBox);
            groupBox1.Controls.Add(label2);
            groupBox1.Controls.Add(intervalComboBox);
            groupBox1.Controls.Add(label1);
            groupBox1.Controls.Add(aprsCallsignTextBox);
            groupBox1.Controls.Add(label5);
            groupBox1.Controls.Add(packetFormatComboBox);
            groupBox1.Location = new System.Drawing.Point(12, 99);
            groupBox1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            groupBox1.Name = "groupBox1";
            groupBox1.Padding = new System.Windows.Forms.Padding(3, 4, 3, 4);
            groupBox1.Size = new System.Drawing.Size(466, 389);
            groupBox1.TabIndex = 19;
            groupBox1.TabStop = false;
            groupBox1.Text = "Beacon Settings";
            // 
            // label8
            // 
            label8.AutoSize = true;
            label8.Location = new System.Drawing.Point(8, 72);
            label8.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label8.Name = "label8";
            label8.Size = new System.Drawing.Size(62, 20);
            label8.TabIndex = 23;
            label8.Text = "Channel";
            // 
            // channelComboBox
            // 
            channelComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            channelComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            channelComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            channelComboBox.FormattingEnabled = true;
            channelComboBox.Items.AddRange(new object[] { "BSS", "APRS" });
            channelComboBox.Location = new System.Drawing.Point(177, 70);
            channelComboBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            channelComboBox.Name = "channelComboBox";
            channelComboBox.Size = new System.Drawing.Size(275, 25);
            channelComboBox.TabIndex = 22;
            // 
            // label6
            // 
            label6.AutoSize = true;
            label6.Location = new System.Drawing.Point(8, 32);
            label6.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label6.Name = "label6";
            label6.Size = new System.Drawing.Size(48, 20);
            label6.TabIndex = 21;
            label6.Text = "Radio";
            // 
            // radioComboBox
            // 
            radioComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            radioComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            radioComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            radioComboBox.FormattingEnabled = true;
            radioComboBox.Items.AddRange(new object[] { "BSS", "APRS" });
            radioComboBox.Location = new System.Drawing.Point(177, 29);
            radioComboBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            radioComboBox.Name = "radioComboBox";
            radioComboBox.Size = new System.Drawing.Size(274, 25);
            radioComboBox.TabIndex = 20;
            radioComboBox.SelectedIndexChanged += radioComboBox_SelectedIndexChanged;
            // 
            // label7
            // 
            label7.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label7.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            label7.Location = new System.Drawing.Point(174, 223);
            label7.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label7.Name = "label7";
            label7.Size = new System.Drawing.Size(277, 30);
            label7.TabIndex = 19;
            label7.Text = "Enter Callsign - Station ID";
            // 
            // shareLocationCheckBox
            // 
            shareLocationCheckBox.AutoSize = true;
            shareLocationCheckBox.Location = new System.Drawing.Point(176, 293);
            shareLocationCheckBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            shareLocationCheckBox.Name = "shareLocationCheckBox";
            shareLocationCheckBox.Size = new System.Drawing.Size(179, 24);
            shareLocationCheckBox.TabIndex = 18;
            shareLocationCheckBox.Text = "Should Share Location";
            shareLocationCheckBox.UseVisualStyleBackColor = true;
            // 
            // sendVoltageCheckBox
            // 
            sendVoltageCheckBox.AutoSize = true;
            sendVoltageCheckBox.Location = new System.Drawing.Point(176, 323);
            sendVoltageCheckBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            sendVoltageCheckBox.Name = "sendVoltageCheckBox";
            sendVoltageCheckBox.Size = new System.Drawing.Size(119, 24);
            sendVoltageCheckBox.TabIndex = 17;
            sendVoltageCheckBox.Text = "Send Voltage";
            sendVoltageCheckBox.UseVisualStyleBackColor = true;
            // 
            // allowPositionCheckBox
            // 
            allowPositionCheckBox.AutoSize = true;
            allowPositionCheckBox.Location = new System.Drawing.Point(176, 354);
            allowPositionCheckBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            allowPositionCheckBox.Name = "allowPositionCheckBox";
            allowPositionCheckBox.Size = new System.Drawing.Size(168, 24);
            allowPositionCheckBox.TabIndex = 16;
            allowPositionCheckBox.Text = "Allow Position Check";
            allowPositionCheckBox.UseVisualStyleBackColor = true;
            // 
            // label3
            // 
            label3.AutoSize = true;
            label3.Location = new System.Drawing.Point(8, 260);
            label3.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label3.Name = "label3";
            label3.Size = new System.Drawing.Size(106, 20);
            label3.TabIndex = 15;
            label3.Text = "APRS Message";
            // 
            // aprsMessageTextBox
            // 
            aprsMessageTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            aprsMessageTextBox.Location = new System.Drawing.Point(177, 256);
            aprsMessageTextBox.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            aprsMessageTextBox.MaxLength = 18;
            aprsMessageTextBox.Name = "aprsMessageTextBox";
            aprsMessageTextBox.Size = new System.Drawing.Size(274, 27);
            aprsMessageTextBox.TabIndex = 14;
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new System.Drawing.Point(8, 154);
            label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label2.Name = "label2";
            label2.Size = new System.Drawing.Size(111, 20);
            label2.TabIndex = 13;
            label2.Text = "Beacon Interval";
            // 
            // intervalComboBox
            // 
            intervalComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            intervalComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            intervalComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            intervalComboBox.FormattingEnabled = true;
            intervalComboBox.Items.AddRange(new object[] { "Off", "Every 10 seconds", "Every 20 seconds", "Every 30 seconds", "Every 40 seconds", "Every 50 seconds", "Every 1 minute", "Every 2 minutes", "Every 3 minutes", "Every 4 minutes", "Every 5 minutes", "Every 6 minutes", "Every 7 minutes", "Every 8 minutes", "Every 9 minutes", "Every 10 minutes", "Every 15 minutes", "Every 20 minutes", "Every 25 minutes", "Every 30 minutes" });
            intervalComboBox.Location = new System.Drawing.Point(176, 151);
            intervalComboBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            intervalComboBox.Name = "intervalComboBox";
            intervalComboBox.Size = new System.Drawing.Size(275, 25);
            intervalComboBox.TabIndex = 12;
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new System.Drawing.Point(8, 195);
            label1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label1.Name = "label1";
            label1.Size = new System.Drawing.Size(100, 20);
            label1.TabIndex = 11;
            label1.Text = "APRS Callsign";
            // 
            // aprsCallsignTextBox
            // 
            aprsCallsignTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            aprsCallsignTextBox.Location = new System.Drawing.Point(177, 191);
            aprsCallsignTextBox.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            aprsCallsignTextBox.MaxLength = 9;
            aprsCallsignTextBox.Name = "aprsCallsignTextBox";
            aprsCallsignTextBox.Size = new System.Drawing.Size(274, 27);
            aprsCallsignTextBox.TabIndex = 10;
            aprsCallsignTextBox.TextChanged += aprsCallsignTextBox_TextChanged;
            aprsCallsignTextBox.KeyPress += aprsCallsignTextBox_KeyPress;
            // 
            // label5
            // 
            label5.AutoSize = true;
            label5.Location = new System.Drawing.Point(8, 113);
            label5.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label5.Name = "label5";
            label5.Size = new System.Drawing.Size(102, 20);
            label5.TabIndex = 9;
            label5.Text = "Packet Format";
            // 
            // packetFormatComboBox
            // 
            packetFormatComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            packetFormatComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            packetFormatComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            packetFormatComboBox.FormattingEnabled = true;
            packetFormatComboBox.Items.AddRange(new object[] { "BSS", "APRS" });
            packetFormatComboBox.Location = new System.Drawing.Point(176, 110);
            packetFormatComboBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            packetFormatComboBox.Name = "packetFormatComboBox";
            packetFormatComboBox.Size = new System.Drawing.Size(275, 25);
            packetFormatComboBox.TabIndex = 8;
            packetFormatComboBox.SelectedIndexChanged += packetFormatComboBox_SelectedIndexChanged;
            // 
            // pictureBox2
            // 
            pictureBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox2.Image = Properties.Resources.MapPoint1;
            pictureBox2.Location = new System.Drawing.Point(414, 11);
            pictureBox2.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            pictureBox2.Name = "pictureBox2";
            pictureBox2.Size = new System.Drawing.Size(64, 79);
            pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox2.TabIndex = 21;
            pictureBox2.TabStop = false;
            // 
            // label4
            // 
            label4.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label4.Location = new System.Drawing.Point(9, 11);
            label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label4.Name = "label4";
            label4.Size = new System.Drawing.Size(397, 79);
            label4.TabIndex = 20;
            label4.Text = "Change how the radio will beacon information about itself including position, voltage and a custom message. Other stations around will be able to see this information.";
            // 
            // EditBeaconSettingsForm
            // 
            AcceptButton = okButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            CancelButton = cancelButton;
            ClientSize = new System.Drawing.Size(490, 548);
            Controls.Add(pictureBox2);
            Controls.Add(label4);
            Controls.Add(groupBox1);
            Controls.Add(okButton);
            Controls.Add(cancelButton);
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "EditBeaconSettingsForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "Beacon Settings";
            Load += EditBeaconSettingsForm_Load;
            groupBox1.ResumeLayout(false);
            groupBox1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).EndInit();
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Button okButton;
        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.GroupBox groupBox1;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.ComboBox packetFormatComboBox;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.TextBox aprsCallsignTextBox;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.TextBox aprsMessageTextBox;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.ComboBox intervalComboBox;
        private System.Windows.Forms.CheckBox shareLocationCheckBox;
        private System.Windows.Forms.CheckBox sendVoltageCheckBox;
        private System.Windows.Forms.CheckBox allowPositionCheckBox;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.ComboBox radioComboBox;
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.ComboBox channelComboBox;
    }
}
