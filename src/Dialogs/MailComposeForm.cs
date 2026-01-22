/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Windows.Forms;
using System.Text.RegularExpressions;

namespace HTCommander
{
    public partial class MailComposeForm : Form
    {
        private DataBrokerClient broker;
        private bool MessageSaved = false;
        public WinLinkMail mail = null;
        private bool MessageChanged = false;

        public MailComposeForm(WinLinkMail mail)
        {
            this.mail = mail;
            InitializeComponent();
            broker = new DataBrokerClient();
        }

        private void MailComposeForm_Load(object sender, EventArgs e)
        {
            if (mail != null)
            {
                toTextBox.Text = mail.To;
                ccTextBox.Text = mail.Cc;
                subjectTextBox.Text = mail.Subject;
                mainTextBox.Text = mail.Body;
                if (mail.Attachments != null)
                {
                    foreach (WinLinkMailAttachement a in  mail.Attachments)
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
                    // Empty message, allow close
                }
                else if ((mail == null) && (MessageChanged == true) && MessageBox.Show("Discard this message?", "Mail", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK)
                {
                    e.Cancel = true;
                    return;
                }
                else if ((mail != null) && (MessageChanged == true) && MessageBox.Show("Discard changes to this message?", "Mail", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK)
                {
                    e.Cancel = true;
                    return;
                }
            }
            broker?.Dispose();
        }

        private void UpdateInfo()
        {
            bool tov = validateToLine(toTextBox.Text);
            bool ccv = validateToLine(ccTextBox.Text);
            draftButton.Enabled = true;
            sendButton.Enabled = tov && ccv && (toTextBox.Text.Length > 0) && (subjectTextBox.Text.Length > 0) && (mainTextBox.Text.Length > 0);
            toTextBox.BackColor = tov ? subjectTextBox.BackColor : Color.Bisque;
            ccTextBox.BackColor = ccv ? subjectTextBox.BackColor : Color.Bisque;
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
            mail.From = broker.GetValue<string>(0, "Callsign", "");
            if (ccTextBox.Text.Length > 0) { mail.Cc = ccTextBox.Text; } else { mail.Cc = null; }
            mail.Subject = subjectTextBox.Text;
            mail.Body = mainTextBox.Text;
            mail.DateTime = DateTime.Now;
            mail.Mailbox = "Outbox";

            if (attachmentsFlowLayoutPanel.Controls.Count > 0)
            {
                mail.Attachments = new System.Collections.Generic.List<WinLinkMailAttachement>();
                foreach (MailAttachmentControl a in attachmentsFlowLayoutPanel.Controls)
                {
                    WinLinkMailAttachement at = new WinLinkMailAttachement();
                    at.Name = a.Filename;
                    at.Data = a.FileData;
                    mail.Attachments.Add(at);
                }
            }
            else
            {
                mail.Attachments = null;
            }

            MessageSaved = true;
            this.DialogResult = DialogResult.OK;
            Close();
        }

        private void draftButton_Click(object sender, EventArgs e)
        {
            bool addMail = false;
            if (mail == null) { mail = new WinLinkMail(); addMail = true; }
            mail.MID = WinLinkMail.GenerateMID();
            mail.To = toTextBox.Text;
            mail.From = broker.GetValue<string>(0, "Callsign", "");
            if (ccTextBox.Text.Length > 0) { mail.Cc = ccTextBox.Text; } else { mail.Cc = null; }
            mail.Subject = subjectTextBox.Text;
            mail.Body = mainTextBox.Text;
            mail.DateTime = DateTime.Now;
            mail.Mailbox = "Draft";

            if (attachmentsFlowLayoutPanel.Controls.Count > 0)
            {
                mail.Attachments = new System.Collections.Generic.List<WinLinkMailAttachement>();
                foreach (MailAttachmentControl a in attachmentsFlowLayoutPanel.Controls)
                {
                    WinLinkMailAttachement at = new WinLinkMailAttachement();
                    at.Name = a.Filename;
                    at.Data = a.FileData;
                    mail.Attachments.Add(at);
                }
            }
            else
            {
                mail.Attachments = null;
            }

            MessageSaved = true;
            this.DialogResult = DialogResult.OK;
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

        private void toTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private void ccTextBox_TextChanged(object sender, EventArgs e)
        {
            UpdateInfo();
        }

        private bool validateToLine(string t)
        {
            string[] s = t.Replace(' ', ';').Split(';');
            foreach (string s2 in s) { if (validateToItem(s2) == false) return false; }
            return true;
        }
        private bool validateToItem(string t)
        {
            if (string.IsNullOrEmpty(t)) return true;
            t = t.Trim();
            int i = t.IndexOf('@');
            if (i == -1)
            {
                // Callsign
                if (t.Length > 10) return false;
                // Returns true is t only contains alphanumeric values
                try
                {
                    if (Regex.IsMatch(t, "^[a-zA-Z0-9]+$") == false) return false;
                }
                catch (Exception) { return false; }
            }
            else
            {
                // Email
                string pattern = @"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$";
                try
                {
                    Regex regex = new Regex(pattern);
                    return regex.IsMatch(t);
                }
                catch (Exception) { return false; }
            }
            return true;
        }

        private string CleanString(string t)
        {
            StringBuilder sb = new StringBuilder();
            string[] s = t.Replace(' ', ';').Split(';');
            foreach (string s2 in s) {
                string s3 = s2.Trim();
                if (s3.Length > 0) { if (sb.Length > 0) { sb.Append(";"); } sb.Append(s3); }
            }
            return sb.ToString();
        }

        private void toTextBox_Leave(object sender, EventArgs e)
        {
            toTextBox.Text = CleanString(toTextBox.Text);
        }

        private void ccTextBox_Leave(object sender, EventArgs e)
        {
            ccTextBox.Text = CleanString(ccTextBox.Text);
        }
    }
}
