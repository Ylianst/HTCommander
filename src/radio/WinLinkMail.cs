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
using System.Globalization;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

namespace HTCommander.radio
{
    public class WinLinkMailAttachement
    {
        public string Name { get; set; }
        public byte[] Data { get; set; }
    }

    public class WinLinkMail
    {
        public string MID { get; set; }
        public DateTime DateTime { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public string Cc { get; set; }
        public string Subject { get; set; }
        public string Mbo { get; set; }
        public string Body { get; set; }
        public string Tag { get; set; }
        public string Location { get; set; }
        public List<WinLinkMailAttachement> Attachements { get; set; }
        public int Flags { get; set; } // 1 = Unread
        public int Mailbox { get; set; }

        public enum MailFlags : int
        {
            Unread = 1,
            Private = 2,
            P2P = 4
        }

        public WinLinkMail() { }

        /*
        public static void Test()
        {
            string test1 = "MID: 1CCIZGEQKFAC\r\nDate: 2025/02/22 03:30\r\nType: Private\r\nFrom: KK7VZT\r\nTo: ysainthilaire@hotmail.com\r\nSubject: Test2\r\nMbo: KK7VZT\r\nX-Location: 45.395833N, 122.791667W (Grid square)\r\nBody: 5\r\n\r\ntest2";
            string test2 = "MID: OLRJZ16F3KHG\r\nDate: 2025/02/22 19:09\r\nType: Private\r\nFrom: KK7VZT\r\nTo: ysainthilaire@hotmail.com\r\nSubject: Test4\r\nMbo: KK7VZT\r\nX-Location: 45.395833N, 122.791667W (Grid square)\r\nBody: 214\r\n\r\nThis is a sample message.\r\nThis is a sample message.\r\nThis is a sample message.\r\nThis is a sample message.\r\nThis is a sample message.\r\nThis is a sample message.\r\nThis is a sample message.\r\nThis is a sample message.";
            WinLinkMail x1 = WinLinkMail.DeserializeMail(test1);
            WinLinkMail x2 = WinLinkMail.DeserializeMail(test2);
            string m1 = SerializeMail(x1);
            string m2 = SerializeMail(x2);

            List<byte[]> blocks = EncodeMailToBlocks(x1);
            WinLinkMail x3 = DecodeBlocksToEmail(blocks);
        }

        public static bool Test2()
        {
            string xm1 = "8A34C7000000ECF57A1C6D66F79F7F89E6E9F47BBD7E9736D6672D87ED00F8E160EFB7961C1DDD7D2A3AD354A1BFA14D52D6D3C00BFCA805FB9FEFA81500825CCB99EFDFE6955BA77C3F15F51C50E4BB8E517FECE77F565F46BF86D198D8F322DCB49688BC56EBDF096CD99DF01F77D993EC16DB62F23CE6914315EA40BF0E3BF26E7B06282D35CE8E6D9E0574026E297E2321BB5B86B0155CB49B091E10E90F187697B0D25C047355ECDFE06D4E379C8A6126C0C4E3503CEE1122";
            byte[] m1 = Utils.HexStringToByteArray(xm1);
            byte[] d1 = new byte[199];
            int dlen1 = WinlinkCompression.Decode(m1, ref d1, true, 199);
            string ds1 = UTF8Encoding.UTF8.GetString(d1);
            WinLinkMail mm1 = WinLinkMail.DeserializeMail(ds1);
            string ds2 = WinLinkMail.SerializeMail(mm1);
            byte[] re1 = new byte[0];
            int clen1 = WinlinkCompression.Encode(UTF8Encoding.UTF8.GetBytes(ds2), ref re1, true);
            string rm1 = Utils.BytesToHex(re1);
            return (xm1 == rm1);
        }
        */

        public static WinLinkMail DecodeBlocksToEmail(byte[] block, out bool fail, out int dataConsumed)
        {
            fail = false;
            dataConsumed = 0;
            if (block == null) return null;
            if (block.Length == 0) return null;

            // Figure out if we have a full mail and the size of the mail
            int cmdlen, payloadLen = 0, ptr = 0;
            bool completeMail = false;
            while ((completeMail == false) && ((ptr + 1) < block.Length))
            {
                int cmd = block[ptr];
                switch (cmd)
                {
                    case 1:
                        cmdlen = block[ptr + 1];
                        ptr += (2 + cmdlen);
                        break;
                    case 2:
                        cmdlen = block[ptr + 1];
                        payloadLen += cmdlen;
                        ptr += (2 + cmdlen);
                        break;
                    case 4:
                        ptr += 2;
                        completeMail = true;
                        break;
                    default:
                        return null;
                }
            }
            if (completeMail == false) return null;

            ptr = 0;
            byte[] payload = new byte[payloadLen];
            int payloadPtr = 0;
            completeMail = false;
            while ((completeMail == false) && ((ptr + 1) < block.Length))
            {
                int cmd = block[ptr];
                switch (cmd)
                {
                    case 1:
                        cmdlen = block[ptr + 1];
                        ptr += (2 + cmdlen);
                        break;
                    case 2:
                        cmdlen = block[ptr + 1];
                        Array.Copy(block, ptr + 2, payload, payloadPtr, cmdlen);
                        payloadPtr += cmdlen;
                        ptr += (2 + cmdlen);
                        break;
                    case 4:
                        cmdlen = block[ptr + 1];
                        if (WinLinkChecksum.ComputeChecksum(payload) != cmdlen) { fail = true; return null; }
                        ptr += 2;
                        break;
                }
            }

            // Decompress the mail
            byte[] obuf = null;
            int expectedLength = (payload[2] + (payload[3] << 8) + (payload[4] << 16) + (payload[5] << 24));
            int obuflen = -1;
            try { obuflen = WinlinkCompression.Decode(payload, ref obuf, true, expectedLength); } catch (Exception) { }
            if (obuflen != expectedLength) { fail = true; return null; }

            // Decode the mail
            WinLinkMail mail = WinLinkMail.DeserializeMail(obuf);
            if (mail == null) { fail = true; return null; }
            dataConsumed = ptr;
            return mail;
        }

        public static List<byte[]> EncodeMailToBlocks(WinLinkMail mail, out int uncompressedSize, out int compressedSize)
        {
            uncompressedSize = 0;
            compressedSize = 0;
            byte[] payloadBuf = null;
            byte[] uncompressedMail = WinLinkMail.SerializeMail(mail);
            uncompressedSize = uncompressedMail.Length;
            //try { WinlinkCompression.Encode(uncompressedMail, ref payloadBuf, true); } catch (Exception) { return null; }
            WinlinkCompression.Encode(uncompressedMail, ref payloadBuf, true);
            if (payloadBuf == null) return null;
            byte[] subjectBuf = UTF8Encoding.UTF8.GetBytes(mail.Subject);
            List<byte[]> blocks = new List<byte[]>();

            // Encode the binary header
            MemoryStream memoryStream = new MemoryStream();
            memoryStream.WriteByte(0x01);
            memoryStream.WriteByte((byte)(subjectBuf.Length + 3));
            memoryStream.Write(subjectBuf, 0, subjectBuf.Length);
            memoryStream.WriteByte(0x00);
            memoryStream.WriteByte(0x30); // ASCII '0' in HEX.
            memoryStream.WriteByte(0x00);

            int payloadPtr = 0;
            while (payloadPtr < payloadBuf.Length)
            {
                int blockSize = Math.Min(250, payloadBuf.Length - payloadPtr);
                memoryStream.WriteByte(0x02);
                memoryStream.WriteByte((byte)blockSize);
                memoryStream.Write(payloadBuf, payloadPtr, blockSize);
                payloadPtr += blockSize;
            }

            memoryStream.WriteByte(0x04);
            memoryStream.WriteByte(WinLinkChecksum.ComputeChecksum(payloadBuf));

            byte[] output = memoryStream.ToArray();
            compressedSize = output.Length;

            // Break the output into 128 byte blocks
            int outputPtr = 0;
            while (outputPtr < output.Length)
            {
                int blockSize = Math.Min(128, output.Length - outputPtr);
                byte[] bytes = new byte[blockSize];
                Array.Copy(output, outputPtr, bytes, 0, blockSize);
                blocks.Add(bytes);
                outputPtr += blockSize;
            }

            return blocks;
        }

        public static byte[] SerializeMail(WinLinkMail mail)
        {
            MemoryStream memoryStream = new MemoryStream();
            byte[] bodyData = UTF8Encoding.UTF8.GetBytes(mail.Body);
            byte[] Between = { 0x0D, 0x0A };
            byte[] End = { 0x00 };

            StringBuilder sb = new StringBuilder();
            sb.AppendLine($"MID: {mail.MID}");
            sb.AppendLine($"Date: {mail.DateTime.ToString("yyyy/MM/dd HH:mm")}");
            if ((mail.Flags & (int)MailFlags.Private) != 0) { sb.AppendLine($"Type: Private"); }
            if (!string.IsNullOrEmpty(mail.From)) { sb.AppendLine($"From: {mail.From}"); }
            if (!string.IsNullOrEmpty(mail.To)) { sb.AppendLine($"To: {mail.To}"); }
            if (!string.IsNullOrEmpty(mail.Cc)) { sb.AppendLine($"Cc: {mail.Cc}"); }
            if (!string.IsNullOrEmpty(mail.Subject)) { sb.AppendLine($"Subject: {mail.Subject}"); }
            if (!string.IsNullOrEmpty(mail.Mbo)) { sb.AppendLine($"Mbo: {mail.Mbo}"); }
            if ((mail.Flags & (int)MailFlags.P2P) != 0) { sb.AppendLine($"X-P2P: True"); }
            if (!string.IsNullOrEmpty(mail.Location)) { sb.AppendLine($"X-Location: {mail.Location}"); }
            if (!string.IsNullOrEmpty(mail.Body)) { sb.AppendLine($"Body: " + bodyData.Length); }
            if (mail.Attachements != null)
            {
                foreach (WinLinkMailAttachement attachement in mail.Attachements)
                {
                    sb.AppendLine("File: " + attachement.Data.Length + " " + attachement.Name);
                }
            }
            sb.AppendLine();

            // Assemble the binary email
            byte[] headerData = UTF8Encoding.UTF8.GetBytes(sb.ToString());
            memoryStream.Write(headerData, 0, headerData.Length);
            memoryStream.Write(bodyData, 0, bodyData.Length);
            memoryStream.Write(Between, 0, Between.Length);
            if (mail.Attachements != null)
            {
                foreach (WinLinkMailAttachement attachement in mail.Attachements)
                {
                    memoryStream.Write(attachement.Data, 0, attachement.Data.Length);
                    memoryStream.Write(Between, 0, Between.Length);
                }
            }
            memoryStream.Write(End, 0, End.Length);
            return memoryStream.ToArray();
        }

        public static int FindFirstDoubleNewline(byte[] data)
        {
            // Not enough data to contain \r\n\r\n
            if (data == null || data.Length < 4) { return -1; }
            for (int i = 0; i <= data.Length - 4; i++)
            {
                // Found \r\n\r\n at index i
                if (data[i] == (byte)'\r' && data[i + 1] == (byte)'\n' && data[i + 2] == (byte)'\r' && data[i + 3] == (byte)'\n') { return i; }
            }
            return -1; // \r\n\r\n not found
        }

        // https://winlink.org/sites/default/files/downloads/winlink_data_flow_and_data_packaging.pdf
        public static WinLinkMail DeserializeMail(byte[] databuf)
        {
            WinLinkMail currentMail = new WinLinkMail();

            // Pull the header out of the data
            int headerLimit = FindFirstDoubleNewline(databuf);
            if (headerLimit < 0) { return null; }
            string header = UTF8Encoding.UTF8.GetString(databuf, 0, headerLimit);

            // Decode the header
            bool done = false;
            int i, bodyLength = -1, ptr = (headerLimit + 4);
            string[] lines = header.Replace("\r\n", "\n").Split(new[] { '\n', '\r' });
            foreach (string line in lines)
            {
                if (done) continue;
                i = line.IndexOf(':');
                if (i > 0)
                {
                    string key = line.Substring(0, i).ToLower().Trim();
                    string value = line.Substring(i + 1).Trim();

                    switch (key)
                    {
                        case "": done = true; break;
                        case "mid": currentMail.MID = value; break;
                        case "date": currentMail.DateTime = DateTime.ParseExact(value, "yyyy/MM/dd HH:mm", CultureInfo.InvariantCulture); break;
                        case "type": { if (value.ToLower() == "private") { currentMail.Flags |= (int)MailFlags.Private; }; } break;
                        case "to": currentMail.To = value; break;
                        case "cc": currentMail.Cc = value; break;
                        case "from": currentMail.From = value; break;
                        case "subject": currentMail.Subject = value; break;
                        case "mbo": currentMail.Mbo = value; break;
                        case "body": bodyLength = int.Parse(value); break;
                        case "file":
                            int j = value.IndexOf(' ');
                            if (j > 0)
                            {
                                WinLinkMailAttachement attachement = new WinLinkMailAttachement();
                                attachement.Data = new byte[int.Parse(value.Substring(0, j).ToLower().Trim())];
                                attachement.Name = value.Substring(j + 1).Trim();
                                if (currentMail.Attachements == null) { currentMail.Attachements = new List<WinLinkMailAttachement>(); }
                                currentMail.Attachements.Add(attachement);
                            }
                            break;
                        case "x-location": currentMail.Location = value; break;
                        case "x-p2p": { if (value.ToLower() == "true") { currentMail.Flags |= (int)MailFlags.P2P; }; } break;
                    }
                }
            }

            // Pull the body out of the data
            if (bodyLength > 0)
            {
                currentMail.Body = UTF8Encoding.UTF8.GetString(databuf, ptr, bodyLength);
                ptr += (bodyLength + 2);
            }

            // Pull the attachments out of the data
            if (currentMail.Attachements != null)
            {
                foreach (WinLinkMailAttachement attachment in currentMail.Attachements)
                {
                    Array.Copy(databuf, ptr, attachment.Data, 0, attachment.Data.Length);
                    ptr += (attachment.Data.Length + 2);
                }
            }

            return currentMail;
        }

        // Serialize a list of stations to a plain text format
        public static string Serialize(List<WinLinkMail> mails)
        {
            StringBuilder sb = new StringBuilder();
            foreach (WinLinkMail mail in mails)
            {
                sb.AppendLine("Mail:");
                sb.AppendLine($"MID={mail.MID}");
                sb.AppendLine($"Time={mail.DateTime.ToString("o")}");
                if (!string.IsNullOrEmpty(mail.From)) { sb.AppendLine($"From={mail.From}"); }
                if (!string.IsNullOrEmpty(mail.To)) { sb.AppendLine($"To={mail.To}"); }
                if (!string.IsNullOrEmpty(mail.Cc)) { sb.AppendLine($"Cc={mail.Cc}"); }
                sb.AppendLine($"Subject={mail.Subject}");
                if (!string.IsNullOrEmpty(mail.Mbo)) { sb.AppendLine($"Mbo={mail.Mbo}"); }
                sb.AppendLine($"Body={EscapeString(mail.Body)}");
                if (!string.IsNullOrEmpty(mail.Tag)) { sb.AppendLine($"Tag={mail.Tag}"); }
                if (!string.IsNullOrEmpty(mail.Location)) { sb.AppendLine($"Tag={mail.Location}"); }
                if (mail.Flags != 0) { sb.AppendLine($"Flags={(int)mail.Flags}"); }
                sb.AppendLine($"Mailbox={(int)mail.Mailbox}");
                if (mail.Attachements != null)
                {
                    foreach (WinLinkMailAttachement attachement in mail.Attachements)
                    {
                        sb.AppendLine($"File={attachement.Name}");
                        sb.AppendLine($"FileData=" + Convert.ToBase64String(attachement.Data));
                    }
                }
                sb.AppendLine(); // Separate entries with a blank line
            }
            return sb.ToString();
        }

        // Deserialize a plain text format into a list of StationInfoClass objects
        public static List<WinLinkMail> Deserialize(string data)
        {
            List<WinLinkMail> mails = new List<WinLinkMail>();
            WinLinkMail currentMail = null;

            string FileName = null;
            string[] lines = data.Split(new[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string line in lines)
            {
                string trimmedLine = line.Trim();
                if (trimmedLine == "Mail:")
                {
                    if (currentMail != null)
                    {
                        if (string.IsNullOrEmpty(currentMail.MID)) { currentMail.MID = WinLinkMail.GenerateMID(); }
                        mails.Add(currentMail);
                    }
                    currentMail = new WinLinkMail();
                }
                else if (currentMail != null)
                {
                    int i = trimmedLine.IndexOf('=');
                    if (i > 0)
                    {
                        string key = trimmedLine.Substring(0, i).Trim();
                        string value = trimmedLine.Substring(i + 1).Trim();

                        switch (key)
                        {
                            case "MID": currentMail.MID = value; break;
                            case "Time": currentMail.DateTime = DateTime.ParseExact(value, "o", CultureInfo.InvariantCulture); break;
                            case "From": currentMail.From = value; break;
                            case "To": currentMail.To = value; break;
                            case "Cc": currentMail.Cc = value; break;
                            case "Subject": currentMail.Subject = value; break;
                            case "Mbo": currentMail.Mbo = value; break;
                            case "Body": currentMail.Body = UnescapeString(value); break;
                            case "Tag": currentMail.Tag = value; break;
                            case "Location": currentMail.Location = value; break;
                            case "Flags": currentMail.Flags = int.Parse(value); break;
                            case "Mailbox": currentMail.Mailbox = int.Parse(value); break;
                            case "File": FileName = value; break;
                            case "FileData":
                                if (!string.IsNullOrEmpty(FileName))
                                {
                                    if (currentMail.Attachements == null) { currentMail.Attachements = new List<WinLinkMailAttachement>(); }
                                    WinLinkMailAttachement attachement = new WinLinkMailAttachement();
                                    attachement.Name = FileName;
                                    attachement.Data = Convert.FromBase64String(value);
                                    currentMail.Attachements.Add(attachement);
                                    FileName = null;
                                }
                                break;
                        }
                    }
                }
            }

            if (currentMail != null)
            {
                if (string.IsNullOrEmpty(currentMail.MID)) { currentMail.MID = WinLinkMail.GenerateMID(); }
                mails.Add(currentMail);
            }

            return mails;
        }

        private const char FieldSeparator = ';';
        private const char RecordSeparator = '\n';
        private const char EscapeCharacter = '\\';
        private static string EscapeString(string data)
        {
            if (string.IsNullOrEmpty(data)) return data;

            StringBuilder sb = new StringBuilder();
            foreach (char c in data)
            {
                if (c == FieldSeparator || c == RecordSeparator || c == EscapeCharacter) { sb.Append(EscapeCharacter).Append(c); } else { sb.Append(c); }
            }
            return sb.ToString();
        }

        private static string UnescapeString(string escapedData)
        {
            if (string.IsNullOrEmpty(escapedData)) return escapedData;

            StringBuilder sb = new StringBuilder();
            bool escaping = false;
            foreach (char c in escapedData)
            {
                if (escaping)
                {
                    sb.Append(c); // Append the escaped character directly
                    escaping = false;
                }
                else if (c == EscapeCharacter)
                {
                    escaping = true; // Next character is escaped
                }
                else
                {
                    sb.Append(c); // Normal character
                }
            }
            return sb.ToString();
        }

        public static string GenerateMID()
        {
            using (var rng = RandomNumberGenerator.Create())
            {
                var bytes = new byte[12];
                rng.GetBytes(bytes);

                StringBuilder result = new StringBuilder(12);
                foreach (byte b in bytes)
                {
                    // Map byte to alphanumeric characters (0-9, A-Z)
                    int value = b % 36; // 36 = 10 digits + 26 letters

                    if (value < 10)
                    {
                        // Digits 0-9
                        result.Append((char)('0' + value));
                    }
                    else
                    {
                        // Uppercase letters A-Z
                        result.Append((char)('A' + (value - 10)));
                    }
                }

                return result.ToString();
            }
        }

        public static bool IsMailForStation(string callsign, string to, string cc, out bool others)
        {
            bool o1, o2;
            bool r1 = IsMailForStationEx(callsign, to, out o1);
            bool r2 = IsMailForStationEx(callsign, cc, out o2);
            others = o1 || o2;
            return r1 || r2;
        }

        private static bool IsMailForStationEx(string callsign, string t, out bool others)
        {
            others = false;
            bool response = false;
            if (string.IsNullOrEmpty(callsign) || string.IsNullOrEmpty(t)) return false;
            string[] s = t.Split(';');
            foreach (string s2 in s)
            {
                if (string.IsNullOrEmpty(s2)) continue;
                bool match = false;
                string s3 = s2.Trim();
                int i = s2.IndexOf('@');
                if (i == -1)
                {
                    // Callsign
                    if (string.Compare(callsign, s2, true) == 0) { match = true; }
                    if (s2.ToUpper().StartsWith(callsign.ToUpper() + "-")) { match = true; }
                }
                else
                {
                    // Email
                    string key = s2.Substring(0, i).ToUpper();
                    string value = s2.Substring(i + 1).ToUpper();
                    if ((value == "WINLINK.ORG") && (string.Compare(callsign, key, true) == 0) || (key.ToUpper().StartsWith(callsign + "-"))) { match = true; }
                }
                if (match) { response = true; } else { others = true; }
            }
            return response;
        }
    }
}
