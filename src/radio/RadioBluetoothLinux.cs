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

#if __MonoCS__

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Tmds.DBus;

namespace HTCommander
{
    public class RadioBluetooth
    {
        private const string BlueZBusName = "org.bluez";
        private const string AdapterPath = "/org/bluez/hci0";
        private const string DeviceInterface = "org.bluez.Device1";
        private const string AdapterInterface = "org.bluez.Adapter1";

        private Radio parent;
        private string selectedDevice;
        private Connection dbusConnection;
        private IAdapter1 adapter;

        public RadioBluetooth(Radio parent)
        {
            this.parent = parent;
        }

        public void Disconnect()
        {
            selectedDevice = null;
        }

        public static async Task<bool> CheckBluetooth()
        {
            try
            {
                using var connection = Connection.System;
                var obj = connection.CreateProxy<IAdapter1>(BlueZBusName, AdapterPath);
                await obj.SetPoweredAsync(true);
                return true;
            }
            catch
            {
                return false;
            }
        }

        public static async Task<string[]> GetDeviceNames()
        {
            List<string> deviceNames = new List<string>();

            using var connection = Connection.System;
            var manager = connection.CreateProxy<IObjectManager>(BlueZBusName, "/");
            var objects = await manager.GetManagedObjectsAsync();

            foreach (var path in objects.Keys)
            {
                if (objects[path].ContainsKey(DeviceInterface))
                {
                    var device = connection.CreateProxy<IDevice1>(BlueZBusName, path);
                    string name = await device.GetNameAsync();
                    deviceNames.Add(name);
                }
            }
            return deviceNames.OrderBy(n => n).ToArray();
        }

        public async Task<bool> Connect(string macAddress)
        {
            dbusConnection = Connection.System;
            adapter = dbusConnection.CreateProxy<IAdapter1>(BlueZBusName, AdapterPath);

            var manager = dbusConnection.CreateProxy<IObjectManager>(BlueZBusName, "/");
            var objects = await manager.GetManagedObjectsAsync();

            foreach (var path in objects.Keys)
            {
                if (objects[path].ContainsKey(DeviceInterface))
                {
                    var device = dbusConnection.CreateProxy<IDevice1>(BlueZBusName, path);
                    string address = await device.GetAddressAsync();

                    if (address.Replace(":", "").ToUpper() == macAddress.ToUpper())
                    {
                        await device.ConnectAsync();
                        selectedDevice = await device.GetNameAsync();
                        return true;
                    }
                }
            }

            parent.Disconnect($"Unable to connect.", Radio.RadioState.UnableToConnect);
            return false;
        }
    }

    [DBusInterface("org.bluez.Adapter1")]
    public interface IAdapter1 : IDBusObject
    {
        Task SetPoweredAsync(bool value);
    }

    [DBusInterface("org.freedesktop.DBus.ObjectManager")]
    public interface IObjectManager : IDBusObject
    {
        Task<IDictionary<ObjectPath, IDictionary<string, IDictionary<string, object>>>> GetManagedObjectsAsync();
    }

    [DBusInterface("org.bluez.Device1")]
    public interface IDevice1 : IDBusObject
    {
        Task<string> GetAddressAsync();
        Task<string> GetNameAsync();
        Task ConnectAsync();
    }
}

#endif