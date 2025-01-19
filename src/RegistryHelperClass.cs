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
using Microsoft.Win32;

namespace HTCommander
{
    public class RegistryHelper
    {
        private readonly string _applicationName;

        /// <summary>
        /// Initializes a new instance of the RegistryHelper class.
        /// </summary>
        /// <param name="applicationName">The name of the application to be used as the registry key.</param>
        public RegistryHelper(string applicationName)
        {
            if (string.IsNullOrEmpty(applicationName))
                throw new ArgumentException("Application name cannot be null or empty.", nameof(applicationName));

            using (var key = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}")) { }

            _applicationName = applicationName;
        }

        /// <summary>
        /// Writes a string value to the registry.
        /// </summary>
        /// <param name="keyName">The name of the registry key.</param>
        /// <param name="value">The string value to write.</param>
        public void WriteString(string keyName, string value)
        {
            using (var key = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}"))
            {
                key?.SetValue(keyName, value, RegistryValueKind.String);
            }
        }

        /// <summary>
        /// Reads a string value from the registry.
        /// </summary>
        /// <param name="keyName">The name of the registry key.</param>
        /// <returns>The string value, or null if the key does not exist.</returns>
        public string ReadString(string keyName, string defaultValue)
        {
            using (var key = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}"))
            {
                if (key == null) { return defaultValue; }
                string r = key?.GetValue(keyName) as string;
                if (r == null) return defaultValue;
                return r;
            }
        }

        /// <summary>
        /// Writes an integer value to the registry.
        /// </summary>
        /// <param name="keyName">The name of the registry key.</param>
        /// <param name="value">The integer value to write.</param>
        public void WriteInt(string keyName, int value)
        {
            using (var key = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}"))
            {
                key?.SetValue(keyName, value, RegistryValueKind.DWord);
            }
        }

        /// <summary>
        /// Reads an integer value from the registry.
        /// </summary>
        /// <param name="keyName">The name of the registry key.</param>
        /// <returns>The integer value, or null if the key does not exist.</returns>
        public int? ReadInt(string keyName, int? defaultValue)
        {
            using (var key = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}"))
            {
                if (key == null) return defaultValue;
                object value = key.GetValue(keyName);
                if (value is int intValue) { return intValue; }
                return defaultValue;
            }
        }

        /// <summary>
        /// Deletes a value from the registry.
        /// </summary>
        /// <param name="keyName">The name of the registry key to delete.</param>
        public void DeleteValue(string keyName)
        {
            using (var key = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}", writable: true))
            {
                key?.DeleteValue(keyName, throwOnMissingValue: false);
            }
        }
    }
}
