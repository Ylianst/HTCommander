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
// HdlcRec2.cs - HDLC frame extraction with error correction
// This file extracts HDLC frames from a block of bits after someone
// else has done the work of pulling it out from between the
// special "flag" sequences.
//

using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// Retry/fix-up attempt levels for bad CRC frames
    /// </summary>
    public enum RetryType
    {
        None = 0,
        InvertSingle = 1,
        InvertDouble = 2,
        InvertTriple = 3,
        InvertTwoSep = 4,
        Max = 5
    }

    /// <summary>
    /// Sanity test levels to apply after fixing bits
    /// </summary>
    public enum SanityTest
    {
        Aprs,    // Must look like APRS
        Ax25,    // Must have valid AX.25 addresses
        None     // No checking
    }

    /// <summary>
    /// Retry mode - how bits are modified
    /// </summary>
    public enum RetryMode
    {
        Contiguous = 0,  // Modify adjacent bits
        Separated = 1    // Modify non-adjacent bits
    }

    /// <summary>
    /// Type of retry operation
    /// </summary>
    public enum RetryOperation
    {
        None = 0,
        Swap = 1  // Invert bits
    }

    /// <summary>
    /// Configuration for retry/fix-up attempts
    /// </summary>
    public struct RetryConfig
    {
        public RetryType Retry;
        public RetryMode Mode;
        public RetryOperation Type;

        // For separated mode
        public int BitIdxA;
        public int BitIdxB;
        public int BitIdxC;

        // For contiguous mode
        public int BitIdx;
        public int NumBits;

        public int InsertValue;
    }

    /// <summary>
    /// Audio configuration for HDLC decoder
    /// </summary>
    public class HdlcAudioConfig
    {
        public RetryType FixBits { get; set; } = RetryType.None;
        public SanityTest SanityTest { get; set; } = SanityTest.Aprs;
        public bool PassAll { get; set; } = false;
        public ModemType ModemType { get; set; } = ModemType.Afsk;
        public int NumSubchan { get; set; } = 1;
    }

    /// <summary>
    /// HDLC state for decoding a single frame
    /// </summary>
    internal class HdlcState2
    {
        public int PrevRaw;           // Previous raw bit for transition detection
        public bool IsScrambled;      // G3RUH scrambling flag
        public int Lfsr;              // Descrambler shift register
        public int PrevDescram;       // Previous descrambled bit
        public byte PatDet;           // 8-bit pattern detector
        public byte OAcc;             // Octet accumulator
        public int OLen;              // Number of bits in accumulator
        public byte[] FrameBuffer;    // Frame being assembled
        public int FrameLen;          // Current frame length

        public HdlcState2()
        {
            FrameBuffer = new byte[MaxFrameLen];
        }

        private const int MaxFrameLen = 2048 + 2;
    }

    /// <summary>
    /// HDLC frame receiver with advanced error correction (Version 2)
    /// </summary>
    public class HdlcRec2 : IHdlcReceiver
    {
        //private const int MinFrameLen = 15 + 2;  // AX25_MIN_PACKET_LEN + 2 for FCS
        private const int MinFrameLen = 8 + 2;  // AX25_MIN_PACKET_LEN + 2 for FCS
        private const int MaxFrameLen = 2048 + 2; // AX25_MAX_PACKET_LEN + 2 for FCS
        private const int MaxRadioChannels = 6;

        private HdlcAudioConfig[] _audioConfig;
        private RawReceivedBitBuffer _currentBlock;
        private HdlcState2 _currentState;
        private List<int> _allReceivedBits = new List<int>();
        private List<int> _allDecodedBits = new List<int>();

        /// <summary>
        /// Initialize HDLC receiver with audio configuration (compatible with HdlcRec)
        /// </summary>
        public void Init(AudioConfig audioConfig)
        {
            // Convert AudioConfig to HdlcAudioConfig array
            _audioConfig = new HdlcAudioConfig[AudioConfig.MaxRadioChannels];
            
            for (int i = 0; i < AudioConfig.MaxRadioChannels; i++)
            {
                _audioConfig[i] = new HdlcAudioConfig
                {
                    FixBits = RetryType.InvertTwoSep,  // Enable bit error correction
                    SanityTest = SanityTest.Aprs,
                    PassAll = false,
                    ModemType = audioConfig.Channels[i].ModemType,
                    NumSubchan = audioConfig.Channels[i].NumSubchan
                };
            }

            // Initialize current state
            _currentState = new HdlcState2();
        }

        /// <summary>
        /// Initialize HDLC receiver with audio configuration (legacy)
        /// </summary>
        public void Init(HdlcAudioConfig[] audioConfig)
        {
            _audioConfig = audioConfig ?? throw new ArgumentNullException(nameof(audioConfig));
            _currentState = new HdlcState2();
        }

        /// <summary>
        /// Process a single received bit (IHdlcReceiver interface)
        /// </summary>
        public void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove)
        {
            long dummyLL = 0;
            int dummy = 0;
            RecBitNew(chan, subchan, slice, raw, isScrambled, notUsedRemove, ref dummyLL, ref dummy);
        }

        /// <summary>
        /// Process a single received bit with PLL tracking (IHdlcReceiver interface)
        /// </summary>
        public void RecBitNew(int chan, int subchan, int slice, int raw, bool isScrambled, 
            int notUsedRemove, ref long pllNudgeTotal, ref int pllSymbolCount)
        {
            // Store raw bits for debugging
            _allReceivedBits.Add(raw);

            // Initialize block if needed
            if (_currentBlock == null)
            {
                _currentBlock = new RawReceivedBitBuffer(chan, subchan, slice, isScrambled, 0, 0);
            }

            // NRZI decode for debugging
            int dbit = (raw == _currentState.PrevRaw) ? 1 : 0;
            _currentState.PrevRaw = raw;
            _allDecodedBits.Add(dbit);

            // Check for flag pattern by accumulating bits
            _currentState.PatDet >>= 1;
            if (dbit != 0)
                _currentState.PatDet |= 0x80;

            // Append raw bit to buffer (TryDecode will do NRZI again)
            _currentBlock.AppendBit((byte)raw);

            Console.WriteLine(_currentState.PatDet);

            // Check for flag pattern 01111110 (0x7e)
            if (_currentState.PatDet == 0x7e)
            {
                // Remove last 8 bits (the flag itself)
                _currentBlock.Chop8();

                // End of frame or start of frame
                if (_currentBlock.Length >= MinFrameLen * 8)
                {
                    // Process the frame
                    _currentBlock.AudioLevel = new AudioLevel(0, 0, 0);
                    ProcessBlock(_currentBlock);
                    
                    // Transfer ownership - ProcessBlock now owns this buffer (like C reference)
                    // Create a NEW buffer for the next frame with preserved scrambler state
                    _currentBlock = new RawReceivedBitBuffer(chan, subchan, slice, isScrambled, _currentState.Lfsr, _currentState.PrevDescram);
                }
                else
                {
                    // Start of frame - clear buffer
                    _currentBlock.Clear(isScrambled, _currentState.Lfsr, _currentState.PrevDescram);
                }

                // Append the last bit of the flag to the new/cleared buffer
                // This MUST be outside the if/else to match C reference (hdlc_rec.c line ~437)
                // The last bit of the closing flag becomes the first bit needed for NRZI
                // decoding the first data bit of the next frame
                _currentBlock.AppendBit((byte)_currentState.PrevRaw);
            }
            // Check for loss of signal (7-8 ones)
            else if (_currentState.PatDet == 0xfe)
            {
                // Reset
                _currentBlock.Clear(isScrambled, 0, 0);
                _currentState.PrevRaw = raw;
            }
        }

        /// <summary>
        /// DCD change notification (IHdlcReceiver interface)
        /// </summary>
        public void DcdChange(int chan, int subchan, int slice, bool dcdOn)
        {
            // Not used in HdlcRec2
        }

        /// <summary>
        /// Get all bits received (for debugging compatibility with HdlcRec)
        /// </summary>
        public List<int> GetAllReceivedBits()
        {
            return _allReceivedBits;
        }

        /// <summary>
        /// Get all bits after NRZI decoding (for debugging compatibility with HdlcRec)
        /// </summary>
        public List<int> GetAllDecodedBits()
        {
            return _allDecodedBits;
        }

        /// <summary>
        /// Process a block of raw bits extracted between flag patterns
        /// </summary>
        public void ProcessBlock(RawReceivedBitBuffer block)
        {
            if (block == null)
                throw new ArgumentNullException(nameof(block));

            int chan = block.Chan;
            int subchan = block.Subchan;
            int slice = block.Slice;
            AudioLevel alevel = block.AudioLevel;

            if (_audioConfig == null || chan >= _audioConfig.Length)
                return;

            // Simple HDLC frame decoding (like HdlcRec.ProcessRawBits)
            byte[] frame = new byte[MaxFrameLen];
            int frameLen = 0;
            byte acc = 0;
            int bitCount = 0;
            int onesCount = 0;
            int prevRaw = block.GetBit(0); // Initialize with first bit
            bool skipNext = false;

            for (int i = 1; i < block.Length; i++)
            {
                int raw = block.GetBit(i);
                
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

            // Check if we have a valid frame
            if (frameLen >= MinFrameLen)
            {
                // Verify FCS
                ushort actualFcs = (ushort)(frame[frameLen - 2] | (frame[frameLen - 1] << 8));
                ushort expectedFcs = FcsCalc.Calculate(frame, frameLen - 2);

                if (actualFcs == expectedFcs)
                {
                    // Valid frame - pass to upper layers
                    ProcessReceivedFrame(chan, subchan, slice, frame, frameLen - 2, alevel, RetryType.None, null);
                }
                else
                {
                    // CRC failed - try to fix errors by flipping bits
                    RetryType fixBits = _audioConfig[chan].FixBits;
                    
                    if (fixBits > RetryType.None)
                    {
                        // Attempt error correction
                        if (!TryToFixQuickNow(block, chan, subchan, slice, alevel))
                        {
                            // All fix attempts failed
                            // Could optionally pass through if PassAll is enabled
                            if (_audioConfig[chan].PassAll)
                            {
                                ProcessReceivedFrame(chan, subchan, slice, frame, frameLen - 2, alevel, RetryType.Max, null);
                            }
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Attempt quick fix-up techniques
        /// </summary>
        private bool TryToFixQuickNow(RawReceivedBitBuffer block, int chan, int subchan, 
            int slice, AudioLevel alevel)
        {
            int len = block.Length;
            RetryType fixBits = _audioConfig[chan].FixBits;

            RetryConfig retryConfig = new RetryConfig
            {
                Mode = RetryMode.Contiguous
            };

            // Try inverting one bit
            if (fixBits < RetryType.InvertSingle)
                return false;

            retryConfig.Type = RetryOperation.Swap;
            retryConfig.Retry = RetryType.InvertSingle;
            retryConfig.NumBits = 1;

            for (int i = 0; i < len; i++)
            {
                retryConfig.BitIdx = i;
                if (TryDecode(block, chan, subchan, slice, alevel, retryConfig, false))
                {
                    return true;
                }
            }

            // Try inverting two adjacent bits
            if (fixBits < RetryType.InvertDouble)
                return false;

            retryConfig.Retry = RetryType.InvertDouble;
            retryConfig.NumBits = 2;

            for (int i = 0; i < len - 1; i++)
            {
                retryConfig.BitIdx = i;
                if (TryDecode(block, chan, subchan, slice, alevel, retryConfig, false))
                {
                    return true;
                }
            }

            // Try inverting three adjacent bits
            if (fixBits < RetryType.InvertTriple)
                return false;

            retryConfig.Retry = RetryType.InvertTriple;
            retryConfig.NumBits = 3;

            for (int i = 0; i < len - 2; i++)
            {
                retryConfig.BitIdx = i;
                if (TryDecode(block, chan, subchan, slice, alevel, retryConfig, false))
                {
                    return true;
                }
            }

            // Try inverting two non-adjacent bits
            if (fixBits < RetryType.InvertTwoSep)
                return false;

            retryConfig.Mode = RetryMode.Separated;
            retryConfig.Type = RetryOperation.Swap;
            retryConfig.Retry = RetryType.InvertTwoSep;
            retryConfig.BitIdxC = -1;

            for (int i = 0; i < len - 2; i++)
            {
                retryConfig.BitIdxA = i;

                for (int j = i + 2; j < len; j++)
                {
                    retryConfig.BitIdxB = j;
                    if (TryDecode(block, chan, subchan, slice, alevel, retryConfig, false))
                    {
                        return true;
                    }
                }
            }

            return false;
        }

        /// <summary>
        /// Check if a bit is modified in contiguous mode
        /// </summary>
        private static bool IsContigBitModified(int bitIdx, RetryConfig retryConfig)
        {
            return bitIdx >= retryConfig.BitIdx && 
                   bitIdx < retryConfig.BitIdx + retryConfig.NumBits;
        }

        /// <summary>
        /// Check if a bit is modified in separated mode
        /// </summary>
        private static bool IsSepBitModified(int bitIdx, RetryConfig retryConfig)
        {
            return bitIdx == retryConfig.BitIdxA ||
                   bitIdx == retryConfig.BitIdxB ||
                   bitIdx == retryConfig.BitIdxC;
        }

        /// <summary>
        /// Try to decode a frame with specified bit modifications
        /// </summary>
        private bool TryDecode(RawReceivedBitBuffer block, int chan, int subchan, int slice,
            AudioLevel alevel, RetryConfig retryConfig, bool passall)
        {
            HdlcState2 H2 = new HdlcState2();
            int blen = block.Length;
            
            // Track which bits were corrected
            List<int> correctedBits = new List<int>();
            
            // Determine corrected bit positions based on retry config
            if (retryConfig.Type == RetryOperation.Swap)
            {
                if (retryConfig.Mode == RetryMode.Contiguous)
                {
                    for (int b = 0; b < retryConfig.NumBits; b++)
                    {
                        correctedBits.Add(retryConfig.BitIdx + b);
                    }
                }
                else if (retryConfig.Mode == RetryMode.Separated)
                {
                    correctedBits.Add(retryConfig.BitIdxA);
                    correctedBits.Add(retryConfig.BitIdxB);
                    if (retryConfig.BitIdxC >= 0)
                        correctedBits.Add(retryConfig.BitIdxC);
                }
            }

            H2.IsScrambled = block.IsScrambled;
            H2.PrevDescram = block.PrevDescram;
            H2.Lfsr = block.DescramState;
            H2.PrevRaw = block.GetBit(0);  // Last bit of opening flag

            // Check if first bit should be modified
            if ((retryConfig.Mode == RetryMode.Contiguous && IsContigBitModified(0, retryConfig)) ||
                (retryConfig.Mode == RetryMode.Separated && IsSepBitModified(0, retryConfig)))
            {
                H2.PrevRaw = H2.PrevRaw == 0 ? 1 : 0;
            }

            H2.PatDet = 0;
            H2.OAcc = 0;
            H2.OLen = 0;
            H2.FrameLen = 0;

            RetryMode retryMode = retryConfig.Mode;
            RetryOperation retryType = retryConfig.Type;
            RetryType retry = retryConfig.Retry;

            // Process all bits
            for (int i = 1; i < blen; i++)
            {
                int raw = block.GetBit(i);

                // Apply bit modifications if needed
                if (retry == RetryType.InvertTwoSep)
                {
                    if (IsSepBitModified(i, retryConfig))
                        raw = raw == 0 ? 1 : 0;
                }
                else if (retryMode == RetryMode.Contiguous)
                {
                    if (retryType == RetryOperation.Swap)
                    {
                        if (IsContigBitModified(i, retryConfig))
                            raw = raw == 0 ? 1 : 0;
                    }
                }

                // Shift through pattern detector
                H2.PatDet >>= 1;

                // NRZI decoding
                int dbit;
                if (H2.IsScrambled)
                {
                    int descram = Descramble(raw, ref H2.Lfsr);
                    dbit = (descram == H2.PrevDescram) ? 1 : 0;
                    H2.PrevDescram = descram;
                    H2.PrevRaw = raw;
                }
                else
                {
                    dbit = (raw == H2.PrevRaw) ? 1 : 0;
                    H2.PrevRaw = raw;
                }

                if (dbit != 0)
                {
                    H2.PatDet |= 0x80;

                    // Abort pattern: 7 ones in a row
                    if (H2.PatDet == 0xfe)
                        return false;

                    H2.OAcc >>= 1;
                    H2.OAcc |= 0x80;
                }
                else
                {
                    // Flag pattern: 01111110
                    if (H2.PatDet == 0x7e)
                        return false;

                    // Bit stuffing: 5 ones followed by 0
                    if ((H2.PatDet >> 2) == 0x1f)
                        continue;

                    H2.OAcc >>= 1;
                }

                // Accumulate bits into octets
                H2.OLen++;

                if ((H2.OLen & 8) != 0)
                {
                    H2.OLen = 0;

                    if (H2.FrameLen < MaxFrameLen)
                    {
                        H2.FrameBuffer[H2.FrameLen] = H2.OAcc;
                        H2.FrameLen++;
                    }
                }
            }

            // Check if we have a complete frame
            if (H2.OLen == 0 && H2.FrameLen >= MinFrameLen)
            {
                // Check FCS
                ushort actualFcs = (ushort)(H2.FrameBuffer[H2.FrameLen - 2] | 
                    (H2.FrameBuffer[H2.FrameLen - 1] << 8));
                ushort expectedFcs = FcsCalc.Calculate(H2.FrameBuffer, H2.FrameLen - 2);

                // Create correction info
                CorrectionInfo corrInfo = new CorrectionInfo
                {
                    CorrectionType = retryConfig.Retry,
                    FecType = FecType.None,
                    CorrectedBitPositions = correctedBits,
                    RsSymbolsCorrected = -1,
                    FX25CorrelationTag = -1,
                    FrameLengthBits = blen,
                    FrameLengthBytes = H2.FrameLen - 2,
                    OriginalCrc = actualFcs,
                    ExpectedCrc = expectedFcs,
                    CrcValid = (actualFcs == expectedFcs)
                };

                if (actualFcs == expectedFcs && 
                    _audioConfig[chan].ModemType == ModemType.Ais)
                {
                    // AIS sanity check
                    int msgType = (H2.FrameBuffer[0] >> 2) & 0x3f;
                    if (AisCheckLength(msgType, H2.FrameLen - 2))
                    {
                        ProcessReceivedFrame(chan, subchan, slice, H2.FrameBuffer, 
                            H2.FrameLen - 2, alevel, retryConfig.Retry, corrInfo);
                        return true;
                    }
                    return false;
                }
                else if (actualFcs == expectedFcs &&
                    SanityCheck(H2.FrameBuffer, H2.FrameLen - 2, retryConfig.Retry,
                        _audioConfig[chan].SanityTest))
                {
                    ProcessReceivedFrame(chan, subchan, slice, H2.FrameBuffer,
                        H2.FrameLen - 2, alevel, retryConfig.Retry, corrInfo);
                    return true;
                }
                else if (passall)
                {
                    if (retry == RetryType.None && retryType == RetryOperation.None)
                    {
                        corrInfo.CorrectionType = RetryType.Max;
                        corrInfo.CrcValid = false;
                        ProcessReceivedFrame(chan, subchan, slice, H2.FrameBuffer,
                            H2.FrameLen - 2, alevel, RetryType.Max, corrInfo);
                        return true;
                    }
                }
            }

            return false;
        }

        /// <summary>
        /// Descramble a bit for G3RUH/K9NG scrambling
        /// </summary>
        private int Descramble(int input, ref int lfsr)
        {
            int bit16 = (lfsr >> 16) & 1;
            int bit11 = (lfsr >> 11) & 1;
            int output = (input ^ bit16 ^ bit11) & 1;
            lfsr = ((lfsr << 1) | (input & 1)) & 0x1ffff;
            return output;
        }

        /// <summary>
        /// Perform sanity check on decoded frame
        /// </summary>
        private bool SanityCheck(byte[] buf, int blen, RetryType bitsFlipped, SanityTest sanityTest)
        {
            // No sanity check if we didn't try fixing the data
            if (bitsFlipped == RetryType.None)
                return true;

            // No sanity check requested
            if (sanityTest == SanityTest.None)
                return true;

            // Check address part is multiple of 7
            int alen = 0;
            for (int j = 0; j < blen && alen == 0; j++)
            {
                if ((buf[j] & 0x01) != 0)
                {
                    alen = j + 1;
                }
            }

            if (alen % 7 != 0)
                return false;

            // Need at least 2 addresses, max 10 (dest, source, 8 digipeaters)
            if (alen / 7 < 2 || alen / 7 > 10)
                return false;

            // Check addresses contain only valid characters
            for (int j = 0; j < alen; j += 7)
            {
                char[] addr = new char[6];
                for (int k = 0; k < 6; k++)
                {
                    addr[k] = (char)(buf[j + k] >> 1);
                }

                // First character must be letter or digit
                if (!char.IsUpper(addr[0]) && !char.IsDigit(addr[0]))
                    return false;

                // Rest can be letter, digit, or space
                for (int k = 1; k < 6; k++)
                {
                    if (!char.IsUpper(addr[k]) && !char.IsDigit(addr[k]) && addr[k] != ' ')
                        return false;
                }
            }

            // That's good enough for AX.25
            if (sanityTest == SanityTest.Ax25)
                return true;

            // APRS requires 0x03 and 0xf0
            if (alen >= blen || buf[alen] != 0x03 || buf[alen + 1] != 0xf0)
                return false;

            // Check for valid characters in info field
            for (int j = alen + 2; j < blen; j++)
            {
                int ch = buf[j];

                if (!((ch >= 0x1c && ch <= 0x7f) ||
                      ch == 0x0a ||
                      ch == 0x0d ||
                      ch == 0x80 ||
                      ch == 0x9f ||
                      ch == 0xc2 ||
                      ch == 0xb0 ||
                      ch == 0xf8))
                {
                    return false;
                }
            }

            return true;
        }

        /// <summary>
        /// Simple AIS message length check
        /// </summary>
        private bool AisCheckLength(int msgType, int len)
        {
            // Simplified - actual implementation would have proper AIS message length table
            return len >= 14 && len <= 256;
        }

        /// <summary>
        /// Process successfully decoded frame
        /// </summary>
        private void ProcessReceivedFrame(int chan, int subchan, int slice, byte[] frame,
            int frameLen, AudioLevel alevel, RetryType retries, CorrectionInfo correctionInfo)
        {
            // Raise event with decoded frame (use FrameReceived for compatibility with HdlcRec)
            OnFrameReceived(new FrameReceivedEventArgs
            {
                Channel = chan,
                Subchannel = subchan,
                Slice = slice,
                Frame = frame,
                FrameLength = frameLen,
                AudioLevel = alevel,
                CorrectionInfo = correctionInfo
            });
        }

        /// <summary>
        /// Event raised when a frame is successfully decoded (compatible with HdlcRec)
        /// </summary>
        public event EventHandler<FrameReceivedEventArgs> FrameReceived;

        protected virtual void OnFrameReceived(FrameReceivedEventArgs e)
        {
            FrameReceived?.Invoke(this, e);
        }

        /// <summary>
        /// Event raised when a frame is successfully decoded (legacy event name)
        /// </summary>
        public event EventHandler<HdlcFrameEventArgs> FrameDecoded;

        protected virtual void OnFrameDecoded(HdlcFrameEventArgs e)
        {
            FrameDecoded?.Invoke(this, e);
        }
    }

    /// <summary>
    /// Event arguments for decoded HDLC frame
    /// </summary>
    public class HdlcFrameEventArgs : EventArgs
    {
        public int Channel { get; set; }
        public int Subchannel { get; set; }
        public int Slice { get; set; }
        public byte[] Frame { get; set; }
        public int FrameLength { get; set; }
        public AudioLevel AudioLevel { get; set; }
        public RetryType Retries { get; set; }
        public CorrectionInfo CorrectionInfo { get; set; }
    }
}
