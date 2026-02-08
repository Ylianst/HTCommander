/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class MailClientDebugForm : Form
    {
        private DataBrokerClient broker;

        public MailClientDebugForm()
        {
            InitializeComponent();
            
            // Initialize the data broker client and subscribe to Winlink traffic events
            broker = new DataBrokerClient();
            broker.Subscribe(1, "WinlinkTraffic", OnWinlinkTraffic);
            broker.Subscribe(1, "WinlinkStateMessage", OnWinlinkStateMessage);
            broker.Subscribe(1, "WinlinkDebugClear", OnWinlinkDebugClear);
            broker.Subscribe(1, "WinlinkDebugHistory", OnWinlinkDebugHistory);
            
            // Request debug history from WinlinkClient
            broker.Dispatch(1, "WinlinkDebugHistoryRequest", true, store: false);
        }

        private void OnWinlinkDebugHistory(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            // Handle the debug history - it should be a List<WinlinkDebugEntry>
            if (data is System.Collections.Generic.List<WinlinkDebugEntry> historyList)
            {
                LoadDebugHistory(historyList);
            }
        }

        private delegate void LoadDebugHistoryHandler(System.Collections.Generic.List<WinlinkDebugEntry> history);
        private void LoadDebugHistory(System.Collections.Generic.List<WinlinkDebugEntry> history)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new LoadDebugHistoryHandler(LoadDebugHistory), history); return; }
            
            // Clear existing content and load history
            mainTextBox.Clear();
            
            foreach (var entry in history)
            {
                if (entry.IsStateMessage)
                {
                    // State message - display in yellow
                    if (mainTextBox.Text.Length != 0) { mainTextBox.AppendText(Environment.NewLine); }
                    AppendText(entry.Data, Color.Yellow);
                }
                else
                {
                    // Traffic message
                    if (mainTextBox.Text.Length != 0) { mainTextBox.AppendText(Environment.NewLine); }
                    if (entry.Outgoing) { AppendText(entry.Address + " < ", Color.Green); } else { AppendText(entry.Address + " > ", Color.Green); }
                    AppendText(entry.Data, entry.Outgoing ? Color.CornflowerBlue : Color.Gainsboro);
                }
            }
            
            if (history.Count > 0)
            {
                mainTextBox.SelectionStart = mainTextBox.Text.Length;
                mainTextBox.ScrollToCaret();
            }
        }

        private void OnWinlinkTraffic(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            // Extract traffic data: { Address, Outgoing, Data }
            var dataType = data.GetType();
            string address = (string)dataType.GetProperty("Address")?.GetValue(data);
            bool outgoing = (bool)(dataType.GetProperty("Outgoing")?.GetValue(data) ?? false);
            string text = dataType.GetProperty("Data")?.GetValue(data)?.ToString();
            
            if (!string.IsNullOrEmpty(text))
            {
                AddMailTraffic(address ?? "", outgoing, text);
            }
        }

        private void OnWinlinkStateMessage(int deviceId, string name, object data)
        {
            string message = data as string;
            AddMailStatusMessage(message);
        }

        private void OnWinlinkDebugClear(int deviceId, string name, object data)
        {
            Clear();
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Hide();
        }

        public void Clear()
        {
            if (this.InvokeRequired) { this.BeginInvoke(new Action(Clear)); return; }
            mainTextBox.Clear();
        }

        private delegate void AddMailTrafficHandler(string address, bool outgoing, string text);
        public void AddMailTraffic(string address, bool outgoing, string text)
        {
            if (this.InvokeRequired) { this.BeginInvoke(new AddMailTrafficHandler(AddMailTraffic), address, outgoing, text); return; }
            if (mainTextBox.Text.Length != 0) { mainTextBox.AppendText(Environment.NewLine); }
            if (outgoing) { AppendText(address + " < ", Color.Green); } else { AppendText(address + " > ", Color.Green); }
            AppendText(text, outgoing ? Color.CornflowerBlue : Color.Gainsboro);
            mainTextBox.SelectionStart = mainTextBox.Text.Length;
            mainTextBox.ScrollToCaret();
        }

        private delegate void AddMailStatusMessageHandler(string text);
        public void AddMailStatusMessage(string text)
        {
            if (text == null) return;
            if (this.InvokeRequired) { this.BeginInvoke(new AddMailStatusMessageHandler(AddMailStatusMessage), text); return; }
            if (mainTextBox.Text.Length != 0) { mainTextBox.AppendText(Environment.NewLine); }
            AppendText(text, Color.Yellow);
            mainTextBox.SelectionStart = mainTextBox.Text.Length;
            mainTextBox.ScrollToCaret();
        }

        private void AppendText(string text, Color color)
        {
            mainTextBox.SelectionStart = mainTextBox.TextLength;
            mainTextBox.SelectionLength = 0;
            mainTextBox.SelectionColor = color;
            mainTextBox.AppendText(text);
            mainTextBox.SelectionColor = mainTextBox.ForeColor;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                broker?.Dispose();
                if (components != null)
                {
                    components.Dispose();
                }
            }
            base.Dispose(disposing);
        }
    }
}
