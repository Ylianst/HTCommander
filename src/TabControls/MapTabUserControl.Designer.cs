namespace HTCommander.Controls
{
    partial class MapTabUserControl
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
            this.mapTopPanel = new System.Windows.Forms.Panel();
            this.mapMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.centerToGpsButton = new System.Windows.Forms.Button();
            this.mapTopLabel = new System.Windows.Forms.Label();
            this.mapZoomOutButton = new System.Windows.Forms.Button();
            this.mapZoomInbutton = new System.Windows.Forms.Button();
            this.mapControl = new GMap.NET.WindowsForms.GMapControl();
            this.mapTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.offlineModeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.cacheAreaToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem8 = new System.Windows.Forms.ToolStripSeparator();
            this.centerToGPSToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem9 = new System.Windows.Forms.ToolStripSeparator();
            this.showTracksToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.showMarkersToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.allToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.last30MinutesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.lastHourToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.last6HoursToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.last12HoursToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.last24HoursToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.largeMarkersToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.downloadMapPanel = new System.Windows.Forms.Panel();
            this.cancelMapDownloadButton = new System.Windows.Forms.Button();
            this.downloadMapLabel = new System.Windows.Forms.Label();
            this.mapTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mapMenuPictureBox)).BeginInit();
            this.mapTabContextMenuStrip.SuspendLayout();
            this.downloadMapPanel.SuspendLayout();
            this.SuspendLayout();
            // 
            // mapTopPanel
            // 
            this.mapTopPanel.BackColor = System.Drawing.Color.Silver;
            this.mapTopPanel.Controls.Add(this.mapMenuPictureBox);
            this.mapTopPanel.Controls.Add(this.centerToGpsButton);
            this.mapTopPanel.Controls.Add(this.mapTopLabel);
            this.mapTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.mapTopPanel.Location = new System.Drawing.Point(0, 0);
            this.mapTopPanel.Margin = new System.Windows.Forms.Padding(4);
            this.mapTopPanel.Name = "mapTopPanel";
            this.mapTopPanel.Size = new System.Drawing.Size(669, 37);
            this.mapTopPanel.TabIndex = 1;
            // 
            // mapMenuPictureBox
            // 
            this.mapMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.mapMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.mapMenuPictureBox.Location = new System.Drawing.Point(637, 6);
            this.mapMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.mapMenuPictureBox.Name = "mapMenuPictureBox";
            this.mapMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.mapMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.mapMenuPictureBox.TabIndex = 5;
            this.mapMenuPictureBox.TabStop = false;
            this.mapMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.mapMenuPictureBox_MouseClick);
            // 
            // centerToGpsButton
            // 
            this.centerToGpsButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.centerToGpsButton.Enabled = false;
            this.centerToGpsButton.Location = new System.Drawing.Point(493, 5);
            this.centerToGpsButton.Margin = new System.Windows.Forms.Padding(4);
            this.centerToGpsButton.Name = "centerToGpsButton";
            this.centerToGpsButton.Size = new System.Drawing.Size(136, 28);
            this.centerToGpsButton.TabIndex = 2;
            this.centerToGpsButton.Text = "Center to GPS";
            this.centerToGpsButton.UseVisualStyleBackColor = true;
            this.centerToGpsButton.Click += new System.EventHandler(this.centerToGpsButton_Click);
            // 
            // mapTopLabel
            // 
            this.mapTopLabel.AutoSize = true;
            this.mapTopLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mapTopLabel.Location = new System.Drawing.Point(4, 6);
            this.mapTopLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.mapTopLabel.Name = "mapTopLabel";
            this.mapTopLabel.Size = new System.Drawing.Size(51, 25);
            this.mapTopLabel.TabIndex = 0;
            this.mapTopLabel.Text = "Map";
            // 
            // mapZoomOutButton
            // 
            this.mapZoomOutButton.Location = new System.Drawing.Point(11, 81);
            this.mapZoomOutButton.Margin = new System.Windows.Forms.Padding(4);
            this.mapZoomOutButton.Name = "mapZoomOutButton";
            this.mapZoomOutButton.Size = new System.Drawing.Size(35, 28);
            this.mapZoomOutButton.TabIndex = 4;
            this.mapZoomOutButton.Text = "-";
            this.mapZoomOutButton.UseVisualStyleBackColor = true;
            this.mapZoomOutButton.Click += new System.EventHandler(this.mapZoomOutButton_Click);
            // 
            // mapZoomInbutton
            // 
            this.mapZoomInbutton.Location = new System.Drawing.Point(11, 45);
            this.mapZoomInbutton.Margin = new System.Windows.Forms.Padding(4);
            this.mapZoomInbutton.Name = "mapZoomInbutton";
            this.mapZoomInbutton.Size = new System.Drawing.Size(35, 28);
            this.mapZoomInbutton.TabIndex = 3;
            this.mapZoomInbutton.Text = "+";
            this.mapZoomInbutton.UseVisualStyleBackColor = true;
            this.mapZoomInbutton.Click += new System.EventHandler(this.mapZoomInbutton_Click);
            // 
            // mapControl
            // 
            this.mapControl.Bearing = 0F;
            this.mapControl.CanDragMap = true;
            this.mapControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mapControl.EmptyTileColor = System.Drawing.Color.Navy;
            this.mapControl.GrayScaleMode = false;
            this.mapControl.HelperLineOption = GMap.NET.WindowsForms.HelperLineOptions.DontShow;
            this.mapControl.LevelsKeepInMemory = 5;
            this.mapControl.Location = new System.Drawing.Point(0, 37);
            this.mapControl.Margin = new System.Windows.Forms.Padding(4);
            this.mapControl.MarkersEnabled = true;
            this.mapControl.MaxZoom = 20;
            this.mapControl.MinZoom = 3;
            this.mapControl.MouseWheelZoomEnabled = true;
            this.mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            this.mapControl.Name = "mapControl";
            this.mapControl.NegativeMode = false;
            this.mapControl.PolygonsEnabled = true;
            this.mapControl.RetryLoadTile = 0;
            this.mapControl.RoutesEnabled = true;
            this.mapControl.ScaleMode = GMap.NET.WindowsForms.ScaleModes.Integer;
            this.mapControl.SelectedAreaFillColor = System.Drawing.Color.FromArgb(((int)(((byte)(33)))), ((int)(((byte)(65)))), ((int)(((byte)(105)))), ((int)(((byte)(225)))));
            this.mapControl.ShowTileGridLines = false;
            this.mapControl.Size = new System.Drawing.Size(669, 549);
            this.mapControl.TabIndex = 2;
            this.mapControl.Zoom = 3D;
            this.mapControl.OnMarkerDoubleClick += new GMap.NET.WindowsForms.MarkerDoubleClick(this.mapControl_OnMarkerDoubleClick);
            this.mapControl.OnPositionChanged += new GMap.NET.PositionChanged(this.mapControl_OnPositionChanged);
            this.mapControl.OnMapZoomChanged += new GMap.NET.MapZoomChanged(this.mapControl_OnMapZoomChanged);
            this.mapControl.Paint += new System.Windows.Forms.PaintEventHandler(this.mapControl_Paint);
            this.mapControl.MouseDown += new System.Windows.Forms.MouseEventHandler(this.mapControl_MouseDown);
            this.mapControl.MouseMove += new System.Windows.Forms.MouseEventHandler(this.mapControl_MouseMove);
            this.mapControl.MouseUp += new System.Windows.Forms.MouseEventHandler(this.mapControl_MouseUp);
            // 
            // mapTabContextMenuStrip
            // 
            this.mapTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mapTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.offlineModeToolStripMenuItem,
            this.cacheAreaToolStripMenuItem,
            this.toolStripMenuItem8,
            this.centerToGPSToolStripMenuItem,
            this.toolStripMenuItem9,
            this.showTracksToolStripMenuItem,
            this.showMarkersToolStripMenuItem,
            this.largeMarkersToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.mapTabContextMenuStrip.Name = "mapTabContextMenuStrip";
            this.mapTabContextMenuStrip.Size = new System.Drawing.Size(172, 202);
            // 
            // offlineModeToolStripMenuItem
            // 
            this.offlineModeToolStripMenuItem.CheckOnClick = true;
            this.offlineModeToolStripMenuItem.Name = "offlineModeToolStripMenuItem";
            this.offlineModeToolStripMenuItem.Size = new System.Drawing.Size(171, 26);
            this.offlineModeToolStripMenuItem.Text = "Offline Mode";
            this.offlineModeToolStripMenuItem.Click += new System.EventHandler(this.offlineModeToolStripMenuItem_Click);
            // 
            // cacheAreaToolStripMenuItem
            // 
            this.cacheAreaToolStripMenuItem.Name = "cacheAreaToolStripMenuItem";
            this.cacheAreaToolStripMenuItem.Size = new System.Drawing.Size(171, 26);
            this.cacheAreaToolStripMenuItem.Text = "Cache Area...";
            this.cacheAreaToolStripMenuItem.Click += new System.EventHandler(this.cacheAreaToolStripMenuItem_Click);
            // 
            // toolStripMenuItem8
            // 
            this.toolStripMenuItem8.Name = "toolStripMenuItem8";
            this.toolStripMenuItem8.Size = new System.Drawing.Size(168, 6);
            // 
            // centerToGPSToolStripMenuItem
            // 
            this.centerToGPSToolStripMenuItem.Enabled = false;
            this.centerToGPSToolStripMenuItem.Name = "centerToGPSToolStripMenuItem";
            this.centerToGPSToolStripMenuItem.Size = new System.Drawing.Size(171, 26);
            this.centerToGPSToolStripMenuItem.Text = "Center to GPS";
            this.centerToGPSToolStripMenuItem.Click += new System.EventHandler(this.centerToGpsButton_Click);
            // 
            // toolStripMenuItem9
            // 
            this.toolStripMenuItem9.Name = "toolStripMenuItem9";
            this.toolStripMenuItem9.Size = new System.Drawing.Size(168, 6);
            // 
            // showTracksToolStripMenuItem
            // 
            this.showTracksToolStripMenuItem.Checked = true;
            this.showTracksToolStripMenuItem.CheckOnClick = true;
            this.showTracksToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.showTracksToolStripMenuItem.Name = "showTracksToolStripMenuItem";
            this.showTracksToolStripMenuItem.Size = new System.Drawing.Size(171, 26);
            this.showTracksToolStripMenuItem.Text = "Show Tracks";
            this.showTracksToolStripMenuItem.Click += new System.EventHandler(this.showTracksToolStripMenuItem_Click);
            // 
            // showMarkersToolStripMenuItem
            // 
            this.showMarkersToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.allToolStripMenuItem,
            this.last30MinutesToolStripMenuItem,
            this.lastHourToolStripMenuItem,
            this.last6HoursToolStripMenuItem,
            this.last12HoursToolStripMenuItem,
            this.last24HoursToolStripMenuItem});
            this.showMarkersToolStripMenuItem.Name = "showMarkersToolStripMenuItem";
            this.showMarkersToolStripMenuItem.Size = new System.Drawing.Size(171, 26);
            this.showMarkersToolStripMenuItem.Text = "Show Markers";
            // 
            // allToolStripMenuItem
            // 
            this.allToolStripMenuItem.Checked = true;
            this.allToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.allToolStripMenuItem.Name = "allToolStripMenuItem";
            this.allToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            this.allToolStripMenuItem.Tag = "0";
            this.allToolStripMenuItem.Text = "All";
            this.allToolStripMenuItem.Click += new System.EventHandler(this.allToolStripMenuItem_Click);
            // 
            // last30MinutesToolStripMenuItem
            // 
            this.last30MinutesToolStripMenuItem.Name = "last30MinutesToolStripMenuItem";
            this.last30MinutesToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            this.last30MinutesToolStripMenuItem.Tag = "30";
            this.last30MinutesToolStripMenuItem.Text = "Last 30 Minutes";
            this.last30MinutesToolStripMenuItem.Click += new System.EventHandler(this.allToolStripMenuItem_Click);
            // 
            // lastHourToolStripMenuItem
            // 
            this.lastHourToolStripMenuItem.Name = "lastHourToolStripMenuItem";
            this.lastHourToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            this.lastHourToolStripMenuItem.Tag = "60";
            this.lastHourToolStripMenuItem.Text = "Last Hour";
            this.lastHourToolStripMenuItem.Click += new System.EventHandler(this.allToolStripMenuItem_Click);
            // 
            // last6HoursToolStripMenuItem
            // 
            this.last6HoursToolStripMenuItem.Name = "last6HoursToolStripMenuItem";
            this.last6HoursToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            this.last6HoursToolStripMenuItem.Tag = "360";
            this.last6HoursToolStripMenuItem.Text = "Last 6 Hours";
            this.last6HoursToolStripMenuItem.Click += new System.EventHandler(this.allToolStripMenuItem_Click);
            // 
            // last12HoursToolStripMenuItem
            // 
            this.last12HoursToolStripMenuItem.Name = "last12HoursToolStripMenuItem";
            this.last12HoursToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            this.last12HoursToolStripMenuItem.Tag = "720";
            this.last12HoursToolStripMenuItem.Text = "Last 12 Hours";
            this.last12HoursToolStripMenuItem.Click += new System.EventHandler(this.allToolStripMenuItem_Click);
            // 
            // last24HoursToolStripMenuItem
            // 
            this.last24HoursToolStripMenuItem.Name = "last24HoursToolStripMenuItem";
            this.last24HoursToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            this.last24HoursToolStripMenuItem.Tag = "1440";
            this.last24HoursToolStripMenuItem.Text = "Last 24 Hours";
            this.last24HoursToolStripMenuItem.Click += new System.EventHandler(this.allToolStripMenuItem_Click);
            // 
            // largeMarkersToolStripMenuItem
            // 
            this.largeMarkersToolStripMenuItem.Checked = true;
            this.largeMarkersToolStripMenuItem.CheckOnClick = true;
            this.largeMarkersToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.largeMarkersToolStripMenuItem.Name = "largeMarkersToolStripMenuItem";
            this.largeMarkersToolStripMenuItem.Size = new System.Drawing.Size(171, 26);
            this.largeMarkersToolStripMenuItem.Text = "Large Markers";
            this.largeMarkersToolStripMenuItem.Click += new System.EventHandler(this.largeMarkersToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(168, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(171, 26);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // downloadMapPanel
            // 
            this.downloadMapPanel.BackColor = System.Drawing.Color.MistyRose;
            this.downloadMapPanel.Controls.Add(this.cancelMapDownloadButton);
            this.downloadMapPanel.Controls.Add(this.downloadMapLabel);
            this.downloadMapPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.downloadMapPanel.Location = new System.Drawing.Point(0, 586);
            this.downloadMapPanel.Margin = new System.Windows.Forms.Padding(4);
            this.downloadMapPanel.Name = "downloadMapPanel";
            this.downloadMapPanel.Size = new System.Drawing.Size(669, 37);
            this.downloadMapPanel.TabIndex = 8;
            this.downloadMapPanel.Visible = false;
            // 
            // cancelMapDownloadButton
            // 
            this.cancelMapDownloadButton.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.cancelMapDownloadButton.Location = new System.Drawing.Point(565, 5);
            this.cancelMapDownloadButton.Margin = new System.Windows.Forms.Padding(4);
            this.cancelMapDownloadButton.Name = "cancelMapDownloadButton";
            this.cancelMapDownloadButton.Size = new System.Drawing.Size(100, 28);
            this.cancelMapDownloadButton.TabIndex = 8;
            this.cancelMapDownloadButton.Text = "Cancel";
            this.cancelMapDownloadButton.UseVisualStyleBackColor = true;
            // 
            // downloadMapLabel
            // 
            this.downloadMapLabel.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.downloadMapLabel.AutoSize = true;
            this.downloadMapLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.downloadMapLabel.Location = new System.Drawing.Point(7, 9);
            this.downloadMapLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.downloadMapLabel.Name = "downloadMapLabel";
            this.downloadMapLabel.Size = new System.Drawing.Size(154, 20);
            this.downloadMapLabel.TabIndex = 7;
            this.downloadMapLabel.Text = "Downloading map...";
            // 
            // MapTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.mapZoomOutButton);
            this.Controls.Add(this.mapZoomInbutton);
            this.Controls.Add(this.mapControl);
            this.Controls.Add(this.downloadMapPanel);
            this.Controls.Add(this.mapTopPanel);
            this.Name = "MapTabUserControl";
            this.Size = new System.Drawing.Size(669, 623);
            this.mapTopPanel.ResumeLayout(false);
            this.mapTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.mapMenuPictureBox)).EndInit();
            this.mapTabContextMenuStrip.ResumeLayout(false);
            this.downloadMapPanel.ResumeLayout(false);
            this.downloadMapPanel.PerformLayout();
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Panel mapTopPanel;
        private System.Windows.Forms.PictureBox mapMenuPictureBox;
        private System.Windows.Forms.Button mapZoomOutButton;
        private System.Windows.Forms.Button mapZoomInbutton;
        private System.Windows.Forms.Button centerToGpsButton;
        private System.Windows.Forms.Label mapTopLabel;
        private GMap.NET.WindowsForms.GMapControl mapControl;
        private System.Windows.Forms.ContextMenuStrip mapTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem offlineModeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem cacheAreaToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem8;
        private System.Windows.Forms.ToolStripMenuItem centerToGPSToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem9;
        private System.Windows.Forms.ToolStripMenuItem showTracksToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem showMarkersToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem allToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem last30MinutesToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem lastHourToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem last6HoursToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem last12HoursToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem last24HoursToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem largeMarkersToolStripMenuItem;
        private System.Windows.Forms.Panel downloadMapPanel;
        private System.Windows.Forms.Button cancelMapDownloadButton;
        private System.Windows.Forms.Label downloadMapLabel;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
    }
}
