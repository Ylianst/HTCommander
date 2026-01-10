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
using System.Text;
using System.IO.Pipes;
using System.Threading;
using System.Diagnostics;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.Collections.Generic;

namespace HTCommander
{
    internal static class Program
    {
        private static List<string> BlackBoxEvents = new List<string>();
        public static string PipeName = "HtCommander-DB346020-4700-4026-A8D1-E05AE4F62A05-pipe";

        /// <summary>
        /// The main entry point for the application.
        /// </summary>
        [STAThread]
        static void Main(string[] args)
        {
            bool isNewInstance;
            string mutexName = "HtCommander-DB346020-4700-4026-A8D1-E05AE4F62A05";

            bool multiInstance = false;
            foreach (string arg in args)
            {
                if (string.Compare(arg, "-multiinstance", true) == 0) { multiInstance = true; }
            }

            if (multiInstance == true)
            {
                MainEx(args);
            }
            else
            {
                using (Mutex mutex = new Mutex(true, mutexName, out isNewInstance))
                {
                    if (isNewInstance)
                    {
                        MainEx(args);
                    }
                    else
                    {
                        // Another instance is already running
                        BringExistingInstanceToFront();
                    }
                }
            }
        }
        static void MainEx(string[] args)
        {
            // Initialize the global data broker
            DataBroker.Initialize("HTCommander");

            // No other instance running
            Application.ThreadException += new System.Threading.ThreadExceptionEventHandler(ExceptionSink);
            AppDomain.CurrentDomain.UnhandledException += new UnhandledExceptionEventHandler(UnhandledExceptionEventSink);
            TaskScheduler.UnobservedTaskException += TaskScheduler_UnobservedTaskException;
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException, true);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                Application.Run(new MainForm(args));
            }
            catch (Exception ex)
            {
                Debug("--- HTCommander Exception ---\r\n" + DateTime.Now + ", Version: " + GetFileVersion() + "\r\nException:\r\n" + ex.ToString() + "\r\n\r\n\r\n");
            }
        }

        private static void BringExistingInstanceToFront()
        {
            // Send "show" command to the main instance
            try
            {
                using (var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out))
                using (var writer = new StreamWriter(client))
                {
                    client.Connect(1000); // Wait up to 1s
                    writer.WriteLine("show");
                    writer.Flush();
                }
            }
            catch
            {
                MessageBox.Show("Could not contact the running instance.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void LaunchDetachedInstance()
        {
            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = Process.GetCurrentProcess().MainModule.FileName,
                    // Launch without the /silentlaunch flag
                    Arguments = "",
                    UseShellExecute = true, // Important for GUI apps
                    WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory,
                };

                Process.Start(startInfo);
            }
            catch (Exception)
            {
                // Log or silently fail — optional
            }
        }

        public static void BlockBoxEvent(string ev)
        {
            BlackBoxEvents.Add(DateTime.Now.ToString() + " - " + ev);
            while (BlackBoxEvents.Count > 50) { BlackBoxEvents.RemoveAt(0); }
        }

        public static void Debug(string msg) { try { File.AppendAllText("debug.log", msg + "\r\n"); } catch (Exception) { } }

        public static void ExceptionSink(object sender, System.Threading.ThreadExceptionEventArgs args)
        {
            Debug("--- HTCommander Exception Sink ---\r\n" + DateTime.Now + ", Version: " + GetFileVersion() + "\r\nException:\r\n" + args.Exception.ToString() + "\r\n\r\n" + GetBlackBoxEvents() + "\r\n\r\n\r\n");
        }

        public static void UnhandledExceptionEventSink(object sender, UnhandledExceptionEventArgs args)
        {
            Debug("--- HTCommander Unhandled Exception ---\r\n" + DateTime.Now + ", Version: " + GetFileVersion() + "\r\nException: " + ((Exception)args.ExceptionObject).ToString() + "\r\n\r\n" + GetBlackBoxEvents() + "\r\n\r\n\r\n");
        }

        static void TaskScheduler_UnobservedTaskException(object sender, UnobservedTaskExceptionEventArgs e)
        {
            Debug("--- HTCommander Unhandled Task Exception ---\r\n" + DateTime.Now + ", Version: " + GetFileVersion() + "\r\nException:\r\n" + e.Exception.ToString() + "\r\n\r\n" + GetBlackBoxEvents() + "\r\n\r\n\r\n");
            e.SetObserved(); // Prevent the application from crashing
        }

        public static void ExceptionSink(object sender, Exception ex)
        {
            Debug("--- HTCommander Exception Sink ---\r\n" + DateTime.Now + ", Version: " + GetFileVersion() + "\r\nException:\r\n" + ex.ToString() + "\r\n\r\n" + GetBlackBoxEvents() + "\r\n\r\n\r\n");
        }

        private static string GetBlackBoxEvents()
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("Last Events:");
            foreach (string e in BlackBoxEvents) { sb.AppendLine(e); }
            return sb.ToString();
        }

        private static string GetFileVersion()
        {
            // Get the path of the currently running executable
            string exePath = Application.ExecutablePath;

            // Get the FileVersionInfo for the executable
            FileVersionInfo versionInfo = FileVersionInfo.GetVersionInfo(exePath);

            // Return the FileVersion as a string
            return versionInfo.FileVersion;
        }
    }
}
