/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using System;
using System.IO;
using System.IO.Pipes;
using System.Windows.Forms;
using System.Threading.Tasks;

namespace HTCommander
{
    public partial class MainForm : Form
    {
        private DataBrokerClient broker;

        public MainForm(string[] args)
        {
            bool multiInstance = false;
            foreach (string arg in args)
            {
                if (string.Compare(arg, "-multiinstance", true) == 0) { multiInstance = true; }
            }
            if (multiInstance == false) { StartPipeServer(); }

            InitializeComponent();

            // Set UI context for broker callbacks and create main form broker client
            DataBroker.SetUIContext(this);
            broker = new DataBrokerClient();

            aprsTabUserControl.Initialize(this);
            mapTabUserControl.Initialize(this);
            voiceTabUserControl.Initialize(this);
            mailTabUserControl.Initialize(this);
            terminalTabUserControl.Initialize(this);
            contactsTabUserControl.Initialize(this);
            bbsTabUserControl.Initialize(this);
            torrentTabUserControl.Initialize(this);
            packetCaptureTabUserControl.Initialize(this);
        }
        private void StartPipeServer()
        {
            Task.Run(() =>
            {
                while (true)
                {
                    using (var server = new NamedPipeServerStream(Program.PipeName))
                    using (var reader = new StreamReader(server))
                    {
                        server.WaitForConnection();
                        var message = reader.ReadLine();
                        //if (message == "show") { showToolStripMenuItem_Click(this, null); }
                    }
                }
            });
        }

        private void MainForm_Load(object sender, EventArgs e)
        {
            
        }

        private void aboutToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            broker.LogInfo("Opening About dialog");
            new AboutForm().ShowDialog(this);
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Application.Exit();
        }
    }
}
