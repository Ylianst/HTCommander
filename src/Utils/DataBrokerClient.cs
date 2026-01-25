/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// A client for the DataBroker that manages subscriptions for a specific component.
    /// When disposed, all subscriptions are automatically removed.
    /// </summary>
    public class DataBrokerClient : IDisposable
    {
        private bool _disposed = false;

        /// <summary>
        /// Creates a new DataBrokerClient instance.
        /// </summary>
        public DataBrokerClient()
        {
        }

        /// <summary>
        /// Subscribes to data changes for a specific device ID and name.
        /// </summary>
        /// <param name="deviceId">The device ID to subscribe to, or DataBroker.AllDevices for all devices.</param>
        /// <param name="name">The name/key to subscribe to, or DataBroker.AllNames for all names.</param>
        /// <param name="callback">The callback to invoke when data changes. Parameters are (deviceId, name, data).</param>
        public void Subscribe(int deviceId, string name, Action<int, string, object> callback)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(DataBrokerClient));
            if (callback == null) throw new ArgumentNullException(nameof(callback));
            if (name == null) throw new ArgumentNullException(nameof(name));

            DataBroker.Subscribe(this, deviceId, name, callback);
        }

        /// <summary>
        /// Subscribes to data changes for a specific device ID and multiple names.
        /// </summary>
        /// <param name="deviceId">The device ID to subscribe to, or DataBroker.AllDevices for all devices.</param>
        /// <param name="names">The names/keys to subscribe to.</param>
        /// <param name="callback">The callback to invoke when data changes. Parameters are (deviceId, name, data).</param>
        public void Subscribe(int deviceId, string[] names, Action<int, string, object> callback)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(DataBrokerClient));
            if (callback == null) throw new ArgumentNullException(nameof(callback));
            if (names == null) throw new ArgumentNullException(nameof(names));

            foreach (var name in names)
            {
                if (name != null)
                {
                    DataBroker.Subscribe(this, deviceId, name, callback);
                }
            }
        }

        /// <summary>
        /// Subscribes to all data changes for a specific device ID.
        /// </summary>
        /// <param name="deviceId">The device ID to subscribe to, or DataBroker.AllDevices for all devices.</param>
        /// <param name="callback">The callback to invoke when data changes. Parameters are (deviceId, name, data).</param>
        public void SubscribeAll(int deviceId, Action<int, string, object> callback)
        {
            Subscribe(deviceId, DataBroker.AllNames, callback);
        }

        /// <summary>
        /// Subscribes to all data changes across all devices.
        /// </summary>
        /// <param name="callback">The callback to invoke when data changes. Parameters are (deviceId, name, data).</param>
        public void SubscribeAll(Action<int, string, object> callback)
        {
            Subscribe(DataBroker.AllDevices, DataBroker.AllNames, callback);
        }

        /// <summary>
        /// Unsubscribes from a specific device ID and name.
        /// </summary>
        /// <param name="deviceId">The device ID to unsubscribe from.</param>
        /// <param name="name">The name/key to unsubscribe from.</param>
        public void Unsubscribe(int deviceId, string name)
        {
            if (_disposed) return;
            DataBroker.Unsubscribe(this, deviceId, name);
        }

        /// <summary>
        /// Unsubscribes from all subscriptions for this client.
        /// </summary>
        public void UnsubscribeAll()
        {
            if (_disposed) return;
            DataBroker.Unsubscribe(this);
        }

        /// <summary>
        /// Dispatches data to the broker.
        /// </summary>
        /// <param name="deviceId">The device ID (use 0 for values that should persist to registry).</param>
        /// <param name="name">The name/key of the data.</param>
        /// <param name="data">The data value.</param>
        /// <param name="store">If true, the value is stored in the broker; if false, only broadcast.</param>
        public void Dispatch(int deviceId, string name, object data, bool store = true)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(DataBrokerClient));
            DataBroker.Dispatch(deviceId, name, data, store);
        }

        /// <summary>
        /// Gets a value from the broker.
        /// </summary>
        /// <typeparam name="T">The expected type of the value.</typeparam>
        /// <param name="deviceId">The device ID.</param>
        /// <param name="name">The name/key of the data.</param>
        /// <param name="defaultValue">The default value to return if not found or type mismatch.</param>
        /// <returns>The stored value or the default value.</returns>
        public T GetValue<T>(int deviceId, string name, T defaultValue = default)
        {
            return DataBroker.GetValue<T>(deviceId, name, defaultValue);
        }

        /// <summary>
        /// Gets a value from the broker as an object.
        /// </summary>
        /// <param name="deviceId">The device ID.</param>
        /// <param name="name">The name/key of the data.</param>
        /// <param name="defaultValue">The default value to return if not found.</param>
        /// <returns>The stored value or the default value.</returns>
        public object GetValue(int deviceId, string name, object defaultValue = null)
        {
            return DataBroker.GetValue(deviceId, name, defaultValue);
        }

        /// <summary>
        /// Checks if a value exists in the broker.
        /// </summary>
        /// <param name="deviceId">The device ID.</param>
        /// <param name="name">The name/key of the data.</param>
        /// <returns>True if the value exists, false otherwise.</returns>
        public bool HasValue(int deviceId, string name)
        {
            return DataBroker.HasValue(deviceId, name);
        }

        /// <summary>
        /// Publishes an informational log message to device 1 under "LogInfo".
        /// </summary>
        /// <param name="msg">The log message.</param>
        public void LogInfo(string msg)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(DataBrokerClient));
            DataBroker.Dispatch(1, "LogInfo", msg, store: false);
        }

        /// <summary>
        /// Publishes an error log message to device 1 under "LogError".
        /// </summary>
        /// <param name="msg">The error message.</param>
        public void LogError(string msg)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(DataBrokerClient));
            DataBroker.Dispatch(1, "LogError", msg, store: false);
        }

        /// <summary>
        /// Disposes the client and unsubscribes from all data changes.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Disposes the client and unsubscribes from all data changes.
        /// </summary>
        /// <param name="disposing">True if called from Dispose(), false if called from finalizer.</param>
        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    // Unsubscribe from all data changes
                    DataBroker.Unsubscribe(this);
                }
                _disposed = true;
            }
        }

        /// <summary>
        /// Finalizer to ensure cleanup if Dispose is not called.
        /// </summary>
        ~DataBrokerClient()
        {
            Dispose(false);
        }
    }
}
