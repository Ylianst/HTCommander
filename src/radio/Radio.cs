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
using System.IO;
using System.Net;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Windows.Devices.Enumeration;
using InTheHand.Bluetooth;
using System.Collections.Concurrent;
using System.Threading;

namespace HTCommander
{
    public class Radio : IDisposable
    {
        public enum RadioAprsMessageTypes : byte
        {
            UNKNOWN = 0,
            ERROR = 1,
            MESSAGE = 2,
            MESSAGE_ACK = 3,
            MESSAGE_REJ = 4,
            SMS_MESSAGE = 5
        }

        private enum RadioCommandGroup : int
        {
            BASIC = 2,
            EXTENDED = 10
        }

        private enum RadioBasicCommand : int
        {
            UNKNOWN = 0,
            GET_DEV_ID = 1,
            SET_REG_TIMES = 2,
            GET_REG_TIMES = 3,
            GET_DEV_INFO = 4,
            READ_STATUS = 5,
            REGISTER_NOTIFICATION = 6, // No Response
            CANCEL_NOTIFICATION = 7,
            GET_NOTIFICATION = 8,
            EVENT_NOTIFICATION = 9,
            READ_SETTINGS = 10,
            WRITE_SETTINGS = 11, // No Response
            STORE_SETTINGS = 12,
            READ_RF_CH = 13, // No Response
            WRITE_RF_CH = 14,
            GET_IN_SCAN = 15,
            SET_IN_SCAN = 16,
            SET_REMOTE_DEVICE_ADDR = 17,
            GET_TRUSTED_DEVICE = 18,
            DEL_TRUSTED_DEVICE = 19,
            GET_HT_STATUS = 20,
            SET_HT_ON_OFF = 21,
            GET_VOLUME = 22,
            SET_VOLUME = 23,
            RADIO_GET_STATUS = 24,
            RADIO_SET_MODE = 25,
            RADIO_SEEK_UP = 26,
            RADIO_SEEK_DOWN = 27,
            RADIO_SET_FREQ = 28,
            READ_ADVANCED_SETTINGS = 29,
            WRITE_ADVANCED_SETTINGS = 30,
            HT_SEND_DATA = 31,
            SET_POSITION = 32,
            READ_BSS_SETTINGS = 33,
            WRITE_BSS_SETTINGS = 34,
            FREQ_MODE_SET_PAR = 35,
            FREQ_MODE_GET_STATUS = 36,
            READ_RDA1846S_AGC = 37,
            WRITE_RDA1846S_AGC = 38,
            READ_FREQ_RANGE = 39,
            WRITE_DE_EMPH_COEFFS = 40,
            STOP_RINGING = 41,
            SET_TX_TIME_LIMIT = 42,
            SET_IS_DIGITAL_SIGNAL = 43,
            SET_HL = 44,
            SET_DID = 45,
            SET_IBA = 46,
            GET_IBA = 47,
            SET_TRUSTED_DEVICE_NAME = 48,
            SET_VOC = 49,
            GET_VOC = 50,
            SET_PHONE_STATUS = 51,
            READ_RF_STATUS = 52,
            PLAY_TONE = 53,
            GET_DID = 54,
            GET_PF = 55,
            SET_PF = 56,
            RX_DATA = 57,
            WRITE_REGION_CH = 58,
            WRITE_REGION_NAME = 59,
            SET_REGION = 60, // No Response
            SET_PP_ID = 61,
            GET_PP_ID = 62,
            READ_ADVANCED_SETTINGS2 = 63,
            WRITE_ADVANCED_SETTINGS2 = 64,
            UNLOCK = 65,
            DO_PROG_FUNC = 66,
            SET_MSG = 67,
            GET_MSG = 68,
            BLE_CONN_PARAM = 69,
            SET_TIME = 70,
            SET_APRS_PATH = 71,
            GET_APRS_PATH = 72,
            READ_REGION_NAME = 73,
            SET_DEV_ID = 74,
            GET_PF_ACTIONS = 75
        }

        private enum RadioExtendedCommand : int
        {
            UNKNOWN = 0,
            GET_BT_SIGNAL = 769,
            UNKNOWN_01 = 1600,
            UNKNOWN_02 = 1601,
            UNKNOWN_03 = 1602,
            UNKNOWN_04 = 16385,
            UNKNOWN_05 = 16386,
            GET_DEV_STATE_VAR = 16387,
            DEV_REGISTRATION = 1825
        }

        private enum RadioPowerStatus : int
        {
            UNKNOWN = 0,
            BATTERY_LEVEL = 1,
            BATTERY_VOLTAGE = 2,
            RC_BATTERY_LEVEL = 3,
            BATTERY_LEVEL_AS_PERCENTAGE = 4
        }

        private enum RadioNotification : int
        {
            UNKNOWN = 0,
            HT_STATUS_CHANGED = 1,
            DATA_RXD = 2,  // Received APRS or BSS Message
            NEW_INQUIRY_DATA = 3,
            RESTORE_FACTORY_SETTINGS = 4,
            HT_CH_CHANGED = 5,
            HT_SETTINGS_CHANGED = 6,
            RINGING_STOPPED = 7,
            RADIO_STATUS_CHANGED = 8,
            USER_ACTION = 9,
            SYSTEM_EVENT = 10,
            BSS_SETTINGS_CHANGED = 11
        }

        public enum RadioChannelType : int
        {
            OFF = 0,
            A = 1,
            B = 2
        }

        public enum RadioModulationType : int
        {
            FM = 0,
            AM = 1,
            DMR = 2
        }
        public enum RadioBandwidthType : int
        {
            NARROW = 0,
            WIDE = 1
        }
        public enum RadioUpdateNotification : int
        {
            State = 1,
            ChannelInfo = 2,
            BatteryLevel = 3,
            BatteryVoltage = 4,
            RcBatteryLevel = 5,
            BatteryAsPercentage = 6,
            HtStatus = 7,
            Settings = 8,
            Volume = 9,
            AllChannelsLoaded = 10,
            RegionChange = 11
        }
        public enum RadioState : int
        {
            Disconnected = 1,
            Connecting = 2,
            Connected = 3,
            MultiRadioSelect = 4,
            UnableToConnect = 5,
            BluetoothNotAvailable = 6,
            NotRadioFound = 7,
            AccessDenied = 8
        }

        public RadioDevInfo Info = null;
        public RadioChannelInfo[] Channels = null;
        public RadioHtStatus HtStatus = null;
        public RadioSettings Settings = null;
        public bool PacketTrace = false;
        public int BatteryLevel = -1;
        public float BatteryVoltage = -1;
        public int RcBatteryLevel = -1;
        public int BatteryAsPercentage = -1;
        public int Volume = -1;

        // Bluetooth Write Queue
        private class DeviceWriteData { public int expectResponse; public byte[] data; public DeviceWriteData(int expectResponse, byte[] data) { this.expectResponse = expectResponse; this.data = data; } }
        private readonly ConcurrentQueue<DeviceWriteData> _writeQueue = new ConcurrentQueue<DeviceWriteData>();
        private readonly SemaphoreSlim _writeSemaphore = new SemaphoreSlim(1, 1); // To ensure only one write is active
        private bool _isProcessing = false;
        private int _expectedResponse = 0;

        public RadioChannelInfo GetChannelByFrequency(float freq, RadioModulationType mod)
        {
            if (Channels == null) return null;
            int xfreq = (int)(freq * 1000000);
            for (int i = 0; i < Channels.Length; i++)
            {
                if ((Channels[i].rx_freq == xfreq) && (Channels[i].tx_freq == xfreq) && (Channels[i].rx_mod == mod) && (Channels[i].tx_mod == mod)) return Channels[i];
            }
            return null;
        }

        public RadioChannelInfo GetChannelByName(string name)
        {
            if (Channels == null) return null;
            for (int i = 0; i < Channels.Length; i++)
            {
                if (Channels[i].name_str == name) return Channels[i];
            }
            return null;
        }

        public bool AllChannelsLoaded()
        {
            if (Channels == null) return false;
            for (int i = 0; i < Channels.Length; i++) { if (Channels[i] == null) return false; }
            return true;
        }


        // Define the target device name and guids
        private static readonly string[] TargetDeviceNames = { "UV-PRO", "GA-5WB", "VR-N76", "VR-N7500" };
        private readonly Guid RADIO_SERVICE_UUID = new Guid("00001100-d102-11e1-9b23-00025b00a5a5");
        private readonly Guid RADIO_WRITE_UUID = new Guid("00001101-d102-11e1-9b23-00025b00a5a5");
        private readonly Guid RADIO_INDICATE_UUID = new Guid("00001102-d102-11e1-9b23-00025b00a5a5");

        private RemoteGattServer gatt = null;
        private GattCharacteristic writeCharacteristic = null;
        private GattCharacteristic indicateCharacteristic = null;
        private TncDataFragment frameAccumulator = null;

        public Radio() { }

        private string selectedDevice = null;
        public string SelectedDevice { get { return (state == RadioState.Connected) ? selectedDevice : null; } }


        private RadioState state = RadioState.Disconnected;
        public RadioState State { get { return state; } }
        private void UpdateState(RadioState newstate)
        {
            if (state == newstate) return;
            state = newstate;
            Update(RadioUpdateNotification.State);
        }

        public delegate void DebugMessageHandler(Radio sender, string msg);
        public event DebugMessageHandler DebugMessage;
        private void Debug(string msg) { if (DebugMessage != null) { DebugMessage(this, msg); } }

        public delegate void InfoUpdateHandler(Radio sender, RadioUpdateNotification msg);
        public event InfoUpdateHandler OnInfoUpdate;
        private void Update(RadioUpdateNotification msg) { if (OnInfoUpdate != null) { OnInfoUpdate(this, msg); } }

        public delegate void PakcetHandler(Radio sender, TncDataFragment frame);
        public event PakcetHandler OnDataFrame;

        public void Dispose()
        {
            Disconnect(null, RadioState.Disconnected);
        }

        private void Disconnect(string msg, RadioState newstate = RadioState.Disconnected)
        {
            if (msg != null) { Debug(msg); }
            UpdateState(newstate);
            Info = null;
            Channels = null;
            HtStatus = null;
            Settings = null;
            writeCharacteristic = null;
            indicateCharacteristic = null;
            frameAccumulator = null;
            if (gatt != null) { gatt.Disconnect(); gatt = null; }
        }

        public void Disconnect() { Disconnect(null, RadioState.Disconnected); }

        public class CompatibleDevice
        {
            public string name;
            public string mac;
            public CompatibleDevice(string name, string mac) { this.name = name; this.mac = mac; }
        }

        public static async Task<bool> CheckBluetooth()
        {
            bool bluetoothAvailable = false;
            try { bluetoothAvailable = await Bluetooth.GetAvailabilityAsync(); } catch (Exception) { }
            return bluetoothAvailable;
        }
        public static async Task<string[]> GetDeviceNames()
        {
            // Find the devices by name
            var devices = await DeviceInformation.FindAllAsync();
            List<string> r = new List<string>();
            foreach (var deviceInfo in devices) { if (!r.Contains(deviceInfo.Name)) { r.Add(deviceInfo.Name); } }
            r.Sort();
            return r.ToArray();
        }

        public static async Task<CompatibleDevice[]> FindCompatibleDevices()
        {
            // Find the devices by name
            List<CompatibleDevice> compatibleDevices = new List<CompatibleDevice>();
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
                            compatibleDevices.Add(new CompatibleDevice(deviceInfo.Name, mac));
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
                                compatibleDevices.Add(new CompatibleDevice(deviceInfo.Name, mac));
                            }
                        }
                    }
                }
            }
            return compatibleDevices.ToArray();
        }

        public async void Connect(string macAddress)
        {
            if (state == RadioState.Connected || state == RadioState.Connecting) return;
            UpdateState(RadioState.Connecting);
            Debug("Attempting to connect to radio MAC: " + macAddress);

            // Regular expression to capture the 12-character MAC address
            var bluetoothDevice = await BluetoothDevice.FromIdAsync(macAddress);
            if (bluetoothDevice == null) {
                Disconnect($"Unable to connect.", RadioState.AccessDenied);
                return;
            }
            selectedDevice = $"{bluetoothDevice.Name} ({bluetoothDevice.Id})";
            Debug($"Selected device: {bluetoothDevice.Name} - {bluetoothDevice.Id}");

            // Connect to the device
            gatt = bluetoothDevice.Gatt;
            Debug("Connecting to radio...");
            await gatt.ConnectAsync();
            //gatt.AutoConnect = true;
            if (gatt.IsConnected == false) { Disconnect($"Gatt not connected.", RadioState.UnableToConnect); return; }

            Debug("Getting radio service...");
            var service = await gatt.GetPrimaryServiceAsync(RADIO_SERVICE_UUID);
            if (service == null) { Disconnect($"Radio service not found.", RadioState.UnableToConnect); return; }

            // Get characteristics
            Debug("Getting radio characteristic...");
            writeCharacteristic = await service.GetCharacteristicAsync(RADIO_WRITE_UUID);
            if (writeCharacteristic == null) { Disconnect($"Unable to get write characteristic.", RadioState.UnableToConnect); return; }
            indicateCharacteristic = await service.GetCharacteristicAsync(RADIO_INDICATE_UUID);
            if (indicateCharacteristic == null) { Disconnect($"Unable to get read/notify characteristic.", RadioState.UnableToConnect); return; }

            // Receive command responses
            Debug("Getting radio information...");
            indicateCharacteristic.CharacteristicValueChanged += Characteristic_CharacteristicValueChanged;
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_DEV_INFO, 3);
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_SETTINGS, null);
            RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE);
        }

        private void UpdateChannels()
        {
            if ((state != RadioState.Connected) || (Info == null)) return;
            for (byte i = 0; i < Info.channel_count; i++)
            {
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_RF_CH, i);
            }
        }
        public void SetChannel(RadioChannelInfo channel)
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.WRITE_RF_CH, channel.ToByteArray());
        }

        public void SetRegion(int region)
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.SET_REGION, (byte)region);
        }

        public void WriteSettings(byte[] data)
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.WRITE_SETTINGS, data);
        }

        public void GetVolumeLevel()
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_VOLUME, null);
        }

        public void SetVolumeLevel(int level)
        {
            if ((level < 0) || (level > 15)) return;
            byte[] buf = new byte[1];
            buf[0] = (byte)level;
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.SET_VOLUME, buf);
        }

        public void GetBatteryLevel() { RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL); }
        public void GetBatteryVoltage() { RequestPowerStatus(RadioPowerStatus.BATTERY_VOLTAGE); }
        public void GetBatteryRcLevel() { RequestPowerStatus(RadioPowerStatus.RC_BATTERY_LEVEL); }
        public void GetBatteryLevelAtPercentage() { RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE); }

        private void RequestPowerStatus(RadioPowerStatus powerStatus)
        {
            byte[] data = new byte[2];
            data[1] = (byte)powerStatus;
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_STATUS, data);
        }

        private void Characteristic_CharacteristicValueChanged(object sender, GattCharacteristicValueChangedEventArgs e)
        {
            if (e.Value == null) { Debug($"Notification: NULL"); return; }
            if (PacketTrace) { Debug($"Response: " + Utils.BytesToHex(e.Value)); }
            else { Program.BlockBoxEvent("BTRECV: " + Utils.BytesToHex(e.Value)); }
            int r = Utils.GetInt(e.Value, 0);
            RadioCommandGroup group = (RadioCommandGroup)Utils.GetShort(e.Value, 0);
            if ((_expectedResponse == -1) || ((_expectedResponse | 0x8000) == Utils.GetInt(e.Value, 0)))
            {
                _expectedResponse = 0;
                ResponseReceived();
            }

            switch (group)
            {
                case RadioCommandGroup.BASIC:
                    RadioBasicCommand cmd = (RadioBasicCommand)(Utils.GetShort(e.Value, 2) & 0x7FFF);
                    if (PacketTrace) { Debug($"Response '{group}' / '{cmd}'"); }
                    switch (cmd)
                    {
                        case RadioBasicCommand.GET_DEV_INFO:
                            Info = new RadioDevInfo(e.Value);
                            Channels = new RadioChannelInfo[Info.channel_count];
                            UpdateState(RadioState.Connected);
                            // Register for notifications
                            // OK: 1, 8  - BAD:0,2,3,4,5,6,16,0x0F,0xFF
                            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.REGISTER_NOTIFICATION, 1);
                            break;
                        case RadioBasicCommand.READ_RF_CH:
                            RadioChannelInfo c = new RadioChannelInfo(e.Value);
                            if (Channels != null) { Channels[c.channel_id] = c; }
                            //if (c.name_str.Length > 0) { Debug($"Channel ({c.channel_id}): '{c.name_str}'"); }
                            Update(RadioUpdateNotification.ChannelInfo);
                            if (AllChannelsLoaded()) { Update(RadioUpdateNotification.AllChannelsLoaded); }
                            break;
                        case RadioBasicCommand.WRITE_RF_CH:
                            if (e.Value[4] == 0)
                            {
                                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_RF_CH, e.Value[5]);
                            }
                            break;
                        case RadioBasicCommand.EVENT_NOTIFICATION:
                            RadioNotification notify = (RadioNotification)e.Value[4];
                            switch (notify)
                            {
                                case RadioNotification.HT_STATUS_CHANGED:
                                    int oldRegion = -1;
                                    if (HtStatus != null) { oldRegion = HtStatus.curr_region; }
                                    HtStatus = new RadioHtStatus(e.Value);
                                    Update(RadioUpdateNotification.HtStatus);
                                    if (oldRegion != HtStatus.curr_region)
                                    {
                                        Update(RadioUpdateNotification.RegionChange);
                                        if (Channels != null) { for (int i = 0; i < Channels.Length; i++) { Channels[i] = null; } }
                                        Update(RadioUpdateNotification.ChannelInfo);
                                        UpdateChannels();
                                    }
                                    break;
                                //case RadioNotification.HT_CH_CHANGED:
                                //Event: 00020009050508CCCEC008C3A70027102710940053796C76616E00000000
                                //break;
                                case RadioNotification.DATA_RXD:
                                    //Debug("RawData: " + BytesToHex(e.Value));
                                    TncDataFragment fragment = new TncDataFragment(e.Value);
                                    if ((fragment.channel_id == -1) && (HtStatus != null)) { fragment.channel_id = HtStatus.curr_ch_id; }

                                    //Debug($"DataFragment, FragId={fragment.fragment_id}, IsFinal={fragment.is_final_fragment}, ChannelId={fragment.channel_id}, DataLen={fragment.data.Length}");
                                    //Debug("Data: " + BytesToHex(fragment.data));
                                    if (frameAccumulator == null) { if (fragment.fragment_id == 0) { frameAccumulator = fragment; } } else { frameAccumulator = frameAccumulator.Append(fragment); }
                                    if ((frameAccumulator != null) && (frameAccumulator.final_fragment))
                                    {
                                        TncDataFragment packet = frameAccumulator;
                                        frameAccumulator = null;
                                        packet.incoming = true;
                                        packet.time = DateTime.Now;
                                        if (OnDataFrame != null) { OnDataFrame(this, packet); }
                                    }
                                    break;
                                case RadioNotification.HT_SETTINGS_CHANGED:
                                    Settings = new RadioSettings(e.Value);
                                    Update(RadioUpdateNotification.Settings);
                                    break;
                                default:
                                    Debug($"Event: " + Utils.BytesToHex(e.Value));
                                    break;
                            }
                            break;
                        case RadioBasicCommand.READ_STATUS:
                            RadioPowerStatus powerStatus = (RadioPowerStatus)Utils.GetShort(e.Value, 5);
                            switch (powerStatus)
                            {
                                case RadioPowerStatus.BATTERY_LEVEL:
                                    BatteryLevel = e.Value[7];
                                    Debug("BatteryLevel: " + BatteryLevel);
                                    Update(RadioUpdateNotification.BatteryLevel);
                                    break;
                                case RadioPowerStatus.BATTERY_VOLTAGE:
                                    BatteryVoltage = Utils.GetShort(e.Value, 7) / 1000;
                                    Debug("BatteryVoltage: " + BatteryVoltage);
                                    Update(RadioUpdateNotification.BatteryVoltage);
                                    break;
                                case RadioPowerStatus.RC_BATTERY_LEVEL:
                                    RcBatteryLevel = e.Value[7];
                                    Debug("RcBatteryLevel: " + RcBatteryLevel);
                                    Update(RadioUpdateNotification.RcBatteryLevel);
                                    break;
                                case RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE:
                                    BatteryAsPercentage = e.Value[7];
                                    //Debug("BatteryAsPercentage: " + BatteryAsPercentage);
                                    Update(RadioUpdateNotification.BatteryAsPercentage);
                                    break;
                                default:
                                    Debug("Unexpected Power Status: " + powerStatus);
                                    break;
                            }
                            break;
                        case RadioBasicCommand.READ_SETTINGS:
                            Settings = new RadioSettings(e.Value);
                            Update(RadioUpdateNotification.Settings);
                            break;
                        case RadioBasicCommand.HT_SEND_DATA:
                            // Data sent, ready to send more
                            // 0002801F00
                            // TODO
                            break;
                        case RadioBasicCommand.SET_VOLUME:
                            break;
                        case RadioBasicCommand.GET_VOLUME:
                            Volume = e.Value[5];
                            Update(RadioUpdateNotification.Volume);
                            break;
                        case RadioBasicCommand.WRITE_SETTINGS:
                            if (e.Value[4] != 0) { Debug("WRITE_SETTINGS ERROR: " + Utils.BytesToHex(e.Value)); }
                            break;
                        case RadioBasicCommand.SET_REGION:
                            break;
                        default:
                            Debug("Unexpected Basic Command Status: " + cmd);
                            Debug(Utils.BytesToHex(e.Value));
                            break;
                    }
                    break;
                case RadioCommandGroup.EXTENDED:
                    RadioExtendedCommand xcmd = (RadioExtendedCommand)(Utils.GetShort(e.Value, 2) & 0x7FFF);
                    if (PacketTrace) { Debug($"Response '{group}' / '{xcmd}'"); }
                    switch (xcmd)
                    {
                        default:
                            Debug("Unexpected Extended Command Status: " + xcmd);
                            break;
                    }
                    break;
                default:
                    Debug("Unexpected Command Group: " + group);
                    break;
            }
        }

        private void SendCommand(RadioCommandGroup group, RadioBasicCommand cmd, byte data)
        {
            if (writeCharacteristic == null) return;
            using (MemoryStream ms = new MemoryStream())
            {
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)group)), 0, 2);
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)cmd)), 0, 2);
                ms.WriteByte(data);
                byte[] cmdData = ms.ToArray();
                if (PacketTrace) { Debug($"Queue: " + group.ToString() + ", " + cmd.ToString() + ": " + Utils.BytesToHex(cmdData)); }
                else { Program.BlockBoxEvent("BTQSEND: " + Utils.BytesToHex(cmdData)); }
                EnqueueWrite(new DeviceWriteData(GetExpectedResponse(group, cmd), cmdData));
            }
        }

        private void SendCommand(RadioCommandGroup group, RadioBasicCommand cmd, byte[] data)
        {
            if (writeCharacteristic == null) return;
            using (MemoryStream ms = new MemoryStream())
            {
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)group)), 0, 2);
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)cmd)), 0, 2);
                if (data != null) { ms.Write(data, 0, data.Length); }
                byte[] cmdData = ms.ToArray();
                if (PacketTrace) { Debug($"Queue: " + group.ToString() + ", " + cmd.ToString() + ": " + Utils.BytesToHex(cmdData)); }
                else { Program.BlockBoxEvent("BTQSEND: " + Utils.BytesToHex(cmdData)); }
                EnqueueWrite(new DeviceWriteData(GetExpectedResponse(group, cmd), cmdData));
            }
        }

        private int GetExpectedResponse(RadioCommandGroup group, RadioBasicCommand cmd)
        {
            int rcmd = ((int)cmd | 0x8000);
            switch (cmd)
            {
                case RadioBasicCommand.REGISTER_NOTIFICATION:
                    return -1;
                case RadioBasicCommand.WRITE_SETTINGS:
                    return -1;
                case RadioBasicCommand.SET_REGION:
                    return -1;
            }
            return ((int)group << 16) + (int)rcmd;
        }

        public void TransmitTncData(AX25Packet packet, int channelId = -1)
        {
            TncDataFragment fragment = new TncDataFragment(true, 0, packet.ToByteArray(), channelId);
            fragment.incoming = false;
            fragment.time = DateTime.Now;
            if (OnDataFrame != null) { OnDataFrame(this, fragment); }
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, fragment.toByteArray());
        }

        // Method to queue a write operation
        private void EnqueueWrite(DeviceWriteData writeData)
        {
            _writeQueue.Enqueue(writeData);
            ProcessQueue(); // Start processing the queue if it's not already running
        }

        // Method to indicate a response has been received
        private void ResponseReceived()
        {
            // Release the semaphore to allow the next item in the queue to be processed
            if (_writeSemaphore.CurrentCount == 0)
            {
                _writeSemaphore.Release();
            }
            else
            {
                _writeSemaphore.Release();
            }
        }

        // Processes the queue
        private async void ProcessQueue()
        {
            if (_isProcessing) return; // Avoid multiple threads starting processing
            _isProcessing = true;

            try
            {
                while (_writeQueue.TryDequeue(out DeviceWriteData cmdData))
                {
                    // Wait for the semaphore to ensure sequential writes
                    await _writeSemaphore.WaitAsync();

                    // Execute the write on a separate thread to avoid blocking
                    await Task.Run(async () =>
                    {
                        try
                        {
                            if (writeCharacteristic != null)
                            {
                                if (PacketTrace) { Debug($"Send: " + Utils.BytesToHex(cmdData.data)); }
                                else { Program.BlockBoxEvent("BTSEND: " + Utils.BytesToHex(cmdData.data)); }
                                _expectedResponse = cmdData.expectResponse;
                                await writeCharacteristic.WriteValueWithResponseAsync(cmdData.data);
                                if (_expectedResponse == -2) { _expectedResponse = 0; _writeSemaphore.Release(); }
                            }
                            else
                            {
                                _writeSemaphore.Release();
                            }
                        }
                        catch (Exception ex)
                        {
                            if (ex.HResult == -2140864497)
                            {
                                Disconnect($"Access denied. Please re-pair the device.", Radio.RadioState.AccessDenied);
                            }
                            _writeSemaphore.Release(); // Ensure semaphore is released on error
                        }
                    });
                }
            }
            finally
            {
                _isProcessing = false; // Mark as not processing when the queue is empty
            }
        }

    }
}