using System;
using System.Text;
using System.Collections.Generic;

namespace HTCommander.radio
{
    public class WinLinkMail
    {
        public DateTime DateTime { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public string Subject { get; set; }
        public string Body { get; set; }
        public string Tag { get; set; }
        public string Attachements { get; set; }
        public int Mailbox { get; set; }

        public WinLinkMail() { }
    }

    public static class WinLinkMailSerializer
    {
        private const char FieldSeparator = ';';
        private const char RecordSeparator = '\n';
        private const char EscapeCharacter = '\\';

        public static string SerializeListToString(List<WinLinkMail> mailList)
        {
            if (mailList == null)
            {
                return string.Empty; // Or handle null as needed
            }

            StringBuilder sb = new StringBuilder();
            foreach (var mail in mailList)
            {
                sb.Append(EscapeString(mail.DateTime.ToString("o"))).Append(FieldSeparator); // "o" is ISO 8601 for DateTime
                sb.Append(EscapeString(mail.From)).Append(FieldSeparator);
                sb.Append(EscapeString(mail.To)).Append(FieldSeparator);
                sb.Append(EscapeString(mail.Subject)).Append(FieldSeparator);
                sb.Append(EscapeString(mail.Body)).Append(FieldSeparator);
                sb.Append(EscapeString(mail.Tag)).Append(FieldSeparator);
                sb.Append(EscapeString(mail.Attachements)).Append(FieldSeparator);
                sb.Append(EscapeString(mail.Mailbox.ToString())).Append(RecordSeparator); // Record separator at the end of each object
            }

            if (sb.Length > 0)
            {
                sb.Remove(sb.Length - 1, 1); // Remove the last RecordSeparator if the list is not empty
            }
            return sb.ToString();
        }

        public static List<WinLinkMail> DeserializeStringToList(string serializedString)
        {
            if (string.IsNullOrEmpty(serializedString))
            {
                return new List<WinLinkMail>();
            }

            List<WinLinkMail> mailList = new List<WinLinkMail>();
            string[] records = serializedString.Split(RecordSeparator);

            foreach (string record in records)
            {
                if (string.IsNullOrWhiteSpace(record)) continue; // Skip empty lines if any

                string[] fields = record.Split(FieldSeparator);
                if (fields.Length != 8) // Expecting 8 fields
                {
                    // Handle error - maybe log or throw exception, for now, skip faulty record
                    continue;
                }

                WinLinkMail mail = new WinLinkMail();
                int fieldIndex = 0;

                mail.DateTime = DateTime.ParseExact(UnescapeString(fields[fieldIndex++]), "o", System.Globalization.CultureInfo.InvariantCulture);
                mail.From = UnescapeString(fields[fieldIndex++]);
                mail.To = UnescapeString(fields[fieldIndex++]);
                mail.Subject = UnescapeString(fields[fieldIndex++]);
                mail.Body = UnescapeString(fields[fieldIndex++]);
                mail.Tag = UnescapeString(fields[fieldIndex++]);
                mail.Attachements = UnescapeString(fields[fieldIndex++]);
                mail.Mailbox = int.Parse(UnescapeString(fields[fieldIndex++]));

                mailList.Add(mail);
            }

            return mailList;
        }

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
    }

}
