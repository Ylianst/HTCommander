/*
Copyright 2025 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

namespace HTCommander
{
    partial class RadioAudioClipsForm
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.ContextMenuStrip clipsContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem playMenuItem;
        private System.Windows.Forms.ToolStripMenuItem playRadioMenuItem;
        private System.Windows.Forms.ToolStripMenuItem renameMenuItem;
        private System.Windows.Forms.ToolStripMenuItem deleteMenuItem;
        private System.Windows.Forms.ToolStripMenuItem duplicateMenuItem;
        private System.Windows.Forms.ToolStripMenuItem boostVolumeMenuItem;
        private System.Windows.Forms.ToolStripMenuItem actionsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem recordToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem stopToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem playToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem transmitToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem renameToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem deleteToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem duplicateToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem boostVolumeToolStripMenuItem;

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

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioAudioClipsForm));
            this.topPanel = new System.Windows.Forms.Panel();
            this.playRadioButton = new System.Windows.Forms.Button();
            this.deleteButton = new System.Windows.Forms.Button();
            this.renameButton = new System.Windows.Forms.Button();
            this.playButton = new System.Windows.Forms.Button();
            this.stopButton = new System.Windows.Forms.Button();
            this.recordButton = new System.Windows.Forms.Button();
            this.clipsListView = new System.Windows.Forms.ListView();
            this.nameColumn = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.durationColumn = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.clipsContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.playMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.playRadioMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.duplicateMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.boostVolumeMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.renameMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.deleteMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.mainStatusStrip = new System.Windows.Forms.StatusStrip();
            this.mainToolStripStatusLabel = new System.Windows.Forms.ToolStripStatusLabel();
            this.mainMenuStrip = new System.Windows.Forms.MenuStrip();
            this.fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.openClipsFolderToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            this.closeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.actionsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.recordToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.stopToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.playToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.transmitToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.duplicateToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.boostVolumeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.renameToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.deleteToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.settingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.confirmTransmitToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.doubleClickTransmitToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.topPanel.SuspendLayout();
            this.clipsContextMenuStrip.SuspendLayout();
            this.mainStatusStrip.SuspendLayout();
            this.mainMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // topPanel
            // 
            this.topPanel.Controls.Add(this.playRadioButton);
            this.topPanel.Controls.Add(this.deleteButton);
            this.topPanel.Controls.Add(this.renameButton);
            this.topPanel.Controls.Add(this.playButton);
            this.topPanel.Controls.Add(this.stopButton);
            this.topPanel.Controls.Add(this.recordButton);
            this.topPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.topPanel.Location = new System.Drawing.Point(0, 28);
            this.topPanel.Margin = new System.Windows.Forms.Padding(4);
            this.topPanel.Name = "topPanel";
            this.topPanel.Size = new System.Drawing.Size(692, 38);
            this.topPanel.TabIndex = 0;
            // 
            // playRadioButton
            // 
            this.playRadioButton.BackColor = System.Drawing.Color.Wheat;
            this.playRadioButton.Dock = System.Windows.Forms.DockStyle.Left;
            this.playRadioButton.Enabled = false;
            this.playRadioButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.playRadioButton.ForeColor = System.Drawing.SystemColors.ControlText;
            this.playRadioButton.Location = new System.Drawing.Point(575, 0);
            this.playRadioButton.Margin = new System.Windows.Forms.Padding(4);
            this.playRadioButton.Name = "playRadioButton";
            this.playRadioButton.Size = new System.Drawing.Size(115, 38);
            this.playRadioButton.TabIndex = 3;
            this.playRadioButton.Text = "📻 Transmit";
            this.playRadioButton.UseVisualStyleBackColor = false;
            this.playRadioButton.Click += new System.EventHandler(this.playRadioButton_Click);
            // 
            // deleteButton
            // 
            this.deleteButton.Dock = System.Windows.Forms.DockStyle.Left;
            this.deleteButton.Enabled = false;
            this.deleteButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.deleteButton.Location = new System.Drawing.Point(460, 0);
            this.deleteButton.Margin = new System.Windows.Forms.Padding(4);
            this.deleteButton.Name = "deleteButton";
            this.deleteButton.Size = new System.Drawing.Size(115, 38);
            this.deleteButton.TabIndex = 5;
            this.deleteButton.Text = "🗑 Delete";
            this.deleteButton.UseVisualStyleBackColor = true;
            this.deleteButton.Click += new System.EventHandler(this.deleteButton_Click);
            // 
            // renameButton
            // 
            this.renameButton.Dock = System.Windows.Forms.DockStyle.Left;
            this.renameButton.Enabled = false;
            this.renameButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.renameButton.Location = new System.Drawing.Point(345, 0);
            this.renameButton.Margin = new System.Windows.Forms.Padding(4);
            this.renameButton.Name = "renameButton";
            this.renameButton.Size = new System.Drawing.Size(115, 38);
            this.renameButton.TabIndex = 4;
            this.renameButton.Text = "✏ Rename";
            this.renameButton.UseVisualStyleBackColor = true;
            this.renameButton.Click += new System.EventHandler(this.renameButton_Click);
            // 
            // playButton
            // 
            this.playButton.Dock = System.Windows.Forms.DockStyle.Left;
            this.playButton.Enabled = false;
            this.playButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.playButton.Location = new System.Drawing.Point(230, 0);
            this.playButton.Margin = new System.Windows.Forms.Padding(4);
            this.playButton.Name = "playButton";
            this.playButton.Size = new System.Drawing.Size(115, 38);
            this.playButton.TabIndex = 2;
            this.playButton.Text = "▶ Play";
            this.playButton.UseVisualStyleBackColor = true;
            this.playButton.Click += new System.EventHandler(this.playButton_Click);
            // 
            // stopButton
            // 
            this.stopButton.Dock = System.Windows.Forms.DockStyle.Left;
            this.stopButton.Enabled = false;
            this.stopButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.stopButton.Location = new System.Drawing.Point(115, 0);
            this.stopButton.Margin = new System.Windows.Forms.Padding(4);
            this.stopButton.Name = "stopButton";
            this.stopButton.Size = new System.Drawing.Size(115, 38);
            this.stopButton.TabIndex = 1;
            this.stopButton.Text = "⬛ Stop";
            this.stopButton.UseVisualStyleBackColor = true;
            this.stopButton.Click += new System.EventHandler(this.stopButton_Click);
            // 
            // recordButton
            // 
            this.recordButton.Dock = System.Windows.Forms.DockStyle.Left;
            this.recordButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 9F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.recordButton.Location = new System.Drawing.Point(0, 0);
            this.recordButton.Margin = new System.Windows.Forms.Padding(4);
            this.recordButton.Name = "recordButton";
            this.recordButton.Size = new System.Drawing.Size(115, 38);
            this.recordButton.TabIndex = 0;
            this.recordButton.Text = "⬤ Record";
            this.recordButton.UseVisualStyleBackColor = true;
            this.recordButton.Click += new System.EventHandler(this.recordButton_Click);
            // 
            // clipsListView
            // 
            this.clipsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.nameColumn,
            this.durationColumn});
            this.clipsListView.ContextMenuStrip = this.clipsContextMenuStrip;
            this.clipsListView.Dock = System.Windows.Forms.DockStyle.Fill;
            this.clipsListView.FullRowSelect = true;
            this.clipsListView.GridLines = true;
            this.clipsListView.HideSelection = false;
            this.clipsListView.Location = new System.Drawing.Point(0, 66);
            this.clipsListView.Margin = new System.Windows.Forms.Padding(4);
            this.clipsListView.Name = "clipsListView";
            this.clipsListView.Size = new System.Drawing.Size(692, 161);
            this.clipsListView.Sorting = System.Windows.Forms.SortOrder.Descending;
            this.clipsListView.TabIndex = 1;
            this.clipsListView.UseCompatibleStateImageBehavior = false;
            this.clipsListView.View = System.Windows.Forms.View.Details;
            this.clipsListView.ColumnClick += new System.Windows.Forms.ColumnClickEventHandler(this.clipsListView_ColumnClick);
            this.clipsListView.SelectedIndexChanged += new System.EventHandler(this.clipsListView_SelectedIndexChanged);
            this.clipsListView.DoubleClick += new System.EventHandler(this.clipsListView_DoubleClick);
            this.clipsListView.KeyDown += new System.Windows.Forms.KeyEventHandler(this.clipsListView_KeyDown);
            // 
            // nameColumn
            // 
            this.nameColumn.Text = "Name";
            this.nameColumn.Width = 49;
            // 
            // durationColumn
            // 
            this.durationColumn.Text = "Duration";
            this.durationColumn.Width = 132;
            // 
            // clipsContextMenuStrip
            // 
            this.clipsContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.clipsContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.playMenuItem,
            this.playRadioMenuItem,
            this.duplicateMenuItem,
            this.boostVolumeMenuItem,
            this.renameMenuItem,
            this.deleteMenuItem});
            this.clipsContextMenuStrip.Name = "clipsContextMenuStrip";
            this.clipsContextMenuStrip.Size = new System.Drawing.Size(171, 148);
            this.clipsContextMenuStrip.Opening += new System.ComponentModel.CancelEventHandler(this.clipsContextMenuStrip_Opening);
            // 
            // playMenuItem
            // 
            this.playMenuItem.Font = new System.Drawing.Font("Segoe UI", 9F, System.Drawing.FontStyle.Bold);
            this.playMenuItem.Name = "playMenuItem";
            this.playMenuItem.Size = new System.Drawing.Size(170, 24);
            this.playMenuItem.Text = "Play";
            this.playMenuItem.Click += new System.EventHandler(this.playButton_Click);
            // 
            // playRadioMenuItem
            // 
            this.playRadioMenuItem.Name = "playRadioMenuItem";
            this.playRadioMenuItem.Size = new System.Drawing.Size(170, 24);
            this.playRadioMenuItem.Text = "Transmit";
            this.playRadioMenuItem.Click += new System.EventHandler(this.playRadioButton_Click);
            // 
            // duplicateMenuItem
            // 
            this.duplicateMenuItem.Name = "duplicateMenuItem";
            this.duplicateMenuItem.Size = new System.Drawing.Size(170, 24);
            this.duplicateMenuItem.Text = "Duplicate";
            this.duplicateMenuItem.Click += new System.EventHandler(this.duplicateMenuItem_Click);
            // 
            // boostVolumeMenuItem
            // 
            this.boostVolumeMenuItem.Name = "boostVolumeMenuItem";
            this.boostVolumeMenuItem.Size = new System.Drawing.Size(170, 24);
            this.boostVolumeMenuItem.Text = "Boost Volume";
            this.boostVolumeMenuItem.Click += new System.EventHandler(this.boostVolumeMenuItem_Click);
            // 
            // renameMenuItem
            // 
            this.renameMenuItem.Name = "renameMenuItem";
            this.renameMenuItem.Size = new System.Drawing.Size(170, 24);
            this.renameMenuItem.Text = "Rename";
            this.renameMenuItem.Click += new System.EventHandler(this.renameButton_Click);
            // 
            // deleteMenuItem
            // 
            this.deleteMenuItem.Name = "deleteMenuItem";
            this.deleteMenuItem.Size = new System.Drawing.Size(170, 24);
            this.deleteMenuItem.Text = "Delete";
            this.deleteMenuItem.Click += new System.EventHandler(this.deleteButton_Click);
            // 
            // mainStatusStrip
            // 
            this.mainStatusStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainStatusStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.mainToolStripStatusLabel});
            this.mainStatusStrip.Location = new System.Drawing.Point(0, 227);
            this.mainStatusStrip.Name = "mainStatusStrip";
            this.mainStatusStrip.Size = new System.Drawing.Size(692, 26);
            this.mainStatusStrip.TabIndex = 3;
            this.mainStatusStrip.Text = "statusStrip1";
            // 
            // mainToolStripStatusLabel
            // 
            this.mainToolStripStatusLabel.Name = "mainToolStripStatusLabel";
            this.mainToolStripStatusLabel.Size = new System.Drawing.Size(50, 20);
            this.mainToolStripStatusLabel.Text = "Ready";
            // 
            // mainMenuStrip
            // 
            this.mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.fileToolStripMenuItem,
            this.actionsToolStripMenuItem,
            this.settingsToolStripMenuItem});
            this.mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            this.mainMenuStrip.Name = "mainMenuStrip";
            this.mainMenuStrip.Size = new System.Drawing.Size(692, 28);
            this.mainMenuStrip.TabIndex = 4;
            this.mainMenuStrip.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            this.fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.openClipsFolderToolStripMenuItem,
            this.toolStripMenuItem1,
            this.closeToolStripMenuItem});
            this.fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            this.fileToolStripMenuItem.Size = new System.Drawing.Size(46, 24);
            this.fileToolStripMenuItem.Text = "&File";
            // 
            // openClipsFolderToolStripMenuItem
            // 
            this.openClipsFolderToolStripMenuItem.Name = "openClipsFolderToolStripMenuItem";
            this.openClipsFolderToolStripMenuItem.Size = new System.Drawing.Size(219, 26);
            this.openClipsFolderToolStripMenuItem.Text = "&Open Clips Folder...";
            this.openClipsFolderToolStripMenuItem.Click += new System.EventHandler(this.openClipsFolderToolStripMenuItem_Click);
            // 
            // toolStripMenuItem1
            // 
            this.toolStripMenuItem1.Name = "toolStripMenuItem1";
            this.toolStripMenuItem1.Size = new System.Drawing.Size(216, 6);
            // 
            // closeToolStripMenuItem
            // 
            this.closeToolStripMenuItem.Name = "closeToolStripMenuItem";
            this.closeToolStripMenuItem.Size = new System.Drawing.Size(219, 26);
            this.closeToolStripMenuItem.Text = "&Close";
            this.closeToolStripMenuItem.Click += new System.EventHandler(this.closeToolStripMenuItem_Click);
            // 
            // actionsToolStripMenuItem
            // 
            this.actionsToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.recordToolStripMenuItem,
            this.stopToolStripMenuItem,
            this.playToolStripMenuItem,
            this.transmitToolStripMenuItem,
            this.duplicateToolStripMenuItem,
            this.boostVolumeToolStripMenuItem,
            this.renameToolStripMenuItem,
            this.deleteToolStripMenuItem});
            this.actionsToolStripMenuItem.Name = "actionsToolStripMenuItem";
            this.actionsToolStripMenuItem.Size = new System.Drawing.Size(72, 24);
            this.actionsToolStripMenuItem.Text = "&Actions";
            // 
            // recordToolStripMenuItem
            // 
            this.recordToolStripMenuItem.Name = "recordToolStripMenuItem";
            this.recordToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.recordToolStripMenuItem.Text = "&Record";
            this.recordToolStripMenuItem.Click += new System.EventHandler(this.recordButton_Click);
            // 
            // stopToolStripMenuItem
            // 
            this.stopToolStripMenuItem.Enabled = false;
            this.stopToolStripMenuItem.Name = "stopToolStripMenuItem";
            this.stopToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.stopToolStripMenuItem.Text = "&Stop";
            this.stopToolStripMenuItem.Click += new System.EventHandler(this.stopButton_Click);
            // 
            // playToolStripMenuItem
            // 
            this.playToolStripMenuItem.Enabled = false;
            this.playToolStripMenuItem.Name = "playToolStripMenuItem";
            this.playToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.playToolStripMenuItem.Text = "&Play";
            this.playToolStripMenuItem.Click += new System.EventHandler(this.playButton_Click);
            // 
            // transmitToolStripMenuItem
            // 
            this.transmitToolStripMenuItem.Enabled = false;
            this.transmitToolStripMenuItem.Name = "transmitToolStripMenuItem";
            this.transmitToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.transmitToolStripMenuItem.Text = "&Transmit";
            this.transmitToolStripMenuItem.Click += new System.EventHandler(this.playRadioButton_Click);
            // 
            // duplicateToolStripMenuItem
            // 
            this.duplicateToolStripMenuItem.Enabled = false;
            this.duplicateToolStripMenuItem.Name = "duplicateToolStripMenuItem";
            this.duplicateToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.duplicateToolStripMenuItem.Text = "D&uplicate";
            this.duplicateToolStripMenuItem.Click += new System.EventHandler(this.duplicateMenuItem_Click);
            // 
            // boostVolumeToolStripMenuItem
            // 
            this.boostVolumeToolStripMenuItem.Enabled = false;
            this.boostVolumeToolStripMenuItem.Name = "boostVolumeToolStripMenuItem";
            this.boostVolumeToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.boostVolumeToolStripMenuItem.Text = "&Boost Volume";
            this.boostVolumeToolStripMenuItem.Click += new System.EventHandler(this.boostVolumeMenuItem_Click);
            // 
            // renameToolStripMenuItem
            // 
            this.renameToolStripMenuItem.Enabled = false;
            this.renameToolStripMenuItem.Name = "renameToolStripMenuItem";
            this.renameToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.renameToolStripMenuItem.Text = "Re&name";
            this.renameToolStripMenuItem.Click += new System.EventHandler(this.renameButton_Click);
            // 
            // deleteToolStripMenuItem
            // 
            this.deleteToolStripMenuItem.Enabled = false;
            this.deleteToolStripMenuItem.Name = "deleteToolStripMenuItem";
            this.deleteToolStripMenuItem.Size = new System.Drawing.Size(184, 26);
            this.deleteToolStripMenuItem.Text = "&Delete";
            this.deleteToolStripMenuItem.Click += new System.EventHandler(this.deleteButton_Click);
            // 
            // settingsToolStripMenuItem
            // 
            this.settingsToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.confirmTransmitToolStripMenuItem,
            this.doubleClickTransmitToolStripMenuItem});
            this.settingsToolStripMenuItem.Name = "settingsToolStripMenuItem";
            this.settingsToolStripMenuItem.Size = new System.Drawing.Size(76, 24);
            this.settingsToolStripMenuItem.Text = "&Settings";
            // 
            // confirmTransmitToolStripMenuItem
            // 
            this.confirmTransmitToolStripMenuItem.Checked = true;
            this.confirmTransmitToolStripMenuItem.CheckOnClick = true;
            this.confirmTransmitToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.confirmTransmitToolStripMenuItem.Name = "confirmTransmitToolStripMenuItem";
            this.confirmTransmitToolStripMenuItem.Size = new System.Drawing.Size(236, 26);
            this.confirmTransmitToolStripMenuItem.Text = "&Confirm Transmit";
            // 
            // doubleClickTransmitToolStripMenuItem
            // 
            this.doubleClickTransmitToolStripMenuItem.CheckOnClick = true;
            this.doubleClickTransmitToolStripMenuItem.Name = "doubleClickTransmitToolStripMenuItem";
            this.doubleClickTransmitToolStripMenuItem.Size = new System.Drawing.Size(236, 26);
            this.doubleClickTransmitToolStripMenuItem.Text = "&Double Click Transmit";
            // 
            // RadioAudioClipsForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(692, 253);
            this.Controls.Add(this.clipsListView);
            this.Controls.Add(this.mainStatusStrip);
            this.Controls.Add(this.topPanel);
            this.Controls.Add(this.mainMenuStrip);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Margin = new System.Windows.Forms.Padding(4);
            this.MinimumSize = new System.Drawing.Size(710, 300);
            this.Name = "RadioAudioClipsForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Audio Clips";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.RadioAudioClipsForm_FormClosing);
            this.Load += new System.EventHandler(this.RadioAudioClipsForm_Load);
            this.topPanel.ResumeLayout(false);
            this.clipsContextMenuStrip.ResumeLayout(false);
            this.mainStatusStrip.ResumeLayout(false);
            this.mainStatusStrip.PerformLayout();
            this.mainMenuStrip.ResumeLayout(false);
            this.mainMenuStrip.PerformLayout();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Panel topPanel;
        private System.Windows.Forms.Button recordButton;
        private System.Windows.Forms.Button stopButton;
        private System.Windows.Forms.Button playButton;
        private System.Windows.Forms.Button playRadioButton;
        private System.Windows.Forms.Button renameButton;
        private System.Windows.Forms.Button deleteButton;
        private System.Windows.Forms.ListView clipsListView;
        private System.Windows.Forms.ColumnHeader nameColumn;
        private System.Windows.Forms.ColumnHeader durationColumn;
        private System.Windows.Forms.StatusStrip mainStatusStrip;
        private System.Windows.Forms.ToolStripStatusLabel mainToolStripStatusLabel;
        private System.Windows.Forms.MenuStrip mainMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem closeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem openClipsFolderToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem settingsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem confirmTransmitToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem doubleClickTransmitToolStripMenuItem;
    }
}
