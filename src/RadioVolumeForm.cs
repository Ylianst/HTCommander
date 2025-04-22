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

using System;
using System.Drawing;
using System.Windows.Forms;
using FftSharp;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using Spectrogram;

namespace HTCommander
{
    public partial class RadioVolumeForm : Form, IMMNotificationClient
    {
        private MMDeviceEnumerator deviceEnumerator = new MMDeviceEnumerator();
        private MainForm parent;
        private Radio radio;
        private MMDevice outputDevice;
        private MMDevice inputDevice;
        private SpectrogramGenerator sg;
        public bool MicrophoneTransmit = false;

        public int Volume { get { return volumeTrackBar.Value; } set { volumeTrackBar.Value = value; } }

        public RadioVolumeForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
            deviceEnumerator.RegisterEndpointNotificationCallback(this);
            LoadAudioDevices();
            transmitButton.Image = microphoneImageList.Images[0];
            outputTrackBar.Value = (int)parent.registry.ReadInt("OutputAudioVolume", 100);
            radio.OutputVolume = SliderToDecibelScaledFloat(outputTrackBar.Value);
            inputTrackBar.Value = (int)parent.registry.ReadInt("InputAudioVolume", 100);
            inputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = inputTrackBar.Value / 100f;
            UpdateInfo();

            sg = new SpectrogramGenerator(36000, fftSize: 4096, stepSize: 500, maxFreq: 3000);
        }

        private void RadioVolumeForm_Load(object sender, EventArgs e)
        {
        }

        private delegate void AudioEndpointVolumeNotificationDelegate(AudioVolumeNotificationData data);
        private void AudioEndpointVolume_OnVolumeNotification(AudioVolumeNotificationData data)
        {
            if (InvokeRequired) { Invoke(new AudioEndpointVolumeNotificationDelegate(AudioEndpointVolume_OnVolumeNotification), data); return; }
            masterVolumeTrackBar.Value = (int)(outputDevice.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
        }
        private void AudioEndpointVolume_OnInputVolumeNotification(AudioVolumeNotificationData data)
        {
            if (InvokeRequired) { Invoke(new AudioEndpointVolumeNotificationDelegate(AudioEndpointVolume_OnInputVolumeNotification), data); return; }
            inputTrackBar.Value = (int)(inputDevice.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
        }


        public void UpdateInfo()
        {
            pollTimer.Enabled = Visible;
            audioButton.Image = parent.AudioEnabled ? microphoneImageList.Images[4] : microphoneImageList.Images[3];
            outputTrackBar.Value = DecibelScaledFloatToSlider(radio.OutputVolume);

            if (radio.State == Radio.RadioState.Connected)
            {
                volumeTrackBar.Enabled = true;
                audioButton.Enabled = true;
                transmitButton.Enabled = parent.AudioEnabled && parent.allowTransmit;
                //squelchTrackBar.Enabled = true;
                if (radio.Settings != null)
                {
                    squelchTrackBar.Value = radio.Settings.squelch_level;
                }
            }
            else
            {
                audioButton.Enabled = false;
                transmitButton.Enabled = false;
                volumeTrackBar.Enabled = false;
                squelchTrackBar.Enabled = false;
            }

            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)outputComboBox.SelectedItem;
            if (selected != null)
            {
                string selectedId = selected.Value;
                MMDevice selectedDevice = GetDeviceById(selectedId, DataFlow.Render);
                masterVolumeTrackBar.Value = (int)(selectedDevice.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
            }
        }

        public void SetAudio(bool enabled)
        {
            audioButton.Image = parent.AudioEnabled ? microphoneImageList.Images[4] : microphoneImageList.Images[3];
        }

        private delegate void LoadAudioDevicesDelegate();

        private void LoadAudioDevices()
        {
            if (InvokeRequired) { Invoke(new LoadAudioDevicesDelegate(LoadAudioDevices)); return; }

            // Load output devices (playback)
            outputComboBox.Items.Clear();
            outputComboBox.Items.Add(new Utils.ComboBoxItem(null, "Default"));
            foreach (var device in deviceEnumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
            {
                outputComboBox.Items.Add(new Utils.ComboBoxItem(device.ID, FixDeviceName(device.FriendlyName)));
            }

            // Select default output device
            outputDevice = deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Console);
            SetSelectedDevice(outputComboBox, outputDevice.ID);

            // Load input devices (recording)
            inputComboBox.Items.Clear();
            inputComboBox.Items.Add(new Utils.ComboBoxItem(null, "Default"));
            foreach (var device in deviceEnumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                inputComboBox.Items.Add(new Utils.ComboBoxItem(device.ID, FixDeviceName(device.FriendlyName)));
            }

            // Select default input device
            inputDevice = deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
            SetSelectedDevice(inputComboBox, inputDevice.ID);
        }

        private void SetSelectedDevice(ComboBox comboBox, string deviceId)
        {
            if (deviceId == null) { comboBox.SelectedIndex = 0; }
            for (int i = 0; i < comboBox.Items.Count; i++)
            {
                if (((Utils.ComboBoxItem)comboBox.Items[i]).Value == deviceId) { comboBox.SelectedIndex = i; break; }
            }
        }

        private void outputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (outputDevice != null) { outputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnVolumeNotification; }
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)outputComboBox.SelectedItem;
            string selectedId = selected.Value;
            outputDevice = GetDeviceById(selectedId, DataFlow.Render);
            outputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnVolumeNotification;
            parent.registry.WriteString("OutputAudioDevice", selectedId == null ? "" : selectedId);
        }

        private void inputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (inputDevice != null) { inputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnInputVolumeNotification; }
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)inputComboBox.SelectedItem;
            string selectedId = selected.Value;
            inputDevice = GetDeviceById(selectedId, DataFlow.Capture);
            inputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnInputVolumeNotification;
            parent.registry.WriteString("InputAudioDevice", selectedId == null ? "" : selectedId);
        }

        private MMDevice GetDeviceById(string id, DataFlow flow)
        {
            if (id == null) return deviceEnumerator.GetDefaultAudioEndpoint(flow, Role.Console);
            foreach (var device in deviceEnumerator.EnumerateAudioEndPoints(flow, DeviceState.Active)) { if (device.ID == id) return device; }
            return null;
        }

        private void volumeTrackBar_Scroll(object sender, EventArgs e)
        {
            radio.SetVolumeLevel(volumeTrackBar.Value);
        }

        private void RadioVolumeForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            e.Cancel = true; // Prevent the form from closing
            Hide(); // Hide the form instead
        }

        private void transmitButton_MouseEnter(object sender, EventArgs e)
        {
            transmitButton.Image = microphoneImageList.Images[1];
        }

        private void transmitButton_MouseLeave(object sender, EventArgs e)
        {
            transmitButton.Image = microphoneImageList.Images[0];
        }

        private void transmitButton_MouseDown(object sender, MouseEventArgs e)
        {
            transmitButton.Image = microphoneImageList.Images[2];
            MicrophoneTransmit = true;
        }

        private void transmitButton_MouseUp(object sender, MouseEventArgs e)
        {
            transmitButton.Image = microphoneImageList.Images[1];
            MicrophoneTransmit = false;
        }

        private void pollTimer_Tick(object sender, EventArgs e)
        {
            pollTimer.Enabled = Visible;
            if (radio.State == Radio.RadioState.Connected) { radio.GetVolumeLevel(); }
        }

        private void squelchTrackBar_Scroll(object sender, EventArgs e)
        {
            radio.SetSquelchLevel(squelchTrackBar.Value);
        }

        private void audioButton_Click(object sender, EventArgs e)
        {
            parent.AudioEnabled = !parent.AudioEnabled;
        }

        private void masterVolumeTrackBar_Scroll(object sender, EventArgs e)
        {
            float volume = masterVolumeTrackBar.Value / 100f;
            outputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = volume;
        }

        private string FixDeviceName(string name) { return name.Replace("(R)", "®"); }

        private void outputTrackBar_Scroll(object sender, EventArgs e) {
            radio.OutputVolume = SliderToDecibelScaledFloat(outputTrackBar.Value);
            parent.registry.WriteInt("OutputAudioVolume", outputTrackBar.Value);
        }

        public static float SliderToDecibelScaledFloat(int sliderValue, float minDecibels = -40.0f) { return (sliderValue / 100F); }

        public static int DecibelScaledFloatToSlider(float value, float minDecibels = -40.0f) { return (int)(value * 100); }

        void IMMNotificationClient.OnDeviceAdded(string deviceId)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnDeviceRemoved(string deviceId)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnDefaultDeviceChanged(DataFlow dataFlow, Role deviceRole, string defaultDeviceId)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnDeviceStateChanged(string deviceId, DeviceState newState)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnPropertyValueChanged(string deviceId, PropertyKey key)
        {
            LoadAudioDevices();
        }

        private void inputTrackBar_Scroll(object sender, EventArgs e)
        {
            parent.registry.WriteInt("InputAudioVolume", inputTrackBar.Value);
            inputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = inputTrackBar.Value / 100f;
        }

        public void ProcessInputAudioData(byte[] buffer, int bytesRecorded)
        {
            inputAmplitudeHistoryBar.ProcessAudioData(buffer, bytesRecorded);
        }

        public void ProcessOutputAudioData(byte[] buffer, int bytesRecorded)
        {
            outputAmplitudeHistoryBar.ProcessAudioData(buffer, bytesRecorded);
        }
    }
}
