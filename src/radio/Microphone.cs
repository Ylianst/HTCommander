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
using NAudio.Wave;
using NAudio.CoreAudioApi;

namespace HTCommander.radio
{
    public class Microphone
    {
        public delegate void DataAvailableHandler(byte[] data, int bytesRecorded);
        public event DataAvailableHandler DataAvailable;
        private WasapiCapture capture = null;
        private MMDevice selectedDevice = null;
        public float Boost = 0;

        public void SetInputDevice(string deviceid)
        {
            try { if ((selectedDevice != null) && (selectedDevice.ID == deviceid)) return; } catch (Exception) { }

            var enumerator = new MMDeviceEnumerator();
            MMDevice targetDevice = null;

            if (string.IsNullOrEmpty(deviceid))
            {
                try { targetDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console); } catch (Exception) { }
                if (targetDevice == selectedDevice) return;
                selectedDevice = targetDevice;
                if (capture != null) StartListening();
                return;
            }

            var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active);
            foreach (var device in devices)
            {
                if (device.ID.Equals(deviceid, StringComparison.OrdinalIgnoreCase))
                {
                    targetDevice = device;
                    if (targetDevice == selectedDevice) return;
                    selectedDevice = targetDevice;
                    if (capture != null) StartListening();
                    return;
                }
            }

            // Fallback to default device if the specified one is not found
            try { targetDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console); } catch (Exception) { }
            if (targetDevice == selectedDevice) return;
            selectedDevice = targetDevice;
            if (capture != null) StartListening();
        }

        public bool StartListening()
        {
            if (selectedDevice == null) { return false; }

            Dispose();
            WaveFormat format = new WaveFormat(32000, 16, 1);
            capture = new WasapiCapture(selectedDevice, true, 1) { ShareMode = AudioClientShareMode.Shared, WaveFormat = format };
            capture.ShareMode = AudioClientShareMode.Shared;
            capture.WaveFormat = format;
            capture.DataAvailable += OnDataAvailable;
            capture.RecordingStopped += OnRecordingStopped;

            try
            {
                capture.StartRecording();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error starting recording: {ex.Message}");
                Dispose();
                return false;
            }

            return true;
        }

        private void Dispose()
        {
            if (capture != null)
            {
                capture.DataAvailable -= OnDataAvailable;
                capture.RecordingStopped -= OnRecordingStopped;
                capture.Dispose();
                capture = null;
            }
        }

        public bool StopListening()
        {
            if (capture == null) return false;
            Dispose();
            return true;
        }

        private void OnDataAvailable(object sender, WaveInEventArgs args)
        {
            if (args.BytesRecorded == 0) return;
            BoostVolume(args.Buffer, args.BytesRecorded, Boost);
            if (DataAvailable != null) { DataAvailable(args.Buffer, args.BytesRecorded); }
        }

        // --- Event Handler for When Recording Stops ---
        private void OnRecordingStopped(object sender, StoppedEventArgs args)
        {
            if (args.Exception != null) { Console.WriteLine($"An error occurred during recording: {args.Exception.Message}"); }
            Dispose();
        }

        private void BoostVolume(byte[] buffer, int bytesRecorded, float volume)
        {
            if (volume <= 0) return;
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

    }
}