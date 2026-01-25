/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Rfcomm;
using Windows.Devices.Enumeration;
using Windows.Networking.Sockets;

namespace HTCommander
{
    public class RadioBluetoothWin
    {
        private Radio parent;
        private bool running = false;
        private StreamSocket bluetoothSocket = null;
        private RfcommDeviceService rfcommService = null;
        private Stream inputStream = null;
        private Stream outputStream = null;
        private CancellationTokenSource connectionCts = null;
        private readonly object connectionLock = new object();
        private Task connectionTask = null;
        private bool isConnecting = false;

        public delegate void ConnectedEventHandler();
        public event ConnectedEventHandler OnConnected;
        public delegate void ReceivedDataHandler(RadioBluetoothWin sender, Exception error, byte[] value);
        public event ReceivedDataHandler ReceivedData;

        private static readonly string[] TargetDeviceNames = { "UV-PRO", "UV-50PRO", "GA-5WB", "VR-N75", "VR-N76", "VR-N7500", "VR-N7600" };

        public RadioBluetoothWin(Radio parent) { this.parent = parent; }

        private void Debug(string msg) { parent.Debug("Transport: " + msg); }

        public void Disconnect()
        {
            lock (connectionLock)
            {
                if (running == false && connectionTask == null) return;
                running = false;
                
                // Cancel the connection loop
                try { connectionCts?.Cancel(); } catch (Exception) { }
            }
            
            // Wait for the connection task to finish (with timeout)
            if (connectionTask != null)
            {
                try { connectionTask.Wait(TimeSpan.FromSeconds(3)); } catch (Exception) { }
            }
            
            lock (connectionLock)
            {
                // Dispose resources in correct order
                // First close streams, then socket, then service
                try { inputStream?.Close(); } catch (Exception) { }
                try { inputStream?.Dispose(); } catch (Exception) { }
                inputStream = null;
                
                try { outputStream?.Close(); } catch (Exception) { }
                try { outputStream?.Dispose(); } catch (Exception) { }
                outputStream = null;
                
                try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                bluetoothSocket = null;
                
                try { rfcommService?.Dispose(); } catch (Exception) { }
                rfcommService = null;
                
                try { connectionCts?.Dispose(); } catch (Exception) { }
                connectionCts = null;
                connectionTask = null;
            }
            
            // Give the OS time to release the socket
            Thread.Sleep(100);
        }

        public static async Task<bool> CheckBluetoothAsync()
        {
            try
            {
                var adapter = await BluetoothAdapter.GetDefaultAsync();
                return adapter != null && adapter.IsLowEnergySupported || adapter.IsCentralRoleSupported;
            }
            catch (Exception) { return false; }
        }

        public static bool CheckBluetooth()
        {
            try
            {
                return Task.Run(() => CheckBluetoothAsync()).GetAwaiter().GetResult();
            }
            catch (Exception) { return false; }
        }

        public static async Task<string[]> GetDeviceNames()
        {
            List<string> r = new List<string>();
            var selector = BluetoothDevice.GetDeviceSelector();
            var devices = await DeviceInformation.FindAllAsync(selector);
            foreach (var deviceInfo in devices)
            {
                if (!r.Contains(deviceInfo.Name)) { r.Add(deviceInfo.Name); }
            }
            r.Sort();
            return r.ToArray();
        }

        public static async Task<Radio.CompatibleDevice[]> FindCompatibleDevices()
        {
            List<Radio.CompatibleDevice> compatibleDevices = new List<Radio.CompatibleDevice>();
            var selector = BluetoothDevice.GetDeviceSelector();
            var devices = await DeviceInformation.FindAllAsync(selector);
            List<string> macs = new List<string>();

            foreach (var deviceInfo in devices)
            {
                if (!TargetDeviceNames.Contains(deviceInfo.Name)) continue;
                string mac = null;

                // Parse MAC from format: "Bluetooth#Bluetooth[MAC1]-[MAC2]"
                if (deviceInfo.Id.StartsWith("Bluetooth#Bluetooth"))
                {
                    int dashIdx = deviceInfo.Id.IndexOf('-');
                    if (dashIdx > 0 && dashIdx < deviceInfo.Id.Length - 1)
                    {
                        string macWithColons = deviceInfo.Id.Substring(dashIdx + 1);
                        mac = macWithColons.Replace(":", "").ToUpper();
                    }
                }

                if (mac != null && !macs.Contains(mac))
                {
                    macs.Add(mac);
                    compatibleDevices.Add(new Radio.CompatibleDevice(deviceInfo.Name, mac));
                }
            }
            return compatibleDevices.ToArray();
        }

        public bool Connect()
        {
            lock (connectionLock)
            {
                if (running || isConnecting) return false;
                isConnecting = true;
            }
            connectionTask = Task.Run(() => StartAsync());
            return true;
        }

        public void EnqueueWrite(int expectedResponse, byte[] cmdData)
        {
            if (!running || outputStream == null) return;
            byte[] bytes = GaiaEncode(cmdData);
            try
            {
                outputStream.Write(bytes, 0, bytes.Length);
                outputStream.Flush();
            }
            catch (Exception ex) { Debug("Error sending: " + ex.Message); }
        }

        // Decode GAIA frame, returns bytes consumed or 0 if incomplete, -1 on error
        private static int GaiaDecode(byte[] data, int index, int len, out byte[] cmd)
        {
            cmd = null;
            if (len < 8) return 0;
            if (data[index] != 0xFF || data[index + 1] != 0x01) return -1;

            byte payloadLen = data[index + 3];
            int hasChecksum = data[index + 2] & 1;
            int totalLen = payloadLen + 8 + hasChecksum;
            if (totalLen > len) return 0;

            cmd = new byte[4 + payloadLen];
            Array.Copy(data, index + 4, cmd, 0, cmd.Length);
            return totalLen;
        }

        // Encode command into GAIA frame
        private static byte[] GaiaEncode(byte[] cmd)
        {
            byte[] bytes = new byte[cmd.Length + 4];
            bytes[0] = 0xFF;
            bytes[1] = 0x01;
            bytes[3] = (byte)(cmd.Length - 4);
            Array.Copy(cmd, 0, bytes, 4, cmd.Length);
            return bytes;
        }

        private async void StartAsync()
        {
            CancellationToken cancellationToken;
            
            lock (connectionLock)
            {
                connectionCts = new CancellationTokenSource();
                cancellationToken = connectionCts.Token;
            }
            
            BluetoothDevice btDevice = null;

            // Connect with retries
            int retry = 5;
            while (retry > 0)
            {
                try
                {
                    Debug("Connecting...");

                    // Convert MAC address to ulong for WinRT API
                    ulong btAddress = Convert.ToUInt64(parent.MacAddress.Replace(":", "").Replace("-", ""), 16);
                    btDevice = await BluetoothDevice.FromBluetoothAddressAsync(btAddress);

                    if (btDevice == null)
                    {
                        Debug("Could not find Bluetooth device with address: " + parent.MacAddress);
                        retry--;
                        continue;
                    }

                    Debug($"Found device: {btDevice.Name}");

                    // Get RFCOMM services from the device
                    var rfcommServices = await btDevice.GetRfcommServicesForIdAsync(RfcommServiceId.SerialPort);

                    if (rfcommServices.Services.Count == 0)
                    {
                        // Try getting all services if SerialPort isn't found
                        var allServices = await btDevice.GetRfcommServicesAsync();
                        if (allServices.Services.Count > 0)
                        {
                            rfcommService = allServices.Services[0];
                            Debug($"Using first available RFCOMM service: {rfcommService.ServiceId.Uuid}");
                        }
                        else
                        {
                            Debug("No RFCOMM services found on device");
                            retry--;
                            continue;
                        }
                    }
                    else
                    {
                        rfcommService = rfcommServices.Services[0];
                        Debug($"Using SerialPort RFCOMM service");
                    }

                    // Connect to the RFCOMM service
                    bluetoothSocket = new StreamSocket();
                    await bluetoothSocket.ConnectAsync(
                        rfcommService.ConnectionHostName,
                        rfcommService.ConnectionServiceName,
                        SocketProtectionLevel.BluetoothEncryptionAllowNullAuthentication);

                    retry = -2;
                }
                catch (Exception ex)
                {
                    retry--;
                    Debug("Connect failed: " + ex.ToString());
                    lock (connectionLock)
                    {
                        try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                        bluetoothSocket = null;
                        try { rfcommService?.Dispose(); } catch (Exception) { }
                        rfcommService = null;
                    }
                }
            }

            if (retry != -2)
            {
                lock (connectionLock)
                {
                    isConnecting = false;
                }
                parent.Disconnect("Unable to connect", Radio.RadioState.UnableToConnect);
                return;
            }

            Debug("Connected.");

            try
            {
                byte[] accumulator = new byte[4096];
                int accumulatorPtr = 0, accumulatorLen = 0;
                
                lock (connectionLock)
                {
                    isConnecting = false;
                    if (cancellationToken.IsCancellationRequested)
                    {
                        running = false;
                        try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                        bluetoothSocket = null;
                        try { rfcommService?.Dispose(); } catch (Exception) { }
                        rfcommService = null;
                        return;
                    }
                    
                    // Create stream wrappers for WinRT socket
                    inputStream = bluetoothSocket.InputStream.AsStreamForRead();
                    outputStream = bluetoothSocket.OutputStream.AsStreamForWrite();
                }
                
                running = true;
                OnConnected?.Invoke();

                while (running && !cancellationToken.IsCancellationRequested)
                {
                    int bytesRead;
                    try
                    {
                        bytesRead = await inputStream.ReadAsync(accumulator, accumulatorPtr + accumulatorLen, accumulator.Length - (accumulatorPtr + accumulatorLen), cancellationToken);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }

                    if (!running) { break; }
                    if (bytesRead == 0)
                    {
                        running = false;
                        Disconnect();
                        parent.Disconnect("Connection closed by remote host.", Radio.RadioState.Disconnected);
                        break;
                    }
                    
                    accumulatorLen += bytesRead;
                    if (accumulatorLen < 8) continue;

                    // Process GAIA frames
                    int cmdSize;
                    byte[] cmd;
                    while ((cmdSize = GaiaDecode(accumulator, accumulatorPtr, accumulatorLen, out cmd)) != 0)
                    {
                        if (cmdSize < 0)
                        {
                            cmdSize = accumulatorLen;
                            Debug($"GAIA: {Utils.BytesToHex(accumulator, accumulatorPtr, accumulatorLen)}");
                        }
                        accumulatorPtr += cmdSize;
                        accumulatorLen -= cmdSize;

                        if (cmd != null) { ReceivedData?.Invoke(this, null, cmd); }
                    }

                    // Reset accumulator position if needed
                    if (accumulatorLen == 0) { accumulatorPtr = 0; }
                    if (accumulatorPtr > 2048)
                    {
                        Array.Copy(accumulator, accumulatorPtr, accumulator, 0, accumulatorLen);
                        accumulatorPtr = 0;
                    }
                }
            }
            catch (Exception ex)
            {
                if (running) { Debug($"Connection error: {ex.Message}"); }
            }
            finally
            {
                lock (connectionLock)
                {
                    running = false;
                    isConnecting = false;
                }
                
                // Dispose resources in correct order
                lock (connectionLock)
                {
                    try { inputStream?.Close(); } catch (Exception) { }
                    try { inputStream?.Dispose(); } catch (Exception) { }
                    inputStream = null;
                    
                    try { outputStream?.Close(); } catch (Exception) { }
                    try { outputStream?.Dispose(); } catch (Exception) { }
                    outputStream = null;
                    
                    try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                    bluetoothSocket = null;
                    
                    try { rfcommService?.Dispose(); } catch (Exception) { }
                    rfcommService = null;
                }
                
                Debug("Connection closed.");
                parent.Disconnect("Connection closed.", Radio.RadioState.Disconnected);
            }
        }
    }
}
