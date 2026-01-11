/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text;
using System.Linq;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Collections.Generic;
using InTheHand.Net;
using InTheHand.Net.Bluetooth;
using InTheHand.Net.Sockets;
using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;

namespace HTCommander
{
    public class RadioBluetoothWin
    {
        private Radio parent;
        public string selectedDevice;
        private bool running = false;
        private BluetoothClient connectionClient = null;
        private NetworkStream stream;

        public delegate void DebugMessageEventHandler(string msg);
        public event DebugMessageEventHandler OnDebugMessage;
        public delegate void ConnectedEventHandler();
        public event ConnectedEventHandler OnConnected;
        public delegate void ReceivedDataHandler(RadioBluetoothWin sender, Exception error, byte[] value);
        public event ReceivedDataHandler ReceivedData;

        private static readonly string[] TargetDeviceNames = { "UV-PRO", "UV-50PRO", "GA-5WB", "VR-N75", "VR-N76", "VR-N7500", "VR-N7600" };

        public RadioBluetoothWin(Radio parent)
        {
            this.parent = parent;
        }

        private void Debug(string msg)
        {
            OnDebugMessage?.Invoke(msg);
        }

        private static string BytesToHex(byte[] data, int index, int length)
        {
            if (data == null) return "";
            StringBuilder result = new StringBuilder(length * 2);
            const string hexAlphabet = "0123456789ABCDEF";
            for (int i = index; i < length; i++)
            {
                byte b = data[i];
                result.Append(hexAlphabet[b >> 4]);
                result.Append(hexAlphabet[b & 0xF]);
            }
            return result.ToString();
        }

        public void Disconnect()
        {
            running = false;
            try { stream?.Dispose(); stream = null; } catch (Exception) { }
        }

        public static bool CheckBluetooth()
        {
            try { return BluetoothRadio.Default != null; } catch (Exception) { return false; }
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

        public bool Connect(string macAddress)
        {
            if (running) return false;
            Task.Run(() => StartAsync(macAddress));
            return true;
        }

        public void EnqueueWrite(int expectedResponse, byte[] cmdData)
        {
            if (!running) return;
            byte[] bytes = GaiaEncode(cmdData);
            try { stream.Write(bytes, 0, bytes.Length); }
            catch (Exception ex) { Debug("Error sending request: " + ex.Message); }
        }

        // Decode GAIA protocol frame
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

        // Encode GAIA protocol frame
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

            // Attempt connection with retries
            int retry = 5;
            while (retry > 0)
            {
                try
                {
                    Debug("Attempting to connect...");
                    connectionClient = new BluetoothClient();
                    await connectionClient.ConnectAsync(address, rfcommServiceUuid);
                    retry = -2;
                }
                catch (Exception ex)
                {
                    retry--;
                    connectionClient.Dispose();
                    connectionClient = null;
                    Debug("Connect failed: " + ex.ToString());
                }
            }

            if (retry != -2)
            {
                parent.Disconnect("Unable to connect", Radio.RadioState.UnableToConnect);
                return;
            }

            Debug("Successfully connected to RFCOMM channel.");

            try
            {
                byte[] accumulator = new byte[4096];
                int accumulatorPtr = 0, accumulatorLen = 0;
                stream = connectionClient.GetStream();
                running = true;
                OnConnected?.Invoke();

                while (running && connectionClient.Connected)
                {
                    int bytesRead = stream.Read(accumulator, accumulatorPtr, accumulator.Length - (accumulatorPtr + accumulatorLen));
                    accumulatorLen += bytesRead;

                    if (!running) { connectionClient?.Close(); stream?.Dispose(); stream = null; return; }
                    if (bytesRead == 0)
                    {
                        running = false;
                        connectionClient?.Close();
                        stream = null;
                        parent.Disconnect("Connection closed by remote host.", Radio.RadioState.Disconnected);
                        break;
                    }
                    if (accumulatorLen < 8) continue;

                    // Process received GAIA frames
                    int cmdSize;
                    byte[] cmd;
                    while ((cmdSize = GaiaDecode(accumulator, accumulatorPtr, accumulatorLen, out cmd)) != 0)
                    {
                        if (cmdSize < 0)
                        {
                            cmdSize = accumulatorLen;
                            Debug($"GAIA: {BytesToHex(accumulator, accumulatorPtr, accumulatorLen)}");
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
                running = false;
                stream = null;
                connectionClient?.Close();
                parent.Disconnect("Bluetooth connection closed.", Radio.RadioState.Disconnected);
            }
        }
    }
}
