/*
Copyright 2025 Ylian Saint-Hilaire

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
using System.Diagnostics;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.Collections.Generic;
using HTCommander.radio;

namespace HTCommander
{
    internal static class Program
    {
        private static List<string> BlackBoxEvents = new List<string>();

        /// <summary>
        /// The main entry point for the application.
        /// </summary>
        [STAThread]
        static void Main(string[] args)
        {
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
