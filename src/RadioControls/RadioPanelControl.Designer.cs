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
            if (disposing)
            {
                broker?.Dispose();
                components?.Dispose();
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
            transmitBarPanel = new System.Windows.Forms.Panel();
            channelsFlowLayoutPanel = new System.Windows.Forms.FlowLayoutPanel();
            rssiProgressBar = new System.Windows.Forms.ProgressBar();
            connectedPanel = new System.Windows.Forms.Panel();
            gpsStatusLabel = new System.Windows.Forms.Label();
            voiceProcessingLabel = new System.Windows.Forms.Label();
            vfo2StatusLabel = new System.Windows.Forms.Label();
            vfo2FreqLabel = new System.Windows.Forms.Label();
            linePanel = new System.Windows.Forms.Panel();
            vfo1StatusLabel = new System.Windows.Forms.Label();
            vfo1FreqLabel = new System.Windows.Forms.Label();
            vfo2Label = new System.Windows.Forms.Label();
            vfo1Label = new System.Windows.Forms.Label();
            radioStateLabel = new System.Windows.Forms.Label();
            connectButton = new System.Windows.Forms.Button();
            radioPictureBox = new System.Windows.Forms.PictureBox();
            radio2PictureBox = new System.Windows.Forms.PictureBox();
            connectedPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)radioPictureBox).BeginInit();
            ((System.ComponentModel.ISupportInitialize)radio2PictureBox).BeginInit();
            SuspendLayout();
            // 
            // transmitBarPanel
            // 
            transmitBarPanel.BackColor = System.Drawing.Color.Red;
            transmitBarPanel.Location = new System.Drawing.Point(84, 408);
            transmitBarPanel.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            transmitBarPanel.Name = "transmitBarPanel";
            transmitBarPanel.Size = new System.Drawing.Size(205, 9);
            transmitBarPanel.TabIndex = 7;
            transmitBarPanel.Visible = false;
            transmitBarPanel.Click += radioPictureBox_Click;
            transmitBarPanel.DoubleClick += radioPictureBox_Click;
            // 
            // channelsFlowLayoutPanel
            // 
            channelsFlowLayoutPanel.BackColor = System.Drawing.Color.DarkKhaki;
            channelsFlowLayoutPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            channelsFlowLayoutPanel.Location = new System.Drawing.Point(0, 671);
            channelsFlowLayoutPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            channelsFlowLayoutPanel.Name = "channelsFlowLayoutPanel";
            channelsFlowLayoutPanel.Size = new System.Drawing.Size(368, 105);
            channelsFlowLayoutPanel.TabIndex = 2;
            channelsFlowLayoutPanel.Visible = false;
            // 
            // rssiProgressBar
            // 
            rssiProgressBar.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            rssiProgressBar.ForeColor = System.Drawing.Color.Black;
            rssiProgressBar.Location = new System.Drawing.Point(84, 408);
            rssiProgressBar.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            rssiProgressBar.Maximum = 15;
            rssiProgressBar.Name = "rssiProgressBar";
            rssiProgressBar.Size = new System.Drawing.Size(205, 9);
            rssiProgressBar.Step = 1;
            rssiProgressBar.Style = System.Windows.Forms.ProgressBarStyle.Continuous;
            rssiProgressBar.TabIndex = 0;
            rssiProgressBar.Visible = false;
            // 
            // connectedPanel
            // 
            connectedPanel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            connectedPanel.Controls.Add(gpsStatusLabel);
            connectedPanel.Controls.Add(voiceProcessingLabel);
            connectedPanel.Controls.Add(vfo2StatusLabel);
            connectedPanel.Controls.Add(vfo2FreqLabel);
            connectedPanel.Controls.Add(linePanel);
            connectedPanel.Controls.Add(vfo1StatusLabel);
            connectedPanel.Controls.Add(vfo1FreqLabel);
            connectedPanel.Controls.Add(vfo2Label);
            connectedPanel.Controls.Add(vfo1Label);
            connectedPanel.Location = new System.Drawing.Point(84, 215);
            connectedPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            connectedPanel.Name = "connectedPanel";
            connectedPanel.Size = new System.Drawing.Size(205, 189);
            connectedPanel.TabIndex = 1;
            connectedPanel.Visible = false;
            connectedPanel.Click += radioPictureBox_Click;
            connectedPanel.DoubleClick += radioPictureBox_Click;
            // 
            // gpsStatusLabel
            // 
            gpsStatusLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            gpsStatusLabel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            gpsStatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            gpsStatusLabel.ForeColor = System.Drawing.Color.DarkGray;
            gpsStatusLabel.Location = new System.Drawing.Point(48, 161);
            gpsStatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            gpsStatusLabel.Name = "gpsStatusLabel";
            gpsStatusLabel.Size = new System.Drawing.Size(152, 21);
            gpsStatusLabel.TabIndex = 8;
            gpsStatusLabel.Text = "GPS";
            gpsStatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            gpsStatusLabel.DoubleClick += gpsStatusLabel_DoubleClick;
            // 
            // voiceProcessingLabel
            // 
            voiceProcessingLabel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            voiceProcessingLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            voiceProcessingLabel.ForeColor = System.Drawing.Color.LightGray;
            voiceProcessingLabel.Location = new System.Drawing.Point(4, 161);
            voiceProcessingLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            voiceProcessingLabel.Name = "voiceProcessingLabel";
            voiceProcessingLabel.Size = new System.Drawing.Size(13, 21);
            voiceProcessingLabel.TabIndex = 8;
            voiceProcessingLabel.Text = "●";
            voiceProcessingLabel.Visible = false;
            voiceProcessingLabel.Click += radioPictureBox_Click;
            voiceProcessingLabel.DoubleClick += radioPictureBox_Click;
            // 
            // vfo2StatusLabel
            // 
            vfo2StatusLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            vfo2StatusLabel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            vfo2StatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            vfo2StatusLabel.ForeColor = System.Drawing.Color.LightGray;
            vfo2StatusLabel.Location = new System.Drawing.Point(95, 134);
            vfo2StatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            vfo2StatusLabel.Name = "vfo2StatusLabel";
            vfo2StatusLabel.Size = new System.Drawing.Size(107, 21);
            vfo2StatusLabel.TabIndex = 7;
            vfo2StatusLabel.Text = "VFO2";
            vfo2StatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            vfo2StatusLabel.Click += radioPictureBox_Click;
            vfo2StatusLabel.DoubleClick += radioPictureBox_Click;
            // 
            // vfo2FreqLabel
            // 
            vfo2FreqLabel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            vfo2FreqLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            vfo2FreqLabel.ForeColor = System.Drawing.Color.LightGray;
            vfo2FreqLabel.Location = new System.Drawing.Point(4, 134);
            vfo2FreqLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            vfo2FreqLabel.Name = "vfo2FreqLabel";
            vfo2FreqLabel.Size = new System.Drawing.Size(117, 21);
            vfo2FreqLabel.TabIndex = 6;
            vfo2FreqLabel.Text = "VFO2";
            vfo2FreqLabel.Click += radioPictureBox_Click;
            vfo2FreqLabel.DoubleClick += radioPictureBox_Click;
            // 
            // linePanel
            // 
            linePanel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            linePanel.BackColor = System.Drawing.Color.LightGray;
            linePanel.ForeColor = System.Drawing.Color.LightGray;
            linePanel.Location = new System.Drawing.Point(15, 79);
            linePanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            linePanel.Name = "linePanel";
            linePanel.Size = new System.Drawing.Size(175, 1);
            linePanel.TabIndex = 5;
            linePanel.Click += radioPictureBox_Click;
            linePanel.DoubleClick += radioPictureBox_Click;
            // 
            // vfo1StatusLabel
            // 
            vfo1StatusLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            vfo1StatusLabel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            vfo1StatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            vfo1StatusLabel.ForeColor = System.Drawing.Color.LightGray;
            vfo1StatusLabel.Location = new System.Drawing.Point(99, 51);
            vfo1StatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            vfo1StatusLabel.Name = "vfo1StatusLabel";
            vfo1StatusLabel.Size = new System.Drawing.Size(103, 21);
            vfo1StatusLabel.TabIndex = 4;
            vfo1StatusLabel.Text = "VFO1";
            vfo1StatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            vfo1StatusLabel.Click += radioPictureBox_Click;
            vfo1StatusLabel.DoubleClick += radioPictureBox_Click;
            // 
            // vfo1FreqLabel
            // 
            vfo1FreqLabel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            vfo1FreqLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            vfo1FreqLabel.ForeColor = System.Drawing.Color.LightGray;
            vfo1FreqLabel.Location = new System.Drawing.Point(4, 51);
            vfo1FreqLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            vfo1FreqLabel.Name = "vfo1FreqLabel";
            vfo1FreqLabel.Size = new System.Drawing.Size(117, 21);
            vfo1FreqLabel.TabIndex = 3;
            vfo1FreqLabel.Text = "VFO1";
            vfo1FreqLabel.Click += radioPictureBox_Click;
            vfo1FreqLabel.DoubleClick += radioPictureBox_Click;
            // 
            // vfo2Label
            // 
            vfo2Label.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            vfo2Label.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            vfo2Label.Font = new System.Drawing.Font("Microsoft Sans Serif", 20.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            vfo2Label.ForeColor = System.Drawing.Color.LightGray;
            vfo2Label.Location = new System.Drawing.Point(4, 81);
            vfo2Label.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            vfo2Label.Name = "vfo2Label";
            vfo2Label.Size = new System.Drawing.Size(197, 51);
            vfo2Label.TabIndex = 2;
            vfo2Label.Text = "VFO2";
            vfo2Label.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            vfo2Label.Click += radioPictureBox_Click;
            vfo2Label.DoubleClick += radioPictureBox_Click;
            // 
            // vfo1Label
            // 
            vfo1Label.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            vfo1Label.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            vfo1Label.Font = new System.Drawing.Font("Microsoft Sans Serif", 20.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            vfo1Label.ForeColor = System.Drawing.Color.LightGray;
            vfo1Label.Location = new System.Drawing.Point(4, 0);
            vfo1Label.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            vfo1Label.Name = "vfo1Label";
            vfo1Label.Size = new System.Drawing.Size(197, 51);
            vfo1Label.TabIndex = 1;
            vfo1Label.Text = "VFO1";
            vfo1Label.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            vfo1Label.Click += radioPictureBox_Click;
            vfo1Label.DoubleClick += radioPictureBox_Click;
            // 
            // radioStateLabel
            // 
            radioStateLabel.BackColor = System.Drawing.Color.FromArgb(86, 86, 88);
            radioStateLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            radioStateLabel.ForeColor = System.Drawing.Color.LightGray;
            radioStateLabel.Location = new System.Drawing.Point(84, 215);
            radioStateLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            radioStateLabel.Name = "radioStateLabel";
            radioStateLabel.Size = new System.Drawing.Size(205, 200);
            radioStateLabel.TabIndex = 1;
            radioStateLabel.Text = "Disconnected";
            radioStateLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            radioStateLabel.Click += radioPictureBox_Click;
            radioStateLabel.DoubleClick += radioPictureBox_Click;
            // 
            // connectButton
            // 
            connectButton.Dock = System.Windows.Forms.DockStyle.Bottom;
            connectButton.Location = new System.Drawing.Point(0, 776);
            connectButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            connectButton.Name = "connectButton";
            connectButton.Size = new System.Drawing.Size(368, 52);
            connectButton.TabIndex = 0;
            connectButton.Text = "Connect";
            connectButton.UseVisualStyleBackColor = true;
            connectButton.Click += connectButton_Click;
            // 
            // radioPictureBox
            // 
            radioPictureBox.Image = (System.Drawing.Image)resources.GetObject("radioPictureBox.Image");
            radioPictureBox.Location = new System.Drawing.Point(11, -1);
            radioPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            radioPictureBox.Name = "radioPictureBox";
            radioPictureBox.Size = new System.Drawing.Size(341, 848);
            radioPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            radioPictureBox.TabIndex = 0;
            radioPictureBox.TabStop = false;
            radioPictureBox.Click += radioPictureBox_Click;
            radioPictureBox.DragDrop += radioPictureBox_DragDrop;
            radioPictureBox.DragEnter += radioPictureBox_DragEnter;
            radioPictureBox.DoubleClick += radioPictureBox_Click;
            // 
            // radio2PictureBox
            // 
            radio2PictureBox.Image = (System.Drawing.Image)resources.GetObject("radio2PictureBox.Image");
            radio2PictureBox.Location = new System.Drawing.Point(-33, -25);
            radio2PictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            radio2PictureBox.Name = "radio2PictureBox";
            radio2PictureBox.Size = new System.Drawing.Size(440, 701);
            radio2PictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            radio2PictureBox.TabIndex = 8;
            radio2PictureBox.TabStop = false;
            radio2PictureBox.Visible = false;
            radio2PictureBox.Click += radioPictureBox_Click;
            radio2PictureBox.DragDrop += radioPictureBox_DragDrop;
            radio2PictureBox.DragEnter += radioPictureBox_DragEnter;
            radio2PictureBox.DoubleClick += radioPictureBox_Click;
            // 
            // RadioPanelControl
            // 
            AllowDrop = true;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            Controls.Add(channelsFlowLayoutPanel);
            Controls.Add(transmitBarPanel);
            Controls.Add(rssiProgressBar);
            Controls.Add(connectedPanel);
            Controls.Add(radioStateLabel);
            Controls.Add(connectButton);
            Controls.Add(radioPictureBox);
            Controls.Add(radio2PictureBox);
            Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            Name = "RadioPanelControl";
            Size = new System.Drawing.Size(368, 828);
            SizeChanged += radioPanel_SizeChanged;
            DragDrop += radioPictureBox_DragDrop;
            DragEnter += radioPictureBox_DragEnter;
            connectedPanel.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)radioPictureBox).EndInit();
            ((System.ComponentModel.ISupportInitialize)radio2PictureBox).EndInit();
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Panel transmitBarPanel;
        private System.Windows.Forms.FlowLayoutPanel channelsFlowLayoutPanel;
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
