using System;
using NAudio.Wave;

namespace HTCommander.radio
{
    public class Microphone
    {
        private WaveInEvent waveSource = null;

        public delegate void DataAvailableHandler(byte[] data, int bytesRecorded);
        public event DataAvailableHandler DataAvailable;

        public bool StartListening()
        {
            if (waveSource != null) return false;

            waveSource = new WaveInEvent
            {
                DeviceNumber = 0, // 0 is usually the default input device
                WaveFormat = new WaveFormat(32000, 16, 1),
                // How often to raise the DataAvailable event (e.g., every 100ms)
                // Smaller buffer sizes mean lower latency but more frequent events.
                BufferMilliseconds = 80
            };

            waveSource.DataAvailable += OnDataAvailable;
            waveSource.RecordingStopped += OnRecordingStopped;

            try
            {
                waveSource.StartRecording();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error starting recording: {ex.Message}");
                Dispose(); // Clean up if start failed
                return false;
            }
            return true;
        }

        public bool StopListening()
        {
            if (waveSource == null) return false;
            waveSource?.StopRecording();
            // The actual stop confirmation and cleanup happens in OnRecordingStopped
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

        // --- Resource Cleanup ---
        private void Dispose()
        {
            if (waveSource == null) return;
            waveSource.DataAvailable -= OnDataAvailable;
            waveSource.RecordingStopped -= OnRecordingStopped;
            waveSource.Dispose();
            waveSource = null;
            Console.WriteLine("WaveSource disposed.");
        }
    }
}