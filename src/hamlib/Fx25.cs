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
// Fx25.cs - FX.25 Forward Error Correction support structures and initialization
//

using System;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// Reed-Solomon codec control block
    /// </summary>
    public class ReedSolomonCodec
    {
        public uint MM { get; set; }              // Bits per symbol
        public uint NN { get; set; }              // Symbols per block (= (1<<mm)-1)
        public byte[] AlphaTo { get; set; }       // log lookup table
        public byte[] IndexOf { get; set; }       // Antilog lookup table
        public byte[] GenPoly { get; set; }       // Generator polynomial
        public uint NRoots { get; set; }          // Number of generator roots = number of parity symbols
        public byte Fcr { get; set; }             // First consecutive root, index form
        public byte Prim { get; set; }            // Primitive element, index form
        public byte IPrim { get; set; }           // prim-th root of 1, index form

        public ReedSolomonCodec()
        {
            AlphaTo = Array.Empty<byte>();
            IndexOf = Array.Empty<byte>();
            GenPoly = Array.Empty<byte>();
        }

        /// <summary>
        /// Modulo NN operation optimized for Reed-Solomon
        /// </summary>
        public int ModNN(int x)
        {
            while (x >= NN)
            {
                x -= (int)NN;
                x = (x >> (int)MM) + (x & (int)NN);
            }
            return x;
        }
    }

    /// <summary>
    /// FX.25 correlation tag definition
    /// </summary>
    internal class CorrelationTag
    {
        public ulong Value { get; set; }          // 64 bit value, send LSB first
        public int NBlockRadio { get; set; }      // Size of transmitted block, all in bytes
        public int KDataRadio { get; set; }       // Size of transmitted data part
        public int NBlockRs { get; set; }         // Size of RS algorithm block
        public int KDataRs { get; set; }          // Size of RS algorithm data part
        public int ITab { get; set; }             // Index into Tab array
    }

    /// <summary>
    /// FX.25 codec configuration
    /// </summary>
    internal class Fx25CodecConfig
    {
        public int SymSize { get; set; }          // Symbol size, bits (1-8). Always 8 for this application
        public int GenPoly { get; set; }          // Field generator polynomial coefficients
        public int Fcs { get; set; }              // First root of RS code generator polynomial, index form
        public int Prim { get; set; }             // Primitive element to generate polynomial roots
        public int NRoots { get; set; }           // RS code generator polynomial degree (number of roots)
        public ReedSolomonCodec Rs { get; set; }  // Pointer to RS codec control block
    }

    /// <summary>
    /// FX.25 static configuration and helper functions
    /// </summary>
    public static class Fx25
    {
        // Constants
        public const int CTAG_MIN = 0x01;
        public const int CTAG_MAX = 0x0B;
        public const int FX25_MAX_DATA = 239;      // i.e. RS(255,239)
        public const int FX25_MAX_CHECK = 64;      // e.g. RS(255, 191)
        public const int FX25_BLOCK_SIZE = 255;    // Block size always 255 for 8 bit symbols
        private const int CLOSE_ENOUGH = 8;        // How many bits can be wrong in tag yet consider it a match?

        private static readonly Fx25CodecConfig[] CodecTab = new Fx25CodecConfig[3]
        {
            new Fx25CodecConfig { SymSize = 8, GenPoly = 0x11d, Fcs = 1, Prim = 1, NRoots = 16, Rs = null },  // RS(255,239)
            new Fx25CodecConfig { SymSize = 8, GenPoly = 0x11d, Fcs = 1, Prim = 1, NRoots = 32, Rs = null },  // RS(255,223)
            new Fx25CodecConfig { SymSize = 8, GenPoly = 0x11d, Fcs = 1, Prim = 1, NRoots = 64, Rs = null }   // RS(255,191)
        };

        private static readonly CorrelationTag[] Tags = new CorrelationTag[16]
        {
            // Tag_00 - Reserved
            new CorrelationTag { Value = 0x566ED2717946107EUL, NBlockRadio = 0, KDataRadio = 0, NBlockRs = 0, KDataRs = 0, ITab = -1 },

            // Tag_01 - RS(255, 239) 16-byte check value, 239 information bytes
            new CorrelationTag { Value = 0xB74DB7DF8A532F3EUL, NBlockRadio = 255, KDataRadio = 239, NBlockRs = 255, KDataRs = 239, ITab = 0 },
            // Tag_02 - RS(144,128) - shortened RS(255, 239), 128 info bytes
            new CorrelationTag { Value = 0x26FF60A600CC8FDEUL, NBlockRadio = 144, KDataRadio = 128, NBlockRs = 255, KDataRs = 239, ITab = 0 },
            // Tag_03 - RS(80,64) - shortened RS(255, 239), 64 info bytes
            new CorrelationTag { Value = 0xC7DC0508F3D9B09EUL, NBlockRadio = 80, KDataRadio = 64, NBlockRs = 255, KDataRs = 239, ITab = 0 },
            // Tag_04 - RS(48,32) - shortened RS(255, 239), 32 info bytes
            new CorrelationTag { Value = 0x8F056EB4369660EEUL, NBlockRadio = 48, KDataRadio = 32, NBlockRs = 255, KDataRs = 239, ITab = 0 },

            // Tag_05 - RS(255, 223) 32-byte check value, 223 information bytes
            new CorrelationTag { Value = 0x6E260B1AC5835FAEUL, NBlockRadio = 255, KDataRadio = 223, NBlockRs = 255, KDataRs = 223, ITab = 1 },
            // Tag_06 - RS(160,128) - shortened RS(255, 223), 128 info bytes
            new CorrelationTag { Value = 0xFF94DC634F1CFF4EUL, NBlockRadio = 160, KDataRadio = 128, NBlockRs = 255, KDataRs = 223, ITab = 1 },
            // Tag_07 - RS(96,64) - shortened RS(255, 223), 64 info bytes
            new CorrelationTag { Value = 0x1EB7B9CDBC09C00EUL, NBlockRadio = 96, KDataRadio = 64, NBlockRs = 255, KDataRs = 223, ITab = 1 },
            // Tag_08 - RS(64,32) - shortened RS(255, 223), 32 info bytes
            new CorrelationTag { Value = 0xDBF869BD2DBB1776UL, NBlockRadio = 64, KDataRadio = 32, NBlockRs = 255, KDataRs = 223, ITab = 1 },

            // Tag_09 - RS(255, 191) 64-byte check value, 191 information bytes
            new CorrelationTag { Value = 0x3ADB0C13DEAE2836UL, NBlockRadio = 255, KDataRadio = 191, NBlockRs = 255, KDataRs = 191, ITab = 2 },
            // Tag_0A - RS(192, 128) - shortened RS(255, 191), 128 info bytes
            new CorrelationTag { Value = 0xAB69DB6A543188D6UL, NBlockRadio = 192, KDataRadio = 128, NBlockRs = 255, KDataRs = 191, ITab = 2 },
            // Tag_0B - RS(128, 64) - shortened RS(255, 191), 64 info bytes
            new CorrelationTag { Value = 0x4A4ABEC4A724B796UL, NBlockRadio = 128, KDataRadio = 64, NBlockRs = 255, KDataRs = 191, ITab = 2 },

            // Tag_0C through 0F - Undefined
            new CorrelationTag { Value = 0x0293D578626B67E6UL, NBlockRadio = 0, KDataRadio = 0, NBlockRs = 0, KDataRs = 0, ITab = -1 },
            new CorrelationTag { Value = 0xE3B0B0D6917E58A6UL, NBlockRadio = 0, KDataRadio = 0, NBlockRs = 0, KDataRs = 0, ITab = -1 },
            new CorrelationTag { Value = 0x720267AF1BE1F846UL, NBlockRadio = 0, KDataRadio = 0, NBlockRs = 0, KDataRs = 0, ITab = -1 },
            new CorrelationTag { Value = 0x93210201E8F4C706UL, NBlockRadio = 0, KDataRadio = 0, NBlockRs = 0, KDataRs = 0, ITab = -1 }
        };

        private static int _debugLevel = 0;
        //private static bool _initialized = false;

        /// <summary>
        /// Initialize FX.25 subsystem
        /// </summary>
        /// <param name="debugLevel">Debug level (0=errors only, 1=default, 2=verbose, 3=dump data)</param>
        public static void Init(int debugLevel)
        {
            _debugLevel = debugLevel;

            // Initialize Reed-Solomon codecs
            for (int i = 0; i < CodecTab.Length; i++)
            {
                CodecTab[i].Rs = InitRs((uint)CodecTab[i].SymSize, (uint)CodecTab[i].GenPoly,
                    (uint)CodecTab[i].Fcs, (uint)CodecTab[i].Prim, (uint)CodecTab[i].NRoots);

                if (CodecTab[i].Rs == null)
                {
                    Console.WriteLine("FX.25 internal error: InitRs failed!");
                    Environment.Exit(1);
                }
            }

            // Verify integrity of tables and assumptions
            for (int j = 0; j < 16; j++)
            {
                for (int k = 0; k < 16; k++)
                {
                    int popcount = PopCount(Tags[j].Value ^ Tags[k].Value);
                    if (j == k)
                    {
                        Debug.Assert(popcount == 0);
                    }
                    else
                    {
                        Debug.Assert(popcount == 32);
                    }
                }
            }

            // Verify tag configurations
            for (int j = CTAG_MIN; j <= CTAG_MAX; j++)
            {
                Debug.Assert(Tags[j].NBlockRadio - Tags[j].KDataRadio == CodecTab[Tags[j].ITab].NRoots);
                Debug.Assert(Tags[j].NBlockRs - Tags[j].KDataRs == CodecTab[Tags[j].ITab].NRoots);
                Debug.Assert(Tags[j].NBlockRs == FX25_BLOCK_SIZE);
            }

            //_initialized = true;
        }

        /// <summary>
        /// Get the Reed-Solomon codec for a specific correlation tag
        /// </summary>
        public static ReedSolomonCodec GetRs(int ctagNum)
        {
            Debug.Assert(ctagNum >= CTAG_MIN && ctagNum <= CTAG_MAX);
            Debug.Assert(Tags[ctagNum].ITab >= 0 && Tags[ctagNum].ITab < CodecTab.Length);
            Debug.Assert(CodecTab[Tags[ctagNum].ITab].Rs != null);
            return CodecTab[Tags[ctagNum].ITab].Rs;
        }

        /// <summary>
        /// Get correlation tag value
        /// </summary>
        public static ulong GetCtagValue(int ctagNum)
        {
            Debug.Assert(ctagNum >= CTAG_MIN && ctagNum <= CTAG_MAX);
            return Tags[ctagNum].Value;
        }

        /// <summary>
        /// Get data size transmitted over radio
        /// </summary>
        public static int GetKDataRadio(int ctagNum)
        {
            Debug.Assert(ctagNum >= CTAG_MIN && ctagNum <= CTAG_MAX);
            return Tags[ctagNum].KDataRadio;
        }

        /// <summary>
        /// Get data size for RS algorithm
        /// </summary>
        public static int GetKDataRs(int ctagNum)
        {
            Debug.Assert(ctagNum >= CTAG_MIN && ctagNum <= CTAG_MAX);
            return Tags[ctagNum].KDataRs;
        }

        /// <summary>
        /// Get number of check bytes (roots)
        /// </summary>
        public static int GetNRoots(int ctagNum)
        {
            Debug.Assert(ctagNum >= CTAG_MIN && ctagNum <= CTAG_MAX);
            return CodecTab[Tags[ctagNum].ITab].NRoots;
        }

        /// <summary>
        /// Get current debug level
        /// </summary>
        public static int GetDebugLevel()
        {
            return _debugLevel;
        }

        /// <summary>
        /// Pick suitable transmission format based on user preference and size of data part required
        /// </summary>
        /// <param name="fxMode">FX.25 mode selection:
        /// - 0 = none (disable FX.25)
        /// - 1 = pick a tag automatically
        /// - 16, 32, 64 = use this many check bytes
        /// - 100 + n = use tag n (0x01-0x0B)</param>
        /// <param name="dlen">Required size for transmitted "data" part, in bytes.
        /// This includes the AX.25 frame with bit stuffing and a flag pattern on each end.</param>
        /// <returns>Correlation tag number in range of CTAG_MIN thru CTAG_MAX, or -1 for failure</returns>
        public static int PickMode(int fxMode, int dlen)
        {
            if (fxMode <= 0) return -1;

            // Specify a specific tag by adding 100 to the number.
            // Fails if data won't fit.
            if (fxMode - 100 >= CTAG_MIN && fxMode - 100 <= CTAG_MAX)
            {
                if (dlen <= GetKDataRadio(fxMode - 100))
                {
                    return fxMode - 100;
                }
                else
                {
                    return -1; // Assuming caller prints failure message
                }
            }

            // Specify number of check bytes.
            // Pick the shortest one that can handle the required data length.
            else if (fxMode == 16 || fxMode == 32 || fxMode == 64)
            {
                for (int k = CTAG_MAX; k >= CTAG_MIN; k--)
                {
                    if (fxMode == GetNRoots(k) && dlen <= GetKDataRadio(k))
                    {
                        return k;
                    }
                }
                return -1;
            }

            // For any other number, try to come up with something reasonable.
            // For shorter frames, use smaller overhead. For longer frames, where
            // an error is more probable, use more check bytes. When the data gets
            // even larger, check bytes must be reduced to fit in block size.
            //
            // Tag  Data  Check  Max Num
            // Number Bytes Bytes Repaired
            // -----------------------
            // 0x04   32    16     8
            // 0x03   64    16     8
            // 0x06  128    32    16
            // 0x09  191    64    32
            // 0x05  223    32    16
            // 0x01  239    16     8
            // none  larger
            int[] prefer = { 0x04, 0x03, 0x06, 0x09, 0x05, 0x01 };
            for (int k = 0; k < prefer.Length; k++)
            {
                int m = prefer[k];
                if (dlen <= GetKDataRadio(m))
                {
                    return m;
                }
            }
            return -1;
        }

        /// <summary>
        /// Find matching correlation tag
        /// </summary>
        /// <param name="t">64-bit correlation tag value</param>
        /// <returns>Tag index (CTAG_MIN to CTAG_MAX) or -1 if no match</returns>
        public static int TagFindMatch(ulong t)
        {
            for (int c = CTAG_MIN; c <= CTAG_MAX; c++)
            {
                if (PopCount(t ^ Tags[c].Value) <= CLOSE_ENOUGH)
                {
                    return c;
                }
            }
            return -1;
        }

        /// <summary>
        /// Count number of '1' bits in a 64-bit integer
        /// </summary>
        private static int PopCount(ulong x)
        {
            int count = 0;
            while (x != 0)
            {
                count++;
                x &= x - 1;  // Clear the least significant bit set
            }
            return count;
        }

        /// <summary>
        /// Initialize a Reed-Solomon codec
        /// </summary>
        private static ReedSolomonCodec InitRs(uint symsize, uint gfpoly, uint fcr, uint prim, uint nroots)
        {
            if (symsize > 8)
                return null;

            if (fcr >= (1u << (int)symsize))
                return null;

            if (prim == 0 || prim >= (1u << (int)symsize))
                return null;

            if (nroots >= (1u << (int)symsize))
                return null;

            var rs = new ReedSolomonCodec
            {
                MM = symsize,
                NN = (1u << (int)symsize) - 1
            };

            rs.AlphaTo = new byte[rs.NN + 1];
            rs.IndexOf = new byte[rs.NN + 1];

            // Generate Galois field lookup tables
            uint A0 = rs.NN;
            rs.IndexOf[0] = (byte)A0;  // log(zero) = -inf
            rs.AlphaTo[A0] = 0;        // alpha**-inf = 0

            uint sr = 1;
            for (int i = 0; i < rs.NN; i++)
            {
                rs.IndexOf[sr] = (byte)i;
                rs.AlphaTo[i] = (byte)sr;
                sr <<= 1;
                if ((sr & (1u << (int)symsize)) != 0)
                    sr ^= gfpoly;
                sr &= rs.NN;
            }

            if (sr != 1)
            {
                // Field generator polynomial is not primitive
                return null;
            }

            // Form RS code generator polynomial from its roots
            rs.GenPoly = new byte[nroots + 1];
            rs.Fcr = (byte)fcr;
            rs.Prim = (byte)prim;
            rs.NRoots = nroots;

            // Find prim-th root of 1, used in decoding
            uint iprim;
            for (iprim = 1; (iprim % prim) != 0; iprim += rs.NN)
                ;
            rs.IPrim = (byte)(iprim / prim);

            rs.GenPoly[0] = 1;
            for (int i = 0, root = (int)(fcr * prim); i < nroots; i++, root += (int)prim)
            {
                rs.GenPoly[i + 1] = 1;

                // Multiply rs.genpoly[] by @**(root + x)
                for (int j = i; j > 0; j--)
                {
                    if (rs.GenPoly[j] != 0)
                        rs.GenPoly[j] = (byte)(rs.GenPoly[j - 1] ^ rs.AlphaTo[rs.ModNN(rs.IndexOf[rs.GenPoly[j]] + root)]);
                    else
                        rs.GenPoly[j] = rs.GenPoly[j - 1];
                }
                rs.GenPoly[0] = rs.AlphaTo[rs.ModNN(rs.IndexOf[rs.GenPoly[0]] + root)];
            }

            // Convert rs.genpoly[] to index form for quicker encoding
            for (int i = 0; i <= nroots; i++)
            {
                rs.GenPoly[i] = rs.IndexOf[rs.GenPoly[i]];
            }

            return rs;
        }

        /// <summary>
        /// Hex dump utility for debugging
        /// </summary>
        public static void HexDump(byte[] data, int len)
        {
            int offset = 0;
            while (len > 0)
            {
                int n = Math.Min(len, 16);
                Console.Write($"  {offset:x3}: ");

                for (int i = 0; i < n; i++)
                {
                    Console.Write($" {data[offset + i]:x2}");
                }

                for (int i = n; i < 16; i++)
                {
                    Console.Write("   ");
                }

                Console.Write("  ");
                for (int i = 0; i < n; i++)
                {
                    char c = (char)data[offset + i];
                    // char.IsAscii not available in .NET Framework 4.8, check manually
                    Console.Write(c >= 32 && c < 127 ? c : '.');
                }
                Console.WriteLine();

                offset += 16;
                len -= 16;
            }
        }
    }
}
