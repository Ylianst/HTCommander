/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Speech.Synthesis;
using System.Speech.AudioFormat;
using HTCommander.radio;
using static HTCommander.radio.MorseCodeEngine;

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
        BSS
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

            // Subscribe to AudioDataEnd from all devices to flush speech-to-text on audio segment end
            broker.Subscribe(DataBroker.AllDevices, "AudioDataEnd", OnAudioDataEnd);

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

            // Subscribe to Voice setting changes (device 0 stores global settings)
            broker.Subscribe(0, "Voice", OnVoiceChanged);

            // Subscribe to UniqueDataFrame events from all devices for AX.25 packet logging
            broker.Subscribe(DataBroker.AllDevices, "UniqueDataFrame", OnUniqueDataFrame);

            // Subscribe to Chat command from all devices for BSS chat message transmission
            // Similar to Speak: device 1 uses voice-enabled radio, device 100+ uses that device directly
            broker.Subscribe(DataBroker.AllDevices, "Chat", OnChat);

            // Initialize text-to-speech synthesizer
            InitializeTextToSpeech();

            // Dispatch initial state (not monitoring any radio)
            DispatchVoiceHandlerState();

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

                // Create a DecodedTextEntry for the BSS packet
                string bssText = $"{bssPacket.Callsign}: {bssPacket.Message}";
                if (bssPacket.Destination != null)
                {
                    bssText = $"{bssPacket.Callsign} > {bssPacket.Destination}: {bssPacket.Message}";
                }
                if (!string.IsNullOrEmpty(bssText))
                {
                    lock (_historyLock)
                    {
                        var entry = new DecodedTextEntry
                        {
                            Text = bssText,
                            Channel = frame.channel_name ?? "",
                            Time = frame.time,
                            IsReceived = frame.incoming,
                            Encoding = VoiceTextEncodingType.BSS
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

                    // Dispatch a TextReady event for the BSS packet
                    DispatchTextReady(bssText, frame.channel_name ?? "", frame.time, true, frame.incoming, VoiceTextEncodingType.BSS);
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

            // Format the text as: "Source > Destination: Message"
            string formattedText = $"{source} > {destination}: {messageText ?? ""}";

            // Add to history as a received AX.25 entry
            lock (_historyLock)
            {
                var entry = new DecodedTextEntry
                {
                    Text = formattedText,
                    Channel = frame.channel_name ?? "",
                    Time = frame.time,
                    IsReceived = true,
                    Encoding = VoiceTextEncodingType.AX25
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
            DispatchTextReady(formattedText, frame.channel_name ?? "", frame.time, true, true, VoiceTextEncodingType.AX25);
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
                AddTransmittedTextToHistory(message, channelName, VoiceTextEncodingType.BSS);
                
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
        /// Handles the AudioDataEnd event - forces speech-to-text to process remaining audio.
        /// This is called when the radio signals the end of an audio segment.
        /// </summary>
        private void OnAudioDataEnd(int deviceId, string name, object data)
        {
            // Only care about audio end events for the radio we're monitoring
            if (deviceId != _targetDeviceId || !_enabled || _speechToTextEngine == null)
            {
                return;
            }

            try
            {
                // Force the speech-to-text engine to process any remaining audio
                _speechToTextEngine.CompleteVoiceSegment();
                _maxVoiceDecodeTime = 0;
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error in OnAudioDataEnd: {ex.Message}");
            }
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

            // Initialize the speech-to-text engine
            InitializeSpeechEngine();

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
        /// Handles AudioDataAvailable events from the Data Broker.
        /// Expected data format: { Data: byte[], Offset: int, Length: int, ChannelName: string, Transmit: bool }
        /// </summary>
        private void OnAudioDataAvailable(int deviceId, string name, object data)
        {
            if (!_enabled || deviceId != _targetDeviceId || _speechToTextEngine == null || data == null)
            {
                return;
            }

            try
            {
                // Use reflection to extract properties from the anonymous object
                var dataType = data.GetType();
                var dataProp = dataType.GetProperty("Data");
                var offsetProp = dataType.GetProperty("Offset");
                var lengthProp = dataType.GetProperty("Length");
                var channelNameProp = dataType.GetProperty("ChannelName");
                var transmitProp = dataType.GetProperty("Transmit");

                if (dataProp == null || offsetProp == null || lengthProp == null || channelNameProp == null || transmitProp == null)
                {
                    return;
                }

                byte[] audioData = (byte[])dataProp.GetValue(data);
                int offset = (int)offsetProp.GetValue(data);
                int length = (int)lengthProp.GetValue(data);
                string channelName = (string)channelNameProp.GetValue(data);
                bool transmit = (bool)transmitProp.GetValue(data);

                // Only process received audio (not transmitted)
                if (transmit)
                {
                    return;
                }

                // Update current channel name
                _currentChannelName = channelName;

                // Process the audio chunk
                ProcessAudioChunk(audioData, offset, length, channelName);
            }
            catch (Exception ex)
            {
                broker.LogError($"[VoiceHandler] Error processing audio data: {ex.Message}");
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
        private void AddTransmittedTextToHistory(string text, string channel, VoiceTextEncodingType encoding)
        {
            lock (_historyLock)
            {
                var entry = new DecodedTextEntry
                {
                    Text = text,
                    Channel = channel,
                    Time = DateTime.Now,
                    IsReceived = false,
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

            // Dispatch a TextReady event for transmitted text so UI updates
            DispatchTextReady(text, channel, DateTime.Now, true, false, encoding);
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
        private void DispatchTextReady(string text, string channel, DateTime time, bool completed, bool isReceived = true, VoiceTextEncodingType encoding = VoiceTextEncodingType.Voice)
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
                    Encoding = encoding
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
