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
using System.Windows.Forms;
using NAudio.CoreAudioApi;
using NAudio.Gui;

namespace HTCommander
{
    public partial class RadioVolumeForm : Form
    {
        private MMDeviceEnumerator deviceEnumerator = new MMDeviceEnumerator();
        private MainForm parent;
        private Radio radio;
        public bool MicrophoneTransmit = false;

        public int Volume { get { return volumeTrackBar.Value; } set { volumeTrackBar.Value = value; } }

        public RadioVolumeForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
        }
        private void RadioVolumeForm_Load(object sender, EventArgs e)
        {
            LoadAudioDevices();
            transmitButton.Image = microphoneImageList.Images[0];
            UpdateInfo();
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

        private void LoadAudioDevices()
        {
            // Load output devices (playback)
            //outputDevices.Clear();
            outputComboBox.Items.Clear();
            outputComboBox.Items.Add(new Utils.ComboBoxItem(null, "Default"));
            foreach (var device in deviceEnumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
            {
                //outputDevices.Add(device);
                outputComboBox.Items.Add(new Utils.ComboBoxItem(device.ID, device.FriendlyName));
            }

            // Select default output device
            var defaultOutput = deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Console);
            SetSelectedDevice(outputComboBox, defaultOutput.ID);

            // Load input devices (recording)
            //inputDevices.Clear();
            inputComboBox.Items.Clear();
            inputComboBox.Items.Add(new Utils.ComboBoxItem(null, "Default"));
            foreach (var device in deviceEnumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                //inputDevices.Add(device);
                inputComboBox.Items.Add(new Utils.ComboBoxItem(device.ID, device.FriendlyName));
            }

            // Select default input device
            var defaultInput = deviceEnumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
            SetSelectedDevice(inputComboBox, defaultInput.ID);
        }


        private void SetSelectedDevice(ComboBox comboBox, string deviceId)
        {
            if (deviceId == null)
            {
                comboBox.SelectedIndex = 0;
            }
            for (int i = 0; i < comboBox.Items.Count; i++)
            {
                if (((Utils.ComboBoxItem)comboBox.Items[i]).Value == deviceId) { comboBox.SelectedIndex = i; break; }
            }
        }

        private void outputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)outputComboBox.SelectedItem;
            string selectedId = selected.Value;
            MMDevice selectedDevice = GetDeviceById(selectedId, DataFlow.Render);
            parent.registry.WriteString("OutputAudioDevice", selectedId == null ? "" : selectedId);

            // Use selectedDevice with WasapiOut, or just store the ID
            //Console.WriteLine("Selected Output Device: " + selectedDevice.FriendlyName);
        }

        private void inputComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)inputComboBox.SelectedItem;
            string selectedId = selected.Value;
            MMDevice selectedDevice = GetDeviceById(selectedId, DataFlow.Capture);
            parent.registry.WriteString("InputAudioDevice", selectedId == null ? "" : selectedId);

            // Use selectedDevice with WasapiCapture or similar
            //Console.WriteLine("Selected Input Device: " + selectedDevice.FriendlyName);
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
            Utils.ComboBoxItem selected = (Utils.ComboBoxItem)outputComboBox.SelectedItem;
            string selectedId = selected.Value;
            MMDevice selectedDevice = GetDeviceById(selectedId, DataFlow.Render);

            float volume = masterVolumeTrackBar.Value / 100f;
            selectedDevice.AudioEndpointVolume.MasterVolumeLevelScalar = volume;
        }

        private void outputTrackBar_Scroll(object sender, EventArgs e)
        {
            radio.OutputVolume = SliderToDecibelScaledFloat(outputTrackBar.Value);
        }

        /// <summary>
        /// Converts a linear slider value (0-100) to a decibel-scaled linear float value (0-1).
        /// </summary>
        /// <param name="sliderValue">The input slider value (0 to 100).</param>
        /// <param name="minDecibels">The minimum decibel level corresponding to slider value 0 (e.g., -40.0f). Must be negative.</param>
        /// <returns>A decibel-scaled linear float value (0 to 1).</returns>
        /// <exception cref="ArgumentException">Thrown if minDecibels is not negative.</exception>
        public static float SliderToDecibelScaledFloat(int sliderValue, float minDecibels = -40.0f)
        {
            return (sliderValue / 100F);

            /*
            if (minDecibels >= 0)
            {
                throw new ArgumentException("minDecibels must be a negative value for decibel scaling.");
            }

            // Clamp the input value to ensure it's within the expected range
            sliderValue = Math.Max(0, Math.Min(100, sliderValue));

            // Handle the edge case for slider value 0 to return exactly 0.0f
            if (sliderValue == 0)
            {
                return 0.0f;
            }

            // Normalize the slider value to a 0-1 range
            float normalizedSliderValue = sliderValue / 100.0f;

            // Calculate the minimum linear amplitude corresponding to minDecibels
            // This value is used to offset the curve so that sliderValue = 0 maps to 0.0f output
            float minLinear = (float)Math.Pow(10, minDecibels / 20.0f);

            // Calculate the intermediate linear value based on the slider position
            // This value ranges from minLinear (at slider 0, conceptually) to 1 (at slider 100)
            // using a decibel-like exponential curve.
            float intermediateLinear = (float)Math.Pow(10, minDecibels * (1.0f - normalizedSliderValue) / 20.0f);

            // Map the intermediate value from the conceptual range [minLinear, 1] to the actual output range [0, 1]
            // This ensures that sliderValue = 0 results in 0.0f and sliderValue = 100 results in 1.0f
            float result = (intermediateLinear - minLinear) / (1.0f - minLinear);

            // Clamp the result to the 0-1 range due to potential floating point inaccuracies near the edges
            return Math.Max(0.0f, Math.Min(1.0f, result));
            */
        }

        /// <summary>
        /// Converts a decibel-scaled linear float value (0-1) back to a linear slider value (0-100).
        /// This is the inverse of SliderToDecibelScaledFloat.
        /// </summary>
        /// <param name="value">The input decibel-scaled linear float value (0 to 1).</param>
        /// <param name="minDecibels">The minimum decibel level used during the forward conversion (e.g., -40.0f). Must be negative.</param>
        /// <returns>A linear slider value (0 to 100).</returns>
        /// <exception cref="ArgumentException">Thrown if minDecibels is not negative.</exception>
        public static int DecibelScaledFloatToSlider(float value, float minDecibels = -40.0f)
        {
            return (int)(value * 100);

            /*
            if (minDecibels >= 0)
            {
                throw new ArgumentException("minDecibels must be a negative value for decibel scaling.");
            }

            // Clamp the input value to ensure it's within the expected range
            value = Math.Max(0.0f, Math.Min(1.0f, value));

            // Handle the edge case for input value 0.0f to return exactly 0
            if (value == 0.0f)
            {
                return 0;
            }

            // Calculate the minimum linear amplitude corresponding to minDecibels
            float minLinear = (float)Math.Pow(10, minDecibels / 20.0f);

            // Reverse the mapping from [0, 1] back to the intermediate conceptual range [minLinear, 1]
            float intermediateLinear = value * (1.0f - minLinear) + minLinear;

            // Reverse the decibel conversion: D = 20 * log10(A)
            // Calculate the decibel value corresponding to the intermediate linear value
            float decibels = 20.0f * (float)Math.Log10(intermediateLinear);

            // Map the decibel value (which ranges from minDecibels to 0) back to a 0-100 slider value
            // This is a linear mapping: Slider = 100 * (Decibels - minDecibels) / (0 - minDecibels)
            float sliderFloat = 100.0f * (decibels - minDecibels) / (0.0f - minDecibels);

            // Clamp and round the result to an integer slider value
            return Math.Max(0, Math.Min(100, (int)Math.Round(sliderFloat)));
            */
        }
    }
}
