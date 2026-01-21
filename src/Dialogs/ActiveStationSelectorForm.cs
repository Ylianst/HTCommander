/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class ActiveStationSelectorForm : Form
    {
        private DataBrokerClient broker;
        public StationInfoClass selectedStation = null;
        private StationInfoClass.StationTypes stationType;

        public ActiveStationSelectorForm(StationInfoClass.StationTypes stationType)
        {
            this.stationType = stationType;
            InitializeComponent();
            broker = new DataBrokerClient();
        }

        private void ActiveStationSelectorForm_Load(object sender, EventArgs e)
        {
            terminalPictureBox.Visible = (stationType == StationInfoClass.StationTypes.Terminal);
            mailPictureBox.Visible = (stationType == StationInfoClass.StationTypes.Winlink);
            UpdateStations();
        }

        private void UpdateStations()
        {
            mainListView.Items.Clear();
            List<StationInfoClass> stations = broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());
            foreach (StationInfoClass station in stations)
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
            if (mainListView.SelectedItems.Count != 1) return;
            selectedStation = (StationInfoClass)mainListView.SelectedItems[0].Tag;
            AddStationForm aform = new AddStationForm();
            aform.DeserializeFromObject(selectedStation);
            if (aform.ShowDialog(this) == DialogResult.OK)
            {
                StationInfoClass station = aform.SerializeToObject();
                List<StationInfoClass> stations = broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());
                
                // Find and remove existing station with same callsign and type
                StationInfoClass delstation = null;
                foreach (StationInfoClass station2 in stations)
                {
                    if ((station2.Callsign == station.Callsign) && (station2.StationType == station.StationType))
                    {
                        delstation = station2;
                    }
                }
                if (delstation != null) { stations.Remove(delstation); }
                stations.Add(station);
                broker.Dispatch(0, "Stations", stations, store: true);
                UpdateStations();
            }
        }

        private void removeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainListView.SelectedItems.Count != 1) return;
            if (MessageBox.Show(this, "Delete selected station?", "Station", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK)
            {
                selectedStation = (StationInfoClass)mainListView.SelectedItems[0].Tag;
                List<StationInfoClass> stations = broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());
                stations.Remove(selectedStation);
                broker.Dispatch(0, "Stations", stations, store: true);
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
