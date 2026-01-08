using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander.Controls
{
    public partial class ContactsTabUserControl : UserControl
    {
        private MainForm mainForm;

        public ContactsTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;
        }

        public void UpdateStations(List<StationInfoClass> stations)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<List<StationInfoClass>>(UpdateStations), stations);
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

        public ListView AddressBookListView
        {
            get { return mainAddressBookListView; }
        }

        private void addStationButton_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;

            AddStationForm form = new AddStationForm(mainForm);
            if (form.ShowDialog(this) == DialogResult.OK)
            {
                StationInfoClass station = form.SerializeToObject();
                mainForm.stations.Add(station);
                mainForm.UpdateStations();
            }
        }

        private void removeStationButton_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            if (mainAddressBookListView.SelectedItems.Count == 0) return;

            if (MessageBox.Show(this, "Remove selected station?", "Stations", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK)
            {
                foreach (ListViewItem l in mainAddressBookListView.SelectedItems)
                {
                    StationInfoClass station = (StationInfoClass)l.Tag;
                    mainForm.stations.Remove(station);
                }
                mainForm.UpdateStations();
            }
        }

        private void mainAddressBookListView_DoubleClick(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            if (mainAddressBookListView.SelectedItems.Count != 1) return;

            StationInfoClass station = (StationInfoClass)mainAddressBookListView.SelectedItems[0].Tag;
            AddStationForm form = new AddStationForm(mainForm);
            form.DeserializeFromObject(station);
            if (form.ShowDialog(this) == DialogResult.OK)
            {
                station = form.SerializeToObject();
                foreach (ListViewItem l in mainAddressBookListView.Items)
                {
                    StationInfoClass station2 = (StationInfoClass)l.Tag;
                    if ((station2.Callsign == station.Callsign) && (station2.StationType == station.StationType))
                    {
                        mainForm.stations.Remove(station2);
                    }
                }
                mainForm.stations.Add(station);

                if ((mainForm.activeStationLock != null) && (mainForm.activeStationLock.StationType == station.StationType) && (mainForm.activeStationLock.Callsign == station.Callsign))
                {
                    mainForm.ActiveLockToStation(station);
                }

                mainForm.UpdateStations();
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
                    setToolStripMenuItem.Enabled = (mainForm != null) && (mainForm.radio.State == Radio.RadioState.Connected);
                }
                else if (station.StationType == StationInfoClass.StationTypes.APRS)
                {
                    setToolStripMenuItem.Enabled = (mainForm != null) && (mainForm.radio.State == Radio.RadioState.Connected);
                }
                else
                {
                    setMenuItemVisible = false;
                }
            }
            setToolStripMenuItem.Visible = setMenuItemVisible;
        }

        private void mainAddressBookListView_Resize(object sender, EventArgs e)
        {
            if (mainAddressBookListView.Columns.Count >= 3)
            {
                mainAddressBookListView.Columns[2].Width = mainAddressBookListView.Width - mainAddressBookListView.Columns[1].Width - mainAddressBookListView.Columns[0].Width - 28;
            }
        }

        private void stationsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            stationsTabContextMenuStrip.Show(stationsMenuPictureBox, new Point(e.X, e.Y));
        }

        private void exportStationsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;

            if (saveStationsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                System.IO.File.WriteAllText(saveStationsFileDialog.FileName, StationInfoClass.Serialize(mainForm.stations));
            }
        }

        private void importStationsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;

            if (openStationsFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                string stationsStr = null;
                try { stationsStr = System.IO.File.ReadAllText(openStationsFileDialog.FileName); } catch (Exception) { }
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
                                    mainForm.stations.Remove(station);
                                }
                            }
                        }
                        foreach (StationInfoClass station2 in stations2)
                        {
                            mainForm.stations.Add(station2);
                        }
                        mainForm.UpdateStations();
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

        private void setToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            if (mainAddressBookListView.SelectedItems.Count != 1) return;

            StationInfoClass station = (StationInfoClass)mainAddressBookListView.SelectedItems[0].Tag;

            if ((station.StationType == StationInfoClass.StationTypes.APRS) && (mainForm.radio.State == Radio.RadioState.Connected))
            {
                /*
                mainForm.aprsDestinationComboBox.Text = station.Callsign;
                if (station.APRSRoute != null)
                {
                    for (int i = 0; i < mainForm.aprsRouteComboBox.Items.Count; i++)
                    {
                        if (mainForm.aprsRouteComboBox.Items[i].ToString() == station.APRSRoute)
                        {
                            mainForm.aprsRouteComboBox.SelectedIndex = i;
                        }
                    }
                }
                */
                // Switch to APRS tab - handled by MainForm
            }

            if ((station.StationType == StationInfoClass.StationTypes.Terminal) && (mainForm.radio.State == Radio.RadioState.Connected))
            {
                mainForm.ActiveLockToStation(station);
                // Switch to terminal tab - handled by MainForm
            }
        }

        private void removeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            removeStationButton_Click(this, null);
        }
    }
}