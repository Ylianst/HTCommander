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
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using NAudio.Gui;
using NAudio.Wave;
using Whisper.net;

namespace HTCommander.radio // Use your original namespace
{
    public class WhisperEngine
    {
        private WhisperProcessor _processor; // The core Whisper processor
        private readonly WaveFormat _sourceAudioFormat = new WaveFormat(32000, 16, 1);
        private readonly WaveFormat _targetAudioFormat = new WaveFormat(16000, 16, 1);
        private byte[] audioBuffer = null;
        private int audioBufferLength = 0;
        private DateTime audioBufferTime = DateTime.MinValue;
        private string audioBufferChannel = null;
        private DateTime processingAudioBufferTime = DateTime.MinValue;
        private string processingAudioBufferChannel = null;
        private StringBuilder textAccumulator = new StringBuilder();
        private int whisperProgress = 100;
        private bool disposed = false;
        private List<ProcessingHold> ProcessingHolds = new List<ProcessingHold>(); 

        // Holding buffer for audio data
        private class ProcessingHold
        {
            public ProcessingHold(DateTime time, string channel, float[] buffer)
            {
                holdAudioBufferTime = time;
                holdAudioBufferChannel = channel;
                holdAudioBuffer = buffer;
            }
            public DateTime holdAudioBufferTime;
            public string holdAudioBufferChannel;
            public float[] holdAudioBuffer;
        }

        // Event for the final aggregated text when Finish/Reset is called
        public event RadioAudio.OnVoiceTextReady onFinalResultReady;
        // Event for each confirmed segment detected by Whisper
        public event RadioAudio.OnVoiceTextReady onIntermediateResultReady;

        // "ggml-tiny.bin", "ggml-base.bin"
        // Constructor now takes the model path and expected input format
        public WhisperEngine(string modelPath = "ggml-base.bin")
        {
            // Basic validation
            if (string.IsNullOrWhiteSpace(modelPath)) throw new ArgumentNullException(nameof(modelPath));
            if (!File.Exists(modelPath)) throw new FileNotFoundException($"Whisper model file not found: {modelPath}", modelPath);

            // Consider downloading model here if needed (your commented code is a good start)
            // await DownloadModelIfNotExistsAsync(); // Make constructor async if using this

            // --- Factory and Processor Initialization ---
            WhisperFactory factory = WhisperFactory.FromPath(modelPath);
            if (factory == null) throw new InvalidOperationException("WhisperFactory.FromPath returned null.");
            WhisperProcessorBuilder builder = factory.CreateBuilder();
            if (builder == null) throw new InvalidOperationException("WhisperFactory.CreateBuilder returned null.");

            // --- Configure the processor ---
            //.WithLanguageDetection()
            builder = builder.WithLanguage("en").WithThreads(Math.Max(1, Environment.ProcessorCount / 2));
            builder = builder.WithSegmentEventHandler(OnWhisperInternalSegmentReceived);
            builder = builder.WithProgressHandler(OnWhisperProgress);

            _processor = builder.Build();
            if (_processor == null) throw new InvalidOperationException("WhisperProcessorBuilder.Build returned null.");
        }

        public void StartVoiceSegment()
        {

        }

        // Reset finishes the current segment and starts a new one
        public void ResetVoiceSegment()
        {
            ProcessAudioChunk(null, 0, 0, null);
        }

        public void ProcessAudioChunk(byte[] data, int index, int length, string channel)
        {
            if (disposed) return;
            try
            {
                if (length > 0)
                {
                    // Collect the time and channel of the first audio frame
                    if (audioBufferChannel == null)
                    {
                        audioBufferTime = DateTime.Now;
                        audioBufferChannel = channel;
                    }

                    // Gather up a bunch of audio data
                    if (audioBuffer == null) { audioBuffer = new byte[1280000]; audioBufferLength = 0; }
                    Array.Copy(data, index, audioBuffer, audioBufferLength, length);
                    audioBufferLength += length;
                }

                if ((audioBufferLength > 0) && ((audioBufferLength > (audioBuffer.Length - 1024)) || (length == 0)))
                {
                    // Resample the audio from 32kHz to 16kHz
                    byte[] pcm16kBytes = ResampleAudioChunk(audioBuffer, 0, audioBufferLength);
                    if (pcm16kBytes == null || pcm16kBytes.Length == 0) return;

                    // Reset the buffer for the next chunk
                    if (length > 0)
                    {
                        Array.Copy(audioBuffer, 1280000 - 128000, audioBuffer, 0, 128000);
                        audioBufferLength = 128000;
                    }
                    else
                    {
                        audioBufferLength = 0;
                    }

                    if (whisperProgress == 100)
                    {
                        // Convert 16-bit PCM bytes to float[] (-1.0 to 1.0) and process it
                        whisperProgress = 0;
                        processingAudioBufferTime = audioBufferTime;
                        processingAudioBufferChannel = audioBufferChannel;
                        Task.Run(() => { _processor.Process(ConvertPcm16ToFloat32(pcm16kBytes)); });
                    }
                    else
                    {
                        if (ProcessingHolds.Count < 5)
                        {
                            Console.WriteLine("Processing hold added");
                            lock (ProcessingHolds)
                            {
                                ProcessingHolds.Add(new ProcessingHold(audioBufferTime, audioBufferChannel, ConvertPcm16ToFloat32(pcm16kBytes)));
                            }
                        }
                        else
                        {
                            if (onFinalResultReady != null) { onFinalResultReady(null, "(CPU Overloaded)", DateTime.MinValue); }
                        }
                    }
                    audioBufferChannel = null;
                }
            }
            catch (Exception ex)
            {
                int t = 5;
            }
        }

        public void Dispose()
        {
            disposed = true;
            _processor.Dispose();
            _processor = null;
            audioBuffer = null;
            textAccumulator.Clear();
            textAccumulator = null;
        }

        private void OnWhisperInternalSegmentReceived(SegmentData segment)
        {
            string t = segment.Text.Trim();
            if ((t == "[BLANK_AUDIO]") || (t == "(water running)") || (t == "*whistles*") || (t == "[Music]") || (t == "(gunshot)")) return;

            DateTime st = processingAudioBufferTime.Add(segment.Start);

            if (onFinalResultReady != null) { onFinalResultReady(st.ToString("mm:ss.fff") + ": " + segment.Text, processingAudioBufferChannel, processingAudioBufferTime); }

            //textAccumulator.Append(segment.Text);
        }

        private void OnWhisperProgress(int progressPercent)
        {
            whisperProgress = progressPercent;
            if ((progressPercent == 100) && (textAccumulator.Length > 0))
            {
                //if (onFinalResultReady != null) { onFinalResultReady(textAccumulator.ToString().Trim(), processingAudioBufferChannel, processingAudioBufferTime); }
                //textAccumulator.Clear();
            }
            lock (ProcessingHolds)
            {
                if ((progressPercent == 100) && (ProcessingHolds.Count > 0))
                {
                    whisperProgress = 0;
                    ProcessingHold p = ProcessingHolds[0];
                    ProcessingHolds.RemoveAt(0);
                    processingAudioBufferTime = p.holdAudioBufferTime;
                    processingAudioBufferChannel = p.holdAudioBufferChannel;
                    Task.Run(() => { _processor.Process(p.holdAudioBuffer); });
                }
            }
        }

        private float[] ConvertPcm16ToFloat32(byte[] pcm16Bytes)
        {
            int outIndex = 0, sampleCount = pcm16Bytes.Length / 2;
            float[] floatBuffer = new float[sampleCount];
            for (int i = 0; i < pcm16Bytes.Length - 1; i += 2) // Ensure we don't read past bounds
            {
                short sample = BitConverter.ToInt16(pcm16Bytes, i); // Assuming little-endian architecture
                floatBuffer[outIndex++] = (float)sample / 32768.0f; // Normalize to range [-1.0, 1.0]
            }
            return floatBuffer;
        }

        private byte[] ResampleAudioChunk(byte[] inputBytes, int inputIndex, int inputLength)
        {
            using (var sourceStream = new RawSourceWaveStream(inputBytes, inputIndex, inputLength, _sourceAudioFormat))
            using (var resampler = new MediaFoundationResampler(sourceStream, _targetAudioFormat)) // Use MediaFoundationResampler (requires Windows Media Foundation)
            // using (var resampler = new WaveFormatConversionStream(_targetAudioFormat, sourceStream)) // Alternative: WaveFormatConversionStream (more basic, cross-platform)
            {
                // Estimate output size reasonably
                int estimatedOutputLength = (int)((double)inputLength * _targetAudioFormat.SampleRate / _sourceAudioFormat.SampleRate * _targetAudioFormat.Channels / _sourceAudioFormat.Channels * _targetAudioFormat.BitsPerSample / _sourceAudioFormat.BitsPerSample);
                estimatedOutputLength = Math.Max(estimatedOutputLength, _targetAudioFormat.BlockAlign * 16); // Ensure some minimum

                using (var ms = new MemoryStream(estimatedOutputLength))
                {
                    // Buffer size can impact performance, 4k-8k is often reasonable
                    int bytesRead;
                    byte[] buffer = new byte[resampler.WaveFormat.AverageBytesPerSecond / 10]; // ~100ms buffer
                    while ((bytesRead = resampler.Read(buffer, 0, buffer.Length)) > 0) { ms.Write(buffer, 0, bytesRead); }
                    return ms.ToArray();
                }
            }
        }
    }
}