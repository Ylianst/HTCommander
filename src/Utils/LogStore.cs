/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// Represents a single log entry with timestamp, level, and message.
    /// </summary>
    public class LogEntry
    {
        /// <summary>
        /// The timestamp when the log entry was created.
        /// </summary>
        public DateTime Time { get; set; }

        /// <summary>
        /// The log level: "Info" or "Error".
        /// </summary>
        public string Level { get; set; }

        /// <summary>
        /// The log message.
        /// </summary>
        public string Message { get; set; }

        /// <summary>
        /// Creates a new log entry.
        /// </summary>
        /// <param name="time">The timestamp.</param>
        /// <param name="level">The log level.</param>
        /// <param name="message">The log message.</param>
        public LogEntry(DateTime time, string level, string message)
        {
            Time = time;
            Level = level;
            Message = message;
        }

        /// <summary>
        /// Returns a string representation of the log entry.
        /// </summary>
        public override string ToString()
        {
            return $"[{Time:yyyy-MM-dd HH:mm:ss.fff}] [{Level}] {Message}";
        }
    }

    /// <summary>
    /// A data handler that stores the last 500 LogInfo and LogError messages in memory.
    /// Listens for LogInfo and LogError events on device 0 and maintains a running list.
    /// Other modules can request the log list via the Data Broker.
    /// Also supports saving logs to a file via Data Broker commands.
    /// </summary>
    public class LogStore : IDisposable
    {
        private readonly DataBrokerClient _broker;
        private readonly object _lock = new object();
        private bool _disposed = false;

        /// <summary>
        /// Maximum number of log entries to keep in memory.
        /// </summary>
        private const int MaxLogsInMemory = 500;

        /// <summary>
        /// The list of recent log entries, kept in chronological order (newest at the end).
        /// </summary>
        private readonly List<LogEntry> _logs = new List<LogEntry>();

        /// <summary>
        /// StreamWriter for file logging (null if not logging to file).
        /// </summary>
        private StreamWriter _fileWriter;

        /// <summary>
        /// The path to the current log file (null if not logging to file).
        /// </summary>
        private string _logFilePath;

        /// <summary>
        /// Creates a new LogStore that listens for LogInfo and LogError events.
        /// </summary>
        public LogStore()
        {
            _broker = new DataBrokerClient();

            // Subscribe to LogInfo and LogError events on device 0
            _broker.Subscribe(0, new[] { "LogInfo", "LogError" }, OnLogMessage);

            // Subscribe to requests for the log list on device 0
            _broker.Subscribe(0, "RequestLogList", OnRequestLogList);

            // Subscribe to file logging control commands
            _broker.Subscribe(0, "LogStoreStartFile", OnStartFileLogging);
            _broker.Subscribe(0, "LogStoreStopFile", OnStopFileLogging);

            // Notify subscribers that LogStore is ready (stored so late subscribers can check)
            _broker.Dispatch(0, "LogStoreReady", true, store: true);

            // Publish initial file logging state
            _broker.Dispatch(0, "LogStoreFileActive", false, store: true);
        }

        /// <summary>
        /// Gets whether the handler is disposed.
        /// </summary>
        public bool IsDisposed => _disposed;

        /// <summary>
        /// Gets whether file logging is currently active.
        /// </summary>
        public bool IsFileLoggingActive
        {
            get
            {
                lock (_lock)
                {
                    return _fileWriter != null;
                }
            }
        }

        /// <summary>
        /// Gets the current log file path, or null if not logging to file.
        /// </summary>
        public string LogFilePath
        {
            get
            {
                lock (_lock)
                {
                    return _logFilePath;
                }
            }
        }

        /// <summary>
        /// Gets the number of log entries currently stored in memory.
        /// </summary>
        public int LogCount
        {
            get
            {
                lock (_lock)
                {
                    return _logs.Count;
                }
            }
        }

        /// <summary>
        /// Gets a copy of the current log list.
        /// </summary>
        /// <returns>A list of LogEntry objects.</returns>
        public List<LogEntry> GetLogs()
        {
            lock (_lock)
            {
                return new List<LogEntry>(_logs);
            }
        }

        /// <summary>
        /// Gets a copy of the log entries filtered by level.
        /// </summary>
        /// <param name="level">The log level to filter by ("Info" or "Error").</param>
        /// <returns>A list of LogEntry objects matching the specified level.</returns>
        public List<LogEntry> GetLogsByLevel(string level)
        {
            lock (_lock)
            {
                return _logs.FindAll(l => l.Level.Equals(level, StringComparison.OrdinalIgnoreCase));
            }
        }

        /// <summary>
        /// Starts logging to a file.
        /// </summary>
        /// <param name="filePath">The path to the log file.</param>
        /// <returns>True if file logging was started successfully, false otherwise.</returns>
        public bool StartFileLogging(string filePath)
        {
            if (string.IsNullOrEmpty(filePath)) return false;

            lock (_lock)
            {
                // Stop existing file logging if active
                StopFileLoggingInternal();

                try
                {
                    _fileWriter = new StreamWriter(filePath, append: true);
                    _fileWriter.AutoFlush = true;
                    _logFilePath = filePath;

                    // Write header
                    _fileWriter.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] [Info] Log file opened: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                }
                catch (Exception)
                {
                    _fileWriter = null;
                    _logFilePath = null;
                    return false;
                }
            }

            // Notify subscribers that file logging is now active
            _broker.Dispatch(0, "LogStoreFileActive", true, store: true);
            _broker.Dispatch(0, "LogStoreFilePath", filePath, store: true);

            return true;
        }

        /// <summary>
        /// Stops logging to file.
        /// </summary>
        public void StopFileLogging()
        {
            bool wasActive;
            lock (_lock)
            {
                wasActive = _fileWriter != null;
                StopFileLoggingInternal();
            }

            if (wasActive)
            {
                // Notify subscribers that file logging is no longer active
                _broker.Dispatch(0, "LogStoreFileActive", false, store: true);
                _broker.Dispatch(0, "LogStoreFilePath", null, store: true);
            }
        }

        /// <summary>
        /// Internal method to stop file logging (must be called within lock).
        /// </summary>
        private void StopFileLoggingInternal()
        {
            if (_fileWriter != null)
            {
                try
                {
                    _fileWriter.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] [Info] Log file closed: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
                    _fileWriter.Close();
                    _fileWriter.Dispose();
                }
                catch (Exception) { }
                _fileWriter = null;
                _logFilePath = null;
            }
        }

        /// <summary>
        /// Handles the LogStoreStartFile command to start file logging.
        /// </summary>
        private void OnStartFileLogging(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (data is string filePath)
            {
                bool success = StartFileLogging(filePath);
                if (success)
                {
                    _broker.LogInfo("Log file opened: " + filePath);
                }
                else
                {
                    _broker.LogError("Failed to open log file: " + filePath);
                }
            }
        }

        /// <summary>
        /// Handles the LogStoreStopFile command to stop file logging.
        /// </summary>
        private void OnStopFileLogging(int deviceId, string name, object data)
        {
            if (_disposed) return;

            string filePath = _logFilePath;
            StopFileLogging();
            if (filePath != null)
            {
                _broker.LogInfo("Log file closed");
            }
        }

        /// <summary>
        /// Handles incoming LogInfo and LogError events and stores the log entry.
        /// </summary>
        private void OnLogMessage(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is string message)) return;

            // Determine the log level based on the event name
            string level = (name == "LogError") ? "Error" : "Info";

            // Create the log entry with current timestamp
            LogEntry entry = new LogEntry(DateTime.Now, level, message);

            // Add to memory list and write to file if active
            lock (_lock)
            {
                _logs.Add(entry);

                // Trim to MaxLogsInMemory
                while (_logs.Count > MaxLogsInMemory)
                {
                    _logs.RemoveAt(0);
                }

                // Write to file if logging is active
                if (_fileWriter != null)
                {
                    try
                    {
                        _fileWriter.WriteLine(entry.ToString());
                    }
                    catch (Exception)
                    {
                        // Ignore write errors
                    }
                }
            }

            // Dispatch an event to notify that a new log entry was stored
            _broker.Dispatch(0, "LogStored", entry, store: false);
        }

        /// <summary>
        /// Handles requests for the log list.
        /// </summary>
        private void OnRequestLogList(int deviceId, string name, object data)
        {
            if (_disposed) return;

            // Dispatch the current log list
            List<LogEntry> logs = GetLogs();
            _broker.Dispatch(0, "LogList", logs, store: false);
        }

        /// <summary>
        /// Clears all log entries from memory.
        /// </summary>
        public void ClearLogs()
        {
            lock (_lock)
            {
                _logs.Clear();
            }
        }

        /// <summary>
        /// Disposes the handler, unsubscribing from the broker.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Disposes the handler.
        /// </summary>
        /// <param name="disposing">True if called from Dispose(), false if called from finalizer.</param>
        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    // Stop file logging
                    lock (_lock)
                    {
                        StopFileLoggingInternal();
                    }

                    // Dispose the broker client (unsubscribes)
                    _broker?.Dispose();

                    // Clear the memory
                    lock (_lock)
                    {
                        _logs.Clear();
                    }
                }
                _disposed = true;
            }
        }

        /// <summary>
        /// Finalizer to ensure cleanup if Dispose is not called.
        /// </summary>
        ~LogStore()
        {
            Dispose(false);
        }
    }
}
