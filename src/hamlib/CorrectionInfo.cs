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
// CorrectionInfo.cs - Detailed information about packet error correction
//
// Purpose: Provide detailed statistics about how a packet was corrected
// to enable channel condition monitoring and error analysis.
//

using System;
using System.Collections.Generic;
using System.Linq;

namespace HamLib
{
    /// <summary>
    /// Detailed information about error correction applied to a packet
    /// </summary>
    public class CorrectionInfo
    {
        /// <summary>
        /// Type of error correction applied
        /// </summary>
        public RetryType CorrectionType { get; set; }

        /// <summary>
        /// Forward Error Correction type used (if any)
        /// </summary>
        public FecType FecType { get; set; }

        /// <summary>
        /// Bit positions that were inverted (for HDLC bit-flip corrections)
        /// Empty if no bit flips were applied
        /// </summary>
        public List<int> CorrectedBitPositions { get; set; }

        /// <summary>
        /// Number of Reed-Solomon symbols/bytes corrected (for FX.25/IL2P)
        /// -1 if not applicable or RS decoding failed
        /// </summary>
        public int RsSymbolsCorrected { get; set; }

        /// <summary>
        /// FX.25 correlation tag number (-1 if not FX.25)
        /// Indicates the RS block size used
        /// </summary>
        public int FX25CorrelationTag { get; set; }

        /// <summary>
        /// Total frame length in bits (for BER calculation)
        /// </summary>
        public int FrameLengthBits { get; set; }

        /// <summary>
        /// Total frame length in bytes
        /// </summary>
        public int FrameLengthBytes { get; set; }

        /// <summary>
        /// Original CRC value from received frame
        /// </summary>
        public ushort OriginalCrc { get; set; }

        /// <summary>
        /// Expected CRC value after correction
        /// </summary>
        public ushort ExpectedCrc { get; set; }

        /// <summary>
        /// Whether the CRC matched (true) or was passed through with bad CRC (false)
        /// </summary>
        public bool CrcValid { get; set; }

        /// <summary>
        /// Constructor
        /// </summary>
        public CorrectionInfo()
        {
            CorrectionType = RetryType.None;
            FecType = FecType.None;
            CorrectedBitPositions = new List<int>();
            RsSymbolsCorrected = -1;
            FX25CorrelationTag = -1;
            FrameLengthBits = 0;
            FrameLengthBytes = 0;
            OriginalCrc = 0;
            ExpectedCrc = 0;
            CrcValid = true;
        }

        /// <summary>
        /// Calculate bit error rate (BER) based on corrections
        /// </summary>
        public double CalculateBER()
        {
            if (FrameLengthBits <= 0)
                return 0.0;

            int bitsFlipped = CorrectedBitPositions.Count;
            
            // For FX.25, estimate bits corrected (8 bits per symbol)
            if (FecType == FecType.Fx25 && RsSymbolsCorrected > 0)
            {
                // This is a rough estimate - RS corrects symbols, not individual bits
                bitsFlipped = RsSymbolsCorrected * 8;
            }

            return (double)bitsFlipped / FrameLengthBits;
        }

        /// <summary>
        /// Get a human-readable description of the correction
        /// </summary>
        public string GetDescription()
        {
            if (FecType == FecType.Fx25)
            {
                if (RsSymbolsCorrected == 0)
                    return "FX.25: No errors detected";
                else if (RsSymbolsCorrected > 0)
                    return $"FX.25: Corrected {RsSymbolsCorrected} symbol(s), Tag=0x{FX25CorrelationTag:X2}";
                else
                    return "FX.25: Too many errors to correct";
            }
            else if (FecType == FecType.Il2p)
            {
                if (RsSymbolsCorrected == 0)
                    return "IL2P: No errors detected";
                else if (RsSymbolsCorrected > 0)
                    return $"IL2P: Corrected {RsSymbolsCorrected} symbol(s)";
                else
                    return "IL2P: Too many errors to correct";
            }
            else
            {
                switch (CorrectionType)
                {
                    case RetryType.None:
                        return CrcValid ? "No correction needed" : "Bad CRC (passed through)";
                    
                    case RetryType.InvertSingle:
                        return $"Fixed by inverting 1 bit at position {CorrectedBitPositions.FirstOrDefault()}";
                    
                    case RetryType.InvertDouble:
                        return $"Fixed by inverting 2 adjacent bits at positions {string.Join(",", CorrectedBitPositions)}";
                    
                    case RetryType.InvertTriple:
                        return $"Fixed by inverting 3 adjacent bits at positions {string.Join(",", CorrectedBitPositions)}";
                    
                    case RetryType.InvertTwoSep:
                        return $"Fixed by inverting 2 separated bits at positions {string.Join(",", CorrectedBitPositions)}";
                    
                    case RetryType.Max:
                        return "Bad CRC (passed through)";
                    
                    default:
                        return "Unknown correction type";
                }
            }
        }

        /// <summary>
        /// Get statistics summary for logging
        /// </summary>
        public override string ToString()
        {
            string fecInfo = FecType != FecType.None ? $", FEC={FecType}" : "";
            string berInfo = FrameLengthBits > 0 ? $", BER={CalculateBER():E2}" : "";
            return $"Correction: {GetDescription()}{fecInfo}{berInfo}";
        }
    }
}
