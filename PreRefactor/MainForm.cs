/*
Copyright 2025 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Drawing;
using System.IO.Pipes;
using System.Diagnostics;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.Collections.Generic;
using aprsparser;
using NAudio.Wave;
using HTCommander.radio;
using static HTCommander.AX25Packet;
using static HTCommander.Radio;

namespace HTCommander
{
    public partial class MainForm : Form
    {
        static public MainForm g_MainForm = null;
        public Radio radio = new Radio();
        public VoiceEngine voiceEngine;
        public RadioChannelControl[] channelControls = null;
        public RadioHtStatusForm radioHtStatusForm = null;
        public RadioSettingsForm radioSettingsForm = null;
        public RadioBssSettingsForm radioBssSettingsForm = null;
        public RadioChannelForm radioChannelForm = null;
        public RadioVolumeForm radioVolumeForm = null;
        public RadioAudioClipsForm radioAudioClipsForm = null;
        public RadioPositionForm radioPositionForm = null;
        public AprsDetailsForm aprsDetailsForm = null;
        public BTActivateForm bluetoothActivateForm = null;
        public SpectrogramForm spectrogramForm = null;
        public AprsConfigurationForm aprsConfigurationForm = null;
        public MailComposeForm mailComposeForm = null;
        public int vfo2LastChannelId = -1;
        public int nextAprsMessageId = 1;
        public RegistryHelper registry = new RegistryHelper("HTCommander");
        public FileStream debugFile = null;
        public FileStream AprsFile = null;
        public string callsign;
        public int stationId;
        public bool allowTransmit;
        public string appTitle;
        public Dictionary<string, List<AX25Address>> aprsRoutes;
        public string aprsSelectedRoute;
        public ChatMessage selectedAprsMessage;
        public bool previewMode = false;
        public CompatibleDevice[] devices = null;
        public bool bluetoothEnabled = false;
        public int aprsChannel = -1;
        public bool showAllChannels = false;
        public List<StationInfoClass> stations = new List<StationInfoClass>();
        public StationInfoClass activeStationLock = null;
        public byte[] activeStationsLock_oldSettings;
        public AX25Session session = null;
        public int activeChannelIdLock = -1;
        public string winlinkPassword = null;
        public HttpsWebSocketServer webserver;
        public bool webServerEnabled = false;
        public int webServerPort = 8080;
        public AgwpeSocketServer agwpeServer;
        public bool agwpeServerEnabled = false;
        public int agwpeServerPort = 8000;
        public ImapServer imapServer;
        public bool imapServerEnabled = false;
        public int imapServerPort = 1143;
        public SmtpServer smtpServer;
        public bool smtpServerEnabled = false;
        public int smtpServerPort = 2525;
        public BBS bbs;
        public Torrent torrent;
        public WinlinkClient winlinkClient;
        public WinlinkClient tcpWinlinkClient;
        public AprsStack aprsStack;
        public YappTransfer yappTransfer;
        public bool Loading = true;
        public MailClientDebugForm mailClientDebugForm = new MailClientDebugForm();
        public string appDataPath;
        public bool RealExit = false;
        public string voiceLanguage = "auto";
        public string voiceModel = null;
        public string voice = null;
        public string voiceConfirmedChannelName;
        public string voiceHistoryCompleted = "";
        public List<MapLocationForm> mapLocationForms = new List<MapLocationForm>();
        //public GMapOverlay mapMarkersOverlay = new GMapOverlay("AprsMarkers");
        //public Dictionary<string, GMapRoute> mapRoutes = new Dictionary<string, GMapRoute>();
        public int mapFilterMinutes = 0;
        public string TerminalLastDone = null;

        // Mailboxes
        public IMailStore mailStore;

        public static bool IsRunningOnMono() { return Type.GetType("Mono.Runtime") != null; }
        public static Image GetImage(int i) { return g_MainForm.mainImageList.Images[i]; }
        public Microphone microphone = null;
        public bool microphoneTransmit = false;

        public bool AudioEnabled { get { return audioEnabledToolStripMenuItem.Checked; } set { audioEnabledToolStripMenuItem.Checked = !value; audioEnabledToolStripMenuItem_Click(this, null); } }

        public MainForm(string[] args)
        {
            bool multiInstance = false;
            foreach (string arg in args)
            {
                if (string.Compare(arg, "-preview", true) == 0) { previewMode = true; }
                if (string.Compare(arg, "-multiinstance", true) == 0) { multiInstance = true; }
            }
            if (multiInstance == false) { StartPipeServer(); }

            g_MainForm = this;
            InitializeComponent();

            bbs = new BBS(this);
            torrent = new Torrent(this);
            aprsStack = new AprsStack(this);
            winlinkClient = new WinlinkClient(this, WinlinkClient.TransportType.X25);
            tcpWinlinkClient = new WinlinkClient(this, WinlinkClient.TransportType.TCP);
            voiceEngine = new VoiceEngine(radio);
            microphone = new Microphone();
            microphone.DataAvailable += Microphone_DataAvailable;
            radioVolumeForm = new RadioVolumeForm(this, radio);

            aprsTabUserControl.Initialize(this);
            mapTabUserControl.Initialize(this);
            voiceTabUserControl.Initialize(this);
            mailTabUserControl.Initialize(this);
            terminalTabUserControl.Initialize(this);
            contactsTabUserControl.Initialize(this);
            bbsTabUserControl.Initialize(this);
            torrentTabUserControl.Initialize(this);
            packetCaptureTabUserControl.Initialize(this);
            debugTabUserControl.Initialize(this);
        }
        private void StartPipeServer()
        {
            Task.Run(() =>
            {
                while (true)
                {
                    using (var server = new NamedPipeServerStream(Program.PipeName))
                    using (var reader = new StreamReader(server))
                    {
                        server.WaitForConnection();
                        var message = reader.ReadLine();
                        if (message == "show") { showToolStripMenuItem_Click(this, null); }
                    }
                }
            });
        }

        private void Microphone_DataAvailable(byte[] data, int bytesRecorded)
        {
            radioVolumeForm.ProcessInputAudioData(data, bytesRecorded);
            if (spectrogramForm != null) { spectrogramForm.AddAudioData(data, 0, bytesRecorded, true); }
            if (radioVolumeForm.MicrophoneTransmit)
            {
                radio.TransmitVoice(data, 0, bytesRecorded, false);
                //if (spectrogramForm != null) { spectrogramForm.AddAudioData(data, 0,bytesRecorded, false); }
            }
        }

        private void RadioAudio_DataAvailable(Radio radio, byte[] data, int offset, int bytesRecorded, string channelName, bool transmit)
        {
            if (transmit == false) { radioVolumeForm.ProcessOutputAudioData(data, bytesRecorded); }
            if (spectrogramForm != null) { spectrogramForm.AddAudioData(data, offset, bytesRecorded, false); }
        }

        private void cancelVoiceButton_Click(object sender, EventArgs e)
        {
            radio.CancelVoiceTransmit();
        }

        public int GetNextAprsMessageId()
        {
            int msgId = nextAprsMessageId++;
            if (nextAprsMessageId > 999) { nextAprsMessageId = 1; }
            registry.WriteInt("NextAprsMessageId", nextAprsMessageId);
            return msgId;
        }

        public void SetRadioImage(int radio)
        {
            //radioPictureBox.Visible = (radio == 0);
            //radio2PictureBox.Visible = (radio == 1);
            registry.WriteInt("RadioImage", radio);
        }

        private void MainForm_Load(object sender, EventArgs e)
        {
            Program.BlockBoxEvent("MainForm_Load");

            appTitle = this.Text;
            this.SuspendLayout();
            
            // Wire up software modem menu item click handlers
            disabledToolStripMenuItem.Click += SoftwareModem_Click;
            aFK1200ToolStripMenuItem.Click += SoftwareModem_Click;
            pSK2400ToolStripMenuItem.Click += SoftwareModem_Click;
            pSK4800ToolStripMenuItem.Click += SoftwareModem_Click;
            g9600ToolStripMenuItem.Click += SoftwareModem_Click;
            
            // Wire up hardware modem menu item click handlers
            radio.DebugMessage += Radio_DebugMessage;
            radio.OnInfoUpdate += Radio_InfoUpdate;
            radio.OnDataFrame += Radio_OnDataFrame;
            radio.OnChannelClear += Radio_OnChannelClear;
            radio.onTextReady += Radio_onTextReady;
            radio.onProcessingVoice += Radio_onProcessingVoice;
            radio.OnVoiceTransmitStateChanged += Radio_OnVoiceTransmitStateChanged;
            radio.OnAudioDataAvailable += RadioAudio_DataAvailable;
            radio.onPositionUpdate += Radio_onPositionUpdate;
            radio.onRawCommand += Radio_onRawCommand;
            mainTabControl.SelectedTab = aprsTabPage;

            string debugFileName = registry.ReadString("DebugFile", null);
            try
            {
                saveTraceFileDialog.FileName = debugFileName;
                debugFile = File.OpenWrite(debugFileName);
                //debugSaveToFileToolStripMenuItem.Checked = true;
                DebugTrace("-- Application Started --");
            }
            catch (Exception) { }

            // Read stations
            string stationsStr = registry.ReadString("Stations", null);
            if (stationsStr != null)
            {

                List<StationInfoClass> xstations = StationInfoClass.Deserialize(stationsStr);
                if (xstations != null) { stations = xstations; }
            }
            UpdateStations();

            // Read registry values
            callsign = registry.ReadString("CallSign", null);
            stationId = (int)registry.ReadInt("StationId", 0);
            if ((callsign != null) && ((callsign.Length > 6) || (callsign.Length < 3))) { callsign = null; }
            if ((stationId < 0) || (stationId > 15)) { stationId = 0; }
            aprsRoutes = Utils.DecodeAprsRoutes(registry.ReadString("AprsRoutes", "Standard,APN000,WIDE1-1,WIDE2-2"));
            aprsSelectedRoute = registry.ReadString("SelectedAprsRoute", "Standard");
            nextAprsMessageId = (int)registry.ReadInt("NextAprsMessageId", new Random().Next(1, 1000));
            radioPanel.Visible = radioToolStripMenuItem.Checked = registry.ReadInt("ViewRadio", 1) == 1;
            showAllChannels = (registry.ReadInt("ShowAllChannels", 0) == 1);
            //aprsDestinationComboBox.Text = registry.ReadString("AprsDestination", "ALL");
            voiceToolStripMenuItem.Checked = (registry.ReadInt("ViewVoice", 0) == 1);
            contactsToolStripMenuItem.Checked = (registry.ReadInt("ViewContacts", 0) == 1);
            bBSToolStripMenuItem.Checked = (registry.ReadInt("ViewBBS", 0) == 1);
            torrentToolStripMenuItem.Checked = (registry.ReadInt("ViewTorrent", 0) == 1);
            terminalToolStripMenuItem.Checked = (registry.ReadInt("ViewTerminal", 1) == 1);
            winlinkPassword = registry.ReadString("WinlinkPassword", "");
            mailToolStripMenuItem.Checked = (registry.ReadInt("ViewMail", 0) == 1);
            packetsToolStripMenuItem.Checked = (registry.ReadInt("ViewPackets", 0) == 1);
            debugToolStripMenuItem.Checked = (registry.ReadInt("ViewDebug", 0) == 1);
            //showAllMessagesToolStripMenuItem.Checked = (registry.ReadInt("aprsViewAll", 1) == 1);
            //showPacketDecodeToolStripMenuItem.Checked = (registry.ReadInt("showPacketDecode", 0) == 1);
            //showCallsignToolStripMenuItem.Checked = (registry.ReadInt("TerminalShowCallsign", 1) == 1);
            viewTrafficToolStripMenuItem.Checked = (registry.ReadInt("ViewBbsTraffic", 1) == 1);
            //bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;
            systemTrayToolStripMenuItem.Checked = (registry.ReadInt("SystemTray", 1) == 1);
            audioEnabledToolStripMenuItem.Checked = (registry.ReadInt("Audio", 0) == 1);
            gPSEnabledToolStripMenuItem.Checked = (registry.ReadInt("GpsEnabled", 0) == 1);
            radio.GpsEnabled(gPSEnabledToolStripMenuItem.Checked);

            checkForUpdatesToolStripMenuItem.Checked = (registry.ReadInt("CheckForUpdates", 1) == 1);
            //offlineModeToolStripMenuItem.Checked = (registry.ReadInt("MapOfflineMode", 0) == 1);
            //cacheAreaToolStripMenuItem.Enabled = !offlineModeToolStripMenuItem.Checked;
            //mapControl.Manager.Mode = offlineModeToolStripMenuItem.Checked ? GMap.NET.AccessMode.CacheOnly : GMap.NET.AccessMode.ServerAndCache;
            //mapTopLabel.Text = offlineModeToolStripMenuItem.Checked ? "Offline Map" : "Map";
            //showTracksToolStripMenuItem.Checked = (registry.ReadInt("MapShowTracks", 1) == 1);
            //mapFilterMinutes = (int)registry.ReadInt("MapTimeFilter", 0);
            //foreach (ToolStripMenuItem i in showMarkersToolStripMenuItem.DropDownItems) { i.Checked = (int.Parse((string)((ToolStripMenuItem)i).Tag) == mapFilterMinutes); }
            //largeMarkersToolStripMenuItem.Checked = (registry.ReadInt("MapLargeMarkers", 1) == 1);
            SetRadioImage((int)registry.ReadInt("RadioImage", 0));
            
            // Initialize the mail store (SQLite-based storage)
            mailStore = new MailStore();
            mailStore.MailsChanged += MailStore_MailsChanged;

            // Get application data path
            appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander");

            // Read torrent files
            List<TorrentFile> torrentFiles = TorrentFile.ReadTorrentFiles();
            foreach (TorrentFile torrentFile in torrentFiles) { AddTorrent(torrentFile); }

            // Read the packets file
            string[] lines = null;
            try { lines = File.ReadAllLines(Path.Combine(appDataPath, "packets.ptcap")); } catch (Exception) { }
            if (lines != null)
            {
                // If the packet file is big, load only the first 200 packets
                int i = 0;
                if (lines.Length > 5000) { i = lines.Length - 5000; }
                List<ListViewItem> listViewItems = new List<ListViewItem>();
                for (; i < lines.Length; i++)
                {
                    try
                    {
                        // Read the packets
                        string[] s = lines[i].Split(',');
                        if (s.Length < 3) continue;
                        DateTime t = new DateTime(long.Parse(s[0]));
                        bool incoming = (s[1] == "1");
                        if ((s[2] != "TncFrag") && (s[2] != "TncFrag2") && (s[2] != "TncFrag3")) continue;
                        int cid = int.Parse(s[3]);
                        int rid = -1;
                        string cn = cid.ToString();
                        byte[] f;
                        TncDataFragment.FragmentEncodingType encoding = TncDataFragment.FragmentEncodingType.Unknown;
                        TncDataFragment.FragmentFrameType frame_type = TncDataFragment.FragmentFrameType.Unknown;
                        int corrections = -1;

                        if (s[2] == "TncFrag")
                        {
                            f = Utils.HexStringToByteArray(s[4]);
                        }
                        else if (s[2] == "TncFrag2")
                        {
                            if (s.Length < 7) continue;
                            rid = 0;
                            int.TryParse(s[4], out rid);
                            cn = s[5];
                            f = Utils.HexStringToByteArray(s[6]);
                        }
                        else
                        {
                            if (s.Length < 10) continue;
                            rid = 0;
                            int.TryParse(s[4], out rid);
                            cn = s[5];
                            f = Utils.HexStringToByteArray(s[6]);
                            encoding = (TncDataFragment.FragmentEncodingType)Enum.Parse(typeof(TncDataFragment.FragmentEncodingType), s[7]);
                            frame_type = (TncDataFragment.FragmentFrameType)Enum.Parse(typeof(TncDataFragment.FragmentFrameType), s[8]);
                            corrections = int.Parse(s[9]);
                        }

                        // Process the packets
                        TncDataFragment fragment = new TncDataFragment(true, 0, f, cid, rid);
                        fragment.time = t;
                        fragment.channel_name = cn;
                        fragment.incoming = incoming;
                        fragment.encoding = encoding;
                        fragment.frame_type = frame_type;
                        fragment.corrections = corrections;
                        Radio_OnDataFrame(null, fragment);

                        // Add to the packet capture tab
                        ListViewItem l = new ListViewItem(new string[] { fragment.time.ToShortTimeString(), fragment.channel_name, Utils.TncDataFragmentToShortString(fragment) });
                        l.ImageIndex = fragment.incoming ? 5 : 4;
                        l.Tag = fragment;
                        listViewItems.Add(l);
                    }
                    catch (Exception) { }
                }
                listViewItems.Sort((a, b) => DateTime.Compare(((TncDataFragment)b.Tag).time, ((TncDataFragment)a.Tag).time));
                packetCaptureTabUserControl.AddPackets(listViewItems);
            }

            // Read the voice history file
            string voiceHistoryFileName = Path.Combine(appDataPath, "voiceHistory.txt");
            try
            {
                StringBuilder sb = new StringBuilder();

                sb.AppendLine("{\\rtf1\\ansi\\ansicpg1252\\deff0\\nouicompat\\deflang1033{\\fonttbl{\\f0\\fnil Microsoft Sans Serif;}{\\f1\\fnil\\fcharset0 Microsoft Sans Serif;}}");
                sb.AppendLine("{\\colortbl ;\\red105\\green105\\blue105;\\red0\\green0\\blue0;\\red255\\green0\\blue0;}");
                sb.AppendLine("{\\*\\generator Riched20 10.0.26100}\\viewkind4\\uc1 \\pard");

                string[] voiceHistory = File.ReadAllLines(voiceHistoryFileName);
                int voiceHistoryStart = 0;
                if (voiceHistory.Length > 500) { voiceHistoryStart = voiceHistory.Length - 500; }
                for (int i = voiceHistoryStart; i < voiceHistory.Length; i++)
                {
                    try
                    {
                        int idx = voiceHistory[i].IndexOf(',');
                        int idx2 = voiceHistory[i].IndexOf(',', idx + 1);
                        bool outbound = (voiceHistory[i][0] == '<');
                        DateTime dateTime = DateTime.Parse(voiceHistory[i].Substring(1, idx));
                        string channelName = voiceHistory[i].Substring(idx + 1, idx2 - idx - 1);
                        string text = voiceHistory[i].Substring(idx2 + 1);
                        //RtfBuilder.AddFormattedEntry(voiceHistoryTextBox, dateTime, channelName, text.Trim(), true, outbound);
                        sb.AppendLine("\\cf1\\f0\\fs16 " + dateTime.ToString() + " - " + channelName + "\\par");
                        if (text.Length > 0)
                        {
                            sb.AppendLine("\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\u8213?\\par");
                            if (outbound)
                            {
                                sb.AppendLine("\\cf3\\fs22 " + text.Trim() + "\\f1\\fs17\\par");
                            }
                            else
                            {
                                sb.AppendLine("\\cf2\\fs22 " + text.Trim() + "\\f1\\fs17\\par");
                            }
                        }
                        sb.AppendLine("\\par");
                    }
                    catch (Exception) { }
                }
                sb.AppendLine("\\cf0\\par");
                sb.AppendLine("}");

                /*
                voiceHistoryCompleted = voiceHistoryTextBox.Rtf = sb.ToString();
                voiceHistoryTextBox.SelectionStart = voiceHistoryTextBox.Text.Length;
                voiceHistoryTextBox.ScrollToCaret();
                */
            }
            catch (Exception) { }

            // Open the packet write file
            try { AprsFile = File.Open(Path.Combine(appDataPath, "packets.ptcap"), FileMode.Append, FileAccess.Write); } catch (Exception) { }
            //aprsChatControl.UpdateMessages(true);

            CheckBluetooth();

            // Setup the TNC server if configured
            agwpeServerEnabled = (registry.ReadInt("agwpeServerEnabled", 0) != 0);
            agwpeServerPort = (int)registry.ReadInt("agwpeServerPort", 0);
            if (agwpeServerEnabled && (agwpeServerPort > 0))
            {
                agwpeServer = new AgwpeSocketServer(this, agwpeServerPort);
                agwpeServer.Start();
            }

            // Setup the HTTP server if configured
            webServerEnabled = (registry.ReadInt("webServerEnabled", 0) != 0);
            webServerPort = (int)registry.ReadInt("webServerPort", 0);
            if (webServerEnabled && (webServerPort > 0))
            {
                webserver = new HttpsWebSocketServer(this, webServerPort);
                webserver.Start();
            }
            toolStripMenuItem2.Visible = localWebSiteToolStripMenuItem.Visible = (webserver != null);

            // Setup the IMAP server if configured
            imapServerEnabled = (registry.ReadInt("imapServerEnabled", 0) != 0);
            imapServerPort = (int)registry.ReadInt("imapServerPort", 1143);
            if (imapServerEnabled && (imapServerPort > 0))
            {
                imapServer = new ImapServer(this, imapServerPort);
                imapServer.Start();
            }

            // Setup the SMTP server if configured
            smtpServerEnabled = (registry.ReadInt("smtpServerEnabled", 0) != 0);
            smtpServerPort = (int)registry.ReadInt("smtpServerPort", 2525);
            if (smtpServerEnabled && (smtpServerPort > 0))
            {
                smtpServer = new SmtpServer(this, smtpServerPort);
                smtpServer.Start();
            }

            allowTransmit = (registry.ReadInt("AllowTransmit", 0) == 1);
            Loading = false;

            // Setup voice language and model
            voiceLanguage = registry.ReadString("VoiceLanguage", "auto");
            voiceModel = registry.ReadString("VoiceModel", null);
            voice = registry.ReadString("Voice", null);
            
            // Load software modem setting from registry
            int softwareModemMode = (int)registry.ReadInt("SoftwareModemMode", 0);
            UpdateSoftwareModemMenu((RadioAudio.SoftwareModemModeType)softwareModemMode);
            if (radio != null) { radio.SoftwareModemMode = (RadioAudio.SoftwareModemModeType)softwareModemMode; }
            
            // Load hardware modem setting from registry
            int hardwareModemMode = (int)registry.ReadInt("HardwareModemMode", 1);
            if (radio != null) { radio.HardwareModemEnabled = (hardwareModemMode != 0); }

            //UpdateGpsStatusDisplay();
            this.ResumeLayout();
            UpdateInfo();
            UpdateTabs();

            // Setup AX25 Session, only 1 session supported per radio
            session = new AX25Session(this, radio);
            session.StateChanged += Session_StateChanged;
            session.DataReceivedEvent += Session_DataReceivedEvent;
            session.UiDataReceivedEvent += Session_UiDataReceivedEvent;
            session.ErrorEvent += Session_ErrorEvent;

            // Setup YAPP file transfer
            yappTransfer = new YappTransfer(session, this);
            yappTransfer.ProgressChanged += YappTransfer_ProgressChanged;
            yappTransfer.TransferComplete += YappTransfer_TransferComplete;
            yappTransfer.TransferError += YappTransfer_TransferError;

            // Check for updates
            if (File.Exists("NoUpdateCheck.txt"))
            {
                checkForUpdatesToolStripMenuItem.Visible = false;
                checkForUpdatesToolStripMenuItem.Checked = false;
            }
            else if (checkForUpdatesToolStripMenuItem.Checked)
            {
                string lastUpdateCheck = registry.ReadString("LastUpdateCheck", "");
                if (string.IsNullOrEmpty(lastUpdateCheck) || (DateTime.Now - DateTime.Parse(lastUpdateCheck)).TotalDays > 1)
                {
                    registry.WriteString("LastUpdateCheck", DateTime.Now.ToString());
                    SelfUpdateForm.CheckForUpdate(this);
                }
            }
        }

        private void Radio_onRawCommand(Radio sender, byte[] cmd)
        {
            if (webserver != null) { webserver.BroadcastBinary(cmd); }
        }

        private void Radio_onPositionUpdate(Radio sender, RadioPosition position)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Radio.OnPositionUpdate(Radio_onPositionUpdate), sender, position); return; }
            if (radioPositionForm != null) { radioPositionForm.UpdatePosition(position); }
            //UpdateGpsStatusDisplay();

            if (position.Status == Radio.RadioCommandState.SUCCESS)
            {
                /*
                foreach (GMapMarker m in mapMarkersOverlay.Markers)
                {
                    if (m.ToolTipText == "Self")
                    {
                        m.Tag = DateTime.Now;
                        m.Position = new PointLatLng(position.Latitude, position.Longitude);
                        return;
                    }
                }
                GMapMarker marker = new GMarkerGoogle(new PointLatLng(position.Latitude, position.Longitude), GMarkerGoogleType.blue_dot);
                marker.ToolTipText = "Self";
                marker.Tag = DateTime.Now;
                marker.ToolTipMode = MarkerTooltipMode.OnMouseOver;
                mapMarkersOverlay.Markers.Add(marker);
                //centerToGpsButton.Enabled = centerToGPSToolStripMenuItem.Enabled = true;
                */
            }
        }

        private delegate void UpdateAvailableHandler(float currentVersion, float onlineVersion, string url);
        public void UpdateAvailable(float currentVersion, float onlineVersion, string url)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new UpdateAvailableHandler(UpdateAvailable), currentVersion, onlineVersion, url); return; }

            // Display update dialog
            SelfUpdateForm updateForm = new SelfUpdateForm();
            updateForm.currentVersionText = currentVersion.ToString();
            updateForm.onlineVersionText = onlineVersion.ToString();
            updateForm.updateUrl = url;
            updateForm.ShowDialog(this);
        }

        private void Radio_OnVoiceTransmitStateChanged(Radio sender, bool transmitting)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Radio.VoiceTransmitStateHandler(Radio_OnVoiceTransmitStateChanged), sender, transmitting); return; }
            //cancelVoiceButton.Visible = transmitting;
            //speakButton.Enabled = !transmitting;
        }

        private void Radio_onProcessingVoice(bool listening, bool processing)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Radio.OnProcessingVoiceHandler(Radio_onProcessingVoice), listening, processing); return; }
            //voiceProcessingLabel.Visible = processing;
        }

        private void Radio_onTextReady(string text, string channel, DateTime time, bool completed)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Radio.OnTextReadyHandler(Radio_onTextReady), text, channel, time, completed); return; }
            if ((text == null) || (text.Trim().Length > 0))
            {
                // Suspend painting
                //Utils.SendMessage(voiceHistoryTextBox.Handle, Utils.WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);

                // Perform update
                //voiceHistoryTextBox.Rtf = voiceHistoryCompleted;
                //RtfBuilder.AddFormattedEntry(voiceHistoryTextBox, time, channel, text != null ? text.Trim() : null, completed, false);
                //if (completed) { voiceHistoryCompleted = voiceHistoryTextBox.Rtf; }

                // Resume painting
                //Utils.SendMessage(voiceHistoryTextBox.Handle, Utils.WM_SETREDRAW, new IntPtr(1), IntPtr.Zero);
                //voiceHistoryTextBox.Invalidate(); // Force repaint

                // If completed, append the text to the voice history file
                if (completed)
                {
                    string voiceHistoryFileName = Path.Combine(appDataPath, "voiceHistory.txt");
                    try
                    {
                        using (FileStream fs = new FileStream(voiceHistoryFileName, FileMode.Append, FileAccess.Write))
                        {
                            byte[] bytes = Encoding.UTF8.GetBytes(">" + time.ToString() + "," + channel + "," + text + "\r\n");
                            fs.Write(bytes, 0, bytes.Length);
                        }
                    }
                    catch (Exception) { }
                }
            }
        }

        private void Session_StateChanged(AX25Session sender, AX25Session.ConnectionState state)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new AX25Session.StateChangedHandler(Session_StateChanged), sender, state); return; }

            DebugTrace("AX25 " + state.ToString());
            if ((activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal))
            {
                switch (state)
                {
                    case AX25Session.ConnectionState.CONNECTING:
                        terminalTabUserControl.AppendTerminalString(false, null, null, "Connecting...");
                        break;
                    case AX25Session.ConnectionState.CONNECTED:
                        terminalTabUserControl.AppendTerminalString(false, null, null, "Connected");
                        break;
                    case AX25Session.ConnectionState.DISCONNECTING:
                        terminalTabUserControl.AppendTerminalString(false, null, null, "Disconnecting...");
                        break;
                    case AX25Session.ConnectionState.DISCONNECTED:
                        terminalTabUserControl.AppendTerminalString(false, null, null, "Disconnected");
                        cancelFileTransfer();
                        if ((activeStationLock != null) && (activeStationLock.WaitForConnection == false))
                        {
                            // If we are the connecting party and we got disconnected, drop the station lock.
                            ActiveLockToStation(null);
                        }
                        else
                        {
                            // Wait for another connection
                            terminalTabUserControl.AppendTerminalString(false, null, null, "Waiting for connection...");
                        }
                        break;
                }
            }
            else if ((activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.BBS))
            {
                bbs.ProcessStreamState(session, state);
            }
            else if ((activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.Winlink))
            {
                winlinkClient.ProcessStreamState(session, state);
                if (state == AX25Session.ConnectionState.DISCONNECTED) { ActiveLockToStation(null); }
            }
            else if ((agwpeServer != null) && (activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.AGWPE))
            {
                switch (state)
                {
                    case AX25Session.ConnectionState.CONNECTING:
                        break;
                    case AX25Session.ConnectionState.CONNECTED:
                        if (activeStationLock.WaitForConnection)
                        {
                            agwpeServer.SendSessionConnectToClientEx(activeStationLock.AgwpeClientId);
                        }
                        else
                        {
                            agwpeServer.SendSessionConnectToClient(activeStationLock.AgwpeClientId);
                        }
                        break;
                    case AX25Session.ConnectionState.DISCONNECTING:
                        agwpeServer.SendSessionDisconnectToClient(activeStationLock.AgwpeClientId);
                        break;
                    case AX25Session.ConnectionState.DISCONNECTED:
                        agwpeServer.SendSessionDisconnectToClient(activeStationLock.AgwpeClientId);
                        session.CallSignOverride = null;
                        session.StationIdOverride = -1;
                        ActiveLockToStation(null, -1);
                        break;
                }
            }
        }
        private void Session_DataReceivedEvent(AX25Session sender, byte[] data)
        {
            Debug("AX25 Stream Data: " + data.Length);
            if (activeStationLock != null)
            {
                if (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal)
                {
                    // Check if this might be YAPP data before processing as text
                    if (yappTransfer != null && yappTransfer.ProcessIncomingData(data))
                    {
                        // Data was processed by YAPP, don't display as text
                        return;
                    }
                    
                    string[] dataStrs = UTF8Encoding.UTF8.GetString(data).Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                    for (int i = 0; i < dataStrs.Length; i++)
                    {
                        if ((dataStrs[i].Length == 0) && (i == (dataStrs.Length - 1))) continue;
                        terminalTabUserControl.AppendTerminalString(false, session.Addresses[0].ToString(), callsign + "-" + stationId, dataStrs[i], i < (dataStrs.Length - 1));
                    }
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.BBS)
                {
                    bbs.ProcessStream(session, data);
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.Winlink)
                {
                    winlinkClient.ProcessStream(session, data);
                }
                else if ((agwpeServer != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.AGWPE))
                {
                    agwpeServer.SendSessionDataToClient(activeStationLock.AgwpeClientId, data);
                }
            }
        }

        private void Session_UiDataReceivedEvent(AX25Session sender, byte[] data)
        {
            Debug("AX25 UI Frame Data: " + data.Length);
            if (activeStationLock != null)
            {
                if (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal)
                {
                    terminalTabUserControl.AppendTerminalString(false, session.Addresses[0].ToString(), callsign + "-" + stationId, UTF8Encoding.UTF8.GetString(data));
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.BBS)
                {
                    bbs.ProcessStream(session, data);
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.Winlink)
                {
                    winlinkClient.ProcessStream(session, data);
                }
            }
        }
        private void Session_ErrorEvent(AX25Session sender, string error)
        {
            Debug("AX25 Error: " + error);
        }

        public async void CheckBluetooth()
        {
            //radioStateLabel.Text = "Searching";
            DebugTrace("Looking for compatible radios...");
            bluetoothEnabled = RadioBluetoothWin.CheckBluetooth();
            if (bluetoothEnabled == false)
            {
                //radioStateLabel.Text = "Disconnected";
                //checkBluetoothButton.Visible = true;
                DebugTrace("Bluetooth LE not found on this computer.");
                if (bluetoothActivateForm == null)
                {
                    bluetoothActivateForm = new BTActivateForm(this);
                    bluetoothActivateForm.StartPosition = FormStartPosition.Manual;

                    // Calculate the center position relative to the parent
                    int x = this.Left + (this.Width - bluetoothActivateForm.Width) / 2;
                    int y = this.Top + (this.Height - bluetoothActivateForm.Height) / 2;

                    // Set the dialog's location
                    bluetoothActivateForm.Location = new Point(x, y);
                    bluetoothActivateForm.Show(this);
                }
                else
                {
                    bluetoothActivateForm.Focus();
                }
            }
            else
            {
                if (bluetoothActivateForm != null)
                {
                    bluetoothActivateForm.Close();
                    bluetoothActivateForm = null;
                }

                // Search for compatible devices
                //checkBluetoothButton.Visible = false;
                devices = await RadioBluetoothWin.FindCompatibleDevices();
                if (devices.Length == 0)
                {
                    MessageBox.Show("No compatible radios found. Please pair the radio using Bluetooth and restart this application.", "Bluetooth Radio", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    DebugTrace("No compatible radios found.");
                }
                else
                {
                    foreach (CompatibleDevice radio in devices) { DebugTrace("Found " + radio.name + " - " + radio.mac); }
                }
                UpdateInfo();
                //radioStateLabel.Text = "Disconnected";
            }
        }

        private void Radio_OnChannelClear(Radio sender)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Action(() => { Radio_OnChannelClear(sender); })); return; }

            DebugTrace("Channel is clear");
            if ((activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.Torrent))
            {
                torrent.ChannelIsClear();
            }
        }

        private void Radio_OnDataFrame(Radio sender, TncDataFragment frame)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Action(() => { Radio_OnDataFrame(sender, frame); })); return; }

            if (sender != null)
            {
                // Add to the packet capture tab
                ListViewItem l = new ListViewItem(new string[] { frame.time.ToShortTimeString(), frame.channel_name, Utils.TncDataFragmentToShortString(frame) });
                l.ImageIndex = frame.incoming ? 5 : 4;
                l.Tag = frame;
                packetCaptureTabUserControl.AddPacket(l);

                // Write frame data to file
                if (AprsFile != null)
                {
                    byte[] bytes = UTF8Encoding.Default.GetBytes(frame.time.Ticks + "," + (frame.incoming ? "1" : "0") + "," + frame.ToString() + "\r\n");
                    AprsFile.Write(bytes, 0, bytes.Length);
                }

                // If the TNC server is enabled, broadcast the frame
                if (agwpeServer != null) { agwpeServer.BroadcastFrame(frame); }

                if (frame.incoming == false) return;
            }

            //DebugTrace("Packet: " + frame.ToHex());

            // If this frame comes from the APRS channel, process it as APRS
            if (frame.channel_name == "APRS")
            {
                AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                if ((p != null) && (p.type == FrameType.U_FRAME))
                {
                    AddAprsPacket(p, !frame.incoming);
                    //aprsChatControl.UpdateMessages(false);
                    DebugTrace(frame.time.ToShortTimeString() + " CHANNEL: " + (frame.channel_id + 1) + " X25: " + Utils.BytesToHex(p.data));
                }
                else
                {
                    DebugTrace("APRS decode failed: " + frame.ToHex());
                }

                // Exit here, can't do any other processing on the APRS channel
                return;
            }

            // If this frame comes from the locked channel, process it here.
            if ((frame.channel_id == activeChannelIdLock) && (activeStationLock != null))
            {
                if (activeStationLock.StationType == StationInfoClass.StationTypes.Winlink)
                {
                    AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                    if (p == null) return;
                    if (p.type == FrameType.U_FRAME_UI)
                    {
                        // Have the Winlink client process this frame as a un-numbered frame
                        //winlinkClient.ProcessFrame(frame, p);
                    }
                    else
                    {
                        // Have the AX.25 session process this packet
                        if (p.addresses[0].CallSignWithId == callsign + "-" + stationId) { session.Receive(p); }
                    }
                    return;
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.BBS)
                {
                    AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                    if (p == null) return;
                    if (p.type == FrameType.U_FRAME_UI)
                    {
                        // Have the BBS process this frame as a un-numbered frame
                        bbs.ProcessFrame(frame, p);
                    }
                    else
                    {
                        // Have the AX.25 session process this packet
                        if (p.addresses[0].CallSignWithId == callsign + "-" + stationId) { session.Receive(p); }
                    }
                    return;
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.Torrent)
                {
                    AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                    if (p == null) return;
                    if (p.type == FrameType.U_FRAME_UI)
                    {
                        // Have the torrent, process this frame as a un-numbered frame
                        torrent.ProcessFrame(frame, p);
                    }
                    return;
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal)
                {
                    // Have the terminal process this frame
                    if ((activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25) || (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25Compress))
                    {
                        AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                        if ((p != null) && (p.addresses[0].CallSignWithId == callsign + "-" + stationId))
                        {
                            if (p == null)
                            {
                                DebugTrace("Terminal Raw AX.25 decode failed: " + frame.ToHex());
                            }
                            else if (p.addresses.Count < 2)
                            {
                                DebugTrace("Terminal Raw AX.25 decode failed, less than 2 addresses: " + frame.ToHex());
                            }
                            else
                            {
                                string dataStr = p.dataStr;
                                if (p.pid == 242) { try { dataStr = UTF8Encoding.Default.GetString(Utils.DecompressBrotli(p.data)); } catch (Exception) { } }
                                if (p.pid == 243) { try { dataStr = UTF8Encoding.Default.GetString(Utils.DecompressDeflate(p.data)); } catch (Exception) { } }
                                terminalTabUserControl.AppendTerminalString(false, p.addresses[1].ToString(), p.addresses[0].CallSignWithId, dataStr);
                            }
                        }
                        return;
                    }
                    else if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.APRS)
                    {
                        // Have APRS process this frame
                        AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                        if (p == null)
                        {
                            DebugTrace("Terminal Raw AX.25 decode failed: " + frame.ToHex());
                        }
                        else if (p.addresses.Count != 2)
                        {
                            DebugTrace("Terminal Raw AX.25 decode failed, less than 2 addresses: " + frame.ToHex());
                        }
                        else
                        {
                            AprsPacket aprsPacket = AprsPacket.Parse(p);
                            if (aprsPacket == null) return;
                            if (aprsStack.ProcessIncoming(aprsPacket) == false) return;
                            if ((aprsPacket.MessageData.Addressee == callsign + "-" + stationId) || (aprsPacket.MessageData.Addressee == callsign)) // Check if this packet is for us
                            {
                                if ((aprsPacket.DataType == PacketDataType.Message) && (aprsPacket.MessageData.MsgType == MessageType.mtGeneral) && (aprsPacket.MessageData.MsgText.Length > 0))
                                {
                                    terminalTabUserControl.AppendTerminalString(false, p.addresses[1].ToString(), p.addresses[0].CallSignWithId, aprsPacket.MessageData.MsgText);
                                }
                            }
                        }
                        return;
                    }
                    else if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.X25Session)
                    {
                        AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                        if ((p != null) && (p.addresses[0].CallSignWithId == callsign + "-" + stationId)) { session.Receive(p); }
                        return;
                    }
                }
                else if (activeStationLock.StationType == StationInfoClass.StationTypes.AGWPE)
                {
                    if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.X25Session)
                    {
                        AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                        if ((p != null) && (p.addresses[0].CallSignWithId == session.SessionCallsign + "-" + session.SessionStationId)) { session.Receive(p); }
                        return;
                    }
                }
            }

            if (sender != null)
            {
                // If this is a AX.25 disconnection frame sent at us and we are already not connected, just ack
                AX25Packet px = AX25Packet.DecodeAX25Packet(frame);
                if ((px != null) && (px.addresses.Count >= 2) && (px.addresses[0].CallSignWithId == callsign + "-" + stationId) && (px.type == FrameType.U_FRAME_DISC))
                {
                    List<AX25Address> addresses = new List<AX25Address>();
                    addresses.Add(AX25Address.GetAddress(px.addresses[1].ToString()));
                    addresses.Add(AX25Address.GetAddress(callsign, stationId));
                    AX25Packet response = new AX25Packet(addresses, 0, 0, true, true, FrameType.U_FRAME_UA, null);
                }
                else if ((activeStationLock == null) && (agwpeServer != null) && (agwpeServer.GetRegisteredClientCount() > 0))
                {
                    // Check if a packet initiated a AGWPE connection
                    if ((px != null) && ((px.type == FrameType.U_FRAME_SABM) || (px.type == FrameType.U_FRAME_SABME)))
                    {
                        Guid? clientid = agwpeServer.GetClientIdByCallsign(px.addresses[0].CallSignWithId);
                        if ((clientid != null) && (clientid != Guid.Empty))
                        {
                            agwpeServer.SessionFrom = px.addresses[0].CallSignWithId;
                            agwpeServer.SessionTo = px.addresses[1].CallSignWithId;

                            activeChannelIdLock = px.channel_id;
                            StationInfoClass station = new StationInfoClass();
                            station.WaitForConnection = true;
                            station.StationType = StationInfoClass.StationTypes.AGWPE;
                            station.TerminalProtocol = StationInfoClass.TerminalProtocols.X25Session;
                            station.AgwpeClientId = (Guid)clientid;
                            activeStationLock = station;
                            UpdateInfo();
                            //UpdateRadioDisplay();

                            DebugTrace("AGWPE connection initiated by " + px.addresses[0].CallSignWithId);
                            session.CallSignOverride = px.addresses[0].address;
                            session.StationIdOverride = px.addresses[0].SSID;
                            session.Receive(px);
                        }
                    }
                }
            }
        }

        private delegate void RadioInfoUpdateHandler(Radio sender, Radio.RadioUpdateNotification msg);

        private void Radio_InfoUpdate(Radio sender, Radio.RadioUpdateNotification msg)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new RadioInfoUpdateHandler(Radio_InfoUpdate), sender, msg); return; }
            try
            {
                switch (msg)
                {
                    case Radio.RadioUpdateNotification.State:
                        switch (radio.State)
                        {
                            case Radio.RadioState.Connected:
                                if (webserver != null) { webserver.BroadcastString("connected"); }
                                connectToolStripMenuItem.Enabled = false;
                                disconnectToolStripMenuItem.Enabled = true;
                                //radioStateLabel.Text = "Connected";
                                channelControls = new RadioChannelControl[radio.Info.channel_count];
                                vfo2LastChannelId = -1;
                                if (registry.ReadInt("Audio", 0) == 1) { radio.AudioEnabled(true); }
                                radioVolumeForm.UpdateInfo();
                                if (allowTransmit) { microphone.StartListening(); }

                                // Set the radio image
                                int radioImage = 0;
                                if ((radio.Info.vendor_id == 6) && (radio.Info.product_id == 260)) { radioImage = 0; } // BTECH UV-Pro
                                if ((radio.Info.vendor_id == 1) && (radio.Info.product_id == 261)) { radioImage = 1; } // Vero VR-N75
                                SetRadioImage(radioImage);
                                break;
                            case Radio.RadioState.Disconnected:
                                if (webserver != null) { webserver.BroadcastString("disconnected"); }
                                connectToolStripMenuItem.Enabled = true;
                                disconnectToolStripMenuItem.Enabled = false;
                                //radioStateLabel.Text = "Disconnected";
                                //channelsFlowLayoutPanel.Controls.Clear();
                                //transmitBarPanel.Visible = false;
                                //rssiProgressBar.Visible = false;
                                ActiveLockToStation(null);
                                if (channelControls != null)
                                {
                                    for (int i = 0; i < channelControls.Length; i++) { if (channelControls[i] != null) { channelControls[i].Dispose(); channelControls[i] = null; } }
                                }
                                if (radioHtStatusForm != null) { radioHtStatusForm.Close(); radioHtStatusForm = null; }
                                if (radioSettingsForm != null) { radioSettingsForm.Close(); radioSettingsForm = null; }
                                if (radioBssSettingsForm != null) { radioBssSettingsForm.Close(); radioBssSettingsForm = null; }
                                if (radioChannelForm != null) { radioChannelForm.Close(); radioChannelForm = null; }
                                if (radioPositionForm != null) { radioPositionForm.Close(); radioPositionForm = null; }
                                radioVolumeForm.UpdateInfo();
                                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
                                microphone.StopListening();
                                break;
                            case Radio.RadioState.Connecting:
                                if (webserver != null) { webserver.BroadcastString("connecting"); }
                                //radioStateLabel.Text = "Connecting";
                                break;
                            case Radio.RadioState.MultiRadioSelect:
                                //radioStateLabel.Text = "Multiple Radios";
                                break;
                            case Radio.RadioState.UnableToConnect:
                                //radioStateLabel.Text = "Can't connect";
                                new CantConnectForm().ShowDialog(this);
                                break;
                            case Radio.RadioState.AccessDenied:
                                //radioStateLabel.Text = "Access Denied";
                                new BTAccessDeniedForm().ShowDialog(this);
                                break;
                            case Radio.RadioState.BluetoothNotAvailable:
                                //radioStateLabel.Text = "No Bluetooth";
                                break;
                            case Radio.RadioState.NotRadioFound:
                                //radioStateLabel.Text = "No Radio Found";
                                break;
                        }

                        UpdateInfo();
                        break;
                    case Radio.RadioUpdateNotification.ChannelInfo:
                        if (radio.Channels != null)
                        {
                            //UpdateChannelsPanel();
                            CheckAprsChannel();
                            //UpdateRadioDisplay();
                            UpdateInfo();
                        }
                        break;
                    case Radio.RadioUpdateNotification.BatteryAsPercentage:
                        batteryToolStripStatusLabel.Text = "Battery " + radio.BatteryAsPercentage + "%";
                        batteryToolStripStatusLabel.Visible = true;
                        break;
                    case Radio.RadioUpdateNotification.HtStatus:
                        if (radio.HtStatus == null) break;
                        //rssiProgressBar.Visible = radio.HtStatus.is_in_rx;
                        //rssiProgressBar.Value = radio.HtStatus.rssi;
                        //transmitBarPanel.Visible = radio.HtStatus.is_in_tx;
                        if (radioHtStatusForm != null) { radioHtStatusForm.UpdateInfo(); }
                        radioStatusToolStripMenuItem.Enabled = true;
                        //UpdateRadioDisplay();
                        setupRegionMenu();
                        break;
                    case Radio.RadioUpdateNotification.Settings:
                        if (radioSettingsForm != null) { radioSettingsForm.UpdateInfo(); }
                        radioSettingsToolStripMenuItem.Enabled = true;
                        dualWatchToolStripMenuItem.Checked = (radio.Settings.double_channel == 1);
                        scanToolStripMenuItem.Checked = radio.Settings.scan;
                        if ((activeStationLock != null) && (activeChannelIdLock != radio.Settings.channel_a)) { ActiveLockToStation(null); } // Check lock/unlock
                        //UpdateRadioDisplay();
                        setupRegionMenu();
                        radioVolumeForm.UpdateInfo();
                        break;
                    case Radio.RadioUpdateNotification.BssSettings:
                        if (radioSettingsForm != null) { radioBssSettingsForm.UpdateInfo(); }
                        radioBSSSettingsToolStripMenuItem.Enabled = true;
                        UpdateInfo();
                        break;
                    case Radio.RadioUpdateNotification.Volume:
                        radioVolumeForm.Volume = radio.Volume;
                        break;
                    case Radio.RadioUpdateNotification.RegionChange:
                        if (channelControls != null)
                        {
                            for (int i = 0; i < channelControls.Length; i++) { if (channelControls[i] != null) { channelControls[i].Dispose(); channelControls[i] = null; } }
                        }
                        break;
                }
            }
            catch (Exception ex)
            {
                Program.ExceptionSink(this, ex);
            }
        }

        public void DebugTrace(string msg)
        {
            Program.BlockBoxEvent(msg);
            try { debugTabUserControl.AppendText(msg); } catch (Exception) { }
            if (debugFile != null)
            {
                byte[] buf = UTF8Encoding.UTF8.GetBytes(DateTime.Now.ToString() + ": " + msg + Environment.NewLine);
                try { debugFile.Write(buf, 0, buf.Length); } catch (Exception) { }
            }
            if (webserver != null) { webserver.BroadcastString("log:" + msg); }
        }

        private void Radio_DebugMessage(Radio sender, string msg)
        {
            try
            {
                if (this.InvokeRequired) { this.BeginInvoke(new Action(() => { Radio_DebugMessage(sender, msg); })); return; }
                DebugTrace(msg);
            }
            catch (Exception) { }
        }

        public void Debug(string msg)
        {
            try
            {
                if (this.InvokeRequired) { this.BeginInvoke(new Action(() => { Debug(msg); })); return; }
                DebugTrace(msg);
            }
            catch (Exception) { }
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e)
        {
            RealExit = true;
            this.Close();
            //Application.Exit();
            //Process.GetCurrentProcess().Kill(); // Force exit
        }

        public void connectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (devices == null || devices.Length == 0) return;
            if (devices.Length == 1)
            {
                // Connect to the only device found
                radio.Connect(devices[0].mac);
            }
            else
            {
                // Have the user select a device to connect to
                RadioSelectorForm selectorForm = new RadioSelectorForm(this);
                if (selectorForm.ShowDialog(this) == DialogResult.OK)
                {
                    radio.Connect(selectorForm.SelectedMac);
                    launchAnotherInstanceToolStripMenuItem.Visible = true;
                }
            }
        }

        private void disconnectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radio.Disconnect();
        }

        private void radioInformationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            RadioInfoForm radioInfoForm = new RadioInfoForm(radio);
            radioInfoForm.ShowDialog();
        }

        private void batteryTimer_Tick(object sender, EventArgs e)
        {
            if (radio.State == Radio.RadioState.Connected) { radio.GetBatteryLevelAtPercentage(); }
        }

        private void radioStatusToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioHtStatusForm != null)
            {
                radioHtStatusForm.Focus();
            }
            else
            {
                radioHtStatusForm = new RadioHtStatusForm(this, radio);
                radioHtStatusForm.Show(this);
            }
        }

        public void ShowChannelDialog(int channelId)
        {
            if (radioChannelForm != null)
            {
                radioChannelForm.UpdateChannel(channelId);
                radioChannelForm.Focus();
            }
            else
            {
                radioChannelForm = new RadioChannelForm(this, radio, channelId);
                radioChannelForm.Show(this);
            }
        }

        private void radioSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioSettingsForm != null)
            {
                radioSettingsForm.UpdateInfo();
                radioSettingsForm.Focus();
            }
            else
            {
                radioSettingsForm = new RadioSettingsForm(this, radio);
                radioSettingsForm.Show(this);
            }
        }

        private void radioToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radioPanel.Visible = radioToolStripMenuItem.Checked;
            registry.WriteInt("ViewRadio", radioPanel.Visible ? 1 : 0);
        }

        private List<AX25Address> GetTransmitAprsRoute()
        {
            List<AX25Address> addresses = new List<AX25Address>(1);
            if (aprsRoutes.Count == 0)
            {
                addresses.Add(AX25Address.GetAddress("APN000", 0));
                addresses.Add(AX25Address.GetAddress(callsign, stationId));
                addresses.Add(AX25Address.GetAddress("WIDE1", 1));
                addresses.Add(AX25Address.GetAddress("WIDE2", 2));
                return addresses;
            }

            string routeKey = null;
            //routeKey = (string)aprsRouteComboBox.SelectedItem;
            if ((routeKey == null) || (aprsRoutes[routeKey] == null)) { routeKey = null; }
            if (routeKey == null) { routeKey = aprsRoutes.Keys.ElementAt(0); }
            List<AX25Address> route = aprsRoutes[routeKey];

            addresses.Add(route[0]);
            addresses.Add(AX25Address.GetAddress(callsign, stationId));
            if (route.Count > 1) { addresses.Add(route[1]); }
            if (route.Count > 2) { addresses.Add(route[2]); }
            if (route.Count > 3) { addresses.Add(route[3]); }
            return addresses;
        }

        public void AddAprsPacket(AX25Packet packet, bool sender)
        {
            string MessageId = null;
            string MessageText = null;
            PacketDataType MessageType = PacketDataType.Message;
            String RoutingString = null;
            String SenderCallsign = null;
            AX25Address SenderAddr = null;
            int ImageIndex = -1;
            AprsPacket aprsPacket = null;
            if ((packet.addresses != null) && (packet.addresses.Count >= 2))
            {
                aprsPacket = AprsPacket.Parse(packet);
                if (aprsPacket == null) return;

                if (sender == false)
                {
                    SenderAddr = packet.addresses[1];
                    RoutingString = SenderAddr.ToString();
                    SenderCallsign = SenderAddr.CallSignWithId;
                    if ((aprsPacket.Position != null) && (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) && (aprsPacket.Position.CoordinateSet.Longitude.Value != 0)) { ImageIndex = 3; }
                }

                // Perform authentication check if needed
                if (packet.authState == AuthState.Unknown) { packet.authState = AprsParser.AprsAuth.checkAprsAuth(stations, sender, sender ? (callsign + "-" + stationId) : SenderCallsign, packet.dataStr, packet.time); }

                if ((sender == false) && (aprsStack.ProcessIncoming(aprsPacket) == false)) return;
                MessageType = aprsPacket.DataType;
                if (aprsPacket.DataType == PacketDataType.Message)
                {
                    bool forSelf = ((aprsPacket.MessageData.Addressee == callsign) || (aprsPacket.MessageData.Addressee == callsign + "-" + stationId));

                    if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtAck)
                    {
                        if (forSelf)
                        {
                            /*
                            // Look at a message to ack
                            foreach (ChatMessage n in aprsChatControl.Messages)
                            {
                                if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId))
                                {
                                    if ((n.AuthState == AuthState.Unknown) || ((n.AuthState == AuthState.Success) && (aprsPacket.Packet.authState == AuthState.Success)) || ((n.AuthState == AuthState.None) && (aprsPacket.Packet.authState == AuthState.None))) { n.ImageIndex = 0; }
                                }
                            }
                            */
                        }
                        return;
                    }
                    else if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtRej)
                    {
                        if (forSelf)
                        {
                            /*
                            // Look at a message to reject
                            foreach (ChatMessage n in aprsChatControl.Messages)
                            {
                                if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId))
                                {
                                    if ((n.AuthState == AuthState.Unknown) || ((n.AuthState == AuthState.Success) && (aprsPacket.Packet.authState == AuthState.Success)) || ((n.AuthState == AuthState.None) && (aprsPacket.Packet.authState == AuthState.None))) { n.ImageIndex = 1; }
                                }
                            }
                            */
                        }
                        return;
                    }

                    // Normal message processing
                    if (sender)
                    {
                        RoutingString = "→ " + aprsPacket.MessageData.Addressee;
                        if (packet.authState == AuthState.Success) { RoutingString += " ✓"; }
                        if (packet.authState == AuthState.Failed) { RoutingString += " ❌"; }
                    }
                    else
                    {
                        if ((SenderAddr.address == aprsPacket.MessageData.Addressee) || (SenderAddr.CallSignWithId == aprsPacket.MessageData.Addressee))
                        {
                            // The sender and destination are the same, no need to show details.
                            RoutingString = aprsPacket.MessageData.Addressee;
                        }
                        else
                        {
                            // Show both sender and destination
                            RoutingString = SenderCallsign + " → " + aprsPacket.MessageData.Addressee;
                        }
                        if (packet.authState == AuthState.Success) { RoutingString += " ✓"; }
                        if (packet.authState == AuthState.Failed) { RoutingString += " ❌"; }
                    }
                    MessageId = aprsPacket.MessageData.SeqId;
                    MessageText = aprsPacket.MessageData.MsgText;

                    // If this is a SMS message, do more processing to make it look good
                    if ((aprsPacket.MessageData.Addressee == "SMS") && (aprsPacket.MessageData.MsgText.Length > 12) && (aprsPacket.MessageData.MsgText[0] == '@'))
                    {
                        int i = aprsPacket.MessageData.MsgText.IndexOf(" ");
                        if (i >= 0)
                        {
                            RoutingString = "→ SMS: " + aprsPacket.MessageData.MsgText.Substring(1, i);
                            MessageId = aprsPacket.MessageData.SeqId;
                            MessageText = aprsPacket.MessageData.MsgText.Substring(i + 1);
                        }
                    }

                    // Check if we already got this exact message before
                    if (MessageId != null)
                    {
                        /*
                        foreach (ChatMessage n in aprsChatControl.Messages)
                        {
                            // If this is a duplicate, don't display it.
                            if ((n.MessageId == MessageId) && (n.Route == RoutingString) && (n.Message == MessageText)) return;
                        }
                        */
                    }
                }
                else
                {
                    if ((aprsPacket.Comment != null) && ((aprsPacket.DataType != PacketDataType.MicE) && (aprsPacket.DataType != PacketDataType.MicECurrent) && (aprsPacket.DataType != PacketDataType.MicEOld)))
                    {
                        // This is not a message
                        MessageText = aprsPacket.Comment;
                    }
                }
            }
            if ((packet.addresses != null) && (packet.addresses.Count == 1))
            {
                AX25Address addr = packet.addresses[0];
                SenderCallsign = RoutingString = addr.ToString();
                MessageText = packet.dataStr;
            }

            if ((MessageText != null) && (MessageText.Trim().Length > 0))
            {
                ChatMessage c = new ChatMessage(RoutingString, SenderCallsign, MessageText.Trim(), packet.time, sender, -1);
                c.Tag = packet;
                c.MessageId = MessageId;
                c.MessageType = MessageType;
                //c.Visible = showAllMessagesToolStripMenuItem.Checked || (c.MessageType == PacketDataType.Message);
                c.ImageIndex = ImageIndex;
                c.AuthState = packet.authState;

                /*
                // Check if we already got this message in the last 5 minutes
                // When starting up HTCommander, this packet may already be loaded, so we still process if the packet is the same content and the same time.
                foreach (ChatMessage chatMessage2 in aprsChatControl.Messages)
                {
                    AX25Packet packet2 = (AX25Packet)chatMessage2.Tag;
                    if ((c.Message == chatMessage2.Message) && (packet2.time.AddMinutes(5).CompareTo(packet.time) > 0) && (c.Time != packet2.time)) { return; }
                }

                // Add the message
                aprsChatControl.Messages.Add(c);
                if (c.Visible) { aprsChatControl.UpdateMessages(true); }
                */

                // If this is a directed message to us, we need to notify
                if ((aprsPacket.DataType == PacketDataType.Message) && ((aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtGeneral) || (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtAnnouncement) || (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtBulletin)) && (aprsPacket.MessageData.MsgText.Length > 0))
                {
                    if ((aprsPacket.MessageData.Addressee == callsign) || (aprsPacket.MessageData.Addressee == callsign + "-" + stationId))
                    {
                        if ((notifyIcon.Visible == true) && ((this.Visible == false) || (mainTabControl.SelectedIndex != 0)))
                        {
                            notifyIcon.BalloonTipText = aprsPacket.MessageData.MsgText;
                            notifyIcon.BalloonTipTitle = packet.addresses[1].ToString();
                            notifyIcon.ShowBalloonTip(10);
                        }
                    }
                }

                // Add or move the map marker
                if ((c.ImageIndex == 3) && (aprsPacket != null))
                {
                    c.Latitude = aprsPacket.Position.CoordinateSet.Latitude.Value;
                    c.Longitude = aprsPacket.Position.CoordinateSet.Longitude.Value;
                    //AddMapMarker(packet.addresses[1].CallSignWithId, aprsPacket.Position.CoordinateSet.Latitude.Value, aprsPacket.Position.CoordinateSet.Longitude.Value, packet.time);
                }
            }
        }

        private void aboutToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            new AboutForm().ShowDialog(this);
        }

        private void MailStore_MailsChanged(object sender, EventArgs e)
        {
            // Called when another instance of the application changes the mail store
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new EventHandler(MailStore_MailsChanged), sender, e);
                return;
            }
        }

        public void UpdateInfo()
        {
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.BeginInvoke(new Action(UpdateInfo)); return; }

            //radioStateLabel.Visible = (radio.State != Radio.RadioState.Connected);
            if (radio.State != Radio.RadioState.Connected)
            {
                //channelsFlowLayoutPanel.Visible = false;
                batteryToolStripStatusLabel.Visible = false;
            }
            //smSMessageToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            //weatherReportToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            //beaconSettingsToolStripMenuItem.Enabled = ((radio.State == Radio.RadioState.Connected) && (radio.BssSettings != null));
            audioEnabledToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            dualWatchToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            scanToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            exportChannelsToolStripMenuItem.Enabled = ((radio.State == Radio.RadioState.Connected) && (radio.Channels != null));
            // importChannelsToolStripMenuItem.Enabled = 
            //aprsDestinationComboBox.Enabled = (radio.State == Radio.RadioState.Connected) && (aprsChannel != -1);
            //aprsTextBox.Enabled = (radio.State == Radio.RadioState.Connected) && (aprsChannel != -1);
            //aprsSendButton.Enabled = (radio.State == Radio.RadioState.Connected) && (aprsChannel != -1);
            batteryTimer.Enabled = (radio.State == Radio.RadioState.Connected);
            //connectToolStripMenuItem.Enabled = connectButton.Visible = (radio.State != Radio.RadioState.Connected && radio.State != Radio.RadioState.Connecting && devices != null && devices.Length > 0);
            radioInformationToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            radioPositionToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected) && (radio.Info != null) && (radio.Info.soft_ver >= 133) && gPSEnabledToolStripMenuItem.Checked; // Check Version 0.8.5 or better
            radioStatusToolStripMenuItem.Enabled = ((radio.State == Radio.RadioState.Connected) && (radio.HtStatus != null));
            //if (radio.State != Radio.RadioState.Connected) { connectedPanel.Visible = false; }
            //exportStationsToolStripMenuItem.Enabled = (stations.Count > 0);
            //waitForConnectionToolStripMenuItem.Visible = allowTransmit;
            //waitForConnectionToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected) && allowTransmit && (activeStationLock == null);
            //toolStripMenuItem7.Visible = smSMessageToolStripMenuItem.Visible = weatherReportToolStripMenuItem.Visible = (allowTransmit && (aprsChannel != -1));
            //beaconSettingsToolStripMenuItem.Visible = (radio.State == Radio.RadioState.Connected) && allowTransmit;
            //aprsBottomPanel.Visible = allowTransmit;
            //newMailButton.Visible = mailConnectButton.Visible = allowTransmit;
            //terminalConnectButton.Visible = allowTransmit;
            //bbsConnectButton.Visible = allowTransmit;
            bBSToolStripMenuItem.Visible = allowTransmit;
            terminalToolStripMenuItem.Visible = allowTransmit;
            //if (radio.State != Radio.RadioState.Connected) cancelVoiceButton.Visible = false;

            // APRS Beacon
            if ((radio.State == Radio.RadioState.Connected) && (radio.BssSettings != null) && (radio.BssSettings.LocationShareInterval > 0) && (radio.BssSettings.PacketFormat == 1) && (radio.BssSettings.BeaconMessage.Trim().Length > 0))
            {
                //aprsTitleLabel.Text = "APRS - " + radio.BssSettings.BeaconMessage.Trim();
            }
            else
            {
                //aprsTitleLabel.Text = "APRS";
            }

            // APRS Routes
            //string selectedAprsRoute = aprsSelectedRoute;
            //if ((aprsSelectedRoute == null) && (aprsRouteComboBox.SelectedItem != null)) { selectedAprsRoute = (string)aprsRouteComboBox.SelectedItem; }
            //aprsRouteComboBox.Visible = ((aprsRoutes != null) && (aprsRoutes.Count > 1) && (allowTransmit));
            //aprsRouteComboBox.Items.Clear();
            //aprsRouteComboBox.Items.AddRange(aprsRoutes.Keys.ToArray());
            //aprsRouteComboBox.SelectedItem = selectedAprsRoute;
            //if (aprsRouteComboBox.SelectedIndex == -1) { aprsRouteComboBox.SelectedIndex = 0; }
            //aprsSelectedRoute = null;

            // Voice
            //voiceBottomPanel.Visible = allowTransmit;
            //speakButton.Enabled = speakTextBox.Enabled = true; // (radio.State == Radio.RadioState.Connected) && allowTransmit && (activeStationLock == null);

            // Terminal
            //terminalConnectButton.Enabled = (radio.State == Radio.RadioState.Connected) && ((activeStationLock == null) || (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal));
            //terminalConnectButton.Text = ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.Terminal)) ? "&Connect" : "&Disconnect";

            // BBS
            //bbsConnectButton.Enabled = (radio.State == Radio.RadioState.Connected) && ((activeStationLock == null) || (activeStationLock.StationType == StationInfoClass.StationTypes.BBS));
            //bbsConnectButton.Text = ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.BBS)) ? "&Activate" : "&Deactivate";

            // Mail
            //mailInternetButton.Enabled = !string.IsNullOrEmpty(callsign) && !string.IsNullOrEmpty(winlinkPassword);
            //mailConnectButton.Enabled = !string.IsNullOrEmpty(callsign) && !string.IsNullOrEmpty(winlinkPassword) && (radio.State == Radio.RadioState.Connected) && ((activeStationLock == null) || (activeStationLock.StationType == StationInfoClass.StationTypes.Winlink));
            //mailConnectButton.Text = ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.Winlink)) ? "&Connect" : "&Disconnect";

            // ActiveLockToStation
            //if ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.Terminal) || (string.IsNullOrEmpty(activeStationLock.Name))) { terminalTitleLabel.Text = "Terminal"; }
            //else { terminalTitleLabel.Text = "Terminal - " + activeStationLock.Name; }

            // Window title
            if ((callsign != null) && (callsign.Length >= 3))
            {
                this.Text = appTitle + " - " + callsign + ((stationId != 0) ? ("-" + stationId) : "");
            }
            else
            {
                this.Text = appTitle;
            }

            // Audio to Text
            //voiceEnableButton.Enabled = (radio.State == Radio.RadioState.Connected);
            //voiceEnableButton.Text = (radio.AudioToTextState) ? "Disable" : "Enable";

            // System Tray
            notifyIcon.Visible = systemTrayToolStripMenuItem.Checked;
            this.ShowInTaskbar = !systemTrayToolStripMenuItem.Checked;

            // Audio Controls
            radioVolumeForm.UpdateInfo();
        }

        private void settingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            ShowSettingsForm();
        }

        private void ShowSettingsForm(int tab = 0)
        {
            using (SettingsForm settingsForm = new SettingsForm())
            {
                if ((callsign != null) && (callsign.Length <= 6)) { settingsForm.CallSign = callsign; }
                if ((stationId >= 0) && (stationId <= 15)) { settingsForm.StationId = stationId; }
                settingsForm.AllowTransmit = allowTransmit;
                settingsForm.AprsRoutes = Utils.EncodeAprsRoutes(aprsRoutes);
                settingsForm.WinlinkPassword = winlinkPassword;
                settingsForm.WebServerEnabled = webServerEnabled;
                settingsForm.WebServerPort = webServerPort;
                settingsForm.AgwpeServerEnabled = agwpeServerEnabled;
                settingsForm.AgwpeServerPort = agwpeServerPort;
                settingsForm.VoiceLanguage = voiceLanguage;
                settingsForm.VoiceModel = voiceModel;
                settingsForm.Voice = voice;
                settingsForm.MoveToTab(tab);
                if (settingsForm.ShowDialog(this) == DialogResult.OK)
                {
                    // License Settings
                    callsign = settingsForm.CallSign;
                    stationId = settingsForm.StationId;
                    allowTransmit = settingsForm.AllowTransmit;
                    winlinkPassword = settingsForm.WinlinkPassword;
                    webServerEnabled = settingsForm.WebServerEnabled;
                    webServerPort = settingsForm.WebServerPort;
                    agwpeServerEnabled = settingsForm.AgwpeServerEnabled;
                    agwpeServerPort = settingsForm.AgwpeServerPort;
                    voiceLanguage = settingsForm.VoiceLanguage;
                    voiceModel = settingsForm.VoiceModel;
                    voice = settingsForm.Voice;
                    registry.WriteString("CallSign", callsign);
                    registry.WriteInt("StationId", stationId);
                    registry.WriteInt("AllowTransmit", allowTransmit ? 1 : 0);
                    registry.WriteInt("webServerEnabled", webServerEnabled ? 1 : 0);
                    registry.WriteInt("webServerPort", webServerPort);
                    registry.WriteInt("agwpeServerEnabled", agwpeServerEnabled ? 1 : 0);
                    registry.WriteInt("agwpeServerPort", agwpeServerPort);
                    registry.WriteString("VoiceLanguage", voiceLanguage);
                    registry.WriteString("VoiceModel", voiceModel);
                    registry.WriteString("Voice", voice);

                    // APRS Settings
                    string aprsRoutesStr = settingsForm.AprsRoutes;
                    registry.WriteString("AprsRoutes", aprsRoutesStr);
                    aprsRoutes = Utils.DecodeAprsRoutes(aprsRoutesStr);

                    // Winlink Settings
                    registry.WriteString("WinlinkPassword", winlinkPassword);

                    // Web Server
                    if ((webServerEnabled == false) && (webserver != null)) { webserver.Stop(); webserver = null; }
                    if ((webserver != null) && (webserver.port != webServerPort)) { webserver.Stop(); webserver = null; }
                    if ((webServerEnabled == true) && (webserver == null)) { webserver = new HttpsWebSocketServer(this, webServerPort); webserver.Start(); }
                    toolStripMenuItem2.Visible = localWebSiteToolStripMenuItem.Visible = (webserver != null);

                    // TNC Server
                    if ((agwpeServerEnabled == false) && (agwpeServer != null)) { agwpeServer.Stop(); agwpeServer = null; }
                    if ((agwpeServer != null) && (agwpeServer.Port != agwpeServerPort)) { agwpeServer.Stop(); agwpeServer = null; }
                    if ((agwpeServerEnabled == true) && (agwpeServer == null)) { agwpeServer = new AgwpeSocketServer(this, agwpeServerPort); agwpeServer.Start(); }

                    // Microphone
                    if (allowTransmit && (radio.State == RadioState.Connected)) { microphone.StartListening(); } else { microphone.StopListening(); }
                    radioVolumeForm.UpdateInfo();

                    CheckAprsChannel();
                    UpdateTabs();
                    UpdateInfo();
                }
            }
        }

        public void volumeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioVolumeForm.Visible == false) { radioVolumeForm.Show(this); }
            radioVolumeForm.Focus();
            radioVolumeForm.UpdateInfo();
        }

        private void audioClipsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioAudioClipsForm == null)
            {
                radioAudioClipsForm = new RadioAudioClipsForm(radio);
                radioAudioClipsForm.FormClosed += (s, args) => { radioAudioClipsForm = null; };
                radioAudioClipsForm.Show(this);
            } else {
                radioAudioClipsForm.Focus();
            }
        }

        public void ChangeChannelA(int channelId)
        {
            if ((activeChannelIdLock != -1) && (activeChannelIdLock != channelId)) return; // Currently locked
            radio.WriteSettings(radio.Settings.ToByteArray(channelId, radio.Settings.channel_b, radio.Settings.double_channel, radio.Settings.scan, radio.Settings.squelch_level));
        }

        public void ChangeChannelB(int channelId)
        {
            radio.WriteSettings(radio.Settings.ToByteArray(radio.Settings.channel_a, channelId, radio.Settings.double_channel, radio.Settings.scan, radio.Settings.squelch_level));
        }

        private void dualWatchToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radio.WriteSettings(radio.Settings.ToByteArray(radio.Settings.channel_a, radio.Settings.channel_b, (radio.Settings.double_channel == 1) ? 0 : 1, radio.Settings.scan, radio.Settings.squelch_level));
        }

        private void scanToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radio.WriteSettings(radio.Settings.ToByteArray(radio.Settings.channel_a, radio.Settings.channel_b, radio.Settings.double_channel, !radio.Settings.scan, radio.Settings.squelch_level));
        }

        private void mapToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void voiceToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void terminalToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void mailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void contactsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }
        private void bBSToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }
        private void packetsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }
        private void debugToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            UpdateTabs();
        }
        private void torrentToolStripMenuItem_Click(object sender, EventArgs e)
        {
            UpdateTabs();
        }

        private void UpdateTabs()
        {
            this.SuspendLayout();

            TabPage selectedTab = mainTabControl.SelectedTab;

            mainTabControl.TabPages.Clear();
            mainTabControl.TabPages.Add(aprsTabPage);
            if (mapToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(mapTabPage); }
            registry.WriteInt("ViewMap", mapToolStripMenuItem.Checked ? 1 : 0);
            if (voiceToolStripMenuItem.Checked && voiceToolStripMenuItem.Enabled)
            {
                mainTabControl.TabPages.Add(voiceTabPage);
            }
            if (mailToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(mailTabPage); }
            if (terminalToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(terminalTabPage); }
            if (contactsToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(addressesTabPage); }
            if (bBSToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(bbsTabPage); }
            if (torrentToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(torrentTabPage); }
            if (packetsToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(packetsTabPage); }
            if (debugToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(debugTabPage); }
            registry.WriteInt("ViewVoice", voiceToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewTerminal", terminalToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewMail", mailToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewContacts", contactsToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewBBS", bBSToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewTorrent", torrentToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewDebug", debugToolStripMenuItem.Checked ? 1 : 0);
            registry.WriteInt("ViewPackets", packetsToolStripMenuItem.Checked ? 1 : 0);

            if (mainTabControl.TabPages.Contains(selectedTab)) { mainTabControl.SelectedTab = selectedTab; }

            this.ResumeLayout();
        }


        private void checkBluetoothButton_Click(object sender, EventArgs e)
        {
            CheckBluetooth();
        }

        private void CheckAprsChannel()
        {
            if ((allowTransmit == false) || (radio.State != Radio.RadioState.Connected) || (radio.Channels == null) || (radio.AllChannelsLoaded() == false))
            {
                //aprsMissingChannelPanel.Visible = false;
                aprsChannel = -1;
                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
                return;
            }

            // Check if we have a APRS channel
            RadioChannelInfo channel = radio.GetChannelByName("APRS");
            if (channel != null)
            {
                //aprsMissingChannelPanel.Visible = false;
                aprsChannel = channel.channel_id;
                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
            }
            else
            {
                //aprsMissingChannelPanel.Visible = true;
                aprsChannel = -1;
            }
        }

        private void allChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            showAllChannels = !allChannelsToolStripMenuItem.Checked;
            registry.WriteInt("ShowAllChannels", showAllChannels ? 1 : 0);
            //UpdateChannelsPanel();
        }

        private void viewToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            allChannelsToolStripMenuItem.Checked = showAllChannels;
        }

        private void radioPanel_SizeChanged(object sender, EventArgs e)
        {
            //UpdateChannelsPanel();
        }

        private void setupRegionMenu()
        {
            if ((radio.State != Radio.RadioState.Connected) || (radio.Settings == null) || (radio.HtStatus == null))
            {
                regionToolStripMenuItem.Enabled = false;
                regionToolStripMenuItem.DropDownItems.Clear();
            }
            else
            {
                if (regionToolStripMenuItem.DropDownItems.Count == 0)
                {
                    for (int i = 0; i < radio.Info.region_count; i++)
                    {
                        ToolStripMenuItem item = new ToolStripMenuItem("Region " + (i + 1).ToString());
                        item.Tag = i;
                        item.Click += regionSelectToolStripMenuItem_Click;
                        regionToolStripMenuItem.DropDownItems.Add(item);
                    }
                }
                foreach (ToolStripMenuItem item in regionToolStripMenuItem.DropDownItems)
                {
                    item.Checked = ((int)item.Tag == radio.HtStatus.curr_region);
                }
                regionToolStripMenuItem.Enabled = true;
            }
        }

        private void regionSelectToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radio.HtStatus == null) return;
            ToolStripMenuItem item = (ToolStripMenuItem)sender;
            int region = (int)item.Tag;
            if (region == radio.HtStatus.curr_region) return;
            radio.SetRegion(region);
        }

        private void removeStationButton_Click(object sender, EventArgs e)
        {
            if (mainAddressBookListView.SelectedItems.Count == 0) return;
            if (MessageBox.Show(this, "Remove selected station?", "Stations", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK)
            {
                foreach (ListViewItem l in mainAddressBookListView.SelectedItems)
                {
                    StationInfoClass station = (StationInfoClass)l.Tag;
                    stations.Remove(station);
                }
                UpdateStations();
            }
        }

        private void addStationButton_Click(object sender, EventArgs e)
        {
            AddStationForm form = new AddStationForm(this);
            if (form.ShowDialog(this) == DialogResult.OK)
            {
                StationInfoClass station = form.SerializeToObject();
                stations.Add(station);
                UpdateStations();
            }
        }

        public void UpdateStations()
        {
            // Update the list of stations in the address book
            mainAddressBookListView.Items.Clear();
            foreach (StationInfoClass station in stations)
            {
                ListViewItem item = new ListViewItem(new string[] { station.CallsignNoZero, station.Name, station.Description });
                item.Group = mainAddressBookListView.Groups[(int)station.StationType];
                if (station.StationType == StationInfoClass.StationTypes.Generic) { item.ImageIndex = 7; }
                if (station.StationType == StationInfoClass.StationTypes.APRS) { item.ImageIndex = 3; }
                if (station.StationType == StationInfoClass.StationTypes.Terminal) { item.ImageIndex = 6; }
                if (station.StationType == StationInfoClass.StationTypes.Winlink) { item.ImageIndex = 8; }
                item.Tag = station;
                mainAddressBookListView.Items.Add(item);
            }

            // Write stations to the registry
            registry.WriteString("Stations", StationInfoClass.Serialize(stations));

            // Update APRS destinations list in APRS tab
            //aprsDestinationComboBox.Items.Clear();
            //aprsDestinationComboBox.Items.Add("ALL");
            //aprsDestinationComboBox.Items.Add("QST");
            //aprsDestinationComboBox.Items.Add("CQ");

            foreach (StationInfoClass station in stations)
            {
                //if (station.StationType == StationInfoClass.StationTypes.APRS) { aprsDestinationComboBox.Items.Add(station.Callsign); }
            }
        }

        private void mainAddressBookListView_DoubleClick(object sender, EventArgs e)
        {
            if (mainAddressBookListView.SelectedItems.Count != 1) return;
            StationInfoClass station = (StationInfoClass)mainAddressBookListView.SelectedItems[0].Tag;
            AddStationForm form = new AddStationForm(this);
            form.DeserializeFromObject(station);
            if (form.ShowDialog(this) == DialogResult.OK)
            {
                station = form.SerializeToObject();
                foreach (ListViewItem l in mainAddressBookListView.Items)
                {
                    StationInfoClass station2 = (StationInfoClass)l.Tag;
                    if ((station2.Callsign == station.Callsign) && (station2.StationType == station.StationType))
                    {
                        stations.Remove(station2);
                    }
                }
                stations.Add(station);

                if ((activeStationLock != null) && (activeStationLock.StationType == station.StationType) && (activeStationLock.Callsign == station.Callsign))
                {
                    ActiveLockToStation(station);
                }

                UpdateStations();
            }
        }

        private void stationsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            stationsMenuPictureBox.ContextMenuStrip.Show(stationsMenuPictureBox, new Point(e.X, e.Y));
        }

        public bool ActiveLockToStation(StationInfoClass station, int channelIdLock = -1)
        {
            if (this.InvokeRequired) { return (bool)this.Invoke(new Func<StationInfoClass, int, bool>(ActiveLockToStation), station, channelIdLock); }

            if (station == null)
            {
                radio.SetNextFreeChannelTime(DateTime.MaxValue);
                if (session.CurrentState == AX25Session.ConnectionState.CONNECTED)
                {
                    session.Disconnect();
                    return false;
                }
                else
                {
                    torrent.Activate(false);
                    if (activeStationsLock_oldSettings != null) { radio.WriteSettings(activeStationsLock_oldSettings); }
                    activeStationsLock_oldSettings = null;
                    if ((activeStationLock != null) && activeStationLock.WaitForConnection && (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal)) { terminalTabUserControl.AppendTerminalString(false, null, null, "Stopped."); }
                    activeStationLock = null;
                    activeChannelIdLock = -1;
                    
                    // Reset YAPP state when disconnecting
                    yappTransfer?.Reset();
                    
                    UpdateInfo();
                    //UpdateRadioDisplay();
                    return true;
                }
            }

            if (station.StationType == StationInfoClass.StationTypes.Generic) return false;
            if ((station.Channel == null) && (channelIdLock == -1)) return false;
            if (radio.Channels == null) return false;

            if (channelIdLock == -1)
            {
                foreach (var channel in radio.Channels)
                {
                    if ((channel != null) && (channel.name_str == station.Channel)) { channelIdLock = channel.channel_id; }
                }
            }
            if (channelIdLock == -1)
            {
                MessageBox.Show(this, "Unable to change to channel \"" + station.Channel + "\".", "Terminal", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            if (station.StationType != StationInfoClass.StationTypes.AGWPE)
            {
                session.CallSignOverride = null;
                session.StationIdOverride = -1;
            }
            activeStationLock = station;
            activeChannelIdLock = channelIdLock;

            // Store the old settings
            activeStationsLock_oldSettings = radio.Settings.ToByteArray();

            // Change to the new channel A and stop scan and dual view.
            radio.WriteSettings(radio.Settings.ToByteArray(activeChannelIdLock, radio.Settings.channel_b, 0, false, radio.Settings.squelch_level));

            UpdateInfo();
            //UpdateRadioDisplay();

            if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.X25Session)
            {
                List<AX25Address> addresses = new List<AX25Address>();
                addresses.Add(AX25Address.GetAddress(station.Callsign));
                addresses.Add(AX25Address.GetAddress(session.SessionCallsign, session.SessionStationId));
                session.Connect(addresses);
                
                // Start YAPP receive mode for terminal sessions
                string downloadPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "HTCommander Downloads");
                yappTransfer?.StartReceiveMode(downloadPath);
            }

            if (activeStationLock.StationType == StationInfoClass.StationTypes.Torrent)
            {
                torrent.Activate(true);
            }

            return true;
        }

        private void exportChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((radio.State != RadioState.Connected) || (radio.Channels == null)) return;
            if (exportChannelsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                ChannelImport.WriteChannelsToFile(radio.Channels, exportChannelsFileDialog.FileName, exportChannelsFileDialog.FilterIndex);
            }
        }

        public void importChannels(string filename)
        {
            // If there are decoded import channels, open a dialog box to merge them.
            List<RadioChannelInfo> importChannels;
            try {
                importChannels = ChannelImport.DecodeChannelsFile(filename);
            } catch (Exception ex) { MessageBox.Show(this, ex.ToString(), "File Error"); return; }
            if (importChannels.Count == 0) return;
            ImportChannelsForm f = new ImportChannelsForm(null, importChannels.ToArray());
            f.Text = f.Text + " - " + new FileInfo(filename).Name;
            f.Show(this);
        }

        private void importChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //if ((radio.State != RadioState.Connected) || (radio.Channels == null)) return;
            if (importChannelFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                importChannels(importChannelFileDialog.FileName);
            }
        }

        public delegate void UpdateBbsStatsHandler(BBS.StationStats stats);

        public void UpdateBbsStats(BBS.StationStats stats)
        {
            bbsTabUserControl.UpdateBbsStats(stats);
        }

        public delegate void AddBbsTrafficHandler(string callsign, bool outgoing, string text);
        public void AddBbsTraffic(string callsign, bool outgoing, string text)
        {
            bbsTabUserControl.AddBbsTraffic(callsign, outgoing, text);
        }

        public delegate void AddBbsControlMessageHandler(string text);
        public void AddBbsControlMessage(string text)
        {
            bbsTabUserControl.AddBbsControlMessage(text);
        }

        public delegate void MailStateMessageHandler(string msg);
        public void MailStateMessage(string msg)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new MailStateMessageHandler(MailStateMessage), msg); return; }
            //mailTransferStatusPanel.Visible = (msg != null);
            //if (msg != null) { mailTransferStatusLabel.Text = msg; } else { mailTransferStatusLabel.Text = ""; }
        }

        private void exitToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            RealExit = true;
            this.Close();
            //Application.Exit();
            //Process.GetCurrentProcess().Kill(); // Force exit

        }

        private void notifyIcon_MouseClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                if (this.Visible == false) { this.Visible = true; this.Focus(); }
                else { this.Visible = false; }
            }
        }

        private void systemTrayToolStripMenuItem_Click(object sender, EventArgs e)
        {
            registry.WriteInt("SystemTray", systemTrayToolStripMenuItem.Checked ? 1 : 0);
            UpdateInfo();
        }

        private void notifyIcon_BalloonTipClicked(object sender, EventArgs e)
        {
            mainTabControl.SelectedIndex = 0;
            if (this.Visible == false) { this.Visible = true; this.Focus(); }
        }

        private void radioBSSSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioBssSettingsForm != null)
            {
                radioBssSettingsForm.UpdateInfo();
                radioBssSettingsForm.Focus();
            }
            else
            {
                radioBssSettingsForm = new RadioBssSettingsForm(this, radio);
                radioBssSettingsForm.Show(this);
            }
        }

        private void MainForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if ((systemTrayToolStripMenuItem.Checked) && (RealExit == false))
            {
                e.Cancel = true;
                this.Visible = false;
            }
            else
            {
                e.Cancel = false;
                if (AprsFile != null)
                {
                    AprsFile.Flush();
                    AprsFile.Close();
                    AprsFile = null;
                }
            }
        }

        private void showToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new MethodInvoker(() => showToolStripMenuItem_Click(sender, e))); return; }
            if (this.Visible == false) { this.Visible = true; this.Focus(); }
        }

        private void hideToolStripMenuItem_Click(object sender, EventArgs e)
        {
            this.Visible = false;
        }

        private void notifyContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            showToolStripMenuItem.Visible = (this.Visible == false);
            hideToolStripMenuItem.Visible = (this.Visible == true);
        }

        private void radioPictureBox_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else if ((files.Length == 1) && (files[0].ToLower().EndsWith(".wav") && allowTransmit && (radio.State == RadioState.Connected)))
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else
                {
                    e.Effect = DragDropEffects.None;
                }
            }
        }

        private void radioPictureBox_DragDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if ((files.Length == 1) && (files[0].ToLower().EndsWith(".csv")))
                {
                    importChannels(files[0]);
                }
                else if ((files.Length == 1) && (files[0].ToLower().EndsWith(".wav")))
                {
                    // Transmit the wav file
                    using (var reader = new WaveFileReader(files[0]))
                    {
                        var buffer = new byte[reader.Length];
                        int bytesRead = reader.Read(buffer, 0, buffer.Length);
                        radio.TransmitVoice(buffer, 0, bytesRead, true);
                    }
                }
            }
        }

        private void AddTorrent(TorrentFile torrentFile)
        {
            /*
            ListViewItem l = new ListViewItem(new string[] { torrentFile.FileName, torrentFile.Mode.ToString(), torrentFile.Description });
            l.ImageIndex = torrentFile.Completed ? 9 : 10;

            string groupName = torrentFile.Callsign;
            if (torrentFile.StationId > 0) groupName += "-" + torrentFile.StationId;
            ListViewGroup group = null;
            foreach (ListViewGroup g in torrentListView.Groups)
            {
                if (g.Header == groupName) { group = g; break; }
            }
            if (group == null)
            {
                group = new ListViewGroup(groupName);
                torrentListView.Groups.Add(group);
            }
            l.Group = group;
            l.Tag = torrentFile;
            torrentFile.ListViewItem = l;
            torrentListView.Items.Add(l);
            torrent.Add(torrentFile);
            torrentFile.WriteTorrentFile();
            */
        }

        public delegate void UpdateTorrentHandler(TorrentFile file);
        public void updateTorrent(TorrentFile file)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new UpdateTorrentHandler(updateTorrent), file); return; }

            // Update a single torrent file
            if (file.ListViewItem != null)
            {
                file.ListViewItem.SubItems[0].Text = (file.FileName == null) ? "" : file.FileName;
                file.ListViewItem.SubItems[1].Text = file.Mode.ToString();
                file.ListViewItem.SubItems[2].Text = (file.Description == null) ? "" : file.Description;
                file.ListViewItem.ImageIndex = file.Completed ? 9 : 10;
                /*
                if ((torrentListView.SelectedItems.Count == 1) && (torrentListView.SelectedItems[0] == file.ListViewItem))
                {
                    torrentListView_SelectedIndexChanged(null, null);
                }
                */
            }
            else
            {
                AddTorrent(file);
            }
        }

        public void updateTorrentList()
        {
            if (this.InvokeRequired) { this.BeginInvoke(new MethodInvoker(updateTorrentList)); return; }

            // Update the entire torrent list
            foreach (TorrentFile file in torrent.Files) { updateTorrent(file); }
        }

        private void settingsToolStripMenuItem1_DropDownOpening(object sender, EventArgs e)
        {
            if (radio.State == RadioState.Connected)
            {
                audioEnabledToolStripMenuItem.Checked = radio.AudioState;
                radioVolumeForm.UpdateInfo();
            }
        }

        private void audioEnabledToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool newAudioState = !audioEnabledToolStripMenuItem.Checked;
            audioEnabledToolStripMenuItem.Checked = newAudioState;
            radio.AudioEnabled(newAudioState);
            registry.WriteInt("Audio", newAudioState ? 1 : 0);
            UpdateInfo();
            radioVolumeForm.SetAudio(newAudioState);
            if (radioAudioClipsForm != null) { radioAudioClipsForm.UpdateUI(); }
            //UpdateGpsStatusDisplay();
        }

        private void checkForUpdatesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            registry.WriteInt("CheckForUpdates", checkForUpdatesToolStripMenuItem.Checked ? 1 : 0);

            // Check for updates
            if (checkForUpdatesToolStripMenuItem.Checked)
            {
                registry.WriteString("LastUpdateCheck", DateTime.Now.ToString());
                SelfUpdateForm.CheckForUpdate(this);
            }
        }

        private void radioPictureBox_Click(object sender, EventArgs e)
        {
            volumeToolStripMenuItem_Click(this, null);
        }

        private void spectrogramToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (spectrogramForm != null)
            {
                spectrogramForm.Focus();
            }
            else
            {
                spectrogramForm = new SpectrogramForm(this);
                spectrogramForm.Show(this);
            }
        }

        public void showAudioGraph(bool input)
        {
            if (spectrogramForm != null)
            {
                spectrogramForm.Focus();
                spectrogramForm.SetGraphMicrophone(input);
            }
            else
            {
                spectrogramForm = new SpectrogramForm(this);
                spectrogramForm.Show(this);
                spectrogramForm.SetGraphMicrophone(input);
            }
        }

        public void radioPositionToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioPositionForm != null)
            {
                radioPositionForm.Focus();
            }
            else
            {
                if (gPSEnabledToolStripMenuItem.Checked)
                {
                    radioPositionForm = new RadioPositionForm(this, radio);
                    radioPositionForm.Show(this);
                }
            }
        }

        private void gPSEnabledToolStripMenuItem_Click(object sender, EventArgs e)
        {
            registry.WriteInt("GpsEnabled", gPSEnabledToolStripMenuItem.Checked ? 1 : 0);
            radio.GpsEnabled(gPSEnabledToolStripMenuItem.Checked);
            if ((radioPositionForm != null) && (gPSEnabledToolStripMenuItem.Checked == false)) { radioPositionForm.Close(); }
            //UpdateGpsStatusDisplay();
            UpdateInfo();

            if (gPSEnabledToolStripMenuItem.Checked == false)
            {
                // Remove self location
                //GMapMarker selfMarker = null;
                //foreach (GMapMarker m in mapMarkersOverlay.Markers) { if (m.ToolTipText == "Self") { selfMarker = m; } }
                //if (selfMarker != null) { mapMarkersOverlay.Markers.Remove(selfMarker); }
                //centerToGpsButton.Enabled = centerToGPSToolStripMenuItem.Enabled = false;
            }
        }

        private void launchAnotherInstanceToolStripMenuItem_Click(object sender, EventArgs e)
        {
            try
            {
                Process.Start(Application.ExecutablePath, "-multiinstance");
            }
            catch (Exception ex)
            {
                MessageBox.Show("Failed to start new instance: " + ex.Message);
            }
        }
        private void localWebSiteToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (webserver != null) { Process.Start("http://localhost:" + webServerPort); }
        }

        private void SoftwareModem_Click(object sender, EventArgs e)
        {
            ToolStripMenuItem clickedItem = sender as ToolStripMenuItem;
            if (clickedItem == null) return;

            // Determine which mode was selected
            RadioAudio.SoftwareModemModeType newMode = RadioAudio.SoftwareModemModeType.Disabled;
            
            if (clickedItem == disabledToolStripMenuItem)
                newMode = RadioAudio.SoftwareModemModeType.Disabled;
            else if (clickedItem == aFK1200ToolStripMenuItem)
                newMode = RadioAudio.SoftwareModemModeType.Afsk1200;
            else if (clickedItem == pSK2400ToolStripMenuItem)
                newMode = RadioAudio.SoftwareModemModeType.Psk2400;
            else if (clickedItem == pSK4800ToolStripMenuItem)
                newMode = RadioAudio.SoftwareModemModeType.Psk4800;
            else if (clickedItem == g9600ToolStripMenuItem)
                newMode = RadioAudio.SoftwareModemModeType.G3RUH9600;

            // Update the menu checkmarks
            UpdateSoftwareModemMenu(newMode);

            // Save to registry
            registry.WriteInt("SoftwareModemMode", (int)newMode);

            // Apply to RadioAudio if available
            if (radio != null) { radio.SoftwareModemMode = newMode; }
            //UpdateGpsStatusDisplay();
        }

        private void UpdateSoftwareModemMenu(RadioAudio.SoftwareModemModeType mode)
        {
            // Uncheck all items first
            disabledToolStripMenuItem.Checked = false;
            aFK1200ToolStripMenuItem.Checked = false;
            pSK2400ToolStripMenuItem.Checked = false;
            pSK4800ToolStripMenuItem.Checked = false;
            g9600ToolStripMenuItem.Checked = false;

            // Check the selected item
            switch (mode)
            {
                case RadioAudio.SoftwareModemModeType.Disabled:
                    disabledToolStripMenuItem.Checked = true;
                    break;
                case RadioAudio.SoftwareModemModeType.Afsk1200:
                    aFK1200ToolStripMenuItem.Checked = true;
                    break;
                case RadioAudio.SoftwareModemModeType.Psk2400:
                    pSK2400ToolStripMenuItem.Checked = true;
                    break;
                case RadioAudio.SoftwareModemModeType.Psk4800:
                    pSK4800ToolStripMenuItem.Checked = true;
                    break;
                case RadioAudio.SoftwareModemModeType.G3RUH9600:
                    g9600ToolStripMenuItem.Checked = true;
                    break;
            }
        }

        private void terminalFileTransferCancelButton_Click(object sender, EventArgs e)
        {
            cancelFileTransfer();
        }

        private void cancelFileTransfer()
        {
            yappTransfer?.CancelTransfer();
        }

        public enum TerminalFileTransferStates
        {
            Idle,
            Sending,
            Receiving
        }

        public void updateTerminalFileTransferProgress(TerminalFileTransferStates state, string filename, int totalSize, int currentPosition)
        {
            /*
            if (InvokeRequired) { BeginInvoke(new Action<TerminalFileTransferStates, string, int, int>(updateTerminalFileTransferProgress), state, filename, totalSize, currentPosition); return; }
            terminalFileTransferProgressBar.Maximum = (totalSize > 0) ? totalSize : 1;
            terminalFileTransferProgressBar.Value = (Math.Min(currentPosition, terminalFileTransferProgressBar.Maximum));
            if (state == TerminalFileTransferStates.Sending)
            {
                terminalFileTransferStatusLabel.Text = "Sending: " + filename;
            }
            else if (state == TerminalFileTransferStates.Receiving)
            {
                terminalFileTransferStatusLabel.Text = "Receiving: " + filename;
            }
            else
            {
                terminalFileTransferStatusLabel.Text = "File Transfer";
            }
            //if ((terminalFileTransferPanel.Visible == false) && (state != TerminalFileTransferStates.Idle)) { terminalTextBox.ScrollToCaret(); }
            //terminalFileTransferPanel.Visible = (state != TerminalFileTransferStates.Idle);
            */
        }

        // YAPP event handlers
        private void YappTransfer_ProgressChanged(object sender, YappProgressEventArgs e)
        {
            updateTerminalFileTransferProgress(
                TerminalFileTransferStates.Receiving,
                e.Filename,
                (int)e.FileSize,
                (int)e.BytesTransferred
            );
        }

        private void YappTransfer_TransferComplete(object sender, YappCompleteEventArgs e)
        {
            updateTerminalFileTransferProgress(TerminalFileTransferStates.Idle, "", 0, 0);
        }

        private void YappTransfer_TransferError(object sender, YappErrorEventArgs e)
        {
            //AppendTerminalString(false, null, null, $"YAPP transfer error: {e.Error}");
            updateTerminalFileTransferProgress(TerminalFileTransferStates.Idle, "", 0, 0);
        }

    }
}
