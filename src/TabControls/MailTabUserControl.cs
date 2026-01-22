/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Reflection;
using System.Diagnostics;
using System.Windows.Forms;
using System.IO.Compression;
using System.Collections.Generic;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    public partial class MailTabUserControl : UserControl
    {
        private DataBrokerClient broker;
        private bool _showDetach = false;

        /// <summary>
        /// Gets or sets whether the "Detach..." menu item is visible.
        /// </summary>
        [System.ComponentModel.Category("Behavior")]
        [System.ComponentModel.Description("Gets or sets whether the Detach menu item is visible.")]
        [System.ComponentModel.DefaultValue(false)]
        public bool ShowDetach
        {
            get { return _showDetach; }
            set
            {
                _showDetach = value;
                if (detachToolStripMenuItem != null)
                {
                    detachToolStripMenuItem.Visible = value;
                    toolStripMenuItemDetachSeparator.Visible = value;
                }
            }
        }
        private Point _mailMouseDownLocation;
        public string SelectedMailbox = "Inbox";
        public string[] MailBoxesNames = { "Inbox", "Outbox", "Draft", "Sent", "Archive", "Trash" };
        public TreeNode[] MailBoxTreeNodes = null;
        public MailTabUserControl()
        {
            InitializeComponent();

            // Enable double buffering on mailBoxesTreeView to reduce flicker
            typeof(TreeView).InvokeMember("DoubleBuffered",
                BindingFlags.SetProperty | BindingFlags.Instance | BindingFlags.NonPublic,
                null, mailBoxesTreeView, new object[] { true });

            // Enable double buffering on mailContextMenuStrip to reduce flicker
            typeof(ToolStripDropDownMenu).InvokeMember("DoubleBuffered",
                BindingFlags.SetProperty | BindingFlags.Instance | BindingFlags.NonPublic,
                null, mailContextMenuStrip, new object[] { true });

            // Initialize the Data Broker client
            broker = new DataBrokerClient();

            // Subscribe to mail-related events
            broker.Subscribe(0, "Mails", OnMailsChanged);
            broker.Subscribe(0, "MailShowPreview", OnMailShowPreviewChanged);

            // Load settings from broker (device 0 for app-wide settings)
            showPreviewToolStripMenuItem.Checked = broker.GetValue<int>(0, "MailShowPreview", 1) == 1;
            mailboxHorizontalSplitContainer.Panel2Collapsed = !showPreviewToolStripMenuItem.Checked;

            // Initial mail display
            UpdateMail();
        }

        private void OnMailsChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnMailsChanged), deviceId, name, data);
                return;
            }
            UpdateMail();
        }

        private void OnMailShowPreviewChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string, object>(OnMailShowPreviewChanged), deviceId, name, data);
                return;
            }
            if (data is int showPreview)
            {
                showPreviewToolStripMenuItem.Checked = showPreview == 1;
                mailboxHorizontalSplitContainer.Panel2Collapsed = !showPreviewToolStripMenuItem.Checked;
            }
        }

        /// <summary>
        /// Gets the list of mails from the broker.
        /// </summary>
        private List<WinLinkMail> GetMails()
        {
            return broker.GetValue<List<WinLinkMail>>(0, "Mails", new List<WinLinkMail>());
        }

        /// <summary>
        /// Saves the list of mails to the broker.
        /// </summary>
        private void SaveMails(List<WinLinkMail> mails)
        {
            broker.Dispatch(0, "Mails", mails);
        }

        public void UpdateMail()
        {
            if (broker == null) return;

            // Update the tree view
            if (MailBoxTreeNodes == null)
            {
                MailBoxTreeNodes = new TreeNode[6];
                MailBoxTreeNodes[0] = new TreeNode("Inbox", 0, 0);
                MailBoxTreeNodes[0].Tag = "Inbox";
                MailBoxTreeNodes[1] = new TreeNode("Outbox", 1, 1);
                MailBoxTreeNodes[1].Tag = "Outbox";
                MailBoxTreeNodes[2] = new TreeNode("Draft", 2, 2);
                MailBoxTreeNodes[2].Tag = "Draft";
                MailBoxTreeNodes[3] = new TreeNode("Sent", 3, 3);
                MailBoxTreeNodes[3].Tag = "Sent";
                MailBoxTreeNodes[4] = new TreeNode("Archive", 4, 4);
                MailBoxTreeNodes[4].Tag = "Archive";
                MailBoxTreeNodes[5] = new TreeNode("Trash", 5, 5);
                MailBoxTreeNodes[5].Tag = "Trash";
                mailBoxesTreeView.Nodes.AddRange(MailBoxTreeNodes);
                mailBoxesTreeView.SelectedNode = MailBoxTreeNodes[0];
            }

            // Get selected mailbox
            string selectedMailbox = "Inbox";
            if (mailBoxesTreeView.SelectedNode != null)
            {
                selectedMailbox = (string)mailBoxesTreeView.SelectedNode.Tag;
            }

            // Update mail counts in tree nodes
            List<WinLinkMail> mails = GetMails();
            int inboxCount = 0, outboxCount = 0, draftCount = 0, sentCount = 0, archiveCount = 0, trashCount = 0;
            foreach (WinLinkMail mail in mails)
            {
                switch (mail.Mailbox)
                {
                    case "Inbox": inboxCount++; break;
                    case "Outbox": outboxCount++; break;
                    case "Draft": draftCount++; break;
                    case "Sent": sentCount++; break;
                    case "Archive": archiveCount++; break;
                    case "Trash": trashCount++; break;
                }
            }
           MailBoxTreeNodes[0].Text = inboxCount > 0 ? $"Inbox ({inboxCount})" : "Inbox";
           MailBoxTreeNodes[1].Text = outboxCount > 0 ? $"Outbox ({outboxCount})" : "Outbox";
           MailBoxTreeNodes[2].Text = draftCount > 0 ? $"Draft ({draftCount})" : "Draft";
           MailBoxTreeNodes[3].Text = sentCount > 0 ? $"Sent ({sentCount})" : "Sent";
           MailBoxTreeNodes[4].Text = archiveCount > 0 ? $"Archive ({archiveCount})" : "Archive";
           MailBoxTreeNodes[5].Text = trashCount > 0 ? $"Trash ({trashCount})" : "Trash";

            // Update the list view
            mailboxListView.BeginUpdate();
            mailboxListView.Items.Clear();
            foreach (WinLinkMail mail in mails)
            {
                if (mail.Mailbox != selectedMailbox) continue;
                ListViewItem l = new ListViewItem(new string[] { mail.DateTime.ToLocalTime().ToString(), mail.From, mail.Subject });
                l.Tag = mail;
                l.ImageIndex = (mail.Attachments != null && mail.Attachments.Count > 0) ? 2 : 1;
                mailboxListView.Items.Add(l);
            }
            mailboxListView.EndUpdate();

            // Update context menu visibility
            bool isEditable = (selectedMailbox == "Draft" || selectedMailbox == "Outbox");
            viewMailToolStripMenuItem.Visible = !isEditable;
            editMailToolStripMenuItem.Visible = isEditable;
        }

        public void SetTransferStatus(string status, bool visible)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string, bool>(SetTransferStatus), status, visible);
                return;
            }
            mailTransferStatusLabel.Text = status;
            mailTransferStatusPanel.Visible = visible;
        }

        public void SetConnectButtonEnabled(bool enabled)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<bool>(SetConnectButtonEnabled), enabled);
                return;
            }
            mailConnectButton.Enabled = enabled;
        }

        private void mailMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            mailTabContextMenuStrip.Show(mailMenuPictureBox, e.Location);
        }

        private void mailBoxesTreeView_NodeMouseClick(object sender, TreeNodeMouseClickEventArgs e)
        {
            mailBoxesTreeView.SelectedNode = e.Node;
            UpdateMail();
        }

        private void newMailButton_Click(object sender, EventArgs e)
        {
            MailComposeForm f = new MailComposeForm(null);
            if (f.ShowDialog(this) == DialogResult.OK)
            {
                AddMail(f.mail);
            }
        }

        private void mailboxListView_DoubleClick(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;
            WinLinkMail m = (WinLinkMail)mailboxListView.SelectedItems[0].Tag;

            string selectedMailbox = "Inbox";
            if (mailBoxesTreeView.SelectedNode != null)
            {
                selectedMailbox = (string)mailBoxesTreeView.SelectedNode.Tag;
            }

            if (selectedMailbox == "Draft" || selectedMailbox == "Outbox")
            {
                // Edit
                MailComposeForm f = new MailComposeForm(m);
                if (f.ShowDialog(this) == DialogResult.OK)
                {
                    UpdateMailItem(f.mail);
                }
            }
            else
            {
                // View
                MailViewerForm f = new MailViewerForm(m);
                f.ShowDialog(this);
            }
        }

        /// <summary>
        /// Adds a new mail to the mail store.
        /// </summary>
        private void AddMail(WinLinkMail mail)
        {
            List<WinLinkMail> mails = GetMails();
            mails.Add(mail);
            SaveMails(mails);
        }

        /// <summary>
        /// Updates an existing mail in the mail store.
        /// </summary>
        private void UpdateMailItem(WinLinkMail mail)
        {
            List<WinLinkMail> mails = GetMails();
            // Remove old mail with same MID
            mails.RemoveAll(m => m.MID == mail.MID);
            mails.Add(mail);
            SaveMails(mails);
        }

        /// <summary>
        /// Deletes a mail from the mail store by MID.
        /// </summary>
        private void DeleteMail(string mid)
        {
            List<WinLinkMail> mails = GetMails();
            mails.RemoveAll(m => m.MID == mid);
            SaveMails(mails);
        }

        private void mailPreviewTextBox_LinkClicked(object sender, LinkClickedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(e.LinkText) { UseShellExecute = true }); } catch { }
        }

        private void mailboxListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0)
            {
                mailPreviewTextBox.Text = "";
                return;
            }
            WinLinkMail m = (WinLinkMail)mailboxListView.SelectedItems[0].Tag;
            StringBuilder sb = new StringBuilder();
            sb.AppendLine($"From: {m.From}");
            sb.AppendLine($"To: {m.To}");
            if (!string.IsNullOrEmpty(m.Cc)) { sb.AppendLine($"Cc: {m.Cc}"); }
            sb.AppendLine($"Date: {m.DateTime.ToLocalTime()}");
            sb.AppendLine($"Subject: {m.Subject}");
            sb.AppendLine();
            sb.AppendLine(m.Body);
            mailPreviewTextBox.Text = sb.ToString();
        }

        private void mailBoxesTreeView_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(typeof(List<WinLinkMail>)))
            {
                Point pt = mailBoxesTreeView.PointToClient(new Point(e.X, e.Y));
                TreeNode node = mailBoxesTreeView.GetNodeAt(pt);
                if (node != null)
                {
                    mailBoxesTreeView.SelectedNode = node;
                    e.Effect = DragDropEffects.Move;
                }
                else
                {
                    e.Effect = DragDropEffects.None;
                }
            }
            else
            {
                e.Effect = DragDropEffects.None;
            }
        }

        private void mailBoxesTreeView_DragDrop(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(typeof(List<WinLinkMail>)))
            {
                Point pt = mailBoxesTreeView.PointToClient(new Point(e.X, e.Y));
                TreeNode node = mailBoxesTreeView.GetNodeAt(pt);
                if (node != null)
                {
                    List<WinLinkMail> draggedMails = (List<WinLinkMail>)e.Data.GetData(typeof(List<WinLinkMail>));
                    string destMailBox = (string)node.Tag;
                    List<WinLinkMail> allMails = GetMails();
                    foreach (WinLinkMail draggedMail in draggedMails)
                    {
                        // Find and update the mail in the store
                        WinLinkMail mailInStore = allMails.Find(m => m.MID == draggedMail.MID);
                        if (mailInStore != null)
                        {
                            mailInStore.Mailbox = destMailBox;
                        }
                    }
                    SaveMails(allMails);
                }
            }
        }

        private void moveToDraftToolStripMenuItem_Click(object sender, EventArgs e)
        {
            MoveSelectedMailsTo("Draft");
        }

        private void moveToOutboxToolStripMenuItem_Click(object sender, EventArgs e)
        {
            MoveSelectedMailsTo("Outbox");
        }

        private void moveToInboxToolStripMenuItem_Click(object sender, EventArgs e)
        {
            MoveSelectedMailsTo("Inbox");
        }

        private void moveToArchiveToolStripMenuItem_Click(object sender, EventArgs e)
        {
            MoveSelectedMailsTo("Archive");
        }

        private void moveToTrashToolStripMenuItem_Click(object sender, EventArgs e)
        {
            MoveSelectedMailsTo("Trash");
        }

        private void MoveSelectedMailsTo(string mailbox)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;
            List<WinLinkMail> allMails = GetMails();
            foreach (ListViewItem l in mailboxListView.SelectedItems)
            {
                WinLinkMail selectedMail = (WinLinkMail)l.Tag;
                WinLinkMail mailInStore = allMails.Find(m => m.MID == selectedMail.MID);
                if (mailInStore != null)
                {
                    mailInStore.Mailbox = mailbox;
                }
            }
            SaveMails(allMails);
        }

        private void deleteMailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;

            if (MessageBox.Show(this, "Are you sure you want to permanently delete the selected mail(s)?", "Delete Mail", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                List<WinLinkMail> allMails = GetMails();
                foreach (ListViewItem l in mailboxListView.SelectedItems)
                {
                    WinLinkMail m = (WinLinkMail)l.Tag;
                    allMails.RemoveAll(mail => mail.MID == m.MID);
                }
                SaveMails(allMails);
            }
        }

        private void showPreviewToolStripMenuItem_Click(object sender, EventArgs e)
        {
            mailboxHorizontalSplitContainer.Panel2Collapsed = !showPreviewToolStripMenuItem.Checked;
            broker.Dispatch(0, "MailShowPreview", showPreviewToolStripMenuItem.Checked ? 1 : 0);
        }

        private void showTrafficToolStripMenuItem_Click(object sender, EventArgs e)
        {
            MailClientDebugForm f = new MailClientDebugForm();
            f.ShowDialog(this);
        }

        private void backupMailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (backupMailSaveFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                try
                {
                    List<WinLinkMail> mails = GetMails();
                    string json = Newtonsoft.Json.JsonConvert.SerializeObject(mails, Newtonsoft.Json.Formatting.Indented);
                    byte[] data = Encoding.UTF8.GetBytes(json);
                    using (FileStream fs = new FileStream(backupMailSaveFileDialog.FileName, FileMode.Create))
                    using (GZipStream gs = new GZipStream(fs, CompressionMode.Compress))
                    {
                        gs.Write(data, 0, data.Length);
                    }
                    MessageBox.Show(this, "Backup completed successfully.", "Backup Mail", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, "Backup failed: " + ex.Message, "Backup Mail", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void restoreMailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (restoreMailOpenFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                try
                {
                    using (FileStream fs = new FileStream(restoreMailOpenFileDialog.FileName, FileMode.Open))
                    using (GZipStream gs = new GZipStream(fs, CompressionMode.Decompress))
                    using (MemoryStream ms = new MemoryStream())
                    {
                        gs.CopyTo(ms);
                        string json = Encoding.UTF8.GetString(ms.ToArray());
                        List<WinLinkMail> restoredMails = Newtonsoft.Json.JsonConvert.DeserializeObject<List<WinLinkMail>>(json);
                        List<WinLinkMail> currentMails = GetMails();
                        bool change = false;
                        foreach (WinLinkMail mail in restoredMails)
                        {
                            if (!IsMailMidPresent(currentMails, mail.MID))
                            {
                                currentMails.Add(mail);
                                change = true;
                            }
                        }
                        if (change) { SaveMails(currentMails); }
                        MessageBox.Show(this, "Restore completed successfully.", "Restore Mail", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, "Restore failed: " + ex.Message, "Restore Mail", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private bool IsMailMidPresent(List<WinLinkMail> mails, string mid)
        {
            foreach (WinLinkMail mail in mails)
            {
                if (mail.MID == mid) return true;
            }
            return false;
        }

        private void mailConnectButton_Click(object sender, EventArgs e)
        {
            // Select a Winlink gateway station
            ActiveStationSelectorForm f = new ActiveStationSelectorForm(StationInfoClass.StationTypes.Winlink);
            if (f.ShowDialog(this) == DialogResult.OK)
            {
                // Dispatch event to lock to the selected station
                broker.Dispatch(0, "ActiveLockToStation", f.selectedStation, store: false);
            }
        }

        private void mailboxListView_MouseDown(object sender, MouseEventArgs e)
        {
            _mailMouseDownLocation = e.Location;
        }

        private void mailboxListView_MouseUp(object sender, MouseEventArgs e)
        {
        }

        private void mailboxListView_MouseMove(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            if (mailboxListView.SelectedItems.Count == 0) return;

            // Check if we moved enough to start a drag
            if (Math.Abs(e.X - _mailMouseDownLocation.X) > 5 || Math.Abs(e.Y - _mailMouseDownLocation.Y) > 5)
            {
                List<WinLinkMail> mails = new List<WinLinkMail>();
                foreach (ListViewItem l in mailboxListView.SelectedItems)
                {
                    mails.Add((WinLinkMail)l.Tag);
                }
                mailboxListView.DoDragDrop(mails, DragDropEffects.Move);
            }
        }

        private void mailboxListView_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Delete)
            {
                moveToTrashToolStripMenuItem_Click(sender, e);
            }
        }

        private void mailboxListView_Resize(object sender, EventArgs e)
        {
            if (mailboxListView.Columns.Count >= 3)
            {
                mailboxListView.Columns[2].Width = mailboxListView.Width - mailboxListView.Columns[1].Width - mailboxListView.Columns[0].Width - 28;
            }
        }

        private void mailInternetButton_Click(object sender, EventArgs e)
        {
            // Dispatch event to connect to Winlink Internet
            broker.Dispatch(0, "ConnectToWinlinkInternet", true, store: false);
        }

        private void mailReplyToolStripButton_Click(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;
            WinLinkMail m = (WinLinkMail)mailboxListView.SelectedItems[0].Tag;

            WinLinkMail reply = new WinLinkMail();
            reply.To = m.From;
            reply.Subject = m.Subject.StartsWith("Re: ") ? m.Subject : "Re: " + m.Subject;
            reply.Body = $"\r\n\r\n--- Original Message ---\r\nFrom: {m.From}\r\nDate: {m.DateTime.ToLocalTime()}\r\n\r\n{m.Body}";

            MailComposeForm f = new MailComposeForm(reply);
            if (f.ShowDialog(this) == DialogResult.OK)
            {
                AddMail(f.mail);
            }
        }

        private void mailReplyAllToolStripButton_Click(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;
            WinLinkMail m = (WinLinkMail)mailboxListView.SelectedItems[0].Tag;

            WinLinkMail reply = new WinLinkMail();
            reply.To = m.From;
            if (!string.IsNullOrEmpty(m.Cc)) { reply.Cc = m.Cc; }
            reply.Subject = m.Subject.StartsWith("Re: ") ? m.Subject : "Re: " + m.Subject;
            reply.Body = $"\r\n\r\n--- Original Message ---\r\nFrom: {m.From}\r\nDate: {m.DateTime.ToLocalTime()}\r\n\r\n{m.Body}";

            MailComposeForm f = new MailComposeForm(reply);
            if (f.ShowDialog(this) == DialogResult.OK)
            {
                AddMail(f.mail);
            }
        }

        private void mailForwardToolStripButton_Click(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;
            WinLinkMail m = (WinLinkMail)mailboxListView.SelectedItems[0].Tag;

            WinLinkMail forward = new WinLinkMail();
            forward.Subject = m.Subject.StartsWith("Fwd: ") ? m.Subject : "Fwd: " + m.Subject;
            forward.Body = $"\r\n\r\n--- Forwarded Message ---\r\nFrom: {m.From}\r\nTo: {m.To}\r\nDate: {m.DateTime.ToLocalTime()}\r\nSubject: {m.Subject}\r\n\r\n{m.Body}";
            if (m.Attachments != null) { forward.Attachments = new List<WinLinkMailAttachement>(m.Attachments); }

            MailComposeForm f = new MailComposeForm(forward);
            if (f.ShowDialog(this) == DialogResult.OK)
            {
                AddMail(f.mail);
            }
        }

        private void mailDeleteToolStripButton_Click(object sender, EventArgs e)
        {
            moveToTrashToolStripMenuItem_Click(sender, e);
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<MailTabUserControl>("Mail");
            form.Show();
        }
    }
}
