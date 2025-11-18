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

//
// WavFile.cs - WAV file reading and writing
// 

using System;
using System.IO;
using System.Text;

namespace HamLib
{
    /// <summary>
    /// Handles reading and writing of WAV audio files
    /// </summary>
    public class WavFile
    {
        private const int WavHeaderSize = 44;

        /// <summary>
        /// WAV file parameters
        /// </summary>
        public class WavParams
        {
            public int SampleRate { get; set; } = 44100;
            public int BitsPerSample { get; set; } = 16;
            public int NumChannels { get; set; } = 1;
        }

        /// <summary>
        /// Write audio samples to a WAV file
        /// </summary>
        public static void Write(string filename, short[] samples, WavParams parameters)
        {
            using (FileStream fs = new FileStream(filename, FileMode.Create, FileAccess.Write))
            using (BinaryWriter writer = new BinaryWriter(fs))
            {
                int dataSize = samples.Length * sizeof(short);
                int fileSize = WavHeaderSize + dataSize - 8;

                // RIFF header
                writer.Write(Encoding.ASCII.GetBytes("RIFF"));
                writer.Write(fileSize);
                writer.Write(Encoding.ASCII.GetBytes("WAVE"));

                // fmt sub-chunk
                writer.Write(Encoding.ASCII.GetBytes("fmt "));
                writer.Write(16); // Sub-chunk size (16 for PCM)
                writer.Write((short)1); // Audio format (1 = PCM)
                writer.Write((short)parameters.NumChannels);
                writer.Write(parameters.SampleRate);
                writer.Write(parameters.SampleRate * parameters.NumChannels * parameters.BitsPerSample / 8); // Byte rate
                writer.Write((short)(parameters.NumChannels * parameters.BitsPerSample / 8)); // Block align
                writer.Write((short)parameters.BitsPerSample);

                // data sub-chunk
                writer.Write(Encoding.ASCII.GetBytes("data"));
                writer.Write(dataSize);

                // Write sample data
                foreach (short sample in samples)
                {
                    writer.Write(sample);
                }
            }
        }

        /// <summary>
        /// Read audio samples from a WAV file
        /// </summary>
        public static (short[] samples, WavParams parameters) Read(string filename)
        {
            using (FileStream fs = new FileStream(filename, FileMode.Open, FileAccess.Read))
            using (BinaryReader reader = new BinaryReader(fs))
            {
                // Read RIFF header
                string riff = Encoding.ASCII.GetString(reader.ReadBytes(4));
                if (riff != "RIFF")
                    throw new InvalidDataException("Not a valid WAV file (missing RIFF header)");

                int fileSize = reader.ReadInt32();
                string wave = Encoding.ASCII.GetString(reader.ReadBytes(4));
                if (wave != "WAVE")
                    throw new InvalidDataException("Not a valid WAV file (missing WAVE header)");

                // Read fmt sub-chunk
                string fmt = Encoding.ASCII.GetString(reader.ReadBytes(4));
                if (fmt != "fmt ")
                    throw new InvalidDataException("Not a valid WAV file (missing fmt header)");

                int fmtSize = reader.ReadInt32();
                short audioFormat = reader.ReadInt16();
                if (audioFormat != 1)
                    throw new NotSupportedException("Only PCM format is supported");

                var parameters = new WavParams
                {
                    NumChannels = reader.ReadInt16(),
                    SampleRate = reader.ReadInt32()
                };

                int byteRate = reader.ReadInt32();
                short blockAlign = reader.ReadInt16();
                parameters.BitsPerSample = reader.ReadInt16();

                // Skip any extra format bytes
                if (fmtSize > 16)
                {
                    reader.ReadBytes(fmtSize - 16);
                }

                // Find data sub-chunk (there might be other chunks)
                string chunkId;
                int chunkSize;
                do
                {
                    chunkId = Encoding.ASCII.GetString(reader.ReadBytes(4));
                    chunkSize = reader.ReadInt32();

                    if (chunkId != "data")
                    {
                        // Skip this chunk
                        reader.ReadBytes(chunkSize);
                    }
                }
                while (chunkId != "data" && fs.Position < fs.Length);

                if (chunkId != "data")
                    throw new InvalidDataException("No data chunk found in WAV file");

                // Read sample data
                int numSamples = chunkSize / (parameters.BitsPerSample / 8);
                short[] samples = new short[numSamples];

                if (parameters.BitsPerSample == 16)
                {
                    for (int i = 0; i < numSamples; i++)
                    {
                        samples[i] = reader.ReadInt16();
                    }
                }
                else if (parameters.BitsPerSample == 8)
                {
                    for (int i = 0; i < numSamples; i++)
                    {
                        // Convert 8-bit unsigned to 16-bit signed
                        byte b = reader.ReadByte();
                        samples[i] = (short)((b - 128) * 256);
                    }
                }
                else
                {
                    throw new NotSupportedException($"Bits per sample {parameters.BitsPerSample} not supported");
                }

                return (samples, parameters);
            }
        }

        /// <summary>
        /// Get duration of a WAV file in seconds
        /// </summary>
        public static double GetDuration(short[] samples, int sampleRate)
        {
            return (double)samples.Length / sampleRate;
        }
    }
}
