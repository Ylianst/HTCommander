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
// AfskEncoder.cs - AFSK encoder for creating WAV files
//

using System;
using System.Collections.Generic;
using System.Text;

namespace HamLib
{
    /// <summary>
    /// Encodes messages to AFSK audio in WAV format
    /// </summary>
    public class AfskEncoder
    {
        private AudioConfig _audioConfig;
        private GenTone _genTone;
        private HdlcSend _hdlcSend;
        private AudioBuffer _audioBuffer;

        public AfskEncoder()
        {
            // Set up default configuration for AFSK 1200 baud
            ConfigureFor1200Baud();
        }

        private void ConfigureFor1200Baud()
        {
            _audioConfig = new AudioConfig();
            _audioConfig.Devices[0].Defined = true;
            _audioConfig.Devices[0].SamplesPerSec = 44100;
            _audioConfig.Devices[0].BitsPerSample = 16;
            _audioConfig.Devices[0].NumChannels = 1;

            _audioConfig.ChannelMedium[0] = Medium.Radio;
            _audioConfig.Channels[0].ModemType = ModemType.Afsk;
            _audioConfig.Channels[0].MarkFreq = 1200;
            _audioConfig.Channels[0].SpaceFreq = 2200;
            _audioConfig.Channels[0].Baud = 1200;
            _audioConfig.Channels[0].Txdelay = 30; // 300ms
            _audioConfig.Channels[0].Txtail = 10; // 100ms

            _audioBuffer = new AudioBuffer(AudioConfig.MaxAudioDevices);
            _genTone = new GenTone(_audioBuffer);
            _genTone.Init(_audioConfig, 50); // 50% amplitude

            _hdlcSend = new HdlcSend(_genTone, _audioConfig);
        }

        private void ConfigureFor9600Baud()
        {
            _audioConfig = new AudioConfig();
            _audioConfig.Devices[0].Defined = true;
            _audioConfig.Devices[0].SamplesPerSec = 44100;
            _audioConfig.Devices[0].BitsPerSample = 16;
            _audioConfig.Devices[0].NumChannels = 1;

            _audioConfig.ChannelMedium[0] = Medium.Radio;
            _audioConfig.Channels[0].ModemType = ModemType.Scramble;  // Use scrambled baseband for 9600
            _audioConfig.Channels[0].Baud = 9600;
            _audioConfig.Channels[0].Txdelay = 30; // 300ms
            _audioConfig.Channels[0].Txtail = 10; // 100ms

            _audioBuffer = new AudioBuffer(AudioConfig.MaxAudioDevices);
            _genTone = new GenTone(_audioBuffer);
            _genTone.Init(_audioConfig, 50); // 50% amplitude

            _hdlcSend = new HdlcSend(_genTone, _audioConfig);
        }

        /// <summary>
        /// Encode a message to AFSK/9600 baud and save as WAV file
        /// </summary>
        public void EncodeToWav(string message, string outputFile, bool use9600 = false)
        {
            // Reconfigure if needed
            if (use9600)
            {
                ConfigureFor9600Baud();
            }
            else
            {
                ConfigureFor1200Baud();
            }

            int chan = 0;

            // Clear any previous data
            _audioBuffer.ClearAll();

            // Create the frame data
            byte[] frameData = CreateAx25Frame(message);

            // Generate preamble flags (txdelay)
            int txdelayFlags = _audioConfig.Channels[chan].Txdelay;
            _hdlcSend.SendFlags(chan, txdelayFlags, false, null);

            // Send the actual frame
            _hdlcSend.SendFrame(chan, frameData, frameData.Length, false);

            // Generate postamble flags (txtail)
            int txtailFlags = _audioConfig.Channels[chan].Txtail;
            _hdlcSend.SendFlags(chan, txtailFlags, true, (device) => { });

            // Get the audio samples
            short[] samples = _audioBuffer.GetAndClear(0);

            // Write to WAV file
            var wavParams = new WavFile.WavParams
            {
                SampleRate = _audioConfig.Devices[0].SamplesPerSec,
                BitsPerSample = _audioConfig.Devices[0].BitsPerSample,
                NumChannels = _audioConfig.Devices[0].NumChannels
            };

            WavFile.Write(outputFile, samples, wavParams);

            Console.WriteLine($"Encoded {samples.Length} samples to {outputFile}");
            Console.WriteLine($"Duration: {WavFile.GetDuration(samples, wavParams.SampleRate):F2} seconds");
            Console.WriteLine($"Baud rate: {_audioConfig.Channels[chan].Baud}");
            Console.WriteLine($"Modulation: {_audioConfig.Channels[chan].ModemType}");
        }

        /// <summary>
        /// Create a basic AX.25 UI frame
        /// </summary>
        private byte[] CreateAx25Frame(string message)
        {
            List<byte> frame = new List<byte>();

            // Destination address: "APRS" (typical APRS destination)
            AddAddress(frame, "APRS", 0, false);

            // Source address: "NOCALL" with SSID 0
            AddAddress(frame, "NOCALL", 0, true); // Last address bit set

            // Control field: 0x03 (UI frame)
            frame.Add(0x03);

            // Protocol ID: 0xF0 (no layer 3)
            frame.Add(0xF0);

            // Information field (the message)
            byte[] messageBytes = Encoding.ASCII.GetBytes(message);
            frame.AddRange(messageBytes);

            return frame.ToArray();
        }

        /// <summary>
        /// Add an AX.25 address to the frame
        /// </summary>
        private void AddAddress(List<byte> frame, string callsign, int ssid, bool isLast)
        {
            // Pad callsign to 6 characters
            callsign = callsign.PadRight(6, ' ').Substring(0, 6);

            // Each character shifted left by 1
            foreach (char c in callsign)
            {
                frame.Add((byte)(c << 1));
            }

            // SSID byte: bits 7-5 are reserved (usually 011), bits 4-1 are SSID, bit 0 is last address flag
            byte ssidByte = (byte)(0x60 | ((ssid & 0x0F) << 1));
            if (isLast)
            {
                ssidByte |= 0x01;
            }
            frame.Add(ssidByte);
        }

    }
}
