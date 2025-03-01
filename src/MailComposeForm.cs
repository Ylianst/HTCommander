using HTCommander.radio;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Windows.System.Update;

namespace HTCommander
{
    public partial class MailComposeForm : Form
    {
        private MainForm parent;
        private bool MessageSaved = false;
        private WinLinkMail mail = null;
        private bool MessageChanged = false;

        public MailComposeForm(MainForm parent, WinLinkMail mail)
        {
            this.parent = parent;
            this.mail = mail;
            InitializeComponent();
        }

        private void MailComposeForm_Load(object sender, EventArgs e)
        {
            if (mail != null)
            {
                toComboBox.Text = mail.To;
                subjectTextBox.Text = mail.Subject;
                mainTextBox.Text = mail.Body;
            }
            MessageChanged = false;
        }

        private void MailComposeForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (MessageSaved == false)
            {
                if ((toComboBox.Text.Length == 0) && (subjectTextBox.Text.Length == 0) && (mainTextBox.Text.Length == 0))
                {
                    parent.mailComposeForm = null;
                }
                else if ((mail == null) && (MessageChanged == true) && MessageBox.Show("Discard this message?", "Main", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK)
                {
                    e.Cancel = true;
                    return;
                }
                else if ((mail != null) && (MessageChanged == true) && MessageBox.Show("Discard changes to this message?", "Mail", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK)
                {
                    e.Cancel = true;
                    return;
                }
                else
                {
                    parent.mailComposeForm = null;
                }
            }
            else
            {
                parent.mailComposeForm = null;
            }
        }

        private void UpdateInfo()
        {
            draftButton.Enabled = (toComboBox.Text.Length > 0) || (subjectTextBox.Text.Length > 0) || (mainTextBox.Text.Length > 0);
            sendButton.Enabled = (toComboBox.Text.Length > 0) && (subjectTextBox.Text.Length > 0) && (mainTextBox.Text.Length > 0);
        }

        private void mainTextBox_TextChanged(object sender, EventArgs e)
        {
            MessageChanged = true;
            UpdateInfo();
        }

        private void toComboBox_TextChanged(object sender, EventArgs e)
        {
            MessageChanged = true;
            UpdateInfo();
        }

        private void subjectTextBox_TextChanged(object sender, EventArgs e)
        {
            MessageChanged = true;
            UpdateInfo();
        }

        private void cancelButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            bool addMail = false;
            if (mail == null) { mail = new WinLinkMail(); addMail = true; }
            mail.To = toComboBox.Text;
            mail.Subject = subjectTextBox.Text;
            mail.Body = mainTextBox.Text;
            mail.DateTime = DateTime.Now;
            mail.Mailbox = 1; // Outbox
            if (addMail) { parent.Mails.Add(mail); }
            parent.SaveMails();
            parent.UpdateMail();
            MessageSaved = true;
            Close();
        }

        private void draftButton_Click(object sender, EventArgs e)
        {
            bool addMail = false;
            if (mail == null) { mail = new WinLinkMail(); addMail = true; }
            mail.To = toComboBox.Text;
            mail.Subject = subjectTextBox.Text;
            mail.Body = mainTextBox.Text;
            mail.DateTime = DateTime.Now;
            mail.Mailbox = 2; // Draft
            if (addMail) { parent.Mails.Add(mail); }
            parent.SaveMails();
            parent.UpdateMail();
            MessageSaved = true;
            Close();
        }

        private void MailComposeForm_Shown(object sender, EventArgs e)
        {
            if (mail != null)
            {
                mainTextBox.Focus();
                mainTextBox.SelectionStart = mainTextBox.Text.Length;
            }
            else
            {
                toComboBox.Focus();
            }
        }
    }
}
