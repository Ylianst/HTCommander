﻿namespace HTCommander
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
            System.Windows.Forms.ListViewGroup listViewGroup4 = new System.Windows.Forms.ListViewGroup("Generic Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup5 = new System.Windows.Forms.ListViewGroup("APRS Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup6 = new System.Windows.Forms.ListViewGroup("Terminal Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup7 = new System.Windows.Forms.ListViewGroup("BBS", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup8 = new System.Windows.Forms.ListViewGroup("Winlink Gateways", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup9 = new System.Windows.Forms.ListViewGroup("Generic Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup10 = new System.Windows.Forms.ListViewGroup("APRS Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup11 = new System.Windows.Forms.ListViewGroup("Terminal Stations", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup12 = new System.Windows.Forms.ListViewGroup("Metadata", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup13 = new System.Windows.Forms.ListViewGroup("AX.25 Header", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup14 = new System.Windows.Forms.ListViewGroup("AX.25 Data", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup15 = new System.Windows.Forms.ListViewGroup("APRS", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup16 = new System.Windows.Forms.ListViewGroup("Position", System.Windows.Forms.HorizontalAlignment.Left);
            System.Windows.Forms.ListViewGroup listViewGroup20 = new System.Windows.Forms.ListViewGroup("Decompression", System.Windows.Forms.HorizontalAlignment.Left);
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
            this.toolStripMenuItem4 = new System.Windows.Forms.ToolStripSeparator();
            this.exitToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.settingsToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.dualWatchToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.scanToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.regionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem5 = new System.Windows.Forms.ToolStripSeparator();
            this.audioEnabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.volumeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem10 = new System.Windows.Forms.ToolStripSeparator();
            this.exportChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.importChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
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
            this.toolStripMenuItem2 = new System.Windows.Forms.ToolStripSeparator();
            this.aboutToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.radioPanel = new System.Windows.Forms.Panel();
            this.transmitPictureBox = new System.Windows.Forms.PictureBox();
            this.transmitBarPanel = new System.Windows.Forms.Panel();
            this.channelsFlowLayoutPanel = new System.Windows.Forms.FlowLayoutPanel();
            this.checkBluetoothButton = new System.Windows.Forms.Button();
            this.rssiProgressBar = new System.Windows.Forms.ProgressBar();
            this.connectedPanel = new System.Windows.Forms.Panel();
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
            this.mainTabControl = new System.Windows.Forms.TabControl();
            this.aprsTabPage = new System.Windows.Forms.TabPage();
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            this.aprsMissingChannelPanel = new System.Windows.Forms.Panel();
            this.aprsSetupButton = new System.Windows.Forms.Button();
            this.missingAprsChannelLabel = new System.Windows.Forms.Label();
            this.aprsBottomPanel = new System.Windows.Forms.Panel();
            this.aprsDestinationComboBox = new System.Windows.Forms.ComboBox();
            this.aprsTextBox = new System.Windows.Forms.TextBox();
            this.aprsSendButton = new System.Windows.Forms.Button();
            this.aprsTopPanel = new System.Windows.Forms.Panel();
            this.aprsRouteComboBox = new System.Windows.Forms.ComboBox();
            this.aprsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.aprsTitleLabel = new System.Windows.Forms.Label();
            this.mapTabPage = new System.Windows.Forms.TabPage();
            this.mapZoomOutButton = new System.Windows.Forms.Button();
            this.mapZoomInbutton = new System.Windows.Forms.Button();
            this.mapTopPanel = new System.Windows.Forms.Panel();
            this.mapTopLabel = new System.Windows.Forms.Label();
            this.voiceTabPage = new System.Windows.Forms.TabPage();
            this.voiceHistoryTextBox = new System.Windows.Forms.RichTextBox();
            this.panel6 = new System.Windows.Forms.Panel();
            this.voiceEnableButton = new System.Windows.Forms.Button();
            this.voiceMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.label6 = new System.Windows.Forms.Label();
            this.mailTabPage = new System.Windows.Forms.TabPage();
            this.mailboxHorizontalSplitContainer = new System.Windows.Forms.SplitContainer();
            this.mailboxVerticalSplitContainer = new System.Windows.Forms.SplitContainer();
            this.mailBoxesTreeView = new System.Windows.Forms.TreeView();
            this.mailBoxImageList = new System.Windows.Forms.ImageList(this.components);
            this.mailboxListView = new System.Windows.Forms.ListView();
            this.columnHeader4 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader5 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader6 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.mailContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.viewMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.editMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem14 = new System.Windows.Forms.ToolStripSeparator();
            this.moveToDraftToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToOutboxToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToInboxToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToArchiveToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToTrashToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem15 = new System.Windows.Forms.ToolStripSeparator();
            this.deleteMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mailPreviewTextBox = new System.Windows.Forms.RichTextBox();
            this.mailTransferStatusPanel = new System.Windows.Forms.Panel();
            this.mailTransferStatusLabel = new System.Windows.Forms.Label();
            this.panel2 = new System.Windows.Forms.Panel();
            this.newMailButton = new System.Windows.Forms.Button();
            this.mailConnectButton = new System.Windows.Forms.Button();
            this.mailMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.stationsTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.exportStationsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.importStationsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mailTitleLabel = new System.Windows.Forms.Label();
            this.terminalTabPage = new System.Windows.Forms.TabPage();
            this.terminalTextBox = new System.Windows.Forms.RichTextBox();
            this.terminalBottomPanel = new System.Windows.Forms.Panel();
            this.terminalInputTextBox = new System.Windows.Forms.TextBox();
            this.terminalSendButton = new System.Windows.Forms.Button();
            this.terminalTopPanel = new System.Windows.Forms.Panel();
            this.terminalConnectButton = new System.Windows.Forms.Button();
            this.terminalMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.terminalTitleLabel = new System.Windows.Forms.Label();
            this.addressesTabPage = new System.Windows.Forms.TabPage();
            this.mainAddressBookListView = new System.Windows.Forms.ListView();
            this.columnHeader1 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader2 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader3 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.stationsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.editToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.removeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.setToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.panel1 = new System.Windows.Forms.Panel();
            this.stationsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.addStationButton = new System.Windows.Forms.Button();
            this.removeStationButton = new System.Windows.Forms.Button();
            this.label1 = new System.Windows.Forms.Label();
            this.bbsTabPage = new System.Windows.Forms.TabPage();
            this.bbsSplitContainer = new System.Windows.Forms.SplitContainer();
            this.bbsListView = new System.Windows.Forms.ListView();
            this.columnHeader10 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader11 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader12 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.bbsTextBox = new System.Windows.Forms.RichTextBox();
            this.panel4 = new System.Windows.Forms.Panel();
            this.bbsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.bbsConnectButton = new System.Windows.Forms.Button();
            this.label3 = new System.Windows.Forms.Label();
            this.torrentTabPage = new System.Windows.Forms.TabPage();
            this.torrentSplitContainer = new System.Windows.Forms.SplitContainer();
            this.torrentListView = new System.Windows.Forms.ListView();
            this.columnHeader14 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader15 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader16 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.torrentContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.torrentPauseToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentShareToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentRequestToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem19 = new System.Windows.Forms.ToolStripSeparator();
            this.torrentSaveAsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem20 = new System.Windows.Forms.ToolStripSeparator();
            this.torrentDeleteToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentTabControl = new System.Windows.Forms.TabControl();
            this.tabPage1 = new System.Windows.Forms.TabPage();
            this.torrentDetailsListView = new System.Windows.Forms.ListView();
            this.columnHeader13 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader17 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.tabPage2 = new System.Windows.Forms.TabPage();
            this.panel5 = new System.Windows.Forms.Panel();
            this.torrentAddFileButton = new System.Windows.Forms.Button();
            this.torrentMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.torrentTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showDetailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.torrentConnectButton = new System.Windows.Forms.Button();
            this.label4 = new System.Windows.Forms.Label();
            this.packetsTabPage = new System.Windows.Forms.TabPage();
            this.packetsSplitContainer = new System.Windows.Forms.SplitContainer();
            this.packetsListView = new System.Windows.Forms.ListView();
            this.columnHeader7 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader8 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader9 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetsListContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.copyHEXValuesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.saveToFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.packetDecodeListView = new System.Windows.Forms.ListView();
            this.packetDecodeColumnHeader1 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetDecodeColumnHeader2 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.packetDataContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.copyToClipboardToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.panel3 = new System.Windows.Forms.Panel();
            this.packetsMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.label5 = new System.Windows.Forms.Label();
            this.debugTabPage = new System.Windows.Forms.TabPage();
            this.debugTextBox = new System.Windows.Forms.TextBox();
            this.debugControlsPanel = new System.Windows.Forms.Panel();
            this.debugMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.label2 = new System.Windows.Forms.Label();
            this.tabsImageList = new System.Windows.Forms.ImageList(this.components);
            this.aprsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showAllMessagesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem7 = new System.Windows.Forms.ToolStripSeparator();
            this.beaconSettingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.smSMessageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.weatherReportToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.terminalTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showCallsignToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.waitForConnectionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem9 = new System.Windows.Forms.ToolStripSeparator();
            this.toolStripMenuItem13 = new System.Windows.Forms.ToolStripMenuItem();
            this.debugTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.debugSaveToFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.showBluetoothFramesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.loopbackModeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem3 = new System.Windows.Forms.ToolStripSeparator();
            this.queryDeviceNamesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem8 = new System.Windows.Forms.ToolStripSeparator();
            this.clearToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.batteryTimer = new System.Windows.Forms.Timer(this.components);
            this.saveTraceFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.aprsMsgContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.detailsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.showLocationToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.copyMessageToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.copyCallsignToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.packetsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showPacketDecodeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem18 = new System.Windows.Forms.ToolStripSeparator();
            this.saveToFileToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.openFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem17 = new System.Windows.Forms.ToolStripSeparator();
            this.clearPacketsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.savePacketsFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.openPacketsFileDialog = new System.Windows.Forms.OpenFileDialog();
            this.saveStationsFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.openStationsFileDialog = new System.Windows.Forms.OpenFileDialog();
            this.exportChannelsFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.importChannelFileDialog = new System.Windows.Forms.OpenFileDialog();
            this.bbsTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.viewTrafficToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem11 = new System.Windows.Forms.ToolStripSeparator();
            this.clearStatsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.notifyIcon = new System.Windows.Forms.NotifyIcon(this.components);
            this.notifyContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.hideToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem12 = new System.Windows.Forms.ToolStripSeparator();
            this.exitToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.mailTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showPreviewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.showTrafficToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem16 = new System.Windows.Forms.ToolStripSeparator();
            this.backupMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.restoreMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.backupMailSaveFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.restoreMailOpenFileDialog = new System.Windows.Forms.OpenFileDialog();
            this.torrentSaveFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.voiceTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.clearHistoryToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.microphoneImageList = new System.Windows.Forms.ImageList(this.components);
            this.voiceBottomPanel = new System.Windows.Forms.Panel();
            this.speakTextBox = new System.Windows.Forms.TextBox();
            this.speakButton = new System.Windows.Forms.Button();
            this.aprsChatControl = new HTCommander.ChatControl();
            this.torrentBlocksUserControl = new HTCommander.TorrentBlocksUserControl();
            this.mainStatusStrip.SuspendLayout();
            this.mainMenuStrip.SuspendLayout();
            this.radioPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.transmitPictureBox)).BeginInit();
            this.connectedPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.radioPictureBox)).BeginInit();
            this.mainTabControl.SuspendLayout();
            this.aprsTabPage.SuspendLayout();
            this.aprsMissingChannelPanel.SuspendLayout();
            this.aprsBottomPanel.SuspendLayout();
            this.aprsTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.aprsMenuPictureBox)).BeginInit();
            this.mapTabPage.SuspendLayout();
            this.mapTopPanel.SuspendLayout();
            this.voiceTabPage.SuspendLayout();
            this.panel6.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.voiceMenuPictureBox)).BeginInit();
            this.mailTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailboxHorizontalSplitContainer)).BeginInit();
            this.mailboxHorizontalSplitContainer.Panel1.SuspendLayout();
            this.mailboxHorizontalSplitContainer.Panel2.SuspendLayout();
            this.mailboxHorizontalSplitContainer.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailboxVerticalSplitContainer)).BeginInit();
            this.mailboxVerticalSplitContainer.Panel1.SuspendLayout();
            this.mailboxVerticalSplitContainer.Panel2.SuspendLayout();
            this.mailboxVerticalSplitContainer.SuspendLayout();
            this.mailContextMenuStrip.SuspendLayout();
            this.mailTransferStatusPanel.SuspendLayout();
            this.panel2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailMenuPictureBox)).BeginInit();
            this.stationsTabContextMenuStrip.SuspendLayout();
            this.terminalTabPage.SuspendLayout();
            this.terminalBottomPanel.SuspendLayout();
            this.terminalTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.terminalMenuPictureBox)).BeginInit();
            this.addressesTabPage.SuspendLayout();
            this.stationsContextMenuStrip.SuspendLayout();
            this.panel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.stationsMenuPictureBox)).BeginInit();
            this.bbsTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.bbsSplitContainer)).BeginInit();
            this.bbsSplitContainer.Panel1.SuspendLayout();
            this.bbsSplitContainer.Panel2.SuspendLayout();
            this.bbsSplitContainer.SuspendLayout();
            this.panel4.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.bbsMenuPictureBox)).BeginInit();
            this.torrentTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.torrentSplitContainer)).BeginInit();
            this.torrentSplitContainer.Panel1.SuspendLayout();
            this.torrentSplitContainer.Panel2.SuspendLayout();
            this.torrentSplitContainer.SuspendLayout();
            this.torrentContextMenuStrip.SuspendLayout();
            this.torrentTabControl.SuspendLayout();
            this.tabPage1.SuspendLayout();
            this.tabPage2.SuspendLayout();
            this.panel5.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.torrentMenuPictureBox)).BeginInit();
            this.torrentTabContextMenuStrip.SuspendLayout();
            this.packetsTabPage.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.packetsSplitContainer)).BeginInit();
            this.packetsSplitContainer.Panel1.SuspendLayout();
            this.packetsSplitContainer.Panel2.SuspendLayout();
            this.packetsSplitContainer.SuspendLayout();
            this.packetsListContextMenuStrip.SuspendLayout();
            this.packetDataContextMenuStrip.SuspendLayout();
            this.panel3.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.packetsMenuPictureBox)).BeginInit();
            this.debugTabPage.SuspendLayout();
            this.debugControlsPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.debugMenuPictureBox)).BeginInit();
            this.aprsContextMenuStrip.SuspendLayout();
            this.terminalTabContextMenuStrip.SuspendLayout();
            this.debugTabContextMenuStrip.SuspendLayout();
            this.aprsMsgContextMenuStrip.SuspendLayout();
            this.packetsContextMenuStrip.SuspendLayout();
            this.bbsTabContextMenuStrip.SuspendLayout();
            this.notifyContextMenuStrip.SuspendLayout();
            this.mailTabContextMenuStrip.SuspendLayout();
            this.voiceTabContextMenuStrip.SuspendLayout();
            this.voiceBottomPanel.SuspendLayout();
            this.SuspendLayout();
            // 
            // mainStatusStrip
            // 
            this.mainStatusStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainStatusStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.mainToolStripStatusLabel,
            this.batteryToolStripStatusLabel});
            this.mainStatusStrip.Location = new System.Drawing.Point(0, 556);
            this.mainStatusStrip.Name = "mainStatusStrip";
            this.mainStatusStrip.Size = new System.Drawing.Size(813, 22);
            this.mainStatusStrip.TabIndex = 0;
            this.mainStatusStrip.Text = "statusStrip1";
            // 
            // mainToolStripStatusLabel
            // 
            this.mainToolStripStatusLabel.Name = "mainToolStripStatusLabel";
            this.mainToolStripStatusLabel.Size = new System.Drawing.Size(798, 17);
            this.mainToolStripStatusLabel.Spring = true;
            // 
            // batteryToolStripStatusLabel
            // 
            this.batteryToolStripStatusLabel.Name = "batteryToolStripStatusLabel";
            this.batteryToolStripStatusLabel.Size = new System.Drawing.Size(44, 17);
            this.batteryToolStripStatusLabel.Text = "Battery";
            this.batteryToolStripStatusLabel.TextAlign = System.Drawing.ContentAlignment.MiddleRight;
            this.batteryToolStripStatusLabel.Visible = false;
            // 
            // mainMenuStrip
            // 
            this.mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.fileToolStripMenuItem,
            this.settingsToolStripMenuItem1,
            this.viewToolStripMenuItem,
            this.aboutToolStripMenuItem});
            this.mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            this.mainMenuStrip.Name = "mainMenuStrip";
            this.mainMenuStrip.Padding = new System.Windows.Forms.Padding(4, 2, 0, 2);
            this.mainMenuStrip.Size = new System.Drawing.Size(813, 24);
            this.mainMenuStrip.TabIndex = 1;
            this.mainMenuStrip.Text = "menuStrip1";
            this.mainMenuStrip.ItemClicked += new System.Windows.Forms.ToolStripItemClickedEventHandler(this.mainMenuStrip_ItemClicked);
            // 
            // fileToolStripMenuItem
            // 
            this.fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.connectToolStripMenuItem,
            this.disconnectToolStripMenuItem,
            this.toolStripMenuItem1,
            this.settingsToolStripMenuItem,
            this.systemTrayToolStripMenuItem,
            this.toolStripMenuItem4,
            this.exitToolStripMenuItem});
            this.fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            this.fileToolStripMenuItem.Size = new System.Drawing.Size(37, 20);
            this.fileToolStripMenuItem.Text = "&File";
            // 
            // connectToolStripMenuItem
            // 
            this.connectToolStripMenuItem.Name = "connectToolStripMenuItem";
            this.connectToolStripMenuItem.Size = new System.Drawing.Size(137, 22);
            this.connectToolStripMenuItem.Text = "&Connect...";
            this.connectToolStripMenuItem.Click += new System.EventHandler(this.connectToolStripMenuItem_Click);
            // 
            // disconnectToolStripMenuItem
            // 
            this.disconnectToolStripMenuItem.Enabled = false;
            this.disconnectToolStripMenuItem.Name = "disconnectToolStripMenuItem";
            this.disconnectToolStripMenuItem.Size = new System.Drawing.Size(137, 22);
            this.disconnectToolStripMenuItem.Text = "&Disconnect";
            this.disconnectToolStripMenuItem.Click += new System.EventHandler(this.disconnectToolStripMenuItem_Click);
            // 
            // toolStripMenuItem1
            // 
            this.toolStripMenuItem1.Name = "toolStripMenuItem1";
            this.toolStripMenuItem1.Size = new System.Drawing.Size(134, 6);
            // 
            // settingsToolStripMenuItem
            // 
            this.settingsToolStripMenuItem.Name = "settingsToolStripMenuItem";
            this.settingsToolStripMenuItem.Size = new System.Drawing.Size(137, 22);
            this.settingsToolStripMenuItem.Text = "&Settings...";
            this.settingsToolStripMenuItem.Click += new System.EventHandler(this.settingsToolStripMenuItem_Click);
            // 
            // systemTrayToolStripMenuItem
            // 
            this.systemTrayToolStripMenuItem.CheckOnClick = true;
            this.systemTrayToolStripMenuItem.Name = "systemTrayToolStripMenuItem";
            this.systemTrayToolStripMenuItem.Size = new System.Drawing.Size(137, 22);
            this.systemTrayToolStripMenuItem.Text = "System &Tray";
            this.systemTrayToolStripMenuItem.Click += new System.EventHandler(this.systemTrayToolStripMenuItem_Click);
            // 
            // toolStripMenuItem4
            // 
            this.toolStripMenuItem4.Name = "toolStripMenuItem4";
            this.toolStripMenuItem4.Size = new System.Drawing.Size(134, 6);
            // 
            // exitToolStripMenuItem
            // 
            this.exitToolStripMenuItem.Name = "exitToolStripMenuItem";
            this.exitToolStripMenuItem.Size = new System.Drawing.Size(137, 22);
            this.exitToolStripMenuItem.Text = "E&xit";
            this.exitToolStripMenuItem.Click += new System.EventHandler(this.exitToolStripMenuItem_Click);
            // 
            // settingsToolStripMenuItem1
            // 
            this.settingsToolStripMenuItem1.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.dualWatchToolStripMenuItem,
            this.scanToolStripMenuItem,
            this.regionToolStripMenuItem,
            this.toolStripMenuItem5,
            this.audioEnabledToolStripMenuItem,
            this.volumeToolStripMenuItem,
            this.toolStripMenuItem10,
            this.exportChannelsToolStripMenuItem,
            this.importChannelsToolStripMenuItem});
            this.settingsToolStripMenuItem1.Name = "settingsToolStripMenuItem1";
            this.settingsToolStripMenuItem1.Size = new System.Drawing.Size(61, 20);
            this.settingsToolStripMenuItem1.Text = "&Settings";
            this.settingsToolStripMenuItem1.DropDownOpening += new System.EventHandler(this.settingsToolStripMenuItem1_DropDownOpening);
            // 
            // dualWatchToolStripMenuItem
            // 
            this.dualWatchToolStripMenuItem.Enabled = false;
            this.dualWatchToolStripMenuItem.Name = "dualWatchToolStripMenuItem";
            this.dualWatchToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.dualWatchToolStripMenuItem.Text = "&Dual-Watch";
            this.dualWatchToolStripMenuItem.Click += new System.EventHandler(this.dualWatchToolStripMenuItem_Click);
            // 
            // scanToolStripMenuItem
            // 
            this.scanToolStripMenuItem.Enabled = false;
            this.scanToolStripMenuItem.Name = "scanToolStripMenuItem";
            this.scanToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.scanToolStripMenuItem.Text = "&Scan";
            this.scanToolStripMenuItem.Click += new System.EventHandler(this.scanToolStripMenuItem_Click);
            // 
            // regionToolStripMenuItem
            // 
            this.regionToolStripMenuItem.Enabled = false;
            this.regionToolStripMenuItem.Name = "regionToolStripMenuItem";
            this.regionToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.regionToolStripMenuItem.Text = "&Regions";
            // 
            // toolStripMenuItem5
            // 
            this.toolStripMenuItem5.Name = "toolStripMenuItem5";
            this.toolStripMenuItem5.Size = new System.Drawing.Size(168, 6);
            // 
            // audioEnabledToolStripMenuItem
            // 
            this.audioEnabledToolStripMenuItem.Name = "audioEnabledToolStripMenuItem";
            this.audioEnabledToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.audioEnabledToolStripMenuItem.Text = "&Audio Enabled";
            this.audioEnabledToolStripMenuItem.Click += new System.EventHandler(this.audioEnabledToolStripMenuItem_Click);
            // 
            // volumeToolStripMenuItem
            // 
            this.volumeToolStripMenuItem.Enabled = false;
            this.volumeToolStripMenuItem.Name = "volumeToolStripMenuItem";
            this.volumeToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.volumeToolStripMenuItem.Text = "&Volume...";
            this.volumeToolStripMenuItem.Click += new System.EventHandler(this.volumeToolStripMenuItem_Click);
            // 
            // toolStripMenuItem10
            // 
            this.toolStripMenuItem10.Name = "toolStripMenuItem10";
            this.toolStripMenuItem10.Size = new System.Drawing.Size(168, 6);
            // 
            // exportChannelsToolStripMenuItem
            // 
            this.exportChannelsToolStripMenuItem.Enabled = false;
            this.exportChannelsToolStripMenuItem.Name = "exportChannelsToolStripMenuItem";
            this.exportChannelsToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.exportChannelsToolStripMenuItem.Text = "&Export Channels...";
            this.exportChannelsToolStripMenuItem.Click += new System.EventHandler(this.exportChannelsToolStripMenuItem_Click);
            // 
            // importChannelsToolStripMenuItem
            // 
            this.importChannelsToolStripMenuItem.Name = "importChannelsToolStripMenuItem";
            this.importChannelsToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.importChannelsToolStripMenuItem.Text = "&Import Channels...";
            this.importChannelsToolStripMenuItem.Click += new System.EventHandler(this.importChannelsToolStripMenuItem_Click);
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
            this.viewToolStripMenuItem.Size = new System.Drawing.Size(44, 20);
            this.viewToolStripMenuItem.Text = "&View";
            this.viewToolStripMenuItem.DropDownOpening += new System.EventHandler(this.viewToolStripMenuItem_DropDownOpening);
            // 
            // radioToolStripMenuItem
            // 
            this.radioToolStripMenuItem.Checked = true;
            this.radioToolStripMenuItem.CheckOnClick = true;
            this.radioToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.radioToolStripMenuItem.Name = "radioToolStripMenuItem";
            this.radioToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.radioToolStripMenuItem.Text = "&Radio";
            this.radioToolStripMenuItem.Click += new System.EventHandler(this.radioToolStripMenuItem_Click);
            // 
            // allChannelsToolStripMenuItem
            // 
            this.allChannelsToolStripMenuItem.Name = "allChannelsToolStripMenuItem";
            this.allChannelsToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.allChannelsToolStripMenuItem.Text = "All Channels";
            this.allChannelsToolStripMenuItem.Click += new System.EventHandler(this.allChannelsToolStripMenuItem_Click);
            // 
            // toolStripMenuItem6
            // 
            this.toolStripMenuItem6.Name = "toolStripMenuItem6";
            this.toolStripMenuItem6.Size = new System.Drawing.Size(137, 6);
            // 
            // mapToolStripMenuItem
            // 
            this.mapToolStripMenuItem.CheckOnClick = true;
            this.mapToolStripMenuItem.Name = "mapToolStripMenuItem";
            this.mapToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.mapToolStripMenuItem.Text = "&Map";
            this.mapToolStripMenuItem.Click += new System.EventHandler(this.mapToolStripMenuItem_Click);
            // 
            // voiceToolStripMenuItem
            // 
            this.voiceToolStripMenuItem.CheckOnClick = true;
            this.voiceToolStripMenuItem.Name = "voiceToolStripMenuItem";
            this.voiceToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.voiceToolStripMenuItem.Text = "&Voice";
            this.voiceToolStripMenuItem.Click += new System.EventHandler(this.voiceToolStripMenuItem_Click);
            // 
            // terminalToolStripMenuItem
            // 
            this.terminalToolStripMenuItem.CheckOnClick = true;
            this.terminalToolStripMenuItem.Name = "terminalToolStripMenuItem";
            this.terminalToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.terminalToolStripMenuItem.Text = "&Terminal";
            this.terminalToolStripMenuItem.Click += new System.EventHandler(this.terminalToolStripMenuItem_Click);
            // 
            // mailToolStripMenuItem
            // 
            this.mailToolStripMenuItem.CheckOnClick = true;
            this.mailToolStripMenuItem.Name = "mailToolStripMenuItem";
            this.mailToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.mailToolStripMenuItem.Text = "&Mail";
            this.mailToolStripMenuItem.Click += new System.EventHandler(this.mailToolStripMenuItem_Click);
            // 
            // contactsToolStripMenuItem
            // 
            this.contactsToolStripMenuItem.CheckOnClick = true;
            this.contactsToolStripMenuItem.Name = "contactsToolStripMenuItem";
            this.contactsToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.contactsToolStripMenuItem.Text = "&Stations";
            this.contactsToolStripMenuItem.Click += new System.EventHandler(this.contactsToolStripMenuItem_Click);
            // 
            // bBSToolStripMenuItem
            // 
            this.bBSToolStripMenuItem.CheckOnClick = true;
            this.bBSToolStripMenuItem.Name = "bBSToolStripMenuItem";
            this.bBSToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.bBSToolStripMenuItem.Text = "&BBS";
            this.bBSToolStripMenuItem.Click += new System.EventHandler(this.bBSToolStripMenuItem_Click);
            // 
            // torrentToolStripMenuItem
            // 
            this.torrentToolStripMenuItem.CheckOnClick = true;
            this.torrentToolStripMenuItem.Name = "torrentToolStripMenuItem";
            this.torrentToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.torrentToolStripMenuItem.Text = "T&orrent";
            this.torrentToolStripMenuItem.Click += new System.EventHandler(this.torrentToolStripMenuItem_Click);
            // 
            // packetsToolStripMenuItem
            // 
            this.packetsToolStripMenuItem.CheckOnClick = true;
            this.packetsToolStripMenuItem.Name = "packetsToolStripMenuItem";
            this.packetsToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.packetsToolStripMenuItem.Text = "&Packets";
            this.packetsToolStripMenuItem.Click += new System.EventHandler(this.packetsToolStripMenuItem_Click);
            // 
            // debugToolStripMenuItem
            // 
            this.debugToolStripMenuItem.CheckOnClick = true;
            this.debugToolStripMenuItem.Name = "debugToolStripMenuItem";
            this.debugToolStripMenuItem.Size = new System.Drawing.Size(140, 22);
            this.debugToolStripMenuItem.Text = "&Debug";
            this.debugToolStripMenuItem.CheckStateChanged += new System.EventHandler(this.debugToolStripMenuItem_CheckStateChanged);
            // 
            // aboutToolStripMenuItem
            // 
            this.aboutToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.radioInformationToolStripMenuItem,
            this.radioStatusToolStripMenuItem,
            this.radioSettingsToolStripMenuItem,
            this.radioBSSSettingsToolStripMenuItem,
            this.toolStripMenuItem2,
            this.aboutToolStripMenuItem1});
            this.aboutToolStripMenuItem.Name = "aboutToolStripMenuItem";
            this.aboutToolStripMenuItem.Size = new System.Drawing.Size(52, 20);
            this.aboutToolStripMenuItem.Text = "&About";
            // 
            // radioInformationToolStripMenuItem
            // 
            this.radioInformationToolStripMenuItem.Enabled = false;
            this.radioInformationToolStripMenuItem.Name = "radioInformationToolStripMenuItem";
            this.radioInformationToolStripMenuItem.Size = new System.Drawing.Size(180, 22);
            this.radioInformationToolStripMenuItem.Text = "Radio Information...";
            this.radioInformationToolStripMenuItem.Click += new System.EventHandler(this.radioInformationToolStripMenuItem_Click);
            // 
            // radioStatusToolStripMenuItem
            // 
            this.radioStatusToolStripMenuItem.Enabled = false;
            this.radioStatusToolStripMenuItem.Name = "radioStatusToolStripMenuItem";
            this.radioStatusToolStripMenuItem.Size = new System.Drawing.Size(180, 22);
            this.radioStatusToolStripMenuItem.Text = "Radio &Status...";
            this.radioStatusToolStripMenuItem.Click += new System.EventHandler(this.radioStatusToolStripMenuItem_Click);
            // 
            // radioSettingsToolStripMenuItem
            // 
            this.radioSettingsToolStripMenuItem.Enabled = false;
            this.radioSettingsToolStripMenuItem.Name = "radioSettingsToolStripMenuItem";
            this.radioSettingsToolStripMenuItem.Size = new System.Drawing.Size(180, 22);
            this.radioSettingsToolStripMenuItem.Text = "Radio S&ettings...";
            this.radioSettingsToolStripMenuItem.Click += new System.EventHandler(this.radioSettingsToolStripMenuItem_Click);
            // 
            // radioBSSSettingsToolStripMenuItem
            // 
            this.radioBSSSettingsToolStripMenuItem.Enabled = false;
            this.radioBSSSettingsToolStripMenuItem.Name = "radioBSSSettingsToolStripMenuItem";
            this.radioBSSSettingsToolStripMenuItem.Size = new System.Drawing.Size(180, 22);
            this.radioBSSSettingsToolStripMenuItem.Text = "Radio BSS Settings...";
            this.radioBSSSettingsToolStripMenuItem.Click += new System.EventHandler(this.radioBSSSettingsToolStripMenuItem_Click);
            // 
            // toolStripMenuItem2
            // 
            this.toolStripMenuItem2.Name = "toolStripMenuItem2";
            this.toolStripMenuItem2.Size = new System.Drawing.Size(177, 6);
            // 
            // aboutToolStripMenuItem1
            // 
            this.aboutToolStripMenuItem1.Name = "aboutToolStripMenuItem1";
            this.aboutToolStripMenuItem1.Size = new System.Drawing.Size(180, 22);
            this.aboutToolStripMenuItem1.Text = "&About...";
            this.aboutToolStripMenuItem1.Click += new System.EventHandler(this.aboutToolStripMenuItem1_Click);
            // 
            // radioPanel
            // 
            this.radioPanel.AllowDrop = true;
            this.radioPanel.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            this.radioPanel.Controls.Add(this.transmitPictureBox);
            this.radioPanel.Controls.Add(this.transmitBarPanel);
            this.radioPanel.Controls.Add(this.channelsFlowLayoutPanel);
            this.radioPanel.Controls.Add(this.checkBluetoothButton);
            this.radioPanel.Controls.Add(this.rssiProgressBar);
            this.radioPanel.Controls.Add(this.connectedPanel);
            this.radioPanel.Controls.Add(this.radioStateLabel);
            this.radioPanel.Controls.Add(this.connectButton);
            this.radioPanel.Controls.Add(this.radioPictureBox);
            this.radioPanel.Dock = System.Windows.Forms.DockStyle.Left;
            this.radioPanel.Location = new System.Drawing.Point(0, 24);
            this.radioPanel.Name = "radioPanel";
            this.radioPanel.Size = new System.Drawing.Size(280, 532);
            this.radioPanel.TabIndex = 2;
            this.radioPanel.SizeChanged += new System.EventHandler(this.radioPanel_SizeChanged);
            this.radioPanel.DragDrop += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragDrop);
            this.radioPanel.DragEnter += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragEnter);
            // 
            // transmitPictureBox
            // 
            this.transmitPictureBox.Location = new System.Drawing.Point(115, 7);
            this.transmitPictureBox.Name = "transmitPictureBox";
            this.transmitPictureBox.Size = new System.Drawing.Size(48, 48);
            this.transmitPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.AutoSize;
            this.transmitPictureBox.TabIndex = 7;
            this.transmitPictureBox.TabStop = false;
            this.transmitPictureBox.Visible = false;
            this.transmitPictureBox.MouseDown += new System.Windows.Forms.MouseEventHandler(this.transmitPictureBox_MouseDown);
            this.transmitPictureBox.MouseEnter += new System.EventHandler(this.transmitPictureBox_MouseEnter);
            this.transmitPictureBox.MouseLeave += new System.EventHandler(this.transmitPictureBox_MouseLeave);
            this.transmitPictureBox.MouseUp += new System.Windows.Forms.MouseEventHandler(this.transmitPictureBox_MouseUp);
            // 
            // transmitBarPanel
            // 
            this.transmitBarPanel.BackColor = System.Drawing.Color.Red;
            this.transmitBarPanel.Location = new System.Drawing.Point(63, 265);
            this.transmitBarPanel.Margin = new System.Windows.Forms.Padding(2);
            this.transmitBarPanel.Name = "transmitBarPanel";
            this.transmitBarPanel.Size = new System.Drawing.Size(154, 6);
            this.transmitBarPanel.TabIndex = 7;
            this.transmitBarPanel.Visible = false;
            // 
            // channelsFlowLayoutPanel
            // 
            this.channelsFlowLayoutPanel.BackColor = System.Drawing.Color.DarkKhaki;
            this.channelsFlowLayoutPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.channelsFlowLayoutPanel.Location = new System.Drawing.Point(0, 392);
            this.channelsFlowLayoutPanel.Name = "channelsFlowLayoutPanel";
            this.channelsFlowLayoutPanel.Size = new System.Drawing.Size(276, 68);
            this.channelsFlowLayoutPanel.TabIndex = 2;
            this.channelsFlowLayoutPanel.Visible = false;
            // 
            // checkBluetoothButton
            // 
            this.checkBluetoothButton.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.checkBluetoothButton.Location = new System.Drawing.Point(0, 460);
            this.checkBluetoothButton.Name = "checkBluetoothButton";
            this.checkBluetoothButton.Size = new System.Drawing.Size(276, 34);
            this.checkBluetoothButton.TabIndex = 3;
            this.checkBluetoothButton.Text = "Check Bluetooth";
            this.checkBluetoothButton.UseVisualStyleBackColor = true;
            this.checkBluetoothButton.Visible = false;
            this.checkBluetoothButton.Click += new System.EventHandler(this.checkBluetoothButton_Click);
            // 
            // rssiProgressBar
            // 
            this.rssiProgressBar.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.rssiProgressBar.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.rssiProgressBar.ForeColor = System.Drawing.Color.Black;
            this.rssiProgressBar.Location = new System.Drawing.Point(63, 265);
            this.rssiProgressBar.Maximum = 15;
            this.rssiProgressBar.Name = "rssiProgressBar";
            this.rssiProgressBar.Size = new System.Drawing.Size(154, 6);
            this.rssiProgressBar.Step = 1;
            this.rssiProgressBar.Style = System.Windows.Forms.ProgressBarStyle.Continuous;
            this.rssiProgressBar.TabIndex = 0;
            this.rssiProgressBar.Visible = false;
            // 
            // connectedPanel
            // 
            this.connectedPanel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.connectedPanel.Controls.Add(this.voiceProcessingLabel);
            this.connectedPanel.Controls.Add(this.vfo2StatusLabel);
            this.connectedPanel.Controls.Add(this.vfo2FreqLabel);
            this.connectedPanel.Controls.Add(this.linePanel);
            this.connectedPanel.Controls.Add(this.vfo1StatusLabel);
            this.connectedPanel.Controls.Add(this.vfo1FreqLabel);
            this.connectedPanel.Controls.Add(this.vfo2Label);
            this.connectedPanel.Controls.Add(this.vfo1Label);
            this.connectedPanel.Location = new System.Drawing.Point(63, 140);
            this.connectedPanel.Name = "connectedPanel";
            this.connectedPanel.Size = new System.Drawing.Size(154, 123);
            this.connectedPanel.TabIndex = 1;
            this.connectedPanel.Visible = false;
            // 
            // voiceProcessingLabel
            // 
            this.voiceProcessingLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.voiceProcessingLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.voiceProcessingLabel.ForeColor = System.Drawing.Color.LightGray;
            this.voiceProcessingLabel.Location = new System.Drawing.Point(3, 105);
            this.voiceProcessingLabel.Name = "voiceProcessingLabel";
            this.voiceProcessingLabel.Size = new System.Drawing.Size(10, 15);
            this.voiceProcessingLabel.TabIndex = 8;
            this.voiceProcessingLabel.Text = "●";
            this.voiceProcessingLabel.Visible = false;
            // 
            // vfo2StatusLabel
            // 
            this.vfo2StatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo2StatusLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo2StatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo2StatusLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo2StatusLabel.Location = new System.Drawing.Point(71, 87);
            this.vfo2StatusLabel.Name = "vfo2StatusLabel";
            this.vfo2StatusLabel.Size = new System.Drawing.Size(80, 15);
            this.vfo2StatusLabel.TabIndex = 7;
            this.vfo2StatusLabel.Text = "VFO2";
            this.vfo2StatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            // 
            // vfo2FreqLabel
            // 
            this.vfo2FreqLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo2FreqLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo2FreqLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo2FreqLabel.Location = new System.Drawing.Point(3, 87);
            this.vfo2FreqLabel.Name = "vfo2FreqLabel";
            this.vfo2FreqLabel.Size = new System.Drawing.Size(88, 15);
            this.vfo2FreqLabel.TabIndex = 6;
            this.vfo2FreqLabel.Text = "VFO2";
            // 
            // linePanel
            // 
            this.linePanel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.linePanel.BackColor = System.Drawing.Color.LightGray;
            this.linePanel.ForeColor = System.Drawing.Color.LightGray;
            this.linePanel.Location = new System.Drawing.Point(11, 51);
            this.linePanel.Name = "linePanel";
            this.linePanel.Size = new System.Drawing.Size(131, 2);
            this.linePanel.TabIndex = 5;
            // 
            // vfo1StatusLabel
            // 
            this.vfo1StatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo1StatusLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo1StatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo1StatusLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo1StatusLabel.Location = new System.Drawing.Point(74, 33);
            this.vfo1StatusLabel.Name = "vfo1StatusLabel";
            this.vfo1StatusLabel.Size = new System.Drawing.Size(77, 15);
            this.vfo1StatusLabel.TabIndex = 4;
            this.vfo1StatusLabel.Text = "VFO1";
            this.vfo1StatusLabel.TextAlign = System.Drawing.ContentAlignment.TopRight;
            // 
            // vfo1FreqLabel
            // 
            this.vfo1FreqLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo1FreqLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 8.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo1FreqLabel.ForeColor = System.Drawing.Color.LightGray;
            this.vfo1FreqLabel.Location = new System.Drawing.Point(3, 33);
            this.vfo1FreqLabel.Name = "vfo1FreqLabel";
            this.vfo1FreqLabel.Size = new System.Drawing.Size(88, 15);
            this.vfo1FreqLabel.TabIndex = 3;
            this.vfo1FreqLabel.Text = "VFO1";
            // 
            // vfo2Label
            // 
            this.vfo2Label.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo2Label.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo2Label.Font = new System.Drawing.Font("Microsoft Sans Serif", 20.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo2Label.ForeColor = System.Drawing.Color.LightGray;
            this.vfo2Label.Location = new System.Drawing.Point(3, 54);
            this.vfo2Label.Name = "vfo2Label";
            this.vfo2Label.Size = new System.Drawing.Size(148, 33);
            this.vfo2Label.TabIndex = 2;
            this.vfo2Label.Text = "VFO2";
            this.vfo2Label.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            // 
            // vfo1Label
            // 
            this.vfo1Label.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.vfo1Label.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.vfo1Label.Font = new System.Drawing.Font("Microsoft Sans Serif", 20.25F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.vfo1Label.ForeColor = System.Drawing.Color.LightGray;
            this.vfo1Label.Location = new System.Drawing.Point(3, 0);
            this.vfo1Label.Name = "vfo1Label";
            this.vfo1Label.Size = new System.Drawing.Size(148, 33);
            this.vfo1Label.TabIndex = 1;
            this.vfo1Label.Text = "VFO1";
            this.vfo1Label.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            // 
            // radioStateLabel
            // 
            this.radioStateLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.radioStateLabel.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(86)))), ((int)(((byte)(86)))), ((int)(((byte)(88)))));
            this.radioStateLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.radioStateLabel.ForeColor = System.Drawing.Color.LightGray;
            this.radioStateLabel.Location = new System.Drawing.Point(63, 140);
            this.radioStateLabel.Name = "radioStateLabel";
            this.radioStateLabel.Size = new System.Drawing.Size(154, 130);
            this.radioStateLabel.TabIndex = 1;
            this.radioStateLabel.Text = "Disconnected";
            this.radioStateLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // connectButton
            // 
            this.connectButton.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.connectButton.Location = new System.Drawing.Point(0, 494);
            this.connectButton.Name = "connectButton";
            this.connectButton.Size = new System.Drawing.Size(276, 34);
            this.connectButton.TabIndex = 0;
            this.connectButton.Text = "Connect";
            this.connectButton.UseVisualStyleBackColor = true;
            this.connectButton.Click += new System.EventHandler(this.connectToolStripMenuItem_Click);
            // 
            // radioPictureBox
            // 
            this.radioPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("radioPictureBox.Image")));
            this.radioPictureBox.Location = new System.Drawing.Point(8, -2);
            this.radioPictureBox.Name = "radioPictureBox";
            this.radioPictureBox.Size = new System.Drawing.Size(256, 551);
            this.radioPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.radioPictureBox.TabIndex = 0;
            this.radioPictureBox.TabStop = false;
            this.radioPictureBox.DragDrop += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragDrop);
            this.radioPictureBox.DragEnter += new System.Windows.Forms.DragEventHandler(this.radioPictureBox_DragEnter);
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
            this.mainTabControl.Location = new System.Drawing.Point(280, 24);
            this.mainTabControl.Multiline = true;
            this.mainTabControl.Name = "mainTabControl";
            this.mainTabControl.SelectedIndex = 0;
            this.mainTabControl.Size = new System.Drawing.Size(533, 532);
            this.mainTabControl.TabIndex = 3;
            // 
            // aprsTabPage
            // 
            this.aprsTabPage.Controls.Add(this.aprsChatControl);
            this.aprsTabPage.Controls.Add(this.aprsMissingChannelPanel);
            this.aprsTabPage.Controls.Add(this.aprsBottomPanel);
            this.aprsTabPage.Controls.Add(this.aprsTopPanel);
            this.aprsTabPage.ImageIndex = 3;
            this.aprsTabPage.Location = new System.Drawing.Point(4, 4);
            this.aprsTabPage.Name = "aprsTabPage";
            this.aprsTabPage.Size = new System.Drawing.Size(490, 524);
            this.aprsTabPage.TabIndex = 3;
            this.aprsTabPage.UseVisualStyleBackColor = true;
            // 
            // mainImageList
            // 
            this.mainImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("mainImageList.ImageStream")));
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.mainImageList.Images.SetKeyName(0, "");
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
            // aprsMissingChannelPanel
            // 
            this.aprsMissingChannelPanel.BackColor = System.Drawing.Color.MistyRose;
            this.aprsMissingChannelPanel.Controls.Add(this.aprsSetupButton);
            this.aprsMissingChannelPanel.Controls.Add(this.missingAprsChannelLabel);
            this.aprsMissingChannelPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.aprsMissingChannelPanel.Location = new System.Drawing.Point(0, 30);
            this.aprsMissingChannelPanel.Name = "aprsMissingChannelPanel";
            this.aprsMissingChannelPanel.Size = new System.Drawing.Size(490, 30);
            this.aprsMissingChannelPanel.TabIndex = 6;
            this.aprsMissingChannelPanel.Visible = false;
            // 
            // aprsSetupButton
            // 
            this.aprsSetupButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsSetupButton.Location = new System.Drawing.Point(412, 4);
            this.aprsSetupButton.Name = "aprsSetupButton";
            this.aprsSetupButton.Size = new System.Drawing.Size(75, 23);
            this.aprsSetupButton.TabIndex = 8;
            this.aprsSetupButton.Text = "Setup";
            this.aprsSetupButton.UseVisualStyleBackColor = true;
            this.aprsSetupButton.Click += new System.EventHandler(this.aprsSetupButton_Click);
            // 
            // missingAprsChannelLabel
            // 
            this.missingAprsChannelLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.missingAprsChannelLabel.AutoSize = true;
            this.missingAprsChannelLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.missingAprsChannelLabel.Location = new System.Drawing.Point(5, 7);
            this.missingAprsChannelLabel.Name = "missingAprsChannelLabel";
            this.missingAprsChannelLabel.Size = new System.Drawing.Size(323, 16);
            this.missingAprsChannelLabel.TabIndex = 7;
            this.missingAprsChannelLabel.Text = "Configure a channel labeled APRS to use this feature.";
            // 
            // aprsBottomPanel
            // 
            this.aprsBottomPanel.BackColor = System.Drawing.Color.Silver;
            this.aprsBottomPanel.Controls.Add(this.aprsDestinationComboBox);
            this.aprsBottomPanel.Controls.Add(this.aprsTextBox);
            this.aprsBottomPanel.Controls.Add(this.aprsSendButton);
            this.aprsBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.aprsBottomPanel.Location = new System.Drawing.Point(0, 486);
            this.aprsBottomPanel.Name = "aprsBottomPanel";
            this.aprsBottomPanel.Size = new System.Drawing.Size(490, 38);
            this.aprsBottomPanel.TabIndex = 4;
            // 
            // aprsDestinationComboBox
            // 
            this.aprsDestinationComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left)));
            this.aprsDestinationComboBox.Enabled = false;
            this.aprsDestinationComboBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.aprsDestinationComboBox.FormattingEnabled = true;
            this.aprsDestinationComboBox.Items.AddRange(new object[] {
            "ALL",
            "QST",
            "CQ"});
            this.aprsDestinationComboBox.Location = new System.Drawing.Point(5, 6);
            this.aprsDestinationComboBox.MaxLength = 9;
            this.aprsDestinationComboBox.Name = "aprsDestinationComboBox";
            this.aprsDestinationComboBox.Size = new System.Drawing.Size(111, 28);
            this.aprsDestinationComboBox.TabIndex = 7;
            this.aprsDestinationComboBox.SelectionChangeCommitted += new System.EventHandler(this.aprsDestinationComboBox_SelectionChangeCommitted);
            this.aprsDestinationComboBox.TextChanged += new System.EventHandler(this.aprsDestinationComboBox_TextChanged);
            this.aprsDestinationComboBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.aprsDestinationComboBox_KeyPress);
            // 
            // aprsTextBox
            // 
            this.aprsTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsTextBox.Enabled = false;
            this.aprsTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.aprsTextBox.Location = new System.Drawing.Point(122, 7);
            this.aprsTextBox.MaxLength = 67;
            this.aprsTextBox.Name = "aprsTextBox";
            this.aprsTextBox.Size = new System.Drawing.Size(284, 26);
            this.aprsTextBox.TabIndex = 1;
            this.aprsTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.aprsTextBox_KeyPress);
            // 
            // aprsSendButton
            // 
            this.aprsSendButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsSendButton.Enabled = false;
            this.aprsSendButton.Location = new System.Drawing.Point(412, 5);
            this.aprsSendButton.Name = "aprsSendButton";
            this.aprsSendButton.Size = new System.Drawing.Size(75, 28);
            this.aprsSendButton.TabIndex = 0;
            this.aprsSendButton.Text = "&Send";
            this.aprsSendButton.UseVisualStyleBackColor = true;
            this.aprsSendButton.Click += new System.EventHandler(this.aprsSendButton_Click);
            // 
            // aprsTopPanel
            // 
            this.aprsTopPanel.BackColor = System.Drawing.Color.Silver;
            this.aprsTopPanel.Controls.Add(this.aprsRouteComboBox);
            this.aprsTopPanel.Controls.Add(this.aprsMenuPictureBox);
            this.aprsTopPanel.Controls.Add(this.aprsTitleLabel);
            this.aprsTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.aprsTopPanel.Location = new System.Drawing.Point(0, 0);
            this.aprsTopPanel.Name = "aprsTopPanel";
            this.aprsTopPanel.Size = new System.Drawing.Size(490, 30);
            this.aprsTopPanel.TabIndex = 2;
            // 
            // aprsRouteComboBox
            // 
            this.aprsRouteComboBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsRouteComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.aprsRouteComboBox.FormattingEnabled = true;
            this.aprsRouteComboBox.Location = new System.Drawing.Point(366, 5);
            this.aprsRouteComboBox.Name = "aprsRouteComboBox";
            this.aprsRouteComboBox.Size = new System.Drawing.Size(94, 21);
            this.aprsRouteComboBox.TabIndex = 3;
            this.aprsRouteComboBox.Visible = false;
            this.aprsRouteComboBox.SelectionChangeCommitted += new System.EventHandler(this.aprsRouteComboBox_SelectionChangeCommitted);
            // 
            // aprsMenuPictureBox
            // 
            this.aprsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("aprsMenuPictureBox.Image")));
            this.aprsMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.aprsMenuPictureBox.Name = "aprsMenuPictureBox";
            this.aprsMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.aprsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.aprsMenuPictureBox.TabIndex = 2;
            this.aprsMenuPictureBox.TabStop = false;
            this.aprsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.aprsMenuPictureBox_MouseClick);
            // 
            // aprsTitleLabel
            // 
            this.aprsTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.aprsTitleLabel.AutoSize = true;
            this.aprsTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.aprsTitleLabel.Location = new System.Drawing.Point(5, 5);
            this.aprsTitleLabel.Name = "aprsTitleLabel";
            this.aprsTitleLabel.Size = new System.Drawing.Size(53, 20);
            this.aprsTitleLabel.TabIndex = 0;
            this.aprsTitleLabel.Text = "APRS";
            this.aprsTitleLabel.DoubleClick += new System.EventHandler(this.aprsTitleLabel_DoubleClick);
            // 
            // mapTabPage
            // 
            this.mapTabPage.Controls.Add(this.mapZoomOutButton);
            this.mapTabPage.Controls.Add(this.mapZoomInbutton);
            this.mapTabPage.Controls.Add(this.mapTopPanel);
            this.mapTabPage.ImageIndex = 1;
            this.mapTabPage.Location = new System.Drawing.Point(4, 4);
            this.mapTabPage.Name = "mapTabPage";
            this.mapTabPage.Size = new System.Drawing.Size(490, 524);
            this.mapTabPage.TabIndex = 0;
            this.mapTabPage.ToolTipText = "APRS";
            this.mapTabPage.UseVisualStyleBackColor = true;
            // 
            // mapZoomOutButton
            // 
            this.mapZoomOutButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mapZoomOutButton.Location = new System.Drawing.Point(3, 76);
            this.mapZoomOutButton.Name = "mapZoomOutButton";
            this.mapZoomOutButton.Size = new System.Drawing.Size(42, 34);
            this.mapZoomOutButton.TabIndex = 5;
            this.mapZoomOutButton.Text = "-";
            this.mapZoomOutButton.UseVisualStyleBackColor = true;
            this.mapZoomOutButton.Click += new System.EventHandler(this.mapZoomOutButton_Click);
            // 
            // mapZoomInbutton
            // 
            this.mapZoomInbutton.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mapZoomInbutton.Location = new System.Drawing.Point(3, 36);
            this.mapZoomInbutton.Name = "mapZoomInbutton";
            this.mapZoomInbutton.Size = new System.Drawing.Size(42, 34);
            this.mapZoomInbutton.TabIndex = 4;
            this.mapZoomInbutton.Text = "+";
            this.mapZoomInbutton.UseVisualStyleBackColor = true;
            this.mapZoomInbutton.Click += new System.EventHandler(this.mapZoomInbutton_Click);
            // 
            // mapTopPanel
            // 
            this.mapTopPanel.BackColor = System.Drawing.Color.Silver;
            this.mapTopPanel.Controls.Add(this.mapTopLabel);
            this.mapTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.mapTopPanel.Location = new System.Drawing.Point(0, 0);
            this.mapTopPanel.Name = "mapTopPanel";
            this.mapTopPanel.Size = new System.Drawing.Size(490, 30);
            this.mapTopPanel.TabIndex = 3;
            // 
            // mapTopLabel
            // 
            this.mapTopLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.mapTopLabel.AutoSize = true;
            this.mapTopLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mapTopLabel.Location = new System.Drawing.Point(5, 5);
            this.mapTopLabel.Name = "mapTopLabel";
            this.mapTopLabel.Size = new System.Drawing.Size(40, 20);
            this.mapTopLabel.TabIndex = 0;
            this.mapTopLabel.Text = "Map";
            // 
            // voiceTabPage
            // 
            this.voiceTabPage.Controls.Add(this.voiceHistoryTextBox);
            this.voiceTabPage.Controls.Add(this.voiceBottomPanel);
            this.voiceTabPage.Controls.Add(this.panel6);
            this.voiceTabPage.ImageIndex = 9;
            this.voiceTabPage.Location = new System.Drawing.Point(4, 4);
            this.voiceTabPage.Margin = new System.Windows.Forms.Padding(2);
            this.voiceTabPage.Name = "voiceTabPage";
            this.voiceTabPage.Size = new System.Drawing.Size(490, 524);
            this.voiceTabPage.TabIndex = 9;
            this.voiceTabPage.UseVisualStyleBackColor = true;
            // 
            // voiceHistoryTextBox
            // 
            this.voiceHistoryTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.voiceHistoryTextBox.Location = new System.Drawing.Point(0, 30);
            this.voiceHistoryTextBox.Margin = new System.Windows.Forms.Padding(2);
            this.voiceHistoryTextBox.Name = "voiceHistoryTextBox";
            this.voiceHistoryTextBox.ReadOnly = true;
            this.voiceHistoryTextBox.ScrollBars = System.Windows.Forms.RichTextBoxScrollBars.ForcedVertical;
            this.voiceHistoryTextBox.Size = new System.Drawing.Size(490, 456);
            this.voiceHistoryTextBox.TabIndex = 0;
            this.voiceHistoryTextBox.Text = "";
            // 
            // panel6
            // 
            this.panel6.BackColor = System.Drawing.Color.Silver;
            this.panel6.Controls.Add(this.voiceEnableButton);
            this.panel6.Controls.Add(this.voiceMenuPictureBox);
            this.panel6.Controls.Add(this.label6);
            this.panel6.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel6.Location = new System.Drawing.Point(0, 0);
            this.panel6.Name = "panel6";
            this.panel6.Size = new System.Drawing.Size(490, 30);
            this.panel6.TabIndex = 2;
            // 
            // voiceEnableButton
            // 
            this.voiceEnableButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.voiceEnableButton.Enabled = false;
            this.voiceEnableButton.Location = new System.Drawing.Point(385, 3);
            this.voiceEnableButton.Name = "voiceEnableButton";
            this.voiceEnableButton.Size = new System.Drawing.Size(75, 23);
            this.voiceEnableButton.TabIndex = 6;
            this.voiceEnableButton.Text = "&Enable";
            this.voiceEnableButton.UseVisualStyleBackColor = true;
            this.voiceEnableButton.Click += new System.EventHandler(this.voiceEnableButton_Click);
            // 
            // voiceMenuPictureBox
            // 
            this.voiceMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.voiceMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("voiceMenuPictureBox.Image")));
            this.voiceMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.voiceMenuPictureBox.Name = "voiceMenuPictureBox";
            this.voiceMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.voiceMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.voiceMenuPictureBox.TabIndex = 3;
            this.voiceMenuPictureBox.TabStop = false;
            this.voiceMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.voiceMenuPictureBox_MouseClick);
            // 
            // label6
            // 
            this.label6.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label6.AutoSize = true;
            this.label6.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label6.Location = new System.Drawing.Point(3, 5);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(49, 20);
            this.label6.TabIndex = 1;
            this.label6.Text = "Voice";
            // 
            // mailTabPage
            // 
            this.mailTabPage.Controls.Add(this.mailboxHorizontalSplitContainer);
            this.mailTabPage.Controls.Add(this.mailTransferStatusPanel);
            this.mailTabPage.Controls.Add(this.panel2);
            this.mailTabPage.ImageIndex = 5;
            this.mailTabPage.Location = new System.Drawing.Point(4, 4);
            this.mailTabPage.Name = "mailTabPage";
            this.mailTabPage.Size = new System.Drawing.Size(490, 524);
            this.mailTabPage.TabIndex = 5;
            this.mailTabPage.UseVisualStyleBackColor = true;
            // 
            // mailboxHorizontalSplitContainer
            // 
            this.mailboxHorizontalSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailboxHorizontalSplitContainer.Location = new System.Drawing.Point(0, 30);
            this.mailboxHorizontalSplitContainer.Margin = new System.Windows.Forms.Padding(2);
            this.mailboxHorizontalSplitContainer.Name = "mailboxHorizontalSplitContainer";
            this.mailboxHorizontalSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // mailboxHorizontalSplitContainer.Panel1
            // 
            this.mailboxHorizontalSplitContainer.Panel1.Controls.Add(this.mailboxVerticalSplitContainer);
            // 
            // mailboxHorizontalSplitContainer.Panel2
            // 
            this.mailboxHorizontalSplitContainer.Panel2.Controls.Add(this.mailPreviewTextBox);
            this.mailboxHorizontalSplitContainer.Size = new System.Drawing.Size(490, 464);
            this.mailboxHorizontalSplitContainer.SplitterDistance = 214;
            this.mailboxHorizontalSplitContainer.SplitterWidth = 3;
            this.mailboxHorizontalSplitContainer.TabIndex = 7;
            // 
            // mailboxVerticalSplitContainer
            // 
            this.mailboxVerticalSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailboxVerticalSplitContainer.FixedPanel = System.Windows.Forms.FixedPanel.Panel1;
            this.mailboxVerticalSplitContainer.Location = new System.Drawing.Point(0, 0);
            this.mailboxVerticalSplitContainer.Margin = new System.Windows.Forms.Padding(2);
            this.mailboxVerticalSplitContainer.Name = "mailboxVerticalSplitContainer";
            // 
            // mailboxVerticalSplitContainer.Panel1
            // 
            this.mailboxVerticalSplitContainer.Panel1.Controls.Add(this.mailBoxesTreeView);
            // 
            // mailboxVerticalSplitContainer.Panel2
            // 
            this.mailboxVerticalSplitContainer.Panel2.Controls.Add(this.mailboxListView);
            this.mailboxVerticalSplitContainer.Size = new System.Drawing.Size(490, 214);
            this.mailboxVerticalSplitContainer.SplitterDistance = 151;
            this.mailboxVerticalSplitContainer.SplitterWidth = 3;
            this.mailboxVerticalSplitContainer.TabIndex = 6;
            // 
            // mailBoxesTreeView
            // 
            this.mailBoxesTreeView.AllowDrop = true;
            this.mailBoxesTreeView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailBoxesTreeView.ImageIndex = 0;
            this.mailBoxesTreeView.ImageList = this.mailBoxImageList;
            this.mailBoxesTreeView.Location = new System.Drawing.Point(0, 0);
            this.mailBoxesTreeView.Margin = new System.Windows.Forms.Padding(2);
            this.mailBoxesTreeView.Name = "mailBoxesTreeView";
            this.mailBoxesTreeView.SelectedImageIndex = 0;
            this.mailBoxesTreeView.ShowRootLines = false;
            this.mailBoxesTreeView.Size = new System.Drawing.Size(151, 214);
            this.mailBoxesTreeView.TabIndex = 0;
            this.mailBoxesTreeView.NodeMouseClick += new System.Windows.Forms.TreeNodeMouseClickEventHandler(this.mailBoxesTreeView_NodeMouseClick);
            this.mailBoxesTreeView.DragDrop += new System.Windows.Forms.DragEventHandler(this.mailBoxesTreeView_DragDrop);
            this.mailBoxesTreeView.DragEnter += new System.Windows.Forms.DragEventHandler(this.mailBoxesTreeView_DragEnter);
            this.mailBoxesTreeView.DragOver += new System.Windows.Forms.DragEventHandler(this.mailBoxesTreeView_DragEnter);
            // 
            // mailBoxImageList
            // 
            this.mailBoxImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("mailBoxImageList.ImageStream")));
            this.mailBoxImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.mailBoxImageList.Images.SetKeyName(0, "mailbox-25.png");
            this.mailBoxImageList.Images.SetKeyName(1, "outbox-25.png");
            this.mailBoxImageList.Images.SetKeyName(2, "draft-25.png");
            this.mailBoxImageList.Images.SetKeyName(3, "sent-25.png");
            this.mailBoxImageList.Images.SetKeyName(4, "archive-25.png");
            this.mailBoxImageList.Images.SetKeyName(5, "trash-25.png");
            this.mailBoxImageList.Images.SetKeyName(6, "folder-25.png");
            this.mailBoxImageList.Images.SetKeyName(7, "junk-25.png");
            this.mailBoxImageList.Images.SetKeyName(8, "notes-25.png");
            // 
            // mailboxListView
            // 
            this.mailboxListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader4,
            this.columnHeader5,
            this.columnHeader6});
            this.mailboxListView.ContextMenuStrip = this.mailContextMenuStrip;
            this.mailboxListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailboxListView.FullRowSelect = true;
            this.mailboxListView.GridLines = true;
            this.mailboxListView.HideSelection = false;
            this.mailboxListView.Location = new System.Drawing.Point(0, 0);
            this.mailboxListView.Name = "mailboxListView";
            this.mailboxListView.Size = new System.Drawing.Size(336, 214);
            this.mailboxListView.SmallImageList = this.mainImageList;
            this.mailboxListView.TabIndex = 5;
            this.mailboxListView.UseCompatibleStateImageBehavior = false;
            this.mailboxListView.View = System.Windows.Forms.View.Details;
            this.mailboxListView.SelectedIndexChanged += new System.EventHandler(this.mailboxListView_SelectedIndexChanged);
            this.mailboxListView.DoubleClick += new System.EventHandler(this.mailboxListView_DoubleClick);
            this.mailboxListView.KeyDown += new System.Windows.Forms.KeyEventHandler(this.mailboxListView_KeyDown);
            this.mailboxListView.MouseDown += new System.Windows.Forms.MouseEventHandler(this.mailboxListView_MouseDown);
            this.mailboxListView.MouseMove += new System.Windows.Forms.MouseEventHandler(this.mailboxListView_MouseMove);
            this.mailboxListView.MouseUp += new System.Windows.Forms.MouseEventHandler(this.mailboxListView_MouseUp);
            // 
            // columnHeader4
            // 
            this.columnHeader4.Text = "Time";
            this.columnHeader4.Width = 100;
            // 
            // columnHeader5
            // 
            this.columnHeader5.Text = "From";
            this.columnHeader5.Width = 100;
            // 
            // columnHeader6
            // 
            this.columnHeader6.Text = "Subject";
            this.columnHeader6.Width = 290;
            // 
            // mailContextMenuStrip
            // 
            this.mailContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mailContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.viewMailToolStripMenuItem,
            this.editMailToolStripMenuItem,
            this.toolStripMenuItem14,
            this.moveToDraftToolStripMenuItem,
            this.moveToOutboxToolStripMenuItem,
            this.moveToInboxToolStripMenuItem,
            this.moveToArchiveToolStripMenuItem,
            this.moveToTrashToolStripMenuItem,
            this.toolStripMenuItem15,
            this.deleteMailToolStripMenuItem});
            this.mailContextMenuStrip.Name = "mailContextMenuStrip";
            this.mailContextMenuStrip.Size = new System.Drawing.Size(162, 192);
            // 
            // viewMailToolStripMenuItem
            // 
            this.viewMailToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.viewMailToolStripMenuItem.Name = "viewMailToolStripMenuItem";
            this.viewMailToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.viewMailToolStripMenuItem.Text = "&View...";
            this.viewMailToolStripMenuItem.Click += new System.EventHandler(this.mailboxListView_DoubleClick);
            // 
            // editMailToolStripMenuItem
            // 
            this.editMailToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.editMailToolStripMenuItem.Name = "editMailToolStripMenuItem";
            this.editMailToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.editMailToolStripMenuItem.Text = "&Edit...";
            this.editMailToolStripMenuItem.Click += new System.EventHandler(this.mailboxListView_DoubleClick);
            // 
            // toolStripMenuItem14
            // 
            this.toolStripMenuItem14.Name = "toolStripMenuItem14";
            this.toolStripMenuItem14.Size = new System.Drawing.Size(158, 6);
            // 
            // moveToDraftToolStripMenuItem
            // 
            this.moveToDraftToolStripMenuItem.Name = "moveToDraftToolStripMenuItem";
            this.moveToDraftToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.moveToDraftToolStripMenuItem.Text = "Move to D&raft";
            this.moveToDraftToolStripMenuItem.Click += new System.EventHandler(this.moveToDraftToolStripMenuItem_Click);
            // 
            // moveToOutboxToolStripMenuItem
            // 
            this.moveToOutboxToolStripMenuItem.Name = "moveToOutboxToolStripMenuItem";
            this.moveToOutboxToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.moveToOutboxToolStripMenuItem.Text = "Move to &Outbox";
            this.moveToOutboxToolStripMenuItem.Click += new System.EventHandler(this.moveToOutboxToolStripMenuItem_Click);
            // 
            // moveToInboxToolStripMenuItem
            // 
            this.moveToInboxToolStripMenuItem.Name = "moveToInboxToolStripMenuItem";
            this.moveToInboxToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.moveToInboxToolStripMenuItem.Text = "Move to &Inbox";
            this.moveToInboxToolStripMenuItem.Click += new System.EventHandler(this.moveToInboxToolStripMenuItem_Click);
            // 
            // moveToArchiveToolStripMenuItem
            // 
            this.moveToArchiveToolStripMenuItem.Name = "moveToArchiveToolStripMenuItem";
            this.moveToArchiveToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.moveToArchiveToolStripMenuItem.Text = "Move to &Archive";
            this.moveToArchiveToolStripMenuItem.Click += new System.EventHandler(this.moveToArchiveToolStripMenuItem_Click);
            // 
            // moveToTrashToolStripMenuItem
            // 
            this.moveToTrashToolStripMenuItem.Name = "moveToTrashToolStripMenuItem";
            this.moveToTrashToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.moveToTrashToolStripMenuItem.Text = "Move to &Trash";
            this.moveToTrashToolStripMenuItem.Click += new System.EventHandler(this.moveToTrashToolStripMenuItem_Click);
            // 
            // toolStripMenuItem15
            // 
            this.toolStripMenuItem15.Name = "toolStripMenuItem15";
            this.toolStripMenuItem15.Size = new System.Drawing.Size(158, 6);
            // 
            // deleteMailToolStripMenuItem
            // 
            this.deleteMailToolStripMenuItem.Name = "deleteMailToolStripMenuItem";
            this.deleteMailToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.deleteMailToolStripMenuItem.Text = "&Delete";
            this.deleteMailToolStripMenuItem.Click += new System.EventHandler(this.deleteMailToolStripMenuItem_Click);
            // 
            // mailPreviewTextBox
            // 
            this.mailPreviewTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.mailPreviewTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailPreviewTextBox.Location = new System.Drawing.Point(0, 0);
            this.mailPreviewTextBox.Margin = new System.Windows.Forms.Padding(2);
            this.mailPreviewTextBox.Name = "mailPreviewTextBox";
            this.mailPreviewTextBox.ReadOnly = true;
            this.mailPreviewTextBox.Size = new System.Drawing.Size(490, 247);
            this.mailPreviewTextBox.TabIndex = 0;
            this.mailPreviewTextBox.Text = "";
            // 
            // mailTransferStatusPanel
            // 
            this.mailTransferStatusPanel.BackColor = System.Drawing.Color.Silver;
            this.mailTransferStatusPanel.Controls.Add(this.mailTransferStatusLabel);
            this.mailTransferStatusPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.mailTransferStatusPanel.Location = new System.Drawing.Point(0, 494);
            this.mailTransferStatusPanel.Name = "mailTransferStatusPanel";
            this.mailTransferStatusPanel.Size = new System.Drawing.Size(490, 30);
            this.mailTransferStatusPanel.TabIndex = 8;
            this.mailTransferStatusPanel.Visible = false;
            // 
            // mailTransferStatusLabel
            // 
            this.mailTransferStatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.mailTransferStatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mailTransferStatusLabel.Location = new System.Drawing.Point(3, 5);
            this.mailTransferStatusLabel.Name = "mailTransferStatusLabel";
            this.mailTransferStatusLabel.Size = new System.Drawing.Size(483, 20);
            this.mailTransferStatusLabel.TabIndex = 1;
            this.mailTransferStatusLabel.Text = "Disconnected";
            // 
            // panel2
            // 
            this.panel2.BackColor = System.Drawing.Color.Silver;
            this.panel2.Controls.Add(this.newMailButton);
            this.panel2.Controls.Add(this.mailConnectButton);
            this.panel2.Controls.Add(this.mailMenuPictureBox);
            this.panel2.Controls.Add(this.mailTitleLabel);
            this.panel2.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel2.Location = new System.Drawing.Point(0, 0);
            this.panel2.Name = "panel2";
            this.panel2.Size = new System.Drawing.Size(490, 30);
            this.panel2.TabIndex = 2;
            // 
            // newMailButton
            // 
            this.newMailButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.newMailButton.Location = new System.Drawing.Point(303, 3);
            this.newMailButton.Name = "newMailButton";
            this.newMailButton.Size = new System.Drawing.Size(75, 23);
            this.newMailButton.TabIndex = 6;
            this.newMailButton.Text = "&New Mail";
            this.newMailButton.UseVisualStyleBackColor = true;
            this.newMailButton.Click += new System.EventHandler(this.newMailButton_Click);
            // 
            // mailConnectButton
            // 
            this.mailConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.mailConnectButton.Enabled = false;
            this.mailConnectButton.Location = new System.Drawing.Point(384, 3);
            this.mailConnectButton.Name = "mailConnectButton";
            this.mailConnectButton.Size = new System.Drawing.Size(75, 23);
            this.mailConnectButton.TabIndex = 5;
            this.mailConnectButton.Text = "&Connect";
            this.mailConnectButton.UseVisualStyleBackColor = true;
            this.mailConnectButton.Click += new System.EventHandler(this.mailConnectButton_Click);
            // 
            // mailMenuPictureBox
            // 
            this.mailMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.mailMenuPictureBox.ContextMenuStrip = this.stationsTabContextMenuStrip;
            this.mailMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("mailMenuPictureBox.Image")));
            this.mailMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.mailMenuPictureBox.Name = "mailMenuPictureBox";
            this.mailMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.mailMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.mailMenuPictureBox.TabIndex = 4;
            this.mailMenuPictureBox.TabStop = false;
            this.mailMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.mailMenuPictureBox_MouseClick);
            // 
            // stationsTabContextMenuStrip
            // 
            this.stationsTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.stationsTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.exportStationsToolStripMenuItem,
            this.importStationsToolStripMenuItem});
            this.stationsTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.stationsTabContextMenuStrip.Size = new System.Drawing.Size(165, 48);
            // 
            // exportStationsToolStripMenuItem
            // 
            this.exportStationsToolStripMenuItem.Name = "exportStationsToolStripMenuItem";
            this.exportStationsToolStripMenuItem.Size = new System.Drawing.Size(164, 22);
            this.exportStationsToolStripMenuItem.Text = "&Export Stations...";
            this.exportStationsToolStripMenuItem.Click += new System.EventHandler(this.exportStationsToolStripMenuItem_Click);
            // 
            // importStationsToolStripMenuItem
            // 
            this.importStationsToolStripMenuItem.Name = "importStationsToolStripMenuItem";
            this.importStationsToolStripMenuItem.Size = new System.Drawing.Size(164, 22);
            this.importStationsToolStripMenuItem.Text = "&Import Stations...";
            this.importStationsToolStripMenuItem.Click += new System.EventHandler(this.importStationsToolStripMenuItem_Click);
            // 
            // mailTitleLabel
            // 
            this.mailTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.mailTitleLabel.AutoSize = true;
            this.mailTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mailTitleLabel.Location = new System.Drawing.Point(3, 5);
            this.mailTitleLabel.Name = "mailTitleLabel";
            this.mailTitleLabel.Size = new System.Drawing.Size(37, 20);
            this.mailTitleLabel.TabIndex = 1;
            this.mailTitleLabel.Text = "Mail";
            // 
            // terminalTabPage
            // 
            this.terminalTabPage.Controls.Add(this.terminalTextBox);
            this.terminalTabPage.Controls.Add(this.terminalBottomPanel);
            this.terminalTabPage.Controls.Add(this.terminalTopPanel);
            this.terminalTabPage.ImageKey = "terminal-32.png";
            this.terminalTabPage.Location = new System.Drawing.Point(4, 4);
            this.terminalTabPage.Name = "terminalTabPage";
            this.terminalTabPage.Size = new System.Drawing.Size(490, 524);
            this.terminalTabPage.TabIndex = 2;
            this.terminalTabPage.UseVisualStyleBackColor = true;
            // 
            // terminalTextBox
            // 
            this.terminalTextBox.BackColor = System.Drawing.Color.Black;
            this.terminalTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.terminalTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.terminalTextBox.Font = new System.Drawing.Font("Courier New", 12F, System.Drawing.FontStyle.Bold);
            this.terminalTextBox.ForeColor = System.Drawing.Color.Gainsboro;
            this.terminalTextBox.Location = new System.Drawing.Point(0, 30);
            this.terminalTextBox.Name = "terminalTextBox";
            this.terminalTextBox.ReadOnly = true;
            this.terminalTextBox.Size = new System.Drawing.Size(490, 457);
            this.terminalTextBox.TabIndex = 4;
            this.terminalTextBox.Text = "";
            // 
            // terminalBottomPanel
            // 
            this.terminalBottomPanel.BackColor = System.Drawing.Color.Silver;
            this.terminalBottomPanel.Controls.Add(this.terminalInputTextBox);
            this.terminalBottomPanel.Controls.Add(this.terminalSendButton);
            this.terminalBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.terminalBottomPanel.Location = new System.Drawing.Point(0, 487);
            this.terminalBottomPanel.Name = "terminalBottomPanel";
            this.terminalBottomPanel.Size = new System.Drawing.Size(490, 37);
            this.terminalBottomPanel.TabIndex = 3;
            // 
            // terminalInputTextBox
            // 
            this.terminalInputTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalInputTextBox.Enabled = false;
            this.terminalInputTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.terminalInputTextBox.Location = new System.Drawing.Point(7, 6);
            this.terminalInputTextBox.Name = "terminalInputTextBox";
            this.terminalInputTextBox.Size = new System.Drawing.Size(399, 26);
            this.terminalInputTextBox.TabIndex = 1;
            this.terminalInputTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.terminalInputTextBox_KeyPress);
            // 
            // terminalSendButton
            // 
            this.terminalSendButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalSendButton.Enabled = false;
            this.terminalSendButton.Location = new System.Drawing.Point(412, 4);
            this.terminalSendButton.Name = "terminalSendButton";
            this.terminalSendButton.Size = new System.Drawing.Size(75, 28);
            this.terminalSendButton.TabIndex = 0;
            this.terminalSendButton.Text = "&Send";
            this.terminalSendButton.UseVisualStyleBackColor = true;
            this.terminalSendButton.Click += new System.EventHandler(this.terminalSendButton_Click);
            // 
            // terminalTopPanel
            // 
            this.terminalTopPanel.BackColor = System.Drawing.Color.Silver;
            this.terminalTopPanel.Controls.Add(this.terminalConnectButton);
            this.terminalTopPanel.Controls.Add(this.terminalMenuPictureBox);
            this.terminalTopPanel.Controls.Add(this.terminalTitleLabel);
            this.terminalTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.terminalTopPanel.Location = new System.Drawing.Point(0, 0);
            this.terminalTopPanel.Name = "terminalTopPanel";
            this.terminalTopPanel.Size = new System.Drawing.Size(490, 30);
            this.terminalTopPanel.TabIndex = 1;
            // 
            // terminalConnectButton
            // 
            this.terminalConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalConnectButton.Enabled = false;
            this.terminalConnectButton.Location = new System.Drawing.Point(384, 3);
            this.terminalConnectButton.Name = "terminalConnectButton";
            this.terminalConnectButton.Size = new System.Drawing.Size(75, 23);
            this.terminalConnectButton.TabIndex = 4;
            this.terminalConnectButton.Text = "&Connect";
            this.terminalConnectButton.UseVisualStyleBackColor = true;
            this.terminalConnectButton.Click += new System.EventHandler(this.terminalConnectButton_Click);
            // 
            // terminalMenuPictureBox
            // 
            this.terminalMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("terminalMenuPictureBox.Image")));
            this.terminalMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.terminalMenuPictureBox.Name = "terminalMenuPictureBox";
            this.terminalMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.terminalMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.terminalMenuPictureBox.TabIndex = 3;
            this.terminalMenuPictureBox.TabStop = false;
            this.terminalMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.terminalMenuPictureBox_MouseClick);
            // 
            // terminalTitleLabel
            // 
            this.terminalTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.terminalTitleLabel.AutoSize = true;
            this.terminalTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.terminalTitleLabel.Location = new System.Drawing.Point(3, 5);
            this.terminalTitleLabel.Name = "terminalTitleLabel";
            this.terminalTitleLabel.Size = new System.Drawing.Size(69, 20);
            this.terminalTitleLabel.TabIndex = 1;
            this.terminalTitleLabel.Text = "Terminal";
            // 
            // addressesTabPage
            // 
            this.addressesTabPage.Controls.Add(this.mainAddressBookListView);
            this.addressesTabPage.Controls.Add(this.panel1);
            this.addressesTabPage.ImageIndex = 4;
            this.addressesTabPage.Location = new System.Drawing.Point(4, 4);
            this.addressesTabPage.Name = "addressesTabPage";
            this.addressesTabPage.Size = new System.Drawing.Size(490, 524);
            this.addressesTabPage.TabIndex = 4;
            this.addressesTabPage.UseVisualStyleBackColor = true;
            // 
            // mainAddressBookListView
            // 
            this.mainAddressBookListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader1,
            this.columnHeader2,
            this.columnHeader3});
            this.mainAddressBookListView.ContextMenuStrip = this.stationsContextMenuStrip;
            this.mainAddressBookListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mainAddressBookListView.FullRowSelect = true;
            this.mainAddressBookListView.GridLines = true;
            listViewGroup4.Header = "Generic Stations";
            listViewGroup4.Name = "Generic Stations";
            listViewGroup5.Header = "APRS Stations";
            listViewGroup5.Name = "APRS Stations";
            listViewGroup6.Header = "Terminal Stations";
            listViewGroup6.Name = "Terminal Stations";
            listViewGroup7.Header = "BBS";
            listViewGroup7.Name = "BBS";
            listViewGroup8.Header = "Winlink Gateways";
            listViewGroup8.Name = "Winlink Gateways";
            this.mainAddressBookListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] {
            listViewGroup4,
            listViewGroup5,
            listViewGroup6,
            listViewGroup7,
            listViewGroup8});
            this.mainAddressBookListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            this.mainAddressBookListView.HideSelection = false;
            this.mainAddressBookListView.Location = new System.Drawing.Point(0, 30);
            this.mainAddressBookListView.Name = "mainAddressBookListView";
            this.mainAddressBookListView.Size = new System.Drawing.Size(490, 494);
            this.mainAddressBookListView.SmallImageList = this.mainImageList;
            this.mainAddressBookListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            this.mainAddressBookListView.TabIndex = 4;
            this.mainAddressBookListView.UseCompatibleStateImageBehavior = false;
            this.mainAddressBookListView.View = System.Windows.Forms.View.Details;
            this.mainAddressBookListView.SelectedIndexChanged += new System.EventHandler(this.mainAddressBookListView_SelectedIndexChanged);
            this.mainAddressBookListView.DoubleClick += new System.EventHandler(this.mainAddressBookListView_DoubleClick);
            // 
            // columnHeader1
            // 
            this.columnHeader1.Text = "Call Sign";
            this.columnHeader1.Width = 100;
            // 
            // columnHeader2
            // 
            this.columnHeader2.Text = "Name";
            this.columnHeader2.Width = 100;
            // 
            // columnHeader3
            // 
            this.columnHeader3.Text = "Description";
            this.columnHeader3.Width = 290;
            // 
            // stationsContextMenuStrip
            // 
            this.stationsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.stationsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.editToolStripMenuItem,
            this.removeToolStripMenuItem,
            this.setToolStripMenuItem});
            this.stationsContextMenuStrip.Name = "stationsContextMenuStrip";
            this.stationsContextMenuStrip.Size = new System.Drawing.Size(118, 70);
            // 
            // editToolStripMenuItem
            // 
            this.editToolStripMenuItem.Name = "editToolStripMenuItem";
            this.editToolStripMenuItem.Size = new System.Drawing.Size(117, 22);
            this.editToolStripMenuItem.Text = "&Edit...";
            this.editToolStripMenuItem.Visible = false;
            this.editToolStripMenuItem.Click += new System.EventHandler(this.mainAddressBookListView_DoubleClick);
            // 
            // removeToolStripMenuItem
            // 
            this.removeToolStripMenuItem.Name = "removeToolStripMenuItem";
            this.removeToolStripMenuItem.Size = new System.Drawing.Size(117, 22);
            this.removeToolStripMenuItem.Text = "&Remove";
            this.removeToolStripMenuItem.Click += new System.EventHandler(this.removeToolStripMenuItem_Click);
            // 
            // setToolStripMenuItem
            // 
            this.setToolStripMenuItem.Name = "setToolStripMenuItem";
            this.setToolStripMenuItem.Size = new System.Drawing.Size(117, 22);
            this.setToolStripMenuItem.Text = "&Set";
            this.setToolStripMenuItem.Click += new System.EventHandler(this.setToolStripMenuItem_Click);
            // 
            // panel1
            // 
            this.panel1.BackColor = System.Drawing.Color.Silver;
            this.panel1.Controls.Add(this.stationsMenuPictureBox);
            this.panel1.Controls.Add(this.addStationButton);
            this.panel1.Controls.Add(this.removeStationButton);
            this.panel1.Controls.Add(this.label1);
            this.panel1.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel1.Location = new System.Drawing.Point(0, 0);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(490, 30);
            this.panel1.TabIndex = 3;
            // 
            // stationsMenuPictureBox
            // 
            this.stationsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.stationsMenuPictureBox.ContextMenuStrip = this.stationsTabContextMenuStrip;
            this.stationsMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("stationsMenuPictureBox.Image")));
            this.stationsMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.stationsMenuPictureBox.Name = "stationsMenuPictureBox";
            this.stationsMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.stationsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.stationsMenuPictureBox.TabIndex = 3;
            this.stationsMenuPictureBox.TabStop = false;
            this.stationsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.stationsMenuPictureBox_MouseClick);
            // 
            // addStationButton
            // 
            this.addStationButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.addStationButton.Location = new System.Drawing.Point(303, 3);
            this.addStationButton.Name = "addStationButton";
            this.addStationButton.Size = new System.Drawing.Size(75, 23);
            this.addStationButton.TabIndex = 2;
            this.addStationButton.Text = "&Add";
            this.addStationButton.UseVisualStyleBackColor = true;
            this.addStationButton.Click += new System.EventHandler(this.addStationButton_Click);
            // 
            // removeStationButton
            // 
            this.removeStationButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.removeStationButton.Enabled = false;
            this.removeStationButton.Location = new System.Drawing.Point(384, 3);
            this.removeStationButton.Name = "removeStationButton";
            this.removeStationButton.Size = new System.Drawing.Size(75, 23);
            this.removeStationButton.TabIndex = 1;
            this.removeStationButton.Text = "&Remove";
            this.removeStationButton.UseVisualStyleBackColor = true;
            this.removeStationButton.Click += new System.EventHandler(this.removeStationButton_Click);
            // 
            // label1
            // 
            this.label1.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label1.AutoSize = true;
            this.label1.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label1.Location = new System.Drawing.Point(5, 5);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(109, 20);
            this.label1.TabIndex = 0;
            this.label1.Text = "Address Book";
            // 
            // bbsTabPage
            // 
            this.bbsTabPage.Controls.Add(this.bbsSplitContainer);
            this.bbsTabPage.Controls.Add(this.panel4);
            this.bbsTabPage.ImageIndex = 8;
            this.bbsTabPage.Location = new System.Drawing.Point(4, 4);
            this.bbsTabPage.Name = "bbsTabPage";
            this.bbsTabPage.Size = new System.Drawing.Size(490, 524);
            this.bbsTabPage.TabIndex = 7;
            this.bbsTabPage.UseVisualStyleBackColor = true;
            // 
            // bbsSplitContainer
            // 
            this.bbsSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.bbsSplitContainer.Location = new System.Drawing.Point(0, 30);
            this.bbsSplitContainer.Name = "bbsSplitContainer";
            this.bbsSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // bbsSplitContainer.Panel1
            // 
            this.bbsSplitContainer.Panel1.Controls.Add(this.bbsListView);
            // 
            // bbsSplitContainer.Panel2
            // 
            this.bbsSplitContainer.Panel2.Controls.Add(this.bbsTextBox);
            this.bbsSplitContainer.Size = new System.Drawing.Size(490, 494);
            this.bbsSplitContainer.SplitterDistance = 110;
            this.bbsSplitContainer.TabIndex = 7;
            // 
            // bbsListView
            // 
            this.bbsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader10,
            this.columnHeader11,
            this.columnHeader12});
            this.bbsListView.ContextMenuStrip = this.stationsContextMenuStrip;
            this.bbsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.bbsListView.FullRowSelect = true;
            this.bbsListView.GridLines = true;
            listViewGroup9.Header = "Generic Stations";
            listViewGroup9.Name = "Generic Stations";
            listViewGroup10.Header = "APRS Stations";
            listViewGroup10.Name = "APRS Stations";
            listViewGroup11.Header = "Terminal Stations";
            listViewGroup11.Name = "Terminal Stations";
            this.bbsListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] {
            listViewGroup9,
            listViewGroup10,
            listViewGroup11});
            this.bbsListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            this.bbsListView.HideSelection = false;
            this.bbsListView.Location = new System.Drawing.Point(0, 0);
            this.bbsListView.Name = "bbsListView";
            this.bbsListView.Size = new System.Drawing.Size(490, 110);
            this.bbsListView.SmallImageList = this.mainImageList;
            this.bbsListView.Sorting = System.Windows.Forms.SortOrder.Ascending;
            this.bbsListView.TabIndex = 6;
            this.bbsListView.UseCompatibleStateImageBehavior = false;
            this.bbsListView.View = System.Windows.Forms.View.Details;
            this.bbsListView.Resize += new System.EventHandler(this.bbsListView_Resize);
            // 
            // columnHeader10
            // 
            this.columnHeader10.Text = "Call Sign";
            this.columnHeader10.Width = 100;
            // 
            // columnHeader11
            // 
            this.columnHeader11.Text = "Last Seen";
            this.columnHeader11.Width = 133;
            // 
            // columnHeader12
            // 
            this.columnHeader12.Text = "Stats";
            this.columnHeader12.Width = 251;
            // 
            // bbsTextBox
            // 
            this.bbsTextBox.BackColor = System.Drawing.Color.Black;
            this.bbsTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.bbsTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.bbsTextBox.Font = new System.Drawing.Font("Courier New", 12F, System.Drawing.FontStyle.Bold);
            this.bbsTextBox.ForeColor = System.Drawing.Color.Gainsboro;
            this.bbsTextBox.Location = new System.Drawing.Point(0, 0);
            this.bbsTextBox.Name = "bbsTextBox";
            this.bbsTextBox.ReadOnly = true;
            this.bbsTextBox.Size = new System.Drawing.Size(490, 380);
            this.bbsTextBox.TabIndex = 5;
            this.bbsTextBox.Text = "";
            // 
            // panel4
            // 
            this.panel4.BackColor = System.Drawing.Color.Silver;
            this.panel4.Controls.Add(this.bbsMenuPictureBox);
            this.panel4.Controls.Add(this.bbsConnectButton);
            this.panel4.Controls.Add(this.label3);
            this.panel4.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel4.Location = new System.Drawing.Point(0, 0);
            this.panel4.Name = "panel4";
            this.panel4.Size = new System.Drawing.Size(490, 30);
            this.panel4.TabIndex = 5;
            // 
            // bbsMenuPictureBox
            // 
            this.bbsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.bbsMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("bbsMenuPictureBox.Image")));
            this.bbsMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.bbsMenuPictureBox.Name = "bbsMenuPictureBox";
            this.bbsMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.bbsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.bbsMenuPictureBox.TabIndex = 4;
            this.bbsMenuPictureBox.TabStop = false;
            this.bbsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.pictureBox1_MouseClick);
            // 
            // bbsConnectButton
            // 
            this.bbsConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.bbsConnectButton.Location = new System.Drawing.Point(384, 3);
            this.bbsConnectButton.Name = "bbsConnectButton";
            this.bbsConnectButton.Size = new System.Drawing.Size(75, 23);
            this.bbsConnectButton.TabIndex = 2;
            this.bbsConnectButton.Text = "&Activate";
            this.bbsConnectButton.UseVisualStyleBackColor = true;
            this.bbsConnectButton.Click += new System.EventHandler(this.bbsConnectButton_Click);
            // 
            // label3
            // 
            this.label3.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label3.AutoSize = true;
            this.label3.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label3.Location = new System.Drawing.Point(5, 5);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(42, 20);
            this.label3.TabIndex = 0;
            this.label3.Text = "BBS";
            // 
            // torrentTabPage
            // 
            this.torrentTabPage.Controls.Add(this.torrentSplitContainer);
            this.torrentTabPage.Controls.Add(this.panel5);
            this.torrentTabPage.ImageIndex = 7;
            this.torrentTabPage.Location = new System.Drawing.Point(4, 4);
            this.torrentTabPage.Margin = new System.Windows.Forms.Padding(2);
            this.torrentTabPage.Name = "torrentTabPage";
            this.torrentTabPage.Size = new System.Drawing.Size(490, 524);
            this.torrentTabPage.TabIndex = 8;
            this.torrentTabPage.UseVisualStyleBackColor = true;
            // 
            // torrentSplitContainer
            // 
            this.torrentSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentSplitContainer.Location = new System.Drawing.Point(0, 30);
            this.torrentSplitContainer.Margin = new System.Windows.Forms.Padding(2);
            this.torrentSplitContainer.Name = "torrentSplitContainer";
            this.torrentSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // torrentSplitContainer.Panel1
            // 
            this.torrentSplitContainer.Panel1.Controls.Add(this.torrentListView);
            // 
            // torrentSplitContainer.Panel2
            // 
            this.torrentSplitContainer.Panel2.Controls.Add(this.torrentTabControl);
            this.torrentSplitContainer.Size = new System.Drawing.Size(490, 494);
            this.torrentSplitContainer.SplitterDistance = 227;
            this.torrentSplitContainer.SplitterWidth = 3;
            this.torrentSplitContainer.TabIndex = 7;
            // 
            // torrentListView
            // 
            this.torrentListView.AllowDrop = true;
            this.torrentListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader14,
            this.columnHeader15,
            this.columnHeader16});
            this.torrentListView.ContextMenuStrip = this.torrentContextMenuStrip;
            this.torrentListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentListView.FullRowSelect = true;
            this.torrentListView.HideSelection = false;
            this.torrentListView.Location = new System.Drawing.Point(0, 0);
            this.torrentListView.Margin = new System.Windows.Forms.Padding(2);
            this.torrentListView.Name = "torrentListView";
            this.torrentListView.Size = new System.Drawing.Size(490, 227);
            this.torrentListView.SmallImageList = this.mainImageList;
            this.torrentListView.TabIndex = 0;
            this.torrentListView.UseCompatibleStateImageBehavior = false;
            this.torrentListView.View = System.Windows.Forms.View.Details;
            this.torrentListView.SelectedIndexChanged += new System.EventHandler(this.torrentListView_SelectedIndexChanged);
            this.torrentListView.DragDrop += new System.Windows.Forms.DragEventHandler(this.torrentListView_DragDrop);
            this.torrentListView.DragEnter += new System.Windows.Forms.DragEventHandler(this.torrentListView_DragEnter);
            this.torrentListView.KeyDown += new System.Windows.Forms.KeyEventHandler(this.torrentListView_KeyDown);
            this.torrentListView.Resize += new System.EventHandler(this.torrentListView_Resize);
            // 
            // columnHeader14
            // 
            this.columnHeader14.Text = "Filename";
            this.columnHeader14.Width = 173;
            // 
            // columnHeader15
            // 
            this.columnHeader15.Text = "Action";
            this.columnHeader15.Width = 70;
            // 
            // columnHeader16
            // 
            this.columnHeader16.Text = "Description";
            this.columnHeader16.Width = 377;
            // 
            // torrentContextMenuStrip
            // 
            this.torrentContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.torrentContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.torrentPauseToolStripMenuItem,
            this.torrentShareToolStripMenuItem,
            this.torrentRequestToolStripMenuItem,
            this.toolStripMenuItem19,
            this.torrentSaveAsToolStripMenuItem,
            this.toolStripMenuItem20,
            this.torrentDeleteToolStripMenuItem});
            this.torrentContextMenuStrip.Name = "mailContextMenuStrip";
            this.torrentContextMenuStrip.Size = new System.Drawing.Size(124, 126);
            this.torrentContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.torrentContextMenuStrip_Opening);
            // 
            // torrentPauseToolStripMenuItem
            // 
            this.torrentPauseToolStripMenuItem.Name = "torrentPauseToolStripMenuItem";
            this.torrentPauseToolStripMenuItem.Size = new System.Drawing.Size(123, 22);
            this.torrentPauseToolStripMenuItem.Text = "Pause";
            this.torrentPauseToolStripMenuItem.Click += new System.EventHandler(this.torrentPauseToolStripMenuItem_Click);
            // 
            // torrentShareToolStripMenuItem
            // 
            this.torrentShareToolStripMenuItem.Name = "torrentShareToolStripMenuItem";
            this.torrentShareToolStripMenuItem.Size = new System.Drawing.Size(123, 22);
            this.torrentShareToolStripMenuItem.Text = "Share";
            this.torrentShareToolStripMenuItem.Click += new System.EventHandler(this.torrentShareToolStripMenuItem_Click);
            // 
            // torrentRequestToolStripMenuItem
            // 
            this.torrentRequestToolStripMenuItem.Name = "torrentRequestToolStripMenuItem";
            this.torrentRequestToolStripMenuItem.Size = new System.Drawing.Size(123, 22);
            this.torrentRequestToolStripMenuItem.Text = "Request";
            this.torrentRequestToolStripMenuItem.Click += new System.EventHandler(this.torrentRequestToolStripMenuItem_Click);
            // 
            // toolStripMenuItem19
            // 
            this.toolStripMenuItem19.Name = "toolStripMenuItem19";
            this.toolStripMenuItem19.Size = new System.Drawing.Size(120, 6);
            // 
            // torrentSaveAsToolStripMenuItem
            // 
            this.torrentSaveAsToolStripMenuItem.Name = "torrentSaveAsToolStripMenuItem";
            this.torrentSaveAsToolStripMenuItem.Size = new System.Drawing.Size(123, 22);
            this.torrentSaveAsToolStripMenuItem.Text = "Save As...";
            this.torrentSaveAsToolStripMenuItem.Click += new System.EventHandler(this.torrentSaveAsToolStripMenuItem_Click);
            // 
            // toolStripMenuItem20
            // 
            this.toolStripMenuItem20.Name = "toolStripMenuItem20";
            this.toolStripMenuItem20.Size = new System.Drawing.Size(120, 6);
            // 
            // torrentDeleteToolStripMenuItem
            // 
            this.torrentDeleteToolStripMenuItem.Name = "torrentDeleteToolStripMenuItem";
            this.torrentDeleteToolStripMenuItem.Size = new System.Drawing.Size(123, 22);
            this.torrentDeleteToolStripMenuItem.Text = "&Delete";
            this.torrentDeleteToolStripMenuItem.Click += new System.EventHandler(this.torrentDeleteToolStripMenuItem_Click);
            // 
            // torrentTabControl
            // 
            this.torrentTabControl.Controls.Add(this.tabPage1);
            this.torrentTabControl.Controls.Add(this.tabPage2);
            this.torrentTabControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentTabControl.Location = new System.Drawing.Point(0, 0);
            this.torrentTabControl.Margin = new System.Windows.Forms.Padding(2);
            this.torrentTabControl.Name = "torrentTabControl";
            this.torrentTabControl.SelectedIndex = 0;
            this.torrentTabControl.Size = new System.Drawing.Size(490, 264);
            this.torrentTabControl.TabIndex = 0;
            // 
            // tabPage1
            // 
            this.tabPage1.Controls.Add(this.torrentDetailsListView);
            this.tabPage1.Location = new System.Drawing.Point(4, 22);
            this.tabPage1.Margin = new System.Windows.Forms.Padding(2);
            this.tabPage1.Name = "tabPage1";
            this.tabPage1.Padding = new System.Windows.Forms.Padding(2);
            this.tabPage1.Size = new System.Drawing.Size(482, 238);
            this.tabPage1.TabIndex = 0;
            this.tabPage1.Text = "Details";
            this.tabPage1.UseVisualStyleBackColor = true;
            // 
            // torrentDetailsListView
            // 
            this.torrentDetailsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader13,
            this.columnHeader17});
            this.torrentDetailsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentDetailsListView.FullRowSelect = true;
            this.torrentDetailsListView.HideSelection = false;
            this.torrentDetailsListView.Location = new System.Drawing.Point(2, 2);
            this.torrentDetailsListView.Margin = new System.Windows.Forms.Padding(2);
            this.torrentDetailsListView.Name = "torrentDetailsListView";
            this.torrentDetailsListView.Size = new System.Drawing.Size(478, 234);
            this.torrentDetailsListView.TabIndex = 0;
            this.torrentDetailsListView.UseCompatibleStateImageBehavior = false;
            this.torrentDetailsListView.View = System.Windows.Forms.View.Details;
            this.torrentDetailsListView.Resize += new System.EventHandler(this.torrentDetailsListView_Resize);
            // 
            // columnHeader13
            // 
            this.columnHeader13.Text = "Name";
            this.columnHeader13.Width = 122;
            // 
            // columnHeader17
            // 
            this.columnHeader17.Text = "Value";
            this.columnHeader17.Width = 469;
            // 
            // tabPage2
            // 
            this.tabPage2.Controls.Add(this.torrentBlocksUserControl);
            this.tabPage2.Location = new System.Drawing.Point(4, 22);
            this.tabPage2.Margin = new System.Windows.Forms.Padding(2);
            this.tabPage2.Name = "tabPage2";
            this.tabPage2.Padding = new System.Windows.Forms.Padding(2);
            this.tabPage2.Size = new System.Drawing.Size(482, 238);
            this.tabPage2.TabIndex = 1;
            this.tabPage2.Text = "Blocks";
            this.tabPage2.UseVisualStyleBackColor = true;
            // 
            // panel5
            // 
            this.panel5.BackColor = System.Drawing.Color.Silver;
            this.panel5.Controls.Add(this.torrentAddFileButton);
            this.panel5.Controls.Add(this.torrentMenuPictureBox);
            this.panel5.Controls.Add(this.torrentConnectButton);
            this.panel5.Controls.Add(this.label4);
            this.panel5.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel5.Location = new System.Drawing.Point(0, 0);
            this.panel5.Name = "panel5";
            this.panel5.Size = new System.Drawing.Size(490, 30);
            this.panel5.TabIndex = 6;
            // 
            // torrentAddFileButton
            // 
            this.torrentAddFileButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.torrentAddFileButton.Location = new System.Drawing.Point(304, 3);
            this.torrentAddFileButton.Name = "torrentAddFileButton";
            this.torrentAddFileButton.Size = new System.Drawing.Size(75, 23);
            this.torrentAddFileButton.TabIndex = 5;
            this.torrentAddFileButton.Text = "Add &File...";
            this.torrentAddFileButton.UseVisualStyleBackColor = true;
            this.torrentAddFileButton.Click += new System.EventHandler(this.torrentAddFileButton_Click);
            // 
            // torrentMenuPictureBox
            // 
            this.torrentMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.torrentMenuPictureBox.ContextMenuStrip = this.torrentTabContextMenuStrip;
            this.torrentMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("torrentMenuPictureBox.Image")));
            this.torrentMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.torrentMenuPictureBox.Name = "torrentMenuPictureBox";
            this.torrentMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.torrentMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.torrentMenuPictureBox.TabIndex = 4;
            this.torrentMenuPictureBox.TabStop = false;
            this.torrentMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.torrentMenuPictureBox_MouseClick);
            // 
            // torrentTabContextMenuStrip
            // 
            this.torrentTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.torrentTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showDetailsToolStripMenuItem});
            this.torrentTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.torrentTabContextMenuStrip.Size = new System.Drawing.Size(142, 26);
            this.torrentTabContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.torrentTabContextMenuStrip_Opening);
            // 
            // showDetailsToolStripMenuItem
            // 
            this.showDetailsToolStripMenuItem.CheckOnClick = true;
            this.showDetailsToolStripMenuItem.Name = "showDetailsToolStripMenuItem";
            this.showDetailsToolStripMenuItem.Size = new System.Drawing.Size(141, 22);
            this.showDetailsToolStripMenuItem.Text = "&Show Details";
            this.showDetailsToolStripMenuItem.Click += new System.EventHandler(this.showDetailsToolStripMenuItem_Click);
            // 
            // torrentConnectButton
            // 
            this.torrentConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.torrentConnectButton.Location = new System.Drawing.Point(384, 3);
            this.torrentConnectButton.Name = "torrentConnectButton";
            this.torrentConnectButton.Size = new System.Drawing.Size(75, 23);
            this.torrentConnectButton.TabIndex = 2;
            this.torrentConnectButton.Text = "&Activate";
            this.torrentConnectButton.UseVisualStyleBackColor = true;
            this.torrentConnectButton.Click += new System.EventHandler(this.torrentActivateButton_Click);
            // 
            // label4
            // 
            this.label4.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label4.AutoSize = true;
            this.label4.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label4.Location = new System.Drawing.Point(5, 5);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(60, 20);
            this.label4.TabIndex = 0;
            this.label4.Text = "Torrent";
            // 
            // packetsTabPage
            // 
            this.packetsTabPage.Controls.Add(this.packetsSplitContainer);
            this.packetsTabPage.Controls.Add(this.panel3);
            this.packetsTabPage.ImageIndex = 6;
            this.packetsTabPage.Location = new System.Drawing.Point(4, 4);
            this.packetsTabPage.Name = "packetsTabPage";
            this.packetsTabPage.Size = new System.Drawing.Size(490, 524);
            this.packetsTabPage.TabIndex = 6;
            this.packetsTabPage.UseVisualStyleBackColor = true;
            // 
            // packetsSplitContainer
            // 
            this.packetsSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetsSplitContainer.Location = new System.Drawing.Point(0, 30);
            this.packetsSplitContainer.Name = "packetsSplitContainer";
            this.packetsSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // packetsSplitContainer.Panel1
            // 
            this.packetsSplitContainer.Panel1.Controls.Add(this.packetsListView);
            // 
            // packetsSplitContainer.Panel2
            // 
            this.packetsSplitContainer.Panel2.Controls.Add(this.packetDecodeListView);
            this.packetsSplitContainer.Size = new System.Drawing.Size(490, 494);
            this.packetsSplitContainer.SplitterDistance = 222;
            this.packetsSplitContainer.TabIndex = 6;
            // 
            // packetsListView
            // 
            this.packetsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader7,
            this.columnHeader8,
            this.columnHeader9});
            this.packetsListView.ContextMenuStrip = this.packetsListContextMenuStrip;
            this.packetsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetsListView.FullRowSelect = true;
            this.packetsListView.GridLines = true;
            this.packetsListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.Nonclickable;
            this.packetsListView.HideSelection = false;
            this.packetsListView.Location = new System.Drawing.Point(0, 0);
            this.packetsListView.Name = "packetsListView";
            this.packetsListView.Size = new System.Drawing.Size(490, 222);
            this.packetsListView.SmallImageList = this.mainImageList;
            this.packetsListView.TabIndex = 5;
            this.packetsListView.UseCompatibleStateImageBehavior = false;
            this.packetsListView.View = System.Windows.Forms.View.Details;
            this.packetsListView.SelectedIndexChanged += new System.EventHandler(this.packetsListView_SelectedIndexChanged);
            this.packetsListView.Resize += new System.EventHandler(this.packetsListView_Resize);
            // 
            // columnHeader7
            // 
            this.columnHeader7.Text = "Time";
            this.columnHeader7.Width = 90;
            // 
            // columnHeader8
            // 
            this.columnHeader8.Text = "Channel";
            this.columnHeader8.Width = 70;
            // 
            // columnHeader9
            // 
            this.columnHeader9.Text = "Data";
            this.columnHeader9.Width = 326;
            // 
            // packetsListContextMenuStrip
            // 
            this.packetsListContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.packetsListContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.copyHEXValuesToolStripMenuItem,
            this.saveToFileToolStripMenuItem});
            this.packetsListContextMenuStrip.Name = "packetsListContextMenuStrip";
            this.packetsListContextMenuStrip.Size = new System.Drawing.Size(164, 48);
            this.packetsListContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.packetsListContextMenuStrip_Opening);
            // 
            // copyHEXValuesToolStripMenuItem
            // 
            this.copyHEXValuesToolStripMenuItem.Name = "copyHEXValuesToolStripMenuItem";
            this.copyHEXValuesToolStripMenuItem.Size = new System.Drawing.Size(163, 22);
            this.copyHEXValuesToolStripMenuItem.Text = "Copy &HEX Values";
            this.copyHEXValuesToolStripMenuItem.Click += new System.EventHandler(this.copyHEXValuesToolStripMenuItem_Click);
            // 
            // saveToFileToolStripMenuItem
            // 
            this.saveToFileToolStripMenuItem.Name = "saveToFileToolStripMenuItem";
            this.saveToFileToolStripMenuItem.Size = new System.Drawing.Size(163, 22);
            this.saveToFileToolStripMenuItem.Text = "Save to &File..";
            this.saveToFileToolStripMenuItem.Click += new System.EventHandler(this.saveToFileToolStripMenuItem_Click_1);
            // 
            // packetDecodeListView
            // 
            this.packetDecodeListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.packetDecodeColumnHeader1,
            this.packetDecodeColumnHeader2});
            this.packetDecodeListView.ContextMenuStrip = this.packetDataContextMenuStrip;
            this.packetDecodeListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.packetDecodeListView.FullRowSelect = true;
            this.packetDecodeListView.GridLines = true;
            listViewGroup12.Header = "Metadata";
            listViewGroup12.Name = "packetDecodeMetadataListViewGroup";
            listViewGroup13.Header = "AX.25 Header";
            listViewGroup13.Name = "packetDecodeHeaderListViewGroup";
            listViewGroup14.Header = "AX.25 Data";
            listViewGroup14.Name = "packetDecodeDataListViewGroup";
            listViewGroup15.Header = "APRS";
            listViewGroup15.Name = "packetDecodeAprsListViewGroup";
            listViewGroup16.Header = "Position";
            listViewGroup16.Name = "packetDecodePositionListViewGroup";
            listViewGroup20.Header = "Decompression";
            listViewGroup20.Name = "packetDecodeDecompressionListViewGroup";
            this.packetDecodeListView.Groups.AddRange(new System.Windows.Forms.ListViewGroup[] {
            listViewGroup12,
            listViewGroup13,
            listViewGroup14,
            listViewGroup15,
            listViewGroup16,
            listViewGroup20});
            this.packetDecodeListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            this.packetDecodeListView.HideSelection = false;
            this.packetDecodeListView.Location = new System.Drawing.Point(0, 0);
            this.packetDecodeListView.Name = "packetDecodeListView";
            this.packetDecodeListView.Size = new System.Drawing.Size(490, 268);
            this.packetDecodeListView.TabIndex = 1;
            this.packetDecodeListView.UseCompatibleStateImageBehavior = false;
            this.packetDecodeListView.View = System.Windows.Forms.View.Details;
            this.packetDecodeListView.Resize += new System.EventHandler(this.packetDecodeListView_Resize);
            // 
            // packetDecodeColumnHeader1
            // 
            this.packetDecodeColumnHeader1.Width = 100;
            // 
            // packetDecodeColumnHeader2
            // 
            this.packetDecodeColumnHeader2.Width = 300;
            // 
            // packetDataContextMenuStrip
            // 
            this.packetDataContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.packetDataContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.copyToClipboardToolStripMenuItem});
            this.packetDataContextMenuStrip.Name = "packetDataContextMenuStrip";
            this.packetDataContextMenuStrip.Size = new System.Drawing.Size(172, 26);
            this.packetDataContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.packetDataContextMenuStrip_Opening);
            // 
            // copyToClipboardToolStripMenuItem
            // 
            this.copyToClipboardToolStripMenuItem.Name = "copyToClipboardToolStripMenuItem";
            this.copyToClipboardToolStripMenuItem.Size = new System.Drawing.Size(171, 22);
            this.copyToClipboardToolStripMenuItem.Text = "Copy to Clipboard";
            this.copyToClipboardToolStripMenuItem.Click += new System.EventHandler(this.copyToClipboardToolStripMenuItem_Click);
            // 
            // panel3
            // 
            this.panel3.BackColor = System.Drawing.Color.Silver;
            this.panel3.Controls.Add(this.packetsMenuPictureBox);
            this.panel3.Controls.Add(this.label5);
            this.panel3.Dock = System.Windows.Forms.DockStyle.Top;
            this.panel3.Location = new System.Drawing.Point(0, 0);
            this.panel3.Name = "panel3";
            this.panel3.Size = new System.Drawing.Size(490, 30);
            this.panel3.TabIndex = 3;
            // 
            // packetsMenuPictureBox
            // 
            this.packetsMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.packetsMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("packetsMenuPictureBox.Image")));
            this.packetsMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.packetsMenuPictureBox.Name = "packetsMenuPictureBox";
            this.packetsMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.packetsMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.packetsMenuPictureBox.TabIndex = 2;
            this.packetsMenuPictureBox.TabStop = false;
            this.packetsMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.packetsMenuPictureBox_MouseClick);
            // 
            // label5
            // 
            this.label5.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label5.AutoSize = true;
            this.label5.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label5.Location = new System.Drawing.Point(5, 5);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(119, 20);
            this.label5.TabIndex = 0;
            this.label5.Text = "Packet Capture";
            // 
            // debugTabPage
            // 
            this.debugTabPage.Controls.Add(this.debugTextBox);
            this.debugTabPage.Controls.Add(this.debugControlsPanel);
            this.debugTabPage.ImageIndex = 0;
            this.debugTabPage.Location = new System.Drawing.Point(4, 4);
            this.debugTabPage.Name = "debugTabPage";
            this.debugTabPage.Size = new System.Drawing.Size(490, 524);
            this.debugTabPage.TabIndex = 1;
            this.debugTabPage.ToolTipText = "Debug";
            this.debugTabPage.UseVisualStyleBackColor = true;
            // 
            // debugTextBox
            // 
            this.debugTextBox.BackColor = System.Drawing.Color.LightGray;
            this.debugTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.debugTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.debugTextBox.Location = new System.Drawing.Point(0, 30);
            this.debugTextBox.Margin = new System.Windows.Forms.Padding(0);
            this.debugTextBox.Multiline = true;
            this.debugTextBox.Name = "debugTextBox";
            this.debugTextBox.ReadOnly = true;
            this.debugTextBox.ScrollBars = System.Windows.Forms.ScrollBars.Both;
            this.debugTextBox.Size = new System.Drawing.Size(490, 494);
            this.debugTextBox.TabIndex = 1;
            this.debugTextBox.WordWrap = false;
            // 
            // debugControlsPanel
            // 
            this.debugControlsPanel.BackColor = System.Drawing.Color.Silver;
            this.debugControlsPanel.Controls.Add(this.debugMenuPictureBox);
            this.debugControlsPanel.Controls.Add(this.label2);
            this.debugControlsPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.debugControlsPanel.Location = new System.Drawing.Point(0, 0);
            this.debugControlsPanel.Name = "debugControlsPanel";
            this.debugControlsPanel.Size = new System.Drawing.Size(490, 30);
            this.debugControlsPanel.TabIndex = 0;
            // 
            // debugMenuPictureBox
            // 
            this.debugMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.debugMenuPictureBox.Image = ((System.Drawing.Image)(resources.GetObject("debugMenuPictureBox.Image")));
            this.debugMenuPictureBox.Location = new System.Drawing.Point(466, 5);
            this.debugMenuPictureBox.Name = "debugMenuPictureBox";
            this.debugMenuPictureBox.Size = new System.Drawing.Size(20, 20);
            this.debugMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.debugMenuPictureBox.TabIndex = 3;
            this.debugMenuPictureBox.TabStop = false;
            this.debugMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.debugMenuPictureBox_MouseClick);
            // 
            // label2
            // 
            this.label2.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label2.AutoSize = true;
            this.label2.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label2.Location = new System.Drawing.Point(3, 5);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(133, 20);
            this.label2.TabIndex = 1;
            this.label2.Text = "Developer Debug";
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
            // aprsContextMenuStrip
            // 
            this.aprsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.aprsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showAllMessagesToolStripMenuItem,
            this.toolStripMenuItem7,
            this.beaconSettingsToolStripMenuItem,
            this.smSMessageToolStripMenuItem,
            this.weatherReportToolStripMenuItem});
            this.aprsContextMenuStrip.Name = "aprsContextMenuStrip";
            this.aprsContextMenuStrip.Size = new System.Drawing.Size(168, 98);
            // 
            // showAllMessagesToolStripMenuItem
            // 
            this.showAllMessagesToolStripMenuItem.CheckOnClick = true;
            this.showAllMessagesToolStripMenuItem.Name = "showAllMessagesToolStripMenuItem";
            this.showAllMessagesToolStripMenuItem.Size = new System.Drawing.Size(167, 22);
            this.showAllMessagesToolStripMenuItem.Text = "Show &Telemetry";
            this.showAllMessagesToolStripMenuItem.CheckStateChanged += new System.EventHandler(this.showAllMessagesToolStripMenuItem_CheckStateChanged);
            // 
            // toolStripMenuItem7
            // 
            this.toolStripMenuItem7.Name = "toolStripMenuItem7";
            this.toolStripMenuItem7.Size = new System.Drawing.Size(164, 6);
            // 
            // beaconSettingsToolStripMenuItem
            // 
            this.beaconSettingsToolStripMenuItem.Name = "beaconSettingsToolStripMenuItem";
            this.beaconSettingsToolStripMenuItem.Size = new System.Drawing.Size(167, 22);
            this.beaconSettingsToolStripMenuItem.Text = "&Beacon Settings...";
            this.beaconSettingsToolStripMenuItem.Click += new System.EventHandler(this.beaconSettingsToolStripMenuItem_Click);
            // 
            // smSMessageToolStripMenuItem
            // 
            this.smSMessageToolStripMenuItem.Name = "smSMessageToolStripMenuItem";
            this.smSMessageToolStripMenuItem.Size = new System.Drawing.Size(167, 22);
            this.smSMessageToolStripMenuItem.Text = "&SMS Message...";
            this.smSMessageToolStripMenuItem.Click += new System.EventHandler(this.aprsSmsButton_Click);
            // 
            // weatherReportToolStripMenuItem
            // 
            this.weatherReportToolStripMenuItem.Name = "weatherReportToolStripMenuItem";
            this.weatherReportToolStripMenuItem.Size = new System.Drawing.Size(167, 22);
            this.weatherReportToolStripMenuItem.Text = "&Weather Report...";
            this.weatherReportToolStripMenuItem.Click += new System.EventHandler(this.weatherReportToolStripMenuItem_Click);
            // 
            // terminalTabContextMenuStrip
            // 
            this.terminalTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.terminalTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showCallsignToolStripMenuItem,
            this.waitForConnectionToolStripMenuItem,
            this.toolStripMenuItem9,
            this.toolStripMenuItem13});
            this.terminalTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.terminalTabContextMenuStrip.Size = new System.Drawing.Size(182, 76);
            // 
            // showCallsignToolStripMenuItem
            // 
            this.showCallsignToolStripMenuItem.CheckOnClick = true;
            this.showCallsignToolStripMenuItem.Name = "showCallsignToolStripMenuItem";
            this.showCallsignToolStripMenuItem.Size = new System.Drawing.Size(181, 22);
            this.showCallsignToolStripMenuItem.Text = "&Show Callsign";
            this.showCallsignToolStripMenuItem.Click += new System.EventHandler(this.showCallsignToolStripMenuItem_Click);
            // 
            // waitForConnectionToolStripMenuItem
            // 
            this.waitForConnectionToolStripMenuItem.Name = "waitForConnectionToolStripMenuItem";
            this.waitForConnectionToolStripMenuItem.Size = new System.Drawing.Size(181, 22);
            this.waitForConnectionToolStripMenuItem.Text = "&Wait for Connection";
            this.waitForConnectionToolStripMenuItem.Click += new System.EventHandler(this.waitForConnectionToolStripMenuItem_Click);
            // 
            // toolStripMenuItem9
            // 
            this.toolStripMenuItem9.Name = "toolStripMenuItem9";
            this.toolStripMenuItem9.Size = new System.Drawing.Size(178, 6);
            // 
            // toolStripMenuItem13
            // 
            this.toolStripMenuItem13.Name = "toolStripMenuItem13";
            this.toolStripMenuItem13.Size = new System.Drawing.Size(181, 22);
            this.toolStripMenuItem13.Text = "&Clear";
            this.toolStripMenuItem13.Click += new System.EventHandler(this.toolStripMenuItem13_Click);
            // 
            // debugTabContextMenuStrip
            // 
            this.debugTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.debugTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.debugSaveToFileToolStripMenuItem,
            this.showBluetoothFramesToolStripMenuItem,
            this.loopbackModeToolStripMenuItem,
            this.toolStripMenuItem3,
            this.queryDeviceNamesToolStripMenuItem,
            this.toolStripMenuItem8,
            this.clearToolStripMenuItem});
            this.debugTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.debugTabContextMenuStrip.Size = new System.Drawing.Size(200, 126);
            // 
            // debugSaveToFileToolStripMenuItem
            // 
            this.debugSaveToFileToolStripMenuItem.Name = "debugSaveToFileToolStripMenuItem";
            this.debugSaveToFileToolStripMenuItem.Size = new System.Drawing.Size(199, 22);
            this.debugSaveToFileToolStripMenuItem.Text = "&Save To File...";
            this.debugSaveToFileToolStripMenuItem.Click += new System.EventHandler(this.saveToFileToolStripMenuItem_Click);
            // 
            // showBluetoothFramesToolStripMenuItem
            // 
            this.showBluetoothFramesToolStripMenuItem.CheckOnClick = true;
            this.showBluetoothFramesToolStripMenuItem.Name = "showBluetoothFramesToolStripMenuItem";
            this.showBluetoothFramesToolStripMenuItem.Size = new System.Drawing.Size(199, 22);
            this.showBluetoothFramesToolStripMenuItem.Text = "Show Bluetooth Frames";
            this.showBluetoothFramesToolStripMenuItem.CheckStateChanged += new System.EventHandler(this.showBluetoothFramesToolStripMenuItem_CheckStateChanged);
            // 
            // loopbackModeToolStripMenuItem
            // 
            this.loopbackModeToolStripMenuItem.CheckOnClick = true;
            this.loopbackModeToolStripMenuItem.Name = "loopbackModeToolStripMenuItem";
            this.loopbackModeToolStripMenuItem.Size = new System.Drawing.Size(199, 22);
            this.loopbackModeToolStripMenuItem.Text = "&Loopback Mode";
            this.loopbackModeToolStripMenuItem.Click += new System.EventHandler(this.loopbackModeToolStripMenuItem_Click);
            // 
            // toolStripMenuItem3
            // 
            this.toolStripMenuItem3.Name = "toolStripMenuItem3";
            this.toolStripMenuItem3.Size = new System.Drawing.Size(196, 6);
            // 
            // queryDeviceNamesToolStripMenuItem
            // 
            this.queryDeviceNamesToolStripMenuItem.Name = "queryDeviceNamesToolStripMenuItem";
            this.queryDeviceNamesToolStripMenuItem.Size = new System.Drawing.Size(199, 22);
            this.queryDeviceNamesToolStripMenuItem.Text = "Query Device Names";
            this.queryDeviceNamesToolStripMenuItem.Click += new System.EventHandler(this.queryDeviceNamesToolStripMenuItem_Click);
            // 
            // toolStripMenuItem8
            // 
            this.toolStripMenuItem8.Name = "toolStripMenuItem8";
            this.toolStripMenuItem8.Size = new System.Drawing.Size(196, 6);
            // 
            // clearToolStripMenuItem
            // 
            this.clearToolStripMenuItem.Name = "clearToolStripMenuItem";
            this.clearToolStripMenuItem.Size = new System.Drawing.Size(199, 22);
            this.clearToolStripMenuItem.Text = "&Clear";
            this.clearToolStripMenuItem.Click += new System.EventHandler(this.clearToolStripMenuItem_Click);
            // 
            // batteryTimer
            // 
            this.batteryTimer.Interval = 60000;
            this.batteryTimer.Tick += new System.EventHandler(this.batteryTimer_Tick);
            // 
            // saveTraceFileDialog
            // 
            this.saveTraceFileDialog.Filter = "Text files|*.txt";
            this.saveTraceFileDialog.Title = "Save Tracing File";
            // 
            // aprsMsgContextMenuStrip
            // 
            this.aprsMsgContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.aprsMsgContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.detailsToolStripMenuItem,
            this.showLocationToolStripMenuItem,
            this.copyMessageToolStripMenuItem,
            this.copyCallsignToolStripMenuItem});
            this.aprsMsgContextMenuStrip.Name = "aprsMsgContextMenuStrip";
            this.aprsMsgContextMenuStrip.Size = new System.Drawing.Size(162, 92);
            this.aprsMsgContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.aprsMsgContextMenuStrip_Opening);
            // 
            // detailsToolStripMenuItem
            // 
            this.detailsToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.detailsToolStripMenuItem.Name = "detailsToolStripMenuItem";
            this.detailsToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.detailsToolStripMenuItem.Text = "&Details...";
            this.detailsToolStripMenuItem.Click += new System.EventHandler(this.detailsToolStripMenuItem_Click);
            // 
            // showLocationToolStripMenuItem
            // 
            this.showLocationToolStripMenuItem.Name = "showLocationToolStripMenuItem";
            this.showLocationToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.showLocationToolStripMenuItem.Text = "Show Location...";
            this.showLocationToolStripMenuItem.Click += new System.EventHandler(this.showLocationToolStripMenuItem_Click);
            // 
            // copyMessageToolStripMenuItem
            // 
            this.copyMessageToolStripMenuItem.Name = "copyMessageToolStripMenuItem";
            this.copyMessageToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.copyMessageToolStripMenuItem.Text = "Copy Message";
            this.copyMessageToolStripMenuItem.Click += new System.EventHandler(this.copyMessageToolStripMenuItem_Click);
            // 
            // copyCallsignToolStripMenuItem
            // 
            this.copyCallsignToolStripMenuItem.Name = "copyCallsignToolStripMenuItem";
            this.copyCallsignToolStripMenuItem.Size = new System.Drawing.Size(161, 22);
            this.copyCallsignToolStripMenuItem.Text = "Copy Callsign";
            this.copyCallsignToolStripMenuItem.Click += new System.EventHandler(this.copyCallsignToolStripMenuItem_Click);
            // 
            // packetsContextMenuStrip
            // 
            this.packetsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.packetsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showPacketDecodeToolStripMenuItem,
            this.toolStripMenuItem18,
            this.saveToFileToolStripMenuItem1,
            this.openFileToolStripMenuItem,
            this.toolStripMenuItem17,
            this.clearPacketsToolStripMenuItem});
            this.packetsContextMenuStrip.Name = "packetsContextMenuStrip";
            this.packetsContextMenuStrip.Size = new System.Drawing.Size(185, 104);
            this.packetsContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.packetsContextMenuStrip_Opening);
            // 
            // showPacketDecodeToolStripMenuItem
            // 
            this.showPacketDecodeToolStripMenuItem.CheckOnClick = true;
            this.showPacketDecodeToolStripMenuItem.Name = "showPacketDecodeToolStripMenuItem";
            this.showPacketDecodeToolStripMenuItem.Size = new System.Drawing.Size(184, 22);
            this.showPacketDecodeToolStripMenuItem.Text = "&Show Packet Decode";
            this.showPacketDecodeToolStripMenuItem.CheckStateChanged += new System.EventHandler(this.showPacketDecodeToolStripMenuItem_CheckStateChanged);
            // 
            // toolStripMenuItem18
            // 
            this.toolStripMenuItem18.Name = "toolStripMenuItem18";
            this.toolStripMenuItem18.Size = new System.Drawing.Size(181, 6);
            // 
            // saveToFileToolStripMenuItem1
            // 
            this.saveToFileToolStripMenuItem1.Name = "saveToFileToolStripMenuItem1";
            this.saveToFileToolStripMenuItem1.Size = new System.Drawing.Size(184, 22);
            this.saveToFileToolStripMenuItem1.Text = "Save to &File...";
            this.saveToFileToolStripMenuItem1.Click += new System.EventHandler(this.saveToFileToolStripMenuItem1_Click);
            // 
            // openFileToolStripMenuItem
            // 
            this.openFileToolStripMenuItem.Name = "openFileToolStripMenuItem";
            this.openFileToolStripMenuItem.Size = new System.Drawing.Size(184, 22);
            this.openFileToolStripMenuItem.Text = "Open File...";
            this.openFileToolStripMenuItem.Click += new System.EventHandler(this.openFileToolStripMenuItem_Click);
            // 
            // toolStripMenuItem17
            // 
            this.toolStripMenuItem17.Name = "toolStripMenuItem17";
            this.toolStripMenuItem17.Size = new System.Drawing.Size(181, 6);
            // 
            // clearPacketsToolStripMenuItem
            // 
            this.clearPacketsToolStripMenuItem.Name = "clearPacketsToolStripMenuItem";
            this.clearPacketsToolStripMenuItem.Size = new System.Drawing.Size(184, 22);
            this.clearPacketsToolStripMenuItem.Text = "&Clear Packets";
            this.clearPacketsToolStripMenuItem.Click += new System.EventHandler(this.clearPacketsToolStripMenuItem_Click);
            // 
            // savePacketsFileDialog
            // 
            this.savePacketsFileDialog.DefaultExt = "ptcap";
            this.savePacketsFileDialog.Filter = "Packet Capture|*.ptcap|All files|*.*";
            this.savePacketsFileDialog.Title = "Save Packet Capture";
            // 
            // openPacketsFileDialog
            // 
            this.openPacketsFileDialog.FileName = "packets.ptcap";
            this.openPacketsFileDialog.Filter = "Packet Capture|*.ptcap|All files|*.*";
            this.openPacketsFileDialog.Title = "Open Packet Capture FIle";
            // 
            // saveStationsFileDialog
            // 
            this.saveStationsFileDialog.DefaultExt = "json";
            this.saveStationsFileDialog.Filter = "JSON Files|*.json";
            this.saveStationsFileDialog.Title = "Export Stations";
            // 
            // openStationsFileDialog
            // 
            this.openStationsFileDialog.Filter = "JSON files|*.json";
            this.openStationsFileDialog.Title = "Import Stations";
            // 
            // exportChannelsFileDialog
            // 
            this.exportChannelsFileDialog.DefaultExt = "csv";
            this.exportChannelsFileDialog.FileName = "channels.csv";
            this.exportChannelsFileDialog.Filter = "Channels (*.csv)|*.csv|CHIRP (*.csv)|*.csv";
            this.exportChannelsFileDialog.Title = "Export Channels";
            // 
            // importChannelFileDialog
            // 
            this.importChannelFileDialog.Filter = "Channels (*.csv)|*.csv|CHIRP (*.csv)|*.csv";
            this.importChannelFileDialog.Title = "Import Channels";
            // 
            // bbsTabContextMenuStrip
            // 
            this.bbsTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.bbsTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.viewTrafficToolStripMenuItem,
            this.toolStripMenuItem11,
            this.clearStatsToolStripMenuItem});
            this.bbsTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.bbsTabContextMenuStrip.Size = new System.Drawing.Size(136, 54);
            // 
            // viewTrafficToolStripMenuItem
            // 
            this.viewTrafficToolStripMenuItem.Checked = true;
            this.viewTrafficToolStripMenuItem.CheckOnClick = true;
            this.viewTrafficToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.viewTrafficToolStripMenuItem.Name = "viewTrafficToolStripMenuItem";
            this.viewTrafficToolStripMenuItem.Size = new System.Drawing.Size(135, 22);
            this.viewTrafficToolStripMenuItem.Text = "&View Traffic";
            this.viewTrafficToolStripMenuItem.Click += new System.EventHandler(this.viewTrafficToolStripMenuItem_Click);
            // 
            // toolStripMenuItem11
            // 
            this.toolStripMenuItem11.Name = "toolStripMenuItem11";
            this.toolStripMenuItem11.Size = new System.Drawing.Size(132, 6);
            // 
            // clearStatsToolStripMenuItem
            // 
            this.clearStatsToolStripMenuItem.Name = "clearStatsToolStripMenuItem";
            this.clearStatsToolStripMenuItem.Size = new System.Drawing.Size(135, 22);
            this.clearStatsToolStripMenuItem.Text = "&Clear Stats";
            this.clearStatsToolStripMenuItem.Click += new System.EventHandler(this.clearStatsToolStripMenuItem_Click);
            // 
            // notifyIcon
            // 
            this.notifyIcon.ContextMenuStrip = this.notifyContextMenuStrip;
            this.notifyIcon.Icon = ((System.Drawing.Icon)(resources.GetObject("notifyIcon.Icon")));
            this.notifyIcon.Text = "HT Commander";
            this.notifyIcon.BalloonTipClicked += new System.EventHandler(this.notifyIcon_BalloonTipClicked);
            this.notifyIcon.MouseClick += new System.Windows.Forms.MouseEventHandler(this.notifyIcon_MouseClick);
            // 
            // notifyContextMenuStrip
            // 
            this.notifyContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.notifyContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showToolStripMenuItem,
            this.hideToolStripMenuItem,
            this.toolStripMenuItem12,
            this.exitToolStripMenuItem1});
            this.notifyContextMenuStrip.Name = "notifyContextMenuStrip";
            this.notifyContextMenuStrip.Size = new System.Drawing.Size(104, 76);
            this.notifyContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.notifyContextMenuStrip_Opening);
            // 
            // showToolStripMenuItem
            // 
            this.showToolStripMenuItem.Name = "showToolStripMenuItem";
            this.showToolStripMenuItem.Size = new System.Drawing.Size(103, 22);
            this.showToolStripMenuItem.Text = "&Show";
            this.showToolStripMenuItem.Click += new System.EventHandler(this.showToolStripMenuItem_Click);
            // 
            // hideToolStripMenuItem
            // 
            this.hideToolStripMenuItem.Name = "hideToolStripMenuItem";
            this.hideToolStripMenuItem.Size = new System.Drawing.Size(103, 22);
            this.hideToolStripMenuItem.Text = "&Hide";
            this.hideToolStripMenuItem.Click += new System.EventHandler(this.hideToolStripMenuItem_Click);
            // 
            // toolStripMenuItem12
            // 
            this.toolStripMenuItem12.Name = "toolStripMenuItem12";
            this.toolStripMenuItem12.Size = new System.Drawing.Size(100, 6);
            // 
            // exitToolStripMenuItem1
            // 
            this.exitToolStripMenuItem1.Name = "exitToolStripMenuItem1";
            this.exitToolStripMenuItem1.Size = new System.Drawing.Size(103, 22);
            this.exitToolStripMenuItem1.Text = "&Exit";
            this.exitToolStripMenuItem1.Click += new System.EventHandler(this.exitToolStripMenuItem1_Click);
            // 
            // mailTabContextMenuStrip
            // 
            this.mailTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mailTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showPreviewToolStripMenuItem,
            this.showTrafficToolStripMenuItem,
            this.toolStripMenuItem16,
            this.backupMailToolStripMenuItem,
            this.restoreMailToolStripMenuItem});
            this.mailTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.mailTabContextMenuStrip.Size = new System.Drawing.Size(149, 98);
            // 
            // showPreviewToolStripMenuItem
            // 
            this.showPreviewToolStripMenuItem.CheckOnClick = true;
            this.showPreviewToolStripMenuItem.Name = "showPreviewToolStripMenuItem";
            this.showPreviewToolStripMenuItem.Size = new System.Drawing.Size(148, 22);
            this.showPreviewToolStripMenuItem.Text = "&Show Preview";
            this.showPreviewToolStripMenuItem.Click += new System.EventHandler(this.showPreviewToolStripMenuItem_Click);
            // 
            // showTrafficToolStripMenuItem
            // 
            this.showTrafficToolStripMenuItem.Name = "showTrafficToolStripMenuItem";
            this.showTrafficToolStripMenuItem.Size = new System.Drawing.Size(148, 22);
            this.showTrafficToolStripMenuItem.Text = "Show Traffic...";
            this.showTrafficToolStripMenuItem.Click += new System.EventHandler(this.showTrafficToolStripMenuItem_Click);
            // 
            // toolStripMenuItem16
            // 
            this.toolStripMenuItem16.Name = "toolStripMenuItem16";
            this.toolStripMenuItem16.Size = new System.Drawing.Size(145, 6);
            // 
            // backupMailToolStripMenuItem
            // 
            this.backupMailToolStripMenuItem.Name = "backupMailToolStripMenuItem";
            this.backupMailToolStripMenuItem.Size = new System.Drawing.Size(148, 22);
            this.backupMailToolStripMenuItem.Text = "&Backup Mail...";
            this.backupMailToolStripMenuItem.Click += new System.EventHandler(this.backupMailToolStripMenuItem_Click);
            // 
            // restoreMailToolStripMenuItem
            // 
            this.restoreMailToolStripMenuItem.Name = "restoreMailToolStripMenuItem";
            this.restoreMailToolStripMenuItem.Size = new System.Drawing.Size(148, 22);
            this.restoreMailToolStripMenuItem.Text = "&Restore Mail...";
            this.restoreMailToolStripMenuItem.Click += new System.EventHandler(this.restoreMailToolStripMenuItem_Click);
            // 
            // backupMailSaveFileDialog
            // 
            this.backupMailSaveFileDialog.DefaultExt = "htmails";
            this.backupMailSaveFileDialog.FileName = "Backup";
            this.backupMailSaveFileDialog.Filter = "Mails (*.htmails)|*.htmails";
            this.backupMailSaveFileDialog.Title = "Backup Mail";
            // 
            // restoreMailOpenFileDialog
            // 
            this.restoreMailOpenFileDialog.DefaultExt = "htmails";
            this.restoreMailOpenFileDialog.FileName = "mails";
            this.restoreMailOpenFileDialog.Filter = "Mails (*.htmails)|*.htmails";
            this.restoreMailOpenFileDialog.Title = "Restore Mail";
            // 
            // torrentSaveFileDialog
            // 
            this.torrentSaveFileDialog.Title = "Save Torrent File";
            // 
            // voiceTabContextMenuStrip
            // 
            this.voiceTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.voiceTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.clearHistoryToolStripMenuItem});
            this.voiceTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.voiceTabContextMenuStrip.Size = new System.Drawing.Size(143, 26);
            // 
            // clearHistoryToolStripMenuItem
            // 
            this.clearHistoryToolStripMenuItem.Name = "clearHistoryToolStripMenuItem";
            this.clearHistoryToolStripMenuItem.Size = new System.Drawing.Size(142, 22);
            this.clearHistoryToolStripMenuItem.Text = "&Clear History";
            this.clearHistoryToolStripMenuItem.Click += new System.EventHandler(this.clearHistoryToolStripMenuItem_Click);
            // 
            // microphoneImageList
            // 
            this.microphoneImageList.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("microphoneImageList.ImageStream")));
            this.microphoneImageList.TransparentColor = System.Drawing.Color.Transparent;
            this.microphoneImageList.Images.SetKeyName(0, "Microphone2-48-BW.png");
            this.microphoneImageList.Images.SetKeyName(1, "Microphone2-48-Blue.png");
            this.microphoneImageList.Images.SetKeyName(2, "Microphone2-48.png");
            // 
            // voiceBottomPanel
            // 
            this.voiceBottomPanel.BackColor = System.Drawing.Color.Silver;
            this.voiceBottomPanel.Controls.Add(this.speakTextBox);
            this.voiceBottomPanel.Controls.Add(this.speakButton);
            this.voiceBottomPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.voiceBottomPanel.Location = new System.Drawing.Point(0, 486);
            this.voiceBottomPanel.Name = "voiceBottomPanel";
            this.voiceBottomPanel.Size = new System.Drawing.Size(490, 38);
            this.voiceBottomPanel.TabIndex = 5;
            // 
            // speakTextBox
            // 
            this.speakTextBox.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.speakTextBox.Enabled = false;
            this.speakTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.speakTextBox.Location = new System.Drawing.Point(7, 7);
            this.speakTextBox.MaxLength = 1000;
            this.speakTextBox.Name = "speakTextBox";
            this.speakTextBox.Size = new System.Drawing.Size(399, 26);
            this.speakTextBox.TabIndex = 1;
            this.speakTextBox.Text = "This is KK7VZT. This is a radio test.";
            this.speakTextBox.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.speakTextBox_KeyPress);
            // 
            // speakButton
            // 
            this.speakButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right)));
            this.speakButton.Enabled = false;
            this.speakButton.Location = new System.Drawing.Point(412, 5);
            this.speakButton.Name = "speakButton";
            this.speakButton.Size = new System.Drawing.Size(75, 28);
            this.speakButton.TabIndex = 0;
            this.speakButton.Text = "&Speak";
            this.speakButton.UseVisualStyleBackColor = true;
            this.speakButton.Click += new System.EventHandler(this.speakButton_Click);
            // 
            // aprsChatControl
            // 
            this.aprsChatControl.CallsignFont = new System.Drawing.Font("Arial", 8F);
            this.aprsChatControl.CallsignTextColor = System.Drawing.Color.Gray;
            this.aprsChatControl.CornerRadius = 4;
            this.aprsChatControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.aprsChatControl.Images = this.mainImageList;
            this.aprsChatControl.InterMessageMargin = 12;
            this.aprsChatControl.Location = new System.Drawing.Point(0, 60);
            this.aprsChatControl.Margin = new System.Windows.Forms.Padding(2);
            this.aprsChatControl.MaxWidth = 300;
            this.aprsChatControl.MessageBoxColor = System.Drawing.Color.LightBlue;
            this.aprsChatControl.MessageBoxMargin = 10;
            this.aprsChatControl.MessageFont = new System.Drawing.Font("Arial", 10F);
            this.aprsChatControl.MinWidth = 100;
            this.aprsChatControl.Name = "aprsChatControl";
            this.aprsChatControl.ShadowOffset = 2;
            this.aprsChatControl.SideMargins = 12;
            this.aprsChatControl.Size = new System.Drawing.Size(490, 426);
            this.aprsChatControl.TabIndex = 5;
            this.aprsChatControl.TextColor = System.Drawing.Color.Black;
            this.aprsChatControl.MouseClick += new System.Windows.Forms.MouseEventHandler(this.aprsChatControl_MouseClick);
            this.aprsChatControl.MouseDoubleClick += new System.Windows.Forms.MouseEventHandler(this.aprsChatControl_MouseDoubleClick);
            // 
            // torrentBlocksUserControl
            // 
            this.torrentBlocksUserControl.AutoScroll = true;
            this.torrentBlocksUserControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.torrentBlocksUserControl.Location = new System.Drawing.Point(2, 2);
            this.torrentBlocksUserControl.Margin = new System.Windows.Forms.Padding(2, 2, 2, 2);
            this.torrentBlocksUserControl.Name = "torrentBlocksUserControl";
            this.torrentBlocksUserControl.Size = new System.Drawing.Size(478, 234);
            this.torrentBlocksUserControl.TabIndex = 0;
            // 
            // MainForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(813, 578);
            this.Controls.Add(this.mainTabControl);
            this.Controls.Add(this.radioPanel);
            this.Controls.Add(this.mainStatusStrip);
            this.Controls.Add(this.mainMenuStrip);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MainMenuStrip = this.mainMenuStrip;
            this.MinimumSize = new System.Drawing.Size(829, 617);
            this.Name = "MainForm";
            this.Text = "Handi-Talkie Commander";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.MainForm_FormClosing);
            this.Load += new System.EventHandler(this.MainForm_Load);
            this.mainStatusStrip.ResumeLayout(false);
            this.mainStatusStrip.PerformLayout();
            this.mainMenuStrip.ResumeLayout(false);
            this.mainMenuStrip.PerformLayout();
            this.radioPanel.ResumeLayout(false);
            this.radioPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.transmitPictureBox)).EndInit();
            this.connectedPanel.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.radioPictureBox)).EndInit();
            this.mainTabControl.ResumeLayout(false);
            this.aprsTabPage.ResumeLayout(false);
            this.aprsMissingChannelPanel.ResumeLayout(false);
            this.aprsMissingChannelPanel.PerformLayout();
            this.aprsBottomPanel.ResumeLayout(false);
            this.aprsBottomPanel.PerformLayout();
            this.aprsTopPanel.ResumeLayout(false);
            this.aprsTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.aprsMenuPictureBox)).EndInit();
            this.mapTabPage.ResumeLayout(false);
            this.mapTopPanel.ResumeLayout(false);
            this.mapTopPanel.PerformLayout();
            this.voiceTabPage.ResumeLayout(false);
            this.panel6.ResumeLayout(false);
            this.panel6.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.voiceMenuPictureBox)).EndInit();
            this.mailTabPage.ResumeLayout(false);
            this.mailboxHorizontalSplitContainer.Panel1.ResumeLayout(false);
            this.mailboxHorizontalSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.mailboxHorizontalSplitContainer)).EndInit();
            this.mailboxHorizontalSplitContainer.ResumeLayout(false);
            this.mailboxVerticalSplitContainer.Panel1.ResumeLayout(false);
            this.mailboxVerticalSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.mailboxVerticalSplitContainer)).EndInit();
            this.mailboxVerticalSplitContainer.ResumeLayout(false);
            this.mailContextMenuStrip.ResumeLayout(false);
            this.mailTransferStatusPanel.ResumeLayout(false);
            this.panel2.ResumeLayout(false);
            this.panel2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailMenuPictureBox)).EndInit();
            this.stationsTabContextMenuStrip.ResumeLayout(false);
            this.terminalTabPage.ResumeLayout(false);
            this.terminalBottomPanel.ResumeLayout(false);
            this.terminalBottomPanel.PerformLayout();
            this.terminalTopPanel.ResumeLayout(false);
            this.terminalTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.terminalMenuPictureBox)).EndInit();
            this.addressesTabPage.ResumeLayout(false);
            this.stationsContextMenuStrip.ResumeLayout(false);
            this.panel1.ResumeLayout(false);
            this.panel1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.stationsMenuPictureBox)).EndInit();
            this.bbsTabPage.ResumeLayout(false);
            this.bbsSplitContainer.Panel1.ResumeLayout(false);
            this.bbsSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.bbsSplitContainer)).EndInit();
            this.bbsSplitContainer.ResumeLayout(false);
            this.panel4.ResumeLayout(false);
            this.panel4.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.bbsMenuPictureBox)).EndInit();
            this.torrentTabPage.ResumeLayout(false);
            this.torrentSplitContainer.Panel1.ResumeLayout(false);
            this.torrentSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.torrentSplitContainer)).EndInit();
            this.torrentSplitContainer.ResumeLayout(false);
            this.torrentContextMenuStrip.ResumeLayout(false);
            this.torrentTabControl.ResumeLayout(false);
            this.tabPage1.ResumeLayout(false);
            this.tabPage2.ResumeLayout(false);
            this.panel5.ResumeLayout(false);
            this.panel5.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.torrentMenuPictureBox)).EndInit();
            this.torrentTabContextMenuStrip.ResumeLayout(false);
            this.packetsTabPage.ResumeLayout(false);
            this.packetsSplitContainer.Panel1.ResumeLayout(false);
            this.packetsSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.packetsSplitContainer)).EndInit();
            this.packetsSplitContainer.ResumeLayout(false);
            this.packetsListContextMenuStrip.ResumeLayout(false);
            this.packetDataContextMenuStrip.ResumeLayout(false);
            this.panel3.ResumeLayout(false);
            this.panel3.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.packetsMenuPictureBox)).EndInit();
            this.debugTabPage.ResumeLayout(false);
            this.debugTabPage.PerformLayout();
            this.debugControlsPanel.ResumeLayout(false);
            this.debugControlsPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.debugMenuPictureBox)).EndInit();
            this.aprsContextMenuStrip.ResumeLayout(false);
            this.terminalTabContextMenuStrip.ResumeLayout(false);
            this.debugTabContextMenuStrip.ResumeLayout(false);
            this.aprsMsgContextMenuStrip.ResumeLayout(false);
            this.packetsContextMenuStrip.ResumeLayout(false);
            this.bbsTabContextMenuStrip.ResumeLayout(false);
            this.notifyContextMenuStrip.ResumeLayout(false);
            this.mailTabContextMenuStrip.ResumeLayout(false);
            this.voiceTabContextMenuStrip.ResumeLayout(false);
            this.voiceBottomPanel.ResumeLayout(false);
            this.voiceBottomPanel.PerformLayout();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

#endregion

        private System.Windows.Forms.StatusStrip mainStatusStrip;
        private System.Windows.Forms.MenuStrip mainMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem exitToolStripMenuItem;
        private System.Windows.Forms.Panel radioPanel;
        private System.Windows.Forms.TabControl mainTabControl;
        private System.Windows.Forms.TabPage mapTabPage;
        private System.Windows.Forms.TabPage debugTabPage;
        private System.Windows.Forms.PictureBox radioPictureBox;
        private System.Windows.Forms.TextBox debugTextBox;
        private System.Windows.Forms.Panel debugControlsPanel;
        private System.Windows.Forms.ImageList tabsImageList;
        private System.Windows.Forms.ToolStripMenuItem connectToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem disconnectToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.Button connectButton;
        private System.Windows.Forms.Label radioStateLabel;
        private System.Windows.Forms.FlowLayoutPanel channelsFlowLayoutPanel;
        private System.Windows.Forms.ToolStripMenuItem aboutToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem2;
        private System.Windows.Forms.ToolStripStatusLabel mainToolStripStatusLabel;
        private System.Windows.Forms.ToolStripStatusLabel batteryToolStripStatusLabel;
        private System.Windows.Forms.Timer batteryTimer;
        private System.Windows.Forms.ProgressBar rssiProgressBar;
        private System.Windows.Forms.ToolStripMenuItem radioStatusToolStripMenuItem;
#if !__MonoCS__
        private GMap.NET.WindowsForms.GMapControl mapControl;
#endif
        private System.Windows.Forms.ToolStripMenuItem radioSettingsToolStripMenuItem;
        private System.Windows.Forms.Panel connectedPanel;
        private System.Windows.Forms.Label vfo2StatusLabel;
        private System.Windows.Forms.Label vfo2FreqLabel;
        private System.Windows.Forms.Panel linePanel;
        private System.Windows.Forms.Label vfo1StatusLabel;
        private System.Windows.Forms.Label vfo1FreqLabel;
        private System.Windows.Forms.Label vfo2Label;
        private System.Windows.Forms.TabPage terminalTabPage;
        private System.Windows.Forms.Panel terminalTopPanel;
        private System.Windows.Forms.Panel terminalBottomPanel;
        private System.Windows.Forms.Button terminalSendButton;
        private System.Windows.Forms.TextBox terminalInputTextBox;
        private System.Windows.Forms.TabPage aprsTabPage;
        private System.Windows.Forms.Panel aprsBottomPanel;
        private System.Windows.Forms.TextBox aprsTextBox;
        private System.Windows.Forms.Button aprsSendButton;
        private System.Windows.Forms.Panel aprsTopPanel;
        //private ChatMessagesControl aprsChatMessages;
        private System.Windows.Forms.Label aprsTitleLabel;
        private System.Windows.Forms.Panel mapTopPanel;
        private System.Windows.Forms.Label mapTopLabel;
        private System.Windows.Forms.ToolStripMenuItem viewToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem radioToolStripMenuItem;
        private System.Windows.Forms.ImageList mainImageList;
        private System.Windows.Forms.TabPage addressesTabPage;
        private System.Windows.Forms.Panel panel1;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.ListView mainAddressBookListView;
        private System.Windows.Forms.ColumnHeader columnHeader1;
        private System.Windows.Forms.ColumnHeader columnHeader2;
        private System.Windows.Forms.Button addStationButton;
        private System.Windows.Forms.Button removeStationButton;
        private System.Windows.Forms.ToolStripMenuItem aboutToolStripMenuItem1;
        private System.Windows.Forms.ColumnHeader columnHeader3;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Label terminalTitleLabel;
        private System.Windows.Forms.SaveFileDialog saveTraceFileDialog;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem4;
        private System.Windows.Forms.ToolStripMenuItem settingsToolStripMenuItem;
        private System.Windows.Forms.ComboBox aprsDestinationComboBox;
        private System.Windows.Forms.TabPage mailTabPage;
        private System.Windows.Forms.Panel panel2;
        private System.Windows.Forms.Label mailTitleLabel;
        private System.Windows.Forms.ListView mailboxListView;
        private System.Windows.Forms.ColumnHeader columnHeader4;
        private System.Windows.Forms.ColumnHeader columnHeader5;
        private System.Windows.Forms.ColumnHeader columnHeader6;
        private ChatControl aprsChatControl;
        private System.Windows.Forms.ToolStripMenuItem settingsToolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem dualWatchToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem scanToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem5;
        private System.Windows.Forms.ToolStripMenuItem volumeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem mapToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem terminalToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem mailToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem contactsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem6;
        private System.Windows.Forms.ContextMenuStrip aprsContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showAllMessagesToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem7;
        private System.Windows.Forms.ToolStripMenuItem smSMessageToolStripMenuItem;
        private System.Windows.Forms.ContextMenuStrip aprsMsgContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem detailsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem copyMessageToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem copyCallsignToolStripMenuItem;
        private System.Windows.Forms.Button mapZoomOutButton;
        private System.Windows.Forms.Button mapZoomInbutton;
        private System.Windows.Forms.TabPage packetsTabPage;
        private System.Windows.Forms.ListView packetsListView;
        private System.Windows.Forms.ColumnHeader columnHeader7;
        private System.Windows.Forms.ColumnHeader columnHeader8;
        private System.Windows.Forms.ColumnHeader columnHeader9;
        private System.Windows.Forms.Panel panel3;
        private System.Windows.Forms.PictureBox packetsMenuPictureBox;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.ToolStripMenuItem packetsToolStripMenuItem;
        private System.Windows.Forms.SplitContainer packetsSplitContainer;
        private System.Windows.Forms.ContextMenuStrip packetsContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showPacketDecodeToolStripMenuItem;
        private System.Windows.Forms.ContextMenuStrip packetsListContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem copyHEXValuesToolStripMenuItem;
        private System.Windows.Forms.PictureBox debugMenuPictureBox;
        private System.Windows.Forms.ContextMenuStrip debugTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem debugSaveToFileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem showBluetoothFramesToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem8;
        private System.Windows.Forms.ToolStripMenuItem clearToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem debugToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem3;
        private System.Windows.Forms.ToolStripMenuItem queryDeviceNamesToolStripMenuItem;
        private System.Windows.Forms.ComboBox aprsRouteComboBox;
        private System.Windows.Forms.ToolStripMenuItem showLocationToolStripMenuItem;
        private System.Windows.Forms.Button checkBluetoothButton;
        private System.Windows.Forms.Panel aprsMissingChannelPanel;
        private System.Windows.Forms.Label missingAprsChannelLabel;
        private System.Windows.Forms.Button aprsSetupButton;
        private System.Windows.Forms.ToolStripMenuItem allChannelsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem regionToolStripMenuItem;
        private System.Windows.Forms.ListView packetDecodeListView;
        private System.Windows.Forms.ColumnHeader packetDecodeColumnHeader1;
        private System.Windows.Forms.ColumnHeader packetDecodeColumnHeader2;
        private System.Windows.Forms.SaveFileDialog savePacketsFileDialog;
        private System.Windows.Forms.ToolStripMenuItem saveToFileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem saveToFileToolStripMenuItem1;
        private System.Windows.Forms.OpenFileDialog openPacketsFileDialog;
        private System.Windows.Forms.ToolStripMenuItem openFileToolStripMenuItem;
        private System.Windows.Forms.ContextMenuStrip packetDataContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem copyToClipboardToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem loopbackModeToolStripMenuItem;
        private System.Windows.Forms.PictureBox terminalMenuPictureBox;
        private System.Windows.Forms.ContextMenuStrip terminalTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem toolStripMenuItem13;
        private System.Windows.Forms.PictureBox stationsMenuPictureBox;
        private System.Windows.Forms.ContextMenuStrip stationsTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem exportStationsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem importStationsToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog saveStationsFileDialog;
        private System.Windows.Forms.OpenFileDialog openStationsFileDialog;
        private System.Windows.Forms.ContextMenuStrip stationsContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem editToolStripMenuItem;
        private System.Windows.Forms.Button terminalConnectButton;
        private System.Windows.Forms.Label vfo1Label;
        private System.Windows.Forms.ToolStripMenuItem setToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem removeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem exportChannelsToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog exportChannelsFileDialog;
        private System.Windows.Forms.ToolStripMenuItem importChannelsToolStripMenuItem;
        private System.Windows.Forms.OpenFileDialog importChannelFileDialog;
        private System.Windows.Forms.RichTextBox terminalTextBox;
        private System.Windows.Forms.ToolStripMenuItem showCallsignToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem9;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem10;
        private System.Windows.Forms.TabPage bbsTabPage;
        private System.Windows.Forms.ListView bbsListView;
        private System.Windows.Forms.ColumnHeader columnHeader10;
        private System.Windows.Forms.ColumnHeader columnHeader11;
        private System.Windows.Forms.ColumnHeader columnHeader12;
        private System.Windows.Forms.Panel panel4;
        private System.Windows.Forms.Button bbsConnectButton;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.ToolStripMenuItem bBSToolStripMenuItem;
        private System.Windows.Forms.SplitContainer bbsSplitContainer;
        private System.Windows.Forms.PictureBox bbsMenuPictureBox;
        private System.Windows.Forms.ContextMenuStrip bbsTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem viewTrafficToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem11;
        private System.Windows.Forms.ToolStripMenuItem clearStatsToolStripMenuItem;
        private System.Windows.Forms.RichTextBox bbsTextBox;
        private System.Windows.Forms.NotifyIcon notifyIcon;
        private System.Windows.Forms.ContextMenuStrip notifyContextMenuStrip;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem12;
        private System.Windows.Forms.ToolStripMenuItem exitToolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem systemTrayToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem radioInformationToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem radioBSSSettingsToolStripMenuItem;
        private System.Windows.Forms.PictureBox aprsMenuPictureBox;
        private System.Windows.Forms.ToolStripMenuItem weatherReportToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem beaconSettingsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem waitForConnectionToolStripMenuItem;
        private System.Windows.Forms.SplitContainer mailboxHorizontalSplitContainer;
        private System.Windows.Forms.SplitContainer mailboxVerticalSplitContainer;
        private System.Windows.Forms.TreeView mailBoxesTreeView;
        private System.Windows.Forms.PictureBox mailMenuPictureBox;
        private System.Windows.Forms.ContextMenuStrip mailTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showPreviewToolStripMenuItem;
        private System.Windows.Forms.Button newMailButton;
        private System.Windows.Forms.Button mailConnectButton;
        private System.Windows.Forms.ImageList mailBoxImageList;
        private System.Windows.Forms.RichTextBox mailPreviewTextBox;
        private System.Windows.Forms.ContextMenuStrip mailContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem moveToOutboxToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToDraftToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToInboxToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToArchiveToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToTrashToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem viewMailToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem editMailToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem14;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem15;
        private System.Windows.Forms.ToolStripMenuItem deleteMailToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem16;
        private System.Windows.Forms.ToolStripMenuItem backupMailToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem restoreMailToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog backupMailSaveFileDialog;
        private System.Windows.Forms.OpenFileDialog restoreMailOpenFileDialog;
        private System.Windows.Forms.Panel transmitBarPanel;
        private System.Windows.Forms.ToolStripMenuItem clearPacketsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem18;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem17;
        private System.Windows.Forms.Panel mailTransferStatusPanel;
        private System.Windows.Forms.Label mailTransferStatusLabel;
        private System.Windows.Forms.ToolStripMenuItem showTrafficToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem showToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem hideToolStripMenuItem;
        private System.Windows.Forms.TabPage torrentTabPage;
        private System.Windows.Forms.Panel panel5;
        private System.Windows.Forms.PictureBox torrentMenuPictureBox;
        private System.Windows.Forms.Button torrentConnectButton;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.SplitContainer torrentSplitContainer;
        private System.Windows.Forms.ToolStripMenuItem torrentToolStripMenuItem;
        private System.Windows.Forms.ListView torrentListView;
        private System.Windows.Forms.ColumnHeader columnHeader14;
        private System.Windows.Forms.ColumnHeader columnHeader15;
        private System.Windows.Forms.ColumnHeader columnHeader16;
        private System.Windows.Forms.Button torrentAddFileButton;
        private System.Windows.Forms.TabControl torrentTabControl;
        private System.Windows.Forms.TabPage tabPage1;
        private System.Windows.Forms.TabPage tabPage2;
        private System.Windows.Forms.ContextMenuStrip torrentContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem torrentPauseToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem torrentShareToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem torrentRequestToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem19;
        private System.Windows.Forms.ToolStripMenuItem torrentSaveAsToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem20;
        private System.Windows.Forms.ToolStripMenuItem torrentDeleteToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog torrentSaveFileDialog;
        private System.Windows.Forms.ContextMenuStrip torrentTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showDetailsToolStripMenuItem;
        private System.Windows.Forms.ListView torrentDetailsListView;
        private System.Windows.Forms.ColumnHeader columnHeader13;
        private System.Windows.Forms.ColumnHeader columnHeader17;
        private TorrentBlocksUserControl torrentBlocksUserControl;
        private System.Windows.Forms.ToolStripMenuItem audioEnabledToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem voiceToolStripMenuItem;
        private System.Windows.Forms.TabPage voiceTabPage;
        private System.Windows.Forms.Panel panel6;
        private System.Windows.Forms.PictureBox voiceMenuPictureBox;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.ContextMenuStrip voiceTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem clearHistoryToolStripMenuItem;
        private System.Windows.Forms.RichTextBox voiceHistoryTextBox;
        private System.Windows.Forms.Button voiceEnableButton;
        private System.Windows.Forms.Label voiceProcessingLabel;
        private System.Windows.Forms.PictureBox transmitPictureBox;
        private System.Windows.Forms.ImageList microphoneImageList;
        private System.Windows.Forms.Panel voiceBottomPanel;
        private System.Windows.Forms.TextBox speakTextBox;
        private System.Windows.Forms.Button speakButton;
    }
}

