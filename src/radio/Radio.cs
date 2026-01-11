/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Net;
using System.Collections.Generic;
using HTCommander.radio;

namespace HTCommander
{
    public class Radio : IDisposable
    {
        #region Constants and Fields

        private const int MAX_MTU = 50;
        private readonly DataBrokerClient broker;

        public int DeviceId { get; }
        public string MacAddress { get; }

        private RadioBluetoothWin radioTransport;
        private TncDataFragment frameAccumulator = null;
        private TncDataFragment lastHardwarePacketReceived = null;
        private RadioState state = RadioState.Disconnected;
        private bool gpsEnabled = false;
        private int gpsLock = 2;

        private List<FragmentInQueue> TncFragmentQueue = new List<FragmentInQueue>();
        private bool TncFragmentInFlight = false;
        private System.Timers.Timer ClearChannelTimer = new System.Timers.Timer();
        private DateTime nextMinFreeChannelTime = DateTime.MaxValue;
        private int nextChannelTimeRandomMS = 800;
        private RadioAudio.SoftwareModemModeType _SoftwareModemMode = RadioAudio.SoftwareModemModeType.Disabled;
        private bool PacketTrace => DataBroker.GetValue<bool>(0, "BluetoothFramesDebug", false);

        #endregion

        #region Enums

        public class CompatibleDevice
        {
            public string name;
            public string mac;
            public CompatibleDevice(string name, string mac) { this.name = name; this.mac = mac; }
        }

        public enum RadioAprsMessageTypes : byte
        {
            UNKNOWN = 0, ERROR = 1, MESSAGE = 2, MESSAGE_ACK = 3, MESSAGE_REJ = 4, SMS_MESSAGE = 5
        }

        private enum RadioCommandGroup : int { BASIC = 2, EXTENDED = 10 }

        private enum RadioBasicCommand : int
        {
            UNKNOWN = 0, GET_DEV_ID = 1, SET_REG_TIMES = 2, GET_REG_TIMES = 3, GET_DEV_INFO = 4,
            READ_STATUS = 5, REGISTER_NOTIFICATION = 6, CANCEL_NOTIFICATION = 7, GET_NOTIFICATION = 8,
            EVENT_NOTIFICATION = 9, READ_SETTINGS = 10, WRITE_SETTINGS = 11, STORE_SETTINGS = 12,
            READ_RF_CH = 13, WRITE_RF_CH = 14, GET_IN_SCAN = 15, SET_IN_SCAN = 16,
            SET_REMOTE_DEVICE_ADDR = 17, GET_TRUSTED_DEVICE = 18, DEL_TRUSTED_DEVICE = 19,
            GET_HT_STATUS = 20, SET_HT_ON_OFF = 21, GET_VOLUME = 22, SET_VOLUME = 23,
            RADIO_GET_STATUS = 24, RADIO_SET_MODE = 25, RADIO_SEEK_UP = 26, RADIO_SEEK_DOWN = 27,
            RADIO_SET_FREQ = 28, READ_ADVANCED_SETTINGS = 29, WRITE_ADVANCED_SETTINGS = 30,
            HT_SEND_DATA = 31, SET_POSITION = 32, READ_BSS_SETTINGS = 33, WRITE_BSS_SETTINGS = 34,
            FREQ_MODE_SET_PAR = 35, FREQ_MODE_GET_STATUS = 36, READ_RDA1846S_AGC = 37,
            WRITE_RDA1846S_AGC = 38, READ_FREQ_RANGE = 39, WRITE_DE_EMPH_COEFFS = 40,
            STOP_RINGING = 41, SET_TX_TIME_LIMIT = 42, SET_IS_DIGITAL_SIGNAL = 43, SET_HL = 44,
            SET_DID = 45, SET_IBA = 46, GET_IBA = 47, SET_TRUSTED_DEVICE_NAME = 48,
            SET_VOC = 49, GET_VOC = 50, SET_PHONE_STATUS = 51, READ_RF_STATUS = 52,
            PLAY_TONE = 53, GET_DID = 54, GET_PF = 55, SET_PF = 56, RX_DATA = 57,
            WRITE_REGION_CH = 58, WRITE_REGION_NAME = 59, SET_REGION = 60, SET_PP_ID = 61,
            GET_PP_ID = 62, READ_ADVANCED_SETTINGS2 = 63, WRITE_ADVANCED_SETTINGS2 = 64,
            UNLOCK = 65, DO_PROG_FUNC = 66, SET_MSG = 67, GET_MSG = 68, BLE_CONN_PARAM = 69,
            SET_TIME = 70, SET_APRS_PATH = 71, GET_APRS_PATH = 72, READ_REGION_NAME = 73,
            SET_DEV_ID = 74, GET_PF_ACTIONS = 75, GET_POSITION = 76
        }

        private enum RadioExtendedCommand : int
        {
            UNKNOWN = 0, GET_BT_SIGNAL = 769, UNKNOWN_01 = 1600, UNKNOWN_02 = 1601,
            UNKNOWN_03 = 1602, UNKNOWN_04 = 16385, UNKNOWN_05 = 16386,
            GET_DEV_STATE_VAR = 16387, DEV_REGISTRATION = 1825
        }

        private enum RadioPowerStatus : int
        {
            UNKNOWN = 0, BATTERY_LEVEL = 1, BATTERY_VOLTAGE = 2,
            RC_BATTERY_LEVEL = 3, BATTERY_LEVEL_AS_PERCENTAGE = 4
        }

        private enum RadioNotification : int
        {
            UNKNOWN = 0, HT_STATUS_CHANGED = 1, DATA_RXD = 2, NEW_INQUIRY_DATA = 3,
            RESTORE_FACTORY_SETTINGS = 4, HT_CH_CHANGED = 5, HT_SETTINGS_CHANGED = 6,
            RINGING_STOPPED = 7, RADIO_STATUS_CHANGED = 8, USER_ACTION = 9, SYSTEM_EVENT = 10,
            BSS_SETTINGS_CHANGED = 11, DATA_TXD = 12, POSITION_CHANGE = 13
        }

        public enum RadioChannelType : int { OFF = 0, A = 1, B = 2 }
        public enum RadioModulationType : int { FM = 0, AM = 1, DMR = 2 }
        public enum RadioBandwidthType : int { NARROW = 0, WIDE = 1 }

        public enum RadioUpdateNotification : int
        {
            State = 1, ChannelInfo = 2, BatteryLevel = 3, BatteryVoltage = 4,
            RcBatteryLevel = 5, BatteryAsPercentage = 6, HtStatus = 7, Settings = 8,
            Volume = 9, AllChannelsLoaded = 10, RegionChange = 11, BssSettings = 12
        }

        public enum RadioState : int
        {
            Disconnected = 1, Connecting = 2, Connected = 3, MultiRadioSelect = 4,
            UnableToConnect = 5, BluetoothNotAvailable = 6, NotRadioFound = 7, AccessDenied = 8
        }

        public enum RadioCommandState : int
        {
            SUCCESS, NOT_SUPPORTED, NOT_AUTHENTICATED, INSUFFICIENT_RESOURCES,
            AUTHENTICATING, INVALID_PARAMETER, INCORRECT_STATE, IN_PROGRESS
        }

        #endregion

        #region Public Properties

        public RadioAudio RadioAudio;
        public RadioDevInfo Info = null;
        public RadioChannelInfo[] Channels = null;
        public RadioHtStatus HtStatus = null;
        public RadioSettings Settings = null;
        public RadioBssSettings BssSettings = null;
        public RadioPosition Position = null;
        public int BatteryLevel = -1;
        public float BatteryVoltage = -1;
        public int RcBatteryLevel = -1;
        public int BatteryAsPercentage = -1;
        public int Volume = -1;
        public bool LoopbackMode = false;
        public string currentChannelName = null;
        public string vfo1ChannelName = null;
        public string vfo2ChannelName = null;
        public bool HardwareModemEnabled = true;

        public RadioState State => state;
        public bool Recording => RadioAudio.Recording;
        public int TransmitQueueLength => TncFragmentQueue.Count;
        public bool AudioState => RadioAudio.IsAudioEnabled;
        public float OutputVolume { get => RadioAudio.Volume; set => RadioAudio.Volume = value; }
        public bool AudioToTextState => RadioAudio.speechToText;

        public RadioAudio.SoftwareModemModeType SoftwareModemMode
        {
            get => _SoftwareModemMode;
            set { _SoftwareModemMode = value; if (RadioAudio != null) RadioAudio.SoftwareModemMode = value; }
        }

        #endregion

        #region Constructor and Disposal

        public Radio(int deviceid, string mac)
        {
            DeviceId = deviceid;
            MacAddress = mac;
            broker = new DataBrokerClient();

            RadioAudio = new RadioAudio(this, deviceid, mac);
            RadioAudio.SoftwareModemMode = _SoftwareModemMode;

            ClearChannelTimer.Elapsed += ClearFrequencyTimer_Elapsed;
            ClearChannelTimer.Enabled = false;
        }

        public void Dispose() => Disconnect(null, RadioState.Disconnected);

        #endregion

        #region Connection Management

        public void Connect()
        {
            if (state == RadioState.Connected || state == RadioState.Connecting) return;
            UpdateState(RadioState.Connecting);
            Debug("Attempting to connect to radio MAC: " + MacAddress);

            radioTransport = new RadioBluetoothWin(this);
            radioTransport.ReceivedData += RadioTransport_ReceivedData;
            radioTransport.OnConnected += RadioTransport_OnConnected;
            radioTransport.Connect();
        }

        public void Disconnect() => Disconnect(null, RadioState.Disconnected);

        public void Disconnect(string msg, RadioState newstate = RadioState.Disconnected)
        {
            if (msg != null) Debug(msg);
            AudioEnabled(false);
            UpdateState(newstate);
            radioTransport.Disconnect();
            Info = null;
            Channels = null;
            HtStatus = null;
            Settings = null;
            frameAccumulator = null;
            TncFragmentQueue.Clear();
            TncFragmentInFlight = false;
            DataBroker.DeleteDevice(DeviceId);
        }

        private void RadioTransport_OnConnected()
        {
            SetVolumeLevel(15); // DEBUG
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_DEV_INFO, 3);
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_SETTINGS, null);
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_BSS_SETTINGS, null);
            RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE);
        }

        private void UpdateState(RadioState newstate)
        {
            if (state == newstate) return;
            state = newstate;
            broker.Dispatch(DeviceId, "State", newstate.ToString(), store: true);
            Debug("State changed to: " + newstate);
            Update(RadioUpdateNotification.State);
        }

        #endregion

        #region Audio Management

        public void AudioEnabled(bool enabled)
        {
            if (enabled) RadioAudio.Start();
            else RadioAudio.Stop();
        }

        #endregion

        #region Channel Management

        public RadioChannelInfo GetChannelByFrequency(float freq, RadioModulationType mod)
        {
            if (Channels == null) return null;
            int xfreq = (int)Math.Round(freq * 1000000);
            foreach (var ch in Channels)
            {
                if (ch.rx_freq == xfreq && ch.tx_freq == xfreq && ch.rx_mod == mod && ch.tx_mod == mod)
                    return ch;
            }
            return null;
        }

        public RadioChannelInfo GetChannelByName(string name)
        {
            if (Channels == null) return null;
            foreach (var ch in Channels)
            {
                if (ch.name_str == name) return ch;
            }
            return null;
        }

        public bool AllChannelsLoaded()
        {
            if (Channels == null) return false;
            foreach (var ch in Channels) { if (ch == null) return false; }
            return true;
        }

        public void SetChannel(RadioChannelInfo channel)
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.WRITE_RF_CH, channel.ToByteArray());
        }

        public void SetRegion(int region)
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.SET_REGION, (byte)region);
        }

        private void UpdateChannels()
        {
            if (state != RadioState.Connected || Info == null) return;
            for (byte i = 0; i < Info.channel_count; i++)
            {
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_RF_CH, i);
            }
        }

        private void UpdateCurrentChannelName()
        {
            if (HtStatus == null) return;

            currentChannelName = RadioAudio.currentChannelName = GetChannelNameById(HtStatus.curr_ch_id);
        }

        private void UpdateVfoChannelNames()
        {
            if (Settings == null) return;

            vfo1ChannelName = GetChannelNameById(Settings.channel_a);
            vfo2ChannelName = GetChannelNameById(Settings.channel_b);
        }

        private string GetChannelNameById(int channelId)
        {
            if (channelId >= 254) return "NOAA";
            if (Channels != null && Channels.Length > channelId && Channels[channelId] != null)
                return Channels[channelId].name_str;
            return string.Empty;
        }

        public bool IsOnMuteChannel()
        {
            if (state != RadioState.Connected || Channels == null || HtStatus == null) return true;
            if (HtStatus.curr_ch_id == 254) return false; // NOAA never muted
            if (HtStatus.curr_ch_id >= Channels.Length) return true;
            if (Channels[HtStatus.curr_ch_id] == null) return true;
            return Channels[HtStatus.curr_ch_id].mute;
        }

        #endregion

        #region GPS Management

        public void GpsEnabled(bool enabled)
        {
            if (gpsEnabled == enabled) return;
            gpsEnabled = enabled;
            if (state == RadioState.Connected)
            {
                gpsLock = 2;
                var cmd = gpsEnabled ? RadioBasicCommand.REGISTER_NOTIFICATION : RadioBasicCommand.CANCEL_NOTIFICATION;
                SendCommand(RadioCommandGroup.BASIC, cmd, (int)RadioNotification.POSITION_CHANGE);
            }
        }

        public void GetPosition()
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_POSITION, null);
        }

        #endregion

        #region Settings and Status

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
            if (level < 0 || level > 15) return;
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.SET_VOLUME, new byte[] { (byte)level });
        }

        public void SetSquelchLevel(int level)
        {
            WriteSettings(Settings.ToByteArray(Settings.channel_a, Settings.channel_b, Settings.double_channel, Settings.scan, level));
        }

        public void SetBssSettings(RadioBssSettings bss)
        {
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.WRITE_BSS_SETTINGS, bss.ToByteArray());
        }

        public void GetBatteryLevel() => RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL);
        public void GetBatteryVoltage() => RequestPowerStatus(RadioPowerStatus.BATTERY_VOLTAGE);
        public void GetBatteryRcLevel() => RequestPowerStatus(RadioPowerStatus.RC_BATTERY_LEVEL);
        public void GetBatteryLevelAtPercentage() => RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE);

        private void RequestPowerStatus(RadioPowerStatus powerStatus)
        {
            byte[] data = new byte[2];
            data[1] = (byte)powerStatus;
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_STATUS, data);
        }

        private bool IsTncFree() => HtStatus != null && !HtStatus.is_in_tx && !HtStatus.is_in_rx;

        #endregion

        #region Clear Channel Timer

        public void SetNextChannelTimeRandom(int ms) => nextChannelTimeRandomMS = ms;

        public void SetNextFreeChannelTime(DateTime time)
        {
            nextMinFreeChannelTime = time;
            ClearChannelTimer.Stop();

            if (nextMinFreeChannelTime == DateTime.MaxValue) return;

            if (IsTncFree())
            {
                int delta = CalculateClearChannelDelay();
                if (delta > 0)
                {
                    ClearChannelTimer.Interval = delta;
                    ClearChannelTimer.Start();
                }
            }
        }

        private void ChannelState(bool channelFree)
        {
            if (channelFree == ClearChannelTimer.Enabled) return;
            ClearChannelTimer.Stop();

            if (channelFree)
            {
                int delta = CalculateClearChannelDelay();
                if (delta > 0)
                {
                    ClearChannelTimer.Interval = delta;
                    ClearChannelTimer.Start();
                }
            }
        }

        private int CalculateClearChannelDelay()
        {
            int randomDelay = 800 + new Random().Next(0, nextChannelTimeRandomMS);
            if (nextMinFreeChannelTime <= DateTime.Now)
                return randomDelay;
            return (int)(nextMinFreeChannelTime - DateTime.Now).TotalMilliseconds + randomDelay;
        }

        private void ClearFrequencyTimer_Elapsed(object sender, System.Timers.ElapsedEventArgs e)
        {
            ClearChannelTimer.Stop();
            broker.Dispatch(DeviceId, "ChannelClear", null, store: false);
        }

        #endregion

        #region Transmit Queue Management

        public void DeleteTransmitByTag(string tag)
        {
            lock (TncFragmentQueue)
            {
                foreach (var f in TncFragmentQueue) { if (f.tag == tag) f.deleted = true; }
            }
        }

        private void ClearTransmitQueue()
        {
            lock (TncFragmentQueue)
            {
                if (TncFragmentQueue.Count == 0 || TncFragmentQueue[0].fragid != 0) return;
                DateTime now = DateTime.Now;
                for (int i = 0; i < TncFragmentQueue.Count; i++)
                {
                    if (TncFragmentQueue[i].deleted || DateTime.Compare(TncFragmentQueue[i].deadline, now) <= 0)
                    {
                        TncFragmentQueue.RemoveAt(i);
                        i--;
                    }
                }
            }
        }

        private class FragmentInQueue
        {
            public byte[] fragment;
            public bool isLast;
            public int fragid;
            public string tag;
            public DateTime deadline;
            public bool deleted;

            public FragmentInQueue(byte[] fragment, bool isLast, int fragid)
            {
                this.fragment = fragment;
                this.isLast = isLast;
                this.fragid = fragid;
            }
        }

        #endregion

        #region Data Transmission

        public int TransmitTncData(AX25Packet packet, int channelId = -1, int regionId = -1)
        {
            byte[] outboundData = packet.ToByteArray();
            if (outboundData == null) return 0;

            DateTime t = DateTime.Now;
            string fragmentChannelName = GetFragmentChannelName(channelId, packet.channel_name);
            TncDataFragment fragment = CreateOutboundFragment(outboundData, channelId, regionId, t, fragmentChannelName);

            if (LoopbackMode)
            {
                TransmitLoopback(fragment, outboundData, channelId, regionId, t, fragmentChannelName);
            }
            else if (RadioAudio.IsAudioEnabled && RadioAudio.SoftwareModemMode != RadioAudio.SoftwareModemModeType.Disabled && Settings.channel_a == channelId)
            {
                TransmitSoftwareModem(fragment);
            }
            else if (HardwareModemEnabled)
            {
                TransmitHardwareModem(fragment, outboundData, channelId, regionId, packet);
            }

            return outboundData.Length;
        }

        private string GetFragmentChannelName(int channelId, string fallback)
        {
            if (Channels != null && channelId >= 0 && channelId < Channels.Length && Channels[channelId] != null)
                return Channels[channelId].name_str;
            return fallback;
        }

        private TncDataFragment CreateOutboundFragment(byte[] data, int channelId, int regionId, DateTime time, string channelName)
        {
            var fragment = new TncDataFragment(true, 0, data, channelId, regionId);
            fragment.incoming = false;
            fragment.time = time;
            fragment.channel_name = channelName ?? string.Empty;
            return fragment;
        }

        private void TransmitLoopback(TncDataFragment fragment, byte[] data, int channelId, int regionId, DateTime time, string channelName)
        {
            fragment.encoding = TncDataFragment.FragmentEncodingType.Loopback;
            fragment.frame_type = TncDataFragment.FragmentFrameType.AX25;
            DispatchDataFrame(fragment);

            // Simulate receiving the frame
            var fragment2 = new TncDataFragment(true, 0, data, channelId, regionId);
            fragment2.incoming = true;
            fragment2.time = time;
            fragment2.encoding = TncDataFragment.FragmentEncodingType.Loopback;
            fragment2.frame_type = TncDataFragment.FragmentFrameType.AX25;
            fragment2.channel_name = channelName ?? string.Empty;
            DispatchDataFrame(fragment2);
        }

        private void TransmitSoftwareModem(TncDataFragment fragment)
        {
            fragment.encoding = RadioAudio.SoftwareModemMode switch
            {
                RadioAudio.SoftwareModemModeType.Afsk1200 => TncDataFragment.FragmentEncodingType.SoftwareAfsk1200,
                RadioAudio.SoftwareModemModeType.G3RUH9600 => TncDataFragment.FragmentEncodingType.SoftwareG3RUH9600,
                RadioAudio.SoftwareModemModeType.Psk2400 => TncDataFragment.FragmentEncodingType.SoftwarePsk2400,
                RadioAudio.SoftwareModemModeType.Psk4800 => TncDataFragment.FragmentEncodingType.SoftwarePsk4800,
                _ => fragment.encoding
            };
            fragment.frame_type = TncDataFragment.FragmentFrameType.FX25;
            DispatchDataFrame(fragment);
            RadioAudio.TransmitPacket(fragment);
        }

        private void TransmitHardwareModem(TncDataFragment fragment, byte[] outboundData, int channelId, int regionId, AX25Packet packet)
        {
            fragment.encoding = TncDataFragment.FragmentEncodingType.HardwareAfsk1200;
            fragment.frame_type = TncDataFragment.FragmentFrameType.AX25;
            DispatchDataFrame(fragment);

            // Fragment data for Bluetooth MTU
            int i = 0, fragid = 0;
            while (i < outboundData.Length)
            {
                int fragmentSize = Math.Min(outboundData.Length - i, MAX_MTU);
                byte[] fragmentData = new byte[fragmentSize];
                Array.Copy(outboundData, i, fragmentData, 0, fragmentSize);
                bool isLast = (i + fragmentData.Length) == outboundData.Length;

                var tncFragment = new TncDataFragment(isLast, fragid, fragmentData, channelId, regionId);
                var fragmentInQueue = new FragmentInQueue(tncFragment.toByteArray(), isLast, fragid)
                {
                    tag = packet.tag,
                    deadline = packet.deadline
                };
                TncFragmentQueue.Add(fragmentInQueue);

                i += fragmentSize;
                fragid++;
            }

            if (!TncFragmentInFlight && TncFragmentQueue.Count > 0 && HtStatus.rssi == 0 && !HtStatus.is_in_tx)
            {
                TncFragmentInFlight = true;
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
            }
        }

        #endregion

        #region Command Handling

        public void SendRawCommand(byte[] rawcmd)
        {
            byte[] data = new byte[rawcmd.Length - 4];
            Array.Copy(rawcmd, 4, data, 0, rawcmd.Length - 4);
            RadioCommandGroup group = (RadioCommandGroup)Utils.GetShort(rawcmd, 0);
            RadioBasicCommand cmd = (RadioBasicCommand)Utils.GetShort(rawcmd, 2);

            // Return cached responses if available
            if (group == RadioCommandGroup.BASIC)
            {
                if (cmd == RadioBasicCommand.GET_DEV_INFO && Info != null) { DispatchRawCommand(Info.raw); return; }
                if (cmd == RadioBasicCommand.READ_SETTINGS && Settings != null) { DispatchRawCommand(Settings.rawData); return; }
                if (cmd == RadioBasicCommand.GET_HT_STATUS && HtStatus != null) { DispatchRawCommand(HtStatus.raw); return; }
                if (cmd == RadioBasicCommand.READ_RF_CH && Channels != null && Channels.Length > rawcmd[4] && Channels[rawcmd[4]] != null)
                {
                    DispatchRawCommand(Channels[rawcmd[4]].raw);
                    return;
                }
            }

            SendCommand(group, cmd, data);
        }

        private void SendCommand(RadioCommandGroup group, RadioBasicCommand cmd, byte data)
        {
            if (radioTransport == null) return;
            using (var ms = new MemoryStream())
            {
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)group)), 0, 2);
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)cmd)), 0, 2);
                ms.WriteByte(data);
                byte[] cmdData = ms.ToArray();
                LogCommand(group, cmd, cmdData);
                radioTransport.EnqueueWrite(GetExpectedResponse(group, cmd), cmdData);
            }
        }

        private void SendCommand(RadioCommandGroup group, RadioBasicCommand cmd, byte[] data)
        {
            if (radioTransport == null) return;
            using (var ms = new MemoryStream())
            {
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)group)), 0, 2);
                ms.Write(BitConverter.GetBytes(IPAddress.HostToNetworkOrder((short)cmd)), 0, 2);
                if (data != null) ms.Write(data, 0, data.Length);
                byte[] cmdData = ms.ToArray();
                LogCommand(group, cmd, cmdData);
                radioTransport.EnqueueWrite(GetExpectedResponse(group, cmd), cmdData);
            }
        }

        private void LogCommand(RadioCommandGroup group, RadioBasicCommand cmd, byte[] cmdData)
        {
            if (PacketTrace) Debug($"Queue: {group}, {cmd}: {Utils.BytesToHex(cmdData)}");
            else Program.BlockBoxEvent("BTQSEND: " + Utils.BytesToHex(cmdData));
        }

        private int GetExpectedResponse(RadioCommandGroup group, RadioBasicCommand cmd)
        {
            switch (cmd)
            {
                case RadioBasicCommand.REGISTER_NOTIFICATION:
                case RadioBasicCommand.WRITE_SETTINGS:
                case RadioBasicCommand.SET_REGION:
                    return -1;
            }
            int rcmd = (int)cmd | 0x8000;
            return ((int)group << 16) + rcmd;
        }

        #endregion

        #region Response Handling

        private void RadioTransport_ReceivedData(RadioBluetoothWin sender, Exception error, byte[] value)
        {
            if (state != RadioState.Connected && state != RadioState.Connecting) return;
            if (error != null) { Debug("Notification ERROR SET"); }
            if (value == null) { Debug("Notification: NULL"); return; }

            if (PacketTrace) Debug("-----> " + Utils.BytesToHex(value));
            else Program.BlockBoxEvent("-----> " + Utils.BytesToHex(value));

            RadioCommandGroup group = (RadioCommandGroup)Utils.GetShort(value, 0);
            DispatchRawCommand(value);

            switch (group)
            {
                case RadioCommandGroup.BASIC:
                    HandleBasicCommand(value);
                    break;
                case RadioCommandGroup.EXTENDED:
                    HandleExtendedCommand(value);
                    break;
                default:
                    Debug("Unexpected Command Group: " + group);
                    break;
            }
        }

        private void HandleBasicCommand(byte[] value)
        {
            RadioBasicCommand cmd = (RadioBasicCommand)(Utils.GetShort(value, 2) & 0x7FFF);
            if (PacketTrace && cmd != RadioBasicCommand.EVENT_NOTIFICATION)
                Debug($"Response 'BASIC' / '{cmd}'");

            switch (cmd)
            {
                case RadioBasicCommand.GET_DEV_INFO:
                    HandleGetDevInfo(value);
                    break;
                case RadioBasicCommand.READ_RF_CH:
                    HandleReadRfChannel(value);
                    break;
                case RadioBasicCommand.WRITE_RF_CH:
                    if (value[4] == 0) SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_RF_CH, value[5]);
                    break;
                case RadioBasicCommand.READ_BSS_SETTINGS:
                    BssSettings = new RadioBssSettings(value);
                    Update(RadioUpdateNotification.BssSettings);
                    break;
                case RadioBasicCommand.WRITE_BSS_SETTINGS:
                    if (value[4] != 0) Debug($"WRITE_BSS_SETTINGS Error: '{value[4]}'");
                    else SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_BSS_SETTINGS, null);
                    break;
                case RadioBasicCommand.EVENT_NOTIFICATION:
                    HandleEventNotification(value);
                    break;
                case RadioBasicCommand.READ_STATUS:
                    HandleReadStatus(value);
                    break;
                case RadioBasicCommand.READ_SETTINGS:
                    Settings = new RadioSettings(value);
                    Update(RadioUpdateNotification.Settings);
                    break;
                case RadioBasicCommand.HT_SEND_DATA:
                    HandleHtSendDataResponse(value);
                    break;
                case RadioBasicCommand.SET_VOLUME:
                    break;
                case RadioBasicCommand.GET_VOLUME:
                    Volume = value[5];
                    Update(RadioUpdateNotification.Volume);
                    break;
                case RadioBasicCommand.WRITE_SETTINGS:
                    if (value[4] != 0) Debug("WRITE_SETTINGS ERROR: " + Utils.BytesToHex(value));
                    break;
                case RadioBasicCommand.SET_REGION:
                    break;
                case RadioBasicCommand.GET_POSITION:
                    Position = new RadioPosition(value);
                    DispatchPositionUpdate(Position);
                    break;
                case RadioBasicCommand.GET_HT_STATUS:
                    HandleGetHtStatus(value);
                    break;
                default:
                    Debug("Unexpected Basic Command: " + cmd);
                    Debug(Utils.BytesToHex(value));
                    break;
            }
        }

        private void HandleGetDevInfo(byte[] value)
        {
            Info = new RadioDevInfo(value);
            Channels = new RadioChannelInfo[Info.channel_count];
            UpdateState(RadioState.Connected);
            broker.Dispatch(DeviceId, "DeviceInfo", Info, store: true);
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.REGISTER_NOTIFICATION, (int)RadioNotification.HT_STATUS_CHANGED);
            if (gpsEnabled)
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.REGISTER_NOTIFICATION, (int)RadioNotification.POSITION_CHANGE);
        }

        private void HandleReadRfChannel(byte[] value)
        {
            RadioChannelInfo c = new RadioChannelInfo(value);
            if (Channels != null) Channels[c.channel_id] = c;

            UpdateCurrentChannelName();
            UpdateVfoChannelNames();
            Update(RadioUpdateNotification.ChannelInfo);
            if (AllChannelsLoaded()) Update(RadioUpdateNotification.AllChannelsLoaded);
        }

        private void HandleEventNotification(byte[] value)
        {
            RadioNotification notify = (RadioNotification)value[4];
            if (PacketTrace) Debug($"Response 'BASIC' / 'EVENT_NOTIFICATION' / '{notify}'");

            switch (notify)
            {
                case RadioNotification.HT_STATUS_CHANGED:
                    HandleHtStatusChanged(value);
                    break;
                case RadioNotification.DATA_RXD:
                    HandleDataReceived(value);
                    break;
                case RadioNotification.HT_SETTINGS_CHANGED:
                    Settings = new RadioSettings(value);
                    UpdateVfoChannelNames();
                    Update(RadioUpdateNotification.Settings);
                    break;
                case RadioNotification.POSITION_CHANGE:
                    value[4] = 0; // Set status to success
                    Position = new RadioPosition(value);
                    if (gpsLock > 0) gpsLock--;
                    Position.Locked = (gpsLock == 0);
                    DispatchPositionUpdate(Position);
                    break;
                default:
                    Debug("Event: " + Utils.BytesToHex(value));
                    break;
            }
        }

        private void HandleHtStatusChanged(byte[] value)
        {
            int oldRegion = HtStatus?.curr_region ?? -1;
            HtStatus = new RadioHtStatus(value);
            Update(RadioUpdateNotification.HtStatus);
            if (HtStatus == null) return;

            if (oldRegion != HtStatus.curr_region)
            {
                Update(RadioUpdateNotification.RegionChange);
                if (Channels != null) Array.Clear(Channels, 0, Channels.Length);
                Update(RadioUpdateNotification.ChannelInfo);
                UpdateChannels();
            }

            UpdateCurrentChannelName();
            ProcessTncQueue();
        }

        private void HandleDataReceived(byte[] value)
        {
            if (!HardwareModemEnabled) return;
            Debug("RawData: " + Utils.BytesToHex(value));

            TncDataFragment fragment = new TncDataFragment(value);
            fragment.encoding = TncDataFragment.FragmentEncodingType.HardwareAfsk1200;
            fragment.corrections = 0;
            if (fragment.channel_id == -1 && HtStatus != null) fragment.channel_id = HtStatus.curr_ch_id;
            fragment.channel_name = GetDataFragmentChannelName(fragment.channel_id);

            Debug($"DataFragment, FragId={fragment.fragment_id}, IsFinal={fragment.final_fragment}, ChannelId={fragment.channel_id}, DataLen={fragment.data.Length}");

            AccumulateFragment(fragment);
        }

        private string GetDataFragmentChannelName(int channelId)
        {
            if (channelId >= 0 && Channels != null && channelId < Channels.Length && Channels[channelId] != null)
            {
                if (Channels[channelId].name_str.Length > 0)
                    return Channels[channelId].name_str.Replace(",", "");
                if (Channels[channelId].rx_freq != 0)
                    return (Channels[channelId].rx_freq / 1000000.0) + " Mhz";
            }
            return (channelId + 1).ToString();
        }

        private void AccumulateFragment(TncDataFragment fragment)
        {
            if (frameAccumulator == null)
            {
                if (fragment.fragment_id == 0) frameAccumulator = fragment;
            }
            else
            {
                frameAccumulator = frameAccumulator.Append(fragment);
            }

            if (frameAccumulator != null && frameAccumulator.final_fragment)
            {
                TncDataFragment packet = frameAccumulator;
                frameAccumulator = null;
                packet.incoming = true;
                packet.time = DateTime.Now;
                lastHardwarePacketReceived = packet;
                DispatchDataFrame(packet);
            }
        }

        private void HandleReadStatus(byte[] value)
        {
            RadioPowerStatus powerStatus = (RadioPowerStatus)Utils.GetShort(value, 5);
            switch (powerStatus)
            {
                case RadioPowerStatus.BATTERY_LEVEL:
                    BatteryLevel = value[7];
                    Debug("BatteryLevel: " + BatteryLevel);
                    Update(RadioUpdateNotification.BatteryLevel);
                    break;
                case RadioPowerStatus.BATTERY_VOLTAGE:
                    BatteryVoltage = Utils.GetShort(value, 7) / 1000f;
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
                    Update(RadioUpdateNotification.BatteryAsPercentage);
                    break;
                default:
                    Debug("Unexpected Power Status: " + powerStatus);
                    break;
            }
        }

        private void HandleHtSendDataResponse(byte[] value)
        {
            ClearTransmitQueue();
            if (TncFragmentQueue.Count == 0) { TncFragmentInFlight = false; return; }

            bool channelFree = IsTncFree();
            RadioCommandState errorCode = (RadioCommandState)value[4];

            if (errorCode == RadioCommandState.INCORRECT_STATE)
            {
                if (TncFragmentQueue[0].fragid == 0)
                {
                    if (channelFree)
                    {
                        TncFragmentInFlight = true;
                        Debug("TNC Fragment failed, TRYING AGAIN.");
                        SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
                    }
                    else
                    {
                        TncFragmentInFlight = false;
                    }
                    return;
                }
                else
                {
                    Debug("TNC Fragment failed, check Bluetooth connection.");
                    while (TncFragmentQueue.Count > 0 && !TncFragmentQueue[0].isLast) TncFragmentQueue.RemoveAt(0);
                    if (TncFragmentQueue.Count > 0) TncFragmentQueue.RemoveAt(0);
                }
            }
            else
            {
                TncFragmentQueue.RemoveAt(0);
            }

            // Continue sending if more fragments available
            if (TncFragmentQueue.Count > 0 && (TncFragmentQueue[0].fragid != 0 || channelFree))
            {
                channelFree = false;
                TncFragmentInFlight = true;
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
            }
            else
            {
                TncFragmentInFlight = false;
            }

            ChannelState(channelFree);
        }

        private void HandleGetHtStatus(byte[] value)
        {
            int oldRegion = HtStatus?.curr_region ?? -1;
            HtStatus = new RadioHtStatus(value);
            Update(RadioUpdateNotification.HtStatus);
            if (HtStatus == null) return;

            if (oldRegion != HtStatus.curr_region)
            {
                Update(RadioUpdateNotification.RegionChange);
                if (Channels != null) Array.Clear(Channels, 0, Channels.Length);
                Update(RadioUpdateNotification.ChannelInfo);
                UpdateChannels();
            }

            UpdateCurrentChannelName();
            ProcessTncQueue();
        }

        private void ProcessTncQueue()
        {
            ClearTransmitQueue();
            bool channelFree = IsTncFree();

            if (channelFree && !TncFragmentInFlight && TncFragmentQueue.Count > 0)
            {
                channelFree = false;
                TncFragmentInFlight = true;
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.HT_SEND_DATA, TncFragmentQueue[0].fragment);
            }
            else if (TncFragmentInFlight && HtStatus.is_in_rx)
            {
                TncFragmentInFlight = false;
            }

            ChannelState(channelFree);
        }

        private void HandleExtendedCommand(byte[] value)
        {
            RadioExtendedCommand xcmd = (RadioExtendedCommand)(Utils.GetShort(value, 2) & 0x7FFF);
            if (PacketTrace) Debug($"Response 'EXTENDED' / '{xcmd}'");
            Debug("Unexpected Extended Command: " + xcmd);
        }

        #endregion

        #region Dispatch Helpers

        public void Debug(string msg) => broker.Dispatch(0, "LogInfo", $"[Radio/{DeviceId}]: {msg}", store: false);
        private void Update(RadioUpdateNotification msg) => broker.Dispatch(DeviceId, "State", msg.ToString(), store: true);
        private void DispatchDataFrame(TncDataFragment frame) => broker.Dispatch(DeviceId, "DataFrame", frame, store: false);
        private void DispatchPositionUpdate(RadioPosition position) => broker.Dispatch(DeviceId, "PositionUpdate", position, store: false);
        private void DispatchRawCommand(byte[] cmd) => broker.Dispatch(DeviceId, "RawCommand", cmd, store: false);

        #endregion
    }
}
