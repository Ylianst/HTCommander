namespace HTCommander
{
    partial class MainForm
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
            components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(MainForm));
            mainStatusStrip = new System.Windows.Forms.StatusStrip();
            mainToolStripStatusLabel = new System.Windows.Forms.ToolStripStatusLabel();
            batteryToolStripStatusLabel = new System.Windows.Forms.ToolStripStatusLabel();
            mainMenuStrip = new System.Windows.Forms.MenuStrip();
            fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            connectToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            disconnectToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            settingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            launchAnotherInstanceToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem4 = new System.Windows.Forms.ToolStripSeparator();
            exitToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem21 = new System.Windows.Forms.ToolStripMenuItem();
            dualWatchToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            scanToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            regionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            gPSEnabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripSeparator1 = new System.Windows.Forms.ToolStripSeparator();
            exportChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            importChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            audioToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            audioEnabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            volumeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            audioClipsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            spectrogramToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            softwareModemToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            disabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            aFK1200ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            pSK2400ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            pSK4800ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            g9600ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            viewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            radioToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            allChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            aboutToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            radioInformationToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            localWebSiteToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem5 = new System.Windows.Forms.ToolStripSeparator();
            checkForUpdatesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            aboutToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            mainTabControl = new System.Windows.Forms.TabControl();
            aprsTabPage = new System.Windows.Forms.TabPage();
            aprsTabUserControl = new HTCommander.Controls.AprsTabUserControl();
            mapTabPage = new System.Windows.Forms.TabPage();
            mapTabUserControl = new HTCommander.Controls.MapTabUserControl();
            voiceTabPage = new System.Windows.Forms.TabPage();
            voiceTabUserControl = new HTCommander.Controls.VoiceTabUserControl();
            mailTabPage = new System.Windows.Forms.TabPage();
            mailTabUserControl = new HTCommander.Controls.MailTabUserControl();
            terminalTabPage = new System.Windows.Forms.TabPage();
            terminalTabUserControl = new HTCommander.Controls.TerminalTabUserControl();
            addressesTabPage = new System.Windows.Forms.TabPage();
            contactsTabUserControl = new HTCommander.Controls.ContactsTabUserControl();
            bbsTabPage = new System.Windows.Forms.TabPage();
            bbsTabUserControl = new HTCommander.Controls.BbsTabUserControl();
            torrentTabPage = new System.Windows.Forms.TabPage();
            torrentTabUserControl = new HTCommander.Controls.TorrentTabUserControl();
            packetsTabPage = new System.Windows.Forms.TabPage();
            packetCaptureTabUserControl = new HTCommander.Controls.PacketCaptureTabUserControl();
            debugTabPage = new System.Windows.Forms.TabPage();
            debugTabUserControl = new HTCommander.Controls.DebugTabUserControl();
            tabsImageList = new System.Windows.Forms.ImageList(components);
            mainImageList = new System.Windows.Forms.ImageList(components);
            radioPanel = new System.Windows.Forms.Panel();
            radioPanelControl = new HTCommander.RadioControls.RadioPanelControl();
            radioWindowToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            mainStatusStrip.SuspendLayout();
            mainMenuStrip.SuspendLayout();
            mainTabControl.SuspendLayout();
            aprsTabPage.SuspendLayout();
            mapTabPage.SuspendLayout();
            voiceTabPage.SuspendLayout();
            mailTabPage.SuspendLayout();
            terminalTabPage.SuspendLayout();
            addressesTabPage.SuspendLayout();
            bbsTabPage.SuspendLayout();
            torrentTabPage.SuspendLayout();
            packetsTabPage.SuspendLayout();
            debugTabPage.SuspendLayout();
            radioPanel.SuspendLayout();
            SuspendLayout();
            // 
            // mainStatusStrip
            // 
            mainStatusStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mainStatusStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { mainToolStripStatusLabel, batteryToolStripStatusLabel });
            mainStatusStrip.Location = new System.Drawing.Point(0, 870);
            mainStatusStrip.Name = "mainStatusStrip";
            mainStatusStrip.Padding = new System.Windows.Forms.Padding(1, 0, 19, 0);
            mainStatusStrip.Size = new System.Drawing.Size(1084, 22);
            mainStatusStrip.TabIndex = 0;
            mainStatusStrip.Text = "statusStrip1";
            // 
            // mainToolStripStatusLabel
            // 
            mainToolStripStatusLabel.Name = "mainToolStripStatusLabel";
            mainToolStripStatusLabel.Size = new System.Drawing.Size(1064, 16);
            mainToolStripStatusLabel.Spring = true;
            // 
            // batteryToolStripStatusLabel
            // 
            batteryToolStripStatusLabel.Name = "batteryToolStripStatusLabel";
            batteryToolStripStatusLabel.Size = new System.Drawing.Size(56, 20);
            batteryToolStripStatusLabel.Text = "Battery";
            batteryToolStripStatusLabel.TextAlign = System.Drawing.ContentAlignment.MiddleRight;
            batteryToolStripStatusLabel.Visible = false;
            // 
            // mainMenuStrip
            // 
            mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { fileToolStripMenuItem, toolStripMenuItem21, audioToolStripMenuItem1, viewToolStripMenuItem, aboutToolStripMenuItem });
            mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            mainMenuStrip.Name = "mainMenuStrip";
            mainMenuStrip.Padding = new System.Windows.Forms.Padding(5, 1, 0, 1);
            mainMenuStrip.Size = new System.Drawing.Size(1084, 26);
            mainMenuStrip.TabIndex = 1;
            mainMenuStrip.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { connectToolStripMenuItem, disconnectToolStripMenuItem, toolStripMenuItem1, settingsToolStripMenuItem, launchAnotherInstanceToolStripMenuItem, toolStripMenuItem4, exitToolStripMenuItem });
            fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            fileToolStripMenuItem.Size = new System.Drawing.Size(46, 24);
            fileToolStripMenuItem.Text = "&File";
            fileToolStripMenuItem.DropDownOpening += fileToolStripMenuItem_DropDownOpening;
            // 
            // connectToolStripMenuItem
            // 
            connectToolStripMenuItem.Name = "connectToolStripMenuItem";
            connectToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            connectToolStripMenuItem.Text = "&Connect...";
            connectToolStripMenuItem.Click += connectToolStripMenuItem_Click;
            // 
            // disconnectToolStripMenuItem
            // 
            disconnectToolStripMenuItem.Enabled = false;
            disconnectToolStripMenuItem.Name = "disconnectToolStripMenuItem";
            disconnectToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            disconnectToolStripMenuItem.Text = "&Disconnect";
            disconnectToolStripMenuItem.Click += disconnectToolStripMenuItem_Click;
            // 
            // toolStripMenuItem1
            // 
            toolStripMenuItem1.Name = "toolStripMenuItem1";
            toolStripMenuItem1.Size = new System.Drawing.Size(250, 6);
            // 
            // settingsToolStripMenuItem
            // 
            settingsToolStripMenuItem.Name = "settingsToolStripMenuItem";
            settingsToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            settingsToolStripMenuItem.Text = "&Settings...";
            settingsToolStripMenuItem.Click += settingsToolStripMenuItem_Click;
            // 
            // launchAnotherInstanceToolStripMenuItem
            // 
            launchAnotherInstanceToolStripMenuItem.Name = "launchAnotherInstanceToolStripMenuItem";
            launchAnotherInstanceToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            launchAnotherInstanceToolStripMenuItem.Text = "Launch Another Instance";
            launchAnotherInstanceToolStripMenuItem.Visible = false;
            // 
            // toolStripMenuItem4
            // 
            toolStripMenuItem4.Name = "toolStripMenuItem4";
            toolStripMenuItem4.Size = new System.Drawing.Size(250, 6);
            // 
            // exitToolStripMenuItem
            // 
            exitToolStripMenuItem.Name = "exitToolStripMenuItem";
            exitToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            exitToolStripMenuItem.Text = "E&xit";
            exitToolStripMenuItem.Click += exitToolStripMenuItem_Click;
            // 
            // toolStripMenuItem21
            // 
            toolStripMenuItem21.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { dualWatchToolStripMenuItem, scanToolStripMenuItem, regionToolStripMenuItem, gPSEnabledToolStripMenuItem, toolStripSeparator1, exportChannelsToolStripMenuItem, importChannelsToolStripMenuItem });
            toolStripMenuItem21.Name = "toolStripMenuItem21";
            toolStripMenuItem21.Size = new System.Drawing.Size(76, 24);
            toolStripMenuItem21.Text = "&Settings";
            // 
            // dualWatchToolStripMenuItem
            // 
            dualWatchToolStripMenuItem.Enabled = false;
            dualWatchToolStripMenuItem.Name = "dualWatchToolStripMenuItem";
            dualWatchToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            dualWatchToolStripMenuItem.Text = "&Dual-Watch";
            // 
            // scanToolStripMenuItem
            // 
            scanToolStripMenuItem.Enabled = false;
            scanToolStripMenuItem.Name = "scanToolStripMenuItem";
            scanToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            scanToolStripMenuItem.Text = "&Scan";
            // 
            // regionToolStripMenuItem
            // 
            regionToolStripMenuItem.Enabled = false;
            regionToolStripMenuItem.Name = "regionToolStripMenuItem";
            regionToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            regionToolStripMenuItem.Text = "&Regions";
            // 
            // gPSEnabledToolStripMenuItem
            // 
            gPSEnabledToolStripMenuItem.CheckOnClick = true;
            gPSEnabledToolStripMenuItem.Name = "gPSEnabledToolStripMenuItem";
            gPSEnabledToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            gPSEnabledToolStripMenuItem.Text = "&GPS Enabled";
            // 
            // toolStripSeparator1
            // 
            toolStripSeparator1.Name = "toolStripSeparator1";
            toolStripSeparator1.Size = new System.Drawing.Size(206, 6);
            // 
            // exportChannelsToolStripMenuItem
            // 
            exportChannelsToolStripMenuItem.Enabled = false;
            exportChannelsToolStripMenuItem.Name = "exportChannelsToolStripMenuItem";
            exportChannelsToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            exportChannelsToolStripMenuItem.Text = "&Export Channels...";
            // 
            // importChannelsToolStripMenuItem
            // 
            importChannelsToolStripMenuItem.Name = "importChannelsToolStripMenuItem";
            importChannelsToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            importChannelsToolStripMenuItem.Text = "&Import Channels...";
            // 
            // audioToolStripMenuItem1
            // 
            audioToolStripMenuItem1.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { audioEnabledToolStripMenuItem, volumeToolStripMenuItem, audioClipsToolStripMenuItem, spectrogramToolStripMenuItem, softwareModemToolStripMenuItem });
            audioToolStripMenuItem1.Name = "audioToolStripMenuItem1";
            audioToolStripMenuItem1.Size = new System.Drawing.Size(63, 24);
            audioToolStripMenuItem1.Text = "A&udio";
            // 
            // audioEnabledToolStripMenuItem
            // 
            audioEnabledToolStripMenuItem.Name = "audioEnabledToolStripMenuItem";
            audioEnabledToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            audioEnabledToolStripMenuItem.Text = "&Audio Enabled";
            // 
            // volumeToolStripMenuItem
            // 
            volumeToolStripMenuItem.Name = "volumeToolStripMenuItem";
            volumeToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            volumeToolStripMenuItem.Text = "Audio &Controls...";
            // 
            // audioClipsToolStripMenuItem
            // 
            audioClipsToolStripMenuItem.Name = "audioClipsToolStripMenuItem";
            audioClipsToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            audioClipsToolStripMenuItem.Text = "Audio C&lips...";
            // 
            // spectrogramToolStripMenuItem
            // 
            spectrogramToolStripMenuItem.Name = "spectrogramToolStripMenuItem";
            spectrogramToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            spectrogramToolStripMenuItem.Text = "Spectrogram...";
            // 
            // softwareModemToolStripMenuItem
            // 
            softwareModemToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { disabledToolStripMenuItem, aFK1200ToolStripMenuItem, pSK2400ToolStripMenuItem, pSK4800ToolStripMenuItem, g9600ToolStripMenuItem });
            softwareModemToolStripMenuItem.Name = "softwareModemToolStripMenuItem";
            softwareModemToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            softwareModemToolStripMenuItem.Text = "Software &Modem";
            // 
            // disabledToolStripMenuItem
            // 
            disabledToolStripMenuItem.Checked = true;
            disabledToolStripMenuItem.CheckOnClick = true;
            disabledToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            disabledToolStripMenuItem.Name = "disabledToolStripMenuItem";
            disabledToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            disabledToolStripMenuItem.Text = "&Disabled";
            // 
            // aFK1200ToolStripMenuItem
            // 
            aFK1200ToolStripMenuItem.CheckOnClick = true;
            aFK1200ToolStripMenuItem.Name = "aFK1200ToolStripMenuItem";
            aFK1200ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            aFK1200ToolStripMenuItem.Text = "AFK &1200";
            // 
            // pSK2400ToolStripMenuItem
            // 
            pSK2400ToolStripMenuItem.CheckOnClick = true;
            pSK2400ToolStripMenuItem.Name = "pSK2400ToolStripMenuItem";
            pSK2400ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            pSK2400ToolStripMenuItem.Text = "PSK &2400";
            pSK2400ToolStripMenuItem.Visible = false;
            // 
            // pSK4800ToolStripMenuItem
            // 
            pSK4800ToolStripMenuItem.CheckOnClick = true;
            pSK4800ToolStripMenuItem.Name = "pSK4800ToolStripMenuItem";
            pSK4800ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            pSK4800ToolStripMenuItem.Text = "PSK &4800";
            pSK4800ToolStripMenuItem.Visible = false;
            // 
            // g9600ToolStripMenuItem
            // 
            g9600ToolStripMenuItem.CheckOnClick = true;
            g9600ToolStripMenuItem.Name = "g9600ToolStripMenuItem";
            g9600ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            g9600ToolStripMenuItem.Text = "G &9600";
            g9600ToolStripMenuItem.Visible = false;
            // 
            // viewToolStripMenuItem
            // 
            viewToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { radioToolStripMenuItem, radioWindowToolStripMenuItem, allChannelsToolStripMenuItem });
            viewToolStripMenuItem.Name = "viewToolStripMenuItem";
            viewToolStripMenuItem.Size = new System.Drawing.Size(55, 24);
            viewToolStripMenuItem.Text = "&View";
            viewToolStripMenuItem.DropDownOpening += viewToolStripMenuItem_DropDownOpening;
            // 
            // radioToolStripMenuItem
            // 
            radioToolStripMenuItem.Checked = true;
            radioToolStripMenuItem.CheckOnClick = true;
            radioToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            radioToolStripMenuItem.Name = "radioToolStripMenuItem";
            radioToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            radioToolStripMenuItem.Text = "&Radio";
            radioToolStripMenuItem.CheckedChanged += radioToolStripMenuItem_CheckedChanged;
            // 
            // allChannelsToolStripMenuItem
            // 
            allChannelsToolStripMenuItem.Name = "allChannelsToolStripMenuItem";
            allChannelsToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            allChannelsToolStripMenuItem.Text = "All Channels";
            allChannelsToolStripMenuItem.Click += allChannelsToolStripMenuItem_Click;
            // 
            // aboutToolStripMenuItem
            // 
            aboutToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { radioInformationToolStripMenuItem, localWebSiteToolStripMenuItem, toolStripMenuItem5, checkForUpdatesToolStripMenuItem, aboutToolStripMenuItem1 });
            aboutToolStripMenuItem.Name = "aboutToolStripMenuItem";
            aboutToolStripMenuItem.Size = new System.Drawing.Size(64, 24);
            aboutToolStripMenuItem.Text = "&About";
            aboutToolStripMenuItem.DropDownOpening += aboutToolStripMenuItem_DropDownOpening;
            // 
            // radioInformationToolStripMenuItem
            // 
            radioInformationToolStripMenuItem.Enabled = false;
            radioInformationToolStripMenuItem.Name = "radioInformationToolStripMenuItem";
            radioInformationToolStripMenuItem.Size = new System.Drawing.Size(222, 26);
            radioInformationToolStripMenuItem.Text = "Radio Information...";
            radioInformationToolStripMenuItem.Click += radioInformationToolStripMenuItem_Click;
            // 
            // localWebSiteToolStripMenuItem
            // 
            localWebSiteToolStripMenuItem.Name = "localWebSiteToolStripMenuItem";
            localWebSiteToolStripMenuItem.Size = new System.Drawing.Size(222, 26);
            localWebSiteToolStripMenuItem.Text = "Local Web Site...";
            localWebSiteToolStripMenuItem.Visible = false;
            // 
            // toolStripMenuItem5
            // 
            toolStripMenuItem5.Name = "toolStripMenuItem5";
            toolStripMenuItem5.Size = new System.Drawing.Size(219, 6);
            // 
            // checkForUpdatesToolStripMenuItem
            // 
            checkForUpdatesToolStripMenuItem.CheckOnClick = true;
            checkForUpdatesToolStripMenuItem.Name = "checkForUpdatesToolStripMenuItem";
            checkForUpdatesToolStripMenuItem.Size = new System.Drawing.Size(222, 26);
            checkForUpdatesToolStripMenuItem.Text = "Check for Updates";
            checkForUpdatesToolStripMenuItem.Click += checkForUpdatesToolStripMenuItem_Click;
            // 
            // aboutToolStripMenuItem1
            // 
            aboutToolStripMenuItem1.Name = "aboutToolStripMenuItem1";
            aboutToolStripMenuItem1.Size = new System.Drawing.Size(222, 26);
            aboutToolStripMenuItem1.Text = "&About...";
            aboutToolStripMenuItem1.Click += aboutToolStripMenuItem1_Click;
            // 
            // mainTabControl
            // 
            mainTabControl.Alignment = System.Windows.Forms.TabAlignment.Right;
            mainTabControl.Controls.Add(aprsTabPage);
            mainTabControl.Controls.Add(mapTabPage);
            mainTabControl.Controls.Add(voiceTabPage);
            mainTabControl.Controls.Add(mailTabPage);
            mainTabControl.Controls.Add(terminalTabPage);
            mainTabControl.Controls.Add(addressesTabPage);
            mainTabControl.Controls.Add(bbsTabPage);
            mainTabControl.Controls.Add(torrentTabPage);
            mainTabControl.Controls.Add(packetsTabPage);
            mainTabControl.Controls.Add(debugTabPage);
            mainTabControl.Dock = System.Windows.Forms.DockStyle.Fill;
            mainTabControl.ImageList = tabsImageList;
            mainTabControl.Location = new System.Drawing.Point(372, 26);
            mainTabControl.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mainTabControl.Multiline = true;
            mainTabControl.Name = "mainTabControl";
            mainTabControl.SelectedIndex = 0;
            mainTabControl.Size = new System.Drawing.Size(712, 844);
            mainTabControl.TabIndex = 3;
            // 
            // aprsTabPage
            // 
            aprsTabPage.Controls.Add(aprsTabUserControl);
            aprsTabPage.ImageIndex = 3;
            aprsTabPage.Location = new System.Drawing.Point(4, 4);
            aprsTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            aprsTabPage.Name = "aprsTabPage";
            aprsTabPage.Size = new System.Drawing.Size(669, 836);
            aprsTabPage.TabIndex = 3;
            aprsTabPage.UseVisualStyleBackColor = true;
            // 
            // aprsTabUserControl
            // 
            aprsTabUserControl.DestinationCallsign = "";
            aprsTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            aprsTabUserControl.Location = new System.Drawing.Point(0, 0);
            aprsTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            aprsTabUserControl.Name = "aprsTabUserControl";
            aprsTabUserControl.SelectedAprsRoute = 0;
            aprsTabUserControl.ShowAllMessages = false;
            aprsTabUserControl.Size = new System.Drawing.Size(669, 836);
            aprsTabUserControl.TabIndex = 0;
            // 
            // mapTabPage
            // 
            mapTabPage.Controls.Add(mapTabUserControl);
            mapTabPage.ImageIndex = 1;
            mapTabPage.Location = new System.Drawing.Point(4, 4);
            mapTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mapTabPage.Name = "mapTabPage";
            mapTabPage.Size = new System.Drawing.Size(669, 836);
            mapTabPage.TabIndex = 0;
            mapTabPage.ToolTipText = "APRS";
            mapTabPage.UseVisualStyleBackColor = true;
            // 
            // mapTabUserControl
            // 
            mapTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            mapTabUserControl.Location = new System.Drawing.Point(0, 0);
            mapTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            mapTabUserControl.Name = "mapTabUserControl";
            mapTabUserControl.Size = new System.Drawing.Size(669, 836);
            mapTabUserControl.TabIndex = 0;
            // 
            // voiceTabPage
            // 
            voiceTabPage.Controls.Add(voiceTabUserControl);
            voiceTabPage.ImageIndex = 9;
            voiceTabPage.Location = new System.Drawing.Point(4, 4);
            voiceTabPage.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            voiceTabPage.Name = "voiceTabPage";
            voiceTabPage.Size = new System.Drawing.Size(669, 836);
            voiceTabPage.TabIndex = 9;
            voiceTabPage.UseVisualStyleBackColor = true;
            // 
            // voiceTabUserControl
            // 
            voiceTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            voiceTabUserControl.Location = new System.Drawing.Point(0, 0);
            voiceTabUserControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            voiceTabUserControl.Name = "voiceTabUserControl";
            voiceTabUserControl.Size = new System.Drawing.Size(669, 836);
            voiceTabUserControl.TabIndex = 0;
            // 
            // mailTabPage
            // 
            mailTabPage.Controls.Add(mailTabUserControl);
            mailTabPage.ImageIndex = 5;
            mailTabPage.Location = new System.Drawing.Point(4, 4);
            mailTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mailTabPage.Name = "mailTabPage";
            mailTabPage.Size = new System.Drawing.Size(669, 836);
            mailTabPage.TabIndex = 5;
            mailTabPage.UseVisualStyleBackColor = true;
            // 
            // mailTabUserControl
            // 
            mailTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            mailTabUserControl.Location = new System.Drawing.Point(0, 0);
            mailTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            mailTabUserControl.Name = "mailTabUserControl";
            mailTabUserControl.Size = new System.Drawing.Size(669, 836);
            mailTabUserControl.TabIndex = 0;
            // 
            // terminalTabPage
            // 
            terminalTabPage.Controls.Add(terminalTabUserControl);
            terminalTabPage.ImageKey = "terminal-32.png";
            terminalTabPage.Location = new System.Drawing.Point(4, 4);
            terminalTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            terminalTabPage.Name = "terminalTabPage";
            terminalTabPage.Size = new System.Drawing.Size(669, 836);
            terminalTabPage.TabIndex = 2;
            terminalTabPage.UseVisualStyleBackColor = true;
            // 
            // terminalTabUserControl
            // 
            terminalTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            terminalTabUserControl.Location = new System.Drawing.Point(0, 0);
            terminalTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            terminalTabUserControl.Name = "terminalTabUserControl";
            terminalTabUserControl.ShowCallsign = false;
            terminalTabUserControl.Size = new System.Drawing.Size(669, 836);
            terminalTabUserControl.TabIndex = 0;
            terminalTabUserControl.WordWrap = false;
            // 
            // addressesTabPage
            // 
            addressesTabPage.Controls.Add(contactsTabUserControl);
            addressesTabPage.ImageIndex = 4;
            addressesTabPage.Location = new System.Drawing.Point(4, 4);
            addressesTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            addressesTabPage.Name = "addressesTabPage";
            addressesTabPage.Size = new System.Drawing.Size(669, 836);
            addressesTabPage.TabIndex = 4;
            addressesTabPage.UseVisualStyleBackColor = true;
            // 
            // contactsTabUserControl
            // 
            contactsTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            contactsTabUserControl.Location = new System.Drawing.Point(0, 0);
            contactsTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            contactsTabUserControl.Name = "contactsTabUserControl";
            contactsTabUserControl.Size = new System.Drawing.Size(669, 836);
            contactsTabUserControl.TabIndex = 0;
            // 
            // bbsTabPage
            // 
            bbsTabPage.Controls.Add(bbsTabUserControl);
            bbsTabPage.ImageIndex = 8;
            bbsTabPage.Location = new System.Drawing.Point(4, 4);
            bbsTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            bbsTabPage.Name = "bbsTabPage";
            bbsTabPage.Size = new System.Drawing.Size(669, 836);
            bbsTabPage.TabIndex = 7;
            bbsTabPage.UseVisualStyleBackColor = true;
            // 
            // bbsTabUserControl
            // 
            bbsTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            bbsTabUserControl.Location = new System.Drawing.Point(0, 0);
            bbsTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            bbsTabUserControl.Name = "bbsTabUserControl";
            bbsTabUserControl.Size = new System.Drawing.Size(669, 836);
            bbsTabUserControl.TabIndex = 0;
            // 
            // torrentTabPage
            // 
            torrentTabPage.Controls.Add(torrentTabUserControl);
            torrentTabPage.ImageIndex = 7;
            torrentTabPage.Location = new System.Drawing.Point(4, 4);
            torrentTabPage.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            torrentTabPage.Name = "torrentTabPage";
            torrentTabPage.Size = new System.Drawing.Size(669, 836);
            torrentTabPage.TabIndex = 8;
            torrentTabPage.UseVisualStyleBackColor = true;
            // 
            // torrentTabUserControl
            // 
            torrentTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            torrentTabUserControl.Location = new System.Drawing.Point(0, 0);
            torrentTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            torrentTabUserControl.Name = "torrentTabUserControl";
            torrentTabUserControl.Size = new System.Drawing.Size(669, 836);
            torrentTabUserControl.TabIndex = 0;
            // 
            // packetsTabPage
            // 
            packetsTabPage.Controls.Add(packetCaptureTabUserControl);
            packetsTabPage.ImageIndex = 6;
            packetsTabPage.Location = new System.Drawing.Point(4, 4);
            packetsTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            packetsTabPage.Name = "packetsTabPage";
            packetsTabPage.Size = new System.Drawing.Size(669, 836);
            packetsTabPage.TabIndex = 6;
            packetsTabPage.UseVisualStyleBackColor = true;
            // 
            // packetCaptureTabUserControl
            // 
            packetCaptureTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            packetCaptureTabUserControl.Location = new System.Drawing.Point(0, 0);
            packetCaptureTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            packetCaptureTabUserControl.Name = "packetCaptureTabUserControl";
            packetCaptureTabUserControl.Size = new System.Drawing.Size(669, 836);
            packetCaptureTabUserControl.TabIndex = 0;
            // 
            // debugTabPage
            // 
            debugTabPage.Controls.Add(debugTabUserControl);
            debugTabPage.ImageIndex = 0;
            debugTabPage.Location = new System.Drawing.Point(4, 4);
            debugTabPage.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            debugTabPage.Name = "debugTabPage";
            debugTabPage.Size = new System.Drawing.Size(669, 836);
            debugTabPage.TabIndex = 1;
            debugTabPage.ToolTipText = "Debug";
            debugTabPage.UseVisualStyleBackColor = true;
            // 
            // debugTabUserControl
            // 
            debugTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            debugTabUserControl.Location = new System.Drawing.Point(0, 0);
            debugTabUserControl.Margin = new System.Windows.Forms.Padding(3, 5, 3, 5);
            debugTabUserControl.Name = "debugTabUserControl";
            debugTabUserControl.Size = new System.Drawing.Size(669, 836);
            debugTabUserControl.TabIndex = 0;
            // 
            // tabsImageList
            // 
            tabsImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth24Bit;
            tabsImageList.ImageStream = (System.Windows.Forms.ImageListStreamer)resources.GetObject("tabsImageList.ImageStream");
            tabsImageList.TransparentColor = System.Drawing.Color.Transparent;
            tabsImageList.Images.SetKeyName(0, "info.ico");
            tabsImageList.Images.SetKeyName(1, "world.ico");
            tabsImageList.Images.SetKeyName(2, "terminal-32.png");
            tabsImageList.Images.SetKeyName(3, "people.ico");
            tabsImageList.Images.SetKeyName(4, "AddressBook.ico");
            tabsImageList.Images.SetKeyName(5, "Letter.png");
            tabsImageList.Images.SetKeyName(6, "search.ico");
            tabsImageList.Images.SetKeyName(7, "transfer.ico");
            tabsImageList.Images.SetKeyName(8, "bbs.ico");
            tabsImageList.Images.SetKeyName(9, "talking.ico");
            // 
            // mainImageList
            // 
            mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth24Bit;
            mainImageList.ImageStream = (System.Windows.Forms.ImageListStreamer)resources.GetObject("mainImageList.ImageStream");
            mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            mainImageList.Images.SetKeyName(0, "GreenCheck-20.png");
            mainImageList.Images.SetKeyName(1, "");
            mainImageList.Images.SetKeyName(2, "");
            mainImageList.Images.SetKeyName(3, "");
            mainImageList.Images.SetKeyName(4, "");
            mainImageList.Images.SetKeyName(5, "");
            mainImageList.Images.SetKeyName(6, "");
            mainImageList.Images.SetKeyName(7, "");
            mainImageList.Images.SetKeyName(8, "mail-20.png");
            mainImageList.Images.SetKeyName(9, "file-20.png");
            mainImageList.Images.SetKeyName(10, "file-empty-20.png");
            // 
            // radioPanel
            // 
            radioPanel.AllowDrop = true;
            radioPanel.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            radioPanel.Controls.Add(radioPanelControl);
            radioPanel.Dock = System.Windows.Forms.DockStyle.Left;
            radioPanel.Location = new System.Drawing.Point(0, 26);
            radioPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            radioPanel.Name = "radioPanel";
            radioPanel.Size = new System.Drawing.Size(372, 844);
            radioPanel.TabIndex = 2;
            // 
            // radioPanelControl
            // 
            radioPanelControl.AllowDrop = true;
            radioPanelControl.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            radioPanelControl.DeviceId = -1;
            radioPanelControl.Dock = System.Windows.Forms.DockStyle.Fill;
            radioPanelControl.Location = new System.Drawing.Point(0, 0);
            radioPanelControl.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            radioPanelControl.Name = "radioPanelControl";
            radioPanelControl.ShowAllChannels = false;
            radioPanelControl.Size = new System.Drawing.Size(368, 840);
            radioPanelControl.TabIndex = 0;
            // 
            // radioWindowToolStripMenuItem
            // 
            radioWindowToolStripMenuItem.Name = "radioWindowToolStripMenuItem";
            radioWindowToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            radioWindowToolStripMenuItem.Text = "Radio Window...";
            radioWindowToolStripMenuItem.Click += radioWindowToolStripMenuItem_Click;
            // 
            // MainForm
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(1084, 892);
            Controls.Add(mainTabControl);
            Controls.Add(radioPanel);
            Controls.Add(mainStatusStrip);
            Controls.Add(mainMenuStrip);
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            MainMenuStrip = mainMenuStrip;
            Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            MinimumSize = new System.Drawing.Size(1097, 928);
            Name = "MainForm";
            Text = "Handi-Talkie Commander";
            Load += MainForm_Load;
            mainStatusStrip.ResumeLayout(false);
            mainStatusStrip.PerformLayout();
            mainMenuStrip.ResumeLayout(false);
            mainMenuStrip.PerformLayout();
            mainTabControl.ResumeLayout(false);
            aprsTabPage.ResumeLayout(false);
            mapTabPage.ResumeLayout(false);
            voiceTabPage.ResumeLayout(false);
            mailTabPage.ResumeLayout(false);
            terminalTabPage.ResumeLayout(false);
            addressesTabPage.ResumeLayout(false);
            bbsTabPage.ResumeLayout(false);
            torrentTabPage.ResumeLayout(false);
            packetsTabPage.ResumeLayout(false);
            debugTabPage.ResumeLayout(false);
            radioPanel.ResumeLayout(false);
            ResumeLayout(false);
            PerformLayout();

        }

        #endregion

        private System.Windows.Forms.StatusStrip mainStatusStrip;
        private System.Windows.Forms.MenuStrip mainMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem exitToolStripMenuItem;
        private System.Windows.Forms.TabControl mainTabControl;
        private System.Windows.Forms.TabPage debugTabPage;
        private System.Windows.Forms.ImageList tabsImageList;
        private System.Windows.Forms.ToolStripMenuItem connectToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem disconnectToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem aboutToolStripMenuItem;
        private System.Windows.Forms.ToolStripStatusLabel mainToolStripStatusLabel;
        private System.Windows.Forms.ToolStripStatusLabel batteryToolStripStatusLabel;
        private System.Windows.Forms.TabPage terminalTabPage;
        private System.Windows.Forms.TabPage aprsTabPage;
        private System.Windows.Forms.ToolStripMenuItem viewToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem radioToolStripMenuItem;
        private System.Windows.Forms.ImageList mainImageList;
        private System.Windows.Forms.TabPage addressesTabPage;
        private System.Windows.Forms.ToolStripMenuItem aboutToolStripMenuItem1;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem4;
        private System.Windows.Forms.ToolStripMenuItem settingsToolStripMenuItem;
        private System.Windows.Forms.TabPage mailTabPage;
        private System.Windows.Forms.ToolStripMenuItem audioToolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem audioClipsToolStripMenuItem;
        private System.Windows.Forms.TabPage packetsTabPage;
        private System.Windows.Forms.ToolStripMenuItem allChannelsToolStripMenuItem;
        private System.Windows.Forms.TabPage bbsTabPage;
        private System.Windows.Forms.ToolStripMenuItem radioInformationToolStripMenuItem;
        private System.Windows.Forms.TabPage torrentTabPage;
        private System.Windows.Forms.TabPage voiceTabPage;
        private System.Windows.Forms.ToolStripMenuItem checkForUpdatesToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem toolStripMenuItem21;
        private System.Windows.Forms.ToolStripMenuItem dualWatchToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem scanToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem regionToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripSeparator1;
        private System.Windows.Forms.ToolStripMenuItem exportChannelsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem importChannelsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem volumeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem spectrogramToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem audioEnabledToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem gPSEnabledToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem launchAnotherInstanceToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem localWebSiteToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem5;
        private System.Windows.Forms.ToolStripMenuItem softwareModemToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem disabledToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem aFK1200ToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem pSK2400ToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem pSK4800ToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem g9600ToolStripMenuItem;
        private Controls.DebugTabUserControl debugTabUserControl;
        private Controls.PacketCaptureTabUserControl packetCaptureTabUserControl;
        private Controls.TorrentTabUserControl torrentTabUserControl;
        private Controls.BbsTabUserControl bbsTabUserControl;
        private Controls.ContactsTabUserControl contactsTabUserControl;
        private Controls.TerminalTabUserControl terminalTabUserControl;
        private Controls.MailTabUserControl mailTabUserControl;
        private Controls.VoiceTabUserControl voiceTabUserControl;
        private System.Windows.Forms.TabPage mapTabPage;
        private Controls.MapTabUserControl mapTabUserControl;
        private Controls.AprsTabUserControl aprsTabUserControl;
        private System.Windows.Forms.Panel radioPanel;
        private RadioControls.RadioPanelControl radioPanelControl;
        private System.Windows.Forms.ToolStripMenuItem radioWindowToolStripMenuItem;
    }
}
