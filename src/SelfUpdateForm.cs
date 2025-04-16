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
using System.Net.Http;
using System.Diagnostics;
using System.Windows.Forms;
using System.Threading.Tasks;

namespace HTCommander
{
    public partial class SelfUpdateForm: Form
    {
        public SelfUpdateForm()
        {
            InitializeComponent();
        }

        public static void CheckForUpdate(MainForm parent)
        {
            Task.Run(() => { CheckForUpdateEx(parent); });
        }

        private static async void CheckForUpdateEx(MainForm parent)
        {
            // Get the current version of the application
            float currentVersion = 0.0f;
            FileVersionInfo versionInfo = FileVersionInfo.GetVersionInfo(Application.ExecutablePath);
            string[] vers = versionInfo.FileVersion.Split('.');
            if (!float.TryParse(vers[0] + "." + vers[1], out currentVersion)) return;

            // Get online version
            string url = "https://raw.githubusercontent.com/Ylianst/HTCommander/refs/heads/main/releases/version.txt";
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

            // Display update dialog
            SelfUpdateForm updateForm = new SelfUpdateForm();
            updateForm.currentVersionLabel.Text = currentVersion.ToString();
            updateForm.onlineVersionLabel.Text = onlineVersion.ToString();
            updateForm.Show(parent);
        }

    }
}
