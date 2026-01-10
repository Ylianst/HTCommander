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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(EditBeaconSettingsForm));
            this.okButton = new System.Windows.Forms.Button();
            this.cancelButton = new System.Windows.Forms.Button();
            this.groupBox1 = new System.Windows.Forms.GroupBox();
            this.pictureBox2 = new System.Windows.Forms.PictureBox();
            this.label4 = new System.Windows.Forms.Label();
            this.label5 = new System.Windows.Forms.Label();
            this.packetFormatComboBox = new System.Windows.Forms.ComboBox();
            this.aprsCallsignTextBox = new System.Windows.Forms.TextBox();
            this.label1 = new System.Windows.Forms.Label();
            this.label2 = new System.Windows.Forms.Label();
            this.intervalComboBox = new System.Windows.Forms.ComboBox();
            this.label3 = new System.Windows.Forms.Label();
            this.aprsMessageTextBox = new System.Windows.Forms.TextBox();
            this.allowPositionCheckBox = new System.Windows.Forms.CheckBox();
            this.sendVoltageCheckBox = new System.Windows.Forms.CheckBox();
            this.shareLocationCheckBox = new System.Windows.Forms.CheckBox();
            this.label7 = new System.Windows.Forms.Label();
            this.groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).BeginInit();
            this.SuspendLayout();
            // 
            // okButton
            // 
            this.okButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.okButton.Location = new System.Drawing.Point(231, 354);
            this.okButton.Margin = new System.Windows.Forms.Padding(4);
            this.okButton.Name = "okButton";
            this.okButton.Size = new System.Drawing.Size(100, 28);
            this.okButton.TabIndex = 18;
            this.okButton.Text = "OK";
            this.okButton.UseVisualStyleBackColor = true;
            this.okButton.Click += new System.EventHandler(this.okButton_Click);
            // 
            // cancelButton
            // 
            this.cancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.cancelButton.Location = new System.Drawing.Point(339, 354);
            this.cancelButton.Margin = new System.Windows.Forms.Padding(4);
            this.cancelButton.Name = "cancelButton";
            this.cancelButton.Size = new System.Drawing.Size(100, 28);
            this.cancelButton.TabIndex = 17;
            this.cancelButton.Text = "Cancel";
            this.cancelButton.UseVisualStyleBackColor = true;
            // 
            // groupBox1
            // 
            this.groupBox1.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.groupBox1.Controls.Add(this.label7);
            this.groupBox1.Controls.Add(this.shareLocationCheckBox);
            this.groupBox1.Controls.Add(this.sendVoltageCheckBox);
            this.groupBox1.Controls.Add(this.allowPositionCheckBox);
            this.groupBox1.Controls.Add(this.label3);
            this.groupBox1.Controls.Add(this.aprsMessageTextBox);
            this.groupBox1.Controls.Add(this.label2);
            this.groupBox1.Controls.Add(this.intervalComboBox);
            this.groupBox1.Controls.Add(this.label1);
            this.groupBox1.Controls.Add(this.aprsCallsignTextBox);
            this.groupBox1.Controls.Add(this.label5);
            this.groupBox1.Controls.Add(this.packetFormatComboBox);
            this.groupBox1.Location = new System.Drawing.Point(12, 79);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Size = new System.Drawing.Size(428, 268);
            this.groupBox1.TabIndex = 19;
            this.groupBox1.TabStop = false;
            this.groupBox1.Text = "Beacon Settings";
            // 
            // pictureBox2
            // 
            this.pictureBox2.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox2.Image = global::HTCommander.Properties.Resources.MapPoint1;
            this.pictureBox2.Location = new System.Drawing.Point(376, 9);
            this.pictureBox2.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox2.Name = "pictureBox2";
            this.pictureBox2.Size = new System.Drawing.Size(64, 63);
            this.pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox2.TabIndex = 21;
            this.pictureBox2.TabStop = false;
            // 
            // label4
            // 
            this.label4.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label4.Location = new System.Drawing.Point(9, 9);
            this.label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(359, 63);
            this.label4.TabIndex = 20;
            this.label4.Text = "Change how the radio will beacon information about itself including position, vol" +
    "tage and a custom message. Other stations around will be able to see this inform" +
    "ation.";
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(7, 32);
            this.label5.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(94, 16);
            this.label5.TabIndex = 9;
            this.label5.Text = "Packet Format";
            // 
            // packetFormatComboBox
            // 
            this.packetFormatComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.packetFormatComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.packetFormatComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.packetFormatComboBox.FormattingEnabled = true;
            this.packetFormatComboBox.Items.AddRange(new object[] {
            "BSS",
            "APRS"});
            this.packetFormatComboBox.Location = new System.Drawing.Point(176, 28);
            this.packetFormatComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.packetFormatComboBox.Name = "packetFormatComboBox";
            this.packetFormatComboBox.Size = new System.Drawing.Size(237, 25);
            this.packetFormatComboBox.TabIndex = 8;
            this.packetFormatComboBox.SelectedIndexChanged += new System.EventHandler(this.packetFormatComboBox_SelectedIndexChanged);
            // 
            // aprsCallsignTextBox
            // 
            this.aprsCallsignTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsCallsignTextBox.Location = new System.Drawing.Point(177, 93);
            this.aprsCallsignTextBox.MaxLength = 9;
            this.aprsCallsignTextBox.Name = "aprsCallsignTextBox";
            this.aprsCallsignTextBox.Size = new System.Drawing.Size(236, 22);
            this.aprsCallsignTextBox.TabIndex = 10;
            this.aprsCallsignTextBox.TextChanged += new System.EventHandler(this.aprsCallsignTextBox_TextChanged);
            this.aprsCallsignTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.aprsCallsignTextBox_KeyPress);
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(8, 96);
            this.label1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(95, 16);
            this.label1.TabIndex = 11;
            this.label1.Text = "APRS Callsign";
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(7, 65);
            this.label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(100, 16);
            this.label2.TabIndex = 13;
            this.label2.Text = "Beacon Interval";
            // 
            // intervalComboBox
            // 
            this.intervalComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.intervalComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.intervalComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.intervalComboBox.FormattingEnabled = true;
            this.intervalComboBox.Items.AddRange(new object[] {
            "Off",
            "Every 10 seconds",
            "Every 20 seconds",
            "Every 30 seconds",
            "Every 40 seconds",
            "Every 50 seconds",
            "Every 1 minute",
            "Every 2 minutes",
            "Every 3 minutes",
            "Every 4 minutes",
            "Every 5 minutes",
            "Every 6 minutes",
            "Every 7 minutes",
            "Every 8 minutes",
            "Every 9 minutes",
            "Every 10 minutes",
            "Every 15 minutes",
            "Every 20 minutes",
            "Every 25 minutes",
            "Every 30 minutes"});
            this.intervalComboBox.Location = new System.Drawing.Point(176, 61);
            this.intervalComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.intervalComboBox.Name = "intervalComboBox";
            this.intervalComboBox.Size = new System.Drawing.Size(237, 25);
            this.intervalComboBox.TabIndex = 12;
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(8, 148);
            this.label3.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(104, 16);
            this.label3.TabIndex = 15;
            this.label3.Text = "APRS Message";
            // 
            // aprsMessageTextBox
            // 
            this.aprsMessageTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsMessageTextBox.Location = new System.Drawing.Point(177, 145);
            this.aprsMessageTextBox.MaxLength = 18;
            this.aprsMessageTextBox.Name = "aprsMessageTextBox";
            this.aprsMessageTextBox.Size = new System.Drawing.Size(236, 22);
            this.aprsMessageTextBox.TabIndex = 14;
            // 
            // allowPositionCheckBox
            // 
            this.allowPositionCheckBox.AutoSize = true;
            this.allowPositionCheckBox.Location = new System.Drawing.Point(176, 230);
            this.allowPositionCheckBox.Margin = new System.Windows.Forms.Padding(4);
            this.allowPositionCheckBox.Name = "allowPositionCheckBox";
            this.allowPositionCheckBox.Size = new System.Drawing.Size(153, 20);
            this.allowPositionCheckBox.TabIndex = 16;
            this.allowPositionCheckBox.Text = "Allow Position Check";
            this.allowPositionCheckBox.UseVisualStyleBackColor = true;
            // 
            // sendVoltageCheckBox
            // 
            this.sendVoltageCheckBox.AutoSize = true;
            this.sendVoltageCheckBox.Location = new System.Drawing.Point(176, 202);
            this.sendVoltageCheckBox.Margin = new System.Windows.Forms.Padding(4);
            this.sendVoltageCheckBox.Name = "sendVoltageCheckBox";
            this.sendVoltageCheckBox.Size = new System.Drawing.Size(111, 20);
            this.sendVoltageCheckBox.TabIndex = 17;
            this.sendVoltageCheckBox.Text = "Send Voltage";
            this.sendVoltageCheckBox.UseVisualStyleBackColor = true;
            // 
            // shareLocationCheckBox
            // 
            this.shareLocationCheckBox.AutoSize = true;
            this.shareLocationCheckBox.Location = new System.Drawing.Point(176, 174);
            this.shareLocationCheckBox.Margin = new System.Windows.Forms.Padding(4);
            this.shareLocationCheckBox.Name = "shareLocationCheckBox";
            this.shareLocationCheckBox.Size = new System.Drawing.Size(164, 20);
            this.shareLocationCheckBox.TabIndex = 18;
            this.shareLocationCheckBox.Text = "Should Share Location";
            this.shareLocationCheckBox.UseVisualStyleBackColor = true;
            // 
            // label7
            // 
            this.label7.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label7.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.label7.Location = new System.Drawing.Point(174, 118);
            this.label7.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(239, 24);
            this.label7.TabIndex = 19;
            this.label7.Text = "Enter Callsign - Station ID";
            // 
            // EditBeaconSettingsForm
            // 
            this.AcceptButton = this.okButton;
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.cancelButton;
            this.ClientSize = new System.Drawing.Size(452, 395);
            this.Controls.Add(this.pictureBox2);
            this.Controls.Add(this.label4);
            this.Controls.Add(this.groupBox1);
            this.Controls.Add(this.okButton);
            this.Controls.Add(this.cancelButton);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "EditBeaconSettingsForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Beacon Settings";
            this.Load += new System.EventHandler(this.EditBeaconSettingsForm_Load);
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).EndInit();
            this.ResumeLayout(false);

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
    }
}