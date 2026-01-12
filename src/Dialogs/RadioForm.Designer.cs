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
            viewToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            allChannelsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            radioPanelControl = new HTCommander.RadioControls.RadioPanelControl();
            mainMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // mainMenuStrip
            // 
            mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { fileToolStripMenuItem, viewToolStripMenuItem });
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
        private System.Windows.Forms.ToolStripMenuItem viewToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem allChannelsToolStripMenuItem;
        private RadioControls.RadioPanelControl radioPanelControl;
    }
}
