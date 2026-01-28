/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Windows.Forms;
using System.Collections.Generic;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using NAudio.Wave;

namespace HTCommander
{
    public partial class RadioAudioForm : Form, IMMNotificationClient, IAudioSessionEventsHandler
    {
        private MMDeviceEnumerator deviceEnumerator = new MMDeviceEnumerator();
        private DataBrokerClient broker;
        private int deviceId;
        private MMDevice outputDevice;
        private MMDevice inputDevice;
        private AudioSessionControl sessionControl;
        private string SelectedOutputDeviceId = "";
        private string SelectedInputDeviceId = "";
        public bool MicrophoneTransmit = false;
        
        // Microphone capture - always active for amplitude display
        private WasapiCapture wasapiCapture = null;
        private WaveFormat captureWaveFormat = null;
        private bool isCapturing = false;
        private bool isTransmitting = false;
        private int inputBoostValue = 0; // Cached boost value to avoid cross-thread access

        public int Volume { get { return volumeTrackBar.Value; } set { volumeTrackBar.Value = value; } }

        public RadioAudioForm(int deviceId)
        {
            InitializeComponent();
            this.deviceId = deviceId;

            // Create the broker for subscribing to events and accessing settings
            broker = new DataBrokerClient();

            // Set initial title with friendly name
            UpdateTitle();

            // Load settings from the broker (per-device settings)
            SelectedOutputDeviceId = broker.GetValue<string>(deviceId, "OutputAudioDevice", "");
            SelectedInputDeviceId = broker.GetValue<string>(deviceId, "InputAudioDevice", "");

            deviceEnumerator.RegisterEndpointNotificationCallback(this);
            LoadAudioDevices();
            transmitButton.Image = microphoneImageList.Images[0];
            recordButton.Image = microphoneImageList.Images[6];

            // Load volume settings
            outputTrackBar.Value = broker.GetValue<int>(deviceId, "OutputAudioVolume", 100);
            broker.Dispatch(deviceId, "SetOutputVolume", outputTrackBar.Value);
            inputTrackBar.Value = broker.GetValue<int>(deviceId, "InputAudioVolume", 100);
            if (inputDevice != null) { inputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = inputTrackBar.Value / 100f; }

            // Set output audio device
            broker.Dispatch(deviceId, "SetOutputAudioDevice", SelectedOutputDeviceId);
            UpdateInfo();

            inputBoostTrackBar.Value = broker.GetValue<int>(deviceId, "InputAudioBoost", 0);
            inputBoostValue = inputBoostTrackBar.Value;
            spacebarPTTToolStripMenuItem.Checked = (broker.GetValue<int>(0, "SpacebarPTT", 0) != 0);

            // Subscribe to radio state changes
            broker.Subscribe(deviceId, "State", OnRadioStateChanged);
            broker.Subscribe(deviceId, "AudioState", OnAudioStateChanged);
            broker.Subscribe(deviceId, "Settings", OnSettingsChanged);
            broker.Subscribe(deviceId, "Volume", OnVolumeLevelChanged);
            broker.Subscribe(deviceId, "Recording", OnRecordingStateChanged);
            broker.Subscribe(deviceId, "OutputAmplitude", OnOutputAmplitudeChanged);
            broker.Subscribe(0, "AllowTransmit", OnAllowTransmitChanged);
            broker.Subscribe(deviceId, "FriendlyName", OnFriendlyNameChanged);

            this.FormClosed += (s, e) => {
                StopMicrophoneCapture();
                broker?.Dispose();
            };

            // Start continuous microphone capture for amplitude display (after inputDevice is set)
            StartMicrophoneCapture();
        }

        private void OnRadioStateChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnRadioStateChanged(devId, name, data))); return; }
            
            // Check if the radio has disconnected
            string stateStr = data as string;
            if (stateStr == "Disconnected")
            {
                // Radio disconnected, close the form (bypass the hide-on-close behavior)
                this.FormClosing -= RadioVolumeForm_FormClosing;
                this.Close();
                return;
            }
            
            UpdateInfo();
        }

        private void OnAudioStateChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnAudioStateChanged(devId, name, data))); return; }
            UpdateInfo();
        }

        private void OnSettingsChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnSettingsChanged(devId, name, data))); return; }
            if (data is RadioSettings settings)
            {
                squelchTrackBar.Value = settings.squelch_level;
            }
            UpdateInfo();
        }

        private void OnVolumeLevelChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnVolumeLevelChanged(devId, name, data))); return; }
            if (data is int volume)
            {
                volumeTrackBar.Value = Math.Min(Math.Max(volume, volumeTrackBar.Minimum), volumeTrackBar.Maximum);
            }
        }

        private void OnRecordingStateChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnRecordingStateChanged(devId, name, data))); return; }
            bool recording = data is bool && (bool)data;
            recordButton.Image = recording ? microphoneImageList.Images[7] : microphoneImageList.Images[6];
        }

        private void OnOutputAmplitudeChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnOutputAmplitudeChanged(devId, name, data))); return; }
            float amplitude = 0f;
            if (data is float f) { amplitude = f; }
            else if (data is double d) { amplitude = (float)d; }
            else if (data is int i) { amplitude = i / 100f; }
            outputAmplitudeHistoryBar.ProcessAudioData(amplitude);
        }

        private void OnAllowTransmitChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnAllowTransmitChanged(devId, name, data))); return; }
            UpdateInfo();
        }

        private void OnFriendlyNameChanged(int devId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnFriendlyNameChanged(devId, name, data))); return; }
            UpdateTitle();
        }

        private void UpdateTitle()
        {
            string friendlyName = broker.GetValue<string>(deviceId, "FriendlyName", null);
            if (string.IsNullOrEmpty(friendlyName))
            {
                this.Text = "Audio Controls";
            }
            else
            {
                this.Text = "Audio Controls - " + friendlyName;
            }
        }

        private void RadioVolumeForm_Load(object sender, EventArgs e)
        {
            pollTimer_Tick(this, null);
        }

        private delegate void AudioEndpointVolumeNotificationDelegate(AudioVolumeNotificationData data);
        private void AudioEndpointVolume_OnVolumeNotification(AudioVolumeNotificationData data)
        {
            if (InvokeRequired) { BeginInvoke(new AudioEndpointVolumeNotificationDelegate(AudioEndpointVolume_OnVolumeNotification), data); return; }
            masterVolumeTrackBar.Value = (int)(outputDevice.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
            masterMuteButton.ImageIndex = outputDevice.AudioEndpointVolume.Mute ? 0 : 1;
        }
        private void AudioEndpointVolume_OnInputVolumeNotification(AudioVolumeNotificationData data)
        {
            if (InvokeRequired) { BeginInvoke(new AudioEndpointVolumeNotificationDelegate(AudioEndpointVolume_OnInputVolumeNotification), data); return; }
            inputTrackBar.Value = (int)(inputDevice.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
        }

        public void UpdateInfo()
        {
            // Don't update if the form is disposed or disposing
            if (IsDisposed || Disposing) return;

            string stateStr = broker.GetValue<string>(deviceId, "State", "Disconnected");
            bool isConnected = stateStr == "Connected";
            bool audioEnabled = broker.GetValue<bool>(deviceId, "AudioState", false);
            bool allowTransmit = broker.GetValue<bool>(0, "AllowTransmit", false);

            pollTimer.Enabled = Visible;
            audioButton.Image = audioEnabled ? microphoneImageList.Images[4] : microphoneImageList.Images[3];
            outputTrackBar.Value = broker.GetValue<int>(deviceId, "OutputAudioVolume", 100);
            inputGraphButton.Enabled = inputComboBox.Enabled = inputTrackBar.Enabled = inputBoostTrackBar.Enabled = allowTransmit && (inputDevice != null);
            transmitButton.Visible = allowTransmit;

            if (isConnected)
            {
                volumeTrackBar.Enabled = true;
                audioButton.Enabled = true;
                recordButton.Enabled = audioEnabled;
                transmitButton.Enabled = audioEnabled && allowTransmit && (inputDevice != null);
                squelchTrackBar.Enabled = true;
                
                // Get squelch from settings
                var settings = broker.GetValue<RadioSettings>(deviceId, "Settings", null);
                if (settings != null) { squelchTrackBar.Value = settings.squelch_level; }
            }
            else
            {
                audioButton.Enabled = false;
                recordButton.Enabled = false;
                transmitButton.Enabled = false;
                volumeTrackBar.Enabled = false;
                squelchTrackBar.Enabled = false;
            }

            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)outputComboBox.SelectedItem;
            if (selected != null)
            {
                string selectedId = selected.Value;
                MMDevice selectedDevice = GetDeviceById(selectedId, DataFlow.Render);
                if (selectedDevice != null)
                {
                    masterVolumeTrackBar.Value = (int)(selectedDevice.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
                    try
                    {
                        if (outputDevice != null) { masterMuteButton.ImageIndex = outputDevice.AudioEndpointVolume.Mute ? 0 : 1; } else { masterMuteButton.ImageIndex = 0; }
                    }
                    catch (Exception) { }
                }
            }
        }

        public void SetAudio(bool enabled)
        {
            bool audioEnabled = broker.GetValue<bool>(deviceId, "AudioState", false);
            audioButton.Image = audioEnabled ? microphoneImageList.Images[4] : microphoneImageList.Images[3];
        }

        private delegate void LoadAudioDevicesDelegate(bool forceUpdate = false);

        private void LoadAudioDevices(bool forceUpdate = false)
        {
            if (InvokeRequired) { BeginInvoke(new LoadAudioDevicesDelegate(LoadAudioDevices), forceUpdate); return; }

            if (forceUpdate)
            {
                outputComboBox.Items.Clear();
                inputComboBox.Items.Clear();
            }

            // Load output devices (playback)
            Dictionary<string, Utils.ComboBoxItem> listDeviceId = new Dictionary<string, Utils.ComboBoxItem>();
            if (outputComboBox.Items.Count == 0)
            {
                MMDevice defaultOutputDevice = null;
                try { defaultOutputDevice = deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia); } catch (Exception) { }
                if (defaultOutputDevice != null) { outputComboBox.Items.Add(new Utils.ComboBoxItem("", "Default (" + FixDeviceName(defaultOutputDevice.FriendlyName) + ")")); }
            }
            foreach (Utils.ComboBoxItem e in outputComboBox.Items) { listDeviceId.Add(e.Value, e); }
            foreach (MMDevice device in deviceEnumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
            {
                if (listDeviceId.ContainsKey(device.ID))
                {
                    listDeviceId.Remove(device.ID);
                }
                else
                {
                    outputComboBox.Items.Add(new Utils.ComboBoxItem(device.ID, FixDeviceName(device.FriendlyName)));
                }
            }
            foreach (Utils.ComboBoxItem e in listDeviceId.Values) { if (e.Value != "") { outputComboBox.Items.Remove(e); } }

            // Select the user selected output device
            SelectedOutputDeviceId = SetSelectedDevice(outputComboBox, SelectedOutputDeviceId);
            broker.Dispatch(deviceId, "OutputAudioDevice", SelectedOutputDeviceId);
            MMDevice xoutputDevice = GetDeviceById(SelectedOutputDeviceId, DataFlow.Render);
            if (xoutputDevice != outputDevice)
            {
                if (outputDevice != null) { outputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnVolumeNotification; }
                outputDevice = xoutputDevice;
                if (outputDevice != null) { outputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnVolumeNotification; }
            }

            // Load input devices (recording)
            listDeviceId.Clear();
            if (inputComboBox.Items.Count == 0)
            {
                MMDevice defaultInputDevice = null;
                try { defaultInputDevice = deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Multimedia); } catch (Exception) { }
                if (defaultInputDevice != null) { inputComboBox.Items.Add(new Utils.ComboBoxItem("", "Default (" + FixDeviceName(defaultInputDevice.FriendlyName) + ")")); }
            }
            foreach (Utils.ComboBoxItem e in inputComboBox.Items) { listDeviceId.Add(e.Value, e); }
            foreach (MMDevice device in deviceEnumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                if (listDeviceId.ContainsKey(device.ID))
                {
                    listDeviceId.Remove(device.ID);
                }
                else
                {
                    inputComboBox.Items.Add(new Utils.ComboBoxItem(device.ID, FixDeviceName(device.FriendlyName)));
                }
            }
            foreach (Utils.ComboBoxItem e in listDeviceId.Values) { if (e.Value != "") { inputComboBox.Items.Remove(e); } }

            // Select the user selected output device
            SelectedInputDeviceId = SetSelectedDevice(inputComboBox, SelectedInputDeviceId);
            broker.Dispatch(deviceId, "InputAudioDevice", SelectedInputDeviceId);
            MMDevice xinputDevice = GetDeviceById(SelectedInputDeviceId, DataFlow.Capture);
            if (xinputDevice != inputDevice)
            {
                if (inputDevice != null) { inputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnInputVolumeNotification; }
                inputDevice = xinputDevice;
                if (inputDevice != null) { inputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnInputVolumeNotification; }
            }
        }

        private string SetSelectedDevice(ComboBox comboBox, string deviceIdToSelect)
        {
            for (int i = 0; i < comboBox.Items.Count; i++)
            {
                if (((Utils.ComboBoxItem)comboBox.Items[i]).Value == deviceIdToSelect) { comboBox.SelectedIndex = i; return deviceIdToSelect; }
            }
            if (comboBox.Items.Count > 0) { comboBox.SelectedIndex = 0; }
            return "";
        }

        private void outputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)outputComboBox.SelectedItem;
            if (SelectedOutputDeviceId == selected.Value) return; // No change
            MMDevice xoutputDevice = GetDeviceById(selected.Value, DataFlow.Render);
            if (xoutputDevice != null && outputDevice != null && xoutputDevice.ID == outputDevice.ID)
            {
                SelectedOutputDeviceId = selected.Value;
                broker.Dispatch(deviceId, "OutputAudioDevice", SelectedOutputDeviceId);
                broker.Dispatch(deviceId, "SetOutputAudioDevice", outputDevice.ID);
            }
            else if (xoutputDevice != null)
            {
                if (outputDevice != null) { outputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnVolumeNotification; }
                SelectedOutputDeviceId = selected.Value;
                outputDevice = xoutputDevice;
                outputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnVolumeNotification;
                broker.Dispatch(deviceId, "OutputAudioDevice", SelectedOutputDeviceId);
                broker.Dispatch(deviceId, "SetOutputAudioDevice", outputDevice.ID);
            }
        }

        private void inputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)inputComboBox.SelectedItem;
            if (SelectedInputDeviceId == selected.Value) return; // No change
            MMDevice xinputDevice = GetDeviceById(selected.Value, DataFlow.Capture);
            if (xinputDevice == null) return;
            if (inputDevice != null && xinputDevice.ID == inputDevice.ID)
            {
                SelectedInputDeviceId = selected.Value;
                broker.Dispatch(deviceId, "InputAudioDevice", SelectedInputDeviceId);
            }
            else
            {
                if (inputDevice != null) { inputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnInputVolumeNotification; }
                SelectedInputDeviceId = selected.Value;
                inputDevice = xinputDevice;
                inputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnInputVolumeNotification;
                broker.Dispatch(deviceId, "InputAudioDevice", SelectedInputDeviceId);
                // Restart microphone capture with new device
                RestartMicrophoneCapture();
            }
        }

        private MMDevice GetDeviceById(string id, DataFlow flow)
        {
            if (id == "")
            {
                try { return deviceEnumerator.GetDefaultAudioEndpoint(flow, Role.Console); } catch (Exception) { }
                return null;
            }
            foreach (var device in deviceEnumerator.EnumerateAudioEndPoints(flow, DeviceState.Active)) { if (device.ID == id) return device; }
            return null;
        }

        private void volumeTrackBar_Scroll(object sender, EventArgs e)
        {
            broker.Dispatch(deviceId, "SetVolumeLevel", volumeTrackBar.Value);
        }

        private void RadioVolumeForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            // Only hide instead of close when user closes the form directly
            // Allow actual closing when application is exiting
            if (e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
            }
        }

        private void transmitButton_MouseEnter(object sender, EventArgs e)
        {
            transmitButton.Image = microphoneImageList.Images[1];
        }

        private void transmitButton_MouseLeave(object sender, EventArgs e)
        {
            if (spacebarPTTToolStripMenuItem.Checked == false) {
                transmitButton.Image = microphoneImageList.Images[0];
            }
        }

        private void transmitButton_MouseDown(object sender, MouseEventArgs e)
        {
            transmitButton.Image = microphoneImageList.Images[2];
            MicrophoneTransmit = true;
            isTransmitting = true;
        }

        private void transmitButton_MouseUp(object sender, MouseEventArgs e)
        {
            transmitButton.Image = microphoneImageList.Images[1];
            MicrophoneTransmit = false;
            isTransmitting = false;
        }

        // Start capturing audio from the microphone (continuous capture for amplitude display)
        private void StartMicrophoneCapture()
        {
            if (isCapturing) return;
            if (inputDevice == null) return;
            
            try
            {
                // Use WasapiCapture which directly accepts an MMDevice, avoiding device name matching issues
                wasapiCapture = new WasapiCapture(inputDevice);
                captureWaveFormat = wasapiCapture.WaveFormat;
                wasapiCapture.DataAvailable += WasapiCapture_DataAvailable;
                wasapiCapture.RecordingStopped += WasapiCapture_RecordingStopped;
                wasapiCapture.StartRecording();
                isCapturing = true;
            }
            catch (Exception)
            {
                // Silently fail - microphone may not be available
            }
        }

        // Stop capturing audio from the microphone
        private void StopMicrophoneCapture()
        {
            if (wasapiCapture == null) return;
            
            try
            {
                isCapturing = false;
                wasapiCapture.DataAvailable -= WasapiCapture_DataAvailable;
                wasapiCapture.RecordingStopped -= WasapiCapture_RecordingStopped;
                wasapiCapture.StopRecording();
                wasapiCapture.Dispose();
                wasapiCapture = null;
            }
            catch (Exception) { }
        }

        // Restart microphone capture (used when input device changes)
        private void RestartMicrophoneCapture()
        {
            StopMicrophoneCapture();
            StartMicrophoneCapture();
        }

        // Handle microphone audio data from WasapiCapture - always process for amplitude display
        private void WasapiCapture_DataAvailable(object sender, WaveInEventArgs e)
        {
            if (!isCapturing) return;
            if (captureWaveFormat == null) return;
            
            // Convert audio to 16-bit PCM if needed (WasapiCapture may capture in different formats)
            byte[] pcm16Data;
            int pcm16BytesRecorded;
            
            if (captureWaveFormat.BitsPerSample == 32 && captureWaveFormat.Encoding == WaveFormatEncoding.IeeeFloat)
            {
                // Convert 32-bit float to 16-bit PCM
                pcm16BytesRecorded = e.BytesRecorded / 2; // 32-bit to 16-bit = half the bytes
                pcm16Data = new byte[pcm16BytesRecorded];
                int sampleCount = e.BytesRecorded / 4;
                for (int i = 0; i < sampleCount; i++)
                {
                    float sample = BitConverter.ToSingle(e.Buffer, i * 4);
                    short pcmSample = (short)Math.Max(short.MinValue, Math.Min(short.MaxValue, sample * 32767f));
                    pcm16Data[i * 2] = (byte)(pcmSample & 0xFF);
                    pcm16Data[i * 2 + 1] = (byte)((pcmSample >> 8) & 0xFF);
                }
            }
            else if (captureWaveFormat.BitsPerSample == 16)
            {
                // Already 16-bit PCM
                pcm16Data = new byte[e.BytesRecorded];
                Buffer.BlockCopy(e.Buffer, 0, pcm16Data, 0, e.BytesRecorded);
                pcm16BytesRecorded = e.BytesRecorded;
            }
            else
            {
                // Unsupported format, skip
                return;
            }
            
            // Apply input boost if needed (always apply boost for amplitude display)
            int boost = inputBoostValue;
            byte[] audioData;
            
            if (boost > 0)
            {
                // Apply boost by scaling the samples
                audioData = new byte[pcm16BytesRecorded];
                float boostFactor = 1.0f + (boost / 10.0f);
                
                for (int i = 0; i < pcm16BytesRecorded - 1; i += 2)
                {
                    short sample = (short)(pcm16Data[i] | (pcm16Data[i + 1] << 8));
                    float boosted = sample * boostFactor;
                    short clipped = (short)Math.Max(short.MinValue, Math.Min(short.MaxValue, boosted));
                    audioData[i] = (byte)(clipped & 0xFF);
                    audioData[i + 1] = (byte)((clipped >> 8) & 0xFF);
                }
            }
            else
            {
                audioData = pcm16Data;
            }
            
            // Calculate amplitude from the boosted audio buffer (take absolute value to handle negative samples)
            float amplitude = CalculateAmplitude(audioData, audioData.Length);
            
            // Always update the input amplitude bar (regardless of transmit state)
            // Use BeginInvoke to safely update the UI from the audio thread
            try
            {
                if (!IsDisposed && inputAmplitudeHistoryBar != null)
                {
                    BeginInvoke(new Action(() => {
                        // Call AddSample directly to bypass visibility check in ProcessAudioData
                        inputAmplitudeHistoryBar.AddSample(amplitude);
                    }));
                }
            }
            catch (Exception) { }
            
            // Only send audio to radio when transmitting
            if (!isTransmitting) return;
            
            // Resample to 32kHz mono if needed for radio transmission
            byte[] transmitData = ResampleTo32kHzMono(audioData, captureWaveFormat.SampleRate, captureWaveFormat.Channels);
            
            // Send PCM audio to the radio via Data Broker (32kHz, 16-bit, mono)
            broker.Dispatch(deviceId, "TransmitVoicePCM", transmitData, store: false);
        }

        // Resample audio to 32kHz mono for radio transmission
        private byte[] ResampleTo32kHzMono(byte[] inputData, int sourceSampleRate, int sourceChannels)
        {
            int sourceSamples = inputData.Length / 2; // 16-bit = 2 bytes per sample
            int sourceSamplesPerChannel = sourceSamples / sourceChannels;
            
            // Calculate output sample count
            int targetSampleRate = 32000;
            int targetSamples = (int)((long)sourceSamplesPerChannel * targetSampleRate / sourceSampleRate);
            
            byte[] outputData = new byte[targetSamples * 2]; // 16-bit mono
            
            for (int i = 0; i < targetSamples; i++)
            {
                // Calculate source position
                double sourcePos = (double)i * sourceSampleRate / targetSampleRate;
                int sourceIndex = (int)sourcePos;
                if (sourceIndex >= sourceSamplesPerChannel - 1) sourceIndex = sourceSamplesPerChannel - 2;
                
                // Linear interpolation
                double frac = sourcePos - sourceIndex;
                
                // Get samples (convert to mono by averaging channels if needed)
                int sample1, sample2;
                if (sourceChannels == 1)
                {
                    sample1 = (short)(inputData[sourceIndex * 2] | (inputData[sourceIndex * 2 + 1] << 8));
                    sample2 = (short)(inputData[(sourceIndex + 1) * 2] | (inputData[(sourceIndex + 1) * 2 + 1] << 8));
                }
                else
                {
                    // Average channels for mono
                    int idx1 = sourceIndex * sourceChannels * 2;
                    int idx2 = (sourceIndex + 1) * sourceChannels * 2;
                    int sum1 = 0, sum2 = 0;
                    for (int ch = 0; ch < sourceChannels; ch++)
                    {
                        sum1 += (short)(inputData[idx1 + ch * 2] | (inputData[idx1 + ch * 2 + 1] << 8));
                        sum2 += (short)(inputData[idx2 + ch * 2] | (inputData[idx2 + ch * 2 + 1] << 8));
                    }
                    sample1 = sum1 / sourceChannels;
                    sample2 = sum2 / sourceChannels;
                }
                
                // Interpolate
                short outputSample = (short)(sample1 + (sample2 - sample1) * frac);
                outputData[i * 2] = (byte)(outputSample & 0xFF);
                outputData[i * 2 + 1] = (byte)((outputSample >> 8) & 0xFF);
            }
            
            return outputData;
        }

        // Calculate the amplitude from PCM audio data (max absolute value normalized to 0-1)
        private float CalculateAmplitude(byte[] buffer, int bytesRecorded)
        {
            short maxAbs = 0;
            for (int i = 0; i < bytesRecorded - 1; i += 2)
            {
                short sample = (short)(buffer[i] | (buffer[i + 1] << 8));
                short abs = sample < 0 ? (short)-sample : sample;
                if (abs > maxAbs) maxAbs = abs;
            }
            return Math.Min(1.0f, maxAbs / 32768f);
        }

        private void WasapiCapture_RecordingStopped(object sender, StoppedEventArgs e)
        {
            // Cleanup is handled in StopMicrophoneCapture
        }

        private void pollTimer_Tick(object sender, EventArgs e)
        {
            pollTimer.Enabled = Visible;
            
            string stateStr = broker.GetValue<string>(deviceId, "State", "Disconnected");
            if (stateStr == "Connected")
            {
                // Request volume level periodically
                // Volume is already dispatched by Radio.cs when it changes
            }

            if (sessionControl == null)
            {
                // App specific volume control
                var enumerator = new MMDeviceEnumerator();
                MMDevice device = null;
                try { device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia); } catch (Exception) { }
                if (device != null)
                {
                    var sessions = device.AudioSessionManager.Sessions;
                    int currentProcessId = System.Diagnostics.Process.GetCurrentProcess().Id;
                    for (int i = 0; i < sessions.Count; i++)
                    {
                        var session = sessions[i];
                        if (session.GetProcessID == currentProcessId)
                        {
                            sessionControl = session;
                            sessionControl.RegisterEventClient(this);
                            appVolumeTrackBar.Enabled = true;
                            appVolumeTrackBar.Value = (int)(sessionControl.SimpleAudioVolume.Volume * 100);
                            appMuteButton.Enabled = true;
                            appMuteButton.ImageIndex = sessionControl.SimpleAudioVolume.Mute ? 0 : 1;
                            break;
                        }
                    }
                }
            }
        }

        private void squelchTrackBar_Scroll(object sender, EventArgs e)
        {
            broker.Dispatch(deviceId, "SetSquelchLevel", squelchTrackBar.Value);
        }

        private void audioButton_Click(object sender, EventArgs e)
        {
            bool audioEnabled = broker.GetValue<bool>(deviceId, "AudioState", false);
            broker.Dispatch(deviceId, "SetAudio", !audioEnabled);
        }

        private void masterVolumeTrackBar_Scroll(object sender, EventArgs e)
        {
            float volume = masterVolumeTrackBar.Value / 100f;
            if (outputDevice != null) { outputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = volume; }
        }

        private string FixDeviceName(string name) { return name.Replace("(R)", "®"); }

        private void outputTrackBar_Scroll(object sender, EventArgs e)
        {
            broker.Dispatch(deviceId, "SetOutputVolume", outputTrackBar.Value);
            broker.Dispatch(deviceId, "OutputAudioVolume", outputTrackBar.Value);
        }

        public static float SliderToDecibelScaledFloat(int sliderValue, float minDecibels = -40.0f) { return (sliderValue / 100F); }

        public static int DecibelScaledFloatToSlider(float value, float minDecibels = -40.0f) { return (int)(value * 100); }

        void IMMNotificationClient.OnDeviceAdded(string deviceIdStr)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnDeviceRemoved(string deviceIdStr)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnDefaultDeviceChanged(DataFlow dataFlow, Role deviceRole, string defaultDeviceId)
        {
            if (dataFlow == DataFlow.Render && deviceRole == Role.Multimedia)
            {
                if (SelectedOutputDeviceId == "") { broker.Dispatch(deviceId, "SetOutputAudioDevice", ""); }
                LoadAudioDevices(true);
            }
            else if (dataFlow == DataFlow.Capture && deviceRole == Role.Console)
            {
                if (SelectedInputDeviceId == "")
                {
                    // Input device changed to default
                }
                LoadAudioDevices(true);
            }
        }

        void IMMNotificationClient.OnDeviceStateChanged(string deviceIdStr, DeviceState newState)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnPropertyValueChanged(string deviceIdStr, PropertyKey key)
        {
            // NOP
        }

        private void inputTrackBar_Scroll(object sender, EventArgs e)
        {
            broker.Dispatch(deviceId, "InputAudioVolume", inputTrackBar.Value);
            if (inputDevice != null) { inputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = inputTrackBar.Value / 100f; }
        }

        public void ProcessInputAudioData(byte[] buffer, int bytesRecorded)
        {
            inputAmplitudeHistoryBar.ProcessAudioData(buffer, bytesRecorded);
        }

        public void ProcessOutputAudioData(byte[] buffer, int bytesRecorded)
        {
            outputAmplitudeHistoryBar.ProcessAudioData(buffer, bytesRecorded);
        }

        public delegate void OnVolumeChangedDelegate(float volume, bool isMuted);
        public void OnVolumeChanged(float volume, bool isMuted)
        {
            if (InvokeRequired) { BeginInvoke(new OnVolumeChangedDelegate(OnVolumeChanged), volume, isMuted); return; }
            appVolumeTrackBar.Value = (int)(sessionControl.SimpleAudioVolume.Volume * 100);
            appMuteButton.ImageIndex = sessionControl.SimpleAudioVolume.Mute ? 0 : 1;
        }

        public void OnDisplayNameChanged(string displayName) { }
        public void OnIconPathChanged(string iconPath) { }
        public void OnChannelVolumeChanged(uint channelCount, IntPtr newVolumes, uint channelIndex) { }
        public void OnGroupingParamChanged(ref Guid groupingId) { }
        public void OnStateChanged(AudioSessionState state) { }

        public delegate void OnSessionDisconnectedDelegate(AudioSessionDisconnectReason disconnectReason);
        public void OnSessionDisconnected(AudioSessionDisconnectReason disconnectReason)
        {
            if (InvokeRequired) { BeginInvoke(new OnSessionDisconnectedDelegate(OnSessionDisconnected), disconnectReason); return; }
            appVolumeTrackBar.Enabled = false;
            appVolumeTrackBar.Value = 0;
            appMuteButton.Enabled = false;
            appMuteButton.ImageIndex = 0;
            sessionControl = null;
        }

        private void appVolumeTrackBar_Scroll(object sender, EventArgs e)
        {
            if (sessionControl == null) return;
            sessionControl.SimpleAudioVolume.Volume = (float)(appVolumeTrackBar.Value / 100F);
        }

        private void recordButton_Click(object sender, EventArgs e)
        {
            bool recording = broker.GetValue<bool>(deviceId, "Recording", false);
            if (recording == true)
            {
                if (MessageBox.Show(this, "Stop Recording?", "Audio") == DialogResult.OK)
                {
                    broker.Dispatch(deviceId, "StopRecording", true);
                }
            }
            else
            {
                if (saveFileDialog.ShowDialog(this) == DialogResult.OK)
                {
                    string fileName = saveFileDialog.FileName;
                    if (fileName != null && fileName.Length > 0)
                    {
                        broker.Dispatch(deviceId, "StartRecording", fileName);
                    }
                }
            }
        }

        private void masterMuteButton_Click(object sender, EventArgs e)
        {
            if (outputDevice == null) return;
            outputDevice.AudioEndpointVolume.Mute = !outputDevice.AudioEndpointVolume.Mute;
            masterMuteButton.ImageIndex = outputDevice.AudioEndpointVolume.Mute ? 0 : 1;
        }

        private void appMuteButton_Click(object sender, EventArgs e)
        {
            if (sessionControl == null) return;
            sessionControl.SimpleAudioVolume.Mute = !sessionControl.SimpleAudioVolume.Mute;
            appMuteButton.ImageIndex = sessionControl.SimpleAudioVolume.Mute ? 0 : 1;
        }

        private void inputBoostTrackBar_Scroll(object sender, EventArgs e)
        {
            inputBoostValue = inputBoostTrackBar.Value;
            broker.Dispatch(deviceId, "InputAudioBoost", inputBoostTrackBar.Value);
        }

        private void outputGraphButton_Click(object sender, EventArgs e)
        {
            // Create SpectrogramForm to display radio audio output
            SpectrogramForm spectrogramForm = new SpectrogramForm(deviceId);
            spectrogramForm.SetShowTransmitAudio(false); // Show receive audio by default
            spectrogramForm.Show();
        }

        private void inputGraphButton_Click(object sender, EventArgs e)
        {
            // Create SpectrogramForm to display microphone input
            // Pass the selected input device ID, or null/empty for default device
            SpectrogramForm spectrogramForm = new SpectrogramForm(SelectedInputDeviceId);
            spectrogramForm.Show();
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void spacebarPTTToolStripMenuItem_Click(object sender, EventArgs e)
        {
            broker.Dispatch(0, "SpacebarPTT", spacebarPTTToolStripMenuItem.Checked ? 1 : 0);
            if (spacebarPTTToolStripMenuItem.Checked == true)
            {
                transmitButton.Image = microphoneImageList.Images[1];
            }
            else
            {
                transmitButton.Image = microphoneImageList.Images[0];
            }
        }

        private void RadioVolumeForm_KeyDown(object sender, KeyEventArgs e)
        {
            bool allowTransmit = broker.GetValue<bool>(0, "AllowTransmit", false);
            if (allowTransmit && spacebarPTTToolStripMenuItem.Checked && transmitButton.Enabled && (e.KeyCode == Keys.Space))
            {
                transmitButton_MouseDown(this, null);
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }

        private void RadioVolumeForm_KeyUp(object sender, KeyEventArgs e)
        {
            bool allowTransmit = broker.GetValue<bool>(0, "AllowTransmit", false);
            if (allowTransmit && spacebarPTTToolStripMenuItem.Checked && transmitButton.Enabled && (e.KeyCode == Keys.Space))
            {
                transmitButton_MouseUp(this, null);
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }

        private void RadioVolumeForm_Deactivate(object sender, EventArgs e)
        {
            transmitButton_MouseUp(this, null);
        }
    }
}