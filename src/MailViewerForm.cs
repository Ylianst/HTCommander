using HTCommander.radio;
using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class MailViewerForm : Form
    {
        private WinLinkMail mail;

        public MailViewerForm(WinLinkMail mail)
        {
            this.mail = mail;
            InitializeComponent();
        }

        private void MailViewerForm_Load(object sender, EventArgs e)
        {


            RtfBuilder rtfBuilder = new RtfBuilder();
            if (!string.IsNullOrEmpty(mail.To)) { rtfBuilder.AppendBold("To: "); rtfBuilder.AppendLine(mail.To); }
            if (!string.IsNullOrEmpty(mail.From)) { rtfBuilder.AppendBold("From: "); rtfBuilder.AppendLine(mail.From); }
            rtfBuilder.AppendBold("Time: ");
            rtfBuilder.AppendLine(mail.DateTime.ToString());
            if (!string.IsNullOrEmpty(mail.Subject)) {
                this.Text += " - " + mail.Subject;
                rtfBuilder.AppendBold("Subject: "); rtfBuilder.AppendLine(mail.Subject);
            }
            rtfBuilder.AppendLine("");
            if (!string.IsNullOrEmpty(mail.Body)) { rtfBuilder.AppendLine(mail.Body); }
            mainTextBox.Rtf = rtfBuilder.ToRtf();
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }
    }
}
