using System;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class EditBeaconSettingsForm : Form
    {
        private MainForm parent;
        private Radio radio;

        public EditBeaconSettingsForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
        }

        private void EditBeaconSettingsForm_Load(object sender, EventArgs e)
        {
            if (radio.BssSettings == null) return;

            packetFormatComboBox.SelectedIndex = radio.BssSettings.PacketFormat;
            aprsCallsignTextBox.Text = radio.BssSettings.AprsCallsign + "-" + radio.BssSettings.AprsSsid.ToString();
            aprsMessageTextBox.Text = radio.BssSettings.BeaconMessage;
            shareLocationCheckBox.Checked = radio.BssSettings.ShouldShareLocation;
            sendVoltageCheckBox.Checked = radio.BssSettings.SendPwrVoltage;
            allowPositionCheckBox.Checked = radio.BssSettings.AllowPositionCheck;

            intervalComboBox.SelectedIndex = 0; // Off
            if (radio.BssSettings.LocationShareInterval >= 10) { intervalComboBox.SelectedIndex = 1; } // Every 10 seconds
            if (radio.BssSettings.LocationShareInterval >= 20) { intervalComboBox.SelectedIndex = 2; } // Every 20 seconds
            if (radio.BssSettings.LocationShareInterval >= 30) { intervalComboBox.SelectedIndex = 3; } // Every 30 seconds
            if (radio.BssSettings.LocationShareInterval >= 40) { intervalComboBox.SelectedIndex = 4; } // Every 40 seconds
            if (radio.BssSettings.LocationShareInterval >= 50) { intervalComboBox.SelectedIndex = 5; } // Every 50 seconds
            if (radio.BssSettings.LocationShareInterval >= (1 * 60)) { intervalComboBox.SelectedIndex = 6; } // Every 1 minute
            if (radio.BssSettings.LocationShareInterval >= (2 * 60)) { intervalComboBox.SelectedIndex = 7; } // Every 2 minutes
            if (radio.BssSettings.LocationShareInterval >= (3 * 60)) { intervalComboBox.SelectedIndex = 8; } // Every 3 minutes
            if (radio.BssSettings.LocationShareInterval >= (4 * 60)) { intervalComboBox.SelectedIndex = 9; } // Every 4 minutes
            if (radio.BssSettings.LocationShareInterval >= (5 * 60)) { intervalComboBox.SelectedIndex = 10; } // Every 5 minutes
            if (radio.BssSettings.LocationShareInterval >= (6 * 60)) { intervalComboBox.SelectedIndex = 11; } // Every 6 minutes
            if (radio.BssSettings.LocationShareInterval >= (7 * 60)) { intervalComboBox.SelectedIndex = 12; } // Every 7 minutes
            if (radio.BssSettings.LocationShareInterval >= (8 * 60)) { intervalComboBox.SelectedIndex = 13; } // Every 8 minutes
            if (radio.BssSettings.LocationShareInterval >= (9 * 60)) { intervalComboBox.SelectedIndex = 14; } // Every 9 minutes
            if (radio.BssSettings.LocationShareInterval >= (10 * 60)) { intervalComboBox.SelectedIndex = 15; } // Every 10 minutes
            if (radio.BssSettings.LocationShareInterval >= (15 * 60)) { intervalComboBox.SelectedIndex = 16; } // Every 15 minutes
            if (radio.BssSettings.LocationShareInterval >= (20 * 60)) { intervalComboBox.SelectedIndex = 17; } // Every 20 minutes
            if (radio.BssSettings.LocationShareInterval >= (25 * 60)) { intervalComboBox.SelectedIndex = 18; } // Every 25 minutes
            if (radio.BssSettings.LocationShareInterval >= (30 * 60)) { intervalComboBox.SelectedIndex = 19; } // Every 30 minutes

            UpdateInfo();
        }

        private void UpdateInfo()
        {
            bool ok = true;

            if (packetFormatComboBox.SelectedIndex == 0)
            {
                aprsCallsignTextBox.BackColor = SystemColors.Window;
                aprsCallsignTextBox.Enabled = false;
                aprsMessageTextBox.Enabled = false;
            }
            else
            {
                // Check callsign
                AX25Address addr = AX25Address.GetAddress(aprsCallsignTextBox.Text);
                aprsCallsignTextBox.BackColor = (addr == null) ? Color.MistyRose : SystemColors.Window;
                if (addr == null) { ok = false; }
                aprsCallsignTextBox.Enabled = true;
                aprsMessageTextBox.Enabled = true;
            }

            okButton.Enabled = ok;
        }

        private void aprsCallsignTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            if ((Control.ModifierKeys & Keys.Control) == Keys.Control) return;

            // Allow letters, numbers, and the dash (-)
            if (!char.IsLetterOrDigit(e.KeyChar) && e.KeyChar != '-' && e.KeyChar != (char)Keys.Back)
            {
                e.Handled = true; // Block the input
            }
        }

        private void aprsCallsignTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void packetFormatComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            byte[] x1 = radio.BssSettings.ToByteArray();
            byte[] x2 = new byte[x1.Length + 5];
            Array.Copy(x1, 0, x2, 5, x1.Length);
            RadioBssSettings r = new RadioBssSettings(x2);

            aprsCallsignTextBox.Text = radio.BssSettings.AprsCallsign + "-" + radio.BssSettings.AprsSsid.ToString();
            AX25Address addr = AX25Address.GetAddress(aprsCallsignTextBox.Text);
            if (addr != null) { r.AprsCallsign = addr.address; r.AprsSsid = addr.SSID; }
            r.PacketFormat = packetFormatComboBox.SelectedIndex;
            r.BeaconMessage = aprsMessageTextBox.Text;
            r.ShouldShareLocation = shareLocationCheckBox.Checked;
            r.SendPwrVoltage = sendVoltageCheckBox.Checked;
            r.AllowPositionCheck = allowPositionCheckBox.Checked;

            if (intervalComboBox.SelectedIndex == 0) { r.LocationShareInterval = 0; }
            if (intervalComboBox.SelectedIndex == 1) { r.LocationShareInterval = 10; }
            if (intervalComboBox.SelectedIndex == 2) { r.LocationShareInterval = 20; }
            if (intervalComboBox.SelectedIndex == 3) { r.LocationShareInterval = 30; }
            if (intervalComboBox.SelectedIndex == 4) { r.LocationShareInterval = 40; }
            if (intervalComboBox.SelectedIndex == 5) { r.LocationShareInterval = 50; }
            if (intervalComboBox.SelectedIndex == 6) { r.LocationShareInterval = (1 * 60); }
            if (intervalComboBox.SelectedIndex == 7) { r.LocationShareInterval = (2 * 60); }
            if (intervalComboBox.SelectedIndex == 8) { r.LocationShareInterval = (3 * 60); }
            if (intervalComboBox.SelectedIndex == 9) { r.LocationShareInterval = (4 * 60); }
            if (intervalComboBox.SelectedIndex == 10) { r.LocationShareInterval = (5 * 60); }
            if (intervalComboBox.SelectedIndex == 11) { r.LocationShareInterval = (6 * 60); }
            if (intervalComboBox.SelectedIndex == 12) { r.LocationShareInterval = (7 * 60); }
            if (intervalComboBox.SelectedIndex == 13) { r.LocationShareInterval = (8 * 60); }
            if (intervalComboBox.SelectedIndex == 14) { r.LocationShareInterval = (9 * 60); }
            if (intervalComboBox.SelectedIndex == 15) { r.LocationShareInterval = (10 * 60); }
            if (intervalComboBox.SelectedIndex == 16) { r.LocationShareInterval = (15 * 60); }
            if (intervalComboBox.SelectedIndex == 17) { r.LocationShareInterval = (20 * 60); }
            if (intervalComboBox.SelectedIndex == 18) { r.LocationShareInterval = (25 * 60); }
            if (intervalComboBox.SelectedIndex == 19) { r.LocationShareInterval = (30 * 60); }

            radio.SetBssSettings(r);

            DialogResult = DialogResult.OK;
        }
    }
}
