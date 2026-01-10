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
            this.appMuteButton = new System.Windows.Forms.Button();
            this.muteImageList = new System.Windows.Forms.ImageList(this.components);
            this.masterMuteButton = new System.Windows.Forms.Button();
            this.label8 = new System.Windows.Forms.Label();
            this.appVolumeTrackBar = new System.Windows.Forms.TrackBar();
            this.outputAmplitudeHistoryBar = new HTCommander.AmplitudeHistoryBar();
            this.label5 = new System.Windows.Forms.Label();
            this.outputTrackBar = new System.Windows.Forms.TrackBar();
            this.label6 = new System.Windows.Forms.Label();
            this.masterVolumeTrackBar = new System.Windows.Forms.TrackBar();
            this.label7 = new System.Windows.Forms.Label();
            this.inputTrackBar = new System.Windows.Forms.TrackBar();
            this.transmitButton = new System.Windows.Forms.Button();
            this.microphoneImageList = new System.Windows.Forms.ImageList(this.components);
            this.pollTimer = new System.Windows.Forms.Timer(this.components);
            this.audioButton = new System.Windows.Forms.Button();
            this.recordButton = new System.Windows.Forms.Button();
            this.saveFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.groupBox3 = new System.Windows.Forms.GroupBox();
            this.label9 = new System.Windows.Forms.Label();
            this.inputAmplitudeHistoryBar = new HTCommander.AmplitudeHistoryBar();
            this.inputBoostTrackBar = new System.Windows.Forms.TrackBar();
            this.outputGraphButton = new System.Windows.Forms.Button();
            this.inputGraphButton = new System.Windows.Forms.Button();
            this.menuStrip1 = new System.Windows.Forms.MenuStrip();
            this.menuStrip2 = new System.Windows.Forms.MenuStrip();
            this.fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.closeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.viewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.outputAudioGraphToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.inputAudioGraphToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.optionsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.spacebarPTTToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)(this.volumeTrackBar)).BeginInit();
            this.groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.squelchTrackBar)).BeginInit();
            this.groupBox2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.appVolumeTrackBar)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.outputTrackBar)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.masterVolumeTrackBar)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.inputTrackBar)).BeginInit();
            this.groupBox3.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.inputBoostTrackBar)).BeginInit();
            this.menuStrip2.SuspendLayout();
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
            this.volumeTrackBar.Size = new System.Drawing.Size(56, 166);
            this.volumeTrackBar.TabIndex = 20;
            this.volumeTrackBar.Scroll += new System.EventHandler(this.volumeTrackBar_Scroll);
            // 
            // groupBox1
            // 
            this.groupBox1.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.groupBox1.Controls.Add(this.label4);
            this.groupBox1.Controls.Add(this.squelchTrackBar);
            this.groupBox1.Controls.Add(this.label1);
            this.groupBox1.Controls.Add(this.volumeTrackBar);
            this.groupBox1.Location = new System.Drawing.Point(12, 114);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Size = new System.Drawing.Size(161, 255);
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
            this.squelchTrackBar.Size = new System.Drawing.Size(56, 166);
            this.squelchTrackBar.TabIndex = 21;
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
            this.outputComboBox.Location = new System.Drawing.Point(74, 41);
            this.outputComboBox.Name = "outputComboBox";
            this.outputComboBox.Size = new System.Drawing.Size(533, 24);
            this.outputComboBox.TabIndex = 10;
            this.outputComboBox.SelectedIndexChanged += new System.EventHandler(this.outputComboBox_SelectedIndexChanged);
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(9, 44);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(45, 16);
            this.label2.TabIndex = 3;
            this.label2.Text = "Output";
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(9, 74);
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
            this.inputComboBox.Location = new System.Drawing.Point(74, 71);
            this.inputComboBox.Name = "inputComboBox";
            this.inputComboBox.Size = new System.Drawing.Size(533, 24);
            this.inputComboBox.TabIndex = 12;
            this.inputComboBox.SelectedIndexChanged += new System.EventHandler(this.inputComboBox_SelectedIndexChanged);
            // 
            // groupBox2
            // 
            this.groupBox2.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.groupBox2.Controls.Add(this.appMuteButton);
            this.groupBox2.Controls.Add(this.masterMuteButton);
            this.groupBox2.Controls.Add(this.label8);
            this.groupBox2.Controls.Add(this.appVolumeTrackBar);
            this.groupBox2.Controls.Add(this.outputAmplitudeHistoryBar);
            this.groupBox2.Controls.Add(this.label5);
            this.groupBox2.Controls.Add(this.outputTrackBar);
            this.groupBox2.Controls.Add(this.label6);
            this.groupBox2.Controls.Add(this.masterVolumeTrackBar);
            this.groupBox2.Location = new System.Drawing.Point(180, 114);
            this.groupBox2.Name = "groupBox2";
            this.groupBox2.Size = new System.Drawing.Size(213, 255);
            this.groupBox2.TabIndex = 6;
            this.groupBox2.TabStop = false;
            this.groupBox2.Text = "Output";
            // 
            // appMuteButton
            // 
            this.appMuteButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.appMuteButton.Enabled = false;
            this.appMuteButton.ImageIndex = 0;
            this.appMuteButton.ImageList = this.muteImageList;
            this.appMuteButton.Location = new System.Drawing.Point(85, 219);
            this.appMuteButton.Name = "appMuteButton";
            this.appMuteButton.Size = new System.Drawing.Size(36, 32);
            this.appMuteButton.TabIndex = 25;
            this.appMuteButton.UseVisualStyleBackColor = true;
            this.appMuteButton.Click += new System.EventHandler(this.appMuteButton_Click);
            // 
            // muteImageList
            // 
            this.muteImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("muteImageList.ImageStream")));
            this.muteImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.muteImageList.Images.SetKeyName(0, "Mute-24.png");
            this.muteImageList.Images.SetKeyName(1, "NotMute-24.png");
            // 
            // masterMuteButton
            // 
            this.masterMuteButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.masterMuteButton.ImageIndex = 1;
            this.masterMuteButton.ImageList = this.muteImageList;
            this.masterMuteButton.Location = new System.Drawing.Point(22, 219);
            this.masterMuteButton.Name = "masterMuteButton";
            this.masterMuteButton.Size = new System.Drawing.Size(36, 32);
            this.masterMuteButton.TabIndex = 23;
            this.masterMuteButton.UseVisualStyleBackColor = true;
            this.masterMuteButton.Click += new System.EventHandler(this.masterMuteButton_Click);
            // 
            // label8
            // 
            this.label8.AutoSize = true;
            this.label8.Location = new System.Drawing.Point(88, 33);
            this.label8.Name = "label8";
            this.label8.Size = new System.Drawing.Size(32, 16);
            this.label8.TabIndex = 10;
            this.label8.Text = "App";
            // 
            // appVolumeTrackBar
            // 
            this.appVolumeTrackBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.appVolumeTrackBar.Enabled = false;
            this.appVolumeTrackBar.LargeChange = 10;
            this.appVolumeTrackBar.Location = new System.Drawing.Point(89, 68);
            this.appVolumeTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.appVolumeTrackBar.Maximum = 100;
            this.appVolumeTrackBar.Name = "appVolumeTrackBar";
            this.appVolumeTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.appVolumeTrackBar.Size = new System.Drawing.Size(56, 156);
            this.appVolumeTrackBar.TabIndex = 24;
            this.appVolumeTrackBar.TickFrequency = 10;
            this.appVolumeTrackBar.Scroll += new System.EventHandler(this.appVolumeTrackBar_Scroll);
            // 
            // outputAmplitudeHistoryBar
            // 
            this.outputAmplitudeHistoryBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.outputAmplitudeHistoryBar.BackColor = System.Drawing.Color.Black;
            this.outputAmplitudeHistoryBar.ForeColor = System.Drawing.Color.LimeGreen;
            this.outputAmplitudeHistoryBar.Location = new System.Drawing.Point(184, 84);
            this.outputAmplitudeHistoryBar.Name = "outputAmplitudeHistoryBar";
            this.outputAmplitudeHistoryBar.Size = new System.Drawing.Size(8, 140);
            this.outputAmplitudeHistoryBar.TabIndex = 8;
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(147, 33);
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
            this.outputTrackBar.Location = new System.Drawing.Point(145, 68);
            this.outputTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.outputTrackBar.Maximum = 100;
            this.outputTrackBar.Name = "outputTrackBar";
            this.outputTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.outputTrackBar.Size = new System.Drawing.Size(56, 166);
            this.outputTrackBar.TabIndex = 26;
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
            this.masterVolumeTrackBar.Size = new System.Drawing.Size(56, 156);
            this.masterVolumeTrackBar.TabIndex = 22;
            this.masterVolumeTrackBar.TickFrequency = 10;
            this.masterVolumeTrackBar.Scroll += new System.EventHandler(this.masterVolumeTrackBar_Scroll);
            // 
            // label7
            // 
            this.label7.AutoSize = true;
            this.label7.Location = new System.Drawing.Point(23, 27);
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
            this.inputTrackBar.Location = new System.Drawing.Point(26, 68);
            this.inputTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.inputTrackBar.Maximum = 100;
            this.inputTrackBar.Name = "inputTrackBar";
            this.inputTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.inputTrackBar.Size = new System.Drawing.Size(56, 166);
            this.inputTrackBar.TabIndex = 27;
            this.inputTrackBar.TickFrequency = 10;
            this.inputTrackBar.Value = 100;
            this.inputTrackBar.Scroll += new System.EventHandler(this.inputTrackBar_Scroll);
            // 
            // transmitButton
            // 
            this.transmitButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.transmitButton.ImageList = this.microphoneImageList;
            this.transmitButton.Location = new System.Drawing.Point(565, 289);
            this.transmitButton.Name = "transmitButton";
            this.transmitButton.Size = new System.Drawing.Size(92, 80);
            this.transmitButton.TabIndex = 42;
            this.transmitButton.UseVisualStyleBackColor = true;
            this.transmitButton.KeyDown += new System.Windows.Forms.KeyEventHandler(this.RadioVolumeForm_KeyDown);
            this.transmitButton.KeyUp += new System.Windows.Forms.KeyEventHandler(this.RadioVolumeForm_KeyUp);
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
            this.microphoneImageList.Images.SetKeyName(5, "Record-48-BW.png");
            this.microphoneImageList.Images.SetKeyName(6, "Record-48-Blue.png");
            this.microphoneImageList.Images.SetKeyName(7, "Record-48-Red.png");
            // 
            // pollTimer
            // 
            this.pollTimer.Interval = 5000;
            this.pollTimer.Tick += new System.EventHandler(this.pollTimer_Tick);
            // 
            // audioButton
            // 
            this.audioButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.audioButton.ImageList = this.microphoneImageList;
            this.audioButton.Location = new System.Drawing.Point(565, 115);
            this.audioButton.Name = "audioButton";
            this.audioButton.Size = new System.Drawing.Size(92, 80);
            this.audioButton.TabIndex = 40;
            this.audioButton.UseVisualStyleBackColor = true;
            this.audioButton.Click += new System.EventHandler(this.audioButton_Click);
            // 
            // recordButton
            // 
            this.recordButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.recordButton.ImageList = this.microphoneImageList;
            this.recordButton.Location = new System.Drawing.Point(565, 201);
            this.recordButton.Name = "recordButton";
            this.recordButton.Size = new System.Drawing.Size(92, 80);
            this.recordButton.TabIndex = 41;
            this.recordButton.UseVisualStyleBackColor = true;
            this.recordButton.Click += new System.EventHandler(this.recordButton_Click);
            // 
            // saveFileDialog
            // 
            this.saveFileDialog.DefaultExt = "wav";
            this.saveFileDialog.Filter = "Wave files (*.wav)|*.wav";
            this.saveFileDialog.Title = "Record Audio";
            // 
            // groupBox3
            // 
            this.groupBox3.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.groupBox3.Controls.Add(this.label9);
            this.groupBox3.Controls.Add(this.label7);
            this.groupBox3.Controls.Add(this.inputAmplitudeHistoryBar);
            this.groupBox3.Controls.Add(this.inputTrackBar);
            this.groupBox3.Controls.Add(this.inputBoostTrackBar);
            this.groupBox3.Location = new System.Drawing.Point(399, 114);
            this.groupBox3.Name = "groupBox3";
            this.groupBox3.Size = new System.Drawing.Size(160, 255);
            this.groupBox3.TabIndex = 10;
            this.groupBox3.TabStop = false;
            this.groupBox3.Text = "Input";
            // 
            // label9
            // 
            this.label9.AutoSize = true;
            this.label9.Location = new System.Drawing.Point(92, 27);
            this.label9.Name = "label9";
            this.label9.Size = new System.Drawing.Size(42, 16);
            this.label9.TabIndex = 9;
            this.label9.Text = "Boost";
            // 
            // inputAmplitudeHistoryBar
            // 
            this.inputAmplitudeHistoryBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.inputAmplitudeHistoryBar.BackColor = System.Drawing.Color.Black;
            this.inputAmplitudeHistoryBar.ForeColor = System.Drawing.Color.LimeGreen;
            this.inputAmplitudeHistoryBar.Location = new System.Drawing.Point(122, 84);
            this.inputAmplitudeHistoryBar.Name = "inputAmplitudeHistoryBar";
            this.inputAmplitudeHistoryBar.Size = new System.Drawing.Size(8, 140);
            this.inputAmplitudeHistoryBar.TabIndex = 7;
            // 
            // inputBoostTrackBar
            // 
            this.inputBoostTrackBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left)));
            this.inputBoostTrackBar.LargeChange = 1;
            this.inputBoostTrackBar.Location = new System.Drawing.Point(83, 68);
            this.inputBoostTrackBar.Margin = new System.Windows.Forms.Padding(4);
            this.inputBoostTrackBar.Name = "inputBoostTrackBar";
            this.inputBoostTrackBar.Orientation = System.Windows.Forms.Orientation.Vertical;
            this.inputBoostTrackBar.Size = new System.Drawing.Size(56, 166);
            this.inputBoostTrackBar.TabIndex = 28;
            this.inputBoostTrackBar.Scroll += new System.EventHandler(this.inputBoostTrackBar_Scroll);
            // 
            // outputGraphButton
            // 
            this.outputGraphButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.outputGraphButton.Image = ((System.Drawing.Image)(resources.GetObject("outputGraphButton.Image")));
            this.outputGraphButton.Location = new System.Drawing.Point(613, 41);
            this.outputGraphButton.Name = "outputGraphButton";
            this.outputGraphButton.Size = new System.Drawing.Size(44, 28);
            this.outputGraphButton.TabIndex = 11;
            this.outputGraphButton.UseVisualStyleBackColor = true;
            this.outputGraphButton.Click += new System.EventHandler(this.outputGraphButton_Click);
            // 
            // inputGraphButton
            // 
            this.inputGraphButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.inputGraphButton.Image = ((System.Drawing.Image)(resources.GetObject("inputGraphButton.Image")));
            this.inputGraphButton.Location = new System.Drawing.Point(613, 71);
            this.inputGraphButton.Name = "inputGraphButton";
            this.inputGraphButton.Size = new System.Drawing.Size(44, 28);
            this.inputGraphButton.TabIndex = 13;
            this.inputGraphButton.UseVisualStyleBackColor = true;
            this.inputGraphButton.Click += new System.EventHandler(this.inputGraphButton_Click);
            // 
            // menuStrip1
            // 
            this.menuStrip1.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.menuStrip1.Location = new System.Drawing.Point(0, 28);
            this.menuStrip1.Name = "menuStrip1";
            this.menuStrip1.Size = new System.Drawing.Size(669, 24);
            this.menuStrip1.TabIndex = 43;
            this.menuStrip1.Text = "menuStrip1";
            // 
            // menuStrip2
            // 
            this.menuStrip2.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.menuStrip2.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.fileToolStripMenuItem,
            this.viewToolStripMenuItem,
            this.optionsToolStripMenuItem});
            this.menuStrip2.Location = new System.Drawing.Point(0, 0);
            this.menuStrip2.Name = "menuStrip2";
            this.menuStrip2.Size = new System.Drawing.Size(669, 28);
            this.menuStrip2.TabIndex = 44;
            this.menuStrip2.Text = "menuStrip2";
            // 
            // fileToolStripMenuItem
            // 
            this.fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.closeToolStripMenuItem});
            this.fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            this.fileToolStripMenuItem.Size = new System.Drawing.Size(46, 24);
            this.fileToolStripMenuItem.Text = "&File";
            // 
            // closeToolStripMenuItem
            // 
            this.closeToolStripMenuItem.Name = "closeToolStripMenuItem";
            this.closeToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            this.closeToolStripMenuItem.Text = "&Close";
            this.closeToolStripMenuItem.Click += new System.EventHandler(this.closeToolStripMenuItem_Click);
            // 
            // viewToolStripMenuItem
            // 
            this.viewToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.outputAudioGraphToolStripMenuItem,
            this.inputAudioGraphToolStripMenuItem});
            this.viewToolStripMenuItem.Name = "viewToolStripMenuItem";
            this.viewToolStripMenuItem.Size = new System.Drawing.Size(55, 24);
            this.viewToolStripMenuItem.Text = "&View";
            // 
            // outputAudioGraphToolStripMenuItem
            // 
            this.outputAudioGraphToolStripMenuItem.Name = "outputAudioGraphToolStripMenuItem";
            this.outputAudioGraphToolStripMenuItem.Size = new System.Drawing.Size(235, 26);
            this.outputAudioGraphToolStripMenuItem.Text = "&Output Audio Graph...";
            this.outputAudioGraphToolStripMenuItem.Click += new System.EventHandler(this.outputGraphButton_Click);
            // 
            // inputAudioGraphToolStripMenuItem
            // 
            this.inputAudioGraphToolStripMenuItem.Name = "inputAudioGraphToolStripMenuItem";
            this.inputAudioGraphToolStripMenuItem.Size = new System.Drawing.Size(235, 26);
            this.inputAudioGraphToolStripMenuItem.Text = "&Input Audio Graph...";
            this.inputAudioGraphToolStripMenuItem.Click += new System.EventHandler(this.inputGraphButton_Click);
            // 
            // optionsToolStripMenuItem
            // 
            this.optionsToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.spacebarPTTToolStripMenuItem});
            this.optionsToolStripMenuItem.Name = "optionsToolStripMenuItem";
            this.optionsToolStripMenuItem.Size = new System.Drawing.Size(75, 24);
            this.optionsToolStripMenuItem.Text = "&Options";
            // 
            // spacebarPTTToolStripMenuItem
            // 
            this.spacebarPTTToolStripMenuItem.CheckOnClick = true;
            this.spacebarPTTToolStripMenuItem.Name = "spacebarPTTToolStripMenuItem";
            this.spacebarPTTToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            this.spacebarPTTToolStripMenuItem.Text = "&Spacebar PTT";
            this.spacebarPTTToolStripMenuItem.Click += new System.EventHandler(this.spacebarPTTToolStripMenuItem_Click);
            // 
            // RadioVolumeForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(669, 381);
            this.Controls.Add(this.inputGraphButton);
            this.Controls.Add(this.outputGraphButton);
            this.Controls.Add(this.groupBox3);
            this.Controls.Add(this.recordButton);
            this.Controls.Add(this.audioButton);
            this.Controls.Add(this.transmitButton);
            this.Controls.Add(this.groupBox2);
            this.Controls.Add(this.label3);
            this.Controls.Add(this.inputComboBox);
            this.Controls.Add(this.label2);
            this.Controls.Add(this.outputComboBox);
            this.Controls.Add(this.groupBox1);
            this.Controls.Add(this.menuStrip1);
            this.Controls.Add(this.menuStrip2);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.KeyPreview = true;
            this.MainMenuStrip = this.menuStrip1;
            this.Margin = new System.Windows.Forms.Padding(4);
            this.MaximizeBox = false;
            this.MaximumSize = new System.Drawing.Size(687, 660);
            this.MinimizeBox = false;
            this.MinimumSize = new System.Drawing.Size(687, 428);
            this.Name = "RadioVolumeForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Audio Controls";
            this.Deactivate += new System.EventHandler(this.RadioVolumeForm_Deactivate);
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.RadioVolumeForm_FormClosing);
            this.Load += new System.EventHandler(this.RadioVolumeForm_Load);
            this.KeyDown += new System.Windows.Forms.KeyEventHandler(this.RadioVolumeForm_KeyDown);
            this.KeyUp += new System.Windows.Forms.KeyEventHandler(this.RadioVolumeForm_KeyUp);
            ((System.ComponentModel.ISupportInitialize)(this.volumeTrackBar)).EndInit();
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.squelchTrackBar)).EndInit();
            this.groupBox2.ResumeLayout(false);
            this.groupBox2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.appVolumeTrackBar)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.outputTrackBar)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.masterVolumeTrackBar)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.inputTrackBar)).EndInit();
            this.groupBox3.ResumeLayout(false);
            this.groupBox3.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.inputBoostTrackBar)).EndInit();
            this.menuStrip2.ResumeLayout(false);
            this.menuStrip2.PerformLayout();
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
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.TrackBar appVolumeTrackBar;
        private System.Windows.Forms.Button recordButton;
        private System.Windows.Forms.SaveFileDialog saveFileDialog;
        private System.Windows.Forms.ImageList muteImageList;
        private System.Windows.Forms.Button masterMuteButton;
        private System.Windows.Forms.Button appMuteButton;
        private System.Windows.Forms.GroupBox groupBox3;
        private System.Windows.Forms.Label label9;
        private System.Windows.Forms.TrackBar inputBoostTrackBar;
        private System.Windows.Forms.Button outputGraphButton;
        private System.Windows.Forms.Button inputGraphButton;
        private System.Windows.Forms.MenuStrip menuStrip1;
        private System.Windows.Forms.MenuStrip menuStrip2;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem closeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem viewToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem outputAudioGraphToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem inputAudioGraphToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem optionsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem spacebarPTTToolStripMenuItem;
    }
}