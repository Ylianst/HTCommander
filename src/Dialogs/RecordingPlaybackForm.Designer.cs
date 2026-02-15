namespace HTCommander
{
    partial class RecordingPlaybackForm
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
            fileNameLabel = new System.Windows.Forms.Label();
            playButton = new System.Windows.Forms.Button();
            trackBar = new System.Windows.Forms.TrackBar();
            positionLabel = new System.Windows.Forms.Label();
            durationLabel = new System.Windows.Forms.Label();
            ((System.ComponentModel.ISupportInitialize)trackBar).BeginInit();
            SuspendLayout();
            // 
            // fileNameLabel
            // 
            fileNameLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            fileNameLabel.Location = new System.Drawing.Point(14, 14);
            fileNameLabel.Name = "fileNameLabel";
            fileNameLabel.Size = new System.Drawing.Size(356, 20);
            fileNameLabel.TabIndex = 0;
            fileNameLabel.Text = "filename.wav";
            fileNameLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // playButton
            // 
            playButton.Location = new System.Drawing.Point(14, 44);
            playButton.Name = "playButton";
            playButton.Size = new System.Drawing.Size(75, 30);
            playButton.TabIndex = 1;
            playButton.Text = "Play";
            playButton.UseVisualStyleBackColor = true;
            playButton.Click += playButton_Click;
            // 
            // trackBar
            // 
            trackBar.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            trackBar.Location = new System.Drawing.Point(95, 44);
            trackBar.Name = "trackBar";
            trackBar.Size = new System.Drawing.Size(275, 56);
            trackBar.TabIndex = 2;
            trackBar.TickStyle = System.Windows.Forms.TickStyle.None;
            trackBar.Scroll += trackBar_Scroll;
            // 
            // positionLabel
            // 
            positionLabel.Location = new System.Drawing.Point(95, 80);
            positionLabel.Name = "positionLabel";
            positionLabel.Size = new System.Drawing.Size(60, 20);
            positionLabel.TabIndex = 3;
            positionLabel.Text = "00:00";
            // 
            // durationLabel
            // 
            durationLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            durationLabel.Location = new System.Drawing.Point(310, 80);
            durationLabel.Name = "durationLabel";
            durationLabel.Size = new System.Drawing.Size(60, 20);
            durationLabel.TabIndex = 4;
            durationLabel.Text = "00:00";
            durationLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            // 
            // RecordingPlaybackForm
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(384, 111);
            Controls.Add(durationLabel);
            Controls.Add(positionLabel);
            Controls.Add(trackBar);
            Controls.Add(playButton);
            Controls.Add(fileNameLabel);
            FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "RecordingPlaybackForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "Recording";
            ((System.ComponentModel.ISupportInitialize)trackBar).EndInit();
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private System.Windows.Forms.Label fileNameLabel;
        private System.Windows.Forms.Button playButton;
        private System.Windows.Forms.TrackBar trackBar;
        private System.Windows.Forms.Label positionLabel;
        private System.Windows.Forms.Label durationLabel;
    }
}
