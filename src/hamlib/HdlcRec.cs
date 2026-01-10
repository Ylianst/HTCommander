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
// HdlcRec.cs - HDLC frame reception and decoding
// https://www.ietf.org/rfc/rfc1549.txt
//

using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// Audio level information for received frames
    /// </summary>
    public struct AudioLevel
    {
        public int Rec;      // Received signal level
        public int Mark;     // Mark tone level
        public int Space;    // Space tone level

        public AudioLevel(int rec = 9999, int mark = 9999, int space = 9999)
        {
            Rec = rec;
            Mark = mark;
            Space = space;
        }
    }

    /// <summary>
    /// Raw Received Bit Buffer - stores raw bits from demodulator
    /// </summary>
    public class RawReceivedBitBuffer
    {
        public RawReceivedBitBuffer Next { get; set; }
        public int Chan { get; private set; }
        public int Subchan { get; private set; }
        public int Slice { get; private set; }
        public AudioLevel AudioLevel { get; set; }
        public float SpeedError { get; set; }
        public int Length { get; private set; }
        public bool IsScrambled { get; private set; }
        public int DescramState { get; private set; }
        public int PrevDescram { get; private set; }

        private const int MaxNumBits = ((AudioConfig.MaxRadioChannels * 2048 + 2) * 8 * 6 / 5);
        private byte[] _data;

        public RawReceivedBitBuffer(int chan, int subchan, int slice, bool isScrambled, int descramState, int prevDescram)
        {
            Chan = chan;
            Subchan = subchan;
            Slice = slice;
            _data = new byte[MaxNumBits];
            Clear(isScrambled, descramState, prevDescram);
        }

        public void Clear(bool isScrambled, int descramState, int prevDescram)
        {
            Next = null;
            AudioLevel = new AudioLevel();
            SpeedError = 0;
            Length = 0;
            IsScrambled = isScrambled;
            DescramState = descramState;
            PrevDescram = prevDescram;
        }

        public void AppendBit(byte val)
        {
            if (Length >= MaxNumBits)
                return; // Silently discard if full

            _data[Length] = val;
            Length++;
        }

        public byte GetBit(int index)
        {
            if (index >= Length)
                return 0;
            return _data[index];
        }

        public void Chop8()
        {
            if (Length >= 8)
                Length -= 8;
        }

        public byte[] GetData()
        {
            byte[] result = new byte[Length];
            Array.Copy(_data, result, Length);
            return result;
        }
    }

    /// <summary>
    /// HDLC frame receiver state for a single channel/subchannel/slice
    /// </summary>
    internal class HdlcState
    {
        public int PrevRaw;              // Previous raw bit for NRZI
        public int Lfsr;                 // Descrambler shift register for 9600 baud
        public int PrevDescram;          // Previous descrambled bit for 9600 baud
        public byte PatDet;              // 8-bit pattern detector shift register
        public uint Flag4Det;            // Last 32 raw bits for flag detection
        public byte OAcc;                // Octet accumulator
        public int OLen;                 // Number of bits in accumulator (-1 = disabled)
        public byte[] FrameBuffer;       // Frame being assembled
        public int FrameLen;             // Length of frame
        public RawReceivedBitBuffer Rrbb; // Raw bit buffer
        public ulong EasAcc;             // EAS accumulator (64 bits)
        public bool EasGathering;        // EAS decoding in progress
        public bool EasPlusFound;        // "+" seen in EAS
        public int EasFieldsAfterPlus;   // Fields after "+" in EAS

        public HdlcState()
        {
            FrameBuffer = new byte[AudioConfig.MaxRadioChannels * 2048 + 2];
            OLen = -1;
        }
    }

    /// <summary>
    /// HDLC frame receiver - extracts frames from bit stream
    /// </summary>
    public class HdlcRec : IHdlcReceiver
    {
        private const int MinFrameLen = 15 + 2;  // AX25_MIN_PACKET_LEN + 2 for FCS
        private const int MaxFrameLen = 2048 + 2; // AX25_MAX_PACKET_LEN + 2 for FCS

        private HdlcState[,,] _hdlcState;
        private int[] _numSubchan;
        private int[,] _compositeDcd;
        private AudioConfig _audioConfig;
        private bool _wasInit;

        // Random number generator for BER injection
        private int _seed = 1;
        private const int MyRandMax = 0x7fffffff;

        public HdlcRec()
        {
            _hdlcState = new HdlcState[AudioConfig.MaxRadioChannels, AudioConfig.MaxSubchannels, AudioConfig.MaxSlicers];
            _numSubchan = new int[AudioConfig.MaxRadioChannels];
            _compositeDcd = new int[AudioConfig.MaxRadioChannels, AudioConfig.MaxSubchannels + 1];
        }

        /// <summary>
        /// Initialize the HDLC receiver
        /// </summary>
        public void Init(AudioConfig audioConfig)
        {
            Debug.Assert(audioConfig != null);
            _audioConfig = audioConfig;

            Array.Clear(_compositeDcd, 0, _compositeDcd.Length);

            for (int ch = 0; ch < AudioConfig.MaxRadioChannels; ch++)
            {
                if (_audioConfig.ChannelMedium[ch] == Medium.Radio)
                {
                    _numSubchan[ch] = _audioConfig.Channels[ch].NumSubchan;
                    Debug.Assert(_numSubchan[ch] >= 1 && _numSubchan[ch] <= AudioConfig.MaxSubchannels);

                    for (int sub = 0; sub < _numSubchan[ch]; sub++)
                    {
                        for (int slice = 0; slice < AudioConfig.MaxSlicers; slice++)
                        {
                            _hdlcState[ch, sub, slice] = new HdlcState();
                            var H = _hdlcState[ch, sub, slice];
                            H.OLen = -1;
                            H.Rrbb = new RawReceivedBitBuffer(ch, sub, slice,
                                _audioConfig.Channels[ch].ModemType == ModemType.Scramble,
                                H.Lfsr, H.PrevDescram);
                        }
                    }
                }
            }

            _wasInit = true;
        }

        private int MyRand()
        {
            _seed = (int)(((uint)_seed * 1103515245 + 12345) & MyRandMax);
            return _seed;
        }

        /// <summary>
        /// Process a single received bit (main entry point)
        /// </summary>
        public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
        {
            long dummyLL = 0;
            int dummy = 0;
            RecBitNew(chan, subchan, slice, raw, isScrambled, notUsedRemove, ref dummyLL, ref dummy);
        }

        private int _recBitCounter = 0; // Track bits received
        private List<int> _allReceivedBits = new List<int>(); // Store all bits for debugging (raw)
        private List<int> _allDecodedBits = new List<int>(); // Store all bits after NRZI decoding

        /// <summary>
        /// Get all bits received (for debugging)
        /// </summary>
        public List<int> GetAllReceivedBits()
        {
            return _allReceivedBits;
        }

        /// <summary>
        /// Get all bits after NRZI decoding (for debugging)
        /// </summary>
        public List<int> GetAllDecodedBits()
        {
            return _allDecodedBits;
        }

        /// <summary>
        /// Process a single received bit with PLL tracking
        /// </summary>
        public void RecBitNew(int chan, int subchan, int slice, int raw, bool isScrambled, 
            int notUsedRemove, ref long pllNudgeTotal, ref int pllSymbolCount)
        {
            Debug.Assert(_wasInit);
            Debug.Assert(chan >= 0 && chan < AudioConfig.MaxRadioChannels);
            Debug.Assert(subchan >= 0 && subchan < AudioConfig.MaxSubchannels);
            Debug.Assert(slice >= 0 && slice < AudioConfig.MaxSlicers);

            // DEBUG: Store and log bits received by HdlcRec
            _recBitCounter++;
            _allReceivedBits.Add(raw);
            
            /*
            if (_recBitCounter <= 20 || _recBitCounter % 100 == 0)
            {
                Console.WriteLine($"[HDLC] RecBit #{_recBitCounter}: chan={chan}, subchan={subchan}, slice={slice}, raw={raw}");
            }
            */

            // Artificial BER injection for testing (not implemented in basic port)
            // Could be added if needed for testing

            // EAS does not use HDLC
            if (_audioConfig.Channels[chan].ModemType == ModemType.Eas)
            {
                EasRecBit(chan, subchan, slice, raw, notUsedRemove);
                return;
            }

            var H = _hdlcState[chan, subchan, slice];

            // NRZI decoding: 0 bit = transition, 1 bit = no change
            int dbit;
            if (isScrambled)
            {
                int descram = Descramble(raw, ref H.Lfsr);
                dbit = (descram == H.PrevDescram) ? 1 : 0;
                H.PrevDescram = descram;
                H.PrevRaw = raw;
            }
            else
            {
                dbit = (raw == H.PrevRaw) ? 1 : 0;
                H.PrevRaw = raw;
            }

            // Store decoded bit for debugging
            _allDecodedBits.Add(dbit);

            // FX.25 and IL2P processing would go here (not implemented in basic port)

            // Shift bit through pattern detector
            H.PatDet >>= 1;
            if (dbit != 0)
                H.PatDet |= 0x80;

            H.Flag4Det >>= 1;
            if (dbit != 0)
                H.Flag4Det |= 0x80000000;

            H.Rrbb.AppendBit((byte)raw);

            // Check for flag pattern 01111110 (0x7e)
            if (H.PatDet == 0x7e)
            {
                //Console.WriteLine($"[HDLC] FLAG detected at bit #{_recBitCounter}, buffer length={H.Rrbb.Length} bits");
                H.Rrbb.Chop8();

                // End of frame or start of frame
                if (H.Rrbb.Length >= MinFrameLen * 8)
                {
                    //Console.WriteLine($"[HDLC] End of frame detected, length={H.Rrbb.Length} bits ({H.Rrbb.Length / 8} bytes)");
                    // End of frame - calculate speed error if available
                    float speedError = 0;
                    if (pllSymbolCount > 0)
                    {
                        speedError = (float)((double)pllNudgeTotal * 100.0 / 
                            (256.0 * 256.0 * 256.0 * 256.0) / (double)pllSymbolCount + 0.02);
                    }
                    H.Rrbb.SpeedError = speedError;

                    // Audio level would be retrieved from demodulator
                    H.Rrbb.AudioLevel = new AudioLevel(0, 0, 0); // Placeholder

                    // Process the frame (would call hdlc_rec2_block in full implementation)
                    //Console.WriteLine($"[HDLC] Processing frame buffer...");
                    ProcessRawBits(H.Rrbb);
                    H.Rrbb = null;

                    // Allocate new buffer
                    H.Rrbb = new RawReceivedBitBuffer(chan, subchan, slice, isScrambled, H.Lfsr, H.PrevDescram);
                }
                else
                {
                    // Start of frame
                    pllNudgeTotal = 0;
                    pllSymbolCount = -1;
                    H.Rrbb.Clear(isScrambled, H.Lfsr, H.PrevDescram);
                }

                H.OLen = 0;
                H.FrameLen = 0;
                H.Rrbb.AppendBit((byte)H.PrevRaw);
            }
            // Check for loss of signal pattern (7 or 8 ones in a row)
            else if (H.PatDet == 0xfe)
            {
                H.OLen = -1;
                H.FrameLen = 0;
                H.Rrbb.Clear(isScrambled, H.Lfsr, H.PrevDescram);
            }
            // Check for bit stuffing pattern (5 ones followed by 0)
            else if ((H.PatDet & 0xfc) == 0x7c)
            {
                // Discard the stuffed 0 bit
            }
            else
            {
                // Accumulate bits into octets
                if (H.OLen >= 0)
                {
                    H.OAcc >>= 1;
                    if (dbit != 0)
                        H.OAcc |= 0x80;
                    H.OLen++;

                    if (H.OLen == 8)
                    {
                        H.OLen = 0;
                        if (H.FrameLen < MaxFrameLen)
                        {
                            H.FrameBuffer[H.FrameLen] = H.OAcc;
                            H.FrameLen++;
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Descramble a bit for 9600 baud G3RUH/K9NG scrambling
        /// </summary>
        private int Descramble(int input, ref int lfsr)
        {
            // Polynomial: x^17 + x^12 + 1
            int bit16 = (lfsr >> 16) & 1;
            int bit11 = (lfsr >> 11) & 1;
            int output = (input ^ bit16 ^ bit11) & 1;
            lfsr = ((lfsr << 1) | (input & 1)) & 0x1ffff;
            return output;
        }

        /// <summary>
        /// Process raw bits buffer (simplified version)
        /// In full implementation, this would call hdlc_rec2 for advanced decoding
        /// </summary>
        private void ProcessRawBits(RawReceivedBitBuffer rrbb)
        {
            if (rrbb == null) return;

            // The bits in rrbb are RAW bits (before NRZI decoding)
            // We need to NRZI decode them and handle bit stuffing
            
            byte[] frame = new byte[MaxFrameLen];
            int frameLen = 0;
            byte acc = 0;
            int bitCount = 0;
            int onesCount = 0;
            int prevRaw = rrbb.GetBit(0); // Initialize with first bit
            bool skipNext = false;

            //Console.WriteLine($"[HDLC] ProcessRawBits: {rrbb.Length} raw bits to process");

            for (int i = 1; i < rrbb.Length; i++) // Start from 1, using 0 as initial
            {
                int raw = rrbb.GetBit(i);
                
                // NRZI decode: no transition = 1, transition = 0
                int dbit = (raw == prevRaw) ? 1 : 0;
                prevRaw = raw;

                // If we're skipping a stuffed bit, skip it and reset flag
                if (skipNext)
                {
                    skipNext = false;
                    onesCount = 0;
                    continue;
                }

                // Check for bit stuffing (5 ones in a row means next 0 is stuffed)
                if (dbit == 1)
                {
                    onesCount++;
                    if (onesCount == 5)
                    {
                        // Next bit (which should be 0) is stuffed, skip it
                        skipNext = true;
                    }
                }
                else
                {
                    onesCount = 0;
                }

                // Accumulate bits (LSB first)
                acc >>= 1;
                if (dbit != 0)
                    acc |= 0x80;
                bitCount++;

                if (bitCount == 8)
                {
                    if (frameLen < MaxFrameLen)
                        frame[frameLen++] = acc;
                    bitCount = 0;
                    acc = 0;
                }
            }

            //Console.WriteLine($"[HDLC] After NRZI decode and destuffing: {frameLen} bytes");

            // Check if we have a valid frame
            if (frameLen >= MinFrameLen)
            {
                // Verify FCS
                ushort actualFcs = (ushort)(frame[frameLen - 2] | (frame[frameLen - 1] << 8));
                ushort expectedFcs = FcsCalc.Calculate(frame, frameLen - 2);

                //Console.WriteLine($"[HDLC] FCS check: Expected={expectedFcs:X4}, Got={actualFcs:X4}");

                if (actualFcs == expectedFcs)
                {
                    // Valid frame - pass to upper layers
                    //Console.WriteLine($"[HDLC] ✓ Valid frame! FCS match. Frame length={frameLen - 2} bytes");
                    // In full implementation, would call multi_modem_process_rec_frame
                    OnFrameReceived(rrbb.Chan, rrbb.Subchan, rrbb.Slice, frame, frameLen - 2, rrbb.AudioLevel);
                }
                else
                {
                    //Console.WriteLine($"[HDLC] ✗ FCS mismatch. Expected={expectedFcs:X4}, Got={actualFcs:X4}");
                }
            }
            else
            {
                //Console.WriteLine($"[HDLC] Frame too short: {frameLen} bytes (minimum {MinFrameLen})");
            }
        }

        /// <summary>
        /// EAS (Emergency Alert System) bit receiver
        /// </summary>
        private void EasRecBit(int chan, int subchan, int slice, int raw, int futureUse)
        {
            var H = _hdlcState[chan, subchan, slice];

            // Accumulate most recent 64 bits
            H.EasAcc >>= 1;
            if (raw != 0)
                H.EasAcc |= 0x8000000000000000UL;

            const ulong PreambleZczc = 0x435a435aababababUL;
            const ulong PreambleNnnn = 0x4e4e4e4eababababUL;
            const int EasMaxLen = 268;

            bool done = false;

            if (H.EasAcc == PreambleZczc)
            {
                H.OLen = 0;
                H.EasGathering = true;
                H.EasPlusFound = false;
                H.EasFieldsAfterPlus = 0;
                Array.Clear(H.FrameBuffer, 0, H.FrameBuffer.Length);
                Array.Copy(System.Text.Encoding.ASCII.GetBytes("ZCZC"), H.FrameBuffer, 4);
                H.FrameLen = 4;
            }
            else if (H.EasAcc == PreambleNnnn)
            {
                H.OLen = 0;
                H.EasGathering = true;
                Array.Clear(H.FrameBuffer, 0, H.FrameBuffer.Length);
                Array.Copy(System.Text.Encoding.ASCII.GetBytes("NNNN"), H.FrameBuffer, 4);
                H.FrameLen = 4;
                done = true;
            }
            else if (H.EasGathering)
            {
                H.OLen++;
                if (H.OLen == 8)
                {
                    H.OLen = 0;
                    char ch = (char)(H.EasAcc >> 56);
                    H.FrameBuffer[H.FrameLen++] = (byte)ch;

                    // Validate character
                    if (!((ch >= ' ' && ch <= 0x7f) || ch == '\r' || ch == '\n'))
                    {
                        H.EasGathering = false;
                        return;
                    }
                    if (H.FrameLen > EasMaxLen)
                    {
                        H.EasGathering = false;
                        return;
                    }
                    if (ch == '+')
                    {
                        H.EasPlusFound = true;
                        H.EasFieldsAfterPlus = 0;
                    }
                    if (H.EasPlusFound && ch == '-')
                    {
                        H.EasFieldsAfterPlus++;
                        if (H.EasFieldsAfterPlus == 3)
                            done = true;
                    }
                }
            }

            if (done)
            {
                OnFrameReceived(chan, subchan, slice, H.FrameBuffer, H.FrameLen, new AudioLevel(0, 0, 0));
                H.EasGathering = false;
            }
        }

        /// <summary>
        /// DCD (Data Carrier Detect) state change
        /// </summary>
        public void DcdChange(int chan, int subchan, int slice, bool state)
        {
            Debug.Assert(chan >= 0 && chan < AudioConfig.MaxRadioChannels);
            Debug.Assert(subchan >= 0 && subchan <= AudioConfig.MaxSubchannels);
            Debug.Assert(slice >= 0 && slice < AudioConfig.MaxSlicers);

            bool old = DataDetectAny(chan);

            if (state)
                _compositeDcd[chan, subchan] |= (1 << slice);
            else
                _compositeDcd[chan, subchan] &= ~(1 << slice);

            bool newState = DataDetectAny(chan);

            if (newState != old)
            {
                // Notify PTT system (not implemented in basic port)
                OnDcdChanged(chan, newState);
            }
        }

        /// <summary>
        /// Check if any decoder on this channel detects data
        /// </summary>
        public bool DataDetectAny(int chan)
        {
            Debug.Assert(chan >= 0 && chan < AudioConfig.MaxRadioChannels);

            for (int sc = 0; sc < _numSubchan[chan]; sc++)
            {
                if (_compositeDcd[chan, sc] != 0)
                    return true;
            }

            return false;
        }

        /// <summary>
        /// Event raised when a valid frame is received
        /// </summary>
        public event EventHandler<FrameReceivedEventArgs> FrameReceived;

        protected virtual void OnFrameReceived(int chan, int subchan, int slice, byte[] frame, int frameLen, AudioLevel alevel)
        {
            FrameReceived?.Invoke(this, new FrameReceivedEventArgs
            {
                Channel = chan,
                Subchannel = subchan,
                Slice = slice,
                Frame = frame,
                FrameLength = frameLen,
                AudioLevel = alevel
            });
        }

        /// <summary>
        /// Event raised when DCD state changes
        /// </summary>
        public event EventHandler<DcdChangedEventArgs> DcdChanged;

        protected virtual void OnDcdChanged(int chan, bool state)
        {
            DcdChanged?.Invoke(this, new DcdChangedEventArgs
            {
                Channel = chan,
                State = state
            });
        }
    }

    /// <summary>
    /// Event arguments for frame received event
    /// </summary>
    public class FrameReceivedEventArgs : EventArgs
    {
        public int Channel { get; set; }
        public int Subchannel { get; set; }
        public int Slice { get; set; }
        public byte[] Frame { get; set; }
        public int FrameLength { get; set; }
        public AudioLevel AudioLevel { get; set; }
        public CorrectionInfo CorrectionInfo { get; set; }
    }

    /// <summary>
    /// Event arguments for DCD changed event
    /// </summary>
    public class DcdChangedEventArgs : EventArgs
    {
        public int Channel { get; set; }
        public bool State { get; set; }
    }
}
