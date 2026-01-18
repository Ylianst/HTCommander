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
    public partial class AprsWeatherForm : Form
    {
        private DataBrokerClient _broker;

        public string Location { get { return locationTextBox.Text; } }

        public AprsWeatherForm()
        {
            InitializeComponent();
            _broker = new DataBrokerClient();
        }

        public string GetAprsMessage()
        {
            string time = timeComboBox.Items[timeComboBox.SelectedIndex].ToString().ToLower();
            string report = reportComboBox.Items[reportComboBox.SelectedIndex].ToString().Split(',')[0].ToLower();
            return locationTextBox.Text + " " + time + " " + report;
        }

        private void linkLabel1_LinkClicked(object sender, LinkLabelLinkClickedEventArgs e)
        {
            System.Diagnostics.Process.Start("https://" + linkLabel1.Text);
        }

        private void UpdateInfo()
        {
            okButton.Enabled = (locationTextBox.Text.Length > 0);
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            // Save settings to DataBroker
            _broker.Dispatch(0, "WxBotLocation", locationTextBox.Text);
            _broker.Dispatch(0, "WxBotTime", timeComboBox.SelectedIndex);
            _broker.Dispatch(0, "WxBotReport", reportComboBox.SelectedIndex);
            DialogResult = DialogResult.OK;
        }

        private void locationTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void locationTextBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            // Check if the pressed character is in the restricted list
            char[] restrictedChars = { '~', '|', '{', '}', ' ' };
            if (restrictedChars.Contains(e.KeyChar)) { e.Handled = true; return; }
        }

        private void AprsWeatherForm_Load(object sender, EventArgs e)
        {
            // Load saved settings from DataBroker
            locationTextBox.Text = _broker.GetValue<string>(0, "WxBotLocation", "");
            
            int timeIndex = _broker.GetValue<int>(0, "WxBotTime", 0);
            if (timeIndex >= 0 && timeIndex < timeComboBox.Items.Count)
            {
                timeComboBox.SelectedIndex = timeIndex;
            }
            else if (timeComboBox.Items.Count > 0)
            {
                timeComboBox.SelectedIndex = 0;
            }

            int reportIndex = _broker.GetValue<int>(0, "WxBotReport", 0);
            if (reportIndex >= 0 && reportIndex < reportComboBox.Items.Count)
            {
                reportComboBox.SelectedIndex = reportIndex;
            }
            else if (reportComboBox.Items.Count > 0)
            {
                reportComboBox.SelectedIndex = 0;
            }

            UpdateInfo();
        }
    }
}
