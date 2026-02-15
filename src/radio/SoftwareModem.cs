/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// Software modem Data Broker handler that processes PCM audio from radios
    /// and decodes/encodes TNC frames using various modulation schemes.
    /// </summary>
    public class SoftwareModem : IDisposable
    {
        private readonly DataBrokerClient broker;
        private readonly object modemLock = new object();
        private readonly Dictionary<int, RadioModemState> radioModems = new Dictionary<int, RadioModemState>();
        private SoftwareModemModeType currentMode = SoftwareModemModeType.None;
        private bool disposed = false;

        /// <summary>
        /// Software modem mode types.
        /// </summary>
        public enum SoftwareModemModeType
        {
            None,
            AFSK1200,
            PSK2400,
            PSK4800,
            G3RUH9600
        }

        /// <summary>
        /// Per-radio modem state for handling audio processing.
        /// </summary>
        private class RadioModemState : IDisposable
        {
            public int DeviceId;
            public string MacAddress;
            public string CurrentChannelName;
            public int CurrentChannelId;
            public int CurrentRegionId;
            public SoftwareModemModeType Mode;
            public bool Initialized;

            // AFSK 1200 modem state
            public HamLib.DemodAfsk AfskDemodulator;
            public HamLib.DemodulatorState AfskDemodState;

            // PSK modem state (for 2400 and 4800)
            public HamLib.DemodPsk PskDemodulator;
            public HamLib.PskDemodulatorState PskDemodState;

            // G3RUH 9600 modem state
            public HamLib.Demod9600.Demod9600State State9600;
            public HamLib.DemodulatorState Demod9600State;

            // Common modem components
            public HamLib.AudioConfig AudioConfig;
            public HamLib.HdlcRec2 HdlcReceiver;
            public HamLib.Fx25Rec Fx25Receiver;
            public HdlcFx25Bridge Bridge;

            // Packet transmission components
            public HamLib.GenTone PacketGenTone;
            public HamLib.AudioBuffer PacketAudioBuffer;
            public HamLib.HdlcSend PacketHdlcSend;
            public HamLib.Fx25Send PacketFx25Send;

            // Parent reference for callbacks
            public SoftwareModem Parent;

            public void Dispose()
            {
                try
                {
                    if (HdlcReceiver != null && Parent != null)
                    {
                        HdlcReceiver.FrameReceived -= Parent.OnFrameReceived;
                    }
                }
                catch { }

                AfskDemodulator = null;
                AfskDemodState = null;
                PskDemodulator = null;
                PskDemodState = null;
                State9600 = null;
                Demod9600State = null;
                AudioConfig = null;
                HdlcReceiver = null;
                Fx25Receiver = null;
                Bridge = null;
                PacketGenTone = null;
                PacketAudioBuffer = null;
                PacketHdlcSend = null;
                PacketFx25Send = null;
                Initialized = false;
            }
        }

        /// <summary>
        /// Bridge that feeds bits to both HDLC and FX.25 receivers.
        /// </summary>
        private class HdlcFx25Bridge : HamLib.IHdlcReceiver
        {
            private readonly HamLib.IHdlcReceiver hdlcReceiver;
            private readonly HamLib.Fx25Rec fx25Receiver;

            public HdlcFx25Bridge(HamLib.IHdlcReceiver hdlcReceiver, HamLib.Fx25Rec fx25Receiver)
            {
                this.hdlcReceiver = hdlcReceiver;
                this.fx25Receiver = fx25Receiver;
            }

            public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
            {
                hdlcReceiver.RecBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
                fx25Receiver.RecBit(chan, subchan, slice, raw);
            }

            public void DcdChange(int chan, int subchan, int slice, bool dcdOn)
            {
                hdlcReceiver.DcdChange(chan, subchan, slice, dcdOn);
            }
        }

        /// <summary>
        /// Wrapper for MultiModem to process FX.25 frames.
        /// </summary>
        private class Fx25MultiModemWrapper : HamLib.MultiModem
        {
            private readonly RadioModemState state;

            public Fx25MultiModemWrapper(RadioModemState state)
            {
                this.state = state;
                this.PacketReady += OnPacketReady;
            }

            private void OnPacketReady(object sender, HamLib.PacketReadyEventArgs e)
            {
                try
                {
                    if (e.Packet == null || state.Parent == null) return;

                    byte[] frameData = e.Packet.GetInfo(out int frameLen);
                    if (frameData == null || frameLen == 0)
                    {
                        frameData = new byte[2048];
                        frameLen = e.Packet.Pack(frameData);
                    }

                    if (frameLen == 0) return;

                    byte[] data = new byte[frameLen];
                    Array.Copy(frameData, data, frameLen);

                    TncDataFragment fragment = new TncDataFragment(true, 0, data, state.CurrentChannelId, state.CurrentRegionId);
                    fragment.incoming = true;
                    fragment.channel_name = state.CurrentChannelName;
                    fragment.encoding = state.Parent.GetEncodingType(state.Mode);
                    fragment.frame_type = TncDataFragment.FragmentFrameType.FX25;
                    fragment.time = DateTime.Now;
                    fragment.RadioMac = state.MacAddress;
                    fragment.RadioDeviceId = state.DeviceId;

                    if (e.CorrectionInfo != null && e.CorrectionInfo.RsSymbolsCorrected >= 0)
                    {
                        fragment.corrections = e.CorrectionInfo.RsSymbolsCorrected;
                    }
                    else
                    {
                        fragment.corrections = 0;
                    }

                    state.Parent.DispatchDecodedFrame(state.DeviceId, fragment);
                }
                catch (Exception ex)
                {
                    state.Parent?.Debug($"FX.25 frame error: {ex.Message}");
                }
            }
        }

        public SoftwareModem()
        {
            broker = new DataBrokerClient();

            // Load saved mode from device 0 (registry)
            string savedMode = broker.GetValue<string>(0, "SoftwareModemMode", "None");
            currentMode = ParseMode(savedMode);

            // Subscribe to mode changes on device 0
            broker.Subscribe(0, "SetSoftwareModemMode", OnSetModeRequested);

            // Subscribe to audio data from all radios
            broker.Subscribe(DataBroker.AllDevices, "AudioDataAvailable", OnAudioDataAvailable);

            // Subscribe to HtStatus changes from all radios to update channel info
            broker.Subscribe(DataBroker.AllDevices, "HtStatus", OnHtStatusChanged);

            // Subscribe to transmit packet requests from all radios
            broker.Subscribe(DataBroker.AllDevices, "SoftModemTransmitPacket", OnTransmitPacketRequested);

            // Publish initial mode
            broker.Dispatch(0, "SoftwareModemMode", currentMode.ToString(), store: true);

            Debug($"SoftwareModem initialized with mode: {currentMode}");
        }

        /// <summary>
        /// Parses a mode string to the enum value.
        /// </summary>
        private static SoftwareModemModeType ParseMode(string mode)
        {
            if (string.IsNullOrEmpty(mode)) return SoftwareModemModeType.None;

            switch (mode.ToUpperInvariant())
            {
                case "NONE": return SoftwareModemModeType.None;
                case "AFSK1200": return SoftwareModemModeType.AFSK1200;
                case "PSK2400": return SoftwareModemModeType.PSK2400;
                case "PSK4800": return SoftwareModemModeType.PSK4800;
                case "G3RUH9600": return SoftwareModemModeType.G3RUH9600;
                default: return SoftwareModemModeType.None;
            }
        }

        /// <summary>
        /// Gets the TncDataFragment encoding type for the current mode.
        /// </summary>
        private TncDataFragment.FragmentEncodingType GetEncodingType(SoftwareModemModeType mode)
        {
            switch (mode)
            {
                case SoftwareModemModeType.AFSK1200: return TncDataFragment.FragmentEncodingType.SoftwareAfsk1200;
                case SoftwareModemModeType.PSK2400: return TncDataFragment.FragmentEncodingType.SoftwarePsk2400;
                case SoftwareModemModeType.PSK4800: return TncDataFragment.FragmentEncodingType.SoftwarePsk4800;
                case SoftwareModemModeType.G3RUH9600: return TncDataFragment.FragmentEncodingType.SoftwareG3RUH9600;
                default: return TncDataFragment.FragmentEncodingType.Unknown;
            }
        }

        /// <summary>
        /// Handles mode change requests from the Data Broker.
        /// </summary>
        private void OnSetModeRequested(int deviceId, string name, object data)
        {
            if (disposed) return;

            string modeStr = data as string;
            if (modeStr == null && data != null) modeStr = data.ToString();

            SoftwareModemModeType newMode = ParseMode(modeStr);
            SetMode(newMode);
        }

        /// <summary>
        /// Sets the software modem mode.
        /// </summary>
        public void SetMode(SoftwareModemModeType mode)
        {
            lock (modemLock)
            {
                if (currentMode == mode) return;

                Debug($"Changing software modem mode from {currentMode} to {mode}");

                // Cleanup all existing per-radio modem states
                foreach (var kvp in radioModems)
                {
                    kvp.Value.Dispose();
                }
                radioModems.Clear();

                currentMode = mode;

                // Save to device 0 (registry)
                broker.Dispatch(0, "SoftwareModemMode", mode.ToString(), store: true);

                Debug($"Software modem mode changed to {mode}");
            }
        }

        /// <summary>
        /// Handles HtStatus changes to update channel info for radios.
        /// </summary>
        private void OnHtStatusChanged(int deviceId, string name, object data)
        {
            if (disposed || deviceId <= 0) return;

            lock (modemLock)
            {
                if (radioModems.TryGetValue(deviceId, out RadioModemState state))
                {
                    if (data is RadioHtStatus htStatus)
                    {
                        state.CurrentChannelId = htStatus.curr_ch_id;
                        state.CurrentRegionId = htStatus.curr_region;
                    }
                }
            }
        }

        /// <summary>
        /// Handles incoming PCM audio data from radios.
        /// </summary>
        private void OnAudioDataAvailable(int deviceId, string name, object data)
        {
            if (disposed || deviceId <= 0) return;
            if (currentMode == SoftwareModemModeType.None) return;

            try
            {
                // Extract audio data from the event
                var dataType = data.GetType();
                var dataProperty = dataType.GetProperty("Data");
                var offsetProperty = dataType.GetProperty("Offset");
                var lengthProperty = dataType.GetProperty("Length");
                var channelProperty = dataType.GetProperty("ChannelName");
                var transmitProperty = dataType.GetProperty("Transmit");

                if (dataProperty == null) return;

                byte[] pcmData = dataProperty.GetValue(data) as byte[];
                if (pcmData == null || pcmData.Length == 0) return;

                // Don't process transmitted or muted audio
                if (transmitProperty != null)
                {
                    object transmitVal = transmitProperty.GetValue(data);
                    if (transmitVal is bool isTransmit && isTransmit) return;
                }
                var mutedProperty = dataType.GetProperty("Muted");
                if (mutedProperty != null)
                {
                    object mutedVal = mutedProperty.GetValue(data);
                    if (mutedVal is bool isMuted && isMuted) return;
                }

                int offset = 0;
                int length = pcmData.Length;
                string channelName = "";

                if (offsetProperty != null)
                {
                    object offsetVal = offsetProperty.GetValue(data);
                    if (offsetVal is int o) offset = o;
                }
                if (lengthProperty != null)
                {
                    object lengthVal = lengthProperty.GetValue(data);
                    if (lengthVal is int l) length = l;
                }
                if (channelProperty != null)
                {
                    object channelVal = channelProperty.GetValue(data);
                    if (channelVal is string s) channelName = s;
                }

                // Process the PCM data
                ProcessPcmData(deviceId, pcmData, offset, length, channelName);
            }
            catch (Exception ex)
            {
                Debug($"OnAudioDataAvailable error: {ex.Message}");
            }
        }

        /// <summary>
        /// Processes PCM audio data for a specific radio.
        /// </summary>
        private void ProcessPcmData(int deviceId, byte[] data, int offset, int length, string channelName)
        {
            lock (modemLock)
            {
                if (currentMode == SoftwareModemModeType.None) return;

                // Get or create modem state for this radio
                if (!radioModems.TryGetValue(deviceId, out RadioModemState state))
                {
                    state = CreateRadioModemState(deviceId);
                    if (state == null) return;
                    radioModems[deviceId] = state;
                }

                // Update channel name if provided
                if (!string.IsNullOrEmpty(channelName))
                {
                    state.CurrentChannelName = channelName;
                }

                // Feed samples to the demodulator
                try
                {
                    int chan = 0;
                    int subchan = 0;

                    switch (currentMode)
                    {
                        case SoftwareModemModeType.AFSK1200:
                            if (state.AfskDemodulator == null || state.AfskDemodState == null) return;
                            for (int i = offset; i < offset + length - 1; i += 2)
                            {
                                short sample = (short)(data[i] | (data[i + 1] << 8));
                                state.AfskDemodulator.ProcessSample(chan, subchan, sample, state.AfskDemodState);
                            }
                            break;

                        case SoftwareModemModeType.PSK2400:
                        case SoftwareModemModeType.PSK4800:
                            if (state.PskDemodulator == null || state.PskDemodState == null) return;
                            for (int i = offset; i < offset + length - 1; i += 2)
                            {
                                short sample = (short)(data[i] | (data[i + 1] << 8));
                                state.PskDemodulator.ProcessSample(chan, subchan, sample, state.PskDemodState);
                            }
                            break;

                        case SoftwareModemModeType.G3RUH9600:
                            if (state.State9600 == null || state.Bridge == null || state.Demod9600State == null) return;
                            for (int i = offset; i < offset + length - 1; i += 2)
                            {
                                short sample = (short)(data[i] | (data[i + 1] << 8));
                                HamLib.Demod9600.ProcessSample(chan, sample, 1, state.Demod9600State, state.State9600, state.Bridge);
                            }
                            break;
                    }
                }
                catch (Exception ex)
                {
                    Debug($"ProcessPcmData error for device {deviceId}: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Creates a new modem state for a radio.
        /// </summary>
        private RadioModemState CreateRadioModemState(int deviceId)
        {
            try
            {
                // Get radio info from the broker
                string macAddress = "";
                var radioInfo = broker.GetValue<object>(deviceId, "Info", null);
                if (radioInfo == null) return null;

                // Try to get MAC address from connected radios list
                var connectedRadios = broker.GetValue<object>(1, "ConnectedRadios", null);
                if (connectedRadios is System.Collections.IEnumerable radioList)
                {
                    foreach (var radio in radioList)
                    {
                        var radioType = radio.GetType();
                        var deviceIdProp = radioType.GetProperty("DeviceId");
                        var macProp = radioType.GetProperty("MacAddress");
                        if (deviceIdProp != null && macProp != null)
                        {
                            object devIdVal = deviceIdProp.GetValue(radio);
                            if (devIdVal is int devId && devId == deviceId)
                            {
                                object macVal = macProp.GetValue(radio);
                                if (macVal is string mac) macAddress = mac;
                                break;
                            }
                        }
                    }
                }

                RadioModemState state = new RadioModemState
                {
                    DeviceId = deviceId,
                    MacAddress = macAddress,
                    CurrentChannelName = "",
                    CurrentChannelId = 0,
                    CurrentRegionId = 0,
                    Mode = currentMode,
                    Parent = this
                };

                // Get current HtStatus for channel info
                var htStatus = broker.GetValue<RadioHtStatus>(deviceId, "HtStatus", null);
                if (htStatus != null)
                {
                    state.CurrentChannelId = htStatus.curr_ch_id;
                    state.CurrentRegionId = htStatus.curr_region;
                }

                // Initialize FX.25 subsystem
                HamLib.Fx25.Init(0);

                // Initialize modem based on current mode
                InitializeModemState(state, currentMode);

                return state;
            }
            catch (Exception ex)
            {
                Debug($"CreateRadioModemState error for device {deviceId}: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Initializes the modem state for a specific mode.
        /// </summary>
        private void InitializeModemState(RadioModemState state, SoftwareModemModeType mode)
        {
            // Setup audio configuration for 32kHz, 16-bit, mono
            state.AudioConfig = new HamLib.AudioConfig();
            state.AudioConfig.Devices[0].Defined = true;
            state.AudioConfig.Devices[0].SamplesPerSec = 32000;
            state.AudioConfig.Devices[0].BitsPerSample = 16;
            state.AudioConfig.Devices[0].NumChannels = 1;
            state.AudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
            state.AudioConfig.Channels[0].NumSubchan = 1;

            switch (mode)
            {
                case SoftwareModemModeType.AFSK1200:
                    InitializeAfsk1200(state);
                    break;
                case SoftwareModemModeType.PSK2400:
                    InitializePsk2400(state);
                    break;
                case SoftwareModemModeType.PSK4800:
                    InitializePsk4800(state);
                    break;
                case SoftwareModemModeType.G3RUH9600:
                    InitializeG3ruh9600(state);
                    break;
            }

            state.Initialized = true;
            Debug($"Initialized {mode} modem for device {state.DeviceId}");
        }

        private void InitializeAfsk1200(RadioModemState state)
        {
            state.AudioConfig.Channels[0].ModemType = HamLib.ModemType.Afsk;
            state.AudioConfig.Channels[0].MarkFreq = 1200;
            state.AudioConfig.Channels[0].SpaceFreq = 2200;
            state.AudioConfig.Channels[0].Baud = 1200;
            state.AudioConfig.Channels[0].Txdelay = 30;
            state.AudioConfig.Channels[0].Txtail = 10;

            // Create HDLC receiver
            state.HdlcReceiver = new HamLib.HdlcRec2();
            state.HdlcReceiver.FrameReceived += OnFrameReceived;
            state.HdlcReceiver.Init(state.AudioConfig);

            // Create FX.25 receiver
            var fx25MultiModem = new Fx25MultiModemWrapper(state);
            state.Fx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

            // Create bridge
            state.Bridge = new HdlcFx25Bridge(state.HdlcReceiver, state.Fx25Receiver);

            // Create AFSK demodulator
            state.AfskDemodulator = new HamLib.DemodAfsk(state.Bridge);
            state.AfskDemodState = new HamLib.DemodulatorState();
            state.AfskDemodulator.Init(32000, 1200, 1200, 2200, 'A', state.AfskDemodState);

            // Initialize transmitter
            InitializeTransmitter(state);
        }

        private void InitializePsk2400(RadioModemState state)
        {
            state.AudioConfig.Channels[0].ModemType = HamLib.ModemType.Qpsk;
            state.AudioConfig.Channels[0].Baud = 1200; // 2400 bps / 2 bits per symbol
            state.AudioConfig.Channels[0].V26Alt = HamLib.V26Alternative.B;
            state.AudioConfig.Channels[0].Txdelay = 30;
            state.AudioConfig.Channels[0].Txtail = 10;

            // Create HDLC receiver
            state.HdlcReceiver = new HamLib.HdlcRec2();
            state.HdlcReceiver.FrameReceived += OnFrameReceived;
            state.HdlcReceiver.Init(state.AudioConfig);

            // Create FX.25 receiver
            var fx25MultiModem = new Fx25MultiModemWrapper(state);
            state.Fx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

            // Create bridge
            state.Bridge = new HdlcFx25Bridge(state.HdlcReceiver, state.Fx25Receiver);

            // Create PSK demodulator
            state.PskDemodulator = new HamLib.DemodPsk(state.Bridge);
            state.PskDemodState = new HamLib.PskDemodulatorState();
            state.PskDemodulator.Init(HamLib.ModemType.Qpsk, HamLib.V26Alternative.B, 32000, 2400, 'B', state.PskDemodState);

            // Initialize transmitter
            InitializeTransmitter(state);
        }

        private void InitializePsk4800(RadioModemState state)
        {
            state.AudioConfig.Channels[0].ModemType = HamLib.ModemType.Psk8;
            state.AudioConfig.Channels[0].Baud = 1600; // 4800 bps / 3 bits per symbol
            state.AudioConfig.Channels[0].V26Alt = HamLib.V26Alternative.B;
            state.AudioConfig.Channels[0].Txdelay = 30;
            state.AudioConfig.Channels[0].Txtail = 10;

            // Create HDLC receiver
            state.HdlcReceiver = new HamLib.HdlcRec2();
            state.HdlcReceiver.FrameReceived += OnFrameReceived;
            state.HdlcReceiver.Init(state.AudioConfig);

            // Create FX.25 receiver
            var fx25MultiModem = new Fx25MultiModemWrapper(state);
            state.Fx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

            // Create bridge
            state.Bridge = new HdlcFx25Bridge(state.HdlcReceiver, state.Fx25Receiver);

            // Create PSK demodulator
            state.PskDemodulator = new HamLib.DemodPsk(state.Bridge);
            state.PskDemodState = new HamLib.PskDemodulatorState();
            state.PskDemodulator.Init(HamLib.ModemType.Psk8, HamLib.V26Alternative.B, 32000, 4800, 'B', state.PskDemodState);

            // Initialize transmitter
            InitializeTransmitter(state);
        }

        private void InitializeG3ruh9600(RadioModemState state)
        {
            state.AudioConfig.Channels[0].ModemType = HamLib.ModemType.Baseband;
            state.AudioConfig.Channels[0].Baud = 9600;
            state.AudioConfig.Channels[0].Txdelay = 30;
            state.AudioConfig.Channels[0].Txtail = 10;

            // Create HDLC receiver
            state.HdlcReceiver = new HamLib.HdlcRec2();
            state.HdlcReceiver.FrameReceived += OnFrameReceived;
            state.HdlcReceiver.Init(state.AudioConfig);

            // Create FX.25 receiver
            var fx25MultiModem = new Fx25MultiModemWrapper(state);
            state.Fx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

            // Create bridge
            state.Bridge = new HdlcFx25Bridge(state.HdlcReceiver, state.Fx25Receiver);

            // Create 9600 baud demodulator
            state.Demod9600State = new HamLib.DemodulatorState();
            state.State9600 = new HamLib.Demod9600.Demod9600State();
            HamLib.Demod9600.Init(32000, 1, 9600, state.Demod9600State, state.State9600);

            // Initialize transmitter
            InitializeTransmitter(state);
        }

        private void InitializeTransmitter(RadioModemState state)
        {
            try
            {
                // Create audio buffer
                state.PacketAudioBuffer = new HamLib.AudioBuffer(HamLib.AudioConfig.MaxAudioDevices);

                // Create tone generator
                state.PacketGenTone = new HamLib.GenTone(state.PacketAudioBuffer);
                state.PacketGenTone.Init(state.AudioConfig, 50);

                // Create HDLC sender
                state.PacketHdlcSend = new HamLib.HdlcSend(state.PacketGenTone, state.AudioConfig);

                // Create FX.25 sender
                state.PacketFx25Send = new HamLib.Fx25Send();
                state.PacketFx25Send.Init(state.PacketGenTone);
            }
            catch (Exception ex)
            {
                Debug($"InitializeTransmitter error: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles decoded HDLC frames from the receiver.
        /// </summary>
        private void OnFrameReceived(object sender, HamLib.FrameReceivedEventArgs e)
        {
            try
            {
                // Find which radio state this frame belongs to
                RadioModemState state = null;
                lock (modemLock)
                {
                    foreach (var kvp in radioModems)
                    {
                        if (kvp.Value.HdlcReceiver == sender)
                        {
                            state = kvp.Value;
                            break;
                        }
                    }
                }

                if (state == null) return;

                byte[] frameData = new byte[e.FrameLength];
                Array.Copy(e.Frame, frameData, e.FrameLength);

                TncDataFragment fragment = new TncDataFragment(true, 0, frameData, state.CurrentChannelId, state.CurrentRegionId);
                fragment.incoming = true;
                fragment.channel_name = state.CurrentChannelName;
                fragment.encoding = GetEncodingType(state.Mode);
                fragment.time = DateTime.Now;
                fragment.RadioMac = state.MacAddress;
                fragment.RadioDeviceId = state.DeviceId;

                if (e.CorrectionInfo != null)
                {
                    if (e.CorrectionInfo.FecType == HamLib.FecType.Fx25)
                    {
                        fragment.frame_type = TncDataFragment.FragmentFrameType.FX25;
                        fragment.corrections = e.CorrectionInfo.RsSymbolsCorrected >= 0 ? e.CorrectionInfo.RsSymbolsCorrected : 0;
                    }
                    else
                    {
                        fragment.frame_type = TncDataFragment.FragmentFrameType.AX25;
                        fragment.corrections = e.CorrectionInfo.CorrectedBitPositions?.Count ?? 0;
                    }
                }
                else
                {
                    fragment.frame_type = TncDataFragment.FragmentFrameType.AX25;
                    fragment.corrections = 0;
                }

                DispatchDecodedFrame(state.DeviceId, fragment);
            }
            catch (Exception ex)
            {
                Debug($"OnFrameReceived error: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles transmit packet requests.
        /// </summary>
        private void OnTransmitPacketRequested(int deviceId, string name, object data)
        {
            if (disposed || deviceId <= 0) return;
            if (currentMode == SoftwareModemModeType.None) return;

            if (!(data is TncDataFragment fragment)) return;

            TransmitPacket(deviceId, fragment);
        }

        /// <summary>
        /// Transmits a TNC packet through the software modem.
        /// </summary>
        public void TransmitPacket(int deviceId, TncDataFragment fragment)
        {
            if (fragment == null || fragment.data == null || fragment.data.Length == 0)
            {
                Debug("TransmitPacket: Invalid fragment");
                return;
            }

            lock (modemLock)
            {
                if (currentMode == SoftwareModemModeType.None) return;

                // Get or create modem state for this radio
                if (!radioModems.TryGetValue(deviceId, out RadioModemState state))
                {
                    state = CreateRadioModemState(deviceId);
                    if (state == null)
                    {
                        Debug($"TransmitPacket: Could not create modem state for device {deviceId}");
                        return;
                    }
                    radioModems[deviceId] = state;
                }

                if (state.PacketAudioBuffer == null || state.PacketGenTone == null)
                {
                    Debug("TransmitPacket: Transmitter not initialized");
                    return;
                }

                try
                {
                    int chan = 0;
                    state.PacketAudioBuffer.ClearAll();

                    // Add pre-silence for G3RUH 9600
                    if (currentMode == SoftwareModemModeType.G3RUH9600)
                    {
                        int silenceSamples = 32000 / 2; // 0.5 seconds
                        for (int i = 0; i < silenceSamples; i++)
                        {
                            state.PacketAudioBuffer.Put(0, 0);
                        }
                    }

                    // Send preamble flags
                    int txdelayFlags = state.AudioConfig.Channels[chan].Txdelay;
                    state.PacketHdlcSend.SendFlags(chan, txdelayFlags, false, null);

                    // Send frame (FX.25 or AX.25)
                    bool useFx25 = (fragment.frame_type == TncDataFragment.FragmentFrameType.FX25);
                    if (useFx25)
                    {
                        int fxMode = 32;
                        state.PacketFx25Send.SendFrame(chan, fragment.data, fragment.data.Length, fxMode);
                        Debug($"Transmitting FX.25 packet ({fragment.data.Length} bytes with FEC) on device {deviceId}");
                    }
                    else
                    {
                        state.PacketHdlcSend.SendFrame(chan, fragment.data, fragment.data.Length, false);
                        Debug($"Transmitting AX.25 packet ({fragment.data.Length} bytes) on device {deviceId}");
                    }

                    // Send postamble flags
                    int txtailFlags = state.AudioConfig.Channels[chan].Txtail;
                    state.PacketHdlcSend.SendFlags(chan, txtailFlags, true, (device) => { });

                    // Add post-silence for G3RUH 9600
                    if (currentMode == SoftwareModemModeType.G3RUH9600)
                    {
                        int silenceSamples = 32000 / 2; // 0.5 seconds
                        for (int i = 0; i < silenceSamples; i++)
                        {
                            state.PacketAudioBuffer.Put(0, 0);
                        }
                    }

                    // Get the generated audio samples
                    short[] samples = state.PacketAudioBuffer.GetAndClear(0);
                    if (samples != null && samples.Length > 0)
                    {
                        // Convert to PCM bytes
                        byte[] pcmData = new byte[samples.Length * 2];
                        Buffer.BlockCopy(samples, 0, pcmData, 0, pcmData.Length);

                        // Dispatch to the radio for transmission
                        broker.Dispatch(deviceId, "TransmitVoicePCM", new { Data = pcmData, PlayLocally = false }, store: false);

                        Debug($"Transmitted packet: {samples.Length} samples, {pcmData.Length} bytes PCM on device {deviceId}");
                    }
                }
                catch (Exception ex)
                {
                    Debug($"TransmitPacket error: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Dispatches a decoded TNC frame to the Data Broker.
        /// </summary>
        private void DispatchDecodedFrame(int deviceId, TncDataFragment fragment)
        {
            broker.Dispatch(deviceId, "DataFrame", fragment, store: false);
        }

        /// <summary>
        /// Gets the current modem mode.
        /// </summary>
        public SoftwareModemModeType CurrentMode => currentMode;

        /// <summary>
        /// Checks if software modem is enabled.
        /// </summary>
        public bool IsEnabled => currentMode != SoftwareModemModeType.None;

        private void Debug(string msg)
        {
            broker.Dispatch(1, "LogInfo", $"[SoftwareModem]: {msg}", store: false);
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;

            lock (modemLock)
            {
                foreach (var kvp in radioModems)
                {
                    kvp.Value.Dispose();
                }
                radioModems.Clear();
            }

            broker?.Dispose();
        }
    }
}