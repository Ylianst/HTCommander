namespace HTCommander.RadioControls
{
    partial class RadioPanelControl
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioPanelControl));
            this.transmitBarPanel = new System.Windows.Forms.Panel();
            this.channelsFlowLayoutPanel = new System.Windows.Forms.FlowLayoutPanel();
            this.checkBluetoothButton = new System.Windows.Forms.Button();
            this.rssiProgressBar = new System.Windows.Forms.ProgressBar();
            this.connectedPanel = new System.Windows.Forms.Panel();
            this.gpsStatusLabel = new System.Windows.Forms.Label();
            this.voiceProcessingLabel = new System.Windows.Forms.Label();
            this.vfo2StatusLabel = new System.Windows.Forms.Label();
            this.vfo2FreqLabel = new System.Windows.Forms.Label();
            this.linePanel = new System.Windows.Forms.Panel();
            this.vfo1StatusLabel = new System.Windows.Forms.Label();
            this.vfo1FreqLabel = new System.Windows.Forms.Label();
            this.vfo2Label = new System.Windows.Forms.Label();
            this.vfo1Label = new System.Windows.Forms.Label();
            this.radioStateLabel = new System.Windows.Forms.Label();
            this.connectButton = new System.Windows.Forms.Button();
            this.radioPictureBox = new System.Windows.Forms.PictureBox();
            this.radio2PictureBox = new System.Windows.Forms.PictureBox();
            this.connectedPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.radioPictureBox)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.radio2PictureBox)).BeginInit();
            this.SuspendLayout();
            // 
            // transmitBarPanel
            // 
            this.transmitBarPanel.BackColor = System.Drawing.Color.Red;
            this.transmitBarPanel.Location = new System.Drawing.Point(84, 326);
            this.transmitBarPanel.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.transmitBarPanel.Name = "transmitBarPanel";
            this.transmitBarPanel.Size = new System.Drawing.Size(205, 7);
            this.transmitBarPanel.TabIndex = 7;
            this.transmitBarPanel.Visible = false;
            this.transmitBarPanel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.transmitBarPanel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // channelsFlowLayoutPanel
            // 
            this.channelsFlowLayoutPanel.BackColor = System.Drawing.Color.DarkKhaki;
            this.channelsFlowLayoutPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.channelsFlowLayoutPanel.Location = new System.Drawing.Point(0, 494);
            this.channelsFlowLayoutPanel.Margin = new System.Windows.Forms.Padding(4);
            this.channelsFlowLayoutPanel.Name = "channelsFlowLayoutPanel";
            this.channelsFlowLayoutPanel.Size = new System.Drawing.Size(368, 84);
            this.channelsFlowLayoutPanel.TabIndex = 2;
            this.channelsFlowLayoutPanel.Visible = false;
            // 
            // checkBluetoothButton
            // 
            this.checkBluetoothButton.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.checkBluetoothButton.Location = new System.Drawing.Point(0, 578);
            this.checkBluetoothButton.Margin = new System.Windows.Forms.Padding(4);
            this.checkBluetoothButton.Name = "checkBluetoothButton";
            this.checkBluetoothButton.Size = new System.Drawing.Size(368, 42);
            this.checkBluetoothButton.TabIndex = 3;
            this.checkBluetoothButton.Text = "Check Bluetooth";
            this.checkBluetoothButton.UseVisualStyleBackColor = true;
            this.checkBluetoothButton.Visible = false;
            this.checkBluetoothButton.Click += new System.EventHandler(this.checkBluetoothButton_ClickInternal);
            // 
            // rssiProgressBar
            // 
            this.rssiProgressBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.rssiProgressBar.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.rssiProgressBar.ForeColor = System.Drawing.Color.Black;
            this.rssiProgressBar.Location = new System.Drawing.Point(84, 326);
            this.rssiProgressBar.Margin = new System.Windows.Forms.Padding(4);
            this.rssiProgressBar.Maximum = 15;
            this.rssiProgressBar.Name = "rssiProgressBar";
            this.rssiProgressBar.Size = new System.Drawing.Size(205, 7);
            this.rssiProgressBar.Step = 1;
            this.rssiProgressBar.Style = System.Windows.Forms.ProgressBarStyle.Continuous;
            this.rssiProgressBar.TabIndex = 0;
            this.rssiProgressBar.Visible = false;
            // 
            // connectedPanel
            // 
            this.connectedPanel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.connectedPanel.Controls.Add(this.gpsStatusLabel);
            this.connectedPanel.Controls.Add(this.voiceProcessingLabel);
            this.connectedPanel.Controls.Add(this.vfo2StatusLabel);
            this.connectedPanel.Controls.Add(this.vfo2FreqLabel);
            this.connectedPanel.Controls.Add(this.linePanel);
            this.connectedPanel.Controls.Add(this.vfo1StatusLabel);
            this.connectedPanel.Controls.Add(this.vfo1FreqLabel);
            this.connectedPanel.Controls.Add(this.vfo2Label);
            this.connectedPanel.Controls.Add(this.vfo1Label);
            this.connectedPanel.Location = new System.Drawing.Point(84, 172);
            this.connectedPanel.Margin = new System.Windows.Forms.Padding(4);
            this.connectedPanel.Name = "connectedPanel";
            this.connectedPanel.Size = new System.Drawing.Size(205, 151);
            this.connectedPanel.TabIndex = 1;
            this.connectedPanel.Visible = false;
            this.connectedPanel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.connectedPanel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // gpsStatusLabel
            // 
            this.gpsStatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.gpsStatusLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.gpsStatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.gpsStatusLabel.ForeColor = System.Drawing.Color.DarkGray;
            this.gpsStatusLabel.Location = new System.Drawing.Point(48, 129);
            this.gpsStatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.gpsStatusLabel.Name = "gpsStatusLabel";
            this.gpsStatusLabel.Size = new System.Drawing.Size(152, 17);
            this.gpsStatusLabel.TabIndex = 8;
            this.gpsStatusLabel.Text = "GPS";
            this.gpsStatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            this.gpsStatusLabel.DoubleClick += new System.EventHandler(this.gpsStatusLabel_DoubleClick);
            // 
            // voiceProcessingLabel
            // 
            this.voiceProcessingLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.voiceProcessingLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.voiceProcessingLabel.ForeColor = System.Drawing.Color.LightGray;
            this.voiceProcessingLabel.Location = new System.Drawing.Point(4, 129);
            this.voiceProcessingLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.voiceProcessingLabel.Name = "voiceProcessingLabel";
            this.voiceProcessingLabel.Size = new System.Drawing.Size(13, 17);
            this.voiceProcessingLabel.TabIndex = 8;
            this.voiceProcessingLabel.Text = "●";
            this.voiceProcessingLabel.Visible = false;
            this.voiceProcessingLabel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.voiceProcessingLabel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // vfo2StatusLabel
            // 
            this.vfo2StatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo2StatusLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo2StatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo2StatusLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo2StatusLabel.Location = new System.Drawing.Point(95, 107);
            this.vfo2StatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.vfo2StatusLabel.Name = "vfo2StatusLabel";
            this.vfo2StatusLabel.Size = new System.Drawing.Size(107, 17);
            this.vfo2StatusLabel.TabIndex = 7;
            this.vfo2StatusLabel.Text = "VFO2";
            this.vfo2StatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            this.vfo2StatusLabel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.vfo2StatusLabel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // vfo2FreqLabel
            // 
            this.vfo2FreqLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo2FreqLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo2FreqLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo2FreqLabel.Location = new System.Drawing.Point(4, 107);
            this.vfo2FreqLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.vfo2FreqLabel.Name = "vfo2FreqLabel";
            this.vfo2FreqLabel.Size = new System.Drawing.Size(117, 17);
            this.vfo2FreqLabel.TabIndex = 6;
            this.vfo2FreqLabel.Text = "VFO2";
            this.vfo2FreqLabel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.vfo2FreqLabel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // linePanel
            // 
            this.linePanel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.linePanel.BackColor = System.Drawing.Color.LightGray;
            this.linePanel.ForeColor = System.Drawing.Color.LightGray;
            this.linePanel.Location = new System.Drawing.Point(15, 63);
            this.linePanel.Margin = new System.Windows.Forms.Padding(4);
            this.linePanel.Name = "linePanel";
            this.linePanel.Size = new System.Drawing.Size(175, 1);
            this.linePanel.TabIndex = 5;
            this.linePanel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.linePanel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // vfo1StatusLabel
            // 
            this.vfo1StatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo1StatusLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo1StatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo1StatusLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo1StatusLabel.Location = new System.Drawing.Point(99, 41);
            this.vfo1StatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.vfo1StatusLabel.Name = "vfo1StatusLabel";
            this.vfo1StatusLabel.Size = new System.Drawing.Size(103, 17);
            this.vfo1StatusLabel.TabIndex = 4;
            this.vfo1StatusLabel.Text = "VFO1";
            this.vfo1StatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            this.vfo1StatusLabel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.vfo1StatusLabel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // vfo1FreqLabel
            // 
            this.vfo1FreqLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo1FreqLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo1FreqLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo1FreqLabel.Location = new System.Drawing.Point(4, 41);
            this.vfo1FreqLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.vfo1FreqLabel.Name = "vfo1FreqLabel";
            this.vfo1FreqLabel.Size = new System.Drawing.Size(117, 17);
            this.vfo1FreqLabel.TabIndex = 3;
            this.vfo1FreqLabel.Text = "VFO1";
            this.vfo1FreqLabel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.vfo1FreqLabel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // vfo2Label
            // 
            this.vfo2Label.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo2Label.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo2Label.Font = new System.Drawing.Font("Microsoft Sans Serif", 20.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo2Label.ForeColor = System.Drawing.Color.LightGray;
            this.vfo2Label.Location = new System.Drawing.Point(4, 65);
            this.vfo2Label.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.vfo2Label.Name = "vfo2Label";
            this.vfo2Label.Size = new System.Drawing.Size(197, 41);
            this.vfo2Label.TabIndex = 2;
            this.vfo2Label.Text = "VFO2";
            this.vfo2Label.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.vfo2Label.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.vfo2Label.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // vfo1Label
            // 
            this.vfo1Label.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo1Label.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo1Label.Font = new System.Drawing.Font("Microsoft Sans Serif", 20.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo1Label.ForeColor = System.Drawing.Color.LightGray;
            this.vfo1Label.Location = new System.Drawing.Point(4, 0);
            this.vfo1Label.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.vfo1Label.Name = "vfo1Label";
            this.vfo1Label.Size = new System.Drawing.Size(197, 41);
            this.vfo1Label.TabIndex = 1;
            this.vfo1Label.Text = "VFO1";
            this.vfo1Label.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.vfo1Label.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.vfo1Label.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // radioStateLabel
            // 
            this.radioStateLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.radioStateLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.radioStateLabel.ForeColor = System.Drawing.Color.LightGray;
            this.radioStateLabel.Location = new System.Drawing.Point(84, 172);
            this.radioStateLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.radioStateLabel.Name = "radioStateLabel";
            this.radioStateLabel.Size = new System.Drawing.Size(205, 160);
            this.radioStateLabel.TabIndex = 1;
            this.radioStateLabel.Text = "Disconnected";
            this.radioStateLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            this.radioStateLabel.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.radioStateLabel.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // connectButton
            // 
            this.connectButton.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.connectButton.Location = new System.Drawing.Point(0, 620);
            this.connectButton.Margin = new System.Windows.Forms.Padding(4);
            this.connectButton.Name = "connectButton";
            this.connectButton.Size = new System.Drawing.Size(368, 42);
            this.connectButton.TabIndex = 0;
            this.connectButton.Text = "Connect";
            this.connectButton.UseVisualStyleBackColor = true;
            this.connectButton.Click += new System.EventHandler(this.connectButton_Click);
            // 
            // radioPictureBox
            // 
            this.radioPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("radioPictureBox.Image")));
            this.radioPictureBox.Location = new System.Drawing.Point(11, -1);
            this.radioPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.radioPictureBox.Name = "radioPictureBox";
            this.radioPictureBox.Size = new System.Drawing.Size(341, 678);
            this.radioPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.radioPictureBox.TabIndex = 0;
            this.radioPictureBox.TabStop = false;
            this.radioPictureBox.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.radioPictureBox.DragDrop += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragDrop);
            this.radioPictureBox.DragEnter += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragEnter);
            this.radioPictureBox.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // radio2PictureBox
            // 
            this.radio2PictureBox.Image = ((System.Drawing.Image)(resources.GetObject("radio2PictureBox.Image")));
            this.radio2PictureBox.Location = new System.Drawing.Point(-33, -20);
            this.radio2PictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.radio2PictureBox.Name = "radio2PictureBox";
            this.radio2PictureBox.Size = new System.Drawing.Size(440, 561);
            this.radio2PictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.radio2PictureBox.TabIndex = 8;
            this.radio2PictureBox.TabStop = false;
            this.radio2PictureBox.Visible = false;
            this.radio2PictureBox.Click += new System.EventHandler(this.radioPictureBox_Click);
            this.radio2PictureBox.DragDrop += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragDrop);
            this.radio2PictureBox.DragEnter += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragEnter);
            this.radio2PictureBox.DoubleClick += new System.EventHandler(this.radioPictureBox_Click);
            // 
            // RadioPanelControl
            // 
            this.AllowDrop = true;
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            this.Controls.Add(this.transmitBarPanel);
            this.Controls.Add(this.channelsFlowLayoutPanel);
            this.Controls.Add(this.checkBluetoothButton);
            this.Controls.Add(this.rssiProgressBar);
            this.Controls.Add(this.connectedPanel);
            this.Controls.Add(this.radioStateLabel);
            this.Controls.Add(this.connectButton);
            this.Controls.Add(this.radioPictureBox);
            this.Controls.Add(this.radio2PictureBox);
            this.Margin = new System.Windows.Forms.Padding(4);
            this.Name = "RadioPanelControl";
            this.Size = new System.Drawing.Size(368, 662);
            this.SizeChanged += new System.EventHandler(this.radioPanel_SizeChanged);
            this.DragDrop += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragDrop);
            this.DragEnter += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragEnter);
            this.connectedPanel.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.radioPictureBox)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.radio2PictureBox)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Panel transmitBarPanel;
        private System.Windows.Forms.FlowLayoutPanel channelsFlowLayoutPanel;
        private System.Windows.Forms.Button checkBluetoothButton;
        private System.Windows.Forms.ProgressBar rssiProgressBar;
        private System.Windows.Forms.Panel connectedPanel;
        private System.Windows.Forms.Label gpsStatusLabel;
        private System.Windows.Forms.Label voiceProcessingLabel;
        private System.Windows.Forms.Label vfo2StatusLabel;
        private System.Windows.Forms.Label vfo2FreqLabel;
        private System.Windows.Forms.Panel linePanel;
        private System.Windows.Forms.Label vfo1StatusLabel;
        private System.Windows.Forms.Label vfo1FreqLabel;
        private System.Windows.Forms.Label vfo2Label;
        private System.Windows.Forms.Label vfo1Label;
        private System.Windows.Forms.Label radioStateLabel;
        private System.Windows.Forms.Button connectButton;
        private System.Windows.Forms.PictureBox radioPictureBox;
        private System.Windows.Forms.PictureBox radio2PictureBox;
    }
}
