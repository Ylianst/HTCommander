﻿/*
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
using System.IO;
using System.Text;
using System.Windows.Forms;
using System.IO.Compression;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Brotli;
using System.Security.Cryptography;

namespace HTCommander
{
    public class Utils
    {
        public static string BytesToHex(byte[] Bytes)
        {
            if (Bytes == null) return "";
            StringBuilder Result = new StringBuilder(Bytes.Length * 2);
            string HexAlphabet = "0123456789ABCDEF";
            foreach (byte B in Bytes)
            {
                Result.Append(HexAlphabet[(int)(B >> 4)]);
                Result.Append(HexAlphabet[(int)(B & 0xF)]);
            }
            return Result.ToString();
        }

        public static byte[] HexStringToByteArray(string Hex)
        {
            byte[] Bytes = new byte[Hex.Length / 2];
            int[] HexValue = new int[] { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F };
            for (int x = 0, i = 0; i < Hex.Length; i += 2, x += 1)
            {
                Bytes[x] = (byte)(HexValue[Char.ToUpper(Hex[i + 0]) - '0'] << 4 | HexValue[Char.ToUpper(Hex[i + 1]) - '0']);
            }
            return Bytes;
        }

        public static int GetShort(byte[] d, int p) { return ((int)d[p] << 8) + (int)d[p + 1]; }
        public static int GetInt(byte[] d, int p) { return ((int)d[p] << 24) + (int)(d[p + 1] << 16) + (int)(d[p + 2] << 8) + (int)d[p + 3]; }
        public static void SetShort(byte[] d, int p, int v) { d[p] = (byte)((v >> 8) & 0xFF); d[p + 1] = (byte)(v & 0xFF); }
        public static void SetInt(byte[] d, int p, int v) { d[p] = (byte)(v >> 24); d[p + 1] = (byte)((v >> 16) & 0xFF); d[p + 2] = (byte)((v >> 8) & 0xFF); d[p + 3] = (byte)(v & 0xFF); }

        // Import the SendMessage function from User32.dll
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam);

        private const uint EM_SETCUEBANNER = 0x1501;

        // Method to set the placeholder text
        public static void SetPlaceholderText(TextBox textBox, string placeholderText)
        {
            SendMessage(textBox.Handle, EM_SETCUEBANNER, (IntPtr)1, placeholderText);
        }

        public static Dictionary<string, List<AX25Address>> DecodeAprsRoutes(string routesStr)
        {
            Dictionary<string, List<AX25Address>> r = new Dictionary<string, List<AX25Address>>();
            if (routesStr != null)
            {
                string[] routes = routesStr.Split('|');
                foreach (string route in routes)
                {
                    string[] args = route.Split(',');
                    if (args.Length > 1)
                    {
                        AX25Address a;
                        List<AX25Address> addresses = new List<AX25Address>();
                        for (int i = 1; i < args.Length; i++)
                        {
                            a = AX25Address.GetAddress(args[i]);
                            if (a == null) break;
                            addresses.Add(a);
                        }
                        r.Add(args[0], addresses);
                    }
                }
            }
            return r;
        }

        public static string EncodeAprsRoutes(Dictionary<string, List<AX25Address>> routes)
        {
            StringBuilder sb = new StringBuilder();
            bool first = true;
            foreach (string routeName in routes.Keys)
            {
                List<AX25Address> addresses = routes[routeName];
                if (addresses.Count > 0)
                {
                    if (first == false) { sb.Append('|'); }
                    sb.Append(routeName);
                    foreach (AX25Address address in addresses) { sb.Append(',' + address.CallSignWithId); }
                    first = false;
                }
            }
            return sb.ToString();
        }

        public static byte[] CompressBrotli(byte[] data)
        {
            using (var output = new MemoryStream())
            {
                using (var brotli = new BrotliStream(output, CompressionMode.Compress, leaveOpen: true))
                {
                    brotli.SetQuality(11); // 0 to 11, 11 is max
                    brotli.SetWindow(22); // 11, 22, 24 - Default is 22
                    brotli.Write(data, 0, data.Length);
                }
                return output.ToArray();
            }
        }

        public static byte[] DecompressBrotli(byte[] compressedData)
        {
            return DecompressBrotli(compressedData, 0, compressedData.Length);
        }

        public static byte[] DecompressBrotli(byte[] compressedData, int index, int length)
        {
            using (var input = new MemoryStream(compressedData, index, length))
            using (var brotli = new BrotliStream(input, CompressionMode.Decompress))
            using (var output = new MemoryStream())
            {
                brotli.CopyTo(output);
                return output.ToArray();
            }
        }

        static public byte[] CompressDeflate(byte[] data)
        {
            using (var output = new MemoryStream())
            {
                using (var dstream = new DeflateStream(output, CompressionLevel.Optimal, leaveOpen: true))
                {
                    dstream.Write(data, 0, data.Length);
                }
                return output.ToArray();
            }
        }

        public static byte[] DecompressDeflate(byte[] compressedData)
        {
            return DecompressDeflate(compressedData, 0, compressedData.Length);
        }

        static public byte[] DecompressDeflate(byte[] compressedData, int index, int length)
        {
            using (var input = new MemoryStream(compressedData, index, length))
            using (var output = new MemoryStream())
            using (var dstream = new DeflateStream(input, CompressionMode.Decompress))
            {
                dstream.CopyTo(output);
                return output.ToArray();
            }
        }

        public static byte[] ComputeShortSha256Hash(byte[] rawData)
        {
            using (SHA256 sha256Hash = SHA256.Create())
            {
                byte[] r = sha256Hash.ComputeHash(rawData);
                byte[] r2 = new byte[12];
                Array.Copy(r, 0, r2, 0, 12);
                return r2;
            }
        }
    }

    public class RtfBuilder
    {
        StringBuilder _builder = new StringBuilder();

        // Helper method to escape RTF special characters
        private string EscapeRtfText(string text)
        {
            return text.Replace(@"\", @"\\")
                       .Replace(@"{", @"\{")
                       .Replace(@"}", @"\}");
        }

        public void AppendBold(string text)
        {
            _builder.Append(@"\b ");
            _builder.Append(EscapeRtfText(text));
            _builder.Append(@"\b0 ");
        }

        public void Append(string text)
        {
            _builder.Append(EscapeRtfText(text));
        }

        public void AppendLine(string text)
        {
            _builder.Append(EscapeRtfText(text));
            _builder.Append(@"\line "); // Added space after \line for better readability in RTF (optional)
        }

        public string ToRtf()
        {
            return @"{\rtf1\ansi " + _builder.ToString() + @" }";
        }
    }
}
