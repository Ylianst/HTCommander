/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Linq;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AprsSmsForm : Form
    {
        private DataBrokerClient _broker;

        public string PhoneNumber { get { return phoneNumberTextBox.Text; } }
        public string Message { get { return messageTextBox.Text; } }

        public AprsSmsForm()
        {
            InitializeComponent();
            _broker = new DataBrokerClient();
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://" + linkLabel1.Text);
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
            if ((Control.ModifierKeys & Keys.Control) == Keys.Control) return;

            // Check if the key pressed is not a digit or control key (like Backspace)
            if (!char.IsDigit(e.KeyChar) && !char.IsControl(e.KeyChar))
            {
                // Cancel the event if it's not a valid input
                e.Handled = true;
            }
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            // Save the phone number to DataBroker
            _broker.Dispatch(0, "SmsPhone", PhoneNumber);
            DialogResult = DialogResult.OK;
        }

        private void AprsSmsForm_Load(object sender, EventArgs e)
        {
            // Load saved phone number from DataBroker
            phoneNumberTextBox.Text = _broker.GetValue<string>(0, "SmsPhone", "");
            if (phoneNumberTextBox.Text.Length == 0)
            {
                phoneNumberTextBox.Focus();
            }
            else
            {
                messageTextBox.Focus();
            }
            UpdateInfo();
        }
    }
}
