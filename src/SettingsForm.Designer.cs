namespace HTCommander
{
    partial class SettingsForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(SettingsForm));
            this.tabControl1 = new System.Windows.Forms.TabControl();
            this.licenseTabPage = new System.Windows.Forms.TabPage();
            this.linkLabel1 = new System.Windows.Forms.LinkLabel();
            this.groupBox1 = new System.Windows.Forms.GroupBox();
            this.allowTransmitCheckBox = new System.Windows.Forms.CheckBox();
            this.label3 = new System.Windows.Forms.Label();
            this.label2 = new System.Windows.Forms.Label();
            this.stationIdComboBox = new System.Windows.Forms.ComboBox();
            this.callsignTextBox = new System.Windows.Forms.TextBox();
            this.label1 = new System.Windows.Forms.Label();
            this.aprsTabPage = new System.Windows.Forms.TabPage();
            this.label4 = new System.Windows.Forms.Label();
            this.groupBox2 = new System.Windows.Forms.GroupBox();
            this.editButton = new System.Windows.Forms.Button();
            this.aprsRoutesListView = new System.Windows.Forms.ListView();
            this.columnHeader1 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader2 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.addAprsButton = new System.Windows.Forms.Button();
            this.deleteAprsButton = new System.Windows.Forms.Button();
            this.webServerTabPage = new System.Windows.Forms.TabPage();
            this.groupBox3 = new System.Windows.Forms.GroupBox();
            this.webPortNumericUpDown = new System.Windows.Forms.NumericUpDown();
            this.label6 = new System.Windows.Forms.Label();
            this.webServerEnabledCheckBox = new System.Windows.Forms.CheckBox();
            this.label5 = new System.Windows.Forms.Label();
            this.okButton = new System.Windows.Forms.Button();
            this.cancelButton = new System.Windows.Forms.Button();
            this.winlinkTabPage = new System.Windows.Forms.TabPage();
            this.linkLabel2 = new System.Windows.Forms.LinkLabel();
            this.groupBox4 = new System.Windows.Forms.GroupBox();
            this.label8 = new System.Windows.Forms.Label();
            this.winlinkPasswordTextBox = new System.Windows.Forms.TextBox();
            this.label9 = new System.Windows.Forms.Label();
            this.pictureBox1 = new System.Windows.Forms.PictureBox();
            this.pictureBox2 = new System.Windows.Forms.PictureBox();
            this.pictureBox4 = new System.Windows.Forms.PictureBox();
            this.pictureBox3 = new System.Windows.Forms.PictureBox();
            this.winlinkAccountTextBox = new System.Windows.Forms.TextBox();
            this.label7 = new System.Windows.Forms.Label();
            this.tabControl1.SuspendLayout();
            this.licenseTabPage.SuspendLayout();
            this.groupBox1.SuspendLayout();
            this.aprsTabPage.SuspendLayout();
            this.groupBox2.SuspendLayout();
            this.webServerTabPage.SuspendLayout();
            this.groupBox3.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.webPortNumericUpDown)).BeginInit();
            this.winlinkTabPage.SuspendLayout();
            this.groupBox4.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox4)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox3)).BeginInit();
            this.SuspendLayout();
            // 
            // tabControl1
            // 
            this.tabControl1.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.tabControl1.Controls.Add(this.licenseTabPage);
            this.tabControl1.Controls.Add(this.aprsTabPage);
            this.tabControl1.Controls.Add(this.winlinkTabPage);
            this.tabControl1.Controls.Add(this.webServerTabPage);
            this.tabControl1.Location = new System.Drawing.Point(16, 15);
            this.tabControl1.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.tabControl1.Name = "tabControl1";
            this.tabControl1.SelectedIndex = 0;
            this.tabControl1.Size = new System.Drawing.Size(500, 459);
            this.tabControl1.TabIndex = 2;
            // 
            // licenseTabPage
            // 
            this.licenseTabPage.Controls.Add(this.linkLabel1);
            this.licenseTabPage.Controls.Add(this.groupBox1);
            this.licenseTabPage.Controls.Add(this.pictureBox1);
            this.licenseTabPage.Controls.Add(this.label1);
            this.licenseTabPage.Location = new System.Drawing.Point(4, 25);
            this.licenseTabPage.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.licenseTabPage.Name = "licenseTabPage";
            this.licenseTabPage.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.licenseTabPage.Size = new System.Drawing.Size(492, 430);
            this.licenseTabPage.TabIndex = 0;
            this.licenseTabPage.Text = "License";
            this.licenseTabPage.UseVisualStyleBackColor = true;
            // 
            // linkLabel1
            // 
            this.linkLabel1.AutoSize = true;
            this.linkLabel1.Location = new System.Drawing.Point(8, 105);
            this.linkLabel1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.linkLabel1.Name = "linkLabel1";
            this.linkLabel1.Size = new System.Drawing.Size(178, 16);
            this.linkLabel1.TabIndex = 3;
            this.linkLabel1.TabStop = true;
            this.linkLabel1.Text = "www.arrl.org/getting-licensed";
            this.linkLabel1.LinkClicked += new System.Windows.Forms.LinkLabelLinkClickedEventHandler(this.linkLabel1_LinkClicked);
            // 
            // groupBox1
            // 
            this.groupBox1.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.groupBox1.Controls.Add(this.allowTransmitCheckBox);
            this.groupBox1.Controls.Add(this.label3);
            this.groupBox1.Controls.Add(this.label2);
            this.groupBox1.Controls.Add(this.stationIdComboBox);
            this.groupBox1.Controls.Add(this.callsignTextBox);
            this.groupBox1.Location = new System.Drawing.Point(12, 142);
            this.groupBox1.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox1.Size = new System.Drawing.Size(469, 144);
            this.groupBox1.TabIndex = 2;
            this.groupBox1.TabStop = false;
            this.groupBox1.Text = "Call Sign && Station ID";
            // 
            // allowTransmitCheckBox
            // 
            this.allowTransmitCheckBox.AutoSize = true;
            this.allowTransmitCheckBox.Enabled = false;
            this.allowTransmitCheckBox.Location = new System.Drawing.Point(12, 110);
            this.allowTransmitCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.allowTransmitCheckBox.Name = "allowTransmitCheckBox";
            this.allowTransmitCheckBox.Size = new System.Drawing.Size(219, 20);
            this.allowTransmitCheckBox.TabIndex = 4;
            this.allowTransmitCheckBox.Text = "Allow this application to transmit.";
            this.allowTransmitCheckBox.UseVisualStyleBackColor = true;
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label3.Location = new System.Drawing.Point(340, 64);
            this.label3.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(23, 31);
            this.label3.TabIndex = 3;
            this.label3.Text = "-";
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(8, 32);
            this.label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(338, 16);
            this.label2.TabIndex = 2;
            this.label2.Text = "Enter your callsign and the station ID for this radio below.";
            // 
            // stationIdComboBox
            // 
            this.stationIdComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.stationIdComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.stationIdComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.stationIdComboBox.FormattingEnabled = true;
            this.stationIdComboBox.Items.AddRange(new object[] {
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
            "10",
            "11",
            "12",
            "13",
            "14",
            "15"});
            this.stationIdComboBox.Location = new System.Drawing.Point(372, 60);
            this.stationIdComboBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.stationIdComboBox.Name = "stationIdComboBox";
            this.stationIdComboBox.Size = new System.Drawing.Size(88, 38);
            this.stationIdComboBox.TabIndex = 1;
            // 
            // callsignTextBox
            // 
            this.callsignTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.callsignTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.callsignTextBox.Location = new System.Drawing.Point(8, 60);
            this.callsignTextBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.callsignTextBox.MaxLength = 6;
            this.callsignTextBox.Name = "callsignTextBox";
            this.callsignTextBox.Size = new System.Drawing.Size(324, 37);
            this.callsignTextBox.TabIndex = 0;
            this.callsignTextBox.TextChanged += new System.EventHandler(this.callsignTextBox_TextChanged);
            this.callsignTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.callsignTextBox_KeyPress);
            // 
            // label1
            // 
            this.label1.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label1.Location = new System.Drawing.Point(8, 14);
            this.label1.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(381, 91);
            this.label1.TabIndex = 0;
            this.label1.Text = resources.GetString("label1.Text");
            // 
            // aprsTabPage
            // 
            this.aprsTabPage.Controls.Add(this.pictureBox2);
            this.aprsTabPage.Controls.Add(this.label4);
            this.aprsTabPage.Controls.Add(this.groupBox2);
            this.aprsTabPage.Location = new System.Drawing.Point(4, 25);
            this.aprsTabPage.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.aprsTabPage.Name = "aprsTabPage";
            this.aprsTabPage.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.aprsTabPage.Size = new System.Drawing.Size(492, 430);
            this.aprsTabPage.TabIndex = 1;
            this.aprsTabPage.Text = "APRS";
            this.aprsTabPage.UseVisualStyleBackColor = true;
            // 
            // label4
            // 
            this.label4.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label4.Location = new System.Drawing.Point(8, 14);
            this.label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(381, 91);
            this.label4.TabIndex = 2;
            this.label4.Text = resources.GetString("label4.Text");
            // 
            // groupBox2
            // 
            this.groupBox2.Controls.Add(this.editButton);
            this.groupBox2.Controls.Add(this.aprsRoutesListView);
            this.groupBox2.Controls.Add(this.addAprsButton);
            this.groupBox2.Controls.Add(this.deleteAprsButton);
            this.groupBox2.Location = new System.Drawing.Point(8, 108);
            this.groupBox2.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox2.Name = "groupBox2";
            this.groupBox2.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox2.Size = new System.Drawing.Size(473, 197);
            this.groupBox2.TabIndex = 0;
            this.groupBox2.TabStop = false;
            this.groupBox2.Text = "Routes";
            // 
            // editButton
            // 
            this.editButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.editButton.Enabled = false;
            this.editButton.Location = new System.Drawing.Point(257, 161);
            this.editButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.editButton.Name = "editButton";
            this.editButton.Size = new System.Drawing.Size(100, 28);
            this.editButton.TabIndex = 4;
            this.editButton.Text = "Edit...";
            this.editButton.UseVisualStyleBackColor = true;
            this.editButton.Click += new System.EventHandler(this.editButton_Click);
            // 
            // aprsRoutesListView
            // 
            this.aprsRoutesListView.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsRoutesListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader1,
            this.columnHeader2});
            this.aprsRoutesListView.FullRowSelect = true;
            this.aprsRoutesListView.GridLines = true;
            this.aprsRoutesListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            this.aprsRoutesListView.HideSelection = false;
            this.aprsRoutesListView.Location = new System.Drawing.Point(8, 23);
            this.aprsRoutesListView.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.aprsRoutesListView.MultiSelect = false;
            this.aprsRoutesListView.Name = "aprsRoutesListView";
            this.aprsRoutesListView.Size = new System.Drawing.Size(456, 130);
            this.aprsRoutesListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            this.aprsRoutesListView.TabIndex = 2;
            this.aprsRoutesListView.UseCompatibleStateImageBehavior = false;
            this.aprsRoutesListView.View = System.Windows.Forms.View.Details;
            this.aprsRoutesListView.SelectedIndexChanged += new System.EventHandler(this.aprsRoutesListView_SelectedIndexChanged);
            this.aprsRoutesListView.DoubleClick += new System.EventHandler(this.editButton_Click);
            // 
            // columnHeader1
            // 
            this.columnHeader1.Text = "Route";
            this.columnHeader1.Width = 100;
            // 
            // columnHeader2
            // 
            this.columnHeader2.Width = 220;
            // 
            // addAprsButton
            // 
            this.addAprsButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.addAprsButton.Location = new System.Drawing.Point(149, 161);
            this.addAprsButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.addAprsButton.Name = "addAprsButton";
            this.addAprsButton.Size = new System.Drawing.Size(100, 28);
            this.addAprsButton.TabIndex = 1;
            this.addAprsButton.Text = "Add...";
            this.addAprsButton.UseVisualStyleBackColor = true;
            this.addAprsButton.Click += new System.EventHandler(this.addAprsButton_Click);
            // 
            // deleteAprsButton
            // 
            this.deleteAprsButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.deleteAprsButton.Enabled = false;
            this.deleteAprsButton.Location = new System.Drawing.Point(365, 161);
            this.deleteAprsButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.deleteAprsButton.Name = "deleteAprsButton";
            this.deleteAprsButton.Size = new System.Drawing.Size(100, 28);
            this.deleteAprsButton.TabIndex = 0;
            this.deleteAprsButton.Text = "Delete";
            this.deleteAprsButton.UseVisualStyleBackColor = true;
            this.deleteAprsButton.Click += new System.EventHandler(this.deleteAprsButton_Click);
            // 
            // webServerTabPage
            // 
            this.webServerTabPage.Controls.Add(this.groupBox3);
            this.webServerTabPage.Controls.Add(this.label5);
            this.webServerTabPage.Controls.Add(this.pictureBox3);
            this.webServerTabPage.Location = new System.Drawing.Point(4, 25);
            this.webServerTabPage.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.webServerTabPage.Name = "webServerTabPage";
            this.webServerTabPage.Size = new System.Drawing.Size(492, 430);
            this.webServerTabPage.TabIndex = 2;
            this.webServerTabPage.Text = "Web Server";
            this.webServerTabPage.UseVisualStyleBackColor = true;
            // 
            // groupBox3
            // 
            this.groupBox3.Controls.Add(this.webPortNumericUpDown);
            this.groupBox3.Controls.Add(this.label6);
            this.groupBox3.Controls.Add(this.webServerEnabledCheckBox);
            this.groupBox3.Location = new System.Drawing.Point(8, 108);
            this.groupBox3.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox3.Name = "groupBox3";
            this.groupBox3.Padding = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.groupBox3.Size = new System.Drawing.Size(473, 102);
            this.groupBox3.TabIndex = 6;
            this.groupBox3.TabStop = false;
            this.groupBox3.Text = "Server Settings";
            // 
            // webPortNumericUpDown
            // 
            this.webPortNumericUpDown.Location = new System.Drawing.Point(305, 66);
            this.webPortNumericUpDown.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.webPortNumericUpDown.Maximum = new decimal(new int[] {
            65535,
            0,
            0,
            0});
            this.webPortNumericUpDown.Minimum = new decimal(new int[] {
            1,
            0,
            0,
            0});
            this.webPortNumericUpDown.Name = "webPortNumericUpDown";
            this.webPortNumericUpDown.Size = new System.Drawing.Size(160, 22);
            this.webPortNumericUpDown.TabIndex = 2;
            this.webPortNumericUpDown.Value = new decimal(new int[] {
            8080,
            0,
            0,
            0});
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(17, 69);
            this.label6.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(106, 16);
            this.label6.TabIndex = 1;
            this.label6.Text = "Web Server Port";
            // 
            // webServerEnabledCheckBox
            // 
            this.webServerEnabledCheckBox.AutoSize = true;
            this.webServerEnabledCheckBox.Location = new System.Drawing.Point(21, 34);
            this.webServerEnabledCheckBox.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.webServerEnabledCheckBox.Name = "webServerEnabledCheckBox";
            this.webServerEnabledCheckBox.Size = new System.Drawing.Size(147, 20);
            this.webServerEnabledCheckBox.TabIndex = 0;
            this.webServerEnabledCheckBox.Text = "Enable Web Server";
            this.webServerEnabledCheckBox.UseVisualStyleBackColor = true;
            this.webServerEnabledCheckBox.CheckedChanged += new System.EventHandler(this.webServerEnabledCheckBox_CheckedChanged);
            // 
            // label5
            // 
            this.label5.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label5.Location = new System.Drawing.Point(8, 14);
            this.label5.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(381, 91);
            this.label5.TabIndex = 4;
            this.label5.Text = "Enable the built-in web server to order to share radio services with other applic" +
    "ations including other instances of this application. Allows you to access this " +
    "radio over the local network.";
            // 
            // okButton
            // 
            this.okButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.okButton.Location = new System.Drawing.Point(311, 481);
            this.okButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.okButton.Name = "okButton";
            this.okButton.Size = new System.Drawing.Size(100, 28);
            this.okButton.TabIndex = 16;
            this.okButton.Text = "OK";
            this.okButton.UseVisualStyleBackColor = true;
            this.okButton.Click += new System.EventHandler(this.okButton_Click);
            // 
            // cancelButton
            // 
            this.cancelButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.cancelButton.Location = new System.Drawing.Point(411, 481);
            this.cancelButton.Margin = new System.Windows.Forms.Padding(4, 4, 4, 4);
            this.cancelButton.Name = "cancelButton";
            this.cancelButton.Size = new System.Drawing.Size(100, 28);
            this.cancelButton.TabIndex = 15;
            this.cancelButton.Text = "Cancel";
            this.cancelButton.UseVisualStyleBackColor = true;
            // 
            // winlinkTabPage
            // 
            this.winlinkTabPage.Controls.Add(this.linkLabel2);
            this.winlinkTabPage.Controls.Add(this.groupBox4);
            this.winlinkTabPage.Controls.Add(this.pictureBox4);
            this.winlinkTabPage.Controls.Add(this.label9);
            this.winlinkTabPage.Location = new System.Drawing.Point(4, 25);
            this.winlinkTabPage.Name = "winlinkTabPage";
            this.winlinkTabPage.Size = new System.Drawing.Size(492, 430);
            this.winlinkTabPage.TabIndex = 3;
            this.winlinkTabPage.Text = "Winlink";
            this.winlinkTabPage.UseVisualStyleBackColor = true;
            // 
            // linkLabel2
            // 
            this.linkLabel2.AutoSize = true;
            this.linkLabel2.Location = new System.Drawing.Point(8, 77);
            this.linkLabel2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.linkLabel2.Name = "linkLabel2";
            this.linkLabel2.Size = new System.Drawing.Size(69, 16);
            this.linkLabel2.TabIndex = 7;
            this.linkLabel2.TabStop = true;
            this.linkLabel2.Text = "winlink.org";
            this.linkLabel2.LinkClicked += new System.Windows.Forms.LinkLabelLinkClickedEventHandler(this.linkLabel2_LinkClicked);
            // 
            // groupBox4
            // 
            this.groupBox4.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.groupBox4.Controls.Add(this.label7);
            this.groupBox4.Controls.Add(this.winlinkAccountTextBox);
            this.groupBox4.Controls.Add(this.label8);
            this.groupBox4.Controls.Add(this.winlinkPasswordTextBox);
            this.groupBox4.Location = new System.Drawing.Point(12, 113);
            this.groupBox4.Margin = new System.Windows.Forms.Padding(4);
            this.groupBox4.Name = "groupBox4";
            this.groupBox4.Padding = new System.Windows.Forms.Padding(4);
            this.groupBox4.Size = new System.Drawing.Size(469, 159);
            this.groupBox4.TabIndex = 6;
            this.groupBox4.TabStop = false;
            this.groupBox4.Text = "Winlink Credentials";
            // 
            // label8
            // 
            this.label8.AutoSize = true;
            this.label8.Location = new System.Drawing.Point(8, 82);
            this.label8.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label8.Name = "label8";
            this.label8.Size = new System.Drawing.Size(67, 16);
            this.label8.TabIndex = 2;
            this.label8.Text = "Password";
            // 
            // winlinkPasswordTextBox
            // 
            this.winlinkPasswordTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.winlinkPasswordTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.winlinkPasswordTextBox.Location = new System.Drawing.Point(8, 110);
            this.winlinkPasswordTextBox.Margin = new System.Windows.Forms.Padding(4);
            this.winlinkPasswordTextBox.MaxLength = 128;
            this.winlinkPasswordTextBox.Name = "winlinkPasswordTextBox";
            this.winlinkPasswordTextBox.PasswordChar = '●';
            this.winlinkPasswordTextBox.Size = new System.Drawing.Size(453, 37);
            this.winlinkPasswordTextBox.TabIndex = 0;
            // 
            // label9
            // 
            this.label9.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label9.Location = new System.Drawing.Point(8, 14);
            this.label9.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label9.Name = "label9";
            this.label9.Size = new System.Drawing.Size(381, 91);
            this.label9.TabIndex = 4;
            this.label9.Text = "You can send and receive emails with this software using Winlink. Create an accou" +
    "nt with your callsign and enter you password account here to get started.";
            // 
            // pictureBox1
            // 
            this.pictureBox1.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox1.Image = global::HTCommander.Properties.Resources.Certificate;
            this.pictureBox1.Location = new System.Drawing.Point(397, 10);
            this.pictureBox1.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox1.Name = "pictureBox1";
            this.pictureBox1.Size = new System.Drawing.Size(92, 95);
            this.pictureBox1.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox1.TabIndex = 1;
            this.pictureBox1.TabStop = false;
            // 
            // pictureBox2
            // 
            this.pictureBox2.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox2.Image = global::HTCommander.Properties.Resources.MapPoint1;
            this.pictureBox2.Location = new System.Drawing.Point(397, 10);
            this.pictureBox2.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox2.Name = "pictureBox2";
            this.pictureBox2.Size = new System.Drawing.Size(92, 95);
            this.pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox2.TabIndex = 3;
            this.pictureBox2.TabStop = false;
            // 
            // pictureBox4
            // 
            this.pictureBox4.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox4.Image = global::HTCommander.Properties.Resources.Letter;
            this.pictureBox4.Location = new System.Drawing.Point(397, 10);
            this.pictureBox4.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox4.Name = "pictureBox4";
            this.pictureBox4.Size = new System.Drawing.Size(92, 95);
            this.pictureBox4.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox4.TabIndex = 5;
            this.pictureBox4.TabStop = false;
            // 
            // pictureBox3
            // 
            this.pictureBox3.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.pictureBox3.Image = global::HTCommander.Properties.Resources.webserver;
            this.pictureBox3.Location = new System.Drawing.Point(397, 10);
            this.pictureBox3.Margin = new System.Windows.Forms.Padding(4);
            this.pictureBox3.Name = "pictureBox3";
            this.pictureBox3.Size = new System.Drawing.Size(92, 95);
            this.pictureBox3.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox3.TabIndex = 5;
            this.pictureBox3.TabStop = false;
            // 
            // winlinkAccountTextBox
            // 
            this.winlinkAccountTextBox.Location = new System.Drawing.Point(11, 50);
            this.winlinkAccountTextBox.Name = "winlinkAccountTextBox";
            this.winlinkAccountTextBox.ReadOnly = true;
            this.winlinkAccountTextBox.Size = new System.Drawing.Size(450, 22);
            this.winlinkAccountTextBox.TabIndex = 3;
            // 
            // label7
            // 
            this.label7.AutoSize = true;
            this.label7.Location = new System.Drawing.Point(8, 26);
            this.label7.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(55, 16);
            this.label7.TabIndex = 4;
            this.label7.Text = "Account";
            // 
            // SettingsForm
            // 
            this.AcceptButton = this.okButton;
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.cancelButton;
            this.ClientSize = new System.Drawing.Size(532, 524);
            this.Controls.Add(this.okButton);
            this.Controls.Add(this.cancelButton);
            this.Controls.Add(this.tabControl1);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Margin = new System.Windows.Forms.Padding(3, 2, 3, 2);
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "SettingsForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Settings";
            this.Load += new System.EventHandler(this.SettingsForm_Load);
            this.tabControl1.ResumeLayout(false);
            this.licenseTabPage.ResumeLayout(false);
            this.licenseTabPage.PerformLayout();
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            this.aprsTabPage.ResumeLayout(false);
            this.groupBox2.ResumeLayout(false);
            this.webServerTabPage.ResumeLayout(false);
            this.groupBox3.ResumeLayout(false);
            this.groupBox3.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.webPortNumericUpDown)).EndInit();
            this.winlinkTabPage.ResumeLayout(false);
            this.winlinkTabPage.PerformLayout();
            this.groupBox4.ResumeLayout(false);
            this.groupBox4.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox2)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox4)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox3)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion
        private System.Windows.Forms.TabControl tabControl1;
        private System.Windows.Forms.TabPage licenseTabPage;
        private System.Windows.Forms.TabPage aprsTabPage;
        private System.Windows.Forms.GroupBox groupBox1;
        private System.Windows.Forms.PictureBox pictureBox1;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.LinkLabel linkLabel1;
        private System.Windows.Forms.ComboBox stationIdComboBox;
        private System.Windows.Forms.TextBox callsignTextBox;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.CheckBox allowTransmitCheckBox;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.GroupBox groupBox2;
        private System.Windows.Forms.Button addAprsButton;
        private System.Windows.Forms.Button deleteAprsButton;
        private System.Windows.Forms.ListView aprsRoutesListView;
        private System.Windows.Forms.ColumnHeader columnHeader1;
        private System.Windows.Forms.ColumnHeader columnHeader2;
        private System.Windows.Forms.Button okButton;
        private System.Windows.Forms.Button cancelButton;
        private System.Windows.Forms.Button editButton;
        private System.Windows.Forms.TabPage webServerTabPage;
        private System.Windows.Forms.PictureBox pictureBox3;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.GroupBox groupBox3;
        private System.Windows.Forms.NumericUpDown webPortNumericUpDown;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.CheckBox webServerEnabledCheckBox;
        private System.Windows.Forms.TabPage winlinkTabPage;
        private System.Windows.Forms.LinkLabel linkLabel2;
        private System.Windows.Forms.GroupBox groupBox4;
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.TextBox winlinkPasswordTextBox;
        private System.Windows.Forms.PictureBox pictureBox4;
        private System.Windows.Forms.Label label9;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.TextBox winlinkAccountTextBox;
    }
}