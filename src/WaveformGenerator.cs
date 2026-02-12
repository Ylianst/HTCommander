/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using NAudio.Wave;
using System;
using System.IO;

namespace HTCommander
{
    /// <summary>
    /// Generates waveform visualization data from audio files
    /// </summary>
    public class WaveformGenerator
    {
        private const int DefaultSampleCount = 200;

        /// <summary>
        /// Generates waveform data from a WAV file
        /// </summary>
        /// <param name="filePath">Path to the WAV file</param>
        /// <param name="sampleCount">Number of samples to generate (default 200)</param>
        /// <returns>Array of float values representing waveform peaks (normalized -1.0 to 1.0)</returns>
        public static float[] GenerateWaveform(string filePath, int sampleCount = DefaultSampleCount)
        {
            if (!File.Exists(filePath))
            {
                return new float[sampleCount];
            }

            try
            {
                using (var reader = new WaveFileReader(filePath))
                {
                    return GenerateWaveform(reader, sampleCount);
                }
            }
            catch (Exception)
            {
                return new float[sampleCount];
            }
        }

        /// <summary>
        /// Generates waveform data from a WaveStream
        /// </summary>
        public static float[] GenerateWaveform(WaveStream stream, int sampleCount = DefaultSampleCount)
        {
            float[] waveform = new float[sampleCount];
            
            long totalSamples = stream.Length / (stream.WaveFormat.BitsPerSample / 8);
            long samplesPerPoint = Math.Max(1, totalSamples / sampleCount);
            
            byte[] buffer = new byte[stream.WaveFormat.BlockAlign * (int)samplesPerPoint];
            stream.Position = 0;
            
            for (int i = 0; i < sampleCount; i++)
            {
                int bytesRead = stream.Read(buffer, 0, buffer.Length);
                if (bytesRead == 0)
                    break;
                
                waveform[i] = GetPeakValue(buffer, bytesRead, stream.WaveFormat);
            }
            
            return waveform;
        }

        /// <summary>
        /// Gets the peak value from a buffer of audio data
        /// </summary>
        private static float GetPeakValue(byte[] buffer, int bytesRead, WaveFormat format)
        {
            float maxValue = 0f;
            
            if (format.BitsPerSample == 16)
            {
                for (int i = 0; i < bytesRead - 1; i += 2)
                {
                    short sample = BitConverter.ToInt16(buffer, i);
                    float normalized = sample / 32768f;
                    maxValue = Math.Max(maxValue, Math.Abs(normalized));
                }
            }
            else if (format.BitsPerSample == 8)
            {
                for (int i = 0; i < bytesRead; i++)
                {
                    float normalized = (buffer[i] - 128) / 128f;
                    maxValue = Math.Max(maxValue, Math.Abs(normalized));
                }
            }
            
            return maxValue;
        }

        /// <summary>
        /// Generates waveform data while recording audio
        /// </summary>
        public static float[] GenerateWaveformFromRecording(byte[] audioData, WaveFormat format, int sampleCount = DefaultSampleCount)
        {
            float[] waveform = new float[sampleCount];
            
            int totalSamples = audioData.Length / (format.BitsPerSample / 8);
            int samplesPerPoint = Math.Max(1, totalSamples / sampleCount);
            int bytesPerPoint = samplesPerPoint * (format.BitsPerSample / 8) * format.Channels;
            
            for (int i = 0; i < sampleCount; i++)
            {
                int offset = i * bytesPerPoint;
                if (offset >= audioData.Length)
                    break;
                
                int length = Math.Min(bytesPerPoint, audioData.Length - offset);
                waveform[i] = GetPeakValue(audioData, offset, length, format);
            }
            
            return waveform;
        }

        /// <summary>
        /// Gets the peak value from a portion of an audio buffer
        /// </summary>
        private static float GetPeakValue(byte[] buffer, int offset, int length, WaveFormat format)
        {
            float maxValue = 0f;
            
            if (format.BitsPerSample == 16)
            {
                for (int i = offset; i < offset + length - 1; i += 2)
                {
                    if (i + 1 >= buffer.Length)
                        break;
                    
                    short sample = BitConverter.ToInt16(buffer, i);
                    float normalized = sample / 32768f;
                    maxValue = Math.Max(maxValue, Math.Abs(normalized));
                }
            }
            else if (format.BitsPerSample == 8)
            {
                for (int i = offset; i < offset + length; i++)
                {
                    if (i >= buffer.Length)
                        break;
                    
                    float normalized = (buffer[i] - 128) / 128f;
                    maxValue = Math.Max(maxValue, Math.Abs(normalized));
                }
            }
            
            return maxValue;
        }

        /// <summary>
        /// Normalizes waveform data to a maximum peak value
        /// </summary>
        public static void NormalizeWaveform(float[] waveform)
        {
            float maxValue = 0f;
            
            foreach (float value in waveform)
            {
                maxValue = Math.Max(maxValue, Math.Abs(value));
            }
            
            if (maxValue > 0f)
            {
                for (int i = 0; i < waveform.Length; i++)
                {
                    waveform[i] /= maxValue;
                }
            }
        }
    }
}
