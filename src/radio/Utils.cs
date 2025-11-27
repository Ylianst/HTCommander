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
using System.IO;
using System.Text;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;
using System.IO.Compression;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using Brotli;

namespace HTCommander
{
    public class Utils
    {
        public class ComboBoxItem
        {
            public int Index { get; }
            public string Value { get; }
            public string Text { get; set; }
            public ComboBoxItem(int index, string text) { Index = index; Text = text; }
            public ComboBoxItem(string value, string text) { Value = value; Text = text; }
            public override string ToString() { return Text; }
        }

        public static Dictionary<byte, byte[]> DecodeShortBinaryMessage(byte[] data)
        {
            var result = new Dictionary<byte, byte[]>();

            if (data == null || data.Length == 0)
                return result;

            int index = 0;

            // Ignore the leading 01 if present
            if (data[0] == 0x01)
                index = 1;

            while (index < data.Length)
            {
                // Need at least length + key
                if (index + 1 >= data.Length)
                    break; // malformed, return what is parsed so far

                byte length = data[index];
                byte key = data[index + 1];

                // Length must allow key(1) + value(?)
                if (length < 1)
                    break; // malformed

                int valueLen = length - 1;

                // Check if we have enough bytes for value
                if (index + 2 + valueLen > data.Length)
                    break; // malformed

                byte[] value = new byte[valueLen];
                Array.Copy(data, index + 2, value, 0, valueLen);

                result[key] = value;

                // Move index to next block
                index += (2 + valueLen);
            }

            return result;
        }

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        public const int WM_SETREDRAW = 0x0B;

        // Helper function to safely get string value from parts array
        public static string GetValue(string[] parts, Dictionary<string, int> headers, string key, string defaultValue = "")
        {
            if (headers.TryGetValue(key, out int index) && index < parts.Length) { return parts[index]; }
            return defaultValue;
        }

        // Helper function to safely parse double
        public static double? TryParseDouble(string value)
        {
            if (double.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out double result)) { return result; }
            return null;
        }

        // Helper function to safely parse int
        public static int? TryParseInt(string value)
        {
            if (int.TryParse(value, out int result)) { return result; }
            return null;
        }

        public static string RemoveQuotes(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length < 2) return value;
            if (value.StartsWith("\"") && value.EndsWith("\"")) { value = value.Substring(1, value.Length - 2); }
            if (value.StartsWith("'") && value.EndsWith("'")) { value = value.Substring(1, value.Length - 2); }
            return value;
        }

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

        public static string BytesToHex(byte[] Bytes, int offset, int length)
        {
            if (Bytes == null) return "";
            StringBuilder Result = new StringBuilder(length * 2);
            string HexAlphabet = "0123456789ABCDEF";
            for (int i = offset; i < length + offset; i++)
            {
                Result.Append(HexAlphabet[(int)(Bytes[i] >> 4)]);
                Result.Append(HexAlphabet[(int)(Bytes[i] & 0xF)]);
            }
            return Result.ToString();
        }

        public static byte[] HexStringToByteArray(string Hex)
        {
            try
            {
                if (Hex.Length % 2 != 0) return null;
                byte[] Bytes = new byte[Hex.Length / 2];
                int[] HexValue = new int[] { 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F };
                for (int x = 0, i = 0; i < Hex.Length; i += 2, x += 1)
                {
                    Bytes[x] = (byte)(HexValue[Char.ToUpper(Hex[i + 0]) - '0'] << 4 | HexValue[Char.ToUpper(Hex[i + 1]) - '0']);
                }
                return Bytes;
            }
            catch (Exception) { return null; }
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

        public static byte[] ComputeSha256Hash(byte[] rawData)
        {
            using (SHA256 sha256Hash = SHA256.Create()) { return sha256Hash.ComputeHash(rawData); }
        }

        public static byte[] ComputeHmacSha256Hash(byte[] authkey, byte[] data)
        {
            using (HMACSHA256 hmac = new HMACSHA256(authkey)) { return hmac.ComputeHash(data); }
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
        public static void AddFormattedEntry(RichTextBox rtb, DateTime entryTime, string smallText, string largeText, bool completed, bool outbound)
        {
            // Ensure we are manipulating the control on the UI thread
            if (rtb.InvokeRequired)
            {
                // If called from a different thread, marshal the call back to the UI thread
                rtb.Invoke(new Action(() => AddFormattedEntry(rtb, entryTime, smallText, largeText, completed, outbound)));
                return; // Exit the current (non-UI thread) method call
            }

            // --- Define Formatting ---
            // Use the RichTextBox's current font family as a base for consistency
            string baseFontFamily = rtb.Font.FontFamily.Name;

            // Small font for metadata (date/source) and separator line
            Font smallFont = new Font(baseFontFamily, 8f, FontStyle.Regular);
            Color smallColor = Color.DimGray; // A nice, lighter gray

            // Larger font for the main message
            Font largeFont = new Font(baseFontFamily, 11f, FontStyle.Regular); // Adjust size as needed
            Color largeColor = Color.Black;
            if (outbound) { largeColor = Color.Red; }
            else if (!completed) { largeColor = Color.DarkBlue; }

            // Separator line - using a character that repeats well
            // Adjust the count (e.g., 50) based on your RichTextBox width and preference
            string horizontalLine = new string('\u2015', 50); // U+2015 HORIZONTAL BAR character

            // Store original settings to potentially restore later if needed (optional)
            // Font originalFont = rtb.SelectionFont;
            // Color originalColor = rtb.SelectionColor;

            // --- Append First Line (Date + Small Text) ---
            // Move cursor to the end
            rtb.Select(rtb.TextLength, 0);
            // Apply small font and color
            rtb.SelectionFont = smallFont;
            rtb.SelectionColor = smallColor;
            // Append the text including a newline
            if (entryTime != DateTime.MinValue)
            {
                rtb.AppendText($"{entryTime:yyyy-MM-dd HH:mm:ss} - {smallText}{Environment.NewLine}");
            }
            else
            {
                rtb.AppendText($"{smallText}{Environment.NewLine}");
            }

            if (largeText != null)
            {
                // --- Append Horizontal Line ---
                // Keep small font and color for the separator line
                rtb.Select(rtb.TextLength, 0);
                rtb.SelectionFont = smallFont;
                rtb.SelectionColor = smallColor;
                // Append the line including a newline
                rtb.AppendText($"{horizontalLine}{Environment.NewLine}");

                // --- Append Large Text ---
                // Move cursor to the end
                rtb.Select(rtb.TextLength, 0);
                // Apply large font and black color
                rtb.SelectionFont = largeFont;
                rtb.SelectionColor = largeColor;
                // Append the main message
                rtb.AppendText(largeText); // No newline immediately after

                // --- Add Bottom Spacing ---
                // Move cursor to the end
                rtb.Select(rtb.TextLength, 0);
                // Reset to default font/color before adding spacing newlines (looks cleaner)
                rtb.SelectionFont = rtb.Font; // Use the control's default font
                rtb.SelectionColor = rtb.ForeColor; // Use the control's default color
                                                    // Append two newlines: one to end the largeText line, one for spacing
                rtb.AppendText($"{Environment.NewLine}");
            }
            rtb.AppendText($"{Environment.NewLine}");

            // --- Clean up ---
            // Dispose of the Font objects we created (good practice)
            smallFont.Dispose();
            largeFont.Dispose();

            // Optional: Restore original selection font/color if needed
            // rtb.SelectionFont = originalFont;
            // rtb.SelectionColor = originalColor;

            // --- Ensure Visibility ---
            // Scroll to the caret (which is now at the end) to make the new entry visible
            rtb.ScrollToCaret();
        }

    }

}
