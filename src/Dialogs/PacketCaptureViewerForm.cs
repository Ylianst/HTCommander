/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Windows.Forms;
using HTCommander.Controls;

namespace HTCommander
{
    /// <summary>
    /// A form that displays packets loaded from a file using the PacketCaptureTabUserControl.
    /// </summary>
    public partial class PacketCaptureViewerForm : Form
    {
        private string filename;

        public PacketCaptureViewerForm(string filename)
        {
            this.filename = filename;
            InitializeComponent();
        }

        private void PacketCaptureViewerForm_Load(object sender, EventArgs e)
        {
            // Set the title to include the filename
            FileInfo fileInfo = new FileInfo(filename);
            Text = "Packet Viewer - " + fileInfo.Name;

            // Load the packets from the file
            PacketCaptureTabUserControl.Filename = filename;
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }
    }
}
