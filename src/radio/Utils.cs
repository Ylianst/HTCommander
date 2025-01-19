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

namespace HTCommander
{
    public class Utils
    {
        public static byte[] HexStringToByteArray(string hex)
        {
            if (hex.Length % 2 != 0) throw new ArgumentException("Hex string must have an even length.");
            byte[] bytes = new byte[hex.Length / 2];
            for (int i = 0; i < hex.Length; i += 2) { bytes[i / 2] = Convert.ToByte(hex.Substring(i, 2), 16); }
            return bytes;
        }
        public static string BytesToHex(byte[] ba) { return BitConverter.ToString(ba).Replace("-", ""); }
        public static int GetShort(byte[] d, int p) { return ((int)d[p] << 8) + (int)d[p + 1]; }
        public static int GetInt(byte[] d, int p) { return ((int)d[p] << 24) + (int)(d[p + 1] << 16) + (int)(d[p + 2] << 8) + (int)d[p + 3]; }
        public static void SetShort(byte[] d, int p, int v) { d[p] = (byte)((v >> 8) & 0xFF); d[p + 1] = (byte)(v & 0xFF); }
        public static void SetInt(byte[] d, int p, int v) { d[p] = (byte)(v >> 24); d[p + 1] = (byte)((v >> 16) & 0xFF); d[p + 2] = (byte)((v >> 8) & 0xFF); d[p + 3] = (byte)(v & 0xFF); }
    }
}
