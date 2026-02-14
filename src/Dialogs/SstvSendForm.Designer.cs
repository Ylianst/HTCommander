namespace HTCommander
{
    partial class SstvSendForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(SstvSendForm));
            this.modeLabel = new System.Windows.Forms.Label();
            this.modeComboBox = new System.Windows.Forms.ComboBox();
            this.resolutionLabel = new System.Windows.Forms.Label();
            this.previewGroupBox = new System.Windows.Forms.GroupBox();
            this.previewPictureBox = new System.Windows.Forms.PictureBox();
            this.okButton = new System.Windows.Forms.Button();
            this.cancelButton = new System.Windows.Forms.Button();
            this.topDescriptionLabel = new System.Windows.Forms.Label();
            this.previewGroupBox.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.previewPictureBox)).BeginInit();
            this.SuspendLayout();
            // 
            // modeLabel
            // 
            this.modeLabel.AutoSize = true;
            this.modeLabel.Location = new System.Drawing.Point(15, 50);
            this.modeLabel.Name = "modeLabel";
            this.modeLabel.Size = new System.Drawing.Size(39, 13);
            this.modeLabel.TabIndex = 0;
            this.modeLabel.Text = "Mode:";
            // 
            // modeComboBox
            // 
            this.modeComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.modeComboBox.FormattingEnabled = true;
            this.modeComboBox.Location = new System.Drawing.Point(60, 47);
            this.modeComboBox.Name = "modeComboBox";
            this.modeComboBox.Size = new System.Drawing.Size(240, 21);
            this.modeComboBox.TabIndex = 1;
            this.modeComboBox.SelectedIndexChanged += new System.EventHandler(this.modeComboBox_SelectedIndexChanged);
            // 
            // resolutionLabel
            // 
            this.resolutionLabel.AutoSize = true;
            this.resolutionLabel.ForeColor = System.Drawing.Color.Gray;
            this.resolutionLabel.Location = new System.Drawing.Point(306, 50);
            this.resolutionLabel.Name = "resolutionLabel";
            this.resolutionLabel.Size = new System.Drawing.Size(0, 13);
            this.resolutionLabel.TabIndex = 2;
            // 
            // previewGroupBox
            // 
            this.previewGroupBox.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.previewGroupBox.Controls.Add(this.previewPictureBox);
            this.previewGroupBox.Location = new System.Drawing.Point(15, 80);
            this.previewGroupBox.Name = "previewGroupBox";
            this.previewGroupBox.Size = new System.Drawing.Size(420, 310);
            this.previewGroupBox.TabIndex = 3;
            this.previewGroupBox.TabStop = false;
            this.previewGroupBox.Text = "Preview";
            // 
            // previewPictureBox
            // 
            this.previewPictureBox.BackColor = System.Drawing.Color.Black;
            this.previewPictureBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.previewPictureBox.Location = new System.Drawing.Point(3, 16);
            this.previewPictureBox.Name = "previewPictureBox";
            this.previewPictureBox.Size = new System.Drawing.Size(414, 291);
            this.previewPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.previewPictureBox.TabIndex = 0;
            this.previewPictureBox.TabStop = false;
            // 
            // okButton
            // 
            this.okButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.okButton.Location = new System.Drawing.Point(279, 400);
            this.okButton.Name = "okButton";
            this.okButton.Size = new System.Drawing.Size(75, 23);
            this.okButton.TabIndex = 4;
            this.okButton.Text = "OK";
            this.okButton.UseVisualStyleBackColor = true;
            this.okButton.Click += new System.EventHandler(this.okButton_Click);
            // 
            // cancelButton
            // 
            this.cancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.cancelButton.Location = new System.Drawing.Point(360, 400);
            this.cancelButton.Name = "cancelButton";
            this.cancelButton.Size = new System.Drawing.Size(75, 23);
            this.cancelButton.TabIndex = 5;
            this.cancelButton.Text = "Cancel";
            this.cancelButton.UseVisualStyleBackColor = true;
            this.cancelButton.Click += new System.EventHandler(this.cancelButton_Click);
            // 
            // topDescriptionLabel
            // 
            this.topDescriptionLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.topDescriptionLabel.Location = new System.Drawing.Point(15, 10);
            this.topDescriptionLabel.Name = "topDescriptionLabel";
            this.topDescriptionLabel.Size = new System.Drawing.Size(420, 30);
            this.topDescriptionLabel.TabIndex = 6;
            this.topDescriptionLabel.Text = "Select an SSTV transmission mode and preview how the image will appear at the targ" +
    "et resolution.";
            // 
            // SstvSendForm
            // 
            this.AcceptButton = this.okButton;
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.cancelButton;
            this.ClientSize = new System.Drawing.Size(450, 435);
            this.Controls.Add(this.topDescriptionLabel);
            this.Controls.Add(this.cancelButton);
            this.Controls.Add(this.okButton);
            this.Controls.Add(this.previewGroupBox);
            this.Controls.Add(this.resolutionLabel);
            this.Controls.Add(this.modeComboBox);
            this.Controls.Add(this.modeLabel);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "SstvSendForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "SSTV Transmit";
            this.previewGroupBox.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.previewPictureBox)).EndInit();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Label modeLabel;
        private System.Windows.Forms.ComboBox modeComboBox;
        private System.Windows.Forms.Label resolutionLabel;
        private System.Windows.Forms.GroupBox previewGroupBox;
        private System.Windows.Forms.PictureBox previewPictureBox;
        private System.Windows.Forms.Button okButton;
        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.Label topDescriptionLabel;
    }
}
