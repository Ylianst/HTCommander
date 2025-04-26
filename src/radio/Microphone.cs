using System;
using NAudio.CoreAudioApi;
using System.Text.RegularExpressions;
using NAudio.Wave;

namespace HTCommander.radio
{
    public class Microphone
    {
        //private WaveInEvent waveSource = null;

        public delegate void DataAvailableHandler(byte[] data, int bytesRecorded);
        public event DataAvailableHandler DataAvailable;
        private WasapiCapture capture = null;
        private MMDevice selectedDevice = null;

        public void SetInputDevice(string deviceid)
        {
            var enumerator = new MMDeviceEnumerator();

            if (string.IsNullOrEmpty(deviceid))
            {
                selectedDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
                Dispose();
                StartListening();
                return;
            }

            var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active);
            foreach (var device in devices)
            {
                if (device.ID.Equals(deviceid, StringComparison.OrdinalIgnoreCase))
                {
                    selectedDevice = device;
                    Dispose();
                    StartListening();
                    return;
                }
            }

            // Fallback to default device if the specified one is not found
            selectedDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
            Dispose();
            StartListening();
        }

        public bool StartListening()
        {
            if (selectedDevice == null) { return false; }

            capture = new WasapiCapture(selectedDevice) { ShareMode = AudioClientShareMode.Shared };
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
            if (DataAvailable != null) { DataAvailable(args.Buffer, args.BytesRecorded); }
            // args.Buffer contains the raw PCM audio data
            // args.BytesRecorded tells you how many bytes in the buffer are valid audio data
            //Console.WriteLine($"Received {args.BytesRecorded} bytes of audio data.");
        }

        // --- Event Handler for When Recording Stops ---
        private void OnRecordingStopped(object sender, StoppedEventArgs args)
        {
            if (args.Exception != null) { Console.WriteLine($"An error occurred during recording: {args.Exception.Message}"); }
            Dispose();
        }

    }
}