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

using System.Diagnostics;

class Program
{
    static void Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.WriteLine("Usage: HtCommanderUpdater.exe <AppProcessName> <InstallerPath> <AppExePath>");
            return;
        }

        string appProcessName = Path.GetFileNameWithoutExtension(args[0]); // e.g. "MyApp"
        string installerPath = args[1]; // e.g. "C:\\Temp\\update.msi"
        string newAppExePath = args[2]; // e.g. "C:\\Program Files\\MyApp\\MyApp.exe"

        // Wait for the main app to exit
        var matchingProcs = Process.GetProcessesByName(appProcessName);
        foreach (var proc in matchingProcs)
        {
            try
            {
                Console.WriteLine($"Waiting for {proc.ProcessName} (PID: {proc.Id}) to exit...");
                proc.WaitForExit();
            }
            catch { }
        }

        // Launch the MSI installer
        try
        {
            var msiProc = Process.Start(new ProcessStartInfo
            {
                FileName = "msiexec.exe",
                Arguments = $"/i \"{installerPath}\" /quiet /norestart",
                UseShellExecute = true,
                Verb = "runas"
            });

            msiProc.WaitForExit();
        }
        catch (Exception ex)
        {
            Console.WriteLine("Installer failed: " + ex.Message);
            return;
        }

        // Launch the updated application
        try
        {
            if (File.Exists(newAppExePath))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = newAppExePath,
                    UseShellExecute = true
                });
            }
            else
            {
                Console.WriteLine("Updated application not found.");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("Failed to launch updated app: " + ex.Message);
        }
    }
}
