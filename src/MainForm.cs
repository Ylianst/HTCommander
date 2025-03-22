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
using System.Windows.Forms;
using System.Globalization;
using System.Collections.Generic;
using aprsparser;
using static HTCommander.Radio;
using static HTCommander.AX25Packet;
using HTCommander.radio;

#if !__MonoCS__
using GMap.NET.MapProviders;
using GMap.NET.WindowsForms;
using GMap.NET.WindowsForms.Markers;
using GMap.NET;
#endif

namespace HTCommander
{
    public partial class MainForm : Form
    {
        static public MainForm g_MainForm = null;
        public Radio radio = new Radio();
        public RadioChannelControl[] channelControls = null;
        public RadioHtStatusForm radioHtStatusForm = null;
        public RadioSettingsForm radioSettingsForm = null;
        public RadioBssSettingsForm radioBssSettingsForm = null;
        public RadioChannelForm radioChannelForm = null;
        public RadioVolumeForm radioVolumeForm = null;
        public AprsDetailsForm aprsDetailsForm = null;
        public BTActivateForm bluetoothActivateForm = null;
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
        public List<TerminalText> terminalTexts = new List<TerminalText>();
        public BBS bbs;
        public Torrent torrent;
        public WinlinkClient winlinkClient;
        public AprsStack aprsStack;
        public bool Loading = true;
        public MailClientDebugForm mailClientDebugForm = new MailClientDebugForm();
#if !__MonoCS__
        public List<MapLocationForm> mapLocationForms = new List<MapLocationForm>();
        public GMapOverlay mapMarkersOverlay = new GMapOverlay("AprsMarkers");
#endif

        // Mailboxes
        public int SelectedMailbox = 0;
        public string[] MailBoxesNames = { "Inbox", "Outbox", "Draft", "Sent", "Archive", "Trash" };
        public TreeNode[] MailBoxTreeNodes = null;
        public List<WinLinkMail> Mails = new List<WinLinkMail>();
        private Point _mailMouseDownLocation;
        private bool _mailIsDragging;

        public static bool IsRunningOnMono() { return Type.GetType("Mono.Runtime") != null; }
        public static System.Drawing.Image GetImage(int i) { return g_MainForm.mainImageList.Images[i]; }

        public MainForm(string[] args)
        {
            foreach (string arg in args) { if (string.Compare(arg, "-preview", true) == 0) { previewMode = true; } }

            g_MainForm = this;
            InitializeComponent();
            bbs = new BBS(this);
            torrent = new Torrent(this);
            aprsStack = new AprsStack(this);
            winlinkClient = new WinlinkClient(this);
        }

        public int GetNextAprsMessageId()
        {
            int msgId = nextAprsMessageId++;
            if (nextAprsMessageId > 999) { nextAprsMessageId = 1; }
            registry.WriteInt("NextAprsMessageId", nextAprsMessageId);
            return msgId;
        }

        private void MainForm_Load(object sender, EventArgs e)
        {
            Program.BlockBoxEvent("MainForm_Load");

            appTitle = this.Text;
            this.SuspendLayout();
            radio.DebugMessage += Radio_DebugMessage;
            radio.OnInfoUpdate += Radio_InfoUpdate;
            radio.OnDataFrame += Radio_OnDataFrame;
            mainTabControl.SelectedTab = aprsTabPage;

#if !__MonoCS__
            // 
            // mapControl
            // 
            this.mapControl = new GMap.NET.WindowsForms.GMapControl();
            this.mapControl.Bearing = 0F;
            this.mapControl.CanDragMap = true;
            this.mapControl.EmptyTileColor = System.Drawing.Color.Navy;
            this.mapControl.GrayScaleMode = false;
            this.mapControl.HelperLineOption = GMap.NET.WindowsForms.HelperLineOptions.DontShow;
            this.mapControl.LevelsKeepInMemory = 5;
            this.mapControl.Location = new System.Drawing.Point(0, 0);
            this.mapControl.MarkersEnabled = true;
            this.mapControl.MaxZoom = 2;
            this.mapControl.MinZoom = 2;
            this.mapControl.MouseWheelZoomEnabled = true;
            this.mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            this.mapControl.Name = "mapControl";
            this.mapControl.NegativeMode = false;
            this.mapControl.PolygonsEnabled = true;
            this.mapControl.RetryLoadTile = 0;
            this.mapControl.RoutesEnabled = true;
            this.mapControl.ScaleMode = GMap.NET.WindowsForms.ScaleModes.Integer;
            this.mapControl.SelectedAreaFillColor = System.Drawing.Color.FromArgb(((int)(((byte)(33)))), ((int)(((byte)(65)))), ((int)(((byte)(105)))), ((int)(((byte)(225)))));
            this.mapControl.ShowTileGridLines = false;
            this.mapControl.Size = new System.Drawing.Size(150, 150);
            this.mapControl.TabIndex = 0;
            this.mapControl.Zoom = 0D;
            this.mapControl.Dock = DockStyle.Fill;
            mapTabPage.Controls.Add(this.mapControl);
            mapControl.MapProvider = GMapProviders.OpenStreetMap;
            mapControl.ShowCenter = false;
            mapControl.MinZoom = 3;
            mapControl.MaxZoom = 20;
            mapControl.CanDragMap = true;
            mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            mapControl.IgnoreMarkerOnMouseWheel = true; // Optional, depending on marker usage
            mapControl.DragButton = MouseButtons.Left; // Set the mouse button for dragging

            if (double.TryParse(registry.ReadString("MapZoom", "3"), out double d1) == false) { d1 = 3; }
            mapControl.Zoom = d1;

            if (double.TryParse(registry.ReadString("MapLatitude", "0"), out d1) == false) { d1 = 0; }
            if (double.TryParse(registry.ReadString("MapLongetude", "0"), out double d2) == false) { d2 = 0; }
            mapControl.Position = new GMap.NET.PointLatLng(d1, d2);

            // Add the overlay to the map
            mapControl.Overlays.Add(mapMarkersOverlay);
            mapControl.Update();
            mapControl.Refresh();
            mapToolStripMenuItem.Checked = (registry.ReadInt("ViewMap", 0) == 1);
#else
            mapToolStripMenuItem.Checked = false;
            mapToolStripMenuItem.Visible = false;
#endif

            string debugFileName = registry.ReadString("DebugFile", null);
            try
            {
                saveTraceFileDialog.FileName = debugFileName;
                debugFile = File.OpenWrite(debugFileName);
                debugSaveToFileToolStripMenuItem.Checked = true;
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
            showBluetoothFramesToolStripMenuItem.Checked = (registry.ReadInt("PacketTrace", 0) == 1);
            showAllChannels = (registry.ReadInt("ShowAllChannels", 0) == 1);
            aprsDestinationComboBox.Text = registry.ReadString("AprsDestination", "ALL");
            contactsToolStripMenuItem.Checked = (registry.ReadInt("ViewContacts", 0) == 1);
            bBSToolStripMenuItem.Checked = (registry.ReadInt("ViewBBS", 0) == 1);
            torrentToolStripMenuItem.Checked = (registry.ReadInt("ViewTorrent", 0) == 1);
            terminalToolStripMenuItem.Checked = (registry.ReadInt("ViewTerminal", 1) == 1);
            winlinkPassword = registry.ReadString("WinlinkPassword", "");
            mailToolStripMenuItem.Checked = (registry.ReadInt("ViewMail", 0) == 1);
            packetsToolStripMenuItem.Checked = (registry.ReadInt("ViewPackets", 0) == 1);
            debugToolStripMenuItem.Checked = (registry.ReadInt("ViewDebug", 0) == 1);
            showAllMessagesToolStripMenuItem.Checked = (registry.ReadInt("aprsViewAll", 1) == 1);
            showPacketDecodeToolStripMenuItem.Checked = (registry.ReadInt("showPacketDecode", 0) == 1);
            showCallsignToolStripMenuItem.Checked = (registry.ReadInt("TerminalShowCallsign", 1) == 1);
            viewTrafficToolStripMenuItem.Checked = (registry.ReadInt("ViewBbsTraffic", 1) == 1);
            systemTrayToolStripMenuItem.Checked = (registry.ReadInt("SystemTray", 1) == 1);
            bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;

            showPreviewToolStripMenuItem.Checked = (registry.ReadInt("MailViewPreview", 1) == 1);
            mailboxHorizontalSplitContainer.Panel2Collapsed = !showPreviewToolStripMenuItem.Checked;

            // Setup mailboxes
            MailBoxTreeNodes = new TreeNode[MailBoxesNames.Length];
            for (int i = 0; i < MailBoxesNames.Length; i++)
            {
                MailBoxTreeNodes[i] = mailBoxesTreeView.Nodes.Add(MailBoxesNames[i]);
                MailBoxTreeNodes[i].Tag = MailBoxTreeNodes[i].SelectedImageIndex = MailBoxTreeNodes[i].ImageIndex = i;
            }
            Mails = WinLinkMail.Deserialize(registry.ReadString("Mails", ""));
            UpdateMail();

            // Read the packets file
            string[] lines = null;
            try { lines = File.ReadAllLines("packets.ptcap"); } catch (Exception) { }
            if (lines != null)
            {
                // If the packet file is big, load only the first 200 packets
                int i = 0;
                if (lines.Length > 5000) { i = lines.Length - 5000; }
                for (; i < lines.Length; i++)
                {
                    try
                    {
                        // Read the packets
                        string[] s = lines[i].Split(',');
                        if (s.Length < 3) continue;
                        DateTime t = new DateTime(long.Parse(s[0]));
                        bool incoming = (s[1] == "1");
                        if ((s[2] != "TncFrag") && (s[2] != "TncFrag2")) continue;
                        int cid = int.Parse(s[3]);
                        int rid = -1;
                        string cn = cid.ToString();
                        byte[] f;
                        if (s[2] == "TncFrag")
                        {
                            f = Utils.HexStringToByteArray(s[4]);
                        }
                        else
                        {
                            if (s.Length < 7) continue;
                            rid = 0;
                            int.TryParse(s[4], out rid);
                            cn = s[5];
                            f = Utils.HexStringToByteArray(s[6]);
                        }

                        // Process the packets
                        TncDataFragment fragment = new TncDataFragment(true, 0, f, cid, rid);
                        fragment.time = t;
                        fragment.channel_name = cn;
                        fragment.incoming = incoming;
                        Radio_OnDataFrame(radio, fragment);
                        if ((incoming == false) && (cn == "APRS"))
                        {
                            AX25Packet packet = AX25Packet.DecodeAX25Packet(fragment);
                            if (packet != null) { AddAprsPacket(packet, true); }
                        }
                    }
                    catch (Exception) { }
                }
            }

            packetsSplitContainer.Panel2Collapsed = !showPacketDecodeToolStripMenuItem.Checked;

            // Open the packet write file
            AprsFile = File.Open("packets.ptcap", FileMode.Append, FileAccess.Write);
            aprsChatControl.UpdateMessages(true);

            debugTextBox.Clear();
            CheckBluetooth();

            // Setup all context menus
            mainAddressBookListView_SelectedIndexChanged(this, null);

            // Setup the HTTP server if configured
            webServerEnabled = (registry.ReadInt("webServerEnabled", 0) != 0);
            webServerPort = (int)registry.ReadInt("webServerPort", 0);
            if (webServerEnabled && (webServerPort > 0))
            {
                webserver = new HttpsWebSocketServer(this, webServerPort);
                webserver.Start();
            }
            allowTransmit = (registry.ReadInt("AllowTransmit", 0) == 1);
            Loading = false;

#if __MonoCS__
            mainTabControl.Alignment = TabAlignment.Top;
            aprsTabPage.ImageIndex = -1;
            aprsTabPage.Text = "APRS";
            mapTabPage.ImageIndex = -1;
            mapTabPage.Text = "Map";
            terminalTabPage.ImageIndex = -1;
            terminalTabPage.Text = "Terminal";
            mailTabPage.ImageIndex = -1;
            mailTabPage.Text = "Mail";
            addressesTabPage.ImageIndex = -1;
            addressesTabPage.Text = "Contacts";
            bbsTabPage.ImageIndex = -1;
            bbsTabPage.Text = "BBS";
            packetsTabPage.ImageIndex = -1;
            packetsTabPage.Text = "Packets";
            debugTabPage.ImageIndex = -1;
            debugTabPage.Text = "Debug";
#endif
            this.ResumeLayout();
            UpdateInfo();
            UpdateTabs();

            // Setup AX25 Session, only 1 session supported per radio
            session = new AX25Session(this, radio);
            session.StateChanged += Session_StateChanged;
            session.DataReceivedEvent += Session_DataReceivedEvent;
            session.UiDataReceivedEvent += Session_UiDataReceivedEvent;
            session.ErrorEvent += Session_ErrorEvent;
        }

        private void Session_StateChanged(AX25Session sender, AX25Session.ConnectionState state)
        {
            if (this.InvokeRequired) { this.Invoke(new AX25Session.StateChangedHandler(Session_StateChanged), sender, state); return; }

            DebugTrace("AX25 " + state.ToString());
            if ((activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal))
            {
                switch (state)
                {
                    case AX25Session.ConnectionState.CONNECTING:
                        AppendTerminalString(false, null, null, "Connecting...");
                        break;
                    case AX25Session.ConnectionState.CONNECTED:
                        AppendTerminalString(false, null, null, "Connected");
                        break;
                    case AX25Session.ConnectionState.DISCONNECTING:
                        AppendTerminalString(false, null, null, "Disconnecting...");
                        break;
                    case AX25Session.ConnectionState.DISCONNECTED:
                        AppendTerminalString(false, null, null, "Disconnected");
                        if ((activeStationLock != null) && (activeStationLock.WaitForConnection == false))
                        {
                            // If we are the connecting party and we got disconnected, drop the station lock.
                            ActiveLockToStation(null);
                        }
                        else
                        {
                            // Wait for another connection
                            AppendTerminalString(false, null, null, "Waiting for connection...");
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
        }
        private void Session_DataReceivedEvent(AX25Session sender, byte[] data)
        {
            Debug("AX25 Stream Data: " + data.Length);
            if (activeStationLock != null)
            {
                if (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal)
                {
                    string[] dataStrs = UTF8Encoding.UTF8.GetString(data).Replace("\r\n", "\r").Replace("\n", "\r").Split('\r');
                    for (int i = 0; i < dataStrs.Length; i++)
                    {
                        if ((dataStrs[i].Length == 0) && (i == (dataStrs.Length - 1))) continue;
                        AppendTerminalString(false, session.Addresses[0].ToString(), callsign + "-" + stationId, dataStrs[i]);
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
            }
        }

        private void Session_UiDataReceivedEvent(AX25Session sender, byte[] data)
        {
            Debug("AX25 UI Frame Data: " + data.Length);
            if (activeStationLock != null)
            {
                if (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal)
                {
                    AppendTerminalString(false, session.Addresses[0].ToString(), callsign + "-" + stationId, UTF8Encoding.UTF8.GetString(data));
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

        private async void CheckBluetooth()
        {
            radioStateLabel.Text = "Searching";
            DebugTrace("Looking for compatible radios...");
            bluetoothEnabled = await RadioBluetoothWin.CheckBluetooth();
            if (bluetoothEnabled == false)
            {
                radioStateLabel.Text = "Disconnected";
                checkBluetoothButton.Visible = true;
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
                checkBluetoothButton.Visible = false;
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
                radioStateLabel.Text = "Disconnected";
            }
        }

        private void Radio_OnDataFrame(Radio sender, TncDataFragment frame)
        {
            if (this.InvokeRequired) { this.Invoke(new Action(() => { Radio_OnDataFrame(sender, frame); })); return; }

            // Add to the packet capture tab
            ListViewItem l = new ListViewItem(new string[] { frame.time.ToShortTimeString(), frame.channel_name, FragmentToShortString(frame) });
            l.ImageIndex = frame.incoming ? 5 : 4;
            l.Tag = frame;
            packetsListView.Items.Add(l);

            // Write frame data to file
            if (AprsFile != null)
            {
                byte[] bytes = UTF8Encoding.Default.GetBytes(frame.time.Ticks + "," + (frame.incoming ? "1" : "0") + "," + frame.ToString() + "\r\n");
                AprsFile.Write(bytes, 0, bytes.Length);
            }
            if (frame.incoming == false) return;

            //DebugTrace("Packet: " + frame.ToHex());

            // If this frame comes from the APRS channel, process it as APRS
            if (frame.channel_name == "APRS")
            {
                AX25Packet p = AX25Packet.DecodeAX25Packet(frame);
                if ((p != null) && (p.type == FrameType.U_FRAME))
                {
                    AddAprsPacket(p, false);
                    aprsChatControl.UpdateMessages(false);
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
                        winlinkClient.ProcessFrame(frame, p);
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
                                AppendTerminalString(false, p.addresses[1].ToString(), p.addresses[0].CallSignWithId, dataStr);
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
                                    AppendTerminalString(false, p.addresses[1].ToString(), p.addresses[0].CallSignWithId, aprsPacket.MessageData.MsgText);
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
            }

            // If this is a AX.25 disconnection frame sent at us and we are already not connected, just ack
            AX25Packet px = AX25Packet.DecodeAX25Packet(frame);
            if ((px != null) && (px.addresses.Count >= 2) && (px.addresses[0].CallSignWithId == callsign + "-" + stationId) && (px.type == FrameType.U_FRAME_DISC))
            {
                List<AX25Address> addresses = new List<AX25Address>();
                addresses.Add(AX25Address.GetAddress(px.addresses[1].ToString()));
                addresses.Add(AX25Address.GetAddress(callsign, stationId));
                AX25Packet response = new AX25Packet(addresses, 0, 0, true, true, FrameType.U_FRAME_UA, null);
            }
        }

        private delegate void RadioInfoUpdateHandler(Radio sender, Radio.RadioUpdateNotification msg);

        private void Radio_InfoUpdate(Radio sender, Radio.RadioUpdateNotification msg)
        {
            if (this.InvokeRequired) { this.Invoke(new RadioInfoUpdateHandler(Radio_InfoUpdate), sender, msg); return; }
            try
            {
                switch (msg)
                {
                    case Radio.RadioUpdateNotification.State:
                        switch (radio.State)
                        {
                            case Radio.RadioState.Connected:
                                connectToolStripMenuItem.Enabled = false;
                                disconnectToolStripMenuItem.Enabled = true;
                                radioStateLabel.Text = "Connected";
                                channelControls = new RadioChannelControl[radio.Info.channel_count];
                                vfo2LastChannelId = -1;
                                break;
                            case Radio.RadioState.Disconnected:
                                connectToolStripMenuItem.Enabled = true;
                                disconnectToolStripMenuItem.Enabled = false;
                                radioStateLabel.Text = "Disconnected";
                                channelsFlowLayoutPanel.Controls.Clear();
                                transmitBarPanel.Visible = false;
                                rssiProgressBar.Visible = false;
                                ActiveLockToStation(null);
                                if (channelControls != null)
                                {
                                    for (int i = 0; i < channelControls.Length; i++) { if (channelControls[i] != null) { channelControls[i].Dispose(); channelControls[i] = null; } }
                                }
                                if (radioHtStatusForm != null) { radioHtStatusForm.Close(); radioHtStatusForm = null; }
                                if (radioSettingsForm != null) { radioSettingsForm.Close(); radioSettingsForm = null; }
                                if (radioBssSettingsForm != null) { radioBssSettingsForm.Close(); radioBssSettingsForm = null; }
                                if (radioChannelForm != null) { radioChannelForm.Close(); radioChannelForm = null; }
                                if (radioVolumeForm != null) { radioVolumeForm.Close(); radioVolumeForm = null; }
                                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
                                break;
                            case Radio.RadioState.Connecting:
                                radioStateLabel.Text = "Connecting";
                                break;
                            case Radio.RadioState.MultiRadioSelect:
                                radioStateLabel.Text = "Multiple Radios";
                                break;
                            case Radio.RadioState.UnableToConnect:
                                radioStateLabel.Text = "Can't connect";
                                break;
                            case Radio.RadioState.AccessDenied:
                                radioStateLabel.Text = "Access Denied";
                                new BTAccessDeniedForm().ShowDialog(this);
                                break;
                            case Radio.RadioState.BluetoothNotAvailable:
                                radioStateLabel.Text = "No Bluetooth";
                                break;
                            case Radio.RadioState.NotRadioFound:
                                radioStateLabel.Text = "No Radio Found";
                                break;
                        }

                        UpdateInfo();
                        break;
                    case Radio.RadioUpdateNotification.ChannelInfo:
                        if (radio.Channels != null)
                        {
                            UpdateChannelsPanel();
                            CheckAprsChannel();
                            UpdateRadioDisplay();
                            UpdateInfo();
                        }
                        break;
                    case Radio.RadioUpdateNotification.BatteryAsPercentage:
                        batteryToolStripStatusLabel.Text = "Battery " + radio.BatteryAsPercentage + "%";
                        batteryToolStripStatusLabel.Visible = true;
                        break;
                    case Radio.RadioUpdateNotification.HtStatus:
                        rssiProgressBar.Visible = radio.HtStatus.is_in_rx;
                        rssiProgressBar.Value = radio.HtStatus.rssi;
                        transmitBarPanel.Visible = radio.HtStatus.is_in_tx;
                        if (radioHtStatusForm != null) { radioHtStatusForm.UpdateInfo(); }
                        radioStatusToolStripMenuItem.Enabled = true;
                        UpdateRadioDisplay();
                        setupRegionMenu();
                        break;
                    case Radio.RadioUpdateNotification.Settings:
                        if (radioSettingsForm != null) { radioSettingsForm.UpdateInfo(); }
                        radioSettingsToolStripMenuItem.Enabled = true;
                        dualWatchToolStripMenuItem.Checked = (radio.Settings.double_channel == 1);
                        scanToolStripMenuItem.Checked = radio.Settings.scan;
                        if ((activeStationLock != null) && (activeChannelIdLock != radio.Settings.channel_a)) { ActiveLockToStation(null); } // Check lock/unlock
                        UpdateRadioDisplay();
                        setupRegionMenu();
                        break;
                    case Radio.RadioUpdateNotification.BssSettings:
                        if (radioSettingsForm != null) { radioBssSettingsForm.UpdateInfo(); }
                        radioBSSSettingsToolStripMenuItem.Enabled = true;
                        UpdateInfo();
                        break;
                    case Radio.RadioUpdateNotification.Volume:
                        if (radioVolumeForm != null)
                        {
                            radioVolumeForm.Volume = radio.Volume;
                        }
                        else
                        {
                            radioVolumeForm = new RadioVolumeForm(this, radio);
                            radioVolumeForm.Volume = radio.Volume;
                            radioVolumeForm.Show(this);
                        }
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


        public delegate void EmptyFuncHandler();

        private void UpdateRadioDisplay()
        {
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.Invoke(new EmptyFuncHandler(UpdateRadioDisplay)); return; }

            if (radio.Settings == null) return;
            if (radio.Channels != null)
            {
                RadioChannelInfo channelA = null;
                RadioChannelInfo channelB = null;

                if ((radio.Settings.channel_a >= 0) && (radio.Settings.channel_a < radio.Channels.Length))
                {
                    channelA = radio.Channels[radio.Settings.channel_a];
                }
                if ((radio.Settings.channel_b >= 0) && (radio.Settings.channel_b < radio.Channels.Length))
                {
                    channelB = radio.Channels[radio.Settings.channel_b];
                }

                if (channelControls != null)
                {
                    foreach (RadioChannelControl c in channelControls)
                    {
                        if (c == null) continue;
                        if ((channelA != null) && (((int)c.Tag) == channelA.channel_id))
                        {
                            c.BackColor = Color.PaleGoldenrod;
                        }
                        else if ((channelB != null) && (radio.Settings.double_channel == 1) && (((int)c.Tag) == channelB.channel_id))
                        {
                            c.BackColor = Color.PaleGoldenrod;
                        }
                        else
                        {
                            c.BackColor = Color.DarkKhaki;
                        }
                    }
                }

                if (channelA != null)
                {
                    if (channelA.name_str.Length > 0)
                    {
                        vfo1Label.Text = channelA.name_str;
                        vfo1FreqLabel.Text = (((float)channelA.rx_freq) / 1000000).ToString("F3") + "Mhz";
                    }
                    else if (channelA.rx_freq > 0)
                    {
                        vfo1Label.Text = ((double)channelA.rx_freq / 1000000).ToString("F3");
                        vfo1FreqLabel.Text = "Mhz";
                    }
                    else
                    {
                        vfo1Label.Text = "Empty";
                        vfo1FreqLabel.Text = "";
                    }
                    vfo1StatusLabel.Text = (activeStationLock == null) ? "" : "Locked";
                }
                else
                {
                    vfo1Label.Text = "";
                    vfo1FreqLabel.Text = "";
                    vfo1StatusLabel.Text = "";
                }
                if (radio.Settings.scan == true)
                {
                    if ((radio.HtStatus != null) && (radio.Channels[radio.HtStatus.curr_ch_id] != null))
                    {
                        if (radio.Channels[radio.HtStatus.curr_ch_id] == channelA)
                        {
                            if (vfo2LastChannelId >= 0)
                            {
                                channelB = radio.Channels[vfo2LastChannelId];
                                vfo2Label.Text = channelB.name_str;
                                vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                                vfo2StatusLabel.Text = "Scanning...";
                            }
                            else
                            {
                                vfo2Label.Text = "Scanning...";
                                vfo2FreqLabel.Text = "";
                                vfo2StatusLabel.Text = "";
                            }
                        }
                        else
                        {
                            channelB = radio.Channels[radio.HtStatus.curr_ch_id];
                            vfo2Label.Text = channelB.name_str;
                            vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                            vfo2StatusLabel.Text = "Scanning...";
                            vfo2LastChannelId = radio.HtStatus.curr_ch_id;
                        }
                    }
                    else
                    {
                        vfo2Label.Text = "Scanning...";
                        vfo2FreqLabel.Text = "";
                        vfo2StatusLabel.Text = "";
                    }
                }
                else if ((radio.Settings.double_channel == 1) && (channelB != null))
                {
                    if (channelB.name_str.Length > 0)
                    {
                        vfo2Label.Text = channelB.name_str;
                        vfo2FreqLabel.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3") + " MHz";
                    }
                    else if (channelB.rx_freq != 0)
                    {
                        vfo2Label.Text = (((float)channelB.rx_freq) / 1000000).ToString("F3");
                        vfo2FreqLabel.Text = "MHz";
                    }
                    else
                    {
                        vfo2Label.Text = "Empty";
                        vfo2FreqLabel.Text = "";
                    }
                    vfo2StatusLabel.Text = "";
                }
                else
                {
                    vfo2Label.Text = "";
                    vfo2FreqLabel.Text = "";
                    vfo2StatusLabel.Text = "";
                }
                connectedPanel.Visible = true;

                // Update the colors
                if ((channelB != null) && (radio.State == Radio.RadioState.Connected) && (radio.HtStatus != null) && (radio.HtStatus.double_channel == RadioChannelType.A))
                {
                    if ((radio.HtStatus.is_in_rx || radio.HtStatus.is_in_tx) && (radio.HtStatus.curr_ch_id == channelB.channel_id))
                    {
                        vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                        vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.Salmon;
                    }
                    else
                    {
                        vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.Salmon;
                        vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
                    }
                }
                else
                {
                    vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                    vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
                }
            }
            else
            {
                vfo1Label.Text = "";
                vfo1FreqLabel.Text = "";
                vfo1StatusLabel.Text = "";
                vfo2Label.Text = "";
                vfo2FreqLabel.Text = "";
                vfo2StatusLabel.Text = "";
                vfo1StatusLabel.ForeColor = vfo1FreqLabel.ForeColor = vfo1Label.ForeColor = Color.LightGray;
                vfo2StatusLabel.ForeColor = vfo2FreqLabel.ForeColor = vfo2Label.ForeColor = Color.LightGray;
            }
            AdjustVfoLabel(vfo1Label);
            AdjustVfoLabel(vfo2Label);
        }

        private void AdjustVfoLabel(Label label)
        {
            // Initial font size.
            float fontSize = 20;
            label.Font = new Font(label.Font.FontFamily, fontSize);

            // Create a Graphics object to measure the text.
            using (Graphics g = label.CreateGraphics())
            {
                // Measure the text width.
                SizeF textSize = g.MeasureString(label.Text, new Font(label.Font.FontFamily, fontSize));

                // While the text width exceeds the label width, reduce the font size.
                while (textSize.Width > label.ClientSize.Width && fontSize > 1) //Ensure font size doesn't go below 1
                {
                    fontSize -= 1; // Reduce font size by 1 (or a finer increment)
                    label.Font = new Font(label.Font.FontFamily, fontSize);
                    textSize = g.MeasureString(label.Text, label.Font);
                }
            }
        }

        public void DebugTrace(string msg)
        {
            Program.BlockBoxEvent(msg);
            try { debugTextBox.AppendText(msg + Environment.NewLine); } catch (Exception) { }
            if (debugFile != null)
            {
                byte[] buf = UTF8Encoding.UTF8.GetBytes(DateTime.Now.ToString() + ": " + msg + Environment.NewLine);
                try { debugFile.Write(buf, 0, buf.Length); } catch (Exception) { }
            }
            if (webserver != null) { webserver.BroadcastString(msg); }
        }

        private void Radio_DebugMessage(Radio sender, string msg)
        {
            try
            {
                if (this.InvokeRequired) { this.Invoke(new Action(() => { Radio_DebugMessage(sender, msg); })); return; }
                DebugTrace(msg);
            }
            catch (Exception) { }
        }

        public void Debug(string msg)
        {
            try
            {
                if (this.InvokeRequired) { this.Invoke(new Action(() => { Debug(msg); })); return; }
                DebugTrace(msg);
            }
            catch (Exception) { }
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Application.Exit();
        }

        private void connectToolStripMenuItem_Click(object sender, EventArgs e)
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

        public class TerminalText
        {
            public bool outgoing;
            public string from;
            public string to;
            public string message;

            public TerminalText(bool outgoing, string from, string to, string message)
            {
                this.outgoing = outgoing;
                this.from = from;
                this.to = to;
                this.message = message;
            }
        }

        private void showCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            registry.WriteInt("TerminalShowCallsign", showCallsignToolStripMenuItem.Checked ? 1 : 0);
            terminalTextBox.Clear();
            foreach (TerminalText terminalText in terminalTexts) { AppendTerminalString(terminalText); }
            terminalTextBox.SelectionStart = terminalTextBox.Text.Length;
            terminalTextBox.ScrollToCaret();
        }

        public delegate void AppendTerminalStringHandler(bool outgoing, string from, string to, string message);
        public void AppendTerminalString(bool outgoing, string from, string to, string message)
        {
            if (this.InvokeRequired) { this.Invoke(new AppendTerminalStringHandler(AppendTerminalString), outgoing, from, to, message); return; }

            TerminalText terminalText = new TerminalText(outgoing, from, to, message);
            terminalTexts.Add(terminalText);
            AppendTerminalString(terminalText);
            terminalTextBox.SelectionStart = terminalTextBox.Text.Length;
            terminalTextBox.ScrollToCaret();
        }

        public void AppendTerminalString(TerminalText terminalText)
        {
            if (terminalTextBox.Text.Length != 0) { terminalTextBox.AppendText(Environment.NewLine); }
            if ((terminalText.to == null) || (terminalText.from == null))
            {
                AppendTerminalText(terminalText.message, Color.Yellow);
                return;
            }
            if (showCallsignToolStripMenuItem.Checked)
            {
                if (terminalText.outgoing) { AppendTerminalText(terminalText.to + " < ", Color.Green); } else { AppendTerminalText(terminalText.from + " > ", Color.Green); }
            }
            AppendTerminalText(terminalText.message, terminalText.outgoing ? Color.CornflowerBlue : Color.Gainsboro);
        }

        public void AppendTerminalText(string text, Color color)
        {
            terminalTextBox.SelectionStart = terminalTextBox.TextLength;
            terminalTextBox.SelectionLength = 0;
            terminalTextBox.SelectionColor = color;
            terminalTextBox.AppendText(text);
            terminalTextBox.SelectionColor = terminalTextBox.ForeColor;
        }

        private void toolStripMenuItem13_Click(object sender, EventArgs e)
        {
            terminalTexts.Clear();
            terminalTextBox.Clear();
        }

        private void terminalClearButton_Click(object sender, EventArgs e)
        {
            terminalTexts.Clear();
            terminalTextBox.Clear();
        }

        private void terminalInputTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == 13) { terminalSendButton_Click(this, null); e.Handled = true; return; }
        }

        private bool ParseCallsignWithId(string callsignWithId, out string xcallsign, out int xstationId)
        {
            xcallsign = null;
            xstationId = -1;
            if (callsignWithId == null) return false;
            string[] destSplit = callsignWithId.Split('-');
            if (destSplit.Length != 2) return false;
            int destStationId = -1;
            if (destSplit[0].Length < 3) return false;
            if (destSplit[0].Length > 6) return false;
            if (destSplit[1].Length < 1) return false;
            if (destSplit[1].Length > 2) return false;
            if (int.TryParse(destSplit[1], out destStationId) == false) return false;
            if ((destStationId < 0) || (destStationId > 15)) return false;
            xcallsign = destSplit[0];
            xstationId = destStationId;
            return true;
        }

        private void terminalSendButton_Click(object sender, EventArgs e)
        {
            if (terminalInputTextBox.Text.Length == 0) return;
            if (activeStationLock == null) return;
            if (activeChannelIdLock == -1) return;
            if (activeStationLock.StationType != StationInfoClass.StationTypes.Terminal) return;
            if (terminalInputTextBox.Text.Length == 0) return;

            string destCallsign;
            int destStationId;
            string sendText = terminalInputTextBox.Text;
            terminalInputTextBox.Clear();

            if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25)
            {
                // Raw AX.25 format
                if (ParseCallsignWithId(activeStationLock.Callsign, out destCallsign, out destStationId) == false) return;
                //terminalTextBox.AppendText(destCallsign + "-" + destStationId + "< " + sendText + Environment.NewLine);
                AppendTerminalString(true, callsign + "-" + stationId, destCallsign + "-" + destStationId, sendText);
                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(AX25Address.GetAddress(destCallsign, destStationId));
                addresses.Add(AX25Address.GetAddress(callsign, stationId));
                AX25Packet packet = new AX25Packet(addresses, sendText, DateTime.Now);
                radio.TransmitTncData(packet, activeChannelIdLock);
            }
            else if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.RawX25Compress)
            {
                // Raw AX.25 format + Deflate
                if (ParseCallsignWithId(activeStationLock.Callsign, out destCallsign, out destStationId) == false) return;
                //terminalTextBox.AppendText(destCallsign + "-" + destStationId + "< " + sendText + Environment.NewLine);
                AppendTerminalString(true, callsign + "-" + stationId, destCallsign + "-" + destStationId, sendText);
                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(AX25Address.GetAddress(destCallsign, destStationId));
                addresses.Add(AX25Address.GetAddress(callsign, stationId));

                byte[] buffer1 = UTF8Encoding.Default.GetBytes(sendText);
                byte[] buffer2 = Utils.CompressBrotli(buffer1);
                byte[] buffer3 = Utils.CompressDeflate(buffer1);
                if ((buffer1.Length <= buffer2.Length) && (buffer1.Length <= buffer3.Length))
                {
                    AX25Packet packet = new AX25Packet(addresses, buffer1, DateTime.Now);
                    packet.pid = 241; // No compression, but compression is supported
                    radio.TransmitTncData(packet, activeChannelIdLock);
                }
                else if (buffer2.Length <= buffer3.Length) // Brotli is smaller
                {
                    AX25Packet packet = new AX25Packet(addresses, buffer2, DateTime.Now);
                    packet.pid = 242; // Compression applied
                    radio.TransmitTncData(packet, activeChannelIdLock);
                }
                else // Deflate is smaller
                {
                    AX25Packet packet = new AX25Packet(addresses, buffer3, DateTime.Now);
                    packet.pid = 243; // Compression applied
                    radio.TransmitTncData(packet, activeChannelIdLock);
                }
            }
            else if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.APRS)
            {
                // APRS format
                if (ParseCallsignWithId(activeStationLock.Callsign, out destCallsign, out destStationId) == false) return;
                string aprsAddr = ":" + activeStationLock.Callsign;
                if (aprsAddr.EndsWith("-0")) { aprsAddr = aprsAddr.Substring(0, aprsAddr.Length - 2); }
                while (aprsAddr.Length < 10) { aprsAddr += " "; }
                aprsAddr += ":";
                //terminalTextBox.AppendText(destCallsign + ((destStationId != 0) ? ("-" + destStationId) : "") + "< " + sendText + Environment.NewLine);
                AppendTerminalString(true, callsign + "-" + stationId, destCallsign + ((destStationId != 0) ? ("-" + destStationId) : ""), sendText);

                // Get the AX25 destivation address
                AX25Address ax25dest = null;
                if (!string.IsNullOrEmpty(activeStationLock.AX25Destination)) { ax25dest = AX25Address.GetAddress(activeStationLock.AX25Destination); }
                if (ax25dest == null) { ax25dest = AX25Address.GetAddress(destCallsign, destStationId); }

                // Format the AX25 packet
                List<AX25Address> addresses = new List<AX25Address>(1);
                addresses.Add(ax25dest);
                addresses.Add(AX25Address.GetAddress(callsign, stationId));
                int msgId = GetNextAprsMessageId();
                AX25Packet packet = new AX25Packet(addresses, aprsAddr + sendText + "{" + msgId, DateTime.Now);
                packet.messageId = msgId;
                aprsStack.ProcessOutgoing(packet, activeChannelIdLock);
            }
            else if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.X25Session)
            {
                // AX.25 Session
                if (session.CurrentState == AX25Session.ConnectionState.CONNECTED)
                {
                    session.Send(UTF8Encoding.UTF8.GetBytes(sendText + "\r"));
                    AppendTerminalString(true, callsign + "-" + stationId, session.Addresses[0].ToString(), sendText);
                }
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
            routeKey = (string)aprsRouteComboBox.SelectedItem;
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

        private void aprsSendButton_Click(object sender, EventArgs e)
        {
            if (aprsTextBox.Text.Length == 0) return;
            if (UTF8Encoding.Default.GetByteCount(aprsTextBox.Text) > 67) return;
            if (aprsChannel < 0) return;

            // APRS format
            string aprsAddr = ":" + aprsDestinationComboBox.Text;
            while (aprsAddr.Length < 10) { aprsAddr += " "; }
            aprsAddr += ":";

            int msgId = GetNextAprsMessageId();
            AX25Packet packet = new AX25Packet(GetTransmitAprsRoute(), aprsAddr + aprsTextBox.Text + "{" + msgId, DateTime.Now);
            packet.messageId = msgId;

            // Simplified Format, not APRS
            //addresses.Add(AX25Address.GetAddress(callsign, 0, false, true));
            //AX25Packet packet = new AX25Packet(1, addresses, 0, aprsTextBox.Text);
            //packet.time = DateTime.Now;

            //radio.TransmitTncData(packet, aprsChannel, radio.HtStatus.curr_region);
            aprsStack.ProcessOutgoing(packet, aprsChannel, radio.HtStatus.curr_region);
            AddAprsPacket(packet, true);
            aprsTextBox.Text = "";
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
                if ((sender == false) && (aprsStack.ProcessIncoming(aprsPacket) == false)) return;
                MessageType = aprsPacket.DataType;

                if (sender == false)
                {
                    SenderAddr = packet.addresses[1];
                    RoutingString = SenderAddr.ToString();
                    SenderCallsign = SenderAddr.CallSignWithId;
                    if ((aprsPacket.Position != null) && (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) && (aprsPacket.Position.CoordinateSet.Longitude.Value != 0)) { ImageIndex = 3; }
                }
                if (aprsPacket.DataType == PacketDataType.Message)
                {
                    bool forSelf = ((aprsPacket.MessageData.Addressee == callsign) || (aprsPacket.MessageData.Addressee == callsign + "-" + stationId));

                    if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtAck)
                    {
                        if (forSelf)
                        {
                            // Look at a message to ack
                            foreach (ChatMessage n in aprsChatControl.Messages)
                            {
                                if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId)) { n.ImageIndex = 0; }
                            }
                        }
                        return;
                    }
                    else if (aprsPacket.MessageData.MsgType == aprsparser.MessageType.mtRej)
                    {
                        if (forSelf)
                        {
                            // Look at a message to reject
                            foreach (ChatMessage n in aprsChatControl.Messages)
                            {
                                if (n.Sender && (n.MessageId == aprsPacket.MessageData.SeqId)) { n.ImageIndex = 1; }
                            }
                        }
                        return;
                    }

                    // Normal message processing
                    if (sender)
                    {
                        RoutingString = "→ " + aprsPacket.MessageData.Addressee;
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
                        foreach (ChatMessage n in aprsChatControl.Messages)
                        {
                            // If this is a duplicate, don't display it.
                            if ((n.MessageId == MessageId) && (n.Route == RoutingString) && (n.Message == MessageText)) return;
                        }
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

            if ((MessageText != null) && (MessageText.Length > 0))
            {
                ChatMessage c = new ChatMessage(RoutingString, SenderCallsign, MessageText.Trim(), packet.time, sender, -1);
                c.Tag = packet;
                c.MessageId = MessageId;
                c.MessageType = MessageType;
                c.Visible = showAllMessagesToolStripMenuItem.Checked || (c.MessageType == PacketDataType.Message);
                c.ImageIndex = ImageIndex;

                // Check if we already got this message in the last 5 minutes
                foreach (ChatMessage chatMessage2 in aprsChatControl.Messages)
                {
                    AX25Packet packet2 = (AX25Packet)chatMessage2.Tag;
                    if ((c.Message == chatMessage2.Message) && (packet2.time.AddMinutes(5).CompareTo(packet.time) > 0)) { return; }
                }

                // Add the message
                aprsChatControl.Messages.Add(c);
                if (c.Visible) { aprsChatControl.UpdateMessages(true); }

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

#if !__MonoCS__
                // Add or move the map marker
                if ((c.ImageIndex == 3) && (aprsPacket != null))
                {
                    c.Latitude = aprsPacket.Position.CoordinateSet.Latitude.Value;
                    c.Longitude = aprsPacket.Position.CoordinateSet.Longitude.Value;
                    AddMapMarker(packet.addresses[1].CallSignWithId, aprsPacket.Position.CoordinateSet.Latitude.Value, aprsPacket.Position.CoordinateSet.Longitude.Value);
                }
#endif
            }
        }

        private void aprsTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == 13) { aprsSendButton_Click(this, null); e.Handled = true; return; }

            // Check if the pressed character is in the restricted list
            char[] restrictedChars = { '~', '|', '}' };
            if (restrictedChars.Contains(e.KeyChar)) { e.Handled = true; return; }
        }

        private void aboutToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            new AboutForm().ShowDialog(this);
        }

        private void mainMenuStrip_ItemClicked(object sender, ToolStripItemClickedEventArgs e)
        {

        }

        private void showPacketTraceToolStripMenuItem_Click(object sender, EventArgs e)
        {

        }

        private void saveToFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (debugFile != null)
            {
                debugFile.Close();
                debugFile = null;
                debugSaveToFileToolStripMenuItem.Checked = false;
                registry.DeleteValue("DebugFile");
            }
            else
            {
                if (saveTraceFileDialog.ShowDialog(this) == DialogResult.OK)
                {
                    debugFile = File.OpenWrite(saveTraceFileDialog.FileName);
                    debugSaveToFileToolStripMenuItem.Checked = true;
                    registry.WriteString("DebugFile", saveTraceFileDialog.FileName);
                }
            }
        }

        private void aprsSmsButton_Click(object sender, EventArgs e)
        {
            using (AprsSmsForm aprsSmsForm = new AprsSmsForm())
            {
                if (aprsSmsForm.ShowDialog(this) == DialogResult.OK)
                {
                    // APRS format
                    if (aprsChannel < 0) return;
                    int msgId = GetNextAprsMessageId();
                    AX25Packet packet = new AX25Packet(GetTransmitAprsRoute(), ":SMS      :@" + aprsSmsForm.PhoneNumber + " " + aprsSmsForm.Message + "{" + msgId, DateTime.Now);
                    packet.messageId = msgId;
                    packet.time = DateTime.Now;

                    aprsStack.ProcessOutgoing(packet, aprsChannel, radio.HtStatus.curr_region);
                    AddAprsPacket(packet, true);
                }
            }
        }
        private void weatherReportToolStripMenuItem_Click(object sender, EventArgs e)
        {
            using (AprsWeatherForm aprsWeatherForm = new AprsWeatherForm())
            {
                if (aprsWeatherForm.ShowDialog(this) == DialogResult.OK)
                {
                    // APRS format
                    if (aprsChannel < 0) return;
                    int msgId = GetNextAprsMessageId();
                    AX25Packet packet = new AX25Packet(GetTransmitAprsRoute(), ":WXBOT    :" + aprsWeatherForm.GetAprsMessage() + "{" + msgId, DateTime.Now);
                    packet.messageId = msgId;
                    packet.time = DateTime.Now;

                    aprsStack.ProcessOutgoing(packet, aprsChannel, radio.HtStatus.curr_region);
                    AddAprsPacket(packet, true);
                }
            }
        }

        public void UpdateMail()
        {
            mailTitleLabel.Text = "Mail - " + MailBoxesNames[SelectedMailbox];

            int[] MailBoxCount = new int[MailBoxesNames.Length];
            for (int i = 0; i < Mails.Count; i++) { MailBoxCount[Mails[i].Mailbox]++; }

            for (int i = 0; i < mailBoxesTreeView.Nodes.Count; i++)
            {
                MailBoxTreeNodes[i].Text = MailBoxesNames[i] + " (" + MailBoxCount[i] + ")";
            }

            if ((SelectedMailbox == 1) || (SelectedMailbox == 2) || (SelectedMailbox == 3))
            {
                mailboxListView.Columns[1].Text = "To";
            }
            else
            {
                mailboxListView.Columns[1].Text = "From";
            }
            UpdateMailBox();
        }

        public void UpdateMailBox()
        {
            List<WinLinkMail> selectedMails = new List<WinLinkMail>();
            foreach (ListViewItem l in mailboxListView.SelectedItems) { selectedMails.Add((WinLinkMail)l.Tag); }

            List<ListViewItem> r = new List<ListViewItem>();
            for (int i = 0; i < Mails.Count; i++)
            {
                if (Mails[i].Mailbox == SelectedMailbox)
                {
                    WinLinkMail m = Mails[i];
                    string secondFeild = m.From;
                    if ((SelectedMailbox == 1) || (SelectedMailbox == 2) || (SelectedMailbox == 3)) { secondFeild = m.To; }
                    ListViewItem item = new ListViewItem(new String[] { m.DateTime.ToShortDateString(), m.To, m.Subject });
                    item.ImageIndex = 8;
                    item.Tag = m;
                    item.Selected = selectedMails.Contains(m);
                    r.Add(item);
                }
            }

            mailboxListView.Items.Clear();
            mailboxListView.Items.AddRange(r.ToArray());
            mailboxListView_SelectedIndexChanged(this, null);
        }

        public void SaveMails()
        {
            registry.WriteString("Mails", WinLinkMail.Serialize(Mails));
        }

        public void UpdateInfo()
        {
            if (this.Disposing || this.IsDisposed) return;
            if (this.InvokeRequired) { this.Invoke(new EmptyFuncHandler(UpdateInfo)); return; }

            radioStateLabel.Visible = (radio.State != Radio.RadioState.Connected);
            if (radio.State != Radio.RadioState.Connected)
            {
                channelsFlowLayoutPanel.Visible = false;
                batteryToolStripStatusLabel.Visible = false;
            }
            smSMessageToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            weatherReportToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            beaconSettingsToolStripMenuItem.Enabled = ((radio.State == Radio.RadioState.Connected) && (radio.BssSettings != null));
            volumeToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            dualWatchToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            scanToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            exportChannelsToolStripMenuItem.Enabled = ((radio.State == Radio.RadioState.Connected) && (radio.Channels != null));
            // importChannelsToolStripMenuItem.Enabled = 
            aprsDestinationComboBox.Enabled = (radio.State == Radio.RadioState.Connected) && (aprsChannel != -1);
            aprsTextBox.Enabled = (radio.State == Radio.RadioState.Connected) && (aprsChannel != -1);
            aprsSendButton.Enabled = (radio.State == Radio.RadioState.Connected) && (aprsChannel != -1);
            batteryTimer.Enabled = (radio.State == Radio.RadioState.Connected);
            connectToolStripMenuItem.Enabled = connectButton.Visible = (radio.State != Radio.RadioState.Connected && radio.State != Radio.RadioState.Connecting && devices != null && devices.Length > 0);
            radioInformationToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected);
            radioStatusToolStripMenuItem.Enabled = ((radio.State == Radio.RadioState.Connected) && (radio.HtStatus != null));
            if (radio.State != Radio.RadioState.Connected) { connectedPanel.Visible = false; }
            exportStationsToolStripMenuItem.Enabled = (stations.Count > 0);
            waitForConnectionToolStripMenuItem.Visible = allowTransmit;
            waitForConnectionToolStripMenuItem.Enabled = (radio.State == Radio.RadioState.Connected) && allowTransmit && (activeStationLock == null);

            toolStripMenuItem7.Visible = smSMessageToolStripMenuItem.Visible = weatherReportToolStripMenuItem.Visible = (allowTransmit && (aprsChannel != -1));
            beaconSettingsToolStripMenuItem.Visible = (radio.State == Radio.RadioState.Connected) && allowTransmit;
            aprsBottomPanel.Visible = allowTransmit;
            newMailButton.Visible = mailConnectButton.Visible = allowTransmit;
            terminalBottomPanel.Visible = allowTransmit;
            terminalConnectButton.Visible = allowTransmit;
            bbsConnectButton.Visible = allowTransmit;
            bBSToolStripMenuItem.Visible = allowTransmit;
            terminalToolStripMenuItem.Visible = allowTransmit;

            // APRS Beacon
            if ((radio.State == Radio.RadioState.Connected) && (radio.BssSettings != null) && (radio.BssSettings.LocationShareInterval > 0) && (radio.BssSettings.PacketFormat == 1) && (radio.BssSettings.BeaconMessage.Trim().Length > 0))
            {
                aprsTitleLabel.Text = "APRS - " + radio.BssSettings.BeaconMessage.Trim();
            }
            else
            {
                aprsTitleLabel.Text = "APRS";
            }

            // APRS Routes
            string selectedAprsRoute = aprsSelectedRoute;
            if ((aprsSelectedRoute == null) && (aprsRouteComboBox.SelectedItem != null)) { selectedAprsRoute = (string)aprsRouteComboBox.SelectedItem; }
            aprsRouteComboBox.Visible = ((aprsRoutes != null) && (aprsRoutes.Count > 1) && (allowTransmit));
            aprsRouteComboBox.Items.Clear();
            aprsRouteComboBox.Items.AddRange(aprsRoutes.Keys.ToArray());
            aprsRouteComboBox.SelectedItem = selectedAprsRoute;
            if (aprsRouteComboBox.SelectedIndex == -1) { aprsRouteComboBox.SelectedIndex = 0; }
            aprsSelectedRoute = null;

            // Terminal
            terminalInputTextBox.Enabled = ((radio.State == Radio.RadioState.Connected) && (activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal));
            terminalSendButton.Enabled = ((radio.State == Radio.RadioState.Connected) && (activeStationLock != null) && (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal));
            terminalConnectButton.Enabled = (radio.State == Radio.RadioState.Connected) && ((activeStationLock == null) || (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal));
            terminalConnectButton.Text = ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.Terminal)) ? "&Connect" : "&Disconnect";

            // BBS
            bbsConnectButton.Enabled = (radio.State == Radio.RadioState.Connected) && ((activeStationLock == null) || (activeStationLock.StationType == StationInfoClass.StationTypes.BBS));
            bbsConnectButton.Text = ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.BBS)) ? "&Activate" : "&Deactivate";

            // Torrent
            torrentConnectButton.Enabled = (radio.State == Radio.RadioState.Connected) && ((activeStationLock == null) || (activeStationLock.StationType == StationInfoClass.StationTypes.Torrent));
            torrentConnectButton.Text = ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.Torrent)) ? "&Activate" : "&Deactivate";

            // Mail
            mailConnectButton.Enabled = (radio.State == Radio.RadioState.Connected) && ((activeStationLock == null) || (activeStationLock.StationType == StationInfoClass.StationTypes.Winlink));
            mailConnectButton.Text = ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.Winlink)) ? "&Connect" : "&Disconnect";

            // ActiveLockToStation
            if ((activeStationLock == null) || (activeStationLock.StationType != StationInfoClass.StationTypes.Terminal) || (string.IsNullOrEmpty(activeStationLock.Name))) { terminalTitleLabel.Text = "Terminal"; }
            else { terminalTitleLabel.Text = "Terminal - " + activeStationLock.Name; }

            // Window title
            if ((callsign != null) && (callsign.Length >= 3))
            {
                this.Text = appTitle + " - " + callsign + ((stationId != 0) ? ("-" + stationId) : "");
            }
            else
            {
                this.Text = appTitle;
            }

            // System Tray
            notifyIcon.Visible = systemTrayToolStripMenuItem.Checked;
            this.ShowInTaskbar = !systemTrayToolStripMenuItem.Checked;
        }

        public void UpdateChannelsPanel()
        {
            channelsFlowLayoutPanel.SuspendLayout();
            int visibleChannels = 0;
            int channelHeight = 0;
            if ((channelControls != null) && (radio.Channels != null))
            {
                for (int i = 0; i < channelControls.Length; i++)
                {
                    if (radio.Channels[i] != null)
                    {
                        if (channelControls[i] == null)
                        {
                            channelControls[i] = new RadioChannelControl(this);
                            channelsFlowLayoutPanel.Controls.Add(channelControls[i]);
                        }
                        channelControls[i].Channel = radio.Channels[i];
                        channelControls[i].Tag = i;
                        bool visible = showAllChannels || (radio.Channels[i].name_str.Length > 0) || (radio.Channels[i].rx_freq != 0);
                        channelControls[i].Visible = visible;
                        if (visible) { visibleChannels++; }
                        channelHeight = channelControls[i].Height;
                    }
                }
                int hBlockCount = ((visibleChannels / 3) + (((visibleChannels % 3) != 0) ? 1 : 0));
                int blockHeight = 0;
                if (hBlockCount > 0)
                {
                    blockHeight = (radioPanel.Height - 310) / hBlockCount;
                    if (blockHeight > 50) { blockHeight = 50; }
                    for (int i = 0; i < channelControls.Length; i++)
                    {
                        if (channelControls[i] != null) { channelControls[i].Height = blockHeight; }
                    }
                }
                channelsFlowLayoutPanel.Height = blockHeight * hBlockCount;
            }
            channelsFlowLayoutPanel.Visible = (visibleChannels > 0);
            channelsFlowLayoutPanel.ResumeLayout();
        }

        private void settingsToolStripMenuItem_Click(object sender, EventArgs e)
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
                if (settingsForm.ShowDialog(this) == DialogResult.OK)
                {
                    // License Settings
                    callsign = settingsForm.CallSign;
                    stationId = settingsForm.StationId;
                    allowTransmit = settingsForm.AllowTransmit;
                    winlinkPassword = settingsForm.WinlinkPassword;
                    webServerEnabled = settingsForm.WebServerEnabled;
                    webServerPort = settingsForm.WebServerPort;
                    registry.WriteString("CallSign", callsign);
                    registry.WriteInt("StationId", stationId);
                    registry.WriteInt("AllowTransmit", allowTransmit ? 1 : 0);
                    registry.WriteInt("webServerEnabled", webServerEnabled ? 1 : 0);
                    registry.WriteInt("webServerPort", webServerPort);

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

                    CheckAprsChannel();
                    UpdateTabs();
                    UpdateInfo();
                }
            }
        }

        private void aprsDestinationComboBox_TextChanged(object sender, EventArgs e)
        {
            // Uppercase the callsign
            int selectionStart = aprsDestinationComboBox.SelectionStart;
            aprsDestinationComboBox.Text = aprsDestinationComboBox.Text.ToUpper();
            aprsDestinationComboBox.SelectionStart = selectionStart;

            AX25Address addr = AX25Address.GetAddress(aprsDestinationComboBox.Text);
            aprsDestinationComboBox.BackColor = (addr == null) ? Color.Salmon : SystemColors.Window;
            registry.WriteString("AprsDestination", aprsDestinationComboBox.Text);
        }

        private void volumeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (radioVolumeForm != null)
            {
                radioVolumeForm.Focus();
            }
            else
            {
                radio.GetVolumeLevel();
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
#if !__MonoCS__
            if (mapToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(mapTabPage); }
            registry.WriteInt("ViewMap", mapToolStripMenuItem.Checked ? 1 : 0);
#endif
            if (mailToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(mailTabPage); }
            if (terminalToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(terminalTabPage); }
            if (contactsToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(addressesTabPage); }
            if (bBSToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(bbsTabPage); }
            if (torrentToolStripMenuItem.Checked && allowTransmit) { mainTabControl.TabPages.Add(torrentTabPage); }
            if (packetsToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(packetsTabPage); }
            if (debugToolStripMenuItem.Checked) { mainTabControl.TabPages.Add(debugTabPage); }
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

        private void aprsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            aprsContextMenuStrip.Show(aprsMenuPictureBox, e.Location);
        }

        private void showAllMessagesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            registry.WriteInt("aprsViewAll", showAllMessagesToolStripMenuItem.Checked ? 1 : 0);
            foreach (ChatMessage n in aprsChatControl.Messages)
            {
                n.Visible = showAllMessagesToolStripMenuItem.Checked || (n.MessageType == PacketDataType.Message);
            }
            aprsChatControl.UpdateMessages(true);
        }

        private void aprsChatControl_MouseClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                selectedAprsMessage = aprsChatControl.GetChatMessageAtXY(e.X, e.Y);
                if (selectedAprsMessage != null) { aprsMsgContextMenuStrip.Show(aprsChatControl, e.Location); }
            }
        }

        private void copyMessageToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((selectedAprsMessage != null) && (string.IsNullOrEmpty(selectedAprsMessage.Message) == false))
            {
                Clipboard.SetText(selectedAprsMessage.Message);
            }
        }

        private void copyCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((selectedAprsMessage != null) && (string.IsNullOrEmpty(selectedAprsMessage.Route) == false))
            {
                Clipboard.SetText(selectedAprsMessage.Route);
            }
        }

        private void detailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (selectedAprsMessage == null) return;
            if (aprsDetailsForm == null)
            {
                aprsDetailsForm = new AprsDetailsForm(this);
                aprsDetailsForm.SetMessage(selectedAprsMessage);
                aprsDetailsForm.Show(this);
            }
            else
            {
                aprsDetailsForm.SetMessage(selectedAprsMessage);
                aprsDetailsForm.Focus();
            }
        }

        private void aprsChatControl_MouseDoubleClick(object sender, MouseEventArgs e)
        {
            selectedAprsMessage = aprsChatControl.GetChatMessageAtXY(e.X, e.Y);
            if (selectedAprsMessage != null)
            {
                if (aprsDetailsForm == null)
                {
                    aprsDetailsForm = new AprsDetailsForm(this);
                    aprsDetailsForm.SetMessage(selectedAprsMessage);
                    aprsDetailsForm.Show(this);
                }
                else
                {
                    aprsDetailsForm.SetMessage(selectedAprsMessage);
                    aprsDetailsForm.Focus();
                }
            }
        }

        private void mapZoomInbutton_Click(object sender, EventArgs e)
        {
#if !__MonoCS__
            mapControl.Zoom = Math.Max(mapControl.Zoom + 1, mapControl.MinZoom);
            mapControl.Update();
            mapControl.Refresh();
#endif
        }

        private void mapZoomOutButton_Click(object sender, EventArgs e)
        {
#if !__MonoCS__
            mapControl.Zoom = Math.Min(mapControl.Zoom - 1, mapControl.MaxZoom);
            mapControl.Update();
            mapControl.Refresh();
#endif
        }

#if !__MonoCS__
        private void mapControl_OnMapZoomChanged()
        {
            registry.WriteString("MapZoom", mapControl.Zoom.ToString());
        }

        private void mapControl_OnPositionChanged(GMap.NET.PointLatLng point)
        {
            registry.WriteString("MapLatitude", mapControl.Position.Lat.ToString());
            registry.WriteString("MapLongetude", mapControl.Position.Lng.ToString());
        }
#endif

        private void AddMapMarker(string callsign, double lat, double lng)
        {
#if !__MonoCS__
            foreach (GMarkerGoogle m in mapMarkersOverlay.Markers)
            {
                if (m.ToolTipText == callsign) { m.Position = new PointLatLng(lat, lng); return; }
            }
            GMarkerGoogle marker = new GMarkerGoogle(new PointLatLng(lat, lng), GMarkerGoogleType.red_dot);
            marker.ToolTipText = callsign;
            marker.ToolTipMode = MarkerTooltipMode.OnMouseOver;
            mapMarkersOverlay.Markers.Add(marker);
#endif
        }

        private void RemoveMapMarker(string callsign)
        {
#if !__MonoCS__
            GMarkerGoogle marker = null;
            foreach (GMarkerGoogle m in mapMarkersOverlay.Markers)
            {
                if (m.ToolTipText == callsign) { marker = m; break; }
            }
            mapMarkersOverlay.Markers.Remove(marker);
#endif
        }

        private void packetsListView_Resize(object sender, EventArgs e)
        {
            packetsListView.Columns[2].Width = packetsListView.Width - packetsListView.Columns[1].Width - packetsListView.Columns[0].Width - 28;
        }

        private void packetsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            packetsContextMenuStrip.Show(packetsMenuPictureBox, e.Location);
        }

        private void showPacketDecodeToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            registry.WriteInt("showPacketDecode", showPacketDecodeToolStripMenuItem.Checked ? 1 : 0);
            packetsSplitContainer.Panel2Collapsed = !showPacketDecodeToolStripMenuItem.Checked;
        }

        private void addPacketDecodeLine(int group, string title, string value)
        {
            ListViewItem l = new ListViewItem(new string[] { title, value });
            l.Group = packetDecodeListView.Groups[group];
            packetDecodeListView.Items.Add(l);
        }

        public string FragmentToShortString(TncDataFragment fragment)
        {
            StringBuilder sb = new StringBuilder();
            AX25Packet packet = AX25Packet.DecodeAX25Packet(fragment);
            if (packet == null)
            {
                return Utils.BytesToHex(fragment.data);
            }
            else
            {
                if (packet.addresses.Count > 1)
                {
                    AX25Address addr = packet.addresses[1];
                    sb.Append(addr.ToString() + ">");
                }
                if (packet.addresses.Count > 0)
                {
                    AX25Address addr = packet.addresses[0];
                    sb.Append(addr.ToString());
                }
                for (int i = 2; i < packet.addresses.Count; i++)
                {
                    AX25Address addr = packet.addresses[i];
                    sb.Append("," + addr.ToString() + ((addr.CRBit1) ? "*" : ""));
                }

                if (sb.Length > 0) { sb.Append(": "); }

                if ((fragment.channel_name == "APRS") && (packet.type == FrameType.U_FRAME))
                {
                    sb.Append(packet.dataStr);
                }
                else
                {
                    if (packet.type == FrameType.U_FRAME)
                    {
                        sb.Append(packet.type.ToString().Replace("_", "-"));
                        string hex = Utils.BytesToHex(packet.data);
                        if (hex.Length > 0) { sb.Append(": " + hex); }
                    }
                    else
                    {
                        sb.Append(packet.type.ToString().Replace("_", "-") + ", NR:" + packet.nr + ", NS:" + packet.ns);
                        string hex = Utils.BytesToHex(packet.data);
                        if (hex.Length > 0) { sb.Append(": " + hex); }
                    }
                }
            }
            return sb.ToString().Replace("\r", "").Replace("\n", "");
        }

        private void packetsListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            packetDecodeListView.Items.Clear();
            if (packetsListView.SelectedItems.Count == 0) return;
            ListViewItem l = packetsListView.SelectedItems[0];
            if (l.Tag == null) return;
            TncDataFragment fragment = (TncDataFragment)l.Tag;
            if (fragment.channel_id >= 0) { addPacketDecodeLine(0, "Channel", (fragment.incoming ? "Received" : "Sent") + " on " + (fragment.channel_id + 1)); }
            addPacketDecodeLine(0, "Time", fragment.time.ToString());
            if (fragment.data != null)
            {
                addPacketDecodeLine(0, "Size", fragment.data.Length + " byte" + (fragment.data.Length > 1 ? "s" : ""));
                addPacketDecodeLine(0, "Data", ASCIIEncoding.ASCII.GetString(fragment.data));
                addPacketDecodeLine(0, "Data HEX", Utils.BytesToHex(fragment.data));
            }

            StringBuilder sb = new StringBuilder();
            AX25Packet packet = AX25Packet.DecodeAX25Packet(fragment);
            if (packet == null)
            {
                addPacketDecodeLine(1, "Decode", "AX25 Decoder failed to decode packet.");
            }
            else
            {
                for (int i = 0; i < packet.addresses.Count; i++)
                {
                    sb.Clear();
                    AX25Address addr = packet.addresses[i];
                    sb.Append(addr.CallSignWithId);
                    sb.Append("  ");
                    sb.Append((addr.CRBit1) ? "X" : "-");
                    sb.Append((addr.CRBit2) ? "X" : "-");
                    sb.Append((addr.CRBit3) ? "X" : "-");
                    addPacketDecodeLine(1, "Address " + (i + 1), sb.ToString());
                }
                addPacketDecodeLine(1, "Type", packet.type.ToString().Replace("_", "-"));
                sb.Clear();
                sb.Append("NS:" + packet.ns + ", NR:" + packet.nr);
                if (packet.command) { sb.Append(", Command"); }
                if (packet.pollFinal) { sb.Append(", PollFinal"); }
                if (packet.modulo128) { sb.Append(", Modulo128"); }
                if (sb.Length > 2) { addPacketDecodeLine(1, "Control", sb.ToString()); }
                if (packet.pid > 0) { addPacketDecodeLine(1, "Protocol ID", packet.pid.ToString()); }
                if (packet.dataStr != null) { addPacketDecodeLine(2, "Data", packet.dataStr); }
                if (packet.data != null) { addPacketDecodeLine(2, "Data HEX", Utils.BytesToHex(packet.data)); }

                if (packet.pid == 242)
                {
                    byte[] decompressedData = null;
                    try { decompressedData = Utils.DecompressBrotli(packet.data); } catch { }
                    if (decompressedData != null)
                    {
                        addPacketDecodeLine(5, "Data", UTF8Encoding.UTF8.GetString(decompressedData));
                        addPacketDecodeLine(5, "Data HEX", Utils.BytesToHex(decompressedData));
                        byte[] deflateBuf = Utils.CompressDeflate(decompressedData);
                        addPacketDecodeLine(5, "Stats", $"Brotli {decompressedData.Length} --> {packet.data.Length}, Deflate would have been {deflateBuf.Length}");
                    }
                }

                if (packet.pid == 243)
                {
                    byte[] decompressedData = null;
                    try { decompressedData = Utils.DecompressDeflate(packet.data); } catch { }
                    if (decompressedData != null)
                    {
                        addPacketDecodeLine(5, "Data", UTF8Encoding.UTF8.GetString(decompressedData));
                        addPacketDecodeLine(5, "Data HEX", Utils.BytesToHex(decompressedData));
                        byte[] brotliBuf = Utils.CompressBrotli(decompressedData);
                        addPacketDecodeLine(5, "Stats", $"Deflate {decompressedData.Length} --> {packet.data.Length}, Brotli would have been {brotliBuf.Length}");
                    }
                }

                if ((packet.type == AX25Packet.FrameType.U_FRAME) && (packet.pid == 240))
                {
                    AprsPacket aprsPacket = AprsPacket.Parse(packet);
                    if (aprsPacket == null)
                    {
                        addPacketDecodeLine(3, "Decode", "APRS Decoder failed to decode packet.");
                    }
                    else
                    {
                        addPacketDecodeLine(3, "Type", aprsPacket.DataType.ToString());
                        if (aprsPacket.TimeStamp != null) { addPacketDecodeLine(3, "Time Stamp", aprsPacket.TimeStamp.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.DestCallsign.StationCallsign)) { addPacketDecodeLine(3, "Destination", aprsPacket.DestCallsign.StationCallsign.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.ThirdPartyHeader)) { addPacketDecodeLine(3, "ThirdParty Header", aprsPacket.ThirdPartyHeader); }
                        if (!string.IsNullOrEmpty(aprsPacket.InformationField)) { addPacketDecodeLine(3, "Information", aprsPacket.InformationField.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.Comment)) { addPacketDecodeLine(3, "Comment", aprsPacket.Comment.ToString()); }
                        if (aprsPacket.SymbolTableIdentifier != 0) { addPacketDecodeLine(3, "Symbol Code", aprsPacket.SymbolTableIdentifier.ToString()); }

                        if (aprsPacket.Position.Speed != 0) { addPacketDecodeLine(4, "Speed", aprsPacket.Position.Speed.ToString()); }
                        if (aprsPacket.Position.Altitude != 0) { addPacketDecodeLine(4, "Altitude", aprsPacket.Position.Altitude.ToString()); }
                        if (aprsPacket.Position.Ambiguity != 0) { addPacketDecodeLine(4, "Ambiguity", aprsPacket.Position.Ambiguity.ToString()); }
                        if (aprsPacket.Position.Course != 0) { addPacketDecodeLine(4, "Course", aprsPacket.Position.Course.ToString()); }
                        if (!string.IsNullOrEmpty(aprsPacket.Position.Gridsquare)) { addPacketDecodeLine(4, "Gridsquare", aprsPacket.Position.Gridsquare.ToString()); }
                        if (aprsPacket.Position.CoordinateSet.Latitude.Value != 0) { addPacketDecodeLine(4, "Latitude", aprsPacket.Position.CoordinateSet.Latitude.Value.ToString()); }
                        if (aprsPacket.Position.CoordinateSet.Longitude.Value != 0) { addPacketDecodeLine(4, "Longitude", aprsPacket.Position.CoordinateSet.Longitude.Value.ToString()); }
                    }
                }
            }
        }

        private void packetsListContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (packetsListView.SelectedItems.Count == 0) { e.Cancel = true; return; }
        }

        private void clearToolStripMenuItem_Click(object sender, EventArgs e)
        {
            debugTextBox.Clear();
        }

        private void showBluetoothFramesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            radio.PacketTrace = showBluetoothFramesToolStripMenuItem.Checked;
            registry.WriteInt("PacketTrace", showBluetoothFramesToolStripMenuItem.Checked ? 1 : 0);
        }

        private void debugMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            debugTabContextMenuStrip.Show(debugMenuPictureBox, e.Location);
        }

        private async void queryDeviceNamesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string[] deviceNames = await RadioBluetoothWin.GetDeviceNames();
            DebugTrace("List of devices:");
            foreach (string deviceName in deviceNames)
            {
                DebugTrace("  " + deviceName);
            }
        }

        private void aprsRouteComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            registry.WriteString("SelectedAprsRoute", (string)aprsRouteComboBox.Text);
        }

        private void showLocationToolStripMenuItem_Click(object sender, EventArgs e)
        {
#if !__MonoCS__
            if ((selectedAprsMessage == null) || ((selectedAprsMessage.Latitude == 0) && (selectedAprsMessage.Longitude == 0))) return;
            foreach (MapLocationForm form in mapLocationForms)
            {
                if (form.Callsign == selectedAprsMessage.SenderCallSign) { form.Focus(); return; }
            }
            MapLocationForm mapForm = new MapLocationForm(this, selectedAprsMessage.Route);
            mapForm.SetPosition(selectedAprsMessage.Latitude, selectedAprsMessage.Longitude);
            List<GMarkerGoogle> markers = new List<GMarkerGoogle>();
            foreach (GMarkerGoogle marker in mapMarkersOverlay.Markers) { markers.Add(marker); }
            mapForm.SetMarkers(markers.ToArray());
            mapLocationForms.Add(mapForm);
            mapForm.Show();
#endif
        }

        private void aprsMsgContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (selectedAprsMessage == null) return;
            showLocationToolStripMenuItem.Visible = ((selectedAprsMessage.Latitude != 0) && (selectedAprsMessage.Longitude != 0));
        }

        private void checkBluetoothButton_Click(object sender, EventArgs e)
        {
            CheckBluetooth();
        }

        private void CheckAprsChannel()
        {
            if ((allowTransmit == false) || (radio.State != Radio.RadioState.Connected) || (radio.Channels == null) || (radio.AllChannelsLoaded() == false))
            {
                aprsMissingChannelPanel.Visible = false;
                aprsChannel = -1;
                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
                return;
            }

            // Check if we have a APRS channel
            RadioChannelInfo channel = radio.GetChannelByName("APRS");
            if (channel != null)
            {
                aprsMissingChannelPanel.Visible = false;
                aprsChannel = channel.channel_id;
                if (aprsConfigurationForm != null) { aprsConfigurationForm.Close(); aprsConfigurationForm = null; }
            }
            else
            {
                aprsMissingChannelPanel.Visible = true;
                aprsChannel = -1;
            }
        }

        private void aprsSetupButton_Click(object sender, EventArgs e)
        {
            if (aprsConfigurationForm != null)
            {
                aprsConfigurationForm.Focus();
            }
            else
            {
                aprsConfigurationForm = new AprsConfigurationForm(this);
                aprsConfigurationForm.Show(this);
            }
        }

        private void allChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            showAllChannels = !allChannelsToolStripMenuItem.Checked;
            registry.WriteInt("ShowAllChannels", showAllChannels ? 1 : 0);
            UpdateChannelsPanel();
        }

        private void viewToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            allChannelsToolStripMenuItem.Checked = showAllChannels;
        }

        private void radioPanel_SizeChanged(object sender, EventArgs e)
        {
            UpdateChannelsPanel();
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

        private void packetDecodeListView_Resize(object sender, EventArgs e)
        {
            packetDecodeListView.Columns[1].Width = packetDecodeListView.Width - packetDecodeListView.Columns[0].Width - 28;
        }

        private void copyHEXValuesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetsListView.SelectedItems)
            {
                TncDataFragment frame = (TncDataFragment)l.Tag;
                sb.AppendLine(Utils.BytesToHex(frame.data));
            }
            if (sb.Length > 0) { Clipboard.SetText(sb.ToString()); }
        }

        private void saveToFileToolStripMenuItem_Click_1(object sender, EventArgs e)
        {
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetsListView.SelectedItems)
            {
                TncDataFragment frame = (TncDataFragment)l.Tag;
                sb.AppendLine(frame.time.Ticks + "," + (frame.incoming ? "1" : "0") + "," + frame.ToString());
            }
            if ((sb.Length > 0) && (savePacketsFileDialog.ShowDialog(this) == DialogResult.OK))
            {
                File.WriteAllText(savePacketsFileDialog.FileName, sb.ToString());
            }
        }

        private void saveToFileToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetsListView.Items)
            {
                TncDataFragment frame = (TncDataFragment)l.Tag;
                sb.AppendLine(frame.time.Ticks + "," + (frame.incoming ? "1" : "0") + "," + frame.ToString());
            }
            if ((sb.Length > 0) && (savePacketsFileDialog.ShowDialog(this) == DialogResult.OK))
            {
                File.WriteAllText(savePacketsFileDialog.FileName, sb.ToString());
            }
        }

        private void packetsContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            saveToFileToolStripMenuItem1.Enabled = (packetsListView.Items.Count > 0);
        }

        private void openFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (openPacketsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                PacketCaptureViewerForm form = new PacketCaptureViewerForm(this, openPacketsFileDialog.FileName);
                form.Show(this);
            }
        }

        private void copyToClipboardToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (packetDecodeListView.SelectedItems.Count == 0) return;
            StringBuilder sb = new StringBuilder();
            foreach (ListViewItem l in packetDecodeListView.SelectedItems)
            {
                sb.AppendLine(l.Text + ", " + l.SubItems[1].Text);
            }
            Clipboard.SetText(sb.ToString());
        }

        private void packetDataContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            copyToClipboardToolStripMenuItem.Visible = (packetDecodeListView.SelectedItems.Count > 0);
        }

        private void loopbackModeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            radio.LoopbackMode = loopbackModeToolStripMenuItem.Checked;
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

        private void mainAddressBookListView_SizeChanged(object sender, EventArgs e)
        {
            mainAddressBookListView.Columns[2].Width = mainAddressBookListView.Width - mainAddressBookListView.Columns[1].Width - mainAddressBookListView.Columns[0].Width - 28;
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
            aprsDestinationComboBox.Items.Clear();
            aprsDestinationComboBox.Items.Add("ALL");
            aprsDestinationComboBox.Items.Add("QST");
            aprsDestinationComboBox.Items.Add("CQ");

            foreach (StationInfoClass station in stations)
            {
                if (station.StationType == StationInfoClass.StationTypes.APRS) { aprsDestinationComboBox.Items.Add(station.Callsign); }
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

        private void mainAddressBookListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            editToolStripMenuItem.Visible = removeToolStripMenuItem.Visible = removeStationButton.Enabled = (mainAddressBookListView.SelectedItems.Count > 0);
            bool setMenuItemVisible = true;
            if (mainAddressBookListView.SelectedItems.Count != 1)
            {
                setMenuItemVisible = false;
            }
            else
            {
                StationInfoClass station = (StationInfoClass)mainAddressBookListView.SelectedItems[0].Tag;
                if (station.StationType == StationInfoClass.StationTypes.Terminal)
                {
                    setToolStripMenuItem.Enabled = ((radio.State == RadioState.Connected) && (terminalToolStripMenuItem.Checked));
                }
                else if (station.StationType == StationInfoClass.StationTypes.APRS)
                {
                    setToolStripMenuItem.Enabled = (radio.State == RadioState.Connected);
                }
                else
                {
                    setMenuItemVisible = false;
                }
            }
            setToolStripMenuItem.Visible = setMenuItemVisible;
        }

        private void exportStationsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (saveStationsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                File.WriteAllText(saveStationsFileDialog.FileName, StationInfoClass.Serialize(stations));
            }
        }

        private void importStationsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (openStationsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                // Import stations
                string stationsStr = null;
                try { stationsStr = File.ReadAllText(openStationsFileDialog.FileName); } catch (Exception) { }
                if (stationsStr != null)
                {
                    List<StationInfoClass> stations2 = StationInfoClass.Deserialize(stationsStr);
                    if (stations2 != null)
                    {
                        foreach (StationInfoClass station2 in stations2)
                        {
                            foreach (ListViewItem l in mainAddressBookListView.Items)
                            {
                                StationInfoClass station = (StationInfoClass)l.Tag;
                                if ((station2.Callsign == station.Callsign) && (station2.StationType == station.StationType))
                                {
                                    stations.Remove(station);
                                }
                            }
                        }
                        foreach (StationInfoClass station2 in stations2)
                        {
                            stations.Add(station2);
                        }
                        UpdateStations();
                    }
                    else
                    {
                        MessageBox.Show(this, "Invalid address book", "Stations", MessageBoxButtons.OK, MessageBoxIcon.Exclamation);
                    }
                }
                else
                {
                    MessageBox.Show(this, "Unable to open address book", "Stations", MessageBoxButtons.OK, MessageBoxIcon.Exclamation);
                }
            }
        }

        private void stationsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            stationsMenuPictureBox.ContextMenuStrip.Show(stationsMenuPictureBox, new Point(e.X, e.Y));
        }

        private void aprsDestinationComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            string stationStr = (string)aprsDestinationComboBox.Items[aprsDestinationComboBox.SelectedIndex];
            string aprsRoute = null;
            foreach (StationInfoClass station in stations)
            {
                if ((station.StationType == StationInfoClass.StationTypes.APRS) && (stationStr == station.Callsign)) { aprsRoute = station.APRSRoute; }
            }
            if (aprsRoute != null)
            {
                for (int i = 0; i < aprsRouteComboBox.Items.Count; i++)
                {
                    if (aprsRouteComboBox.Items[i].ToString() == aprsRoute)
                    {
                        aprsRouteComboBox.SelectedIndex = i;
                    }
                }
            }
        }

        public bool ActiveLockToStation(StationInfoClass station)
        {
            if (station == null)
            {
                if (session.CurrentState != AX25Session.ConnectionState.DISCONNECTED)
                {
                    session.Disconnect();
                    return false;
                }
                else
                {
                    if (activeStationsLock_oldSettings != null) { radio.WriteSettings(activeStationsLock_oldSettings); }
                    activeStationsLock_oldSettings = null;
                    if ((activeStationLock != null) && activeStationLock.WaitForConnection && (activeStationLock.StationType == StationInfoClass.StationTypes.Terminal)) { AppendTerminalString(false, null, null, "Stopped."); }
                    activeStationLock = null;
                    activeChannelIdLock = -1;
                    UpdateInfo();
                    UpdateRadioDisplay();
                    return true;
                }
            }

            if ((station.StationType != StationInfoClass.StationTypes.Terminal) && (station.StationType != StationInfoClass.StationTypes.Winlink)) return false;
            if (station.Channel == null) return false;
            if (radio.Channels == null) return false;

            int channelIdLock = -1;
            foreach (var channel in radio.Channels)
            {
                if ((channel != null) && (channel.name_str == station.Channel)) { channelIdLock = channel.channel_id; }
            }
            if (channelIdLock == -1)
            {
                MessageBox.Show(this, "Unable to change to channel \"" + station.Channel + "\".", "Terminal", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            activeStationLock = station;
            activeChannelIdLock = channelIdLock;

            // Store the old settings
            activeStationsLock_oldSettings = radio.Settings.ToByteArray();

            // Change to the new channel A and stop scan and dual view.
            radio.WriteSettings(radio.Settings.ToByteArray(activeChannelIdLock, radio.Settings.channel_b, 0, false, radio.Settings.squelch_level));

            UpdateInfo();
            UpdateRadioDisplay();

            if (activeStationLock.TerminalProtocol == StationInfoClass.TerminalProtocols.X25Session)
            {
                List<AX25Address> addresses = new List<AX25Address>();
                addresses.Add(AX25Address.GetAddress(station.Callsign));
                addresses.Add(AX25Address.GetAddress(callsign, stationId));
                session.Connect(addresses);
            }

            return true;
        }

        private void waitForConnectionToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (activeStationLock == null)
            {
                activeChannelIdLock = radio.Settings.channel_a;
                StationInfoClass station = new StationInfoClass();
                station.WaitForConnection = true;
                station.StationType = StationInfoClass.StationTypes.Terminal;
                station.TerminalProtocol = StationInfoClass.TerminalProtocols.X25Session;
                activeStationLock = station;
                UpdateInfo();
                UpdateRadioDisplay();
                terminalInputTextBox.Focus();
                AppendTerminalString(false, null, null, "Waiting for connection...");
            }
        }

        private void terminalConnectButton_Click(object sender, EventArgs e)
        {
            if (activeStationLock == null)
            {
                int terminalStationCount = 0;
                foreach (StationInfoClass station in stations)
                {
                    if (station.StationType == StationInfoClass.StationTypes.Terminal) { terminalStationCount++; }
                }

                if (terminalStationCount == 0)
                {
                    AddStationForm form = new AddStationForm(this);
                    form.FixStationType(StationInfoClass.StationTypes.Terminal);
                    if (form.ShowDialog(this) == DialogResult.OK)
                    {
                        StationInfoClass station = form.SerializeToObject();
                        stations.Add(station);
                        UpdateStations();
                        ActiveLockToStation(station);
                        terminalInputTextBox.Focus();
                    }
                }
                else
                {
                    ActiveStationSelectorForm form = new ActiveStationSelectorForm(this, StationInfoClass.StationTypes.Terminal);
                    DialogResult r = form.ShowDialog(this);
                    if (r == DialogResult.OK)
                    {
                        if (form.selectedStation != null)
                        {
                            ActiveLockToStation(form.selectedStation);
                            terminalInputTextBox.Focus();
                        }
                    }
                    else if (r == DialogResult.Yes)
                    {
                        AddStationForm aform = new AddStationForm(this);
                        aform.FixStationType(StationInfoClass.StationTypes.Terminal);
                        if (aform.ShowDialog(this) == DialogResult.OK)
                        {
                            StationInfoClass station = aform.SerializeToObject();
                            stations.Add(station);
                            UpdateStations();
                            ActiveLockToStation(station);
                            terminalInputTextBox.Focus();
                        }
                    }
                }
            }
            else
            {
                if (session.CurrentState != AX25Session.ConnectionState.DISCONNECTED)
                {
                    // Do a soft-disconnect
                    session.Disconnect();
                }
                else
                {
                    ActiveLockToStation(null);
                }
            }
        }

        private void terminalMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            terminalTabContextMenuStrip.Show(terminalMenuPictureBox, e.Location);
        }

        private void setToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainAddressBookListView.SelectedItems.Count != 1) return;
            StationInfoClass station = (StationInfoClass)mainAddressBookListView.SelectedItems[0].Tag;

            if ((station.StationType == StationInfoClass.StationTypes.APRS) && (radio.State == RadioState.Connected))
            {
                aprsDestinationComboBox.Text = station.Callsign;
                if (station.APRSRoute != null)
                {
                    for (int i = 0; i < aprsRouteComboBox.Items.Count; i++)
                    {
                        if (aprsRouteComboBox.Items[i].ToString() == station.APRSRoute)
                        {
                            aprsRouteComboBox.SelectedIndex = i;
                        }
                    }
                }
                mainTabControl.SelectedTab = aprsTabPage;
                aprsTextBox.Focus();

                // TODO: Switch to APRS frequency if not already there.
            }

            if ((station.StationType == StationInfoClass.StationTypes.Terminal) && (terminalToolStripMenuItem.Checked) && (radio.State == RadioState.Connected))
            {
                ActiveLockToStation(station);
                mainTabControl.SelectedTab = terminalTabPage;
                terminalInputTextBox.Focus();
            }
        }

        private void removeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            removeStationButton_Click(this, null);
        }

        private void aprsDestinationComboBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Allow letters, numbers, and the dash (-)
            if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != (char)Keys.Back)
            {
                e.Handled = true; // Block the input
            }
        }

        private void exportChannelsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if ((radio.State != RadioState.Connected) || (radio.Channels == null)) return;
            if (exportChannelsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                if (exportChannelsFileDialog.FilterIndex == 1)
                {
                    StringBuilder sb = new StringBuilder();
                    sb.AppendLine("title,tx_freq,rx_freq,tx_sub_audio(CTCSS=freq/DCS=number),rx_sub_audio(CTCSS=freq/DCS=number),tx_power(H/M/L),bandwidth(12500/25000),scan(0=OFF/1=ON),talk around(0=OFF/1=ON),pre_de_emph_bypass(0=OFF/1=ON),sign(0=OFF/1=ON),tx_dis(0=OFF/1=ON),mute(0=OFF/1=ON),rx_modulation(0=FM/1=AM),tx_modulation(0=FM/1=AM)");
                    foreach (RadioChannelInfo c in radio.Channels)
                    {
                        if ((c != null) && (c.tx_freq != 0) && (c.rx_freq != 0))
                        {
                            string power = "L";
                            if (c.tx_at_max_power) { power = "H"; }
                            if (c.tx_at_med_power) { power = "M"; }
                            string[] values = new string[] { c.name_str, c.tx_freq.ToString(), c.rx_freq.ToString(), c.tx_sub_audio.ToString(), c.rx_sub_audio.ToString(), power, c.bandwidth == RadioBandwidthType.NARROW ? "12500" : "25000", c.scan ? "1" : "0", c.talk_around ? "1" : "0", c.pre_de_emph_bypass ? "1" : "0", c.sign ? "1" : "0", c.tx_disable ? "1" : "0", c.mute ? "1" : "0", ((int)c.rx_mod).ToString(), ((int)c.tx_mod).ToString() };
                            sb.AppendLine(string.Join(",", values));
                        }
                    }
                    File.WriteAllText(exportChannelsFileDialog.FileName, sb.ToString());
                }
                if (exportChannelsFileDialog.FilterIndex == 2)
                {
                    StringBuilder sb = new StringBuilder();
                    sb.AppendLine("Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power");
                    for (int i = 0; i < radio.Channels.Length; i++)
                    {
                        RadioChannelInfo c = radio.Channels[i];
                        if ((c != null) && (c.tx_freq != 0) && (c.rx_freq != 0))
                        {
                            string duplex = "";
                            if (c.tx_freq < c.rx_freq) { duplex = "-"; }
                            if (c.tx_freq > c.rx_freq) { duplex = "+"; }

                            double offset = ((double)Math.Abs(c.tx_freq - c.rx_freq)) / 1000000;

                            // (None),Tone,TSQL,DTCS,DTCS-R,TSQL-R,Cross
                            string tone = "";
                            string rToneFreq = "";
                            string cToneFreq = "";
                            string DtcsCode = "";
                            string DtcsPolarity = "";
                            if ((c.tx_sub_audio >= 1000) && (c.rx_sub_audio >= 1000))
                            {
                                tone = "TONE";
                                rToneFreq = ((double)c.rx_sub_audio / 100).ToString();
                                cToneFreq = ((double)c.tx_sub_audio / 100).ToString();
                            }
                            else if ((c.tx_sub_audio > 0) && (c.rx_sub_audio > 0) && (c.tx_sub_audio < 1000) && (c.rx_sub_audio < 1000) && (c.rx_sub_audio == c.tx_sub_audio))
                            {
                                tone = "DTCS";
                                DtcsCode = c.rx_sub_audio.ToString();
                                DtcsPolarity = "NN";
                            }

                            string Mode = c.rx_mod.ToString();
                            if (c.rx_mod == RadioModulationType.FM)
                            {
                                if (c.bandwidth == RadioBandwidthType.WIDE) { Mode = "FM"; }
                                if (c.bandwidth == RadioBandwidthType.NARROW) { Mode = "NFM"; }
                            }

                            string Power = "";
                            if (c.tx_at_max_power) { Power = "5.0W"; }
                            else if (c.tx_at_med_power) { Power = "3.0W"; }
                            else { Power = "1.0W"; }

                            string[] values = new string[] { i.ToString(), c.name_str, (((double)c.rx_freq) / 1000000).ToString("F6"), duplex, offset.ToString("F6"), tone, rToneFreq, cToneFreq, DtcsCode, DtcsPolarity, Mode, "", "", Power };
                            sb.AppendLine(string.Join(",", values));
                        }
                    }
                    File.WriteAllText(exportChannelsFileDialog.FileName, sb.ToString());
                }
            }
        }

        public void importChannels(string filename)
        {
            List<RadioChannelInfo> importChannels = new List<RadioChannelInfo>();
            string[] lines = null;
            try { lines = File.ReadAllLines(filename); } catch (Exception ex) { MessageBox.Show(this, ex.ToString(), "File Error"); }
            if ((lines == null) || (lines.Length < 2)) return;
            Dictionary<string, int> headers = lines[0].Split(',').Select((h, i) => new { h, i }).ToDictionary(x => x.h.Trim(), x => x.i);

            // File format 1
            if (headers.ContainsKey("Location") && headers.ContainsKey("Name") && headers.ContainsKey("Frequency") && headers.ContainsKey("Mode"))
            {
                for (int i = 1; i < lines.Length; i++)
                {
                    RadioChannelInfo c = null;
                    try { c = ParseChannel1(lines[i].Split(','), headers); } catch (Exception) { }
                    if (c != null) { importChannels.Add(c); }
                }
            }

            // File format 2
            if (headers.ContainsKey("title") && headers.ContainsKey("tx_freq") && headers.ContainsKey("rx_freq"))
            {
                for (int i = 1; i < lines.Length; i++)
                {
                    RadioChannelInfo c = null;
                    try { c = ParseChannel2(lines[i].Split(','), headers); } catch (Exception) { }
                    if (c != null) { importChannels.Add(c); }
                }
            }

            // If there are decoded import channels, open a dialog box to merge them.
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

        private static RadioChannelInfo ParseChannel2(string[] parts, Dictionary<string, int> headers)
        {
            RadioChannelInfo r = new RadioChannelInfo();
            r.channel_id = 0;
            r.name_str = parts[headers["title"]];
            r.tx_freq = int.Parse(parts[headers["tx_freq"]]);
            r.rx_freq = int.Parse(parts[headers["rx_freq"]]);
            r.tx_sub_audio = int.Parse(parts[headers["tx_sub_audio(CTCSS=freq/DCS=number)"]]);
            r.rx_sub_audio = int.Parse(parts[headers["rx_sub_audio(CTCSS=freq/DCS=number)"]]);
            string power = parts[headers["tx_power(H/M/L)"]];
            r.tx_at_max_power = (power == "H");
            r.tx_at_med_power = (power == "M");
            r.bandwidth = (parts[headers["bandwidth(12500/25000)"]] == "25000") ? RadioBandwidthType.WIDE : RadioBandwidthType.NARROW;
            r.scan = (parts[headers["scan(0=OFF/1=ON)"]] == "1");
            r.talk_around = (parts[headers["talk around(0=OFF/1=ON)"]] == "1");
            r.pre_de_emph_bypass = (parts[headers["pre_de_emph_bypass(0=OFF/1=ON)"]] == "1");
            r.sign = (parts[headers["sign(0=OFF/1=ON)"]] == "1");
            r.tx_disable = (parts[headers["tx_dis(0=OFF/1=ON)"]] == "1");
            r.mute = (parts[headers["mute(0=OFF/1=ON)"]] == "1");
            string rx_mod = parts[headers["rx_modulation(0=FM/1=AM)"]];
            if (rx_mod == "AM") { r.rx_mod = RadioModulationType.AM; }
            if (rx_mod == "DMR") { r.rx_mod = RadioModulationType.DMR; }
            if (rx_mod == "FO") { r.rx_mod = RadioModulationType.FM; }
            string tx_mod = parts[headers["tx_modulation(0=FM/1=AM)"]];
            if (tx_mod == "AM") { r.tx_mod = RadioModulationType.AM; }
            if (tx_mod == "DMR") { r.tx_mod = RadioModulationType.DMR; }
            if (tx_mod == "FO") { r.tx_mod = RadioModulationType.FM; }
            return r;
        }

        private static RadioChannelInfo ParseChannel1(string[] parts, Dictionary<string, int> headers)
        {
            RadioChannelInfo r = new RadioChannelInfo();
            r.channel_id = int.Parse(parts[headers["Location"]]);
            r.name_str = parts[headers["Name"]];
            r.rx_freq = (int)(double.Parse(parts[headers["Frequency"]], CultureInfo.InvariantCulture) * 1000000);
            r.tx_at_max_power = true;
            r.tx_at_med_power = false;

            float powerWatts = -1;
            if (headers.ContainsKey("Power"))
            {
                if (parts[headers["Power"]].EndsWith("W")) { float.TryParse(parts[headers["Power"]].Substring(0, parts[headers["Power"]].Length - 1), out powerWatts); }
                if (powerWatts >= 0)
                {
                    if (powerWatts <= 1) { r.tx_at_max_power = false; r.tx_at_med_power = false; }
                    else if (powerWatts <= 4) { r.tx_at_max_power = false; r.tx_at_med_power = true; }
                    else { r.tx_at_max_power = true; r.tx_at_med_power = false; }
                }
            }

            int duplex = 0;
            if (headers.ContainsKey("Duplex"))
            {
                if (parts[headers["Duplex"]] == "-") { duplex = -1; }
                else if (parts[headers["Duplex"]] == "+") { duplex = 1; }
            }
            if (duplex == 0) { r.tx_freq = r.rx_freq; }
            else
            {
                int offset = (int)(double.Parse(parts[headers["Offset"]], CultureInfo.InvariantCulture) * 1000000);
                r.tx_freq = r.rx_freq + (duplex * offset);
            }

            string tone = "";
            if (headers.ContainsKey("Tone")) { tone = parts[headers["Tone"]]; }
            if ((tone == "Tone") || (tone == "TSQL"))
            {
                r.rx_sub_audio = headers.ContainsKey("rToneFreq") ? (int)(double.Parse(parts[headers["rToneFreq"]], CultureInfo.InvariantCulture) * 100) : 0;
                r.tx_sub_audio = headers.ContainsKey("cToneFreq") ? (int)(double.Parse(parts[headers["cToneFreq"]], CultureInfo.InvariantCulture) * 100) : 0;
            }
            if (tone == "DTCS")
            {
                r.tx_sub_audio = r.rx_sub_audio = headers.ContainsKey("DtcsCode") ? (int)(double.Parse(parts[headers["DtcsCode"]], CultureInfo.InvariantCulture)) : 0;
            }

            if (parts[headers["Mode"]] == "FM") { r.rx_mod = r.tx_mod = RadioModulationType.FM; r.bandwidth = RadioBandwidthType.WIDE; }
            if (parts[headers["Mode"]] == "NFM") { r.rx_mod = r.tx_mod = RadioModulationType.FM; r.bandwidth = RadioBandwidthType.NARROW; }
            if (parts[headers["Mode"]] == "DMR") { r.rx_mod = r.tx_mod = RadioModulationType.DMR; r.bandwidth = RadioBandwidthType.WIDE; }
            if (parts[headers["Mode"]] == "AM") { r.rx_mod = r.tx_mod = RadioModulationType.AM; r.bandwidth = RadioBandwidthType.WIDE; }

            return r;
        }

        private void bbsConnectButton_Click(object sender, EventArgs e)
        {
            if (activeStationLock != null)
            {
                if (activeStationLock.StationType == StationInfoClass.StationTypes.BBS)
                {
                    activeStationLock = null;
                    activeChannelIdLock = -1;
                    UpdateInfo();
                    UpdateRadioDisplay();
                }
            }
            else
            {
                activeChannelIdLock = radio.Settings.channel_a;
                activeStationLock = new StationInfoClass();
                activeStationLock.StationType = StationInfoClass.StationTypes.BBS;
                UpdateInfo();
                UpdateRadioDisplay();
            }
        }

        public delegate void UpdateBbsStatsHandler(BBS.StationStats stats);

        public void UpdateBbsStats(BBS.StationStats stats)
        {
            if (this.InvokeRequired) { this.Invoke(new UpdateBbsStatsHandler(UpdateBbsStats), stats); return; }

            ListViewItem l;
            if (stats.listViewItem == null)
            {
                l = new ListViewItem(new string[] { stats.callsign, "", "" });
                l.ImageIndex = 7;
                bbsListView.Items.Add(l);
                stats.listViewItem = l;
            }
            else { l = stats.listViewItem; }
            l.SubItems[1].Text = stats.lastseen.ToString();
            StringBuilder sb = new StringBuilder();
            sb.Append($"{stats.protocol}, {stats.packetsIn} in / {stats.packetsOut} out, {stats.bytesIn} in / {stats.bytesOut} out");
            l.SubItems[2].Text = sb.ToString();
        }

        private void viewTrafficToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bbsSplitContainer.Panel2Collapsed = !viewTrafficToolStripMenuItem.Checked;
            registry.WriteInt("ViewBbsTraffic", viewTrafficToolStripMenuItem.Checked ? 1 : 0);
        }

        private void clearStatsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bbsListView.Items.Clear();
            bbs.ClearStats();
        }

        private void pictureBox1_MouseClick(object sender, MouseEventArgs e)
        {
            bbsTabContextMenuStrip.Show(bbsMenuPictureBox, e.Location);
        }

        public delegate void AddBbsTrafficHandler(string callsign, bool outgoing, string text);
        public void AddBbsTraffic(string callsign, bool outgoing, string text)
        {
            if (this.InvokeRequired) { this.Invoke(new AddBbsTrafficHandler(AddBbsTraffic), callsign, outgoing, text); return; }

            if (bbsTextBox.Text.Length != 0) { bbsTextBox.AppendText(Environment.NewLine); }
            if (outgoing) { AppendBbsText(callsign + " < ", Color.Green); } else { AppendBbsText(callsign + " > ", Color.Green); }
            AppendBbsText(text, outgoing ? Color.CornflowerBlue : Color.Gainsboro);
            bbsTextBox.SelectionStart = bbsTextBox.Text.Length;
            bbsTextBox.ScrollToCaret();
        }

        public delegate void AddBbsControlMessageHandler(string text);
        public void AddBbsControlMessage(string text)
        {
            if (this.InvokeRequired) { this.Invoke(new AddBbsControlMessageHandler(AddBbsControlMessage), text); return; }
            if (bbsTextBox.Text.Length != 0) { bbsTextBox.AppendText(Environment.NewLine); }
            AppendBbsText(text, Color.Yellow);
            bbsTextBox.SelectionStart = bbsTextBox.Text.Length;
            bbsTextBox.ScrollToCaret();
        }

        public void AppendBbsText(string text, Color color)
        {
            bbsTextBox.SelectionStart = bbsTextBox.TextLength;
            bbsTextBox.SelectionLength = 0;
            bbsTextBox.SelectionColor = color;
            bbsTextBox.AppendText(text);
            bbsTextBox.SelectionColor = bbsTextBox.ForeColor;
        }

        private void bbsListView_Resize(object sender, EventArgs e)
        {
            bbsListView.Columns[2].Width = bbsListView.Width - bbsListView.Columns[1].Width - bbsListView.Columns[0].Width - 28;
        }

        public delegate void MailStateMessageHandler(string msg);
        public void MailStateMessage(string msg)
        {
            if (this.InvokeRequired) { this.Invoke(new MailStateMessageHandler(MailStateMessage), msg); return; }
            mailTransferStatusPanel.Visible = (msg != null);
            if (msg != null) { mailTransferStatusLabel.Text = msg; } else { mailTransferStatusLabel.Text = ""; }
            ;
        }

        private void exitToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            Application.Exit();
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

        private void beaconSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            using (EditBeaconSettingsForm beaconSettingsForm = new EditBeaconSettingsForm(this, radio))
            {
                if (beaconSettingsForm.ShowDialog(this) == DialogResult.OK) { }
            }
        }

        private void aprsTitleLabel_DoubleClick(object sender, EventArgs e)
        {
            if ((radio.State == RadioState.Connected) && (radio.BssSettings != null) && allowTransmit)
            {
                using (EditBeaconSettingsForm beaconSettingsForm = new EditBeaconSettingsForm(this, radio))
                {
                    if (beaconSettingsForm.ShowDialog(this) == DialogResult.OK) { }
                }
            }
        }

        private void mailMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            mailTabContextMenuStrip.Show(mailMenuPictureBox, e.Location);
        }

        private void showPreviewToolStripMenuItem_Click(object sender, EventArgs e)
        {
            mailboxHorizontalSplitContainer.Panel2Collapsed = !showPreviewToolStripMenuItem.Checked;
            registry.WriteInt("MailViewPreview", showPreviewToolStripMenuItem.Checked ? 1 : 0);
        }

        private void mailBoxesTreeView_NodeMouseClick(object sender, TreeNodeMouseClickEventArgs e)
        {
            if (e.Node == null) return;
            for (int i = 0; i < mailBoxesTreeView.Nodes.Count; i++)
            {
                if (e.Node == MailBoxTreeNodes[i])
                {
                    SelectedMailbox = i;
                }
            }
            UpdateMail();
        }

        private void newMailButton_Click(object sender, EventArgs e)
        {
            if (mailComposeForm != null)
            {
                mailComposeForm.Focus();
            }
            else
            {
                mailComposeForm = new MailComposeForm(this, null);
                mailComposeForm.Show(this);
            }
        }

        private void mailboxListView_DoubleClick(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count != 1) return;
            WinLinkMail m = (WinLinkMail)mailboxListView.SelectedItems[0].Tag;

            if ((SelectedMailbox == 1) || (SelectedMailbox == 2))
            {
                if (mailComposeForm != null)
                {
                    mailComposeForm.Focus();
                }
                else
                {
                    mailComposeForm = new MailComposeForm(this, m);
                    mailComposeForm.Show(this);
                }
            }
            else
            {
                new MailViewerForm(m).Show(this);
            }
        }

        private void mailboxListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            // Adjust menus
            viewMailToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0) && ((SelectedMailbox == 0) || (SelectedMailbox == 3) || (SelectedMailbox == 4) || (SelectedMailbox == 5));
            editMailToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0) && ((SelectedMailbox == 1) || (SelectedMailbox == 2));
            toolStripMenuItem14.Visible = (mailboxListView.SelectedItems.Count > 0);
            moveToDraftToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0) && (SelectedMailbox == 1);
            moveToOutboxToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0) && (SelectedMailbox == 2);
            moveToInboxToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0) && ((SelectedMailbox == 4) || (SelectedMailbox == 5));
            moveToArchiveToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0) && ((SelectedMailbox == 0) || (SelectedMailbox == 5));
            moveToTrashToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0) && ((SelectedMailbox == 0) || (SelectedMailbox == 4));
            toolStripMenuItem15.Visible = (mailboxListView.SelectedItems.Count > 0);
            deleteMailToolStripMenuItem.Visible = (mailboxListView.SelectedItems.Count > 0);

            // Adjust mail preview
            mailPreviewTextBox.Clear();
            if (mailboxListView.SelectedItems.Count == 0) return;
            WinLinkMail mail = (WinLinkMail)mailboxListView.SelectedItems[0].Tag;
            RtfBuilder rtfBuilder = new RtfBuilder();
            if (!string.IsNullOrEmpty(mail.From)) { rtfBuilder.AppendBold("From: "); rtfBuilder.AppendLine(mail.From); }
            if (!string.IsNullOrEmpty(mail.To)) { rtfBuilder.AppendBold("To: "); rtfBuilder.AppendLine(mail.To); }
            if (!string.IsNullOrEmpty(mail.Cc)) { rtfBuilder.AppendBold("Cc: "); rtfBuilder.AppendLine(mail.Cc); }
            rtfBuilder.AppendBold("Time: ");
            rtfBuilder.AppendLine(mail.DateTime.ToString());
            if (!string.IsNullOrEmpty(mail.Subject)) { rtfBuilder.AppendBold("Subject: "); rtfBuilder.AppendLine(mail.Subject); }
            if (mail.Attachements != null)
            {
                if (mail.Attachements.Count < 2) { rtfBuilder.AppendBold("Attachment: "); } else { rtfBuilder.AppendBold("Attachments: "); }
                bool first = true;
                foreach (WinLinkMailAttachement attachment in mail.Attachements)
                {
                    if (!first) { rtfBuilder.Append(", "); }
                    rtfBuilder.Append("\"" + attachment.Name + "\"");
                    first = false;
                }
                rtfBuilder.AppendLine("");
            }
            rtfBuilder.AppendLine("");
            if (!string.IsNullOrEmpty(mail.Body)) { rtfBuilder.Append(mail.Body); }
            mailPreviewTextBox.Rtf = rtfBuilder.ToRtf();
        }

        private void moveToDraftToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in mailboxListView.SelectedItems)
            {
                WinLinkMail m = (WinLinkMail)l.Tag;
                m.Mailbox = 2;
            }
            UpdateMail();
            SaveMails();
        }

        private void moveToOutboxToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in mailboxListView.SelectedItems)
            {
                WinLinkMail m = (WinLinkMail)l.Tag;
                m.Mailbox = 1;
            }
            UpdateMail();
            SaveMails();
        }

        private void moveToInboxToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in mailboxListView.SelectedItems)
            {
                WinLinkMail m = (WinLinkMail)l.Tag;
                m.Mailbox = 0;
            }
            UpdateMail();
            SaveMails();
        }

        private void moveToArchiveToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in mailboxListView.SelectedItems)
            {
                WinLinkMail m = (WinLinkMail)l.Tag;
                m.Mailbox = 4;
            }
            UpdateMail();
            SaveMails();
        }

        private void moveToTrashToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ListViewItem l in mailboxListView.SelectedItems)
            {
                WinLinkMail m = (WinLinkMail)l.Tag;
                m.Mailbox = 5;
            }
            UpdateMail();
            SaveMails();
        }

        private void deleteMailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;
            if (MessageBox.Show(this, "Permanently delete selected mails?", "Mail", MessageBoxButtons.OKCancel, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.OK)
            {
                foreach (ListViewItem l in mailboxListView.SelectedItems)
                {
                    WinLinkMail m = (WinLinkMail)l.Tag;
                    Mails.Remove(m);
                }
                UpdateMail();
                SaveMails();
            }
        }

        private void mailBoxesTreeView_DragEnter(object sender, DragEventArgs e)
        {
            // Convert screen coordinates to client coordinates
            Point clientPoint = mailBoxesTreeView.PointToClient(new Point(e.X, e.Y));

            // Get the TreeNode at the client point
            TreeNode n = mailBoxesTreeView.GetNodeAt(clientPoint);

            if (n == null) { e.Effect = DragDropEffects.None; return; }
            if (e.Data.GetDataPresent(typeof(WinLinkMail[])))
            {
                WinLinkMail[] mails = (WinLinkMail[])e.Data.GetData(typeof(WinLinkMail[]));
                if ((mails.Length > 0))
                {
                    int sourceMailBox = mails[0].Mailbox;
                    int destMailBox = (int)n.Tag;

                    bool allowedMove = false;
                    if ((sourceMailBox == 1) && (destMailBox == 2)) { allowedMove = true; }
                    if (((sourceMailBox == 0) || (sourceMailBox == 4) || (sourceMailBox == 5)) && ((destMailBox == 0) || (destMailBox == 4) || (destMailBox == 5))) { allowedMove = true; }

                    if ((sourceMailBox != destMailBox) && allowedMove)
                    {
                        e.Effect = DragDropEffects.Move;
                    }
                    else
                    {
                        e.Effect = DragDropEffects.None;
                    }
                }
                else
                {
                    e.Effect = DragDropEffects.None;
                }
            }
            else
            {
                e.Effect = DragDropEffects.None;
            }
        }

        private void mailBoxesTreeView_DragDrop(object sender, DragEventArgs e)
        {
            // Convert screen coordinates to client coordinates
            Point clientPoint = mailBoxesTreeView.PointToClient(new Point(e.X, e.Y));

            // Get the TreeNode at the client point
            TreeNode n = mailBoxesTreeView.GetNodeAt(clientPoint);

            if (n == null) { e.Effect = DragDropEffects.None; return; }
            if (e.Data.GetDataPresent(typeof(WinLinkMail[])))
            {
                WinLinkMail[] mails = (WinLinkMail[])e.Data.GetData(typeof(WinLinkMail[]));
                if ((mails.Length > 0))
                {
                    int sourceMailBox = mails[0].Mailbox;
                    int destMailBox = (int)n.Tag;

                    bool allowedMove = false;
                    if (((sourceMailBox == 1) || (sourceMailBox == 2)) && ((destMailBox == 1) || (destMailBox == 2))) { allowedMove = true; }
                    if (((sourceMailBox == 0) || (sourceMailBox == 4) || (sourceMailBox == 5)) && ((destMailBox == 0) || (destMailBox == 4) || (destMailBox == 5))) { allowedMove = true; }

                    if ((sourceMailBox != destMailBox) && allowedMove)
                    {
                        foreach (WinLinkMail mail in mails) { mail.Mailbox = destMailBox; }
                        UpdateMail();
                        SaveMails();
                    }
                }
            }
        }

        private void backupMailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (backupMailSaveFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                File.WriteAllText(backupMailSaveFileDialog.FileName, WinLinkMail.Serialize(Mails));
            }
        }

        private void restoreMailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (restoreMailOpenFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                string data = File.ReadAllText(restoreMailOpenFileDialog.FileName);
                List<WinLinkMail> restoreMails = WinLinkMail.Deserialize(data);
                bool change = false;
                foreach (WinLinkMail mail in restoreMails)
                {
                    if (IsMailMidPresent(mail.MID) == false) { Mails.Add(mail); change = true; }
                }
                if (change)
                {
                    UpdateMail();
                    SaveMails();
                }
            }
        }

        private bool IsMailMidPresent(string MID)
        {
            foreach (WinLinkMail m in Mails) { if (m.MID == MID) return true; }
            return false;
        }

        private void mailConnectButton_Click(object sender, EventArgs e)
        {
            if (activeStationLock == null)
            {
                int terminalStationCount = 0;
                foreach (StationInfoClass station in stations)
                {
                    if (station.StationType == StationInfoClass.StationTypes.Winlink) { terminalStationCount++; }
                }

                if (terminalStationCount == 0)
                {
                    AddStationForm form = new AddStationForm(this);
                    form.FixStationType(StationInfoClass.StationTypes.Winlink);
                    if (form.ShowDialog(this) == DialogResult.OK)
                    {
                        StationInfoClass station = form.SerializeToObject();
                        stations.Add(station);
                        UpdateStations();
                        ActiveLockToStation(station);
                    }
                }
                else
                {
                    ActiveStationSelectorForm form = new ActiveStationSelectorForm(this, StationInfoClass.StationTypes.Winlink);
                    DialogResult r = form.ShowDialog(this);
                    if (r == DialogResult.OK)
                    {
                        if (form.selectedStation != null)
                        {
                            ActiveLockToStation(form.selectedStation);
                        }
                    }
                    else if (r == DialogResult.Yes)
                    {
                        AddStationForm aform = new AddStationForm(this);
                        aform.FixStationType(StationInfoClass.StationTypes.Winlink);
                        if (aform.ShowDialog(this) == DialogResult.OK)
                        {
                            StationInfoClass station = aform.SerializeToObject();
                            stations.Add(station);
                            UpdateStations();
                            ActiveLockToStation(station);
                        }
                    }
                }
            }
            else
            {
                if (session.CurrentState != AX25Session.ConnectionState.DISCONNECTED)
                {
                    // Do a soft-disconnect
                    session.Disconnect();
                }
                else
                {
                    ActiveLockToStation(null);
                }
            }
        }

        private void clearPacketsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, "Clear packets?", "Packet Capture", MessageBoxButtons.OKCancel, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.OK)
            {
                packetsListView.Items.Clear();
                packetDecodeListView.Clear();
            }
        }

        private void showTrafficToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mailClientDebugForm.Visible)
            {
                mailClientDebugForm.Focus();
            }
            else
            {
                mailClientDebugForm.Show(this);
            }
        }

        private void MainForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (systemTrayToolStripMenuItem.Checked)
            {
                e.Cancel = true;
                this.Visible = false;
            }
            else
            {
                e.Cancel = false;
            }
        }

        private void mailboxListView_MouseDown(object sender, MouseEventArgs e)
        {
            _mailIsDragging = false;
            _mailMouseDownLocation = e.Location;
        }

        private void mailboxListView_MouseUp(object sender, MouseEventArgs e)
        {
            _mailIsDragging = false;
        }
        private void mailboxListView_MouseMove(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left && !_mailIsDragging)
            {
                int deltaX = Math.Abs(e.X - _mailMouseDownLocation.X);
                int deltaY = Math.Abs(e.Y - _mailMouseDownLocation.Y);

                // Adjust the threshold as needed. A larger value requires more movement.
                if (deltaX > SystemInformation.DragSize.Width || deltaY > SystemInformation.DragSize.Height)
                {
                    _mailIsDragging = true;

                    List<WinLinkMail> mails = new List<WinLinkMail>();
                    foreach (ListViewItem l in mailboxListView.SelectedItems)
                    {
                        WinLinkMail m = (WinLinkMail)l.Tag;
                        mails.Add(m);
                    }
                    DoDragDrop((object)mails.ToArray(), DragDropEffects.Copy | DragDropEffects.Move);
                }
            }
        }

        private void mailboxListView_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Delete)
            {
                deleteMailToolStripMenuItem_Click(this, null);
                e.Handled = true;
                return;
            }
            if ((e.KeyCode == Keys.A) && e.Control)
            {
                foreach (ListViewItem item in mailboxListView.Items) { item.Selected = true; }
            }
            e.Handled = false;
        }

        private void showToolStripMenuItem_Click(object sender, EventArgs e)
        {
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
            }
        }

        private void torrentActivateButton_Click(object sender, EventArgs e)
        {
            if (activeStationLock != null)
            {
                if (activeStationLock.StationType == StationInfoClass.StationTypes.Torrent)
                {
                    activeStationLock = null;
                    activeChannelIdLock = -1;
                    UpdateInfo();
                    UpdateRadioDisplay();
                }
            }
            else
            {
                activeChannelIdLock = radio.Settings.channel_a;
                activeStationLock = new StationInfoClass();
                activeStationLock.StationType = StationInfoClass.StationTypes.Torrent;
                UpdateInfo();
                UpdateRadioDisplay();
            }
        }
        private void torrentAddFileButton_Click(object sender, EventArgs e)
        {
            using (AddTorrentFileForm form = new AddTorrentFileForm(this))
            {
                if (form.ShowDialog() == DialogResult.OK) { AddTorrent(form.torrentFile); }
            }
        }

        private void AddTorrent(TorrentFile torrentFile)
        {
            ListViewItem l = new ListViewItem(new string[] { torrentFile.FileName, torrentFile.Mode.ToString(), torrentFile.Description });
            l.ImageIndex = 9;

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
        }

        private void torrentListView_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files.Length == 1)
                {
                    e.Effect = DragDropEffects.Copy;
                }
                else
                {
                    e.Effect = DragDropEffects.None;
                }
            }
            else
            {
                e.Effect = DragDropEffects.None;
            }
        }

        private void torrentListView_DragDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files.Length == 1)
                {
                    using (AddTorrentFileForm form = new AddTorrentFileForm(this))
                    {
                        if (form.Import(files[0]))
                        {
                            if (form.ShowDialog() == DialogResult.OK)
                            {
                                AddTorrent(form.torrentFile);
                            }
                        }

                    }
                }
            }
        }

        private void torrentListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count == 1)
            {
                TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;

                torrentPauseToolStripMenuItem.Visible = true;
                torrentPauseToolStripMenuItem.Checked = (file.Mode == TorrentFile.TorrentModes.Pause);
                torrentShareToolStripMenuItem.Visible = true;
                torrentShareToolStripMenuItem.Checked = (file.Mode == TorrentFile.TorrentModes.Sharing);
                torrentRequestToolStripMenuItem.Visible = true;
                torrentRequestToolStripMenuItem.Checked = (file.Mode == TorrentFile.TorrentModes.Request);
                torrentRequestToolStripMenuItem.Enabled = (file.Completed == false);
                toolStripMenuItem19.Visible = true;
                torrentSaveAsToolStripMenuItem.Visible = file.Completed;
                toolStripMenuItem20.Visible = true;
                torrentDeleteToolStripMenuItem.Visible = true;
            }
            else
            {
                torrentPauseToolStripMenuItem.Visible = false;
                torrentShareToolStripMenuItem.Visible = false;
                torrentRequestToolStripMenuItem.Visible = false;
                toolStripMenuItem19.Visible = false;
                torrentSaveAsToolStripMenuItem.Visible = false;
                toolStripMenuItem20.Visible = false;
                torrentDeleteToolStripMenuItem.Visible = false;
            }
        }

        private void torrentPauseToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count != 1) return;
            TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;
            file.Mode = TorrentFile.TorrentModes.Pause;
            file.ListViewItem.SubItems[1].Text = file.Mode.ToString();
        }

        private void torrentShareToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count != 1) return;
            TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;
            file.Mode = TorrentFile.TorrentModes.Sharing;
            file.ListViewItem.SubItems[1].Text = file.Mode.ToString();
        }

        private void torrentRequestToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count != 1) return;
            TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;
            file.Mode = TorrentFile.TorrentModes.Request;
            file.ListViewItem.SubItems[1].Text = file.Mode.ToString();
        }

        private void torrentContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            torrentListView_SelectedIndexChanged(sender, null);
        }

        private void torrentDeleteToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count != 1) return;
            if (MessageBox.Show(this, "Deleted selected torrent file?", "Torrent", MessageBoxButtons.OKCancel, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.OK)
            {
                TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;
                torrent.Remove(file);
                torrentListView.Items.Remove(torrentListView.SelectedItems[0]);
            }
        }

        private void torrentSaveAsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (torrentListView.SelectedItems.Count != 1) return;
            TorrentFile file = (TorrentFile)torrentListView.SelectedItems[0].Tag;
            if (file.Completed == false) return;
            byte[] filedata = file.GetFileData();
            torrentSaveFileDialog.FileName = file.FileName;
            if (torrentSaveFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                try
                {
                    File.WriteAllBytes(torrentSaveFileDialog.FileName, filedata);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, "Error saving file: " + ex.Message, "Torrent", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
    }
}
