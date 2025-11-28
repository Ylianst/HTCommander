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

using HTCommander.radio;
using InTheHand.Net;
using InTheHand.Net.Bluetooth;
using InTheHand.Net.Sockets;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using static HTCommander.RadioAudio;

namespace HTCommander
{
    public class RadioAudio
    {
        private Radio parent;
        private const int ReceiveBufferSize = 1024;
        private BluetoothClient connectionClient;

        // LibSbc implementation
        private LibSbc.sbc_struct sbcContext;
        private LibSbc.sbc_struct sbcContext2;
        private bool isSbcInitialized = false;

        // C# SBC implementation
        private SbcDecoder sbcDecoder;
        private SbcEncoder sbcEncoder;
        private SbcFrame sbcDecoderFrame;
        private SbcFrame sbcEncoderFrame;

        // Flag to switch between implementations (true = use C# SBC, false = use LibSbc)
        public bool UseManagedSbc { get; set; } = true;

        private WasapiOut waveOut = null;
        private byte[] pcmFrame = new byte[16000];
        private bool running = false;
        private NetworkStream audioStream;
        public bool speechToText = false;
        private WhisperEngine speechToTextEngine = null;
        public string currentChannelName = "";
        public string voiceLanguage = "auto";
        public string voiceModel = null;
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

        // Software modem (AFSK decoder) fields
        public SoftwareModemModeType SoftwareModemMode { get { return _softwareModemMode; } }
        private SoftwareModemModeType _softwareModemMode = SoftwareModemModeType.Disabled;
        private HamLib.DemodAfsk softModemDemodulator = null;
        private HamLib.DemodPsk softModemPskDemodulator = null;
        private HamLib.PskDemodulatorState softModemPskDemodState = null;
        private HamLib.HdlcRec2 softModemHdlcReceiver = null;
        private HamLib.DemodulatorState softModemDemodState = null;
        private HamLib.AudioConfig softModemAudioConfig = null;
        private bool softModemInitialized = false;

        // FX.25 decoder fields
        private HamLib.Fx25Rec softModemFx25Receiver = null;
        private bool fx25Initialized = false;
        private HdlcFx25Bridge softModemBridge = null;

        // 9600 baud modem fields
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

        public delegate void DebugMessageEventHandler(string msg);
        public event DebugMessageEventHandler OnDebugMessage;
        public delegate void AudioStateChangedHandler(RadioAudio sender, bool enabled);
        public event AudioStateChangedHandler OnAudioStateChanged;
        public delegate void OnTextReadyHandler(string text, string channel, DateTime time, bool completed);
        public event OnTextReadyHandler onTextReady;
        public delegate void OnProcessingVoiceHandler(bool listening, bool processing);
        public event OnProcessingVoiceHandler onProcessingVoice;
        public delegate void OnSoftModemPacketDecodedHandler(TncDataFragment fragment);
        public event OnSoftModemPacketDecodedHandler OnSoftModemPacketDecoded;

        public RadioAudio(Radio radio) 
        { 
            parent = radio;
            //InitializeSoftModem(SoftwareModemModeType.Afsk1200);
            //InitializeSoftModem(SoftwareModemModeType.G3RUH9600);
            InitializeSoftModem(SoftwareModemModeType.Psk2400);
        }

        private void Debug(string msg) { if (OnDebugMessage != null) { OnDebugMessage(msg); } }

        public enum SoftwareModemModeType
        {
            Disabled,
            Afsk1200,
            Psk2400,
            Psk4800,
            G3RUH9600,
        }

        /// <summary>
        /// Initialize the software modem (AFSK decoder) for real-time packet decoding
        /// </summary>
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

        /// <summary>
        /// Event handler for frames decoded by the software modem
        /// </summary>
        private void SoftModemHdlcReceiver_FrameReceived(object sender, HamLib.FrameReceivedEventArgs e)
        {
            try
            {
                // Notify listeners that a packet was decoded
                if (OnSoftModemPacketDecoded != null)
                {
                    byte[] frameData = new byte[e.FrameLength];
                    Array.Copy(e.Frame, frameData, e.FrameLength);
                    TncDataFragment fragment = new TncDataFragment(true, 0, frameData, parent.HtStatus.curr_ch_id, parent.HtStatus.curr_region);
                    fragment.incoming = true;
                    fragment.channel_name = currentChannelName;
                    
                    // Set encoding type based on modem mode
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

                    // Determine frame type and corrections based on FEC type
                    if (e.CorrectionInfo != null)
                    {
                        if (e.CorrectionInfo.FecType == HamLib.FecType.Fx25)
                        {
                            // FX.25 frame with forward error correction
                            fragment.frame_type = TncDataFragment.FragmentFrameType.FX25;
                            
                            // For FX.25, use the number of RS symbols corrected
                            // Each symbol is 8 bits, so this represents bytes corrected
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
                            // Regular AX.25 frame (possibly with bit-flip corrections)
                            fragment.frame_type = TncDataFragment.FragmentFrameType.AX25;
                            
                            // For regular HDLC, use number of bits corrected
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

                    OnSoftModemPacketDecoded(fragment);
                }
            }
            catch (Exception ex)
            {
                Debug($"Error processing decoded frame: {ex.Message}");
            }
        }

        /// <summary>
        /// Reset the software modem decoder state (call when radio loses signal)
        /// </summary>
        public void ResetSoftModem()
        {
            if (!softModemInitialized) return;

            try
            {
                // Reinitialize the appropriate demodulator to reset its state
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

                Debug("Software modem reset successfully");
            }
            catch (Exception ex)
            {
                Debug($"Error resetting software modem: {ex.Message}");
            }
        }

        /// <summary>
        /// Bridge class that feeds bits to both HDLC and FX.25 receivers
        /// </summary>
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
                // Feed bit to HDLC receiver for standard AX.25 decoding
                _hdlcReceiver.RecBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);

                // Also feed to FX.25 receiver for correlation tag detection
                // FX.25 needs the decoded bit (after NRZI), not raw bit
                // The HDLC receiver will do NRZI decoding, but we need to do it here too for FX.25
                // For simplicity, FX.25 will do its own NRZI internally via the bit stream
                _fx25Receiver.RecBit(chan, subchan, slice, raw);
            }

            public void DcdChange(int chan, int subchan, int slice, bool dcdOn)
            {
                // Forward DCD change to HDLC receiver
                _hdlcReceiver.DcdChange(chan, subchan, slice, dcdOn);
            }
        }

        /// <summary>
        /// Wrapper for MultiModem to process FX.25 frames from Fx25Rec
        /// </summary>
        private class Fx25MultiModemWrapper : HamLib.MultiModem
        {
            private RadioAudio _parent;

            public Fx25MultiModemWrapper(RadioAudio parent)
            {
                _parent = parent;
                
                // Subscribe to the PacketReady event
                this.PacketReady += OnPacketReady;
            }

            private void OnPacketReady(object sender, HamLib.PacketReadyEventArgs e)
            {
                // This is called by Fx25Rec when a valid FX.25 frame is decoded
                try
                {
                    if (_parent.OnSoftModemPacketDecoded != null && e.Packet != null)
                    {
                        // Get the frame data from the packet
                        byte[] frameData = e.Packet.GetInfo(out int frameLen);
                        if (frameData == null || frameLen == 0)
                        {
                            // Try to pack the whole packet if no info field
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

                        // For FX.25, use the number of RS symbols corrected
                        if (e.CorrectionInfo != null && e.CorrectionInfo.RsSymbolsCorrected >= 0)
                        {
                            fragment.corrections = e.CorrectionInfo.RsSymbolsCorrected;
                        }
                        else
                        {
                            fragment.corrections = 0;
                        }

                        _parent.OnSoftModemPacketDecoded(fragment);
                    }
                }
                catch (Exception ex)
                {
                    _parent.Debug($"Error processing FX.25 decoded frame: {ex.Message}");
                }
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
            if (running == false) return;
            running = false;
            try { if (audioStream != null) { audioStream.Dispose(); } } catch (Exception) { }
            if (OnAudioStateChanged != null) { OnAudioStateChanged(this, false); }
        }

        public void Start(string mac)
        {
            if (running) return;
            Task.Run(() => { StartAsync(mac); });
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

        private async void StartAsync(string mac)
        {
            running = true;
            int maxVoiceDecodeTime = 0;
            Guid rfcommServiceUuid = BluetoothService.GenericAudio;
            BluetoothAddress address = BluetoothAddress.Parse(mac);
            BluetoothEndPoint remoteEndPoint = new BluetoothEndPoint(address, rfcommServiceUuid, 2);
            connectionClient = new BluetoothClient();
            connectionClient.Client.SendBufferSize = 1024; // Limit the outgoing buffer.

            // Connect to the remote endpoint asynchronously
            Debug("Attempting to connect...");
            try
            {
                connectionClient.Connect(remoteEndPoint);
            }
            catch (Exception ex)
            {
                Debug($"Connection error: {ex.Message}");
                connectionClient.Dispose();
                connectionClient = null;
                running = false;
                return;
            }
            Debug("Successfully connected to the RFCOMM channel.");

            try
            {
                if (UseManagedSbc)
                {
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

                    Debug("Using C# SBC implementation");
                }
                else
                {
                    // Initialize LibSbc implementation
                    sbcContext2 = new LibSbc.sbc_struct();
                    int initResult = LibSbc.sbc_init(ref sbcContext2, 0);
                    sbcContext2.frequency = LibSbc.SBC_FREQ_32000;
                    sbcContext2.blocks = LibSbc.SBC_BLK_16;
                    sbcContext2.endian = LibSbc.SBC_LE;
                    sbcContext2.mode = LibSbc.SBC_MODE_MONO;
                    sbcContext2.allocation = LibSbc.SBC_AM_LOUDNESS;
                    sbcContext2.subbands = LibSbc.SBC_SB_8;
                    sbcContext2.bitpool = 18;
                    if (initResult != 0) { Debug($"Error initializing SBC (A2DP): {initResult}"); running = false; return; }

                    sbcContext = new LibSbc.sbc_struct();
                    initResult = LibSbc.sbc_init(ref sbcContext, 0);
                    if (initResult != 0) { Debug($"Error initializing SBC (A2DP): {initResult}"); running = false; return; }
                    isSbcInitialized = true;

                    // Get expected frame sizes
                    pcmInputSizePerFrame = (int)LibSbc.sbc_get_codesize(ref sbcContext).ToUInt32();
                    sbcOutputBuffer = new byte[1024];

                    Debug("Using LibSbc native implementation");
                }

                // If the output audio device is not set, use the default one
                if (waveOut == null) { SetOutputDevice(""); }

                MemoryStream accumulator = new MemoryStream();
                using (NetworkStream stream = connectionClient.GetStream())
                {
                    audioStream = stream;
                    Debug("Ready to receive data.");
                    if (OnAudioStateChanged != null) { OnAudioStateChanged(this, true); }
                    byte[] receiveBuffer = new byte[ReceiveBufferSize];

                    while (running && connectionClient.Connected)
                    {
                        // Receive data asynchronously
                        int bytesRead = await stream.ReadAsync(receiveBuffer, 0, receiveBuffer.Length);
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
                                        if (speechToText && (speechToTextEngine == null))
                                        {
                                            speechToTextEngine = new WhisperEngine(voiceModel, voiceLanguage);
                                            speechToTextEngine.OnDebugMessage += SpeechToTextEngine_OnDebugMessage;
                                            speechToTextEngine.onProcessingVoice += SpeechToTextEngine_onProcessingVoice;
                                            speechToTextEngine.onTextReady += SpeechToTextEngine_onTextReady;
                                            speechToTextEngine.StartVoiceSegment();
                                            maxVoiceDecodeTime = 0;
                                            if (onProcessingVoice != null) { onProcessingVoice(true, false); }
                                        }
                                        if (!speechToText && (speechToTextEngine != null))
                                        {
                                            speechToTextEngine.ResetVoiceSegment();
                                            speechToTextEngine.OnDebugMessage -= SpeechToTextEngine_OnDebugMessage;
                                            speechToTextEngine.onProcessingVoice -= SpeechToTextEngine_onProcessingVoice;
                                            speechToTextEngine.onTextReady -= SpeechToTextEngine_onTextReady;
                                            speechToTextEngine.Dispose();
                                            speechToTextEngine = null;
                                            if (onProcessingVoice != null) { onProcessingVoice(false, false); }
                                        }
                                        DecodeSbcFrame(frame, 1, uframeLength - 1);
                                        maxVoiceDecodeTime += (uframeLength - 1);
                                        if ((speechToTextEngine != null) && (maxVoiceDecodeTime > 19200000)) // 5 minutes (32k * 2 * 60 & 5)
                                        {
                                            speechToTextEngine.ResetVoiceSegment();
                                            maxVoiceDecodeTime = 0;
                                        }
                                        break;
                                    case 0x01: // Audio end
                                        //Debug("Command: 0x01, Audio End, Size: " + uframeLength);// + ", HEX: " + BytesToHex(uframe, 0, uframe.Length));
                                        if (speechToTextEngine != null)
                                        {
                                            speechToTextEngine.ResetVoiceSegment();
                                            maxVoiceDecodeTime = 0;
                                        }
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
            }
            catch (Exception ex)
            {
                if (running) { Debug($"Connection error: {ex.Message}"); }
            }
            finally
            {
                running = false;

                if (speechToTextEngine != null)
                {
                    speechToTextEngine.ResetVoiceSegment();
                    speechToTextEngine.OnDebugMessage -= SpeechToTextEngine_OnDebugMessage;
                    speechToTextEngine.onProcessingVoice -= SpeechToTextEngine_onProcessingVoice;
                    speechToTextEngine.onTextReady -= SpeechToTextEngine_onTextReady;
                    speechToTextEngine.Dispose();
                    speechToTextEngine = null;
                }

                if (speechToTextEngine != null) { speechToTextEngine.Dispose(); speechToTextEngine = null; }
                if (OnAudioStateChanged != null) { OnAudioStateChanged(this, false); }
                connectionClient?.Close();
                waveOut?.Stop();
                waveOut?.Dispose();
                waveOut = null;
                audioStream = null;

                // Cleanup SBC resources
                if (UseManagedSbc)
                {
                    // C# SBC cleanup (managed objects, no special cleanup needed)
                    sbcDecoder = null;
                    sbcEncoder = null;
                }
                else
                {
                    // LibSbc cleanup
                    if (isSbcInitialized)
                    {
                        LibSbc.sbc_finish(ref sbcContext);
                        LibSbc.sbc_finish(ref sbcContext2);
                        isSbcInitialized = false;
                    }
                }

                Debug("Bluetooth connection closed.");
            }
        }

        private void SpeechToTextEngine_OnDebugMessage(string msg)
        {
            Debug("Whisper: " + msg);
        }

        private void SpeechToTextEngine_onTextReady(string text, string channel, DateTime time, bool completed)
        {
            if (onTextReady != null) { onTextReady(text, channel, time, completed); }
        }
        private void SpeechToTextEngine_onProcessingVoice(bool processing)
        {
            if (onProcessingVoice != null) { onProcessingVoice(speechToTextEngine != null, processing); }
        }

        private int DecodeSbcFrame(byte[] sbcFrame, int start, int length)
        {
            if (sbcFrame == null || sbcFrame.Length == 0) return 1;

            if (UseManagedSbc)
            {
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
                            if (speechToTextEngine != null)
                            {
                                try { speechToTextEngine.ProcessAudioChunk(pcmFrame, 0, totalWritten, currentChannelName); }
                                catch (Exception ex) { Debug("ProcessAudioChunk Error: " + ex.ToString()); }
                            }
                            parent.GotAudioData(pcmFrame, 0, totalWritten, currentChannelName, false);
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
            else
            {
                // Use LibSbc native decoder
                // Pin the input SBC frame in memory
                GCHandle sbcHandle = GCHandle.Alloc(sbcFrame, GCHandleType.Pinned);
                IntPtr sbcPtr = sbcHandle.AddrOfPinnedObject() + start;
                UIntPtr sbcLen = (UIntPtr)length;

                // Parse the SBC frame to get its parameters
                IntPtr parsedPtr = LibSbc.sbc_parse(ref sbcContext, sbcPtr, sbcLen);
                if (parsedPtr == IntPtr.Zero) { sbcHandle.Free(); return 2; } // Error parsing SBC frame.

                // Allocate a buffer for the decoded PCM data
                GCHandle pcmHandle = GCHandle.Alloc(pcmFrame, GCHandleType.Pinned);
                IntPtr decodeResult, pcmPtr = pcmHandle.AddrOfPinnedObject();
                UIntPtr written, pcmLen = (UIntPtr)pcmFrame.Length;
                int totalWritten = 0;

                // Decode the SBC frame
                while ((decodeResult = LibSbc.sbc_decode(ref sbcContext, sbcPtr, sbcLen, pcmPtr, pcmLen, out written)).ToInt64() > 0)
                {
                    totalWritten += (int)written;
                    sbcPtr += (int)decodeResult;
                    sbcLen -= (int)decodeResult;
                    pcmPtr += (int)written;
                    pcmLen -= (int)written;
                }

                if (parent.IsOnMuteChannel() == false)
                {
                    // Make use of the PCM data
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
                    if (speechToTextEngine != null)
                    {
                        try { speechToTextEngine.ProcessAudioChunk(pcmFrame, 0, totalWritten, currentChannelName); }
                        catch (Exception ex) { Debug("ProcessAudioChunk Error: " + ex.ToString()); }
                    }
                    parent.GotAudioData(pcmFrame, 0, totalWritten, currentChannelName, false);
                }

                // We need to send the audio into the AFPK1200, PFK2400, PFK4800 or 9600 software modem for decoding
                SoftModemPcmFrame(pcmFrame, 0, totalWritten, currentChannelName);

                // Clean up
                pcmHandle.Free();
                sbcHandle.Free();
                return 0;
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

            if (UseManagedSbc)
            {
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
            else
            {
                // Use LibSbc native encoder
                // Pin the PCM input buffer segment
                GCHandle pcmHandle = GCHandle.Alloc(pcmInputData, GCHandleType.Pinned);
                IntPtr pcmPtr = pcmHandle.AddrOfPinnedObject() + pcmOffset;
                UIntPtr pcmLen = (UIntPtr)pcmLength;

                // Pin the reusable SBC output buffer
                GCHandle sbcHandle = GCHandle.Alloc(sbcOutputBuffer, GCHandleType.Pinned);
                IntPtr sbcPtr = sbcHandle.AddrOfPinnedObject();
                UIntPtr sbcBufLen = (UIntPtr)(sbcOutputBuffer.Length); // Max capacity

                int TotalToConsume = pcmLength;
                int TotalGenerated = 0;

                try
                {
                    while ((TotalToConsume >= pcmInputSizePerFrame) && (TotalGenerated < 300))
                    {
                        // Call the native SBC encode function
                        int bytesConsumedThisRound = (int)LibSbc.sbc_encode(ref sbcContext2, pcmPtr, pcmLen, sbcPtr, sbcBufLen, out IntPtr sbcBytesWritten).ToInt64();
                        if (bytesConsumedThisRound < 0) { return false; }
                        int sbcWrittenBytes = (int)sbcBytesWritten.ToInt64();

                        TotalToConsume -= bytesConsumedThisRound;
                        TotalGenerated += sbcWrittenBytes;
                        pcmPtr += bytesConsumedThisRound;
                        pcmLen -= bytesConsumedThisRound;
                        sbcPtr += sbcWrittenBytes;
                        sbcBufLen -= sbcWrittenBytes;
                        bytesConsumed += bytesConsumedThisRound;
                    }

                    // If bytes were written to the SBC buffer, copy them to the output array
                    if (TotalGenerated > 0)
                    {
                        encodedSbcFrame = new byte[TotalGenerated];
                        Array.Copy(sbcOutputBuffer, 0, encodedSbcFrame, 0, TotalGenerated);
                    }

                    return true;
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"Exception during SBC encoding: {ex.Message}");
                    return false;
                }
                finally
                {
                    // Unpin the memory handles
                    if (sbcHandle.IsAllocated) sbcHandle.Free();
                    if (pcmHandle.IsAllocated) pcmHandle.Free();
                }
            }
        }

        //private bool VoiceTransmit = false;
        private bool VoiceTransmitCancel = false;
        public delegate void VoiceTransmitStateHandler(RadioAudio sender, bool transmitting);
        public event VoiceTransmitStateHandler OnVoiceTransmitStateChanged;

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

        /// <summary>
        /// Transmit a packet (AX.25 or FX.25)
        /// If the radio is busy, the packet is queued for transmission
        /// </summary>
        /// <param name="fragment">The packet data to transmit</param>
        public void TransmitPacket(TncDataFragment fragment)
        {
            if (fragment == null || fragment.data == null || fragment.data.Length == 0)
            {
                Debug("TransmitPacket: Invalid fragment");
                return;
            }

            // Queue the packet
            packetQueue.Enqueue(fragment);

            // Start the packet transmitter if not already running
            if (!isTransmittingPacket)
            {
                StartPacketTransmitter();
            }
        }

        /// <summary>
        /// Initialize packet transmission components
        /// </summary>
        private void InitializePacketTransmitter()
        {
            if (packetAudioConfig != null)
                return; // Already initialized

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

        /// <summary>
        /// Start the packet transmitter background task
        /// </summary>
        private void StartPacketTransmitter()
        {
            if (isTransmittingPacket || packetTransmitTask != null)
                return;

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
                        // Wait a bit for more packets
                        await Task.Delay(50);

                        // If still no packets, exit
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

        /// <summary>
        /// Transmit a single packet
        /// </summary>
        private async Task TransmitPacketAsync(TncDataFragment fragment)
        {
            WaveFileWriter debugWavWriter = null;
            try
            {
                // Initialize if needed
                InitializePacketTransmitter();

                if (packetAudioConfig == null || packetGenTone == null || packetAudioBuffer == null)
                {
                    Debug("Packet transmitter not initialized");
                    return;
                }

                int chan = 0;

                // Clear audio buffer
                packetAudioBuffer.ClearAll();

                // For G3RUH 9600 baud, add 0.5 seconds of silence before data
                if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                {
                    int sampleRate = packetAudioConfig.Devices[0].SamplesPerSec;
                    int silenceSamples = sampleRate / 2; // 0.5 seconds
                    for (int i = 0; i < silenceSamples; i++)
                    {
                        packetAudioBuffer.Put(0, 0); // Channel 0, amplitude 0 (silence)
                    }
                }

                // Generate preamble flags (txdelay)
                int txdelayFlags = packetAudioConfig.Channels[chan].Txdelay;
                packetHdlcSend.SendFlags(chan, txdelayFlags, false, null);

                // Determine if we should use FX.25 encoding
                bool useFx25 = (fragment.frame_type == TncDataFragment.FragmentFrameType.FX25);

                if (useFx25)
                {
                    // Use FX.25 encoding with forward error correction
                    int fxMode = 32; // FX.25 mode with 4 bytes of FEC (16, 32 and 64 are valid)
                    packetFx25Send.SendFrame(chan, fragment.data, fragment.data.Length, fxMode);
                    Debug($"Transmitting FX.25 packet ({fragment.data.Length} bytes with FEC)");
                }
                else
                {
                    // Use standard AX.25 HDLC encoding
                    packetHdlcSend.SendFrame(chan, fragment.data, fragment.data.Length, false);
                    Debug($"Transmitting AX.25 packet ({fragment.data.Length} bytes)");
                }

                // Generate postamble flags (txtail)
                int txtailFlags = packetAudioConfig.Channels[chan].Txtail;
                packetHdlcSend.SendFlags(chan, txtailFlags, true, (device) => { });

                // For G3RUH 9600 baud, add 0.5 seconds of silence after data
                if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                {
                    int sampleRate = packetAudioConfig.Devices[0].SamplesPerSec;
                    int silenceSamples = sampleRate / 2; // 0.5 seconds
                    for (int i = 0; i < silenceSamples; i++)
                    {
                        packetAudioBuffer.Put(0, 0); // Channel 0, amplitude 0 (silence)
                    }
                }

                // Get the generated audio samples
                short[] samples = packetAudioBuffer.GetAndClear(0);
                if (samples != null && samples.Length > 0)
                {
                    // Convert 16-bit samples to byte array
                    byte[] pcmData = new byte[samples.Length * 2];
                    Buffer.BlockCopy(samples, 0, pcmData, 0, pcmData.Length);
                    TransmitVoice(pcmData, 0, pcmData.Length, false);
                    Debug($"Transmitted packet: {samples.Length} samples, {pcmData.Length} bytes PCM");
                }
            }
            catch (Exception ex)
            {
                Debug($"Error transmitting packet: {ex.Message}");
            }
            finally
            {
                if (debugWavWriter != null)
                {
                    try { debugWavWriter.Dispose(); }
                    catch (Exception) { }
                }
            }
        }

        /// <summary>
        /// Transmit packet audio data through the radio
        /// </summary>
        /// <param name="pcmData">PCM audio data to transmit</param>
        /// <param name="playLocally">If true, plays the audio through the local audio device</param>
        private async Task TransmitPacketAudioAsync(byte[] pcmData, bool playLocally)
        {
            if (audioStream == null || !running)
            {
                Debug("Cannot transmit packet: radio not connected");
                return;
            }

            try
            {
                // Encode and send the PCM data in chunks
                int offset = 0;
                int length = pcmData.Length;

                while (offset < length)
                {
                    int chunkSize = Math.Min(pcmInputSizePerFrame, length - offset);
                    
                    // Need at least one full frame to encode
                    if (chunkSize < pcmInputSizePerFrame && offset + chunkSize < length)
                    {
                        // Wait for more data or pad
                        chunkSize = pcmInputSizePerFrame;
                    }

                    if (chunkSize >= pcmInputSizePerFrame)
                    {
                        byte[] encodedSbcFrame;
                        int bytesConsumed;
                        
                        if (EncodeSbcFrame(pcmData, offset, chunkSize, out encodedSbcFrame, out bytesConsumed))
                        {
                            // Send the audio frame to the radio
                            byte[] escaped = EscapeBytes(0, encodedSbcFrame, encodedSbcFrame.Length);
                            await audioStream.WriteAsync(escaped, 0, escaped.Length);
                            await audioStream.FlushAsync();
                            
                            // Play locally if requested
                            if (playLocally && waveProvider != null)
                            {
                                try
                                {
                                    // Play the transmitted PCM audio through the local audio device
                                    PlayPcmBufferAsync(pcmData, offset, bytesConsumed);
                                }
                                catch (Exception ex)
                                {
                                    Debug($"Error playing packet audio locally: {ex.Message}");
                                }
                            }

                            offset += bytesConsumed;
                        }
                        else
                        {
                            Debug("Failed to encode SBC frame for packet");
                            break;
                        }
                    }
                    else
                    {
                        // End of data
                        break;
                    }

                    // Small delay to avoid overwhelming the radio
                    await Task.Delay(10);
                }
            }
            catch (Exception ex)
            {
                Debug($"Error transmitting packet audio: {ex.Message}");
            }
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
                if (OnVoiceTransmitStateChanged != null) { OnVoiceTransmitStateChanged(this, true); }
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
                    await audioStream.WriteAsync(endAudio, 0, endAudio.Length);
                    await audioStream.FlushAsync();
                }
                finally
                {
                    if (OnVoiceTransmitStateChanged != null) { OnVoiceTransmitStateChanged(this, false); }
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
                await audioStream.WriteAsync(escaped, 0, escaped.Length);
                await audioStream.FlushAsync();

                // Do extra processing if needed
                if (recording != null)
                {
                    try { recording.Write(pcmData, pcmOffset, bytesConsumed); } catch (Exception ex) { Debug("Recording Write error: " + ex.Message); }
                }
                if (PlayInputBack)
                {
                    try { PlayPcmBufferAsync(pcmData, pcmOffset, bytesConsumed); } catch (Exception ex) { Debug("PlayPcmBufferAsync error: " + ex.Message); }
                }
                try { parent.GotAudioData(pcmData, pcmOffset, bytesConsumed, currentChannelName, true); } catch (Exception ex) { Debug("GotAudioData error: " + ex.Message); }

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

        /// <summary>
        /// Handle 32k, 16bit, Mono PCM frames for software modem decoding
        /// Processes PCM audio samples through the AFSK or G3RUH 9600 decoder for real-time packet detection
        /// Includes support for both standard AX.25 and FX.25 frames
        /// </summary>
        /// <param name="data">PCM audio data buffer (16-bit samples)</param>
        /// <param name="offset">Starting offset in the buffer</param>
        /// <param name="len">Length of data to process</param>
        /// <param name="channelName">Name of the current channel</param>
        public void SoftModemPcmFrame(byte[] data, int offset, int len, string channelName)
        {
            if (!softModemInitialized || softModemDemodState == null)
            {
                return;
            }

            try
            {
                // Convert byte array to 16-bit samples and feed to demodulator
                // PCM data is 16-bit signed samples (little-endian)
                int chan = 0;      // Channel number
                int subchan = 0;   // Subchannel number

                // Process based on modem type
                if (_softwareModemMode == SoftwareModemModeType.Afsk1200)
                {
                    if (softModemDemodulator == null) return;

                    // Process each 16-bit sample through AFSK demodulator
                    for (int i = offset; i < offset + len - 1; i += 2)
                    {
                        // Extract 16-bit sample (little-endian)
                        short sample = (short)(data[i] | (data[i + 1] << 8));

                        // Feed sample to AFSK demodulator
                        softModemDemodulator.ProcessSample(chan, subchan, sample, softModemDemodState);
                    }
                }
                else if (_softwareModemMode == SoftwareModemModeType.Psk2400 || _softwareModemMode == SoftwareModemModeType.Psk4800)
                {
                    if (softModemPskDemodulator == null || softModemPskDemodState == null) return;

                    // Process each 16-bit sample through PSK demodulator
                    for (int i = offset; i < offset + len - 1; i += 2)
                    {
                        // Extract 16-bit sample (little-endian)
                        short sample = (short)(data[i] | (data[i + 1] << 8));

                        // Feed sample to PSK demodulator
                        softModemPskDemodulator.ProcessSample(chan, subchan, sample, softModemPskDemodState);
                    }
                }
                else if (_softwareModemMode == SoftwareModemModeType.G3RUH9600)
                {
                    if (softModem9600State == null || softModemBridge == null) return;

                    // Process each 16-bit sample through G3RUH 9600 baud demodulator
                    for (int i = offset; i < offset + len - 1; i += 2)
                    {
                        // Extract 16-bit sample (little-endian)
                        short sample = (short)(data[i] | (data[i + 1] << 8));

                        // Feed sample to G3RUH 9600 baud demodulator
                        // Parameters: channel, sample, upsample factor, demod state, 9600 state, HDLC receiver
                        HamLib.Demod9600.ProcessSample(
                            chan,
                            sample,
                            1,  // Upsample factor (1 = no upsampling)
                            softModemDemodState,
                            softModem9600State,
                            softModemBridge
                        );
                    }
                }

                // Note: FX.25 bit processing is handled internally by the demodulator
                // The demodulator feeds decoded bits to both the HDLC receiver and FX.25 receiver
            }
            catch (Exception ex)
            {
                Debug($"Error in SoftModemPcmFrame: {ex.Message}");
            }
        }
    }
}
