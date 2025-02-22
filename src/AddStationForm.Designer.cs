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
            this.mainTabControl.SuspendLayout();
            this.stationTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).BeginInit();
            this.aprsTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).BeginInit();
            this.terminalTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox3)).BeginInit();
            this.SuspendLayout();
            // 
            // nextButton
            // 
            this.nextButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.nextButton.Enabled = false;
            this.nextButton.Location = new System.Drawing.Point(311, 314);
            this.nextButton.Margin = new System.Windows.Forms.Padding(4);
            this.nextButton.Name = "nextButton";
            this.nextButton.Size = new System.Drawing.Size(100, 28);
            this.nextButton.TabIndex = 101;
            this.nextButton.Text = "Next";
            this.nextButton.UseVisualStyleBackColor = true;
            this.nextButton.Click += new System.EventHandler(this.nextButton_Click);
            // 
            // cancelButton
            // 
            this.cancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.cancelButton.Location = new System.Drawing.Point(419, 314);
            this.cancelButton.Margin = new System.Windows.Forms.Padding(4);
            this.cancelButton.Name = "cancelButton";
            this.cancelButton.Size = new System.Drawing.Size(100, 28);
            this.cancelButton.TabIndex = 102;
            this.cancelButton.Text = "Cancel";
            this.cancelButton.UseVisualStyleBackColor = true;
            this.cancelButton.Click += new System.EventHandler(this.cancelButton_Click);
            // 
            // backButton
            // 
            this.backButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.backButton.Enabled = false;
            this.backButton.Location = new System.Drawing.Point(203, 314);
            this.backButton.Margin = new System.Windows.Forms.Padding(4);
            this.backButton.Name = "backButton";
            this.backButton.Size = new System.Drawing.Size(100, 28);
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
            this.mainTabControl.Location = new System.Drawing.Point(16, 15);
            this.mainTabControl.Margin = new System.Windows.Forms.Padding(4);
            this.mainTabControl.Name = "mainTabControl";
            this.mainTabControl.SelectedIndex = 0;
            this.mainTabControl.Size = new System.Drawing.Size(503, 292);
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
            this.stationTabPage.Location = new System.Drawing.Point(4, 25);
            this.stationTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.stationTabPage.Name = "stationTabPage";
            this.stationTabPage.Padding = new System.Windows.Forms.Padding(4);
            this.stationTabPage.Size = new System.Drawing.Size(495, 263);
            this.stationTabPage.TabIndex = 0;
            this.stationTabPage.Text = "Station";
            this.stationTabPage.UseVisualStyleBackColor = true;
            // 
            // typeOfStationLabel
            // 
            this.typeOfStationLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.typeOfStationLabel.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.typeOfStationLabel.Location = new System.Drawing.Point(168, 219);
            this.typeOfStationLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.typeOfStationLabel.Name = "typeOfStationLabel";
            this.typeOfStationLabel.Size = new System.Drawing.Size(268, 25);
            this.typeOfStationLabel.TabIndex = 19;
            this.typeOfStationLabel.Text = "Type of station";
            // 
            // label7
            // 
            this.label7.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label7.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.label7.Location = new System.Drawing.Point(168, 97);
            this.label7.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(268, 25);
            this.label7.TabIndex = 18;
            this.label7.Text = "Enter Callsign - Station ID";
            // 
            // stationTypeLabel
            // 
            this.stationTypeLabel.AutoSize = true;
            this.stationTypeLabel.Location = new System.Drawing.Point(8, 193);
            this.stationTypeLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.stationTypeLabel.Name = "stationTypeLabel";
            this.stationTypeLabel.Size = new System.Drawing.Size(83, 16);
            this.stationTypeLabel.TabIndex = 7;
            this.stationTypeLabel.Text = "Station Type";
            // 
            // label4
            // 
            this.label4.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label4.Location = new System.Drawing.Point(8, 7);
            this.label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(388, 42);
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
            "Terminal Station (BBS)"});
            this.stationTypeComboBox.Location = new System.Drawing.Point(168, 190);
            this.stationTypeComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.stationTypeComboBox.Name = "stationTypeComboBox";
            this.stationTypeComboBox.Size = new System.Drawing.Size(301, 24);
            this.stationTypeComboBox.TabIndex = 13;
            this.stationTypeComboBox.SelectedIndexChanged += new System.EventHandler(this.stationTypeComboBox_SelectedIndexChanged);
            // 
            // callsignTextBox
            // 
            this.callsignTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.callsignTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.callsignTextBox.Location = new System.Drawing.Point(168, 66);
            this.callsignTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.callsignTextBox.MaxLength = 9;
            this.callsignTextBox.Name = "callsignTextBox";
            this.callsignTextBox.Size = new System.Drawing.Size(301, 26);
            this.callsignTextBox.TabIndex = 10;
            this.callsignTextBox.TextChanged += new System.EventHandler(this.callsignTextBox_TextChanged);
            this.callsignTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.callsignTextBox_KeyPress);
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(8, 161);
            this.label3.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(75, 16);
            this.label3.TabIndex = 5;
            this.label3.Text = "Description";
            // 
            // pictureBox2
            // 
            this.pictureBox2.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox2.Image = global::HTCommander.Properties.Resources.Signal;
            this.pictureBox2.Location = new System.Drawing.Point(404, 7);
            this.pictureBox2.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox2.Name = "pictureBox2";
            this.pictureBox2.Size = new System.Drawing.Size(67, 42);
            this.pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox2.TabIndex = 17;
            this.pictureBox2.TabStop = false;
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(8, 73);
            this.label1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(58, 16);
            this.label1.TabIndex = 1;
            this.label1.Text = "Call sign";
            // 
            // desciptionTextBox
            // 
            this.desciptionTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.desciptionTextBox.Location = new System.Drawing.Point(168, 158);
            this.desciptionTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.desciptionTextBox.MaxLength = 256;
            this.desciptionTextBox.Name = "desciptionTextBox";
            this.desciptionTextBox.Size = new System.Drawing.Size(301, 22);
            this.desciptionTextBox.TabIndex = 12;
            // 
            // nameTextBox
            // 
            this.nameTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.nameTextBox.Location = new System.Drawing.Point(168, 126);
            this.nameTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.nameTextBox.MaxLength = 32;
            this.nameTextBox.Name = "nameTextBox";
            this.nameTextBox.Size = new System.Drawing.Size(301, 22);
            this.nameTextBox.TabIndex = 11;
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(8, 129);
            this.label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(44, 16);
            this.label2.TabIndex = 3;
            this.label2.Text = "Name";
            // 
            // aprsTabPage
            // 
            this.aprsTabPage.Controls.Add(this.label9);
            this.aprsTabPage.Controls.Add(this.label6);
            this.aprsTabPage.Controls.Add(this.aprsRouteComboBox);
            this.aprsTabPage.Controls.Add(this.pictureBox1);
            this.aprsTabPage.Location = new System.Drawing.Point(4, 25);
            this.aprsTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.aprsTabPage.Name = "aprsTabPage";
            this.aprsTabPage.Padding = new System.Windows.Forms.Padding(4);
            this.aprsTabPage.Size = new System.Drawing.Size(495, 263);
            this.aprsTabPage.TabIndex = 1;
            this.aprsTabPage.Text = "APRS";
            this.aprsTabPage.UseVisualStyleBackColor = true;
            // 
            // label9
            // 
            this.label9.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label9.Location = new System.Drawing.Point(8, 7);
            this.label9.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label9.Name = "label9";
            this.label9.Size = new System.Drawing.Size(385, 42);
            this.label9.TabIndex = 18;
            this.label9.Text = "APRS stations can use prefered relay routes.";
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(12, 74);
            this.label6.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(98, 16);
            this.label6.TabIndex = 7;
            this.label6.Text = "Prefered Route";
            // 
            // aprsRouteComboBox
            // 
            this.aprsRouteComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsRouteComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.aprsRouteComboBox.FormattingEnabled = true;
            this.aprsRouteComboBox.Location = new System.Drawing.Point(172, 70);
            this.aprsRouteComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.aprsRouteComboBox.Name = "aprsRouteComboBox";
            this.aprsRouteComboBox.Size = new System.Drawing.Size(297, 24);
            this.aprsRouteComboBox.TabIndex = 20;
            // 
            // pictureBox1
            // 
            this.pictureBox1.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox1.Image = global::HTCommander.Properties.Resources.MapPoint1;
            this.pictureBox1.Location = new System.Drawing.Point(404, 7);
            this.pictureBox1.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox1.Name = "pictureBox1";
            this.pictureBox1.Size = new System.Drawing.Size(67, 42);
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
            this.terminalTabPage.Location = new System.Drawing.Point(4, 25);
            this.terminalTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.terminalTabPage.Name = "terminalTabPage";
            this.terminalTabPage.Size = new System.Drawing.Size(495, 263);
            this.terminalTabPage.TabIndex = 2;
            this.terminalTabPage.Text = "Terminal";
            this.terminalTabPage.UseVisualStyleBackColor = true;
            // 
            // label13
            // 
            this.label13.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label13.ForeColor = System.Drawing.SystemColors.ControlDarkDark;
            this.label13.Location = new System.Drawing.Point(168, 165);
            this.label13.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label13.Name = "label13";
            this.label13.Size = new System.Drawing.Size(303, 25);
            this.label13.TabIndex = 28;
            this.label13.Text = "Enter callsign-id";
            // 
            // ax25DestTextBox
            // 
            this.ax25DestTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.ax25DestTextBox.Location = new System.Drawing.Point(172, 137);
            this.ax25DestTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.ax25DestTextBox.MaxLength = 9;
            this.ax25DestTextBox.Name = "ax25DestTextBox";
            this.ax25DestTextBox.Size = new System.Drawing.Size(297, 22);
            this.ax25DestTextBox.TabIndex = 33;
            this.ax25DestTextBox.TextChanged += new System.EventHandler(this.ax25DestTextBox_TextChanged);
            this.ax25DestTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.ax25DestTextBox_KeyPress);
            // 
            // label14
            // 
            this.label14.AutoSize = true;
            this.label14.Location = new System.Drawing.Point(12, 140);
            this.label14.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label14.Name = "label14";
            this.label14.Size = new System.Drawing.Size(111, 16);
            this.label14.TabIndex = 27;
            this.label14.Text = "AX.25 Destination";
            // 
            // label12
            // 
            this.label12.AutoSize = true;
            this.label12.Location = new System.Drawing.Point(12, 107);
            this.label12.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label12.Name = "label12";
            this.label12.Size = new System.Drawing.Size(56, 16);
            this.label12.TabIndex = 25;
            this.label12.Text = "Channel";
            // 
            // channelsComboBox
            // 
            this.channelsComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.channelsComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.channelsComboBox.FormattingEnabled = true;
            this.channelsComboBox.Location = new System.Drawing.Point(172, 103);
            this.channelsComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.channelsComboBox.Name = "channelsComboBox";
            this.channelsComboBox.Size = new System.Drawing.Size(297, 24);
            this.channelsComboBox.TabIndex = 32;
            this.channelsComboBox.SelectedIndexChanged += new System.EventHandler(this.channelsComboBox_SelectedIndexChanged);
            this.channelsComboBox.TextChanged += new System.EventHandler(this.channelsComboBox_TextChanged);
            // 
            // label11
            // 
            this.label11.AutoSize = true;
            this.label11.Location = new System.Drawing.Point(12, 74);
            this.label11.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label11.Name = "label11";
            this.label11.Size = new System.Drawing.Size(57, 16);
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
            "Raw AX.25 + Compression"});
            this.terminalProtocolComboBox.Location = new System.Drawing.Point(172, 70);
            this.terminalProtocolComboBox.Margin = new System.Windows.Forms.Padding(4);
            this.terminalProtocolComboBox.Name = "terminalProtocolComboBox";
            this.terminalProtocolComboBox.Size = new System.Drawing.Size(297, 24);
            this.terminalProtocolComboBox.TabIndex = 31;
            this.terminalProtocolComboBox.SelectedIndexChanged += new System.EventHandler(this.terminalProtocolComboBox_SelectedIndexChanged);
            // 
            // label10
            // 
            this.label10.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label10.Location = new System.Drawing.Point(8, 7);
            this.label10.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label10.Name = "label10";
            this.label10.Size = new System.Drawing.Size(385, 42);
            this.label10.TabIndex = 20;
            this.label10.Text = "Select the station\'s terminal protocol, channel and settings";
            // 
            // pictureBox3
            // 
            this.pictureBox3.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox3.Image = global::HTCommander.Properties.Resources.Terminal;
            this.pictureBox3.Location = new System.Drawing.Point(404, 7);
            this.pictureBox3.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox3.Name = "pictureBox3";
            this.pictureBox3.Size = new System.Drawing.Size(67, 42);
            this.pictureBox3.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox3.TabIndex = 21;
            this.pictureBox3.TabStop = false;
            // 
            // AddStationForm
            // 
            this.AcceptButton = this.nextButton;
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.cancelButton;
            this.ClientSize = new System.Drawing.Size(535, 357);
            this.Controls.Add(this.backButton);
            this.Controls.Add(this.mainTabControl);
            this.Controls.Add(this.nextButton);
            this.Controls.Add(this.cancelButton);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Margin = new System.Windows.Forms.Padding(4);
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
    }
}