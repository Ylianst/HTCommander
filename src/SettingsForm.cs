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
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Speech.Synthesis;
using HTCommander.radio;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace HTCommander
{
    public partial class SettingsForm : Form
    {
        private readonly FileDownloader _downloader;
        private CancellationTokenSource _cts;

        public bool AllowTransmit { get { return allowTransmitCheckBox.Checked; } set { allowTransmitCheckBox.Checked = value; } }
        public string CallSign { get { return callsignTextBox.Text; } set { callsignTextBox.Text = value; } }
        public int StationId { get { return stationIdComboBox.SelectedIndex; } set { stationIdComboBox.SelectedIndex = value; } }
        public string AprsRoutes { get { return GetAprsRoutes(); } set { SetAprsRoutes(value); } }
        public string WinlinkPassword { get { return winlinkPasswordTextBox.Text; } set { winlinkPasswordTextBox.Text = value; } }
        public bool WebServerEnabled { get { return webServerEnabledCheckBox.Checked; } set { webServerEnabledCheckBox.Checked = value; } }
        public int WebServerPort { get { return (int)webPortNumericUpDown.Value; } set { if (value > 0) { webPortNumericUpDown.Value = value; } else { webPortNumericUpDown.Value = 8080; }; } }
        public bool AgwpeServerEnabled { get { return agwpeServerEnabledCheckBox.Checked; } set { agwpeServerEnabledCheckBox.Checked = value; } }
        public int AgwpeServerPort { get { return (int)agwpePortNumericUpDown.Value; } set { if (value > 0) { agwpePortNumericUpDown.Value = value; } else { agwpePortNumericUpDown.Value = 8000; }; } }

        public string VoiceLanguage {
            get { Utils.ComboBoxItem selected = (Utils.ComboBoxItem)languageComboBox.SelectedItem; return selected.Value; }
            set { foreach (Utils.ComboBoxItem item in languageComboBox.Items) { if (item.Value == value) { languageComboBox.SelectedItem = item; break; } } }
        }

        public string VoiceModel
        {
            get { Utils.ComboBoxItem selected = (Utils.ComboBoxItem)modelsComboBox.SelectedItem; return selected.Value; }
            set { if (value == "") { modelsComboBox.SelectedIndex = 0; return; } foreach(Utils.ComboBoxItem item in modelsComboBox.Items) { if (item.Value == value) { modelsComboBox.SelectedItem = item; break; } } }
        }

        public string Voice
        {
            get { return (string)voicesComboBox.SelectedItem; }
            set { foreach (string item in voicesComboBox.Items) { if (item == value) { voicesComboBox.SelectedItem = item; break; } } }
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
            //"Large-v3-turbo-q5_0, 574 MB"
            //"Large-v1, 3.09 GB",
            //"Large-v2, 3.09 GB",
            //"Large-v3, 3.1 GB",
            //"Large-v3-turbo, 1.62 GB"
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

            SpeechSynthesizer synthesizer = new SpeechSynthesizer();
            System.Collections.ObjectModel.ReadOnlyCollection<InstalledVoice> voices = synthesizer.GetInstalledVoices();
            foreach (InstalledVoice voice in voices) { voicesComboBox.Items.Add(voice.VoiceInfo.Name); }
            voicesComboBox.SelectedIndex = 0;
            Voice = "Microsoft Zira Desktop";
            synthesizer.Dispose();

            UpdateInfo();
        }

        public void MoveToTab(int tabIndex)
        {
            if (tabControl1.TabPages.Count > tabIndex) { tabControl1.SelectedIndex = tabIndex; }
        }

        private void SettingsForm_Load(object sender, EventArgs e)
        {
            // If there are no ARPS routes, add the default one.
            if (aprsRoutesListView.Items.Count == 0) { AddAprsRouteString("Standard|APN000,WIDE1-1,WIDE2-2"); }
            UpdateInfo();
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
            //aprsRoutesListView.Clear();
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
            DialogResult = DialogResult.OK;
        }

        private void UpdateInfo()
        {
            allowTransmitCheckBox.Enabled = (callsignTextBox.Text.Length >= 3);
            if (allowTransmitCheckBox.Enabled == false) { allowTransmitCheckBox.Checked = false; }
            webPortNumericUpDown.Enabled = webServerEnabledCheckBox.Checked;
            agwpePortNumericUpDown.Enabled = agwpeServerEnabledCheckBox.Checked;

            if (callsignTextBox.Text.Length > 0)
            {
                winlinkAccountTextBox.Text = callsignTextBox.Text + "@winlink.org";
                winlinkPasswordTextBox.Enabled = true;
            }
            else
            {
                winlinkAccountTextBox.Text = "None";
                winlinkPasswordTextBox.Enabled = false;
            }

            // For the models, if the selected model is "None", disable the download button.
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)modelsComboBox.SelectedItem;
            string filename = "ggml-" + selected.Value.ToLower() + ".bin";
            string appDataFilename = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", filename);
            downloadButton.Enabled = (_cts == null) && (modelsComboBox.SelectedIndex != 0) && !File.Exists(appDataFilename);
            deleteButton.Enabled = (modelsComboBox.SelectedIndex != 0) && File.Exists(appDataFilename);

            // okButton
            okButton.Enabled = (downloadButton.Enabled == false);
        }

        private void callsignTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

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
                // If there are no ARPS routes, add the default one.
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
                if (form.ShowDialog(this) == DialogResult.OK) {
                    aprsRoutesListView.Items.Remove(l);
                    AddAprsRouteString(form.AprsRouteStr);
                    UpdateInfo();
                }
            }
        }

        private void callsignTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Allow letters, numbers, and the dash (-)
            if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != (char)Keys.Back)
            {
                e.Handled = true; // Block the input
            }
        }

        private void webServerEnabledCheckBox_CheckedChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void linkLabel2_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://" + linkLabel2.Text);
        }

        private async void downloadButton_Click(object sender, EventArgs e)
        {
            // Get application data path
            string model = ((Utils.ComboBoxItem)modelsComboBox.SelectedItem).Value;
            string url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-" + model.ToLower() + ".bin?download=true";
            string filename = "ggml-" + model.ToLower() + ".bin";
            string filenamePart = "ggml-" + model.ToLower() + ".bin.part";
            string appDataFilename = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", filename);
            string appDataFilenamePart = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", filenamePart);
            File.Delete(appDataFilenamePart);

            try
            {
                // Prepare for download
                _cts = new CancellationTokenSource();
                var progressIndicator = new Progress<DownloadProgressInfo>(ReportProgress);

                // Start the download asynchronously
                cancelDownloadButton.Visible = true;
                downloadButton.Enabled = false;
                await _downloader.DownloadFileAsync(url, appDataFilenamePart, progressIndicator, _cts);
            }
            catch (Exception ex) // Catch potential exceptions during setup/await if not caught by downloader
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
                _cts?.Dispose();
                _cts = null;
                UpdateInfo();
            }
            else if (progressInfo.IsCancelled)
            {
                MessageBox.Show("Download cancelled.", "Cancelled", MessageBoxButtons.OK, MessageBoxIcon.Information);
                _cts?.Dispose();
                _cts = null;
                UpdateInfo();
            }
            else if (progressInfo.IsComplete)
            {
                progressBar.Visible = false;
                MessageBox.Show("Download completed successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
                _cts?.Dispose();
                _cts = null;
                UpdateInfo();
            }
            else
            {
                progressBar.Visible = true;
                progressBar.Value = (int)progressInfo.Percentage;
            }
        }

        private void modelsComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

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

        private void cancelButton_Click(object sender, EventArgs e)
        {
            if (_cts != null) { _cts.Cancel(); }
        }

        public static int GetDefaultOutputDeviceNumber()
        {
            var enumerator = new MMDeviceEnumerator();
            var defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Console);
            string defaultId = defaultDevice.ID;

            var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active);

            for (int i = 0; i < WaveOut.DeviceCount; i++)
            {
                var caps = WaveOut.GetCapabilities(i);
                foreach (var device in devices)
                {
                    if (device.FriendlyName.StartsWith(caps.ProductName) && device.ID == defaultId)
                    {
                        return i;
                    }
                }
            }

            return -1;
        }

        public static int GetDefaultInputDeviceNumber()
        {
            var enumerator = new MMDeviceEnumerator();
            var defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
            string defaultId = defaultDevice.ID;

            var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active);

            for (int i = 0; i < WaveIn.DeviceCount; i++)
            {
                var caps = WaveIn.GetCapabilities(i);
                foreach (var device in devices)
                {
                    if (device.FriendlyName.StartsWith(caps.ProductName) && device.ID == defaultId)
                    {
                        return i;
                    }
                }
            }

            return -1;
        }

        private void tncServerEnabledCheckBox_CheckedChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }
    }
}
