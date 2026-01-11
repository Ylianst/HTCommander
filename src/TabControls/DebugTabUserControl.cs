/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Windows.Forms;

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
            broker.Subscribe(0, new[] { "LogInfo", "LogError" }, OnLogMessage);

            // Subscribe to data handler lifecycle events for log file management
            broker.Subscribe(0, new[] { "DataHandlerAdded", "DataHandlerRemoved" }, OnDataHandlerChanged);

            // Subscribe to Bluetooth frames debug setting changes (persisted in registry)
            broker.Subscribe(0, "BluetoothFramesDebug", OnBluetoothFramesDebugChanged);

            // Subscribe to loopback mode changes (device 1, not persisted)
            broker.Subscribe(1, "LoopbackMode", OnLoopbackModeChanged);

            // Initialize menu item states from current broker values
            InitializeMenuItemStates();
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
        /// Initializes the checked states of menu items based on current broker values.
        /// </summary>
        private void InitializeMenuItemStates()
        {
            // Check if log file handler is currently active
            debugSaveToFileToolStripMenuItem.Checked = DataBroker.HasDataHandler("DebugLogFile");

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
        /// Handles data handler lifecycle events to update the save-to-file menu item state.
        /// </summary>
        /// <param name="deviceId">The device ID associated with the event.</param>
        /// <param name="name">The event name (DataHandlerAdded or DataHandlerRemoved).</param>
        /// <param name="data">The handler name that was added or removed.</param>
        private void OnDataHandlerChanged(int deviceId, string name, object data)
        {
            if (data is string handlerName && handlerName == "DebugLogFile")
            {
                debugSaveToFileToolStripMenuItem.Checked = (name == "DataHandlerAdded");
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
        /// Toggles saving debug output to a log file.
        /// </summary>
        /// <remarks>
        /// If logging is active, stops logging and closes the file.
        /// If logging is inactive, prompts the user to select a file and starts logging.
        /// The last used file path is persisted in the registry.
        /// </remarks>
        private void saveToFileToolStripMenuItem_Click(object sender, EventArgs e)
        {
            const string handlerName = "DebugLogFile";

            if (DataBroker.HasDataHandler(handlerName))
            {
                // Stop logging: remove the handler (disposes and closes the file)
                DataBroker.RemoveDataHandler(handlerName);
                debugSaveToFileToolStripMenuItem.Checked = false;
                broker.LogInfo("Log file closed");
            }
            else
            {
                // Start logging: prompt for file location
                StartLoggingToFile(handlerName);
            }
        }

        /// <summary>
        /// Prompts the user to select a log file and starts logging.
        /// </summary>
        /// <param name="handlerName">The name to register the log handler under.</param>
        private void StartLoggingToFile(string handlerName)
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
                try
                {
                    // Persist the selected file path to registry
                    DataBroker.Dispatch(0, "DebugFile", saveTraceFileDialog.FileName);

                    // Create and register the log file handler
                    var logHandler = new LogFileHandler(saveTraceFileDialog.FileName, append: true);
                    DataBroker.AddDataHandler(handlerName, logHandler);
                    debugSaveToFileToolStripMenuItem.Checked = true;
                    broker.LogInfo("Log file opened: " + saveTraceFileDialog.FileName);
                }
                catch (Exception ex)
                {
                    broker.LogError("Failed to open log file: " + ex.Message);
                    MessageBox.Show(
                        "Failed to open log file: " + ex.Message,
                        "Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
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

        #endregion
    }
}
