﻿/*
Copyright 2025 Ylian Saint-Hilaire

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

using aprsparser;
using System.Windows.Forms;
using static HTCommander.Radio;

namespace HTCommander
{
    public partial class RadioSelectorForm : Form
    {
        private MainForm parent;

        public string SelectedMac { get { return radiosListView.SelectedItems[0].SubItems[1].Text; } }

        public RadioSelectorForm(MainForm parent)
        {
            this.parent = parent;
            InitializeComponent();
        }

        private void RadioSelectorForm_Load(object sender, System.EventArgs e)
        {
            foreach (CompatibleDevice radio in parent.devices)
            {
                ListViewItem item = new ListViewItem(new string[] { radio.name, radio.mac });
                radiosListView.Items.Add(item);
            }
        }

        private void radiosListView_SelectedIndexChanged(object sender, System.EventArgs e)
        {
            okButton.Enabled = (radiosListView.SelectedItems.Count == 1);
        }

        private void okButton_Click(object sender, System.EventArgs e)
        {
            DialogResult = DialogResult.OK;
        }
    }
}
