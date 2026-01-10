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
using System.Windows.Forms;
using static HTCommander.StationInfoClass;

namespace HTCommander
{
    public partial class ActiveStationSelectorForm : Form
    {
        private MainForm parent;
        public StationInfoClass selectedStation = null;
        private StationInfoClass.StationTypes stationType;

        public ActiveStationSelectorForm(MainForm parent, StationInfoClass.StationTypes stationType)
        {
            this.parent = parent;
            this.stationType = stationType;
            InitializeComponent();
        }

        private void ActiveStationSelectorForm_Load(object sender, EventArgs e)
        {
            terminalPictureBox.Visible = (stationType == StationTypes.Terminal);
            mailPictureBox.Visible = (stationType == StationTypes.Winlink);
            UpdateStations();
        }

        private void UpdateStations()
        {
            /*
            mainListView.Items.Clear();
            foreach (StationInfoClass station in parent.stations)
            {
                if (station.StationType == stationType)
                {
                    string stationName = station.Callsign;
                    if (!string.IsNullOrEmpty(station.Name)) { stationName += ", " + station.Name; }
                    ListViewItem l = new ListViewItem(new string[] { stationName });
                    if (stationType == StationInfoClass.StationTypes.Terminal) { l.ImageIndex = 0; }
                    if (stationType == StationInfoClass.StationTypes.Winlink) { l.ImageIndex = 1; }
                    l.Tag = station;
                    mainListView.Items.Add(l);
                }
            }
            UpdateInfo();
            */
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            if (mainListView.SelectedItems.Count != 1) return;
            selectedStation = (StationInfoClass)mainListView.SelectedItems[0].Tag;
            this.DialogResult = DialogResult.OK;
        }

        private void newButton_Click(object sender, EventArgs e)
        {
            this.DialogResult = DialogResult.Yes;
        }

        private void mainListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void UpdateInfo()
        {
            removeButton.Enabled = editButton.Enabled = connectButton.Enabled = (mainListView.SelectedItems.Count == 1);
        }

        private void editToolStripMenuItem_Click(object sender, EventArgs e)
        {
            /*
            if (mainListView.SelectedItems.Count != 1) return;
            selectedStation = (StationInfoClass)mainListView.SelectedItems[0].Tag;
            AddStationForm aform = new AddStationForm(parent);
            aform.DeserializeFromObject(selectedStation);
            if (aform.ShowDialog(this) == DialogResult.OK)
            {
                StationInfoClass station = aform.SerializeToObject();
                StationInfoClass delstation = null;
                foreach (StationInfoClass station2 in parent.stations)
                {
                    if ((station2.Callsign == station.Callsign) && (station2.StationType == station.StationType))
                    {
                        delstation = station2;
                    }
                }
                if (delstation != null) { parent.stations.Remove(delstation); }
                parent.stations.Add(station);
                parent.UpdateStations();
                UpdateStations();
            }
            */
        }

        private void removeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainListView.SelectedItems.Count != 1) return;
            if (MessageBox.Show(parent, "Delete selected station?", "Station", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK)
            {
                selectedStation = (StationInfoClass)mainListView.SelectedItems[0].Tag;
                //parent.stations.Remove(selectedStation);
                //parent.UpdateStations();
                UpdateStations();
            }
        }

        private void mainListView_DoubleClick(object sender, EventArgs e)
        {
            okButton_Click(this, null);
        }

        private void editButton_Click(object sender, EventArgs e)
        {
            editToolStripMenuItem_Click(this, null);
        }

        private void removeButton_Click(object sender, EventArgs e)
        {
            removeToolStripMenuItem_Click(this, null);
        }
    }
}
