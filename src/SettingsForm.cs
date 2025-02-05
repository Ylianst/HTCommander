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
using System.Text;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class SettingsForm : Form
    {
        public bool AllowTransmit { get { return allowTransmitCheckBox.Checked; } set { allowTransmitCheckBox.Checked = value; } }
        public string CallSign { get { return callsignTextBox.Text; } set { callsignTextBox.Text = value; } }
        public int StationId { get { return stationIdComboBox.SelectedIndex; } set { stationIdComboBox.SelectedIndex = value; } }

        public string AprsRoutes { get { return GetAprsRoutes(); } set { SetAprsRoutes(value); } }

        public bool WebServerEnabled { get { return webServerEnabledCheckBox.Checked; } set { webServerEnabledCheckBox.Checked = value; } }
        public int WebServerPort { get { return (int)webPortNumericUpDown.Value; } set { if (value > 0) { webPortNumericUpDown.Value = value; } else { webPortNumericUpDown.Value = 8080; }; } }

        public SettingsForm()
        {
            InitializeComponent();
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
    }
}
