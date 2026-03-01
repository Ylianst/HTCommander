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
            tabControl1 = new System.Windows.Forms.TabControl();
            licenseTabPage = new System.Windows.Forms.TabPage();
            linkLabel1 = new System.Windows.Forms.LinkLabel();
            groupBox1 = new System.Windows.Forms.GroupBox();
            allowTransmitCheckBox = new System.Windows.Forms.CheckBox();
            label3 = new System.Windows.Forms.Label();
            label2 = new System.Windows.Forms.Label();
            stationIdComboBox = new System.Windows.Forms.ComboBox();
            callsignTextBox = new System.Windows.Forms.TextBox();
            pictureBox1 = new System.Windows.Forms.PictureBox();
            label1 = new System.Windows.Forms.Label();
            aprsTabPage = new System.Windows.Forms.TabPage();
            pictureBox2 = new System.Windows.Forms.PictureBox();
            label4 = new System.Windows.Forms.Label();
            groupBox2 = new System.Windows.Forms.GroupBox();
            editButton = new System.Windows.Forms.Button();
            aprsRoutesListView = new System.Windows.Forms.ListView();
            columnHeader1 = new System.Windows.Forms.ColumnHeader();
            columnHeader2 = new System.Windows.Forms.ColumnHeader();
            addAprsButton = new System.Windows.Forms.Button();
            deleteAprsButton = new System.Windows.Forms.Button();
            voiceTabPage = new System.Windows.Forms.TabPage();
            groupBox6 = new System.Windows.Forms.GroupBox();
            label14 = new System.Windows.Forms.Label();
            voicesComboBox = new System.Windows.Forms.ComboBox();
            progressBar = new System.Windows.Forms.ProgressBar();
            pictureBox5 = new System.Windows.Forms.PictureBox();
            label10 = new System.Windows.Forms.Label();
            groupBox5 = new System.Windows.Forms.GroupBox();
            cancelDownloadButton = new System.Windows.Forms.Button();
            label12 = new System.Windows.Forms.Label();
            modelsComboBox = new System.Windows.Forms.ComboBox();
            label11 = new System.Windows.Forms.Label();
            languageComboBox = new System.Windows.Forms.ComboBox();
            downloadButton = new System.Windows.Forms.Button();
            deleteButton = new System.Windows.Forms.Button();
            winlinkTabPage = new System.Windows.Forms.TabPage();
            winlinkStationIdCheckBox = new System.Windows.Forms.CheckBox();
            linkLabel2 = new System.Windows.Forms.LinkLabel();
            groupBox4 = new System.Windows.Forms.GroupBox();
            label7 = new System.Windows.Forms.Label();
            winlinkAccountTextBox = new System.Windows.Forms.TextBox();
            label8 = new System.Windows.Forms.Label();
            winlinkPasswordTextBox = new System.Windows.Forms.TextBox();
            label9 = new System.Windows.Forms.Label();
            pictureBox4 = new System.Windows.Forms.PictureBox();
            webServerTabPage = new System.Windows.Forms.TabPage();
            groupBox3 = new System.Windows.Forms.GroupBox();
            agwpePortNumericUpDown = new System.Windows.Forms.NumericUpDown();
            label13 = new System.Windows.Forms.Label();
            webPortNumericUpDown = new System.Windows.Forms.NumericUpDown();
            agwpeServerEnabledCheckBox = new System.Windows.Forms.CheckBox();
            label6 = new System.Windows.Forms.Label();
            webServerEnabledCheckBox = new System.Windows.Forms.CheckBox();
            label5 = new System.Windows.Forms.Label();
            pictureBox3 = new System.Windows.Forms.PictureBox();
            airplanesTabPage = new System.Windows.Forms.TabPage();
            groupBox8 = new System.Windows.Forms.GroupBox();
            gpsStateButton = new System.Windows.Forms.Button();
            gpsBaudRateComboBox = new System.Windows.Forms.ComboBox();
            gpsSerialPortComboBox = new System.Windows.Forms.ComboBox();
            label18 = new System.Windows.Forms.Label();
            groupBox7 = new System.Windows.Forms.GroupBox();
            dump1090testResultsLabel = new System.Windows.Forms.Label();
            dump1090testButton = new System.Windows.Forms.Button();
            dump1090urlTextBox = new System.Windows.Forms.TextBox();
            label15 = new System.Windows.Forms.Label();
            label17 = new System.Windows.Forms.Label();
            pictureBox6 = new System.Windows.Forms.PictureBox();
            okButton = new System.Windows.Forms.Button();
            cancelButton = new System.Windows.Forms.Button();
            gpsStatusLabel = new System.Windows.Forms.Label();
            tabControl1.SuspendLayout();
            licenseTabPage.SuspendLayout();
            groupBox1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox1).BeginInit();
            aprsTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).BeginInit();
            groupBox2.SuspendLayout();
            voiceTabPage.SuspendLayout();
            groupBox6.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox5).BeginInit();
            groupBox5.SuspendLayout();
            winlinkTabPage.SuspendLayout();
            groupBox4.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox4).BeginInit();
            webServerTabPage.SuspendLayout();
            groupBox3.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)agwpePortNumericUpDown).BeginInit();
            ((System.ComponentModel.ISupportInitialize)webPortNumericUpDown).BeginInit();
            ((System.ComponentModel.ISupportInitialize)pictureBox3).BeginInit();
            airplanesTabPage.SuspendLayout();
            groupBox8.SuspendLayout();
            groupBox7.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox6).BeginInit();
            SuspendLayout();
            // 
            // tabControl1
            // 
            tabControl1.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            tabControl1.Controls.Add(licenseTabPage);
            tabControl1.Controls.Add(aprsTabPage);
            tabControl1.Controls.Add(voiceTabPage);
            tabControl1.Controls.Add(winlinkTabPage);
            tabControl1.Controls.Add(webServerTabPage);
            tabControl1.Controls.Add(airplanesTabPage);
            tabControl1.Location = new System.Drawing.Point(16, 19);
            tabControl1.Margin = new System.Windows.Forms.Padding(5);
            tabControl1.Name = "tabControl1";
            tabControl1.SelectedIndex = 0;
            tabControl1.Size = new System.Drawing.Size(501, 573);
            tabControl1.TabIndex = 2;
            // 
            // licenseTabPage
            // 
            licenseTabPage.Controls.Add(linkLabel1);
            licenseTabPage.Controls.Add(groupBox1);
            licenseTabPage.Controls.Add(pictureBox1);
            licenseTabPage.Controls.Add(label1);
            licenseTabPage.Location = new System.Drawing.Point(4, 29);
            licenseTabPage.Margin = new System.Windows.Forms.Padding(5);
            licenseTabPage.Name = "licenseTabPage";
            licenseTabPage.Padding = new System.Windows.Forms.Padding(5);
            licenseTabPage.Size = new System.Drawing.Size(493, 540);
            licenseTabPage.TabIndex = 0;
            licenseTabPage.Text = "License";
            licenseTabPage.UseVisualStyleBackColor = true;
            // 
            // linkLabel1
            // 
            linkLabel1.AutoSize = true;
            linkLabel1.Location = new System.Drawing.Point(8, 131);
            linkLabel1.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            linkLabel1.Name = "linkLabel1";
            linkLabel1.Size = new System.Drawing.Size(207, 20);
            linkLabel1.TabIndex = 3;
            linkLabel1.TabStop = true;
            linkLabel1.Text = "www.arrl.org/getting-licensed";
            linkLabel1.LinkClicked += linkLabel1_LinkClicked;
            // 
            // groupBox1
            // 
            groupBox1.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            groupBox1.Controls.Add(allowTransmitCheckBox);
            groupBox1.Controls.Add(label3);
            groupBox1.Controls.Add(label2);
            groupBox1.Controls.Add(stationIdComboBox);
            groupBox1.Controls.Add(callsignTextBox);
            groupBox1.Location = new System.Drawing.Point(11, 177);
            groupBox1.Margin = new System.Windows.Forms.Padding(5);
            groupBox1.Name = "groupBox1";
            groupBox1.Padding = new System.Windows.Forms.Padding(5);
            groupBox1.Size = new System.Drawing.Size(469, 180);
            groupBox1.TabIndex = 2;
            groupBox1.TabStop = false;
            groupBox1.Text = "Call Sign && Station ID";
            // 
            // allowTransmitCheckBox
            // 
            allowTransmitCheckBox.AutoSize = true;
            allowTransmitCheckBox.Enabled = false;
            allowTransmitCheckBox.Location = new System.Drawing.Point(11, 137);
            allowTransmitCheckBox.Margin = new System.Windows.Forms.Padding(5);
            allowTransmitCheckBox.Name = "allowTransmitCheckBox";
            allowTransmitCheckBox.Size = new System.Drawing.Size(254, 24);
            allowTransmitCheckBox.TabIndex = 4;
            allowTransmitCheckBox.Text = "Allow this application to transmit.";
            allowTransmitCheckBox.UseVisualStyleBackColor = true;
            // 
            // label3
            // 
            label3.AutoSize = true;
            label3.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            label3.Location = new System.Drawing.Point(341, 80);
            label3.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label3.Name = "label3";
            label3.Size = new System.Drawing.Size(23, 31);
            label3.TabIndex = 3;
            label3.Text = "-";
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new System.Drawing.Point(8, 40);
            label2.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label2.Name = "label2";
            label2.Size = new System.Drawing.Size(389, 20);
            label2.TabIndex = 2;
            label2.Text = "Enter your callsign and the station ID for this radio below.";
            // 
            // stationIdComboBox
            // 
            stationIdComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            stationIdComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            stationIdComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            stationIdComboBox.FormattingEnabled = true;
            stationIdComboBox.Items.AddRange(new object[] { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15" });
            stationIdComboBox.Location = new System.Drawing.Point(373, 75);
            stationIdComboBox.Margin = new System.Windows.Forms.Padding(5);
            stationIdComboBox.Name = "stationIdComboBox";
            stationIdComboBox.Size = new System.Drawing.Size(89, 38);
            stationIdComboBox.TabIndex = 1;
            // 
            // callsignTextBox
            // 
            callsignTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            callsignTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            callsignTextBox.Location = new System.Drawing.Point(8, 75);
            callsignTextBox.Margin = new System.Windows.Forms.Padding(5);
            callsignTextBox.MaxLength = 6;
            callsignTextBox.Name = "callsignTextBox";
            callsignTextBox.Size = new System.Drawing.Size(324, 37);
            callsignTextBox.TabIndex = 0;
            callsignTextBox.TextChanged += callsignTextBox_TextChanged;
            callsignTextBox.KeyPress += callsignTextBox_KeyPress;
            // 
            // pictureBox1
            // 
            pictureBox1.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox1.Image = Properties.Resources.Certificate;
            pictureBox1.Location = new System.Drawing.Point(397, 12);
            pictureBox1.Margin = new System.Windows.Forms.Padding(5);
            pictureBox1.Name = "pictureBox1";
            pictureBox1.Size = new System.Drawing.Size(91, 119);
            pictureBox1.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox1.TabIndex = 1;
            pictureBox1.TabStop = false;
            // 
            // label1
            // 
            label1.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label1.Location = new System.Drawing.Point(8, 17);
            label1.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label1.Name = "label1";
            label1.Size = new System.Drawing.Size(381, 113);
            label1.TabIndex = 0;
            label1.Text = resources.GetString("label1.Text");
            // 
            // aprsTabPage
            // 
            aprsTabPage.Controls.Add(pictureBox2);
            aprsTabPage.Controls.Add(label4);
            aprsTabPage.Controls.Add(groupBox2);
            aprsTabPage.Location = new System.Drawing.Point(4, 29);
            aprsTabPage.Margin = new System.Windows.Forms.Padding(5);
            aprsTabPage.Name = "aprsTabPage";
            aprsTabPage.Padding = new System.Windows.Forms.Padding(5);
            aprsTabPage.Size = new System.Drawing.Size(493, 540);
            aprsTabPage.TabIndex = 1;
            aprsTabPage.Text = "APRS";
            aprsTabPage.UseVisualStyleBackColor = true;
            // 
            // pictureBox2
            // 
            pictureBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox2.Image = Properties.Resources.MapPoint1;
            pictureBox2.Location = new System.Drawing.Point(397, 12);
            pictureBox2.Margin = new System.Windows.Forms.Padding(5);
            pictureBox2.Name = "pictureBox2";
            pictureBox2.Size = new System.Drawing.Size(91, 119);
            pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox2.TabIndex = 3;
            pictureBox2.TabStop = false;
            // 
            // label4
            // 
            label4.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label4.Location = new System.Drawing.Point(8, 17);
            label4.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label4.Name = "label4";
            label4.Size = new System.Drawing.Size(381, 113);
            label4.TabIndex = 2;
            label4.Text = resources.GetString("label4.Text");
            // 
            // groupBox2
            // 
            groupBox2.Controls.Add(editButton);
            groupBox2.Controls.Add(aprsRoutesListView);
            groupBox2.Controls.Add(addAprsButton);
            groupBox2.Controls.Add(deleteAprsButton);
            groupBox2.Location = new System.Drawing.Point(8, 135);
            groupBox2.Margin = new System.Windows.Forms.Padding(5);
            groupBox2.Name = "groupBox2";
            groupBox2.Padding = new System.Windows.Forms.Padding(5);
            groupBox2.Size = new System.Drawing.Size(473, 247);
            groupBox2.TabIndex = 0;
            groupBox2.TabStop = false;
            groupBox2.Text = "Routes";
            // 
            // editButton
            // 
            editButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            editButton.Enabled = false;
            editButton.Location = new System.Drawing.Point(257, 201);
            editButton.Margin = new System.Windows.Forms.Padding(5);
            editButton.Name = "editButton";
            editButton.Size = new System.Drawing.Size(101, 35);
            editButton.TabIndex = 4;
            editButton.Text = "Edit...";
            editButton.UseVisualStyleBackColor = true;
            editButton.Click += editButton_Click;
            // 
            // aprsRoutesListView
            // 
            aprsRoutesListView.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            aprsRoutesListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader1, columnHeader2 });
            aprsRoutesListView.FullRowSelect = true;
            aprsRoutesListView.GridLines = true;
            aprsRoutesListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            aprsRoutesListView.Location = new System.Drawing.Point(8, 29);
            aprsRoutesListView.Margin = new System.Windows.Forms.Padding(5);
            aprsRoutesListView.MultiSelect = false;
            aprsRoutesListView.Name = "aprsRoutesListView";
            aprsRoutesListView.Size = new System.Drawing.Size(457, 161);
            aprsRoutesListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            aprsRoutesListView.TabIndex = 2;
            aprsRoutesListView.UseCompatibleStateImageBehavior = false;
            aprsRoutesListView.View = System.Windows.Forms.View.Details;
            aprsRoutesListView.SelectedIndexChanged += aprsRoutesListView_SelectedIndexChanged;
            aprsRoutesListView.DoubleClick += editButton_Click;
            // 
            // columnHeader1
            // 
            columnHeader1.Text = "Route";
            columnHeader1.Width = 100;
            // 
            // columnHeader2
            // 
            columnHeader2.Width = 220;
            // 
            // addAprsButton
            // 
            addAprsButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            addAprsButton.Location = new System.Drawing.Point(149, 201);
            addAprsButton.Margin = new System.Windows.Forms.Padding(5);
            addAprsButton.Name = "addAprsButton";
            addAprsButton.Size = new System.Drawing.Size(101, 35);
            addAprsButton.TabIndex = 1;
            addAprsButton.Text = "Add...";
            addAprsButton.UseVisualStyleBackColor = true;
            addAprsButton.Click += addAprsButton_Click;
            // 
            // deleteAprsButton
            // 
            deleteAprsButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            deleteAprsButton.Enabled = false;
            deleteAprsButton.Location = new System.Drawing.Point(365, 201);
            deleteAprsButton.Margin = new System.Windows.Forms.Padding(5);
            deleteAprsButton.Name = "deleteAprsButton";
            deleteAprsButton.Size = new System.Drawing.Size(101, 35);
            deleteAprsButton.TabIndex = 0;
            deleteAprsButton.Text = "Delete";
            deleteAprsButton.UseVisualStyleBackColor = true;
            deleteAprsButton.Click += deleteAprsButton_Click;
            // 
            // voiceTabPage
            // 
            voiceTabPage.Controls.Add(groupBox6);
            voiceTabPage.Controls.Add(progressBar);
            voiceTabPage.Controls.Add(pictureBox5);
            voiceTabPage.Controls.Add(label10);
            voiceTabPage.Controls.Add(groupBox5);
            voiceTabPage.Location = new System.Drawing.Point(4, 29);
            voiceTabPage.Name = "voiceTabPage";
            voiceTabPage.Size = new System.Drawing.Size(493, 540);
            voiceTabPage.TabIndex = 4;
            voiceTabPage.Text = "Voice";
            voiceTabPage.UseVisualStyleBackColor = true;
            // 
            // groupBox6
            // 
            groupBox6.Controls.Add(label14);
            groupBox6.Controls.Add(voicesComboBox);
            groupBox6.Location = new System.Drawing.Point(8, 305);
            groupBox6.Margin = new System.Windows.Forms.Padding(5);
            groupBox6.Name = "groupBox6";
            groupBox6.Padding = new System.Windows.Forms.Padding(5);
            groupBox6.Size = new System.Drawing.Size(473, 85);
            groupBox6.TabIndex = 8;
            groupBox6.TabStop = false;
            groupBox6.Text = "Text-to-Speech";
            // 
            // label14
            // 
            label14.AutoSize = true;
            label14.Location = new System.Drawing.Point(7, 40);
            label14.Name = "label14";
            label14.Size = new System.Drawing.Size(45, 20);
            label14.TabIndex = 6;
            label14.Text = "Voice";
            // 
            // voicesComboBox
            // 
            voicesComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            voicesComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            voicesComboBox.FormattingEnabled = true;
            voicesComboBox.Location = new System.Drawing.Point(149, 37);
            voicesComboBox.Name = "voicesComboBox";
            voicesComboBox.Size = new System.Drawing.Size(316, 28);
            voicesComboBox.TabIndex = 5;
            // 
            // progressBar
            // 
            progressBar.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            progressBar.Location = new System.Drawing.Point(8, 493);
            progressBar.Name = "progressBar";
            progressBar.Size = new System.Drawing.Size(473, 29);
            progressBar.TabIndex = 7;
            progressBar.Visible = false;
            // 
            // pictureBox5
            // 
            pictureBox5.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox5.Image = Properties.Resources.Voice;
            pictureBox5.Location = new System.Drawing.Point(397, 12);
            pictureBox5.Margin = new System.Windows.Forms.Padding(5);
            pictureBox5.Name = "pictureBox5";
            pictureBox5.Size = new System.Drawing.Size(91, 119);
            pictureBox5.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox5.TabIndex = 6;
            pictureBox5.TabStop = false;
            // 
            // label10
            // 
            label10.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label10.Location = new System.Drawing.Point(8, 17);
            label10.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label10.Name = "label10";
            label10.Size = new System.Drawing.Size(381, 113);
            label10.TabIndex = 5;
            label10.Text = resources.GetString("label10.Text");
            // 
            // groupBox5
            // 
            groupBox5.Controls.Add(cancelDownloadButton);
            groupBox5.Controls.Add(label12);
            groupBox5.Controls.Add(modelsComboBox);
            groupBox5.Controls.Add(label11);
            groupBox5.Controls.Add(languageComboBox);
            groupBox5.Controls.Add(downloadButton);
            groupBox5.Controls.Add(deleteButton);
            groupBox5.Location = new System.Drawing.Point(8, 135);
            groupBox5.Margin = new System.Windows.Forms.Padding(5);
            groupBox5.Name = "groupBox5";
            groupBox5.Padding = new System.Windows.Forms.Padding(5);
            groupBox5.Size = new System.Drawing.Size(473, 160);
            groupBox5.TabIndex = 4;
            groupBox5.TabStop = false;
            groupBox5.Text = "Speech-to-Text";
            // 
            // cancelDownloadButton
            // 
            cancelDownloadButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            cancelDownloadButton.Location = new System.Drawing.Point(149, 113);
            cancelDownloadButton.Margin = new System.Windows.Forms.Padding(5);
            cancelDownloadButton.Name = "cancelDownloadButton";
            cancelDownloadButton.Size = new System.Drawing.Size(101, 35);
            cancelDownloadButton.TabIndex = 9;
            cancelDownloadButton.Text = "Cancel";
            cancelDownloadButton.UseVisualStyleBackColor = true;
            cancelDownloadButton.Visible = false;
            cancelDownloadButton.Click += cancelDownloadButton_Click;
            // 
            // label12
            // 
            label12.AutoSize = true;
            label12.Location = new System.Drawing.Point(7, 77);
            label12.Name = "label12";
            label12.Size = new System.Drawing.Size(52, 20);
            label12.TabIndex = 8;
            label12.Text = "Model";
            // 
            // modelsComboBox
            // 
            modelsComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            modelsComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            modelsComboBox.FormattingEnabled = true;
            modelsComboBox.Location = new System.Drawing.Point(149, 73);
            modelsComboBox.Name = "modelsComboBox";
            modelsComboBox.Size = new System.Drawing.Size(316, 28);
            modelsComboBox.TabIndex = 7;
            modelsComboBox.SelectedIndexChanged += modelsComboBox_SelectedIndexChanged;
            // 
            // label11
            // 
            label11.AutoSize = true;
            label11.Location = new System.Drawing.Point(7, 40);
            label11.Name = "label11";
            label11.Size = new System.Drawing.Size(74, 20);
            label11.TabIndex = 6;
            label11.Text = "Language";
            // 
            // languageComboBox
            // 
            languageComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            languageComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            languageComboBox.FormattingEnabled = true;
            languageComboBox.Location = new System.Drawing.Point(149, 37);
            languageComboBox.Name = "languageComboBox";
            languageComboBox.Size = new System.Drawing.Size(316, 28);
            languageComboBox.TabIndex = 5;
            // 
            // downloadButton
            // 
            downloadButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            downloadButton.Location = new System.Drawing.Point(257, 115);
            downloadButton.Margin = new System.Windows.Forms.Padding(5);
            downloadButton.Name = "downloadButton";
            downloadButton.Size = new System.Drawing.Size(101, 35);
            downloadButton.TabIndex = 1;
            downloadButton.Text = "Download...";
            downloadButton.UseVisualStyleBackColor = true;
            downloadButton.Click += downloadButton_Click;
            // 
            // deleteButton
            // 
            deleteButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            deleteButton.Enabled = false;
            deleteButton.Location = new System.Drawing.Point(365, 115);
            deleteButton.Margin = new System.Windows.Forms.Padding(5);
            deleteButton.Name = "deleteButton";
            deleteButton.Size = new System.Drawing.Size(101, 35);
            deleteButton.TabIndex = 0;
            deleteButton.Text = "Delete";
            deleteButton.UseVisualStyleBackColor = true;
            deleteButton.Click += deleteButton_Click;
            // 
            // winlinkTabPage
            // 
            winlinkTabPage.Controls.Add(winlinkStationIdCheckBox);
            winlinkTabPage.Controls.Add(linkLabel2);
            winlinkTabPage.Controls.Add(groupBox4);
            winlinkTabPage.Controls.Add(label9);
            winlinkTabPage.Controls.Add(pictureBox4);
            winlinkTabPage.Location = new System.Drawing.Point(4, 29);
            winlinkTabPage.Name = "winlinkTabPage";
            winlinkTabPage.Size = new System.Drawing.Size(493, 540);
            winlinkTabPage.TabIndex = 3;
            winlinkTabPage.Text = "Winlink";
            winlinkTabPage.UseVisualStyleBackColor = true;
            // 
            // winlinkStationIdCheckBox
            // 
            winlinkStationIdCheckBox.AutoSize = true;
            winlinkStationIdCheckBox.Location = new System.Drawing.Point(11, 361);
            winlinkStationIdCheckBox.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            winlinkStationIdCheckBox.Name = "winlinkStationIdCheckBox";
            winlinkStationIdCheckBox.Size = new System.Drawing.Size(251, 24);
            winlinkStationIdCheckBox.TabIndex = 8;
            winlinkStationIdCheckBox.Text = "Use station ID to get/send emails";
            winlinkStationIdCheckBox.UseVisualStyleBackColor = true;
            // 
            // linkLabel2
            // 
            linkLabel2.AutoSize = true;
            linkLabel2.Location = new System.Drawing.Point(8, 97);
            linkLabel2.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            linkLabel2.Name = "linkLabel2";
            linkLabel2.Size = new System.Drawing.Size(81, 20);
            linkLabel2.TabIndex = 7;
            linkLabel2.TabStop = true;
            linkLabel2.Text = "winlink.org";
            linkLabel2.LinkClicked += linkLabel2_LinkClicked;
            // 
            // groupBox4
            // 
            groupBox4.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            groupBox4.Controls.Add(label7);
            groupBox4.Controls.Add(winlinkAccountTextBox);
            groupBox4.Controls.Add(label8);
            groupBox4.Controls.Add(winlinkPasswordTextBox);
            groupBox4.Location = new System.Drawing.Point(11, 141);
            groupBox4.Margin = new System.Windows.Forms.Padding(5);
            groupBox4.Name = "groupBox4";
            groupBox4.Padding = new System.Windows.Forms.Padding(5);
            groupBox4.Size = new System.Drawing.Size(469, 199);
            groupBox4.TabIndex = 6;
            groupBox4.TabStop = false;
            groupBox4.Text = "Winlink Credentials";
            // 
            // label7
            // 
            label7.AutoSize = true;
            label7.Location = new System.Drawing.Point(8, 32);
            label7.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label7.Name = "label7";
            label7.Size = new System.Drawing.Size(63, 20);
            label7.TabIndex = 4;
            label7.Text = "Account";
            // 
            // winlinkAccountTextBox
            // 
            winlinkAccountTextBox.Location = new System.Drawing.Point(11, 63);
            winlinkAccountTextBox.Name = "winlinkAccountTextBox";
            winlinkAccountTextBox.ReadOnly = true;
            winlinkAccountTextBox.Size = new System.Drawing.Size(449, 27);
            winlinkAccountTextBox.TabIndex = 3;
            // 
            // label8
            // 
            label8.AutoSize = true;
            label8.Location = new System.Drawing.Point(8, 103);
            label8.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label8.Name = "label8";
            label8.Size = new System.Drawing.Size(70, 20);
            label8.TabIndex = 2;
            label8.Text = "Password";
            // 
            // winlinkPasswordTextBox
            // 
            winlinkPasswordTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            winlinkPasswordTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            winlinkPasswordTextBox.Location = new System.Drawing.Point(8, 137);
            winlinkPasswordTextBox.Margin = new System.Windows.Forms.Padding(5);
            winlinkPasswordTextBox.MaxLength = 128;
            winlinkPasswordTextBox.Name = "winlinkPasswordTextBox";
            winlinkPasswordTextBox.PasswordChar = '●';
            winlinkPasswordTextBox.Size = new System.Drawing.Size(453, 37);
            winlinkPasswordTextBox.TabIndex = 0;
            // 
            // label9
            // 
            label9.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label9.Location = new System.Drawing.Point(8, 17);
            label9.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label9.Name = "label9";
            label9.Size = new System.Drawing.Size(381, 113);
            label9.TabIndex = 4;
            label9.Text = "You can send and receive emails with this software using Winlink. Create an account with your callsign and enter you password account here to get started.";
            // 
            // pictureBox4
            // 
            pictureBox4.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox4.Image = Properties.Resources.Letter;
            pictureBox4.Location = new System.Drawing.Point(397, 12);
            pictureBox4.Margin = new System.Windows.Forms.Padding(5);
            pictureBox4.Name = "pictureBox4";
            pictureBox4.Size = new System.Drawing.Size(91, 119);
            pictureBox4.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox4.TabIndex = 5;
            pictureBox4.TabStop = false;
            // 
            // webServerTabPage
            // 
            webServerTabPage.Controls.Add(groupBox3);
            webServerTabPage.Controls.Add(label5);
            webServerTabPage.Controls.Add(pictureBox3);
            webServerTabPage.Location = new System.Drawing.Point(4, 29);
            webServerTabPage.Margin = new System.Windows.Forms.Padding(5);
            webServerTabPage.Name = "webServerTabPage";
            webServerTabPage.Size = new System.Drawing.Size(493, 540);
            webServerTabPage.TabIndex = 2;
            webServerTabPage.Text = "Services";
            webServerTabPage.UseVisualStyleBackColor = true;
            // 
            // groupBox3
            // 
            groupBox3.Controls.Add(agwpePortNumericUpDown);
            groupBox3.Controls.Add(label13);
            groupBox3.Controls.Add(webPortNumericUpDown);
            groupBox3.Controls.Add(agwpeServerEnabledCheckBox);
            groupBox3.Controls.Add(label6);
            groupBox3.Controls.Add(webServerEnabledCheckBox);
            groupBox3.Location = new System.Drawing.Point(8, 135);
            groupBox3.Margin = new System.Windows.Forms.Padding(5);
            groupBox3.Name = "groupBox3";
            groupBox3.Padding = new System.Windows.Forms.Padding(5);
            groupBox3.Size = new System.Drawing.Size(473, 124);
            groupBox3.TabIndex = 6;
            groupBox3.TabStop = false;
            groupBox3.Text = "Server Settings";
            // 
            // agwpePortNumericUpDown
            // 
            agwpePortNumericUpDown.Location = new System.Drawing.Point(383, 77);
            agwpePortNumericUpDown.Margin = new System.Windows.Forms.Padding(5);
            agwpePortNumericUpDown.Maximum = new decimal(new int[] { 65535, 0, 0, 0 });
            agwpePortNumericUpDown.Minimum = new decimal(new int[] { 1, 0, 0, 0 });
            agwpePortNumericUpDown.Name = "agwpePortNumericUpDown";
            agwpePortNumericUpDown.Size = new System.Drawing.Size(82, 27);
            agwpePortNumericUpDown.TabIndex = 2;
            agwpePortNumericUpDown.TextAlign = System.Windows.Forms.HorizontalAlignment.Right;
            agwpePortNumericUpDown.Value = new decimal(new int[] { 8000, 0, 0, 0 });
            agwpePortNumericUpDown.ValueChanged += agwpePortNumericUpDown_ValueChanged;
            // 
            // label13
            // 
            label13.AutoSize = true;
            label13.Location = new System.Drawing.Point(344, 80);
            label13.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label13.Name = "label13";
            label13.Size = new System.Drawing.Size(35, 20);
            label13.TabIndex = 1;
            label13.Text = "Port";
            // 
            // webPortNumericUpDown
            // 
            webPortNumericUpDown.Location = new System.Drawing.Point(383, 40);
            webPortNumericUpDown.Margin = new System.Windows.Forms.Padding(5);
            webPortNumericUpDown.Maximum = new decimal(new int[] { 65535, 0, 0, 0 });
            webPortNumericUpDown.Minimum = new decimal(new int[] { 1, 0, 0, 0 });
            webPortNumericUpDown.Name = "webPortNumericUpDown";
            webPortNumericUpDown.Size = new System.Drawing.Size(82, 27);
            webPortNumericUpDown.TabIndex = 2;
            webPortNumericUpDown.TextAlign = System.Windows.Forms.HorizontalAlignment.Right;
            webPortNumericUpDown.Value = new decimal(new int[] { 8080, 0, 0, 0 });
            webPortNumericUpDown.ValueChanged += webPortNumericUpDown_ValueChanged;
            // 
            // agwpeServerEnabledCheckBox
            // 
            agwpeServerEnabledCheckBox.AutoSize = true;
            agwpeServerEnabledCheckBox.Location = new System.Drawing.Point(21, 79);
            agwpeServerEnabledCheckBox.Margin = new System.Windows.Forms.Padding(5);
            agwpeServerEnabledCheckBox.Name = "agwpeServerEnabledCheckBox";
            agwpeServerEnabledCheckBox.Size = new System.Drawing.Size(175, 24);
            agwpeServerEnabledCheckBox.TabIndex = 0;
            agwpeServerEnabledCheckBox.Text = "Enable AGWPE Server";
            agwpeServerEnabledCheckBox.UseVisualStyleBackColor = true;
            agwpeServerEnabledCheckBox.CheckedChanged += tncServerEnabledCheckBox_CheckedChanged;
            // 
            // label6
            // 
            label6.AutoSize = true;
            label6.Location = new System.Drawing.Point(344, 43);
            label6.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label6.Name = "label6";
            label6.Size = new System.Drawing.Size(35, 20);
            label6.TabIndex = 1;
            label6.Text = "Port";
            // 
            // webServerEnabledCheckBox
            // 
            webServerEnabledCheckBox.AutoSize = true;
            webServerEnabledCheckBox.Location = new System.Drawing.Point(21, 43);
            webServerEnabledCheckBox.Margin = new System.Windows.Forms.Padding(5);
            webServerEnabledCheckBox.Name = "webServerEnabledCheckBox";
            webServerEnabledCheckBox.Size = new System.Drawing.Size(155, 24);
            webServerEnabledCheckBox.TabIndex = 0;
            webServerEnabledCheckBox.Text = "Enable Web Server";
            webServerEnabledCheckBox.UseVisualStyleBackColor = true;
            webServerEnabledCheckBox.CheckedChanged += webServerEnabledCheckBox_CheckedChanged;
            // 
            // label5
            // 
            label5.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label5.Location = new System.Drawing.Point(8, 17);
            label5.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label5.Name = "label5";
            label5.Size = new System.Drawing.Size(381, 113);
            label5.TabIndex = 4;
            label5.Text = "Enable the servers to order to share radio services with other applications including other instances of this application. Allows you to access this radio over the local network.";
            // 
            // pictureBox3
            // 
            pictureBox3.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox3.Image = Properties.Resources.webserver;
            pictureBox3.Location = new System.Drawing.Point(397, 12);
            pictureBox3.Margin = new System.Windows.Forms.Padding(5);
            pictureBox3.Name = "pictureBox3";
            pictureBox3.Size = new System.Drawing.Size(91, 119);
            pictureBox3.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox3.TabIndex = 5;
            pictureBox3.TabStop = false;
            // 
            // airplanesTabPage
            // 
            airplanesTabPage.Controls.Add(groupBox8);
            airplanesTabPage.Controls.Add(groupBox7);
            airplanesTabPage.Controls.Add(label17);
            airplanesTabPage.Controls.Add(pictureBox6);
            airplanesTabPage.Location = new System.Drawing.Point(4, 29);
            airplanesTabPage.Name = "airplanesTabPage";
            airplanesTabPage.Size = new System.Drawing.Size(493, 540);
            airplanesTabPage.TabIndex = 5;
            airplanesTabPage.Text = "Data Sources";
            airplanesTabPage.UseVisualStyleBackColor = true;
            // 
            // groupBox8
            // 
            groupBox8.Controls.Add(gpsStatusLabel);
            groupBox8.Controls.Add(gpsStateButton);
            groupBox8.Controls.Add(gpsBaudRateComboBox);
            groupBox8.Controls.Add(gpsSerialPortComboBox);
            groupBox8.Controls.Add(label18);
            groupBox8.Location = new System.Drawing.Point(8, 302);
            groupBox8.Margin = new System.Windows.Forms.Padding(5);
            groupBox8.Name = "groupBox8";
            groupBox8.Padding = new System.Windows.Forms.Padding(5);
            groupBox8.Size = new System.Drawing.Size(473, 147);
            groupBox8.TabIndex = 10;
            groupBox8.TabStop = false;
            groupBox8.Text = "GPS Device";
            // 
            // gpsStateButton
            // 
            gpsStateButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            gpsStateButton.AutoEllipsis = true;
            gpsStateButton.Location = new System.Drawing.Point(316, 68);
            gpsStateButton.Name = "gpsStateButton";
            gpsStateButton.Size = new System.Drawing.Size(149, 28);
            gpsStateButton.TabIndex = 6;
            gpsStateButton.Text = "GPS Data...";
            gpsStateButton.UseVisualStyleBackColor = true;
            gpsStateButton.Click += gpsStateButton_Click;
            // 
            // gpsBaudRateComboBox
            // 
            gpsBaudRateComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            gpsBaudRateComboBox.FormattingEnabled = true;
            gpsBaudRateComboBox.Location = new System.Drawing.Point(164, 68);
            gpsBaudRateComboBox.Name = "gpsBaudRateComboBox";
            gpsBaudRateComboBox.Size = new System.Drawing.Size(146, 28);
            gpsBaudRateComboBox.TabIndex = 5;
            // 
            // gpsSerialPortComboBox
            // 
            gpsSerialPortComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            gpsSerialPortComboBox.FormattingEnabled = true;
            gpsSerialPortComboBox.Location = new System.Drawing.Point(12, 68);
            gpsSerialPortComboBox.Name = "gpsSerialPortComboBox";
            gpsSerialPortComboBox.Size = new System.Drawing.Size(146, 28);
            gpsSerialPortComboBox.TabIndex = 4;
            // 
            // label18
            // 
            label18.AutoSize = true;
            label18.Location = new System.Drawing.Point(12, 38);
            label18.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label18.Name = "label18";
            label18.Size = new System.Drawing.Size(389, 20);
            label18.TabIndex = 3;
            label18.Text = "Select the serial port and baud rate of NMEA 0183 device";
            // 
            // groupBox7
            // 
            groupBox7.Controls.Add(dump1090testResultsLabel);
            groupBox7.Controls.Add(dump1090testButton);
            groupBox7.Controls.Add(dump1090urlTextBox);
            groupBox7.Controls.Add(label15);
            groupBox7.Location = new System.Drawing.Point(8, 135);
            groupBox7.Margin = new System.Windows.Forms.Padding(5);
            groupBox7.Name = "groupBox7";
            groupBox7.Padding = new System.Windows.Forms.Padding(5);
            groupBox7.Size = new System.Drawing.Size(473, 157);
            groupBox7.TabIndex = 9;
            groupBox7.TabStop = false;
            groupBox7.Text = "Dump1090 ADS-B";
            // 
            // dump1090testResultsLabel
            // 
            dump1090testResultsLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            dump1090testResultsLabel.Location = new System.Drawing.Point(110, 105);
            dump1090testResultsLabel.Name = "dump1090testResultsLabel";
            dump1090testResultsLabel.Size = new System.Drawing.Size(355, 25);
            dump1090testResultsLabel.TabIndex = 6;
            // 
            // dump1090testButton
            // 
            dump1090testButton.Location = new System.Drawing.Point(10, 101);
            dump1090testButton.Name = "dump1090testButton";
            dump1090testButton.Size = new System.Drawing.Size(94, 29);
            dump1090testButton.TabIndex = 5;
            dump1090testButton.Text = "Test";
            dump1090testButton.UseVisualStyleBackColor = true;
            dump1090testButton.Click += dump1090testButton_Click;
            // 
            // dump1090urlTextBox
            // 
            dump1090urlTextBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            dump1090urlTextBox.Location = new System.Drawing.Point(10, 68);
            dump1090urlTextBox.Name = "dump1090urlTextBox";
            dump1090urlTextBox.Size = new System.Drawing.Size(455, 27);
            dump1090urlTextBox.TabIndex = 4;
            dump1090urlTextBox.TextChanged += dump1090urlTextBox_TextChanged;
            // 
            // label15
            // 
            label15.AutoSize = true;
            label15.Location = new System.Drawing.Point(10, 36);
            label15.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label15.Name = "label15";
            label15.Size = new System.Drawing.Size(379, 20);
            label15.TabIndex = 3;
            label15.Text = "Enter the hostname:port or URL of the Dump1090 server";
            // 
            // label17
            // 
            label17.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label17.Location = new System.Drawing.Point(8, 17);
            label17.Margin = new System.Windows.Forms.Padding(5, 0, 5, 0);
            label17.Name = "label17";
            label17.Size = new System.Drawing.Size(381, 113);
            label17.TabIndex = 7;
            label17.Text = "If you have a Dump1090 ADS-B server on your local network or a serial GPS device, configure them here to make use of this data.";
            // 
            // pictureBox6
            // 
            pictureBox6.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox6.Image = Properties.Resources.webserver;
            pictureBox6.Location = new System.Drawing.Point(397, 12);
            pictureBox6.Margin = new System.Windows.Forms.Padding(5);
            pictureBox6.Name = "pictureBox6";
            pictureBox6.Size = new System.Drawing.Size(91, 119);
            pictureBox6.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox6.TabIndex = 8;
            pictureBox6.TabStop = false;
            // 
            // okButton
            // 
            okButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            okButton.Location = new System.Drawing.Point(311, 601);
            okButton.Margin = new System.Windows.Forms.Padding(5);
            okButton.Name = "okButton";
            okButton.Size = new System.Drawing.Size(101, 35);
            okButton.TabIndex = 16;
            okButton.Text = "OK";
            okButton.UseVisualStyleBackColor = true;
            okButton.Click += okButton_Click;
            // 
            // cancelButton
            // 
            cancelButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            cancelButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            cancelButton.Location = new System.Drawing.Point(411, 601);
            cancelButton.Margin = new System.Windows.Forms.Padding(5);
            cancelButton.Name = "cancelButton";
            cancelButton.Size = new System.Drawing.Size(101, 35);
            cancelButton.TabIndex = 15;
            cancelButton.Text = "Cancel";
            cancelButton.UseVisualStyleBackColor = true;
            cancelButton.Click += cancelButton_Click;
            // 
            // gpsStatusLabel
            // 
            gpsStatusLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            gpsStatusLabel.Location = new System.Drawing.Point(12, 108);
            gpsStatusLabel.Name = "gpsStatusLabel";
            gpsStatusLabel.Size = new System.Drawing.Size(453, 25);
            gpsStatusLabel.TabIndex = 7;
            // 
            // SettingsForm
            // 
            AcceptButton = okButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            CancelButton = cancelButton;
            ClientSize = new System.Drawing.Size(533, 655);
            Controls.Add(okButton);
            Controls.Add(cancelButton);
            Controls.Add(tabControl1);
            FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "SettingsForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "Settings";
            Load += SettingsForm_Load;
            tabControl1.ResumeLayout(false);
            licenseTabPage.ResumeLayout(false);
            licenseTabPage.PerformLayout();
            groupBox1.ResumeLayout(false);
            groupBox1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox1).EndInit();
            aprsTabPage.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)pictureBox2).EndInit();
            groupBox2.ResumeLayout(false);
            voiceTabPage.ResumeLayout(false);
            groupBox6.ResumeLayout(false);
            groupBox6.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox5).EndInit();
            groupBox5.ResumeLayout(false);
            groupBox5.PerformLayout();
            winlinkTabPage.ResumeLayout(false);
            winlinkTabPage.PerformLayout();
            groupBox4.ResumeLayout(false);
            groupBox4.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox4).EndInit();
            webServerTabPage.ResumeLayout(false);
            groupBox3.ResumeLayout(false);
            groupBox3.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)agwpePortNumericUpDown).EndInit();
            ((System.ComponentModel.ISupportInitialize)webPortNumericUpDown).EndInit();
            ((System.ComponentModel.ISupportInitialize)pictureBox3).EndInit();
            airplanesTabPage.ResumeLayout(false);
            groupBox8.ResumeLayout(false);
            groupBox8.PerformLayout();
            groupBox7.ResumeLayout(false);
            groupBox7.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox6).EndInit();
            ResumeLayout(false);

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
        private System.Windows.Forms.TabPage voiceTabPage;
        private System.Windows.Forms.PictureBox pictureBox5;
        private System.Windows.Forms.Label label10;
        private System.Windows.Forms.GroupBox groupBox5;
        private System.Windows.Forms.Button downloadButton;
        private System.Windows.Forms.Button deleteButton;
        private System.Windows.Forms.Label label11;
        private System.Windows.Forms.ComboBox languageComboBox;
        private System.Windows.Forms.Label label12;
        private System.Windows.Forms.ComboBox modelsComboBox;
        private System.Windows.Forms.ProgressBar progressBar;
        private System.Windows.Forms.GroupBox groupBox6;
        private System.Windows.Forms.Label label14;
        private System.Windows.Forms.ComboBox voicesComboBox;
        private System.Windows.Forms.Button cancelDownloadButton;
        private System.Windows.Forms.NumericUpDown agwpePortNumericUpDown;
        private System.Windows.Forms.Label label13;
        private System.Windows.Forms.CheckBox agwpeServerEnabledCheckBox;
        private System.Windows.Forms.CheckBox winlinkStationIdCheckBox;
        private System.Windows.Forms.TabPage airplanesTabPage;
        private System.Windows.Forms.GroupBox groupBox7;
        private System.Windows.Forms.Label label17;
        private System.Windows.Forms.PictureBox pictureBox6;
        private System.Windows.Forms.TextBox dump1090urlTextBox;
        private System.Windows.Forms.Label label15;
        private System.Windows.Forms.Label dump1090testResultsLabel;
        private System.Windows.Forms.Button dump1090testButton;
        private System.Windows.Forms.GroupBox groupBox8;
        private System.Windows.Forms.Label label18;
        private System.Windows.Forms.ComboBox gpsBaudRateComboBox;
        private System.Windows.Forms.ComboBox gpsSerialPortComboBox;
        private System.Windows.Forms.Button gpsStateButton;
        private System.Windows.Forms.Label gpsStatusLabel;
    }
}