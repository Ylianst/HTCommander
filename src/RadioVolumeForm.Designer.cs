namespace HTCommander
{
    partial class RadioVolumeForm
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
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioVolumeForm));
            this.volumeTrackBar = new System.Windows.Forms.TrackBar();
            this.groupBox1 = new System.Windows.Forms.GroupBox();
            this.label4 = new System.Windows.Forms.Label();
            this.squelchTrackBar = new System.Windows.Forms.TrackBar();
            this.label1 = new System.Windows.Forms.Label();
            this.outputComboBox = new System.Windows.Forms.ComboBox();
            this.label2 = new System.Windows.Forms.Label();
            this.label3 = new System.Windows.Forms.Label();
            this.inputComboBox = new System.Windows.Forms.ComboBox();
            this.groupBox2 = new System.Windows.Forms.GroupBox();
            this.label7 = new System.Windows.Forms.Label();
            this.inputTrackBar = new System.Windows.Forms.TrackBar();
            this.label5 = new System.Windows.Forms.Label();
            this.outputTrackBar = new System.Windows.Forms.TrackBar();
            this.label6 = new System.Windows.Forms.Label();
            this.masterVolumeTrackBar = new System.Windows.Forms.TrackBar();
            this.transmitButton = new System.Windows.Forms.Button();
            this.microphoneImageList = new System.Windows.Forms.ImageList(this.components);
            this.pollTimer = new System.Windows.Forms.Timer(this.components);
            this.audioButton = new System.Windows.Forms.Button();
            this.inputAmplitudeHistoryBar = new HTCommander.AmplitudeHistoryBar();
            this.outputAmplitudeHistoryBar = new HTCommander.AmplitudeHistoryBar();
            ((System.ComponentModel.ISupportInitialize)(this.volumeTrackBar)).BeginInit();
            this.groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.squelchTrackBar)).BeginInit();
            this.groupBox2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.inputTrackBar)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.outputTrackBar)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.masterVolumeTrackBar)).BeginInit();
            this.SuspendLayout();
            // 
            // volumeTrackBar
            // 
            this.volumeTrackBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.volumeTrackBar.LargeChange = 1;
            this.volumeTrackBar.Location = new System.Drawing.Point(25, 68);
            this.volumeTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.volumeTrackBar.Maximum = 15;
            this.volumeTrackBar.Name = "volumeTrackBar";
            this.volumeTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.volumeTrackBar.Size = new System.Drawing.Size(56, 284);
            this.volumeTrackBar.TabIndex = 0;
            this.volumeTrackBar.Scroll += new System.EventHandler(this.volumeTrackBar_Scroll);
            // 
            // groupBox1
            // 
            this.groupBox1.Controls.Add(this.label4);
            this.groupBox1.Controls.Add(this.squelchTrackBar);
            this.groupBox1.Controls.Add(this.label1);
            this.groupBox1.Controls.Add(this.volumeTrackBar);
            this.groupBox1.Location = new System.Drawing.Point(12, 82);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Size = new System.Drawing.Size(161, 373);
            this.groupBox1.TabIndex = 1;
            this.groupBox1.TabStop = false;
            this.groupBox1.Text = "Radio";
            // 
            // label4
            // 
            this.label4.AutoSize = true;
            this.label4.Location = new System.Drawing.Point(86, 33);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(56, 16);
            this.label4.TabIndex = 4;
            this.label4.Text = "Squelch";
            // 
            // squelchTrackBar
            // 
            this.squelchTrackBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.squelchTrackBar.LargeChange = 1;
            this.squelchTrackBar.Location = new System.Drawing.Point(89, 68);
            this.squelchTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.squelchTrackBar.Maximum = 9;
            this.squelchTrackBar.Name = "squelchTrackBar";
            this.squelchTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.squelchTrackBar.Size = new System.Drawing.Size(56, 284);
            this.squelchTrackBar.TabIndex = 3;
            this.squelchTrackBar.Scroll += new System.EventHandler(this.squelchTrackBar_Scroll);
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(22, 33);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(53, 16);
            this.label1.TabIndex = 2;
            this.label1.Text = "Volume";
            // 
            // outputComboBox
            // 
            this.outputComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.outputComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.outputComboBox.FormattingEnabled = true;
            this.outputComboBox.Location = new System.Drawing.Point(74, 12);
            this.outputComboBox.Name = "outputComboBox";
            this.outputComboBox.Size = new System.Drawing.Size(419, 24);
            this.outputComboBox.TabIndex = 2;
            this.outputComboBox.SelectedIndexChanged += new System.EventHandler(this.outputComboBox_SelectedIndexChanged);
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(9, 15);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(45, 16);
            this.label2.TabIndex = 3;
            this.label2.Text = "Output";
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(9, 45);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(35, 16);
            this.label3.TabIndex = 5;
            this.label3.Text = "Input";
            // 
            // inputComboBox
            // 
            this.inputComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.inputComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.inputComboBox.FormattingEnabled = true;
            this.inputComboBox.Location = new System.Drawing.Point(74, 42);
            this.inputComboBox.Name = "inputComboBox";
            this.inputComboBox.Size = new System.Drawing.Size(419, 24);
            this.inputComboBox.TabIndex = 4;
            this.inputComboBox.SelectedIndexChanged += new System.EventHandler(this.inputComboBox_SelectedIndexChanged);
            // 
            // groupBox2
            // 
            this.groupBox2.Controls.Add(this.outputAmplitudeHistoryBar);
            this.groupBox2.Controls.Add(this.inputAmplitudeHistoryBar);
            this.groupBox2.Controls.Add(this.label7);
            this.groupBox2.Controls.Add(this.inputTrackBar);
            this.groupBox2.Controls.Add(this.label5);
            this.groupBox2.Controls.Add(this.outputTrackBar);
            this.groupBox2.Controls.Add(this.label6);
            this.groupBox2.Controls.Add(this.masterVolumeTrackBar);
            this.groupBox2.Location = new System.Drawing.Point(180, 82);
            this.groupBox2.Name = "groupBox2";
            this.groupBox2.Size = new System.Drawing.Size(215, 373);
            this.groupBox2.TabIndex = 6;
            this.groupBox2.TabStop = false;
            this.groupBox2.Text = "Computer";
            // 
            // label7
            // 
            this.label7.AutoSize = true;
            this.label7.Location = new System.Drawing.Point(150, 33);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(35, 16);
            this.label7.TabIndex = 6;
            this.label7.Text = "Input";
            // 
            // inputTrackBar
            // 
            this.inputTrackBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.inputTrackBar.LargeChange = 10;
            this.inputTrackBar.Location = new System.Drawing.Point(153, 68);
            this.inputTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.inputTrackBar.Maximum = 100;
            this.inputTrackBar.Name = "inputTrackBar";
            this.inputTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.inputTrackBar.Size = new System.Drawing.Size(56, 284);
            this.inputTrackBar.TabIndex = 5;
            this.inputTrackBar.TickFrequency = 10;
            this.inputTrackBar.Value = 100;
            this.inputTrackBar.Scroll += new System.EventHandler(this.inputTrackBar_Scroll);
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(86, 33);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(45, 16);
            this.label5.TabIndex = 4;
            this.label5.Text = "Output";
            // 
            // outputTrackBar
            // 
            this.outputTrackBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.outputTrackBar.LargeChange = 10;
            this.outputTrackBar.Location = new System.Drawing.Point(89, 68);
            this.outputTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.outputTrackBar.Maximum = 100;
            this.outputTrackBar.Name = "outputTrackBar";
            this.outputTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.outputTrackBar.Size = new System.Drawing.Size(56, 284);
            this.outputTrackBar.TabIndex = 3;
            this.outputTrackBar.TickFrequency = 10;
            this.outputTrackBar.Value = 100;
            this.outputTrackBar.Scroll += new System.EventHandler(this.outputTrackBar_Scroll);
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(22, 33);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(48, 16);
            this.label6.TabIndex = 2;
            this.label6.Text = "Master";
            // 
            // masterVolumeTrackBar
            // 
            this.masterVolumeTrackBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.masterVolumeTrackBar.LargeChange = 10;
            this.masterVolumeTrackBar.Location = new System.Drawing.Point(25, 68);
            this.masterVolumeTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.masterVolumeTrackBar.Maximum = 100;
            this.masterVolumeTrackBar.Name = "masterVolumeTrackBar";
            this.masterVolumeTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.masterVolumeTrackBar.Size = new System.Drawing.Size(56, 284);
            this.masterVolumeTrackBar.TabIndex = 0;
            this.masterVolumeTrackBar.TickFrequency = 10;
            this.masterVolumeTrackBar.Scroll += new System.EventHandler(this.masterVolumeTrackBar_Scroll);
            // 
            // transmitButton
            // 
            this.transmitButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.transmitButton.ImageList = this.microphoneImageList;
            this.transmitButton.Location = new System.Drawing.Point(401, 375);
            this.transmitButton.Name = "transmitButton";
            this.transmitButton.Size = new System.Drawing.Size(92, 80);
            this.transmitButton.TabIndex = 7;
            this.transmitButton.UseVisualStyleBackColor = true;
            this.transmitButton.MouseDown += new System.Windows.Forms.MouseEventHandler(this.transmitButton_MouseDown);
            this.transmitButton.MouseEnter += new System.EventHandler(this.transmitButton_MouseEnter);
            this.transmitButton.MouseLeave += new System.EventHandler(this.transmitButton_MouseLeave);
            this.transmitButton.MouseUp += new System.Windows.Forms.MouseEventHandler(this.transmitButton_MouseUp);
            // 
            // microphoneImageList
            // 
            this.microphoneImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("microphoneImageList.ImageStream")));
            this.microphoneImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.microphoneImageList.Images.SetKeyName(0, "Microphone2-48-BW.png");
            this.microphoneImageList.Images.SetKeyName(1, "Microphone2-48-Blue.png");
            this.microphoneImageList.Images.SetKeyName(2, "Microphone2-48.png");
            this.microphoneImageList.Images.SetKeyName(3, "Speaker-48-Gray.png");
            this.microphoneImageList.Images.SetKeyName(4, "Speaker-48-Blue.png");
            // 
            // pollTimer
            // 
            this.pollTimer.Interval = 5000;
            this.pollTimer.Tick += new System.EventHandler(this.pollTimer_Tick);
            // 
            // audioButton
            // 
            this.audioButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.audioButton.ImageList = this.microphoneImageList;
            this.audioButton.Location = new System.Drawing.Point(401, 88);
            this.audioButton.Name = "audioButton";
            this.audioButton.Size = new System.Drawing.Size(92, 80);
            this.audioButton.TabIndex = 8;
            this.audioButton.UseVisualStyleBackColor = true;
            this.audioButton.Click += new System.EventHandler(this.audioButton_Click);
            // 
            // inputAmplitudeHistoryBar
            // 
            this.inputAmplitudeHistoryBar.BackColor = System.Drawing.Color.Black;
            this.inputAmplitudeHistoryBar.ForeColor = System.Drawing.Color.LimeGreen;
            this.inputAmplitudeHistoryBar.Location = new System.Drawing.Point(197, 84);
            this.inputAmplitudeHistoryBar.Name = "inputAmplitudeHistoryBar";
            this.inputAmplitudeHistoryBar.Size = new System.Drawing.Size(8, 258);
            this.inputAmplitudeHistoryBar.TabIndex = 7;
            // 
            // outputAmplitudeHistoryBar
            // 
            this.outputAmplitudeHistoryBar.BackColor = System.Drawing.Color.Black;
            this.outputAmplitudeHistoryBar.ForeColor = System.Drawing.Color.LimeGreen;
            this.outputAmplitudeHistoryBar.Location = new System.Drawing.Point(128, 84);
            this.outputAmplitudeHistoryBar.Name = "outputAmplitudeHistoryBar";
            this.outputAmplitudeHistoryBar.Size = new System.Drawing.Size(8, 258);
            this.outputAmplitudeHistoryBar.TabIndex = 8;
            // 
            // RadioVolumeForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(505, 467);
            this.Controls.Add(this.audioButton);
            this.Controls.Add(this.transmitButton);
            this.Controls.Add(this.groupBox2);
            this.Controls.Add(this.label3);
            this.Controls.Add(this.inputComboBox);
            this.Controls.Add(this.label2);
            this.Controls.Add(this.outputComboBox);
            this.Controls.Add(this.groupBox1);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Margin = new System.Windows.Forms.Padding(4);
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "RadioVolumeForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Audio Controls";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.RadioVolumeForm_FormClosing);
            this.Load += new System.EventHandler(this.RadioVolumeForm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.volumeTrackBar)).EndInit();
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.squelchTrackBar)).EndInit();
            this.groupBox2.ResumeLayout(false);
            this.groupBox2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.inputTrackBar)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.outputTrackBar)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.masterVolumeTrackBar)).EndInit();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion
        private System.Windows.Forms.TrackBar volumeTrackBar;
        private System.Windows.Forms.GroupBox groupBox1;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.ComboBox outputComboBox;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.ComboBox inputComboBox;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.TrackBar squelchTrackBar;
        private System.Windows.Forms.GroupBox groupBox2;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.TrackBar inputTrackBar;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.TrackBar outputTrackBar;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.TrackBar masterVolumeTrackBar;
        private System.Windows.Forms.Button transmitButton;
        private System.Windows.Forms.ImageList microphoneImageList;
        private System.Windows.Forms.Timer pollTimer;
        private System.Windows.Forms.Button audioButton;
        private AmplitudeHistoryBar inputAmplitudeHistoryBar;
        private AmplitudeHistoryBar outputAmplitudeHistoryBar;
    }
}