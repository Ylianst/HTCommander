namespace HTCommander.Dialogs
{
    partial class RadioForm
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

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioForm));
            mainMenuStrip = new System.Windows.Forms.MenuStrip();
            fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            closeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            settingsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            dualWatchToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            scanToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            regionToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            gPSEnabledToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            viewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            allChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            radioPanelControl = new HTCommander.RadioControls.RadioPanelControl();
            toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            exportChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            importChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            importChannelsFileDialog = new System.Windows.Forms.OpenFileDialog();
            exportChannelsFileDialog = new System.Windows.Forms.SaveFileDialog();
            mainMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // mainMenuStrip
            // 
            mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { fileToolStripMenuItem, settingsToolStripMenuItem, viewToolStripMenuItem });
            mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            mainMenuStrip.Name = "mainMenuStrip";
            mainMenuStrip.Size = new System.Drawing.Size(366, 28);
            mainMenuStrip.TabIndex = 0;
            mainMenuStrip.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { closeToolStripMenuItem });
            fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            fileToolStripMenuItem.Size = new System.Drawing.Size(46, 24);
            fileToolStripMenuItem.Text = "&File";
            // 
            // closeToolStripMenuItem
            // 
            closeToolStripMenuItem.Name = "closeToolStripMenuItem";
            closeToolStripMenuItem.Size = new System.Drawing.Size(128, 26);
            closeToolStripMenuItem.Text = "&Close";
            closeToolStripMenuItem.Click += closeToolStripMenuItem_Click;
            // 
            // settingsToolStripMenuItem
            // 
            settingsToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { dualWatchToolStripMenuItem, scanToolStripMenuItem, regionToolStripMenuItem, gPSEnabledToolStripMenuItem, toolStripMenuItem1, exportChannelsToolStripMenuItem, importChannelsToolStripMenuItem });
            settingsToolStripMenuItem.Name = "settingsToolStripMenuItem";
            settingsToolStripMenuItem.Size = new System.Drawing.Size(76, 24);
            settingsToolStripMenuItem.Text = "&Settings";
            settingsToolStripMenuItem.DropDownOpening += settingsToolStripMenuItem_DropDownOpening;
            // 
            // dualWatchToolStripMenuItem
            // 
            dualWatchToolStripMenuItem.Enabled = false;
            dualWatchToolStripMenuItem.Name = "dualWatchToolStripMenuItem";
            dualWatchToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            dualWatchToolStripMenuItem.Text = "&Dual-Watch";
            dualWatchToolStripMenuItem.Click += dualWatchToolStripMenuItem_Click;
            // 
            // scanToolStripMenuItem
            // 
            scanToolStripMenuItem.Enabled = false;
            scanToolStripMenuItem.Name = "scanToolStripMenuItem";
            scanToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            scanToolStripMenuItem.Text = "&Scan";
            scanToolStripMenuItem.Click += scanToolStripMenuItem_Click;
            // 
            // regionToolStripMenuItem
            // 
            regionToolStripMenuItem.Enabled = false;
            regionToolStripMenuItem.Name = "regionToolStripMenuItem";
            regionToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            regionToolStripMenuItem.Text = "&Regions";
            // 
            // gPSEnabledToolStripMenuItem
            // 
            gPSEnabledToolStripMenuItem.Name = "gPSEnabledToolStripMenuItem";
            gPSEnabledToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            gPSEnabledToolStripMenuItem.Text = "&GPS Enabled";
            gPSEnabledToolStripMenuItem.Click += gPSEnabledToolStripMenuItem_Click;
            // 
            // viewToolStripMenuItem
            // 
            viewToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { allChannelsToolStripMenuItem });
            viewToolStripMenuItem.Name = "viewToolStripMenuItem";
            viewToolStripMenuItem.Size = new System.Drawing.Size(55, 24);
            viewToolStripMenuItem.Text = "&View";
            viewToolStripMenuItem.DropDownOpening += viewToolStripMenuItem_DropDownOpening;
            // 
            // allChannelsToolStripMenuItem
            // 
            allChannelsToolStripMenuItem.Name = "allChannelsToolStripMenuItem";
            allChannelsToolStripMenuItem.Size = new System.Drawing.Size(173, 26);
            allChannelsToolStripMenuItem.Text = "&All Channels";
            allChannelsToolStripMenuItem.Click += allChannelsToolStripMenuItem_Click;
            // 
            // radioPanelControl
            // 
            radioPanelControl.AllowDrop = true;
            radioPanelControl.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            radioPanelControl.DeviceId = -1;
            radioPanelControl.Dock = System.Windows.Forms.DockStyle.Fill;
            radioPanelControl.Location = new System.Drawing.Point(0, 28);
            radioPanelControl.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            radioPanelControl.Name = "radioPanelControl";
            radioPanelControl.ShowAllChannels = false;
            radioPanelControl.Size = new System.Drawing.Size(366, 765);
            radioPanelControl.TabIndex = 1;
            // 
            // toolStripMenuItem1
            // 
            toolStripMenuItem1.Name = "toolStripMenuItem1";
            toolStripMenuItem1.Size = new System.Drawing.Size(221, 6);
            // 
            // exportChannelsToolStripMenuItem
            // 
            exportChannelsToolStripMenuItem.Name = "exportChannelsToolStripMenuItem";
            exportChannelsToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            exportChannelsToolStripMenuItem.Text = "&Export Channels...";
            exportChannelsToolStripMenuItem.Click += exportChannelsToolStripMenuItem_Click;
            // 
            // importChannelsToolStripMenuItem
            // 
            importChannelsToolStripMenuItem.Name = "importChannelsToolStripMenuItem";
            importChannelsToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            importChannelsToolStripMenuItem.Text = "&Import Channels...";
            importChannelsToolStripMenuItem.Click += importChannelsToolStripMenuItem_Click;
            // 
            // importChannelsFileDialog
            // 
            importChannelsFileDialog.Filter = "Channel Files|*.csv";
            importChannelsFileDialog.Title = "Import Channels";
            // 
            // exportChannelsFileDialog
            // 
            exportChannelsFileDialog.Filter = "Native Channel File|*.csv|CHIRP Channel File|*.csv";
            exportChannelsFileDialog.Title = "Export Channels";
            // 
            // RadioForm
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(366, 793);
            Controls.Add(radioPanelControl);
            Controls.Add(mainMenuStrip);
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            MainMenuStrip = mainMenuStrip;
            MaximizeBox = false;
            MaximumSize = new System.Drawing.Size(384, 1000);
            MinimumSize = new System.Drawing.Size(384, 720);
            Name = "RadioForm";
            Text = "Radio";
            mainMenuStrip.ResumeLayout(false);
            mainMenuStrip.PerformLayout();
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private System.Windows.Forms.MenuStrip mainMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem closeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem settingsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem dualWatchToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem scanToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem regionToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem gPSEnabledToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem viewToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem allChannelsToolStripMenuItem;
        private RadioControls.RadioPanelControl radioPanelControl;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem exportChannelsToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem importChannelsToolStripMenuItem;
        private System.Windows.Forms.OpenFileDialog importChannelsFileDialog;
        private System.Windows.Forms.SaveFileDialog exportChannelsFileDialog;
    }
}
