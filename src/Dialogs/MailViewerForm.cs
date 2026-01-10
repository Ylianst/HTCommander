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
            if (!string.IsNullOrEmpty(mail.From)) { rtfBuilder.AppendBold("From: "); rtfBuilder.AppendLine(mail.From); }
            if (!string.IsNullOrEmpty(mail.To)) { rtfBuilder.AppendBold("To: "); rtfBuilder.AppendLine(mail.To); }
            if (!string.IsNullOrEmpty(mail.Cc)) { rtfBuilder.AppendBold("Cc: "); rtfBuilder.AppendLine(mail.Cc); }
            rtfBuilder.AppendBold("Time: ");
            rtfBuilder.AppendLine(mail.DateTime.ToString());
            if (!string.IsNullOrEmpty(mail.Subject)) {
                rtfBuilder.AppendBold("Subject: "); rtfBuilder.AppendLine(mail.Subject);
                this.Text += " - " + mail.Subject;
            }
            if (mail.Attachments != null)
            {
                if (mail.Attachments.Count < 2) { rtfBuilder.AppendBold("Attachment: "); } else { rtfBuilder.AppendBold("Attachments: "); }
                bool first = true;
                foreach (WinLinkMailAttachement attachment in mail.Attachments)
                {
                    if (!first) { rtfBuilder.Append(", "); }
                    rtfBuilder.Append("\"" + attachment.Name + "\"");
                    first = false;
                }
                rtfBuilder.AppendLine("");
            }
            rtfBuilder.AppendLine("");
            if (!string.IsNullOrEmpty(mail.Body)) { rtfBuilder.Append(mail.Body); }
            mainTextBox.Rtf = rtfBuilder.ToRtf();

            if (mail.Attachments != null)
            {
                foreach (WinLinkMailAttachement a in mail.Attachments)
                {
                    MailAttachmentControl mailAttachmentControl = new MailAttachmentControl();
                    mailAttachmentControl.AllowRemove = false;
                    mailAttachmentControl.Filename = a.Name;
                    mailAttachmentControl.FileData = a.Data;
                    attachmentsFlowLayoutPanel.Controls.Add(mailAttachmentControl);
                }
            }
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }
    }
}
