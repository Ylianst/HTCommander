using System;
using System.Diagnostics;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class BTAccessDeniedForm : Form
    {
        public BTAccessDeniedForm()
        {
            InitializeComponent();
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void bluetoothLinkLabel_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "ms-settings:bluetooth",
                UseShellExecute = true
            });
        }
    }
}
