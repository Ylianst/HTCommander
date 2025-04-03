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
using System.Text;
using System.Linq;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Collections.Generic;
using InTheHand.Net.Bluetooth;
using InTheHand.Net.Sockets;
using InTheHand.Net;
using Windows.Devices.Enumeration;

#if !__MonoCS__
using System.Collections.Concurrent;
#endif

namespace HTCommander
{
    public class RadioBluetoothWin
    {
        private Radio parent;
        public string selectedDevice;
        private bool running = false;
        private BluetoothClient connectionClient = new BluetoothClient();
        private NetworkStream stream;
        public delegate void DebugMessageEventHandler(string msg);
        public event DebugMessageEventHandler OnDebugMessage;
        public delegate void ConnectedEventHandler();
        public event ConnectedEventHandler OnConnected;

        private static string BytesToHex(byte[] data, int index, int length)
        {
            if (data == null) return "";
            StringBuilder Result = new StringBuilder(data.Length * 2);
            string HexAlphabet = "0123456789ABCDEF";
            for (int i = index; i < length; i++)
            {
                byte B = data[i];
                Result.Append(HexAlphabet[(int)(B >> 4)]);
                Result.Append(HexAlphabet[(int)(B & 0xF)]);
            }
            return Result.ToString();
        }

        private void Debug(string msg)
        {
            if (OnDebugMessage != null) { OnDebugMessage(msg); }
        }

        // Define the target device name and guids
        private static readonly string[] TargetDeviceNames = { "UV-PRO", "GA-5WB", "VR-N76", "VR-N7500" };
        private class DeviceWriteData { public int expectResponse; public byte[] data; public DeviceWriteData(int expectResponse, byte[] data) { this.expectResponse = expectResponse; this.data = data; } }
        private ConcurrentQueue<DeviceWriteData> _writeQueue = new ConcurrentQueue<DeviceWriteData>();

        public RadioBluetoothWin(Radio parent)
        {
            this.parent = parent;
        }

        public void Disconnect()
        {
            running = false;
            try { if (stream != null) { stream.Dispose(); stream = null; } } catch (Exception) { }
        }

        public static bool CheckBluetooth()
        {
            return (BluetoothRadio.Default != null);
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

        public bool Connect(string macAddress)
        {
            if (running) return false;
            Task.Run(() => StartAsync(macAddress));
            return true;
        }

        public delegate void ReceivedDataHandler(RadioBluetoothWin sender, Exception error, byte[] value);
        public event ReceivedDataHandler ReceivedData;

        // Method to queue a write operation
        public void EnqueueWrite(int expectedResponse, byte[] cmdData)
        {
            if (!running) return;
            byte[] bytes = GaiaEncode(cmdData);
            //Debug("Write: " + BytesToHex(bytes, 0, bytes.Length));
            try { stream.Write(bytes, 0, bytes.Length); } catch (Exception ex) { Debug("Error sending request: " + ex.Message); return; }
        }

        private static int GaiaDecode(byte[] data, int index, int len, out byte[] cmd)
        {
            cmd = null;
            if (len < 8) return 0;
            if (data[index] != 0xFF) return -1; // Error
            if (data[index + 1] != 0x01) return -1; // Error
            byte nBytesPayload = data[index + 3];
            int hasChecksum = (data[index + 2] & 1);
            int totalLen = nBytesPayload + 8 + hasChecksum;
            if (totalLen > len) return 0; // Wait for more data
            cmd = new byte[4 + nBytesPayload]; // TODO: Check if checksum is correct if present
            Array.Copy(data, index + 4, cmd, 0, cmd.Length);
            return totalLen;
        }

        private static byte[] GaiaEncode(byte[] cmd)
        {
            byte[] bytes = new byte[cmd.Length + 4];
            bytes[0] = 0xFF;
            bytes[1] = 0x01;
            bytes[3] = (byte)(cmd.Length - 4);
            Array.Copy(cmd, 0, bytes, 4, cmd.Length);
            return bytes;
        }

        private async void StartAsync(string mac)
        {
            Guid rfcommServiceUuid = BluetoothService.SerialPort;
            BluetoothAddress address = BluetoothAddress.Parse(mac);
            BluetoothEndPoint remoteEndPoint = new BluetoothEndPoint(address, rfcommServiceUuid, 0);
            // Connect to the remote endpoint asynchronously
            Debug("Attempting to connect...");
            try
            {
                connectionClient.Connect(remoteEndPoint);
            }
            catch (Exception)
            {
                parent.Disconnect("Unable to connect", Radio.RadioState.UnableToConnect);
                return;
            }
            Debug("Successfully connected to the RFCOMM channel.");

            try
            {
                byte[] accumulator = new byte[4096];
                int accumulatorPtr = 0, accumulatorLen = 0;
                stream = connectionClient.GetStream();

                running = true;
                //Debug("Ready to receive data.");
                if (OnConnected != null) { OnConnected(); }
                while (running && connectionClient.Connected)
                {
                    // Receive data
                    int bytesRead = stream.Read(accumulator, accumulatorPtr, accumulator.Length - (accumulatorPtr + accumulatorLen));
                    accumulatorLen += bytesRead;
                    //Debug($"Received {bytesRead} bytes, Accumulator: {BytesToHex(accumulator, accumulatorPtr, accumulatorLen)}");
                    if (running == false) { connectionClient?.Close(); stream.Dispose(); stream = null; return; }
                    if (bytesRead == 0) { running = false; connectionClient?.Close(); stream = null; parent.Disconnect("Connection closed by remote host.", Radio.RadioState.Disconnected); break; }
                    if (accumulatorLen < 8) continue; // Wait for at least 8 bytes

                    int cmdSize;
                    byte[] cmd;
                    while ((cmdSize = GaiaDecode(accumulator, accumulatorPtr, accumulatorLen, out cmd)) != 0)
                    {
                        if (cmdSize < 0) {
                            cmdSize = accumulatorLen;
                            Debug($"GAIA: {BytesToHex(accumulator, accumulatorPtr, accumulatorLen)}");
                        }
                        accumulatorPtr += cmdSize;
                        accumulatorLen -= cmdSize;

                        if (cmd != null)
                        {
                            //Debug("CMD: " + BytesToHex(cmd, 0, cmd.Length));
                            if (ReceivedData != null) { ReceivedData(this, null, cmd); }
                        }
                    }

                    // Get the accumulator ready for the next read
                    if (accumulatorLen == 0) { accumulatorPtr = 0; }
                    if (accumulatorPtr > 2048) { Array.Copy(accumulator, accumulatorPtr, accumulator, 0, accumulatorLen); accumulatorPtr = 0; }
                }
            }
            catch (Exception ex)
            {
                if (running) { Debug($"Connection error: {ex.Message}"); }
            }
            finally
            {
                running = false;
                stream = null;
                connectionClient?.Close();
                parent.Disconnect("Bluetooth connection closed.", Radio.RadioState.Disconnected);
            }
        }

    }
}
