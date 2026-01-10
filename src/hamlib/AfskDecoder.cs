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

//
// AfskDecoder.cs - AFSK decoder
//

using System;
using System.Collections.Generic;
using System.Text;

namespace HamLib
{
    /// <summary>
    /// Decodes AFSK audio from WAV files using the ported demodulator components
    /// </summary>
    public class AfskDecoder
    {
        private PacketCollector _packetCollector;
        private HdlcRecWithCollector _hdlcRecCollector;
        private double _errorRate = 0.0;
        private Random _random = new Random();
        private int _totalBits = 0;
        private int _flippedBits = 0;

        public AfskDecoder()
        {
            _packetCollector = new PacketCollector();
        }

        /// <summary>
        /// Set the bit error rate for testing error correction
        /// </summary>
        /// <param name="errorRate">Error rate (0.0 to 1.0, e.g., 0.01 = 1%)</param>
        public void SetErrorRate(double errorRate)
        {
            _errorRate = Math.Max(0.0, Math.Min(1.0, errorRate));
        }

        /// <summary>
        /// Get statistics on bit flipping
        /// </summary>
        public (int total, int flipped) GetBitErrorStats()
        {
            return (_totalBits, _flippedBits);
        }

        /// <summary>
        /// Event handler for displaying frames as they are received
        /// </summary>
        private void OnFrameReceived(object sender, FrameReceivedEventArgs e)
        {
            // Create packet from frame
            var alevel = new ALevel(e.AudioLevel.Rec, e.AudioLevel.Mark, e.AudioLevel.Space);
            var packet = Packet.FromFrame(e.Frame, e.FrameLength, alevel);
            
            if (packet != null && packet.IsAprs())
            {
                // Display decoded message
                Console.WriteLine($"**Source: {packet.GetAddrWithSsid(Ax25Constants.Source)}");
                Console.WriteLine($"  Destination: {packet.GetAddrWithSsid(Ax25Constants.Destination)}");
                
                // Display correction information if available
                if (e.CorrectionInfo != null && e.CorrectionInfo.CorrectionType != RetryType.None)
                {
                    string correctionMsg;
                    switch (e.CorrectionInfo.CorrectionType)
                    {
                        case RetryType.InvertSingle:
                            correctionMsg = $"Corrected 1 bit (position {string.Join(", ", e.CorrectionInfo.CorrectedBitPositions)})";
                            break;
                        case RetryType.InvertDouble:
                            correctionMsg = $"Corrected 2 adjacent bits (positions {string.Join(", ", e.CorrectionInfo.CorrectedBitPositions)})";
                            break;
                        case RetryType.InvertTriple:
                            correctionMsg = $"Corrected 3 adjacent bits (positions {string.Join(", ", e.CorrectionInfo.CorrectedBitPositions)})";
                            break;
                        case RetryType.InvertTwoSep:
                            correctionMsg = $"Corrected 2 separated bits (positions {string.Join(", ", e.CorrectionInfo.CorrectedBitPositions)})";
                            break;
                        default:
                            correctionMsg = "Unknown correction applied";
                            break;
                    }
                    Console.WriteLine($"  Fix Applied: {correctionMsg}");
                }
                else
                {
                    Console.WriteLine($"  Fix Applied: No correction needed (CRC valid)");
                }
                
                // Extract and display message
                var info = packet.GetInfo(out int infoLen);
                StringBuilder message = new StringBuilder();
                for (int i = 0; i < infoLen; i++)
                {
                    if (info[i] >= 32 && info[i] <= 126)
                    {
                        message.Append((char)info[i]);
                    }
                }

                Console.WriteLine($"  Message: {message.ToString()}");
            }
        }

        /// <summary>
        /// Decode AFSK audio from WAV file with debug output
        /// </summary>
        public string DecodeFromWavWithDebug(string inputFile)
        {
            try
            {
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine("                  AFSK DECODER - STARTING");
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine();

                // Read the WAV file
                Console.WriteLine("[STEP 1] Reading WAV file...");
                var (samples, wavParams) = WavFile.Read(inputFile);

                Console.WriteLine($"  ✓ Read {samples.Length} samples from {inputFile}");
                Console.WriteLine($"  ✓ Sample rate: {wavParams.SampleRate} Hz");
                Console.WriteLine($"  ✓ Duration: {WavFile.GetDuration(samples, wavParams.SampleRate):F2} seconds");
                Console.WriteLine($"  ✓ First few samples: {samples[0]}, {samples[1]}, {samples[2]}, {samples[3]}, {samples[4]}");
                Console.WriteLine();

                // Setup audio configuration
                Console.WriteLine("[STEP 2] Configuring AFSK demodulator...");
                var audioConfig = new AudioConfig();
                audioConfig.Devices[0].Defined = true;
                audioConfig.Devices[0].SamplesPerSec = wavParams.SampleRate;
                audioConfig.Devices[0].BitsPerSample = wavParams.BitsPerSample;
                audioConfig.Devices[0].NumChannels = wavParams.NumChannels;

                // Configure for AFSK 1200 baud
                audioConfig.ChannelMedium[0] = Medium.Radio;
                audioConfig.Channels[0].ModemType = ModemType.Afsk;
                audioConfig.Channels[0].MarkFreq = 1200;
                audioConfig.Channels[0].SpaceFreq = 2200;
                audioConfig.Channels[0].Baud = 1200;
                audioConfig.Channels[0].NumSubchan = 1;

                Console.WriteLine($"  ✓ Modem: AFSK 1200 baud");
                Console.WriteLine($"  ✓ Mark frequency: 1200 Hz");
                Console.WriteLine($"  ✓ Space frequency: 2200 Hz");
                Console.WriteLine();

                // Create HDLC receiver with packet collector
                Console.WriteLine("[STEP 3] Initializing HDLC receiver...");
                var hdlcRecCollector = new HdlcRecWithCollector(_packetCollector, debugMode: true);
                hdlcRecCollector.Init(audioConfig);
                Console.WriteLine("  ✓ HDLC receiver initialized");
                Console.WriteLine();

                // Create and initialize demodulator with error injection if configured
                Console.WriteLine("[STEP 4] Initializing AFSK demodulator (Profile A)...");
                IHdlcReceiver receiver = hdlcRecCollector.GetHdlcRec();
                if (_errorRate > 0.0)
                {
                    receiver = new BitErrorInjector(receiver, _errorRate, _random, ref _totalBits, ref _flippedBits);
                    Console.WriteLine($"  ✓ Bit error injection enabled at {_errorRate * 100:F5}%");
                }
                var demodAfsk = new DemodAfsk(receiver);
                var demodState = new DemodulatorState();
                demodAfsk.Init(
                    wavParams.SampleRate,
                    audioConfig.Channels[0].Baud,
                    audioConfig.Channels[0].MarkFreq,
                    audioConfig.Channels[0].SpaceFreq,
                    'A',
                    demodState
                );
                Console.WriteLine($"  ✓ Demodulator initialized");
                Console.WriteLine($"  ✓ PLL step per sample: {demodState.PllStepPerSample}");
                Console.WriteLine($"  ✓ Low-pass filter taps: {demodState.LpFilterTaps}");
                Console.WriteLine();

                // Process all samples
                Console.WriteLine("[STEP 5] Processing audio samples...");
                Console.WriteLine($"  Processing {samples.Length} samples...");
                int chan = 0;
                int subchan = 0;

                for (int i = 0; i < samples.Length; i++)
                {
                    demodAfsk.ProcessSample(chan, subchan, samples[i], demodState);
                    
                    // Progress indicator every 10000 samples
                    if ((i + 1) % 10000 == 0)
                    {
                        float progress = (i + 1) * 100.0f / samples.Length;
                        Console.Write($"\r  Progress: {progress:F1}% ({i + 1}/{samples.Length} samples)");
                    }
                }
                Console.WriteLine($"\r  ✓ Completed: 100.0% ({samples.Length}/{samples.Length} samples)");
                Console.WriteLine();

                // Check for collected packets
                Console.WriteLine("[STEP 6] Checking for decoded packets...");
                var packets = _packetCollector.GetPackets();
                
                Console.WriteLine($"  Found {packets.Count} packet(s)");
                
                // Display bit error statistics if error injection was enabled
                if (_errorRate > 0.0)
                {
                    Console.WriteLine();
                    Console.WriteLine($"Bit Error Statistics:");
                    Console.WriteLine($"  Total bits processed: {_totalBits}");
                    Console.WriteLine($"  Bits flipped: {_flippedBits}");
                    Console.WriteLine($"  Actual error rate: {(_totalBits > 0 ? (_flippedBits * 100.0 / _totalBits) : 0.0):F5}%");
                }
                Console.WriteLine();

                // Display all bits received by HDLC decoder (RAW bits before NRZI)
                var allBits = hdlcRecCollector.GetHdlcRec().GetAllReceivedBits();
                Console.WriteLine($"[BIT DUMP] Total RAW bits received by HDLC decoder: {allBits.Count}");
                
                // Display NRZI decoded bits
                var decodedBits = hdlcRecCollector.GetHdlcRec().GetAllDecodedBits();
                Console.WriteLine($"[BIT DUMP] Total bits after NRZI decoding: {decodedBits.Count}");
                Console.WriteLine();
                
                if (allBits.Count > 0)
                {
                    Console.WriteLine("════════════════════════════════════════════════════════════");
                    Console.WriteLine("         RAW BITS SENT TO HDLC DECODER (before NRZI)");
                    Console.WriteLine("════════════════════════════════════════════════════════════");
                    Console.WriteLine();
                    
                    // Display as binary (80 bits per line)
                    Console.WriteLine("Binary format (80 bits per line, with spaces every 8 bits):");
                    Console.WriteLine();
                    for (int i = 0; i < allBits.Count; i++)
                    {
                        Console.Write(allBits[i]);
                        if ((i + 1) % 80 == 0)
                        {
                            Console.WriteLine($"  // Bits {i - 79} to {i}");
                        }
                        else if ((i + 1) % 8 == 0)
                        {
                            Console.Write(" ");
                        }
                    }
                    if (allBits.Count % 80 != 0)
                    {
                        Console.WriteLine($"  // Bits {(allBits.Count / 80) * 80} to {allBits.Count - 1}");
                    }
                    Console.WriteLine();
                    
                    // Display as hex bytes
                    Console.WriteLine("Hex format (bytes, 16 per line):");
                    Console.WriteLine();
                    int byteCount = 0;
                    for (int i = 0; i + 7 < allBits.Count; i += 8)
                    {
                        int byteVal = 0;
                        for (int bit = 0; bit < 8; bit++)
                        {
                            byteVal = (byteVal << 1) | allBits[i + bit];
                        }
                        Console.Write($"{byteVal:X2} ");
                        byteCount++;
                        if (byteCount % 16 == 0)
                        {
                            Console.WriteLine($" // Bytes {byteCount - 15} to {byteCount}");
                        }
                    }
                    if (byteCount % 16 != 0)
                    {
                        Console.WriteLine($" // Bytes {(byteCount / 16) * 16 + 1} to {byteCount}");
                    }
                    Console.WriteLine();
                    Console.WriteLine($"Total: {byteCount} complete bytes ({allBits.Count} bits)");
                    
                    // Show first 16 bytes as ASCII if printable
                    Console.WriteLine();
                    Console.WriteLine("First bytes as ASCII (if printable):");
                    for (int i = 0; i + 7 < Math.Min(allBits.Count, 128); i += 8)
                    {
                        int byteVal = 0;
                        for (int bit = 0; bit < 8; bit++)
                        {
                            byteVal = (byteVal << 1) | allBits[i + bit];
                        }
                        char c = (char)byteVal;
                        if (c >= 32 && c <= 126)
                            Console.Write(c);
                        else
                            Console.Write($"[{byteVal:X2}]");
                    }
                    Console.WriteLine();
                    Console.WriteLine();
                }

                // Display NRZI decoded bits
                if (decodedBits.Count > 0)
                {
                    Console.WriteLine("════════════════════════════════════════════════════════════");
                    Console.WriteLine("         BITS AFTER NRZI DECODING (HDLC bit stream)");
                    Console.WriteLine("════════════════════════════════════════════════════════════");
                    Console.WriteLine();
                    
                    // Display as binary (80 bits per line)
                    Console.WriteLine("Binary format (80 bits per line, with spaces every 8 bits):");
                    Console.WriteLine();
                    for (int i = 0; i < decodedBits.Count; i++)
                    {
                        Console.Write(decodedBits[i]);
                        if ((i + 1) % 80 == 0)
                        {
                            Console.WriteLine($"  // Bits {i - 79} to {i}");
                        }
                        else if ((i + 1) % 8 == 0)
                        {
                            Console.Write(" ");
                        }
                    }
                    if (decodedBits.Count % 80 != 0)
                    {
                        Console.WriteLine($"  // Bits {(decodedBits.Count / 80) * 80} to {decodedBits.Count - 1}");
                    }
                    Console.WriteLine();
                    
                    // Display as hex bytes
                    Console.WriteLine("Hex format (bytes, 16 per line):");
                    Console.WriteLine();
                    int decodedByteCount = 0;
                    for (int i = 0; i + 7 < decodedBits.Count; i += 8)
                    {
                        int byteVal = 0;
                        for (int bit = 0; bit < 8; bit++)
                        {
                            byteVal = (byteVal << 1) | decodedBits[i + bit];
                        }
                        Console.Write($"{byteVal:X2} ");
                        decodedByteCount++;
                        if (decodedByteCount % 16 == 0)
                        {
                            Console.WriteLine($" // Bytes {decodedByteCount - 15} to {decodedByteCount}");
                        }
                    }
                    if (decodedByteCount % 16 != 0)
                    {
                        Console.WriteLine($" // Bytes {(decodedByteCount / 16) * 16 + 1} to {decodedByteCount}");
                    }
                    Console.WriteLine();
                    Console.WriteLine($"Total: {decodedByteCount} complete bytes ({decodedBits.Count} bits)");
                    
                    // Show first bytes as ASCII if printable
                    Console.WriteLine();
                    Console.WriteLine("First bytes as ASCII (if printable):");
                    for (int i = 0; i + 7 < Math.Min(decodedBits.Count, 128); i += 8)
                    {
                        int byteVal = 0;
                        for (int bit = 0; bit < 8; bit++)
                        {
                            byteVal = (byteVal << 1) | decodedBits[i + bit];
                        }
                        char c = (char)byteVal;
                        if (c >= 32 && c <= 126)
                            Console.Write(c);
                        else
                            Console.Write($"[{byteVal:X2}]");
                    }
                    Console.WriteLine();
                    
                    // Look for HDLC flag patterns (0x7E = 01111110)
                    Console.WriteLine();
                    Console.WriteLine("HDLC Flag Pattern Analysis (looking for 0x7E = 01111110):");
                    for (int i = 0; i + 7 < decodedBits.Count; i += 8)
                    {
                        int byteVal = 0;
                        for (int bit = 0; bit < 8; bit++)
                        {
                            byteVal = (byteVal << 1) | decodedBits[i + bit];
                        }
                    }
                    Console.WriteLine();
                    Console.WriteLine();
                }

                // Extract message from first packet
                var packet = packets[0];
                var info = packet.GetInfo(out int infoLen);
                
                // Convert to string, removing control bytes
                StringBuilder message = new StringBuilder();
                for (int i = 0; i < infoLen; i++)
                {
                    if (info[i] >= 32 && info[i] <= 126)
                    {
                        message.Append((char)info[i]);
                    }
                }

                string result = message.ToString();
                
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine("                  DECODE SUCCESSFUL!");
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine();
                Console.WriteLine($"  Packets decoded: {packets.Count}");
                Console.WriteLine($"  Source: {packet.GetAddrWithSsid(Ax25Constants.Source)}");
                Console.WriteLine($"  Destination: {packet.GetAddrWithSsid(Ax25Constants.Destination)}");
                Console.WriteLine($"  Message length: {infoLen} bytes");
                Console.WriteLine();
                Console.WriteLine($"  Message: {result}");
                Console.WriteLine();

                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error decoding file: {ex.Message}");
                Console.WriteLine(ex.StackTrace);
                return null;
            }
        }

        /// <summary>
        /// Decode AFSK audio from WAV file (without debug messages)
        /// </summary>
        public string DecodeFromWav(string inputFile, bool use9600 = false)
        {
            try
            {
                // Read the WAV file
                var (samples, wavParams) = WavFile.Read(inputFile);

                // Setup audio configuration
                var audioConfig = new AudioConfig();
                audioConfig.Devices[0].Defined = true;
                audioConfig.Devices[0].SamplesPerSec = wavParams.SampleRate;
                audioConfig.Devices[0].BitsPerSample = wavParams.BitsPerSample;
                audioConfig.Devices[0].NumChannels = wavParams.NumChannels;

                // Configure for selected baud rate
                audioConfig.ChannelMedium[0] = Medium.Radio;
                if (use9600)
                {
                    audioConfig.Channels[0].ModemType = ModemType.Scramble;
                    audioConfig.Channels[0].Baud = 9600;
                }
                else
                {
                    audioConfig.Channels[0].ModemType = ModemType.Afsk;
                    audioConfig.Channels[0].MarkFreq = 1200;
                    audioConfig.Channels[0].SpaceFreq = 2200;
                    audioConfig.Channels[0].Baud = 1200;
                }
                audioConfig.Channels[0].NumSubchan = 1;

                // Create HDLC receiver with packet collector and register for frame events
                _hdlcRecCollector = new HdlcRecWithCollector(_packetCollector, debugMode: false);
                _hdlcRecCollector.GetHdlcRec().FrameReceived += OnFrameReceived;
                _hdlcRecCollector.Init(audioConfig);

                // Create and initialize demodulator with error injection if configured
                IHdlcReceiver receiver = _hdlcRecCollector.GetHdlcRec();
                if (_errorRate > 0.0)
                {
                    receiver = new BitErrorInjector(receiver, _errorRate, _random, ref _totalBits, ref _flippedBits);
                }

                int chan = 0;
                int subchan = 0;

                if (use9600)
                {
                    // Use 9600 baud baseband demodulator
                    var demodState = new DemodulatorState();
                    var state9600 = new Demod9600.Demod9600State();
                    
                    int upsample = 1; // No upsampling for now
                    Demod9600.Init(wavParams.SampleRate, upsample, audioConfig.Channels[0].Baud, 
                        demodState, state9600);

                    // Process all samples with 9600 baud demodulator
                    for (int i = 0; i < samples.Length; i++)
                    {
                        Demod9600.ProcessSample(chan, samples[i], upsample, demodState, state9600, receiver);
                    }
                }
                else
                {
                    // Use AFSK 1200 baud demodulator
                    var demodAfsk = new DemodAfsk(receiver);
                    var demodState = new DemodulatorState();
                    demodAfsk.Init(
                        wavParams.SampleRate,
                        audioConfig.Channels[0].Baud,
                        audioConfig.Channels[0].MarkFreq,
                        audioConfig.Channels[0].SpaceFreq,
                        'A',
                        demodState
                    );

                    // Process all samples with AFSK demodulator
                    for (int i = 0; i < samples.Length; i++)
                    {
                        demodAfsk.ProcessSample(chan, subchan, samples[i], demodState);
                    }
                }

                // Display bit error statistics if error injection was enabled
                if (_errorRate > 0.0 && _totalBits > 0)
                {
                    Console.WriteLine();
                    Console.WriteLine($"Bit Error Statistics:");
                    Console.WriteLine($"  Total bits processed: {_totalBits}");
                    Console.WriteLine($"  Bits flipped: {_flippedBits}");
                    Console.WriteLine($"  Actual error rate: {(_flippedBits * 100.0 / _totalBits):F5}%");
                    Console.WriteLine();
                }

                // Return first decoded message if available
                var packets = _packetCollector.GetPackets();
                if (packets.Count > 0)
                {
                    var packet = packets[0];
                    var info = packet.GetInfo(out int infoLen);
                    
                    // Convert to string, removing control bytes
                    StringBuilder message = new StringBuilder();
                    for (int i = 0; i < infoLen; i++)
                    {
                        if (info[i] >= 32 && info[i] <= 126)
                        {
                            message.Append((char)info[i]);
                        }
                    }
                    
                    return message.ToString();
                }
                
                return null;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error decoding file: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Decode AFSK audio from WAV file with FX.25 error correction support
        /// </summary>
        public string DecodeFromWavFx25(string inputFile, bool use9600 = false)
        {
            try
            {
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine("            AFSK DECODER - FX.25 MODE (WITH FEC)");
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine();

                // Initialize FX.25 subsystem with debug level 3 (maximum verbosity)
                Console.WriteLine("[STEP 1] Initializing FX.25 subsystem...");
                Fx25.Init(3);
                Console.WriteLine($"  ✓ FX.25 error correction enabled");
                Console.WriteLine($"  ✓ Reed-Solomon codecs initialized");
                Console.WriteLine($"  ✓ Debug level: {Fx25.GetDebugLevel()}");
                Console.WriteLine();

                // Read the WAV file
                Console.WriteLine("[STEP 2] Reading WAV file...");
                var (samples, wavParams) = WavFile.Read(inputFile);

                Console.WriteLine($"  ✓ Read {samples.Length} samples from {inputFile}");
                Console.WriteLine($"  ✓ Sample rate: {wavParams.SampleRate} Hz");
                Console.WriteLine($"  ✓ Duration: {WavFile.GetDuration(samples, wavParams.SampleRate):F2} seconds");
                Console.WriteLine();

                // Setup audio configuration
                Console.WriteLine("[STEP 3] Configuring demodulator...");
                var audioConfig = new AudioConfig();
                audioConfig.Devices[0].Defined = true;
                audioConfig.Devices[0].SamplesPerSec = wavParams.SampleRate;
                audioConfig.Devices[0].BitsPerSample = wavParams.BitsPerSample;
                audioConfig.Devices[0].NumChannels = wavParams.NumChannels;

                // Configure for selected baud rate
                audioConfig.ChannelMedium[0] = Medium.Radio;
                if (use9600)
                {
                    audioConfig.Channels[0].ModemType = ModemType.Scramble;
                    audioConfig.Channels[0].Baud = 9600;
                    Console.WriteLine($"  ✓ Modem: 9600 baud (baseband/scrambled)");
                }
                else
                {
                    audioConfig.Channels[0].ModemType = ModemType.Afsk;
                    audioConfig.Channels[0].MarkFreq = 1200;
                    audioConfig.Channels[0].SpaceFreq = 2200;
                    audioConfig.Channels[0].Baud = 1200;
                    Console.WriteLine($"  ✓ Modem: AFSK 1200 baud");
                    Console.WriteLine($"  ✓ Mark frequency: 1200 Hz");
                    Console.WriteLine($"  ✓ Space frequency: 2200 Hz");
                }
                audioConfig.Channels[0].NumSubchan = 1;
                Console.WriteLine();

                // Create MultiModem for packet collection with FX.25 support
                Console.WriteLine("[STEP 4] Initializing FX.25 receiver chain...");
                var multiModem = new MultiModem();
                multiModem.Init(audioConfig);
                
                // Set up packet collector using event handler
                var fx25PacketCollector = new Fx25PacketCollector();
                multiModem.PacketReady += (sender, e) =>
                {
                    if (e.Packet != null)
                    {
                        // Store packet, FEC type, correlation tag, and errors corrected
                        int errorsCorrected = (e.FecType == FecType.Fx25) ? (int)e.Retries : 0;
                        fx25PacketCollector.AddPacket(e.Packet, e.FecType, e.CtagNum, errorsCorrected);
                        
                        // Display correlation tag info immediately
                        if (e.FecType == FecType.Fx25)
                        {
                            Console.WriteLine($"  [FX.25] Packet received with FEC (correlation tag 0x{e.CtagNum:X2}, {errorsCorrected} errors corrected)");
                        }
                        else
                        {
                            Console.WriteLine($"  [AX.25] Packet received without FEC (plain AX.25)");
                        }
                    }
                };

                Console.WriteLine("  ✓ FX.25 receiver initialized");
                Console.WriteLine("  ✓ Ready to decode frames with error correction");
                Console.WriteLine();

                // Create FX.25 receiver that connects to MultiModem
                Console.WriteLine("[STEP 5] Initializing AFSK demodulator with BOTH AX.25 and FX.25...");
                var fx25Rec = new Fx25Rec(multiModem);
                
                // Create HDLC receiver for plain AX.25 frames
                var hdlcRec = new HdlcRec2();
                hdlcRec.Init(audioConfig);
                
                // Connect HDLC receiver to MultiModem for plain AX.25 packets
                hdlcRec.FrameReceived += (sender, e) =>
                {
                    var alevel = new ALevel(e.AudioLevel.Rec, e.AudioLevel.Mark, e.AudioLevel.Space);
                    var packet = Packet.FromFrame(e.Frame, e.FrameLength, alevel);
                    if (packet != null)
                    {
                        // Check if bit correction was applied
                        string correctionMsg = "  [AX.25] Packet received without FEC (plain AX.25)";
                        if (e.CorrectionInfo != null && e.CorrectionInfo.CorrectionType != RetryType.None)
                        {
                            correctionMsg += $" with {e.CorrectionInfo.CorrectedBitPositions.Count} bit(s) corrected";
                        }
                        
                        fx25PacketCollector.AddPacket(packet, FecType.None, -1, 0, e.CorrectionInfo);
                        Console.WriteLine(correctionMsg);
                    }
                };
                
                Console.WriteLine("  ✓ AX.25 and FX.25 decoders initialized");
                if (_errorRate > 0.0)
                {
                    Console.WriteLine($"  ✓ Bit error injection enabled at {_errorRate * 100:F5}%");
                }

                // Create dual receiver wrapper that feeds bits to both HDLC and FX.25
                IHdlcReceiver dualReceiver = new HdlcRecWithFx25Nrzi(hdlcRec, fx25Rec);
                
                // Wrap with bit error injector if configured
                if (_errorRate > 0.0)
                {
                    dualReceiver = new BitErrorInjector(dualReceiver, _errorRate, _random, ref _totalBits, ref _flippedBits);
                }

                Console.WriteLine($"  ✓ Demodulator initialized");
                Console.WriteLine();

                // Process all samples
                Console.WriteLine("[STEP 6] Processing audio samples...");
                Console.WriteLine($"  Processing {samples.Length} samples...");
                int chan = 0;
                int subchan = 0;

                if (use9600)
                {
                    // Use 9600 baud demodulator
                    var demodState = new DemodulatorState();
                    var state9600 = new Demod9600.Demod9600State();
                    
                    int upsample = 1; // No upsampling for now
                    Demod9600.Init(wavParams.SampleRate, upsample, audioConfig.Channels[0].Baud, 
                        demodState, state9600);

                    for (int i = 0; i < samples.Length; i++)
                    {
                        Demod9600.ProcessSample(chan, samples[i], upsample, demodState, state9600, dualReceiver);
                        
                        // Progress indicator every 10000 samples
                        if ((i + 1) % 10000 == 0)
                        {
                            float progress = (i + 1) * 100.0f / samples.Length;
                            Console.Write($"\r  Progress: {progress:F1}% ({i + 1}/{samples.Length} samples)");
                        }
                    }
                }
                else
                {
                    // Use AFSK 1200 baud demodulator
                    var demodAfsk = new DemodAfsk(dualReceiver);
                    var demodState = new DemodulatorState();
                    demodAfsk.Init(
                        wavParams.SampleRate,
                        audioConfig.Channels[0].Baud,
                        audioConfig.Channels[0].MarkFreq,
                        audioConfig.Channels[0].SpaceFreq,
                        'A',
                        demodState
                    );

                    for (int i = 0; i < samples.Length; i++)
                    {
                        demodAfsk.ProcessSample(chan, subchan, samples[i], demodState);
                        
                        // Progress indicator every 10000 samples
                        if ((i + 1) % 10000 == 0)
                        {
                            float progress = (i + 1) * 100.0f / samples.Length;
                            Console.Write($"\r  Progress: {progress:F1}% ({i + 1}/{samples.Length} samples)");
                        }
                    }
                }
                Console.WriteLine($"\r  ✓ Completed: 100.0% ({samples.Length}/{samples.Length} samples)");
                Console.WriteLine();

                // Check for collected packets
                Console.WriteLine("[STEP 7] Checking for decoded packets...");
                var packets = fx25PacketCollector.GetPackets();
                
                Console.WriteLine($"  Found {packets.Count} packet(s)");
                
                // Display bit error statistics if error injection was enabled
                if (_errorRate > 0.0 && _totalBits > 0)
                {
                    Console.WriteLine();
                    Console.WriteLine($"Bit Error Statistics:");
                    Console.WriteLine($"  Total bits processed: {_totalBits}");
                    Console.WriteLine($"  Bits flipped: {_flippedBits}");
                    Console.WriteLine($"  Actual error rate: {(_flippedBits * 100.0 / _totalBits):F5}%");
                }
                Console.WriteLine();

                if (packets.Count == 0)
                {
                    Console.WriteLine("No packets decoded.");
                    return null;
                }

                // Display results for all packets
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine("              FX.25 DECODE SUCCESSFUL!");
                Console.WriteLine("════════════════════════════════════════════════════════════");
                Console.WriteLine();

                StringBuilder allMessages = new StringBuilder();

                int fecCount = 0;
                int plainCount = 0;

                for (int i = 0; i < packets.Count; i++)
                {
                    var packet = packets[i];
                    var fecType = fx25PacketCollector.GetFecType(i);
                    var info = packet.GetInfo(out int infoLen);
                    
                    // Count FEC vs plain packets
                    if (fecType == FecType.Fx25)
                        fecCount++;
                    else
                        plainCount++;
                    
                    // Convert to string, removing control bytes
                    StringBuilder message = new StringBuilder();
                    for (int j = 0; j < infoLen; j++)
                    {
                        if (info[j] >= 32 && info[j] <= 126)
                        {
                            message.Append((char)info[j]);
                        }
                    }

                    string result = message.ToString();
                    if (allMessages.Length > 0)
                        allMessages.Append(" | ");
                    allMessages.Append(result);

                    Console.WriteLine($"[PACKET {i + 1}]");
                    
                    // Display FEC status, correlation tag, and errors corrected
                    if (fecType == FecType.Fx25)
                    {
                        int ctagNum = fx25PacketCollector.GetCtagNum(i);
                        int errorsCorrected = fx25PacketCollector.GetErrorsCorrected(i);
                        Console.WriteLine($"  FEC Type: FX.25 (with error correction)");
                        if (ctagNum >= 0)
                        {
                            Console.WriteLine($"  Correlation Tag: 0x{ctagNum:X2}");
                        }
                        if (errorsCorrected > 0)
                        {
                            Console.WriteLine($"  Fix Applied: Corrected {errorsCorrected} Reed-Solomon symbol(s)");
                        }
                        else
                        {
                            Console.WriteLine($"  Fix Applied: No errors detected (clean reception)");
                        }
                    }
                    else
                    {
                        Console.WriteLine($"  FEC Type: None (plain AX.25)");
                        
                        // Check if bit correction was applied
                        var correctionInfo = fx25PacketCollector.GetCorrectionInfo(i);
                        if (correctionInfo != null && correctionInfo.CorrectionType != RetryType.None)
                        {
                            string correctionMsg;
                            switch (correctionInfo.CorrectionType)
                            {
                                case RetryType.InvertSingle:
                                    correctionMsg = $"Corrected 1 bit (position {string.Join(", ", correctionInfo.CorrectedBitPositions)})";
                                    break;
                                case RetryType.InvertDouble:
                                    correctionMsg = $"Corrected 2 adjacent bits (positions {string.Join(", ", correctionInfo.CorrectedBitPositions)})";
                                    break;
                                case RetryType.InvertTriple:
                                    correctionMsg = $"Corrected 3 adjacent bits (positions {string.Join(", ", correctionInfo.CorrectedBitPositions)})";
                                    break;
                                case RetryType.InvertTwoSep:
                                    correctionMsg = $"Corrected 2 separated bits (positions {string.Join(", ", correctionInfo.CorrectedBitPositions)})";
                                    break;
                                default:
                                    correctionMsg = "Unknown correction applied";
                                    break;
                            }
                            Console.WriteLine($"  Fix Applied: {correctionMsg}");
                        }
                        else
                        {
                            Console.WriteLine($"  Fix Applied: No correction needed (CRC valid)");
                        }
                    }
                    
                    Console.WriteLine($"  Source: {packet.GetAddrWithSsid(Ax25Constants.Source)}");
                    Console.WriteLine($"  Destination: {packet.GetAddrWithSsid(Ax25Constants.Destination)}");
                    Console.WriteLine($"  Message length: {infoLen} bytes");
                    Console.WriteLine($"  Message: {result}");
                    Console.WriteLine();
                }

                Console.WriteLine($"Total packets: {packets.Count} ({fecCount} with FX.25 FEC, {plainCount} plain AX.25)");
                Console.WriteLine();

                return allMessages.ToString();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error decoding file: {ex.Message}");
                Console.WriteLine(ex.StackTrace);
                return null;
            }
        }

        /// <summary>
        /// Verify FCS of a frame
        /// </summary>
        public static bool VerifyFcs(byte[] frame, int length)
        {
            if (length < 2)
                return false;

            // Calculate FCS on all but last 2 bytes
            ushort calculated = FcsCalc.Calculate(frame, length - 2);

            // Extract FCS from last 2 bytes
            ushort received = (ushort)(frame[length - 2] | (frame[length - 1] << 8));

            return calculated == received;
        }

        /// <summary>
        /// Parse AX.25 address field
        /// </summary>
        public static string ParseAddress(byte[] addressBytes)
        {
            if (addressBytes.Length != 7)
                return "INVALID";

            StringBuilder callsign = new StringBuilder();

            // Extract callsign (first 6 bytes, shifted right by 1)
            for (int i = 0; i < 6; i++)
            {
                char c = (char)(addressBytes[i] >> 1);
                if (c != ' ')
                    callsign.Append(c);
            }

            // Extract SSID from 7th byte
            int ssid = (addressBytes[6] >> 1) & 0x0F;
            if (ssid != 0)
            {
                callsign.Append('-');
                callsign.Append(ssid);
            }

            return callsign.ToString();
        }
    }

    /// <summary>
    /// Bit error injector wrapper - flips bits randomly at a specified rate
    /// </summary>
    internal class BitErrorInjector : IHdlcReceiver
    {
        private readonly IHdlcReceiver _innerReceiver;
        private readonly double _errorRate;
        private readonly Random _random;
        private int _totalBits;
        private int _flippedBits;

        public BitErrorInjector(IHdlcReceiver innerReceiver, double errorRate, Random random, ref int totalBits, ref int flippedBits)
        {
            _innerReceiver = innerReceiver ?? throw new ArgumentNullException(nameof(innerReceiver));
            _errorRate = errorRate;
            _random = random ?? new Random();
            _totalBits = totalBits;
            _flippedBits = flippedBits;
        }

        public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
        {
            _totalBits++;
            
            // Randomly flip the bit based on error rate
            if (_random.NextDouble() < _errorRate)
            {
                raw = raw ^ 1; // Flip the bit (0->1 or 1->0)
                _flippedBits++;
            }
            
            // Forward the (possibly modified) bit to the inner receiver
            _innerReceiver.RecBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
        }

        public void DcdChange(int chan, int subchan, int slice, bool dcdOn)
        {
            _innerReceiver.DcdChange(chan, subchan, slice, dcdOn);
        }
    }

    /// <summary>
    /// Collects decoded packets from the HDLC receiver
    /// </summary>
    internal class PacketCollector
    {
        private List<Packet> _packets = new List<Packet>();

        public void AddPacket(Packet packet)
        {
            _packets.Add(packet);
        }

        public List<Packet> GetPackets()
        {
            return _packets;
        }

        public void Clear()
        {
            _packets.Clear();
        }
    }

    /// <summary>
    /// Collects decoded packets from FX.25 receiver via MultiModem
    /// </summary>
    internal class Fx25PacketCollector
    {
        private class PacketInfo
        {
            public Packet Packet { get; set; }
            public FecType FecType { get; set; }
            public int CtagNum { get; set; }
            public int ErrorsCorrected { get; set; }
            public CorrectionInfo CorrectionInfo { get; set; }
        }

        private List<PacketInfo> _packets = new List<PacketInfo>();

        public void AddPacket(Packet packet, FecType fecType, int ctagNum = -1, int errorsCorrected = 0, CorrectionInfo correctionInfo = null)
        {
            _packets.Add(new PacketInfo 
            { 
                Packet = packet, 
                FecType = fecType, 
                CtagNum = ctagNum,
                ErrorsCorrected = errorsCorrected,
                CorrectionInfo = correctionInfo
            });
        }

        public List<Packet> GetPackets()
        {
            var packets = new List<Packet>();
            foreach (var info in _packets)
            {
                packets.Add(info.Packet);
            }
            return packets;
        }

        public FecType GetFecType(int index)
        {
            if (index >= 0 && index < _packets.Count)
                return _packets[index].FecType;
            return FecType.None;
        }

        public int GetCtagNum(int index)
        {
            if (index >= 0 && index < _packets.Count)
                return _packets[index].CtagNum;
            return -1;
        }

        public int GetErrorsCorrected(int index)
        {
            if (index >= 0 && index < _packets.Count)
                return _packets[index].ErrorsCorrected;
            return 0;
        }

        public CorrectionInfo GetCorrectionInfo(int index)
        {
            if (index >= 0 && index < _packets.Count)
                return _packets[index].CorrectionInfo;
            return null;
        }

        public void Clear()
        {
            _packets.Clear();
        }
    }

    /// <summary>
    /// Wrapper for Fx25Rec that implements IHdlcReceiver interface
    /// Only forwards bits to FX.25 receiver (no AX.25 HDLC decoder)
    /// Performs NRZI decoding before passing to FX.25
    /// </summary>
    internal class Fx25RecWrapper : IHdlcReceiver
    {
        private readonly Fx25Rec _fx25Rec;
        private int[,,] _prevRaw; // Previous raw bit for NRZI decoding [chan, subchan, slice]

        public Fx25RecWrapper(Fx25Rec fx25Rec)
        {
            _fx25Rec = fx25Rec ?? throw new ArgumentNullException(nameof(fx25Rec));
            _prevRaw = new int[6, 9, 9]; // Max channels, subchannels, slicers
        }

        /// <summary>
        /// Process a bit - perform NRZI decoding and feed to FX.25 receiver
        /// </summary>
        public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
        {
            // NRZI decoding: 0 bit = transition, 1 bit = no change
            // In NRZI: same as previous = logic 1, different from previous = logic 0
            int dbit = (raw == _prevRaw[chan, subchan, slice]) ? 1 : 0;
            _prevRaw[chan, subchan, slice] = raw;

            // Feed NRZI-decoded bit to FX.25 receiver for correlation tag detection and FEC
            // Do NOT feed to HDLC receiver - this is FX.25 only mode
            _fx25Rec.RecBit(chan, subchan, slice, dbit);
        }

        /// <summary>
        /// Handle DCD change - ignored for FX.25 only mode
        /// </summary>
        public void DcdChange(int chan, int subchan, int slice, bool dcdOn)
        {
            // No-op for FX.25 only mode
        }
    }

    /// <summary>
    /// Wrapper that feeds bits to both HDLC and FX.25 receivers
    /// Performs NRZI decoding for FX.25 while letting HDLC do its own NRZI
    /// </summary>
    internal class HdlcRecWithFx25Nrzi : IHdlcReceiver
    {
        private readonly IHdlcReceiver _hdlcRec;
        private readonly Fx25Rec _fx25Rec;
        private int[,,] _prevRaw; // Previous raw bit for NRZI decoding [chan, subchan, slice]

        public HdlcRecWithFx25Nrzi(IHdlcReceiver hdlcRec, Fx25Rec fx25Rec)
        {
            _hdlcRec = hdlcRec ?? throw new ArgumentNullException(nameof(hdlcRec));
            _fx25Rec = fx25Rec ?? throw new ArgumentNullException(nameof(fx25Rec));
            _prevRaw = new int[6, 9, 9]; // Max channels, subchannels, slicers
        }

        /// <summary>
        /// Process a bit - feed raw bits to HDLC and NRZI-decoded bits to FX.25
        /// </summary>
        public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
        {
            // Feed raw bits to HDLC receiver (it does its own NRZI decoding)
            _hdlcRec.RecBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
            
            // Perform NRZI decoding for FX.25
            int dbit = (raw == _prevRaw[chan, subchan, slice]) ? 1 : 0;
            _prevRaw[chan, subchan, slice] = raw;
            
            // Feed NRZI-decoded bits to FX.25 receiver for correlation tag detection and FEC
            _fx25Rec.RecBit(chan, subchan, slice, dbit);
        }

        /// <summary>
        /// Handle DCD change - forward to HDLC receiver
        /// </summary>
        public void DcdChange(int chan, int subchan, int slice, bool dcdOn)
        {
            _hdlcRec.DcdChange(chan, subchan, slice, dcdOn);
        }
    }

    /// <summary>
    /// HDLC receiver wrapper that collects packets using event handler
    /// </summary>
    internal class HdlcRecWithCollector
    {
        private PacketCollector _collector;
        private HdlcRec2 _hdlcRec;
        private bool _debugMode;

        public HdlcRecWithCollector(PacketCollector collector, bool debugMode = false)
        {
            _collector = collector;
            _debugMode = debugMode;
            _hdlcRec = new HdlcRec2();
            _hdlcRec.FrameReceived += OnFrameReceived;
        }

        public void Init(AudioConfig audioConfig)
        {
            _hdlcRec.Init(audioConfig);
        }

        public HdlcRec2 GetHdlcRec()
        {
            return _hdlcRec;
        }

        public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
        {
            _hdlcRec.RecBit(chan, subchan, slice, raw, isScrambled, notUsedRemove);
        }

        public void RecBitNew(int chan, int subchan, int slice, int raw, bool isScrambled,
            int notUsedRemove, ref long pllNudgeTotal, ref int pllSymbolCount)
        {
            _hdlcRec.RecBitNew(chan, subchan, slice, raw, isScrambled, notUsedRemove, ref pllNudgeTotal, ref pllSymbolCount);
        }

        private void OnFrameReceived(object sender, FrameReceivedEventArgs e)
        {
            if (_debugMode)
            {
                Console.WriteLine($"\n════════════════════════════════════════════════════════════");
                Console.WriteLine($"             FRAME RECEIVED EVENT TRIGGERED");
                Console.WriteLine($"════════════════════════════════════════════════════════════");
                Console.WriteLine($"  Channel: {e.Channel}, Subchannel: {e.Subchannel}, Slice: {e.Slice}");
                Console.WriteLine($"  Frame length: {e.FrameLength} bytes");
                Console.WriteLine();
                
                // Display frame in HEX format
                Console.WriteLine("Frame Data (HEX):");
                for (int i = 0; i < e.FrameLength; i++)
                {
                    Console.Write($"{e.Frame[i]:X2} ");
                    if ((i + 1) % 16 == 0)
                        Console.WriteLine($" // Bytes {i - 15} to {i}");
                }
                if (e.FrameLength % 16 != 0)
                    Console.WriteLine($" // Bytes {(e.FrameLength / 16) * 16} to {e.FrameLength - 1}");
                Console.WriteLine();
                
                // Display frame in ASCII format
                Console.WriteLine("Frame Data (ASCII):");
                for (int i = 0; i < e.FrameLength; i++)
                {
                    char c = (char)e.Frame[i];
                    if (c >= 32 && c <= 126)
                        Console.Write(c);
                    else
                        Console.Write($"[{e.Frame[i]:X2}]");
                }
                Console.WriteLine();
                Console.WriteLine();
            }
            
            // Create packet from frame
            var alevel = new ALevel(e.AudioLevel.Rec, e.AudioLevel.Mark, e.AudioLevel.Space);
            var packet = Packet.FromFrame(e.Frame, e.FrameLength, alevel);
            
            if (packet != null)
            {
                if (_debugMode)
                {
                    Console.WriteLine($"  ✓ Packet created successfully");
                    Console.WriteLine($"  ✓ Is APRS: {packet.IsAprs()}");
                }
                
                if (packet.IsAprs())
                {
                    _collector.AddPacket(packet);
                    
                    if (_debugMode)
                    {
                        Console.WriteLine($"  ✓ Packet added to collector (total: {_collector.GetPackets().Count})");
                        
                        // Display decoded packet info
                        Console.WriteLine($"\n[DECODED PACKET] [{DateTime.Now:HH:mm:ss}]");
                        Console.WriteLine($"  Addresses: {packet.FormatAddrs()}");
                        
                        var info = packet.GetInfo(out int infoLen);
                        StringBuilder message = new StringBuilder();
                        for (int i = 0; i < infoLen; i++)
                        {
                            if (info[i] >= 32 && info[i] <= 126)
                                message.Append((char)info[i]);
                        }
                        Console.WriteLine($"  Message: {message.ToString()}");
                        Console.WriteLine();
                    }
                }
                else if (_debugMode)
                {
                    Console.WriteLine($"  ⚠ Packet is not APRS format");
                    Console.WriteLine();
                }
            }
            else if (_debugMode)
            {
                Console.WriteLine($"  ✗ Failed to create packet from frame");
                Console.WriteLine();
            }
        }
    }
}
