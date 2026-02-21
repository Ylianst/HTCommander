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
    public partial class MailTabUserControl : UserControl, IRadioDeviceSelector
    {
        private int _preferredRadioDeviceId = -1;
        private DataBrokerClient broker;

        /// <summary>
        /// Gets or sets the preferred radio device ID for this control.
        /// </summary>
        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public int PreferredRadioDeviceId
        {
            get { return _preferredRadioDeviceId; }
            set { _preferredRadioDeviceId = value; }
        }
        private bool _showDetach = false;
        private List<int> connectedRadios = new List<int>();
        private Dictionary<int, RadioLockState> lockStates = new Dictionary<int, RadioLockState>();
        private ContextMenuStrip mailConnectContextMenuStrip;

        /// <summary>
        /// Helper method to invoke an action on the UI thread if required.
        /// </summary>
        private void InvokeIfRequired(Action action)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(action);
            }
            else
            {
                action();
            }
        }

        /// <summary>
        /// Gets the currently selected mailbox name from the tree view.
        /// </summary>
        private string GetSelectedMailbox()
        {
            if (mailBoxesTreeView.SelectedNode != null)
            {
                return (string)mailBoxesTreeView.SelectedNode.Tag;
            }
            return "Inbox";
        }

        /// <summary>
        /// Formats a mailbox name with its count for display in the tree view.
        /// </summary>
        private string FormatMailboxNodeText(string name, int count)
        {
            return count > 0 ? $"{name} ({count})" : name;
        }

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
        private int mailSortColumn = 0;
        private SortOrder mailSortOrder = SortOrder.Descending;
        private readonly string[] mailColumnBaseNames = { "Time", "From", "Subject" };
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
            broker.Subscribe(0, "MailsChanged", OnMailsChanged);
            broker.Subscribe(0, "MailList", OnMailListReceived);
            broker.Subscribe(0, "MailShowPreview", OnMailShowPreviewChanged);
            broker.Subscribe(0, "MailStoreReady", OnMailStoreReady);
            broker.Subscribe(0, "DataHandlerAdded", OnDataHandlerAdded);
            broker.Subscribe(1, "WinlinkBusy", OnWinlinkBusyChanged);
            broker.Subscribe(1, "WinlinkStateMessage", OnWinlinkStateMessageChanged);

            // Subscribe to connected radios and lock state to update connect button
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);

            // Initialize the context menu for the connect button
            mailConnectContextMenuStrip = new ContextMenuStrip();

            // Load settings from broker (device 0 for app-wide settings)
            showPreviewToolStripMenuItem.Checked = broker.GetValue<int>(0, "MailShowPreview", 1) == 1;
            mailboxHorizontalSplitContainer.Panel2Collapsed = !showPreviewToolStripMenuItem.Checked;

            // Hide preview controls initially (no mail selected)
            mailPreviewTextBox.Visible = false;
            mailToolStrip.Visible = false;

            // Check initial WinlinkBusy state to set connect button state
            bool isBusy = broker.GetValue<bool>(1, "WinlinkBusy", false);
            mailConnectButton.Enabled = !isBusy;

            // Check initial WinlinkStateMessage state
            string stateMessage = broker.GetValue<string>(1, "WinlinkStateMessage", null);
            if (!string.IsNullOrEmpty(stateMessage))
            {
                mailTransferStatusLabel.Text = stateMessage;
                mailTransferStatusPanel.Visible = true;
            }

            // Initial mail display
            UpdateMail();
        }

        private void OnMailsChanged(int deviceId, string name, object data)
        {
            InvokeIfRequired(() => UpdateMail());
        }

        private void OnMailListReceived(int deviceId, string name, object data)
        {
            // This is called in response to MailGetAll - the data contains the mail list
            // If we need immediate access to the mail list after requesting it, this is where we'd handle it
            // For now, we just update the display
            InvokeIfRequired(() => UpdateMail());
        }

        private void OnMailStoreReady(int deviceId, string name, object data)
        {
            // MailStore is now ready - refresh the mail display to show correct counts
            InvokeIfRequired(() => UpdateMail());
        }

        private void OnDataHandlerAdded(int deviceId, string name, object data)
        {
            // Check if MailStore was just added - if so, refresh the mail display
            if (data is string handlerName && handlerName == "MailStore")
            {
                InvokeIfRequired(() => UpdateMail());
            }
        }

        private void OnMailShowPreviewChanged(int deviceId, string name, object data)
        {
            InvokeIfRequired(() =>
            {
                if (data is int showPreview)
                {
                    showPreviewToolStripMenuItem.Checked = showPreview == 1;
                    mailboxHorizontalSplitContainer.Panel2Collapsed = !showPreviewToolStripMenuItem.Checked;
                }
            });
        }

        private void OnWinlinkBusyChanged(int deviceId, string name, object data)
        {
            InvokeIfRequired(() =>
            {
                bool isBusy = (data is bool b) && b;
                mailConnectButton.Enabled = !isBusy;
            });
        }

        private void OnWinlinkStateMessageChanged(int deviceId, string name, object data)
        {
            InvokeIfRequired(() =>
            {
                string status = data as string;
                if (string.IsNullOrEmpty(status))
                {
                    mailTransferStatusPanel.Visible = false;
                }
                else
                {
                    mailTransferStatusLabel.Text = status;
                    mailTransferStatusPanel.Visible = true;
                }
            });
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (data == null) return;

            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ProcessConnectedRadiosChanged(data)));
            }
            else
            {
                ProcessConnectedRadiosChanged(data);
            }
        }

        private void ProcessConnectedRadiosChanged(object data)
        {
            connectedRadios.Clear();

            if (data is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var itemType = item.GetType();
                    int? deviceIdValue = (int?)itemType.GetProperty("DeviceId")?.GetValue(item);
                    if (deviceIdValue.HasValue)
                    {
                        connectedRadios.Add(deviceIdValue.Value);
                    }
                }
            }

            UpdateConnectButtonState();
        }

        private void OnLockStateChanged(int deviceId, string name, object data)
        {
            if (!(data is RadioLockState lockState)) return;

            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ProcessLockStateChanged(deviceId, lockState)));
            }
            else
            {
                ProcessLockStateChanged(deviceId, lockState);
            }
        }

        private void ProcessLockStateChanged(int deviceId, RadioLockState lockState)
        {
            lockStates[deviceId] = lockState;
            UpdateConnectButtonState();
        }

        private void UpdateConnectButtonState()
        {
            // Button is enabled if we have internet or at least one unlocked radio
            bool hasAvailableRadio = GetAvailableRadiosWithNames().Count > 0;
            // Always have internet option available (unless busy, handled by WinlinkBusy)
            mailConnectButton.Enabled = true;
        }

        /// <summary>
        /// Gets all available (unlocked) radios with their friendly names.
        /// </summary>
        /// <returns>A list of tuples containing DeviceId and FriendlyName for each available radio.</returns>
        private List<(int DeviceId, string FriendlyName)> GetAvailableRadiosWithNames()
        {
            var availableRadios = new List<(int DeviceId, string FriendlyName)>();

            foreach (var radioId in connectedRadios)
            {
                if (!lockStates.TryGetValue(radioId, out RadioLockState lockState) || !lockState.IsLocked)
                {
                    // Get the friendly name from the DataBroker
                    string friendlyName = broker.GetValue<string>(radioId, "FriendlyName", $"Radio {radioId}");
                    availableRadios.Add((radioId, friendlyName));
                }
            }

            return availableRadios;
        }

        /// <summary>
        /// Gets the list of mails from the MailStore via DataBroker.
        /// </summary>
        private List<WinLinkMail> GetMails()
        {
            // Get the MailStore handler directly for synchronous access
            MailStore mailStore = DataBroker.GetDataHandler<MailStore>("MailStore");
            if (mailStore != null)
            {
                return mailStore.GetAllMails();
            }
            return new List<WinLinkMail>();
        }

        /// <summary>
        /// Adds a single mail using the broker event.
        /// </summary>
        private void AddMailToBroker(WinLinkMail mail)
        {
            broker.Dispatch(0, "MailAdd", mail, store: false);
        }

        /// <summary>
        /// Updates a single mail using the broker event.
        /// </summary>
        private void UpdateMailInBroker(WinLinkMail mail)
        {
            broker.Dispatch(0, "MailUpdate", mail, store: false);
        }

        /// <summary>
        /// Deletes a mail by MID using the broker event.
        /// </summary>
        private void DeleteMailFromBroker(string mid)
        {
            broker.Dispatch(0, "MailDelete", mid, store: false);
        }

        /// <summary>
        /// Moves a mail to a different mailbox using the broker event.
        /// </summary>
        private void MoveMailInBroker(string mid, string mailbox)
        {
            broker.Dispatch(0, "MailMove", new { MID = mid, Mailbox = mailbox }, store: false);
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
            string selectedMailbox = GetSelectedMailbox();

            // Update mail counts in tree nodes using dictionary for cleaner code
            List<WinLinkMail> mails = GetMails();
            Dictionary<string, int> mailCounts = new Dictionary<string, int>
            {
                { "Inbox", 0 }, { "Outbox", 0 }, { "Draft", 0 },
                { "Sent", 0 }, { "Archive", 0 }, { "Trash", 0 }
            };
            foreach (WinLinkMail mail in mails)
            {
                if (mailCounts.ContainsKey(mail.Mailbox))
                {
                    mailCounts[mail.Mailbox]++;
                }
            }
            for (int i = 0; i < MailBoxesNames.Length; i++)
            {
                MailBoxTreeNodes[i].Text = FormatMailboxNodeText(MailBoxesNames[i], mailCounts[MailBoxesNames[i]]);
            }

            // Update the list view
            mailboxListView.BeginUpdate();
            mailboxListView.Items.Clear();
            foreach (WinLinkMail mail in mails)
            {
                if (mail.Mailbox != selectedMailbox) continue;
                string fromDisplay = mail.From;
                if (fromDisplay.StartsWith("SMTP:", StringComparison.OrdinalIgnoreCase))
                {
                    fromDisplay = fromDisplay.Substring(5);
                }
                ListViewItem l = new ListViewItem(new string[] { mail.DateTime.ToLocalTime().ToString(), fromDisplay, mail.Subject });
                l.Tag = mail;
                l.ImageIndex = 0;//  (mail.Attachments != null && mail.Attachments.Count > 0) ? 2 : 1;
                mailboxListView.Items.Add(l);
            }
            mailboxListView.EndUpdate();

            // Apply current sort
            mailboxListView.ListViewItemSorter = new MailListViewComparer(mailSortColumn, mailSortOrder);
            mailboxListView.Sort();
            UpdateMailSortGlyph();

            // Automatically select the first item if available
            if (mailboxListView.Items.Count > 0)
            {
                mailboxListView.Items[0].Selected = true;
                mailboxListView.Items[0].Focused = true;
            }

            // Update context menu visibility
            bool isEditable = (selectedMailbox == "Draft" || selectedMailbox == "Outbox");
            viewMailToolStripMenuItem.Visible = !isEditable;
            editMailToolStripMenuItem.Visible = isEditable;
        }

        public void SetTransferStatus(string status, bool visible)
        {
            InvokeIfRequired(() =>
            {
                mailTransferStatusLabel.Text = status;
                mailTransferStatusPanel.Visible = visible;
            });
        }

        public void SetConnectButtonEnabled(bool enabled)
        {
            InvokeIfRequired(() => mailConnectButton.Enabled = enabled);
        }

        private void mailMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            mailTabContextMenuStrip.Show(mailMenuPictureBox, e.Location);
        }

        private void mailBoxesTreeView_NodeMouseClick(object sender, TreeNodeMouseClickEventArgs e)
        {
            // Only clear preview and update if switching to a different mailbox
            if (mailBoxesTreeView.SelectedNode != e.Node)
            {
                mailBoxesTreeView.SelectedNode = e.Node;

                // Clear the preview when switching mailboxes
                mailPreviewTextBox.Text = "";
                mailPreviewTextBox.Visible = false;
                mailToolStrip.Visible = false;

                UpdateMail();
            }
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

            string selectedMailbox = GetSelectedMailbox();

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
            AddMailToBroker(mail);
        }

        /// <summary>
        /// Updates an existing mail in the mail store.
        /// </summary>
        private void UpdateMailItem(WinLinkMail mail)
        {
            UpdateMailInBroker(mail);
        }

        /// <summary>
        /// Deletes a mail from the mail store by MID.
        /// </summary>
        private void DeleteMail(string mid)
        {
            DeleteMailFromBroker(mid);
        }

        private void mailPreviewTextBox_LinkClicked(object sender, LinkClickedEventArgs e)
        {
            try { Process.Start(new ProcessStartInfo(e.LinkText) { UseShellExecute = true }); } catch { }
        }

        private void mailboxListView_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0)
            {
                // Defer the hide check to avoid flickering when clicking between emails.
                // When selecting a new item, the old selection is cleared first (Count == 0),
                // then the new item is selected. By deferring, we check after both events complete.
                BeginInvoke(new Action(() =>
                {
                    if (mailboxListView.SelectedItems.Count == 0)
                    {
                        mailPreviewTextBox.Text = "";
                        mailPreviewTextBox.Visible = false;
                        mailToolStrip.Visible = false;
                    }
                }));
                return;
            }
            mailPreviewTextBox.Visible = true;
            mailToolStrip.Visible = true;
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
                    foreach (WinLinkMail draggedMail in draggedMails)
                    {
                        // Move mail to the destination mailbox
                        MoveMailInBroker(draggedMail.MID, destMailBox);
                    }
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
            if (mailboxListView.SelectedItems.Count == 0) return;

            // Get the current mailbox
            string selectedMailbox = GetSelectedMailbox();

            if (selectedMailbox == "Trash")
            {
                // Already in Trash - permanently delete
                int count = mailboxListView.SelectedItems.Count;
                string message = count == 1
                    ? "This message will be permanently deleted. Are you sure?"
                    : $"These {count} messages will be permanently deleted. Are you sure?";

                if (MessageBox.Show(this, message, "Delete Permanently", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
                {
                    foreach (ListViewItem l in mailboxListView.SelectedItems)
                    {
                        WinLinkMail m = (WinLinkMail)l.Tag;
                        DeleteMailFromBroker(m.MID);
                    }
                }
            }
            else
            {
                // Not in Trash - move to Trash with confirmation
                int count = mailboxListView.SelectedItems.Count;
                string message = count == 1
                    ? "Move the selected message to Trash?"
                    : $"Move the selected {count} messages to Trash?";

                if (MessageBox.Show(this, message, "Move to Trash", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    MoveSelectedMailsTo("Trash");
                }
            }
        }

        private void MoveSelectedMailsTo(string mailbox)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;
            foreach (ListViewItem l in mailboxListView.SelectedItems)
            {
                WinLinkMail selectedMail = (WinLinkMail)l.Tag;
                MoveMailInBroker(selectedMail.MID, mailbox);
            }
        }

        private void deleteMailToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mailboxListView.SelectedItems.Count == 0) return;

            if (MessageBox.Show(this, "Are you sure you want to permanently delete the selected mail(s)?", "Delete Mail", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
            {
                foreach (ListViewItem l in mailboxListView.SelectedItems)
                {
                    WinLinkMail m = (WinLinkMail)l.Tag;
                    DeleteMailFromBroker(m.MID);
                }
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
            f.Show(this);
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
                        foreach (WinLinkMail mail in restoredMails)
                        {
                            if (!IsMailMidPresent(currentMails, mail.MID))
                            {
                                AddMailToBroker(mail);
                            }
                        }
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
            // Build and show the connect dropdown menu
            BuildConnectMenu();
            mailConnectContextMenuStrip.Show(mailConnectButton, new Point(0, mailConnectButton.Height));
        }

        /// <summary>
        /// Builds the connect dropdown menu with Internet and available radio options.
        /// </summary>
        private void BuildConnectMenu()
        {
            mailConnectContextMenuStrip.Items.Clear();

            // Add Internet option first
            ToolStripMenuItem internetItem = new ToolStripMenuItem("Internet (Winlink Server)");
            internetItem.Click += ConnectInternetMenuItem_Click;
            mailConnectContextMenuStrip.Items.Add(internetItem);

            // Get available radios
            var availableRadios = GetAvailableRadiosWithNames();

            // Add separator and radio options if there are any available radios
            if (availableRadios.Count > 0)
            {
                mailConnectContextMenuStrip.Items.Add(new ToolStripSeparator());

                foreach (var radio in availableRadios)
                {
                    ToolStripMenuItem radioItem = new ToolStripMenuItem(radio.FriendlyName);
                    radioItem.Tag = radio.DeviceId;
                    radioItem.Click += ConnectRadioMenuItem_Click;
                    mailConnectContextMenuStrip.Items.Add(radioItem);
                }
            }
        }

        /// <summary>
        /// Handles the Internet connection menu item click.
        /// </summary>
        private void ConnectInternetMenuItem_Click(object sender, EventArgs e)
        {
            // Dispatch event to connect to Winlink via Internet
            broker.Dispatch(1, "WinlinkSync", new { Server = "server.winlink.org", Port = 8773, UseTls = true }, store: false);
        }

        /// <summary>
        /// Handles a radio connection menu item click.
        /// </summary>
        private void ConnectRadioMenuItem_Click(object sender, EventArgs e)
        {
            if (!(sender is ToolStripMenuItem menuItem)) return;
            if (!(menuItem.Tag is int radioId)) return;

            // Show station selector for Winlink stations
            ActiveStationSelectorForm f = new ActiveStationSelectorForm(StationInfoClass.StationTypes.Winlink);
            DialogResult result = f.ShowDialog(this);

            if (result == DialogResult.OK && f.selectedStation != null)
            {
                // Dispatch WinlinkSync with both the radio ID and station info
                broker.Dispatch(1, "WinlinkSync", new { RadioId = radioId, Station = f.selectedStation }, store: false);
            }
            else if (result == DialogResult.Yes)
            {
                // User wants to create a new Winlink station
                AddStationForm addForm = new AddStationForm();
                addForm.FixStationType(StationInfoClass.StationTypes.Winlink);

                if (addForm.ShowDialog(this) == DialogResult.OK)
                {
                    // Get the new station and save it
                    StationInfoClass newStation = addForm.SerializeToObject();
                    List<StationInfoClass> stations = broker.GetValue<List<StationInfoClass>>(0, "Stations", new List<StationInfoClass>());

                    // Remove any existing station with same callsign and type
                    stations.RemoveAll(s => s.Callsign == newStation.Callsign && s.StationType == newStation.StationType);
                    stations.Add(newStation);
                    broker.Dispatch(0, "Stations", stations, store: true);

                    // Use the newly created station for the connection
                    broker.Dispatch(1, "WinlinkSync", new { RadioId = radioId, Station = newStation }, store: false);
                }
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
                // Use -2 to auto-size column to fill remaining space
                mailboxListView.Columns[2].Width = -2;
            }
        }

        /// <summary>
        /// Gets the currently selected mail from the list view, or null if none selected.
        /// </summary>
        private WinLinkMail GetSelectedMail()
        {
            if (mailboxListView.SelectedItems.Count == 0) return null;
            return (WinLinkMail)mailboxListView.SelectedItems[0].Tag;
        }

        /// <summary>
        /// Creates a new mail based on the selected mail and shows the compose form.
        /// </summary>
        private void ComposeNewMailFrom(Func<WinLinkMail, WinLinkMail> createMail)
        {
            WinLinkMail original = GetSelectedMail();
            if (original == null) return;

            WinLinkMail newMail = createMail(original);
            MailComposeForm f = new MailComposeForm(newMail);
            if (f.ShowDialog(this) == DialogResult.OK)
            {
                AddMail(f.mail);
            }
        }

        private void mailReplyToolStripButton_Click(object sender, EventArgs e)
        {
            ComposeNewMailFrom(m => new WinLinkMail
            {
                To = m.From,
                Subject = m.Subject.StartsWith("Re: ") ? m.Subject : "Re: " + m.Subject,
                Body = $"\r\n\r\n--- Original Message ---\r\nFrom: {m.From}\r\nDate: {m.DateTime.ToLocalTime()}\r\n\r\n{m.Body}"
            });
        }

        private void mailReplyAllToolStripButton_Click(object sender, EventArgs e)
        {
            ComposeNewMailFrom(m => new WinLinkMail
            {
                To = m.From,
                Cc = m.Cc,
                Subject = m.Subject.StartsWith("Re: ") ? m.Subject : "Re: " + m.Subject,
                Body = $"\r\n\r\n--- Original Message ---\r\nFrom: {m.From}\r\nDate: {m.DateTime.ToLocalTime()}\r\n\r\n{m.Body}"
            });
        }

        private void mailForwardToolStripButton_Click(object sender, EventArgs e)
        {
            ComposeNewMailFrom(m => new WinLinkMail
            {
                Subject = m.Subject.StartsWith("Fwd: ") ? m.Subject : "Fwd: " + m.Subject,
                Body = $"\r\n\r\n--- Forwarded Message ---\r\nFrom: {m.From}\r\nTo: {m.To}\r\nDate: {m.DateTime.ToLocalTime()}\r\nSubject: {m.Subject}\r\n\r\n{m.Body}",
                Attachments = m.Attachments != null ? new List<WinLinkMailAttachement>(m.Attachments) : null
            });
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

        private void disconnectButton_Click(object sender, EventArgs e)
        {
            // Dispatch WinlinkDisconnect to stop the current Winlink session
            broker.Dispatch(1, "WinlinkDisconnect", null, store: false);
        }

        private void mailboxListView_ColumnClick(object sender, ColumnClickEventArgs e)
        {
            if (e.Column == mailSortColumn)
            {
                mailSortOrder = (mailSortOrder == SortOrder.Ascending) ? SortOrder.Descending : SortOrder.Ascending;
            }
            else
            {
                mailSortColumn = e.Column;
                mailSortOrder = SortOrder.Ascending;
            }
            mailboxListView.ListViewItemSorter = new MailListViewComparer(mailSortColumn, mailSortOrder);
            mailboxListView.Sort();
            UpdateMailSortGlyph();
        }

        private void UpdateMailSortGlyph()
        {
            for (int i = 0; i < mailboxListView.Columns.Count; i++)
            {
                if (i == mailSortColumn)
                {
                    string arrow = (mailSortOrder == SortOrder.Ascending) ? " \u25B2" : " \u25BC";
                    mailboxListView.Columns[i].Text = mailColumnBaseNames[i] + arrow;
                }
                else
                {
                    mailboxListView.Columns[i].Text = mailColumnBaseNames[i];
                }
            }
        }
    }

    /// <summary>
    /// Custom comparer for sorting the mailbox ListView items.
    /// </summary>
    public class MailListViewComparer : System.Collections.IComparer
    {
        private readonly int columnIndex;
        private readonly SortOrder sortOrder;

        public MailListViewComparer(int column, SortOrder order)
        {
            columnIndex = column;
            sortOrder = order;
        }

        public int Compare(object x, object y)
        {
            ListViewItem itemX = x as ListViewItem;
            ListViewItem itemY = y as ListViewItem;
            if (itemX == null || itemY == null) return 0;

            int result;
            if (columnIndex == 0)
            {
                // Sort by DateTime from the Tag
                WinLinkMail mailX = itemX.Tag as WinLinkMail;
                WinLinkMail mailY = itemY.Tag as WinLinkMail;
                if (mailX != null && mailY != null)
                    result = mailX.DateTime.CompareTo(mailY.DateTime);
                else
                    result = string.Compare(itemX.SubItems[0].Text, itemY.SubItems[0].Text, StringComparison.OrdinalIgnoreCase);
            }
            else
            {
                result = string.Compare(itemX.SubItems[columnIndex].Text, itemY.SubItems[columnIndex].Text, StringComparison.OrdinalIgnoreCase);
            }

            if (sortOrder == SortOrder.Descending) result = -result;
            return result;
        }
    }
}
