using System;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Globalization;

namespace HTCommander.radio
{
    public class WinLinkMail
    {
        public string MID { get; set; }
        public DateTime DateTime { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public string Subject { get; set; }
        public string Mbo { get; set; }
        public string Body { get; set; }
        public string Tag { get; set; }
        public string Location { get; set; }
        public string Attachements { get; set; }
        public int Flags { get; set; } // 1 = Unread
        public int Mailbox { get; set; }

        public enum MailFlags: int
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

        public static WinLinkMail DecodeBlocksToEmail(List<byte[]> blocks)
        {
            // TODO: Add support for multiple blocks
            if (blocks == null) return null;
            if (blocks.Count == 0) return null;

            byte[] block = blocks[0];

            int cmdlen, ptr = 0;
            byte[] payload = null;
            while (ptr < block.Length)
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
                        payload = new byte[cmdlen];
                        Array.Copy(block, ptr + 2, payload, 0, cmdlen);
                        ptr += (2 + cmdlen);
                        break;
                    case 4:
                        cmdlen = block[ptr + 1];
                        if (WinLinkChecksum.ComputeChecksum(payload) != cmdlen) return null;
                        ptr += 2;
                        break;
                }
                
            }

            // Decompress the mail
            byte[] obuf = null;
            int expectedLength = (payload[2] + (payload[3] << 8) + (payload[4] << 16) + (payload[5] << 24));
            int obuflen = WinlinkCompression.Decode(payload, ref obuf, true, expectedLength);
            if (obuflen != expectedLength) return null;

            // Decode the mail
            return WinLinkMail.DeserializeMail(UTF8Encoding.UTF8.GetString(obuf));
        }

        public static List<byte[]> EncodeMailToBlocks(WinLinkMail mail)
        {
            byte[] payloadBuf = null;
            WinlinkCompression.Encode(UTF8Encoding.UTF8.GetBytes(WinLinkMail.SerializeMail(mail)), ref payloadBuf, true);
            if (payloadBuf == null) return null;
            byte[] subjectBuf = UTF8Encoding.UTF8.GetBytes(mail.Subject);
            List<byte[]> blocks = new List<byte[]>();

            // TODO: This assumes the message fits in one block, add support for multi-blocks.
            int ptr = 0;
            byte[] output = new byte[2 + subjectBuf.Length + 5 + payloadBuf.Length + 2];
            output[ptr++] = 1;
            output[ptr++] = (byte)(subjectBuf.Length + 3);
            Array.Copy(subjectBuf, 0, output, ptr, subjectBuf.Length);
            ptr += subjectBuf.Length;
            output[ptr++] = 0;
            output[ptr++] = 0x30; // ASCII '0' in HEX.
            output[ptr++] = 0;
            output[ptr++] = 2;
            output[ptr++] = (byte)payloadBuf.Length;
            Array.Copy(payloadBuf, 0, output, ptr, payloadBuf.Length);
            ptr += payloadBuf.Length;
            output[ptr++] = 4;
            output[ptr++] = WinLinkChecksum.ComputeChecksum(payloadBuf);

            blocks.Add(output);
            return blocks;
        }

        public static string SerializeMail(WinLinkMail mail)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine($"MID: {mail.MID}");
            sb.AppendLine($"Date: {mail.DateTime.ToString("yyyy/MM/dd HH:mm")}");
            if ((mail.Flags & (int)MailFlags.Private) != 0) { sb.AppendLine($"Type: Private"); }
            if (!string.IsNullOrEmpty(mail.From)) { sb.AppendLine($"From: {mail.From}"); }
            if (!string.IsNullOrEmpty(mail.To)) { sb.AppendLine($"To: {mail.To}"); }
            if (!string.IsNullOrEmpty(mail.Subject)) { sb.AppendLine($"Subject: {mail.Subject}"); }
            if (!string.IsNullOrEmpty(mail.Mbo)) { sb.AppendLine($"Mbo: {mail.Mbo}"); }
            if ((mail.Flags & (int)MailFlags.P2P) != 0) { sb.AppendLine($"X-P2P: True"); }
            if (!string.IsNullOrEmpty(mail.Location)) { sb.AppendLine($"X-Location: {mail.Location}"); }
            if (!string.IsNullOrEmpty(mail.Body)) { sb.AppendLine($"Body: " + mail.Body.Length); sb.AppendLine(); sb.Append(mail.Body); }
            return sb.ToString();
        }

        // https://winlink.org/sites/default/files/downloads/winlink_data_flow_and_data_packaging.pdf
        public static WinLinkMail DeserializeMail(string data)
        {
            WinLinkMail currentMail = new WinLinkMail();

            bool done = false;
            int i, bodyLength = -1;
            string[] lines = data.Replace("\r\n","\n").Split(new[] { '\n', '\r' });
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
                        case "from": currentMail.From = value; break;
                        case "subject": currentMail.Subject = value; break;
                        case "mbo": currentMail.Mbo = value; break;
                        case "body": bodyLength = int.Parse(value); break;
                        case "x-location": currentMail.Location = value; break;
                        case "x-p2p": { if (value.ToLower() == "true") { currentMail.Flags |= (int)MailFlags.P2P; }; } break;
                    }
                }
            }

            i = data.IndexOf("\r\n\r\n");
            if (i > 0) { currentMail.Body = data.Substring(i + 4, bodyLength); }
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
                sb.AppendLine($"Subject={mail.Subject}");
                if (!string.IsNullOrEmpty(mail.Mbo)) { sb.AppendLine($"Mbo={mail.Mbo}"); }
                sb.AppendLine($"Body={EscapeString(mail.Body)}");
                if (!string.IsNullOrEmpty(mail.Tag)) { sb.AppendLine($"Tag={mail.Tag}"); }
                if (!string.IsNullOrEmpty(mail.Location)) { sb.AppendLine($"Tag={mail.Location}"); }
                if (mail.Flags != 0) { sb.AppendLine($"Flags={(int)mail.Flags}"); }
                sb.AppendLine($"Mailbox={(int)mail.Mailbox}");
                sb.AppendLine(); // Separate entries with a blank line
            }
            return sb.ToString();
        }

        // Deserialize a plain text format into a list of StationInfoClass objects
        public static List<WinLinkMail> Deserialize(string data)
        {
            List<WinLinkMail> mails = new List<WinLinkMail>();
            WinLinkMail currentMail = null;

            string[] lines = data.Split(new[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string line in lines)
            {
                string trimmedLine = line.Trim();
                if (trimmedLine == "Mail:")
                {
                    if (currentMail != null) {
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
                            case "Time": currentMail.DateTime = DateTime.ParseExact(value, "o", System.Globalization.CultureInfo.InvariantCulture); break;
                            case "From": currentMail.From = value; break;
                            case "To": currentMail.To = value; break;
                            case "Subject": currentMail.Subject = value; break;
                            case "Mbo": currentMail.Mbo = value; break;
                            case "Body": currentMail.Body = UnescapeString(value); break;
                            case "Tag": currentMail.Tag = value; break;
                            case "Location": currentMail.Location = value; break;
                            case "Flags": currentMail.Flags = int.Parse(value); break;
                            case "Mailbox": currentMail.Mailbox = int.Parse(value); break;
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
                if (c == FieldSeparator || c == RecordSeparator || c == EscapeCharacter)
                {
                    sb.Append(EscapeCharacter).Append(c);
                }
                else
                {
                    sb.Append(c);
                }
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
    }
}
