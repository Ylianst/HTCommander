/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.IO.Ports;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Speech.Synthesis;
using System.ComponentModel;
using HTCommander.radio;
using HTCommander.Dialogs;
using HTCommander.Gps;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace HTCommander
{
    public partial class SettingsForm : Form
    {
        private readonly FileDownloader _downloader;
        private readonly DataBrokerClient _settingsBroker;
        private CancellationTokenSource _cts;

        // Original GPS settings saved on load so Cancel can restore them
        private string _originalGpsPort;
        private int _originalGpsBaudRate;

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public bool AllowTransmit { get { return allowTransmitCheckBox.Checked; } set { allowTransmitCheckBox.Checked = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string CallSign { get { return callsignTextBox.Text; } set { callsignTextBox.Text = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public int StationId { get { return stationIdComboBox.SelectedIndex; } set { stationIdComboBox.SelectedIndex = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string AprsRoutes { get { return GetAprsRoutes(); } set { SetAprsRoutes(value); } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string WinlinkPassword { get { return winlinkPasswordTextBox.Text; } set { winlinkPasswordTextBox.Text = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public bool WinlinkUseStationId { get { return winlinkStationIdCheckBox.Checked; } set { winlinkStationIdCheckBox.Checked = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public bool WebServerEnabled { get { return webServerEnabledCheckBox.Checked; } set { webServerEnabledCheckBox.Checked = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public int WebServerPort { get { return (int)webPortNumericUpDown.Value; } set { if (value > 0) { webPortNumericUpDown.Value = value; } else { webPortNumericUpDown.Value = 8080; }; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public bool AgwpeServerEnabled { get { return agwpeServerEnabledCheckBox.Checked; } set { agwpeServerEnabledCheckBox.Checked = value; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public int AgwpeServerPort { get { return (int)agwpePortNumericUpDown.Value; } set { if (value > 0) { agwpePortNumericUpDown.Value = value; } else { agwpePortNumericUpDown.Value = 8000; }; } }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string VoiceLanguage {
            get { Utils.ComboBoxItem selected = (Utils.ComboBoxItem)languageComboBox.SelectedItem; return selected.Value; }
            set { foreach (Utils.ComboBoxItem item in languageComboBox.Items) { if (item.Value == value) { languageComboBox.SelectedItem = item; break; } } }
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string VoiceModel
        {
            get { Utils.ComboBoxItem selected = (Utils.ComboBoxItem)modelsComboBox.SelectedItem; return selected.Value; }
            set { if (value == "") { modelsComboBox.SelectedIndex = 0; return; } foreach(Utils.ComboBoxItem item in modelsComboBox.Items) { if (item.Value == value) { modelsComboBox.SelectedItem = item; break; } } }
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string Voice
        {
            get { return (string)voicesComboBox.SelectedItem; }
            set { foreach (string item in voicesComboBox.Items) { if (item == value) { voicesComboBox.SelectedItem = item; break; } } }
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public string GpsSerialPort
        {
            get { return gpsSerialPortComboBox.SelectedItem as string ?? "None"; }
            set { if (gpsSerialPortComboBox.Items.Contains(value)) gpsSerialPortComboBox.SelectedItem = value; else gpsSerialPortComboBox.SelectedIndex = 0; }
        }

        [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
        [Browsable(false)]
        public int GpsBaudRate
        {
            get { return gpsBaudRateComboBox.SelectedItem is int v ? v : 4800; }
            set { foreach (object item in gpsBaudRateComboBox.Items) { if (item is int baud && baud == value) { gpsBaudRateComboBox.SelectedItem = item; return; } } gpsBaudRateComboBox.SelectedIndex = 0; }
        }

        // https://huggingface.co/ggerganov/whisper.cpp/tree/main
        string[] models = new string[] {
            "None",
            "Tiny, 77.7 MB",
            "Tiny.en, 77.7 MB, English",
            "Base, 148 MB",
            "Base.en, 148 MB, English (Recommended)",
            "Small, 488 MB",
            "Small.en, 488 MB, English",
            "Medium, 1.53 GB",
            "Medium.en, 1.53 GB, English",
        };

        string[] languages = new string[] {
            "auto|Auto-detect",
            "af|Afrikaans",
            "ar|Arabic",
            "hy|Armenian",
            "az|Azerbaijani",
            "be|Belarusian",
            "bs|Bosnian",
            "bg|Bulgarian",
            "ca|Catalan",
            "zh|Chinese",
            "hr|Croatian",
            "cs|Czech",
            "da|Danish",
            "nl|Dutch",
            "en|English",
            "et|Estonian",
            "fi|Finnish",
            "fr|French",
            "gl|Galician",
            "de|German",
            "el|Greek",
            "he|Hebrew",
            "hi|Hindi",
            "hu|Hungarian",
            "is|Icelandic",
            "id|Indonesian",
            "it|Italian",
            "ja|Japanese",
            "kn|Kannada",
            "kk|Kazakh",
            "ko|Korean",
            "lv|Latvian",
            "lt|Lithuanian",
            "mk|Macedonian",
            "ms|Malay",
            "mr|Marathi",
            "mi|Maori",
            "ne|Nepali",
            "no|Norwegian",
            "fa|Persian",
            "pl|Polish",
            "pt|Portuguese",
            "ro|Romanian",
            "ru|Russian",
            "sr|Serbian",
            "sk|Slovak",
            "sl|Slovenian",
            "es|Spanish",
            "sw|Swahili",
            "sv|Swedish",
            "tl|Tagalog",
            "ta|Tamil",
            "th|Thai",
            "tr|Turkish",
            "uk|Ukrainian",
            "ur|Urdu",
            "vi|Vietnamese",
            "cy|Welsh"
        };

        public SettingsForm()
        {
            InitializeComponent();
            _downloader = new FileDownloader();
            _settingsBroker = new DataBrokerClient();
            _settingsBroker.Subscribe(1, "TestAirplaneServerResult", OnTestAirplaneServerResult);
            _settingsBroker.Subscribe(1, "GpsStatus", OnGpsStatusChanged);

            foreach (string language in languages)
            {
                string[] parts = language.Split('|');
                if (parts.Length == 2) { languageComboBox.Items.Add(new Utils.ComboBoxItem(parts[0], parts[1])); }
            }
            languageComboBox.SelectedIndex = 0;

            foreach (string model in models)
            {
                int i = model.IndexOf(',');
                string modelName = "";
                if (i > 0) { modelName = model.Substring(0, i); }
                modelsComboBox.Items.Add(new Utils.ComboBoxItem(modelName, model));
            }
            modelsComboBox.SelectedIndex = 0;

            try
            {
                SpeechSynthesizer synthesizer = new SpeechSynthesizer();
                System.Collections.ObjectModel.ReadOnlyCollection<InstalledVoice> voices = synthesizer.GetInstalledVoices();
                foreach (InstalledVoice voice in voices) { voicesComboBox.Items.Add(voice.VoiceInfo.Name); }
                if (voicesComboBox.Items.Count > 0)
                {
                    voicesComboBox.SelectedIndex = 0;
                    Voice = "Microsoft Zira Desktop";
                }
                synthesizer.Dispose();
            }
            catch (System.Runtime.InteropServices.COMException)
            {
                voicesComboBox.Items.Add("(Text-to-Speech not available)");
                voicesComboBox.SelectedIndex = 0;
                voicesComboBox.Enabled = false;
            }
            catch (Exception ex)
            {
                voicesComboBox.Items.Add("(Text-to-Speech not available)");
                voicesComboBox.SelectedIndex = 0;
                voicesComboBox.Enabled = false;
                Console.WriteLine($"Warning: Failed to load TTS voices: {ex.Message}");
            }

            // GPS Serial Port - "None" first, then COM ports sorted numerically
            RefreshSerialPorts();

            // GPS Baud Rate (common NMEA 0183 rates)
            foreach (int baud in new int[] { 4800, 9600, 19200, 38400, 57600, 115200 }) { gpsBaudRateComboBox.Items.Add(baud); }
            gpsBaudRateComboBox.SelectedIndex = 0; // 4800 is the NMEA 0183 default

            UpdateInfo();
        }

        public void MoveToTab(int tabIndex)
        {
            if (tabControl1.TabPages.Count > tabIndex) { tabControl1.SelectedIndex = tabIndex; }
        }

        private void SettingsForm_Load(object sender, EventArgs e)
        {
            // Load settings from DataBroker (device 0)
            LoadSettingsFromDataBroker();

            // Populate GPS status label from current status
            UpdateGpsStatusLabel();

            // Snapshot original GPS settings so Cancel can revert them
            _originalGpsPort     = GpsSerialPort;
            _originalGpsBaudRate = GpsBaudRate;

            // Dispatch GPS changes immediately as the user changes the combo boxes
            gpsSerialPortComboBox.SelectedIndexChanged += OnGpsComboChanged;
            gpsBaudRateComboBox.SelectedIndexChanged   += OnGpsComboChanged;

            // If there are no APRS routes, add the default one.
            if (aprsRoutesListView.Items.Count == 0) { AddAprsRouteString("Standard|APN000,WIDE1-1,WIDE2-2"); }
            UpdateInfo();
        }

        private void LoadSettingsFromDataBroker()
        {
            CallSign          = DataBroker.GetValue<string>(0, "CallSign", "");
            StationId         = DataBroker.GetValue<int>(0, "StationId", 0);
            AllowTransmit     = DataBroker.GetValue<int>(0, "AllowTransmit", 0) == 1;
            WebServerEnabled  = DataBroker.GetValue<int>(0, "webServerEnabled", 0) == 1;
            WebServerPort     = DataBroker.GetValue<int>(0, "webServerPort", 8080);
            AgwpeServerEnabled = DataBroker.GetValue<int>(0, "agwpeServerEnabled", 0) == 1;
            AgwpeServerPort   = DataBroker.GetValue<int>(0, "agwpeServerPort", 8000);
            VoiceLanguage     = DataBroker.GetValue<string>(0, "VoiceLanguage", "auto");
            VoiceModel        = DataBroker.GetValue<string>(0, "VoiceModel", "");
            Voice             = DataBroker.GetValue<string>(0, "Voice", "Microsoft Zira Desktop");

            string aprsRoutesStr = DataBroker.GetValue<string>(0, "AprsRoutes", "");
            if (!string.IsNullOrEmpty(aprsRoutesStr)) { AprsRoutes = aprsRoutesStr; }

            WinlinkPassword    = DataBroker.GetValue<string>(0, "WinlinkPassword", "");
            WinlinkUseStationId = DataBroker.GetValue<int>(0, "WinlinkUseStationId", 0) == 1;

            dump1090urlTextBox.Text = DataBroker.GetValue<string>(0, "AirplaneServer", "");

            GpsSerialPort = DataBroker.GetValue<string>(0, "GpsSerialPort", "None");
            GpsBaudRate   = DataBroker.GetValue<int>(0, "GpsBaudRate", 4800);
        }

        private void SaveSettingsToDataBroker()
        {
            DataBroker.Dispatch(0, "CallSign", CallSign);
            DataBroker.Dispatch(0, "StationId", StationId);
            DataBroker.Dispatch(0, "AllowTransmit", AllowTransmit ? 1 : 0);
            DataBroker.Dispatch(0, "webServerEnabled", WebServerEnabled ? 1 : 0);
            DataBroker.Dispatch(0, "webServerPort", WebServerPort);
            DataBroker.Dispatch(0, "agwpeServerEnabled", AgwpeServerEnabled ? 1 : 0);
            DataBroker.Dispatch(0, "agwpeServerPort", AgwpeServerPort);
            DataBroker.Dispatch(0, "VoiceLanguage", VoiceLanguage);
            DataBroker.Dispatch(0, "VoiceModel", VoiceModel);
            DataBroker.Dispatch(0, "Voice", Voice);
            DataBroker.Dispatch(0, "AprsRoutes", AprsRoutes);
            DataBroker.Dispatch(0, "WinlinkPassword", WinlinkPassword);
            DataBroker.Dispatch(0, "WinlinkUseStationId", WinlinkUseStationId ? 1 : 0);
            DataBroker.Dispatch(0, "AirplaneServer", dump1090urlTextBox.Text);
            DataBroker.Dispatch(0, "GpsSerialPort", GpsSerialPort);
            DataBroker.Dispatch(0, "GpsBaudRate", GpsBaudRate);
        }

        private string GetAprsRoutes()
        {
            StringBuilder sb = new StringBuilder();
            bool first = true;
            foreach (ListViewItem l in aprsRoutesListView.Items)
            {
                sb.Append((first ? "" : "|") + (string)l.Tag);
                first = false;
            }
            return sb.ToString();
        }

        private void SetAprsRoutes(string routesStr)
        {
            if (routesStr == null) return;
            string[] routes = routesStr.Split('|');
            foreach (string route in routes) { AddAprsRouteString(route); }
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://" + linkLabel1.Text);
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            SaveSettingsToDataBroker();
            _settingsBroker?.Dispose();
            Close();
        }

        private void UpdateInfo()
        {
            allowTransmitCheckBox.Enabled = (callsignTextBox.Text.Length >= 3);
            if (allowTransmitCheckBox.Enabled == false) { allowTransmitCheckBox.Checked = false; }
            webPortNumericUpDown.Enabled  = webServerEnabledCheckBox.Checked;
            agwpePortNumericUpDown.Enabled = agwpeServerEnabledCheckBox.Checked;

            if (callsignTextBox.Text.Length > 0)
            {
                winlinkAccountTextBox.Text    = callsignTextBox.Text + "@winlink.org";
                winlinkPasswordTextBox.Enabled = true;
            }
            else
            {
                winlinkAccountTextBox.Text    = "None";
                winlinkPasswordTextBox.Enabled = false;
            }

            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)modelsComboBox.SelectedItem;
            string filename = "ggml-" + selected.Value.ToLower() + ".bin";
            string appDataFilename = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", filename);
            downloadButton.Enabled = (_cts == null) && (modelsComboBox.SelectedIndex != 0) && !File.Exists(appDataFilename);
            deleteButton.Enabled   = (modelsComboBox.SelectedIndex != 0) && File.Exists(appDataFilename);

            bool ok = true;
            if (downloadButton.Enabled) { ok = false; }
            if (webPortNumericUpDown.Enabled && agwpePortNumericUpDown.Enabled && (webPortNumericUpDown.Value == agwpePortNumericUpDown.Value)) { ok = false; }
            okButton.Enabled = ok;

            dump1090testButton.Enabled = (dump1090urlTextBox.Text.Trim().Length > 0);
        }

        private void dump1090urlTextBox_TextChanged(object sender, EventArgs e)
        {
            dump1090testResultsLabel.Text = "";
            UpdateInfo();
        }

        private void dump1090testButton_Click(object sender, EventArgs e)
        {
            dump1090testButton.Enabled    = false;
            dump1090testResultsLabel.Text = "Testing...";
            DataBroker.Dispatch(1, "TestAirplaneServer", dump1090urlTextBox.Text.Trim(), store: false);
        }

        // ------------------------------------------------------------------
        // GPS status label
        // ------------------------------------------------------------------

        private void OnGpsStatusChanged(int deviceId, string name, object value)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { BeginInvoke(new Action<int, string, object>(OnGpsStatusChanged), deviceId, name, value); return; }
            UpdateGpsStatusLabel();
        }

        private void UpdateGpsStatusLabel()
        {
            string port   = DataBroker.GetValue<string>(0, "GpsSerialPort", "None");
            string status = DataBroker.GetValue<string>(1, "GpsStatus", "");

            if (string.IsNullOrEmpty(port) || port == "None")
            {
                gpsStatusLabel.Text = "No GPS device configured";
                return;
            }

            switch (status)
            {
                case "Connecting":      gpsStatusLabel.Text = "Connecting to GPS port..."; break;
                case "Communicating":   gpsStatusLabel.Text = "GPS communicating";         break;
                case "Disabled":        gpsStatusLabel.Text = "No GPS device configured";  break;
                case "PortError":       gpsStatusLabel.Text = "Unable to open GPS port";   break;
                case "Disconnected":    gpsStatusLabel.Text = "GPS disconnected";           break;
                default:                gpsStatusLabel.Text = "Waiting for GPS data...";   break;
            }
        }

        private void OnTestAirplaneServerResult(int deviceId, string name, object data)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { BeginInvoke(new Action<int, string, object>(OnTestAirplaneServerResult), deviceId, name, data); return; }
            dump1090testResultsLabel.Text = data as string ?? "Unknown result";
            UpdateInfo();
        }

        private void callsignTextBox_TextChanged(object sender, EventArgs e) { UpdateInfo(); }

        private void addAprsButton_Click(object sender, EventArgs e)
        {
            AddAprsRouteForm form = new AddAprsRouteForm();
            if (form.ShowDialog(this) == DialogResult.OK) { AddAprsRouteString(form.AprsRouteStr); }
        }

        private void AddAprsRouteString(string routeStr)
        {
            string[] route = routeStr.Split(',');

            ListViewItem delItem = null;
            foreach (ListViewItem i in aprsRoutesListView.Items) { if (i.Text == route[0]) { delItem = i; } }
            if (delItem != null) { aprsRoutesListView.Items.Remove(delItem); }

            ListViewItem l = new ListViewItem();
            l.Text = route[0];
            string t = route[1];
            if (route.Length > 2) { t += " thru " + route[2]; }
            if (route.Length > 3) { t += "," + route[3]; }
            if (route.Length > 4) { t += "," + route[4]; }
            l.Tag = routeStr;
            l.SubItems.Add(t);
            aprsRoutesListView.Items.Add(l);
        }

        private void aprsRoutesListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            editButton.Enabled = deleteAprsButton.Enabled = (aprsRoutesListView.SelectedItems.Count == 1);
        }

        private void deleteAprsButton_Click(object sender, EventArgs e)
        {
            if (aprsRoutesListView.SelectedItems.Count == 1)
            {
                ListViewItem l = aprsRoutesListView.SelectedItems[0];
                aprsRoutesListView.Items.Remove(l);
                if (aprsRoutesListView.Items.Count == 0) { AddAprsRouteString("Standard,APN000,WIDE1-1,WIDE2-2"); }
                UpdateInfo();
            }
        }

        private void editButton_Click(object sender, EventArgs e)
        {
            if (aprsRoutesListView.SelectedItems.Count == 1)
            {
                ListViewItem l = aprsRoutesListView.SelectedItems[0];
                AddAprsRouteForm form = new AddAprsRouteForm();
                form.AprsRouteStr = (string)l.Tag;
                if (form.ShowDialog(this) == DialogResult.OK)
                {
                    aprsRoutesListView.Items.Remove(l);
                    AddAprsRouteString(form.AprsRouteStr);
                    UpdateInfo();
                }
            }
        }

        private void callsignTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != (char)Keys.Back)
                e.Handled = true;
        }

        private void webServerEnabledCheckBox_CheckedChanged(object sender, EventArgs e) { UpdateInfo(); }

        private void linkLabel2_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://" + linkLabel2.Text);
        }

        private async void downloadButton_Click(object sender, EventArgs e)
        {
            string model = ((Utils.ComboBoxItem)modelsComboBox.SelectedItem).Value;
            string url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-" + model.ToLower() + ".bin?download=true";
            string filename = "ggml-" + model.ToLower() + ".bin";
            string filenamePart = "ggml-" + model.ToLower() + ".bin.part";
            string appDataFilename = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", filename);
            string appDataFilenamePart = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", filenamePart);
            File.Delete(appDataFilenamePart);

            try
            {
                _cts = new CancellationTokenSource();
                var progressIndicator = new Progress<DownloadProgressInfo>(ReportProgress);
                cancelDownloadButton.Visible = true;
                downloadButton.Enabled = false;
                await _downloader.DownloadFileAsync(url, appDataFilenamePart, progressIndicator, _cts);
            }
            catch (Exception ex)
            {
                cancelDownloadButton.Visible = false;
                MessageBox.Show($"An unexpected error occurred: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                UpdateInfo();
                return;
            }
            cancelDownloadButton.Visible = false;
            try { File.Move(appDataFilenamePart, appDataFilename); } catch (Exception) { }
            UpdateInfo();
        }

        private void ReportProgress(DownloadProgressInfo progressInfo)
        {
            if (progressInfo.Error != null)
            {
                MessageBox.Show($"Error: {progressInfo.Error.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                _cts?.Dispose(); _cts = null;
                UpdateInfo();
            }
            else if (progressInfo.IsCancelled)
            {
                MessageBox.Show("Download cancelled.", "Cancelled", MessageBoxButtons.OK, MessageBoxIcon.Information);
                _cts?.Dispose(); _cts = null;
                UpdateInfo();
            }
            else if (progressInfo.IsComplete)
            {
                progressBar.Visible = false;
                MessageBox.Show("Download completed successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                _cts?.Dispose(); _cts = null;
                UpdateInfo();
            }
            else
            {
                progressBar.Visible = true;
                progressBar.Value   = (int)progressInfo.Percentage;
            }
        }

        private void modelsComboBox_SelectedIndexChanged(object sender, EventArgs e) { UpdateInfo(); }

        private void deleteButton_Click(object sender, EventArgs e)
        {
            if (MessageBox.Show(this, "Delete selected model?", "Speech Model", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                string model = ((Utils.ComboBoxItem)modelsComboBox.SelectedItem).Value;
                string filename = "ggml-" + model.ToLower() + ".bin";
                string appDataFilename = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", filename);
                if (File.Exists(appDataFilename)) { File.Delete(appDataFilename); UpdateInfo(); }
            }
        }

        private void cancelDownloadButton_Click(object sender, EventArgs e)
        {
            if (_cts != null) { _cts.Cancel(); }
        }

        // ------------------------------------------------------------------
        // GPS combo — dispatch immediately; revert on Cancel
        // ------------------------------------------------------------------

        private void OnGpsComboChanged(object sender, EventArgs e)
        {
            DataBroker.Dispatch(0, "GpsSerialPort", GpsSerialPort);
            DataBroker.Dispatch(0, "GpsBaudRate",   GpsBaudRate);
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            if (_cts != null) { _cts.Cancel(); }
            // Restore the GPS settings that were active before the form was opened
            DataBroker.Dispatch(0, "GpsSerialPort", _originalGpsPort);
            DataBroker.Dispatch(0, "GpsBaudRate",   _originalGpsBaudRate);
            _settingsBroker?.Dispose();
            Close();
        }

        // ------------------------------------------------------------------
        // Audio device helpers
        // ------------------------------------------------------------------

        public static int GetDefaultOutputDeviceNumber()
        {
            var enumerator    = new MMDeviceEnumerator();
            var defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Console);
            string defaultId  = defaultDevice.ID;
            var devices       = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active);

            for (int i = 0; i < WaveOut.DeviceCount; i++)
            {
                var caps = WaveOut.GetCapabilities(i);
                foreach (var device in devices)
                    if (device.FriendlyName.StartsWith(caps.ProductName) && device.ID == defaultId)
                        return i;
            }
            return -1;
        }

        public static int GetDefaultInputDeviceNumber()
        {
            var enumerator    = new MMDeviceEnumerator();
            var defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
            string defaultId  = defaultDevice.ID;
            var devices       = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active);

            for (int i = 0; i < WaveIn.DeviceCount; i++)
            {
                var caps = WaveIn.GetCapabilities(i);
                foreach (var device in devices)
                    if (device.FriendlyName.StartsWith(caps.ProductName) && device.ID == defaultId)
                        return i;
            }
            return -1;
        }

        // ------------------------------------------------------------------
        // Serial port refresh (responds to device plug/unplug)
        // ------------------------------------------------------------------

        private void RefreshSerialPorts()
        {
            string selected = gpsSerialPortComboBox.SelectedItem as string;
            gpsSerialPortComboBox.Items.Clear();
            gpsSerialPortComboBox.Items.Add("None");
            string[] ports = SerialPort.GetPortNames();
            Array.Sort(ports, (a, b) => {
                int numA = int.TryParse(System.Text.RegularExpressions.Regex.Match(a, @"\d+").Value, out int na) ? na : 0;
                int numB = int.TryParse(System.Text.RegularExpressions.Regex.Match(b, @"\d+").Value, out int nb) ? nb : 0;
                return numA.CompareTo(numB);
            });
            foreach (string port in ports) { gpsSerialPortComboBox.Items.Add(port); }
            if (selected != null && gpsSerialPortComboBox.Items.Contains(selected))
                gpsSerialPortComboBox.SelectedItem = selected;
            else
                gpsSerialPortComboBox.SelectedIndex = 0;
        }

        protected override void WndProc(ref Message m)
        {
            const int WM_DEVICECHANGE         = 0x0219;
            const int DBT_DEVICEARRIVAL       = 0x8000;
            const int DBT_DEVICEREMOVECOMPLETE = 0x8004;
            if (m.Msg == WM_DEVICECHANGE &&
                (m.WParam.ToInt32() == DBT_DEVICEARRIVAL || m.WParam.ToInt32() == DBT_DEVICEREMOVECOMPLETE))
            {
                RefreshSerialPorts();
            }
            base.WndProc(ref m);
        }

        private void tncServerEnabledCheckBox_CheckedChanged(object sender, EventArgs e) { UpdateInfo(); }
        private void agwpePortNumericUpDown_ValueChanged(object sender, EventArgs e)      { UpdateInfo(); }
        private void webPortNumericUpDown_ValueChanged(object sender, EventArgs e)        { UpdateInfo(); }

        private void gpsStateButton_Click(object sender, EventArgs e)
        {
            // Pass the MainForm (this.Owner) as the owner so GpsDetailsForm
            // remains open if the SettingsForm is closed.
            GpsDetailsForm.ShowInstance(this.Owner ?? this);
        }
    }
}