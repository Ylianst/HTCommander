/*
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

using System;
using System.Linq;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AprsSmsForm : Form
    {
        public string PhoneNumber { get { return phoneNumberTextBox.Text; } }
        public string Message { get { return messageTextBox.Text; } }


        public AprsSmsForm()
        {
            InitializeComponent();
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start(linkLabel1.Text);
        }

        private void messageTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Check if the pressed character is in the restricted list
            char[] restrictedChars = { '~', '|', '}' };
            if (restrictedChars.Contains(e.KeyChar)) { e.Handled = true; return; }
        }

        private void UpdateInfo()
        {
            okButton.Enabled = (messageTextBox.Text.Length > 0) && (phoneNumberTextBox.Text.Length >= 10);
        }

        private void messageTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void phoneNumberTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void phoneNumberTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Check if the key pressed is not a digit or control key (like Backspace)
            if (!char.IsDigit(e.KeyChar) && !char.IsControl(e.KeyChar))
            {
                // Cancel the event if it's not a valid input
                e.Handled = true;
            }
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            MainForm.g_MainForm.registry.WriteString("SmsPhone", PhoneNumber);
            DialogResult = DialogResult.OK;
        }

        private void AprsSmsForm_Load(object sender, EventArgs e)
        {
            phoneNumberTextBox.Text = MainForm.g_MainForm.registry.ReadString("SmsPhone", "");
            if (phoneNumberTextBox.Text.Length == 0)
            {
                phoneNumberTextBox.Focus();
            }
            else
            {
                messageTextBox.Focus();
            }
        }
    }
}
