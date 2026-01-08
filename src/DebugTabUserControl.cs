using System;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace HTCommander.Controls
{
    public partial class DebugTabUserControl : UserControl
    {
        private MainForm mainForm;

        public DebugTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;
            
            // Load settings from registry
            showBluetoothFramesToolStripMenuItem.Checked = (mainForm.registry.ReadInt("PacketTrace", 0) == 1);
            
            string debugFileName = mainForm.registry.ReadString("DebugFile", null);
            if (!string.IsNullOrEmpty(debugFileName))
            {
                saveTraceFileDialog.FileName = debugFileName;
                debugSaveToFileToolStripMenuItem.Checked = (mainForm.debugFile != null);
            }
        }

        public void AppendText(string text)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(AppendText), text);
                return;
            }
            try { debugTextBox.AppendText(text + Environment.NewLine); } catch (Exception) { }
        }

        public void Clear()
        {
            debugTextBox.Clear();
        }

        private void debugMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            debugTabContextMenuStrip.Show(debugMenuPictureBox, e.Location);
        }

        private void saveToFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm.debugFile != null)
            {
                mainForm.debugFile.Close();
                mainForm.debugFile = null;
                debugSaveToFileToolStripMenuItem.Checked = false;
                mainForm.registry.DeleteValue("DebugFile");
            }
            else
            {
                if (saveTraceFileDialog.ShowDialog(this) == DialogResult.OK)
                {
                    mainForm.debugFile = File.OpenWrite(saveTraceFileDialog.FileName);
                    debugSaveToFileToolStripMenuItem.Checked = true;
                    mainForm.registry.WriteString("DebugFile", saveTraceFileDialog.FileName);
                }
            }
        }

        private void showBluetoothFramesToolStripMenuItem_CheckStateChanged(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            mainForm.radio.PacketTrace = showBluetoothFramesToolStripMenuItem.Checked;
            mainForm.registry.WriteInt("PacketTrace", showBluetoothFramesToolStripMenuItem.Checked ? 1 : 0);
        }

        private void loopbackModeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (mainForm == null) return;
            mainForm.radio.LoopbackMode = loopbackModeToolStripMenuItem.Checked;
        }

        private async void queryDeviceNamesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string[] deviceNames = await RadioBluetoothWin.GetDeviceNames();
            mainForm.DebugTrace("List of devices:");
            foreach (string deviceName in deviceNames)
            {
                mainForm.DebugTrace("  " + deviceName);
            }
        }

        private void clearToolStripMenuItem_Click(object sender, EventArgs e)
        {
            debugTextBox.Clear();
        }
    }
}