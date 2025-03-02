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

using System;
using System.Text;
using System.Security.Cryptography;

// Usefu Github stuff for WinLink
// https://github.com/la5nta/wl2k-go
// https://github.com/la5nta/wl2k-go/blob/c52b1a2774edb0c7829d377ae4f21b2ae75c907a/docs/F6FBB-B2F/protocole.html
// https://outpostpm.org/index.php?content=bbs/bbswl2k
// https://raw.githubusercontent.com/ham-radio-software/lzhuf/refs/heads/main/lzhuf.c
// https://raw.githubusercontent.com/ARSFI/Winlink-Compression/refs/heads/master/WinlinkSupport.vb
// https://raw.githubusercontent.com/nwdigitalradio/paclink-unix/cc7b2f9474959a70856cabaf812bfce53d2da145/lzhuf_1.c
// https://kg4nxo.com/wp-content/uploads/2021/04/WINLINK-COMMAND-CODES.pdf

namespace HTCommander.radio
{
    public static class WinlinkSecurity
    {
        private static readonly byte[] WinlinkSecureSalt = new byte[]
        {
            77, 197, 101, 206, 190, 249, 93, 200, 51, 243, 93, 237, 71, 94, 239, 138, 68, 108,
            70, 185, 225, 137, 217, 16, 51, 122, 193, 48, 194, 195, 198, 175, 172, 169, 70, 84, 61, 62, 104, 186, 114, 52,
            61, 168, 66, 129, 192, 208, 187, 249, 232, 193, 41, 113, 41, 45, 240, 16, 29, 228, 208, 228, 61, 20
        };

        public static bool Test()
        {
            if (WinlinkSecurity.SecureLoginResponse("23753528", "FOOBAR") != "72768415") return false;
            if (WinlinkSecurity.SecureLoginResponse("23753528", "FooBar") != "95074758") return false;
            return true;
        }

        // Used for WinLink login
        public static string SecureLoginResponse(string challenge, string password)
        {
            // MD5(challenge + password + WinlinkSecureSalt)
            byte[] a1 = Encoding.ASCII.GetBytes(challenge);
            byte[] a2 = Encoding.ASCII.GetBytes(password);
            byte[] a3 = WinlinkSecureSalt;

            byte[] rv = new byte[a1.Length + a2.Length + a3.Length];
            Buffer.BlockCopy(a1, 0, rv, 0, a1.Length);
            Buffer.BlockCopy(a2, 0, rv, a1.Length, a2.Length);
            Buffer.BlockCopy(a3, 0, rv, a1.Length + a2.Length, a3.Length);

            using (MD5 md5 = MD5.Create())
            {
                byte[] hashBytes = md5.ComputeHash(rv);
                int pr = hashBytes[3] & 0x3f;
                for (int i = 2; i >= 0; i--) { pr = (pr << 8) | hashBytes[i]; }
                string str = pr.ToString("D8"); // "D8" formats as decimal with 8 digits, padding with leading zeros
                return str.Substring(str.Length - 8);
            }
        }
    }

    public class WinlinkCompression
    {
        private static readonly object LZSync = new object();
        private const int N = 2048;
        private const int F = 60;
        private const int Threshold = 2;
        private const int NodeNIL = N;
        private const int NChar = (256 - Threshold) + F;
        private const int T = (NChar * 2) - 1;
        private const int R = T - 1;
        private const int MaxFreq = 0x8000;
        private const int TBSize = N + F - 2;
        private static byte[] textBuf = new byte[TBSize + 1];
        private static int[] lSon = new int[N + 1];
        private static int[] dad = new int[N + 1];
        private static int[] rSon = new int[N + 256 + 1];
        private static int[] freq = new int[T + 1];
        private static int[] son = new int[T];
        private static int[] parent = new int[T + NChar];

        // Tables for encoding/decoding upper 6 bits of sliding dictionary pointer encoder table}
        // Position Encode length
        private static byte[] p_len = {
                0x3, 0x4, 0x4, 0x4, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
                0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
                0x8, 0x8, 0x8, 0x8
            };

        // Position Encode Table
        private static int[] p_code = {
                0x0, 0x20, 0x30, 0x40, 0x50, 0x58,
                0x60, 0x68, 0x70, 0x78, 0x80, 0x88,
                0x90, 0x94, 0x98, 0x9C, 0xA0, 0xA4,
                0xA8, 0xAC, 0xB0, 0xB4, 0xB8, 0xBC,
                0xC0, 0xC2, 0xC4, 0xC6, 0xC8, 0xCA,
                0xCC, 0xCE, 0xD0, 0xD2, 0xD4, 0xD6,
                0xD8, 0xDA, 0xDC, 0xDE, 0xE0, 0xE2,
                0xE4, 0xE6, 0xE8, 0xEA, 0xEC, 0xEE,
                0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5,
                0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB,
                0xFC, 0xFD, 0xFE, 0xFF
            };

        // Position decode table
        private static int[] d_code = {
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
                0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
                0x02, 0x02, 0x02, 0x02, 0x03, 0x03,
                0x03, 0x03, 0x03, 0x03, 0x03, 0x03,
                0x03, 0x03, 0x03, 0x03, 0x03, 0x03,
                0x03, 0x03, 0x04, 0x04, 0x04, 0x04,
                0x04, 0x04, 0x04, 0x04, 0x05, 0x05,
                0x05, 0x05, 0x05, 0x05, 0x05, 0x05,
                0x06, 0x06, 0x06, 0x06, 0x06, 0x06,
                0x06, 0x06, 0x07, 0x07, 0x07, 0x07,
                0x07, 0x07, 0x07, 0x07, 0x08, 0x08,
                0x08, 0x08, 0x08, 0x08, 0x08, 0x08,
                0x09, 0x09, 0x09, 0x09, 0x09, 0x09,
                0x09, 0x09, 0x0A, 0x0A, 0x0A, 0x0A,
                0x0A, 0x0A, 0x0A, 0x0A, 0x0B, 0x0B,
                0x0B, 0x0B, 0x0B, 0x0B, 0x0B, 0x0B,
                0x0C, 0x0C, 0x0C, 0x0C, 0x0D, 0x0D,
                0x0D, 0x0D, 0x0E, 0x0E, 0x0E, 0x0E,
                0x0F, 0x0F, 0x0F, 0x0F, 0x10, 0x10,
                0x10, 0x10, 0x11, 0x11, 0x11, 0x11,
                0x12, 0x12, 0x12, 0x12, 0x13, 0x13,
                0x13, 0x13, 0x14, 0x14, 0x14, 0x14,
                0x15, 0x15, 0x15, 0x15, 0x16, 0x16,
                0x16, 0x16, 0x17, 0x17, 0x17, 0x17,
                0x18, 0x18, 0x19, 0x19, 0x1A, 0x1A,
                0x1B, 0x1B, 0x1C, 0x1C, 0x1D, 0x1D,
                0x1E, 0x1E, 0x1F, 0x1F, 0x20, 0x20,
                0x21, 0x21, 0x22, 0x22, 0x23, 0x23,
                0x24, 0x24, 0x25, 0x25, 0x26, 0x26,
                0x27, 0x27, 0x28, 0x28, 0x29, 0x29,
                0x2A, 0x2A, 0x2B, 0x2B, 0x2C, 0x2C,
                0x2D, 0x2D, 0x2E, 0x2E, 0x2F, 0x2F,
                0x30, 0x31, 0x32, 0x33, 0x34, 0x35,
                0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B,
                0x3C, 0x3D, 0x3E, 0x3F
            };

        // Position decode length
        private static int[] d_len = {
                0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
                0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
                0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
                0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
                0x3, 0x3, 0x3, 0x3, 0x3, 0x3,
                0x3, 0x3, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x4, 0x4, 0x4, 0x4,
                0x4, 0x4, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x5, 0x5, 0x5, 0x5, 0x5, 0x5,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x6, 0x6, 0x6, 0x6, 0x6, 0x6,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x7, 0x7, 0x7, 0x7, 0x7, 0x7,
                0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
                0x8, 0x8, 0x8, 0x8, 0x8, 0x8,
                0x8, 0x8, 0x8, 0x8
            };

        // CRC Table 
        // Word->UInt16
        private static int CRCMask = 0xFFFF;
        private static int[] CRCTable = {
                0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50A5,
                0x60C6, 0x70E7, 0x8108, 0x9129, 0xA14A, 0xB16B,
                0xC18C, 0xD1AD, 0xE1CE, 0xF1EF, 0x1231, 0x0210,
                0x3273, 0x2252, 0x52B5, 0x4294, 0x72F7, 0x62D6,
                0x9339, 0x8318, 0xB37B, 0xA35A, 0xD3BD, 0xC39C,
                0xF3FF, 0xE3DE, 0x2462, 0x3443, 0x0420, 0x1401,
                0x64E6, 0x74C7, 0x44A4, 0x5485, 0xA56A, 0xB54B,
                0x8528, 0x9509, 0xE5EE, 0xF5CF, 0xC5AC, 0xD58D,
                0x3653, 0x2672, 0x1611, 0x0630, 0x76D7, 0x66F6,
                0x5695, 0x46B4, 0xB75B, 0xA77A, 0x9719, 0x8738,
                0xF7DF, 0xE7FE, 0xD79D, 0xC7BC, 0x48C4, 0x58E5,
                0x6886, 0x78A7, 0x0840, 0x1861, 0x2802, 0x3823,
                0xC9CC, 0xD9ED, 0xE98E, 0xF9AF, 0x8948, 0x9969,
                0xA90A, 0xB92B, 0x5AF5, 0x4AD4, 0x7AB7, 0x6A96,
                0x1A71, 0x0A50, 0x3A33, 0x2A12, 0xDBFD, 0xCBDC,
                0xFBBF, 0xEB9E, 0x9B79, 0x8B58, 0xBB3B, 0xAB1A,
                0x6CA6, 0x7C87, 0x4CE4, 0x5CC5, 0x2C22, 0x3C03,
                0x0C60, 0x1C41, 0xEDAE, 0xFD8F, 0xCDEC, 0xDDCD,
                0xAD2A, 0xBD0B, 0x8D68, 0x9D49, 0x7E97, 0x6EB6,
                0x5ED5, 0x4EF4, 0x3E13, 0x2E32, 0x1E51, 0x0E70,
                0xFF9F, 0xEFBE, 0xDFDD, 0xCFFC, 0xBF1B, 0xAF3A,
                0x9F59, 0x8F78, 0x9188, 0x81A9, 0xB1CA, 0xA1EB,
                0xD10C, 0xC12D, 0xF14E, 0xE16F, 0x1080, 0x00A1,
                0x30C2, 0x20E3, 0x5004, 0x4025, 0x7046, 0x6067,
                0x83B9, 0x9398, 0xA3FB, 0xB3DA, 0xC33D, 0xD31C,
                0xE37F, 0xF35E, 0x02B1, 0x1290, 0x22F3, 0x32D2,
                0x4235, 0x5214, 0x6277, 0x7256, 0xB5EA, 0xA5CB,
                0x95A8, 0x8589, 0xF56E, 0xE54F, 0xD52C, 0xC50D,
                0x34E2, 0x24C3, 0x14A0, 0x0481, 0x7466, 0x6447,
                0x5424, 0x4405, 0xA7DB, 0xB7FA, 0x8799, 0x97B8,
                0xE75F, 0xF77E, 0xC71D, 0xD73C, 0x26D3, 0x36F2,
                0x0691, 0x16B0, 0x6657, 0x7676, 0x4615, 0x5634,
                0xD94C, 0xC96D, 0xF90E, 0xE92F, 0x99C8, 0x89E9,
                0xB98A, 0xA9AB, 0x5844, 0x4865, 0x7806, 0x6827,
                0x18C0, 0x08E1, 0x3882, 0x28A3, 0xCB7D, 0xDB5C,
                0xEB3F, 0xFB1E, 0x8BF9, 0x9BD8, 0xABBB, 0xBB9A,
                0x4A75, 0x5A54, 0x6A37, 0x7A16, 0x0AF1, 0x1AD0,
                0x2AB3, 0x3A92, 0xFD2E, 0xED0F, 0xDD6C, 0xCD4D,
                0xBDAA, 0xAD8B, 0x9DE8, 0x8DC9, 0x7C26, 0x6C07,
                0x5C64, 0x4C45, 0x3CA2, 0x2C83, 0x1CE0, 0x0CC1,
                0xEF1F, 0xFF3E, 0xCF5D, 0xDF7C, 0xAF9B, 0xBFBA,
                0x8FD9, 0x9FF8, 0x6E17, 0x7E36, 0x4E55, 0x5E74,
                0x2E93, 0x3EB2, 0x0ED1, 0x1EF0
            };

        private static byte[] inBuf = null;
        private static byte[] outBuf = null;
        private static int inPtr = 0;
        private static int inEnd = 0;
        private static int outPtr = 0;
        private static int CRC;
        private static bool EncDec = false; // true for Encode, false for Decode
        private static int getBuf = 0;
        private static int getLen = 0;
        private static int putBuf = 0;
        private static int putLen = 0;
        private static int textSize = 0;
        private static int codeSize = 0;
        private static int matchPosition = 0;
        private static int matchLength = 0;

        public static int Encode(byte[] iBuf, ref byte[] oBuf, bool prependCRC)
        {
            int tmp = 0;
            return Encode(iBuf, ref oBuf, ref tmp, prependCRC);
        }

        public static int Encode(byte[] iBuf, ref byte[] oBuf, ref int retCRC)
        {
            return Encode(iBuf, ref oBuf, ref retCRC, false);
        }

        // Encoding/Compressing
        public static int Encode(byte[] iBuf, ref byte[] oBuf, ref int retCRC, bool prependCRC)
        {
            int i, c, len, r, s, last_match_length, j = 0;

            lock (LZSync)
            {
                Init();
                EncDec = true;

                // The lock makes the code thread-safe
                // Allocate work buffers to hold the incoming message.
                inBuf = new byte[iBuf.Length + 100];
                outBuf = new byte[iBuf.Length * 2 + 10000];

                for (i = 0; i < iBuf.Length; i++) { inBuf[inEnd++] = iBuf[i]; }

                putc((byte)(inEnd & 0xFF));
                putc((byte)((inEnd >> 8) & 0xFF));
                putc((byte)((inEnd >> 16) & 0xFF));
                putc((byte)((inEnd >> 24) & 0xFF));

                codeSize += 4;

                if (inEnd == 0)
                {
                    oBuf = new byte[0]; // Changed from New Byte(-1) {} which is invalid in C# and likely VB.NET as well, should be empty array.
                    retCRC = 0;

                    // Free the work buffers
                    inBuf = null;
                    outBuf = null;
                    return codeSize;
                }
                textSize = 0;
                StartHuff();
                InitTree();
                s = 0;
                r = N - F;
                for (i = 0; i < r; i++) { textBuf[i] = (byte)0x20; }

                len = 0;
                while ((len < F) && (inPtr < inEnd)) { textBuf[r + len++] = (byte)(getc() & 0xFF); }
                textSize = len;
                for (i = 1; i <= F; i++) { InsertNode(r - i); }
                InsertNode(r);
                do
                {
                    if (matchLength > len) { matchLength = len; }
                    if (matchLength <= Threshold)
                    {
                        matchLength = 1;
                        EncodeChar(textBuf[r]);
                    }
                    else
                    {
                        EncodeChar((255 - Threshold) + matchLength);
                        EncodePosition(matchPosition);
                    }
                    last_match_length = matchLength;
                    i = 0;
                    while ((i < last_match_length) && (inPtr < inEnd))
                    {
                        i++;
                        DeleteNode(s);
                        c = getc();
                        textBuf[s] = (byte)(c & 0xFF);
                        if (s < F - 1) { textBuf[s + N] = (byte)c; }
                        s = (s + 1) & (N - 1);
                        r = (r + 1) & (N - 1);
                        InsertNode(r);
                    }
                    textSize += i;
                    while (i < last_match_length)
                    {
                        i++;
                        DeleteNode(s);
                        s = (s + 1) & (N - 1);
                        r = (r + 1) & (N - 1);
                        len--;
                        if (len > 0) { InsertNode(r); }
                    }
                } while (len > 0);
                EncodeEnd();
                retCRC = GetCRC();

                // Create a buffer to hold the results
                if (prependCRC)
                {
                    oBuf = new byte[codeSize + 2]; // Changed size to + 2 to accommodate prepended CRC (2 bytes)
                    oBuf[0] = (byte)((retCRC >> 8) & 0xFF);
                    oBuf[1] = (byte)(retCRC & 0xFF);
                    j = 2;
                }
                else
                {
                    oBuf = new byte[codeSize]; // Corrected size to codeSize, not codeSize - 1
                    j = 0;
                }

                // Corrected loop condition to i < codeSize
                for (i = 0; i < codeSize; i++) { oBuf[j++] = outBuf[i]; }
                if (prependCRC) { codeSize += 2; }

                // Free the work buffers
                inBuf = null;
                outBuf = null;

                return codeSize;
            }
        }

        public static int Decode(byte[] iBuf, ref byte[] oBuf, bool checkCRC, int intExpectedUncompressedSize)
        {
            ushort tmp = 0;
            return DecodeWork(iBuf, ref oBuf, ref tmp, checkCRC, intExpectedUncompressedSize);
        }

        public static int Decode(byte[] iBuf, ref byte[] oBuf, ushort retCRC, int intExpectedUncompressedSize)
        {
            return DecodeWork(iBuf, ref oBuf, ref retCRC, false, intExpectedUncompressedSize);
        }

        // Decoding/Uncompressing
        public static int DecodeWork(byte[] iBuf, ref byte[] oBuf, ref ushort retCRC, bool checkCRC, int intExpectedUncompressedSize)
        {
            int i, j, k, r, c, count, iBufStart = 0, suppliedCRC = 0;

            lock (LZSync)
            {
                EncDec = false;
                Init();

                // The lock makes the code thread-safe
                // Allocate work buffers to hold the incoming message.
                inBuf = new byte[iBuf.Length + 100];
                outBuf = new byte[intExpectedUncompressedSize + 10000];

                if (checkCRC)
                {
                    iBufStart = 2;
                    suppliedCRC = (iBuf[1] & 0xFF);
                    suppliedCRC |= (iBuf[0] << 8);
                }

                // Load the user supplied buffer into the internal processing buffer
                for (i = iBufStart; i < iBuf.Length; i++) { inBuf[inEnd++] = iBuf[i]; }

                // Read size of original text
                textSize = getc();
                textSize |= (getc() << 8);
                textSize |= (getc() << 16);
                textSize |= (getc() << 24);

                if (textSize == 0)
                {
                    oBuf = new byte[0]; // Changed from New Byte(-1) {} which is invalid in C# and likely VB.NET as well, should be empty array.
                    retCRC = 0;

                    // Free the work buffers
                    inBuf = null;
                    outBuf = null;

                    return textSize;
                }

                StartHuff();

                for (i = 0; i < (N - F); i++) { textBuf[i] = (byte)0x20; }

                r = N - F;
                count = 0;
                while (count < textSize)
                {
                    c = DecodeChar();
                    if (c < 256)
                    {
                        putc((byte)(c & 0xFF));
                        textBuf[r] = (byte)(c & 0xFF);
                        r = (r + 1) & (N - 1);
                        count++;
                    }
                    else
                    {
                        i = ((r - DecodePosition()) - 1) & (N - 1);
                        j = (c - 255) + Threshold;
                        for (k = 0; k < j; k++)
                        {
                            c = (int)textBuf[(i + k) & (N - 1)];
                            putc((byte)(c & 0xFF));
                            textBuf[r] = (byte)(c & 0xFF);
                            r = (r + 1) & (N - 1);
                            count++;
                        }
                    }
                }

                oBuf = new byte[count]; // Corrected size to count
                retCRC = (ushort)GetCRC(); // Casting to ushort

                for (i = 0; i < count; i++) { oBuf[i] = outBuf[i]; }

                // Check the CRC.  Return 0 if mismatch
                if (checkCRC && (retCRC != suppliedCRC)) { count = 0; }

                // Free the work buffers
                inBuf = null;
                outBuf = null;
                return count;
            }
        }

        public static int GetCRC()
        {
            return (int)Swap((ushort)(CRC & 0xFFFF)); // Casting to ushort and then int
        }

        // Initialize all structures pointers and counters
        private static void Init()
        {
            inPtr = 0;
            inEnd = 0;
            outPtr = 0;
            //outEnd = 0;

            getBuf = 0;
            getLen = 0;
            putBuf = 0;
            putLen = 0;

            textSize = 0;
            codeSize = 0;

            matchPosition = 0;
            matchLength = 0;

            InitArrayB(textBuf);

            lSon = new int[N + 1]; // Re-initialize arrays to avoid potential issues if Init is called multiple times
            dad = new int[N + 1];
            rSon = new int[N + 256 + 1];
            freq = new int[T + 1];
            parent = new int[T + NChar];
            son = new int[T];
            inBuf = null; // Ensure these are null for re-initialization
            outBuf = null;

            CRC = 0;
        }

        // Update running tally of CRC
        private static void DoCRC(int c)
        {
            CRC = ((CRC << 8) ^ CRCTable[((CRC >> 8) ^ c) & 0xFF]) & CRCMask; // Changed index to use & 0xFF to ensure it's within CRCTable bounds.
        }

        private static int getc()
        {
            // Get a character from the input buffer
            int c = 0;
            if (inPtr < inEnd)
            {
                c = (int)inBuf[inPtr++] & 0xFF;
                // Do CRC on input for Decode
                if (!EncDec) { DoCRC(c); }
            }
            return c;
        }

        private static void putc(byte c) // Parameter type changed to byte
        {
            // Write a character from the output buffer
            outBuf[outPtr++] = c;
            // Do CRC on output for Encode
            if (EncDec) { DoCRC(c); }
        }

        // Initializing tree
        private static void InitTree()
        {
            // {root}
            for (int i = N + 1; i <= N + 256; i++) { rSon[i] = NodeNIL; }

            //{node}
            for (int i = 0; i < N; i++) { dad[i] = NodeNIL; }
        }

        // Insert nodes to the tree
        private static void InsertNode(int r)
        {
            int i, p, c;
            bool geq = true;

            p = N + 1 + textBuf[r];
            rSon[r] = NodeNIL;
            lSon[r] = NodeNIL;
            matchLength = 0;
            while (true)
            {
                if (geq)
                {
                    if (rSon[p] == NodeNIL)
                    {
                        rSon[p] = r;
                        dad[r] = p;
                        return;
                    }
                    else
                    {
                        p = rSon[p];
                    }
                }
                else
                {
                    if (lSon[p] == NodeNIL)
                    {
                        lSon[p] = r;
                        dad[r] = p;
                        return;
                    }
                    else
                    {
                        p = lSon[p];
                    }
                }
                i = 1;
                while ((i < F) && (textBuf[r + i] == textBuf[p + i]))
                {
                    i++;
                }

                geq = (textBuf[r + i] >= textBuf[p + i]) || (i == F);

                if (i > Threshold)
                {
                    if (i > matchLength)
                    {
                        matchPosition = ((r - p) & (N - 1)) - 1;
                        matchLength = i;
                        if (matchLength >= F)
                        {
                            break;
                        }
                    }
                    if (i == matchLength)
                    {
                        c = ((r - p) & (N - 1)) - 1;
                        if (c < matchPosition)
                        {
                            matchPosition = c;
                        }
                    }
                }
            }

            dad[r] = dad[p];
            lSon[r] = lSon[p];
            rSon[r] = rSon[p];
            dad[lSon[p]] = r;
            dad[rSon[p]] = r;
            if (rSon[dad[p]] == p) { rSon[dad[p]] = r; } else { lSon[dad[p]] = r; }
            dad[p] = NodeNIL;
            // remove p
        }

        private static void DeleteNode(int p)
        {
            // Delete node from the tree
            int q;

            // unregistered
            if (dad[p] == NodeNIL) { return; }

            if (rSon[p] == NodeNIL)
            {
                q = lSon[p];
            }
            else
            {
                if (lSon[p] == NodeNIL)
                {
                    q = rSon[p];
                }
                else
                {
                    q = lSon[p];

                    if (rSon[q] != NodeNIL)
                    {
                        do
                        {
                            q = rSon[q];
                        } while (rSon[q] != NodeNIL);
                        rSon[dad[q]] = lSon[q];
                        dad[lSon[q]] = dad[q];
                        lSon[q] = lSon[p];
                        dad[lSon[p]] = q;
                    }
                    rSon[q] = rSon[p];
                    dad[rSon[p]] = q;
                }
            }
            dad[q] = dad[p];
            if (rSon[dad[p]] == p) { rSon[dad[p]] = q; } else { lSon[dad[p]] = q; }
            dad[p] = NodeNIL;
        }

        // Get one bit
        private static int GetBit()
        {
            int retVal;
            while (getLen <= 8)
            {
                getBuf = (getBuf | (getc() << (8 - getLen))) & 0xFFFF;
                getLen += 8;
            }
            retVal = (getBuf >> 15) & 0x1;
            getBuf = (getBuf << 1) & 0xFFFF;
            getLen--;
            return retVal;
        }

        // Get one byte
        private static int GetByte()
        {
            int retVal;
            while (getLen <= 8)
            {
                getBuf = (getBuf | (getc() << (8 - getLen))) & 0xFFFF;
                getLen += 8;
            }
            retVal = Hi(getBuf) & 0xFF;
            getBuf = (getBuf << 8) & 0xFFFF;
            getLen -= 8;
            return retVal;
        }

        // Output 'n' bits
        private static void Putcode(int n, int c)
        {
            putBuf = (putBuf | (c >> putLen)) & 0xFFFF;
            putLen += n;
            if (putLen >= 8)
            {
                putc((byte)(Hi(putBuf) & 0xFF));
                putLen -= 8;
                if (putLen >= 8)
                {
                    putc((byte)(Lo(putBuf) & 0xFF));
                    codeSize += 2;
                    putLen -= 8;
                    putBuf = (c << (n - putLen)) & 0xFFFF;
                }
                else
                {
                    putBuf = (int)Swap((ushort)(putBuf & 0xFF));
                    codeSize += 1;
                }
            }
        }

        // Initialize freq tree
        private static void StartHuff()
        {
            int i, j;
            for (i = 0; i < NChar; i++)
            {
                freq[i] = 1;
                son[i] = i + T;
                parent[i + T] = i;
            }
            i = 0;
            j = NChar;
            while (j <= R)
            {
                freq[j] = (freq[i] + freq[i + 1]) & 0xFFFF;
                son[j] = i;
                parent[i] = j;
                parent[i + 1] = j;
                i += 2;
                j++;
            }
            freq[T] = 0xFFFF;
            parent[R] = 0;
        }

        // Reconstruct freq tree
        private static void reconst()
        {
            int i, j = 0, k, f, n;

            // Halven cumulative freq for leaf nodes
            for (i = 0; i < T; i++)
            {
                if (son[i] >= T)
                {
                    freq[j] = (freq[i] + 1) >> 1;
                    son[j] = son[i];
                    j++;
                }
            }

            // Make a tree : first, connect children nodes
            i = 0;
            j = NChar;
            while (j < T)
            {
                k = i + 1;
                f = (freq[i] + freq[k]) & 0xFFFF;
                freq[j] = f;
                k = j - 1;
                while (f < freq[k]) { k--; }
                k++;

                for (n = j; n >= k + 1; n--)
                {
                    freq[n] = freq[n - 1];
                    son[n] = son[n - 1];
                }
                freq[k] = f;
                son[k] = i;

                i += 2;
                j++;
            }

            // Connect parent nodes
            for (i = 0; i < T; i++)
            {
                k = son[i];
                parent[k] = i;
                if (k < T) { parent[k + 1] = i; }
            }
        }

        // Update freq tree
        private static void update(int c)
        {
            int i, j, k, n;

            if (freq[R] == MaxFreq) { reconst(); }
            c = parent[c + T];
            do
            {
                freq[c]++;
                k = freq[c];

                // Swap nodes to keep the tree freq-ordered}
                n = c + 1;
                if (k > freq[n])
                {
                    while (k > freq[n + 1]) { n++; }
                    freq[c] = freq[n];
                    freq[n] = k;

                    i = son[c];
                    parent[i] = n;
                    if (i < T) { parent[i + 1] = n; }
                    j = son[n];
                    son[n] = i;

                    parent[j] = c;
                    if (j < T) { parent[j + 1] = c; }
                    son[c] = j;

                    c = n;
                }
                c = parent[c];
            } while (c != 0); // do it until reaching the root
        }

        private static void EncodeChar(int c)
        {
            int code = 0, k = parent[c + T];
            byte len = 0;

            // Search connections from leaf node to the root
            do
            {
                code >>= 1;

                // If node's address is odd, output 1 else output 0
                if ((k & 1) > 0) { code += 0x8000; }
                len++;
                k = parent[k];
            } while (k != R);
            Putcode(len, code);
            update(c);
        }

        private static void EncodePosition(int c)
        {
            // Output upper 6 bits with encoding
            int i = c >> 6;
            Putcode(p_len[i], p_code[i] << 8);

            // Output lower 6 bits directly
            Putcode(6, (c & 0x3F) << 10);
        }

        private static void EncodeEnd()
        {
            if (putLen > 0)
            {
                putc((byte)Hi(putBuf));
                codeSize++;
            }
        }

        private static int DecodeChar()
        {
            int c;
            int RetVal;
            c = son[R];

            // Start searching tree from the root to leaves.
            // Choose node #(son[]) if input bit = 0
            // else choose #(son[]+1) (input bit = 1)
            while (c < T) { c = son[c + GetBit()]; }
            c -= T;
            update(c);
            RetVal = c & 0xFFFF;
            return RetVal;
        }

        private static int DecodePosition()
        {
            int i, j, c, RetVal;

            // Decode upper 6 bits from given table
            i = GetByte();
            c = (d_code[i] << 6) & 0xFFFF;
            j = d_len[i];

            // Input lower 6 bits directly
            j -= 2;
            while (j > 0) { j--; i = ((i << 1) | GetBit()) & 0xFFFF; }
            RetVal = c | (i & 0x3F);
            return RetVal;
        }


        //
        // Byte manipulation helper routines
        //
        private static int Hi(int X) { return (X >> 8) & 0xFF; }

        private static int Lo(int X) { return X & 0xFF; }

        private static ushort Swap(ushort X) // Changed to ushort to match usage and return type
        {
            return (ushort)(((X >> 8) & 0xFF) | ((X & 0xFF) << 8)); // Casting to ushort
        }

        private static void InitArrayB(byte[] b)
        {
            if (b != null) // Added null check to prevent NullReferenceException
            {
                for (int i = 0; i < b.Length; i++) { b[i] = 0; }
            }
        }

        private static void InitArrayI(int[] b)
        {
            if (b != null) // Added null check to prevent NullReferenceException
            {
                for (int i = 0; i < b.Length; i++) { b[i] = 0; }
            }
        }

        public static bool Test()
        {
            string xm1 = "8A34C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122";
            string xm2 = "F05B9A010000ECF57A1C6D676FB1DEEB79B7BC2E96FFAFD4E9E672D87ED00F8E160EFB795FC1DDD753ACAB3D3BBE2D2A3336967E005FE4605FB9FEFA814F882549B99DFDFE69D4B781C3F15E51440E4B3AE50FFECA73F563F46BF86D15B5873231E339388BC2EEBDF056CD99DF01F77D98BF4069A56EE38FE01A6E2BCC817E1477E4DCDF98A0C4D73635A69CEB5FEE0D95E21361DADC346D34CA49325D7414878C1B4B5868FC0041AAF467EFDB534CE7229450038FE8445165D954D200F01160F273EA006213D0FF86E9F662B3C86BB61AF60D350340";
            byte[] m1 = Utils.HexStringToByteArray(xm1);
            byte[] m2 = Utils.HexStringToByteArray(xm2);

            byte[] d1 = new byte[199];
            int dlen1 = WinlinkCompression.Decode(m1, ref d1, true, 199);
            string ds1 = UTF8Encoding.UTF8.GetString(d1);

            byte[] re1 = new byte[0];
            int clen1 = WinlinkCompression.Encode(d1, ref re1, true);
            string rm1 = Utils.BytesToHex(re1);

            byte[] d2 = new byte[410];
            int dlen2 = WinlinkCompression.Decode(m2, ref d2, true, 410);
            string ds2 = UTF8Encoding.UTF8.GetString(d2);

            byte[] re2 = new byte[0];
            int clen2 = WinlinkCompression.Encode(d2, ref re2, true);
            string rm2 = Utils.BytesToHex(re2);

            if (xm1 != rm1) return false;
            if (xm2 != rm2) return false;
            return true;
        }
    }

    /// <summary>
    /// Compute and checks the single byte checksum at the end of messages.
    /// </summary>
    public static class WinLinkChecksum
    {
        public static byte ComputeChecksum(byte[] data)
        {
            return ComputeChecksum(data, 0, data.Length);
        }
        public static byte ComputeChecksum(byte[] data, int off, int len)
        {
            int crc = 0;
            for (int i = off; i < len; i++) { crc += data[i]; }
            return (byte)((~(crc % 256) + 1) % 256);
        }
        public static bool CheckChecksum(byte[] data, byte checksum)
        {
            byte crc = 0;
            for (int i = 0; i < data.Length; i++) { crc += data[i]; }
            return ((byte)(crc + checksum)) == 0;
        }
        public static bool Test()
        {
            byte[] m1 = Utils.HexStringToByteArray("8A34C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122");
            byte[] m2 = Utils.HexStringToByteArray("F05B9A010000ECF57A1C6D676FB1DEEB79B7BC2E96FFAFD4E9E672D87ED00F8E160EFB795FC1DDD753ACAB3D3BBE2D2A3336967E005FE4605FB9FEFA814F882549B99DFDFE69D4B781C3F15E51440E4B3AE50FFECA73F563F46BF86D15B5873231E339388BC2EEBDF056CD99DF01F77D98BF4069A56EE38FE01A6E2BCC817E1477E4DCDF98A0C4D73635A69CEB5FEE0D95E21361DADC346D34CA49325D7414878C1B4B5868FC0041AAF467EFDB534CE7229450038FE8445165D954D200F01160F273EA006213D0FF86E9F662B3C86BB61AF60D350340");
            if (WinLinkChecksum.CheckChecksum(m1, 0x53) == false) return false;
            if (WinLinkChecksum.CheckChecksum(m2, 0x2A) == false) return false;
            if (WinLinkChecksum.ComputeChecksum(m1) != 0x53) return false;
            if (WinLinkChecksum.ComputeChecksum(m2) != 0x2A) return false;
            return true;
        }
    }

    /// <summary>
    /// This is the full CRC16 calculator for WinLink
    /// </summary>
    public static class WinlinkCrc16
    {
        public static bool Test()
        {
            byte[] m1 = Utils.HexStringToByteArray("C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122");
            byte[] m2 = Utils.HexStringToByteArray("9A010000ECF57A1C6D676FB1DEEB79B7BC2E96FFAFD4E9E672D87ED00F8E160EFB795FC1DDD753ACAB3D3BBE2D2A3336967E005FE4605FB9FEFA814F882549B99DFDFE69D4B781C3F15E51440E4B3AE50FFECA73F563F46BF86D15B5873231E339388BC2EEBDF056CD99DF01F77D98BF4069A56EE38FE01A6E2BCC817E1477E4DCDF98A0C4D73635A69CEB5FEE0D95E21361DADC346D34CA49325D7414878C1B4B5868FC0041AAF467EFDB534CE7229450038FE8445165D954D200F01160F273EA006213D0FF86E9F662B3C86BB61AF60D350340");
            if (WinlinkCrc16.Compute(m1) != 0x348A) return false;
            if (WinlinkCrc16.Compute(m2) != 0x5BF0) return false;
            return true;
        }

        private static ushort UdpCRC16(int cp, ushort sum)
        {
            return (ushort)(((sum << 8) & 0xff00) ^ Crc16Tab[((sum >> 8) & 0xff)] ^ (ushort)cp);
        }

        // Note that you need to reverse the bytes of the CRC16 when placing it in front of the binary dataf
        public static ushort Compute(byte[] p)
        {
            ushort sum = 0;
            byte[] extendedP = new byte[p.Length + 2];
            Array.Copy(p, extendedP, p.Length);
            extendedP[p.Length] = 0;
            extendedP[p.Length + 1] = 0;
            foreach (byte c in extendedP) { sum = UdpCRC16((int)c, sum); }
            return sum;
        }

        public static readonly ushort[] Crc16Tab = {
            0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7,
            0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef,
            0x1231, 0x0210, 0x3273, 0x2252, 0x52b5, 0x4294, 0x72f7, 0x62d6,
            0x9339, 0x8318, 0xb37b, 0xa35a, 0xd3bd, 0xc39c, 0xf3ff, 0xe3de,
            0x2462, 0x3443, 0x0420, 0x1401, 0x64e6, 0x74c7, 0x44a4, 0x5485,
            0xa56a, 0xb54b, 0x8528, 0x9509, 0xe5ee, 0xf5cf, 0xc5ac, 0xd58d,
            0x3653, 0x2672, 0x1611, 0x0630, 0x76d7, 0x66f6, 0x5695, 0x46b4,
            0xb75b, 0xa77a, 0x9719, 0x8738, 0xf7df, 0xe7fe, 0xd79d, 0xc7bc,
            0x48c4, 0x58e5, 0x6886, 0x78a7, 0x0840, 0x1861, 0x2802, 0x3823,
            0xc9cc, 0xd9ed, 0xe98e, 0xf9af, 0x8948, 0x9969, 0xa90a, 0xb92b,
            0x5af5, 0x4ad4, 0x7ab7, 0x6a96, 0x1a71, 0x0a50, 0x3a33, 0x2a12,
            0xdbfd, 0xcbdc, 0xfbbf, 0xeb9e, 0x9b79, 0x8b58, 0xbb3b, 0xab1a,
            0x6ca6, 0x7c87, 0x4ce4, 0x5cc5, 0x2c22, 0x3c03, 0x0c60, 0x1c41,
            0xedae, 0xfd8f, 0xcdec, 0xddcd, 0xad2a, 0xbd0b, 0x8d68, 0x9d49,
            0x7e97, 0x6eb6, 0x5ed5, 0x4ef4, 0x3e13, 0x2e32, 0x1e51, 0x0e70,
            0xff9f, 0xefbe, 0xdfdd, 0xcffc, 0xbf1b, 0xaf3a, 0x9f59, 0x8f78,
            0x9188, 0x81a9, 0xb1ca, 0xa1eb, 0xd10c, 0xc12d, 0xf14e, 0xe16f,
            0x1080, 0x00a1, 0x30c2, 0x20e3, 0x5004, 0x4025, 0x7046, 0x6067,
            0x83b9, 0x9398, 0xa3fb, 0xb3da, 0xc33d, 0xd31c, 0xe37f, 0xf35e,
            0x02b1, 0x1290, 0x22f3, 0x32d2, 0x4235, 0x5214, 0x6277, 0x7256,
            0xb5ea, 0xa5cb, 0x95a8, 0x8589, 0xf56e, 0xe54f, 0xd52c, 0xc50d,
            0x34e2, 0x24c3, 0x14a0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
            0xa7db, 0xb7fa, 0x8799, 0x97b8, 0xe75f, 0xf77e, 0xc71d, 0xd73c,
            0x26d3, 0x36f2, 0x0691, 0x16b0, 0x6657, 0x7676, 0x4615, 0x5634,
            0xd94c, 0xc96d, 0xf90e, 0xe92f, 0x99c8, 0x89e9, 0xb98a, 0xa9ab,
            0x5844, 0x4865, 0x7806, 0x6827, 0x18c0, 0x08e1, 0x3882, 0x28a3,
            0xcb7d, 0xdb5c, 0xeb3f, 0xfb1e, 0x8bf9, 0x9bd8, 0xabbb, 0xbb9a,
            0x4a75, 0x5a54, 0x6a37, 0x7a16, 0x0af1, 0x1ad0, 0x2ab3, 0x3a92,
            0xfd2e, 0xed0f, 0xdd6c, 0xcd4d, 0xbdaa, 0xad8b, 0x9de8, 0x8dc9,
            0x7c26, 0x6c07, 0x5c64, 0x4c45, 0x3ca2, 0x2c83, 0x1ce0, 0x0cc1,
            0xef1f, 0xff3e, 0xcf5d, 0xdf7c, 0xaf9b, 0xbfba, 0x8fd9, 0x9ff8,
            0x6e17, 0x7e36, 0x4e55, 0x5e74, 0x2e93, 0x3eb2, 0x0ed1, 0x1ef0,
        };
    }
}


