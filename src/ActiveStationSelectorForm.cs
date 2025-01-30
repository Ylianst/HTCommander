using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class ActiveStationSelectorForm : Form
    {
        private MainForm parent;
        public StationInfoClass selectedStation = null;

        public ActiveStationSelectorForm(MainForm parent)
        {
            this.parent = parent;
            InitializeComponent();
        }

        private void ActiveStationSelectorForm_Load(object sender, EventArgs e)
        {
            UpdateStations();
        }

        private void UpdateStations()
        {
            mainListView.Items.Clear();
            foreach (StationInfoClass station in parent.stations)
            {
                if (station.StationType == StationInfoClass.StationTypes.Terminal)
                {
                    string stationName = station.Callsign;
                    if (!string.IsNullOrEmpty(station.Name)) { stationName += ", " + station.Name; }
                    ListViewItem l = new ListViewItem(new string[] { stationName });
                    l.ImageIndex = 0;
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
        }

        private void removeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainListView.SelectedItems.Count != 1) return;
            if (MessageBox.Show(parent, "Delete selected station?", "Station", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK)
            {
                selectedStation = (StationInfoClass)mainListView.SelectedItems[0].Tag;
                parent.stations.Remove(selectedStation);
                parent.UpdateStations();
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
