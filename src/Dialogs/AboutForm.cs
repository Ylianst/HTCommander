/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Diagnostics;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AboutForm : Form
    {
        public AboutForm()
        {
            InitializeComponent();
        }

        private void AboutForm_Load(object sender, EventArgs e)
        {
            var vers = FileVersionInfo.GetVersionInfo(Application.ExecutablePath).FileVersion.Split('.');
            mainTextBox.Text = mainTextBox.Text.Replace("{0}", $"{vers[0]}.{vers[1]}");
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.OK;
        }

        // Opens the URL from any LinkLabel
        private void linkLabel_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            if (sender is LinkLabel label)
            {
                Process.Start(new ProcessStartInfo("https://" + label.Text) { UseShellExecute = true });
            }
        }
    }
}
