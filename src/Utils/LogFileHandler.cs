/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using System;
using System.IO;

namespace HTCommander
{
    /// <summary>
    /// A data handler that saves log messages (LogInfo and LogError) to a file.
    /// Implements IDisposable for proper cleanup when removed from the broker.
    /// </summary>
    public class LogFileHandler : IDisposable
    {
        private readonly DataBrokerClient _broker;
        private readonly string _filePath;
        private StreamWriter _writer;
        private readonly object _lock = new object();
        private bool _disposed = false;

        /// <summary>
        /// Creates a new LogFileHandler that writes log messages to the specified file.
        /// </summary>
        /// <param name="filePath">The path to the log file.</param>
        /// <param name="append">If true, append to existing file; if false, overwrite.</param>
        public LogFileHandler(string filePath, bool append = true)
        {
            if (string.IsNullOrEmpty(filePath)) throw new ArgumentNullException(nameof(filePath));

            _filePath = filePath;
            _broker = new DataBrokerClient();

            // Open the file for writing
            _writer = new StreamWriter(filePath, append);
            _writer.AutoFlush = true;

            // Subscribe to log messages
            _broker.Subscribe(1, new[] { "LogInfo", "LogError" }, OnLogMessage);

            // Write header
            WriteLog("INFO", "Log file opened: " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
        }

        /// <summary>
        /// Gets the path to the log file.
        /// </summary>
        public string FilePath => _filePath;

        /// <summary>
        /// Gets whether the handler is disposed.
        /// </summary>
        public bool IsDisposed => _disposed;

        private void OnLogMessage(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (data is string message)
            {
                string level = (name == "LogError") ? "ERROR" : "INFO";
                WriteLog(level, message);
            }
        }

        private void WriteLog(string level, string message)
        {
            lock (_lock)
            {
                if (_writer != null && !_disposed)
                {
                    try
                    {
                        string timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
                        _writer.WriteLine($"[{timestamp}] [{level}] {message}");
                    }
                    catch (Exception)
                    {
                        // Ignore write errors
                    }
                }
            }
        }

        /// <summary>
        /// Writes a custom message directly to the log file.
        /// </summary>
        /// <param name="level">The log level (e.g., "INFO", "ERROR", "DEBUG").</param>
        /// <param name="message">The message to write.</param>
        public void Write(string level, string message)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(LogFileHandler));
            WriteLog(level, message);
        }

        /// <summary>
        /// Flushes the log file buffer.
        /// </summary>
        public void Flush()
        {
            lock (_lock)
            {
                if (_writer != null && !_disposed)
                {
                    try
                    {
                        _writer.Flush();
                    }
                    catch (Exception)
                    {
                        // Ignore flush errors
                    }
                }
            }
        }

        /// <summary>
        /// Disposes the handler, closing the log file and unsubscribing from the broker.
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
                    // Write closing message
                    WriteLog("INFO", "Log file closed: " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));

                    // Dispose the broker client (unsubscribes)
                    _broker?.Dispose();

                    // Close the file
                    lock (_lock)
                    {
                        if (_writer != null)
                        {
                            try
                            {
                                _writer.Close();
                                _writer.Dispose();
                            }
                            catch (Exception)
                            {
                                // Ignore close errors
                            }
                            _writer = null;
                        }
                    }
                }
                _disposed = true;
            }
        }

        /// <summary>
        /// Finalizer to ensure cleanup if Dispose is not called.
        /// </summary>
        ~LogFileHandler()
        {
            Dispose(false);
        }
    }
}
