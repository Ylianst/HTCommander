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
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AudioClipRenameDialog : Form
    {
        public string ClipName
        {
            get { return clipNameTextBox.Text.Trim(); }
            set { clipNameTextBox.Text = value; }
        }

        public AudioClipRenameDialog()
        {
            InitializeComponent();
        }

        public AudioClipRenameDialog(string currentName) : this()
        {
            ClipName = currentName;
        }

        private void AudioClipRenameDialog_Load(object sender, EventArgs e)
        {
            // Select all text for easy editing
            clipNameTextBox.SelectAll();
            clipNameTextBox.Focus();
            UpdateOkButton();
        }

        private void clipNameTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateOkButton();
        }

        private void UpdateOkButton()
        {
            // Gray out OK button if name is empty or only whitespace
            okButton.Enabled = !string.IsNullOrWhiteSpace(clipNameTextBox.Text);
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            if (!string.IsNullOrWhiteSpace(clipNameTextBox.Text))
            {
                DialogResult = DialogResult.OK;
                Close();
            }
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }
    }
}
