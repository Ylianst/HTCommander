using System;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;

namespace HTCommander.radio
{
    public class WinLinkMail
    {
        public string MID { get; set; }
        public DateTime DateTime { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public string Subject { get; set; }
        public string Body { get; set; }
        public string Tag { get; set; }
        public string Attachements { get; set; }
        public int Flags { get; set; } // 1 = Unread
        public int Mailbox { get; set; }

        public WinLinkMail() { }


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
                sb.AppendLine($"Body={EscapeString(mail.Body)}");
                if (!string.IsNullOrEmpty(mail.Tag)) { sb.AppendLine($"Tag={mail.Tag}"); }
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
                    string[] parts = trimmedLine.Split('=');
                    if (parts.Length == 2)
                    {
                        string key = parts[0].Trim();
                        string value = parts[1].Trim();

                        switch (key)
                        {
                            case "MID": currentMail.MID = value; break;
                            case "Time": currentMail.DateTime = DateTime.ParseExact(value, "o", System.Globalization.CultureInfo.InvariantCulture); break;
                            case "From": currentMail.From = value; break;
                            case "To": currentMail.To = value; break;
                            case "Subject": currentMail.Subject = value; break;
                            case "Body": currentMail.Body = UnescapeString(value); break;
                            case "Tag": currentMail.Tag = value; break;
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
