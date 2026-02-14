namespace HTCommander
{
    partial class ImagePreviewForm
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            pictureBox = new System.Windows.Forms.PictureBox();
            ((System.ComponentModel.ISupportInitialize)pictureBox).BeginInit();
            SuspendLayout();
            // 
            // pictureBox
            // 
            pictureBox.BackColor = System.Drawing.Color.Black;
            pictureBox.Dock = System.Windows.Forms.DockStyle.Fill;
            pictureBox.Location = new System.Drawing.Point(0, 0);
            pictureBox.Name = "pictureBox";
            pictureBox.Size = new System.Drawing.Size(600, 400);
            pictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox.TabIndex = 0;
            pictureBox.TabStop = false;
            // 
            // ImagePreviewForm
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(600, 400);
            Controls.Add(pictureBox);
            MinimumSize = new System.Drawing.Size(200, 150);
            Name = "ImagePreviewForm";
            Text = "Image Preview";
            ((System.ComponentModel.ISupportInitialize)pictureBox).EndInit();
            ResumeLayout(false);
        }

        #endregion

        private System.Windows.Forms.PictureBox pictureBox;
    }
}
