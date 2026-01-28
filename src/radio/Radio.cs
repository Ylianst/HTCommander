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
        public string FriendlyName { get; private set; }

        private RadioBluetoothWin radioTransport;
        private TncDataFragment frameAccumulator = null;
        private RadioState state = RadioState.Disconnected;
        private bool _gpsEnabled = false;
        private int gpsLock = 2;

        private List<FragmentInQueue> TncFragmentQueue = new List<FragmentInQueue>();
        private bool TncFragmentInFlight = false;
        private System.Timers.Timer ClearChannelTimer = new System.Timers.Timer();
        private DateTime nextMinFreeChannelTime = DateTime.MaxValue;
        private int nextChannelTimeRandomMS = 800;
        private RadioAudio.SoftwareModemModeType _SoftwareModemMode = RadioAudio.SoftwareModemModeType.Disabled;
        private bool PacketTrace => DataBroker.GetValue<bool>(0, "BluetoothFramesDebug", false);
        private bool LoopbackMode => DataBroker.GetValue<bool>(1, "LoopbackMode", false);
        private bool AllowTransmit => DataBroker.GetValue<bool>(0, "AllowTransmit", false);

        // Lock state fields
        private RadioLockState lockState = null;
        private int savedRegionId = -1;
        private int savedChannelId = -1;
        private bool savedScan = false;
        private int savedDualWatch = 0;

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
        public bool HardwareModemEnabled = true;

        public RadioState State => state;
        public bool Recording => RadioAudio?.Recording ?? false;
        public int TransmitQueueLength => TncFragmentQueue.Count;
        public bool AudioState => RadioAudio?.IsAudioEnabled ?? false;
        public float OutputVolume { get => RadioAudio?.Volume ?? 0; set { if (RadioAudio != null) RadioAudio.Volume = value; } }

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

            // Subscribe to channel change events
            broker.Subscribe(deviceid, new[] { "ChannelChangeVfoA", "ChannelChangeVfoB" }, OnChannelChangeEvent);

            // Subscribe to settings change events from UI
            broker.Subscribe(deviceid, new[] { "WriteSettings", "SetRegion", "DualWatch", "Scan", "SetGPS", "Region" }, OnSettingsChangeEvent);

            // Subscribe to channel write events (for updating individual channels)
            broker.Subscribe(deviceid, "WriteChannel", OnWriteChannelEvent);

            // Subscribe to GetPosition event (for refreshing GPS position)
            broker.Subscribe(deviceid, "GetPosition", OnGetPositionEvent);

            // Subscribe to TransmitDataFrame event (for transmitting AX.25 packets)
            broker.Subscribe(deviceid, "TransmitDataFrame", OnTransmitDataFrameEvent);

            // Subscribe to SetBssSettings event (for updating beacon settings from UI)
            broker.Subscribe(deviceid, "SetBssSettings", OnSetBssSettingsEvent);

            // Subscribe to lock/unlock events
            broker.Subscribe(deviceid, "SetLock", OnSetLockEvent);
            broker.Subscribe(deviceid, "SetUnlock", OnSetUnlockEvent);

            // Subscribe to audio control events
            broker.Subscribe(deviceid, "SetAudio", OnSetAudioEvent);
            
            // Subscribe to volume and squelch control events
            broker.Subscribe(deviceid, "SetVolumeLevel", OnSetVolumeLevelEvent);
            broker.Subscribe(deviceid, "SetSquelchLevel", OnSetSquelchLevelEvent);
        }
        
        /// <summary>
        /// Handles SetVolumeLevel event from the broker (for setting radio hardware volume).
        /// </summary>
        private void OnSetVolumeLevelEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (data is int level)
            {
                SetVolumeLevel(level);
            }
        }
        
        /// <summary>
        /// Handles SetSquelchLevel event from the broker (for setting squelch level).
        /// </summary>
        private void OnSetSquelchLevelEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (data is int level && Settings != null)
            {
                SetSquelchLevel(level);
            }
        }

        /// <summary>
        /// Handles channel change events from the broker.
        /// </summary>
        private void OnChannelChangeEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (Settings == null) return;

            // Ignore channel changes when radio is locked
            if (lockState != null) return;

            int channelId = (int)data;

            switch (name)
            {
                case "ChannelChangeVfoA":
                    // Change VFO A to the new channel
                    WriteSettings(Settings.ToByteArray(channelId, Settings.channel_b, Settings.double_channel, Settings.scan, Settings.squelch_level));
                    break;
                case "ChannelChangeVfoB":
                    // Change VFO B to the new channel
                    WriteSettings(Settings.ToByteArray(Settings.channel_a, channelId, Settings.double_channel, Settings.scan, Settings.squelch_level));
                    break;
            }
        }

        /// <summary>
        /// Handles settings change events from the broker (from UI like RadioForm).
        /// </summary>
        private void OnSettingsChangeEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;

            switch (name)
            {
                case "WriteSettings":
                    // Ignore WriteSettings when radio is locked
                    if (lockState != null) return;
                    // Write the new settings to the radio
                    if (data is byte[] settingsData)
                    {
                        WriteSettings(settingsData);
                    }
                    break;
                case "SetRegion":
                case "Region":
                    // Ignore region changes when radio is locked
                    if (lockState != null) return;
                    // Set the region
                    if (data is int regionId)
                    {
                        SetRegion(regionId);
                    }
                    break;
                case "SetGPS":
                    // Toggle GPS (allowed even when locked)
                    if (data is bool gpsState)
                    {
                        GpsEnabled(gpsState);
                    }
                    break;
                case "DualWatch":
                    // Ignore dual-watch changes when radio is locked
                    if (lockState != null) return;
                    // Toggle dual-watch
                    if (Settings != null && data is bool dualWatchEnabled)
                    {
                        int newDoubleChannel = dualWatchEnabled ? 1 : 0;
                        WriteSettings(Settings.ToByteArray(Settings.channel_a, Settings.channel_b, newDoubleChannel, Settings.scan, Settings.squelch_level));
                    }
                    break;
                case "Scan":
                    // Ignore scan changes when radio is locked
                    if (lockState != null) return;
                    // Toggle scan
                    if (Settings != null && data is bool scanEnabled)
                    {
                        WriteSettings(Settings.ToByteArray(Settings.channel_a, Settings.channel_b, Settings.double_channel, scanEnabled, Settings.squelch_level));
                    }
                    break;
            }
        }

        /// <summary>
        /// Handles channel write events from the broker (for updating individual channel settings).
        /// </summary>
        private void OnWriteChannelEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (data is RadioChannelInfo channel)
            {
                SetChannel(channel);
            }
        }

        /// <summary>
        /// Handles GetPosition event from the broker (for refreshing GPS position on demand).
        /// </summary>
        private void OnGetPositionEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            GetPosition();
        }

        /// <summary>
        /// Handles TransmitDataFrame event from the broker (for transmitting AX.25 packets).
        /// </summary>
        private void OnTransmitDataFrameEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (!(data is TransmitDataFrameData txData)) return;

            // Set the channel ID on the packet if provided
            if (txData.ChannelId >= 0)
            {
                txData.Packet.channel_id = txData.ChannelId;
            }

            // Transmit the packet
            TransmitTncData(txData.Packet, txData.ChannelId, txData.RegionId);
        }

        /// <summary>
        /// Handles SetBssSettings event from the broker (for updating beacon settings from UI).
        /// </summary>
        private void OnSetBssSettingsEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (data is RadioBssSettings bssSettings)
            {
                SetBssSettings(bssSettings);
            }
        }

        /// <summary>
        /// Handles SetLock event from the broker to lock the radio to a specific channel/region.
        /// </summary>
        private void OnSetLockEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (!(data is SetLockData lockData)) return;

            // Ignore if already locked
            if (lockState != null) return;

            // Ensure we have settings and HtStatus to save current state
            if (Settings == null || HtStatus == null) return;

            // Save current state
            savedRegionId = HtStatus.curr_region;
            savedChannelId = Settings.channel_a;
            savedScan = Settings.scan;
            savedDualWatch = Settings.double_channel;

            // Create and store the lock state
            lockState = new RadioLockState
            {
                IsLocked = true,
                Usage = lockData.Usage,
                RegionId = lockData.RegionId,
                ChannelId = lockData.ChannelId
            };

            // Dispatch that we are now in locked state
            broker.Dispatch(DeviceId, "LockState", lockState, store: true);
            Debug($"Radio locked for usage '{lockData.Usage}' - Region: {lockData.RegionId}, Channel: {lockData.ChannelId}");

            // Apply lock settings: disable scanning and dual-watch, change channel
            // First, change region if different
            if (lockData.RegionId != HtStatus.curr_region)
            {
                SetRegion(lockData.RegionId);
            }

            // Then write settings with scan disabled, dual-watch disabled, and new channel
            WriteSettings(Settings.ToByteArray(lockData.ChannelId, Settings.channel_b, 0, false, Settings.squelch_level));
        }

        /// <summary>
        /// Handles SetAudio event from the broker to enable/disable audio streaming.
        /// </summary>
        private void OnSetAudioEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (data is bool audioEnabled)
            {
                AudioEnabled(audioEnabled);
            }
        }

        /// <summary>
        /// Handles SetUnlock event from the broker to unlock the radio and restore previous settings.
        /// </summary>
        private void OnSetUnlockEvent(int deviceId, string name, object data)
        {
            if (deviceId != DeviceId) return;
            if (!(data is SetUnlockData unlockData)) return;

            // Ignore if not locked
            if (lockState == null) return;

            // Ignore if usage doesn't match
            if (lockState.Usage != unlockData.Usage) return;

            // Ensure we have settings to restore
            if (Settings == null) return;

            Debug($"Radio unlocked from usage '{unlockData.Usage}' - Restoring previous settings");

            // Restore previous region if different
            if (HtStatus != null && savedRegionId != HtStatus.curr_region && savedRegionId >= 0)
            {
                SetRegion(savedRegionId);
            }

            // Restore previous settings: channel, scan, dual-watch
            WriteSettings(Settings.ToByteArray(savedChannelId, Settings.channel_b, savedDualWatch, savedScan, Settings.squelch_level));

            // Clear the lock state
            lockState = null;

            // Dispatch that we are now unlocked
            var unlockedState = new RadioLockState
            {
                IsLocked = false,
                Usage = null,
                RegionId = -1,
                ChannelId = -1
            };
            broker.Dispatch(DeviceId, "LockState", unlockedState, store: true);
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

            // Dispose RadioAudio to clean up its resources and data broker
            RadioAudio?.Dispose();
            RadioAudio = null;

            // Dispatch null values through the Data Broker to notify subscribers of disconnection
            broker.Dispatch(DeviceId, "Info", null, store: true);
            broker.Dispatch(DeviceId, "Channels", null, store: true);
            broker.Dispatch(DeviceId, "HtStatus", null, store: true);
            broker.Dispatch(DeviceId, "Settings", null, store: true);
            broker.Dispatch(DeviceId, "BssSettings", null, store: true);
            broker.Dispatch(DeviceId, "Position", null, store: true);
            broker.Dispatch(DeviceId, "AllChannelsLoaded", false, store: true);
            broker.Dispatch(DeviceId, "GpsEnabled", false, store: true);
            broker.Dispatch(DeviceId, "LockState", null, store: true);
            broker.Dispatch(DeviceId, "Volume", 0, store: true);
            broker.Dispatch(DeviceId, "BatteryAsPercentage", 0, store: true);
            broker.Dispatch(DeviceId, "BatteryLevel", 0, store: true);
            broker.Dispatch(DeviceId, "BatteryVoltage", 0f, store: true);
            broker.Dispatch(DeviceId, "RcBatteryLevel", 0, store: true);

            // Clear local state
            Info = null;
            Channels = null;
            HtStatus = null;
            Settings = null;
            BssSettings = null;
            Position = null;
            frameAccumulator = null;
            TncFragmentQueue.Clear();
            TncFragmentInFlight = false;
            lockState = null;
            _gpsEnabled = false;

            DataBroker.DeleteDevice(DeviceId);
        }

        private void RadioTransport_OnConnected()
        {
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
        }

        #endregion

        #region Audio Management

        public void AudioEnabled(bool enabled)
        {
            if (RadioAudio == null) return;
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
            if (HtStatus == null || RadioAudio == null) return;
            RadioAudio.currentChannelId = HtStatus.curr_ch_id;
            RadioAudio.currentChannelName = GetChannelNameById(HtStatus.curr_ch_id);
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
            if (_gpsEnabled == enabled) return;
            _gpsEnabled = enabled;

            // Publish the GPS enabled state to the broker
            broker.Dispatch(DeviceId, "GpsEnabled", _gpsEnabled, store: true);

            if (state == RadioState.Connected)
            {
                gpsLock = 2;
                var cmd = _gpsEnabled ? RadioBasicCommand.REGISTER_NOTIFICATION : RadioBasicCommand.CANCEL_NOTIFICATION;
                SendCommand(RadioCommandGroup.BASIC, cmd, (int)RadioNotification.POSITION_CHANGE);
            }

            // If GPS is disabled, dispatch a null Position to clear the marker
            if (!_gpsEnabled)
            {
                Position = null;
                broker.Dispatch(DeviceId, "Position", null, store: true);
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
            if (AllowTransmit == false) return 0; // Make sure not to transmit if not allowed
            byte[] outboundData = packet.ToByteArray();
            if (outboundData == null) return 0;

            DateTime t = DateTime.Now;
            string fragmentChannelName = GetFragmentChannelName(channelId, packet.channel_name);
            TncDataFragment fragment = CreateOutboundFragment(outboundData, channelId, regionId, t, fragmentChannelName);

            if (LoopbackMode)
            {
                TransmitLoopback(fragment, outboundData, channelId, regionId, t, fragmentChannelName);
            }
            else if (RadioAudio != null && RadioAudio.IsAudioEnabled && RadioAudio.SoftwareModemMode != RadioAudio.SoftwareModemModeType.Disabled && Settings.channel_a == channelId)
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
                    Info = new RadioDevInfo(value);
                    Channels = new RadioChannelInfo[Info.channel_count];
                    UpdateState(RadioState.Connected);
                    broker.Dispatch(DeviceId, "Info", Info, store: true);
                    // Publish initial FriendlyName
                    broker.Dispatch(DeviceId, "FriendlyName", FriendlyName, store: true);
                    // Publish initial GPS enabled state
                    broker.Dispatch(DeviceId, "GpsEnabled", _gpsEnabled, store: true);
                    // Channels are not loaded yet
                    broker.Dispatch(DeviceId, "AllChannelsLoaded", false, store: true);
                    SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.REGISTER_NOTIFICATION, (int)RadioNotification.HT_STATUS_CHANGED);
                    if (_gpsEnabled) SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.REGISTER_NOTIFICATION, (int)RadioNotification.POSITION_CHANGE);
                    break;
                case RadioBasicCommand.READ_RF_CH:
                    HandleReadRfChannel(value);
                    break;
                case RadioBasicCommand.WRITE_RF_CH:
                    if (value[4] == 0) SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_RF_CH, value[5]);
                    break;
                case RadioBasicCommand.READ_BSS_SETTINGS:
                    BssSettings = new RadioBssSettings(value);
                    broker.Dispatch(DeviceId, "BssSettings", BssSettings, store: true);
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
                    broker.Dispatch(DeviceId, "Settings", Settings, store: true);
                    break;
                case RadioBasicCommand.HT_SEND_DATA:
                    HandleHtSendDataResponse(value);
                    break;
                case RadioBasicCommand.SET_VOLUME:
                    break;
                case RadioBasicCommand.GET_VOLUME:
                    broker.Dispatch(DeviceId, "Volume", value[5], store: true);
                    break;
                case RadioBasicCommand.WRITE_SETTINGS:
                    if (value[4] != 0) Debug("WRITE_SETTINGS ERROR: " + Utils.BytesToHex(value));
                    break;
                case RadioBasicCommand.SET_REGION:
                    break;
                case RadioBasicCommand.GET_POSITION:
                    Position = new RadioPosition(value);
                    // Only dispatch position if GPS is enabled
                    if (_gpsEnabled)
                    {
                        broker.Dispatch(DeviceId, "Position", Position, store: true);
                    }
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

        private void HandleReadRfChannel(byte[] value)
        {
            RadioChannelInfo c = new RadioChannelInfo(value);
            if (Channels != null) { Channels[c.channel_id] = c; }
            UpdateCurrentChannelName();
            if (AllChannelsLoaded())
            {
                broker.Dispatch(DeviceId, "Channels", Channels, store: true);
                broker.Dispatch(DeviceId, "AllChannelsLoaded", true, store: true);
            }
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
                    broker.Dispatch(DeviceId, "Settings", Settings, store: true);
                    break;
                case RadioNotification.POSITION_CHANGE:
                    value[4] = 0; // Set status to success
                    Position = new RadioPosition(value);
                    if (gpsLock > 0) gpsLock--;
                    Position.Locked = (gpsLock == 0);
                    // Only dispatch position if GPS is enabled
                    if (_gpsEnabled)
                    {
                        broker.Dispatch(DeviceId, "Position", Position, store: true);
                    }
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
            broker.Dispatch(DeviceId, "HtStatus", HtStatus, store: true);
            if (HtStatus == null) return;

            if (oldRegion != HtStatus.curr_region)
            {
                broker.Dispatch(DeviceId, "RegionChange", null, store: false);
                // Mark channels as not loaded since we're reloading them
                broker.Dispatch(DeviceId, "AllChannelsLoaded", false, store: true);
                if (Channels != null) Array.Clear(Channels, 0, Channels.Length);
                broker.Dispatch(DeviceId, "Channels", Channels, store: true);
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
                
                // Populate usage field if radio is locked and data received on locked channel
                if (lockState != null && lockState.IsLocked && packet.channel_id == lockState.ChannelId)
                {
                    packet.usage = lockState.Usage;
                }
                
                DispatchDataFrame(packet);
            }
        }

        private void HandleReadStatus(byte[] value)
        {
            RadioPowerStatus powerStatus = (RadioPowerStatus)Utils.GetShort(value, 5);
            switch (powerStatus)
            {
                case RadioPowerStatus.BATTERY_LEVEL:
                    int BatteryLevel = value[7];
                    Debug("BatteryLevel: " + BatteryLevel);
                    broker.Dispatch(DeviceId, "BatteryLevel", BatteryLevel, store: true);
                    break;
                case RadioPowerStatus.BATTERY_VOLTAGE:
                    float BatteryVoltage = Utils.GetShort(value, 7) / 1000f;
                    Debug("BatteryVoltage: " + BatteryVoltage);
                    broker.Dispatch(DeviceId, "BatteryVoltage", BatteryVoltage, store: true);
                    break;
                case RadioPowerStatus.RC_BATTERY_LEVEL:
                    int RcBatteryLevel = value[7];
                    Debug("RcBatteryLevel: " + RcBatteryLevel);
                    broker.Dispatch(DeviceId, "RcBatteryLevel", RcBatteryLevel, store: true);
                    break;
                case RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE:
                    int BatteryAsPercentage = value[7];
                    broker.Dispatch(DeviceId, "BatteryAsPercentage", BatteryAsPercentage, store: true);
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
            if (AllChannelsLoaded()) { broker.Dispatch(DeviceId, "HtStatus", HtStatus, store: true); }
            if (HtStatus == null) return;

            if (oldRegion != HtStatus.curr_region)
            {
                broker.Dispatch(DeviceId, "RegionChange", null, store: true);
                // Mark channels as not loaded since we're reloading them
                broker.Dispatch(DeviceId, "AllChannelsLoaded", false, store: true);
                if (Channels != null)
                {
                    Array.Clear(Channels, 0, Channels.Length);
                    broker.Dispatch(DeviceId, "Channels", Channels, store: true);
                }
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

        public void Debug(string msg) => broker.Dispatch(1, "LogInfo", $"[Radio/{DeviceId}]: {msg}", store: false);
        private void DispatchDataFrame(TncDataFragment frame)
        {
            frame.RadioMac = MacAddress;
            frame.RadioDeviceId = DeviceId;
            broker.Dispatch(DeviceId, "DataFrame", frame, store: false);
        }
        private void DispatchRawCommand(byte[] cmd) => broker.Dispatch(DeviceId, "RawCommand", cmd, store: false);

        #endregion

        #region Friendly Name Management

        /// <summary>
        /// Updates the friendly name and dispatches a FriendlyName event.
        /// </summary>
        /// <param name="newName">The new friendly name for the radio.</param>
        public void UpdateFriendlyName(string newName)
        {
            FriendlyName = newName;
            broker.Dispatch(DeviceId, "FriendlyName", newName, store: false);
        }

        #endregion
    }

    /// <summary>
    /// Data class representing the radio's lock state.
    /// </summary>
    public class RadioLockState
    {
        /// <summary>
        /// Whether the radio is currently locked.
        /// </summary>
        public bool IsLocked { get; set; }

        /// <summary>
        /// The usage identifier for the current lock.
        /// </summary>
        public string Usage { get; set; }

        /// <summary>
        /// The locked region ID.
        /// </summary>
        public int RegionId { get; set; }

        /// <summary>
        /// The locked channel ID.
        /// </summary>
        public int ChannelId { get; set; }
    }

    /// <summary>
    /// Data class for setting a lock on the radio.
    /// </summary>
    public class SetLockData
    {
        /// <summary>
        /// The usage identifier for the lock.
        /// </summary>
        public string Usage { get; set; }

        /// <summary>
        /// The region ID to lock to.
        /// </summary>
        public int RegionId { get; set; }

        /// <summary>
        /// The channel ID to lock to.
        /// </summary>
        public int ChannelId { get; set; }
    }

    /// <summary>
    /// Data class for unlocking the radio.
    /// </summary>
    public class SetUnlockData
    {
        /// <summary>
        /// The usage identifier that must match the current lock to unlock.
        /// </summary>
        public string Usage { get; set; }
    }

    /// <summary>
    /// Data class for transmitting AX.25 packets via the Data Broker.
    /// </summary>
    public class TransmitDataFrameData
    {
        /// <summary>
        /// The AX.25 packet to transmit.
        /// </summary>
        public AX25Packet Packet { get; set; }

        /// <summary>
        /// The channel ID to transmit on. Use -1 to use the current channel.
        /// </summary>
        public int ChannelId { get; set; } = -1;

        /// <summary>
        /// The region ID. Use -1 if not applicable.
        /// </summary>
        public int RegionId { get; set; } = -1;
    }
}
