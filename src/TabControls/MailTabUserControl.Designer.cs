namespace HTCommander.Controls
{
    partial class MailTabUserControl
    {
        /// <summary> 
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary> 
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Component Designer generated code

        /// <summary> 
        /// Required method for Designer support - do not modify 
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(MailTabUserControl));
            mailboxHorizontalSplitContainer = new System.Windows.Forms.SplitContainer();
            mailboxVerticalSplitContainer = new System.Windows.Forms.SplitContainer();
            mailBoxesTreeView = new System.Windows.Forms.TreeView();
            mailBoxImageList = new System.Windows.Forms.ImageList(components);
            mailboxListView = new System.Windows.Forms.ListView();
            columnHeader4 = new System.Windows.Forms.ColumnHeader();
            columnHeader5 = new System.Windows.Forms.ColumnHeader();
            columnHeader6 = new System.Windows.Forms.ColumnHeader();
            mailContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            viewMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            editMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem14 = new System.Windows.Forms.ToolStripSeparator();
            moveToDraftToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            moveToOutboxToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            moveToInboxToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            moveToArchiveToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            moveToTrashToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem15 = new System.Windows.Forms.ToolStripSeparator();
            deleteMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            mainImageList = new System.Windows.Forms.ImageList(components);
            mailPreviewTextBox = new System.Windows.Forms.RichTextBox();
            mailToolStrip = new System.Windows.Forms.ToolStrip();
            mailReplyToolStripButton = new System.Windows.Forms.ToolStripButton();
            mailReplyAllToolStripButton = new System.Windows.Forms.ToolStripButton();
            mailForwardToolStripButton = new System.Windows.Forms.ToolStripButton();
            toolStripSeparator2 = new System.Windows.Forms.ToolStripSeparator();
            mailDeleteToolStripButton = new System.Windows.Forms.ToolStripButton();
            mailTransferStatusPanel = new System.Windows.Forms.Panel();
            mailTransferStatusLabel = new System.Windows.Forms.Label();
            mailTopPanel = new System.Windows.Forms.Panel();
            mailInternetButton = new System.Windows.Forms.Button();
            newMailButton = new System.Windows.Forms.Button();
            mailConnectButton = new System.Windows.Forms.Button();
            mailMenuPictureBox = new System.Windows.Forms.PictureBox();
            mailTitleLabel = new System.Windows.Forms.Label();
            mailTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            showPreviewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            showTrafficToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem16 = new System.Windows.Forms.ToolStripSeparator();
            backupMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            restoreMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            backupMailSaveFileDialog = new System.Windows.Forms.SaveFileDialog();
            restoreMailOpenFileDialog = new System.Windows.Forms.OpenFileDialog();
            ((System.ComponentModel.ISupportInitialize)mailboxHorizontalSplitContainer).BeginInit();
            mailboxHorizontalSplitContainer.Panel1.SuspendLayout();
            mailboxHorizontalSplitContainer.Panel2.SuspendLayout();
            mailboxHorizontalSplitContainer.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)mailboxVerticalSplitContainer).BeginInit();
            mailboxVerticalSplitContainer.Panel1.SuspendLayout();
            mailboxVerticalSplitContainer.Panel2.SuspendLayout();
            mailboxVerticalSplitContainer.SuspendLayout();
            mailContextMenuStrip.SuspendLayout();
            mailToolStrip.SuspendLayout();
            mailTransferStatusPanel.SuspendLayout();
            mailTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)mailMenuPictureBox).BeginInit();
            mailTabContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // mailboxHorizontalSplitContainer
            // 
            mailboxHorizontalSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            mailboxHorizontalSplitContainer.FixedPanel = System.Windows.Forms.FixedPanel.Panel1;
            mailboxHorizontalSplitContainer.Location = new System.Drawing.Point(0, 46);
            mailboxHorizontalSplitContainer.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            mailboxHorizontalSplitContainer.Name = "mailboxHorizontalSplitContainer";
            mailboxHorizontalSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // mailboxHorizontalSplitContainer.Panel1
            // 
            mailboxHorizontalSplitContainer.Panel1.Controls.Add(mailboxVerticalSplitContainer);
            // 
            // mailboxHorizontalSplitContainer.Panel2
            // 
            mailboxHorizontalSplitContainer.Panel2.Controls.Add(mailPreviewTextBox);
            mailboxHorizontalSplitContainer.Panel2.Controls.Add(mailToolStrip);
            mailboxHorizontalSplitContainer.Size = new System.Drawing.Size(669, 464);
            mailboxHorizontalSplitContainer.SplitterDistance = 250;
            mailboxHorizontalSplitContainer.SplitterWidth = 5;
            mailboxHorizontalSplitContainer.TabIndex = 7;
            // 
            // mailboxVerticalSplitContainer
            // 
            mailboxVerticalSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            mailboxVerticalSplitContainer.FixedPanel = System.Windows.Forms.FixedPanel.Panel1;
            mailboxVerticalSplitContainer.Location = new System.Drawing.Point(0, 0);
            mailboxVerticalSplitContainer.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            mailboxVerticalSplitContainer.Name = "mailboxVerticalSplitContainer";
            // 
            // mailboxVerticalSplitContainer.Panel1
            // 
            mailboxVerticalSplitContainer.Panel1.Controls.Add(mailBoxesTreeView);
            // 
            // mailboxVerticalSplitContainer.Panel2
            // 
            mailboxVerticalSplitContainer.Panel2.Controls.Add(mailboxListView);
            mailboxVerticalSplitContainer.Size = new System.Drawing.Size(669, 250);
            mailboxVerticalSplitContainer.SplitterDistance = 151;
            mailboxVerticalSplitContainer.TabIndex = 6;
            // 
            // mailBoxesTreeView
            // 
            mailBoxesTreeView.AllowDrop = true;
            mailBoxesTreeView.Dock = System.Windows.Forms.DockStyle.Fill;
            mailBoxesTreeView.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            mailBoxesTreeView.ImageIndex = 0;
            mailBoxesTreeView.ImageList = mailBoxImageList;
            mailBoxesTreeView.Location = new System.Drawing.Point(0, 0);
            mailBoxesTreeView.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            mailBoxesTreeView.Name = "mailBoxesTreeView";
            mailBoxesTreeView.SelectedImageIndex = 0;
            mailBoxesTreeView.ShowRootLines = false;
            mailBoxesTreeView.Size = new System.Drawing.Size(151, 250);
            mailBoxesTreeView.TabIndex = 0;
            mailBoxesTreeView.NodeMouseClick += mailBoxesTreeView_NodeMouseClick;
            mailBoxesTreeView.DragDrop += mailBoxesTreeView_DragDrop;
            mailBoxesTreeView.DragEnter += mailBoxesTreeView_DragEnter;
            mailBoxesTreeView.DragOver += mailBoxesTreeView_DragEnter;
            // 
            // mailBoxImageList
            // 
            mailBoxImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth8Bit;
            mailBoxImageList.ImageStream = (System.Windows.Forms.ImageListStreamer)resources.GetObject("mailBoxImageList.ImageStream");
            mailBoxImageList.TransparentColor = System.Drawing.Color.Transparent;
            mailBoxImageList.Images.SetKeyName(0, "mailbox-25.png");
            mailBoxImageList.Images.SetKeyName(1, "outbox-25.png");
            mailBoxImageList.Images.SetKeyName(2, "draft-25.png");
            mailBoxImageList.Images.SetKeyName(3, "sent-25.png");
            mailBoxImageList.Images.SetKeyName(4, "archive-25.png");
            mailBoxImageList.Images.SetKeyName(5, "trash-25.png");
            mailBoxImageList.Images.SetKeyName(6, "folder-25.png");
            mailBoxImageList.Images.SetKeyName(7, "junk-25.png");
            mailBoxImageList.Images.SetKeyName(8, "notes-25.png");
            // 
            // mailboxListView
            // 
            mailboxListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader4, columnHeader5, columnHeader6 });
            mailboxListView.ContextMenuStrip = mailContextMenuStrip;
            mailboxListView.Dock = System.Windows.Forms.DockStyle.Fill;
            mailboxListView.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            mailboxListView.FullRowSelect = true;
            mailboxListView.GridLines = true;
            mailboxListView.Location = new System.Drawing.Point(0, 0);
            mailboxListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mailboxListView.Name = "mailboxListView";
            mailboxListView.Size = new System.Drawing.Size(514, 250);
            mailboxListView.SmallImageList = mainImageList;
            mailboxListView.TabIndex = 5;
            mailboxListView.UseCompatibleStateImageBehavior = false;
            mailboxListView.View = System.Windows.Forms.View.Details;
            mailboxListView.SelectedIndexChanged += mailboxListView_SelectedIndexChanged;
            mailboxListView.DoubleClick += mailboxListView_DoubleClick;
            mailboxListView.KeyDown += mailboxListView_KeyDown;
            mailboxListView.MouseDown += mailboxListView_MouseDown;
            mailboxListView.MouseMove += mailboxListView_MouseMove;
            mailboxListView.MouseUp += mailboxListView_MouseUp;
            mailboxListView.Resize += mailboxListView_Resize;
            // 
            // columnHeader4
            // 
            columnHeader4.Text = "Time";
            columnHeader4.Width = 100;
            // 
            // columnHeader5
            // 
            columnHeader5.Text = "From";
            columnHeader5.Width = 100;
            // 
            // columnHeader6
            // 
            columnHeader6.Text = "Subject";
            columnHeader6.Width = 290;
            // 
            // mailContextMenuStrip
            // 
            mailContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mailContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { viewMailToolStripMenuItem, editMailToolStripMenuItem, toolStripMenuItem14, moveToDraftToolStripMenuItem, moveToOutboxToolStripMenuItem, moveToInboxToolStripMenuItem, moveToArchiveToolStripMenuItem, moveToTrashToolStripMenuItem, toolStripMenuItem15, deleteMailToolStripMenuItem });
            mailContextMenuStrip.Name = "mailContextMenuStrip";
            mailContextMenuStrip.Size = new System.Drawing.Size(187, 208);
            // 
            // viewMailToolStripMenuItem
            // 
            viewMailToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, 0);
            viewMailToolStripMenuItem.Name = "viewMailToolStripMenuItem";
            viewMailToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            viewMailToolStripMenuItem.Text = "&View...";
            viewMailToolStripMenuItem.Click += mailboxListView_DoubleClick;
            // 
            // editMailToolStripMenuItem
            // 
            editMailToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, 0);
            editMailToolStripMenuItem.Name = "editMailToolStripMenuItem";
            editMailToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            editMailToolStripMenuItem.Text = "&Edit...";
            editMailToolStripMenuItem.Click += mailboxListView_DoubleClick;
            // 
            // toolStripMenuItem14
            // 
            toolStripMenuItem14.Name = "toolStripMenuItem14";
            toolStripMenuItem14.Size = new System.Drawing.Size(183, 6);
            // 
            // moveToDraftToolStripMenuItem
            // 
            moveToDraftToolStripMenuItem.Name = "moveToDraftToolStripMenuItem";
            moveToDraftToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            moveToDraftToolStripMenuItem.Text = "Move to D&raft";
            moveToDraftToolStripMenuItem.Click += moveToDraftToolStripMenuItem_Click;
            // 
            // moveToOutboxToolStripMenuItem
            // 
            moveToOutboxToolStripMenuItem.Name = "moveToOutboxToolStripMenuItem";
            moveToOutboxToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            moveToOutboxToolStripMenuItem.Text = "Move to &Outbox";
            moveToOutboxToolStripMenuItem.Click += moveToOutboxToolStripMenuItem_Click;
            // 
            // moveToInboxToolStripMenuItem
            // 
            moveToInboxToolStripMenuItem.Name = "moveToInboxToolStripMenuItem";
            moveToInboxToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            moveToInboxToolStripMenuItem.Text = "Move to &Inbox";
            moveToInboxToolStripMenuItem.Click += moveToInboxToolStripMenuItem_Click;
            // 
            // moveToArchiveToolStripMenuItem
            // 
            moveToArchiveToolStripMenuItem.Name = "moveToArchiveToolStripMenuItem";
            moveToArchiveToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            moveToArchiveToolStripMenuItem.Text = "Move to &Archive";
            moveToArchiveToolStripMenuItem.Click += moveToArchiveToolStripMenuItem_Click;
            // 
            // moveToTrashToolStripMenuItem
            // 
            moveToTrashToolStripMenuItem.Name = "moveToTrashToolStripMenuItem";
            moveToTrashToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            moveToTrashToolStripMenuItem.Text = "Move to &Trash";
            moveToTrashToolStripMenuItem.Click += moveToTrashToolStripMenuItem_Click;
            // 
            // toolStripMenuItem15
            // 
            toolStripMenuItem15.Name = "toolStripMenuItem15";
            toolStripMenuItem15.Size = new System.Drawing.Size(183, 6);
            // 
            // deleteMailToolStripMenuItem
            // 
            deleteMailToolStripMenuItem.Name = "deleteMailToolStripMenuItem";
            deleteMailToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            deleteMailToolStripMenuItem.Text = "&Delete";
            deleteMailToolStripMenuItem.Click += deleteMailToolStripMenuItem_Click;
            // 
            // mainImageList
            // 
            mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit;
            mainImageList.ImageSize = new System.Drawing.Size(20, 20);
            mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            // 
            // mailPreviewTextBox
            // 
            mailPreviewTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            mailPreviewTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            mailPreviewTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            mailPreviewTextBox.Location = new System.Drawing.Point(0, 25);
            mailPreviewTextBox.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            mailPreviewTextBox.Name = "mailPreviewTextBox";
            mailPreviewTextBox.ReadOnly = true;
            mailPreviewTextBox.Size = new System.Drawing.Size(669, 184);
            mailPreviewTextBox.TabIndex = 0;
            mailPreviewTextBox.Text = "";
            mailPreviewTextBox.LinkClicked += mailPreviewTextBox_LinkClicked;
            // 
            // mailToolStrip
            // 
            mailToolStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mailToolStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { mailReplyToolStripButton, mailReplyAllToolStripButton, mailForwardToolStripButton, toolStripSeparator2, mailDeleteToolStripButton });
            mailToolStrip.Location = new System.Drawing.Point(0, 0);
            mailToolStrip.Name = "mailToolStrip";
            mailToolStrip.Size = new System.Drawing.Size(669, 25);
            mailToolStrip.TabIndex = 1;
            mailToolStrip.Text = "toolStrip1";
            // 
            // mailReplyToolStripButton
            // 
            mailReplyToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            mailReplyToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            mailReplyToolStripButton.Name = "mailReplyToolStripButton";
            mailReplyToolStripButton.Size = new System.Drawing.Size(29, 22);
            mailReplyToolStripButton.Text = "Reply";
            mailReplyToolStripButton.Click += mailReplyToolStripButton_Click;
            // 
            // mailReplyAllToolStripButton
            // 
            mailReplyAllToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            mailReplyAllToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            mailReplyAllToolStripButton.Name = "mailReplyAllToolStripButton";
            mailReplyAllToolStripButton.Size = new System.Drawing.Size(29, 22);
            mailReplyAllToolStripButton.Text = "Reply All";
            mailReplyAllToolStripButton.Click += mailReplyAllToolStripButton_Click;
            // 
            // mailForwardToolStripButton
            // 
            mailForwardToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            mailForwardToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            mailForwardToolStripButton.Name = "mailForwardToolStripButton";
            mailForwardToolStripButton.Size = new System.Drawing.Size(29, 22);
            mailForwardToolStripButton.Text = "Forward";
            mailForwardToolStripButton.Click += mailForwardToolStripButton_Click;
            // 
            // toolStripSeparator2
            // 
            toolStripSeparator2.Name = "toolStripSeparator2";
            toolStripSeparator2.Size = new System.Drawing.Size(6, 25);
            // 
            // mailDeleteToolStripButton
            // 
            mailDeleteToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            mailDeleteToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            mailDeleteToolStripButton.Name = "mailDeleteToolStripButton";
            mailDeleteToolStripButton.Size = new System.Drawing.Size(29, 22);
            mailDeleteToolStripButton.Text = "Delete";
            mailDeleteToolStripButton.Click += mailDeleteToolStripButton_Click;
            // 
            // mailTransferStatusPanel
            // 
            mailTransferStatusPanel.BackColor = System.Drawing.Color.Silver;
            mailTransferStatusPanel.Controls.Add(mailTransferStatusLabel);
            mailTransferStatusPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            mailTransferStatusPanel.Location = new System.Drawing.Point(0, 510);
            mailTransferStatusPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mailTransferStatusPanel.Name = "mailTransferStatusPanel";
            mailTransferStatusPanel.Size = new System.Drawing.Size(669, 46);
            mailTransferStatusPanel.TabIndex = 8;
            mailTransferStatusPanel.Visible = false;
            // 
            // mailTransferStatusLabel
            // 
            mailTransferStatusLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            mailTransferStatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            mailTransferStatusLabel.Location = new System.Drawing.Point(4, 8);
            mailTransferStatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            mailTransferStatusLabel.Name = "mailTransferStatusLabel";
            mailTransferStatusLabel.Size = new System.Drawing.Size(658, 31);
            mailTransferStatusLabel.TabIndex = 1;
            mailTransferStatusLabel.Text = "Disconnected";
            // 
            // mailTopPanel
            // 
            mailTopPanel.BackColor = System.Drawing.Color.Silver;
            mailTopPanel.Controls.Add(mailInternetButton);
            mailTopPanel.Controls.Add(newMailButton);
            mailTopPanel.Controls.Add(mailConnectButton);
            mailTopPanel.Controls.Add(mailMenuPictureBox);
            mailTopPanel.Controls.Add(mailTitleLabel);
            mailTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            mailTopPanel.Location = new System.Drawing.Point(0, 0);
            mailTopPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mailTopPanel.Name = "mailTopPanel";
            mailTopPanel.Size = new System.Drawing.Size(669, 46);
            mailTopPanel.TabIndex = 2;
            // 
            // mailInternetButton
            // 
            mailInternetButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            mailInternetButton.Location = new System.Drawing.Point(418, 5);
            mailInternetButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mailInternetButton.Name = "mailInternetButton";
            mailInternetButton.Size = new System.Drawing.Size(100, 35);
            mailInternetButton.TabIndex = 7;
            mailInternetButton.Text = "&Internet";
            mailInternetButton.UseVisualStyleBackColor = true;
            mailInternetButton.Click += mailInternetButton_Click;
            // 
            // newMailButton
            // 
            newMailButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            newMailButton.Location = new System.Drawing.Point(310, 5);
            newMailButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            newMailButton.Name = "newMailButton";
            newMailButton.Size = new System.Drawing.Size(100, 35);
            newMailButton.TabIndex = 6;
            newMailButton.Text = "&New Mail";
            newMailButton.UseVisualStyleBackColor = true;
            newMailButton.Click += newMailButton_Click;
            // 
            // mailConnectButton
            // 
            mailConnectButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            mailConnectButton.Enabled = false;
            mailConnectButton.Location = new System.Drawing.Point(526, 5);
            mailConnectButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mailConnectButton.Name = "mailConnectButton";
            mailConnectButton.Size = new System.Drawing.Size(100, 35);
            mailConnectButton.TabIndex = 5;
            mailConnectButton.Text = "&Connect...";
            mailConnectButton.UseVisualStyleBackColor = true;
            mailConnectButton.Click += mailConnectButton_Click;
            // 
            // mailMenuPictureBox
            // 
            mailMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            mailMenuPictureBox.Image = Properties.Resources.MenuIcon;
            mailMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            mailMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mailMenuPictureBox.Name = "mailMenuPictureBox";
            mailMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            mailMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            mailMenuPictureBox.TabIndex = 4;
            mailMenuPictureBox.TabStop = false;
            mailMenuPictureBox.MouseClick += mailMenuPictureBox_MouseClick;
            // 
            // mailTitleLabel
            // 
            mailTitleLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            mailTitleLabel.AutoSize = true;
            mailTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            mailTitleLabel.Location = new System.Drawing.Point(4, 8);
            mailTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            mailTitleLabel.Name = "mailTitleLabel";
            mailTitleLabel.Size = new System.Drawing.Size(48, 25);
            mailTitleLabel.TabIndex = 1;
            mailTitleLabel.Text = "Mail";
            // 
            // mailTabContextMenuStrip
            // 
            mailTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mailTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { showPreviewToolStripMenuItem, showTrafficToolStripMenuItem, toolStripMenuItem16, backupMailToolStripMenuItem, restoreMailToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            mailTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            mailTabContextMenuStrip.Size = new System.Drawing.Size(171, 136);
            // 
            // showPreviewToolStripMenuItem
            // 
            showPreviewToolStripMenuItem.CheckOnClick = true;
            showPreviewToolStripMenuItem.Name = "showPreviewToolStripMenuItem";
            showPreviewToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            showPreviewToolStripMenuItem.Text = "&Show Preview";
            showPreviewToolStripMenuItem.Click += showPreviewToolStripMenuItem_Click;
            // 
            // showTrafficToolStripMenuItem
            // 
            showTrafficToolStripMenuItem.Name = "showTrafficToolStripMenuItem";
            showTrafficToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            showTrafficToolStripMenuItem.Text = "Show Traffic...";
            showTrafficToolStripMenuItem.Click += showTrafficToolStripMenuItem_Click;
            // 
            // toolStripMenuItem16
            // 
            toolStripMenuItem16.Name = "toolStripMenuItem16";
            toolStripMenuItem16.Size = new System.Drawing.Size(167, 6);
            // 
            // backupMailToolStripMenuItem
            // 
            backupMailToolStripMenuItem.Name = "backupMailToolStripMenuItem";
            backupMailToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            backupMailToolStripMenuItem.Text = "&Backup Mail...";
            backupMailToolStripMenuItem.Click += backupMailToolStripMenuItem_Click;
            // 
            // restoreMailToolStripMenuItem
            // 
            restoreMailToolStripMenuItem.Name = "restoreMailToolStripMenuItem";
            restoreMailToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            restoreMailToolStripMenuItem.Text = "&Restore Mail...";
            restoreMailToolStripMenuItem.Click += restoreMailToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(167, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // backupMailSaveFileDialog
            // 
            backupMailSaveFileDialog.DefaultExt = "htmails";
            backupMailSaveFileDialog.FileName = "Backup";
            backupMailSaveFileDialog.Filter = "Mails (*.htmails)|*.htmails";
            backupMailSaveFileDialog.Title = "Backup Mail";
            // 
            // restoreMailOpenFileDialog
            // 
            restoreMailOpenFileDialog.DefaultExt = "htmails";
            restoreMailOpenFileDialog.FileName = "mails";
            restoreMailOpenFileDialog.Filter = "Mails (*.htmails)|*.htmails";
            restoreMailOpenFileDialog.Title = "Restore Mail";
            // 
            // MailTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(mailboxHorizontalSplitContainer);
            Controls.Add(mailTransferStatusPanel);
            Controls.Add(mailTopPanel);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            Name = "MailTabUserControl";
            Size = new System.Drawing.Size(669, 556);
            mailboxHorizontalSplitContainer.Panel1.ResumeLayout(false);
            mailboxHorizontalSplitContainer.Panel2.ResumeLayout(false);
            mailboxHorizontalSplitContainer.Panel2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)mailboxHorizontalSplitContainer).EndInit();
            mailboxHorizontalSplitContainer.ResumeLayout(false);
            mailboxVerticalSplitContainer.Panel1.ResumeLayout(false);
            mailboxVerticalSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)mailboxVerticalSplitContainer).EndInit();
            mailboxVerticalSplitContainer.ResumeLayout(false);
            mailContextMenuStrip.ResumeLayout(false);
            mailToolStrip.ResumeLayout(false);
            mailToolStrip.PerformLayout();
            mailTransferStatusPanel.ResumeLayout(false);
            mailTopPanel.ResumeLayout(false);
            mailTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)mailMenuPictureBox).EndInit();
            mailTabContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.SplitContainer mailboxHorizontalSplitContainer;
        private System.Windows.Forms.SplitContainer mailboxVerticalSplitContainer;
        private System.Windows.Forms.TreeView mailBoxesTreeView;
        private System.Windows.Forms.ImageList mailBoxImageList;
        private System.Windows.Forms.ListView mailboxListView;
        private System.Windows.Forms.ColumnHeader columnHeader4;
        private System.Windows.Forms.ColumnHeader columnHeader5;
        private System.Windows.Forms.ColumnHeader columnHeader6;
        private System.Windows.Forms.ContextMenuStrip mailContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem viewMailToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem editMailToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem14;
        private System.Windows.Forms.ToolStripMenuItem moveToDraftToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToOutboxToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToInboxToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToArchiveToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem moveToTrashToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem15;
        private System.Windows.Forms.ToolStripMenuItem deleteMailToolStripMenuItem;
        private System.Windows.Forms.ImageList mainImageList;
        private System.Windows.Forms.RichTextBox mailPreviewTextBox;
        private System.Windows.Forms.ToolStrip mailToolStrip;
        private System.Windows.Forms.ToolStripButton mailReplyToolStripButton;
        private System.Windows.Forms.ToolStripButton mailReplyAllToolStripButton;
        private System.Windows.Forms.ToolStripButton mailForwardToolStripButton;
        private System.Windows.Forms.ToolStripSeparator toolStripSeparator2;
        private System.Windows.Forms.ToolStripButton mailDeleteToolStripButton;
        private System.Windows.Forms.Panel mailTransferStatusPanel;
        private System.Windows.Forms.Label mailTransferStatusLabel;
        private System.Windows.Forms.Panel mailTopPanel;
        private System.Windows.Forms.Button mailInternetButton;
        private System.Windows.Forms.Button newMailButton;
        private System.Windows.Forms.Button mailConnectButton;
        private System.Windows.Forms.PictureBox mailMenuPictureBox;
        private System.Windows.Forms.Label mailTitleLabel;
        private System.Windows.Forms.ContextMenuStrip mailTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem showPreviewToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem showTrafficToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem16;
        private System.Windows.Forms.ToolStripMenuItem backupMailToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem restoreMailToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog backupMailSaveFileDialog;
        private System.Windows.Forms.OpenFileDialog restoreMailOpenFileDialog;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
    }
}
