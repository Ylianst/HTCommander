namespace HTCommander
{
    partial class MailAttachmentControl
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

        #region Component Designer generated code

        /// <summary> 
        /// Required method for Designer support - do not modify 
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            this.filenameLabel = new System.Windows.Forms.Label();
            this.removePictureBox = new System.Windows.Forms.PictureBox();
            this.saveFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.mainContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.saveAsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            this.removeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)(this.removePictureBox)).BeginInit();
            this.mainContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // filenameLabel
            // 
            this.filenameLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.filenameLabel.BackColor = System.Drawing.Color.RoyalBlue;
            this.filenameLabel.ContextMenuStrip = this.mainContextMenuStrip;
            this.filenameLabel.Cursor = System.Windows.Forms.Cursors.Hand;
            this.filenameLabel.ForeColor = System.Drawing.Color.White;
            this.filenameLabel.Location = new System.Drawing.Point(6, 6);
            this.filenameLabel.Name = "filenameLabel";
            this.filenameLabel.Padding = new System.Windows.Forms.Padding(2);
            this.filenameLabel.Size = new System.Drawing.Size(233, 24);
            this.filenameLabel.TabIndex = 0;
            this.filenameLabel.Text = "label1";
            this.filenameLabel.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.filenameLabel.Click += new System.EventHandler(this.filenameLabel_Click);
            // 
            // removePictureBox
            // 
            this.removePictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.removePictureBox.BackColor = System.Drawing.Color.RoyalBlue;
            this.removePictureBox.ContextMenuStrip = this.mainContextMenuStrip;
            this.removePictureBox.Cursor = System.Windows.Forms.Cursors.Hand;
            this.removePictureBox.Image = global::HTCommander.Properties.Resources.xicon64;
            this.removePictureBox.Location = new System.Drawing.Point(246, 10);
            this.removePictureBox.Margin = new System.Windows.Forms.Padding(6);
            this.removePictureBox.Name = "removePictureBox";
            this.removePictureBox.Size = new System.Drawing.Size(16, 16);
            this.removePictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.removePictureBox.TabIndex = 1;
            this.removePictureBox.TabStop = false;
            this.removePictureBox.Click += new System.EventHandler(this.removePictureBox_Click);
            // 
            // saveFileDialog
            // 
            this.saveFileDialog.Filter = "All files|*.*";
            this.saveFileDialog.Title = "Save Attachment";
            // 
            // mainContextMenuStrip
            // 
            this.mainContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.saveAsToolStripMenuItem,
            this.toolStripMenuItem1,
            this.removeToolStripMenuItem});
            this.mainContextMenuStrip.Name = "mainContextMenuStrip";
            this.mainContextMenuStrip.Size = new System.Drawing.Size(139, 58);
            // 
            // saveAsToolStripMenuItem
            // 
            this.saveAsToolStripMenuItem.Name = "saveAsToolStripMenuItem";
            this.saveAsToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.saveAsToolStripMenuItem.Text = "Save As...";
            this.saveAsToolStripMenuItem.Click += new System.EventHandler(this.saveAsToolStripMenuItem_Click);
            // 
            // toolStripMenuItem1
            // 
            this.toolStripMenuItem1.Name = "toolStripMenuItem1";
            this.toolStripMenuItem1.Size = new System.Drawing.Size(207, 6);
            // 
            // removeToolStripMenuItem
            // 
            this.removeToolStripMenuItem.Name = "removeToolStripMenuItem";
            this.removeToolStripMenuItem.Size = new System.Drawing.Size(210, 24);
            this.removeToolStripMenuItem.Text = "&Remove";
            // 
            // MailAttachmentControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ContextMenuStrip = this.mainContextMenuStrip;
            this.Controls.Add(this.removePictureBox);
            this.Controls.Add(this.filenameLabel);
            this.ForeColor = System.Drawing.Color.RoyalBlue;
            this.Name = "MailAttachmentControl";
            this.Size = new System.Drawing.Size(275, 36);
            ((System.ComponentModel.ISupportInitialize)(this.removePictureBox)).EndInit();
            this.mainContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Label filenameLabel;
        private System.Windows.Forms.PictureBox removePictureBox;
        private System.Windows.Forms.SaveFileDialog saveFileDialog;
        private System.Windows.Forms.ContextMenuStrip mainContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem saveAsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem removeToolStripMenuItem;
    }
}
