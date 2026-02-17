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
            if (disposing)
            {
                broker?.Dispose();
                if (components != null)
                {
                    components.Dispose();
                }
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
            mapTopPanel = new System.Windows.Forms.Panel();
            mapMenuPictureBox = new System.Windows.Forms.PictureBox();
            centerToGpsButton = new System.Windows.Forms.Button();
            mapTopLabel = new System.Windows.Forms.Label();
            mapZoomOutButton = new System.Windows.Forms.Button();
            mapZoomInbutton = new System.Windows.Forms.Button();
            mapControl = new GMap.NET.WindowsForms.GMapControl();
            mapTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            offlineModeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            cacheAreaToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem8 = new System.Windows.Forms.ToolStripSeparator();
            centerToGPSToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem9 = new System.Windows.Forms.ToolStripSeparator();
            showTracksToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            showMarkersToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            allToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            last30MinutesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            lastHourToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            last6HoursToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            last12HoursToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            last24HoursToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            largeMarkersToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            downloadMapPanel = new System.Windows.Forms.Panel();
            cancelMapDownloadButton = new System.Windows.Forms.Button();
            downloadMapLabel = new System.Windows.Forms.Label();
            showAirplanesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            mapTopPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)mapMenuPictureBox).BeginInit();
            mapTabContextMenuStrip.SuspendLayout();
            downloadMapPanel.SuspendLayout();
            SuspendLayout();
            // 
            // mapTopPanel
            // 
            mapTopPanel.BackColor = System.Drawing.Color.Silver;
            mapTopPanel.Controls.Add(mapMenuPictureBox);
            mapTopPanel.Controls.Add(centerToGpsButton);
            mapTopPanel.Controls.Add(mapTopLabel);
            mapTopPanel.Dock = System.Windows.Forms.DockStyle.Top;
            mapTopPanel.Location = new System.Drawing.Point(0, 0);
            mapTopPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mapTopPanel.Name = "mapTopPanel";
            mapTopPanel.Size = new System.Drawing.Size(669, 46);
            mapTopPanel.TabIndex = 1;
            // 
            // mapMenuPictureBox
            // 
            mapMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            mapMenuPictureBox.Image = Properties.Resources.MenuIcon;
            mapMenuPictureBox.Location = new System.Drawing.Point(637, 8);
            mapMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mapMenuPictureBox.Name = "mapMenuPictureBox";
            mapMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            mapMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            mapMenuPictureBox.TabIndex = 5;
            mapMenuPictureBox.TabStop = false;
            mapMenuPictureBox.MouseClick += mapMenuPictureBox_MouseClick;
            // 
            // centerToGpsButton
            // 
            centerToGpsButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            centerToGpsButton.Enabled = false;
            centerToGpsButton.Location = new System.Drawing.Point(493, 6);
            centerToGpsButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            centerToGpsButton.Name = "centerToGpsButton";
            centerToGpsButton.Size = new System.Drawing.Size(136, 35);
            centerToGpsButton.TabIndex = 2;
            centerToGpsButton.Text = "Center to GPS";
            centerToGpsButton.UseVisualStyleBackColor = true;
            centerToGpsButton.Click += centerToGpsButton_Click;
            // 
            // mapTopLabel
            // 
            mapTopLabel.AutoSize = true;
            mapTopLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            mapTopLabel.Location = new System.Drawing.Point(4, 8);
            mapTopLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            mapTopLabel.Name = "mapTopLabel";
            mapTopLabel.Size = new System.Drawing.Size(51, 25);
            mapTopLabel.TabIndex = 0;
            mapTopLabel.Text = "Map";
            // 
            // mapZoomOutButton
            // 
            mapZoomOutButton.Location = new System.Drawing.Point(11, 101);
            mapZoomOutButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mapZoomOutButton.Name = "mapZoomOutButton";
            mapZoomOutButton.Size = new System.Drawing.Size(35, 35);
            mapZoomOutButton.TabIndex = 4;
            mapZoomOutButton.Text = "-";
            mapZoomOutButton.UseVisualStyleBackColor = true;
            mapZoomOutButton.Click += mapZoomOutButton_Click;
            // 
            // mapZoomInbutton
            // 
            mapZoomInbutton.Location = new System.Drawing.Point(11, 56);
            mapZoomInbutton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mapZoomInbutton.Name = "mapZoomInbutton";
            mapZoomInbutton.Size = new System.Drawing.Size(35, 35);
            mapZoomInbutton.TabIndex = 3;
            mapZoomInbutton.Text = "+";
            mapZoomInbutton.UseVisualStyleBackColor = true;
            mapZoomInbutton.Click += mapZoomInbutton_Click;
            // 
            // mapControl
            // 
            mapControl.Bearing = 0F;
            mapControl.CanDragMap = true;
            mapControl.Dock = System.Windows.Forms.DockStyle.Fill;
            mapControl.EmptyTileColor = System.Drawing.Color.Navy;
            mapControl.GrayScaleMode = false;
            mapControl.HelperLineOption = GMap.NET.WindowsForms.HelperLineOptions.DontShow;
            mapControl.LevelsKeepInMemory = 5;
            mapControl.Location = new System.Drawing.Point(0, 46);
            mapControl.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mapControl.MarkersEnabled = true;
            mapControl.MaxZoom = 20;
            mapControl.MinZoom = 3;
            mapControl.MouseWheelZoomEnabled = true;
            mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            mapControl.Name = "mapControl";
            mapControl.NegativeMode = false;
            mapControl.PolygonsEnabled = true;
            mapControl.RetryLoadTile = 0;
            mapControl.RoutesEnabled = true;
            mapControl.ScaleMode = GMap.NET.WindowsForms.ScaleModes.Integer;
            mapControl.SelectedAreaFillColor = System.Drawing.Color.FromArgb(33, 65, 105, 225);
            mapControl.ShowTileGridLines = false;
            mapControl.Size = new System.Drawing.Size(669, 356);
            mapControl.TabIndex = 2;
            mapControl.Zoom = 3D;
            mapControl.OnMarkerDoubleClick += mapControl_OnMarkerDoubleClick;
            mapControl.OnPositionChanged += mapControl_OnPositionChanged;
            mapControl.OnMapZoomChanged += mapControl_OnMapZoomChanged;
            mapControl.Paint += mapControl_Paint;
            mapControl.MouseDown += mapControl_MouseDown;
            mapControl.MouseEnter += mapControl_MouseEnter;
            mapControl.MouseMove += mapControl_MouseMove;
            mapControl.MouseUp += mapControl_MouseUp;
            // 
            // mapTabContextMenuStrip
            // 
            mapTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            mapTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { offlineModeToolStripMenuItem, cacheAreaToolStripMenuItem, toolStripMenuItem8, centerToGPSToolStripMenuItem, toolStripMenuItem9, showTracksToolStripMenuItem, showMarkersToolStripMenuItem, showAirplanesToolStripMenuItem, largeMarkersToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            mapTabContextMenuStrip.Name = "mapTabContextMenuStrip";
            mapTabContextMenuStrip.Size = new System.Drawing.Size(211, 258);
            // 
            // offlineModeToolStripMenuItem
            // 
            offlineModeToolStripMenuItem.CheckOnClick = true;
            offlineModeToolStripMenuItem.Name = "offlineModeToolStripMenuItem";
            offlineModeToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            offlineModeToolStripMenuItem.Text = "Offline Mode";
            offlineModeToolStripMenuItem.Click += offlineModeToolStripMenuItem_Click;
            // 
            // cacheAreaToolStripMenuItem
            // 
            cacheAreaToolStripMenuItem.Name = "cacheAreaToolStripMenuItem";
            cacheAreaToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            cacheAreaToolStripMenuItem.Text = "Cache Area...";
            cacheAreaToolStripMenuItem.Click += cacheAreaToolStripMenuItem_Click;
            // 
            // toolStripMenuItem8
            // 
            toolStripMenuItem8.Name = "toolStripMenuItem8";
            toolStripMenuItem8.Size = new System.Drawing.Size(207, 6);
            // 
            // centerToGPSToolStripMenuItem
            // 
            centerToGPSToolStripMenuItem.Enabled = false;
            centerToGPSToolStripMenuItem.Name = "centerToGPSToolStripMenuItem";
            centerToGPSToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            centerToGPSToolStripMenuItem.Text = "Center to GPS";
            centerToGPSToolStripMenuItem.Click += centerToGpsButton_Click;
            // 
            // toolStripMenuItem9
            // 
            toolStripMenuItem9.Name = "toolStripMenuItem9";
            toolStripMenuItem9.Size = new System.Drawing.Size(207, 6);
            // 
            // showTracksToolStripMenuItem
            // 
            showTracksToolStripMenuItem.Checked = true;
            showTracksToolStripMenuItem.CheckOnClick = true;
            showTracksToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            showTracksToolStripMenuItem.Name = "showTracksToolStripMenuItem";
            showTracksToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            showTracksToolStripMenuItem.Text = "Show Tracks";
            showTracksToolStripMenuItem.Click += showTracksToolStripMenuItem_Click;
            // 
            // showMarkersToolStripMenuItem
            // 
            showMarkersToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] { allToolStripMenuItem, last30MinutesToolStripMenuItem, lastHourToolStripMenuItem, last6HoursToolStripMenuItem, last12HoursToolStripMenuItem, last24HoursToolStripMenuItem });
            showMarkersToolStripMenuItem.Name = "showMarkersToolStripMenuItem";
            showMarkersToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            showMarkersToolStripMenuItem.Text = "Show Markers";
            // 
            // allToolStripMenuItem
            // 
            allToolStripMenuItem.Checked = true;
            allToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            allToolStripMenuItem.Name = "allToolStripMenuItem";
            allToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            allToolStripMenuItem.Tag = "0";
            allToolStripMenuItem.Text = "All";
            allToolStripMenuItem.Click += allToolStripMenuItem_Click;
            // 
            // last30MinutesToolStripMenuItem
            // 
            last30MinutesToolStripMenuItem.Name = "last30MinutesToolStripMenuItem";
            last30MinutesToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            last30MinutesToolStripMenuItem.Tag = "30";
            last30MinutesToolStripMenuItem.Text = "Last 30 Minutes";
            last30MinutesToolStripMenuItem.Click += allToolStripMenuItem_Click;
            // 
            // lastHourToolStripMenuItem
            // 
            lastHourToolStripMenuItem.Name = "lastHourToolStripMenuItem";
            lastHourToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            lastHourToolStripMenuItem.Tag = "60";
            lastHourToolStripMenuItem.Text = "Last Hour";
            lastHourToolStripMenuItem.Click += allToolStripMenuItem_Click;
            // 
            // last6HoursToolStripMenuItem
            // 
            last6HoursToolStripMenuItem.Name = "last6HoursToolStripMenuItem";
            last6HoursToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            last6HoursToolStripMenuItem.Tag = "360";
            last6HoursToolStripMenuItem.Text = "Last 6 Hours";
            last6HoursToolStripMenuItem.Click += allToolStripMenuItem_Click;
            // 
            // last12HoursToolStripMenuItem
            // 
            last12HoursToolStripMenuItem.Name = "last12HoursToolStripMenuItem";
            last12HoursToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            last12HoursToolStripMenuItem.Tag = "720";
            last12HoursToolStripMenuItem.Text = "Last 12 Hours";
            last12HoursToolStripMenuItem.Click += allToolStripMenuItem_Click;
            // 
            // last24HoursToolStripMenuItem
            // 
            last24HoursToolStripMenuItem.Name = "last24HoursToolStripMenuItem";
            last24HoursToolStripMenuItem.Size = new System.Drawing.Size(194, 26);
            last24HoursToolStripMenuItem.Tag = "1440";
            last24HoursToolStripMenuItem.Text = "Last 24 Hours";
            last24HoursToolStripMenuItem.Click += allToolStripMenuItem_Click;
            // 
            // largeMarkersToolStripMenuItem
            // 
            largeMarkersToolStripMenuItem.Checked = true;
            largeMarkersToolStripMenuItem.CheckOnClick = true;
            largeMarkersToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            largeMarkersToolStripMenuItem.Name = "largeMarkersToolStripMenuItem";
            largeMarkersToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            largeMarkersToolStripMenuItem.Text = "Large Markers";
            largeMarkersToolStripMenuItem.Click += largeMarkersToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(207, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // downloadMapPanel
            // 
            downloadMapPanel.BackColor = System.Drawing.Color.MistyRose;
            downloadMapPanel.Controls.Add(cancelMapDownloadButton);
            downloadMapPanel.Controls.Add(downloadMapLabel);
            downloadMapPanel.Dock = System.Windows.Forms.DockStyle.Bottom;
            downloadMapPanel.Location = new System.Drawing.Point(0, 402);
            downloadMapPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            downloadMapPanel.Name = "downloadMapPanel";
            downloadMapPanel.Size = new System.Drawing.Size(669, 46);
            downloadMapPanel.TabIndex = 8;
            downloadMapPanel.Visible = false;
            // 
            // cancelMapDownloadButton
            // 
            cancelMapDownloadButton.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            cancelMapDownloadButton.Location = new System.Drawing.Point(565, 6);
            cancelMapDownloadButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            cancelMapDownloadButton.Name = "cancelMapDownloadButton";
            cancelMapDownloadButton.Size = new System.Drawing.Size(100, 35);
            cancelMapDownloadButton.TabIndex = 8;
            cancelMapDownloadButton.Text = "Cancel";
            cancelMapDownloadButton.UseVisualStyleBackColor = true;
            cancelMapDownloadButton.Click += cancelMapDownloadButton_Click;
            // 
            // downloadMapLabel
            // 
            downloadMapLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            downloadMapLabel.AutoSize = true;
            downloadMapLabel.Font = new System.Drawing.Font("Microsoft Sans Serif", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            downloadMapLabel.Location = new System.Drawing.Point(7, 11);
            downloadMapLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            downloadMapLabel.Name = "downloadMapLabel";
            downloadMapLabel.Size = new System.Drawing.Size(154, 20);
            downloadMapLabel.TabIndex = 7;
            downloadMapLabel.Text = "Downloading map...";
            // 
            // showAirplanesToolStripMenuItem
            // 
            showAirplanesToolStripMenuItem.CheckOnClick = true;
            showAirplanesToolStripMenuItem.Name = "showAirplanesToolStripMenuItem";
            showAirplanesToolStripMenuItem.Size = new System.Drawing.Size(210, 26);
            showAirplanesToolStripMenuItem.Text = "Show Airplanes";
            showAirplanesToolStripMenuItem.Visible = false;
            showAirplanesToolStripMenuItem.Click += showAirplanesToolStripMenuItem_Click;
            // 
            // MapTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(mapZoomOutButton);
            Controls.Add(mapZoomInbutton);
            Controls.Add(mapControl);
            Controls.Add(downloadMapPanel);
            Controls.Add(mapTopPanel);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            Name = "MapTabUserControl";
            Size = new System.Drawing.Size(669, 448);
            mapTopPanel.ResumeLayout(false);
            mapTopPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)mapMenuPictureBox).EndInit();
            mapTabContextMenuStrip.ResumeLayout(false);
            downloadMapPanel.ResumeLayout(false);
            downloadMapPanel.PerformLayout();
            ResumeLayout(false);

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
        private System.Windows.Forms.ToolStripMenuItem showAirplanesToolStripMenuItem;
    }
}
