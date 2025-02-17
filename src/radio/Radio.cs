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
using System.Collections.Generic;


namespace HTCommander
{
    public class Radio : IDisposable
    {
        private const int MAX_MTU = 50;

        public class CompatibleDevice
        {
            public string name;
            public string mac;
            public CompatibleDevice(string name, string mac) { this.name = name; this.mac = mac; }
        }

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
            RegionChange = 11,
            BssSettings = 12
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

        private enum RadioCommandState : int
        {
            SUCCESS,
            NOT_SUPPORTED,
            NOT_AUTHENTICATED,
            INSUFFICIENT_RESOURCES,
            AUTHENTICATING,
            INVALID_PARAMETER,
            INCORRECT_STATE,
            IN_PROGRESS
        }

        public RadioDevInfo Info = null;
        public RadioChannelInfo[] Channels = null;
        public RadioHtStatus HtStatus = null;
        public RadioSettings Settings = null;
        public RadioBssSettings BssSettings = null;
        public bool PacketTrace = false;
        public int BatteryLevel = -1;
        public float BatteryVoltage = -1;
        public int RcBatteryLevel = -1;
        public int BatteryAsPercentage = -1;
        public int Volume = -1;
        public bool LoopbackMode = false;
        private List<fragmentInQueue> TncFragmentQueue = new List<fragmentInQueue>();
        private bool TncFragmentInFlight = false;

        private class fragmentInQueue
        {
            public byte[] fragment;
            public bool isLast;
            public int fragid;

            public fragmentInQueue(byte[] fragment, bool isLast, int fragid)
            {
                this.fragment = fragment;
                this.isLast = isLast;
                this.fragid = fragid;
            }
        }

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

        private TncDataFragment frameAccumulator = null;
        private RadioBluetoothWin radioTransport;

        public Radio() { }
        public string SelectedDevice { get { return ((radioTransport != null) && (state == RadioState.Connected)) ? radioTransport.selectedDevice : null; } }


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
        public void Debug(string msg) { if (DebugMessage != null) { DebugMessage(this, msg); } }

        public delegate void InfoUpdateHandler(Radio sender, RadioUpdateNotification msg);
        public event InfoUpdateHandler OnInfoUpdate;
        private void Update(RadioUpdateNotification msg) { if (OnInfoUpdate != null) { OnInfoUpdate(this, msg); } }

        public delegate void PakcetHandler(Radio sender, TncDataFragment frame);
        public event PakcetHandler OnDataFrame;

        public void Dispose()
        {
            Disconnect(null, RadioState.Disconnected);
        }

        public void Disconnect(string msg, RadioState newstate = RadioState.Disconnected)
        {
            if (msg != null) { Debug(msg); }
            UpdateState(newstate);
            radioTransport.Disconnect();
            Info = null;
            Channels = null;
            HtStatus = null;
            Settings = null;
            frameAccumulator = null;
            TncFragmentQueue.Clear();
            TncFragmentInFlight = false;
        }

        public void Disconnect() { Disconnect(null, RadioState.Disconnected); }

        public async void Connect(string macAddress)
        {
            if (state == RadioState.Connected || state == RadioState.Connecting) return;
            UpdateState(RadioState.Connecting);
            Debug("Attempting to connect to radio MAC: " + macAddress);

            radioTransport = new RadioBluetoothWin(this);
            radioTransport.ReceivedData += RadioTransport_ReceivedData;
            bool success = await radioTransport.Connect(macAddress);
            if (success)
            {
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_DEV_INFO, 3);
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_SETTINGS, null);
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_BSS_SETTINGS, null);
                RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE);
            }
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

        public void SetBssSettings(RadioBssSettings bss)
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.WRITE_BSS_SETTINGS, bss.ToByteArray());
        }

        public void GetBatteryLevel() { RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL); }
        public void GetBatteryVoltage() { RequestPowerStatus(RadioPowerStatus.BATTERY_VOLTAGE); }
        public void GetBatteryRcLevel() { RequestPowerStatus(RadioPowerStatus.RC_BATTERY_LEVEL); }
        public void GetBatteryLevelAtPercentage() { RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE); }
        private bool IsTncFree() { return ((HtStatus != null) && (HtStatus.is_in_tx == false)); }
        private void RequestPowerStatus(RadioPowerStatus powerStatus)
        {
            byte[] data = new byte[2];
            data[1] = (byte)powerStatus;
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_STATUS, data);
        }

        private void RadioTransport_ReceivedData(RadioBluetoothWin sender, Exception error, byte[] value)
        {
            if ((state != RadioState.Connected) && (state != RadioState.Connecting)) { return; }
            if (error != null) { Debug($"Notification ERROR SET"); }
            if (value == null) { Debug($"Notification: NULL"); return; }
            if (PacketTrace) { Debug("-----> " + Utils.BytesToHex(value)); }
            else { Program.BlockBoxEvent("-----> " + Utils.BytesToHex(value)); }
            int r = Utils.GetInt(value, 0);
            RadioCommandGroup group = (RadioCommandGroup)Utils.GetShort(value, 0);

            switch (group)
            {
                case RadioCommandGroup.BASIC:
                    RadioBasicCommand cmd = (RadioBasicCommand)(Utils.GetShort(value, 2) & 0x7FFF);
                    if (PacketTrace && (cmd != RadioBasicCommand.EVENT_NOTIFICATION)) { Debug($"Response '{group}' / '{cmd}'"); }
                    switch (cmd)
                    {
                        case RadioBasicCommand.GET_DEV_INFO:
                            Info = new RadioDevInfo(value);
                            Channels = new RadioChannelInfo[Info.channel_count];
                            UpdateState(RadioState.Connected);
                            // Register for notifications
                            // OK: 1, 8  - BAD:0,2,3,4,5,6,16,0x0F,0xFF
                            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.REGISTER_NOTIFICATION, 1);
                            break;
                        case RadioBasicCommand.READ_RF_CH:
                            RadioChannelInfo c = new RadioChannelInfo(value);
                            if (Channels != null) { Channels[c.channel_id] = c; }
                            //if (c.name_str.Length > 0) { Debug($"Channel ({c.channel_id}): '{c.name_str}'"); }
                            Update(RadioUpdateNotification.ChannelInfo);
                            if (AllChannelsLoaded()) { Update(RadioUpdateNotification.AllChannelsLoaded); }
                            break;
                        case RadioBasicCommand.WRITE_RF_CH:
                            if (value[4] == 0)
                            {
                                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_RF_CH, value[5]);
                            }
                            break;
                        case RadioBasicCommand.READ_BSS_SETTINGS:
                            BssSettings = new RadioBssSettings(value);
                            Update(RadioUpdateNotification.BssSettings);
                            break;
                        case RadioBasicCommand.EVENT_NOTIFICATION:
                            RadioNotification notify = (RadioNotification)value[4];
                            if (PacketTrace) { Debug($"Response '{group}' / '{cmd}' / '{notify}'"); }
                            switch (notify)
                            {
                                case RadioNotification.HT_STATUS_CHANGED:
                                    int oldRegion = -1;
                                    if (HtStatus != null) { oldRegion = HtStatus.curr_region; }
                                    HtStatus = new RadioHtStatus(value);
                                    Update(RadioUpdateNotification.HtStatus);
                                    if (oldRegion != HtStatus.curr_region)
                                    {
                                        Update(RadioUpdateNotification.RegionChange);
                                        if (Channels != null) { for (int i = 0; i < Channels.Length; i++) { Channels[i] = null; } }
                                        Update(RadioUpdateNotification.ChannelInfo);
                                        UpdateChannels();
                                    }
                                    Debug($"inRX={HtStatus.is_in_rx}, inTX={HtStatus.is_in_tx}");
                                    if (IsTncFree() && (TncFragmentInFlight == false) && (TncFragmentQueue.Count > 0)) // We are clear to send a packet
                                    {
                                        // Send more data
                                        TncFragmentInFlight = true;
                                        SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
                                    }
                                    break;
                                //case RadioNotification.HT_CH_CHANGED:
                                //Event: 00020009050508CCCEC008C3A70027102710940053796C76616E00000000
                                //break;
                                case RadioNotification.DATA_RXD:
                                    //Debug("RawData: " + BytesToHex(e.Value));
                                    TncDataFragment fragment = new TncDataFragment(value);
                                    if ((fragment.channel_id == -1) && (HtStatus != null))
                                    {
                                        fragment.channel_id = HtStatus.curr_ch_id;
                                        if ((Channels != null) && (Channels[HtStatus.curr_ch_id] != null))
                                        {
                                            if (Channels[HtStatus.curr_ch_id].name_str.Length > 0)
                                            {
                                                fragment.channel_name = Channels[HtStatus.curr_ch_id].name_str.Replace(",", "");
                                            }
                                            else if (Channels[HtStatus.curr_ch_id].rx_freq != 0)
                                            {
                                                fragment.channel_name = (((double)Channels[HtStatus.curr_ch_id].rx_freq) / 1000000) + " Mhz";
                                            }
                                            else
                                            {
                                                fragment.channel_name = (HtStatus.curr_ch_id + 1).ToString();
                                            }
                                        }
                                        else
                                        {
                                            fragment.channel_name = (HtStatus.curr_ch_id + 1).ToString();
                                        }
                                    }

                                    Debug($"DataFragment, FragId={fragment.fragment_id}, IsFinal={fragment.final_fragment}, ChannelId={fragment.channel_id}, DataLen={fragment.data.Length}");
                                    //Debug("Data: " + BytesToHex(fragment.data));
                                    if (frameAccumulator == null)
                                    {
                                        if (fragment.fragment_id == 0)
                                        {
                                            frameAccumulator = fragment;
                                        }
                                    }
                                    else
                                    {
                                        frameAccumulator = frameAccumulator.Append(fragment);
                                    }
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
                                    Settings = new RadioSettings(value);
                                    Update(RadioUpdateNotification.Settings);
                                    break;
                                default:
                                    Debug($"Event: " + Utils.BytesToHex(value));
                                    break;
                            }
                            break;
                        case RadioBasicCommand.READ_STATUS:
                            RadioPowerStatus powerStatus = (RadioPowerStatus)Utils.GetShort(value, 5);
                            switch (powerStatus)
                            {
                                case RadioPowerStatus.BATTERY_LEVEL:
                                    BatteryLevel = value[7];
                                    Debug("BatteryLevel: " + BatteryLevel);
                                    Update(RadioUpdateNotification.BatteryLevel);
                                    break;
                                case RadioPowerStatus.BATTERY_VOLTAGE:
                                    BatteryVoltage = Utils.GetShort(value, 7) / 1000;
                                    Debug("BatteryVoltage: " + BatteryVoltage);
                                    Update(RadioUpdateNotification.BatteryVoltage);
                                    break;
                                case RadioPowerStatus.RC_BATTERY_LEVEL:
                                    RcBatteryLevel = value[7];
                                    Debug("RcBatteryLevel: " + RcBatteryLevel);
                                    Update(RadioUpdateNotification.RcBatteryLevel);
                                    break;
                                case RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE:
                                    BatteryAsPercentage = value[7];
                                    //Debug("BatteryAsPercentage: " + BatteryAsPercentage);
                                    Update(RadioUpdateNotification.BatteryAsPercentage);
                                    break;
                                default:
                                    Debug("Unexpected Power Status: " + powerStatus);
                                    break;
                            }
                            break;
                        case RadioBasicCommand.READ_SETTINGS:
                            Settings = new RadioSettings(value);
                            Update(RadioUpdateNotification.Settings);
                            break;
                        case RadioBasicCommand.HT_SEND_DATA:
                            // Data sent, ready to send more
                            // 0002801F00 = OK READY FOR MORE.
                            // 0002801F06 = NOT READY, TRY AGAIN.
                            if (TncFragmentQueue.Count == 0) { TncFragmentInFlight = false; break; }

                            RadioCommandState errorCode = (RadioCommandState)value[4];
                            if (errorCode == RadioCommandState.INCORRECT_STATE)
                            {
                                if (TncFragmentQueue[0].fragid == 0)
                                {
                                    if (IsTncFree())
                                    {
                                        // If this is the first fragment, try again
                                        TncFragmentInFlight = true;
                                        Debug("TNC Fragment failed, TRYING AGAIN.");
                                        SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
                                    }
                                    else
                                    {
                                        TncFragmentInFlight = false;
                                    }
                                    break;
                                }
                                else
                                {
                                    // Send failed, clear all fragements until the last of this packet.
                                    Debug("TNC Fragment failed, check Bluetooth connection.");
                                    while (TncFragmentQueue[0].isLast == false) { TncFragmentQueue.RemoveAt(0); }
                                    TncFragmentQueue.RemoveAt(0);
                                }
                            }
                            else
                            {
                                // Success
                                TncFragmentQueue.RemoveAt(0);
                            }

                            // Ready for more data. If this is the start of a new fragment, wait with RSSI is zero.
                            if ((TncFragmentQueue.Count > 0) && ((TncFragmentQueue[0].fragid != 0) || IsTncFree()))
                            {
                                // Send the next fragment
                                TncFragmentInFlight = true;
                                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
                            }
                            else
                            {
                                // Nothing more to send
                                TncFragmentInFlight = false;
                            }
                            break;
                        case RadioBasicCommand.SET_VOLUME:
                            break;
                        case RadioBasicCommand.GET_VOLUME:
                            Volume = value[5];
                            Update(RadioUpdateNotification.Volume);
                            break;
                        case RadioBasicCommand.WRITE_SETTINGS:
                            if (value[4] != 0) { Debug("WRITE_SETTINGS ERROR: " + Utils.BytesToHex(value)); }
                            break;
                        case RadioBasicCommand.SET_REGION:
                            break;
                        default:
                            Debug("Unexpected Basic Command Status: " + cmd);
                            Debug(Utils.BytesToHex(value));
                            break;
                    }
                    break;
                case RadioCommandGroup.EXTENDED:
                    RadioExtendedCommand xcmd = (RadioExtendedCommand)(Utils.GetShort(value, 2) & 0x7FFF);
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
            if (radioTransport == null) return;
            using (MemoryStream ms = new MemoryStream())
            {
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)group)), 0, 2);
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)cmd)), 0, 2);
                ms.WriteByte(data);
                byte[] cmdData = ms.ToArray();
                if (PacketTrace) { Debug($"Queue: " + group.ToString() + ", " + cmd.ToString() + ": " + Utils.BytesToHex(cmdData)); }
                else { Program.BlockBoxEvent("BTQSEND: " + Utils.BytesToHex(cmdData)); }
                radioTransport.EnqueueWrite(GetExpectedResponse(group, cmd), cmdData);
            }
        }

        private void SendCommand(RadioCommandGroup group, RadioBasicCommand cmd, byte[] data)
        {
            if (radioTransport == null) return;
            using (MemoryStream ms = new MemoryStream())
            {
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)group)), 0, 2);
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)cmd)), 0, 2);
                if (data != null) { ms.Write(data, 0, data.Length); }
                byte[] cmdData = ms.ToArray();
                if (PacketTrace) { Debug($"Queue: " + group.ToString() + ", " + cmd.ToString() + ": " + Utils.BytesToHex(cmdData)); }
                else { Program.BlockBoxEvent("BTQSEND: " + Utils.BytesToHex(cmdData)); }
                radioTransport.EnqueueWrite(GetExpectedResponse(group, cmd), cmdData);
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

        public int TransmitTncData(AX25Packet packet, int channelId = -1, int regionId = -1)
        {
            // Get fragment data
            DateTime t = DateTime.Now;
            byte[] outboundData = packet.ToByteArray();
            int i = 0;
            string fragmentChannelName = null;
            if ((Channels != null) && (channelId >= 0) && (channelId < Channels.Length) && (Channels[channelId] != null))
            {
                fragmentChannelName = Channels[channelId].name_str;
            }

            // Create a fragment for eventing that we are sendign this
            TncDataFragment fragment = new TncDataFragment(true, 0, outboundData, channelId, regionId);
            fragment.incoming = false;
            fragment.time = t;
            if (fragmentChannelName != null) { fragment.channel_name = fragmentChannelName; } else { fragment.channel_name = packet.channel_name; }
            if (OnDataFrame != null) { OnDataFrame(this, fragment); }

            if (LoopbackMode == false)
            {
                // Break the packet into fragments and send
                int fragid = 0;
                while (i < outboundData.Length)
                {
                    int fragmentSize = Math.Min(outboundData.Length - i, MAX_MTU);
                    byte[] fragmentData = new byte[fragmentSize];
                    Array.Copy(outboundData, i, fragmentData, 0, fragmentSize);
                    bool isLast = (i + fragmentData.Length) == outboundData.Length;
                    fragment = new TncDataFragment(isLast, fragid, fragmentData, channelId, regionId);
                    TncFragmentQueue.Add(new fragmentInQueue(fragment.toByteArray(), isLast, fragid));
                    i += fragmentSize;
                    fragid++;
                }
                if ((TncFragmentInFlight == false) && (TncFragmentQueue.Count > 0) && (HtStatus.rssi == 0) && (HtStatus.is_in_tx == false))
                {
                    TncFragmentInFlight = true;
                    SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
                }
            }
            else
            {
                // Simulate receiving the frame we just sent
                fragment.incoming = true;
                if (OnDataFrame != null) { OnDataFrame(this, fragment); }
            }

            return outboundData.Length;
        }

    }
}
