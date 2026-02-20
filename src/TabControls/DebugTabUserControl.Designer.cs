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
            components = new System.ComponentModel.Container();
            debugTextBox = new System.Windows.Forms.TextBox();
            debugControlsPanel = new System.Windows.Forms.Panel();
            debugMenuPictureBox = new System.Windows.Forms.PictureBox();
            label2 = new System.Windows.Forms.Label();
            debugTabContextMenuStrip = new System.Windows.Forms.ContextMenuStrip(components);
            debugSaveToFileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            showBluetoothFramesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            loopbackModeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem3 = new System.Windows.Forms.ToolStripSeparator();
            queryDeviceNamesToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItem8 = new System.Windows.Forms.ToolStripSeparator();
            clearToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            toolStripMenuItemDetachSeparator = new System.Windows.Forms.ToolStripSeparator();
            detachToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            saveTraceFileDialog = new System.Windows.Forms.SaveFileDialog();
            debugControlsPanel.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)debugMenuPictureBox).BeginInit();
            debugTabContextMenuStrip.SuspendLayout();
            SuspendLayout();
            // 
            // debugTextBox
            // 
            debugTextBox.BackColor = System.Drawing.Color.LightGray;
            debugTextBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            debugTextBox.Dock = System.Windows.Forms.DockStyle.Fill;
            debugTextBox.Location = new System.Drawing.Point(0, 46);
            debugTextBox.Margin = new System.Windows.Forms.Padding(0);
            debugTextBox.Multiline = true;
            debugTextBox.Name = "debugTextBox";
            debugTextBox.ReadOnly = true;
            debugTextBox.ScrollBars = System.Windows.Forms.ScrollBars.Both;
            debugTextBox.Size = new System.Drawing.Size(668, 475);
            debugTextBox.TabIndex = 1;
            debugTextBox.WordWrap = false;
            // 
            // debugControlsPanel
            // 
            debugControlsPanel.BackColor = System.Drawing.Color.Silver;
            debugControlsPanel.Controls.Add(debugMenuPictureBox);
            debugControlsPanel.Controls.Add(label2);
            debugControlsPanel.Dock = System.Windows.Forms.DockStyle.Top;
            debugControlsPanel.Location = new System.Drawing.Point(0, 0);
            debugControlsPanel.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            debugControlsPanel.Name = "debugControlsPanel";
            debugControlsPanel.Size = new System.Drawing.Size(668, 46);
            debugControlsPanel.TabIndex = 0;
            // 
            // debugMenuPictureBox
            // 
            debugMenuPictureBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            debugMenuPictureBox.Image = Properties.Resources.MenuIcon;
            debugMenuPictureBox.Location = new System.Drawing.Point(636, 8);
            debugMenuPictureBox.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            debugMenuPictureBox.Name = "debugMenuPictureBox";
            debugMenuPictureBox.Size = new System.Drawing.Size(27, 31);
            debugMenuPictureBox.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            debugMenuPictureBox.TabIndex = 3;
            debugMenuPictureBox.TabStop = false;
            debugMenuPictureBox.MouseClick += debugMenuPictureBox_MouseClick;
            // 
            // label2
            // 
            label2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label2.AutoSize = true;
            label2.Font = new System.Drawing.Font("Microsoft Sans Serif", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, 0);
            label2.Location = new System.Drawing.Point(4, 8);
            label2.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label2.Name = "label2";
            label2.Size = new System.Drawing.Size(164, 25);
            label2.TabIndex = 1;
            label2.Text = "Developer Debug";
            // 
            // debugTabContextMenuStrip
            // 
            debugTabContextMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            debugTabContextMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] { debugSaveToFileToolStripMenuItem, showBluetoothFramesToolStripMenuItem, loopbackModeToolStripMenuItem, toolStripMenuItem3, queryDeviceNamesToolStripMenuItem, toolStripMenuItem8, clearToolStripMenuItem, toolStripMenuItemDetachSeparator, detachToolStripMenuItem });
            debugTabContextMenuStrip.Name = "debugTabContextMenuStrip";
            debugTabContextMenuStrip.Size = new System.Drawing.Size(235, 166);
            // 
            // debugSaveToFileToolStripMenuItem
            // 
            debugSaveToFileToolStripMenuItem.Name = "debugSaveToFileToolStripMenuItem";
            debugSaveToFileToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            debugSaveToFileToolStripMenuItem.Text = "&Save To File...";
            debugSaveToFileToolStripMenuItem.Click += saveToFileToolStripMenuItem_Click;
            // 
            // showBluetoothFramesToolStripMenuItem
            // 
            showBluetoothFramesToolStripMenuItem.CheckOnClick = true;
            showBluetoothFramesToolStripMenuItem.Name = "showBluetoothFramesToolStripMenuItem";
            showBluetoothFramesToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            showBluetoothFramesToolStripMenuItem.Text = "Show Bluetooth Frames";
            showBluetoothFramesToolStripMenuItem.Click += showBluetoothFramesToolStripMenuItem_Click;
            // 
            // loopbackModeToolStripMenuItem
            // 
            loopbackModeToolStripMenuItem.CheckOnClick = true;
            loopbackModeToolStripMenuItem.Name = "loopbackModeToolStripMenuItem";
            loopbackModeToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            loopbackModeToolStripMenuItem.Text = "&Loopback Mode";
            loopbackModeToolStripMenuItem.Click += loopbackModeToolStripMenuItem_Click;
            // 
            // toolStripMenuItem3
            // 
            toolStripMenuItem3.Name = "toolStripMenuItem3";
            toolStripMenuItem3.Size = new System.Drawing.Size(231, 6);
            // 
            // queryDeviceNamesToolStripMenuItem
            // 
            queryDeviceNamesToolStripMenuItem.Name = "queryDeviceNamesToolStripMenuItem";
            queryDeviceNamesToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            queryDeviceNamesToolStripMenuItem.Text = "Query Device Names";
            queryDeviceNamesToolStripMenuItem.Click += queryDeviceNamesToolStripMenuItem_Click;
            // 
            // toolStripMenuItem8
            // 
            toolStripMenuItem8.Name = "toolStripMenuItem8";
            toolStripMenuItem8.Size = new System.Drawing.Size(231, 6);
            // 
            // clearToolStripMenuItem
            // 
            clearToolStripMenuItem.Name = "clearToolStripMenuItem";
            clearToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            clearToolStripMenuItem.Text = "&Clear";
            clearToolStripMenuItem.Click += clearToolStripMenuItem_Click;
            // 
            // toolStripMenuItemDetachSeparator
            // 
            toolStripMenuItemDetachSeparator.Name = "toolStripMenuItemDetachSeparator";
            toolStripMenuItemDetachSeparator.Size = new System.Drawing.Size(231, 6);
            toolStripMenuItemDetachSeparator.Visible = false;
            // 
            // detachToolStripMenuItem
            // 
            detachToolStripMenuItem.Name = "detachToolStripMenuItem";
            detachToolStripMenuItem.Size = new System.Drawing.Size(234, 24);
            detachToolStripMenuItem.Text = "Detach...";
            detachToolStripMenuItem.Visible = false;
            detachToolStripMenuItem.Click += detachToolStripMenuItem_Click;
            // 
            // saveTraceFileDialog
            // 
            saveTraceFileDialog.Filter = "Text files|*.txt";
            saveTraceFileDialog.Title = "Save Tracing File";
            // 
            // DebugTabUserControl
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(debugTextBox);
            Controls.Add(debugControlsPanel);
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            Name = "DebugTabUserControl";
            Size = new System.Drawing.Size(668, 521);
            debugControlsPanel.ResumeLayout(false);
            debugControlsPanel.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)debugMenuPictureBox).EndInit();
            debugTabContextMenuStrip.ResumeLayout(false);
            ResumeLayout(false);
            PerformLayout();

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
