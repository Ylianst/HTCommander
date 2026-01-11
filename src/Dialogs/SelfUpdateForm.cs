/*
Copyright 2026 Ylian Saint-Hilaire

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
using System.Threading;
using System.Net.Http;
using System.Diagnostics;
using System.Windows.Forms;
using System.Threading.Tasks;
using HTCommander.radio;

namespace HTCommander
{
    public partial class SelfUpdateForm: Form
    {
        private readonly FileDownloader _downloader;
        private CancellationTokenSource _cts;
        private static bool checkingForUpdate = false;

        public SelfUpdateForm()
        {
            InitializeComponent();
            _downloader = new FileDownloader();
        }

        public static void CheckForUpdate(MainForm parent)
        {
            Task.Run(() => { CheckForUpdateEx(parent); });
            DataBroker.Dispatch(0, "LastUpdateCheck", DateTime.Now.ToString());
        }

        private string updateUrlEx = null;
        public string updateUrl { get { return updateUrlEx; } set { updateUrlEx = value; } }

        public string currentVersionText
        {
            get { return currentVersionLabel.Text; }
            set { currentVersionLabel.Text = value; }
        }
        public string onlineVersionText
        {
            get { return onlineVersionLabel.Text; }
            set { onlineVersionLabel.Text = value; }
        }

        private static async void CheckForUpdateEx(MainForm parent)
        {
            if (checkingForUpdate == true) return;
            try
            {
                checkingForUpdate = true;
                // Get the current version of the application
                float currentVersion = 0.0f;
                FileVersionInfo versionInfo = FileVersionInfo.GetVersionInfo(Application.ExecutablePath);
                string[] vers = versionInfo.FileVersion.Split('.');
                if (!float.TryParse(vers[0] + "." + vers[1], out currentVersion)) return;

                // Get online version
                string url = "https://raw.githubusercontent.com/Ylianst/HTCommander/refs/heads/main/releases/version.txt?req=aa";
                float onlineVersion = 0.0f;
                string updateFileName = null;
                try
                {
                    HttpClient client = new HttpClient();
                    string content = await client.GetStringAsync(url);
                    string[] lines = content.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string line in lines)
                    {
                        if (line.StartsWith("version=")) { if (!float.TryParse(line.Substring(8).Trim(), out onlineVersion)) return; }
                        if (line.StartsWith("filename=")) { updateFileName = line.Substring(9).Trim(); }
                    }
                }
                catch (Exception) { }

                // Check if update is needed
                if (updateFileName == null) return;
                if (currentVersion == 0) return;
                if (onlineVersion == 0) return;
                if (onlineVersion <= currentVersion) return;

                parent.UpdateAvailable(currentVersion, onlineVersion, "https://raw.githubusercontent.com/Ylianst/HTCommander/refs/heads/main/releases/" + updateFileName);
            }
            catch (Exception) { }
            checkingForUpdate = false;
        }

        private void TriggerUpdate(string msiPath)
        {
            string originalUpdaterPath1 = "HtCommanderUpdater.exe";
            string originalUpdaterPath2 = "HtCommanderUpdater.dll";
            string originalUpdaterPath3 = "HtCommanderUpdater.runtimeconfig.json";
            string tempUpdaterPath1 = Path.Combine(Path.GetTempPath(), "HtCommanderUpdater.exe");
            string tempUpdaterPath2 = Path.Combine(Path.GetTempPath(), "HtCommanderUpdater.dll");
            string tempUpdaterPath3 = Path.Combine(Path.GetTempPath(), "HtCommanderUpdater.runtimeconfig.json");
            string fullExePath = System.Reflection.Assembly.GetExecutingAssembly().Location;

            try
            {
                // Copy Updater to a temp directory to avoid deletion during update
                File.Copy(originalUpdaterPath1, tempUpdaterPath1, true);
                File.Copy(originalUpdaterPath2, tempUpdaterPath2, true);
                File.Copy(originalUpdaterPath3, tempUpdaterPath3, true);
                string currentProcessName = Process.GetCurrentProcess().ProcessName;

                Process.Start(new ProcessStartInfo
                {
                    FileName = tempUpdaterPath1,
                    Arguments = $"\"{currentProcessName}\" \"{msiPath}\" \"{fullExePath}\"",
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show("Failed to start updater: " + ex.Message);
                return;
            }

            Application.Exit();
        }

        private async void okButton_Click(object sender, EventArgs e)
        {
            // Get application data path
            string appDataFilename = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", "Update.msi");
            string appDataFilenamePart = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander", "Update.msi.part");
            File.Delete(appDataFilename);
            File.Delete(appDataFilenamePart);

            try
            {
                // Prepare for download
                _cts = new CancellationTokenSource();
                var progressIndicator = new Progress<DownloadProgressInfo>(ReportProgress);

                // Start the download asynchronously
                okButton.Enabled = false;
                await _downloader.DownloadFileAsync(updateUrlEx, appDataFilename, progressIndicator, _cts);
            }
            catch (Exception ex) // Catch potential exceptions during setup/await if not caught by downloader
            {
                try { _cts.Cancel(); _cts.Dispose(); } catch (Exception) { }
                _cts = null;
                MessageBox.Show($"An unexpected error occurred: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                UpdateInfo();
                return;
            }
            UpdateInfo();
            try { File.Move(appDataFilenamePart, appDataFilename); } catch (Exception) { }
            TriggerUpdate(appDataFilename);
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
                //MessageBox.Show("Download completed successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
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

        private void UpdateInfo()
        {
            okButton.Enabled = (_cts == null);
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            if (_cts != null)
            {
                _cts.Cancel();
                _cts.Dispose();
                _cts = null;
            }
            DialogResult = DialogResult.Cancel;
        }
    }
}
