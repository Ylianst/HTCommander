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
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(MailTabUserControl));
            this.mailboxHorizontalSplitContainer = new System.Windows.Forms.SplitContainer();
            this.mailboxVerticalSplitContainer = new System.Windows.Forms.SplitContainer();
            this.mailBoxesTreeView = new System.Windows.Forms.TreeView();
            this.mailBoxImageList = new System.Windows.Forms.ImageList(this.components);
            this.mailboxListView = new System.Windows.Forms.ListView();
            this.columnHeader4 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader5 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.columnHeader6 = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.mailContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.viewMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.editMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem14 = new System.Windows.Forms.ToolStripSeparator();
            this.moveToDraftToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToOutboxToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToInboxToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToArchiveToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.moveToTrashToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem15 = new System.Windows.Forms.ToolStripSeparator();
            this.deleteMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mainImageList = new System.Windows.Forms.ImageList(this.components);
            this.mailPreviewTextBox = new System.Windows.Forms.RichTextBox();
            this.mailToolStrip = new System.Windows.Forms.ToolStrip();
            this.mailReplyToolStripButton = new System.Windows.Forms.ToolStripButton();
            this.mailReplyAllToolStripButton = new System.Windows.Forms.ToolStripButton();
            this.mailForwardToolStripButton = new System.Windows.Forms.ToolStripButton();
            this.toolStripSeparator2 = new System.Windows.Forms.ToolStripSeparator();
            this.mailDeleteToolStripButton = new System.Windows.Forms.ToolStripButton();
            this.mailTransferStatusPanel = new System.Windows.Forms.Panel();
            this.mailTransferStatusLabel = new System.Windows.Forms.Label();
            this.mailTopPanel = new System.Windows.Forms.Panel();
            this.mailInternetButton = new System.Windows.Forms.Button();
            this.newMailButton = new System.Windows.Forms.Button();
            this.mailConnectButton = new System.Windows.Forms.Button();
            this.mailMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.mailTitleLabel = new System.Windows.Forms.Label();
            this.mailTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.showPreviewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.showTrafficToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem16 = new System.Windows.Forms.ToolStripSeparator();
            this.backupMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.restoreMailToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.backupMailSaveFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.restoreMailOpenFileDialog = new System.Windows.Forms.OpenFileDialog();
            ((System.ComponentModel.ISupportInitialize)(this.mailboxHorizontalSplitContainer)).BeginInit();
            this.mailboxHorizontalSplitContainer.Panel1.SuspendLayout();
            this.mailboxHorizontalSplitContainer.Panel2.SuspendLayout();
            this.mailboxHorizontalSplitContainer.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailboxVerticalSplitContainer)).BeginInit();
            this.mailboxVerticalSplitContainer.Panel1.SuspendLayout();
            this.mailboxVerticalSplitContainer.Panel2.SuspendLayout();
            this.mailboxVerticalSplitContainer.SuspendLayout();
            this.mailContextMenuStrip.SuspendLayout();
            this.mailToolStrip.SuspendLayout();
            this.mailTransferStatusPanel.SuspendLayout();
            this.mailTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailMenuPictureBox)).BeginInit();
            this.mailTabContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // mailboxHorizontalSplitContainer
            // 
            this.mailboxHorizontalSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailboxHorizontalSplitContainer.FixedPanel = System.Windows.Forms.FixedPanel.Panel1;
            this.mailboxHorizontalSplitContainer.Location = new System.Drawing.Point(0, 37);
            this.mailboxHorizontalSplitContainer.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.mailboxHorizontalSplitContainer.Name = "mailboxHorizontalSplitContainer";
            this.mailboxHorizontalSplitContainer.Orientation = System.Windows.Forms.Orientation.Horizontal;
            // 
            // mailboxHorizontalSplitContainer.Panel1
            // 
            this.mailboxHorizontalSplitContainer.Panel1.Controls.Add(this.mailboxVerticalSplitContainer);
            // 
            // mailboxHorizontalSplitContainer.Panel2
            // 
            this.mailboxHorizontalSplitContainer.Panel2.Controls.Add(this.mailPreviewTextBox);
            this.mailboxHorizontalSplitContainer.Panel2.Controls.Add(this.mailToolStrip);
            this.mailboxHorizontalSplitContainer.Size = new System.Drawing.Size(669, 584);
            this.mailboxHorizontalSplitContainer.SplitterDistance = 200;
            this.mailboxHorizontalSplitContainer.TabIndex = 7;
            // 
            // mailboxVerticalSplitContainer
            // 
            this.mailboxVerticalSplitContainer.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailboxVerticalSplitContainer.FixedPanel = System.Windows.Forms.FixedPanel.Panel1;
            this.mailboxVerticalSplitContainer.Location = new System.Drawing.Point(0, 0);
            this.mailboxVerticalSplitContainer.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.mailboxVerticalSplitContainer.Name = "mailboxVerticalSplitContainer";
            // 
            // mailboxVerticalSplitContainer.Panel1
            // 
            this.mailboxVerticalSplitContainer.Panel1.Controls.Add(this.mailBoxesTreeView);
            // 
            // mailboxVerticalSplitContainer.Panel2
            // 
            this.mailboxVerticalSplitContainer.Panel2.Controls.Add(this.mailboxListView);
            this.mailboxVerticalSplitContainer.Size = new System.Drawing.Size(669, 200);
            this.mailboxVerticalSplitContainer.SplitterDistance = 151;
            this.mailboxVerticalSplitContainer.TabIndex = 6;
            // 
            // mailBoxesTreeView
            // 
            this.mailBoxesTreeView.AllowDrop = true;
            this.mailBoxesTreeView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailBoxesTreeView.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mailBoxesTreeView.ImageIndex = 0;
            this.mailBoxesTreeView.ImageList = this.mailBoxImageList;
            this.mailBoxesTreeView.Location = new System.Drawing.Point(0, 0);
            this.mailBoxesTreeView.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.mailBoxesTreeView.Name = "mailBoxesTreeView";
            this.mailBoxesTreeView.SelectedImageIndex = 0;
            this.mailBoxesTreeView.ShowRootLines = false;
            this.mailBoxesTreeView.Size = new System.Drawing.Size(151, 200);
            this.mailBoxesTreeView.TabIndex = 0;
            this.mailBoxesTreeView.NodeMouseClick += new System.Windows.Forms.TreeNodeMouseClickEventHandler(this.mailBoxesTreeView_NodeMouseClick);
            this.mailBoxesTreeView.DragDrop += new System.Windows.Forms.DragEventHandler(this.mailBoxesTreeView_DragDrop);
            this.mailBoxesTreeView.DragEnter += new System.Windows.Forms.DragEventHandler(this.mailBoxesTreeView_DragEnter);
            this.mailBoxesTreeView.DragOver += new System.Windows.Forms.DragEventHandler(this.mailBoxesTreeView_DragEnter);
            // 
            // mailBoxImageList
            // 
            this.mailBoxImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit;
            this.mailBoxImageList.ImageSize = new System.Drawing.Size(25, 25);
            this.mailBoxImageList.TransparentColor = System.Drawing.Color.Transparent;
            // 
            // mailboxListView
            // 
            this.mailboxListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.columnHeader4,
            this.columnHeader5,
            this.columnHeader6});
            this.mailboxListView.ContextMenuStrip = this.mailContextMenuStrip;
            this.mailboxListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailboxListView.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mailboxListView.FullRowSelect = true;
            this.mailboxListView.GridLines = true;
            this.mailboxListView.HideSelection = false;
            this.mailboxListView.Location = new System.Drawing.Point(0, 0);
            this.mailboxListView.Margin = new System.Windows.Forms.Padding(4);
            this.mailboxListView.Name = "mailboxListView";
            this.mailboxListView.Size = new System.Drawing.Size(514, 200);
            this.mailboxListView.SmallImageList = this.mainImageList;
            this.mailboxListView.TabIndex = 5;
            this.mailboxListView.UseCompatibleStateImageBehavior = false;
            this.mailboxListView.View = System.Windows.Forms.View.Details;
            this.mailboxListView.SelectedIndexChanged += new System.EventHandler(this.mailboxListView_SelectedIndexChanged);
            this.mailboxListView.DoubleClick += new System.EventHandler(this.mailboxListView_DoubleClick);
            this.mailboxListView.KeyDown += new System.Windows.Forms.KeyEventHandler(this.mailboxListView_KeyDown);
            this.mailboxListView.MouseDown += new System.Windows.Forms.MouseEventHandler(this.mailboxListView_MouseDown);
            this.mailboxListView.MouseMove += new System.Windows.Forms.MouseEventHandler(this.mailboxListView_MouseMove);
            this.mailboxListView.MouseUp += new System.Windows.Forms.MouseEventHandler(this.mailboxListView_MouseUp);
            this.mailboxListView.Resize += new System.EventHandler(this.mailboxListView_Resize);
            // 
            // columnHeader4
            // 
            this.columnHeader4.Text = "Time";
            this.columnHeader4.Width = 100;
            // 
            // columnHeader5
            // 
            this.columnHeader5.Text = "From";
            this.columnHeader5.Width = 100;
            // 
            // columnHeader6
            // 
            this.columnHeader6.Text = "Subject";
            this.columnHeader6.Width = 290;
            // 
            // mailContextMenuStrip
            // 
            this.mailContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mailContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.viewMailToolStripMenuItem,
            this.editMailToolStripMenuItem,
            this.toolStripMenuItem14,
            this.moveToDraftToolStripMenuItem,
            this.moveToOutboxToolStripMenuItem,
            this.moveToInboxToolStripMenuItem,
            this.moveToArchiveToolStripMenuItem,
            this.moveToTrashToolStripMenuItem,
            this.toolStripMenuItem15,
            this.deleteMailToolStripMenuItem});
            this.mailContextMenuStrip.Name = "mailContextMenuStrip";
            this.mailContextMenuStrip.Size = new System.Drawing.Size(187, 208);
            // 
            // viewMailToolStripMenuItem
            // 
            this.viewMailToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.viewMailToolStripMenuItem.Name = "viewMailToolStripMenuItem";
            this.viewMailToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.viewMailToolStripMenuItem.Text = "&View...";
            this.viewMailToolStripMenuItem.Click += new System.EventHandler(this.mailboxListView_DoubleClick);
            // 
            // editMailToolStripMenuItem
            // 
            this.editMailToolStripMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.editMailToolStripMenuItem.Name = "editMailToolStripMenuItem";
            this.editMailToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.editMailToolStripMenuItem.Text = "&Edit...";
            this.editMailToolStripMenuItem.Click += new System.EventHandler(this.mailboxListView_DoubleClick);
            // 
            // toolStripMenuItem14
            // 
            this.toolStripMenuItem14.Name = "toolStripMenuItem14";
            this.toolStripMenuItem14.Size = new System.Drawing.Size(183, 6);
            // 
            // moveToDraftToolStripMenuItem
            // 
            this.moveToDraftToolStripMenuItem.Name = "moveToDraftToolStripMenuItem";
            this.moveToDraftToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.moveToDraftToolStripMenuItem.Text = "Move to D&raft";
            this.moveToDraftToolStripMenuItem.Click += new System.EventHandler(this.moveToDraftToolStripMenuItem_Click);
            // 
            // moveToOutboxToolStripMenuItem
            // 
            this.moveToOutboxToolStripMenuItem.Name = "moveToOutboxToolStripMenuItem";
            this.moveToOutboxToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.moveToOutboxToolStripMenuItem.Text = "Move to &Outbox";
            this.moveToOutboxToolStripMenuItem.Click += new System.EventHandler(this.moveToOutboxToolStripMenuItem_Click);
            // 
            // moveToInboxToolStripMenuItem
            // 
            this.moveToInboxToolStripMenuItem.Name = "moveToInboxToolStripMenuItem";
            this.moveToInboxToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.moveToInboxToolStripMenuItem.Text = "Move to &Inbox";
            this.moveToInboxToolStripMenuItem.Click += new System.EventHandler(this.moveToInboxToolStripMenuItem_Click);
            // 
            // moveToArchiveToolStripMenuItem
            // 
            this.moveToArchiveToolStripMenuItem.Name = "moveToArchiveToolStripMenuItem";
            this.moveToArchiveToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.moveToArchiveToolStripMenuItem.Text = "Move to &Archive";
            this.moveToArchiveToolStripMenuItem.Click += new System.EventHandler(this.moveToArchiveToolStripMenuItem_Click);
            // 
            // moveToTrashToolStripMenuItem
            // 
            this.moveToTrashToolStripMenuItem.Name = "moveToTrashToolStripMenuItem";
            this.moveToTrashToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.moveToTrashToolStripMenuItem.Text = "Move to &Trash";
            this.moveToTrashToolStripMenuItem.Click += new System.EventHandler(this.moveToTrashToolStripMenuItem_Click);
            // 
            // toolStripMenuItem15
            // 
            this.toolStripMenuItem15.Name = "toolStripMenuItem15";
            this.toolStripMenuItem15.Size = new System.Drawing.Size(183, 6);
            // 
            // deleteMailToolStripMenuItem
            // 
            this.deleteMailToolStripMenuItem.Name = "deleteMailToolStripMenuItem";
            this.deleteMailToolStripMenuItem.Size = new System.Drawing.Size(186, 24);
            this.deleteMailToolStripMenuItem.Text = "&Delete";
            this.deleteMailToolStripMenuItem.Click += new System.EventHandler(this.deleteMailToolStripMenuItem_Click);
            // 
            // mainImageList
            // 
            this.mainImageList.ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit;
            this.mainImageList.ImageSize = new System.Drawing.Size(20, 20);
            this.mainImageList.TransparentColor = System.Drawing.Color.Transparent;
            // 
            // mailPreviewTextBox
            // 
            this.mailPreviewTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.mailPreviewTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mailPreviewTextBox.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mailPreviewTextBox.Location = new System.Drawing.Point(0, 27);
            this.mailPreviewTextBox.Margin = new System.Windows.Forms.Padding(3, 1, 3, 1);
            this.mailPreviewTextBox.Name = "mailPreviewTextBox";
            this.mailPreviewTextBox.ReadOnly = true;
            this.mailPreviewTextBox.Size = new System.Drawing.Size(669, 353);
            this.mailPreviewTextBox.TabIndex = 0;
            this.mailPreviewTextBox.Text = "";
            this.mailPreviewTextBox.LinkClicked += new System.Windows.Forms.LinkClickedEventHandler(this.mailPreviewTextBox_LinkClicked);
            // 
            // mailToolStrip
            // 
            this.mailToolStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mailToolStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.mailReplyToolStripButton,
            this.mailReplyAllToolStripButton,
            this.mailForwardToolStripButton,
            this.toolStripSeparator2,
            this.mailDeleteToolStripButton});
            this.mailToolStrip.Location = new System.Drawing.Point(0, 0);
            this.mailToolStrip.Name = "mailToolStrip";
            this.mailToolStrip.Size = new System.Drawing.Size(669, 27);
            this.mailToolStrip.TabIndex = 1;
            this.mailToolStrip.Text = "toolStrip1";
            // 
            // mailReplyToolStripButton
            // 
            this.mailReplyToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            this.mailReplyToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            this.mailReplyToolStripButton.Name = "mailReplyToolStripButton";
            this.mailReplyToolStripButton.Size = new System.Drawing.Size(29, 24);
            this.mailReplyToolStripButton.Text = "Reply";
            this.mailReplyToolStripButton.Click += new System.EventHandler(this.mailReplyToolStripButton_Click);
            // 
            // mailReplyAllToolStripButton
            // 
            this.mailReplyAllToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            this.mailReplyAllToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            this.mailReplyAllToolStripButton.Name = "mailReplyAllToolStripButton";
            this.mailReplyAllToolStripButton.Size = new System.Drawing.Size(29, 24);
            this.mailReplyAllToolStripButton.Text = "Reply All";
            this.mailReplyAllToolStripButton.Click += new System.EventHandler(this.mailReplyAllToolStripButton_Click);
            // 
            // mailForwardToolStripButton
            // 
            this.mailForwardToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            this.mailForwardToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            this.mailForwardToolStripButton.Name = "mailForwardToolStripButton";
            this.mailForwardToolStripButton.Size = new System.Drawing.Size(29, 24);
            this.mailForwardToolStripButton.Text = "Forward";
            this.mailForwardToolStripButton.Click += new System.EventHandler(this.mailForwardToolStripButton_Click);
            // 
            // toolStripSeparator2
            // 
            this.toolStripSeparator2.Name = "toolStripSeparator2";
            this.toolStripSeparator2.Size = new System.Drawing.Size(6, 27);
            // 
            // mailDeleteToolStripButton
            // 
            this.mailDeleteToolStripButton.DisplayStyle = System.Windows.Forms.ToolStripItemDisplayStyle.Image;
            this.mailDeleteToolStripButton.ImageTransparentColor = System.Drawing.Color.Magenta;
            this.mailDeleteToolStripButton.Name = "mailDeleteToolStripButton";
            this.mailDeleteToolStripButton.Size = new System.Drawing.Size(29, 24);
            this.mailDeleteToolStripButton.Text = "Delete";
            this.mailDeleteToolStripButton.Click += new System.EventHandler(this.mailDeleteToolStripButton_Click);
            // 
            // mailTransferStatusPanel
            // 
            this.mailTransferStatusPanel.BackColor = System.Drawing.Color.Silver;
            this.mailTransferStatusPanel.Controls.Add(this.mailTransferStatusLabel);
            this.mailTransferStatusPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.mailTransferStatusPanel.Location = new System.Drawing.Point(0, 621);
            this.mailTransferStatusPanel.Margin = new System.Windows.Forms.Padding(4);
            this.mailTransferStatusPanel.Name = "mailTransferStatusPanel";
            this.mailTransferStatusPanel.Size = new System.Drawing.Size(669, 37);
            this.mailTransferStatusPanel.TabIndex = 8;
            this.mailTransferStatusPanel.Visible = false;
            // 
            // mailTransferStatusLabel
            // 
            this.mailTransferStatusLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.mailTransferStatusLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mailTransferStatusLabel.Location = new System.Drawing.Point(4, 6);
            this.mailTransferStatusLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.mailTransferStatusLabel.Name = "mailTransferStatusLabel";
            this.mailTransferStatusLabel.Size = new System.Drawing.Size(658, 25);
            this.mailTransferStatusLabel.TabIndex = 1;
            this.mailTransferStatusLabel.Text = "Disconnected";
            // 
            // mailTopPanel
            // 
            this.mailTopPanel.BackColor = System.Drawing.Color.Silver;
            this.mailTopPanel.Controls.Add(this.mailInternetButton);
            this.mailTopPanel.Controls.Add(this.newMailButton);
            this.mailTopPanel.Controls.Add(this.mailConnectButton);
            this.mailTopPanel.Controls.Add(this.mailMenuPictureBox);
            this.mailTopPanel.Controls.Add(this.mailTitleLabel);
            this.mailTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.mailTopPanel.Location = new System.Drawing.Point(0, 0);
            this.mailTopPanel.Margin = new System.Windows.Forms.Padding(4);
            this.mailTopPanel.Name = "mailTopPanel";
            this.mailTopPanel.Size = new System.Drawing.Size(669, 37);
            this.mailTopPanel.TabIndex = 2;
            // 
            // mailInternetButton
            // 
            this.mailInternetButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.mailInternetButton.Location = new System.Drawing.Point(418, 4);
            this.mailInternetButton.Margin = new System.Windows.Forms.Padding(4);
            this.mailInternetButton.Name = "mailInternetButton";
            this.mailInternetButton.Size = new System.Drawing.Size(100, 28);
            this.mailInternetButton.TabIndex = 7;
            this.mailInternetButton.Text = "&Internet";
            this.mailInternetButton.UseVisualStyleBackColor = true;
            this.mailInternetButton.Click += new System.EventHandler(this.mailInternetButton_Click);
            // 
            // newMailButton
            // 
            this.newMailButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.newMailButton.Location = new System.Drawing.Point(310, 4);
            this.newMailButton.Margin = new System.Windows.Forms.Padding(4);
            this.newMailButton.Name = "newMailButton";
            this.newMailButton.Size = new System.Drawing.Size(100, 28);
            this.newMailButton.TabIndex = 6;
            this.newMailButton.Text = "&New Mail";
            this.newMailButton.UseVisualStyleBackColor = true;
            this.newMailButton.Click += new System.EventHandler(this.newMailButton_Click);
            // 
            // mailConnectButton
            // 
            this.mailConnectButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.mailConnectButton.Enabled = false;
            this.mailConnectButton.Location = new System.Drawing.Point(526, 4);
            this.mailConnectButton.Margin = new System.Windows.Forms.Padding(4);
            this.mailConnectButton.Name = "mailConnectButton";
            this.mailConnectButton.Size = new System.Drawing.Size(100, 28);
            this.mailConnectButton.TabIndex = 5;
            this.mailConnectButton.Text = "&Connect...";
            this.mailConnectButton.UseVisualStyleBackColor = true;
            this.mailConnectButton.Click += new System.EventHandler(this.mailConnectButton_Click);
            // 
            // mailMenuPictureBox
            // 
            this.mailMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.mailMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.mailMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.mailMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.mailMenuPictureBox.Name = "mailMenuPictureBox";
            this.mailMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.mailMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.mailMenuPictureBox.TabIndex = 4;
            this.mailMenuPictureBox.TabStop = false;
            this.mailMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.mailMenuPictureBox_MouseClick);
            // 
            // mailTitleLabel
            // 
            this.mailTitleLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.mailTitleLabel.AutoSize = true;
            this.mailTitleLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mailTitleLabel.Location = new System.Drawing.Point(4, 6);
            this.mailTitleLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.mailTitleLabel.Name = "mailTitleLabel";
            this.mailTitleLabel.Size = new System.Drawing.Size(48, 25);
            this.mailTitleLabel.TabIndex = 1;
            this.mailTitleLabel.Text = "Mail";
            // 
            // mailTabContextMenuStrip
            // 
            this.mailTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mailTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.showPreviewToolStripMenuItem,
            this.showTrafficToolStripMenuItem,
            this.toolStripMenuItem16,
            this.backupMailToolStripMenuItem,
            this.restoreMailToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.mailTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.mailTabContextMenuStrip.Size = new System.Drawing.Size(171, 136);
            // 
            // showPreviewToolStripMenuItem
            // 
            this.showPreviewToolStripMenuItem.CheckOnClick = true;
            this.showPreviewToolStripMenuItem.Name = "showPreviewToolStripMenuItem";
            this.showPreviewToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            this.showPreviewToolStripMenuItem.Text = "&Show Preview";
            this.showPreviewToolStripMenuItem.Click += new System.EventHandler(this.showPreviewToolStripMenuItem_Click);
            // 
            // showTrafficToolStripMenuItem
            // 
            this.showTrafficToolStripMenuItem.Name = "showTrafficToolStripMenuItem";
            this.showTrafficToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            this.showTrafficToolStripMenuItem.Text = "Show Traffic...";
            this.showTrafficToolStripMenuItem.Click += new System.EventHandler(this.showTrafficToolStripMenuItem_Click);
            // 
            // toolStripMenuItem16
            // 
            this.toolStripMenuItem16.Name = "toolStripMenuItem16";
            this.toolStripMenuItem16.Size = new System.Drawing.Size(167, 6);
            // 
            // backupMailToolStripMenuItem
            // 
            this.backupMailToolStripMenuItem.Name = "backupMailToolStripMenuItem";
            this.backupMailToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            this.backupMailToolStripMenuItem.Text = "&Backup Mail...";
            this.backupMailToolStripMenuItem.Click += new System.EventHandler(this.backupMailToolStripMenuItem_Click);
            // 
            // restoreMailToolStripMenuItem
            // 
            this.restoreMailToolStripMenuItem.Name = "restoreMailToolStripMenuItem";
            this.restoreMailToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            this.restoreMailToolStripMenuItem.Text = "&Restore Mail...";
            this.restoreMailToolStripMenuItem.Click += new System.EventHandler(this.restoreMailToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(167, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(170, 24);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // backupMailSaveFileDialog
            // 
            this.backupMailSaveFileDialog.DefaultExt = "htmails";
            this.backupMailSaveFileDialog.FileName = "Backup";
            this.backupMailSaveFileDialog.Filter = "Mails (*.htmails)|*.htmails";
            this.backupMailSaveFileDialog.Title = "Backup Mail";
            // 
            // restoreMailOpenFileDialog
            // 
            this.restoreMailOpenFileDialog.DefaultExt = "htmails";
            this.restoreMailOpenFileDialog.FileName = "mails";
            this.restoreMailOpenFileDialog.Filter = "Mails (*.htmails)|*.htmails";
            this.restoreMailOpenFileDialog.Title = "Restore Mail";
            // 
            // MailTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.mailboxHorizontalSplitContainer);
            this.Controls.Add(this.mailTransferStatusPanel);
            this.Controls.Add(this.mailTopPanel);
            this.Name = "MailTabUserControl";
            this.Size = new System.Drawing.Size(669, 658);
            this.mailboxHorizontalSplitContainer.Panel1.ResumeLayout(false);
            this.mailboxHorizontalSplitContainer.Panel2.ResumeLayout(false);
            this.mailboxHorizontalSplitContainer.Panel2.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailboxHorizontalSplitContainer)).EndInit();
            this.mailboxHorizontalSplitContainer.ResumeLayout(false);
            this.mailboxVerticalSplitContainer.Panel1.ResumeLayout(false);
            this.mailboxVerticalSplitContainer.Panel2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.mailboxVerticalSplitContainer)).EndInit();
            this.mailboxVerticalSplitContainer.ResumeLayout(false);
            this.mailContextMenuStrip.ResumeLayout(false);
            this.mailToolStrip.ResumeLayout(false);
            this.mailToolStrip.PerformLayout();
            this.mailTransferStatusPanel.ResumeLayout(false);
            this.mailTopPanel.ResumeLayout(false);
            this.mailTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mailMenuPictureBox)).EndInit();
            this.mailTabContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);

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
