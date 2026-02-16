/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using aprsparser;
using HTCommander.radio;
using HTCommander.SSTV;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Speech.AudioFormat;
using System.Speech.Synthesis;
using System.Text.Json;

namespace HTCommander
{
    /// <summary>
    /// Encoding type for voice text entries.
    /// </summary>
    public enum VoiceTextEncodingType
    {
        Voice,
        Morse,
        VoiceClip,
        AX25,
        BSS,
        Recording,
        Picture,
        APRS
    }

    /// <summary>
    /// Represents a voice text entry (received or transmitted).
    /// </summary>
    public class DecodedTextEntry
    {
        public string Text { get; set; }
        public string Channel { get; set; }
        public DateTime Time { get; set; }
        /// <summary>
        /// True if this entry was received (decoded), false if it was sent (transmitted).
        /// </summary>
        public bool IsReceived { get; set; } = true;
        /// <summary>
        /// The encoding type used for this entry (Voice, Morse, etc.).
        /// </summary>
        public VoiceTextEncodingType Encoding { get; set; } = VoiceTextEncodingType.Voice;
        /// <summary>
        /// Source callsign (for BSS packets).
        /// </summary>
        public string Source { get; set; }
        /// <summary>
        /// Destination callsign (for BSS packets, may be null for broadcast).
        /// </summary>
        public string Destination { get; set; }
        /// <summary>
        /// Latitude coordinate if location data is available.
        /// </summary>
        public double Latitude { get; set; } = 0;
        /// <summary>
        /// Longitude coordinate if location data is available.
        /// </summary>
        public double Longitude { get; set; } = 0;
        /// <summary>
        /// Filename for picture entries (SSTV images) and recording entries.
        /// </summary>
        public string Filename { get; set; }
        /// <summary>
        /// Duration in seconds (for recording entries).
        /// </summary>
        public int Duration { get; set; } = 0;
    }

    /// <summary>
    /// Voice Handler - Listens to audio data from radios and converts speech to text using Whisper.
    /// This is a Data Broker handler that can be enabled/disabled and configured to listen to specific radios.
    /// </summary>
    public class VoiceHandler : IDisposable
    {
        private readonly DataBrokerClient broker;
        private bool _disposed = false;
        private bool _enabled = false;
        private int _targetDeviceId = -1; // -1 means disabled, specific device ID when enabled
        private string _voiceLanguage = "auto";
        private string _voiceModel = null;
        private WhisperEngine _speechToTextEngine = null;
        private string _currentChannelName = "";
        private int _maxVoiceDecodeTime = 0;
        private const int MaxVoiceDecodeTimeLimit = (32000 * 2 * 60 * 1); // 1 minute (32k * 2 * 60 * 1)

        // Decoded text history
        private readonly List<DecodedTextEntry> _decodedTextHistory = new List<DecodedTextEntry>();
        private readonly object _historyLock = new object();
        private DecodedTextEntry _currentEntry = null;
        private const int MaxHistorySize = 1000;

        // File persistence
        private const string VoiceTextFileName = "voicetext.json";
        private readonly string _appDataPath;

        // Flag to track if voice text history has been loaded
        private bool _voiceTextHistoryLoaded = false;

        // Text-to-speech fields
        private SpeechSynthesizer _synthesizer = null;
        private MemoryStream _ttsAudioStream = null;
        private bool _ttsAvailable = false;
        private string _currentVoice = "Microsoft Zira Desktop";
        private int _ttsPendingDeviceId = -1;
        private readonly object _ttsLock = new object();

        // Speech-to-text enabled setting (saved as device 0 setting)
        private bool _speechToTextEnabled = true;

        // SSTV auto-decode fields
        private SstvMonitor _sstvMonitor = null;
        private readonly object _sstvLock = new object();
        private readonly string _sstvImagesPath;
        private bool _sstvDecoding = false;
        private DecodedTextEntry _currentSstvEntry = null;
        private DateTime _sstvStartTime;

        // Recording fields
        private bool _recordingEnabled = false;
        private readonly string _recordingsPath;
        private NAudio.Wave.WaveFileWriter _currentRecordingWriter = null;
        private DateTime _currentRecordingStartTime;
        private string _currentRecordingChannel = "";
        private string _currentRecordingFilename = "";
        private readonly object _recordingLock = new object();

        /// <summary>
        /// Initializes the VoiceHandler and subscribes to Data Broker events.
        /// </summary>
        public VoiceHandler()
        {
            // Set up app data path for persistence
            _appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HTCommander");
            if (!Directory.Exists(_appDataPath))
            {
                Directory.CreateDirectory(_appDataPath);
            }

            // Set up recordings folder
            _recordingsPath = Path.Combine(_appDataPath, "Recordings");
            if (!Directory.Exists(_recordingsPath))
            {
                Directory.CreateDirectory(_recordingsPath);
            }

            // Set up SSTV images folder
            _sstvImagesPath = Path.Combine(_appDataPath, "SSTV");
            if (!Directory.Exists(_sstvImagesPath))
            {
                Directory.CreateDirectory(_sstvImagesPath);
            }

            broker = new DataBrokerClient();

            // Load saved voice text history from file
            LoadVoiceTextHistory();

            // Subscribe to VoiceHandlerEnable command (from device 1 - global voice handler commands)
            broker.Subscribe(1, "VoiceHandlerEnable", OnVoiceHandlerEnable);

            // Subscribe to VoiceHandlerDisable command
            broker.Subscribe(1, "VoiceHandlerDisable", OnVoiceHandlerDisable);

            // Subscribe to AudioDataAvailable from all devices (we'll filter by target device)
            broker.Subscribe(DataBroker.AllDevices, "AudioDataAvailable", OnAudioDataAvailable);

            // Subscribe to radio State changes from all devices to detect disconnection
            broker.Subscribe(DataBroker.AllDevices, "State", OnRadioStateChanged);

            // Subscribe to AudioState changes from all devices to detect when audio is disabled
            broker.Subscribe(DataBroker.AllDevices, "AudioState", OnAudioStateChanged);

            // Subscribe to AudioDataStart from all devices to start recording when audio begins
            broker.Subscribe(DataBroker.AllDevices, "AudioDataStart", OnAudioDataStart);

            // Subscribe to AudioDataEnd from all devices to flush speech-to-text on audio segment end
            broker.Subscribe(DataBroker.AllDevices, "AudioDataEnd", OnAudioDataEnd);

            // Subscribe to recording enable/disable commands
            broker.Subscribe(1, "RecordingEnable", OnRecordingEnable);
            broker.Subscribe(1, "RecordingDisable", OnRecordingDisable);

            // Subscribe to ClearVoiceText command
            broker.Subscribe(1, "ClearVoiceText", OnClearVoiceText);

            // Subscribe to Speak command from all devices for text-to-speech transmission
            // If received on device 1, use the currently voice-enabled radio (_targetDeviceId)
            // If received on device 100+, use that device ID directly
            broker.Subscribe(DataBroker.AllDevices, "Speak", OnSpeak);

            // Subscribe to Morse command from all devices for morse code transmission
            // Similar to Speak: device 1 uses voice-enabled radio, device 100+ uses that device directly
            broker.Subscribe(DataBroker.AllDevices, "Morse", OnMorse);

            // Subscribe to VoiceClipTransmitted command from all devices
            // Records when a voice clip is transmitted over a radio
            broker.Subscribe(DataBroker.AllDevices, "VoiceClipTransmitted", OnVoiceClipTransmitted);

            // Subscribe to PictureTransmitted command from all devices
            // Records when an SSTV picture is transmitted over a radio
            broker.Subscribe(DataBroker.AllDevices, "PictureTransmitted", OnPictureTransmitted);

            // Subscribe to Voice setting changes (device 0 stores global settings)
            broker.Subscribe(0, "Voice", OnVoiceChanged);

            // Subscribe to SpeechToTextEnabled setting changes (device 0 stores global settings)
            broker.Subscribe(0, "SpeechToTextEnabled", OnSpeechToTextEnabledChanged);

            // Load the initial SpeechToTextEnabled setting
            _speechToTextEnabled = DataBroker.GetValue<bool>(0, "SpeechToTextEnabled", true);

            // Subscribe to UniqueDataFrame events from all devices for AX.25 packet logging
            broker.Subscribe(DataBroker.AllDevices, "UniqueDataFrame", OnUniqueDataFrame);

            // Subscribe to Chat command from all devices for BSS chat message transmission
            // Similar to Speak: device 1 uses voice-enabled radio, device 100+ uses that device directly
            broker.Subscribe(DataBroker.AllDevices, "Chat", OnChat);

            // Initialize text-to-speech synthesizer
            InitializeTextToSpeech();

            // Load the initial RecordingState setting from registry
            _recordingEnabled = DataBroker.GetValue<bool>(0, "RecordingState", false);

            // Dispatch initial state (not monitoring any radio)
            DispatchVoiceHandlerState();

            // Dispatch initial recording state
            DispatchRecordingState();

            // Dispatch initial empty history
            DispatchDecodedTextHistory();

            broker.LogInfo("[VoiceHandler] Voice Handler initialized");
        }

        /// <summary>
        /// Initializes the text-to-speech synthesizer.
        /// </summary>
        private void InitializeTextToSpeech()
        {
            try
            {
                _ttsAudioStream = new MemoryStream();
                _synthesizer = new SpeechSynthesizer();
                // Output to memory stream at 32kHz, 16-bit, mono (matches radio audio format)
                _synthesizer.SetOutputToAudioStream(_ttsAudioStream, new SpeechAudioFormatInfo(32000, AudioBitsPerSample.Sixteen, AudioChannel.Mono));
                
                // Load the voice setting from DataBroker
                _currentVoice = DataBroker.GetValue<string>(0, "Voice", "Microsoft Zira Desktop");
                try { _synthesizer.SelectVoice(_currentVoice); } catch (Exception) { }
                
                _synthesizer.Rate = 0; // Normal speed
                _synthesizer.Volume = 100; // Maximum volume
                _synthesizer.SpeakCompleted += Synthesizer_SpeakCompleted;
                _ttsAvailable = true;
                
                broker.LogInfo($"[VoiceHandler] Text-to-speech initialized with voice: {_currentVoice}");
            }
            catch (System.Runtime.InteropServices.COMException ex)
            {
                broker.LogError($"[VoiceHandler] Text-to-Speech not available: {ex.Message}");
                _ttsAvailable = false;
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Failed to initialize Text-to-Speech: {ex.Message}");
                _ttsAvailable = false;
            }
        }

        /// <summary>
        /// Handles incoming UniqueDataFrame events and processes unassigned AX.25 packets.
        /// Creates DecodedTextEntry for packets with no usage, not on APRS channel, and of type U_FRAME_UI or U_FRAME.
        /// </summary>
        private void OnUniqueDataFrame(int deviceId, string name, object data)
        {
            if (_disposed) return;
            if (!(data is TncDataFragment frame)) return;

            // Only process frames with null or empty usage (unassigned packets)
            if (!string.IsNullOrEmpty(frame.usage)) return;

            // Skip frames from the APRS channel
            if (frame.channel_name == "APRS") return;

            BSSPacket bssPacket = BSSPacket.Decode(frame.data);
            if (bssPacket != null)
            {
                // Only add to history if this is an incoming BSS packet
                // Outgoing BSS packets are already recorded by OnChat()
                if (!frame.incoming) return;

                // Don't create entry if message is empty
                if (string.IsNullOrEmpty(bssPacket.Message)) return;

                // Extract location data if available
                double latitude = 0;
                double longitude = 0;
                if (bssPacket.Location != null)
                {
                    latitude = bssPacket.Location.Latitude;
                    longitude = bssPacket.Location.Longitude;
                }

                // Create a DecodedTextEntry for the BSS packet
                if (!string.IsNullOrEmpty(bssPacket.Message))
                {
                    lock (_historyLock)
                    {
                        var entry = new DecodedTextEntry
                        {
                            Text = bssPacket.Message,
                            Channel = frame.channel_name ?? "",
                            Time = frame.time,
                            IsReceived = frame.incoming,
                            Encoding = VoiceTextEncodingType.BSS,
                            Source = bssPacket.Callsign,
                            Destination = bssPacket.Destination,
                            Latitude = latitude,
                            Longitude = longitude
                        };
                        _decodedTextHistory.Add(entry);

                        // Trim if exceeds max size
                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }
                    }

                    // Save to file and dispatch updated history
                    SaveVoiceTextHistory();
                    DispatchDecodedTextHistory();

                    // Dispatch a TextReady event for the BSS packet (including location)
                    DispatchTextReady(bssPacket.Message, frame.channel_name ?? "", frame.time, true, frame.incoming, VoiceTextEncodingType.BSS, latitude, longitude, source: bssPacket.Callsign, destination: bssPacket.Destination);
                }

                return;
            }

            // Decode the frame as AX.25
            AX25Packet ax25Packet = AX25Packet.DecodeAX25Packet(frame);
            if (ax25Packet == null) return;

            // Only process U_FRAME_UI or U_FRAME (unnumbered information frames)
            if (ax25Packet.type != AX25Packet.FrameType.U_FRAME_UI && ax25Packet.type != AX25Packet.FrameType.U_FRAME) return;

            // Extract source and destination from the AX.25 packet
            if (ax25Packet.addresses == null || ax25Packet.addresses.Count < 2) return;

            string destination = ax25Packet.addresses[0].CallSignWithId;
            string source = ax25Packet.addresses[1].CallSignWithId;

            AprsPacket aprsPacket = AprsPacket.Parse(ax25Packet);
            if (aprsPacket != null)
            {
                double latitude = 0;
                double longitude = 0;
                if (aprsPacket.Position != null)
                {
                    latitude = aprsPacket.Position.CoordinateSet.Latitude.Value;
                    longitude = aprsPacket.Position.CoordinateSet.Longitude.Value;
                }

                if (aprsPacket.Comment != null)
                {
                    // Add to history as a received AX.25 entry
                    lock (_historyLock)
                    {
                        var entry = new DecodedTextEntry
                        {
                            Text = aprsPacket.Comment,
                            Channel = frame.channel_name ?? "",
                            Time = frame.time,
                            IsReceived = true,
                            Encoding = VoiceTextEncodingType.APRS,
                            Source = source,
                            Destination = null,
                            Latitude = latitude,
                            Longitude = longitude
                        };
                        _decodedTextHistory.Add(entry);

                        // Trim if exceeds max size
                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }
                    }

                    // Save to file and dispatch updated history
                    SaveVoiceTextHistory();
                    DispatchDecodedTextHistory();

                    // Dispatch a TextReady event for the APRS packet
                    DispatchTextReady(aprsPacket.Comment, frame.channel_name ?? "", frame.time, true, true, VoiceTextEncodingType.APRS, latitude, longitude, source: source, destination: null);
                    return;
                }

                if ((aprsPacket.MessageData != null) && (aprsPacket.MessageData.MsgText != null))
                {
                    // Add to history as a received AX.25 entry
                    lock (_historyLock)
                    {
                        var entry = new DecodedTextEntry
                        {
                            Text = aprsPacket.MessageData.MsgText,
                            Channel = frame.channel_name ?? "",
                            Time = frame.time,
                            IsReceived = true,
                            Encoding = VoiceTextEncodingType.APRS,
                            Source = source,
                            Destination = aprsPacket.MessageData.Addressee,
                            Latitude = latitude,
                            Longitude = longitude
                        };
                        _decodedTextHistory.Add(entry);

                        // Trim if exceeds max size
                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }
                    }

                    // Save to file and dispatch updated history
                    SaveVoiceTextHistory();
                    DispatchDecodedTextHistory();

                    // Dispatch a TextReady event for the APRS packet
                    DispatchTextReady(aprsPacket.MessageData.MsgText, frame.channel_name ?? "", frame.time, true, true, VoiceTextEncodingType.APRS, latitude, longitude, source: source, destination: aprsPacket.MessageData.Addressee);
                    return;
                }
            }

            // Get the message/data content
            string messageText = ax25Packet.dataStr;
            if (string.IsNullOrEmpty(messageText) && ax25Packet.data != null && ax25Packet.data.Length > 0)
            {
                // Try to convert binary data to string if dataStr is empty
                try
                {
                    messageText = System.Text.Encoding.ASCII.GetString(ax25Packet.data);
                }
                catch
                {
                    messageText = "[Binary data]";
                }
            }

            // Add to history as a received AX.25 entry
            lock (_historyLock)
            {
                var entry = new DecodedTextEntry
                {
                    Text = messageText,
                    Channel = frame.channel_name ?? "",
                    Time = frame.time,
                    IsReceived = true,
                    Encoding = VoiceTextEncodingType.AX25,
                    Source = source,
                    Destination = destination
                };
                _decodedTextHistory.Add(entry);

                // Trim if exceeds max size
                while (_decodedTextHistory.Count > MaxHistorySize)
                {
                    _decodedTextHistory.RemoveAt(0);
                }
            }

            // Save to file and dispatch updated history
            SaveVoiceTextHistory();
            DispatchDecodedTextHistory();

            // Dispatch a TextReady event for the AX.25 packet
            DispatchTextReady(messageText, frame.channel_name ?? "", frame.time, true, true, VoiceTextEncodingType.AX25, source: source, destination: destination);
        }

        /// <summary>
        /// Handles SpeechToTextEnabled setting changes from DataBroker.
        /// </summary>
        private void OnSpeechToTextEnabledChanged(int deviceId, string name, object data)
        {
            if (data == null) return;

            bool enabled = true;
            if (data is bool boolValue)
            {
                enabled = boolValue;
            }

            if (_speechToTextEnabled == enabled) return;
            _speechToTextEnabled = enabled;

            broker.LogInfo($"[VoiceHandler] SpeechToTextEnabled changed to: {_speechToTextEnabled}");

            if (_enabled)
            {
                if (_speechToTextEnabled)
                {
                    // Re-initialize the speech engine if voice handler is enabled
                    InitializeSpeechEngine();
                }
                else
                {
                    // Clean up the speech engine
                    CleanupSpeechEngine();
                }
            }
        }

        /// <summary>
        /// Handles voice setting changes from DataBroker.
        /// </summary>
        private void OnVoiceChanged(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            string newVoice = data as string;
            if (string.IsNullOrEmpty(newVoice)) return;
            
            lock (_ttsLock)
            {
                if (_currentVoice != newVoice)
                {
                    _currentVoice = newVoice;
                    if (_synthesizer != null && _ttsAvailable)
                    {
                        try
                        {
                            _synthesizer.SelectVoice(_currentVoice);
                            broker.LogInfo($"[VoiceHandler] Voice changed to: {_currentVoice}");
                        }
                        catch (Exception ex)
                        {
                            broker.LogError($"[VoiceHandler] Failed to change voice: {ex.Message}");
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Gets the current VFO A channel name from the radio.
        /// VFO A is always used for transmission.
        /// </summary>
        /// <param name="radioDeviceId">The device ID of the radio.</param>
        /// <returns>The channel name, or empty string if not available.</returns>
        private string GetVfoAChannelName(int radioDeviceId)
        {
            try
            {
                // Get Settings from the radio to find channel_a ID
                var settings = DataBroker.GetValue(radioDeviceId, "Settings");
                if (settings == null) return "";

                var settingsType = settings.GetType();
                
                // channel_a is a field, not a property
                var channelAField = settingsType.GetField("channel_a");
                if (channelAField == null) return "";

                object channelAValue = channelAField.GetValue(settings);
                if (channelAValue == null) return "";

                int channelAId = Convert.ToInt32(channelAValue);

                // Get Channels array from the radio
                var channels = DataBroker.GetValue(radioDeviceId, "Channels") as Array;
                if (channels == null || channelAId < 0 || channelAId >= channels.Length) return "";

                var channelInfo = channels.GetValue(channelAId);
                if (channelInfo == null) return "";

                // Get the channel name - name_str is a field, not a property
                var channelType = channelInfo.GetType();
                var nameStrField = channelType.GetField("name_str");
                if (nameStrField != null)
                {
                    string name = nameStrField.GetValue(channelInfo) as string;
                    if (!string.IsNullOrEmpty(name)) return name;
                }

                // If no name, try to get the frequency as a fallback
                var rxFreqField = channelType.GetField("rx_freq");
                if (rxFreqField != null)
                {
                    object freqValue = rxFreqField.GetValue(channelInfo);
                    if (freqValue != null)
                    {
                        long freq = Convert.ToInt64(freqValue);
                        if (freq > 0)
                        {
                            return ((double)freq / 1000000).ToString("F3") + " MHz";
                        }
                    }
                }

                return "";
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error getting VFO A channel name: {ex.Message}");
                return "";
            }
        }

        /// <summary>
        /// Handles the Speak command to generate and transmit speech.
        /// If received on device 1, use the currently voice-enabled radio (_targetDeviceId).
        /// If received on device 100+, use that device ID directly for transmission.
        /// Expected data: string (the text to speak)
        /// </summary>
        private void OnSpeak(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            string textToSpeak = data as string;
            if (string.IsNullOrEmpty(textToSpeak)) return;
            
            // Determine the target device for transmission
            int transmitDeviceId;
            if (deviceId == 1)
            {
                // Device 1: use the currently voice-enabled radio
                transmitDeviceId = _targetDeviceId;
                if (transmitDeviceId <= 0)
                {
                    broker.LogError("[VoiceHandler] Cannot speak: No radio is voice-enabled");
                    return;
                }
            }
            else if (deviceId >= 100)
            {
                // Device 100+: use that device ID directly
                transmitDeviceId = deviceId;
            }
            else
            {
                // Other device IDs (2-99): ignore
                return;
            }
            
            lock (_ttsLock)
            {
                if (!_ttsAvailable || _synthesizer == null)
                {
                    broker.LogError("[VoiceHandler] Cannot speak: Text-to-Speech not available");
                    return;
                }
                
                if (_ttsPendingDeviceId != -1)
                {
                    broker.LogError("[VoiceHandler] Cannot speak: Already processing another speech request");
                    return;
                }
                
                // Store the target device ID for when speech completes
                _ttsPendingDeviceId = transmitDeviceId;
                
                // Clear the audio stream
                _ttsAudioStream.SetLength(0);
                
                // Get the VFO A channel name for history
                string channelName = GetVfoAChannelName(transmitDeviceId);
                
                broker.LogInfo($"[VoiceHandler] Speaking on device {transmitDeviceId}: {textToSpeak}");
                
                // Add to history as a transmitted voice entry
                AddTransmittedTextToHistory(textToSpeak, channelName, VoiceTextEncodingType.Voice);
                
                // Start async speech generation
                _synthesizer.SpeakAsync(textToSpeak);
            }
        }

        /// <summary>
        /// Handles the Morse command to generate and transmit morse code.
        /// If received on device 1, use the currently voice-enabled radio (_targetDeviceId).
        /// If received on device 100+, use that device ID directly for transmission.
        /// Expected data: string (the text to convert to morse)
        /// </summary>
        private void OnMorse(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            string textToMorse = data as string;
            if (string.IsNullOrEmpty(textToMorse)) return;
            
            // Determine the target device for transmission
            int transmitDeviceId;
            if (deviceId == 1)
            {
                // Device 1: use the currently voice-enabled radio
                transmitDeviceId = _targetDeviceId;
                if (transmitDeviceId <= 0)
                {
                    broker.LogError("[VoiceHandler] Cannot transmit morse: No radio is voice-enabled");
                    return;
                }
            }
            else if (deviceId >= 100)
            {
                // Device 100+: use that device ID directly
                transmitDeviceId = deviceId;
            }
            else
            {
                // Other device IDs (2-99): ignore
                return;
            }
            
            try
            {
                // Get the VFO A channel name for history
                string channelName = GetVfoAChannelName(transmitDeviceId);
                
                broker.LogInfo($"[VoiceHandler] Generating morse code on device {transmitDeviceId}: {textToMorse}");
                
                // Add to history as a transmitted morse entry
                AddTransmittedTextToHistory(textToMorse, channelName, VoiceTextEncodingType.Morse);
                
                // Generate morse code PCM (8-bit unsigned, 32kHz)
                byte[] morsePcm8bit = MorseCodeEngine.GenerateMorsePcm(textToMorse);
                
                if (morsePcm8bit == null || morsePcm8bit.Length == 0)
                {
                    broker.LogError("[VoiceHandler] Failed to generate morse code PCM");
                    return;
                }
                
                // Convert 8-bit unsigned PCM to 16-bit signed PCM
                // 8-bit unsigned: 0-255, with 128 as center (silence)
                // 16-bit signed: -32768 to 32767, with 0 as center (silence)
                byte[] pcmData = new byte[morsePcm8bit.Length * 2];
                for (int i = 0; i < morsePcm8bit.Length; i++)
                {
                    // Convert 8-bit unsigned (0-255, center 128) to 16-bit signed (-32768 to 32767, center 0)
                    short sample16 = (short)((morsePcm8bit[i] - 128) * 256);
                    pcmData[i * 2] = (byte)(sample16 & 0xFF);
                    pcmData[i * 2 + 1] = (byte)((sample16 >> 8) & 0xFF);
                }
                
                // Send PCM data to the radio for transmission via DataBroker
                // Include PlayLocally=true so the user can hear the morse output
                broker.Dispatch(transmitDeviceId, "TransmitVoicePCM", new { Data = pcmData, PlayLocally = true }, store: false);
                broker.LogInfo($"[VoiceHandler] Transmitted {pcmData.Length} bytes of morse PCM to device {transmitDeviceId}");
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error generating morse code: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles the Chat command to transmit a BSS chat message.
        /// If received on device 1, use the currently voice-enabled radio (_targetDeviceId).
        /// If received on device 100+, use that device ID directly for transmission.
        /// Expected data: string (the message to send)
        /// </summary>
        private void OnChat(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            string message = data as string;
            if (string.IsNullOrEmpty(message)) return;
            
            // Validate message length (must be > 0 and < 255 characters)
            if (message.Length == 0 || message.Length >= 255)
            {
                broker.LogError($"[VoiceHandler] Cannot send chat: Message length must be between 1 and 254 characters (got {message.Length})");
                return;
            }
            
            // Determine the target device for transmission
            int transmitDeviceId;
            if (deviceId == 1)
            {
                // Device 1: use the currently voice-enabled radio
                transmitDeviceId = _targetDeviceId;
                if (transmitDeviceId <= 0)
                {
                    broker.LogError("[VoiceHandler] Cannot send chat: No radio is voice-enabled");
                    return;
                }
            }
            else if (deviceId >= 100)
            {
                // Device 100+: use that device ID directly
                transmitDeviceId = deviceId;
            }
            else
            {
                // Other device IDs (2-99): ignore
                return;
            }
            
            try
            {
                // Get our callsign from settings (without station ID)
                string callsign = broker.GetValue<string>(0, "CallSign", "");
                if (string.IsNullOrEmpty(callsign))
                {
                    broker.LogError("[VoiceHandler] Cannot send chat: Callsign not configured");
                    return;
                }
                
                // Get the VFO A channel name for history
                string channelName = GetVfoAChannelName(transmitDeviceId);
                
                broker.LogInfo($"[VoiceHandler] Sending chat on device {transmitDeviceId}: {callsign}: {message}");
                
                // Create a BSS packet with callsign and message
                BSSPacket bssPacket = new BSSPacket(callsign, null, message);
                byte[] bssData = bssPacket.Encode();
                
                // Don't create entry if message is empty
                if (string.IsNullOrEmpty(message)) return;

                // Add to history as a transmitted BSS entry (just the message text)
                AddTransmittedTextToHistory(message, channelName, VoiceTextEncodingType.BSS, source: callsign);
                
                // Create TransmitDataFrameData and dispatch to the radio
                var txData = new TransmitDataFrameData
                {
                    BSSPacket = bssPacket,
                    ChannelId = -1, // Use current channel
                    RegionId = -1
                };
                
                broker.Dispatch(transmitDeviceId, "TransmitDataFrame", txData, store: false);
                broker.LogInfo($"[VoiceHandler] Transmitted BSS chat packet to device {transmitDeviceId}");
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error sending chat: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles the VoiceClipTransmitted command to record voice clip transmission in history.
        /// Expected data: { ClipName: string, ChannelName: string }
        /// </summary>
        private void OnVoiceClipTransmitted(int deviceId, string name, object data)
        {
            if (data == null) return;
            
            try
            {
                // Use reflection to extract properties from the anonymous object
                var dataType = data.GetType();
                var clipNameProp = dataType.GetProperty("ClipName");
                var channelNameProp = dataType.GetProperty("ChannelName");
                
                if (clipNameProp == null || channelNameProp == null)
                {
                    broker.LogError("[VoiceHandler] Invalid VoiceClipTransmitted data format");
                    return;
                }
                
                string clipName = (string)clipNameProp.GetValue(data);
                string channelName = (string)channelNameProp.GetValue(data);
                
                if (string.IsNullOrEmpty(clipName))
                {
                    broker.LogError("[VoiceHandler] VoiceClipTransmitted: ClipName is empty");
                    return;
                }
                
                broker.LogInfo($"[VoiceHandler] Voice clip transmitted on device {deviceId}: {clipName}");
                
                // Add to history as a transmitted voice clip entry
                AddTransmittedTextToHistory(clipName, channelName ?? "", VoiceTextEncodingType.VoiceClip);
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error in OnVoiceClipTransmitted: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles the PictureTransmitted command to record SSTV picture transmission in history.
        /// Expected data: { ModeName: string, Filename: string }
        /// </summary>
        private void OnPictureTransmitted(int deviceId, string name, object data)
        {
            if (data == null) return;

            try
            {
                var dataType = data.GetType();
                var modeNameProp = dataType.GetProperty("ModeName");
                var filenameProp = dataType.GetProperty("Filename");

                if (modeNameProp == null || filenameProp == null)
                {
                    broker.LogError("[VoiceHandler] Invalid PictureTransmitted data format");
                    return;
                }

                string modeName = (string)modeNameProp.GetValue(data);
                string filename = (string)filenameProp.GetValue(data);

                if (string.IsNullOrEmpty(filename))
                {
                    broker.LogError("[VoiceHandler] PictureTransmitted: Filename is empty");
                    return;
                }

                // Determine the transmit device for channel name lookup
                int transmitDeviceId = (deviceId >= 100) ? deviceId : _targetDeviceId;
                string channelName = (transmitDeviceId > 0) ? GetVfoAChannelName(transmitDeviceId) : "";

                broker.LogInfo($"[VoiceHandler] SSTV picture transmitted on device {deviceId}: {modeName}, file: {filename}");

                // Add to history as a transmitted picture entry
                AddTransmittedTextToHistory(modeName ?? "SSTV", channelName, VoiceTextEncodingType.Picture, filename: filename);
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error in OnPictureTransmitted: {ex.Message}");
            }
        }

        /// <summary>
        /// Called when speech synthesis is complete.
        /// </summary>
        private void Synthesizer_SpeakCompleted(object sender, SpeakCompletedEventArgs e)
        {
            int targetDeviceId;
            byte[] pcmData;
            
            lock (_ttsLock)
            {
                targetDeviceId = _ttsPendingDeviceId;
                _ttsPendingDeviceId = -1;
                
                if (targetDeviceId <= 0)
                {
                    return;
                }
                
                pcmData = _ttsAudioStream.ToArray();
                _ttsAudioStream.SetLength(0);
            }
            
            if (pcmData.Length > 0)
            {
                // Boost volume to match radio audio levels
                BoostVolume(pcmData, pcmData.Length, 5f);
                
                // Send PCM data to the radio for transmission via DataBroker
                // Include PlayLocally=true so the user can hear the TTS output
                broker.Dispatch(targetDeviceId, "TransmitVoicePCM", new { Data = pcmData, PlayLocally = true }, store: false);
                broker.LogInfo($"[VoiceHandler] Transmitted {pcmData.Length} bytes of speech PCM to device {targetDeviceId}");
            }
        }

        /// <summary>
        /// Boosts the volume of PCM audio data.
        /// </summary>
        private void BoostVolume(byte[] buffer, int bytesRecorded, float volume)
        {
            for (int i = 0; i < bytesRecorded; i += 2)
            {
                short sample = (short)(buffer[i] | (buffer[i + 1] << 8));
                int boosted = (int)(sample * volume);

                // Clamp to prevent clipping
                if (boosted > short.MaxValue) boosted = short.MaxValue;
                if (boosted < short.MinValue) boosted = short.MinValue;

                buffer[i] = (byte)(boosted & 0xFF);
                buffer[i + 1] = (byte)((boosted >> 8) & 0xFF);
            }
        }

        /// <summary>
        /// Handles the AudioDataEnd event - forces speech-to-text to process remaining audio and finalizes recordings.
        /// This is called when the radio signals the end of an audio segment.
        /// </summary>
        private void OnAudioDataEnd(int deviceId, string name, object data)
        {
            // Handle speech-to-text completion
            if (deviceId == _targetDeviceId && _enabled && _speechToTextEngine != null)
            {
                try
                {
                    // Force the speech-to-text engine to process any remaining audio
                    _speechToTextEngine.CompleteVoiceSegment();
                    _maxVoiceDecodeTime = 0;
                }
                catch (Exception ex)
                {
                    broker.LogError($"[VoiceHandler] Error in OnAudioDataEnd (speech-to-text): {ex.Message}");
                }
            }

            // Handle recording completion
            if (_recordingEnabled && deviceId == _targetDeviceId)
            {
                FinalizeCurrentRecording();
            }
        }

        /// <summary>
        /// Handles the AudioDataStart event - starts a new recording if recording is enabled.
        /// Expected data: { StartTime: DateTime, ChannelName: string }
        /// </summary>
        private void OnAudioDataStart(int deviceId, string name, object data)
        {
            // Only care about audio start events for the radio we're monitoring
            if (!_recordingEnabled || deviceId != _targetDeviceId)
            {
                return;
            }

            try
            {
                // Get the start time and channel name from the event data
                DateTime startTime = DateTime.UtcNow;
                string channelName = _currentChannelName;

                if (data != null)
                {
                    // Try to extract from anonymous object with StartTime and ChannelName properties
                    var dataType = data.GetType();
                    var startTimeProp = dataType.GetProperty("StartTime");
                    var channelNameProp = dataType.GetProperty("ChannelName");

                    if (startTimeProp != null)
                    {
                        object startTimeValue = startTimeProp.GetValue(data);
                        if (startTimeValue is DateTime dt)
                        {
                            startTime = dt;
                        }
                    }

                    if (channelNameProp != null)
                    {
                        object channelNameValue = channelNameProp.GetValue(data);
                        if (channelNameValue is string cn && !string.IsNullOrEmpty(cn))
                        {
                            channelName = cn;
                            _currentChannelName = cn; // Update current channel name
                        }
                    }
                }

                // Start a new recording
                StartNewRecording(startTime, channelName);
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error in OnAudioDataStart: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles the RecordingEnable command to enable automatic recording of voice clips.
        /// </summary>
        private void OnRecordingEnable(int deviceId, string name, object data)
        {
            if (_recordingEnabled) return;

            _recordingEnabled = true;
            DispatchRecordingState();
            broker.LogInfo("[VoiceHandler] Recording enabled");
        }

        /// <summary>
        /// Handles the RecordingDisable command to disable automatic recording of voice clips.
        /// </summary>
        private void OnRecordingDisable(int deviceId, string name, object data)
        {
            if (!_recordingEnabled) return;

            // Finalize any current recording before disabling
            FinalizeCurrentRecording();

            _recordingEnabled = false;
            DispatchRecordingState();
            broker.LogInfo("[VoiceHandler] Recording disabled");
        }

        /// <summary>
        /// Starts a new recording with the given start time and channel name.
        /// </summary>
        private void StartNewRecording(DateTime startTime, string channelName)
        {
            lock (_recordingLock)
            {
                // If there's already an active recording, finalize it first
                if (_currentRecordingWriter != null)
                {
                    FinalizeCurrentRecordingInternal();
                }

                try
                {
                    // Generate filename: Recording_{date}_{time}_{channel}.wav
                    string sanitizedChannel = SanitizeFilename(channelName);
                    string filename = $"Recording_{startTime:yyyy-MM-dd}_{startTime:HH-mm-ss}_{sanitizedChannel}.wav";
                    string fullPath = Path.Combine(_recordingsPath, filename);

                    // Create the WAV file writer (32kHz, 16-bit, mono)
                    _currentRecordingWriter = new NAudio.Wave.WaveFileWriter(fullPath, new NAudio.Wave.WaveFormat(32000, 16, 1));
                    _currentRecordingStartTime = startTime;
                    _currentRecordingChannel = channelName;
                    _currentRecordingFilename = filename;

                    broker.LogInfo($"[VoiceHandler] Started recording: {filename}");
                }
                catch (Exception ex)
                {
                    broker.LogError($"[VoiceHandler] Failed to start recording: {ex.Message}");
                    _currentRecordingWriter = null;
                }
            }
        }

        /// <summary>
        /// Finalizes the current recording, adds it to history, and closes the file.
        /// </summary>
        private void FinalizeCurrentRecording()
        {
            lock (_recordingLock)
            {
                FinalizeCurrentRecordingInternal();
            }
        }

        /// <summary>
        /// Internal method to finalize recording (must be called within lock).
        /// </summary>
        private void FinalizeCurrentRecordingInternal()
        {
            if (_currentRecordingWriter == null) return;

            try
            {
                // Calculate the duration in seconds
                // Audio format is 32kHz, 16-bit, mono = 64000 bytes per second
                long totalBytes = _currentRecordingWriter.Length;
                double durationSeconds = totalBytes / 64000.0;

                // Close and dispose the writer
                _currentRecordingWriter.Dispose();
                _currentRecordingWriter = null;

                // Only add to history if the recording has some content (at least 0.1 seconds)
                if (durationSeconds >= 0.1)
                {
                    int durationInt = (int)Math.Round(durationSeconds);

                    // Add to history as a received recording entry
                    lock (_historyLock)
                    {
                        var entry = new DecodedTextEntry
                        {
                            Text = null,
                            Channel = _currentRecordingChannel,
                            Time = _currentRecordingStartTime,
                            IsReceived = true,
                            Encoding = VoiceTextEncodingType.Recording,
                            Filename = _currentRecordingFilename,
                            Duration = durationInt
                        };
                        _decodedTextHistory.Add(entry);

                        // Trim if exceeds max size
                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }
                    }

                    // Save to file and dispatch updated history
                    SaveVoiceTextHistory();
                    DispatchDecodedTextHistory();

                    // Dispatch TextReady event for the recording
                    DispatchTextReady(null, _currentRecordingChannel, _currentRecordingStartTime, true, true, VoiceTextEncodingType.Recording, filename: _currentRecordingFilename, duration: durationInt);

                    broker.LogInfo($"[VoiceHandler] Completed recording: {_currentRecordingFilename} ({durationSeconds:F1} sec)");
                }
                else
                {
                    // Delete very short recordings
                    try
                    {
                        string fullPath = Path.Combine(_recordingsPath, _currentRecordingFilename);
                        if (File.Exists(fullPath))
                        {
                            File.Delete(fullPath);
                        }
                    }
                    catch (Exception) { }

                    broker.LogInfo($"[VoiceHandler] Discarded short recording: {_currentRecordingFilename}");
                }
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error finalizing recording: {ex.Message}");
                try { _currentRecordingWriter?.Dispose(); } catch { }
                _currentRecordingWriter = null;
            }

            // Clear recording state
            _currentRecordingFilename = "";
            _currentRecordingChannel = "";
        }

        /// <summary>
        /// Sanitizes a string for use in a filename by replacing invalid characters.
        /// </summary>
        private string SanitizeFilename(string input)
        {
            if (string.IsNullOrEmpty(input)) return "Unknown";

            char[] invalidChars = Path.GetInvalidFileNameChars();
            string result = input;
            foreach (char c in invalidChars)
            {
                result = result.Replace(c, '_');
            }
            return result;
        }

        /// <summary>
        /// Dispatches the current recording state to the Data Broker.
        /// </summary>
        private void DispatchRecordingState()
        {
            broker.Dispatch(0, "RecordingState", _recordingEnabled, store: true);
        }

        /// <summary>
        /// Handles radio state change events. If the target radio disconnects, disable the handler.
        /// </summary>
        private void OnRadioStateChanged(int deviceId, string name, object data)
        {
            // Only care about state changes for the radio we're monitoring
            if (deviceId != _targetDeviceId || !_enabled) return;

            string state = data as string;
            if (state == null) return;

            // If the radio is disconnected, disable the voice handler
            if (state == "Disconnected" || state == "UnableToConnect" || state == "BluetoothNotAvailable" || state == "AccessDenied")
            {
                broker.LogInfo($"[VoiceHandler] Target radio {deviceId} disconnected (state: {state}), disabling voice handler");
                Disable();
            }
        }

        /// <summary>
        /// Handles AudioState change events. If audio is disabled for the target radio, disable speech-to-text.
        /// </summary>
        private void OnAudioStateChanged(int deviceId, string name, object data)
        {
            // Only care about audio state changes for the radio we're monitoring
            if (deviceId != _targetDeviceId || !_enabled) return;

            // Check if audio state is false (audio disabled)
            bool audioEnabled = false;
            if (data is bool boolValue)
            {
                audioEnabled = boolValue;
            }

            // If audio is disabled, disable the voice handler
            if (!audioEnabled)
            {
                broker.LogInfo($"[VoiceHandler] Audio disabled on target radio {deviceId}, disabling speech-to-text processing");
                Disable();
            }
        }

        /// <summary>
        /// Handles the VoiceHandlerEnable command.
        /// Expected data format: { DeviceId: int, Language: string, Model: string }
        /// </summary>
        private void OnVoiceHandlerEnable(int deviceId, string name, object data)
        {
            try
            {
                if (data == null) return;

                // Use reflection to extract properties from the anonymous object
                var dataType = data.GetType();
                var deviceIdProp = dataType.GetProperty("DeviceId");
                var languageProp = dataType.GetProperty("Language");
                var modelProp = dataType.GetProperty("Model");

                if (deviceIdProp == null || languageProp == null || modelProp == null)
                {
                    broker.LogError("[VoiceHandler] Invalid VoiceHandlerEnable data format");
                    return;
                }

                int targetDevice = (int)deviceIdProp.GetValue(data);
                string language = (string)languageProp.GetValue(data);
                string model = (string)modelProp.GetValue(data);

                Enable(targetDevice, language, model);
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error in OnVoiceHandlerEnable: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles the VoiceHandlerDisable command.
        /// </summary>
        private void OnVoiceHandlerDisable(int deviceId, string name, object data)
        {
            Disable();
        }

        /// <summary>
        /// Enables the voice handler to listen to a specific radio device.
        /// </summary>
        /// <param name="deviceId">The radio device ID to listen to.</param>
        /// <param name="language">The language for speech recognition ("auto" for automatic detection).</param>
        /// <param name="model">The path to the Whisper model file.</param>
        public void Enable(int deviceId, string language, string model)
        {
            if (_enabled && _targetDeviceId == deviceId && _voiceLanguage == language && _voiceModel == model)
            {
                return; // Already enabled with the same settings
            }

            // Validate that the radio is connected before enabling
            string radioState = DataBroker.GetValue<string>(deviceId, "State", null);
            if (radioState != "Connected")
            {
                broker.LogError($"[VoiceHandler] Cannot enable for device {deviceId}: Radio is not connected (state: {radioState ?? "unknown"})");
                return;
            }

            // Check if audio is enabled for this radio, and enable it if not
            // Voice processing requires audio streaming from the radio
            bool audioEnabled = DataBroker.GetValue<bool>(deviceId, "AudioState", false);
            if (!audioEnabled)
            {
                broker.LogInfo($"[VoiceHandler] Audio not enabled for device {deviceId}, enabling audio streaming");
                broker.Dispatch(deviceId, "SetAudio", true, store: false);
            }

            // Disable first if already enabled
            if (_enabled)
            {
                Disable();
            }

            _targetDeviceId = deviceId;
            _voiceLanguage = language;
            _voiceModel = model;
            _enabled = true;
            _maxVoiceDecodeTime = 0;

            broker.LogInfo($"[VoiceHandler] Enabled for device {deviceId}, language: {language}");

            // Initialize the speech-to-text engine (only if speech-to-text is enabled)
            if (_speechToTextEnabled)
            {
                InitializeSpeechEngine();
            }

            // Initialize the SSTV monitor for auto-detection
            InitializeSstvMonitor();

            // Dispatch the updated state
            DispatchVoiceHandlerState();
        }

        /// <summary>
        /// Disables the voice handler.
        /// </summary>
        public void Disable()
        {
            if (!_enabled) return;

            int previousDeviceId = _targetDeviceId;
            _enabled = false;
            _targetDeviceId = -1;

            // Clean up the speech engine
            CleanupSpeechEngine();

            // Clean up the SSTV monitor
            CleanupSstvMonitor();

            // Dispatch ProcessingVoice to indicate we're no longer listening/processing
            if (previousDeviceId > 0)
            {
                broker.Dispatch(previousDeviceId, "ProcessingVoice", new
                {
                    Listening = false,
                    Processing = false
                }, store: false);
            }

            // Dispatch the updated state
            DispatchVoiceHandlerState();

            broker.LogInfo("[VoiceHandler] Disabled");
        }

        /// <summary>
        /// Initializes the WhisperEngine for speech-to-text conversion.
        /// </summary>
        private void InitializeSpeechEngine()
        {
            if (_speechToTextEngine != null)
            {
                CleanupSpeechEngine();
            }

            try
            {
                // Construct the full path to the model file
                // Model name is stored as e.g., "Tiny", "Base.en", etc.
                // Full path is: %LOCALAPPDATA%\HTCommander\ggml-{model}.bin
                string modelPath = GetModelFullPath(_voiceModel);
                
                if (string.IsNullOrEmpty(modelPath))
                {
                    broker.LogError("[VoiceHandler] No voice model specified");
                    return;
                }

                if (!File.Exists(modelPath))
                {
                    broker.LogError($"[VoiceHandler] Voice model file not found: {modelPath}");
                    return;
                }

                _speechToTextEngine = new WhisperEngine(modelPath, _voiceLanguage);
                _speechToTextEngine.OnDebugMessage += OnWhisperDebugMessage;
                _speechToTextEngine.onProcessingVoice += OnWhisperProcessingVoice;
                _speechToTextEngine.onTextReady += OnWhisperTextReady;
                _speechToTextEngine.StartVoiceSegment();

                DispatchProcessingVoice(true, false);
                broker.LogInfo($"[VoiceHandler] Speech engine initialized with model: {modelPath}");
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Failed to initialize speech engine: {ex.Message}");
                _speechToTextEngine = null;
            }
        }

        /// <summary>
        /// Gets the full path to the voice model file.
        /// </summary>
        /// <param name="modelName">The model name (e.g., "Tiny", "Base.en").</param>
        /// <returns>The full path to the model file, or null if model name is empty.</returns>
        private string GetModelFullPath(string modelName)
        {
            if (string.IsNullOrEmpty(modelName))
            {
                return null;
            }

            // Model files are stored in: %LOCALAPPDATA%\HTCommander\ggml-{model}.bin
            string filename = "ggml-" + modelName.ToLower() + ".bin";
            string appDataPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HTCommander",
                filename);

            return appDataPath;
        }

        /// <summary>
        /// Cleans up the WhisperEngine.
        /// </summary>
        private void CleanupSpeechEngine()
        {
            if (_speechToTextEngine != null)
            {
                try
                {
                    _speechToTextEngine.ResetVoiceSegment();
                    _speechToTextEngine.OnDebugMessage -= OnWhisperDebugMessage;
                    _speechToTextEngine.onProcessingVoice -= OnWhisperProcessingVoice;
                    _speechToTextEngine.onTextReady -= OnWhisperTextReady;
                    _speechToTextEngine.Dispose();
                }
                catch (Exception ex)
                {
                    broker.LogError($"[VoiceHandler] Error cleaning up speech engine: {ex.Message}");
                }
                finally
                {
                    _speechToTextEngine = null;
                }

                DispatchProcessingVoice(false, false);
            }

            _maxVoiceDecodeTime = 0;
        }

        /// <summary>
        /// Initializes the SSTV monitor for automatic image detection and decoding.
        /// </summary>
        private void InitializeSstvMonitor()
        {
            lock (_sstvLock)
            {
                CleanupSstvMonitor();

                _sstvMonitor = new SstvMonitor(32000);
                _sstvMonitor.DecodingStarted += OnSstvDecodingStarted;
                _sstvMonitor.DecodingProgress += OnSstvDecodingProgress;
                _sstvMonitor.DecodingComplete += OnSstvDecodingComplete;

                broker.LogInfo("[VoiceHandler] SSTV monitor initialized");
            }
        }

        /// <summary>
        /// Cleans up the SSTV monitor.
        /// </summary>
        private void CleanupSstvMonitor()
        {
            lock (_sstvLock)
            {
                if (_sstvMonitor != null)
                {
                    _sstvMonitor.DecodingStarted -= OnSstvDecodingStarted;
                    _sstvMonitor.DecodingProgress -= OnSstvDecodingProgress;
                    _sstvMonitor.DecodingComplete -= OnSstvDecodingComplete;
                    _sstvMonitor.Dispose();
                    _sstvMonitor = null;
                }
            }
        }

        /// <summary>
        /// Called when the SSTV monitor detects the start of an SSTV image.
        /// </summary>
        private void OnSstvDecodingStarted(object sender, SstvDecodingStartedEventArgs e)
        {
            broker.LogInfo($"[VoiceHandler] SSTV decoding started: {e.ModeName} ({e.Width}x{e.Height})");
            _sstvDecoding = true;
            _sstvStartTime = DateTime.Now;

            // Pause speech-to-text by flushing any pending audio
            if (_speechToTextEngine != null)
            {
                try { _speechToTextEngine.CompleteVoiceSegment(); }
                catch (Exception ex) { broker.LogError($"[VoiceHandler] Error pausing speech-to-text for SSTV: {ex.Message}"); }
            }

            // Create a partial decoded text entry for the in-progress SSTV image
            string channelName = _currentChannelName;
            lock (_historyLock)
            {
                _currentSstvEntry = new DecodedTextEntry
                {
                    Text = $"Receiving {e.ModeName}...",
                    Channel = channelName,
                    Time = _sstvStartTime,
                    IsReceived = true,
                    Encoding = VoiceTextEncodingType.Picture
                };
            }

            // Dispatch partial TextReady so the UI shows the in-progress entry
            DispatchTextReady($"Receiving {e.ModeName}...", channelName, _sstvStartTime, false, true, VoiceTextEncodingType.Picture);

            if (_targetDeviceId > 0)
            {
                broker.Dispatch(_targetDeviceId, "SstvDecodingState", new
                {
                    Active = true,
                    ModeName = e.ModeName,
                    Width = e.Width,
                    Height = e.Height,
                    PercentComplete = 0f
                }, store: false);
            }
        }

        /// <summary>
        /// Called when the SSTV monitor has decoded more scan lines (progress update).
        /// </summary>
        private void OnSstvDecodingProgress(object sender, SstvDecodingProgressEventArgs e)
        {
            // Extract a partial image from the monitor to show progressive decoding
            Bitmap partialImage = null;
            lock (_sstvLock)
            {
                if (_sstvMonitor != null)
                {
                    partialImage = _sstvMonitor.GetPartialImage();
                }
            }

            // Dispatch partial TextReady with the partial image so the UI can display it
            string progressText = $"Receiving {e.ModeName}... {e.PercentComplete:F0}%";
            string channelName = _currentChannelName;

            lock (_historyLock)
            {
                if (_currentSstvEntry != null)
                {
                    _currentSstvEntry.Text = progressText;
                }
            }

            DispatchTextReady(progressText, channelName, _sstvStartTime, false, true, VoiceTextEncodingType.Picture, partialImage: partialImage);

            if (_targetDeviceId > 0)
            {
                broker.Dispatch(_targetDeviceId, "SstvDecodingState", new
                {
                    Active = true,
                    ModeName = e.ModeName,
                    Width = 0,
                    Height = e.TotalLines,
                    PercentComplete = e.PercentComplete
                }, store: false);
            }
        }

        /// <summary>
        /// Called when the SSTV monitor has completed decoding an image.
        /// Saves the image to disk and adds it to the voice text history.
        /// </summary>
        private void OnSstvDecodingComplete(object sender, SstvDecodingCompleteEventArgs e)
        {
            broker.LogInfo($"[VoiceHandler] SSTV image decoded: {e.ModeName} ({e.Width}x{e.Height})");

            if (_targetDeviceId > 0)
            {
                broker.Dispatch(_targetDeviceId, "SstvDecodingState", new
                {
                    Active = false,
                    ModeName = e.ModeName,
                    Width = e.Width,
                    Height = e.Height,
                    PercentComplete = 100f
                }, store: false);
            }

            _sstvDecoding = false;

            // Resume speech-to-text after SSTV decoding
            if (_speechToTextEngine != null)
            {
                try { _speechToTextEngine.StartVoiceSegment(); }
                catch (Exception ex) { broker.LogError($"[VoiceHandler] Error resuming speech-to-text after SSTV: {ex.Message}"); }
            }

            if (e.Image == null)
            {
                // SSTV decoding failed - finalize with error
                lock (_historyLock) { _currentSstvEntry = null; }
                DispatchTextReady($"{e.ModeName} - Reception failed", _currentChannelName, _sstvStartTime, true, true, VoiceTextEncodingType.Picture);
                return;
            }

            try
            {
                // Save the image to the SSTV folder
                DateTime now = _sstvStartTime;
                string safeMode = SanitizeFilename(e.ModeName ?? "Unknown");
                string filename = $"SSTV_{now:yyyy-MM-dd}_{now:HH-mm-ss}_{safeMode}.png";
                string fullPath = Path.Combine(_sstvImagesPath, filename);

                e.Image.Save(fullPath, ImageFormat.Png);
                e.Image.Dispose();

                broker.LogInfo($"[VoiceHandler] SSTV image saved: {filename}");

                // Finalize the partial entry into the decoded text history
                string channelName = _currentChannelName;
                lock (_historyLock)
                {
                    if (_currentSstvEntry != null)
                    {
                        _currentSstvEntry.Text = e.ModeName;
                        _currentSstvEntry.Filename = filename;
                        _decodedTextHistory.Add(_currentSstvEntry);

                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }

                        _currentSstvEntry = null;
                    }
                    else
                    {
                        // Fallback: create entry directly
                        var entry = new DecodedTextEntry
                        {
                            Text = e.ModeName,
                            Channel = channelName,
                            Time = now,
                            IsReceived = true,
                            Encoding = VoiceTextEncodingType.Picture,
                            Filename = filename
                        };
                        _decodedTextHistory.Add(entry);

                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }
                    }
                }

                SaveVoiceTextHistory();
                DispatchDecodedTextHistory();

                // Dispatch completed TextReady event for the decoded picture
                DispatchTextReady(e.ModeName, channelName, now, true, true,
                    VoiceTextEncodingType.Picture, filename: filename);
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error saving SSTV image: {ex.Message}");
                e.Image?.Dispose();
                lock (_historyLock) { _currentSstvEntry = null; }
            }
        }

        /// <summary>
        /// Handles AudioDataAvailable events from the Data Broker.
        /// Expected data format: { Data: byte[], Offset: int, Length: int, ChannelName: string, Transmit: bool }
        /// </summary>
        private void OnAudioDataAvailable(int deviceId, string name, object data)
        {
            // Check if we need to process this audio (for speech-to-text, recording, or SSTV)
            bool needsSpeechToText = _enabled && _speechToTextEnabled && deviceId == _targetDeviceId && _speechToTextEngine != null && !_sstvDecoding;
            bool needsRecording = _recordingEnabled && deviceId == _targetDeviceId;
            bool needsSstv = _enabled && deviceId == _targetDeviceId && _sstvMonitor != null;

            if (!needsSpeechToText && !needsRecording && !needsSstv)
            {
                return;
            }

            if (data == null) return;

            try
            {
                // Use reflection to extract properties from the anonymous object
                var dataType = data.GetType();
                var dataProp = dataType.GetProperty("Data");
                var offsetProp = dataType.GetProperty("Offset");
                var lengthProp = dataType.GetProperty("Length");
                var channelNameProp = dataType.GetProperty("ChannelName");
                var transmitProp = dataType.GetProperty("Transmit");
                var mutedProp = dataType.GetProperty("Muted");

                if (dataProp == null || offsetProp == null || lengthProp == null || channelNameProp == null || transmitProp == null)
                {
                    return;
                }

                byte[] audioData = (byte[])dataProp.GetValue(data);
                int offset = (int)offsetProp.GetValue(data);
                int length = (int)lengthProp.GetValue(data);
                string channelName = (string)channelNameProp.GetValue(data);
                bool transmit = (bool)transmitProp.GetValue(data);
                bool muted = mutedProp != null && (bool)mutedProp.GetValue(data);

                // Only process received audio. Muted audio is ok.
                if (transmit)
                {
                    return;
                }

                // Update current channel name
                _currentChannelName = channelName;

                // Process the audio chunk for speech-to-text
                if (needsSpeechToText)
                {
                    ProcessAudioChunk(audioData, offset, length, channelName);
                }

                // Process through SSTV monitor for auto-detection
                if (needsSstv)
                {
                    SstvMonitor monitor;
                    lock (_sstvLock) { monitor = _sstvMonitor; }
                    monitor?.ProcessPcm16(audioData, offset, length);
                }

                // Write audio data to recording file
                if (needsRecording)
                {
                    WriteAudioToRecording(audioData, offset, length);
                }
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error processing audio data: {ex.Message}");
            }
        }

        /// <summary>
        /// Writes audio data to the current recording file.
        /// </summary>
        private void WriteAudioToRecording(byte[] audioData, int offset, int length)
        {
            lock (_recordingLock)
            {
                if (_currentRecordingWriter == null) return;

                try
                {
                    _currentRecordingWriter.Write(audioData, offset, length);
                }
                catch (Exception ex)
                {
                    broker.LogError($"[VoiceHandler] Error writing to recording: {ex.Message}");
                }
            }
        }

        /// <summary>
        /// Processes an audio chunk through the speech-to-text engine.
        /// </summary>
        private void ProcessAudioChunk(byte[] audioData, int offset, int length, string channelName)
        {
            if (_speechToTextEngine == null)
            {
                return;
            }

            try
            {
                _speechToTextEngine.ProcessAudioChunk(audioData, offset, length, channelName);
                _maxVoiceDecodeTime += length;

                // Reset if we've been processing for too long (prevent memory buildup)
                if (_maxVoiceDecodeTime > MaxVoiceDecodeTimeLimit)
                {
                    _speechToTextEngine.ResetVoiceSegment();
                    _maxVoiceDecodeTime = 0;
                    broker.LogInfo("[VoiceHandler] Voice segment reset due to time limit");
                }
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error in ProcessAudioChunk: {ex.Message}");
            }
        }

        /// <summary>
        /// Handles debug messages from the WhisperEngine.
        /// </summary>
        private void OnWhisperDebugMessage(string msg)
        {
            broker.LogInfo($"[VoiceHandler/Whisper] {msg}");
        }

        /// <summary>
        /// Handles text ready events from the WhisperEngine.
        /// </summary>
        private void OnWhisperTextReady(string text, string channel, DateTime time, bool completed)
        {
            // Update the decoded text history (received voice)
            UpdateDecodedTextHistory(text, channel, time, completed, true, VoiceTextEncodingType.Voice);

            // Dispatch the individual TextReady event
            DispatchTextReady(text, channel, time, completed);
        }

        /// <summary>
        /// Adds a transmitted text entry to the history.
        /// </summary>
        private void AddTransmittedTextToHistory(string text, string channel, VoiceTextEncodingType encoding, string source = null, string destination = null, string filename = null)
        {
            lock (_historyLock)
            {
                var entry = new DecodedTextEntry
                {
                    Text = text,
                    Channel = channel,
                    Time = DateTime.Now,
                    IsReceived = false,
                    Encoding = encoding,
                    Source = source,
                    Destination = destination,
                    Filename = filename
                };
                _decodedTextHistory.Add(entry);

                // Trim if exceeds max size
                while (_decodedTextHistory.Count > MaxHistorySize)
                {
                    _decodedTextHistory.RemoveAt(0);
                }
            }

            // Save to file and dispatch updated history
            SaveVoiceTextHistory();
            DispatchDecodedTextHistory();

            // Dispatch a TextReady event for transmitted text so UI updates
            DispatchTextReady(text, channel, DateTime.Now, true, false, encoding, source: source, destination: destination, filename: filename);
        }

        /// <summary>
        /// Updates the decoded text history with new text.
        /// </summary>
        private void UpdateDecodedTextHistory(string text, string channel, DateTime time, bool completed, bool isReceived, VoiceTextEncodingType encoding)
        {
            lock (_historyLock)
            {
                if (!completed)
                {
                    // In-progress text: update or create current entry
                    if (_currentEntry == null)
                    {
                        _currentEntry = new DecodedTextEntry();
                    }
                    _currentEntry.Text = text;
                    _currentEntry.Channel = channel;
                    _currentEntry.Time = time;
                    _currentEntry.IsReceived = isReceived;
                    _currentEntry.Encoding = encoding;
                }
                else
                {
                    // Completed text: finalize the entry
                    if (_currentEntry != null)
                    {
                        // Update with final values
                        _currentEntry.Text = text;
                        _currentEntry.Channel = channel;
                        _currentEntry.Time = time;
                        _currentEntry.IsReceived = isReceived;
                        _currentEntry.Encoding = encoding;

                        // Add to history
                        _decodedTextHistory.Add(_currentEntry);

                        // Trim if exceeds max size
                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }

                        _currentEntry = null;
                    }
                    else
                    {
                        // No current entry, create and add directly
                        var entry = new DecodedTextEntry
                        {
                            Text = text,
                            Channel = channel,
                            Time = time,
                            IsReceived = isReceived,
                            Encoding = encoding
                        };
                        _decodedTextHistory.Add(entry);

                        // Trim if exceeds max size
                        while (_decodedTextHistory.Count > MaxHistorySize)
                        {
                            _decodedTextHistory.RemoveAt(0);
                        }
                    }

                    // Save to file and dispatch updated history
                    SaveVoiceTextHistory();
                    DispatchDecodedTextHistory();
                    DispatchCurrentEntry();
                }
            }

            // Dispatch current entry state (whether it's set or cleared)
            if (!completed)
            {
                DispatchCurrentEntry();
            }
        }

        /// <summary>
        /// Handles the ClearVoiceText command to clear all decoded text history.
        /// </summary>
        private void OnClearVoiceText(int deviceId, string name, object data)
        {
            lock (_historyLock)
            {
                _decodedTextHistory.Clear();
                _currentEntry = null;
            }

            // Save empty history to file
            SaveVoiceTextHistory();
            DispatchDecodedTextHistory();
            DispatchCurrentEntry();

            // Notify all UI components to clear their voice text displays
            broker.Dispatch(1, "VoiceTextCleared", null, store: false);

            broker.LogInfo("[VoiceHandler] Decoded text history cleared");
        }

        /// <summary>
        /// Loads the voice text history from the JSON file.
        /// </summary>
        private void LoadVoiceTextHistory()
        {
            string filePath = Path.Combine(_appDataPath, VoiceTextFileName);

            try
            {
                if (File.Exists(filePath))
                {
                    string json = File.ReadAllText(filePath);
                    if (!string.IsNullOrWhiteSpace(json))
                    {
                        var entries = JsonSerializer.Deserialize<List<DecodedTextEntry>>(json);
                        if (entries != null)
                        {
                            lock (_historyLock)
                            {
                                _decodedTextHistory.Clear();
                                _decodedTextHistory.AddRange(entries);

                                // Trim if exceeds max size (in case file was manually edited)
                                while (_decodedTextHistory.Count > MaxHistorySize)
                                {
                                    _decodedTextHistory.RemoveAt(0);
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception)
            {
                // Ignore load errors - start with empty history
            }

            // Mark history as loaded and dispatch the loaded event
            _voiceTextHistoryLoaded = true;
            DispatchDecodedTextHistory();
            DispatchVoiceTextHistoryLoaded();
        }

        /// <summary>
        /// Dispatches the VoiceTextHistoryLoaded event to notify subscribers that history is ready.
        /// </summary>
        private void DispatchVoiceTextHistoryLoaded()
        {
            broker.Dispatch(1, "VoiceTextHistoryLoaded", _voiceTextHistoryLoaded, store: true);
        }

        /// <summary>
        /// Saves the voice text history to the JSON file.
        /// </summary>
        private void SaveVoiceTextHistory()
        {
            string filePath = Path.Combine(_appDataPath, VoiceTextFileName);

            try
            {
                List<DecodedTextEntry> entriesToSave;
                lock (_historyLock)
                {
                    entriesToSave = new List<DecodedTextEntry>(_decodedTextHistory);
                }

                var options = new JsonSerializerOptions { WriteIndented = true };
                string json = JsonSerializer.Serialize(entriesToSave, options);
                File.WriteAllText(filePath, json);
            }
            catch (Exception)
            {
                // Ignore save errors
            }
        }

        /// <summary>
        /// Dispatches the decoded text history to the Data Broker.
        /// </summary>
        private void DispatchDecodedTextHistory()
        {
            List<DecodedTextEntry> historyCopy;
            lock (_historyLock)
            {
                // Create a copy of the list for dispatch
                historyCopy = new List<DecodedTextEntry>(_decodedTextHistory);
            }

            // Store under device ID 1 (global) since only one radio can do speech-to-text at a time
            broker.Dispatch(1, "DecodedTextHistory", historyCopy, store: true);
        }

        /// <summary>
        /// Dispatches the current entry (in-progress text) to the Data Broker.
        /// This allows new subscribers to see any text currently being decoded.
        /// </summary>
        private void DispatchCurrentEntry()
        {
            DecodedTextEntry entryCopy = null;
            lock (_historyLock)
            {
                if (_currentEntry != null)
                {
                    entryCopy = new DecodedTextEntry
                    {
                        Text = _currentEntry.Text,
                        Channel = _currentEntry.Channel,
                        Time = _currentEntry.Time
                    };
                }
            }

            // Store under device ID 1 (global) - null means no current entry
            broker.Dispatch(1, "CurrentDecodedTextEntry", entryCopy, store: true);
        }

        /// <summary>
        /// Handles processing voice state changes from the WhisperEngine.
        /// </summary>
        private void OnWhisperProcessingVoice(bool processing)
        {
            DispatchProcessingVoice(_speechToTextEngine != null, processing);
        }

        /// <summary>
        /// Dispatches a TextReady event to the Data Broker.
        /// </summary>
        private void DispatchTextReady(string text, string channel, DateTime time, bool completed, bool isReceived = true, VoiceTextEncodingType encoding = VoiceTextEncodingType.Voice, double latitude = 0, double longitude = 0, string source = null, string destination = null, string filename = null, int duration = 0, Bitmap partialImage = null)
        {
            if (_targetDeviceId > 0)
            {
                broker.Dispatch(_targetDeviceId, "TextReady", new
                {
                    Text = text,
                    Channel = channel,
                    Time = time,
                    Completed = completed,
                    IsReceived = isReceived,
                    Encoding = encoding,
                    Latitude = latitude,
                    Longitude = longitude,
                    Source = source,
                    Destination = destination,
                    Filename = filename,
                    Duration = duration,
                    PartialImage = partialImage
                }, store: false);
            }
        }

        /// <summary>
        /// Dispatches a ProcessingVoice event to the Data Broker.
        /// </summary>
        private void DispatchProcessingVoice(bool listening, bool processing)
        {
            if (_targetDeviceId > 0)
            {
                broker.Dispatch(_targetDeviceId, "ProcessingVoice", new
                {
                    Listening = listening,
                    Processing = processing
                }, store: false);
            }
        }

        /// <summary>
        /// Dispatches the current VoiceHandler state to the Data Broker on device 1.
        /// This indicates which radio (if any) is being monitored for speech-to-text.
        /// </summary>
        private void DispatchVoiceHandlerState()
        {
            broker.Dispatch(1, "VoiceHandlerState", new
            {
                Enabled = _enabled,
                TargetDeviceId = _targetDeviceId,
                Language = _voiceLanguage,
                Model = _voiceModel,
                EngineReady = _speechToTextEngine != null
            }, store: true);
        }

        /// <summary>
        /// Disposes the VoiceHandler and cleans up all resources.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        /// <summary>
        /// Disposes the VoiceHandler.
        /// </summary>
        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    broker?.LogInfo("[VoiceHandler] Voice Handler disposing");

                    // Disable and clean up speech-to-text
                    if (_enabled)
                    {
                        Disable();
                    }

                    // Clean up SSTV monitor
                    CleanupSstvMonitor();

                    // Clean up text-to-speech resources
                    lock (_ttsLock)
                    {
                        if (_synthesizer != null)
                        {
                            try
                            {
                                _synthesizer.SpeakCompleted -= Synthesizer_SpeakCompleted;
                                _synthesizer.Dispose();
                            }
                            catch (Exception) { }
                            _synthesizer = null;
                        }
                        
                        if (_ttsAudioStream != null)
                        {
                            try { _ttsAudioStream.Dispose(); }
                            catch (Exception) { }
                            _ttsAudioStream = null;
                        }
                        
                        _ttsAvailable = false;
                    }

                    // Dispose the broker client
                    broker?.Dispose();
                }

                _disposed = true;
            }
        }
    }
}
