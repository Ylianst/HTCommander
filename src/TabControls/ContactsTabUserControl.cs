/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class ContactsTabUserControl : UserControl, IRadioDeviceSelector
    {
        private int _preferredRadioDeviceId = -1;
        private DataBrokerClient broker;

        /// <summary>
        /// Gets or sets the preferred radio device ID for this control.
        /// </summary>
        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public int PreferredRadioDeviceId
        {
            get { return _preferredRadioDeviceId; }
            set { _preferredRadioDeviceId = value; }
        }
        private bool _showDetach = false;

        /// <summary>
        /// Gets or sets whether the "Detach..." menu item is visible.
        /// </summary>
        [System.ComponentModel.Category("Behavior")]
        [System.ComponentModel.Description("Gets or sets whether the Detach menu item is visible.")]
        [System.ComponentModel.DefaultValue(false)]
        public bool ShowDetach
        {
            get { return _showDetach; }
            set
            {
                _showDetach = value;
                if (detachToolStripMenuItem != null)
                {
                    detachToolStripMenuItem.Visible = value;
                    toolStripMenuItemDetachSeparator.Visible = value;
                }
            }
        }

        public ContactsTabUserControl()
        {
            InitializeComponent();

            // Enable double-buffering on the ListView to reduce flickering
            Utils.SetDoubleBuffered(mainAddressBookListView, true);

            // Initialize DataBroker client and subscribe to Stations changes
            broker = new DataBrokerClient();
            broker.Subscribe(0, "Stations", OnStationsChanged);

            // Load initial stations from DataBroker
            List<StationInfoClass> stations = broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());
            UpdateStationsInternal(stations);
        }

        private void OnStationsChanged(int deviceId, string name, object data)
        {
            if (data is List<StationInfoClass> stations)
            {
                UpdateStationsInternal(stations);
            }
        }

        private void UpdateStationsInternal(List<StationInfoClass> stations)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<List<StationInfoClass>>(UpdateStationsInternal), stations);
                return;
            }

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
        }

        private List<StationInfoClass> GetStations()
        {
            return broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());
        }

        private void SaveStations(List<StationInfoClass> stations)
        {
            broker.Dispatch(0, "Stations", stations);
        }

        public ListView AddressBookListView
        {
            get { return mainAddressBookListView; }
        }

        private void addStationButton_Click(object sender, EventArgs e)
        {
            AddStationForm form = new AddStationForm();
            if (form.ShowDialog(this) == DialogResult.OK)
            {
                StationInfoClass station = form.SerializeToObject();
                List<StationInfoClass> stations = GetStations();
                stations.Add(station);
                SaveStations(stations);
            }
        }

        private void removeStationButton_Click(object sender, EventArgs e)
        {
            if (mainAddressBookListView.SelectedItems.Count == 0) return;

            if (MessageBox.Show(this, "Remove selected station?", "Stations", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK)
            {
                List<StationInfoClass> stations = GetStations();
                foreach (ListViewItem l in mainAddressBookListView.SelectedItems)
                {
                    StationInfoClass station = (StationInfoClass)l.Tag;
                    stations.RemoveAll(s => s.Callsign == station.Callsign && s.StationType == station.StationType);
                }
                SaveStations(stations);
            }
            toolStripMenuItem10.Visible = editToolStripMenuItem.Visible = removeToolStripMenuItem.Visible = removeStationButton.Enabled = (mainAddressBookListView.SelectedItems.Count > 0);
            editButton.Enabled = (mainAddressBookListView.SelectedItems.Count == 1);
        }

        private void mainAddressBookListView_DoubleClick(object sender, EventArgs e)
        {
            if (mainAddressBookListView.SelectedItems.Count != 1) return;

            StationInfoClass station = (StationInfoClass)mainAddressBookListView.SelectedItems[0].Tag;
            AddStationForm form = new AddStationForm();
            form.DeserializeFromObject(station);
            if (form.ShowDialog(this) == DialogResult.OK)
            {
                StationInfoClass updatedStation = form.SerializeToObject();
                List<StationInfoClass> stations = GetStations();

                // Remove the old station entry
                stations.RemoveAll(s => s.Callsign == station.Callsign && s.StationType == station.StationType);

                // Add the updated station
                stations.Add(updatedStation);
                SaveStations(stations);

                // Dispatch event for active station lock update if needed
                broker.Dispatch(0, "StationUpdated", updatedStation, store: false);
            }
        }

        private void mainAddressBookListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            toolStripMenuItem10.Visible = editToolStripMenuItem.Visible = removeToolStripMenuItem.Visible = removeStationButton.Enabled = (mainAddressBookListView.SelectedItems.Count > 0);
            editButton.Enabled = (mainAddressBookListView.SelectedItems.Count == 1);
        }

        private void mainAddressBookListView_Resize(object sender, EventArgs e)
        {
            if (mainAddressBookListView.Columns.Count >= 3)
            {
                mainAddressBookListView.Columns[2].Width = -2; // Auto-fill remaining width
            }
        }

        private void stationsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            stationsTabContextMenuStrip.Show(stationsMenuPictureBox, new Point(e.X, e.Y));
        }

        private void exportStationsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (saveStationsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                List<StationInfoClass> stations = GetStations();
                System.IO.File.WriteAllText(saveStationsFileDialog.FileName, StationInfoClass.Serialize(stations));
            }
        }

        private void importStationsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (openStationsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                string stationsStr = null;
                try { stationsStr = System.IO.File.ReadAllText(openStationsFileDialog.FileName); } catch (Exception) { }
                if (stationsStr != null)
                {
                    List<StationInfoClass> importedStations = StationInfoClass.Deserialize(stationsStr);
                    if (importedStations != null)
                    {
                        List<StationInfoClass> stations = GetStations();

                        // Remove existing stations that match imported ones
                        foreach (StationInfoClass importedStation in importedStations)
                        {
                            stations.RemoveAll(s => s.Callsign == importedStation.Callsign && s.StationType == importedStation.StationType);
                        }

                        // Add all imported stations
                        stations.AddRange(importedStations);
                        SaveStations(stations);
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

        private void removeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            removeStationButton_Click(this, null);
        }

        private void mainAddressBookListView_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Delete)
            {
                removeStationButton_Click(this, null);
                e.Handled = true;
            }
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<ContactsTabUserControl>("Contacts");
            form.Show();
        }

        private void stationsTabContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            toolStripMenuItem10.Visible = editToolStripMenuItem.Visible = removeToolStripMenuItem.Visible = removeStationButton.Enabled = (mainAddressBookListView.SelectedItems.Count > 0);
            editButton.Enabled = (mainAddressBookListView.SelectedItems.Count == 1);
        }
    }
}
