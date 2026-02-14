/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text.Json;
using System.Windows.Forms;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// A global data broker for dispatching and receiving data across components.
    /// Supports device-specific and named data channels with optional persistence.
    /// </summary>
    public static class DataBroker
    {
        /// <summary>
        /// Subscribe to all device IDs.
        /// </summary>
        public const int AllDevices = -1;

        /// <summary>
        /// Subscribe to all names.
        /// </summary>
        public const string AllNames = "*";

        private static readonly object _lock = new object();
        private static readonly Dictionary<DataKey, object> _dataStore = new Dictionary<DataKey, object>();
        private static readonly List<Subscription> _subscriptions = new List<Subscription>();
        private static readonly Dictionary<string, object> _dataHandlers = new Dictionary<string, object>();
        private static RegistryHelper _registryHelper;
        private static bool _initialized = false;
        private static Control _uiContext;

        /// <summary>
        /// Internal structure for storing data keys.
        /// </summary>
        private struct DataKey : IEquatable<DataKey>
        {
            public int DeviceId;
            public string Name;

            public DataKey(int deviceId, string name)
            {
                DeviceId = deviceId;
                Name = name;
            }

            public bool Equals(DataKey other)
            {
                return DeviceId == other.DeviceId && Name == other.Name;
            }

            public override bool Equals(object obj)
            {
                return obj is DataKey other && Equals(other);
            }

            public override int GetHashCode()
            {
                unchecked
                {
                    return (DeviceId * 397) ^ (Name != null ? Name.GetHashCode() : 0);
                }
            }
        }

        /// <summary>
        /// Internal subscription information.
        /// </summary>
        internal class Subscription
        {
            public DataBrokerClient Client;
            public int DeviceId;
            public string Name;
            public Action<int, string, object> Callback;
        }

        /// <summary>
        /// Initializes the data broker with optional registry persistence.
        /// </summary>
        /// <param name="appName">The application name for registry storage.</param>
        /// <param name="uiContext">Optional UI control for marshalling callbacks to the UI thread.</param>
        public static void Initialize(string appName, Control uiContext = null)
        {
            lock (_lock)
            {
                if (_initialized) return;
                _registryHelper = new RegistryHelper(appName);
                _uiContext = uiContext;
                _initialized = true;
            }
        }

        /// <summary>
        /// Sets the UI context for marshalling callbacks to the UI thread.
        /// </summary>
        /// <param name="uiContext">A control that can be used for Invoke operations.</param>
        public static void SetUIContext(Control uiContext)
        {
            lock (_lock)
            {
                _uiContext = uiContext;
            }
        }

        /// <summary>
        /// Dispatches data to the broker, optionally storing it and notifying subscribers.
        /// </summary>
        /// <param name="deviceId">The device ID (use 0 for values that should persist to registry).</param>
        /// <param name="name">The name/key of the data.</param>
        /// <param name="data">The data value.</param>
        /// <param name="store">If true, the value is stored in the broker; if false, only broadcast.</param>
        public static void Dispatch(int deviceId, string name, object data, bool store = true)
        {
            List<Subscription> matchingSubscriptions;

            lock (_lock)
            {
                if (store)
                {
                    var key = new DataKey(deviceId, name);
                    _dataStore[key] = data;

                    // Persist to registry if device 0
                    if (deviceId == 0 && _registryHelper != null)
                    {
                        if (data is int intValue)
                        {
                            _registryHelper.WriteInt(name, intValue);
                        }
                        else if (data is string stringValue)
                        {
                            _registryHelper.WriteString(name, stringValue);
                        }
                        else if (data is bool boolValue)
                        {
                            _registryHelper.WriteBool(name, boolValue);
                        }
                        else if (data != null)
                        {
                            // Serialize complex types with type marker prefix
                            string typeName = GetSerializableTypeName(data.GetType());
                            string json = JsonSerializer.Serialize(data);
                            string serialized = $"~~JSON:{typeName}:{json}";
                            _registryHelper.WriteString(name, serialized);
                        }
                    }
                }

                // Find matching subscriptions
                matchingSubscriptions = new List<Subscription>();
                foreach (var sub in _subscriptions)
                {
                    bool deviceMatches = (sub.DeviceId == AllDevices) || (sub.DeviceId == deviceId);
                    bool nameMatches = (sub.Name == AllNames) || (sub.Name == name);
                    if (deviceMatches && nameMatches)
                    {
                        matchingSubscriptions.Add(sub);
                    }
                }
            }

            // Invoke callbacks outside the lock to prevent deadlocks
            foreach (var sub in matchingSubscriptions)
            {
                try
                {
                    InvokeCallback(sub.Callback, deviceId, name, data);
                }
                catch (Exception)
                {
                    // Swallow exceptions from callbacks to prevent broker failure
                }
            }
        }

        /// <summary>
        /// Invokes a callback, marshalling to the UI thread if a UI context is available.
        /// </summary>
        private static void InvokeCallback(Action<int, string, object> callback, int deviceId, string name, object data)
        {
            Control uiContext;
            lock (_lock)
            {
                uiContext = _uiContext;
            }

            if (uiContext != null && uiContext.InvokeRequired)
            {
                try
                {
                    uiContext.BeginInvoke(callback, deviceId, name, data);
                }
                catch (ObjectDisposedException)
                {
                    // Control has been disposed, ignore
                }
                catch (InvalidOperationException)
                {
                    // Handle not created yet, invoke directly
                    callback(deviceId, name, data);
                }
            }
            else
            {
                callback(deviceId, name, data);
            }
        }

        /// <summary>
        /// Gets a value from the broker.
        /// </summary>
        /// <typeparam name="T">The expected type of the value.</typeparam>
        /// <param name="deviceId">The device ID.</param>
        /// <param name="name">The name/key of the data.</param>
        /// <param name="defaultValue">The default value to return if not found or type mismatch.</param>
        /// <returns>The stored value or the default value.</returns>
        public static T GetValue<T>(int deviceId, string name, T defaultValue = default)
        {
            lock (_lock)
            {
                var key = new DataKey(deviceId, name);
                if (_dataStore.TryGetValue(key, out object value))
                {
                    if (value is T typedValue)
                    {
                        return typedValue;
                    }
                    // Try conversion for compatible types
                    try
                    {
                        return (T)Convert.ChangeType(value, typeof(T));
                    }
                    catch (Exception)
                    {
                        return defaultValue;
                    }
                }

                // For device 0, try loading from registry if not in memory
                if (deviceId == 0 && _registryHelper != null)
                {
                    if (typeof(T) == typeof(int) || typeof(T) == typeof(int?))
                    {
                        int? regValue = _registryHelper.ReadInt(name, null);
                        if (regValue.HasValue)
                        {
                            _dataStore[key] = regValue.Value;
                            if (defaultValue is int)
                            {
                                return (T)(object)regValue.Value;
                            }
                        }
                    }
                    else if (typeof(T) == typeof(string))
                    {
                        string regValue = _registryHelper.ReadString(name, null);
                        if (regValue != null)
                        {
                            // Check if this is a serialized JSON value (shouldn't return as plain string)
                            if (!regValue.StartsWith("~~JSON:"))
                            {
                                _dataStore[key] = regValue;
                                return (T)(object)regValue;
                            }
                        }
                    }
                    else if (typeof(T) == typeof(bool) || typeof(T) == typeof(bool?))
                    {
                        // Check if value exists in registry by trying to read it
                        // We use a sentinel approach: read with a default, then read with opposite default
                        bool val1 = _registryHelper.ReadBool(name, false);
                        bool val2 = _registryHelper.ReadBool(name, true);
                        if (val1 == val2)
                        {
                            // Value exists in registry (both reads returned the same value)
                            _dataStore[key] = val1;
                            return (T)(object)val1;
                        }
                    }
                    else
                    {
                        // Try to load serialized JSON for complex types
                        string regValue = _registryHelper.ReadString(name, null);
                        if (regValue != null && regValue.StartsWith("~~JSON:"))
                        {
                            try
                            {
                                // Parse: "~~JSON:TypeName:actual_json"
                                int firstColon = regValue.IndexOf(':', 7); // Start after "~~JSON:"
                                if (firstColon > 0)
                                {
                                    string json = regValue.Substring(firstColon + 1);
                                    T deserializedValue = JsonSerializer.Deserialize<T>(json);
                                    if (deserializedValue != null)
                                    {
                                        _dataStore[key] = deserializedValue;
                                        return deserializedValue;
                                    }
                                }
                            }
                            catch (JsonException)
                            {
                                // Failed to deserialize, return default
                            }
                        }
                    }
                }

                return defaultValue;
            }
        }

        /// <summary>
        /// Gets a value from the broker as an object.
        /// </summary>
        /// <param name="deviceId">The device ID.</param>
        /// <param name="name">The name/key of the data.</param>
        /// <param name="defaultValue">The default value to return if not found.</param>
        /// <returns>The stored value or the default value.</returns>
        public static object GetValue(int deviceId, string name, object defaultValue = null)
        {
            lock (_lock)
            {
                var key = new DataKey(deviceId, name);
                if (_dataStore.TryGetValue(key, out object value))
                {
                    return value;
                }
                return defaultValue;
            }
        }

        /// <summary>
        /// Checks if a value exists in the broker.
        /// </summary>
        /// <param name="deviceId">The device ID.</param>
        /// <param name="name">The name/key of the data.</param>
        /// <returns>True if the value exists, false otherwise.</returns>
        public static bool HasValue(int deviceId, string name)
        {
            lock (_lock)
            {
                var key = new DataKey(deviceId, name);
                return _dataStore.ContainsKey(key);
            }
        }

        /// <summary>
        /// Removes a value from the broker.
        /// </summary>
        /// <param name="deviceId">The device ID.</param>
        /// <param name="name">The name/key of the data.</param>
        /// <returns>True if the value was removed, false if it didn't exist.</returns>
        public static bool RemoveValue(int deviceId, string name)
        {
            lock (_lock)
            {
                var key = new DataKey(deviceId, name);
                bool removed = _dataStore.Remove(key);

                // Also remove from registry if device 0
                if (deviceId == 0 && _registryHelper != null)
                {
                    _registryHelper.DeleteValue(name);
                }

                return removed;
            }
        }

        /// <summary>
        /// Subscribes to data changes. Called internally by DataBrokerClient.
        /// </summary>
        internal static void Subscribe(DataBrokerClient client, int deviceId, string name, Action<int, string, object> callback)
        {
            lock (_lock)
            {
                _subscriptions.Add(new Subscription
                {
                    Client = client,
                    DeviceId = deviceId,
                    Name = name,
                    Callback = callback
                });
            }
        }

        /// <summary>
        /// Unsubscribes all subscriptions for a client. Called internally by DataBrokerClient.
        /// </summary>
        internal static void Unsubscribe(DataBrokerClient client)
        {
            lock (_lock)
            {
                _subscriptions.RemoveAll(s => s.Client == client);
            }
        }

        /// <summary>
        /// Unsubscribes a specific subscription for a client.
        /// </summary>
        internal static void Unsubscribe(DataBrokerClient client, int deviceId, string name)
        {
            lock (_lock)
            {
                _subscriptions.RemoveAll(s => s.Client == client && s.DeviceId == deviceId && s.Name == name);
            }
        }

        /// <summary>
        /// Gets all stored values for a specific device.
        /// </summary>
        /// <param name="deviceId">The device ID.</param>
        /// <returns>A dictionary of name/value pairs for the device.</returns>
        public static Dictionary<string, object> GetDeviceValues(int deviceId)
        {
            lock (_lock)
            {
                var result = new Dictionary<string, object>();
                foreach (var kvp in _dataStore)
                {
                    if (kvp.Key.DeviceId == deviceId)
                    {
                        result[kvp.Key.Name] = kvp.Value;
                    }
                }
                return result;
            }
        }

        /// <summary>
        /// Clears all stored data for a specific device.
        /// </summary>
        /// <param name="deviceId">The device ID.</param>
        public static void ClearDevice(int deviceId)
        {
            lock (_lock)
            {
                var keysToRemove = new List<DataKey>();
                foreach (var key in _dataStore.Keys)
                {
                    if (key.DeviceId == deviceId)
                    {
                        keysToRemove.Add(key);
                    }
                }
                foreach (var key in keysToRemove)
                {
                    _dataStore.Remove(key);
                }
            }
        }

        /// <summary>
        /// Deletes all data for a specific device, dispatching null values to all subscribers
        /// before removing the data from storage.
        /// </summary>
        /// <param name="deviceId">The device ID to delete.</param>
        public static void DeleteDevice(int deviceId)
        {
            List<DataKey> keysToRemove;

            lock (_lock)
            {
                keysToRemove = new List<DataKey>();
                foreach (var key in _dataStore.Keys)
                {
                    if (key.DeviceId == deviceId)
                    {
                        keysToRemove.Add(key);
                    }
                }
            }

            // Dispatch null for each key to notify subscribers
            foreach (var key in keysToRemove)
            {
                Dispatch(key.DeviceId, key.Name, null, store: false);
            }

            // Remove all values for the device from storage
            lock (_lock)
            {
                foreach (var key in keysToRemove)
                {
                    _dataStore.Remove(key);
                }
            }
        }

        /// <summary>
        /// Clears all stored data and subscriptions. Use with caution.
        /// </summary>
        public static void Reset()
        {
            lock (_lock)
            {
                _dataStore.Clear();
                _subscriptions.Clear();
            }
        }

        /// <summary>
        /// Adds a data handler to the broker. Data handlers are global objects that process data from the broker.
        /// Dispatches a "DataHandlerAdded" event on device 0 with the handler name.
        /// </summary>
        /// <param name="name">A unique name for the data handler.</param>
        /// <param name="handler">The handler object instance.</param>
        /// <returns>True if added successfully, false if a handler with that name already exists.</returns>
        public static bool AddDataHandler(string name, object handler)
        {
            if (string.IsNullOrEmpty(name)) throw new ArgumentNullException(nameof(name));
            if (handler == null) throw new ArgumentNullException(nameof(handler));

            bool added = false;
            lock (_lock)
            {
                if (!_dataHandlers.ContainsKey(name))
                {
                    _dataHandlers[name] = handler;
                    added = true;
                }
            }

            // Dispatch event outside the lock to prevent deadlocks
            if (added)
            {
                Dispatch(0, "DataHandlerAdded", name, store: false);
            }

            return added;
        }

        /// <summary>
        /// Gets a data handler by name.
        /// </summary>
        /// <param name="name">The name of the data handler.</param>
        /// <returns>The handler object, or null if not found.</returns>
        public static object GetDataHandler(string name)
        {
            if (string.IsNullOrEmpty(name)) return null;

            lock (_lock)
            {
                if (_dataHandlers.TryGetValue(name, out object handler))
                {
                    return handler;
                }
                return null;
            }
        }

        /// <summary>
        /// Gets a data handler by name with type casting.
        /// </summary>
        /// <typeparam name="T">The expected type of the handler.</typeparam>
        /// <param name="name">The name of the data handler.</param>
        /// <returns>The handler object cast to type T, or default if not found or type mismatch.</returns>
        public static T GetDataHandler<T>(string name) where T : class
        {
            return GetDataHandler(name) as T;
        }

        /// <summary>
        /// Removes a data handler by name. If the handler implements IDisposable, Dispose() is called.
        /// Dispatches a "DataHandlerRemoved" event on device 0 with the handler name.
        /// </summary>
        /// <param name="name">The name of the data handler to remove.</param>
        /// <returns>True if removed, false if not found.</returns>
        public static bool RemoveDataHandler(string name)
        {
            if (string.IsNullOrEmpty(name)) return false;

            object handler = null;
            lock (_lock)
            {
                if (_dataHandlers.TryGetValue(name, out handler))
                {
                    _dataHandlers.Remove(name);
                }
            }

            // Dispose outside the lock to prevent deadlocks
            if (handler != null)
            {
                if (handler is IDisposable disposable)
                {
                    try
                    {
                        disposable.Dispose();
                    }
                    catch (Exception)
                    {
                        // Swallow disposal exceptions
                    }
                }

                // Dispatch event after disposal
                Dispatch(0, "DataHandlerRemoved", name, store: false);
                return true;
            }
            return false;
        }

        /// <summary>
        /// Checks if a data handler with the specified name exists.
        /// </summary>
        /// <param name="name">The name of the data handler.</param>
        /// <returns>True if the handler exists, false otherwise.</returns>
        public static bool HasDataHandler(string name)
        {
            if (string.IsNullOrEmpty(name)) return false;

            lock (_lock)
            {
                return _dataHandlers.ContainsKey(name);
            }
        }

        /// <summary>
        /// Removes all data handlers. Dispose() is called on each handler that implements IDisposable.
        /// </summary>
        public static void RemoveAllDataHandlers()
        {
            List<object> handlers;
            lock (_lock)
            {
                handlers = new List<object>(_dataHandlers.Values);
                _dataHandlers.Clear();
            }

            // Dispose outside the lock
            foreach (var handler in handlers)
            {
                if (handler is IDisposable disposable)
                {
                    try
                    {
                        disposable.Dispose();
                    }
                    catch (Exception)
                    {
                        // Swallow disposal exceptions
                    }
                }
            }
        }

        /// <summary>
        /// Gets a friendly type name for serialization purposes.
        /// </summary>
        private static string GetSerializableTypeName(Type type)
        {
            if (type.IsGenericType)
            {
                var genericTypeDef = type.GetGenericTypeDefinition();
                var genericArgs = type.GetGenericArguments();
                string baseName = genericTypeDef.Name;
                int backtickIndex = baseName.IndexOf('`');
                if (backtickIndex > 0)
                {
                    baseName = baseName.Substring(0, backtickIndex);
                }
                string argNames = string.Join(",", Array.ConvertAll(genericArgs, t => t.Name));
                return $"{baseName}<{argNames}>";
            }
            return type.Name;
        }
    }
}
