using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using aprsparser;

namespace HTCommander.Controls
{
    public partial class AprsTabUserControl : UserControl
    {
        private MainForm mainForm;
        private ChatMessage rightClickedMessage = null;
        private List<string[]> aprsRoutes = new List<string[]>();
        private int selectedAprsRoute = 0;

        public AprsTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;
            //this.aprsRoutes = routes;

            // Setup routes combobox
            UpdateAprsRoutesComboBox();

            // Load settings
            //showAllMessagesToolStripMenuItem.Checked = (mainForm.registry.ReadInt("ShowAllAprsMessages", 0) == 1);
        }

        public ChatControl ChatControl => aprsChatControl;

        public bool ShowAllMessages
        {
            get { return showAllMessagesToolStripMenuItem.Checked; }
            set { showAllMessagesToolStripMenuItem.Checked = value; }
        }

        public string DestinationCallsign
        {
            get { return aprsDestinationComboBox.Text; }
            set { aprsDestinationComboBox.Text = value; }
        }

        public int SelectedAprsRoute
        {
            get { return selectedAprsRoute; }
            set { selectedAprsRoute = value; }
        }

        public void SetMissingChannelVisible(bool visible)
        {
            aprsMissingChannelPanel.Visible = visible;
        }

        public void SetControlsEnabled(bool enabled)
        {
            aprsTextBox.Enabled = enabled;
            aprsSendButton.Enabled = enabled;
            aprsDestinationComboBox.Enabled = enabled;
        }

        public void AddDestinationCallsign(string callsign)
        {
            if (!aprsDestinationComboBox.Items.Contains(callsign))
            {
                aprsDestinationComboBox.Items.Add(callsign);
            }
        }

        public void UpdateAprsRoutesComboBox()
        {
            aprsRouteComboBox.Items.Clear();
            if (aprsRoutes.Count > 0)
            {
                foreach (string[] route in aprsRoutes)
                {
                    aprsRouteComboBox.Items.Add(route[0]);
                }
                if (selectedAprsRoute >= aprsRoutes.Count) { selectedAprsRoute = 0; }
                aprsRouteComboBox.SelectedIndex = selectedAprsRoute;
                aprsRouteComboBox.Visible = (aprsRoutes.Count > 1);
            }
            else
            {
                aprsRouteComboBox.Visible = false;
            }
        }

        public string[] GetSelectedRoute()
        {
            if (aprsRoutes.Count == 0) return null;
            if (selectedAprsRoute >= aprsRoutes.Count) selectedAprsRoute = 0;
            return aprsRoutes[selectedAprsRoute];
        }

        private void aprsMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            aprsContextMenuStrip.Show(aprsMenuPictureBox, e.Location);
        }

        private void aprsSendButton_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            string destination = aprsDestinationComboBox.Text.Trim().ToUpper();
            string message = aprsTextBox.Text;
            if (string.IsNullOrEmpty(destination) || string.IsNullOrEmpty(message)) return;

            //mainForm.SendAprsMessage(destination, message);
            aprsTextBox.Text = "";
        }

        private void aprsTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                aprsSendButton_Click(this, null);
            }
        }

        private void aprsDestinationComboBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if (e.KeyChar == (char)Keys.Enter)
            {
                e.Handled = true;
                aprsTextBox.Focus();
            }
            else if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != (char)Keys.Back)
            {
                e.Handled = true;
            }
        }

        private void aprsDestinationComboBox_TextChanged(object sender, EventArgs e)
        {
            int selectionStart = aprsDestinationComboBox.SelectionStart;
            aprsDestinationComboBox.Text = aprsDestinationComboBox.Text.ToUpper();
            aprsDestinationComboBox.SelectionStart = selectionStart;
        }

        private void aprsDestinationComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            aprsTextBox.Focus();
        }

        private void showAllMessagesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            //mainForm.registry.WriteInt("ShowAllAprsMessages", showAllMessagesToolStripMenuItem.Checked ? 1 : 0);
        }

        private void beaconSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            //mainForm.ShowBeaconSettingsForm();
        }

        private void aprsSmsButton_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            //mainForm.ShowAprsSmsForm();
        }

        private void weatherReportToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            //mainForm.ShowAprsWeatherForm();
        }

        private void aprsSetupButton_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            //mainForm.ShowAprsConfigurationForm();
        }

        private void requestPositionToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            string destination = aprsDestinationComboBox.Text.Trim().ToUpper();
            if (string.IsNullOrEmpty(destination)) return;
            //mainForm.SendAprsPositionRequest(destination);
        }

        private void aprsRouteComboBox_SelectionChangeCommitted(object sender, EventArgs e)
        {
            selectedAprsRoute = aprsRouteComboBox.SelectedIndex;
        }

        private void aprsTitleLabel_DoubleClick(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            //mainForm.ShowAprsConfigurationForm();
        }

        private void aprsChatControl_MouseClick(object sender, MouseEventArgs e)
        {
            /*
            if (e.Button == MouseButtons.Right)
            {
                rightClickedMessage = aprsChatControl.GetMessageAt(e.Location);
                if (rightClickedMessage != null)
                {
                    aprsMsgContextMenuStrip.Show(aprsChatControl, e.Location);
                }
            }
            */
        }

        private void aprsChatControl_MouseDoubleClick(object sender, MouseEventArgs e)
        {
            /*
            ChatMessage msg = aprsChatControl.GetMessageAt(e.Location);
            if (msg != null && msg.Tag is AprsPacket)
            {
                AprsPacket packet = (AprsPacket)msg.Tag;
                ShowAprsDetails(packet);
            }
            */
        }

        private void aprsMsgContextMenuStrip_Opening(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (rightClickedMessage == null)
            {
                e.Cancel = true;
                return;
            }
            AprsPacket packet = rightClickedMessage.Tag as AprsPacket;
            showLocationToolStripMenuItem.Enabled = (packet != null && packet.Position != null);
        }

        private void detailsToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedMessage != null && rightClickedMessage.Tag is AprsPacket)
            {
                AprsPacket packet = (AprsPacket)rightClickedMessage.Tag;
                ShowAprsDetails(packet);
            }
        }

        private void showLocationToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            if (rightClickedMessage != null && rightClickedMessage.Tag is AprsPacket)
            {
                AprsPacket packet = (AprsPacket)rightClickedMessage.Tag;
                if (packet.Position != null)
                {
                    //mainForm.ShowLocationOnMap(packet.Position.Latitude, packet.Position.Longitude, packet.SourceCallsign);
                }
            }
        }

        private void copyMessageToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedMessage != null)
            {
                Clipboard.SetText(rightClickedMessage.Message);
            }
        }

        private void copyCallsignToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (rightClickedMessage != null)
            {
                //Clipboard.SetText(rightClickedMessage.Callsign);
            }
        }

        private void ShowAprsDetails(AprsPacket packet)
        {
            //AprsDetailsForm form = new AprsDetailsForm();
            //form.SetPacket(packet);
            //form.ShowDialog(this);
        }
    }
}