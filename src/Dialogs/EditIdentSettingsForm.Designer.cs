namespace HTCommander
{
    partial class EditIdentSettingsForm
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
            okButton = new System.Windows.Forms.Button();
            cancelButton = new System.Windows.Forms.Button();
            groupBox1 = new System.Windows.Forms.GroupBox();
            sendIdInfoCheckBox = new System.Windows.Forms.CheckBox();
            label6 = new System.Windows.Forms.Label();
            radioComboBox = new System.Windows.Forms.ComboBox();
            label7 = new System.Windows.Forms.Label();
            sendLocationCheckBox = new System.Windows.Forms.CheckBox();
            label1 = new System.Windows.Forms.Label();
            idInfoTextBox = new System.Windows.Forms.TextBox();
            pictureBox2 = new System.Windows.Forms.PictureBox();
            label4 = new System.Windows.Forms.Label();
            groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).BeginInit();
            SuspendLayout();
            // 
            // okButton
            // 
            okButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            okButton.Location = new System.Drawing.Point(269, 293);
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
            cancelButton.Location = new System.Drawing.Point(377, 293);
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
            groupBox1.Controls.Add(sendIdInfoCheckBox);
            groupBox1.Controls.Add(label6);
            groupBox1.Controls.Add(radioComboBox);
            groupBox1.Controls.Add(label7);
            groupBox1.Controls.Add(sendLocationCheckBox);
            groupBox1.Controls.Add(label1);
            groupBox1.Controls.Add(idInfoTextBox);
            groupBox1.Location = new System.Drawing.Point(12, 99);
            groupBox1.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            groupBox1.Name = "groupBox1";
            groupBox1.Padding = new System.Windows.Forms.Padding(3, 4, 3, 4);
            groupBox1.Size = new System.Drawing.Size(466, 186);
            groupBox1.TabIndex = 19;
            groupBox1.TabStop = false;
            groupBox1.Text = "Ident Settings";
            // 
            // sendIdInfoCheckBox
            // 
            sendIdInfoCheckBox.AutoSize = true;
            sendIdInfoCheckBox.Location = new System.Drawing.Point(178, 123);
            sendIdInfoCheckBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            sendIdInfoCheckBox.Name = "sendIdInfoCheckBox";
            sendIdInfoCheckBox.Size = new System.Drawing.Size(120, 24);
            sendIdInfoCheckBox.TabIndex = 22;
            sendIdInfoCheckBox.Text = "Send Callsign";
            sendIdInfoCheckBox.UseVisualStyleBackColor = true;
            // 
            // label6
            // 
            label6.AutoSize = true;
            label6.Location = new System.Drawing.Point(7, 34);
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
            label7.Location = new System.Drawing.Point(173, 97);
            label7.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label7.Name = "label7";
            label7.Size = new System.Drawing.Size(277, 30);
            label7.TabIndex = 19;
            label7.Text = "Enter Callsign - Station ID";
            // 
            // sendLocationCheckBox
            // 
            sendLocationCheckBox.AutoSize = true;
            sendLocationCheckBox.Location = new System.Drawing.Point(178, 153);
            sendLocationCheckBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            sendLocationCheckBox.Name = "sendLocationCheckBox";
            sendLocationCheckBox.Size = new System.Drawing.Size(120, 24);
            sendLocationCheckBox.TabIndex = 16;
            sendLocationCheckBox.Text = "Send Position";
            sendLocationCheckBox.UseVisualStyleBackColor = true;
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new System.Drawing.Point(7, 69);
            label1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label1.Name = "label1";
            label1.Size = new System.Drawing.Size(61, 20);
            label1.TabIndex = 11;
            label1.Text = "Callsign";
            // 
            // idInfoTextBox
            // 
            idInfoTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            idInfoTextBox.Location = new System.Drawing.Point(176, 65);
            idInfoTextBox.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            idInfoTextBox.MaxLength = 12;
            idInfoTextBox.Name = "idInfoTextBox";
            idInfoTextBox.Size = new System.Drawing.Size(274, 27);
            idInfoTextBox.TabIndex = 10;
            idInfoTextBox.TextChanged += aprsCallsignTextBox_TextChanged;
            idInfoTextBox.KeyPress += aprsCallsignTextBox_KeyPress;
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
            label4.Text = "If enabled, sends your callsign and/or location information each time you release the PTT on the channel you are transmitting on.";
            // 
            // EditIdentSettingsForm
            // 
            AcceptButton = okButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            CancelButton = cancelButton;
            ClientSize = new System.Drawing.Size(490, 345);
            Controls.Add(pictureBox2);
            Controls.Add(label4);
            Controls.Add(groupBox1);
            Controls.Add(okButton);
            Controls.Add(cancelButton);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "EditIdentSettingsForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "PTT Release Settings";
            Load += EditIdentSettingsForm_Load;
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
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.TextBox idInfoTextBox;
        private System.Windows.Forms.CheckBox sendLocationCheckBox;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.ComboBox radioComboBox;
        private System.Windows.Forms.CheckBox sendIdInfoCheckBox;
    }
}
