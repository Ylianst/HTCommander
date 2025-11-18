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
// Fx25Rec.cs - FX.25 codeblock extraction and processing from bit stream
//

using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// FX.25 receiver state
    /// </summary>
    internal enum Fx25State
    {
        FxTag = 0,    // Looking for correlation tag
        FxData,       // Accumulating data bytes
        FxCheck       // Accumulating check bytes
    }

    /// <summary>
    /// FX.25 receiver context for a single channel/subchannel/slicer
    /// </summary>
    internal class Fx25Context
    {
        public Fx25State State { get; set; }
        public ulong Accum { get; set; }           // Accumulate bits for matching to correlation tag
        public int CtagNum { get; set; }           // Correlation tag number, CTAG_MIN to CTAG_MAX if approx. match found
        public int KDataRadio { get; set; }        // Expected size of "data" sent over radio
        public int Coffs { get; set; }             // Starting offset of the check part
        public int NRoots { get; set; }            // Expected number of check bytes
        public int Dlen { get; set; }              // Accumulated length in "data" below
        public int Clen { get; set; }              // Accumulated length in "check" below
        public byte IMask { get; set; }            // Mask for storing a bit
        public byte[] Block { get; set; }          // RS codeblock buffer
        public byte Fence { get; set; }            // Fence value for buffer overflow detection

        public Fx25Context()
        {
            State = Fx25State.FxTag;
            Accum = 0;
            CtagNum = -1;
            Block = new byte[Fx25.FX25_BLOCK_SIZE + 1];
            Fence = 0x55;
            Block[Fx25.FX25_BLOCK_SIZE] = Fence;
        }
    }

    /// <summary>
    /// FX.25 receiver - extracts and decodes FX.25 frames from bit stream
    /// </summary>
    public class Fx25Rec
    {
        private const int MaxRadioChans = 6;
        private const int MaxSubchans = 9;
        private const int MaxSlicers = 9;
        private const byte Fence = 0x55;

        // Context for each channel/subchannel/slicer combination
        private readonly Fx25Context[,,] _contexts;

        // Reference to MultiModem for frame processing
        private readonly MultiModem _multiModem;

        /// <summary>
        /// Constructor
        /// </summary>
        public Fx25Rec(MultiModem multiModem = null)
        {
            _contexts = new Fx25Context[MaxRadioChans, MaxSubchans, MaxSlicers];
            _multiModem = multiModem;
        }

        /// <summary>
        /// Process a single received bit for FX.25 decoding
        /// </summary>
        /// <param name="chan">Radio channel number</param>
        /// <param name="subchan">Subchannel (demodulator) number</param>
        /// <param name="slice">Slicer number</param>
        /// <param name="dbit">Data bit (after NRZI and descrambling). Non-zero = logic '1'</param>
        public void RecBit(int chan, int subchan, int slice, int dbit)
        {
            Debug.Assert(chan >= 0 && chan < MaxRadioChans);
            Debug.Assert(subchan >= 0 && subchan < MaxSubchans);
            Debug.Assert(slice >= 0 && slice < MaxSlicers);

            // Allocate context blocks only as needed
            Fx25Context F = _contexts[chan, subchan, slice];
            if (F == null)
            {
                F = new Fx25Context();
                _contexts[chan, subchan, slice] = F;
            }

            // State machine to identify correlation tag then gather appropriate number of data and check bytes
            switch (F.State)
            {
                case Fx25State.FxTag:
                    F.Accum >>= 1;
                    if (dbit != 0)
                        F.Accum |= 1UL << 63;

                    int c = Fx25.TagFindMatch(F.Accum);
                    if (c >= Fx25.CTAG_MIN && c <= Fx25.CTAG_MAX)
                    {
                        F.CtagNum = c;
                        F.KDataRadio = Fx25.GetKDataRadio(F.CtagNum);
                        F.NRoots = Fx25.GetNRoots(F.CtagNum);
                        F.Coffs = Fx25.GetKDataRs(F.CtagNum);
                        Debug.Assert(F.Coffs == Fx25.FX25_BLOCK_SIZE - F.NRoots);

                        if (Fx25.GetDebugLevel() >= 2)
                        {
                            int bitErrors = PopCount(F.Accum ^ Fx25.GetCtagValue(c));
                            Console.WriteLine($"FX.25[{chan}.{slice}]: Matched correlation tag 0x{c:x2} with {bitErrors} bit errors. " +
                                            $"Expecting {F.KDataRadio} data & {F.NRoots} check bytes.");
                        }

                        F.IMask = 0x01;
                        F.Dlen = 0;
                        F.Clen = 0;
                        Array.Clear(F.Block, 0, F.Block.Length - 1);
                        F.Block[Fx25.FX25_BLOCK_SIZE] = Fence;
                        F.State = Fx25State.FxData;
                    }
                    break;

                case Fx25State.FxData:
                    if (dbit != 0)
                        F.Block[F.Dlen] |= F.IMask;

                    F.IMask <<= 1;
                    if (F.IMask == 0)
                    {
                        F.IMask = 0x01;
                        F.Dlen++;
                        if (F.Dlen >= F.KDataRadio)
                        {
                            F.State = Fx25State.FxCheck;
                        }
                    }
                    break;

                case Fx25State.FxCheck:
                    if (dbit != 0)
                        F.Block[F.Coffs + F.Clen] |= F.IMask;

                    F.IMask <<= 1;
                    if (F.IMask == 0)
                    {
                        F.IMask = 0x01;
                        F.Clen++;
                        if (F.Clen >= F.NRoots)
                        {
                            ProcessRsBlock(chan, subchan, slice, F);

                            F.CtagNum = -1;
                            F.Accum = 0;
                            F.State = Fx25State.FxTag;
                        }
                    }
                    break;
            }
        }

        /// <summary>
        /// Check if FX.25 reception is currently in progress for a channel
        /// </summary>
        /// <param name="chan">Radio channel number</param>
        /// <returns>True if FX.25 block reception is in progress</returns>
        public bool IsBusy(int chan)
        {
            Debug.Assert(chan >= 0 && chan < MaxRadioChans);

            for (int i = 0; i < MaxSubchans; i++)
            {
                for (int j = 0; j < MaxSlicers; j++)
                {
                    if (_contexts[chan, i, j] != null)
                    {
                        if (_contexts[chan, i, j].State != Fx25State.FxTag)
                        {
                            return true;
                        }
                    }
                }
            }
            return false;
        }

        /// <summary>
        /// Process a complete Reed-Solomon block
        /// </summary>
        private void ProcessRsBlock(int chan, int subchan, int slice, Fx25Context F)
        {
            if (Fx25.GetDebugLevel() >= 3)
            {
                Console.WriteLine($"FX.25[{chan}.{slice}]: Received RS codeblock.");
                Fx25.HexDump(F.Block, Fx25.FX25_BLOCK_SIZE);
            }

            Debug.Assert(F.Block[Fx25.FX25_BLOCK_SIZE] == Fence);

            int[] derrLocs = new int[Fx25.FX25_MAX_CHECK];
            ReedSolomonCodec rs = Fx25.GetRs(F.CtagNum);

            int derrors = ReedSolomon.Decode(rs, F.Block, null, 0);

            if (derrors >= 0)
            {
                // Success: -1 for failure, >= 0 for success with number of bytes corrected
                if (Fx25.GetDebugLevel() >= 2)
                {
                    if (derrors == 0)
                    {
                        Console.WriteLine($"FX.25[{chan}.{slice}]: FEC complete with no errors.");
                    }
                    else
                    {
                        Console.WriteLine($"FX.25[{chan}.{slice}]: FEC complete, fixed {derrors,2} errors.");
                    }
                }

                byte[] frameBuf = new byte[Fx25.FX25_MAX_DATA + 1];
                int frameLen = Unstuff(chan, subchan, slice, F.Block, F.Dlen, frameBuf);

                if (frameLen >= 14 + 1 + 2)  // Minimum: Two addresses & control & FCS
                {
                    ushort actualFcs = (ushort)(frameBuf[frameLen - 2] | (frameBuf[frameLen - 1] << 8));
                    ushort expectedFcs = FcsCalc.Calculate(frameBuf, frameLen - 2);

                    if (actualFcs == expectedFcs)
                    {
                        if (Fx25.GetDebugLevel() >= 3)
                        {
                            Console.WriteLine($"FX.25[{chan}.{slice}]: Extracted AX.25 frame:");
                            Fx25.HexDump(frameBuf, frameLen);
                        }

                        // Create correction info for FX.25
                        CorrectionInfo corrInfo = new CorrectionInfo
                        {
                            CorrectionType = (RetryType)derrors,
                            FecType = FecType.Fx25,
                            CorrectedBitPositions = new List<int>(),
                            RsSymbolsCorrected = derrors,
                            FX25CorrelationTag = F.CtagNum,
                            FrameLengthBits = F.KDataRadio * 8,
                            FrameLengthBytes = frameLen - 2,
                            OriginalCrc = actualFcs,
                            ExpectedCrc = expectedFcs,
                            CrcValid = true
                        };

                        // Pass to MultiModem for further processing
                        if (_multiModem != null)
                        {
                            // Create a simple audio level (would be from demod in real implementation)
                            ALevel alevel = new ALevel();

                            _multiModem.ProcessRecFrame(chan, subchan, slice, frameBuf, frameLen - 2,
                                alevel, (RetryType)derrors, FecType.Fx25, F.CtagNum, corrInfo);
                        }
                    }
                    else
                    {
                        // Most likely cause is defective sender software
                        Console.WriteLine($"FX.25[{chan}.{slice}]: Bad FCS for AX.25 frame.");
                        Fx25.HexDump(F.Block, F.Dlen);
                        Fx25.HexDump(frameBuf, frameLen);
                    }
                }
                else
                {
                    // Most likely cause is defective sender software
                    Console.WriteLine($"FX.25[{chan}.{slice}]: AX.25 frame is shorter than minimum length.");
                    Fx25.HexDump(F.Block, F.Dlen);
                    Fx25.HexDump(frameBuf, frameLen);
                }
            }
            else if (Fx25.GetDebugLevel() >= 2)
            {
                Console.WriteLine($"FX.25[{chan}.{slice}]: FEC failed. Too many errors.");
            }
        }

        /// <summary>
        /// Remove HDLC bit stuffing and surrounding flag delimiters
        /// </summary>
        /// <param name="chan">Channel number (for error messages)</param>
        /// <param name="subchan">Subchannel number (for error messages)</param>
        /// <param name="slice">Slicer number (for error messages)</param>
        /// <param name="pin">Input data buffer</param>
        /// <param name="ilen">Input length</param>
        /// <param name="frameBuf">Output frame buffer</param>
        /// <returns>Number of bytes in frame buffer including FCS, or 0 if error</returns>
        private int Unstuff(int chan, int subchan, int slice, byte[] pin, int ilen, byte[] frameBuf)
        {
            byte patDet = 0;      // Pattern detector
            byte oacc = 0;        // Accumulator for a byte out
            int olen = 0;         // Number of good bits in oacc
            int frameLen = 0;     // Number of bytes accumulated, including CRC
            int pinIndex = 0;

            if (pin[0] != 0x7e)
            {
                Console.WriteLine($"FX.25[{chan}.{slice}] error: Data section did not start with 0x7e.");
                Fx25.HexDump(pin, ilen);
                return 0;
            }

            // Skip over leading flag byte(s)
            while (ilen > 0 && pin[pinIndex] == 0x7e)
            {
                ilen--;
                pinIndex++;
            }

            for (int i = 0; i < ilen; pinIndex++, i++)
            {
                for (byte imask = 0x01; imask != 0; imask <<= 1)
                {
                    byte dbit = (byte)((pin[pinIndex] & imask) != 0 ? 1 : 0);

                    // Shift the most recent eight bits through the pattern detector
                    patDet >>= 1;
                    patDet |= (byte)(dbit << 7);

                    if (patDet == 0xfe)
                    {
                        Console.WriteLine($"FX.25[{chan}.{slice}]: Invalid AX.25 frame - Seven '1' bits in a row.");
                        Fx25.HexDump(pin, ilen);
                        return 0;
                    }

                    if (dbit != 0)
                    {
                        oacc >>= 1;
                        oacc |= 0x80;
                    }
                    else
                    {
                        if (patDet == 0x7e)
                        {
                            // "flag" pattern - End of frame
                            if (olen == 7)
                            {
                                return frameLen;  // Whole number of bytes in result including CRC
                            }
                            else
                            {
                                Console.WriteLine($"FX.25[{chan}.{slice}]: Invalid AX.25 frame - Not a whole number of bytes.");
                                Fx25.HexDump(pin, ilen);
                                return 0;
                            }
                        }
                        else if ((patDet >> 2) == 0x1f)
                        {
                            // Five '1' bits in a row, followed by '0'. Discard the '0'
                            continue;
                        }
                        oacc >>= 1;
                    }

                    olen++;
                    if ((olen & 8) != 0)
                    {
                        olen = 0;
                        frameBuf[frameLen++] = oacc;
                    }
                }
            }

            Console.WriteLine($"FX.25[{chan}.{slice}]: Invalid AX.25 frame - Terminating flag not found.");
            Fx25.HexDump(pin, ilen);
            return 0;
        }

        /// <summary>
        /// Count number of '1' bits in a 64-bit integer
        /// </summary>
        private int PopCount(ulong x)
        {
            int count = 0;
            while (x != 0)
            {
                count++;
                x &= x - 1;  // Clear the least significant bit set
            }
            return count;
        }
    }
}
