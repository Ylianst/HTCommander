/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Windows.Forms;
using HTCommander.Dialogs;

namespace HTCommander.Controls
{
    /// <summary>
    /// User control that provides a debug console for displaying log messages and diagnostics.
    /// Features include logging to file, Bluetooth frame debugging, and loopback mode control.
    /// </summary>
    /// <remarks>
    /// This control uses the DataBroker pattern to subscribe to log events and synchronize
    /// debug settings across the application. Settings like the debug file path and Bluetooth
    /// frames debug flag are persisted to the registry.
    /// </remarks>
    public partial class DebugTabUserControl : UserControl
    {
        #region Private Fields

        /// <summary>
        /// Client for subscribing to and dispatching messages through the DataBroker.
        /// </summary>
        private DataBrokerClient broker;

        /// <summary>
        /// Backing field for ShowDetach property.
        /// </summary>
        private bool _showDetach = false;

        #endregion

        #region Constructor

        /// <summary>
        /// Initializes a new instance of the <see cref="DebugTabUserControl"/> class.
        /// </summary>
        public DebugTabUserControl()
        {
            InitializeComponent();

            // Initialize the broker client for pub/sub messaging
            broker = new DataBrokerClient();

            // Subscribe to log messages (info and error)
            broker.Subscribe(1, new[] { "LogInfo", "LogError" }, OnLogMessage);

            // Subscribe to LogStore file logging state changes
            broker.Subscribe(0, "LogStoreFileActive", OnLogStoreFileActiveChanged);

            // Subscribe to Bluetooth frames debug setting changes (persisted in registry)
            broker.Subscribe(0, "BluetoothFramesDebug", OnBluetoothFramesDebugChanged);

            // Subscribe to loopback mode changes (device 1, not persisted)
            broker.Subscribe(1, "LoopbackMode", OnLoopbackModeChanged);

            // Subscribe to LogStoreReady in case LogStore is initialized after this control
            broker.Subscribe(0, "LogStoreReady", OnLogStoreReady);

            // Initialize menu item states from current broker values
            InitializeMenuItemStates();

            // Load existing log entries from LogStore
            LoadExistingLogs();
        }

        #endregion

        #region Public Properties

        /// <summary>
        /// Gets or sets whether the "Detach..." menu item is visible.
        /// This property can be set in the designer.
        /// </summary>
        [System.ComponentModel.Category("Behavior")]
        [System.ComponentModel.Description("Gets or sets whether the Detach menu item is visible.")]
        [System.ComponentModel.DefaultValue(false)]
        public bool ShowDetach
        {
            get { return _showDetach; }
            set
            {
                _showDetach = value;
                if (detachToolStripMenuItem != null)
                {
                    detachToolStripMenuItem.Visible = value;
                    toolStripMenuItemDetachSeparator.Visible = value;
                }
            }
        }

        #endregion

        #region Public Methods

        /// <summary>
        /// Appends a line of text to the debug output text box.
        /// </summary>
        /// <param name="text">The text to append.</param>
        /// <remarks>
        /// This method is thread-safe and will marshal the call to the UI thread if necessary.
        /// </remarks>
        public void AppendText(string text)
        {
            // Marshal to UI thread if called from a background thread
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(AppendText), text);
                return;
            }

            try
            {
                debugTextBox.AppendText(text + Environment.NewLine);
            }
            catch (Exception)
            {
                // Silently ignore any exceptions during text append (e.g., control disposed)
            }
        }

        /// <summary>
        /// Clears all text from the debug output text box.
        /// </summary>
        public void Clear()
        {
            debugTextBox.Clear();
        }

        #endregion

        #region Private Methods - Initialization

        /// <summary>
        /// Loads existing log entries from the LogStore data handler.
        /// </summary>
        private void LoadExistingLogs()
        {
            LogStore logStore = DataBroker.GetDataHandler<LogStore>("LogStore");
            if (logStore != null)
            {
                var logs = logStore.GetLogs();
                foreach (var entry in logs)
                {
                    if (entry.Level == "Error")
                    {
                        AppendText("[Error] " + entry.Message);
                    }
                    else
                    {
                        AppendText(entry.Message);
                    }
                }
            }
        }

        /// <summary>
        /// Initializes the checked states of menu items based on current broker values.
        /// </summary>
        private void InitializeMenuItemStates()
        {
            // Check if LogStore file logging is currently active
            debugSaveToFileToolStripMenuItem.Checked = DataBroker.GetValue<bool>(0, "LogStoreFileActive", false);

            // Get Bluetooth frames debug setting (persisted in registry)
            showBluetoothFramesToolStripMenuItem.Checked = DataBroker.GetValue<bool>(0, "BluetoothFramesDebug", false);

            // Get loopback mode setting (device 1, not persisted)
            loopbackModeToolStripMenuItem.Checked = DataBroker.GetValue<bool>(1, "LoopbackMode", false);
        }

        #endregion

        #region Private Methods - Event Handlers (DataBroker)

        /// <summary>
        /// Handles log messages received from the DataBroker.
        /// </summary>
        /// <param name="deviceId">The device ID that generated the message.</param>
        /// <param name="name">The message type name (LogInfo or LogError).</param>
        /// <param name="data">The log message content.</param>
        private void OnLogMessage(int deviceId, string name, object data)
        {
            if (data is string message)
            {
                // Prefix error messages for visibility
                if (name == "LogError")
                {
                    AppendText("[Error] " + message);
                }
                else
                {
                    AppendText(message);
                }
            }
        }

        /// <summary>
        /// Handles LogStore file logging state changes.
        /// </summary>
        /// <param name="deviceId">The device ID associated with the event.</param>
        /// <param name="name">The event name.</param>
        /// <param name="data">The new boolean state.</param>
        private void OnLogStoreFileActiveChanged(int deviceId, string name, object data)
        {
            if (data is bool isActive)
            {
                debugSaveToFileToolStripMenuItem.Checked = isActive;
            }
        }

        /// <summary>
        /// Handles changes to the Bluetooth frames debug setting.
        /// </summary>
        /// <param name="deviceId">The device ID associated with the setting.</param>
        /// <param name="name">The setting name.</param>
        /// <param name="data">The new boolean value.</param>
        private void OnBluetoothFramesDebugChanged(int deviceId, string name, object data)
        {
            if (data is bool value && showBluetoothFramesToolStripMenuItem.Checked != value)
            {
                showBluetoothFramesToolStripMenuItem.Checked = value;
            }
        }

        /// <summary>
        /// Handles changes to the loopback mode setting.
        /// </summary>
        /// <param name="deviceId">The device ID associated with the setting.</param>
        /// <param name="name">The setting name.</param>
        /// <param name="data">The new boolean value.</param>
        private void OnLoopbackModeChanged(int deviceId, string name, object data)
        {
            if (data is bool value && loopbackModeToolStripMenuItem.Checked != value)
            {
                loopbackModeToolStripMenuItem.Checked = value;
            }
        }

        /// <summary>
        /// Handles the LogStoreReady event to load existing logs if they weren't available at startup.
        /// </summary>
        /// <param name="deviceId">The device ID associated with the event.</param>
        /// <param name="name">The event name.</param>
        /// <param name="data">The event data.</param>
        private void OnLogStoreReady(int deviceId, string name, object data)
        {
            // Only load if we haven't loaded any logs yet (text box is empty)
            if (debugTextBox.TextLength == 0)
            {
                LoadExistingLogs();
            }
        }

        #endregion

        #region Private Methods - Event Handlers (UI Controls)

        /// <summary>
        /// Shows the context menu when the menu picture box is clicked.
        /// </summary>
        private void debugMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            debugTabContextMenuStrip.Show(debugMenuPictureBox, e.Location);
        }

        /// <summary>
        /// Toggles saving debug output to a log file via LogStore.
        /// </summary>
        /// <remarks>
        /// If logging is active, stops logging and closes the file.
        /// If logging is inactive, prompts the user to select a file and starts logging.
        /// The last used file path is persisted in the registry.
        /// </remarks>
        private void saveToFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            bool isFileLoggingActive = DataBroker.GetValue<bool>(0, "LogStoreFileActive", false);

            if (isFileLoggingActive)
            {
                // Stop logging via LogStore
                broker.Dispatch(0, "LogStoreStopFile", null, store: false);
            }
            else
            {
                // Start logging: prompt for file location
                StartLoggingToFile();
            }
        }

        /// <summary>
        /// Prompts the user to select a log file and starts logging via LogStore.
        /// </summary>
        private void StartLoggingToFile()
        {
            // Restore last used file path from registry
            string lastDebugFile = DataBroker.GetValue<string>(0, "DebugFile", null);
            if (!string.IsNullOrEmpty(lastDebugFile))
            {
                saveTraceFileDialog.FileName = lastDebugFile;
            }

            // Show save file dialog
            if (saveTraceFileDialog.ShowDialog(this) == DialogResult.OK)
            {
                // Persist the selected file path to registry
                DataBroker.Dispatch(0, "DebugFile", saveTraceFileDialog.FileName);

                // Start file logging via LogStore
                broker.Dispatch(0, "LogStoreStartFile", saveTraceFileDialog.FileName, store: false);
            }
        }

        /// <summary>
        /// Toggles the Bluetooth frames debug setting.
        /// </summary>
        private void showBluetoothFramesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Dispatch the new value (persists to registry via broker)
            DataBroker.Dispatch(0, "BluetoothFramesDebug", showBluetoothFramesToolStripMenuItem.Checked);
        }

        /// <summary>
        /// Toggles the loopback mode setting.
        /// </summary>
        private void loopbackModeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // Dispatch the new value (device 1, not persisted to registry)
            DataBroker.Dispatch(1, "LoopbackMode", loopbackModeToolStripMenuItem.Checked);
        }

        /// <summary>
        /// Queries and displays all connected Bluetooth device names.
        /// </summary>
        private async void queryDeviceNamesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string[] deviceNames = await RadioBluetoothWin.GetDeviceNames();
            broker.LogInfo("List of devices:");
            foreach (string deviceName in deviceNames)
            {
                broker.LogInfo("  " + deviceName);
            }
        }

        /// <summary>
        /// Clears the debug output text box.
        /// </summary>
        private void clearToolStripMenuItem_Click(object sender, EventArgs e)
        {
            debugTextBox.Clear();
        }

        /// <summary>
        /// Opens a new detached window with a DebugTabUserControl.
        /// </summary>
        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<DebugTabUserControl>("Developer Debug");
            form.Show();
        }

        #endregion
    }
}
