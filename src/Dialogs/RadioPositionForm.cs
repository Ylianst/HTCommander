using aprsparser;
using HTCommander.radio;
using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class RadioPositionForm : Form
    {
        private MainForm parent;
        private Radio radio;

        public RadioPositionForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
            if (this.radio.Position != null) { UpdatePosition(this.radio.Position); }
        }

        private void refrashButton_Click(object sender, EventArgs e)
        {
            radio.GetPosition();
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void addItem(string name, string value)
        {
            foreach (ListViewItem l in mainListView.Items)
            {
                if (l.SubItems[0].Text == name) { l.SubItems[1].Text = value; return; }
            }
            mainListView.Items.Add(new ListViewItem(new string[2] { name, value }));
        }

        public void UpdatePosition(RadioPosition position)
        {
            if (position.Status == Radio.RadioCommandState.SUCCESS)
            {
                addItem("Latitude", position.LatitudeStr);
                addItem("Longitude", position.LongitudeStr);
                if (position.Time != DateTime.MinValue)
                {
                    addItem("Accuracy", position.Accuracy.ToString() + " meters");
                    addItem("Altitude", position.Altitude.ToString() + " meters");
                    addItem("Speed", position.Speed.ToString());
                    addItem("Heading", position.Heading.ToString() + " degrees");
                    addItem("Received Time", position.ReceivedTime.ToString("yyyy-MM-dd HH:mm:ss"));
                    addItem("GPS Time Local", position.Time.ToString("yyyy-MM-dd HH:mm:ss"));
                    addItem("GPS Time UTC", position.TimeUTC.ToString("yyyy-MM-dd HH:mm:ss"));
                }
            }
            else
            {
                addItem("Status", "No GPS lock");
            }
        }

        private void RadioPositionForm_FormClosed(object sender, FormClosedEventArgs e)
        {
            //parent.radioPositionForm = null;
        }
    }
}
