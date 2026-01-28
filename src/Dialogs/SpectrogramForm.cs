/*
Copyright 2026 Ylian Saint-Hilaire

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
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Linq;
using Spectrogram;
using NAudio.Wave;
using NAudio.CoreAudioApi;

namespace HTCommander
{
    public enum SpectrogramMode
    {
        None,           // No audio source selected
        RadioAudio,     // Listen to audio from a radio device via DataBroker
        Microphone      // Capture audio from a local microphone
    }

    public partial class SpectrogramForm : Form
    {
        private DataBrokerClient broker;
        private SpectrogramGenerator spec;
        private Colormap[] cmaps;
        private int cbFftSize = 0;
        private int heightDiff = 0;
        private bool roll = false;
        private int maxFrequency = 16000;
        private bool showTransmitAudio = false; // For radio mode: whether to show transmit audio (true) or receive audio (false)
        public readonly int SampleRate = 2;
        public double AmplitudeFrac { get; private set; }
        public double TotalSamples { get; private set; }
        public double TotalTimeSec { get { return (double)TotalSamples / SampleRate; } }
        private readonly List<double> audio = new List<double>();
        public int SamplesInMemory { get { return audio.Count; } }

        // Mode tracking
        private SpectrogramMode mode = SpectrogramMode.None;
        private int radioDeviceId = -1;
        private string microphoneDeviceId = null;
        private WasapiCapture microphoneCapture = null;

        // Connected radios cache for menu
        private List<dynamic> connectedRadios = new List<dynamic>();

        /// <summary>
        /// Default constructor - opens the spectrogram without a pre-selected source.
        /// User can select a radio or microphone from the Source menu.
        /// </summary>
        public SpectrogramForm()
        {
            broker = new DataBrokerClient();
            InitializeComponent();
            LoadSettings();

            // Subscribe to ConnectedRadios changes to update the source menu
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Get the current list of connected radios
            LoadConnectedRadios();
        }

        /// <summary>
        /// Constructor for Radio Audio mode - subscribes to AudioDataAvailable from a specific radio device
        /// </summary>
        /// <param name="deviceId">The radio device ID to listen to</param>
        public SpectrogramForm(int deviceId)
        {
            broker = new DataBrokerClient();
            InitializeComponent();
            LoadSettings();

            // Subscribe to ConnectedRadios changes to update the source menu
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Get the current list of connected radios
            LoadConnectedRadios();

            // Set initial source to the specified radio
            SelectRadioSource(deviceId);
        }

        /// <summary>
        /// Constructor for Microphone mode - captures audio from a local microphone device
        /// </summary>
        /// <param name="microphoneId">The microphone device ID (MMDevice.ID), or null/empty for default device</param>
        public SpectrogramForm(string microphoneId)
        {
            broker = new DataBrokerClient();
            InitializeComponent();
            LoadSettings();

            // Subscribe to ConnectedRadios changes to update the source menu
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Get the current list of connected radios
            LoadConnectedRadios();

            // Set initial source to the specified microphone
            SelectMicrophoneSource(microphoneId);
        }

        /// <summary>
        /// Load settings common to all constructors
        /// </summary>
        private void LoadSettings()
        {
            // Load Settings from DataBroker (device 0)
            maxFrequency = broker.GetValue<int>(0, "SpecMaxFrequency", 16000);
            hzToolStripMenuItem.Checked = (maxFrequency == 16000);
            hzToolStripMenuItem1.Checked = (maxFrequency == 8000);
            hzToolStripMenuItem2.Checked = (maxFrequency == 4000);
            pbScaleVert.Visible = scaleToolStripMenuItem.Checked = (broker.GetValue<int>(0, "SpecShowScale", 0) == 1);
            roll = rollToolStripMenuItem.Checked = (broker.GetValue<int>(0, "SpecRoll", 0) == 1);
            cbFftSize = broker.GetValue<int>(0, "SpecLarge", 0);
            largeToolStripMenuItem1.Checked = (cbFftSize == 1);
        }

        /// <summary>
        /// Load the current list of connected radios from the DataBroker
        /// </summary>
        private void LoadConnectedRadios()
        {
            var data = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (data == null)
            {
                connectedRadios.Clear();
            }
            else
            {
                try
                {
                    // The data is a list of anonymous objects with DeviceId, MacAddress, FriendlyName, State
                    connectedRadios = ((System.Collections.IEnumerable)data).Cast<dynamic>().ToList();
                }
                catch
                {
                    connectedRadios.Clear();
                }
            }
        }

        /// <summary>
        /// Handle ConnectedRadios changes from the DataBroker
        /// </summary>
        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            if (data == null)
            {
                connectedRadios.Clear();
            }
            else
            {
                try
                {
                    // The data is a list of anonymous objects with DeviceId, MacAddress, FriendlyName, State
                    connectedRadios = ((System.Collections.IEnumerable)data).Cast<dynamic>().ToList();
                }
                catch
                {
                    connectedRadios.Clear();
                }
            }

            // Update the window title in case the radio name changed
            UpdateWindowTitle();
        }

        /// <summary>
        /// Select a radio as the audio source
        /// </summary>
        private void SelectRadioSource(int deviceId)
        {
            // Stop any existing source
            StopCurrentSource();

            // Set the new mode and device
            mode = SpectrogramMode.RadioAudio;
            radioDeviceId = deviceId;
            microphoneDeviceId = null;

            // Subscribe to audio data from the specified radio device
            broker.Subscribe(deviceId, "AudioDataAvailable", OnRadioAudioDataAvailable);

            // Subscribe to radio state changes to detect disconnection
            broker.Subscribe(deviceId, "State", OnRadioStateChanged);

            // Update window title
            UpdateWindowTitle();
        }

        /// <summary>
        /// Select a microphone as the audio source
        /// </summary>
        private void SelectMicrophoneSource(string deviceId)
        {
            // Stop any existing source
            StopCurrentSource();

            // Set the new mode and device
            mode = SpectrogramMode.Microphone;
            radioDeviceId = -1;
            microphoneDeviceId = deviceId;

            // Initialize and start microphone capture
            InitializeMicrophoneCapture();
            StartMicrophoneCapture();

            // Update window title
            UpdateWindowTitle();
        }

        /// <summary>
        /// Stop the current audio source
        /// </summary>
        private void StopCurrentSource()
        {
            if (mode == SpectrogramMode.RadioAudio && radioDeviceId > 0)
            {
                broker.Unsubscribe(radioDeviceId, "AudioDataAvailable");
                broker.Unsubscribe(radioDeviceId, "State");
            }
            else if (mode == SpectrogramMode.Microphone)
            {
                StopMicrophoneCapture();
                try { microphoneCapture?.Dispose(); } catch { }
                microphoneCapture = null;
            }

            mode = SpectrogramMode.None;
            radioDeviceId = -1;
            microphoneDeviceId = null;
        }

        /// <summary>
        /// Update the window title based on the current source
        /// </summary>
        private void UpdateWindowTitle()
        {
            string sourceName = "No Source";

            if (mode == SpectrogramMode.RadioAudio && radioDeviceId > 0)
            {
                // Find the radio's friendly name
                var radio = connectedRadios.FirstOrDefault(r => (int)r.DeviceId == radioDeviceId);
                if (radio != null && !string.IsNullOrEmpty((string)radio.FriendlyName))
                {
                    sourceName = (string)radio.FriendlyName;
                }
                else
                {
                    sourceName = $"Radio {radioDeviceId}";
                }
            }
            else if (mode == SpectrogramMode.Microphone)
            {
                sourceName = GetMicrophoneName(microphoneDeviceId);
            }

            this.Text = $"Spectrogram - {sourceName}";
        }

        /// <summary>
        /// Get the friendly name for a microphone device
        /// </summary>
        private string GetMicrophoneName(string deviceId)
        {
            if (string.IsNullOrEmpty(deviceId))
            {
                return "Default Microphone";
            }

            try
            {
                var enumerator = new MMDeviceEnumerator();
                var device = enumerator.GetDevice(deviceId);
                return device?.FriendlyName ?? "Microphone";
            }
            catch
            {
                return "Microphone";
            }
        }

        /// <summary>
        /// Get all available audio input devices
        /// </summary>
        private List<MMDevice> GetAudioInputDevices()
        {
            var devices = new List<MMDevice>();
            try
            {
                var enumerator = new MMDeviceEnumerator();
                var collection = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active);
                foreach (var device in collection)
                {
                    devices.Add(device);
                }
            }
            catch
            {
                // Ignore errors enumerating devices
            }
            return devices;
        }

        /// <summary>
        /// Handle radio state changes to detect disconnection
        /// </summary>
        private void OnRadioStateChanged(int deviceId, string name, object data)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => OnRadioStateChanged(deviceId, name, data))); return; }

            // Check if the radio has disconnected
            string stateStr = data as string;
            if (stateStr == "Disconnected")
            {
                // Radio disconnected, close the form
                this.Close();
            }
        }

        /// <summary>
        /// Handle audio data received from the radio via DataBroker
        /// </summary>
        private void OnRadioAudioDataAvailable(int deviceId, string name, object data)
        {
            if (data == null) return;

            try
            {
                // The data is an anonymous object with Data, Offset, Length, ChannelName, Transmit properties
                dynamic audioData = data;
                byte[] buffer = audioData.Data;
                int offset = audioData.Offset;
                int length = audioData.Length;
                bool isTransmit = audioData.Transmit;

                // Filter based on whether we want transmit or receive audio
                if (isTransmit != showTransmitAudio) return;

                AddAudioData(buffer, offset, length);
            }
            catch (Exception)
            {
                // Ignore errors parsing audio data
            }
        }

        /// <summary>
        /// Initialize microphone capture using WASAPI
        /// </summary>
        private void InitializeMicrophoneCapture()
        {
            try
            {
                MMDevice targetDevice = null;
                var enumerator = new MMDeviceEnumerator();

                if (string.IsNullOrEmpty(microphoneDeviceId))
                {
                    // Use default microphone
                    try { targetDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications); } catch { }
                    if (targetDevice == null)
                    {
                        try { targetDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Multimedia); } catch { }
                    }
                }
                else
                {
                    // Use specific device
                    try { targetDevice = enumerator.GetDevice(microphoneDeviceId); } catch { }
                }

                if (targetDevice == null)
                {
                    MessageBox.Show("Could not find the specified microphone device.", "Microphone Error", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // Create WASAPI capture at 32kHz, 16-bit, mono to match radio audio format
                microphoneCapture = new WasapiCapture(targetDevice, false, 50);
                microphoneCapture.WaveFormat = new WaveFormat(32000, 16, 1);
                microphoneCapture.DataAvailable += MicrophoneCapture_DataAvailable;
                microphoneCapture.RecordingStopped += MicrophoneCapture_RecordingStopped;
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Error initializing microphone: {ex.Message}", "Microphone Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        /// <summary>
        /// Handle audio data from microphone capture
        /// </summary>
        private void MicrophoneCapture_DataAvailable(object sender, WaveInEventArgs e)
        {
            if (e.BytesRecorded > 0)
            {
                AddAudioData(e.Buffer, 0, e.BytesRecorded);
            }
        }

        /// <summary>
        /// Handle microphone recording stopped
        /// </summary>
        private void MicrophoneCapture_RecordingStopped(object sender, StoppedEventArgs e)
        {
            if (e.Exception != null)
            {
                // Recording stopped due to error - could log or notify
            }
        }

        /// <summary>
        /// Start microphone capture (call after form is loaded)
        /// </summary>
        private void StartMicrophoneCapture()
        {
            try
            {
                microphoneCapture?.StartRecording();
            }
            catch (Exception)
            {
                // Ignore errors starting capture
            }
        }

        /// <summary>
        /// Stop microphone capture
        /// </summary>
        private void StopMicrophoneCapture()
        {
            try
            {
                microphoneCapture?.StopRecording();
            }
            catch (Exception)
            {
                // Ignore errors stopping capture
            }
        }

        private void StartListening()
        {
            int sampleRate = 32000;
            int fftSize = 1 << (9 + cbFftSize); // cbFftSize.SelectedIndex
            int stepSize = fftSize / 20;

            pbSpectrogram.Image?.Dispose();
            pbSpectrogram.Image = null;
            spec = new SpectrogramGenerator(sampleRate, fftSize, stepSize, maxFreq: maxFrequency); // Max: 6200, 100, 100
            pbSpectrogram.Height = spec.Height;

            pbScaleVert.Image?.Dispose();
            pbScaleVert.Image = spec.GetVerticalScale(pbScaleVert.Width);
            pbScaleVert.Height = spec.Height;

            int refHeight = GetRefHeight();
            int h = refHeight + (refHeight * cbFftSize) + heightDiff;
            this.MinimumSize = new Size(200, h);
            this.MaximumSize = new Size(65535, h);
            this.Height = h;
        }

        private void updateTimer_Tick(object sender, EventArgs e)
        {
            if (spec == null) return;
            spec.Add(GetNewAudio(), process: false);
            double multiplier = 100 / 20.0;

            if (spec.FftsToProcess > 0)
            {
                spec.Process();
                spec.SetFixedWidth(pbSpectrogram.Width);
                Bitmap bmpSpec = new Bitmap(spec.Width, spec.Height, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
                using (var bmpSpecIndexed = spec.GetBitmap(multiplier, true, roll: roll))
                using (var gfx = Graphics.FromImage(bmpSpec))
                using (var pen = new Pen(Color.White))
                {
                    gfx.DrawImage(bmpSpecIndexed, 0, 0);
                    if (roll) { gfx.DrawLine(pen, spec.NextColumnIndex, 0, spec.NextColumnIndex, pbSpectrogram.Height); }
                }
                pbSpectrogram.Image?.Dispose();
                pbSpectrogram.Image = bmpSpec;
            }
        }

        /// <summary>
        /// Add PCM audio data to the spectrogram buffer
        /// </summary>
        /// <param name="Buffer">PCM audio buffer (16-bit samples)</param>
        /// <param name="offset">Offset into the buffer</param>
        /// <param name="BytesRecorded">Number of bytes to process</param>
        public void AddAudioData(byte[] Buffer, int offset, int BytesRecorded)
        {
            if (amplitudeHistoryBar.Visible) { amplitudeHistoryBar.ProcessAudioData(Buffer, BytesRecorded); }
            int bytesPerSample = 2;
            int newSampleCount = BytesRecorded / bytesPerSample;
            double[] buffer = new double[newSampleCount];
            double peak = 0;
            for (int i = 0; i < newSampleCount; i++)
            {
                buffer[i] = BitConverter.ToInt16(Buffer, offset + (i * bytesPerSample));
                peak = Math.Max(peak, buffer[i]);
            }
            lock (audio) { audio.AddRange(buffer); }
            AmplitudeFrac = peak / (1 << 15);
            TotalSamples += newSampleCount;
        }
        private double[] GetNewAudio()
        {
            lock (audio)
            {
                double[] values = new double[audio.Count];
                for (int i = 0; i < values.Length; i++) { values[i] = audio[i]; }
                audio.RemoveRange(0, values.Length);
                return values;
            }
        }

        private void SpectrogramForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            updateTimer.Enabled = false;

            // Stop current audio source
            StopCurrentSource();

            broker?.Dispose();
        }

        private int GetRefHeight()
        {
            return (maxFrequency * 256 / 16000);
        }

        private void SpectrogramForm_Load(object sender, EventArgs e)
        {
            heightDiff = this.Height - pbSpectrogram.Height;
            this.Height = GetRefHeight() + heightDiff;
            StartListening();

            string selectedColor = broker.GetValue<string>(0, "SpecColor", "Viridis");
            cmaps = Colormap.GetColormaps();
            for (int i = 0; i < cmaps.Length; i++)
            {
                Colormap cmap = cmaps[i];
                ToolStripMenuItem m = new ToolStripMenuItem(cmap.Name);
                m.Tag = i;
                m.Click += colorToolStripMenuItem_Click;
                m.Checked = (cmap.Name == selectedColor);
                if (cmap.Name == selectedColor) { spec.Colormap = cmap; }
                colorsToolStripMenuItem.DropDownItems.Add(m);
            }

            // Update window title
            UpdateWindowTitle();
        }

        /// <summary>
        /// Populate the Source menu when it opens
        /// </summary>
        private void sourceToolStripMenuItem_DropDownOpening(object sender, EventArgs e)
        {
            // Reload the connected radios list to ensure we have the latest
            LoadConnectedRadios();

            // Clear existing items
            sourceToolStripMenuItem.DropDownItems.Clear();

            // Add connected radios
            if (connectedRadios.Count > 0)
            {
                foreach (var radio in connectedRadios)
                {
                    int deviceId = (int)radio.DeviceId;
                    string friendlyName = (string)radio.FriendlyName;
                    string displayName = !string.IsNullOrEmpty(friendlyName) ? friendlyName : $"Radio {deviceId}";

                    ToolStripMenuItem radioItem = new ToolStripMenuItem(displayName);
                    radioItem.Tag = deviceId;
                    radioItem.Checked = (mode == SpectrogramMode.RadioAudio && radioDeviceId == deviceId);
                    radioItem.Click += RadioMenuItem_Click;
                    sourceToolStripMenuItem.DropDownItems.Add(radioItem);
                }
            }
            else
            {
                // No radios connected - show disabled placeholder
                ToolStripMenuItem noRadiosItem = new ToolStripMenuItem("(No radios connected)");
                noRadiosItem.Enabled = false;
                sourceToolStripMenuItem.DropDownItems.Add(noRadiosItem);
            }

            // Add separator
            sourceToolStripMenuItem.DropDownItems.Add(new ToolStripSeparator());

            // Add audio input devices (microphones)
            var audioDevices = GetAudioInputDevices();
            if (audioDevices.Count > 0)
            {
                foreach (var device in audioDevices)
                {
                    ToolStripMenuItem micItem = new ToolStripMenuItem(device.FriendlyName);
                    micItem.Tag = device.ID;
                    micItem.Checked = (mode == SpectrogramMode.Microphone && microphoneDeviceId == device.ID);
                    micItem.Click += MicrophoneMenuItem_Click;
                    sourceToolStripMenuItem.DropDownItems.Add(micItem);
                }
            }
            else
            {
                // No microphones found - show disabled placeholder
                ToolStripMenuItem noMicsItem = new ToolStripMenuItem("(No audio inputs found)");
                noMicsItem.Enabled = false;
                sourceToolStripMenuItem.DropDownItems.Add(noMicsItem);
            }
        }

        /// <summary>
        /// Handle click on a radio menu item
        /// </summary>
        private void RadioMenuItem_Click(object sender, EventArgs e)
        {
            ToolStripMenuItem item = (ToolStripMenuItem)sender;
            int deviceId = (int)item.Tag;
            SelectRadioSource(deviceId);
        }

        /// <summary>
        /// Handle click on a microphone menu item
        /// </summary>
        private void MicrophoneMenuItem_Click(object sender, EventArgs e)
        {
            ToolStripMenuItem item = (ToolStripMenuItem)sender;
            string deviceId = (string)item.Tag;
            SelectMicrophoneSource(deviceId);
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void largeToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            cbFftSize = largeToolStripMenuItem1.Checked ? 1 : 0;
            broker.Dispatch(0, "SpecLarge", cbFftSize);
            StartListening();
        }

        private void rollToolStripMenuItem_Click(object sender, EventArgs e)
        {
            roll = rollToolStripMenuItem.Checked;
            broker.Dispatch(0, "SpecRoll", roll ? 1 : 0);
        }

        private void scaleToolStripMenuItem_Click(object sender, EventArgs e)
        {
            pbScaleVert.Visible = scaleToolStripMenuItem.Checked;
            broker.Dispatch(0, "SpecShowScale", scaleToolStripMenuItem.Checked ? 1 : 0);
        }

        private void hzToolStripMenuItem_Click(object sender, EventArgs e)
        {
            maxFrequency = 16000;
            broker.Dispatch(0, "SpecMaxFrequency", maxFrequency);
            hzToolStripMenuItem.Checked = true;
            hzToolStripMenuItem1.Checked = false;
            hzToolStripMenuItem2.Checked = false;
            StartListening();
        }

        private void hzToolStripMenuItem1_Click(object sender, EventArgs e)
        {
            maxFrequency = 8000;
            broker.Dispatch(0, "SpecMaxFrequency", maxFrequency);
            hzToolStripMenuItem.Checked = false;
            hzToolStripMenuItem1.Checked = true;
            hzToolStripMenuItem2.Checked = false;
            StartListening();
        }

        private void hzToolStripMenuItem2_Click(object sender, EventArgs e)
        {
            maxFrequency = 4000;
            broker.Dispatch(0, "SpecMaxFrequency", maxFrequency);
            hzToolStripMenuItem.Checked = false;
            hzToolStripMenuItem1.Checked = false;
            hzToolStripMenuItem2.Checked = true;
            StartListening();
        }

        private void colorToolStripMenuItem_Click(object sender, EventArgs e)
        {
            ToolStripMenuItem m = (ToolStripMenuItem)sender;
            spec.Colormap = cmaps[(int)m.Tag];
            foreach (ToolStripMenuItem n in colorsToolStripMenuItem.DropDownItems) { n.Checked = (n == m); }
            broker.Dispatch(0, "SpecColor", spec.Colormap.Name);
        }

        private void radioToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // This is now handled by the dynamic menu
        }

        private void microphoneToolStripMenuItem_Click(object sender, EventArgs e)
        {
            // This is now handled by the dynamic menu
        }

        /// <summary>
        /// For radio mode: switch between showing receive audio (false) or transmit audio (true)
        /// </summary>
        public void SetShowTransmitAudio(bool showTransmit)
        {
            if (mode != SpectrogramMode.RadioAudio) return;
            showTransmitAudio = showTransmit;
        }

        /// <summary>
        /// Gets the current spectrogram mode
        /// </summary>
        public SpectrogramMode Mode { get { return mode; } }

        /// <summary>
        /// Gets the radio device ID (only valid in RadioAudio mode)
        /// </summary>
        public int RadioDeviceId { get { return radioDeviceId; } }

        /// <summary>
        /// Gets the microphone device ID (only valid in Microphone mode)
        /// </summary>
        public string MicrophoneDeviceId { get { return microphoneDeviceId; } }
    }
}