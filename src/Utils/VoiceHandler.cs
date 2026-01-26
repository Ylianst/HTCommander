/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using HTCommander.radio;

namespace HTCommander
{
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

        /// <summary>
        /// Initializes the VoiceHandler and subscribes to Data Broker events.
        /// </summary>
        public VoiceHandler()
        {
            broker = new DataBrokerClient();

            // Subscribe to VoiceHandlerEnable command (from device 0 or any device)
            broker.Subscribe(0, "VoiceHandlerEnable", OnVoiceHandlerEnable);

            // Subscribe to VoiceHandlerDisable command
            broker.Subscribe(0, "VoiceHandlerDisable", OnVoiceHandlerDisable);

            // Subscribe to AudioDataAvailable from all devices (we'll filter by target device)
            broker.Subscribe(DataBroker.AllDevices, "AudioDataAvailable", OnAudioDataAvailable);

            // Subscribe to radio State changes from all devices to detect disconnection
            broker.Subscribe(DataBroker.AllDevices, "State", OnRadioStateChanged);

            // Dispatch initial state (not monitoring any radio)
            DispatchVoiceHandlerState();

            broker.LogInfo("[VoiceHandler] Voice Handler initialized");
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

            _enabled = false;
            _targetDeviceId = -1;

            // Clean up the speech engine
            CleanupSpeechEngine();

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
            DispatchTextReady(text, channel, time, completed);
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
        private void DispatchTextReady(string text, string channel, DateTime time, bool completed)
        {
            if (_targetDeviceId > 0)
            {
                broker.Dispatch(_targetDeviceId, "TextReady", new
                {
                    Text = text,
                    Channel = channel,
                    Time = time,
                    Completed = completed
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
        /// Dispatches the current VoiceHandler state to the Data Broker on device 0.
        /// This indicates which radio (if any) is being monitored for speech-to-text.
        /// </summary>
        private void DispatchVoiceHandlerState()
        {
            broker.Dispatch(0, "VoiceHandlerState", new
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

                    // Disable and clean up
                    if (_enabled)
                    {
                        Disable();
                    }

                    // Dispose the broker client
                    broker?.Dispose();
                }

                _disposed = true;
            }
        }
    }
}
