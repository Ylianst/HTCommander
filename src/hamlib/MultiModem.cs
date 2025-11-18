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
// MultiModem.cs - Use multiple modems in parallel to increase chances of decoding
//

using System;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// FEC type for received signal
    /// </summary>
    public enum FecType
    {
        None = 0,
        Fx25 = 1,
        Il2p = 2
    }

    /// <summary>
    /// Candidate packet for best selection
    /// </summary>
    internal class CandidatePacket
    {
        public Packet PacketP;
        public ALevel Alevel;
        public float SpeedError;
        public FecType FecType;
        public RetryType Retries;
        public int Age;
        public ushort Crc;
        public int Score;
        public CorrectionInfo CorrectionInfo;

        public CandidatePacket()
        {
            PacketP = null;
            Alevel = new ALevel();
            SpeedError = 0.0f;
            FecType = FecType.None;
            Retries = RetryType.None;
            Age = 0;
            Crc = 0;
            Score = 0;
            CorrectionInfo = null;
        }
    }

    /// <summary>
    /// Multi-modem manager - coordinates multiple demodulators and slicers
    /// </summary>
    public class MultiModem
    {
        // Constants
        private const int MaxRadioChannels = 6;
        private const int MaxSubchannels = 9;
        private const int MaxSlicers = 9;
        private const int ProcessAfterBits = 3;

        // Audio configuration
        private AudioConfig _audioConfig;

        // Candidates for further processing
        private CandidatePacket[,,] _candidates;

        // Process age tracking
        private int[] _processAge;

        // DC average tracking
        private float[] _dcAverage;

        // FX.25 busy state (simplified for now)
        private bool[] _fx25Busy;

        /// <summary>
        /// Event raised when a packet is ready to be processed
        /// </summary>
        public event EventHandler<PacketReadyEventArgs> PacketReady;

        /// <summary>
        /// Constructor
        /// </summary>
        public MultiModem()
        {
            _candidates = new CandidatePacket[MaxRadioChannels, MaxSubchannels, MaxSlicers];
            _processAge = new int[MaxRadioChannels];
            _dcAverage = new float[MaxRadioChannels];
            _fx25Busy = new bool[MaxRadioChannels];

            // Initialize all candidates
            for (int chan = 0; chan < MaxRadioChannels; chan++)
            {
                for (int subchan = 0; subchan < MaxSubchannels; subchan++)
                {
                    for (int slice = 0; slice < MaxSlicers; slice++)
                    {
                        _candidates[chan, subchan, slice] = new CandidatePacket();
                    }
                }
                _processAge[chan] = 0;
                _dcAverage[chan] = 0.0f;
                _fx25Busy[chan] = false;
            }
        }

        /// <summary>
        /// Initialize multi-modem with audio configuration
        /// </summary>
        public void Init(AudioConfig audioConfig)
        {
            _audioConfig = audioConfig ?? throw new ArgumentNullException(nameof(audioConfig));

            // Clear candidates
            for (int chan = 0; chan < MaxRadioChannels; chan++)
            {
                for (int subchan = 0; subchan < MaxSubchannels; subchan++)
                {
                    for (int slice = 0; slice < MaxSlicers; slice++)
                    {
                        _candidates[chan, subchan, slice] = new CandidatePacket();
                    }
                }
            }

            // Calculate process age for each channel
            for (int chan = 0; chan < MaxRadioChannels; chan++)
            {
                if (_audioConfig.ChannelMedium[chan] == Medium.Radio)
                {
                    if (_audioConfig.Channels[chan].Baud <= 0)
                    {
                        Console.WriteLine($"Internal error, chan={chan}, MultiModem.Init");
                        _audioConfig.Channels[chan].Baud = 1200; // Default
                    }

                    int realBaud = _audioConfig.Channels[chan].Baud;

                    // Adjust for multi-bit modems
                    if (_audioConfig.Channels[chan].ModemType == ModemType.Qpsk)
                        realBaud = _audioConfig.Channels[chan].Baud / 2;
                    else if (_audioConfig.Channels[chan].ModemType == ModemType.Psk8)
                        realBaud = _audioConfig.Channels[chan].Baud / 3;

                    int adevIndex = AudioConfig.ChannelToDevice(chan);
                    int samplesPerSec = _audioConfig.Devices[adevIndex].SamplesPerSec;

                    _processAge[chan] = ProcessAfterBits * samplesPerSec / realBaud;
                }
            }
        }

        /// <summary>
        /// Get DC average for a channel (scaled to +- 200)
        /// </summary>
        public int GetDcAverage(int chan)
        {
            if (chan < 0 || chan >= MaxRadioChannels)
                return 0;

            // Scale to +- 200 so it will be like the deviation measurement
            return (int)(_dcAverage[chan] * (200.0f / 32767.0f));
        }

        /// <summary>
        /// Process a single audio sample
        /// </summary>
        public void ProcessSample(int chan, int audioSample)
        {
            if (_audioConfig == null)
                return;

            if (chan < 0 || chan >= MaxRadioChannels)
                return;

            // Accumulate an average DC bias level
            // Shouldn't happen with a soundcard but could with mistuned SDR
            _dcAverage[chan] = _dcAverage[chan] * 0.999f + (float)audioSample * 0.001f;

            // Validate configuration
            if (_audioConfig.Channels[chan].NumSubchan <= 0 || 
                _audioConfig.Channels[chan].NumSubchan > MaxSubchannels ||
                _audioConfig.Channels[chan].NumSlicers <= 0 || 
                _audioConfig.Channels[chan].NumSlicers > MaxSlicers)
            {
                Console.WriteLine($"ERROR! Something is seriously wrong in MultiModem.ProcessSample");
                Console.WriteLine($"chan = {chan}, num_subchan = {_audioConfig.Channels[chan].NumSubchan} [max {MaxSubchannels}], " +
                                 $"num_slicers = {_audioConfig.Channels[chan].NumSlicers} [max {MaxSlicers}]");
                Console.WriteLine("Please report this message and include a copy of your configuration.");
                return;
            }

            // Send to all demodulators
            // Note: In a complete implementation, this would call demod_process_sample
            // For now, this is a placeholder for the demodulator interface

            // Age candidates and check if they're ready to process
            for (int subchan = 0; subchan < _audioConfig.Channels[chan].NumSubchan; subchan++)
            {
                for (int slice = 0; slice < _audioConfig.Channels[chan].NumSlicers; slice++)
                {
                    if (_candidates[chan, subchan, slice].PacketP != null)
                    {
                        _candidates[chan, subchan, slice].Age++;

                        if (_candidates[chan, subchan, slice].Age > _processAge[chan])
                        {
                            if (_fx25Busy[chan])
                            {
                                // Reset age if FX.25 is busy
                                _candidates[chan, subchan, slice].Age = 0;
                            }
                            else
                            {
                                PickBestCandidate(chan);
                            }
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Process a received frame (legacy interface)
        /// </summary>
        public void ProcessRecFrame(int chan, int subchan, int slice, byte[] fbuf, int flen,
            ALevel alevel, RetryType retries, FecType fecType)
        {
            ProcessRecFrame(chan, subchan, slice, fbuf, flen, alevel, retries, fecType, -1, null);
        }

        /// <summary>
        /// Process a received frame with correlation tag information
        /// </summary>
        public void ProcessRecFrame(int chan, int subchan, int slice, byte[] fbuf, int flen,
            ALevel alevel, RetryType retries, FecType fecType, int ctagNum)
        {
            ProcessRecFrame(chan, subchan, slice, fbuf, flen, alevel, retries, fecType, ctagNum, null);
        }

        /// <summary>
        /// Process a received frame with correlation tag and correction information
        /// </summary>
        public void ProcessRecFrame(int chan, int subchan, int slice, byte[] fbuf, int flen,
            ALevel alevel, RetryType retries, FecType fecType, int ctagNum, CorrectionInfo correctionInfo)
        {
            if (_audioConfig == null)
                return;

            Debug.Assert(chan >= 0 && chan < MaxRadioChannels);
            Debug.Assert(subchan >= 0 && subchan < MaxSubchannels);
            Debug.Assert(slice >= 0 && slice < MaxSlicers);

            Packet pp = null;

            // Special encapsulation for AIS & EAS
            if (_audioConfig.Channels[chan].ModemType == ModemType.Ais)
            {
                // AIS to NMEA conversion would go here
                // For now, create a simple encapsulated packet
                string monfmt = $"AIS>APRS,NOGATE:{{AIS_DATA}}";
                pp = Packet.FromText(monfmt, false);
            }
            else if (_audioConfig.Channels[chan].ModemType == ModemType.Eas)
            {
                // EAS encapsulation
                string monfmt = $"EAS>APRS,NOGATE:{{EAS_DATA}}";
                pp = Packet.FromText(monfmt, false);
            }
            else
            {
                pp = Packet.FromFrame(fbuf, flen, alevel);
            }

            ProcessRecPacket(chan, subchan, slice, pp, alevel, retries, fecType, ctagNum, correctionInfo);
        }

        /// <summary>
        /// Process a received packet (legacy interface)
        /// </summary>
        public void ProcessRecPacket(int chan, int subchan, int slice, Packet pp,
            ALevel alevel, RetryType retries, FecType fecType)
        {
            ProcessRecPacket(chan, subchan, slice, pp, alevel, retries, fecType, -1, null);
        }

        /// <summary>
        /// Process a received packet with correlation tag information
        /// </summary>
        public void ProcessRecPacket(int chan, int subchan, int slice, Packet pp,
            ALevel alevel, RetryType retries, FecType fecType, int ctagNum)
        {
            ProcessRecPacket(chan, subchan, slice, pp, alevel, retries, fecType, ctagNum, null);
        }

        /// <summary>
        /// Process a received packet with correlation tag and correction information
        /// </summary>
        public void ProcessRecPacket(int chan, int subchan, int slice, Packet pp,
            ALevel alevel, RetryType retries, FecType fecType, int ctagNum, CorrectionInfo correctionInfo)
        {
            if (pp == null)
            {
                Console.WriteLine("Unexpected internal problem in MultiModem.ProcessRecPacket");
                return;
            }

            if (_audioConfig == null)
                return;

            // If only one demodulator/slicer, and no FX.25 in progress, push it through immediately
            if (_audioConfig.Channels[chan].NumSubchan == 1 &&
                _audioConfig.Channels[chan].NumSlicers == 1 &&
                !_fx25Busy[chan])
            {
                bool dropIt = false;

                // Simulate receive error rate if configured
                // (In production code, this would check _audioConfig.recv_error_rate)

                if (dropIt)
                {
                    // Packet deleted (simulated drop)
                }
                else
                {
                    // Send directly to application
                    OnPacketReady(new PacketReadyEventArgs
                    {
                        Channel = chan,
                        Subchannel = subchan,
                        Slice = slice,
                        Packet = pp,
                        AudioLevel = alevel,
                        FecType = fecType,
                        Retries = retries,
                        Spectrum = "",
                        CtagNum = ctagNum,
                        CorrectionInfo = correctionInfo
                    });
                }
                return;
            }

            // Otherwise, save for later selection
            if (_candidates[chan, subchan, slice].PacketP != null)
            {
                // Replace existing candidate (FX.25 has priority)
                _candidates[chan, subchan, slice].PacketP = null;
            }

            Debug.Assert(pp != null);

            _candidates[chan, subchan, slice].PacketP = pp;
            _candidates[chan, subchan, slice].Alevel = alevel;
            _candidates[chan, subchan, slice].FecType = fecType;
            _candidates[chan, subchan, slice].Retries = retries;
            _candidates[chan, subchan, slice].Age = 0;
            _candidates[chan, subchan, slice].Crc = pp.MultiModemCrc();
            _candidates[chan, subchan, slice].CorrectionInfo = correctionInfo;
        }

        /// <summary>
        /// Pick the best candidate from all available options
        /// </summary>
        private void PickBestCandidate(int chan)
        {
            if (_audioConfig == null)
                return;

            if (_audioConfig.Channels[chan].NumSlicers < 1)
            {
                _audioConfig.Channels[chan].NumSlicers = 1;
            }

            int numBars = _audioConfig.Channels[chan].NumSlicers * _audioConfig.Channels[chan].NumSubchan;
            char[] spectrum = new char[numBars + 1];
            for (int i = 0; i < spectrum.Length; i++)
            {
                spectrum[i] = '_';
            }

            int bestN = 0;
            int bestScore = 0;

            // Build spectrum display and calculate scores
            for (int n = 0; n < numBars; n++)
            {
                int j = SubchanFromN(n, chan);
                int k = SliceFromN(n, chan);

                // Build the spectrum display
                if (_candidates[chan, j, k].PacketP == null)
                {
                    spectrum[n] = '_';
                }
                else if (_candidates[chan, j, k].FecType != FecType.None)
                {
                    // FX.25 or IL2P
                    int retries = (int)_candidates[chan, j, k].Retries;
                    if (retries <= 9)
                    {
                        spectrum[n] = (char)('0' + retries);
                    }
                    else
                    {
                        spectrum[n] = '+';
                    }
                }
                else if (_candidates[chan, j, k].Retries == RetryType.None)
                {
                    spectrum[n] = '|';
                }
                else if (_candidates[chan, j, k].Retries == RetryType.InvertSingle)
                {
                    spectrum[n] = ':';
                }
                else
                {
                    spectrum[n] = '.';
                }

                // Calculate beginning score based on effort to get valid frame CRC
                if (_candidates[chan, j, k].PacketP == null)
                {
                    _candidates[chan, j, k].Score = 0;
                }
                else
                {
                    if (_candidates[chan, j, k].FecType != FecType.None)
                    {
                        // Has FEC
                        _candidates[chan, j, k].Score = 9000 - 100 * (int)_candidates[chan, j, k].Retries;
                    }
                    else
                    {
                        // Regular AX.25
                        _candidates[chan, j, k].Score = (int)RetryType.Max * 1000 - 
                            ((int)_candidates[chan, j, k].Retries * 1000) + 1;
                    }
                }
            }

            // Bump up score if others nearby have the same CRC
            for (int n = 0; n < numBars; n++)
            {
                int j = SubchanFromN(n, chan);
                int k = SliceFromN(n, chan);

                if (_candidates[chan, j, k].PacketP != null)
                {
                    for (int m = 0; m < numBars; m++)
                    {
                        int mj = SubchanFromN(m, chan);
                        int mk = SliceFromN(m, chan);

                        if (m != n && _candidates[chan, mj, mk].PacketP != null)
                        {
                            if (_candidates[chan, j, k].Crc == _candidates[chan, mj, mk].Crc)
                            {
                                _candidates[chan, j, k].Score += (numBars + 1) - Math.Abs(m - n);
                            }
                        }
                    }
                }
            }

            // Find best score
            for (int n = 0; n < numBars; n++)
            {
                int j = SubchanFromN(n, chan);
                int k = SliceFromN(n, chan);

                if (_candidates[chan, j, k].PacketP != null)
                {
                    if (_candidates[chan, j, k].Score > bestScore)
                    {
                        bestScore = _candidates[chan, j, k].Score;
                        bestN = n;
                    }
                }
            }

            if (bestScore == 0)
            {
                Console.WriteLine("Unexpected internal problem in MultiModem.PickBestCandidate. How can best score be zero?");
            }

            // Delete those not chosen
            for (int n = 0; n < numBars; n++)
            {
                int j = SubchanFromN(n, chan);
                int k = SliceFromN(n, chan);

                if (n != bestN && _candidates[chan, j, k].PacketP != null)
                {
                    _candidates[chan, j, k].PacketP = null;
                }
            }

            // Pass along the best one
            int bestJ = SubchanFromN(bestN, chan);
            int bestK = SliceFromN(bestN, chan);

            bool dropIt = false;

            // Simulate receive error rate if configured
            // (In production code, this would check _audioConfig.recv_error_rate)

            if (dropIt)
            {
                _candidates[chan, bestJ, bestK].PacketP = null;
            }
            else
            {
                Debug.Assert(_candidates[chan, bestJ, bestK].PacketP != null);

                OnPacketReady(new PacketReadyEventArgs
                {
                    Channel = chan,
                    Subchannel = bestJ,
                    Slice = bestK,
                    Packet = _candidates[chan, bestJ, bestK].PacketP,
                    AudioLevel = _candidates[chan, bestJ, bestK].Alevel,
                    FecType = _candidates[chan, bestJ, bestK].FecType,
                    Retries = _candidates[chan, bestJ, bestK].Retries,
                    Spectrum = new string(spectrum, 0, numBars),
                    CorrectionInfo = _candidates[chan, bestJ, bestK].CorrectionInfo
                });

                // Clear ownership
                _candidates[chan, bestJ, bestK].PacketP = null;
            }

            // Clear in preparation for next time
            for (int subchan = 0; subchan < MaxSubchannels; subchan++)
            {
                for (int slice = 0; slice < MaxSlicers; slice++)
                {
                    _candidates[chan, subchan, slice] = new CandidatePacket();
                }
            }
        }

        /// <summary>
        /// Helper: Get subchannel from linear index
        /// </summary>
        private int SubchanFromN(int n, int chan)
        {
            if (_audioConfig == null)
                return 0;
            return n % _audioConfig.Channels[chan].NumSubchan;
        }

        /// <summary>
        /// Helper: Get slice from linear index
        /// </summary>
        private int SliceFromN(int n, int chan)
        {
            if (_audioConfig == null)
                return 0;
            return n / _audioConfig.Channels[chan].NumSubchan;
        }

        /// <summary>
        /// Set FX.25 busy state for a channel
        /// </summary>
        public void SetFx25Busy(int chan, bool busy)
        {
            if (chan >= 0 && chan < MaxRadioChannels)
            {
                _fx25Busy[chan] = busy;
            }
        }

        /// <summary>
        /// Raise packet ready event
        /// </summary>
        protected virtual void OnPacketReady(PacketReadyEventArgs e)
        {
            PacketReady?.Invoke(this, e);
        }
    }

    /// <summary>
    /// Event arguments for packet ready event
    /// </summary>
    public class PacketReadyEventArgs : EventArgs
    {
        public int Channel { get; set; }
        public int Subchannel { get; set; }
        public int Slice { get; set; }
        public Packet Packet { get; set; }
        public ALevel AudioLevel { get; set; }
        public FecType FecType { get; set; }
        public RetryType Retries { get; set; }
        public string Spectrum { get; set; } = "";
        public int CtagNum { get; set; } = -1;  // FX.25 correlation tag number (-1 = none)
        public CorrectionInfo CorrectionInfo { get; set; }  // Detailed error correction information
    }
}
