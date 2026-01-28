/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;
using WinBluetooth = Windows.Devices.Bluetooth;
using WinRfcomm = Windows.Devices.Bluetooth.Rfcomm;
using HTCommander.radio;
using NAudio.Wave;
using NAudio.CoreAudioApi;
using NAudio.Wave.SampleProviders;

namespace HTCommander
{
    public class RadioAudio : IDisposable
    {
        private Radio parent;
        private const int ReceiveBufferSize = 1024;
        private readonly DataBrokerClient broker;
        private readonly int DeviceId;
        private readonly string MacAddress;

        // Bluetooth connection resources
        private Windows.Networking.Sockets.StreamSocket bluetoothSocket = null;
        private WinRfcomm.RfcommDeviceService rfcommService = null;
        private Stream winRtInputStream = null;
        private Stream winRtOutputStream = null;
        private CancellationTokenSource audioLoopCts = null;
        private readonly object connectionLock = new object();
        private Task audioLoopTask = null;
        private bool isConnecting = false;

        // SBC codec
        private SbcDecoder sbcDecoder;
        private SbcEncoder sbcEncoder;
        private SbcFrame sbcDecoderFrame;
        private SbcFrame sbcEncoderFrame;

        private WasapiOut waveOut = null;
        private byte[] pcmFrame = new byte[16000];
        private bool running = false;
        private NetworkStream audioStream;
        public string currentChannelName = "";
        public int currentChannelId = 0;
        private int pcmInputSizePerFrame; // Expected PCM bytes per encode call
        //private int sbcOutputSizePerFrame; // Max SBC bytes generated per encode call
        private byte[] sbcOutputBuffer; // Reusable buffer for SBC frame output
        private BufferedWaveProvider waveProvider = null;
        private float OutputVolume = 1;
        private float InputVolume = 1;
        private VolumeSampleProvider volumeProvider;
        public bool Recording { get { return recording != null; } }
        private WaveFileWriter recording = null;
        private MMDevice currentOutputDevice = null;

        // Software modem fields
        private readonly object softModemLock = new object();
        public SoftwareModemModeType SoftwareModemMode 
        { 
            get 
            { 
                return _softwareModemMode; 
            }
            set
            {
                lock (softModemLock)
                {
                    if (_softwareModemMode == value)
                        return; // No change needed

                    Debug($"Changing software modem from {_softwareModemMode} to {value}");
                    
                    // Clean up existing modem resources
                    CleanupSoftModem();
                    
                    // Initialize new modem
                    InitializeSoftModem(value);
                    
                    // Reinitialize packet transmitter for the new modem type
                    CleanupPacketTransmitter();
                    if (value != SoftwareModemModeType.Disabled)
                    {
                        InitializePacketTransmitter();
                    }
                    
                    Debug($"Software modem changed to {value}");
                }
            }
        }
        private SoftwareModemModeType _softwareModemMode = SoftwareModemModeType.Disabled;
        private HamLib.DemodAfsk softModemDemodulator = null;
        private HamLib.DemodPsk softModemPskDemodulator = null;
        private HamLib.PskDemodulatorState softModemPskDemodState = null;
        private HamLib.HdlcRec2 softModemHdlcReceiver = null;
        private HamLib.DemodulatorState softModemDemodState = null;
        private HamLib.AudioConfig softModemAudioConfig = null;
        private bool softModemInitialized = false;

        // FX.25 decoder
        private HamLib.Fx25Rec softModemFx25Receiver = null;
        private bool fx25Initialized = false;
        private HdlcFx25Bridge softModemBridge = null;

        // 9600 baud modem
        private HamLib.Demod9600.Demod9600State softModem9600State = null;

        public void StartRecording(string filename)
        {
            if (recording != null) { recording.Dispose(); recording = null; }
            recording = new WaveFileWriter(filename, new WaveFormat(32000, 16, 1));
        }

        public void StopRecording()
        {
            recording.Dispose();
            recording = null;
        }

        public RadioAudio(Radio radio, int deviceid, string mac) 
        { 
            parent = radio;
            DeviceId = deviceid;
            MacAddress = mac;
            broker = new DataBrokerClient();
            
            // Subscribe to Data Broker commands for audio control
            broker.Subscribe(DeviceId, "SetOutputAudioDevice", OnSetOutputAudioDevice);
            broker.Subscribe(DeviceId, "SetOutputVolume", OnSetOutputVolume);
            broker.Subscribe(DeviceId, "TransmitVoicePCM", OnTransmitVoicePCM);
            broker.Subscribe(DeviceId, "StartRecording", OnStartRecording);
            broker.Subscribe(DeviceId, "StopRecording", OnStopRecording);
            
            // Initialize output volume from stored value
            OutputVolume = broker.GetValue<float>(DeviceId, "OutputVolume", 1.0f);
            
            InitializeSoftModem(SoftwareModemModeType.Psk2400);
        }
        
        // Data Broker event handlers
        private void OnSetOutputAudioDevice(int deviceId, string name, object data)
        {
            if (data is string audioDeviceId)
            {
                SetOutputDevice(audioDeviceId);
                broker.Dispatch(DeviceId, "OutputAudioDevice", audioDeviceId, store: true);
            }
        }
        
        private void OnSetOutputVolume(int deviceId, string name, object data)
        {
            if (data is float volume)
            {
                OutputVolume = volume;
                if (volumeProvider != null) { volumeProvider.Volume = volume; }
                broker.Dispatch(DeviceId, "OutputVolume", volume, store: true);
            }
            else if (data is int volumeInt)
            {
                float vol = volumeInt / 100f;
                OutputVolume = vol;
                if (volumeProvider != null) { volumeProvider.Volume = vol; }
                broker.Dispatch(DeviceId, "OutputVolume", vol, store: true);
            }
        }
        
        private void OnTransmitVoicePCM(int deviceId, string name, object data)
        {
            if (data is byte[] pcmData && pcmData.Length > 0)
            {
                TransmitVoice(pcmData, 0, pcmData.Length, false);
            }
        }
        
        private void OnStartRecording(int deviceId, string name, object data)
        {
            if (data is string filename && !string.IsNullOrEmpty(filename))
            {
                StartRecording(filename);
                broker.Dispatch(DeviceId, "Recording", true, store: true);
            }
        }
        
        private void OnStopRecording(int deviceId, string name, object data)
        {
            StopRecording();
            broker.Dispatch(DeviceId, "Recording", false, store: true);
        }

        /// <summary>
        /// Disposes of all resources used by RadioAudio, including the data broker.
        /// </summary>
        public void Dispose()
        {
            // Stop audio streaming first
            Stop();

            // Clean up software modem resources
            lock (softModemLock)
            {
                CleanupSoftModem();
                CleanupPacketTransmitter();
            }

            // Dispose recording if active
            try { recording?.Dispose(); } catch (Exception) { }
            recording = null;

            // Dispose wave output
            try { waveOut?.Stop(); } catch (Exception) { }
            try { waveOut?.Dispose(); } catch (Exception) { }
            waveOut = null;
            waveProvider = null;
            volumeProvider = null;

            // Cancel any ongoing transmission
            try { transmissionTokenSource?.Cancel(); } catch (Exception) { }
            try { transmissionTokenSource?.Dispose(); } catch (Exception) { }
            transmissionTokenSource = null;

            // Clear queues
            while (pcmQueue.TryDequeue(out _)) { }
            while (packetQueue.TryDequeue(out _)) { }

            // Dispose the data broker client
            broker?.Dispose();

            // Clear parent reference
            parent = null;
        }

        private void Debug(string msg) { broker.Dispatch(1, "LogInfo", $"[RadioAudio/{DeviceId}]: {msg}", store: false); }
        
        /// <summary>
        /// Fast calculation of max amplitude from 16-bit PCM data, normalized to 0.0-1.0
        /// </summary>
        private static unsafe float CalculatePcmAmplitude(byte[] pcmData, int bytesRecorded)
        {
            if (pcmData == null || bytesRecorded < 2) return 0f;
            short max = 0;
            fixed (byte* ptr = pcmData)
            {
                short* samples = (short*)ptr;
                int count = bytesRecorded / 2;
                for (int i = 0; i < count; i++)
                {
                    short val = samples[i];
                    if (val < 0) val = (short)-val; // Absolute value
                    if (val > max) max = val;
                }
            }
            return Math.Min(1.0f, max / 32768f);
        }
        
        private void DispatchAudioStateChanged(bool enabled) { broker.Dispatch(DeviceId, "AudioState", enabled, store: true); }
        private void DispatchVoiceTransmitStateChanged(bool transmitting) { broker.Dispatch(DeviceId, "VoiceTransmitStateChanged", transmitting, store: false); }
        private void DispatchSoftModemPacketDecoded(TncDataFragment fragment) { broker.Dispatch(DeviceId, "SoftModemPacketDecoded", fragment, store: false); }
        private void DispatchAudioDataAvailable(byte[] data, int offset, int length, string channelName, bool transmit) { broker.Dispatch(DeviceId, "AudioDataAvailable", new { Data = data, Offset = offset, Length = length, ChannelName = channelName, Transmit = transmit }, store: false); }
        private void DispatchAudioDataStart() { broker.Dispatch(DeviceId, "AudioDataStart", null, store: false); }
        private void DispatchAudioDataEnd() { broker.Dispatch(DeviceId, "AudioDataEnd", null, store: false); broker.Dispatch(DeviceId, "OutputAmplitude", 0f, store: false); }

        // Audio run state tracking
        private bool inAudioRun = false;

        public enum SoftwareModemModeType
        {
            Disabled,
            Afsk1200,
            Psk2400,
            Psk4800,
            G3RUH9600,
        }

        // Clean up software modem. Call with softModemLock held.
        private void CleanupSoftModem()
        {
            try
            {
                if (softModemHdlcReceiver != null)
                {
                    softModemHdlcReceiver.FrameReceived -= SoftModemHdlcReceiver_FrameReceived;
                }

                softModemDemodulator = null;
                softModemPskDemodulator = null;
                softModemPskDemodState = null;
                softModemHdlcReceiver = null;
                softModemDemodState = null;
                softModemAudioConfig = null;
                softModemFx25Receiver = null;
                softModemBridge = null;
                softModem9600State = null;
                
                softModemInitialized = false;
                fx25Initialized = false;
            }
            catch (Exception ex) { Debug($"CleanupSoftModem error: {ex.Message}"); }
        }

        // Clean up packet transmitter. Call with softModemLock held.
        private void CleanupPacketTransmitter()
        {
            try
            {
                packetAudioConfig = null;
                packetGenTone = null;
                packetAudioBuffer = null;
                packetHdlcSend = null;
                packetFx25Send = null;
            }
            catch (Exception ex) { Debug($"CleanupPacketTransmitter error: {ex.Message}"); }
        }

        // Initialize software modem. Call with softModemLock held.
        private void InitializeSoftModem(SoftwareModemModeType mode)
        {
            if (mode == SoftwareModemModeType.Disabled)
            {
                _softwareModemMode = mode;
                softModemInitialized = false;
                fx25Initialized = false;
                return;
            }
            else if (mode == SoftwareModemModeType.Afsk1200)
            {
                try
                {
                    // Initialize FX.25 subsystem
                    HamLib.Fx25.Init(0); // Debug level 0 = errors only

                    // Setup audio configuration for 32kHz, 16-bit, mono (matches PCM from SBC decoder)
                    softModemAudioConfig = new HamLib.AudioConfig();
                    softModemAudioConfig.Devices[0].Defined = true;
                    softModemAudioConfig.Devices[0].SamplesPerSec = 32000;
                    softModemAudioConfig.Devices[0].BitsPerSample = 16;
                    softModemAudioConfig.Devices[0].NumChannels = 1;

                    // Configure for AFSK 1200 baud
                    softModemAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    softModemAudioConfig.Channels[0].ModemType = HamLib.ModemType.Afsk;
                    softModemAudioConfig.Channels[0].MarkFreq = 1200;
                    softModemAudioConfig.Channels[0].SpaceFreq = 2200;
                    softModemAudioConfig.Channels[0].Baud = 1200;
                    softModemAudioConfig.Channels[0].NumSubchan = 1;

                    // Create HDLC receiver with frame event handler
                    softModemHdlcReceiver = new HamLib.HdlcRec2();
                    softModemHdlcReceiver.FrameReceived += SoftModemHdlcReceiver_FrameReceived;
                    softModemHdlcReceiver.Init(softModemAudioConfig);

                    // Create FX.25 receiver with MultiModem wrapper for frame processing
                    var fx25MultiModem = new Fx25MultiModemWrapper(this);
                    softModemFx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

                    // Create bridge that feeds bits to both HDLC and FX.25 receivers
                    softModemBridge = new HdlcFx25Bridge(softModemHdlcReceiver, softModemFx25Receiver);

                    // Create and initialize AFSK demodulator with the bridge
                    softModemDemodulator = new HamLib.DemodAfsk(softModemBridge);
                    softModemDemodState = new HamLib.DemodulatorState();
                    softModemDemodulator.Init(
                        32000,  // Sample rate
                        1200,   // Baud rate
                        1200,   // Mark frequency
                        2200,   // Space frequency
                        'A',    // Profile
                        softModemDemodState
                    );

                    _softwareModemMode = mode;
                    softModemInitialized = true;
                    fx25Initialized = true;
                    Debug("Software modem (AFSK 1200 decoder with FX.25 support) initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing software modem: {ex.Message}");
                    _softwareModemMode = SoftwareModemModeType.Disabled;
                    softModemInitialized = false;
                    fx25Initialized = false;
                }
            }
            else if (mode == SoftwareModemModeType.Psk2400)
            {
                try
                {
                    // Initialize FX.25 subsystem
                    HamLib.Fx25.Init(0); // Debug level 0 = errors only

                    // Setup audio configuration for 32kHz, 16-bit, mono (matches PCM from SBC decoder)
                    softModemAudioConfig = new HamLib.AudioConfig();
                    softModemAudioConfig.Devices[0].Defined = true;
                    softModemAudioConfig.Devices[0].SamplesPerSec = 32000;
                    softModemAudioConfig.Devices[0].BitsPerSample = 16;
                    softModemAudioConfig.Devices[0].NumChannels = 1;

                    // Configure for PSK 2400 bps (QPSK with V.26 Alternative B)
                    softModemAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    softModemAudioConfig.Channels[0].ModemType = HamLib.ModemType.Qpsk;
                    softModemAudioConfig.Channels[0].Baud = 1200; // 2400 bps / 2 bits per symbol = 1200 baud
                    softModemAudioConfig.Channels[0].V26Alt = HamLib.V26Alternative.B; // Always use profile B as requested
                    softModemAudioConfig.Channels[0].NumSubchan = 1;

                    // Create HDLC receiver with frame event handler
                    softModemHdlcReceiver = new HamLib.HdlcRec2();
                    softModemHdlcReceiver.FrameReceived += SoftModemHdlcReceiver_FrameReceived;
                    softModemHdlcReceiver.Init(softModemAudioConfig);

                    // Create FX.25 receiver with MultiModem wrapper for frame processing
                    var fx25MultiModem = new Fx25MultiModemWrapper(this);
                    softModemFx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

                    // Create bridge that feeds bits to both HDLC and FX.25 receivers
                    softModemBridge = new HdlcFx25Bridge(softModemHdlcReceiver, softModemFx25Receiver);

                    // Create and initialize PSK demodulator with the bridge
                    softModemPskDemodulator = new HamLib.DemodPsk(softModemBridge);
                    softModemPskDemodState = new HamLib.PskDemodulatorState();
                    softModemPskDemodulator.Init(
                        HamLib.ModemType.Qpsk,      // QPSK mode for 2400 bps
                        HamLib.V26Alternative.B,    // Use profile B as requested
                        32000,                      // Sample rate (matches PCM from SBC decoder)
                        2400,                       // Bits per second
                        'B',                        // Profile B (fallback if V26Alt not used internally)
                        softModemPskDemodState
                    );

                    _softwareModemMode = mode;
                    softModemInitialized = true;
                    fx25Initialized = true;
                    Debug("Software modem (PSK 2400 bps decoder with FX.25 support) initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing PSK 2400 software modem: {ex.Message}");
                    _softwareModemMode = SoftwareModemModeType.Disabled;
                    softModemInitialized = false;
                    fx25Initialized = false;
                }
            }
            else if (mode == SoftwareModemModeType.Psk4800)
            {
                try
                {
                    // Initialize FX.25 subsystem
                    HamLib.Fx25.Init(0); // Debug level 0 = errors only

                    // Setup audio configuration for 32kHz, 16-bit, mono (matches PCM from SBC decoder)
                    softModemAudioConfig = new HamLib.AudioConfig();
                    softModemAudioConfig.Devices[0].Defined = true;
                    softModemAudioConfig.Devices[0].SamplesPerSec = 32000;
                    softModemAudioConfig.Devices[0].BitsPerSample = 16;
                    softModemAudioConfig.Devices[0].NumChannels = 1;

                    // Configure for PSK 4800 bps (8PSK)
                    softModemAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    softModemAudioConfig.Channels[0].ModemType = HamLib.ModemType.Psk8;
                    softModemAudioConfig.Channels[0].Baud = 1600; // 4800 bps / 3 bits per symbol = 1600 baud
                    softModemAudioConfig.Channels[0].V26Alt = HamLib.V26Alternative.B; // Always use profile B as requested
                    softModemAudioConfig.Channels[0].NumSubchan = 1;

                    // Create HDLC receiver with frame event handler
                    softModemHdlcReceiver = new HamLib.HdlcRec2();
                    softModemHdlcReceiver.FrameReceived += SoftModemHdlcReceiver_FrameReceived;
                    softModemHdlcReceiver.Init(softModemAudioConfig);

                    // Create FX.25 receiver with MultiModem wrapper for frame processing
                    var fx25MultiModem = new Fx25MultiModemWrapper(this);
                    softModemFx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

                    // Create bridge that feeds bits to both HDLC and FX.25 receivers
                    softModemBridge = new HdlcFx25Bridge(softModemHdlcReceiver, softModemFx25Receiver);

                    // Create and initialize PSK demodulator with the bridge
                    softModemPskDemodulator = new HamLib.DemodPsk(softModemBridge);
                    softModemPskDemodState = new HamLib.PskDemodulatorState();
                    softModemPskDemodulator.Init(
                        HamLib.ModemType.Psk8,      // 8PSK mode for 4800 bps
                        HamLib.V26Alternative.B,    // Use profile B as requested
                        32000,                      // Sample rate (matches PCM from SBC decoder)
                        4800,                       // Bits per second
                        'B',                        // Profile B (fallback if V26Alt not used internally)
                        softModemPskDemodState
                    );

                    _softwareModemMode = mode;
                    softModemInitialized = true;
                    fx25Initialized = true;
                    Debug("Software modem (PSK 4800 bps decoder with FX.25 support) initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing PSK 4800 software modem: {ex.Message}");
                    _softwareModemMode = SoftwareModemModeType.Disabled;
                    softModemInitialized = false;
                    fx25Initialized = false;
                }
            }
            else if (mode == SoftwareModemModeType.G3RUH9600)
            {
                try
                {
                    // Initialize FX.25 subsystem
                    HamLib.Fx25.Init(0); // Debug level 0 = errors only

                    // Setup audio configuration for 32kHz, 16-bit, mono (matches PCM from SBC decoder)
                    softModemAudioConfig = new HamLib.AudioConfig();
                    softModemAudioConfig.Devices[0].Defined = true;
                    softModemAudioConfig.Devices[0].SamplesPerSec = 32000;
                    softModemAudioConfig.Devices[0].BitsPerSample = 16;
                    softModemAudioConfig.Devices[0].NumChannels = 1;

                    // Configure for G3RUH 9600 baud baseband
                    softModemAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    softModemAudioConfig.Channels[0].ModemType = HamLib.ModemType.Baseband;
                    softModemAudioConfig.Channels[0].Baud = 9600;
                    softModemAudioConfig.Channels[0].NumSubchan = 1;

                    // Create HDLC receiver with frame event handler
                    softModemHdlcReceiver = new HamLib.HdlcRec2();
                    softModemHdlcReceiver.FrameReceived += SoftModemHdlcReceiver_FrameReceived;
                    softModemHdlcReceiver.Init(softModemAudioConfig);

                    // Create FX.25 receiver with MultiModem wrapper for frame processing
                    var fx25MultiModem = new Fx25MultiModemWrapper(this);
                    softModemFx25Receiver = new HamLib.Fx25Rec(fx25MultiModem);

                    // Create bridge that feeds bits to both HDLC and FX.25 receivers
                    softModemBridge = new HdlcFx25Bridge(softModemHdlcReceiver, softModemFx25Receiver);

                    // Create and initialize 9600 baud demodulator with the bridge
                    softModemDemodState = new HamLib.DemodulatorState();
                    softModem9600State = new HamLib.Demod9600.Demod9600State();
                    
                    // Initialize the G3RUH 9600 baud demodulator
                    // Parameters: sample rate, upsample factor, baud rate, demod state, 9600 state
                    HamLib.Demod9600.Init(
                        32000,  // Sample rate (matches PCM from SBC decoder)
                        1,      // Upsample factor (1 = no upsampling)
                        9600,   // Baud rate
                        softModemDemodState,
                        softModem9600State
                    );

                    _softwareModemMode = mode;
                    softModemInitialized = true;
                    fx25Initialized = true;
                    Debug("Software modem (G3RUH 9600 baud with FX.25 support) initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing G3RUH 9600 software modem: {ex.Message}");
                    _softwareModemMode = SoftwareModemModeType.Disabled;
                    softModemInitialized = false;
                    fx25Initialized = false;
                }
            }
        }

        // Handle frames decoded by software modem
        private void SoftModemHdlcReceiver_FrameReceived(object sender, HamLib.FrameReceivedEventArgs e)
        {
            try
            {
                byte[] frameData = new byte[e.FrameLength];
                Array.Copy(e.Frame, frameData, e.FrameLength);
                TncDataFragment fragment = new TncDataFragment(true, 0, frameData, parent.HtStatus.curr_ch_id, parent.HtStatus.curr_region);
                fragment.incoming = true;
                fragment.channel_name = currentChannelName;
                
                if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                {
                    fragment.encoding = TncDataFragment.FragmentEncodingType.SoftwareG3RUH9600;
                }
                else if (_softwareModemMode == SoftwareModemModeType.Psk2400)
                {
                    fragment.encoding = TncDataFragment.FragmentEncodingType.SoftwarePsk2400;
                }
                else if (_softwareModemMode == SoftwareModemModeType.Psk4800)
                {
                    fragment.encoding = TncDataFragment.FragmentEncodingType.SoftwarePsk4800;
                }
                else
                {
                    fragment.encoding = TncDataFragment.FragmentEncodingType.SoftwareAfsk1200;
                }
                
                fragment.time = DateTime.Now;

                if (e.CorrectionInfo != null)
                {
                    if (e.CorrectionInfo.FecType == HamLib.FecType.Fx25)
                    {
                        fragment.frame_type = TncDataFragment.FragmentFrameType.FX25;
                        if (e.CorrectionInfo.RsSymbolsCorrected >= 0)
                        {
                            fragment.corrections = e.CorrectionInfo.RsSymbolsCorrected;
                        }
                        else
                        {
                            fragment.corrections = 0;
                        }
                    }
                    else
                    {
                        fragment.frame_type = TncDataFragment.FragmentFrameType.AX25;
                        if (e.CorrectionInfo.CorrectedBitPositions != null)
                        {
                            fragment.corrections = e.CorrectionInfo.CorrectedBitPositions.Count;
                        }
                        else
                        {
                            fragment.corrections = 0;
                        }
                    }
                }
                else
                {
                    fragment.frame_type = TncDataFragment.FragmentFrameType.AX25;
                    fragment.corrections = 0;
                }

                DispatchSoftModemPacketDecoded(fragment);
            }
            catch (Exception ex) { Debug($"FrameReceived error: {ex.Message}"); }
        }

        // Reset software modem state (call when radio loses signal)
        public void ResetSoftModem()
        {
            lock (softModemLock)
            {
                if (!softModemInitialized) return;

                try
                {
                    if (_softwareModemMode == SoftwareModemModeType.Afsk1200)
                {
                    if (softModemDemodulator != null && softModemDemodState != null)
                    {
                        softModemDemodulator.Init(
                            32000,  // Sample rate
                            1200,   // Baud rate
                            1200,   // Mark frequency
                            2200,   // Space frequency
                            'A',    // Profile
                            softModemDemodState
                        );
                    }
                }
                else if (_softwareModemMode == SoftwareModemModeType.Psk2400)
                {
                    if (softModemPskDemodulator != null && softModemPskDemodState != null)
                    {
                        softModemPskDemodulator.Init(
                            HamLib.ModemType.Qpsk,      // QPSK mode for 2400 bps
                            HamLib.V26Alternative.B,    // Use profile B as requested
                            32000,                      // Sample rate
                            2400,                       // Bits per second
                            'B',                        // Profile B (fallback)
                            softModemPskDemodState
                        );
                    }
                }
                else if (_softwareModemMode == SoftwareModemModeType.Psk4800)
                {
                    if (softModemPskDemodulator != null && softModemPskDemodState != null)
                    {
                        softModemPskDemodulator.Init(
                            HamLib.ModemType.Psk8,      // 8PSK mode for 4800 bps
                            HamLib.V26Alternative.B,    // Use profile B as requested
                            32000,                      // Sample rate
                            4800,                       // Bits per second
                            'B',                        // Profile B (fallback)
                            softModemPskDemodState
                        );
                    }
                }
                else if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                {
                    if (softModem9600State != null && softModemDemodState != null)
                    {
                        // Reinitialize the G3RUH 9600 baud demodulator
                        HamLib.Demod9600.Init(
                            32000,  // Sample rate
                            1,      // Upsample factor
                            9600,   // Baud rate
                            softModemDemodState,
                            softModem9600State
                        );
                    }
                }

                    Debug("Software modem reset");
                }
                catch (Exception ex) { Debug($"ResetSoftModem error: {ex.Message}"); }
            }
        }

        // Bridge that feeds bits to both HDLC and FX.25 receivers
        private class HdlcFx25Bridge : HamLib.IHdlcReceiver
        {
            private HamLib.IHdlcReceiver _hdlcReceiver;
            private HamLib.Fx25Rec _fx25Receiver;

            public HdlcFx25Bridge(HamLib.IHdlcReceiver hdlcReceiver, HamLib.Fx25Rec fx25Receiver)
            {
                _hdlcReceiver = hdlcReceiver;
                _fx25Receiver = fx25Receiver;
            }

            public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
            {
                _hdlcReceiver.RecBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
                _fx25Receiver.RecBit(chan, subchan, slice, raw);
            }

            public void DcdChange(int chan, int subchan, int slice, bool dcdOn)
            {
                _hdlcReceiver.DcdChange(chan, subchan, slice, dcdOn);
            }
        }

        // Wrapper for MultiModem to process FX.25 frames
        private class Fx25MultiModemWrapper : HamLib.MultiModem
        {
            private RadioAudio _parent;

            public Fx25MultiModemWrapper(RadioAudio parent)
            {
                _parent = parent;
                this.PacketReady += OnPacketReady;
            }

            private void OnPacketReady(object sender, HamLib.PacketReadyEventArgs e)
            {
                try
                {
                    if (e.Packet != null)
                    {
                        byte[] frameData = e.Packet.GetInfo(out int frameLen);
                        if (frameData == null || frameLen == 0)
                        {
                            frameData = new byte[2048];
                            frameLen = e.Packet.Pack(frameData);
                        }
                        
                        TncDataFragment fragment = new TncDataFragment(true, 0, frameData, 
                            _parent.parent.HtStatus.curr_ch_id, _parent.parent.HtStatus.curr_region);
                        fragment.incoming = true;
                        fragment.channel_name = _parent.currentChannelName;
                        //fragment.encoding = TncDataFragment.FragmentEncodingType.SoftwareAfsk1200;
                        fragment.encoding = TncDataFragment.FragmentEncodingType.SoftwarePsk2400;
                        fragment.frame_type = TncDataFragment.FragmentFrameType.FX25;
                        fragment.time = DateTime.Now;

                        if (e.CorrectionInfo != null && e.CorrectionInfo.RsSymbolsCorrected >= 0)
                        {
                            fragment.corrections = e.CorrectionInfo.RsSymbolsCorrected;
                        }
                        else
                        {
                            fragment.corrections = 0;
                        }

                        _parent.DispatchSoftModemPacketDecoded(fragment);
                    }
                }
                catch (Exception ex) { _parent.Debug($"FX.25 frame error: {ex.Message}"); }
            }
        }

        public bool IsAudioEnabled { get { return running; } }

        private static unsafe int UnescapeBytesInPlace(byte[] buffer)
        {
            if (buffer == null || buffer.Length == 0) return 0;
            fixed (byte* pBuffer = buffer)
            {
                byte* src = pBuffer;
                byte* dst = pBuffer;
                byte* end = pBuffer + buffer.Length;
                while (src < end)
                {
                    if (*src == 0x7d) // Escape byte
                    {
                        src++;
                        if (src < end) { *dst = (byte)(*src ^ 0x20); dst++; } else { break; }
                    }
                    else { *dst = *src; dst++; }
                    src++;
                }
                return (int)(dst - pBuffer); // New length after unescaping
            }
        }

        private static unsafe byte[] EscapeBytes(byte cmd, byte[] b, int len)
        {
            // Estimate worst case: each byte could expand to 2 bytes (if it needs escaping), plus 2 for start/end
            int maxLen = 2 + len * 2;
            byte[] result = new byte[maxLen];
            fixed (byte* bPtr = b)
            fixed (byte* rPtr = result)
            {
                byte* src = bPtr;
                byte* dest = rPtr;
                *dest++ = 0x7e;
                *dest++ = cmd;
                for (int i = 0; i < len; i++)
                {
                    byte currentByte = *src++;
                    if (currentByte == 0x7d || currentByte == 0x7e)
                    {
                        *dest++ = 0x7d;
                        *dest++ = (byte)(currentByte ^ 0x20);
                    }
                    else { *dest++ = currentByte; }
                }
                *dest++ = 0x7e;
                int finalLen = (int)(dest - rPtr);
                // Resize array to actual length
                Array.Resize(ref result, finalLen);
            }
            return result;
        }

        private static byte[] ExtractData(ref MemoryStream inputStream)
        {
            if (inputStream.Length < 2) { inputStream.Position = 0; return null; }

            // Fall back to GetBuffer if TryGetBuffer isn't available (rare)
            if (!inputStream.TryGetBuffer(out ArraySegment<byte> bufferSegment))
            {
                bufferSegment = new ArraySegment<byte>(inputStream.GetBuffer(), 0, (int)inputStream.Length);
            }

            byte[] buffer = bufferSegment.Array;
            int bufferLength = bufferSegment.Count;
            int start = -1, end = -1;

            for (int i = 0; i < bufferLength; i++)
            {
                if (buffer[i] == 0x7e)
                {
                    if (start == -1)
                    {
                        start = i;
                        // Check if double marker (0x7e 0x7e)
                        if (start + 1 < bufferLength && buffer[start + 1] == 0x7e) { start++; }
                    }
                    else
                    {
                        end = i;
                        break;
                    }
                }
            }

            if (start != -1 && end != -1 && end > start)
            {
                int dataLength = end - start - 1;
                byte[] extractedData = new byte[dataLength];
                Buffer.BlockCopy(buffer, start + 1, extractedData, 0, dataLength);

                // Move remaining data to the beginning
                int remaining = bufferLength - (end + 1);
                if (remaining > 0)
                {
                    Buffer.BlockCopy(buffer, end + 1, buffer, 0, remaining);
                    inputStream.SetLength(remaining);
                }
                else { inputStream.SetLength(0); }
                return extractedData;
            }
            else
            {
                inputStream.Position = 0;
                return null;
            }
        }

        public void Stop()
        {
            lock (connectionLock)
            {
                if (running == false && audioLoopTask == null) return;
                running = false;
                
                // Cancel the audio loop
                try { audioLoopCts?.Cancel(); } catch (Exception) { }
            }
            
            // Wait for the audio loop to finish (with timeout)
            if (audioLoopTask != null)
            {
                try { audioLoopTask.Wait(TimeSpan.FromSeconds(3)); } catch (Exception) { }
            }
            
            lock (connectionLock)
            {
                // Dispose Bluetooth resources in correct order
                // First close streams, then socket, then service
                try { winRtInputStream?.Close(); } catch (Exception) { }
                try { winRtInputStream?.Dispose(); } catch (Exception) { }
                winRtInputStream = null;
                
                try { winRtOutputStream?.Close(); } catch (Exception) { }
                try { winRtOutputStream?.Dispose(); } catch (Exception) { }
                winRtOutputStream = null;
                
                try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                bluetoothSocket = null;
                
                try { rfcommService?.Dispose(); } catch (Exception) { }
                rfcommService = null;
                
                try { audioStream?.Close(); } catch (Exception) { }
                try { audioStream?.Dispose(); } catch (Exception) { }
                audioStream = null;
                
                try { audioLoopCts?.Dispose(); } catch (Exception) { }
                audioLoopCts = null;
                audioLoopTask = null;
            }
            
            DispatchAudioStateChanged(false);
            
            // Give the OS time to release the socket
            Thread.Sleep(100);
        }

        public void Start()
        {
            lock (connectionLock)
            {
                if (running || isConnecting) return;
                isConnecting = true;
            }
            audioLoopTask = Task.Run(() => { StartAsync(); });
        }

        public float Volume
        {
            get { return volumeProvider?.Volume ?? InputVolume; }
            set { InputVolume = value; if (volumeProvider != null) { volumeProvider.Volume = value; } }
        }

        public void SetOutputDevice(string deviceid)
        {
            try { if ((currentOutputDevice != null) && (currentOutputDevice.ID == deviceid)) { return; } } catch (Exception) { }

            MMDevice targetDevice = null;
            MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
            if (deviceid != null)
            {
                if (deviceid.Length > 0)
                {
                    targetDevice = enumerator.GetDevice(deviceid);
                }
                else
                {
                    try { targetDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia); } catch (Exception) { }
                }
                if (targetDevice == null) { Debug("No audio device found."); return; }
            }

            if (waveOut != null) { waveOut.Stop(); waveOut.Dispose(); waveOut = null; }
            waveProvider = null;
            volumeProvider = null;
            if (targetDevice == null) { return; }

            // Configure audio output (adjust format based on SBC parameters)
            // These are common A2DP SBC defaults, but the actual device might differ.
            WaveFormat waveFormat = new WaveFormat(32000, 16, 1);
            waveProvider = new BufferedWaveProvider(waveFormat);
            var sampleProvider = waveProvider.ToSampleProvider();
            currentOutputDevice = targetDevice;

            // Wrap with volume control
            volumeProvider = new VolumeSampleProvider(sampleProvider);
            volumeProvider.Volume = OutputVolume;

            waveOut = new WasapiOut(targetDevice, AudioClientShareMode.Shared, true, 50); // ****
            waveOut.Init(volumeProvider);
            waveOut.Play();
        }

        private async void StartAsync()
        {
            CancellationToken cancellationToken;
            
            lock (connectionLock)
            {
                running = true;
                audioLoopCts = new CancellationTokenSource();
                cancellationToken = audioLoopCts.Token;
            }

            // Use WinRT Bluetooth APIs to connect to the device
            WinBluetooth.BluetoothDevice btDevice = null;
            WinRfcomm.RfcommDeviceService rfcommService = null;
            Windows.Networking.Sockets.StreamSocket socket = null;

            Debug("Attempting to connect using WinRT APIs...");
            try
            {
                // Convert MAC address to the format needed by WinRT (with colons)
                string macFormatted = MacAddress;
                if (!macFormatted.Contains(":"))
                {
                    macFormatted = string.Join(":", Enumerable.Range(0, 6).Select(i => MacAddress.Substring(i * 2, 2)));
                }

                // Get the Bluetooth device by MAC address
                ulong btAddress = Convert.ToUInt64(MacAddress.Replace(":", "").Replace("-", ""), 16);
                btDevice = await WinBluetooth.BluetoothDevice.FromBluetoothAddressAsync(btAddress);
                
                if (btDevice == null)
                {
                    Debug("Could not find Bluetooth device with address: " + MacAddress);
                    running = false;
                    return;
                }

                Debug($"Found device: {btDevice.Name}");

                // Get RFCOMM services from the device
                var rfcommServices = await btDevice.GetRfcommServicesAsync();
                
                if (rfcommServices.Services.Count == 0)
                {
                    Debug("No RFCOMM services found on device");
                    running = false;
                    return;
                }

                // Find the audio service (GenericAudio UUID: 00001203-0000-1000-8000-00805f9b34fb)
                // or try to find any available service
                Guid genericAudioUuid = new Guid("00001203-0000-1000-8000-00805f9b34fb");
                
                foreach (var service in rfcommServices.Services)
                {
                    Debug($"Found RFCOMM service: {service.ServiceId.Uuid} - {service.ConnectionServiceName}");
                    if (service.ServiceId.Uuid == genericAudioUuid)
                    {
                        rfcommService = service;
                        break;
                    }
                }

                // If GenericAudio not found, try the second service (index 1) as it might be the audio channel
                if (rfcommService == null && rfcommServices.Services.Count > 1)
                {
                    rfcommService = rfcommServices.Services[0];
                    Debug($"Using service at index 0: {rfcommService.ServiceId.Uuid}");
                }
                else if (rfcommService == null && rfcommServices.Services.Count > 0)
                {
                    rfcommService = rfcommServices.Services[0];
                    Debug($"Using first available service: {rfcommService.ServiceId.Uuid}");
                }

                if (rfcommService == null)
                {
                    Debug("Could not find suitable RFCOMM service");
                    running = false;
                    return;
                }

                // Connect to the RFCOMM service
                bluetoothSocket = new Windows.Networking.Sockets.StreamSocket();
                this.rfcommService = rfcommService;
                await bluetoothSocket.ConnectAsync(
                    rfcommService.ConnectionHostName,
                    rfcommService.ConnectionServiceName,
                    Windows.Networking.Sockets.SocketProtectionLevel.BluetoothEncryptionAllowNullAuthentication);

                Debug("Successfully connected to the RFCOMM channel.");
            }
            catch (Exception ex)
            {
                Debug($"Connection error: {ex.Message}");
                lock (connectionLock)
                {
                    try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                    bluetoothSocket = null;
                    try { rfcommService?.Dispose(); } catch (Exception) { }
                    this.rfcommService = null;
                    running = false;
                    isConnecting = false;
                }
                return;
            }

            // Create stream wrapper for WinRT socket
            try
            {
                lock (connectionLock)
                {
                    isConnecting = false;
                    if (cancellationToken.IsCancellationRequested)
                    {
                        running = false;
                        try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                        bluetoothSocket = null;
                        try { rfcommService?.Dispose(); } catch (Exception) { }
                        this.rfcommService = null;
                        return;
                    }
                    
                    winRtInputStream = bluetoothSocket.InputStream.AsStreamForRead();
                    winRtOutputStream = bluetoothSocket.OutputStream.AsStreamForWrite();
                    audioStream = null; // We use winRtOutputStream directly now
                }

                // Initialize C# SBC implementation
                sbcDecoder = new SbcDecoder();
                sbcEncoder = new SbcEncoder();

                // Configure decoder frame (will be updated when parsing actual frames)
                sbcDecoderFrame = new SbcFrame
                {
                    Frequency = SbcFrequency.Freq32K,
                    Blocks = 16,
                    Mode = SbcMode.Mono,
                    AllocationMethod = SbcBitAllocationMethod.Loudness,
                    Subbands = 8,
                    Bitpool = 18
                };

                // Configure encoder frame
                sbcEncoderFrame = new SbcFrame
                {
                    Frequency = SbcFrequency.Freq32K,
                    Blocks = 16,
                    Mode = SbcMode.Mono,
                    AllocationMethod = SbcBitAllocationMethod.Loudness,
                    Subbands = 8,
                    Bitpool = 18
                };

                pcmInputSizePerFrame = sbcEncoderFrame.Blocks * sbcEncoderFrame.Subbands * 2; // 16-bit samples
                sbcOutputBuffer = new byte[1024];

                // If the output audio device is not set, use the default one
                if (waveOut == null) { SetOutputDevice(""); }

                MemoryStream accumulator = new MemoryStream();
                
                Debug("Ready to receive data.");
                DispatchAudioStateChanged(true);
                byte[] receiveBuffer = new byte[ReceiveBufferSize];

                while (running && !cancellationToken.IsCancellationRequested)
                {
                    // Receive data asynchronously from WinRT stream with cancellation support
                    int bytesRead;
                    try
                    {
                        bytesRead = await winRtInputStream.ReadAsync(receiveBuffer, 0, receiveBuffer.Length, cancellationToken);
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                    if (bytesRead > 0)
                    {
                        byte[] frame;
                        accumulator.Write(receiveBuffer, 0, bytesRead);
                        while ((frame = ExtractData(ref accumulator)) != null)
                        {
                            int uframeLength = UnescapeBytesInPlace(frame);
                            if (uframeLength == 0) break;
                            switch (frame[0])
                            {
                                case 0x00: // Audio normal
                                case 0x03: // Audio odd
                                    if (!inAudioRun)
                                    {
                                        inAudioRun = true;
                                        DispatchAudioDataStart();
                                    }
                                    DecodeSbcFrame(frame, 1, uframeLength - 1);
                                    break;
                                case 0x01: // Audio end
                                    //Debug("Command: 0x01, Audio End, Size: " + uframeLength);// + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                    inAudioRun = false;
                                    DispatchAudioDataEnd();
                                    break;
                                case 0x02: // Audio ACK
                                    //Debug("Command: 0x02, Audio Ack, Size: " + uframeLength);// + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                    break;
                                default:
                                    Debug($"Unknown command: {frame[0]}");
                                    break;
                            }
                        }
                    }
                    else if (bytesRead == 0)
                    {
                        if (running) { Debug("Connection closed by remote host."); }
                        break;
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

                DispatchAudioStateChanged(false);
                waveOut?.Stop();
                waveOut?.Dispose();
                waveOut = null;

                // Dispose Bluetooth resources in correct order
                lock (connectionLock)
                {
                    try { winRtInputStream?.Close(); } catch (Exception) { }
                    try { winRtInputStream?.Dispose(); } catch (Exception) { }
                    winRtInputStream = null;
                    
                    try { winRtOutputStream?.Close(); } catch (Exception) { }
                    try { winRtOutputStream?.Dispose(); } catch (Exception) { }
                    winRtOutputStream = null;
                    
                    try { bluetoothSocket?.Dispose(); } catch (Exception) { }
                    bluetoothSocket = null;
                    
                    try { rfcommService?.Dispose(); } catch (Exception) { }
                    rfcommService = null;
                    
                    try { audioStream?.Close(); } catch (Exception) { }
                    try { audioStream?.Dispose(); } catch (Exception) { }
                    audioStream = null;
                }

                // SBC cleanup
                sbcDecoder = null;
                sbcEncoder = null;

                Debug("Bluetooth connection closed.");
            }
        }

        private int DecodeSbcFrame(byte[] sbcFrame, int start, int length)
        {
            if (sbcFrame == null || sbcFrame.Length == 0) return 1;

            // Use C# SBC decoder
            try
            {
                int offset = start;
                int remaining = length;
                int totalWritten = 0;

                // Loop through all SBC frames in the buffer
                while (remaining > 0)
                {
                    // Extract the current SBC frame slice
                    byte[] sbcData = new byte[remaining];
                    Buffer.BlockCopy(sbcFrame, offset, sbcData, 0, remaining);

                    // Decode one SBC frame
                    if (!sbcDecoder.Decode(sbcData, out short[] pcmLeft, out short[] pcmRight, out SbcFrame frame))
                    {
                        break; // Stop on decode error
                    }

                    // Get the size of the frame we just decoded
                    int frameSize = frame.GetFrameSize();
                    if (frameSize <= 0 || frameSize > remaining)
                    {
                        break; // Invalid frame size
                    }

                    // Convert short[] to byte[] (16-bit PCM)
                    int pcmBytes = pcmLeft.Length * 2;
                    if (totalWritten + pcmBytes > pcmFrame.Length)
                    {
                        // Expand buffer if needed
                        Array.Resize(ref pcmFrame, totalWritten + pcmBytes);
                    }

                    Buffer.BlockCopy(pcmLeft, 0, pcmFrame, totalWritten, pcmBytes);
                    totalWritten += pcmBytes;

                    // Advance to next frame
                    offset += frameSize;
                    remaining -= frameSize;
                }

                // Make use of all accumulated PCM data
                if (totalWritten > 0)
                {
                    if (parent.IsOnMuteChannel() == false)
                    {
                        if (waveProvider != null)
                        {
                            try { waveProvider.AddSamples(pcmFrame, 0, totalWritten); }
                            catch (Exception ex) { SetOutputDevice(null); Debug("WaveProvider AddSamples: " + ex.ToString()); }
                        }
                        if (recording != null)
                        {
                            try { recording.Write(pcmFrame, 0, totalWritten); }
                            catch (Exception ex) { Debug("Recording Write Error: " + ex.ToString()); }
                        }
                        DispatchAudioDataAvailable(pcmFrame, 0, totalWritten, currentChannelName, false);
                        
                        // Calculate and dispatch output amplitude (after volume is applied conceptually)
                        // Fast calculation: find max sample and normalize to 0.0-1.0, scaled by output volume
                        float amplitude = CalculatePcmAmplitude(pcmFrame, totalWritten) * OutputVolume;
                        broker.Dispatch(DeviceId, "OutputAmplitude", amplitude, store: false);
                    }

                    // We need to send the audio into the AFPK1200 or 9600 software modem for decoding
                    SoftModemPcmFrame(pcmFrame, 0, totalWritten, currentChannelName);
                }

                return 0;
            }
            catch (Exception ex)
            {
                Debug("C# SBC Decode Error: " + ex.ToString());
                return 2;
            }
        }

        private bool EncodeSbcFrame(byte[] pcmInputData, int pcmOffset, int pcmLength, out byte[] encodedSbcFrame, out int bytesConsumed)
        {
            encodedSbcFrame = null;
            bytesConsumed = 0;
            if (pcmInputData == null) { return false; }
            if (sbcOutputBuffer == null) { return false; }
            if (pcmLength < pcmInputSizePerFrame) { return false; }
            if (pcmOffset < 0 || pcmOffset >= pcmInputData.Length || pcmOffset + pcmInputSizePerFrame > pcmInputData.Length) { return false; }

            // Use C# SBC encoder
            try
            {
                int TotalToConsume = pcmLength;
                int TotalGenerated = 0;
                int totalBytesConsumed = 0;
                byte[] outputBuffer = new byte[1024];
                int outputOffset = 0;

                while ((TotalToConsume >= pcmInputSizePerFrame) && (TotalGenerated < 300))
                {
                    int samplesPerChannel = sbcEncoderFrame.Blocks * sbcEncoderFrame.Subbands;

                    // Convert byte[] PCM to short[]
                    short[] pcmSamples = new short[samplesPerChannel];
                    Buffer.BlockCopy(pcmInputData, pcmOffset + totalBytesConsumed, pcmSamples, 0, samplesPerChannel * 2);

                    // Encode the frame
                    byte[] sbcFrameData = sbcEncoder.Encode(pcmSamples, null, sbcEncoderFrame);
                    if (sbcFrameData == null || sbcFrameData.Length == 0)
                    {
                        break;
                    }

                    // Copy to output buffer
                    if (outputOffset + sbcFrameData.Length > outputBuffer.Length)
                    {
                        break;
                    }
                    Buffer.BlockCopy(sbcFrameData, 0, outputBuffer, outputOffset, sbcFrameData.Length);
                    outputOffset += sbcFrameData.Length;

                    int bytesConsumedThisRound = samplesPerChannel * 2; // 16-bit samples
                    TotalToConsume -= bytesConsumedThisRound;
                    TotalGenerated += sbcFrameData.Length;
                    totalBytesConsumed += bytesConsumedThisRound;
                }

                if (TotalGenerated > 0)
                {
                    encodedSbcFrame = new byte[TotalGenerated];
                    Buffer.BlockCopy(outputBuffer, 0, encodedSbcFrame, 0, TotalGenerated);
                    bytesConsumed = totalBytesConsumed;
                    return true;
                }

                return false;
            }
            catch (Exception ex)
            {
                Debug("C# SBC Encode Error: " + ex.ToString());
                return false;
            }
        }

        //private bool VoiceTransmit = false;
        private bool VoiceTransmitCancel = false;

        public void CancelVoiceTransmit()
        {
            waveProvider.ClearBuffer();
            VoiceTransmitCancel = true;
            transmissionTokenSource?.Cancel();
        }

        // Voice transmission fields
        private ConcurrentQueue<byte[]> pcmQueue = new ConcurrentQueue<byte[]>();
        private bool isTransmitting = false;
        private CancellationTokenSource transmissionTokenSource = null;
        private TaskCompletionSource<bool> newDataAvailable = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        private bool PlayInputBack = false;
        private byte[] ReminderTransmitPcmAudio = null;

        // Packet transmission fields
        private ConcurrentQueue<TncDataFragment> packetQueue = new ConcurrentQueue<TncDataFragment>();
        private bool isTransmittingPacket = false;
        private Task packetTransmitTask = null;
        private HamLib.AudioConfig packetAudioConfig = null;
        private HamLib.GenTone packetGenTone = null;
        private HamLib.AudioBuffer packetAudioBuffer = null;
        private HamLib.HdlcSend packetHdlcSend = null;
        private HamLib.Fx25Send packetFx25Send = null;

        // Transmit a packet (AX.25 or FX.25). Queued if radio is busy.
        public void TransmitPacket(TncDataFragment fragment)
        {
            if (fragment == null || fragment.data == null || fragment.data.Length == 0)
            {
                Debug("TransmitPacket: Invalid fragment");
                return;
            }

            packetQueue.Enqueue(fragment);
            if (!isTransmittingPacket)
            {
                StartPacketTransmitter();
            }
        }

        // Initialize packet transmission. Call with softModemLock held.
        private void InitializePacketTransmitter()
        {
            if (packetAudioConfig != null) return;

            if (_softwareModemMode == SoftwareModemModeType.Afsk1200)
            {
                try
                {
                    // Initialize FX.25 if not already done
                    if (!fx25Initialized)
                    {
                        HamLib.Fx25.Init(0);
                        fx25Initialized = true;
                    }

                    // Set up audio configuration for AFSK 1200 baud (32kHz to match radio)
                    packetAudioConfig = new HamLib.AudioConfig();
                    packetAudioConfig.Devices[0].Defined = true;
                    packetAudioConfig.Devices[0].SamplesPerSec = 32000; // Match radio sample rate
                    packetAudioConfig.Devices[0].BitsPerSample = 16;
                    packetAudioConfig.Devices[0].NumChannels = 1;

                    packetAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    packetAudioConfig.Channels[0].ModemType = HamLib.ModemType.Afsk;
                    packetAudioConfig.Channels[0].MarkFreq = 1200;
                    packetAudioConfig.Channels[0].SpaceFreq = 2200;
                    packetAudioConfig.Channels[0].Baud = 1200;
                    packetAudioConfig.Channels[0].Txdelay = 30; // 300ms preamble
                    packetAudioConfig.Channels[0].Txtail = 10;  // 100ms postamble

                    // Create audio buffer
                    packetAudioBuffer = new HamLib.AudioBuffer(HamLib.AudioConfig.MaxAudioDevices);

                    // Create tone generator
                    packetGenTone = new HamLib.GenTone(packetAudioBuffer);
                    packetGenTone.Init(packetAudioConfig, 50); // 50% amplitude

                    // Create HDLC sender
                    packetHdlcSend = new HamLib.HdlcSend(packetGenTone, packetAudioConfig);

                    // Create FX.25 sender
                    packetFx25Send = new HamLib.Fx25Send();
                    packetFx25Send.Init(packetGenTone);

                    Debug("Packet transmitter initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing packet transmitter: {ex.Message}");
                    packetAudioConfig = null;
                }
            }

            if (_softwareModemMode == SoftwareModemModeType.Psk2400)
            {
                try
                {
                    // Initialize FX.25 if not already done
                    if (!fx25Initialized)
                    {
                        HamLib.Fx25.Init(0);
                        fx25Initialized = true;
                    }

                    // Set up audio configuration for PSK 2400 bps (32kHz to match radio)
                    packetAudioConfig = new HamLib.AudioConfig();
                    packetAudioConfig.Devices[0].Defined = true;
                    packetAudioConfig.Devices[0].SamplesPerSec = 32000; // Match radio sample rate
                    packetAudioConfig.Devices[0].BitsPerSample = 16;
                    packetAudioConfig.Devices[0].NumChannels = 1;

                    packetAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    packetAudioConfig.Channels[0].ModemType = HamLib.ModemType.Qpsk; // QPSK for 2400 bps
                    packetAudioConfig.Channels[0].Baud = 1200; // 2400 bps / 2 bits per symbol = 1200 baud
                    packetAudioConfig.Channels[0].V26Alt = HamLib.V26Alternative.B; // Always use profile B
                    packetAudioConfig.Channels[0].Txdelay = 30; // 300ms preamble
                    packetAudioConfig.Channels[0].Txtail = 10;  // 100ms postamble

                    // Create audio buffer
                    packetAudioBuffer = new HamLib.AudioBuffer(HamLib.AudioConfig.MaxAudioDevices);

                    // Create tone generator for PSK modulation
                    packetGenTone = new HamLib.GenTone(packetAudioBuffer);
                    packetGenTone.Init(packetAudioConfig, 50); // 50% amplitude

                    // Create HDLC sender
                    packetHdlcSend = new HamLib.HdlcSend(packetGenTone, packetAudioConfig);

                    // Create FX.25 sender
                    packetFx25Send = new HamLib.Fx25Send();
                    packetFx25Send.Init(packetGenTone);

                    Debug("PSK 2400 bps packet transmitter initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing PSK 2400 packet transmitter: {ex.Message}");
                    packetAudioConfig = null;
                }
            }

            if (_softwareModemMode == SoftwareModemModeType.Psk4800)
            {
                try
                {
                    // Initialize FX.25 if not already done
                    if (!fx25Initialized)
                    {
                        HamLib.Fx25.Init(0);
                        fx25Initialized = true;
                    }

                    // Set up audio configuration for PSK 4800 bps (32kHz to match radio)
                    packetAudioConfig = new HamLib.AudioConfig();
                    packetAudioConfig.Devices[0].Defined = true;
                    packetAudioConfig.Devices[0].SamplesPerSec = 32000; // Match radio sample rate
                    packetAudioConfig.Devices[0].BitsPerSample = 16;
                    packetAudioConfig.Devices[0].NumChannels = 1;

                    packetAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    packetAudioConfig.Channels[0].ModemType = HamLib.ModemType.Psk8; // 8PSK for 4800 bps
                    packetAudioConfig.Channels[0].Baud = 1600; // 4800 bps / 3 bits per symbol = 1600 baud
                    packetAudioConfig.Channels[0].V26Alt = HamLib.V26Alternative.B; // Always use profile B
                    packetAudioConfig.Channels[0].Txdelay = 30; // 300ms preamble
                    packetAudioConfig.Channels[0].Txtail = 10;  // 100ms postamble

                    // Create audio buffer
                    packetAudioBuffer = new HamLib.AudioBuffer(HamLib.AudioConfig.MaxAudioDevices);

                    // Create tone generator for PSK modulation
                    packetGenTone = new HamLib.GenTone(packetAudioBuffer);
                    packetGenTone.Init(packetAudioConfig, 50); // 50% amplitude

                    // Create HDLC sender
                    packetHdlcSend = new HamLib.HdlcSend(packetGenTone, packetAudioConfig);

                    // Create FX.25 sender
                    packetFx25Send = new HamLib.Fx25Send();
                    packetFx25Send.Init(packetGenTone);

                    Debug("PSK 4800 bps packet transmitter initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing PSK 4800 packet transmitter: {ex.Message}");
                    packetAudioConfig = null;
                }
            }

            if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
            {
                try
                {
                    // Initialize FX.25 if not already done
                    if (!fx25Initialized)
                    {
                        HamLib.Fx25.Init(0);
                        fx25Initialized = true;
                    }

                    // Set up audio configuration for G3RUH 9600 baud baseband (32kHz to match radio)
                    packetAudioConfig = new HamLib.AudioConfig();
                    packetAudioConfig.Devices[0].Defined = true;
                    packetAudioConfig.Devices[0].SamplesPerSec = 32000; // Match radio sample rate
                    packetAudioConfig.Devices[0].BitsPerSample = 16;
                    packetAudioConfig.Devices[0].NumChannels = 1;

                    packetAudioConfig.ChannelMedium[0] = HamLib.Medium.Radio;
                    packetAudioConfig.Channels[0].ModemType = HamLib.ModemType.Baseband; // Baseband for G3RUH
                    packetAudioConfig.Channels[0].Baud = 9600;
                    packetAudioConfig.Channels[0].Txdelay = 30; // 300ms preamble
                    packetAudioConfig.Channels[0].Txtail = 10;  // 100ms postamble

                    // Create audio buffer
                    packetAudioBuffer = new HamLib.AudioBuffer(HamLib.AudioConfig.MaxAudioDevices);

                    // Create tone generator (handles baseband modulation for G3RUH)
                    packetGenTone = new HamLib.GenTone(packetAudioBuffer);
                    packetGenTone.Init(packetAudioConfig, 50); // 50% amplitude

                    // Create HDLC sender
                    packetHdlcSend = new HamLib.HdlcSend(packetGenTone, packetAudioConfig);

                    // Create FX.25 sender
                    packetFx25Send = new HamLib.Fx25Send();
                    packetFx25Send.Init(packetGenTone);

                    Debug("G3RUH 9600 baud packet transmitter initialized successfully");
                }
                catch (Exception ex)
                {
                    Debug($"Error initializing G3RUH 9600 packet transmitter: {ex.Message}");
                    packetAudioConfig = null;
                }
            }
        }

        // Start packet transmitter background task
        private void StartPacketTransmitter()
        {
            if (isTransmittingPacket || packetTransmitTask != null) return;

            isTransmittingPacket = true;

            packetTransmitTask = Task.Run(async () =>
            {
                while (isTransmittingPacket)
                {
                    if (packetQueue.TryDequeue(out TncDataFragment fragment))
                    {
                        await TransmitPacketAsync(fragment);
                    }
                    else
                    {
                        await Task.Delay(50);
                        if (packetQueue.IsEmpty)
                        {
                            isTransmittingPacket = false;
                            break;
                        }
                    }
                }

                packetTransmitTask = null;
            });
        }

        // Transmit a single packet
        private Task TransmitPacketAsync(TncDataFragment fragment)
        {
            WaveFileWriter debugWavWriter = null;
            try
            {
                InitializePacketTransmitter();

                if (packetAudioConfig == null || packetGenTone == null || packetAudioBuffer == null)
                {
                    Debug("Packet transmitter not initialized");
                    return null;
                }

                int chan = 0;
                packetAudioBuffer.ClearAll();

                // For G3RUH 9600, add 0.5s silence before data
                if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                {
                    int sampleRate = packetAudioConfig.Devices[0].SamplesPerSec;
                    int silenceSamples = sampleRate / 2;
                    for (int i = 0; i < silenceSamples; i++) { packetAudioBuffer.Put(0, 0); }
                }

                int txdelayFlags = packetAudioConfig.Channels[chan].Txdelay;
                packetHdlcSend.SendFlags(chan, txdelayFlags, false, null);

                bool useFx25 = (fragment.frame_type == TncDataFragment.FragmentFrameType.FX25);
                if (useFx25)
                {
                    int fxMode = 32;
                    packetFx25Send.SendFrame(chan, fragment.data, fragment.data.Length, fxMode);
                    Debug($"Transmitting FX.25 packet ({fragment.data.Length} bytes with FEC)");
                }
                else
                {
                    packetHdlcSend.SendFrame(chan, fragment.data, fragment.data.Length, false);
                    Debug($"Transmitting AX.25 packet ({fragment.data.Length} bytes)");
                }

                int txtailFlags = packetAudioConfig.Channels[chan].Txtail;
                packetHdlcSend.SendFlags(chan, txtailFlags, true, (device) => { });

                // For G3RUH 9600, add 0.5s silence after data
                if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                {
                    int sampleRate = packetAudioConfig.Devices[0].SamplesPerSec;
                    int silenceSamples = sampleRate / 2;
                    for (int i = 0; i < silenceSamples; i++) { packetAudioBuffer.Put(0, 0); }
                }

                short[] samples = packetAudioBuffer.GetAndClear(0);
                if (samples != null && samples.Length > 0)
                {
                    byte[] pcmData = new byte[samples.Length * 2];
                    Buffer.BlockCopy(samples, 0, pcmData, 0, pcmData.Length);
                    TransmitVoice(pcmData, 0, pcmData.Length, false);
                    Debug($"Transmitted packet: {samples.Length} samples, {pcmData.Length} bytes PCM");
                }
            }
            catch (Exception ex) { Debug($"TransmitPacketAsync error: {ex.Message}"); }
            finally
            {
                if (debugWavWriter != null)
                {
                    try { debugWavWriter.Dispose(); }
                    catch (Exception) { }
                }
            }
            return null;
        }

        // Transmit packet audio through radio
        private async Task TransmitPacketAudioAsync(byte[] pcmData, bool playLocally)
        {
            if (winRtOutputStream == null || !running)
            {
                Debug("Cannot transmit packet: radio not connected");
                return;
            }

            try
            {
                int offset = 0;
                int length = pcmData.Length;

                while (offset < length)
                {
                    int chunkSize = Math.Min(pcmInputSizePerFrame, length - offset);
                    if (chunkSize < pcmInputSizePerFrame && offset + chunkSize < length) { chunkSize = pcmInputSizePerFrame; }

                    if (chunkSize >= pcmInputSizePerFrame)
                    {
                        byte[] encodedSbcFrame;
                        int bytesConsumed;
                        
                        if (EncodeSbcFrame(pcmData, offset, chunkSize, out encodedSbcFrame, out bytesConsumed))
                        {
                            byte[] escaped = EscapeBytes(0, encodedSbcFrame, encodedSbcFrame.Length);
                            await winRtOutputStream.WriteAsync(escaped, 0, escaped.Length);
                            await winRtOutputStream.FlushAsync();
                            
                            if (playLocally && waveProvider != null)
                            {
                                try { PlayPcmBufferAsync(pcmData, offset, bytesConsumed); }
                                catch (Exception ex) { Debug($"PlayPcmBufferAsync error: {ex.Message}"); }
                            }

                            offset += bytesConsumed;
                        }
                        else { Debug("Failed to encode SBC frame"); break; }
                    }
                    else { break; }
                    await Task.Delay(10);
                }
            }
            catch (Exception ex) { Debug($"TransmitPacketAudioAsync error: {ex.Message}"); }
        }

        public bool TransmitVoice(byte[] pcmInputData, int pcmOffset, int pcmLength, bool play)
        {
            // Copy just the relevant slice of PCM data
            PlayInputBack = play;
            VoiceTransmitCancel = false;
            byte[] pcmSlice = new byte[pcmLength];
            Buffer.BlockCopy(pcmInputData, pcmOffset, pcmSlice, 0, pcmLength);
            pcmQueue.Enqueue(pcmSlice);

            // Signal that new data is available
            if (isTransmitting) { newDataAvailable.TrySetResult(true); }

            StartTransmissionIfNeeded();
            return true;
        }

        private void StartTransmissionIfNeeded()
        {
            if (isTransmitting) return;

            Console.WriteLine("Starting voice transmission...");

            isTransmitting = true;
            transmissionTokenSource = new CancellationTokenSource();
            CancellationToken token = transmissionTokenSource.Token;
            Task.Run(async () =>
            {
                DispatchVoiceTransmitStateChanged(true);
                try
                {
                    while (!token.IsCancellationRequested)
                    {
                        if (pcmQueue.TryDequeue(out var pcmData))
                        {
                            await ProcessPcmDataAsync(pcmData, token);
                        }
                        else
                        {
                            // Wait for up to 100ms for more data. If none arrives, exit the loop.
                            Task delayTask = Task.Delay(100, token);
                            Task signalTask = newDataAvailable.Task;
                            Task completedTask = await Task.WhenAny(delayTask, signalTask);
                            if (completedTask == signalTask)
                            {
                                // New data arrived, reset the signal
                                newDataAvailable = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                            }
                            else { break; }
                        }
                    }
                    // Send end audio frame
                    ReminderTransmitPcmAudio = null;
                    byte[] endAudio = { 0x7e, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7e };
                    if (winRtOutputStream != null)
                    {
                        await winRtOutputStream.WriteAsync(endAudio, 0, endAudio.Length);
                        await winRtOutputStream.FlushAsync();
                    }
                }
                finally
                {
                    DispatchVoiceTransmitStateChanged(false);
                    Console.WriteLine("Voice transmission stopped.");
                    isTransmitting = false;
                }
            }, token);
        }

        private async Task ProcessPcmDataAsync(byte[] pcmData, CancellationToken token)
        {
            int pcmOffset = 0;
            int pcmLength = pcmData.Length;

            if (ReminderTransmitPcmAudio != null)
            {
                // If there are remaining bytes from the previous call, copy them to the beginning of the buffer
                byte[] pcmData2 = new byte[ReminderTransmitPcmAudio.Length + pcmLength];
                Buffer.BlockCopy(ReminderTransmitPcmAudio, 0, pcmData2, 0, ReminderTransmitPcmAudio.Length);
                Buffer.BlockCopy(pcmData, 0, pcmData2, ReminderTransmitPcmAudio.Length, pcmLength);
                pcmData = pcmData2;
                pcmLength = pcmData2.Length;
                ReminderTransmitPcmAudio = null;
            }

            // TODO: Run up to 7 loops of this before using the PCM/SBC data
            while ((pcmLength >= pcmInputSizePerFrame) && (!token.IsCancellationRequested))
            {
                int bytesConsumed = 0;
                byte[] encodedSbcFrame;
                if (!EncodeSbcFrame(pcmData, pcmOffset, pcmLength, out encodedSbcFrame, out bytesConsumed)) { break; }

                // Send the audio frame to the radio
                byte[] escaped = EscapeBytes(0, encodedSbcFrame, encodedSbcFrame.Length);
                if (winRtOutputStream != null)
                {
                    await winRtOutputStream.WriteAsync(escaped, 0, escaped.Length);
                    await winRtOutputStream.FlushAsync();
                }

                // Do extra processing if needed
                if (recording != null)
                {
                    try { recording.Write(pcmData, pcmOffset, bytesConsumed); } catch (Exception ex) { Debug("Recording Write error: " + ex.Message); }
                }
                if (PlayInputBack)
                {
                    try { PlayPcmBufferAsync(pcmData, pcmOffset, bytesConsumed); } catch (Exception ex) { Debug("PlayPcmBufferAsync error: " + ex.Message); }
                }
                try { DispatchAudioDataAvailable(pcmData, pcmOffset, bytesConsumed, currentChannelName, true); } catch (Exception ex) { Debug("GotAudioData error: " + ex.Message); }

                pcmOffset += bytesConsumed;
                pcmLength -= bytesConsumed;
            }

            // If there are remaining bytes, keep them for the next call
            if (pcmLength != 0)
            {
                ReminderTransmitPcmAudio = new byte[pcmLength];
                Buffer.BlockCopy(pcmData, pcmOffset, ReminderTransmitPcmAudio, 0, pcmLength);
            }
        }

        public void PlayPcmBufferAsync(byte[] pcmInputData, int pcmOffset, int pcmLength)
        {
            Task.Run(() =>
           {
               int bytesPerMillisecond = waveProvider.WaveFormat.AverageBytesPerSecond / 1000;
               int chunkMilliseconds = 20;
               int chunkSize = bytesPerMillisecond * chunkMilliseconds;
               for (int offset = pcmOffset; offset < pcmOffset + pcmLength; offset += chunkSize)
               {
                   int bytesToCopy = Math.Min(chunkSize, pcmOffset + pcmLength - offset);
                   while ((waveProvider.BufferedBytes + bytesToCopy > waveProvider.BufferLength) && (VoiceTransmitCancel == false)) { Thread.Sleep(5); }
                   if (VoiceTransmitCancel == true)
                   {
                       waveProvider.ClearBuffer();
                       return;
                   }
                   waveProvider.AddSamples(pcmInputData, offset, bytesToCopy);
               }
           });
        }

        public static void ParseSbcFrame(byte[] data)
        {
            if (data.Length < 4)
            {
                Console.WriteLine("Frame too short to be valid.");
                return;
            }

            int index = 0;

            // Sync word
            if (data[index++] != 0x9C)
            {
                Console.WriteLine("Invalid SBC frame: Missing sync word (0x9C).");
                return;
            }

            byte headerByte = data[index++];

            // Sampling Frequency
            int samplingFreq = (headerByte >> 6) & 0x03;
            string[] frequencies = { "16 kHz", "32 kHz", "44.1 kHz", "48 kHz" };

            // Block Count
            int blocks = ((headerByte >> 4) & 0x03);
            int[] blockValues = { 4, 8, 12, 16 };

            // Channel Mode
            int channelMode = (headerByte >> 2) & 0x03;
            string[] channelModes = { "Mono", "Dual Channel", "Stereo", "Joint Stereo" };

            // Allocation Method
            int allocationMethod = (headerByte >> 1) & 0x01;
            string allocation = allocationMethod == 0 ? "Loudness" : "SNR";

            // Subbands
            int subbands = (headerByte & 0x01) == 0 ? 4 : 8;

            // Bitpool
            byte bitpool = data[index++];

            // CRC
            byte crc = data[index++];

            Console.WriteLine("SBC Frame Parsed:");
            Console.WriteLine($"  Sampling Frequency : {frequencies[samplingFreq]}");
            Console.WriteLine($"  Blocks        : {blockValues[blocks]}");
            Console.WriteLine($"  Channel Mode       : {channelModes[channelMode]}");
            Console.WriteLine($"  Allocation Method  : {allocation}");
            Console.WriteLine($"  Subbands      : {subbands}");
            Console.WriteLine($"  Bitpool         : {bitpool}");
            Console.WriteLine($"  CRC    : 0x{crc:X2}");
        }

        // Process 32k/16bit/Mono PCM for software modem decoding (AFSK/PSK/G3RUH)
        public void SoftModemPcmFrame(byte[] data, int offset, int len, string channelName)
        {
            lock (softModemLock)
            {
                if (!softModemInitialized || softModemDemodState == null) return;

                try
                {
                    int chan = 0;
                    int subchan = 0;

                    if (_softwareModemMode == SoftwareModemModeType.Afsk1200)
                {
                        if (softModemDemodulator == null) return;
                        for (int i = offset; i < offset + len - 1; i += 2)
                        {
                            short sample = (short)(data[i] | (data[i + 1] << 8));
                            softModemDemodulator.ProcessSample(chan, subchan, sample, softModemDemodState);
                        }
                }
                    else if (_softwareModemMode == SoftwareModemModeType.Psk2400 || _softwareModemMode == SoftwareModemModeType.Psk4800)
                    {
                        if (softModemPskDemodulator == null || softModemPskDemodState == null) return;
                        for (int i = offset; i < offset + len - 1; i += 2)
                        {
                            short sample = (short)(data[i] | (data[i + 1] << 8));
                            softModemPskDemodulator.ProcessSample(chan, subchan, sample, softModemPskDemodState);
                        }
                    }
                    else if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                    {
                        if (softModem9600State == null || softModemBridge == null) return;
                        for (int i = offset; i < offset + len - 1; i += 2)
                        {
                            short sample = (short)(data[i] | (data[i + 1] << 8));
                            HamLib.Demod9600.ProcessSample(chan, sample, 1, softModemDemodState, softModem9600State, softModemBridge);
                        }
                    }
                }
                catch (Exception ex) { Debug($"SoftModemPcmFrame error: {ex.Message}"); }
            }
        }
    }
}
