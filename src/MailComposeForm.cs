﻿using System;
using System.IO;
using System.Windows.Forms;
using HTCommander.radio;

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
                toTextBox.Text = mail.To;
                ccTextBox.Text = mail.Cc;
                subjectTextBox.Text = mail.Subject;
                mainTextBox.Text = mail.Body;
                if (mail.Attachements != null)
                {
                    foreach (WinLinkMailAttachement a in  mail.Attachements)
                    {
                        MailAttachmentControl mailAttachmentControl = new MailAttachmentControl();
                        mailAttachmentControl.AllowRemove = true;
                        mailAttachmentControl.Filename = a.Name;
                        mailAttachmentControl.FileData = a.Data;
                        attachmentsFlowLayoutPanel.Controls.Add(mailAttachmentControl);
                    }
                }
            }
            MessageChanged = false;
        }

        private void MailComposeForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (MessageSaved == false)
            {
                if ((toTextBox.Text.Length == 0) && (subjectTextBox.Text.Length == 0) && (mainTextBox.Text.Length == 0))
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
            draftButton.Enabled = (toTextBox.Text.Length > 0) || (subjectTextBox.Text.Length > 0) || (mainTextBox.Text.Length > 0);
            sendButton.Enabled = (toTextBox.Text.Length > 0) && (subjectTextBox.Text.Length > 0) && (mainTextBox.Text.Length > 0);
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

        private void MailComposeForm_Shown(object sender, EventArgs e)
        {
            if (mail != null)
            {
                mainTextBox.Focus();
                mainTextBox.SelectionStart = mainTextBox.Text.Length;
            }
            else
            {
                toTextBox.Focus();
            }
        }

        private void sendButton_Click(object sender, EventArgs e)
        {
            bool addMail = false;
            if (mail == null) { mail = new WinLinkMail(); addMail = true; }
            mail.MID = WinLinkMail.GenerateMID();
            mail.To = toTextBox.Text;
            mail.From = parent.callsign;
            if (ccTextBox.Text.Length > 0) { mail.Cc = ccTextBox.Text; } else { mail.Cc = null; }
            mail.Subject = subjectTextBox.Text;
            mail.Body = mainTextBox.Text;
            mail.DateTime = DateTime.Now;
            mail.Mailbox = 1; // Outbox

            if (attachmentsFlowLayoutPanel.Controls.Count > 0)
            {
                mail.Attachements = new System.Collections.Generic.List<WinLinkMailAttachement>();
                foreach (MailAttachmentControl a in attachmentsFlowLayoutPanel.Controls)
                {
                    WinLinkMailAttachement at = new WinLinkMailAttachement();
                    at.Name = a.Filename;
                    at.Data = a.FileData;
                    mail.Attachements.Add(at);
                }
            }
            else
            {
                mail.Attachements = null;
            }

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
            mail.MID = WinLinkMail.GenerateMID();
            mail.To = toTextBox.Text;
            mail.From = parent.callsign;
            if (ccTextBox.Text.Length > 0) { mail.Cc = ccTextBox.Text; } else { mail.Cc = null; }
            mail.Subject = subjectTextBox.Text;
            mail.Body = mainTextBox.Text;
            mail.DateTime = DateTime.Now;
            mail.Mailbox = 2; // Draft

            if (attachmentsFlowLayoutPanel.Controls.Count > 0)
            {
                mail.Attachements = new System.Collections.Generic.List<WinLinkMailAttachement>();
                foreach (MailAttachmentControl a in attachmentsFlowLayoutPanel.Controls)
                {
                    WinLinkMailAttachement at = new WinLinkMailAttachement();
                    at.Name = a.Filename;
                    at.Data = a.FileData;
                    mail.Attachements.Add(at);
                }
            }
            else
            {
                mail.Attachements = null;
            }

            if (addMail) { parent.Mails.Add(mail); }
            parent.SaveMails();
            parent.UpdateMail();
            MessageSaved = true;
            Close();
        }

        private void addToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (addAttachementPpenFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                byte[] filedata = File.ReadAllBytes(addAttachementPpenFileDialog.FileName);
                FileInfo file = new FileInfo(addAttachementPpenFileDialog.FileName);
                MailAttachmentControl mailAttachmentControl = new MailAttachmentControl();
                mailAttachmentControl.AllowRemove = true;
                mailAttachmentControl.Filename = file.Name;
                mailAttachmentControl.FileData = filedata;
                attachmentsFlowLayoutPanel.Controls.Add(mailAttachmentControl);
            }
        }

        private void mainTextBox_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                e.Effect = DragDropEffects.Copy;
            }
            else
            {
                e.Effect = DragDropEffects.None;
            }
        }

        private void mainTextBox_DragDrop(object sender, DragEventArgs e)
        {
            string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
            if (files != null && files.Length > 0)
            {
                foreach (string xfile in files)
                {
                    byte[] filedata = File.ReadAllBytes(xfile);
                    FileInfo file = new FileInfo(xfile);
                    MailAttachmentControl mailAttachmentControl = new MailAttachmentControl();
                    mailAttachmentControl.AllowRemove = true;
                    mailAttachmentControl.Filename = file.Name;
                    mailAttachmentControl.FileData = filedata;
                    attachmentsFlowLayoutPanel.Controls.Add(mailAttachmentControl);
                }
            }
        }
    }
}
