/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System.Linq;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class AddAprsRouteForm : Form
    {
        public string AprsRouteStr = null;

        public AddAprsRouteForm()
        {
            InitializeComponent();
        }

        private void AddAprsRouteForm_Load(object sender, System.EventArgs e)
        {
            Utils.SetPlaceholderText(destTextBox, "APN000-0");

            if (AprsRouteStr != null)
            {
                string[] route = AprsRouteStr.Split(',');
                if (route.Length > 0) { routeNameTextBox.Text = route[0]; }
                if (route.Length > 1) { destTextBox.Text = route[1]; }
                if (route.Length > 2) { repeater1TextBox.Text = route[2]; }
                if (route.Length > 3) { repeater2TextBox.Text = route[3]; }
                if (route.Length > 4) { repeater3TextBox.Text = route[4]; }
            }
            UpdateInfo();
        }

        private void okButton_Click(object sender, System.EventArgs e)
        {
            AX25Address addr;
            AprsRouteStr = routeNameTextBox.Text + ",";
            if (destTextBox.Text.Length == 0)
            {
                AprsRouteStr += "APN000-0";
            }
            else
            {
                addr = AX25Address.GetAddress(destTextBox.Text);
                if (addr != null) { AprsRouteStr += addr.CallSignWithId; } else { AprsRouteStr += "APN000-0"; }
            }
            addr = AX25Address.GetAddress(repeater1TextBox.Text);
            if (addr != null) {
                AprsRouteStr += "," + addr.CallSignWithId;
                addr = AX25Address.GetAddress(repeater2TextBox.Text);
                if (addr != null)
                {
                    AprsRouteStr += "," + addr.CallSignWithId;
                    addr = AX25Address.GetAddress(repeater3TextBox.Text);
                    if (addr != null)
                    {
                        AprsRouteStr += "," + addr.CallSignWithId;
                    }
                }
            }
            DialogResult = DialogResult.OK;
        }

        private void UpdateInfo()
        {
            bool ok = true;
            if (routeNameTextBox.Text.Length == 0) { ok = false; }
            if (validateCallsignInput(destTextBox) == false) { ok = false; }
            if (validateCallsignInput(repeater1TextBox) == false) { ok = false; }
            if (validateCallsignInput(repeater2TextBox) == false) { ok = false; }
            if (validateCallsignInput(repeater3TextBox) == false) { ok = false; }
            okButton.Enabled = ok;
        }

        private void routeNameTextBox_TextChanged(object sender, System.EventArgs e)
        {
            UpdateInfo();
        }

        private bool validateCallsignInput(TextBox textbox)
        {
            if (textbox.Text.Length == 0) return true;
            int selectionStart = textbox.SelectionStart;
            textbox.Text = textbox.Text.ToUpper();
            textbox.SelectionStart = selectionStart;
            AX25Address addr = AX25Address.GetAddress(textbox.Text);
            textbox.BackColor = (addr == null) ? Color.Salmon : routeNameTextBox.BackColor;
            return (addr != null);
        }

        private void destTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Check if the pressed character is in the restricted list
            char[] restrictedChars = { '~', '|', '{', '}', ',' };
            if (restrictedChars.Contains(e.KeyChar)) { e.Handled = true; return; }
        }
    }
}
