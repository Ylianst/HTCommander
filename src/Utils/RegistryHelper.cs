/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
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

            _applicationName = applicationName;

            // Ensure the registry key exists
            using (var key = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}")) { }
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
        /// Writes a boolean value to the registry.
        /// </summary>
        /// <param name="keyName">The name of the registry key.</param>
        /// <param name="value">The boolean value to write.</param>
        public void WriteBool(string keyName, bool value)
        {
            using (var key = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}"))
            {
                key?.SetValue(keyName, value ? 1 : 0, RegistryValueKind.DWord);
            }
        }

        /// <summary>
        /// Reads a boolean value from the registry.
        /// </summary>
        /// <param name="keyName">The name of the registry key.</param>
        /// <param name="defaultValue">The default value to return if the key does not exist.</param>
        /// <returns>The boolean value, or the default value if the key does not exist.</returns>
        public bool ReadBool(string keyName, bool defaultValue)
        {
            using (var key = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}"))
            {
                if (key == null) return defaultValue;
                object value = key.GetValue(keyName);
                if (value is int intValue) { return intValue != 0; }
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
