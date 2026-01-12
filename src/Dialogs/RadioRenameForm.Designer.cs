namespace HTCommander.Dialogs
{
    partial class RadioRenameForm
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
            groupBox2 = new System.Windows.Forms.GroupBox();
            radioNameTextBox = new System.Windows.Forms.TextBox();
            label1 = new System.Windows.Forms.Label();
            pictureBox2 = new System.Windows.Forms.PictureBox();
            label4 = new System.Windows.Forms.Label();
            cancelButton = new System.Windows.Forms.Button();
            okButton = new System.Windows.Forms.Button();
            groupBox2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).BeginInit();
            SuspendLayout();
            // 
            // groupBox2
            // 
            groupBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            groupBox2.Controls.Add(radioNameTextBox);
            groupBox2.Controls.Add(label1);
            groupBox2.Location = new System.Drawing.Point(17, 70);
            groupBox2.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox2.Name = "groupBox2";
            groupBox2.Padding = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox2.Size = new System.Drawing.Size(424, 81);
            groupBox2.TabIndex = 8;
            groupBox2.TabStop = false;
            groupBox2.Text = "Radio";
            // 
            // radioNameTextBox
            // 
            radioNameTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            radioNameTextBox.Location = new System.Drawing.Point(95, 37);
            radioNameTextBox.Name = "radioNameTextBox";
            radioNameTextBox.Size = new System.Drawing.Size(313, 27);
            radioNameTextBox.TabIndex = 1;
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new System.Drawing.Point(19, 40);
            label1.Name = "label1";
            label1.Size = new System.Drawing.Size(49, 20);
            label1.TabIndex = 0;
            label1.Text = "Name";
            // 
            // pictureBox2
            // 
            pictureBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox2.Image = Properties.Resources.Radio;
            pictureBox2.Location = new System.Drawing.Point(396, 9);
            pictureBox2.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            pictureBox2.Name = "pictureBox2";
            pictureBox2.Size = new System.Drawing.Size(45, 52);
            pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox2.TabIndex = 10;
            pictureBox2.TabStop = false;
            // 
            // label4
            // 
            label4.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label4.Location = new System.Drawing.Point(13, 9);
            label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label4.Name = "label4";
            label4.Size = new System.Drawing.Size(375, 52);
            label4.TabIndex = 9;
            label4.Text = "Enter a friendly name for your radio or leave blank to return to the default name.";
            // 
            // cancelButton
            // 
            cancelButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            cancelButton.Location = new System.Drawing.Point(347, 159);
            cancelButton.Name = "cancelButton";
            cancelButton.Size = new System.Drawing.Size(94, 29);
            cancelButton.TabIndex = 3;
            cancelButton.Text = "Cancel";
            cancelButton.UseVisualStyleBackColor = true;
            // 
            // okButton
            // 
            okButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            okButton.Location = new System.Drawing.Point(247, 159);
            okButton.Name = "okButton";
            okButton.Size = new System.Drawing.Size(94, 29);
            okButton.TabIndex = 2;
            okButton.Text = "OK";
            okButton.UseVisualStyleBackColor = true;
            // 
            // RadioRenameForm
            // 
            AcceptButton = okButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            CancelButton = cancelButton;
            ClientSize = new System.Drawing.Size(454, 200);
            Controls.Add(okButton);
            Controls.Add(cancelButton);
            Controls.Add(groupBox2);
            Controls.Add(pictureBox2);
            Controls.Add(label4);
            FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "RadioRenameForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "Radio Rename";
            groupBox2.ResumeLayout(false);
            groupBox2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).EndInit();
            ResumeLayout(false);
        }

        #endregion

        private System.Windows.Forms.GroupBox groupBox2;
        private System.Windows.Forms.TextBox radioNameTextBox;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.Button okButton;
    }
}