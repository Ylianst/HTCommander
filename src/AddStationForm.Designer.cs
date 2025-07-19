namespace HTCommander
{
    partial class AddStationForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(AddStationForm));
            this.nextButton = new System.Windows.Forms.Button();
            this.cancelButton = new System.Windows.Forms.Button();
            this.backButton = new System.Windows.Forms.Button();
            this.mainTabControl = new HTCommander.NoTabsTabControl();
            this.stationTabPage = new System.Windows.Forms.TabPage();
            this.typeOfStationLabel = new System.Windows.Forms.Label();
            this.label7 = new System.Windows.Forms.Label();
            this.stationTypeLabel = new System.Windows.Forms.Label();
            this.label4 = new System.Windows.Forms.Label();
            this.stationTypeComboBox = new System.Windows.Forms.ComboBox();
            this.callsignTextBox = new System.Windows.Forms.TextBox();
            this.label3 = new System.Windows.Forms.Label();
            this.pictureBox2 = new System.Windows.Forms.PictureBox();
            this.label1 = new System.Windows.Forms.Label();
            this.desciptionTextBox = new System.Windows.Forms.TextBox();
            this.nameTextBox = new System.Windows.Forms.TextBox();
            this.label2 = new System.Windows.Forms.Label();
            this.aprsTabPage = new System.Windows.Forms.TabPage();
            this.authCheckBox = new System.Windows.Forms.CheckBox();
            this.label18 = new System.Windows.Forms.Label();
            this.authPasswordTextBox = new System.Windows.Forms.TextBox();
            this.label9 = new System.Windows.Forms.Label();
            this.label6 = new System.Windows.Forms.Label();
            this.aprsRouteComboBox = new System.Windows.Forms.ComboBox();
            this.pictureBox1 = new System.Windows.Forms.PictureBox();
            this.terminalTabPage = new System.Windows.Forms.TabPage();
            this.label13 = new System.Windows.Forms.Label();
            this.ax25DestTextBox = new System.Windows.Forms.TextBox();
            this.label14 = new System.Windows.Forms.Label();
            this.label12 = new System.Windows.Forms.Label();
            this.channelsComboBox = new System.Windows.Forms.ComboBox();
            this.label11 = new System.Windows.Forms.Label();
            this.terminalProtocolComboBox = new System.Windows.Forms.ComboBox();
            this.label10 = new System.Windows.Forms.Label();
            this.pictureBox3 = new System.Windows.Forms.PictureBox();
            this.winLinkTabPage = new System.Windows.Forms.TabPage();
            this.label16 = new System.Windows.Forms.Label();
            this.label15 = new System.Windows.Forms.Label();
            this.linkLabel1 = new System.Windows.Forms.LinkLabel();
            this.label5 = new System.Windows.Forms.Label();
            this.channelsComboBox2 = new System.Windows.Forms.ComboBox();
            this.label8 = new System.Windows.Forms.Label();
            this.pictureBox4 = new System.Windows.Forms.PictureBox();
            this.mainTabControl.SuspendLayout();
            this.stationTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).BeginInit();
            this.aprsTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).BeginInit();
            this.terminalTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox3)).BeginInit();
            this.winLinkTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox4)).BeginInit();
            this.SuspendLayout();
            // 
            // nextButton
            // 
            this.nextButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.nextButton.Enabled = false;
            this.nextButton.Location = new System.Drawing.Point(233, 255);
            this.nextButton.Name = "nextButton";
            this.nextButton.Size = new System.Drawing.Size(75, 23);
            this.nextButton.TabIndex = 101;
            this.nextButton.Text = "Next";
            this.nextButton.UseVisualStyleBackColor = true;
            this.nextButton.Click += new System.EventHandler(this.nextButton_Click);
            // 
            // cancelButton
            // 
            this.cancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.cancelButton.Location = new System.Drawing.Point(314, 255);
            this.cancelButton.Name = "cancelButton";
            this.cancelButton.Size = new System.Drawing.Size(75, 23);
            this.cancelButton.TabIndex = 102;
            this.cancelButton.Text = "Cancel";
            this.cancelButton.UseVisualStyleBackColor = true;
            this.cancelButton.Click += new System.EventHandler(this.cancelButton_Click);
            // 
            // backButton
            // 
            this.backButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.backButton.Enabled = false;
            this.backButton.Location = new System.Drawing.Point(152, 255);
            this.backButton.Name = "backButton";
            this.backButton.Size = new System.Drawing.Size(75, 23);
            this.backButton.TabIndex = 100;
            this.backButton.Text = "Back";
            this.backButton.UseVisualStyleBackColor = true;
            this.backButton.Click += new System.EventHandler(this.backButton_Click);
            // 
            // mainTabControl
            // 
            this.mainTabControl.Controls.Add(this.stationTabPage);
            this.mainTabControl.Controls.Add(this.aprsTabPage);
            this.mainTabControl.Controls.Add(this.terminalTabPage);
            this.mainTabControl.Controls.Add(this.winLinkTabPage);
            this.mainTabControl.Location = new System.Drawing.Point(12, 12);
            this.mainTabControl.Name = "mainTabControl";
            this.mainTabControl.SelectedIndex = 0;
            this.mainTabControl.Size = new System.Drawing.Size(377, 237);
            this.mainTabControl.TabIndex = 22;
            // 
            // stationTabPage
            // 
            this.stationTabPage.Controls.Add(this.typeOfStationLabel);
            this.stationTabPage.Controls.Add(this.label7);
            this.stationTabPage.Controls.Add(this.stationTypeLabel);
            this.stationTabPage.Controls.Add(this.label4);
            this.stationTabPage.Controls.Add(this.stationTypeComboBox);
            this.stationTabPage.Controls.Add(this.callsignTextBox);
            this.stationTabPage.Controls.Add(this.label3);
            this.stationTabPage.Controls.Add(this.pictureBox2);
            this.stationTabPage.Controls.Add(this.label1);
            this.stationTabPage.Controls.Add(this.desciptionTextBox);
            this.stationTabPage.Controls.Add(this.nameTextBox);
            this.stationTabPage.Controls.Add(this.label2);
            this.stationTabPage.Location = new System.Drawing.Point(4, 22);
            this.stationTabPage.Name = "stationTabPage";
            this.stationTabPage.Padding = new System.Windows.Forms.Padding(3);
            this.stationTabPage.Size = new System.Drawing.Size(369, 211);
            this.stationTabPage.TabIndex = 0;
            this.stationTabPage.Text = "Station";
            this.stationTabPage.UseVisualStyleBackColor = true;
            // 
            // typeOfStationLabel
            // 
            this.typeOfStationLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.typeOfStationLabel.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.typeOfStationLabel.Location = new System.Drawing.Point(126, 178);
            this.typeOfStationLabel.Name = "typeOfStationLabel";
            this.typeOfStationLabel.Size = new System.Drawing.Size(201, 20);
            this.typeOfStationLabel.TabIndex = 19;
            this.typeOfStationLabel.Text = "Type of station";
            // 
            // label7
            // 
            this.label7.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label7.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.label7.Location = new System.Drawing.Point(126, 79);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(201, 20);
            this.label7.TabIndex = 18;
            this.label7.Text = "Enter Callsign - Station ID";
            // 
            // stationTypeLabel
            // 
            this.stationTypeLabel.AutoSize = true;
            this.stationTypeLabel.Location = new System.Drawing.Point(6, 157);
            this.stationTypeLabel.Name = "stationTypeLabel";
            this.stationTypeLabel.Size = new System.Drawing.Size(67, 13);
            this.stationTypeLabel.TabIndex = 7;
            this.stationTypeLabel.Text = "Station Type";
            // 
            // label4
            // 
            this.label4.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label4.Location = new System.Drawing.Point(6, 6);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(291, 34);
            this.label4.TabIndex = 16;
            this.label4.Text = "Setup station settings here to manage and quickly communicate with them.";
            // 
            // stationTypeComboBox
            // 
            this.stationTypeComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.stationTypeComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.stationTypeComboBox.FormattingEnabled = true;
            this.stationTypeComboBox.Items.AddRange(new object[] {
            "Generic",
            "APRS Station",
            "Terminal Station (BBS)",
            "Winlink Gateway (Mail)"});
            this.stationTypeComboBox.Location = new System.Drawing.Point(126, 154);
            this.stationTypeComboBox.Name = "stationTypeComboBox";
            this.stationTypeComboBox.Size = new System.Drawing.Size(227, 21);
            this.stationTypeComboBox.TabIndex = 13;
            this.stationTypeComboBox.SelectedIndexChanged += new System.EventHandler(this.stationTypeComboBox_SelectedIndexChanged);
            // 
            // callsignTextBox
            // 
            this.callsignTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.callsignTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.callsignTextBox.Location = new System.Drawing.Point(126, 54);
            this.callsignTextBox.MaxLength = 9;
            this.callsignTextBox.Name = "callsignTextBox";
            this.callsignTextBox.Size = new System.Drawing.Size(227, 22);
            this.callsignTextBox.TabIndex = 10;
            this.callsignTextBox.TextChanged += new System.EventHandler(this.callsignTextBox_TextChanged);
            this.callsignTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.callsignTextBox_KeyPress);
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(6, 131);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(60, 13);
            this.label3.TabIndex = 5;
            this.label3.Text = "Description";
            // 
            // pictureBox2
            // 
            this.pictureBox2.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox2.Image = global::HTCommander.Properties.Resources.Signal;
            this.pictureBox2.Location = new System.Drawing.Point(303, 6);
            this.pictureBox2.Name = "pictureBox2";
            this.pictureBox2.Size = new System.Drawing.Size(50, 34);
            this.pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox2.TabIndex = 17;
            this.pictureBox2.TabStop = false;
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(6, 59);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(46, 13);
            this.label1.TabIndex = 1;
            this.label1.Text = "Call sign";
            // 
            // desciptionTextBox
            // 
            this.desciptionTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.desciptionTextBox.Location = new System.Drawing.Point(126, 128);
            this.desciptionTextBox.MaxLength = 256;
            this.desciptionTextBox.Name = "desciptionTextBox";
            this.desciptionTextBox.Size = new System.Drawing.Size(227, 20);
            this.desciptionTextBox.TabIndex = 12;
            // 
            // nameTextBox
            // 
            this.nameTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.nameTextBox.Location = new System.Drawing.Point(126, 102);
            this.nameTextBox.MaxLength = 32;
            this.nameTextBox.Name = "nameTextBox";
            this.nameTextBox.Size = new System.Drawing.Size(227, 20);
            this.nameTextBox.TabIndex = 11;
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(6, 105);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(35, 13);
            this.label2.TabIndex = 3;
            this.label2.Text = "Name";
            // 
            // aprsTabPage
            // 
            this.aprsTabPage.Controls.Add(this.authCheckBox);
            this.aprsTabPage.Controls.Add(this.label18);
            this.aprsTabPage.Controls.Add(this.authPasswordTextBox);
            this.aprsTabPage.Controls.Add(this.label9);
            this.aprsTabPage.Controls.Add(this.label6);
            this.aprsTabPage.Controls.Add(this.aprsRouteComboBox);
            this.aprsTabPage.Controls.Add(this.pictureBox1);
            this.aprsTabPage.Location = new System.Drawing.Point(4, 22);
            this.aprsTabPage.Name = "aprsTabPage";
            this.aprsTabPage.Padding = new System.Windows.Forms.Padding(3);
            this.aprsTabPage.Size = new System.Drawing.Size(369, 211);
            this.aprsTabPage.TabIndex = 1;
            this.aprsTabPage.Text = "APRS";
            this.aprsTabPage.UseVisualStyleBackColor = true;
            // 
            // authCheckBox
            // 
            this.authCheckBox.AutoSize = true;
            this.authCheckBox.Location = new System.Drawing.Point(129, 106);
            this.authCheckBox.Name = "authCheckBox";
            this.authCheckBox.Size = new System.Drawing.Size(116, 17);
            this.authCheckBox.TabIndex = 24;
            this.authCheckBox.Text = "Use Authentication";
            this.authCheckBox.UseVisualStyleBackColor = true;
            this.authCheckBox.CheckedChanged += new System.EventHandler(this.authCheckBox_CheckedChanged);
            // 
            // label18
            // 
            this.label18.AutoSize = true;
            this.label18.Location = new System.Drawing.Point(10, 132);
            this.label18.Name = "label18";
            this.label18.Size = new System.Drawing.Size(78, 13);
            this.label18.TabIndex = 23;
            this.label18.Text = "Auth Password";
            // 
            // authPasswordTextBox
            // 
            this.authPasswordTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.authPasswordTextBox.Enabled = false;
            this.authPasswordTextBox.Location = new System.Drawing.Point(129, 129);
            this.authPasswordTextBox.Name = "authPasswordTextBox";
            this.authPasswordTextBox.PasswordChar = '';
            this.authPasswordTextBox.Size = new System.Drawing.Size(224, 20);
            this.authPasswordTextBox.TabIndex = 21;
            this.authPasswordTextBox.TextChanged += new System.EventHandler(this.authPasswordTextBox_TextChanged);
            // 
            // label9
            // 
            this.label9.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label9.Location = new System.Drawing.Point(6, 6);
            this.label9.Name = "label9";
            this.label9.Size = new System.Drawing.Size(289, 34);
            this.label9.TabIndex = 18;
            this.label9.Text = "APRS stations can use prefered relay routes.";
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(9, 60);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(79, 13);
            this.label6.TabIndex = 7;
            this.label6.Text = "Prefered Route";
            // 
            // aprsRouteComboBox
            // 
            this.aprsRouteComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsRouteComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.aprsRouteComboBox.FormattingEnabled = true;
            this.aprsRouteComboBox.Location = new System.Drawing.Point(129, 57);
            this.aprsRouteComboBox.Name = "aprsRouteComboBox";
            this.aprsRouteComboBox.Size = new System.Drawing.Size(224, 21);
            this.aprsRouteComboBox.TabIndex = 20;
            // 
            // pictureBox1
            // 
            this.pictureBox1.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox1.Image = global::HTCommander.Properties.Resources.MapPoint1;
            this.pictureBox1.Location = new System.Drawing.Point(303, 6);
            this.pictureBox1.Name = "pictureBox1";
            this.pictureBox1.Size = new System.Drawing.Size(50, 34);
            this.pictureBox1.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox1.TabIndex = 19;
            this.pictureBox1.TabStop = false;
            // 
            // terminalTabPage
            // 
            this.terminalTabPage.Controls.Add(this.label13);
            this.terminalTabPage.Controls.Add(this.ax25DestTextBox);
            this.terminalTabPage.Controls.Add(this.label14);
            this.terminalTabPage.Controls.Add(this.label12);
            this.terminalTabPage.Controls.Add(this.channelsComboBox);
            this.terminalTabPage.Controls.Add(this.label11);
            this.terminalTabPage.Controls.Add(this.terminalProtocolComboBox);
            this.terminalTabPage.Controls.Add(this.label10);
            this.terminalTabPage.Controls.Add(this.pictureBox3);
            this.terminalTabPage.Location = new System.Drawing.Point(4, 22);
            this.terminalTabPage.Name = "terminalTabPage";
            this.terminalTabPage.Size = new System.Drawing.Size(369, 211);
            this.terminalTabPage.TabIndex = 2;
            this.terminalTabPage.Text = "Terminal";
            this.terminalTabPage.UseVisualStyleBackColor = true;
            // 
            // label13
            // 
            this.label13.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label13.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.label13.Location = new System.Drawing.Point(126, 134);
            this.label13.Name = "label13";
            this.label13.Size = new System.Drawing.Size(227, 20);
            this.label13.TabIndex = 28;
            this.label13.Text = "Enter callsign-id";
            // 
            // ax25DestTextBox
            // 
            this.ax25DestTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.ax25DestTextBox.Location = new System.Drawing.Point(129, 111);
            this.ax25DestTextBox.MaxLength = 9;
            this.ax25DestTextBox.Name = "ax25DestTextBox";
            this.ax25DestTextBox.Size = new System.Drawing.Size(224, 20);
            this.ax25DestTextBox.TabIndex = 33;
            this.ax25DestTextBox.TextChanged += new System.EventHandler(this.ax25DestTextBox_TextChanged);
            this.ax25DestTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.ax25DestTextBox_KeyPress);
            // 
            // label14
            // 
            this.label14.AutoSize = true;
            this.label14.Location = new System.Drawing.Point(9, 114);
            this.label14.Name = "label14";
            this.label14.Size = new System.Drawing.Size(92, 13);
            this.label14.TabIndex = 27;
            this.label14.Text = "AX.25 Destination";
            // 
            // label12
            // 
            this.label12.AutoSize = true;
            this.label12.Location = new System.Drawing.Point(9, 87);
            this.label12.Name = "label12";
            this.label12.Size = new System.Drawing.Size(46, 13);
            this.label12.TabIndex = 25;
            this.label12.Text = "Channel";
            // 
            // channelsComboBox
            // 
            this.channelsComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.channelsComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.channelsComboBox.FormattingEnabled = true;
            this.channelsComboBox.Location = new System.Drawing.Point(129, 84);
            this.channelsComboBox.Name = "channelsComboBox";
            this.channelsComboBox.Size = new System.Drawing.Size(224, 21);
            this.channelsComboBox.TabIndex = 32;
            this.channelsComboBox.SelectedIndexChanged += new System.EventHandler(this.channelsComboBox_SelectedIndexChanged);
            this.channelsComboBox.TextChanged += new System.EventHandler(this.channelsComboBox_TextChanged);
            // 
            // label11
            // 
            this.label11.AutoSize = true;
            this.label11.Location = new System.Drawing.Point(9, 60);
            this.label11.Name = "label11";
            this.label11.Size = new System.Drawing.Size(46, 13);
            this.label11.TabIndex = 23;
            this.label11.Text = "Protocol";
            // 
            // terminalProtocolComboBox
            // 
            this.terminalProtocolComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalProtocolComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.terminalProtocolComboBox.FormattingEnabled = true;
            this.terminalProtocolComboBox.Items.AddRange(new object[] {
            "Raw AX.25 Frames",
            "APRS Packets",
            "Raw AX.25 + Compression",
            "AX.25 Session"});
            this.terminalProtocolComboBox.Location = new System.Drawing.Point(129, 57);
            this.terminalProtocolComboBox.Name = "terminalProtocolComboBox";
            this.terminalProtocolComboBox.Size = new System.Drawing.Size(224, 21);
            this.terminalProtocolComboBox.TabIndex = 31;
            this.terminalProtocolComboBox.SelectedIndexChanged += new System.EventHandler(this.terminalProtocolComboBox_SelectedIndexChanged);
            // 
            // label10
            // 
            this.label10.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label10.Location = new System.Drawing.Point(6, 6);
            this.label10.Name = "label10";
            this.label10.Size = new System.Drawing.Size(289, 34);
            this.label10.TabIndex = 20;
            this.label10.Text = "Select the station\'s terminal protocol, channel and settings";
            // 
            // pictureBox3
            // 
            this.pictureBox3.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox3.Image = global::HTCommander.Properties.Resources.Terminal;
            this.pictureBox3.Location = new System.Drawing.Point(303, 6);
            this.pictureBox3.Name = "pictureBox3";
            this.pictureBox3.Size = new System.Drawing.Size(50, 34);
            this.pictureBox3.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox3.TabIndex = 21;
            this.pictureBox3.TabStop = false;
            // 
            // winLinkTabPage
            // 
            this.winLinkTabPage.Controls.Add(this.label16);
            this.winLinkTabPage.Controls.Add(this.label15);
            this.winLinkTabPage.Controls.Add(this.linkLabel1);
            this.winLinkTabPage.Controls.Add(this.label5);
            this.winLinkTabPage.Controls.Add(this.channelsComboBox2);
            this.winLinkTabPage.Controls.Add(this.label8);
            this.winLinkTabPage.Controls.Add(this.pictureBox4);
            this.winLinkTabPage.Location = new System.Drawing.Point(4, 22);
            this.winLinkTabPage.Margin = new System.Windows.Forms.Padding(2);
            this.winLinkTabPage.Name = "winLinkTabPage";
            this.winLinkTabPage.Size = new System.Drawing.Size(369, 211);
            this.winLinkTabPage.TabIndex = 3;
            this.winLinkTabPage.Text = "Winlink";
            this.winLinkTabPage.UseVisualStyleBackColor = true;
            // 
            // label16
            // 
            this.label16.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.label16.AutoSize = true;
            this.label16.Location = new System.Drawing.Point(8, 187);
            this.label16.Margin = new System.Windows.Forms.Padding(2, 0, 2, 0);
            this.label16.Name = "label16";
            this.label16.Size = new System.Drawing.Size(181, 13);
            this.label16.TabIndex = 39;
            this.label16.Text = "Click \"Packet\" at the top of the map.";
            // 
            // label15
            // 
            this.label15.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.label15.AutoSize = true;
            this.label15.Location = new System.Drawing.Point(8, 150);
            this.label15.Margin = new System.Windows.Forms.Padding(2, 0, 2, 0);
            this.label15.Name = "label15";
            this.label15.Size = new System.Drawing.Size(148, 13);
            this.label15.TabIndex = 38;
            this.label15.Text = "Find gateways in your area at:";
            // 
            // linkLabel1
            // 
            this.linkLabel1.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.linkLabel1.AutoSize = true;
            this.linkLabel1.Location = new System.Drawing.Point(8, 167);
            this.linkLabel1.Margin = new System.Windows.Forms.Padding(2, 0, 2, 0);
            this.linkLabel1.Name = "linkLabel1";
            this.linkLabel1.Size = new System.Drawing.Size(191, 13);
            this.linkLabel1.TabIndex = 37;
            this.linkLabel1.TabStop = true;
            this.linkLabel1.Text = "winlink.org/content/gateway_locations";
            this.linkLabel1.LinkClicked += new System.Windows.Forms.LinkLabelLinkClickedEventHandler(this.linkLabel1_LinkClicked);
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(8, 58);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(46, 13);
            this.label5.TabIndex = 35;
            this.label5.Text = "Channel";
            // 
            // channelsComboBox2
            // 
            this.channelsComboBox2.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.channelsComboBox2.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.channelsComboBox2.FormattingEnabled = true;
            this.channelsComboBox2.Location = new System.Drawing.Point(128, 55);
            this.channelsComboBox2.Name = "channelsComboBox2";
            this.channelsComboBox2.Size = new System.Drawing.Size(224, 21);
            this.channelsComboBox2.TabIndex = 36;
            // 
            // label8
            // 
            this.label8.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label8.Location = new System.Drawing.Point(5, 6);
            this.label8.Name = "label8";
            this.label8.Size = new System.Drawing.Size(289, 34);
            this.label8.TabIndex = 33;
            this.label8.Text = "A Winlink gateway in your area can be used to send and receive emails from the In" +
    "ternet using your radio.";
            // 
            // pictureBox4
            // 
            this.pictureBox4.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox4.Image = global::HTCommander.Properties.Resources.Letter;
            this.pictureBox4.Location = new System.Drawing.Point(302, 6);
            this.pictureBox4.Name = "pictureBox4";
            this.pictureBox4.Size = new System.Drawing.Size(50, 34);
            this.pictureBox4.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox4.TabIndex = 34;
            this.pictureBox4.TabStop = false;
            // 
            // AddStationForm
            // 
            this.AcceptButton = this.nextButton;
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.cancelButton;
            this.ClientSize = new System.Drawing.Size(401, 290);
            this.Controls.Add(this.backButton);
            this.Controls.Add(this.mainTabControl);
            this.Controls.Add(this.nextButton);
            this.Controls.Add(this.cancelButton);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "AddStationForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Station";
            this.Load += new System.EventHandler(this.AddStationForm_Load);
            this.mainTabControl.ResumeLayout(false);
            this.stationTabPage.ResumeLayout(false);
            this.stationTabPage.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).EndInit();
            this.aprsTabPage.ResumeLayout(false);
            this.aprsTabPage.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).EndInit();
            this.terminalTabPage.ResumeLayout(false);
            this.terminalTabPage.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox3)).EndInit();
            this.winLinkTabPage.ResumeLayout(false);
            this.winLinkTabPage.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox4)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.TextBox desciptionTextBox;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.TextBox nameTextBox;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.TextBox callsignTextBox;
        private System.Windows.Forms.Button nextButton;
        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.Label stationTypeLabel;
        private System.Windows.Forms.ComboBox stationTypeComboBox;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.ComboBox aprsRouteComboBox;
        private System.Windows.Forms.TabPage stationTabPage;
        private System.Windows.Forms.TabPage aprsTabPage;
        private System.Windows.Forms.TabPage terminalTabPage;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.Label typeOfStationLabel;
        private System.Windows.Forms.Label label9;
        private System.Windows.Forms.PictureBox pictureBox1;
        private System.Windows.Forms.Label label11;
        private System.Windows.Forms.ComboBox terminalProtocolComboBox;
        private System.Windows.Forms.Label label10;
        private System.Windows.Forms.PictureBox pictureBox3;
        private System.Windows.Forms.Button backButton;
        private System.Windows.Forms.Label label12;
        private System.Windows.Forms.ComboBox channelsComboBox;
        private NoTabsTabControl mainTabControl;
        private System.Windows.Forms.Label label13;
        private System.Windows.Forms.TextBox ax25DestTextBox;
        private System.Windows.Forms.Label label14;
        private System.Windows.Forms.TabPage winLinkTabPage;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.ComboBox channelsComboBox2;
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.PictureBox pictureBox4;
        private System.Windows.Forms.LinkLabel linkLabel1;
        private System.Windows.Forms.Label label15;
        private System.Windows.Forms.Label label16;
        private System.Windows.Forms.TextBox authPasswordTextBox;
        private System.Windows.Forms.CheckBox authCheckBox;
        private System.Windows.Forms.Label label18;
    }
}