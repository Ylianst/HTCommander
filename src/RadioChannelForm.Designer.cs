namespace HTCommander
{
    partial class RadioChannelForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioChannelForm));
            this.cancelButton = new System.Windows.Forms.Button();
            this.label4 = new System.Windows.Forms.Label();
            this.basicGroupBox = new System.Windows.Forms.GroupBox();
            this.moreSettingsButton = new System.Windows.Forms.Button();
            this.muteCheckBox = new System.Windows.Forms.CheckBox();
            this.disableTransmitCheckBox = new System.Windows.Forms.CheckBox();
            this.label5 = new System.Windows.Forms.Label();
            this.powerComboBox = new System.Windows.Forms.ComboBox();
            this.label3 = new System.Windows.Forms.Label();
            this.label2 = new System.Windows.Forms.Label();
            this.label1 = new System.Windows.Forms.Label();
            this.nameTextBox = new System.Windows.Forms.TextBox();
            this.modeComboBox = new System.Windows.Forms.ComboBox();
            this.freqTextBox = new System.Windows.Forms.TextBox();
            this.pictureBox2 = new System.Windows.Forms.PictureBox();
            this.repeaterBookLinkLabel = new System.Windows.Forms.LinkLabel();
            this.advGroupBox = new System.Windows.Forms.GroupBox();
            this.deemphasisCheckBox = new System.Windows.Forms.CheckBox();
            this.label13 = new System.Windows.Forms.Label();
            this.advBandwidthComboBox = new System.Windows.Forms.ComboBox();
            this.label12 = new System.Windows.Forms.Label();
            this.receiveCtcssComboBox = new System.Windows.Forms.ComboBox();
            this.label7 = new System.Windows.Forms.Label();
            this.transmitCtcssComboBox = new System.Windows.Forms.ComboBox();
            this.advTalkAroundCheckBox = new System.Windows.Forms.CheckBox();
            this.advScanCheckBox = new System.Windows.Forms.CheckBox();
            this.label10 = new System.Windows.Forms.Label();
            this.label11 = new System.Windows.Forms.Label();
            this.advTransmitFreqTextBox = new System.Windows.Forms.TextBox();
            this.advMuteCheckBox = new System.Windows.Forms.CheckBox();
            this.advDisableTransmitCheckBox = new System.Windows.Forms.CheckBox();
            this.label6 = new System.Windows.Forms.Label();
            this.advPowerComboBox = new System.Windows.Forms.ComboBox();
            this.label8 = new System.Windows.Forms.Label();
            this.label9 = new System.Windows.Forms.Label();
            this.advNameTextBox = new System.Windows.Forms.TextBox();
            this.advModeComboBox = new System.Windows.Forms.ComboBox();
            this.advReceiveFreqTextBox = new System.Windows.Forms.TextBox();
            this.okButton = new System.Windows.Forms.Button();
            this.clearButton = new System.Windows.Forms.Button();
            this.basicGroupBox.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).BeginInit();
            this.advGroupBox.SuspendLayout();
            this.SuspendLayout();
            // 
            // cancelButton
            // 
            this.cancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.cancelButton.Location = new System.Drawing.Point(419, 779);
            this.cancelButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.cancelButton.Name = "cancelButton";
            this.cancelButton.Size = new System.Drawing.Size(100, 28);
            this.cancelButton.TabIndex = 32;
            this.cancelButton.Text = "Cancel";
            this.cancelButton.UseVisualStyleBackColor = true;
            this.cancelButton.Click += new System.EventHandler(this.cancelButton_Click);
            // 
            // label4
            // 
            this.label4.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label4.Location = new System.Drawing.Point(16, 11);
            this.label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(403, 64);
            this.label4.TabIndex = 8;
            this.label4.Text = "Finding the right frequencies and settings for your area can be some work, take a" +
    " look at this site for help:";
            // 
            // basicGroupBox
            // 
            this.basicGroupBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.basicGroupBox.Controls.Add(this.moreSettingsButton);
            this.basicGroupBox.Controls.Add(this.muteCheckBox);
            this.basicGroupBox.Controls.Add(this.disableTransmitCheckBox);
            this.basicGroupBox.Controls.Add(this.label5);
            this.basicGroupBox.Controls.Add(this.powerComboBox);
            this.basicGroupBox.Controls.Add(this.label3);
            this.basicGroupBox.Controls.Add(this.label2);
            this.basicGroupBox.Controls.Add(this.label1);
            this.basicGroupBox.Controls.Add(this.nameTextBox);
            this.basicGroupBox.Controls.Add(this.modeComboBox);
            this.basicGroupBox.Controls.Add(this.freqTextBox);
            this.basicGroupBox.Location = new System.Drawing.Point(20, 82);
            this.basicGroupBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.basicGroupBox.Name = "basicGroupBox";
            this.basicGroupBox.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.basicGroupBox.Size = new System.Drawing.Size(499, 282);
            this.basicGroupBox.TabIndex = 7;
            this.basicGroupBox.TabStop = false;
            this.basicGroupBox.Text = "Channel";
            // 
            // moreSettingsButton
            // 
            this.moreSettingsButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.moreSettingsButton.Location = new System.Drawing.Point(12, 246);
            this.moreSettingsButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.moreSettingsButton.Name = "moreSettingsButton";
            this.moreSettingsButton.Size = new System.Drawing.Size(120, 28);
            this.moreSettingsButton.TabIndex = 7;
            this.moreSettingsButton.Text = "More Settings";
            this.moreSettingsButton.UseVisualStyleBackColor = true;
            this.moreSettingsButton.Click += new System.EventHandler(this.moreSettingsButton_Click);
            // 
            // muteCheckBox
            // 
            this.muteCheckBox.AutoSize = true;
            this.muteCheckBox.Location = new System.Drawing.Point(215, 219);
            this.muteCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.muteCheckBox.Name = "muteCheckBox";
            this.muteCheckBox.Size = new System.Drawing.Size(58, 20);
            this.muteCheckBox.TabIndex = 6;
            this.muteCheckBox.Text = "Mute";
            this.muteCheckBox.UseVisualStyleBackColor = true;
            this.muteCheckBox.CheckedChanged += new System.EventHandler(this.muteCheckBox_CheckedChanged);
            // 
            // disableTransmitCheckBox
            // 
            this.disableTransmitCheckBox.AutoSize = true;
            this.disableTransmitCheckBox.Location = new System.Drawing.Point(215, 191);
            this.disableTransmitCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.disableTransmitCheckBox.Name = "disableTransmitCheckBox";
            this.disableTransmitCheckBox.Size = new System.Drawing.Size(131, 20);
            this.disableTransmitCheckBox.TabIndex = 5;
            this.disableTransmitCheckBox.Text = "Disable Transmit";
            this.disableTransmitCheckBox.UseVisualStyleBackColor = true;
            this.disableTransmitCheckBox.CheckedChanged += new System.EventHandler(this.disableTransmitCheckBox_CheckedChanged);
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(8, 150);
            this.label5.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(45, 16);
            this.label5.TabIndex = 7;
            this.label5.Text = "Power";
            // 
            // powerComboBox
            // 
            this.powerComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.powerComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.powerComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.powerComboBox.FormattingEnabled = true;
            this.powerComboBox.Items.AddRange(new object[] {
            "High",
            "Medium",
            "Low"});
            this.powerComboBox.Location = new System.Drawing.Point(215, 146);
            this.powerComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.powerComboBox.Name = "powerComboBox";
            this.powerComboBox.Size = new System.Drawing.Size(275, 25);
            this.powerComboBox.TabIndex = 4;
            this.powerComboBox.SelectedIndexChanged += new System.EventHandler(this.powerComboBox_SelectedIndexChanged);
            // 
            // label3
            // 
            this.label3.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label3.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.label3.Location = new System.Drawing.Point(211, 113);
            this.label3.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(280, 18);
            this.label3.TabIndex = 5;
            this.label3.Text = "136 MHz - 174 MHz, 300 MHz - 550 MHz\r\n";
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(8, 86);
            this.label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(71, 16);
            this.label2.TabIndex = 4;
            this.label2.Text = "Frequency";
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(8, 38);
            this.label1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(44, 16);
            this.label1.TabIndex = 3;
            this.label1.Text = "Name";
            // 
            // nameTextBox
            // 
            this.nameTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.nameTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.nameTextBox.Location = new System.Drawing.Point(215, 23);
            this.nameTextBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.nameTextBox.MaxLength = 10;
            this.nameTextBox.Name = "nameTextBox";
            this.nameTextBox.Size = new System.Drawing.Size(275, 37);
            this.nameTextBox.TabIndex = 1;
            this.nameTextBox.TextChanged += new System.EventHandler(this.nameTextBox_TextChanged);
            // 
            // modeComboBox
            // 
            this.modeComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.modeComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.modeComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.modeComboBox.FormattingEnabled = true;
            this.modeComboBox.Items.AddRange(new object[] {
            "FM",
            "AM"});
            this.modeComboBox.Location = new System.Drawing.Point(409, 69);
            this.modeComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.modeComboBox.Name = "modeComboBox";
            this.modeComboBox.Size = new System.Drawing.Size(80, 38);
            this.modeComboBox.TabIndex = 3;
            // 
            // freqTextBox
            // 
            this.freqTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.freqTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.freqTextBox.Location = new System.Drawing.Point(215, 71);
            this.freqTextBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.freqTextBox.Name = "freqTextBox";
            this.freqTextBox.Size = new System.Drawing.Size(183, 37);
            this.freqTextBox.TabIndex = 2;
            this.freqTextBox.TextChanged += new System.EventHandler(this.freqTextBox_TextChanged);
            this.freqTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.freqTextBox_KeyPress);
            // 
            // pictureBox2
            // 
            this.pictureBox2.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox2.Image = global::HTCommander.Properties.Resources.Signal;
            this.pictureBox2.Location = new System.Drawing.Point(427, 11);
            this.pictureBox2.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.pictureBox2.Name = "pictureBox2";
            this.pictureBox2.Size = new System.Drawing.Size(92, 64);
            this.pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox2.TabIndex = 9;
            this.pictureBox2.TabStop = false;
            // 
            // repeaterBookLinkLabel
            // 
            this.repeaterBookLinkLabel.AutoSize = true;
            this.repeaterBookLinkLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.repeaterBookLinkLabel.Location = new System.Drawing.Point(16, 49);
            this.repeaterBookLinkLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.repeaterBookLinkLabel.Name = "repeaterBookLinkLabel";
            this.repeaterBookLinkLabel.Size = new System.Drawing.Size(194, 20);
            this.repeaterBookLinkLabel.TabIndex = 0;
            this.repeaterBookLinkLabel.TabStop = true;
            this.repeaterBookLinkLabel.Text = "https://repeaterbook.com";
            this.repeaterBookLinkLabel.LinkClicked += new System.Windows.Forms.LinkLabelLinkClickedEventHandler(this.repeaterBookLinkLabel_LinkClicked);
            // 
            // advGroupBox
            // 
            this.advGroupBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.advGroupBox.Controls.Add(this.deemphasisCheckBox);
            this.advGroupBox.Controls.Add(this.label13);
            this.advGroupBox.Controls.Add(this.advBandwidthComboBox);
            this.advGroupBox.Controls.Add(this.label12);
            this.advGroupBox.Controls.Add(this.receiveCtcssComboBox);
            this.advGroupBox.Controls.Add(this.label7);
            this.advGroupBox.Controls.Add(this.transmitCtcssComboBox);
            this.advGroupBox.Controls.Add(this.advTalkAroundCheckBox);
            this.advGroupBox.Controls.Add(this.advScanCheckBox);
            this.advGroupBox.Controls.Add(this.label10);
            this.advGroupBox.Controls.Add(this.label11);
            this.advGroupBox.Controls.Add(this.advTransmitFreqTextBox);
            this.advGroupBox.Controls.Add(this.advMuteCheckBox);
            this.advGroupBox.Controls.Add(this.advDisableTransmitCheckBox);
            this.advGroupBox.Controls.Add(this.label6);
            this.advGroupBox.Controls.Add(this.advPowerComboBox);
            this.advGroupBox.Controls.Add(this.label8);
            this.advGroupBox.Controls.Add(this.label9);
            this.advGroupBox.Controls.Add(this.advNameTextBox);
            this.advGroupBox.Controls.Add(this.advModeComboBox);
            this.advGroupBox.Controls.Add(this.advReceiveFreqTextBox);
            this.advGroupBox.Location = new System.Drawing.Point(20, 372);
            this.advGroupBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advGroupBox.Name = "advGroupBox";
            this.advGroupBox.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advGroupBox.Size = new System.Drawing.Size(499, 399);
            this.advGroupBox.TabIndex = 12;
            this.advGroupBox.TabStop = false;
            this.advGroupBox.Text = "Channel";
            // 
            // deemphasisCheckBox
            // 
            this.deemphasisCheckBox.AutoSize = true;
            this.deemphasisCheckBox.Location = new System.Drawing.Point(361, 370);
            this.deemphasisCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.deemphasisCheckBox.Name = "deemphasisCheckBox";
            this.deemphasisCheckBox.Size = new System.Drawing.Size(110, 20);
            this.deemphasisCheckBox.TabIndex = 22;
            this.deemphasisCheckBox.Text = "De-emphasis";
            this.deemphasisCheckBox.UseVisualStyleBackColor = true;
            // 
            // label13
            // 
            this.label13.AutoSize = true;
            this.label13.Location = new System.Drawing.Point(8, 251);
            this.label13.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label13.Name = "label13";
            this.label13.Size = new System.Drawing.Size(69, 16);
            this.label13.TabIndex = 21;
            this.label13.Text = "Bandwidth";
            // 
            // advBandwidthComboBox
            // 
            this.advBandwidthComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.advBandwidthComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.advBandwidthComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.advBandwidthComboBox.FormattingEnabled = true;
            this.advBandwidthComboBox.Items.AddRange(new object[] {
            "25 Khz - Wide",
            "12.5 KHz - Narrow"});
            this.advBandwidthComboBox.Location = new System.Drawing.Point(215, 247);
            this.advBandwidthComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advBandwidthComboBox.Name = "advBandwidthComboBox";
            this.advBandwidthComboBox.Size = new System.Drawing.Size(275, 25);
            this.advBandwidthComboBox.TabIndex = 16;
            // 
            // label12
            // 
            this.label12.AutoSize = true;
            this.label12.Location = new System.Drawing.Point(8, 218);
            this.label12.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label12.Name = "label12";
            this.label12.Size = new System.Drawing.Size(138, 16);
            this.label12.TabIndex = 19;
            this.label12.Text = "Receive CTCSS/DCS";
            // 
            // receiveCtcssComboBox
            // 
            this.receiveCtcssComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.receiveCtcssComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.receiveCtcssComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.receiveCtcssComboBox.FormattingEnabled = true;
            this.receiveCtcssComboBox.Items.AddRange(new object[] {
            "None",
            "67.0 Hz",
            "69.3 Hz",
            "71.9 Hz",
            "74.4 Hz",
            "77.0 Hz",
            "79.7 Hz",
            "82.5 Hz",
            "85.4 Hz",
            "88.5 Hz",
            "91.5 Hz",
            "94.8 Hz",
            "97.4 Hz",
            "100.0 Hz",
            "103.5 Hz",
            "107.2 Hz",
            "110.9 Hz",
            "114.8 Hz",
            "118.8 Hz",
            "123.0 Hz",
            "127.3 Hz",
            "131.8 Hz",
            "136.5 Hz",
            "141.3 Hz",
            "146.2 Hz",
            "151.4 Hz",
            "156.7 Hz",
            "159.8 Hz",
            "162.2 Hz",
            "165.5 Hz",
            "167.9 Hz",
            "173.8 Hz",
            "177.3 Hz",
            "179.9 Hz",
            "186.2 Hz",
            "189.9 Hz",
            "192.8 Hz",
            "196.6 Hz",
            "199.5 Hz",
            "203.5 Hz",
            "206.5 Hz",
            "210.7 Hz",
            "213.8 Hz",
            "218.1 Hz",
            "221.3 Hz",
            "225.7 Hz",
            "229.1 Hz",
            "233.6 Hz",
            "237.1 Hz",
            "241.8 Hz",
            "245.5 Hz",
            "250.3 Hz",
            "254.1 Hz",
            "DCS-023N/047I",
            "DCS-025N/244I",
            "DCS-026N/464I",
            "DCS-031N/627I",
            "DCS-032N/051I",
            "DCS-036N/172I",
            "DCS-043N/445I",
            "DCS-047N/023I",
            "DCS-051N/032I",
            "DCS-053N/452I",
            "DCS-054N/413I",
            "DCS-065N/271I",
            "DCS-071N/306I",
            "DCS-072N/245I",
            "DCS-073N/506I",
            "DCS-074N/174I",
            "DCS-114N/712I",
            "DCS-115N/152I",
            "DCS-116N/754I",
            "DCS-122N/225I",
            "DCS-125N/365I",
            "DCS-131N/364I",
            "DCS-132N/546I",
            "DCS-134N/223I",
            "DCS-143N/412I",
            "DCS-145N/274I",
            "DCS-152N/115I",
            "DCS-155N/731I",
            "DCS-156N/265I",
            "DCS-162N/503I",
            "DCS-165N/251I",
            "DCS-172N/036I",
            "DCS-174N/074I",
            "DCS-205N/263I",
            "DCS-212N/356I",
            "DCS-223N/134I",
            "DCS-225N/122I",
            "DCS-226N/411I",
            "DCS-243N/351I",
            "DCS-244N/025I",
            "DCS-245N/072I",
            "DCS-246N/523I",
            "DCS-251N/165I",
            "DCS-252N/462I",
            "DCS-255N/446I",
            "DCS-261N/732I",
            "DCS-263N/205I",
            "DCS-265N/156I",
            "DCS-266N/454I",
            "DCS-271N/065I",
            "DCS-274N/145I",
            "DCS-306N/071I",
            "DCS-311N/664I",
            "DCS-315N/423I",
            "DCS-325N/526I",
            "DCS-331N/465I",
            "DCS-332N/455I",
            "DCS-343N/532I",
            "DCS-346N/612I",
            "DCS-351N/243I",
            "DCS-356N/212I",
            "DCS-364N/131I",
            "DCS-365N/125I",
            "DCS-371N/734I",
            "DCS-411N/226I",
            "DCS-412N/143I",
            "DCS-413N/054I",
            "DCS-423N/315I",
            "DCS-431N/723I",
            "DCS-432N/516I",
            "DCS-445N/043I",
            "DCS-446N/255I",
            "DCS-452N/053I",
            "DCS-454N/266I",
            "DCS-455N/332I",
            "DCS-462N/252I",
            "DCS-464N/026I",
            "DCS-465N/331I",
            "DCS-466N/662I",
            "DCS-503N/162I",
            "DCS-506N/073I",
            "DCS-516N/432I",
            "DCS-523N/246I",
            "DCS-526N/325I",
            "DCS-532N/343I",
            "DCS-546N/132I",
            "DCS-565N/703I",
            "DCS-606N/631I",
            "DCS-612N/346I",
            "DCS-624N/632I",
            "DCS-627N/031I",
            "DCS-631N/606I",
            "DCS-632N/624I",
            "DCS-654N/743I",
            "DCS-662N/466I",
            "DCS-664N/311I",
            "DCS-703N/565I",
            "DCS-712N/114I",
            "DCS-723N/431I",
            "DCS-731N/155I",
            "DCS-732N/261I",
            "DCS-734N/371I",
            "DCS-743N/654I",
            "DCS-754N/116I"});
            this.receiveCtcssComboBox.Location = new System.Drawing.Point(215, 214);
            this.receiveCtcssComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.receiveCtcssComboBox.Name = "receiveCtcssComboBox";
            this.receiveCtcssComboBox.Size = new System.Drawing.Size(275, 25);
            this.receiveCtcssComboBox.TabIndex = 15;
            // 
            // label7
            // 
            this.label7.AutoSize = true;
            this.label7.Location = new System.Drawing.Point(8, 185);
            this.label7.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(139, 16);
            this.label7.TabIndex = 17;
            this.label7.Text = "Transmit CTCSS/DCS";
            // 
            // transmitCtcssComboBox
            // 
            this.transmitCtcssComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.transmitCtcssComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.transmitCtcssComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.transmitCtcssComboBox.FormattingEnabled = true;
            this.transmitCtcssComboBox.Items.AddRange(new object[] {
            "None",
            "67.0 Hz",
            "69.3 Hz",
            "71.9 Hz",
            "74.4 Hz",
            "77.0 Hz",
            "79.7 Hz",
            "82.5 Hz",
            "85.4 Hz",
            "88.5 Hz",
            "91.5 Hz",
            "94.8 Hz",
            "97.4 Hz",
            "100.0 Hz",
            "103.5 Hz",
            "107.2 Hz",
            "110.9 Hz",
            "114.8 Hz",
            "118.8 Hz",
            "123.0 Hz",
            "127.3 Hz",
            "131.8 Hz",
            "136.5 Hz",
            "141.3 Hz",
            "146.2 Hz",
            "151.4 Hz",
            "156.7 Hz",
            "159.8 Hz",
            "162.2 Hz",
            "165.5 Hz",
            "167.9 Hz",
            "173.8 Hz",
            "177.3 Hz",
            "179.9 Hz",
            "186.2 Hz",
            "189.9 Hz",
            "192.8 Hz",
            "196.6 Hz",
            "199.5 Hz",
            "203.5 Hz",
            "206.5 Hz",
            "210.7 Hz",
            "213.8 Hz",
            "218.1 Hz",
            "221.3 Hz",
            "225.7 Hz",
            "229.1 Hz",
            "233.6 Hz",
            "237.1 Hz",
            "241.8 Hz",
            "245.5 Hz",
            "250.3 Hz",
            "254.1 Hz",
            "DCS-023N/047I",
            "DCS-025N/244I",
            "DCS-026N/464I",
            "DCS-031N/627I",
            "DCS-032N/051I",
            "DCS-036N/172I",
            "DCS-043N/445I",
            "DCS-047N/023I",
            "DCS-051N/032I",
            "DCS-053N/452I",
            "DCS-054N/413I",
            "DCS-065N/271I",
            "DCS-071N/306I",
            "DCS-072N/245I",
            "DCS-073N/506I",
            "DCS-074N/174I",
            "DCS-114N/712I",
            "DCS-115N/152I",
            "DCS-116N/754I",
            "DCS-122N/225I",
            "DCS-125N/365I",
            "DCS-131N/364I",
            "DCS-132N/546I",
            "DCS-134N/223I",
            "DCS-143N/412I",
            "DCS-145N/274I",
            "DCS-152N/115I",
            "DCS-155N/731I",
            "DCS-156N/265I",
            "DCS-162N/503I",
            "DCS-165N/251I",
            "DCS-172N/036I",
            "DCS-174N/074I",
            "DCS-205N/263I",
            "DCS-212N/356I",
            "DCS-223N/134I",
            "DCS-225N/122I",
            "DCS-226N/411I",
            "DCS-243N/351I",
            "DCS-244N/025I",
            "DCS-245N/072I",
            "DCS-246N/523I",
            "DCS-251N/165I",
            "DCS-252N/462I",
            "DCS-255N/446I",
            "DCS-261N/732I",
            "DCS-263N/205I",
            "DCS-265N/156I",
            "DCS-266N/454I",
            "DCS-271N/065I",
            "DCS-274N/145I",
            "DCS-306N/071I",
            "DCS-311N/664I",
            "DCS-315N/423I",
            "DCS-325N/526I",
            "DCS-331N/465I",
            "DCS-332N/455I",
            "DCS-343N/532I",
            "DCS-346N/612I",
            "DCS-351N/243I",
            "DCS-356N/212I",
            "DCS-364N/131I",
            "DCS-365N/125I",
            "DCS-371N/734I",
            "DCS-411N/226I",
            "DCS-412N/143I",
            "DCS-413N/054I",
            "DCS-423N/315I",
            "DCS-431N/723I",
            "DCS-432N/516I",
            "DCS-445N/043I",
            "DCS-446N/255I",
            "DCS-452N/053I",
            "DCS-454N/266I",
            "DCS-455N/332I",
            "DCS-462N/252I",
            "DCS-464N/026I",
            "DCS-465N/331I",
            "DCS-466N/662I",
            "DCS-503N/162I",
            "DCS-506N/073I",
            "DCS-516N/432I",
            "DCS-523N/246I",
            "DCS-526N/325I",
            "DCS-532N/343I",
            "DCS-546N/132I",
            "DCS-565N/703I",
            "DCS-606N/631I",
            "DCS-612N/346I",
            "DCS-624N/632I",
            "DCS-627N/031I",
            "DCS-631N/606I",
            "DCS-632N/624I",
            "DCS-654N/743I",
            "DCS-662N/466I",
            "DCS-664N/311I",
            "DCS-703N/565I",
            "DCS-712N/114I",
            "DCS-723N/431I",
            "DCS-731N/155I",
            "DCS-732N/261I",
            "DCS-734N/371I",
            "DCS-743N/654I",
            "DCS-754N/116I"});
            this.transmitCtcssComboBox.Location = new System.Drawing.Point(215, 181);
            this.transmitCtcssComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.transmitCtcssComboBox.Name = "transmitCtcssComboBox";
            this.transmitCtcssComboBox.Size = new System.Drawing.Size(275, 25);
            this.transmitCtcssComboBox.TabIndex = 14;
            // 
            // advTalkAroundCheckBox
            // 
            this.advTalkAroundCheckBox.AutoSize = true;
            this.advTalkAroundCheckBox.Location = new System.Drawing.Point(361, 342);
            this.advTalkAroundCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advTalkAroundCheckBox.Name = "advTalkAroundCheckBox";
            this.advTalkAroundCheckBox.Size = new System.Drawing.Size(102, 20);
            this.advTalkAroundCheckBox.TabIndex = 21;
            this.advTalkAroundCheckBox.Text = "Talk Around";
            this.advTalkAroundCheckBox.UseVisualStyleBackColor = true;
            // 
            // advScanCheckBox
            // 
            this.advScanCheckBox.AutoSize = true;
            this.advScanCheckBox.Location = new System.Drawing.Point(361, 314);
            this.advScanCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advScanCheckBox.Name = "advScanCheckBox";
            this.advScanCheckBox.Size = new System.Drawing.Size(60, 20);
            this.advScanCheckBox.TabIndex = 20;
            this.advScanCheckBox.Text = "Scan";
            this.advScanCheckBox.UseVisualStyleBackColor = true;
            // 
            // label10
            // 
            this.label10.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label10.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.label10.Location = new System.Drawing.Point(211, 159);
            this.label10.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label10.Name = "label10";
            this.label10.Size = new System.Drawing.Size(280, 18);
            this.label10.TabIndex = 13;
            this.label10.Text = "136 MHz - 174 MHz, 300 MHz - 550 MHz\r\n";
            // 
            // label11
            // 
            this.label11.AutoSize = true;
            this.label11.Location = new System.Drawing.Point(8, 132);
            this.label11.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label11.Name = "label11";
            this.label11.Size = new System.Drawing.Size(126, 16);
            this.label11.TabIndex = 12;
            this.label11.Text = "Transmit Frequency";
            // 
            // advTransmitFreqTextBox
            // 
            this.advTransmitFreqTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.advTransmitFreqTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.advTransmitFreqTextBox.Location = new System.Drawing.Point(215, 117);
            this.advTransmitFreqTextBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advTransmitFreqTextBox.Name = "advTransmitFreqTextBox";
            this.advTransmitFreqTextBox.Size = new System.Drawing.Size(183, 37);
            this.advTransmitFreqTextBox.TabIndex = 13;
            this.advTransmitFreqTextBox.TextChanged += new System.EventHandler(this.advTransmitFreqTextBox_TextChanged);
            this.advTransmitFreqTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.advTransmitFreqTextBox_KeyPress);
            // 
            // advMuteCheckBox
            // 
            this.advMuteCheckBox.AutoSize = true;
            this.advMuteCheckBox.Location = new System.Drawing.Point(215, 342);
            this.advMuteCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advMuteCheckBox.Name = "advMuteCheckBox";
            this.advMuteCheckBox.Size = new System.Drawing.Size(58, 20);
            this.advMuteCheckBox.TabIndex = 19;
            this.advMuteCheckBox.Text = "Mute";
            this.advMuteCheckBox.UseVisualStyleBackColor = true;
            // 
            // advDisableTransmitCheckBox
            // 
            this.advDisableTransmitCheckBox.AutoSize = true;
            this.advDisableTransmitCheckBox.Location = new System.Drawing.Point(215, 314);
            this.advDisableTransmitCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advDisableTransmitCheckBox.Name = "advDisableTransmitCheckBox";
            this.advDisableTransmitCheckBox.Size = new System.Drawing.Size(131, 20);
            this.advDisableTransmitCheckBox.TabIndex = 18;
            this.advDisableTransmitCheckBox.Text = "Disable Transmit";
            this.advDisableTransmitCheckBox.UseVisualStyleBackColor = true;
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(8, 284);
            this.label6.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(45, 16);
            this.label6.TabIndex = 7;
            this.label6.Text = "Power";
            // 
            // advPowerComboBox
            // 
            this.advPowerComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.advPowerComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.advPowerComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.advPowerComboBox.FormattingEnabled = true;
            this.advPowerComboBox.Items.AddRange(new object[] {
            "High",
            "Medium",
            "Low"});
            this.advPowerComboBox.Location = new System.Drawing.Point(215, 281);
            this.advPowerComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advPowerComboBox.Name = "advPowerComboBox";
            this.advPowerComboBox.Size = new System.Drawing.Size(275, 25);
            this.advPowerComboBox.TabIndex = 17;
            // 
            // label8
            // 
            this.label8.AutoSize = true;
            this.label8.Location = new System.Drawing.Point(8, 86);
            this.label8.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label8.Name = "label8";
            this.label8.Size = new System.Drawing.Size(125, 16);
            this.label8.TabIndex = 4;
            this.label8.Text = "Receive Frequency";
            // 
            // label9
            // 
            this.label9.AutoSize = true;
            this.label9.Location = new System.Drawing.Point(8, 38);
            this.label9.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label9.Name = "label9";
            this.label9.Size = new System.Drawing.Size(44, 16);
            this.label9.TabIndex = 3;
            this.label9.Text = "Name";
            // 
            // advNameTextBox
            // 
            this.advNameTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.advNameTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.advNameTextBox.Location = new System.Drawing.Point(215, 23);
            this.advNameTextBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advNameTextBox.MaxLength = 10;
            this.advNameTextBox.Name = "advNameTextBox";
            this.advNameTextBox.Size = new System.Drawing.Size(275, 37);
            this.advNameTextBox.TabIndex = 10;
            // 
            // advModeComboBox
            // 
            this.advModeComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.advModeComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.advModeComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.advModeComboBox.FormattingEnabled = true;
            this.advModeComboBox.Items.AddRange(new object[] {
            "FM",
            "AM"});
            this.advModeComboBox.Location = new System.Drawing.Point(409, 69);
            this.advModeComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advModeComboBox.Name = "advModeComboBox";
            this.advModeComboBox.Size = new System.Drawing.Size(80, 38);
            this.advModeComboBox.TabIndex = 12;
            // 
            // advReceiveFreqTextBox
            // 
            this.advReceiveFreqTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.advReceiveFreqTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.advReceiveFreqTextBox.Location = new System.Drawing.Point(215, 71);
            this.advReceiveFreqTextBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.advReceiveFreqTextBox.Name = "advReceiveFreqTextBox";
            this.advReceiveFreqTextBox.Size = new System.Drawing.Size(183, 37);
            this.advReceiveFreqTextBox.TabIndex = 11;
            this.advReceiveFreqTextBox.TextChanged += new System.EventHandler(this.advReceiveFreqTextBox_TextChanged);
            this.advReceiveFreqTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.advReceiveFreqTextBox_KeyPress);
            // 
            // okButton
            // 
            this.okButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.okButton.Location = new System.Drawing.Point(311, 778);
            this.okButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.okButton.Name = "okButton";
            this.okButton.Size = new System.Drawing.Size(100, 28);
            this.okButton.TabIndex = 31;
            this.okButton.Text = "OK";
            this.okButton.UseVisualStyleBackColor = true;
            this.okButton.Click += new System.EventHandler(this.okButton_Click);
            // 
            // clearButton
            // 
            this.clearButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.clearButton.Location = new System.Drawing.Point(20, 779);
            this.clearButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.clearButton.Name = "clearButton";
            this.clearButton.Size = new System.Drawing.Size(100, 28);
            this.clearButton.TabIndex = 30;
            this.clearButton.Text = "Clear";
            this.clearButton.UseVisualStyleBackColor = true;
            this.clearButton.Click += new System.EventHandler(this.clearButton_Click);
            // 
            // RadioChannelForm
            // 
            this.AcceptButton = this.okButton;
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.cancelButton;
            this.ClientSize = new System.Drawing.Size(535, 822);
            this.Controls.Add(this.clearButton);
            this.Controls.Add(this.okButton);
            this.Controls.Add(this.advGroupBox);
            this.Controls.Add(this.repeaterBookLinkLabel);
            this.Controls.Add(this.pictureBox2);
            this.Controls.Add(this.label4);
            this.Controls.Add(this.basicGroupBox);
            this.Controls.Add(this.cancelButton);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "RadioChannelForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Channel";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.RadioChannelForm_FormClosing);
            this.Load += new System.EventHandler(this.RadioInfoForm_Load);
            this.basicGroupBox.ResumeLayout(false);
            this.basicGroupBox.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).EndInit();
            this.advGroupBox.ResumeLayout(false);
            this.advGroupBox.PerformLayout();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.GroupBox basicGroupBox;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.TextBox nameTextBox;
        private System.Windows.Forms.ComboBox modeComboBox;
        private System.Windows.Forms.TextBox freqTextBox;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.ComboBox powerComboBox;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.CheckBox muteCheckBox;
        private System.Windows.Forms.CheckBox disableTransmitCheckBox;
        private System.Windows.Forms.LinkLabel repeaterBookLinkLabel;
        private System.Windows.Forms.Button moreSettingsButton;
        private System.Windows.Forms.GroupBox advGroupBox;
        private System.Windows.Forms.Label label10;
        private System.Windows.Forms.Label label11;
        private System.Windows.Forms.TextBox advTransmitFreqTextBox;
        private System.Windows.Forms.CheckBox advMuteCheckBox;
        private System.Windows.Forms.CheckBox advDisableTransmitCheckBox;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.ComboBox advPowerComboBox;
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.Label label9;
        private System.Windows.Forms.TextBox advNameTextBox;
        private System.Windows.Forms.ComboBox advModeComboBox;
        private System.Windows.Forms.TextBox advReceiveFreqTextBox;
        private System.Windows.Forms.CheckBox advTalkAroundCheckBox;
        private System.Windows.Forms.CheckBox advScanCheckBox;
        private System.Windows.Forms.Label label13;
        private System.Windows.Forms.ComboBox advBandwidthComboBox;
        private System.Windows.Forms.Label label12;
        private System.Windows.Forms.ComboBox receiveCtcssComboBox;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.ComboBox transmitCtcssComboBox;
        private System.Windows.Forms.Button okButton;
        private System.Windows.Forms.CheckBox deemphasisCheckBox;
        private System.Windows.Forms.Button clearButton;
    }
}