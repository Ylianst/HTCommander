/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

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

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://github.com/Ylianst/HTCommander/blob/main/docs/Paring.md");
        }
    }
}
