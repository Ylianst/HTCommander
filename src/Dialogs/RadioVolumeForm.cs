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
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows.Forms;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;

namespace HTCommander
{
    public partial class RadioVolumeForm : Form, IMMNotificationClient, IAudioSessionEventsHandler
    {
        private MMDeviceEnumerator deviceEnumerator = new MMDeviceEnumerator();
        private MainForm parent;
        private Radio radio;
        private MMDevice outputDevice;
        private MMDevice inputDevice;
        private AudioSessionControl sessionControl;
        private string SelectedOutputDeviceId = "";
        private string SelectedInputDeviceId = "";
        public bool MicrophoneTransmit = false;

        public int Volume { get { return volumeTrackBar.Value; } set { volumeTrackBar.Value = value; } }

        public RadioVolumeForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            /*
            this.parent = parent;
            this.radio = radio;
            SelectedOutputDeviceId = parent.registry.ReadString("OutputAudioDevice", "");
            SelectedInputDeviceId = parent.registry.ReadString("InputAudioDevice", "");
            deviceEnumerator.RegisterEndpointNotificationCallback(this);
            LoadAudioDevices();
            transmitButton.Image = microphoneImageList.Images[0];
            recordButton.Image = microphoneImageList.Images[6];
            outputTrackBar.Value = (int)parent.registry.ReadInt("OutputAudioVolume", 100);
            radio.OutputVolume = SliderToDecibelScaledFloat(outputTrackBar.Value);
            inputTrackBar.Value = (int)parent.registry.ReadInt("InputAudioVolume", 100);
            if (inputDevice != null) { inputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = inputTrackBar.Value / 100f; }
            parent.microphone.SetInputDevice(SelectedInputDeviceId);
            radio.SetOutputAudioDevice(SelectedOutputDeviceId);
            UpdateInfo();
            parent.microphone.Boost = inputBoostTrackBar.Value = (int)parent.registry.ReadInt("InputAudioBoost", 0);
            spacebarPTTToolStripMenuItem.Checked = (parent.registry.ReadInt("SpacebarPTT", 0) != 0);
            */
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
            /*
            pollTimer.Enabled = Visible;
            audioButton.Image = parent.AudioEnabled ? microphoneImageList.Images[4] : microphoneImageList.Images[3];
            outputTrackBar.Value = DecibelScaledFloatToSlider(radio.OutputVolume);
            inputGraphButton.Enabled = inputComboBox.Enabled = inputTrackBar.Enabled = inputBoostTrackBar.Enabled = parent.allowTransmit && (inputDevice != null);
            transmitButton.Visible = parent.allowTransmit;

            if (radio.State == Radio.RadioState.Connected)
            {
                volumeTrackBar.Enabled = true;
                audioButton.Enabled = true;
                recordButton.Enabled = parent.AudioEnabled;
                transmitButton.Enabled = parent.AudioEnabled && parent.allowTransmit && (inputDevice != null);
                squelchTrackBar.Enabled = true;
                if (radio.Settings != null) { squelchTrackBar.Value = radio.Settings.squelch_level; }
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
                masterVolumeTrackBar.Value = (int)(selectedDevice.AudioEndpointVolume.MasterVolumeLevelScalar * 100);
                try
                {
                    if (outputDevice != null) { masterMuteButton.ImageIndex = outputDevice.AudioEndpointVolume.Mute ? 0 : 1; } else { masterMuteButton.ImageIndex = 0; }
                }
                catch (Exception) { }
            }
            */
        }

        public void SetAudio(bool enabled)
        {
            //audioButton.Image = parent.AudioEnabled ? microphoneImageList.Images[4] : microphoneImageList.Images[3];
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
            //parent.registry.WriteString("OutputAudioDevice", SelectedOutputDeviceId);
            MMDevice xoutputDevice = GetDeviceById(SelectedOutputDeviceId, DataFlow.Render);
            if (xoutputDevice != outputDevice)
            {
                if (outputDevice != null) { outputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnVolumeNotification; }
                outputDevice = xoutputDevice;
                outputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnVolumeNotification;
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
            //parent.registry.WriteString("InputAudioDevice", SelectedInputDeviceId);
            MMDevice xinputDevice = GetDeviceById(SelectedInputDeviceId, DataFlow.Capture);
            if (xinputDevice != inputDevice)
            {
                if (inputDevice != null) { inputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnInputVolumeNotification; }
                inputDevice = xinputDevice;
                if (inputDevice != null) { inputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnInputVolumeNotification; }
            }
        }

        private string SetSelectedDevice(ComboBox comboBox, string deviceId)
        {
            for (int i = 0; i < comboBox.Items.Count; i++)
            {
                if (((Utils.ComboBoxItem)comboBox.Items[i]).Value == deviceId) { comboBox.SelectedIndex = i; return deviceId; }
            }
            if (comboBox.Items.Count > 0) { comboBox.SelectedIndex = 0; }
            return "";
        }

        private void outputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)outputComboBox.SelectedItem;
            if (SelectedOutputDeviceId == selected.Value) return; // No change
            MMDevice xoutputDevice = GetDeviceById(selected.Value, DataFlow.Render);
            if (xoutputDevice.ID == outputDevice.ID)
            {
                SelectedOutputDeviceId = selected.Value;
                //parent.registry.WriteString("OutputAudioDevice", SelectedOutputDeviceId);
                radio.RadioAudio.SetOutputDevice(outputDevice.ID);
            }
            else
            {
                if (outputDevice != null) { outputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnVolumeNotification; }
                SelectedOutputDeviceId = selected.Value;
                outputDevice = xoutputDevice;
                outputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnVolumeNotification;
                //parent.registry.WriteString("OutputAudioDevice", SelectedOutputDeviceId);
                radio.RadioAudio.SetOutputDevice(outputDevice.ID);
            }
        }

        private void inputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)inputComboBox.SelectedItem;
            if (SelectedInputDeviceId == selected.Value) return; // No change
            MMDevice xinputDevice = GetDeviceById(SelectedInputDeviceId, DataFlow.Capture);
            if (xinputDevice == null) return;
            if (xinputDevice.ID == inputDevice.ID)
            {
                SelectedInputDeviceId = selected.Value;
                //parent.registry.WriteString("InputAudioDevice", SelectedInputDeviceId);
                //parent.microphone.SetInputDevice(inputDevice.ID);
            }
            else
            {
                if (inputDevice != null) { inputDevice.AudioEndpointVolume.OnVolumeNotification -= AudioEndpointVolume_OnInputVolumeNotification; }
                SelectedInputDeviceId = selected.Value;
                inputDevice = xinputDevice;
                inputDevice.AudioEndpointVolume.OnVolumeNotification += AudioEndpointVolume_OnInputVolumeNotification;
                //parent.registry.WriteString("InputAudioDevice", SelectedInputDeviceId);
                //parent.microphone.SetInputDevice(inputDevice.ID);
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
            if (spacebarPTTToolStripMenuItem.Checked == false) {
                transmitButton.Image = microphoneImageList.Images[0];
            }
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

            if (sessionControl == null)
            {
                // App specific volume control
                var enumerator = new MMDeviceEnumerator();
                MMDevice device = null;
                try { device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia); } catch (Exception) { }
                if (device != null)
                {
                    var sessions = device.AudioSessionManager.Sessions;
                    int currentProcessId = Process.GetCurrentProcess().Id;
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
            radio.SetSquelchLevel(squelchTrackBar.Value);
        }

        private void audioButton_Click(object sender, EventArgs e)
        {
            //parent.AudioEnabled = !parent.AudioEnabled;
        }

        private void masterVolumeTrackBar_Scroll(object sender, EventArgs e)
        {
            float volume = masterVolumeTrackBar.Value / 100f;
            if (outputDevice != null) { outputDevice.AudioEndpointVolume.MasterVolumeLevelScalar = volume; }
        }

        private string FixDeviceName(string name) { return name.Replace("(R)", "®"); }

        private void outputTrackBar_Scroll(object sender, EventArgs e)
        {
            radio.OutputVolume = SliderToDecibelScaledFloat(outputTrackBar.Value);
            //parent.registry.WriteInt("OutputAudioVolume", outputTrackBar.Value);
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
            if (dataFlow == DataFlow.Render && deviceRole == Role.Multimedia)
            {
                if (SelectedOutputDeviceId == "") { radio.RadioAudio.SetOutputDevice(""); }
                LoadAudioDevices(true);
            }
            else if (dataFlow == DataFlow.Capture && deviceRole == Role.Console)
            {
                //if (SelectedInputDeviceId == "") { parent.microphone.SetInputDevice(""); }
                LoadAudioDevices(true);
            }
        }

        void IMMNotificationClient.OnDeviceStateChanged(string deviceId, DeviceState newState)
        {
            LoadAudioDevices();
        }

        void IMMNotificationClient.OnPropertyValueChanged(string deviceId, PropertyKey key)
        {
            // NOP
        }

        private void inputTrackBar_Scroll(object sender, EventArgs e)
        {
            //parent.registry.WriteInt("InputAudioVolume", inputTrackBar.Value);
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
            /*
            if (parent.radio.Recording == true)
            {
                if (MessageBox.Show(this, "Stop Recording?", "Audio") == DialogResult.OK)
                {
                    parent.radio.StopRecording();
                    recordButton.Image = microphoneImageList.Images[6];
                }
            }
            else
            {
                if (saveFileDialog.ShowDialog(this) == DialogResult.OK)
                {
                    string fileName = saveFileDialog.FileName;
                    if (fileName != null && fileName.Length > 0)
                    {
                        parent.radio.StartRecording(fileName);
                        recordButton.Image = microphoneImageList.Images[7];
                    }
                }
            }
            */
        }

        private void masterMuteButton_Click(object sender, EventArgs e)
        {
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
            //parent.microphone.Boost = inputBoostTrackBar.Value;
            //parent.registry.WriteInt("InputAudioBoost", inputBoostTrackBar.Value);
        }

        private void outputGraphButton_Click(object sender, EventArgs e)
        {
            //parent.showAudioGraph(false);
        }

        private void inputGraphButton_Click(object sender, EventArgs e)
        {
            //parent.showAudioGraph(true);
        }

        private void closeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void spacebarPTTToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //parent.registry.WriteInt("SpacebarPTT", spacebarPTTToolStripMenuItem.Checked ? 1 : 0);
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
            if (spacebarPTTToolStripMenuItem.Checked && transmitButton.Enabled && (e.KeyCode == Keys.Space))
            {
                transmitButton_MouseDown(this, null);
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }

        private void RadioVolumeForm_KeyUp(object sender, KeyEventArgs e)
        {
            if (spacebarPTTToolStripMenuItem.Checked && transmitButton.Enabled && (e.KeyCode == Keys.Space))
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
