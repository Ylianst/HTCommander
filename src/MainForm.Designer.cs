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
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(MainForm));
            this.mainStatusStrip = new System.Windows.Forms.StatusStrip();
            this.mainToolStripStatusLabel = new System.Windows.Forms.ToolStripStatusLabel();
            this.batteryToolStripStatusLabel = new System.Windows.Forms.ToolStripStatusLabel();
            this.mainMenuStrip = new System.Windows.Forms.MenuStrip();
            this.fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.connectToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.disconnectToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            this.settingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.systemTrayToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.launchAnotherInstanceToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem4 = new System.Windows.Forms.ToolStripSeparator();
            this.exitToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem21 = new System.Windows.Forms.ToolStripMenuItem();
            this.dualWatchToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.scanToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.regionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.gPSEnabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripSeparator1 = new System.Windows.Forms.ToolStripSeparator();
            this.exportChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.importChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.audioToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.audioEnabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.volumeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.audioClipsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.spectrogramToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.softwareModemToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.disabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.aFK1200ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.pSK2400ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.pSK4800ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.g9600ToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.viewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.radioToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.allChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem6 = new System.Windows.Forms.ToolStripSeparator();
            this.mapToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.voiceToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.terminalToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.contactsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.bBSToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.packetsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.debugToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.aboutToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.radioInformationToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.radioStatusToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.radioSettingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.radioBSSSettingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.radioPositionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem2 = new System.Windows.Forms.ToolStripSeparator();
            this.localWebSiteToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem5 = new System.Windows.Forms.ToolStripSeparator();
            this.checkForUpdatesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.aboutToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.mainTabControl = new System.Windows.Forms.TabControl();
            this.aprsTabPage = new System.Windows.Forms.TabPage();
            this.aprsTabUserControl = new HTCommander.Controls.AprsTabUserControl();
            this.mapTabPage = new System.Windows.Forms.TabPage();
            this.mapTabUserControl = new HTCommander.Controls.MapTabUserControl();
            this.voiceTabPage = new System.Windows.Forms.TabPage();
            this.voiceTabUserControl = new HTCommander.Controls.VoiceTabUserControl();
            this.mailTabPage = new System.Windows.Forms.TabPage();
            this.mailTabUserControl = new HTCommander.Controls.MailTabUserControl();
            this.terminalTabPage = new System.Windows.Forms.TabPage();
            this.terminalTabUserControl = new HTCommander.Controls.TerminalTabUserControl();
            this.addressesTabPage = new System.Windows.Forms.TabPage();
            this.contactsTabUserControl = new HTCommander.Controls.ContactsTabUserControl();
            this.bbsTabPage = new System.Windows.Forms.TabPage();
            this.bbsTabUserControl = new HTCommander.Controls.BbsTabUserControl();
            this.torrentTabPage = new System.Windows.Forms.TabPage();
            this.torrentTabUserControl = new HTCommander.Controls.TorrentTabUserControl();
            this.packetsTabPage = new System.Windows.Forms.TabPage();
            this.packetCaptureTabUserControl = new HTCommander.Controls.PacketCaptureTabUserControl();
            this.debugTabPage = new System.Windows.Forms.TabPage();
            this.debugTabUserControl = new HTCommander.Controls.DebugTabUserControl();
            this.tabsImageList = new System.Windows.Forms.ImageList(this.components);
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            this.radioPanel = new System.Windows.Forms.Panel();
            this.radioPanelControl1 = new HTCommander.RadioControls.RadioPanelControl();
            this.mainStatusStrip.SuspendLayout();
            this.mainMenuStrip.SuspendLayout();
            this.mainTabControl.SuspendLayout();
            this.aprsTabPage.SuspendLayout();
            this.mapTabPage.SuspendLayout();
            this.voiceTabPage.SuspendLayout();
            this.mailTabPage.SuspendLayout();
            this.terminalTabPage.SuspendLayout();
            this.addressesTabPage.SuspendLayout();
            this.bbsTabPage.SuspendLayout();
            this.torrentTabPage.SuspendLayout();
            this.packetsTabPage.SuspendLayout();
            this.debugTabPage.SuspendLayout();
            this.radioPanel.SuspendLayout();
            this.SuspendLayout();
            // 
            // mainStatusStrip
            // 
            this.mainStatusStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainStatusStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.mainToolStripStatusLabel,
            this.batteryToolStripStatusLabel});
            this.mainStatusStrip.Location = new System.Drawing.Point(0, 692);
            this.mainStatusStrip.Name = "mainStatusStrip";
            this.mainStatusStrip.Padding = new System.Windows.Forms.Padding(1, 0, 19, 0);
            this.mainStatusStrip.Size = new System.Drawing.Size(1084, 22);
            this.mainStatusStrip.TabIndex = 0;
            this.mainStatusStrip.Text = "statusStrip1";
            // 
            // mainToolStripStatusLabel
            // 
            this.mainToolStripStatusLabel.Name = "mainToolStripStatusLabel";
            this.mainToolStripStatusLabel.Size = new System.Drawing.Size(1064, 16);
            this.mainToolStripStatusLabel.Spring = true;
            // 
            // batteryToolStripStatusLabel
            // 
            this.batteryToolStripStatusLabel.Name = "batteryToolStripStatusLabel";
            this.batteryToolStripStatusLabel.Size = new System.Drawing.Size(56, 20);
            this.batteryToolStripStatusLabel.Text = "Battery";
            this.batteryToolStripStatusLabel.TextAlign = System.Drawing.ContentAlignment.MiddleRight;
            this.batteryToolStripStatusLabel.Visible = false;
            // 
            // mainMenuStrip
            // 
            this.mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.fileToolStripMenuItem,
            this.toolStripMenuItem21,
            this.audioToolStripMenuItem1,
            this.viewToolStripMenuItem,
            this.aboutToolStripMenuItem});
            this.mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            this.mainMenuStrip.Name = "mainMenuStrip";
            this.mainMenuStrip.Padding = new System.Windows.Forms.Padding(5, 1, 0, 1);
            this.mainMenuStrip.Size = new System.Drawing.Size(1084, 26);
            this.mainMenuStrip.TabIndex = 1;
            this.mainMenuStrip.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            this.fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.connectToolStripMenuItem,
            this.disconnectToolStripMenuItem,
            this.toolStripMenuItem1,
            this.settingsToolStripMenuItem,
            this.systemTrayToolStripMenuItem,
            this.launchAnotherInstanceToolStripMenuItem,
            this.toolStripMenuItem4,
            this.exitToolStripMenuItem});
            this.fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            this.fileToolStripMenuItem.Size = new System.Drawing.Size(46, 24);
            this.fileToolStripMenuItem.Text = "&File";
            // 
            // connectToolStripMenuItem
            // 
            this.connectToolStripMenuItem.Name = "connectToolStripMenuItem";
            this.connectToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            this.connectToolStripMenuItem.Text = "&Connect...";
            // 
            // disconnectToolStripMenuItem
            // 
            this.disconnectToolStripMenuItem.Enabled = false;
            this.disconnectToolStripMenuItem.Name = "disconnectToolStripMenuItem";
            this.disconnectToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            this.disconnectToolStripMenuItem.Text = "&Disconnect";
            // 
            // toolStripMenuItem1
            // 
            this.toolStripMenuItem1.Name = "toolStripMenuItem1";
            this.toolStripMenuItem1.Size = new System.Drawing.Size(250, 6);
            // 
            // settingsToolStripMenuItem
            // 
            this.settingsToolStripMenuItem.Name = "settingsToolStripMenuItem";
            this.settingsToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            this.settingsToolStripMenuItem.Text = "&Settings...";
            // 
            // systemTrayToolStripMenuItem
            // 
            this.systemTrayToolStripMenuItem.CheckOnClick = true;
            this.systemTrayToolStripMenuItem.Name = "systemTrayToolStripMenuItem";
            this.systemTrayToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            this.systemTrayToolStripMenuItem.Text = "System &Tray";
            // 
            // launchAnotherInstanceToolStripMenuItem
            // 
            this.launchAnotherInstanceToolStripMenuItem.Name = "launchAnotherInstanceToolStripMenuItem";
            this.launchAnotherInstanceToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            this.launchAnotherInstanceToolStripMenuItem.Text = "Launch Another Instance";
            this.launchAnotherInstanceToolStripMenuItem.Visible = false;
            // 
            // toolStripMenuItem4
            // 
            this.toolStripMenuItem4.Name = "toolStripMenuItem4";
            this.toolStripMenuItem4.Size = new System.Drawing.Size(250, 6);
            // 
            // exitToolStripMenuItem
            // 
            this.exitToolStripMenuItem.Name = "exitToolStripMenuItem";
            this.exitToolStripMenuItem.Size = new System.Drawing.Size(253, 26);
            this.exitToolStripMenuItem.Text = "E&xit";
            this.exitToolStripMenuItem.Click += new System.EventHandler(this.exitToolStripMenuItem_Click);
            // 
            // toolStripMenuItem21
            // 
            this.toolStripMenuItem21.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.dualWatchToolStripMenuItem,
            this.scanToolStripMenuItem,
            this.regionToolStripMenuItem,
            this.gPSEnabledToolStripMenuItem,
            this.toolStripSeparator1,
            this.exportChannelsToolStripMenuItem,
            this.importChannelsToolStripMenuItem});
            this.toolStripMenuItem21.Name = "toolStripMenuItem21";
            this.toolStripMenuItem21.Size = new System.Drawing.Size(76, 24);
            this.toolStripMenuItem21.Text = "&Settings";
            // 
            // dualWatchToolStripMenuItem
            // 
            this.dualWatchToolStripMenuItem.Enabled = false;
            this.dualWatchToolStripMenuItem.Name = "dualWatchToolStripMenuItem";
            this.dualWatchToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            this.dualWatchToolStripMenuItem.Text = "&Dual-Watch";
            // 
            // scanToolStripMenuItem
            // 
            this.scanToolStripMenuItem.Enabled = false;
            this.scanToolStripMenuItem.Name = "scanToolStripMenuItem";
            this.scanToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            this.scanToolStripMenuItem.Text = "&Scan";
            // 
            // regionToolStripMenuItem
            // 
            this.regionToolStripMenuItem.Enabled = false;
            this.regionToolStripMenuItem.Name = "regionToolStripMenuItem";
            this.regionToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            this.regionToolStripMenuItem.Text = "&Regions";
            // 
            // gPSEnabledToolStripMenuItem
            // 
            this.gPSEnabledToolStripMenuItem.CheckOnClick = true;
            this.gPSEnabledToolStripMenuItem.Name = "gPSEnabledToolStripMenuItem";
            this.gPSEnabledToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            this.gPSEnabledToolStripMenuItem.Text = "&GPS Enabled";
            // 
            // toolStripSeparator1
            // 
            this.toolStripSeparator1.Name = "toolStripSeparator1";
            this.toolStripSeparator1.Size = new System.Drawing.Size(206, 6);
            // 
            // exportChannelsToolStripMenuItem
            // 
            this.exportChannelsToolStripMenuItem.Enabled = false;
            this.exportChannelsToolStripMenuItem.Name = "exportChannelsToolStripMenuItem";
            this.exportChannelsToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            this.exportChannelsToolStripMenuItem.Text = "&Export Channels...";
            // 
            // importChannelsToolStripMenuItem
            // 
            this.importChannelsToolStripMenuItem.Name = "importChannelsToolStripMenuItem";
            this.importChannelsToolStripMenuItem.Size = new System.Drawing.Size(209, 26);
            this.importChannelsToolStripMenuItem.Text = "&Import Channels...";
            // 
            // audioToolStripMenuItem1
            // 
            this.audioToolStripMenuItem1.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.audioEnabledToolStripMenuItem,
            this.volumeToolStripMenuItem,
            this.audioClipsToolStripMenuItem,
            this.spectrogramToolStripMenuItem,
            this.softwareModemToolStripMenuItem});
            this.audioToolStripMenuItem1.Name = "audioToolStripMenuItem1";
            this.audioToolStripMenuItem1.Size = new System.Drawing.Size(63, 24);
            this.audioToolStripMenuItem1.Text = "A&udio";
            // 
            // audioEnabledToolStripMenuItem
            // 
            this.audioEnabledToolStripMenuItem.Name = "audioEnabledToolStripMenuItem";
            this.audioEnabledToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            this.audioEnabledToolStripMenuItem.Text = "&Audio Enabled";
            // 
            // volumeToolStripMenuItem
            // 
            this.volumeToolStripMenuItem.Name = "volumeToolStripMenuItem";
            this.volumeToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            this.volumeToolStripMenuItem.Text = "Audio &Controls...";
            // 
            // audioClipsToolStripMenuItem
            // 
            this.audioClipsToolStripMenuItem.Name = "audioClipsToolStripMenuItem";
            this.audioClipsToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            this.audioClipsToolStripMenuItem.Text = "Audio C&lips...";
            // 
            // spectrogramToolStripMenuItem
            // 
            this.spectrogramToolStripMenuItem.Name = "spectrogramToolStripMenuItem";
            this.spectrogramToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            this.spectrogramToolStripMenuItem.Text = "Spectrogram...";
            // 
            // softwareModemToolStripMenuItem
            // 
            this.softwareModemToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.disabledToolStripMenuItem,
            this.aFK1200ToolStripMenuItem,
            this.pSK2400ToolStripMenuItem,
            this.pSK4800ToolStripMenuItem,
            this.g9600ToolStripMenuItem});
            this.softwareModemToolStripMenuItem.Name = "softwareModemToolStripMenuItem";
            this.softwareModemToolStripMenuItem.Size = new System.Drawing.Size(207, 26);
            this.softwareModemToolStripMenuItem.Text = "Software &Modem";
            // 
            // disabledToolStripMenuItem
            // 
            this.disabledToolStripMenuItem.Checked = true;
            this.disabledToolStripMenuItem.CheckOnClick = true;
            this.disabledToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.disabledToolStripMenuItem.Name = "disabledToolStripMenuItem";
            this.disabledToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            this.disabledToolStripMenuItem.Text = "&Disabled";
            // 
            // aFK1200ToolStripMenuItem
            // 
            this.aFK1200ToolStripMenuItem.CheckOnClick = true;
            this.aFK1200ToolStripMenuItem.Name = "aFK1200ToolStripMenuItem";
            this.aFK1200ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            this.aFK1200ToolStripMenuItem.Text = "AFK &1200";
            // 
            // pSK2400ToolStripMenuItem
            // 
            this.pSK2400ToolStripMenuItem.CheckOnClick = true;
            this.pSK2400ToolStripMenuItem.Name = "pSK2400ToolStripMenuItem";
            this.pSK2400ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            this.pSK2400ToolStripMenuItem.Text = "PSK &2400";
            this.pSK2400ToolStripMenuItem.Visible = false;
            // 
            // pSK4800ToolStripMenuItem
            // 
            this.pSK4800ToolStripMenuItem.CheckOnClick = true;
            this.pSK4800ToolStripMenuItem.Name = "pSK4800ToolStripMenuItem";
            this.pSK4800ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            this.pSK4800ToolStripMenuItem.Text = "PSK &4800";
            this.pSK4800ToolStripMenuItem.Visible = false;
            // 
            // g9600ToolStripMenuItem
            // 
            this.g9600ToolStripMenuItem.CheckOnClick = true;
            this.g9600ToolStripMenuItem.Name = "g9600ToolStripMenuItem";
            this.g9600ToolStripMenuItem.Size = new System.Drawing.Size(154, 26);
            this.g9600ToolStripMenuItem.Text = "G &9600";
            this.g9600ToolStripMenuItem.Visible = false;
            // 
            // viewToolStripMenuItem
            // 
            this.viewToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.radioToolStripMenuItem,
            this.allChannelsToolStripMenuItem,
            this.toolStripMenuItem6,
            this.mapToolStripMenuItem,
            this.voiceToolStripMenuItem,
            this.terminalToolStripMenuItem,
            this.mailToolStripMenuItem,
            this.contactsToolStripMenuItem,
            this.bBSToolStripMenuItem,
            this.torrentToolStripMenuItem,
            this.packetsToolStripMenuItem,
            this.debugToolStripMenuItem});
            this.viewToolStripMenuItem.Name = "viewToolStripMenuItem";
            this.viewToolStripMenuItem.Size = new System.Drawing.Size(55, 24);
            this.viewToolStripMenuItem.Text = "&View";
            // 
            // radioToolStripMenuItem
            // 
            this.radioToolStripMenuItem.Checked = true;
            this.radioToolStripMenuItem.CheckOnClick = true;
            this.radioToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.radioToolStripMenuItem.Name = "radioToolStripMenuItem";
            this.radioToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.radioToolStripMenuItem.Text = "&Radio";
            // 
            // allChannelsToolStripMenuItem
            // 
            this.allChannelsToolStripMenuItem.Name = "allChannelsToolStripMenuItem";
            this.allChannelsToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.allChannelsToolStripMenuItem.Text = "All Channels";
            // 
            // toolStripMenuItem6
            // 
            this.toolStripMenuItem6.Name = "toolStripMenuItem6";
            this.toolStripMenuItem6.Size = new System.Drawing.Size(170, 6);
            // 
            // mapToolStripMenuItem
            // 
            this.mapToolStripMenuItem.CheckOnClick = true;
            this.mapToolStripMenuItem.Name = "mapToolStripMenuItem";
            this.mapToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.mapToolStripMenuItem.Text = "&Map";
            // 
            // voiceToolStripMenuItem
            // 
            this.voiceToolStripMenuItem.CheckOnClick = true;
            this.voiceToolStripMenuItem.Name = "voiceToolStripMenuItem";
            this.voiceToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.voiceToolStripMenuItem.Text = "&Voice";
            // 
            // terminalToolStripMenuItem
            // 
            this.terminalToolStripMenuItem.CheckOnClick = true;
            this.terminalToolStripMenuItem.Name = "terminalToolStripMenuItem";
            this.terminalToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.terminalToolStripMenuItem.Text = "&Terminal";
            // 
            // mailToolStripMenuItem
            // 
            this.mailToolStripMenuItem.CheckOnClick = true;
            this.mailToolStripMenuItem.Name = "mailToolStripMenuItem";
            this.mailToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.mailToolStripMenuItem.Text = "&Mail";
            // 
            // contactsToolStripMenuItem
            // 
            this.contactsToolStripMenuItem.CheckOnClick = true;
            this.contactsToolStripMenuItem.Name = "contactsToolStripMenuItem";
            this.contactsToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.contactsToolStripMenuItem.Text = "&Stations";
            // 
            // bBSToolStripMenuItem
            // 
            this.bBSToolStripMenuItem.CheckOnClick = true;
            this.bBSToolStripMenuItem.Name = "bBSToolStripMenuItem";
            this.bBSToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.bBSToolStripMenuItem.Text = "&BBS";
            // 
            // torrentToolStripMenuItem
            // 
            this.torrentToolStripMenuItem.CheckOnClick = true;
            this.torrentToolStripMenuItem.Name = "torrentToolStripMenuItem";
            this.torrentToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.torrentToolStripMenuItem.Text = "T&orrent";
            // 
            // packetsToolStripMenuItem
            // 
            this.packetsToolStripMenuItem.CheckOnClick = true;
            this.packetsToolStripMenuItem.Name = "packetsToolStripMenuItem";
            this.packetsToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.packetsToolStripMenuItem.Text = "&Packets";
            // 
            // debugToolStripMenuItem
            // 
            this.debugToolStripMenuItem.CheckOnClick = true;
            this.debugToolStripMenuItem.Name = "debugToolStripMenuItem";
            this.debugToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            this.debugToolStripMenuItem.Text = "&Debug";
            // 
            // aboutToolStripMenuItem
            // 
            this.aboutToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.radioInformationToolStripMenuItem,
            this.radioStatusToolStripMenuItem,
            this.radioSettingsToolStripMenuItem,
            this.radioBSSSettingsToolStripMenuItem,
            this.radioPositionToolStripMenuItem,
            this.toolStripMenuItem2,
            this.localWebSiteToolStripMenuItem,
            this.toolStripMenuItem5,
            this.checkForUpdatesToolStripMenuItem,
            this.aboutToolStripMenuItem1});
            this.aboutToolStripMenuItem.Name = "aboutToolStripMenuItem";
            this.aboutToolStripMenuItem.Size = new System.Drawing.Size(64, 24);
            this.aboutToolStripMenuItem.Text = "&About";
            // 
            // radioInformationToolStripMenuItem
            // 
            this.radioInformationToolStripMenuItem.Enabled = false;
            this.radioInformationToolStripMenuItem.Name = "radioInformationToolStripMenuItem";
            this.radioInformationToolStripMenuItem.Size = new System.Drawing.Size(226, 26);
            this.radioInformationToolStripMenuItem.Text = "Radio Information...";
            // 
            // radioStatusToolStripMenuItem
            // 
            this.radioStatusToolStripMenuItem.Enabled = false;
            this.radioStatusToolStripMenuItem.Name = "radioStatusToolStripMenuItem";
            this.radioStatusToolStripMenuItem.Size = new System.Drawing.Size(226, 26);
            this.radioStatusToolStripMenuItem.Text = "Radio &Status...";
            // 
            // radioSettingsToolStripMenuItem
            // 
            this.radioSettingsToolStripMenuItem.Enabled = false;
            this.radioSettingsToolStripMenuItem.Name = "radioSettingsToolStripMenuItem";
            this.radioSettingsToolStripMenuItem.Size = new System.Drawing.Size(226, 26);
            this.radioSettingsToolStripMenuItem.Text = "Radio S&ettings...";
            // 
            // radioBSSSettingsToolStripMenuItem
            // 
            this.radioBSSSettingsToolStripMenuItem.Enabled = false;
            this.radioBSSSettingsToolStripMenuItem.Name = "radioBSSSettingsToolStripMenuItem";
            this.radioBSSSettingsToolStripMenuItem.Size = new System.Drawing.Size(226, 26);
            this.radioBSSSettingsToolStripMenuItem.Text = "Radio BSS Settings...";
            // 
            // radioPositionToolStripMenuItem
            // 
            this.radioPositionToolStripMenuItem.Enabled = false;
            this.radioPositionToolStripMenuItem.Name = "radioPositionToolStripMenuItem";
            this.radioPositionToolStripMenuItem.Size = new System.Drawing.Size(226, 26);
            this.radioPositionToolStripMenuItem.Text = "Radio Position...";
            // 
            // toolStripMenuItem2
            // 
            this.toolStripMenuItem2.Name = "toolStripMenuItem2";
            this.toolStripMenuItem2.Size = new System.Drawing.Size(223, 6);
            this.toolStripMenuItem2.Visible = false;
            // 
            // localWebSiteToolStripMenuItem
            // 
            this.localWebSiteToolStripMenuItem.Name = "localWebSiteToolStripMenuItem";
            this.localWebSiteToolStripMenuItem.Size = new System.Drawing.Size(226, 26);
            this.localWebSiteToolStripMenuItem.Text = "Local Web Site...";
            this.localWebSiteToolStripMenuItem.Visible = false;
            // 
            // toolStripMenuItem5
            // 
            this.toolStripMenuItem5.Name = "toolStripMenuItem5";
            this.toolStripMenuItem5.Size = new System.Drawing.Size(223, 6);
            // 
            // checkForUpdatesToolStripMenuItem
            // 
            this.checkForUpdatesToolStripMenuItem.CheckOnClick = true;
            this.checkForUpdatesToolStripMenuItem.Name = "checkForUpdatesToolStripMenuItem";
            this.checkForUpdatesToolStripMenuItem.Size = new System.Drawing.Size(226, 26);
            this.checkForUpdatesToolStripMenuItem.Text = "Check for Updates";
            // 
            // aboutToolStripMenuItem1
            // 
            this.aboutToolStripMenuItem1.Name = "aboutToolStripMenuItem1";
            this.aboutToolStripMenuItem1.Size = new System.Drawing.Size(226, 26);
            this.aboutToolStripMenuItem1.Text = "&About...";
            this.aboutToolStripMenuItem1.Click += new System.EventHandler(this.aboutToolStripMenuItem1_Click);
            // 
            // mainTabControl
            // 
            this.mainTabControl.Alignment = System.Windows.Forms.TabAlignment.Right;
            this.mainTabControl.Controls.Add(this.aprsTabPage);
            this.mainTabControl.Controls.Add(this.mapTabPage);
            this.mainTabControl.Controls.Add(this.voiceTabPage);
            this.mainTabControl.Controls.Add(this.mailTabPage);
            this.mainTabControl.Controls.Add(this.terminalTabPage);
            this.mainTabControl.Controls.Add(this.addressesTabPage);
            this.mainTabControl.Controls.Add(this.bbsTabPage);
            this.mainTabControl.Controls.Add(this.torrentTabPage);
            this.mainTabControl.Controls.Add(this.packetsTabPage);
            this.mainTabControl.Controls.Add(this.debugTabPage);
            this.mainTabControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mainTabControl.ImageList = this.tabsImageList;
            this.mainTabControl.Location = new System.Drawing.Point(372, 26);
            this.mainTabControl.Margin = new System.Windows.Forms.Padding(4);
            this.mainTabControl.Multiline = true;
            this.mainTabControl.Name = "mainTabControl";
            this.mainTabControl.SelectedIndex = 0;
            this.mainTabControl.Size = new System.Drawing.Size(712, 666);
            this.mainTabControl.TabIndex = 3;
            // 
            // aprsTabPage
            // 
            this.aprsTabPage.Controls.Add(this.aprsTabUserControl);
            this.aprsTabPage.ImageIndex = 3;
            this.aprsTabPage.Location = new System.Drawing.Point(4, 4);
            this.aprsTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.aprsTabPage.Name = "aprsTabPage";
            this.aprsTabPage.Size = new System.Drawing.Size(669, 658);
            this.aprsTabPage.TabIndex = 3;
            this.aprsTabPage.UseVisualStyleBackColor = true;
            // 
            // aprsTabUserControl
            // 
            this.aprsTabUserControl.DestinationCallsign = "";
            this.aprsTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.aprsTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.aprsTabUserControl.Name = "aprsTabUserControl";
            this.aprsTabUserControl.SelectedAprsRoute = 0;
            this.aprsTabUserControl.ShowAllMessages = false;
            this.aprsTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.aprsTabUserControl.TabIndex = 0;
            // 
            // mapTabPage
            // 
            this.mapTabPage.Controls.Add(this.mapTabUserControl);
            this.mapTabPage.ImageIndex = 1;
            this.mapTabPage.Location = new System.Drawing.Point(4, 4);
            this.mapTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.mapTabPage.Name = "mapTabPage";
            this.mapTabPage.Size = new System.Drawing.Size(669, 658);
            this.mapTabPage.TabIndex = 0;
            this.mapTabPage.ToolTipText = "APRS";
            this.mapTabPage.UseVisualStyleBackColor = true;
            // 
            // mapTabUserControl
            // 
            this.mapTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mapTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.mapTabUserControl.Name = "mapTabUserControl";
            this.mapTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.mapTabUserControl.TabIndex = 0;
            // 
            // voiceTabPage
            // 
            this.voiceTabPage.Controls.Add(this.voiceTabUserControl);
            this.voiceTabPage.ImageIndex = 9;
            this.voiceTabPage.Location = new System.Drawing.Point(4, 4);
            this.voiceTabPage.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.voiceTabPage.Name = "voiceTabPage";
            this.voiceTabPage.Size = new System.Drawing.Size(669, 658);
            this.voiceTabPage.TabIndex = 9;
            this.voiceTabPage.UseVisualStyleBackColor = true;
            // 
            // voiceTabUserControl
            // 
            this.voiceTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.voiceTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.voiceTabUserControl.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.voiceTabUserControl.Name = "voiceTabUserControl";
            this.voiceTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.voiceTabUserControl.TabIndex = 0;
            // 
            // mailTabPage
            // 
            this.mailTabPage.Controls.Add(this.mailTabUserControl);
            this.mailTabPage.ImageIndex = 5;
            this.mailTabPage.Location = new System.Drawing.Point(4, 4);
            this.mailTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.mailTabPage.Name = "mailTabPage";
            this.mailTabPage.Size = new System.Drawing.Size(669, 658);
            this.mailTabPage.TabIndex = 5;
            this.mailTabPage.UseVisualStyleBackColor = true;
            // 
            // mailTabUserControl
            // 
            this.mailTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.mailTabUserControl.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.mailTabUserControl.Name = "mailTabUserControl";
            this.mailTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.mailTabUserControl.TabIndex = 0;
            // 
            // terminalTabPage
            // 
            this.terminalTabPage.Controls.Add(this.terminalTabUserControl);
            this.terminalTabPage.ImageKey = "terminal-32.png";
            this.terminalTabPage.Location = new System.Drawing.Point(4, 4);
            this.terminalTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.terminalTabPage.Name = "terminalTabPage";
            this.terminalTabPage.Size = new System.Drawing.Size(669, 658);
            this.terminalTabPage.TabIndex = 2;
            this.terminalTabPage.UseVisualStyleBackColor = true;
            // 
            // terminalTabUserControl
            // 
            this.terminalTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.terminalTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.terminalTabUserControl.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.terminalTabUserControl.Name = "terminalTabUserControl";
            this.terminalTabUserControl.ShowCallsign = false;
            this.terminalTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.terminalTabUserControl.TabIndex = 0;
            this.terminalTabUserControl.WordWrap = false;
            // 
            // addressesTabPage
            // 
            this.addressesTabPage.Controls.Add(this.contactsTabUserControl);
            this.addressesTabPage.ImageIndex = 4;
            this.addressesTabPage.Location = new System.Drawing.Point(4, 4);
            this.addressesTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.addressesTabPage.Name = "addressesTabPage";
            this.addressesTabPage.Size = new System.Drawing.Size(669, 658);
            this.addressesTabPage.TabIndex = 4;
            this.addressesTabPage.UseVisualStyleBackColor = true;
            // 
            // contactsTabUserControl
            // 
            this.contactsTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.contactsTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.contactsTabUserControl.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.contactsTabUserControl.Name = "contactsTabUserControl";
            this.contactsTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.contactsTabUserControl.TabIndex = 0;
            // 
            // bbsTabPage
            // 
            this.bbsTabPage.Controls.Add(this.bbsTabUserControl);
            this.bbsTabPage.ImageIndex = 8;
            this.bbsTabPage.Location = new System.Drawing.Point(4, 4);
            this.bbsTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.bbsTabPage.Name = "bbsTabPage";
            this.bbsTabPage.Size = new System.Drawing.Size(669, 658);
            this.bbsTabPage.TabIndex = 7;
            this.bbsTabPage.UseVisualStyleBackColor = true;
            // 
            // bbsTabUserControl
            // 
            this.bbsTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.bbsTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.bbsTabUserControl.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.bbsTabUserControl.Name = "bbsTabUserControl";
            this.bbsTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.bbsTabUserControl.TabIndex = 0;
            // 
            // torrentTabPage
            // 
            this.torrentTabPage.Controls.Add(this.torrentTabUserControl);
            this.torrentTabPage.ImageIndex = 7;
            this.torrentTabPage.Location = new System.Drawing.Point(4, 4);
            this.torrentTabPage.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.torrentTabPage.Name = "torrentTabPage";
            this.torrentTabPage.Size = new System.Drawing.Size(669, 658);
            this.torrentTabPage.TabIndex = 8;
            this.torrentTabPage.UseVisualStyleBackColor = true;
            // 
            // torrentTabUserControl
            // 
            this.torrentTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.torrentTabUserControl.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.torrentTabUserControl.Name = "torrentTabUserControl";
            this.torrentTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.torrentTabUserControl.TabIndex = 0;
            // 
            // packetsTabPage
            // 
            this.packetsTabPage.Controls.Add(this.packetCaptureTabUserControl);
            this.packetsTabPage.ImageIndex = 6;
            this.packetsTabPage.Location = new System.Drawing.Point(4, 4);
            this.packetsTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.packetsTabPage.Name = "packetsTabPage";
            this.packetsTabPage.Size = new System.Drawing.Size(669, 658);
            this.packetsTabPage.TabIndex = 6;
            this.packetsTabPage.UseVisualStyleBackColor = true;
            // 
            // packetCaptureTabUserControl
            // 
            this.packetCaptureTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetCaptureTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.packetCaptureTabUserControl.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.packetCaptureTabUserControl.Name = "packetCaptureTabUserControl";
            this.packetCaptureTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.packetCaptureTabUserControl.TabIndex = 0;
            // 
            // debugTabPage
            // 
            this.debugTabPage.Controls.Add(this.debugTabUserControl);
            this.debugTabPage.ImageIndex = 0;
            this.debugTabPage.Location = new System.Drawing.Point(4, 4);
            this.debugTabPage.Margin = new System.Windows.Forms.Padding(4);
            this.debugTabPage.Name = "debugTabPage";
            this.debugTabPage.Size = new System.Drawing.Size(669, 658);
            this.debugTabPage.TabIndex = 1;
            this.debugTabPage.ToolTipText = "Debug";
            this.debugTabPage.UseVisualStyleBackColor = true;
            // 
            // debugTabUserControl
            // 
            this.debugTabUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.debugTabUserControl.Location = new System.Drawing.Point(0, 0);
            this.debugTabUserControl.Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            this.debugTabUserControl.Name = "debugTabUserControl";
            this.debugTabUserControl.Size = new System.Drawing.Size(669, 658);
            this.debugTabUserControl.TabIndex = 0;
            // 
            // tabsImageList
            // 
            this.tabsImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("tabsImageList.ImageStream")));
            this.tabsImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.tabsImageList.Images.SetKeyName(0, "info.ico");
            this.tabsImageList.Images.SetKeyName(1, "world.ico");
            this.tabsImageList.Images.SetKeyName(2, "terminal-32.png");
            this.tabsImageList.Images.SetKeyName(3, "people.ico");
            this.tabsImageList.Images.SetKeyName(4, "AddressBook.ico");
            this.tabsImageList.Images.SetKeyName(5, "Letter.png");
            this.tabsImageList.Images.SetKeyName(6, "search.ico");
            this.tabsImageList.Images.SetKeyName(7, "transfer.ico");
            this.tabsImageList.Images.SetKeyName(8, "bbs.ico");
            this.tabsImageList.Images.SetKeyName(9, "talking.ico");
            // 
            // mainImageList
            // 
            this.mainImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("mainImageList.ImageStream")));
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.mainImageList.Images.SetKeyName(0, "GreenCheck-20.png");
            this.mainImageList.Images.SetKeyName(1, "");
            this.mainImageList.Images.SetKeyName(2, "");
            this.mainImageList.Images.SetKeyName(3, "");
            this.mainImageList.Images.SetKeyName(4, "");
            this.mainImageList.Images.SetKeyName(5, "");
            this.mainImageList.Images.SetKeyName(6, "");
            this.mainImageList.Images.SetKeyName(7, "");
            this.mainImageList.Images.SetKeyName(8, "mail-20.png");
            this.mainImageList.Images.SetKeyName(9, "file-20.png");
            this.mainImageList.Images.SetKeyName(10, "file-empty-20.png");
            // 
            // radioPanel
            // 
            this.radioPanel.AllowDrop = true;
            this.radioPanel.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            this.radioPanel.Controls.Add(this.radioPanelControl1);
            this.radioPanel.Dock = System.Windows.Forms.DockStyle.Left;
            this.radioPanel.Location = new System.Drawing.Point(0, 26);
            this.radioPanel.Margin = new System.Windows.Forms.Padding(4);
            this.radioPanel.Name = "radioPanel";
            this.radioPanel.Size = new System.Drawing.Size(372, 666);
            this.radioPanel.TabIndex = 2;
            // 
            // radioPanelControl1
            // 
            this.radioPanelControl1.AllowDrop = true;
            this.radioPanelControl1.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            this.radioPanelControl1.ChannelControls = null;
            this.radioPanelControl1.CheckBluetoothButtonVisible = false;
            this.radioPanelControl1.ConnectButtonVisible = true;
            this.radioPanelControl1.ConnectedPanelVisible = false;
            this.radioPanelControl1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.radioPanelControl1.GpsStatusText = "GPS";
            this.radioPanelControl1.Location = new System.Drawing.Point(0, 0);
            this.radioPanelControl1.Margin = new System.Windows.Forms.Padding(4);
            this.radioPanelControl1.Name = "radioPanelControl1";
            this.radioPanelControl1.RadioStateLabelVisible = true;
            this.radioPanelControl1.RadioStateText = "Disconnected";
            this.radioPanelControl1.RssiProgressBarVisible = false;
            this.radioPanelControl1.RssiValue = 0;
            this.radioPanelControl1.Size = new System.Drawing.Size(368, 662);
            this.radioPanelControl1.TabIndex = 0;
            this.radioPanelControl1.TransmitBarVisible = false;
            this.radioPanelControl1.Vfo2LastChannelId = -1;
            this.radioPanelControl1.VoiceProcessingVisible = false;
            // 
            // MainForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(1084, 714);
            this.Controls.Add(this.mainTabControl);
            this.Controls.Add(this.radioPanel);
            this.Controls.Add(this.mainStatusStrip);
            this.Controls.Add(this.mainMenuStrip);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MainMenuStrip = this.mainMenuStrip;
            this.Margin = new System.Windows.Forms.Padding(4);
            this.MinimumSize = new System.Drawing.Size(1097, 752);
            this.Name = "MainForm";
            this.Text = "Handi-Talkie Commander";
            this.Load += new System.EventHandler(this.MainForm_Load);
            this.mainStatusStrip.ResumeLayout(false);
            this.mainStatusStrip.PerformLayout();
            this.mainMenuStrip.ResumeLayout(false);
            this.mainMenuStrip.PerformLayout();
            this.mainTabControl.ResumeLayout(false);
            this.aprsTabPage.ResumeLayout(false);
            this.mapTabPage.ResumeLayout(false);
            this.voiceTabPage.ResumeLayout(false);
            this.mailTabPage.ResumeLayout(false);
            this.terminalTabPage.ResumeLayout(false);
            this.addressesTabPage.ResumeLayout(false);
            this.bbsTabPage.ResumeLayout(false);
            this.torrentTabPage.ResumeLayout(false);
            this.packetsTabPage.ResumeLayout(false);
            this.debugTabPage.ResumeLayout(false);
            this.radioPanel.ResumeLayout(false);
            this.ResumeLayout(false);
            this.PerformLayout();

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
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem2;
        private System.Windows.Forms.ToolStripStatusLabel mainToolStripStatusLabel;
        private System.Windows.Forms.ToolStripStatusLabel batteryToolStripStatusLabel;
        private System.Windows.Forms.ToolStripMenuItem radioStatusToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem radioSettingsToolStripMenuItem;
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
        private System.Windows.Forms.ToolStripMenuItem mapToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem terminalToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem mailToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem contactsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem6;
        private System.Windows.Forms.TabPage packetsTabPage;
        private System.Windows.Forms.ToolStripMenuItem packetsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem debugToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem allChannelsToolStripMenuItem;
        private System.Windows.Forms.TabPage bbsTabPage;
        private System.Windows.Forms.ToolStripMenuItem bBSToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem systemTrayToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem radioInformationToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem radioBSSSettingsToolStripMenuItem;
        private System.Windows.Forms.TabPage torrentTabPage;
        private System.Windows.Forms.ToolStripMenuItem torrentToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem voiceToolStripMenuItem;
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
        private System.Windows.Forms.ToolStripMenuItem radioPositionToolStripMenuItem;
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
        private RadioControls.RadioPanelControl radioPanelControl1;
    }
}
