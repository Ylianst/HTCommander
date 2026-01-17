namespace HTCommander.Controls
{
    partial class DebugTabUserControl
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
            this.debugTextBox = new System.Windows.Forms.TextBox();
            this.debugControlsPanel = new System.Windows.Forms.Panel();
            this.debugMenuPictureBox = new System.Windows.Forms.PictureBox();
            this.label2 = new System.Windows.Forms.Label();
            this.debugTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.debugSaveToFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.showBluetoothFramesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.loopbackModeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem3 = new System.Windows.Forms.ToolStripSeparator();
            this.queryDeviceNamesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem8 = new System.Windows.Forms.ToolStripSeparator();
            this.clearToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            this.detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.saveTraceFileDialog = new System.Windows.Forms.SaveFileDialog();
            this.debugControlsPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.debugMenuPictureBox)).BeginInit();
            this.debugTabContextMenuStrip.SuspendLayout();
            this.SuspendLayout();
            // 
            // debugTextBox
            // 
            this.debugTextBox.BackColor = System.Drawing.Color.LightGray;
            this.debugTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.debugTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            this.debugTextBox.Location = new System.Drawing.Point(0, 37);
            this.debugTextBox.Margin = new System.Windows.Forms.Padding(0);
            this.debugTextBox.Multiline = true;
            this.debugTextBox.Name = "debugTextBox";
            this.debugTextBox.ReadOnly = true;
            this.debugTextBox.ScrollBars = System.Windows.Forms.ScrollBars.Both;
            this.debugTextBox.Size = new System.Drawing.Size(668, 588);
            this.debugTextBox.TabIndex = 1;
            this.debugTextBox.WordWrap = false;
            // 
            // debugControlsPanel
            // 
            this.debugControlsPanel.BackColor = System.Drawing.Color.Silver;
            this.debugControlsPanel.Controls.Add(this.debugMenuPictureBox);
            this.debugControlsPanel.Controls.Add(this.label2);
            this.debugControlsPanel.Dock = System.Windows.Forms.DockStyle.Top;
            this.debugControlsPanel.Location = new System.Drawing.Point(0, 0);
            this.debugControlsPanel.Margin = new System.Windows.Forms.Padding(4);
            this.debugControlsPanel.Name = "debugControlsPanel";
            this.debugControlsPanel.Size = new System.Drawing.Size(668, 37);
            this.debugControlsPanel.TabIndex = 0;
            // 
            // debugMenuPictureBox
            // 
            this.debugMenuPictureBox.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.debugMenuPictureBox.Image = global::HTCommander.Properties.Resources.MenuIcon;
            this.debugMenuPictureBox.Location = new System.Drawing.Point(636, 6);
            this.debugMenuPictureBox.Margin = new System.Windows.Forms.Padding(4);
            this.debugMenuPictureBox.Name = "debugMenuPictureBox";
            this.debugMenuPictureBox.Size = new System.Drawing.Size(27, 25);
            this.debugMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.debugMenuPictureBox.TabIndex = 3;
            this.debugMenuPictureBox.TabStop = false;
            this.debugMenuPictureBox.MouseClick += new System.Windows.Forms.MouseEventHandler(this.debugMenuPictureBox_MouseClick);
            // 
            // label2
            // 
            this.label2.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.label2.AutoSize = true;
            this.label2.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label2.Location = new System.Drawing.Point(4, 6);
            this.label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(164, 25);
            this.label2.TabIndex = 1;
            this.label2.Text = "Developer Debug";
            // 
            // debugTabContextMenuStrip
            // 
            this.debugTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.debugTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.debugSaveToFileToolStripMenuItem,
            this.showBluetoothFramesToolStripMenuItem,
            this.loopbackModeToolStripMenuItem,
            this.toolStripMenuItem3,
            this.queryDeviceNamesToolStripMenuItem,
            this.toolStripMenuItem8,
            this.clearToolStripMenuItem,
            this.toolStripMenuItemDetachSeparator,
            this.detachToolStripMenuItem});
            this.debugTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            this.debugTabContextMenuStrip.Size = new System.Drawing.Size(235, 166);
            // 
            // debugSaveToFileToolStripMenuItem
            // 
            this.debugSaveToFileToolStripMenuItem.Name = "debugSaveToFileToolStripMenuItem";
            this.debugSaveToFileToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            this.debugSaveToFileToolStripMenuItem.Text = "&Save To File...";
            this.debugSaveToFileToolStripMenuItem.Click += new System.EventHandler(this.saveToFileToolStripMenuItem_Click);
            // 
            // showBluetoothFramesToolStripMenuItem
            // 
            this.showBluetoothFramesToolStripMenuItem.CheckOnClick = true;
            this.showBluetoothFramesToolStripMenuItem.Name = "showBluetoothFramesToolStripMenuItem";
            this.showBluetoothFramesToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            this.showBluetoothFramesToolStripMenuItem.Text = "Show Bluetooth Frames";
            this.showBluetoothFramesToolStripMenuItem.Click += new System.EventHandler(this.showBluetoothFramesToolStripMenuItem_Click);
            // 
            // loopbackModeToolStripMenuItem
            // 
            this.loopbackModeToolStripMenuItem.CheckOnClick = true;
            this.loopbackModeToolStripMenuItem.Name = "loopbackModeToolStripMenuItem";
            this.loopbackModeToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            this.loopbackModeToolStripMenuItem.Text = "&Loopback Mode";
            this.loopbackModeToolStripMenuItem.Click += new System.EventHandler(this.loopbackModeToolStripMenuItem_Click);
            // 
            // toolStripMenuItem3
            // 
            this.toolStripMenuItem3.Name = "toolStripMenuItem3";
            this.toolStripMenuItem3.Size = new System.Drawing.Size(231, 6);
            // 
            // queryDeviceNamesToolStripMenuItem
            // 
            this.queryDeviceNamesToolStripMenuItem.Name = "queryDeviceNamesToolStripMenuItem";
            this.queryDeviceNamesToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            this.queryDeviceNamesToolStripMenuItem.Text = "Query Device Names";
            this.queryDeviceNamesToolStripMenuItem.Click += new System.EventHandler(this.queryDeviceNamesToolStripMenuItem_Click);
            // 
            // toolStripMenuItem8
            // 
            this.toolStripMenuItem8.Name = "toolStripMenuItem8";
            this.toolStripMenuItem8.Size = new System.Drawing.Size(231, 6);
            // 
            // clearToolStripMenuItem
            // 
            this.clearToolStripMenuItem.Name = "clearToolStripMenuItem";
            this.clearToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            this.clearToolStripMenuItem.Text = "&Clear";
            this.clearToolStripMenuItem.Click += new System.EventHandler(this.clearToolStripMenuItem_Click);
            // 
            // toolStripMenuItemDetachSeparator
            // 
            this.toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            this.toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(231, 6);
            this.toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            this.detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            this.detachToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            this.detachToolStripMenuItem.Text = "Detach...";
            this.detachToolStripMenuItem.Visible = false;
            this.detachToolStripMenuItem.Click += new System.EventHandler(this.detachToolStripMenuItem_Click);
            // 
            // saveTraceFileDialog
            // 
            this.saveTraceFileDialog.Filter = "Text files|*.txt";
            this.saveTraceFileDialog.Title = "Save Tracing File";
            // 
            // DebugTabUserControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.debugTextBox);
            this.Controls.Add(this.debugControlsPanel);
            this.Name = "DebugTabUserControl";
            this.Size = new System.Drawing.Size(668, 625);
            this.debugControlsPanel.ResumeLayout(false);
            this.debugControlsPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.debugMenuPictureBox)).EndInit();
            this.debugTabContextMenuStrip.ResumeLayout(false);
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.TextBox debugTextBox;
        private System.Windows.Forms.Panel debugControlsPanel;
        private System.Windows.Forms.PictureBox debugMenuPictureBox;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.ContextMenuStrip debugTabContextMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem debugSaveToFileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem showBluetoothFramesToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem loopbackModeToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem3;
        private System.Windows.Forms.ToolStripMenuItem queryDeviceNamesToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem8;
        private System.Windows.Forms.ToolStripMenuItem clearToolStripMenuItem;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItemDetachSeparator;
        private System.Windows.Forms.ToolStripMenuItem detachToolStripMenuItem;
        private System.Windows.Forms.SaveFileDialog saveTraceFileDialog;
    }
}
