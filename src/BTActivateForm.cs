using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class BTActivateForm : Form
    {
        MainForm parent;

        public BTActivateForm(MainForm parent)
        {
            this.parent = parent;
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

        private void BTActivateForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            parent.bluetoothActivateForm = null;
        }
    }
}
