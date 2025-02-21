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
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
#if !__MonoCS__
using System.Collections.Concurrent;
using Windows.Devices.Enumeration;
using InTheHand.Bluetooth;
#endif

namespace HTCommander
{
    public class RadioBluetoothWin
    {
        private Radio parent;

#if !__MonoCS__
        // Bluetooth Write Queue
        private class DeviceWriteData { public int expectResponse; public byte[] data; public DeviceWriteData(int expectResponse, byte[] data) { this.expectResponse = expectResponse; this.data = data; } }
        private ConcurrentQueue<DeviceWriteData> _writeQueue = new ConcurrentQueue<DeviceWriteData>();
        private SemaphoreSlim _writeSemaphore = new SemaphoreSlim(1, 1); // To ensure only one write is active
        private bool _isProcessing = false;
        private int _expectedResponse = 0;

        // Define the target device name and guids
        private static readonly string[] TargetDeviceNames = { "UV-PRO", "GA-5WB", "VR-N76", "VR-N7500" };
        private readonly Guid RADIO_SERVICE_UUID = new Guid("00001100-d102-11e1-9b23-00025b00a5a5");
        private readonly Guid RADIO_WRITE_UUID = new Guid("00001101-d102-11e1-9b23-00025b00a5a5");
        private readonly Guid RADIO_INDICATE_UUID = new Guid("00001102-d102-11e1-9b23-00025b00a5a5");

        private RemoteGattServer gatt = null;
        private GattCharacteristic writeCharacteristic = null;
        private GattCharacteristic indicateCharacteristic = null;
#endif

        public string selectedDevice;

        public RadioBluetoothWin(Radio parent)
        {
            this.parent = parent;
        }

        public void Disconnect()
        {
#if !__MonoCS__
            writeCharacteristic = null;
            indicateCharacteristic = null;
            _writeQueue = new ConcurrentQueue<DeviceWriteData>();
            _writeSemaphore = new SemaphoreSlim(1, 1);
            _isProcessing = false;
            _expectedResponse = 0;
            if (gatt != null) { gatt.Disconnect(); gatt = null; }
#endif
        }

        public static async Task<bool> CheckBluetooth()
        {
#if !__MonoCS__
            bool bluetoothAvailable = false;
            try { bluetoothAvailable = await Bluetooth.GetAvailabilityAsync(); } catch (Exception) { }
            return bluetoothAvailable;
#else
            return false;
#endif
        }
        public static async Task<string[]> GetDeviceNames()
        {
            List<string> r = new List<string>();
#if !__MonoCS__
            // Find the devices by name
            var devices = await DeviceInformation.FindAllAsync();
            foreach (var deviceInfo in devices) { if (!r.Contains(deviceInfo.Name)) { r.Add(deviceInfo.Name); } }
            r.Sort();
#endif
            return r.ToArray();
        }

        public static async Task<Radio.CompatibleDevice[]> FindCompatibleDevices()
        {
            // Find the devices by name
            List<Radio.CompatibleDevice> compatibleDevices = new List<Radio.CompatibleDevice>();
#if !__MonoCS__
            var devices = await DeviceInformation.FindAllAsync();
            List<string> macs = new List<string>();
            foreach (var deviceInfo in devices)
            {
                if (TargetDeviceNames.Contains(deviceInfo.Name))
                {
                    if (deviceInfo.Id.StartsWith("\\\\?\\BTHLE#Dev_"))
                    {
                        string mac = deviceInfo.Id.Substring(14, 12).ToUpper();
                        if (!macs.Contains(mac))
                        {
                            macs.Add(mac);
                            compatibleDevices.Add(new Radio.CompatibleDevice(deviceInfo.Name, mac));
                        }
                    }
                    else if (deviceInfo.Id.StartsWith("\\\\?\\BTHENUM#Dev_"))
                    {
                        int i = deviceInfo.Id.IndexOf("BluetoothDevice_");
                        if (i > 0)
                        {
                            string mac = deviceInfo.Id.Substring(i + 16, 12).ToUpper();
                            if (!macs.Contains(mac))
                            {
                                macs.Add(mac);
                                compatibleDevices.Add(new Radio.CompatibleDevice(deviceInfo.Name, mac));
                            }
                        }
                    }
                }
            }
#endif
            return compatibleDevices.ToArray();
        }

        public async Task<bool> Connect(string macAddress)
        {
#if !__MonoCS__
            // Regular expression to capture the 12-character MAC address
            var bluetoothDevice = await BluetoothDevice.FromIdAsync(macAddress);
            if (bluetoothDevice == null)
            {
                parent.Disconnect($"Unable to connect.", Radio.RadioState.AccessDenied);
                return false;
            }
            selectedDevice = $"{bluetoothDevice.Name} ({bluetoothDevice.Id})";
            parent.Debug($"Selected device: {bluetoothDevice.Name} - {bluetoothDevice.Id}");

            // Connect to the device
            gatt = bluetoothDevice.Gatt;
            parent.Debug("Connecting to radio...");
            try { await gatt.ConnectAsync(); } catch (Exception) { parent.Disconnect($"Unable to connect.", Radio.RadioState.UnableToConnect); return false; }
            //gatt.AutoConnect = true;
            if (gatt.IsConnected == false) { parent.Disconnect($"Gatt not connected.", Radio.RadioState.UnableToConnect); return false; }

            parent.Debug("Getting radio service...");
            var service = await gatt.GetPrimaryServiceAsync(RADIO_SERVICE_UUID);
            if (service == null) { parent.Disconnect($"Radio service not found.", Radio.RadioState.UnableToConnect); return false; }

            // Get characteristics
            parent.Debug("Getting radio characteristic...");
            writeCharacteristic = await service.GetCharacteristicAsync(RADIO_WRITE_UUID);
            if (writeCharacteristic == null) { parent.Disconnect($"Unable to get write characteristic.", Radio.RadioState.UnableToConnect); return false; }
            indicateCharacteristic = await service.GetCharacteristicAsync(RADIO_INDICATE_UUID);
            if (indicateCharacteristic == null) { parent.Disconnect($"Unable to get read/notify characteristic.", Radio.RadioState.UnableToConnect); return false; }

            // Receive command responses
            parent.Debug("Getting radio information...");
            indicateCharacteristic.CharacteristicValueChanged += Characteristic_CharacteristicValueChanged;

            return true;
#else
            return false;
#endif
        }

        // private void ReceivedData(RadioBluetooth sender, Exception error, byte[] value)

        public delegate void ReceivedDataHandler(RadioBluetoothWin sender, Exception error, byte[] value);
        public event ReceivedDataHandler ReceivedData;

#if !__MonoCS__
        private void Characteristic_CharacteristicValueChanged(object sender, GattCharacteristicValueChangedEventArgs e)
        {
            Task.Run(() =>
            {
                if (e.Value != null)
                {
                    if ((_expectedResponse == -1) || ((_expectedResponse | 0x8000) == Utils.GetInt(e.Value, 0)))
                    {
                        _expectedResponse = 0;
                    }
                }

                if (ReceivedData != null) { ReceivedData(this, e.Error, e.Value); }
            });
        }
#endif

        // Method to queue a write operation
        public void EnqueueWrite(int expectedResponse, byte[] cmdData)
        {
#if !__MonoCS__
            _writeQueue.Enqueue(new DeviceWriteData(expectedResponse, cmdData));
            ProcessQueue(); // Start processing the queue if it's not already running
#endif
        }

        // Processes the queue
        private async void ProcessQueue()
        {
#if !__MonoCS__
            if (_isProcessing) return; // Avoid multiple threads starting processing
            _isProcessing = true;

            try
            {
                // Execute the write on a separate thread to avoid blocking
                await Task.Run(async () =>
                {
                    while (_writeQueue.TryDequeue(out DeviceWriteData cmdData))
                    {
                        try
                        {
                            if (writeCharacteristic != null)
                            {
                                if (parent.PacketTrace) { parent.Debug("<--" + _writeQueue.Count + "-- " + Utils.BytesToHex(cmdData.data)); }
                                else { Program.BlockBoxEvent("<--" + _writeQueue.Count + "-- " + Utils.BytesToHex(cmdData.data)); }
                                _expectedResponse = cmdData.expectResponse;
                                await Task.Run(async () => { await writeCharacteristic.WriteValueWithResponseAsync(cmdData.data); });
                                if (_expectedResponse == -2) { _expectedResponse = 0; }
                            }
                        }
                        catch (Exception ex)
                        {
                            if (ex.HResult == -2140864497)
                            {
                                parent.Disconnect("Access denied. Please re-pair the device.", Radio.RadioState.AccessDenied);
                            }
                            else
                            {
                                parent.Disconnect("Unable to send command to device.", Radio.RadioState.Disconnected);
                            }
                        }
                    }
                });
            }
            finally
            {
                _isProcessing = false; // Mark as not processing when the queue is empty
            }
#endif
        }

    }
}
