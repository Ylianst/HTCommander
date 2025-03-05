using System;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class MailClientDebugForm : Form
    {
        public MailClientDebugForm()
        {
            InitializeComponent();
        }
        private void clearToolStripMenuItem_Click(object sender, EventArgs e)
        {
            mainTextBox.Clear();
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Hide();
        }

        public void Clear()
        {
            mainTextBox.Clear();
        }

        private delegate void AddBbsTrafficHandler(string callsign, bool outgoing, string text);
        public void AddBbsTraffic(string callsign, bool outgoing, string text)
        {
            if (this.InvokeRequired) { this.Invoke(new AddBbsTrafficHandler(AddBbsTraffic), callsign, outgoing, text); return; }
            if (mainTextBox.Text.Length != 0) { mainTextBox.AppendText(Environment.NewLine); }
            if (outgoing) { AppendBbsText(callsign + " < ", Color.Green); } else { AppendBbsText(callsign + " > ", Color.Green); }
            AppendBbsText(text, outgoing ? Color.CornflowerBlue : Color.Gainsboro);
            mainTextBox.SelectionStart = mainTextBox.Text.Length;
            mainTextBox.ScrollToCaret();
        }

        private delegate void AddBbsControlMessageHandler(string text);
        public void AddBbsControlMessage(string text)
        {
            if (text == null) return;
            if (this.InvokeRequired) { this.Invoke(new AddBbsControlMessageHandler(AddBbsControlMessage), text); return; }
            if (mainTextBox.Text.Length != 0) { mainTextBox.AppendText(Environment.NewLine); }
            AppendBbsText(text, Color.Yellow);
            mainTextBox.SelectionStart = mainTextBox.Text.Length;
            mainTextBox.ScrollToCaret();
        }

        private void AppendBbsText(string text, Color color)
        {
            mainTextBox.SelectionStart = mainTextBox.TextLength;
            mainTextBox.SelectionLength = 0;
            mainTextBox.SelectionColor = color;
            mainTextBox.AppendText(text);
            mainTextBox.SelectionColor = mainTextBox.ForeColor;
        }

        private void MailClientDebugForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            e.Cancel = true;
            Hide();
        }
    }
}
